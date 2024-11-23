#include "ruby.h"
#include "../fbuffer/fbuffer.h"

static VALUE mJSON, mExt, cParser, eNestingError, Encoding_UTF_8;
static VALUE CNaN, CInfinity, CMinusInfinity;

static ID i_json_creatable_p, i_json_create, i_create_id,
          i_chr, i_deep_const_get, i_match, i_aset, i_aref,
          i_leftshift, i_new, i_try_convert, i_uminus, i_encode;

static VALUE sym_max_nesting, sym_allow_nan, sym_allow_trailing_comma, sym_symbolize_names, sym_freeze,
             sym_create_additions, sym_create_id, sym_object_class, sym_array_class,
             sym_decimal_class, sym_match_string;

static int binary_encindex;
static int utf8_encindex;

#ifdef HAVE_RB_CATEGORY_WARN
# define json_deprecated(message) rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, message)
#else
# define json_deprecated(message) rb_warn(message)
#endif

static const char deprecated_create_additions_warning[] =
    "JSON.load implicit support for `create_additions: true` is deprecated "
    "and will be removed in 3.0, use JSON.unsafe_load or explicitly "
    "pass `create_additions: true`";

#ifndef HAVE_RB_HASH_BULK_INSERT
// For TruffleRuby
void rb_hash_bulk_insert(long count, const VALUE *pairs, VALUE hash)
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

static inline int rstring_cache_cmp(const char *str, const long length, VALUE rstring)
{
    long rstring_length = RSTRING_LEN(rstring);
    if (length == rstring_length) {
        return memcmp(str, RSTRING_PTR(rstring), length);
    } else {
        return (int)(length - rstring_length);
    }
}

static VALUE rstring_cache_fetch(rvalue_cache *cache, const char *str, const long length)
{
    if (RB_UNLIKELY(length > JSON_RVALUE_CACHE_MAX_ENTRY_LENGTH)) {
        // Common names aren't likely to be very long. So we just don't
        // cache names above an arbitrary threshold.
        return Qfalse;
    }

    if (RB_UNLIKELY(!isalpha(str[0]))) {
        // Simple heuristic, if the first character isn't a letter,
        // we're much less likely to see this string again.
        // We mostly want to cache strings that are likely to be repeated.
        return Qfalse;
    }

    int low = 0;
    int high = cache->length - 1;
    int mid = 0;
    int last_cmp = 0;

    while (low <= high) {
        mid = (high + low) >> 1;
        VALUE entry = cache->entries[mid];
        last_cmp = rstring_cache_cmp(str, length, entry);

        if (last_cmp == 0) {
            return entry;
        } else if (last_cmp > 0) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (RB_UNLIKELY(memchr(str, '\\', length))) {
        // We assume the overwhelming majority of names don't need to be escaped.
        // But if they do, we have to fallback to the slow path.
        return Qfalse;
    }

    VALUE rstring = build_interned_string(str, length);

    if (cache->length < JSON_RVALUE_CACHE_CAPA) {
        if (last_cmp > 0) {
            mid += 1;
        }

        rvalue_cache_insert_at(cache, mid, rstring);
    }
    return rstring;
}

static VALUE rsymbol_cache_fetch(rvalue_cache *cache, const char *str, const long length)
{
    if (RB_UNLIKELY(length > JSON_RVALUE_CACHE_MAX_ENTRY_LENGTH)) {
        // Common names aren't likely to be very long. So we just don't
        // cache names above an arbitrary threshold.
        return Qfalse;
    }

    if (RB_UNLIKELY(!isalpha(str[0]))) {
        // Simple heuristic, if the first character isn't a letter,
        // we're much less likely to see this string again.
        // We mostly want to cache strings that are likely to be repeated.
        return Qfalse;
    }

    int low = 0;
    int high = cache->length - 1;
    int mid = 0;
    int last_cmp = 0;

    while (low <= high) {
        mid = (high + low) >> 1;
        VALUE entry = cache->entries[mid];
        last_cmp = rstring_cache_cmp(str, length, rb_sym2str(entry));

        if (last_cmp == 0) {
            return entry;
        } else if (last_cmp > 0) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (RB_UNLIKELY(memchr(str, '\\', length))) {
        // We assume the overwhelming majority of names don't need to be escaped.
        // But if they do, we have to fallback to the slow path.
        return Qfalse;
    }

    VALUE rsymbol = build_symbol(str, length);

    if (cache->length < JSON_RVALUE_CACHE_CAPA) {
        if (last_cmp > 0) {
            mid += 1;
        }

        rvalue_cache_insert_at(cache, mid, rsymbol);
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

static void rvalue_stack_push(rvalue_stack *stack, VALUE value, VALUE *handle, rvalue_stack **stack_ref)
{
    if (RB_UNLIKELY(stack->head >= stack->capa)) {
        stack = rvalue_stack_grow(stack, handle, stack_ref);
    }
    stack->ptr[stack->head] = value;
    stack->head++;
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
    rvalue_stack *stack;
    TypedData_Get_Struct(handle, rvalue_stack, &JSON_Parser_rvalue_stack_type, stack);
    RTYPEDDATA_DATA(handle) = NULL;
    rvalue_stack_free(stack);
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

static uint32_t unescape_unicode(const unsigned char *p)
{
    const uint32_t replacement_char = 0xFFFD;

    signed char b;
    uint32_t result = 0;
    b = digit_values[p[0]];
    if (b < 0) return replacement_char;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[1]];
    if (b < 0) return replacement_char;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[2]];
    if (b < 0) return replacement_char;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[3]];
    if (b < 0) return replacement_char;
    result = (result << 4) | (unsigned char)b;
    return result;
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

typedef struct JSON_ParserStruct {
    VALUE Vsource;
    char *source;
    long len;
    char *memo;
    VALUE create_id;
    VALUE object_class;
    VALUE array_class;
    VALUE decimal_class;
    VALUE match_string;
    FBuffer fbuffer;
    int in_array;
    int max_nesting;
    bool allow_nan;
    bool allow_trailing_comma;
    bool parsing_name;
    bool symbolize_names;
    bool freeze;
    bool create_additions;
    bool deprecated_create_additions;
    rvalue_cache name_cache;
    rvalue_stack *stack;
    VALUE stack_handle;
} JSON_Parser;

#define GET_PARSER                          \
    GET_PARSER_INIT;                        \
    if (!json->Vsource) rb_raise(rb_eTypeError, "uninitialized instance")

#define GET_PARSER_INIT                     \
    JSON_Parser *json;                      \
    TypedData_Get_Struct(self, JSON_Parser, &JSON_Parser_type, json)

#define MinusInfinity "-Infinity"
#define EVIL 0x666

static const rb_data_type_t JSON_Parser_type;
static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);
static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);
static char *JSON_parse_number(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);


#define PARSE_ERROR_FRAGMENT_LEN 32
#ifdef RBIMPL_ATTR_NORETURN
RBIMPL_ATTR_NORETURN()
#endif
static void raise_parse_error(const char *format, const char *start)
{
    char buffer[PARSE_ERROR_FRAGMENT_LEN + 1];

    size_t len = strnlen(start, PARSE_ERROR_FRAGMENT_LEN);
    const char *ptr = start;

    if (len == PARSE_ERROR_FRAGMENT_LEN) {
        MEMCPY(buffer, start, char, PARSE_ERROR_FRAGMENT_LEN);
        buffer[PARSE_ERROR_FRAGMENT_LEN] = '\0';
        ptr = buffer;
    }

    rb_enc_raise(enc_utf8, rb_path2class("JSON::ParserError"), format, ptr);
}


%%{
    machine JSON_common;

    cr                  = '\n';
    cr_neg              = [^\n];
    ws                  = [ \t\r\n];
    c_comment           = '/*' ( any* - (any* '*/' any* ) ) '*/';
    cpp_comment         = '//' cr_neg* cr;
    comment             = c_comment | cpp_comment;
    ignore              = ws | comment;
    name_separator      = ':';
    value_separator     = ',';
    Vnull               = 'null';
    Vfalse              = 'false';
    Vtrue               = 'true';
    VNaN                = 'NaN';
    VInfinity           = 'Infinity';
    VMinusInfinity      = '-Infinity';
    begin_value         = [nft\"\-\[\{NI] | digit;
    begin_object        = '{';
    end_object          = '}';
    begin_array         = '[';
    end_array           = ']';
    begin_string        = '"';
    begin_name          = begin_string;
    begin_number        = digit | '-';
}%%

%%{
    machine JSON_object;
    include JSON_common;

    write data;

    action parse_value {
        char *np = JSON_parse_value(json, fpc, pe, result, current_nesting);
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }

    action allow_trailing_comma { json->allow_trailing_comma }

    action parse_name {
        char *np;
        json->parsing_name = true;
        np = JSON_parse_string(json, fpc, pe, result);
        json->parsing_name = false;
        if (np == NULL) { fhold; fbreak; } else {
            PUSH(*result);
            fexec np;
         }
    }

    action exit { fhold; fbreak; }

    pair  = ignore* begin_name >parse_name ignore* name_separator ignore* begin_value >parse_value;
    next_pair   = ignore* value_separator pair;

    main := (
      begin_object
      (pair (next_pair)*((ignore* value_separator) when allow_trailing_comma)?)? ignore*
      end_object
    ) @exit;
}%%

#define PUSH(result) rvalue_stack_push(json->stack, result, &json->stack_handle, &json->stack)

static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;

    if (json->max_nesting && current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", current_nesting);
    }

    long stack_head = json->stack->head;

    %% write init;
    %% write exec;

    if (cs >= JSON_object_first_final) {
        long count = json->stack->head - stack_head;

        if (RB_UNLIKELY(json->object_class)) {
            VALUE object = rb_class_new_instance(0, 0, json->object_class);
            long index = 0;
            VALUE *items = rvalue_stack_peek(json->stack, count);
            while (index < count) {
                VALUE name = items[index++];
                VALUE value = items[index++];
                rb_funcall(object, i_aset, 2, name, value);
            }
            *result = object;
        } else {
            VALUE hash;
#ifdef HAVE_RB_HASH_NEW_CAPA
            hash = rb_hash_new_capa(count >> 1);
#else
            hash = rb_hash_new();
#endif
            rb_hash_bulk_insert(count, rvalue_stack_peek(json->stack, count), hash);
            *result = hash;
        }
        rvalue_stack_pop(json->stack, count);

        if (RB_UNLIKELY(json->create_additions)) {
            VALUE klassname;
            if (json->object_class) {
                klassname = rb_funcall(*result, i_aref, 1, json->create_id);
            } else {
                klassname = rb_hash_aref(*result, json->create_id);
            }
            if (!NIL_P(klassname)) {
                VALUE klass = rb_funcall(mJSON, i_deep_const_get, 1, klassname);
                if (RTEST(rb_funcall(klass, i_json_creatable_p, 0))) {
                    if (json->deprecated_create_additions) {
                        json_deprecated(deprecated_create_additions_warning);
                    }
                    *result = rb_funcall(klass, i_json_create, 1, *result);
                }
            }
        }
        return p + 1;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_value;
    include JSON_common;

    write data;

    action parse_null {
        *result = Qnil;
    }
    action parse_false {
        *result = Qfalse;
    }
    action parse_true {
        *result = Qtrue;
    }
    action parse_nan {
        if (json->allow_nan) {
            *result = CNaN;
        } else {
            raise_parse_error("unexpected token at '%s'", p - 2);
        }
    }
    action parse_infinity {
        if (json->allow_nan) {
            *result = CInfinity;
        } else {
            raise_parse_error("unexpected token at '%s'", p - 7);
        }
    }
    action parse_string {
        char *np = JSON_parse_string(json, fpc, pe, result);
        if (np == NULL) {
            fhold;
            fbreak;
        } else {
            fexec np;
        }
    }

    action parse_number {
        char *np;
        if(pe > fpc + 8 && !strncmp(MinusInfinity, fpc, 9)) {
            if (json->allow_nan) {
                *result = CMinusInfinity;
                fexec p + 10;
                fhold; fbreak;
            } else {
                raise_parse_error("unexpected token at '%s'", p);
            }
        }
        np = JSON_parse_number(json, fpc, pe, result);
        if (np != NULL) {
            fexec np;
        }
        fhold; fbreak;
    }

    action parse_array {
        char *np;
        json->in_array++;
        np = JSON_parse_array(json, fpc, pe, result, current_nesting + 1);
        json->in_array--;
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_object {
        char *np;
        np =  JSON_parse_object(json, fpc, pe, result, current_nesting + 1);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

main := ignore* (
              Vnull @parse_null |
              Vfalse @parse_false |
              Vtrue @parse_true |
              VNaN @parse_nan |
              VInfinity @parse_infinity |
              begin_number @parse_number |
              begin_string @parse_string |
              begin_array @parse_array |
              begin_object @parse_object
        ) ignore* %*exit;
}%%

static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;

    %% write init;
    %% write exec;

    if (json->freeze) {
        OBJ_FREEZE(*result);
    }

    if (cs >= JSON_value_first_final) {
        PUSH(*result);
        return p;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_integer;

    write data;

    action exit { fhold; fbreak; }

    main := '-'? ('0' | [1-9][0-9]*) (^[0-9]? @exit);
}%%

#define MAX_FAST_INTEGER_SIZE 18
static inline VALUE fast_parse_integer(char *p, char *pe)
{
    bool negative = false;
    if (*p == '-') {
        negative = true;
        p++;
    }

    long long memo = 0;
    while (p < pe) {
        memo *= 10;
        memo += *p - '0';
        p++;
    }

    if (negative) {
        memo = -memo;
    }
    return LL2NUM(memo);
}

static char *JSON_decode_integer(JSON_Parser *json, char *p, VALUE *result)
{
        long len = p - json->memo;
        if (RB_LIKELY(len < MAX_FAST_INTEGER_SIZE)) {
            *result = fast_parse_integer(json->memo, p);
        } else {
            fbuffer_clear(&json->fbuffer);
            fbuffer_append(&json->fbuffer, json->memo, len);
            fbuffer_append_char(&json->fbuffer, '\0');
            *result = rb_cstr2inum(FBUFFER_PTR(&json->fbuffer), 10);
        }
        return p + 1;
}

%%{
    machine JSON_float;
    include JSON_common;

    write data;

    action exit { fhold; fbreak; }
    action isFloat {  is_float = true; }

    main := '-'? (
              (('0' | [1-9][0-9]*)
                ((('.' [0-9]+ ([Ee] [+\-]?[0-9]+)?) |
                 ([Ee] [+\-]?[0-9]+)) > isFloat)?
              ) (^[0-9Ee.\-]? @exit ));
}%%

static char *JSON_parse_number(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    bool is_float = false;

    %% write init;
    json->memo = p;
    %% write exec;

    if (cs >= JSON_float_first_final) {
        if (!is_float) {
            return JSON_decode_integer(json, p, result);
        }
        VALUE mod = Qnil;
        ID method_id = 0;
        if (json->decimal_class) {
            if (rb_respond_to(json->decimal_class, i_try_convert)) {
                mod = json->decimal_class;
                method_id = i_try_convert;
            } else if (rb_respond_to(json->decimal_class, i_new)) {
                mod = json->decimal_class;
                method_id = i_new;
            } else if (RB_TYPE_P(json->decimal_class, T_CLASS)) {
                VALUE name = rb_class_name(json->decimal_class);
                const char *name_cstr = RSTRING_PTR(name);
                const char *last_colon = strrchr(name_cstr, ':');
                if (last_colon) {
                    const char *mod_path_end = last_colon - 1;
                    VALUE mod_path = rb_str_substr(name, 0, mod_path_end - name_cstr);
                    mod = rb_path_to_class(mod_path);

                    const char *method_name_beg = last_colon + 1;
                    long before_len = method_name_beg - name_cstr;
                    long len = RSTRING_LEN(name) - before_len;
                    VALUE method_name = rb_str_substr(name, before_len, len);
                    method_id = SYM2ID(rb_str_intern(method_name));
                } else {
                    mod = rb_mKernel;
                    method_id = SYM2ID(rb_str_intern(name));
                }
            }
        }

        long len = p - json->memo;
        fbuffer_clear(&json->fbuffer);
        fbuffer_append(&json->fbuffer, json->memo, len);
        fbuffer_append_char(&json->fbuffer, '\0');

        if (method_id) {
            VALUE text = rb_str_new2(FBUFFER_PTR(&json->fbuffer));
            *result = rb_funcallv(mod, method_id, 1, &text);
        } else {
            *result = DBL2NUM(rb_cstr_to_dbl(FBUFFER_PTR(&json->fbuffer), 1));
        }

        return p + 1;
    } else {
        return NULL;
    }
}


%%{
    machine JSON_array;
    include JSON_common;

    write data;

    action parse_value {
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, fpc, pe, &v, current_nesting);
        if (np == NULL) {
            fhold; fbreak;
        } else {
            fexec np;
        }
    }

    action allow_trailing_comma { json->allow_trailing_comma }

    action exit { fhold; fbreak; }

    next_element  = value_separator ignore* begin_value >parse_value;

    main := begin_array ignore*
          ((begin_value >parse_value ignore*)
          (ignore* next_element ignore*)*((value_separator ignore*) when allow_trailing_comma)?)?
          end_array @exit;
}%%

static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;

    if (json->max_nesting && current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", current_nesting);
    }
    long stack_head = json->stack->head;

    %% write init;
    %% write exec;

    if(cs >= JSON_array_first_final) {
        long count = json->stack->head - stack_head;

        if (RB_UNLIKELY(json->array_class)) {
            VALUE array = rb_class_new_instance(0, 0, json->array_class);
            VALUE *items = rvalue_stack_peek(json->stack, count);
            long index;
            for (index = 0; index < count; index++) {
                rb_funcall(array, i_leftshift, 1, items[index]);
            }
            *result = array;
        } else {
            VALUE array = rb_ary_new_from_values(count, rvalue_stack_peek(json->stack, count));
            *result = array;
        }
        rvalue_stack_pop(json->stack, count);

        return p + 1;
    } else {
        raise_parse_error("unexpected token at '%s'", p);
        return NULL;
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

static VALUE json_string_fastpath(JSON_Parser *json, char *string, char *stringEnd, bool is_name, bool intern, bool symbolize)
{
    size_t bufferSize = stringEnd - string;

    if (is_name && json->in_array) {
        VALUE cached_key;
        if (RB_UNLIKELY(symbolize)) {
            cached_key = rsymbol_cache_fetch(&json->name_cache, string, bufferSize);
        } else {
            cached_key = rstring_cache_fetch(&json->name_cache, string, bufferSize);
        }

        if (RB_LIKELY(cached_key)) {
            return cached_key;
        }
    }

    return build_string(string, stringEnd, intern, symbolize);
}

static VALUE json_string_unescape(JSON_Parser *json, char *string, char *stringEnd, bool is_name, bool intern, bool symbolize)
{
    size_t bufferSize = stringEnd - string;
    char *p = string, *pe = string, *unescape, *bufferStart, *buffer;
    int unescape_len;
    char buf[4];

    if (is_name && json->in_array) {
        VALUE cached_key;
        if (RB_UNLIKELY(symbolize)) {
            cached_key = rsymbol_cache_fetch(&json->name_cache, string, bufferSize);
        } else {
            cached_key = rstring_cache_fetch(&json->name_cache, string, bufferSize);
        }

        if (RB_LIKELY(cached_key)) {
            return cached_key;
        }
    }

    pe = memchr(p, '\\', bufferSize);
    if (RB_UNLIKELY(pe == NULL)) {
        return build_string(string, stringEnd, intern, symbolize);
    }

    VALUE result = rb_str_buf_new(bufferSize);
    rb_enc_associate_index(result, utf8_encindex);
    buffer = bufferStart = RSTRING_PTR(result);

    while (pe < stringEnd) {
        if (*pe == '\\') {
            unescape = (char *) "?";
            unescape_len = 1;
            if (pe > p) {
              MEMCPY(buffer, p, char, pe - p);
              buffer += pe - p;
            }
            switch (*++pe) {
                case 'n':
                    unescape = (char *) "\n";
                    break;
                case 'r':
                    unescape = (char *) "\r";
                    break;
                case 't':
                    unescape = (char *) "\t";
                    break;
                case '"':
                    unescape = (char *) "\"";
                    break;
                case '\\':
                    unescape = (char *) "\\";
                    break;
                case 'b':
                    unescape = (char *) "\b";
                    break;
                case 'f':
                    unescape = (char *) "\f";
                    break;
                case 'u':
                    if (pe > stringEnd - 4) {
                      raise_parse_error("incomplete unicode character escape sequence at '%s'", p);
                    } else {
                        uint32_t ch = unescape_unicode((unsigned char *) ++pe);
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
                              raise_parse_error("incomplete surrogate pair at '%s'", p);
                            }
                            if (pe[0] == '\\' && pe[1] == 'u') {
                                uint32_t sur = unescape_unicode((unsigned char *) pe + 2);
                                ch = (((ch & 0x3F) << 10) | ((((ch >> 6) & 0xF) + 1) << 16)
                                        | (sur & 0x3FF));
                                pe += 5;
                            } else {
                                unescape = (char *) "?";
                                break;
                            }
                        }
                        unescape_len = convert_UTF32_to_UTF8(buf, ch);
                        unescape = buf;
                    }
                    break;
                default:
                    p = pe;
                    continue;
            }
            MEMCPY(buffer, unescape, char, unescape_len);
            buffer += unescape_len;
            p = ++pe;
        } else {
            pe++;
        }
    }

    if (pe > p) {
      MEMCPY(buffer, p, char, pe - p);
      buffer += pe - p;
    }
    rb_str_set_len(result, buffer - bufferStart);

    if (symbolize) {
        result = rb_str_intern(result);
    } else if (intern) {
        result = rb_funcall(rb_str_freeze(result), i_uminus, 0);
    }

    return result;
}

%%{
    machine JSON_string;
    include JSON_common;

    write data;

    action parse_complex_string {
        *result = json_string_unescape(json, json->memo + 1, p, json->parsing_name, json->parsing_name || json-> freeze, json->parsing_name && json->symbolize_names);
        fexec p + 1;
        fhold;
        fbreak;
    }

    action parse_simple_string {
        *result = json_string_fastpath(json, json->memo + 1, p, json->parsing_name, json->parsing_name || json-> freeze, json->parsing_name && json->symbolize_names);
        fexec p + 1;
        fhold;
        fbreak;
    }

    double_quote = '"';
    escape = '\\';
    control = 0..0x1f;
    simple = any - escape - double_quote - control;

    main := double_quote (
         (simple*)(
            (double_quote) @parse_simple_string |
            ((^([\"\\] | control) | escape[\"\\/bfnrt] | '\\u'[0-9a-fA-F]{4} | escape^([\"\\/bfnrtu]|0..0x1f))* double_quote) @parse_complex_string
         )
    );
}%%

static int
match_i(VALUE regexp, VALUE klass, VALUE memo)
{
    if (regexp == Qundef) return ST_STOP;
    if (RTEST(rb_funcall(klass, i_json_creatable_p, 0)) &&
      RTEST(rb_funcall(regexp, i_match, 1, rb_ary_entry(memo, 0)))) {
        rb_ary_push(memo, klass);
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE match_string;

    %% write init;
    json->memo = p;
    %% write exec;

    if (json->create_additions && RTEST(match_string = json->match_string)) {
          VALUE klass;
          VALUE memo = rb_ary_new2(2);
          rb_ary_push(memo, *result);
          rb_hash_foreach(match_string, match_i, memo);
          klass = rb_ary_entry(memo, 1);
          if (RTEST(klass)) {
              *result = rb_funcall(klass, i_json_create, 1, *result);
          }
    }

    if (cs >= JSON_string_first_final) {
        return p + 1;
    } else {
        return NULL;
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

static int configure_parser_i(VALUE key, VALUE val, VALUE data)
{
    JSON_Parser *json = (JSON_Parser *)data;

         if (key == sym_max_nesting)          { json->max_nesting = RTEST(val) ? FIX2INT(val) : 0; }
    else if (key == sym_allow_nan)            { json->allow_nan = RTEST(val); }
    else if (key == sym_allow_trailing_comma) { json->allow_trailing_comma = RTEST(val); }
    else if (key == sym_symbolize_names)      { json->symbolize_names = RTEST(val); }
    else if (key == sym_freeze)               { json->freeze = RTEST(val); }
    else if (key == sym_create_id)            { json->create_id = RTEST(val) ? val : Qfalse; }
    else if (key == sym_object_class)         { json->object_class = RTEST(val) ? val : Qfalse; }
    else if (key == sym_array_class)          { json->array_class = RTEST(val) ? val : Qfalse; }
    else if (key == sym_decimal_class)        { json->decimal_class = RTEST(val) ? val : Qfalse; }
    else if (key == sym_match_string)         { json->match_string = RTEST(val) ? val : Qfalse; }
    else if (key == sym_create_additions)     {
        if (NIL_P(val)) {
            json->create_additions = true;
            json->deprecated_create_additions = true;
        } else {
            json->create_additions = RTEST(val);
            json->deprecated_create_additions = false;
        }
    }

    return ST_CONTINUE;
}

static void parser_init(JSON_Parser *json, VALUE source, VALUE opts)
{
    if (json->Vsource) {
        rb_raise(rb_eTypeError, "already initialized instance");
    }

    json->fbuffer.initial_length = FBUFFER_INITIAL_LENGTH_DEFAULT;
    json->max_nesting = 100;

    if (!NIL_P(opts)) {
        Check_Type(opts, T_HASH);
        if (RHASH_SIZE(opts) > 0) {
            // We assume in most cases few keys are set so it's faster to go over
            // the provided keys than to check all possible keys.
            rb_hash_foreach(opts, configure_parser_i, (VALUE)json);

            if (json->symbolize_names && json->create_additions) {
                rb_raise(rb_eArgError,
                    "options :symbolize_names and :create_additions cannot be "
                    " used in conjunction");
            }

            if (json->create_additions && !json->create_id) {
                json->create_id = rb_funcall(mJSON, i_create_id, 0);
            }
        }

    }
    source = convert_encoding(StringValue(source));
    StringValue(source);
    json->len = RSTRING_LEN(source);
    json->source = RSTRING_PTR(source);
    json->Vsource = source;
}

/*
 * call-seq: new(source, opts => {})
 *
 * Creates a new JSON::Ext::Parser instance for the string _source_.
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
 * * *create_additions*: If set to false, the Parser doesn't create
 *   additions even if a matching class and create_id was found. This option
 *   defaults to false.
 * * *object_class*: Defaults to Hash. If another type is provided, it will be used
 *   instead of Hash to represent JSON objects. The type must respond to
 *   +new+ without arguments, and return an object that respond to +[]=+.
 * * *array_class*: Defaults to Array If another type is provided, it will be used
 *   instead of Hash to represent JSON arrays. The type must respond to
 *   +new+ without arguments, and return an object that respond to +<<+.
 * * *decimal_class*: Specifies which class to use instead of the default
 *    (Float) when parsing decimal numbers. This class must accept a single
 *    string argument in its constructor.
 */
static VALUE cParser_initialize(int argc, VALUE *argv, VALUE self)
{
    GET_PARSER_INIT;

    rb_check_arity(argc, 1, 2);

    parser_init(json, argv[0], argc == 2 ? argv[1] : Qnil);
    return self;
}

%%{
    machine JSON;

    write data;

    include JSON_common;

    action parse_value {
        char *np = JSON_parse_value(json, fpc, pe, &result, 0);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    main := ignore* (
            begin_value >parse_value
            ) ignore*;
}%%

/*
 * call-seq: parse()
 *
 *  Parses the current JSON text _source_ and returns the complete data
 *  structure as a result.
 *  It raises JSON::ParserError if fail to parse.
 */
static VALUE cParser_parse(VALUE self)
{
    char *p, *pe;
    int cs = EVIL;
    VALUE result = Qnil;
    GET_PARSER;

    char stack_buffer[FBUFFER_STACK_SIZE];
    fbuffer_stack_init(&json->fbuffer, FBUFFER_INITIAL_LENGTH_DEFAULT, stack_buffer, FBUFFER_STACK_SIZE);

    VALUE rvalue_stack_buffer[RVALUE_STACK_INITIAL_CAPA];
    rvalue_stack stack = {
        .type = RVALUE_STACK_STACK_ALLOCATED,
        .ptr = rvalue_stack_buffer,
        .capa = RVALUE_STACK_INITIAL_CAPA,
    };
    json->stack = &stack;

    %% write init;
    p = json->source;
    pe = p + json->len;
    %% write exec;

    if (json->stack_handle) {
        rvalue_stack_eagerly_release(json->stack_handle);
    }

    if (cs >= JSON_first_final && p == pe) {
        return result;
    } else {
        raise_parse_error("unexpected token at '%s'", p);
        return Qnil;
    }
}

static VALUE cParser_m_parse(VALUE klass, VALUE source, VALUE opts)
{
    char *p, *pe;
    int cs = EVIL;
    VALUE result = Qnil;

    JSON_Parser _parser = {0};
    JSON_Parser *json = &_parser;
    parser_init(json, source, opts);

    char stack_buffer[FBUFFER_STACK_SIZE];
    fbuffer_stack_init(&json->fbuffer, FBUFFER_INITIAL_LENGTH_DEFAULT, stack_buffer, FBUFFER_STACK_SIZE);

    VALUE rvalue_stack_buffer[RVALUE_STACK_INITIAL_CAPA];
    rvalue_stack stack = {
        .type = RVALUE_STACK_STACK_ALLOCATED,
        .ptr = rvalue_stack_buffer,
        .capa = RVALUE_STACK_INITIAL_CAPA,
    };
    json->stack = &stack;

    %% write init;
    p = json->source;
    pe = p + json->len;
    %% write exec;

    if (json->stack_handle) {
        rvalue_stack_eagerly_release(json->stack_handle);
    }

    if (cs >= JSON_first_final && p == pe) {
        return result;
    } else {
        raise_parse_error("unexpected token at '%s'", p);
        return Qnil;
    }
}

static void JSON_mark(void *ptr)
{
    JSON_Parser *json = ptr;
    rb_gc_mark(json->Vsource);
    rb_gc_mark(json->create_id);
    rb_gc_mark(json->object_class);
    rb_gc_mark(json->array_class);
    rb_gc_mark(json->decimal_class);
    rb_gc_mark(json->match_string);
    rb_gc_mark(json->stack_handle);

    long index;
    for (index = 0; index < json->name_cache.length; index++) {
        rb_gc_mark(json->name_cache.entries[index]);
    }
}

static void JSON_free(void *ptr)
{
    JSON_Parser *json = ptr;
    fbuffer_free(&json->fbuffer);
    ruby_xfree(json);
}

static size_t JSON_memsize(const void *ptr)
{
    const JSON_Parser *json = ptr;
    return sizeof(*json) + FBUFFER_CAPA(&json->fbuffer);
}

static const rb_data_type_t JSON_Parser_type = {
    "JSON/Parser",
    {JSON_mark, JSON_free, JSON_memsize,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cJSON_parser_s_allocate(VALUE klass)
{
    JSON_Parser *json;
    VALUE obj = TypedData_Make_Struct(klass, JSON_Parser, &JSON_Parser_type, json);
    fbuffer_stack_init(&json->fbuffer, 0, NULL, 0);
    return obj;
}

/*
 * call-seq: source()
 *
 * Returns a copy of the current _source_ string, that was used to construct
 * this Parser.
 */
static VALUE cParser_source(VALUE self)
{
    GET_PARSER;
    return rb_str_dup(json->Vsource);
}

void Init_parser(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

#undef rb_intern
    rb_require("json/common");
    mJSON = rb_define_module("JSON");
    mExt = rb_define_module_under(mJSON, "Ext");
    cParser = rb_define_class_under(mExt, "Parser", rb_cObject);
    eNestingError = rb_path2class("JSON::NestingError");
    rb_gc_register_mark_object(eNestingError);
    rb_define_alloc_func(cParser, cJSON_parser_s_allocate);
    rb_define_method(cParser, "initialize", cParser_initialize, -1);
    rb_define_method(cParser, "parse", cParser_parse, 0);
    rb_define_method(cParser, "source", cParser_source, 0);

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
    sym_symbolize_names = ID2SYM(rb_intern("symbolize_names"));
    sym_freeze = ID2SYM(rb_intern("freeze"));
    sym_create_additions = ID2SYM(rb_intern("create_additions"));
    sym_create_id = ID2SYM(rb_intern("create_id"));
    sym_object_class = ID2SYM(rb_intern("object_class"));
    sym_array_class = ID2SYM(rb_intern("array_class"));
    sym_decimal_class = ID2SYM(rb_intern("decimal_class"));
    sym_match_string = ID2SYM(rb_intern("match_string"));

    i_create_id = rb_intern("create_id");
    i_json_creatable_p = rb_intern("json_creatable?");
    i_json_create = rb_intern("json_create");
    i_chr = rb_intern("chr");
    i_match = rb_intern("match");
    i_deep_const_get = rb_intern("deep_const_get");
    i_aset = rb_intern("[]=");
    i_aref = rb_intern("[]");
    i_leftshift = rb_intern("<<");
    i_new = rb_intern("new");
    i_try_convert = rb_intern("try_convert");
    i_uminus = rb_intern("-@");
    i_encode = rb_intern("encode");

    binary_encindex = rb_ascii8bit_encindex();
    utf8_encindex = rb_utf8_encindex();
    enc_utf8 = rb_utf8_encoding();
}

/*
 * Local variables:
 * mode: c
 * c-file-style: ruby
 * indent-tabs-mode: nil
 * End:
 */
