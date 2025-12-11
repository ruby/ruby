#include "../json.h"
#include "../vendor/ryu.h"
#include "../simd/simd.h"

static VALUE mJSON, eNestingError, Encoding_UTF_8;
static VALUE CNaN, CInfinity, CMinusInfinity;

static ID i_new, i_try_convert, i_uminus, i_encode;

static VALUE sym_max_nesting, sym_allow_nan, sym_allow_trailing_comma, sym_allow_control_characters, sym_symbolize_names, sym_freeze,
             sym_decimal_class, sym_on_load, sym_allow_duplicate_key;

static int binary_encindex;
static int utf8_encindex;

#ifndef HAVE_RB_HASH_BULK_INSERT
// For TruffleRuby
static void
rb_hash_bulk_insert(long count, const VALUE *pairs, VALUE hash)
{
    long index = 0;
    while (index < count) {
        VALUE name = pairs[index++];
        VALUE value = pairs[index++];
        rb_hash_aset(hash, name, value);
    }
    RB_GC_GUARD(hash);
}
#endif

#ifndef HAVE_RB_HASH_NEW_CAPA
#define rb_hash_new_capa(n) rb_hash_new()
#endif

#ifndef HAVE_RB_STR_TO_INTERNED_STR
static VALUE rb_str_to_interned_str(VALUE str)
{
    return rb_funcall(rb_str_freeze(str), i_uminus, 0);
}
#endif

/* name cache */

#include <string.h>
#include <ctype.h>

// Object names are likely to be repeated, and are frozen.
// As such we can re-use them if we keep a cache of the ones we've seen so far,
// and save much more expensive lookups into the global fstring table.
// This cache implementation is deliberately simple, as we're optimizing for compactness,
// to be able to fit safely on the stack.
// As such, binary search into a sorted array gives a good tradeoff between compactness and
// performance.
#define JSON_RVALUE_CACHE_CAPA 63
typedef struct rvalue_cache_struct {
    int length;
    VALUE entries[JSON_RVALUE_CACHE_CAPA];
} rvalue_cache;

static rb_encoding *enc_utf8;

#define JSON_RVALUE_CACHE_MAX_ENTRY_LENGTH 55

static inline VALUE build_interned_string(const char *str, const long length)
{
# ifdef HAVE_RB_ENC_INTERNED_STR
    return rb_enc_interned_str(str, length, enc_utf8);
# else
    VALUE rstring = rb_utf8_str_new(str, length);
    return rb_funcall(rb_str_freeze(rstring), i_uminus, 0);
# endif
}

static inline VALUE build_symbol(const char *str, const long length)
{
    return rb_str_intern(build_interned_string(str, length));
}

static void rvalue_cache_insert_at(rvalue_cache *cache, int index, VALUE rstring)
{
    MEMMOVE(&cache->entries[index + 1], &cache->entries[index], VALUE, cache->length - index);
    cache->length++;
    cache->entries[index] = rstring;
}

#define rstring_cache_memcmp memcmp

#if JSON_CPU_LITTLE_ENDIAN_64BITS
#if __has_builtin(__builtin_bswap64)
#undef rstring_cache_memcmp
ALWAYS_INLINE(static) int rstring_cache_memcmp(const char *str, const char *rptr, const long length)
{
    // The libc memcmp has numerous complex optimizations, but in this particular case,
    // we know the string is small (JSON_RVALUE_CACHE_MAX_ENTRY_LENGTH), so being able to
    // inline a simpler memcmp outperforms calling the libc version.
    long i = 0;

    for (; i + 8 <= length; i += 8) {
        uint64_t a, b;
        memcpy(&a, str + i, 8);
        memcpy(&b, rptr + i, 8);
        if (a != b) {
            a = __builtin_bswap64(a);
            b = __builtin_bswap64(b);
            return (a < b) ? -1 : 1;
        }
    }

    for (; i < length; i++) {
        if (str[i] != rptr[i]) {
            return (str[i] < rptr[i]) ? -1 : 1;
        }
    }

    return 0;
}
#endif
#endif

ALWAYS_INLINE(static) int rstring_cache_cmp(const char *str, const long length, VALUE rstring)
{
    const char *rstring_ptr;
    long rstring_length;

    RSTRING_GETMEM(rstring, rstring_ptr, rstring_length);

    if (length == rstring_length) {
        return rstring_cache_memcmp(str, rstring_ptr, length);
    } else {
        return (int)(length - rstring_length);
    }
}

ALWAYS_INLINE(static) VALUE rstring_cache_fetch(rvalue_cache *cache, const char *str, const long length)
{
    int low = 0;
    int high = cache->length - 1;

    while (low <= high) {
        int mid = (high + low) >> 1;
        VALUE entry = cache->entries[mid];
        int cmp = rstring_cache_cmp(str, length, entry);

        if (cmp == 0) {
            return entry;
        } else if (cmp > 0) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    VALUE rstring = build_interned_string(str, length);

    if (cache->length < JSON_RVALUE_CACHE_CAPA) {
        rvalue_cache_insert_at(cache, low, rstring);
    }
    return rstring;
}

static VALUE rsymbol_cache_fetch(rvalue_cache *cache, const char *str, const long length)
{
    int low = 0;
    int high = cache->length - 1;

    while (low <= high) {
        int mid = (high + low) >> 1;
        VALUE entry = cache->entries[mid];
        int cmp = rstring_cache_cmp(str, length, rb_sym2str(entry));

        if (cmp == 0) {
            return entry;
        } else if (cmp > 0) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    VALUE rsymbol = build_symbol(str, length);

    if (cache->length < JSON_RVALUE_CACHE_CAPA) {
        rvalue_cache_insert_at(cache, low, rsymbol);
    }
    return rsymbol;
}

/* rvalue stack */

#define RVALUE_STACK_INITIAL_CAPA 128

enum rvalue_stack_type {
    RVALUE_STACK_HEAP_ALLOCATED = 0,
    RVALUE_STACK_STACK_ALLOCATED = 1,
};

typedef struct rvalue_stack_struct {
    enum rvalue_stack_type type;
    long capa;
    long head;
    VALUE *ptr;
} rvalue_stack;

static rvalue_stack *rvalue_stack_spill(rvalue_stack *old_stack, VALUE *handle, rvalue_stack **stack_ref);

static rvalue_stack *rvalue_stack_grow(rvalue_stack *stack, VALUE *handle, rvalue_stack **stack_ref)
{
    long required = stack->capa * 2;

    if (stack->type == RVALUE_STACK_STACK_ALLOCATED) {
        stack = rvalue_stack_spill(stack, handle, stack_ref);
    } else {
        REALLOC_N(stack->ptr, VALUE, required);
        stack->capa = required;
    }
    return stack;
}

static VALUE rvalue_stack_push(rvalue_stack *stack, VALUE value, VALUE *handle, rvalue_stack **stack_ref)
{
    if (RB_UNLIKELY(stack->head >= stack->capa)) {
        stack = rvalue_stack_grow(stack, handle, stack_ref);
    }
    stack->ptr[stack->head] = value;
    stack->head++;
    return value;
}

static inline VALUE *rvalue_stack_peek(rvalue_stack *stack, long count)
{
    return stack->ptr + (stack->head - count);
}

static inline void rvalue_stack_pop(rvalue_stack *stack, long count)
{
    stack->head -= count;
}

static void rvalue_stack_mark(void *ptr)
{
    rvalue_stack *stack = (rvalue_stack *)ptr;
    long index;
    for (index = 0; index < stack->head; index++) {
        rb_gc_mark(stack->ptr[index]);
    }
}

static void rvalue_stack_free(void *ptr)
{
    rvalue_stack *stack = (rvalue_stack *)ptr;
    if (stack) {
        ruby_xfree(stack->ptr);
        ruby_xfree(stack);
    }
}

static size_t rvalue_stack_memsize(const void *ptr)
{
    const rvalue_stack *stack = (const rvalue_stack *)ptr;
    return sizeof(rvalue_stack) + sizeof(VALUE) * stack->capa;
}

static const rb_data_type_t JSON_Parser_rvalue_stack_type = {
    "JSON::Ext::Parser/rvalue_stack",
    {
        .dmark = rvalue_stack_mark,
        .dfree = rvalue_stack_free,
        .dsize = rvalue_stack_memsize,
    },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static rvalue_stack *rvalue_stack_spill(rvalue_stack *old_stack, VALUE *handle, rvalue_stack **stack_ref)
{
    rvalue_stack *stack;
    *handle = TypedData_Make_Struct(0, rvalue_stack, &JSON_Parser_rvalue_stack_type, stack);
    *stack_ref = stack;
    MEMCPY(stack, old_stack, rvalue_stack, 1);

    stack->capa = old_stack->capa << 1;
    stack->ptr = ALLOC_N(VALUE, stack->capa);
    stack->type = RVALUE_STACK_HEAP_ALLOCATED;
    MEMCPY(stack->ptr, old_stack->ptr, VALUE, old_stack->head);
    return stack;
}

static void rvalue_stack_eagerly_release(VALUE handle)
{
    if (handle) {
        rvalue_stack *stack;
        TypedData_Get_Struct(handle, rvalue_stack, &JSON_Parser_rvalue_stack_type, stack);
        RTYPEDDATA_DATA(handle) = NULL;
        rvalue_stack_free(stack);
    }
}

static int convert_UTF32_to_UTF8(char *buf, uint32_t ch)
{
    int len = 1;
    if (ch <= 0x7F) {
        buf[0] = (char) ch;
    } else if (ch <= 0x07FF) {
        buf[0] = (char) ((ch >> 6) | 0xC0);
        buf[1] = (char) ((ch & 0x3F) | 0x80);
        len++;
    } else if (ch <= 0xFFFF) {
        buf[0] = (char) ((ch >> 12) | 0xE0);
        buf[1] = (char) (((ch >> 6) & 0x3F) | 0x80);
        buf[2] = (char) ((ch & 0x3F) | 0x80);
        len += 2;
    } else if (ch <= 0x1fffff) {
        buf[0] =(char) ((ch >> 18) | 0xF0);
        buf[1] =(char) (((ch >> 12) & 0x3F) | 0x80);
        buf[2] =(char) (((ch >> 6) & 0x3F) | 0x80);
        buf[3] =(char) ((ch & 0x3F) | 0x80);
        len += 3;
    } else {
        buf[0] = '?';
    }
    return len;
}

enum duplicate_key_action {
    JSON_DEPRECATED = 0,
    JSON_IGNORE,
    JSON_RAISE,
};

typedef struct JSON_ParserStruct {
    VALUE on_load_proc;
    VALUE decimal_class;
    ID decimal_method_id;
    enum duplicate_key_action on_duplicate_key;
    int max_nesting;
    bool allow_nan;
    bool allow_trailing_comma;
    bool allow_control_characters;
    bool symbolize_names;
    bool freeze;
} JSON_ParserConfig;

typedef struct JSON_ParserStateStruct {
    VALUE stack_handle;
    const char *start;
    const char *cursor;
    const char *end;
    rvalue_stack *stack;
    rvalue_cache name_cache;
    int in_array;
    int current_nesting;
} JSON_ParserState;

static inline size_t rest(JSON_ParserState *state) {
    return state->end - state->cursor;
}

static inline bool eos(JSON_ParserState *state) {
    return state->cursor >= state->end;
}

static inline char peek(JSON_ParserState *state)
{
    if (RB_UNLIKELY(eos(state))) {
        return 0;
    }
    return *state->cursor;
}

static void cursor_position(JSON_ParserState *state, long *line_out, long *column_out)
{
    const char *cursor = state->cursor;
    long column = 0;
    long line = 1;

    while (cursor >= state->start) {
        if (*cursor-- == '\n') {
            break;
        }
        column++;
    }

    while (cursor >= state->start) {
        if (*cursor-- == '\n') {
            line++;
        }
    }
    *line_out = line;
    *column_out = column;
}

static void emit_parse_warning(const char *message, JSON_ParserState *state)
{
    long line, column;
    cursor_position(state, &line, &column);

    VALUE warning = rb_sprintf("%s at line %ld column %ld", message, line, column);
    rb_funcall(mJSON, rb_intern("deprecation_warning"), 1, warning);
}

#define PARSE_ERROR_FRAGMENT_LEN 32

#ifdef RBIMPL_ATTR_NORETURN
RBIMPL_ATTR_NORETURN()
#endif
static void raise_parse_error(const char *format, JSON_ParserState *state)
{
    unsigned char buffer[PARSE_ERROR_FRAGMENT_LEN + 3];
    long line, column;
    cursor_position(state, &line, &column);

    const char *ptr = "EOF";
    if (state->cursor && state->cursor < state->end) {
        ptr = state->cursor;
        size_t len = 0;
        while (len < PARSE_ERROR_FRAGMENT_LEN) {
            char ch = ptr[len];
            if (!ch || ch == '\n' || ch == ' ' || ch == '\t' || ch == '\r') {
                break;
            }
            len++;
        }

        if (len) {
            buffer[0] = '\'';
            MEMCPY(buffer + 1, ptr, char, len);

            while (buffer[len] >= 0x80 && buffer[len] < 0xC0) { // Is continuation byte
                len--;
            }

            if (buffer[len] >= 0xC0) { // multibyte character start
                len--;
            }

            buffer[len + 1] = '\'';
            buffer[len + 2] = '\0';
            ptr = (const char *)buffer;
        }
    }

    VALUE msg = rb_sprintf(format, ptr);
    VALUE message = rb_enc_sprintf(enc_utf8, "%s at line %ld column %ld", RSTRING_PTR(msg), line, column);
    RB_GC_GUARD(msg);

    VALUE exc = rb_exc_new_str(rb_path2class("JSON::ParserError"), message);
    rb_ivar_set(exc, rb_intern("@line"), LONG2NUM(line));
    rb_ivar_set(exc, rb_intern("@column"), LONG2NUM(column));
    rb_exc_raise(exc);
}

#ifdef RBIMPL_ATTR_NORETURN
RBIMPL_ATTR_NORETURN()
#endif
static void raise_parse_error_at(const char *format, JSON_ParserState *state, const char *at)
{
    state->cursor = at;
    raise_parse_error(format, state);
}

/* unicode */

static const signed char digit_values[256] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1,
    -1, -1, -1, -1, -1, -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1
};

static uint32_t unescape_unicode(JSON_ParserState *state, const unsigned char *p)
{
    signed char b;
    uint32_t result = 0;
    b = digit_values[p[0]];
    if (b < 0) raise_parse_error_at("incomplete unicode character escape sequence at %s", state, (char *)p - 2);
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[1]];
    if (b < 0) raise_parse_error_at("incomplete unicode character escape sequence at %s", state, (char *)p - 2);
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[2]];
    if (b < 0) raise_parse_error_at("incomplete unicode character escape sequence at %s", state, (char *)p - 2);
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[3]];
    if (b < 0) raise_parse_error_at("incomplete unicode character escape sequence at %s", state, (char *)p - 2);
    result = (result << 4) | (unsigned char)b;
    return result;
}

#define GET_PARSER_CONFIG                          \
    JSON_ParserConfig *config;                      \
    TypedData_Get_Struct(self, JSON_ParserConfig, &JSON_ParserConfig_type, config)

static const rb_data_type_t JSON_ParserConfig_type;

static void
json_eat_comments(JSON_ParserState *state)
{
    const char *start = state->cursor;
    state->cursor++;

    switch (peek(state)) {
        case '/': {
            state->cursor = memchr(state->cursor, '\n', state->end - state->cursor);
            if (!state->cursor) {
                state->cursor = state->end;
            } else {
                state->cursor++;
            }
            break;
        }
        case '*': {
            state->cursor++;

            while (true) {
                const char *next_match = memchr(state->cursor, '*', state->end - state->cursor);
                if (!next_match) {
                    raise_parse_error_at("unterminated comment, expected closing '*/'", state, start);
                }

                state->cursor = next_match + 1;
                if (peek(state) == '/') {
                    state->cursor++;
                    break;
                }
            }
            break;
        }
        default:
            raise_parse_error_at("unexpected token %s", state, start);
            break;
    }
}

ALWAYS_INLINE(static) void
json_eat_whitespace(JSON_ParserState *state)
{
    while (true) {
        switch (peek(state)) {
            case ' ':
                state->cursor++;
                break;
            case '\n':
                state->cursor++;

                // Heuristic: if we see a newline, there is likely consecutive spaces after it.
#if JSON_CPU_LITTLE_ENDIAN_64BITS
                while (rest(state) > 8) {
                    uint64_t chunk;
                    memcpy(&chunk, state->cursor, sizeof(uint64_t));
                    if (chunk == 0x2020202020202020) {
                        state->cursor += 8;
                        continue;
                    }

                    uint32_t consecutive_spaces = trailing_zeros64(chunk ^ 0x2020202020202020) / CHAR_BIT;
                    state->cursor += consecutive_spaces;
                    break;
                }
#endif
                break;
            case '\t':
            case '\r':
                state->cursor++;
                break;
            case '/':
                json_eat_comments(state);
                break;

            default:
                return;
        }
    }
}

static inline VALUE build_string(const char *start, const char *end, bool intern, bool symbolize)
{
    if (symbolize) {
        intern = true;
    }
    VALUE result;
# ifdef HAVE_RB_ENC_INTERNED_STR
    if (intern) {
      result = rb_enc_interned_str(start, (long)(end - start), enc_utf8);
    } else {
      result = rb_utf8_str_new(start, (long)(end - start));
    }
# else
    result = rb_utf8_str_new(start, (long)(end - start));
    if (intern) {
        result = rb_funcall(rb_str_freeze(result), i_uminus, 0);
    }
# endif

    if (symbolize) {
      result = rb_str_intern(result);
    }

    return result;
}

static inline bool json_string_cacheable_p(const char *string, size_t length)
{
    //  We mostly want to cache strings that are likely to be repeated.
    // Simple heuristics:
    //  - Common names aren't likely to be very long. So we just don't cache names above an arbitrary threshold.
    //  - If the first character isn't a letter, we're much less likely to see this string again.
    return length <= JSON_RVALUE_CACHE_MAX_ENTRY_LENGTH && rb_isalpha(string[0]);
}

static inline VALUE json_string_fastpath(JSON_ParserState *state, JSON_ParserConfig *config, const char *string, const char *stringEnd, bool is_name)
{
    bool intern = is_name || config->freeze;
    bool symbolize = is_name && config->symbolize_names;
    size_t bufferSize = stringEnd - string;

    if (is_name && state->in_array && RB_LIKELY(json_string_cacheable_p(string, bufferSize))) {
        VALUE cached_key;
        if (RB_UNLIKELY(symbolize)) {
            cached_key = rsymbol_cache_fetch(&state->name_cache, string, bufferSize);
        } else {
            cached_key = rstring_cache_fetch(&state->name_cache, string, bufferSize);
        }

        if (RB_LIKELY(cached_key)) {
            return cached_key;
        }
    }

    return build_string(string, stringEnd, intern, symbolize);
}

#define JSON_MAX_UNESCAPE_POSITIONS 16
typedef struct _json_unescape_positions {
    long size;
    const char **positions;
    bool has_more;
} JSON_UnescapePositions;

static inline const char *json_next_backslash(const char *pe, const char *stringEnd, JSON_UnescapePositions *positions)
{
    while (positions->size) {
        positions->size--;
        const char *next_position = positions->positions[0];
        positions->positions++;
        if (next_position >= pe) {
            return next_position;
        }
    }

    if (positions->has_more) {
        return memchr(pe, '\\', stringEnd - pe);
    }

    return NULL;
}

NOINLINE(static) VALUE json_string_unescape(JSON_ParserState *state, JSON_ParserConfig *config, const char *string, const char *stringEnd, bool is_name, JSON_UnescapePositions *positions)
{
    bool intern = is_name || config->freeze;
    bool symbolize = is_name && config->symbolize_names;
    size_t bufferSize = stringEnd - string;
    const char *p = string, *pe = string, *bufferStart;
    char *buffer;

    VALUE result = rb_str_buf_new(bufferSize);
    rb_enc_associate_index(result, utf8_encindex);
    buffer = RSTRING_PTR(result);
    bufferStart = buffer;

#define APPEND_CHAR(chr) *buffer++ = chr; p = ++pe;

    while (pe < stringEnd && (pe = json_next_backslash(pe, stringEnd, positions))) {
        if (pe > p) {
          MEMCPY(buffer, p, char, pe - p);
          buffer += pe - p;
        }
        switch (*++pe) {
            case '"':
            case '/':
                p = pe; // nothing to unescape just need to skip the backslash
                break;
            case '\\':
                APPEND_CHAR('\\');
                break;
            case 'n':
                APPEND_CHAR('\n');
                break;
            case 'r':
                APPEND_CHAR('\r');
                break;
            case 't':
                APPEND_CHAR('\t');
                break;
            case 'b':
                APPEND_CHAR('\b');
                break;
            case 'f':
                APPEND_CHAR('\f');
                break;
            case 'u':
                if (pe > stringEnd - 5) {
                    raise_parse_error_at("incomplete unicode character escape sequence at %s", state, p);
                } else {
                    uint32_t ch = unescape_unicode(state, (unsigned char *) ++pe);
                    pe += 3;
                    /* To handle values above U+FFFF, we take a sequence of
                     * \uXXXX escapes in the U+D800..U+DBFF then
                     * U+DC00..U+DFFF ranges, take the low 10 bits from each
                     * to make a 20-bit number, then add 0x10000 to get the
                     * final codepoint.
                     *
                     * See Unicode 15: 3.8 "Surrogates", 5.3 "Handling
                     * Surrogate Pairs in UTF-16", and 23.6 "Surrogates
                     * Area".
                     */
                    if ((ch & 0xFC00) == 0xD800) {
                        pe++;
                        if (pe > stringEnd - 6) {
                            raise_parse_error_at("incomplete surrogate pair at %s", state, p);
                        }
                        if (pe[0] == '\\' && pe[1] == 'u') {
                            uint32_t sur = unescape_unicode(state, (unsigned char *) pe + 2);

                            if ((sur & 0xFC00) != 0xDC00) {
                                raise_parse_error_at("invalid surrogate pair at %s", state, p);
                            }

                            ch = (((ch & 0x3F) << 10) | ((((ch >> 6) & 0xF) + 1) << 16)
                                    | (sur & 0x3FF));
                            pe += 5;
                        } else {
                            raise_parse_error_at("incomplete surrogate pair at %s", state, p);
                            break;
                        }
                    }

                    char buf[4];
                    int unescape_len = convert_UTF32_to_UTF8(buf, ch);
                    MEMCPY(buffer, buf, char, unescape_len);
                    buffer += unescape_len;
                    p = ++pe;
                }
                break;
            default:
                if ((unsigned char)*pe < 0x20) {
                    if (!config->allow_control_characters) {
                        if (*pe == '\n') {
                            raise_parse_error_at("Invalid unescaped newline character (\\n) in string: %s", state, pe - 1);
                        }
                        raise_parse_error_at("invalid ASCII control character in string: %s", state, pe - 1);
                    }
                } else {
                    raise_parse_error_at("invalid escape character in string: %s", state, pe - 1);
                }
                break;
        }
    }
#undef APPEND_CHAR

    if (stringEnd > p) {
      MEMCPY(buffer, p, char, stringEnd - p);
      buffer += stringEnd - p;
    }
    rb_str_set_len(result, buffer - bufferStart);

    if (symbolize) {
        result = rb_str_intern(result);
    } else if (intern) {
        result = rb_str_to_interned_str(result);
    }

    return result;
}

#define MAX_FAST_INTEGER_SIZE 18

static VALUE json_decode_large_integer(const char *start, long len)
{
    VALUE buffer_v;
    char *buffer = RB_ALLOCV_N(char, buffer_v, len + 1);
    MEMCPY(buffer, start, char, len);
    buffer[len] = '\0';
    VALUE number = rb_cstr2inum(buffer, 10);
    RB_ALLOCV_END(buffer_v);
    return number;
}

static inline VALUE
json_decode_integer(uint64_t mantissa, int mantissa_digits, bool negative, const char *start, const char *end)
{
    if (RB_LIKELY(mantissa_digits < MAX_FAST_INTEGER_SIZE)) {
        if (negative) {
            return INT64T2NUM(-((int64_t)mantissa));
        }
        return UINT64T2NUM(mantissa);
    }

    return json_decode_large_integer(start, end - start);
}

static VALUE json_decode_large_float(const char *start, long len)
{
    if (RB_LIKELY(len < 64)) {
        char buffer[64];
        MEMCPY(buffer, start, char, len);
        buffer[len] = '\0';
        return DBL2NUM(rb_cstr_to_dbl(buffer, 1));
    }

    VALUE buffer_v;
    char *buffer = RB_ALLOCV_N(char, buffer_v, len + 1);
    MEMCPY(buffer, start, char, len);
    buffer[len] = '\0';
    VALUE number = DBL2NUM(rb_cstr_to_dbl(buffer, 1));
    RB_ALLOCV_END(buffer_v);
    return number;
}

/* Ruby JSON optimized float decoder using vendored Ryu algorithm
 * Accepts pre-extracted mantissa and exponent from first-pass validation
 */
static inline VALUE json_decode_float(JSON_ParserConfig *config, uint64_t mantissa, int mantissa_digits, int32_t exponent, bool negative,
                                          const char *start, const char *end)
{
    if (RB_UNLIKELY(config->decimal_class)) {
        VALUE text = rb_str_new(start, end - start);
        return rb_funcallv(config->decimal_class, config->decimal_method_id, 1, &text);
    }

    // Fall back to rb_cstr_to_dbl for potential subnormals (rare edge case)
    // Ryu has rounding issues with subnormals around 1e-310 (< 2.225e-308)
    if (RB_UNLIKELY(mantissa_digits > 17 || mantissa_digits + exponent < -307)) {
        return json_decode_large_float(start, end - start);
    }

    return DBL2NUM(ryu_s2d_from_parts(mantissa, mantissa_digits, exponent, negative));
}

static inline VALUE json_decode_array(JSON_ParserState *state, JSON_ParserConfig *config, long count)
{
    VALUE array = rb_ary_new_from_values(count, rvalue_stack_peek(state->stack, count));
    rvalue_stack_pop(state->stack, count);

    if (config->freeze) {
        RB_OBJ_FREEZE(array);
    }

    return array;
}

static VALUE json_find_duplicated_key(size_t count, const VALUE *pairs)
{
    VALUE set = rb_hash_new_capa(count / 2);
    for (size_t index = 0; index < count; index += 2) {
        size_t before = RHASH_SIZE(set);
        VALUE key = pairs[index];
        rb_hash_aset(set, key, Qtrue);
        if (RHASH_SIZE(set) == before) {
            if (RB_SYMBOL_P(key)) {
                return rb_sym2str(key);
            }
            return key;
        }
    }
    return Qfalse;
}

static void emit_duplicate_key_warning(JSON_ParserState *state, VALUE duplicate_key)
{
    VALUE message = rb_sprintf(
        "detected duplicate key %"PRIsVALUE" in JSON object. This will raise an error in json 3.0 unless enabled via `allow_duplicate_key: true`",
        rb_inspect(duplicate_key)
    );

    emit_parse_warning(RSTRING_PTR(message), state);
    RB_GC_GUARD(message);
}

#ifdef RBIMPL_ATTR_NORETURN
RBIMPL_ATTR_NORETURN()
#endif
static void raise_duplicate_key_error(JSON_ParserState *state, VALUE duplicate_key)
{
    VALUE message = rb_sprintf(
        "duplicate key %"PRIsVALUE,
        rb_inspect(duplicate_key)
    );

    raise_parse_error(RSTRING_PTR(message), state);
    RB_GC_GUARD(message);
}

static inline VALUE json_decode_object(JSON_ParserState *state, JSON_ParserConfig *config, size_t count)
{
    size_t entries_count = count / 2;
    VALUE object = rb_hash_new_capa(entries_count);
    const VALUE *pairs = rvalue_stack_peek(state->stack, count);
    rb_hash_bulk_insert(count, pairs, object);

    if (RB_UNLIKELY(RHASH_SIZE(object) < entries_count)) {
        switch (config->on_duplicate_key) {
            case JSON_IGNORE:
                break;
            case JSON_DEPRECATED:
                emit_duplicate_key_warning(state, json_find_duplicated_key(count, pairs));
                break;
            case JSON_RAISE:
                raise_duplicate_key_error(state, json_find_duplicated_key(count, pairs));
                break;
        }
    }

    rvalue_stack_pop(state->stack, count);

    if (config->freeze) {
        RB_OBJ_FREEZE(object);
    }

    return object;
}

static inline VALUE json_push_value(JSON_ParserState *state, JSON_ParserConfig *config, VALUE value)
{
    if (RB_UNLIKELY(config->on_load_proc)) {
        value = rb_proc_call_with_block(config->on_load_proc, 1, &value, Qnil);
    }
    rvalue_stack_push(state->stack, value, &state->stack_handle, &state->stack);
    return value;
}

static const bool string_scan_table[256] = {
    // ASCII Control Characters
     1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    // ASCII Characters
     0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // '"'
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, // '\\'
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

#ifdef HAVE_SIMD
static SIMD_Implementation simd_impl = SIMD_NONE;
#endif /* HAVE_SIMD */

ALWAYS_INLINE(static) bool string_scan(JSON_ParserState *state)
{
#ifdef HAVE_SIMD
#if defined(HAVE_SIMD_NEON)

    uint64_t mask = 0;
    if (string_scan_simd_neon(&state->cursor, state->end, &mask)) {
        state->cursor += trailing_zeros64(mask) >> 2;
        return true;
    }

#elif defined(HAVE_SIMD_SSE2)
    if (simd_impl == SIMD_SSE2) {
        int mask = 0;
        if (string_scan_simd_sse2(&state->cursor, state->end, &mask)) {
            state->cursor += trailing_zeros(mask);
            return true;
        }
    }
#endif /* HAVE_SIMD_NEON or HAVE_SIMD_SSE2 */
#endif /* HAVE_SIMD */

    while (!eos(state)) {
        if (RB_UNLIKELY(string_scan_table[(unsigned char)*state->cursor])) {
            return true;
        }
        state->cursor++;
    }
    return false;
}

static VALUE json_parse_escaped_string(JSON_ParserState *state, JSON_ParserConfig *config, bool is_name, const char *start)
{
    const char *backslashes[JSON_MAX_UNESCAPE_POSITIONS];
    JSON_UnescapePositions positions = {
        .size = 0,
        .positions = backslashes,
        .has_more = false,
    };

    do {
        switch (*state->cursor) {
            case '"': {
                VALUE string = json_string_unescape(state, config, start, state->cursor, is_name, &positions);
                state->cursor++;
                return json_push_value(state, config, string);
            }
            case '\\': {
                if (RB_LIKELY(positions.size < JSON_MAX_UNESCAPE_POSITIONS)) {
                    backslashes[positions.size] = state->cursor;
                    positions.size++;
                } else {
                    positions.has_more = true;
                }
                state->cursor++;
                break;
            }
            default:
                if (!config->allow_control_characters) {
                    raise_parse_error("invalid ASCII control character in string: %s", state);
                }
                break;
        }

        state->cursor++;
    } while (string_scan(state));

    raise_parse_error("unexpected end of input, expected closing \"", state);
    return Qfalse;
}

ALWAYS_INLINE(static) VALUE json_parse_string(JSON_ParserState *state, JSON_ParserConfig *config, bool is_name)
{
    state->cursor++;
    const char *start = state->cursor;

    if (RB_UNLIKELY(!string_scan(state))) {
        raise_parse_error("unexpected end of input, expected closing \"", state);
    }

    if (RB_LIKELY(*state->cursor == '"')) {
        VALUE string = json_string_fastpath(state, config, start, state->cursor, is_name);
        state->cursor++;
        return json_push_value(state, config, string);
    }
    return json_parse_escaped_string(state, config, is_name, start);
}

#if JSON_CPU_LITTLE_ENDIAN_64BITS
// From: https://lemire.me/blog/2022/01/21/swar-explained-parsing-eight-digits/
// Additional References:
// https://johnnylee-sde.github.io/Fast-numeric-string-to-int/
// http://0x80.pl/notesen/2014-10-12-parsing-decimal-numbers-part-1-swar.html
static inline uint64_t decode_8digits_unrolled(uint64_t val) {
    const uint64_t mask = 0x000000FF000000FF;
    const uint64_t mul1 = 0x000F424000000064; // 100 + (1000000ULL << 32)
    const uint64_t mul2 = 0x0000271000000001; // 1 + (10000ULL << 32)
    val -= 0x3030303030303030;
    val = (val * 10) + (val >> 8); // val = (val * 2561) >> 8;
    val = (((val & mask) * mul1) + (((val >> 16) & mask) * mul2)) >> 32;
    return val;
}

static inline uint64_t decode_4digits_unrolled(uint32_t val) {
    const uint32_t mask = 0x000000FF;
    const uint32_t mul1 = 100;
    val -= 0x30303030;
    val = (val * 10) + (val >> 8); // val = (val * 2561) >> 8;
    val = ((val & mask) * mul1) + (((val >> 16) & mask));
    return val;
}
#endif

static inline int json_parse_digits(JSON_ParserState *state, uint64_t *accumulator)
{
    const char *start = state->cursor;

#if JSON_CPU_LITTLE_ENDIAN_64BITS
    while (rest(state) >= sizeof(uint64_t)) {
        uint64_t next_8bytes;
        memcpy(&next_8bytes, state->cursor, sizeof(uint64_t));

        // From: https://github.com/simdjson/simdjson/blob/32b301893c13d058095a07d9868edaaa42ee07aa/include/simdjson/generic/numberparsing.h#L333
        // Branchless version of: http://0x80.pl/articles/swar-digits-validate.html
        uint64_t match = (next_8bytes & 0xF0F0F0F0F0F0F0F0) | (((next_8bytes + 0x0606060606060606) & 0xF0F0F0F0F0F0F0F0) >> 4);

        if (match == 0x3333333333333333) { // 8 consecutive digits
            *accumulator = (*accumulator * 100000000) + decode_8digits_unrolled(next_8bytes);
            state->cursor += 8;
            continue;
        }

        uint32_t consecutive_digits = trailing_zeros64(match ^ 0x3333333333333333) / CHAR_BIT;

        if (consecutive_digits >= 4) {
            *accumulator = (*accumulator * 10000) + decode_4digits_unrolled((uint32_t)next_8bytes);
            state->cursor += 4;
            consecutive_digits -= 4;
        }

        while (consecutive_digits) {
            *accumulator = *accumulator * 10 + (*state->cursor - '0');
            consecutive_digits--;
            state->cursor++;
        }

        return (int)(state->cursor - start);
    }
#endif

    char next_char;
    while (rb_isdigit(next_char = peek(state))) {
        *accumulator = *accumulator * 10 + (next_char - '0');
        state->cursor++;
    }
    return (int)(state->cursor - start);
}

static inline VALUE json_parse_number(JSON_ParserState *state, JSON_ParserConfig *config, bool negative, const char *start)
{
    bool integer = true;
    const char first_digit = *state->cursor;

    // Variables for Ryu optimization - extract digits during parsing
    int32_t exponent = 0;
    int decimal_point_pos = -1;
    uint64_t mantissa = 0;

    // Parse integer part and extract mantissa digits
    int mantissa_digits = json_parse_digits(state, &mantissa);

    if (RB_UNLIKELY((first_digit == '0' && mantissa_digits > 1) || (negative && mantissa_digits == 0))) {
        raise_parse_error_at("invalid number: %s", state, start);
    }

    // Parse fractional part
    if (peek(state) == '.') {
        integer = false;
        decimal_point_pos = mantissa_digits;  // Remember position of decimal point
        state->cursor++;

        int fractional_digits = json_parse_digits(state, &mantissa);
        mantissa_digits += fractional_digits;

        if (RB_UNLIKELY(!fractional_digits)) {
            raise_parse_error_at("invalid number: %s", state, start);
        }
    }

    // Parse exponent
    if (rb_tolower(peek(state)) == 'e') {
        integer = false;
        state->cursor++;

        bool negative_exponent = false;
        const char next_char = peek(state);
        if (next_char == '-' || next_char == '+') {
            negative_exponent = next_char == '-';
            state->cursor++;
        }

        uint64_t abs_exponent = 0;
        int exponent_digits = json_parse_digits(state, &abs_exponent);

        if (RB_UNLIKELY(!exponent_digits)) {
            raise_parse_error_at("invalid number: %s", state, start);
        }

        exponent = negative_exponent ? -((int32_t)abs_exponent) : ((int32_t)abs_exponent);
    }

    if (integer) {
        return json_decode_integer(mantissa, mantissa_digits, negative, start, state->cursor);
    }

    // Adjust exponent based on decimal point position
    if (decimal_point_pos >= 0) {
        exponent -= (mantissa_digits - decimal_point_pos);
    }

    return json_decode_float(config, mantissa, mantissa_digits, exponent, negative, start, state->cursor);
}

static inline VALUE json_parse_positive_number(JSON_ParserState *state, JSON_ParserConfig *config)
{
    return json_parse_number(state, config, false, state->cursor);
}

static inline VALUE json_parse_negative_number(JSON_ParserState *state, JSON_ParserConfig *config)
{
    const char *start = state->cursor;
    state->cursor++;
    return json_parse_number(state, config, true, start);
}

static VALUE json_parse_any(JSON_ParserState *state, JSON_ParserConfig *config)
{
    json_eat_whitespace(state);

    switch (peek(state)) {
        case 'n':
            if (rest(state) >= 4 && (memcmp(state->cursor, "null", 4) == 0)) {
                state->cursor += 4;
                return json_push_value(state, config, Qnil);
            }

            raise_parse_error("unexpected token %s", state);
            break;
        case 't':
            if (rest(state) >= 4 && (memcmp(state->cursor, "true", 4) == 0)) {
                state->cursor += 4;
                return json_push_value(state, config, Qtrue);
            }

            raise_parse_error("unexpected token %s", state);
            break;
        case 'f':
            // Note: memcmp with a small power of two compile to an integer comparison
            if (rest(state) >= 5 && (memcmp(state->cursor + 1, "alse", 4) == 0)) {
                state->cursor += 5;
                return json_push_value(state, config, Qfalse);
            }

            raise_parse_error("unexpected token %s", state);
            break;
        case 'N':
            // Note: memcmp with a small power of two compile to an integer comparison
            if (config->allow_nan && rest(state) >= 3 && (memcmp(state->cursor + 1, "aN", 2) == 0)) {
                state->cursor += 3;
                return json_push_value(state, config, CNaN);
            }

            raise_parse_error("unexpected token %s", state);
            break;
        case 'I':
            if (config->allow_nan && rest(state) >= 8 && (memcmp(state->cursor, "Infinity", 8) == 0)) {
                state->cursor += 8;
                return json_push_value(state, config, CInfinity);
            }

            raise_parse_error("unexpected token %s", state);
            break;
        case '-': {
            // Note: memcmp with a small power of two compile to an integer comparison
            if (rest(state) >= 9 && (memcmp(state->cursor + 1, "Infinity", 8) == 0)) {
                if (config->allow_nan) {
                    state->cursor += 9;
                    return json_push_value(state, config, CMinusInfinity);
                } else {
                    raise_parse_error("unexpected token %s", state);
                }
            }
            return json_push_value(state, config, json_parse_negative_number(state, config));
            break;
        }
        case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
            return json_push_value(state, config, json_parse_positive_number(state, config));
            break;
        case '"': {
            // %r{\A"[^"\\\t\n\x00]*(?:\\[bfnrtu\\/"][^"\\]*)*"}
            return json_parse_string(state, config, false);
            break;
        }
        case '[': {
            state->cursor++;
            json_eat_whitespace(state);
            long stack_head = state->stack->head;

            if (peek(state) == ']') {
                state->cursor++;
                return json_push_value(state, config, json_decode_array(state, config, 0));
            } else {
                state->current_nesting++;
                if (RB_UNLIKELY(config->max_nesting && (config->max_nesting < state->current_nesting))) {
                    rb_raise(eNestingError, "nesting of %d is too deep", state->current_nesting);
                }
                state->in_array++;
                json_parse_any(state, config);
            }

            while (true) {
                json_eat_whitespace(state);

                const char next_char = peek(state);

                if (RB_LIKELY(next_char == ',')) {
                    state->cursor++;
                    if (config->allow_trailing_comma) {
                        json_eat_whitespace(state);
                        if (peek(state) == ']') {
                            continue;
                        }
                    }
                    json_parse_any(state, config);
                    continue;
                }

                if (next_char == ']') {
                    state->cursor++;
                    long count = state->stack->head - stack_head;
                    state->current_nesting--;
                    state->in_array--;
                    return json_push_value(state, config, json_decode_array(state, config, count));
                }

                raise_parse_error("expected ',' or ']' after array value", state);
            }
            break;
        }
        case '{': {
            const char *object_start_cursor = state->cursor;

            state->cursor++;
            json_eat_whitespace(state);
            long stack_head = state->stack->head;

            if (peek(state) == '}') {
                state->cursor++;
                return json_push_value(state, config, json_decode_object(state, config, 0));
            } else {
                state->current_nesting++;
                if (RB_UNLIKELY(config->max_nesting && (config->max_nesting < state->current_nesting))) {
                    rb_raise(eNestingError, "nesting of %d is too deep", state->current_nesting);
                }

                if (peek(state) != '"') {
                    raise_parse_error("expected object key, got %s", state);
                }
                json_parse_string(state, config, true);

                json_eat_whitespace(state);
                if (peek(state) != ':') {
                    raise_parse_error("expected ':' after object key", state);
                }
                state->cursor++;

                json_parse_any(state, config);
            }

            while (true) {
                json_eat_whitespace(state);

                const char next_char = peek(state);
                if (next_char == '}') {
                    state->cursor++;
                    state->current_nesting--;
                    size_t count = state->stack->head - stack_head;

                    // Temporary rewind cursor in case an error is raised
                    const char *final_cursor = state->cursor;
                    state->cursor = object_start_cursor;
                    VALUE object = json_decode_object(state, config, count);
                    state->cursor = final_cursor;

                    return json_push_value(state, config, object);
                }

                if (next_char == ',') {
                    state->cursor++;
                    json_eat_whitespace(state);

                    if (config->allow_trailing_comma) {
                        if (peek(state) == '}') {
                            continue;
                        }
                    }

                    if (RB_UNLIKELY(peek(state) != '"')) {
                        raise_parse_error("expected object key, got: %s", state);
                    }
                    json_parse_string(state, config, true);

                    json_eat_whitespace(state);
                    if (RB_UNLIKELY(peek(state) != ':')) {
                        raise_parse_error("expected ':' after object key, got: %s", state);
                    }
                    state->cursor++;

                    json_parse_any(state, config);

                    continue;
                }

                raise_parse_error("expected ',' or '}' after object value, got: %s", state);
            }
            break;
        }

        case 0:
            raise_parse_error("unexpected end of input", state);
            break;

        default:
            raise_parse_error("unexpected character: %s", state);
            break;
    }

    raise_parse_error("unreachable: %s", state);
    return Qundef;
}

static void json_ensure_eof(JSON_ParserState *state)
{
    json_eat_whitespace(state);
    if (!eos(state)) {
        raise_parse_error("unexpected token at end of stream %s", state);
    }
}

/*
 * Document-class: JSON::Ext::Parser
 *
 * This is the JSON parser implemented as a C extension. It can be configured
 * to be used by setting
 *
 *  JSON.parser = JSON::Ext::Parser
 *
 * with the method parser= in JSON.
 *
 */

static VALUE convert_encoding(VALUE source)
{
  int encindex = RB_ENCODING_GET(source);

  if (RB_LIKELY(encindex == utf8_encindex)) {
    return source;
  }

 if (encindex == binary_encindex) {
    // For historical reason, we silently reinterpret binary strings as UTF-8
    return rb_enc_associate_index(rb_str_dup(source), utf8_encindex);
  }

  return rb_funcall(source, i_encode, 1, Encoding_UTF_8);
}

static int parser_config_init_i(VALUE key, VALUE val, VALUE data)
{
    JSON_ParserConfig *config = (JSON_ParserConfig *)data;

         if (key == sym_max_nesting)                { config->max_nesting = RTEST(val) ? FIX2INT(val) : 0; }
    else if (key == sym_allow_nan)                  { config->allow_nan = RTEST(val); }
    else if (key == sym_allow_trailing_comma)       { config->allow_trailing_comma = RTEST(val); }
    else if (key == sym_allow_control_characters)   { config->allow_control_characters = RTEST(val); }
    else if (key == sym_symbolize_names)            { config->symbolize_names = RTEST(val); }
    else if (key == sym_freeze)                     { config->freeze = RTEST(val); }
    else if (key == sym_on_load)                    { config->on_load_proc = RTEST(val) ? val : Qfalse; }
    else if (key == sym_allow_duplicate_key)        { config->on_duplicate_key = RTEST(val) ? JSON_IGNORE : JSON_RAISE; }
    else if (key == sym_decimal_class)              {
        if (RTEST(val)) {
            if (rb_respond_to(val, i_try_convert)) {
                config->decimal_class = val;
                config->decimal_method_id = i_try_convert;
            } else if (rb_respond_to(val, i_new)) {
                config->decimal_class = val;
                config->decimal_method_id = i_new;
            } else if (RB_TYPE_P(val, T_CLASS)) {
                VALUE name = rb_class_name(val);
                const char *name_cstr = RSTRING_PTR(name);
                const char *last_colon = strrchr(name_cstr, ':');
                if (last_colon) {
                    const char *mod_path_end = last_colon - 1;
                    VALUE mod_path = rb_str_substr(name, 0, mod_path_end - name_cstr);
                    config->decimal_class = rb_path_to_class(mod_path);

                    const char *method_name_beg = last_colon + 1;
                    long before_len = method_name_beg - name_cstr;
                    long len = RSTRING_LEN(name) - before_len;
                    VALUE method_name = rb_str_substr(name, before_len, len);
                    config->decimal_method_id = SYM2ID(rb_str_intern(method_name));
                } else {
                    config->decimal_class = rb_mKernel;
                    config->decimal_method_id = SYM2ID(rb_str_intern(name));
                }
            }
        }
    }

    return ST_CONTINUE;
}

static void parser_config_init(JSON_ParserConfig *config, VALUE opts)
{
    config->max_nesting = 100;

    if (!NIL_P(opts)) {
        Check_Type(opts, T_HASH);
        if (RHASH_SIZE(opts) > 0) {
            // We assume in most cases few keys are set so it's faster to go over
            // the provided keys than to check all possible keys.
            rb_hash_foreach(opts, parser_config_init_i, (VALUE)config);
        }

    }
}

/*
 * call-seq: new(opts => {})
 *
 * Creates a new JSON::Ext::ParserConfig instance.
 *
 * It will be configured by the _opts_ hash. _opts_ can have the following
 * keys:
 *
 * _opts_ can have the following keys:
 * * *max_nesting*: The maximum depth of nesting allowed in the parsed data
 *   structures. Disable depth checking with :max_nesting => false|nil|0, it
 *   defaults to 100.
 * * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
 *   defiance of RFC 4627 to be parsed by the Parser. This option defaults to
 *   false.
 * * *symbolize_names*: If set to true, returns symbols for the names
 *   (keys) in a JSON object. Otherwise strings are returned, which is
 *   also the default. It's not possible to use this option in
 *   conjunction with the *create_additions* option.
 * * *decimal_class*: Specifies which class to use instead of the default
 *    (Float) when parsing decimal numbers. This class must accept a single
 *    string argument in its constructor.
 */
static VALUE cParserConfig_initialize(VALUE self, VALUE opts)
{
    rb_check_frozen(self);
    GET_PARSER_CONFIG;

    parser_config_init(config, opts);

    RB_OBJ_WRITTEN(self, Qundef, config->decimal_class);

    return self;
}

static VALUE cParser_parse(JSON_ParserConfig *config, VALUE Vsource)
{
    Vsource = convert_encoding(StringValue(Vsource));
    StringValue(Vsource);

    VALUE rvalue_stack_buffer[RVALUE_STACK_INITIAL_CAPA];
    rvalue_stack stack = {
        .type = RVALUE_STACK_STACK_ALLOCATED,
        .ptr = rvalue_stack_buffer,
        .capa = RVALUE_STACK_INITIAL_CAPA,
    };

    long len;
    const char *start;
    RSTRING_GETMEM(Vsource, start, len);

    JSON_ParserState _state = {
        .start = start,
        .cursor = start,
        .end = start + len,
        .stack = &stack,
    };
    JSON_ParserState *state = &_state;

    VALUE result = json_parse_any(state, config);

    // This may be skipped in case of exception, but
    // it won't cause a leak.
    rvalue_stack_eagerly_release(state->stack_handle);

    json_ensure_eof(state);

    return result;
}

/*
 * call-seq: parse(source)
 *
 *  Parses the current JSON text _source_ and returns the complete data
 *  structure as a result.
 *  It raises JSON::ParserError if fail to parse.
 */
static VALUE cParserConfig_parse(VALUE self, VALUE Vsource)
{
    GET_PARSER_CONFIG;
    return cParser_parse(config, Vsource);
}

static VALUE cParser_m_parse(VALUE klass, VALUE Vsource, VALUE opts)
{
    Vsource = convert_encoding(StringValue(Vsource));
    StringValue(Vsource);

    JSON_ParserConfig _config = {0};
    JSON_ParserConfig *config = &_config;
    parser_config_init(config, opts);

    return cParser_parse(config, Vsource);
}

static void JSON_ParserConfig_mark(void *ptr)
{
    JSON_ParserConfig *config = ptr;
    rb_gc_mark(config->on_load_proc);
    rb_gc_mark(config->decimal_class);
}

static void JSON_ParserConfig_free(void *ptr)
{
    JSON_ParserConfig *config = ptr;
    ruby_xfree(config);
}

static size_t JSON_ParserConfig_memsize(const void *ptr)
{
    return sizeof(JSON_ParserConfig);
}

static const rb_data_type_t JSON_ParserConfig_type = {
    "JSON::Ext::Parser/ParserConfig",
    {
        JSON_ParserConfig_mark,
        JSON_ParserConfig_free,
        JSON_ParserConfig_memsize,
    },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE,
};

static VALUE cJSON_parser_s_allocate(VALUE klass)
{
    JSON_ParserConfig *config;
    return TypedData_Make_Struct(klass, JSON_ParserConfig, &JSON_ParserConfig_type, config);
}

void Init_parser(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

#undef rb_intern
    rb_require("json/common");
    mJSON = rb_define_module("JSON");
    VALUE mExt = rb_define_module_under(mJSON, "Ext");
    VALUE cParserConfig = rb_define_class_under(mExt, "ParserConfig", rb_cObject);
    eNestingError = rb_path2class("JSON::NestingError");
    rb_gc_register_mark_object(eNestingError);
    rb_define_alloc_func(cParserConfig, cJSON_parser_s_allocate);
    rb_define_method(cParserConfig, "initialize", cParserConfig_initialize, 1);
    rb_define_method(cParserConfig, "parse", cParserConfig_parse, 1);

    VALUE cParser = rb_define_class_under(mExt, "Parser", rb_cObject);
    rb_define_singleton_method(cParser, "parse", cParser_m_parse, 2);

    CNaN = rb_const_get(mJSON, rb_intern("NaN"));
    rb_gc_register_mark_object(CNaN);

    CInfinity = rb_const_get(mJSON, rb_intern("Infinity"));
    rb_gc_register_mark_object(CInfinity);

    CMinusInfinity = rb_const_get(mJSON, rb_intern("MinusInfinity"));
    rb_gc_register_mark_object(CMinusInfinity);

    rb_global_variable(&Encoding_UTF_8);
    Encoding_UTF_8 = rb_const_get(rb_path2class("Encoding"), rb_intern("UTF_8"));

    sym_max_nesting = ID2SYM(rb_intern("max_nesting"));
    sym_allow_nan = ID2SYM(rb_intern("allow_nan"));
    sym_allow_trailing_comma = ID2SYM(rb_intern("allow_trailing_comma"));
    sym_allow_control_characters = ID2SYM(rb_intern("allow_control_characters"));
    sym_symbolize_names = ID2SYM(rb_intern("symbolize_names"));
    sym_freeze = ID2SYM(rb_intern("freeze"));
    sym_on_load = ID2SYM(rb_intern("on_load"));
    sym_decimal_class = ID2SYM(rb_intern("decimal_class"));
    sym_allow_duplicate_key = ID2SYM(rb_intern("allow_duplicate_key"));

    i_new = rb_intern("new");
    i_try_convert = rb_intern("try_convert");
    i_uminus = rb_intern("-@");
    i_encode = rb_intern("encode");

    binary_encindex = rb_ascii8bit_encindex();
    utf8_encindex = rb_utf8_encindex();
    enc_utf8 = rb_utf8_encoding();

#ifdef HAVE_SIMD
    simd_impl = find_simd_implementation();
#endif
}
