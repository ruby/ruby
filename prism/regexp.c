#include "prism/internal/regexp.h"

#include "prism/compiler/align.h"
#include "prism/compiler/inline.h"
#include "prism/compiler/fallthrough.h"
#include "prism/internal/arena.h"
#include "prism/internal/assert.h"
#include "prism/internal/buffer.h"
#include "prism/internal/char.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/memchr.h"
#include "prism/internal/memequal.h"
#include "prism/internal/node.h"
#include "prism/internal/options.h"
#include "prism/internal/parser.h"
#include "prism/internal/stringy.h"
#include "prism/internal/strncasecmp.h"
#include "prism/internal/xxh3.h"

#include <string.h>

/** The maximum depth of nested groups allowed in a regular expression. */
#define PM_REGEXP_PARSE_DEPTH_MAX 4096

/**
 * Whether an ASCII byte is written as it is when a regular expression is
 * quoted. That is a printable character other than the slash.
 */
static PRISM_INLINE bool
pm_regexp_format_verbatim_p(uint8_t byte) {
    return byte >= 0x20 && byte < 0x7F && byte != '/';
}

/**
 * Whether the content of a regular expression can be quoted as it is. That is
 * when every ASCII character is written as it is and every other character is
 * valid UTF-8, since messages are in UTF-8.
 */
static bool
pm_regexp_format_verbatim_content_p(const pm_encoding_t *encoding, const uint8_t *cursor, const uint8_t *end) {
    while (cursor < end) {
        if (*cursor < 0x80) {
            if (!pm_regexp_format_verbatim_p(*cursor)) return false;
            cursor++;
        } else {
            if (encoding != PM_ENCODING_UTF_8_ENTRY) return false;

            size_t width = pm_encoding_char_width(encoding, cursor, end - cursor);
            if (width == 0) return false;
            cursor += width;
        }
    }

    return true;
}

/**
 * Write the content of a regular expression the way Ruby quotes it in an
 * error. Content that can be quoted as it is gets written unchanged. Otherwise
 * each character is written like this:
 *
 * - a backslash and the character after it, unchanged, as in \n;
 * - a slash as \/;
 * - printable ASCII and whitespace, unchanged;
 * - other ASCII as \xHH, as in \x01;
 * - a byte that is not part of a valid character as \xHH;
 * - a UTF-8 or CESU-8 character as \uHHHH, or \u{HHHHH} past U+FFFF;
 * - any other character as \xHH, or as \x{HHHH} with all of its bytes.
 */
static void
pm_regexp_format_for_error(pm_buffer_t *buffer, const pm_encoding_t *encoding, const uint8_t *source, size_t length) {
    const uint8_t *cursor = source;
    const uint8_t *end = source + length;

    if (pm_regexp_format_verbatim_content_p(encoding, cursor, end)) {
        pm_buffer_append_string(buffer, (const char *) source, length);
        return;
    }

    while (cursor < end) {
        uint8_t byte = *cursor;

        if (byte == '\\' && cursor + 1 < end) {
            size_t width = pm_encoding_char_width(encoding, cursor + 1, end - cursor - 1);
            if (width == 0) width = 1;

            pm_buffer_append_string(buffer, (const char *) cursor, width + 1);
            cursor += width + 1;
        } else if (byte >= 0x80) {
            size_t width = pm_encoding_char_width(encoding, cursor, end - cursor);

            if (width == 0) {
                pm_buffer_append_byte_escape(buffer, byte);
                cursor++;
                continue;
            }

            int32_t codepoint = pm_encoding_unicode_codepoint(encoding, cursor, width);
            if (codepoint >= 0x10000) {
                PM_BUFFER_APPEND_LITERAL(buffer, "\\u{");
                pm_buffer_append_hexadecimal(buffer, (uint32_t) codepoint, 0);
                pm_buffer_append_byte(buffer, '}');
            } else if (codepoint >= 0) {
                PM_BUFFER_APPEND_LITERAL(buffer, "\\u");
                pm_buffer_append_hexadecimal(buffer, (uint32_t) codepoint, 4);
            } else if (width == 1) {
                pm_buffer_append_byte_escape(buffer, byte);
            } else {
                pm_buffer_append_string(buffer, "\\x{", 3);
                for (size_t index = 0; index < width; index++) pm_buffer_append_hexadecimal(buffer, cursor[index], 2);
                pm_buffer_append_byte(buffer, '}');
            }

            cursor += width;
        } else if (byte == '/') {
            pm_buffer_append_string(buffer, "\\/", 2);
            cursor++;
        } else if (pm_regexp_format_verbatim_p(byte) || pm_char_is_whitespace(byte)) {
            pm_buffer_append_byte(buffer, byte);
            cursor++;
        } else {
            pm_buffer_append_byte_escape(buffer, byte);
            cursor++;
        }
    }
}

/**
 * A regular expression as it is validated: its content, its options, and the
 * place in the source of the errors that are about it as a whole.
 */
typedef struct {
    /** The parser that the regular expression is in. */
    pm_parser_t *parser;

    /**
     * The content, in which the lexer keeps the escapes that the regular
     * expression engine reads as their text.
     */
    const uint8_t *source;

    /** The length of the content. */
    size_t size;

    /**
     * The encoding that the content is in. This is the source encoding,
     * except for content joined from strings in another encoding.
     */
    const pm_encoding_t *encoding;

    /** The flags of the regular expression, which hold its options. */
    pm_node_flags_t flags;

    /** Where errors about the regular expression as a whole are reported. */
    pm_location_t location;

    /**
     * Whether the content holds characters that the lexer did not check, as
     * the values of strings joined into it do, so that an invalid character is
     * an error once its escapes are read rather than one that was reported
     * where it was lexed.
     */
    bool unlexed;
} pm_regexp_t;

/**
 * Write the option letters shown after a quoted regular expression in a
 * diagnostic and return the number written. Ruby shows m, i, and x in that
 * order and omits encoding options.
 */
static size_t
pm_regexp_option_letters(pm_node_flags_t flags, char letters[3]) {
    size_t index = 0;
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE) letters[index++] = 'm';
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE) letters[index++] = 'i';
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_EXTENDED) letters[index++] = 'x';
    return index;
}

/**
 * The name of a named group, in the pattern.
 */
typedef struct {
    /** The start of the name. */
    const uint8_t *start;

    /** The length of the name. */
    size_t length;
} pm_regexp_name_t;

/** A name's binding, with a one-based index into the capture list. */
typedef struct {
    uint64_t hash;
    uint32_t capture;
    uint32_t count;
} pm_regexp_name_binding_t;

/**
 * A list of the names of named groups.
 */
typedef struct {
    /** The names, which the list owns in the scratch arena. */
    pm_regexp_name_t *values;

    /** The number of names in the list. */
    size_t size;

    /** The number of names the list has room for. */
    size_t capacity;

    /** Bindings built when a reference needs to search a larger list. */
    pm_regexp_name_binding_t *bindings;

    /** The number of distinct names in the bindings. */
    size_t bindings_size;

    /** The number of slots in the bindings, always a power of two when used. */
    size_t bindings_capacity;
} pm_regexp_names_t;

/**
 * The kinds of references to groups that are checked once the whole pattern is
 * parsed, as the regular expression engine checks them when it compiles it.
 */
typedef enum {
    /** A backreference by number, as in \1 or \k<1>. */
    PM_REGEXP_DEFERRED_NUMBER,

    /** A condition by number, as in (?(1)a). */
    PM_REGEXP_DEFERRED_CONDITION_NUMBER,

    /**
     * A condition with a number in the form of a name, as in (?(<1>)a), which
     * the engine treats as a reference by name, so it may be used alongside
     * named groups.
     */
    PM_REGEXP_DEFERRED_NAMED_NUMBER,

    /** A call by number, as in \g<1>. */
    PM_REGEXP_DEFERRED_CALL_NUMBER,

    /** A call by name, as in \g<n>. */
    PM_REGEXP_DEFERRED_CALL_NAME
} pm_regexp_deferred_type_t;

/**
 * A reference to a group that is checked once the whole pattern is parsed.
 */
typedef struct {
    /** The kind of reference. */
    pm_regexp_deferred_type_t type;

    /** The start of the reference as it is written. */
    const uint8_t *start;

    /** The end of the reference as it is written. */
    const uint8_t *end;

    /** The number of the group, for a reference by number. */
    int64_t number;
} pm_regexp_deferred_t;

/**
 * A list of the references to groups that are checked once the whole pattern
 * is parsed.
 */
typedef struct {
    /** The references, which the list owns in the scratch arena. */
    pm_regexp_deferred_t *values;

    /** The number of references in the list. */
    size_t size;

    /** The number of references the list has room for. */
    size_t capacity;
} pm_regexp_deferreds_t;

/**
 * This is the parser that is going to handle parsing regular expressions.
 */
typedef struct {
    /** The parser that is currently being used. */
    pm_parser_t *parser;

    /** The regular expression that is being validated, which errors quote. */
    const pm_regexp_t *regexp;

    /** A pointer to the start of the pattern that we are parsing. */
    const uint8_t *start;

    /** A pointer to the current position in the pattern. */
    const uint8_t *cursor;

    /** A pointer to the end of the pattern that we are parsing. */
    const uint8_t *end;

    /**
     * Where the pattern stops lining up with the content, or NULL if it is the
     * content itself.
     */
    const pm_regexp_offsets_t *pattern_offsets;

    /**
     * Where the content stops lining up with the source, for reporting errors
     * at their place in the source. NULL when the content does not line up with
     * the source at all, as when it is joined from several parts, in which case
     * errors are reported at the location of the whole regular expression.
     */
    const pm_regexp_offsets_t *offsets;

    /** The offset in the source of the start of the content. */
    uint32_t source_start;

    /** The location of the whole regular expression. */
    pm_location_t location;

    /** The encoding of the source. */
    const pm_encoding_t *encoding;

    /**
     * Pointer to the first non-POSIX property name (for /n error messages).
     * POSIX properties (Alnum, Alpha, etc.) work in all encodings.
     * Script properties (Hiragana, Katakana, etc.) work in /e, /s, /u.
     * Unicode-only properties (L, Ll, etc.) work only in /u.
     */
    const uint8_t *property_name;

    /** Length of the first non-POSIX property name found. */
    size_t property_name_length;

    /**
     * Pointer to the first Unicode-only property name (for /e, /s error
     * messages). NULL if only POSIX or script properties have been seen.
     */
    const uint8_t *unicode_property_name;

    /** Length of the first Unicode-only property name found. */
    size_t unicode_property_name_length;

    /**
     * Whether or not the regular expression currently being parsed is in
     * extended mode, wherein whitespace is ignored and comments are allowed.
     */
    bool extended_mode;

    /** Whether the encoding has changed from the default. */
    bool encoding_changed;

    /** Number of syntax diagnostics that have quoted the complete pattern. */
    uint8_t quoted_errors;

    /**
     * The number of capturing groups opened so far, plain and named. A group
     * counts from its (, before its body, as in the regular expression engine.
     */
    uint32_t groups;

    /**
     * The names of the named groups opened so far, for the references that
     * need a name to be defined already.
     */
    pm_regexp_names_t names;

    /**
     * The references to groups that are checked once the whole pattern is
     * parsed.
     */
    pm_regexp_deferreds_t deferreds;
} pm_regexp_parser_t;

/** Find the binding for a name, or its empty slot. */
static pm_regexp_name_binding_t *
pm_regexp_name_binding(const pm_regexp_names_t *names, pm_regexp_name_t name, uint64_t hash) {
    size_t mask = names->bindings_capacity - 1;
    size_t index = (size_t) hash & mask;

    while (names->bindings[index].capture != 0) {
        pm_regexp_name_binding_t *binding = &names->bindings[index];
        const pm_regexp_name_t *capture = &names->values[binding->capture - 1];
        if (binding->hash == hash && capture->length == name.length && pm_memequal(capture->start, name.start, name.length)) return binding;
        index = (index + 1) & mask;
    }

    return &names->bindings[index];
}

/** Update a name's binding when another capture with that name is opened. */
static void
pm_regexp_name_bind(pm_arena_t *arena, pm_regexp_names_t *names, size_t capture) {
    const pm_regexp_name_binding_t *previous = names->bindings;
    if (previous == NULL || names->bindings_size >= names->bindings_capacity / 4 * 3) {
        size_t capacity = previous == NULL ? 16 : names->bindings_capacity * 2;
        size_t mask = capacity - 1;
        pm_regexp_name_binding_t *bindings = PM_ARENA_ZALLOC_ARRAY(arena, pm_regexp_name_binding_t, capacity);

        if (previous != NULL) {
            for (size_t index = 0; index < names->bindings_capacity; index++) {
                pm_regexp_name_binding_t binding = previous[index];
                if (binding.capture == 0) continue;

                size_t slot = (size_t) binding.hash & mask;
                while (bindings[slot].capture != 0) slot = (slot + 1) & mask;
                bindings[slot] = binding;
            }
        }

        names->bindings = bindings;
        names->bindings_capacity = capacity;
    }

    pm_regexp_name_t name = names->values[capture];
    uint64_t hash = pm_xxh3(name.start, name.length);
    pm_regexp_name_binding_t *binding = pm_regexp_name_binding(names, name, hash);
    if (binding->capture == 0) {
        binding->hash = hash;
        binding->capture = (uint32_t) (capture + 1);
        names->bindings_size++;
    }
    binding->count++;
}

/**
 * Append a name to the names of the named groups opened so far, growing the
 * list in the scratch arena.
 */
static void
pm_regexp_names_append(pm_regexp_parser_t *parser, pm_regexp_name_t name) {
    pm_regexp_names_t *names = &parser->names;

    if (names->size == names->capacity) {
        size_t capacity = names->capacity == 0 ? 4 : names->capacity * 2;
        pm_regexp_name_t *values = (pm_regexp_name_t *) pm_arena_alloc(&parser->parser->scratch_arena, capacity * sizeof(pm_regexp_name_t), PRISM_ALIGNOF(pm_regexp_name_t));

        if (names->size > 0) memcpy(values, names->values, names->size * sizeof(pm_regexp_name_t));
        names->values = values;
        names->capacity = capacity;
    }

    names->values[names->size++] = name;
    if (names->bindings != NULL) pm_regexp_name_bind(&parser->parser->scratch_arena, names, names->size - 1);
}

/**
 * Keep a reference to a group to check once the whole pattern is parsed,
 * growing the list in the scratch arena.
 */
static void
pm_regexp_defer(pm_regexp_parser_t *parser, pm_regexp_deferred_type_t type, const uint8_t *start, const uint8_t *end, int64_t number) {
    pm_regexp_deferreds_t *deferreds = &parser->deferreds;

    if (deferreds->size == deferreds->capacity) {
        size_t capacity = deferreds->capacity == 0 ? 4 : deferreds->capacity * 2;
        pm_regexp_deferred_t *values = (pm_regexp_deferred_t *) pm_arena_alloc(&parser->parser->scratch_arena, capacity * sizeof(pm_regexp_deferred_t), PRISM_ALIGNOF(pm_regexp_deferred_t));

        if (deferreds->size > 0) memcpy(values, deferreds->values, deferreds->size * sizeof(pm_regexp_deferred_t));
        deferreds->values = values;
        deferreds->capacity = capacity;
    }

    deferreds->values[deferreds->size++] = (pm_regexp_deferred_t) { .type = type, .start = start, .end = end, .number = number };
}

/**
 * Append a place to a list of places, growing the list in the scratch arena.
 */
void
pm_regexp_offsets_append(pm_parser_t *parser, pm_regexp_offsets_t *offsets, pm_regexp_offset_t offset) {
    pm_regexp_offset_t *values = offsets->values;
    if (values == NULL || offsets->size == offsets->capacity) {
        size_t capacity = values == NULL ? 4 : offsets->capacity * 2;
        pm_regexp_offset_t *grown = PM_ARENA_ALLOC_ARRAY(&parser->scratch_arena, pm_regexp_offset_t, capacity);

        if (values != NULL) memcpy(grown, values, offsets->size * sizeof(pm_regexp_offset_t));
        offsets->values = grown;
        offsets->capacity = capacity;
        values = grown;
    }

    values[offsets->size++] = offset;
}

/**
 * Map an offset in the content to an offset in the source, through the places
 * where the two stop lining up. The base is the offset in the source of the
 * start of the content.
 *
 * Each byte after a place is at the same distance from it in the source as in
 * the content. A byte in text written in place of an escape maps to somewhere
 * within that escape. The start flag says whether the offset starts a range or
 * ends one. At a place, the escape before it wrote nothing at that offset, so
 * a range that starts there starts at the escape, and one that ends there ends
 * after it.
 */
static uint32_t
pm_regexp_offsets_map(const pm_regexp_offsets_t *offsets, uint32_t base, uint32_t content, bool start) {
    const pm_regexp_offset_t *values = offsets->values;
    size_t size = offsets->size;

    /* Find the number of places at or before the position. */
    size_t low = 0;
    size_t high = size;

    while (low < high) {
        size_t middle = low + (high - low) / 2;

        if (values[middle].content <= content) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }

    /* The place that the position is measured from, which for the start of a
     * range at a recorded place is the one before it. */
    size_t from = low;
    if (start && from > 0 && values[from - 1].content == content) from--;

    uint32_t source = (from == 0) ? (base + content) : (values[from - 1].source + (content - values[from - 1].content));
    if (from < size && source > values[from].source) source = values[from].source;

    return source;
}

/**
 * Return the offset in the source of the given position in the pattern, as the
 * start (or else the end) of a range. The pattern maps to the content first,
 * and the content then maps to the source.
 *
 * In the pattern, text written in place of an escape lines up with the escape
 * at both ends, so it maps the same way whether it starts or ends a range.
 */
static uint32_t
pm_regexp_source_offset(const pm_regexp_parser_t *parser, const uint8_t *position, bool start) {
    if (parser->offsets == NULL) {
        return start ? parser->location.start : (parser->location.start + parser->location.length);
    }

    uint32_t content = (uint32_t) (position - parser->start);
    if (parser->pattern_offsets != NULL) content = pm_regexp_offsets_map(parser->pattern_offsets, 0, content, false);

    return pm_regexp_offsets_map(parser->offsets, parser->source_start, content, start);
}

/** Report a message followed by the quoted regular expression and its options. */
static void
pm_regexp_error_with_content(const pm_regexp_t *regexp, uint32_t start, uint32_t length, const char *message, size_t message_length) {
    pm_parser_t *parser = regexp->parser;

    char letters[3];
    size_t letters_length = pm_regexp_option_letters(regexp->flags, letters);

    pm_buffer_t buffer = { 0 };
    pm_buffer_append_string(&buffer, message, message_length);
    pm_buffer_append_string(&buffer, ": /", 3);
    pm_regexp_format_for_error(&buffer, regexp->encoding, regexp->source, regexp->size);
    pm_buffer_append_byte(&buffer, '/');
    pm_buffer_append_string(&buffer, letters, letters_length);

    pm_diagnostic_list_append_slice(
        &parser->metadata_arena,
        &parser->error_list,
        start,
        length,
        PM_ERR_REGEXP_PARSE_ERROR,
        pm_diagnostic_slice(pm_buffer_value(&buffer), buffer.length)
    );
    pm_buffer_cleanup(&buffer);
}

/**
 * Append a syntax error to the parser's error list, at the place in the source
 * of the given range of the content. The first eight messages are followed by
 * the quoted regular expression and its options, as in "unmatched close
 * parenthesis: /a)/i".
 */
static void
pm_regexp_parse_error(pm_regexp_parser_t *regexp_parser, const uint8_t *start, const uint8_t *end, const char *message, size_t message_length) {
    pm_parser_t *parser = regexp_parser->parser;
    const pm_regexp_t *regexp = regexp_parser->regexp;

    uint32_t source_start = pm_regexp_source_offset(regexp_parser, start, true);
    uint32_t source_end = pm_regexp_source_offset(regexp_parser, end, false);

    /* Recovery can report an error for every byte of the pattern. Limit how
     * many diagnostics copy it so the total message size remains linear. */
    if (regexp_parser->quoted_errors == 8) {
        pm_diagnostic_list_append_slice(
            &parser->metadata_arena,
            &parser->error_list,
            source_start,
            source_end - source_start,
            PM_ERR_REGEXP_PARSE_ERROR,
            (pm_string_t) { .source = (const uint8_t *) message, .length = message_length }
        );
    } else {
        regexp_parser->quoted_errors++;
        pm_regexp_error_with_content(regexp, source_start, source_end - source_start, message, message_length);
    }
}

/* Report a literal message using its compile-time length. */
#define PM_REGEXP_PARSE_ERROR(parser_, start_, end_, message_) \
    pm_regexp_parse_error((parser_), (start_), (end_), "" message_, sizeof(message_) - 1)

/** The text around a name quoted in a regular expression error. */
typedef struct {
    const char *before;
    const char *after;
    uint8_t before_length;
    uint8_t after_length;
} pm_regexp_quoted_error_t;

#define PM_REGEXP_QUOTED_ERROR(before_, after_) \
    { .before = "" before_, .after = "" after_, .before_length = sizeof(before_) - 1, .after_length = sizeof(after_) - 1 }

static const pm_regexp_quoted_error_t pm_regexp_invalid_property_name = PM_REGEXP_QUOTED_ERROR("invalid character property name {", "}");
static const pm_regexp_quoted_error_t pm_regexp_invalid_group_name = PM_REGEXP_QUOTED_ERROR("invalid group name <", ">");
static const pm_regexp_quoted_error_t pm_regexp_invalid_char_in_group_name = PM_REGEXP_QUOTED_ERROR("invalid char in group name <", ">");
static const pm_regexp_quoted_error_t pm_regexp_undefined_group = PM_REGEXP_QUOTED_ERROR("undefined group <", "> reference");
static const pm_regexp_quoted_error_t pm_regexp_undefined_name = PM_REGEXP_QUOTED_ERROR("undefined name <", "> reference");
static const pm_regexp_quoted_error_t pm_regexp_multiplex_name = PM_REGEXP_QUOTED_ERROR("multiplex definition name <", "> call");

#undef PM_REGEXP_QUOTED_ERROR

/**
 * Report an error that quotes a name, like "undefined group <2> reference".
 */
static void
pm_regexp_parse_quoted_error(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end, const pm_regexp_quoted_error_t *error) {
    pm_buffer_t buffer = { 0 };
    pm_buffer_append_string(&buffer, error->before, error->before_length);
    pm_buffer_append_bytes(&buffer, start, (size_t) (end - start));
    pm_buffer_append_string(&buffer, error->after, error->after_length);

    /* A NUL in the name ends the message before the quoted regexp is appended. */
    pm_string_t message = pm_diagnostic_slice(buffer.value, buffer.length);
    pm_regexp_parse_error(parser, start, end, buffer.value, message.length);
    pm_buffer_cleanup(&buffer);
}

/**
 * Report that the stack budget was used up while parsing the regular
 * expression.
 */
static void
pm_regexp_parse_stack_exhausted(pm_regexp_parser_t *regexp_parser) {
    uint32_t source_start = pm_regexp_source_offset(regexp_parser, regexp_parser->start, true);
    uint32_t source_end = pm_regexp_source_offset(regexp_parser, regexp_parser->end, false);
    pm_parser_err_stack_exhausted(regexp_parser->parser, source_start, source_end - source_start);
}

/**
 * Returns true if the next character is the end of the source.
 */
static PRISM_INLINE bool
pm_regexp_char_is_eof(pm_regexp_parser_t *parser) {
    return parser->cursor >= parser->end;
}

/**
 * Optionally accept a char and consume it if it exists.
 */
static PRISM_INLINE bool
pm_regexp_char_accept(pm_regexp_parser_t *parser, uint8_t value) {
    if (!pm_regexp_char_is_eof(parser) && *parser->cursor == value) {
        parser->cursor++;
        return true;
    }
    return false;
}

/**
 * Expect a character to be present and consume it.
 */
static PRISM_INLINE bool
pm_regexp_char_expect(pm_regexp_parser_t *parser, uint8_t value) {
    if (!pm_regexp_char_is_eof(parser) && *parser->cursor == value) {
        parser->cursor++;
        return true;
    }
    return false;
}

/**
 * Skip the whitespace that extended mode ignores outside of a character class:
 * a space, tab, newline, carriage return, or form feed. Each place that reads
 * the next part of the pattern skips it first, so in /( *)/x the * has nothing
 * to repeat.
 */
static PRISM_INLINE void
pm_regexp_skip_extended_whitespace(pm_regexp_parser_t *parser) {
    if (!parser->extended_mode) return;

    while (parser->cursor < parser->end) {
        switch (*parser->cursor) {
            case ' ':
            case '\t':
            case '\n':
            case '\r':
            case '\f':
                parser->cursor++;
                break;
            default:
                return;
        }
    }
}

/**
 * Advance past the character at the cursor, reading it whole in the encoding of
 * the regular expression. An invalid character, which the lexer has already
 * reported, is skipped a byte at a time.
 */
static void
pm_regexp_skip_char(pm_regexp_parser_t *parser) {
    ptrdiff_t remaining = parser->end - parser->cursor;
    size_t width = parser->encoding_changed ? pm_encoding_char_width(parser->encoding, parser->cursor, remaining) : pm_encoding_utf_8_char_width(parser->cursor, remaining);
    parser->cursor += (width == 0) ? 1 : width;
}

/**
 * Parse a hex digit character and return its value, or -1 if not a hex digit.
 */
static PRISM_INLINE int
pm_regexp_hex_digit_value(uint8_t byte) {
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
    return -1;
}

/**
 * Return the value of the digits at the cursor in the given base, reading at
 * most maximum of them, and set length to how many were read.
 */
static uint32_t
pm_regexp_scan_digits(const uint8_t *cursor, const uint8_t *end, uint32_t maximum, uint32_t base, uint32_t *length) {
    uint32_t value = 0;
    uint32_t index = 0;

    while (index < maximum && cursor + index < end) {
        int digit = pm_regexp_hex_digit_value(cursor[index]);
        if (digit < 0 || (uint32_t) digit >= base) break;

        value = value * base + (uint32_t) digit;
        index++;
    }

    *length = index;
    return value;
}

/**
 * Read the decimal digit at the cursor the way the regular expression engine
 * reads one, setting its width and value. Returns false if there is no digit.
 *
 * The engine reads each digit's value as its code point minus that of 0. That
 * is right for 0 through 9. In an encoding whose characters are Unicode code
 * points, other digits count too, with much bigger values, so even two
 * fullwidth digits make a number that is too big for an interval.
 */
static bool
pm_regexp_digit(const pm_regexp_parser_t *parser, const uint8_t *cursor, size_t *width, uint32_t *value) {
    if (pm_char_is_decimal_digit(*cursor)) {
        *width = 1;
        *value = (uint32_t) (*cursor - '0');
        return true;
    }

    if (*cursor < 0x80) return false;

    *width = pm_encoding_char_width(parser->encoding, cursor, (ptrdiff_t) (parser->end - cursor));
    if (*width == 0) return false;

    int32_t codepoint = pm_encoding_unicode_codepoint(parser->encoding, cursor, *width);
    if (codepoint < 0 || !pm_encoding_unicode_digit_p((uint32_t) codepoint, parser->parser->version)) return false;

    *value = (uint32_t) codepoint - '0';
    return true;
}

/**
 * Add a digit to a number the way the regular expression engine does, which
 * gives up as soon as the number would overflow an int. Returns false then.
 */
static PRISM_INLINE bool
pm_regexp_number_append(uint32_t *number, uint32_t digit) {
    if ((INT32_MAX - digit) / 10 < *number) return false;
    *number = *number * 10 + digit;
    return true;
}

/** The largest bound of an interval, like the 3 in a{3}. */
#define PM_REGEXP_INTERVAL_MAXIMUM 100000

/**
 * Read the bound of an interval at the cursor, like the 3 in a{3}, and advance
 * the cursor past its digits. Returns false if the bound is too big.
 */
static bool
pm_regexp_parse_interval_bound(const pm_regexp_parser_t *parser, const uint8_t **cursor, uint32_t *bound) {
    uint32_t value = 0;

    while (*cursor < parser->end) {
        size_t width;
        uint32_t digit;

        if (!pm_regexp_digit(parser, *cursor, &width, &digit)) break;
        if (!pm_regexp_number_append(&value, digit)) return false;

        *cursor += width;
    }

    *bound = value;
    return value <= PM_REGEXP_INTERVAL_MAXIMUM;
}

/**
 * The results of reading an interval.
 */
typedef enum {
    /** The interval is invalid, which has been reported. */
    PM_REGEXP_INTERVAL_INVALID,

    /** The { does not start an interval, so it is a character. */
    PM_REGEXP_INTERVAL_NONE,

    /** The interval is valid, and the cursor is past it. */
    PM_REGEXP_INTERVAL_VALID
} pm_regexp_interval_t;

/**
 * Read an interval, like {3}, {3,}, {,5}, or {3,5}. The cursor is just past its
 * {. A bound that is too big is an error, even if the interval never closes. So
 * is an upper bound below the lower one. Anything else that is not an interval,
 * like {x} or {,}, is not an error: its { is just a character.
 */
static pm_regexp_interval_t
pm_regexp_parse_interval(pm_regexp_parser_t *parser) {
    const uint8_t *start = parser->cursor - 1;
    const uint8_t *cursor = parser->cursor;
    const uint8_t *end = parser->end;

    uint32_t lower;
    if (!pm_regexp_parse_interval_bound(parser, &cursor, &lower)) {
        PM_REGEXP_PARSE_ERROR(parser, start, cursor, "too big number for repeat range");
        return PM_REGEXP_INTERVAL_INVALID;
    }

    bool has_lower = cursor != parser->cursor;
    bool has_upper = true;
    uint32_t upper = lower;

    if (cursor < end && *cursor == ',') {
        const uint8_t *digits = ++cursor;
        if (!pm_regexp_parse_interval_bound(parser, &cursor, &upper)) {
            PM_REGEXP_PARSE_ERROR(parser, start, cursor, "too big number for repeat range");
            return PM_REGEXP_INTERVAL_INVALID;
        }

        /* {,} has neither bound. */
        if (cursor == digits) {
            if (!has_lower) return PM_REGEXP_INTERVAL_NONE;
            has_upper = false;
        }
    } else if (!has_lower) {
        return PM_REGEXP_INTERVAL_NONE;
    }

    if (cursor == end || *cursor != '}') return PM_REGEXP_INTERVAL_NONE;
    cursor++;

    if (has_upper && lower > upper) {
        PM_REGEXP_PARSE_ERROR(parser, start, cursor, "upper is smaller than lower in repeat range");
        return PM_REGEXP_INTERVAL_INVALID;
    }

    parser->cursor = cursor;
    return PM_REGEXP_INTERVAL_VALID;
}

/**
 * quantifier : star-quantifier
 *            | plus-quantifier
 *            | optional-quantifier
 *            | interval
 *            | <empty>
 *            ;
 */
static bool
pm_regexp_parse_quantifier(pm_regexp_parser_t *parser) {
    while (true) {
        pm_regexp_skip_extended_whitespace(parser);
        if (pm_regexp_char_is_eof(parser)) return true;

        switch (*parser->cursor) {
            case '*':
            case '+':
            case '?':
                parser->cursor++;
                break;
            case '{':
                parser->cursor++;
                switch (pm_regexp_parse_interval(parser)) {
                    case PM_REGEXP_INTERVAL_INVALID:
                        return false;
                    case PM_REGEXP_INTERVAL_NONE:
                        /* The { is a character, which starts the next item. */
                        parser->cursor--;
                        return true;
                    case PM_REGEXP_INTERVAL_VALID:
                        break;
                }
                break;
            default:
                return true;
        }
    }
}

/**
 * Property escape classification. Onigmo supports three tiers of property
 * names depending on the encoding:
 *
 * - POSIX properties (Alnum, Alpha, ASCII, Blank, Cntrl, Digit, Graph, Lower,
 *   Print, Punct, Space, Upper, XDigit, Word): valid in all encodings.
 * - Script properties (Hiragana, Katakana, Han, Latin, Greek, Cyrillic): valid
 *   in EUC-JP (/e), Windows-31J (/s), and UTF-8 (/u), but not ASCII-8BIT (/n).
 * - Unicode-only properties (general categories like L, Ll, Lu, etc., plus
 *   Any, Assigned): valid only in UTF-8 (/u).
 */
typedef enum {
    PM_REGEXP_PROPERTY_POSIX,
    PM_REGEXP_PROPERTY_SCRIPT,
    PM_REGEXP_PROPERTY_UNICODE
} pm_regexp_property_type_t;

/**
 * Classify a property name. The name may start with '^' for negation, which
 * is skipped before matching.
 */
static pm_regexp_property_type_t
pm_regexp_classify_property(const uint8_t *name, size_t length) {
    // Skip leading '^' for negated properties like \p{^Hiragana}.
    if (length > 0 && name[0] == '^') {
        name++;
        length--;
    }

#define PM_REGEXP_CASECMP(str_) (pm_strncasecmp(name, (const uint8_t *) (str_), length) == 0)

    switch (length) {
        case 3:
            if (PM_REGEXP_CASECMP("Han")) return PM_REGEXP_PROPERTY_SCRIPT;
            break;
        case 4:
            if (PM_REGEXP_CASECMP("Word")) return PM_REGEXP_PROPERTY_POSIX;
            break;
        case 5:
            /* Most properties are length 5, so dispatch on first character. */
            switch (name[0] | 0x20) {
                case 'a':
                    if (PM_REGEXP_CASECMP("Alnum")) return PM_REGEXP_PROPERTY_POSIX;
                    if (PM_REGEXP_CASECMP("Alpha")) return PM_REGEXP_PROPERTY_POSIX;
                    if (PM_REGEXP_CASECMP("ASCII")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 'b':
                    if (PM_REGEXP_CASECMP("Blank")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 'c':
                    if (PM_REGEXP_CASECMP("Cntrl")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 'd':
                    if (PM_REGEXP_CASECMP("Digit")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 'g':
                    if (PM_REGEXP_CASECMP("Graph")) return PM_REGEXP_PROPERTY_POSIX;
                    if (PM_REGEXP_CASECMP("Greek")) return PM_REGEXP_PROPERTY_SCRIPT;
                    break;
                case 'l':
                    if (PM_REGEXP_CASECMP("Lower")) return PM_REGEXP_PROPERTY_POSIX;
                    if (PM_REGEXP_CASECMP("Latin")) return PM_REGEXP_PROPERTY_SCRIPT;
                    break;
                case 'p':
                    if (PM_REGEXP_CASECMP("Print")) return PM_REGEXP_PROPERTY_POSIX;
                    if (PM_REGEXP_CASECMP("Punct")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 's':
                    if (PM_REGEXP_CASECMP("Space")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
                case 'u':
                    if (PM_REGEXP_CASECMP("Upper")) return PM_REGEXP_PROPERTY_POSIX;
                    break;
            }
            break;
        case 6:
            if (PM_REGEXP_CASECMP("XDigit")) return PM_REGEXP_PROPERTY_POSIX;
            break;
        case 8:
            if (PM_REGEXP_CASECMP("Hiragana")) return PM_REGEXP_PROPERTY_SCRIPT;
            if (PM_REGEXP_CASECMP("Katakana")) return PM_REGEXP_PROPERTY_SCRIPT;
            if (PM_REGEXP_CASECMP("Cyrillic")) return PM_REGEXP_PROPERTY_SCRIPT;
            break;
    }

#undef PM_REGEXP_CASECMP

    // Everything else is Unicode-only (general categories, other scripts, etc.).
    return PM_REGEXP_PROPERTY_UNICODE;
}

/**
 * Check for and skip a `\p{...}` or `\P{...}` Unicode property escape. The
 * cursor should be pointing at 'p' or 'P' when this is called. If a property
 * escape is found, record it on the regexp parser and advance past the closing
 * '}'.
 *
 * Properties are classified into three tiers (POSIX, script, Unicode-only) to
 * determine which encoding modifiers they are valid with.
 */
static bool
pm_regexp_parse_property_escape(pm_regexp_parser_t *parser) {
    PRISM_ASSERT(*parser->cursor == 'p' || *parser->cursor == 'P');

    if (parser->cursor + 1 >= parser->end || parser->cursor[1] != '{') {
        // Not a property escape, just skip the single character after '\'.
        parser->cursor++;
        return false;
    }

    /* Read the name the way Onigmo's fetch_char_property_to_ctype does: up to
     * a }, after the ^ that negates the property. A (, ), {, or | stops the
     * name, and so does the end of the pattern, after which the name is
     * quoted without the last character read. An empty name is no property. */
    parser->cursor += 2;
    if (parser->cursor < parser->end && *parser->cursor == '^') parser->cursor++;

    const uint8_t *name_start = parser->cursor;
    const uint8_t *previous = parser->cursor;

    while (parser->cursor < parser->end) {
        previous = parser->cursor;
        uint8_t byte = *parser->cursor;
        pm_regexp_skip_char(parser);

        if (byte == '}') {
            size_t name_length = (size_t) (previous - name_start);
            if (name_length == 0) break;

            pm_regexp_property_type_t type = pm_regexp_classify_property(name_start, name_length);

            // Track the first non-POSIX property name (for /n error messages).
            if (type >= PM_REGEXP_PROPERTY_SCRIPT && parser->property_name == NULL) {
                parser->property_name = name_start;
                parser->property_name_length = name_length;
            }

            // Track the first Unicode-only property name (for /e, /s error messages).
            if (type == PM_REGEXP_PROPERTY_UNICODE && parser->unicode_property_name == NULL) {
                parser->unicode_property_name = name_start;
                parser->unicode_property_name_length = name_length;
            }

            return true;
        }

        if (byte == '(' || byte == ')' || byte == '{' || byte == '|') break;
    }

    pm_regexp_parse_quoted_error(parser, name_start, previous, &pm_regexp_invalid_property_name);
    return true;
}

/**
 * Skip a \u escape, in either its \uHHHH or its \u{...} form. The cursor should
 * be pointing at the character after the 'u' when this is called. Its code
 * points were checked when the escapes of the content were read, before the
 * pattern is parsed, so this only finds where the escape ends.
 */
static void
pm_regexp_parse_unicode_escape(pm_regexp_parser_t *parser) {
    if (pm_regexp_char_accept(parser, '{')) {
        while (!pm_regexp_char_is_eof(parser) && *parser->cursor != '}') parser->cursor++;
        pm_regexp_char_accept(parser, '}');
    } else {
        for (int index = 0; index < 4 && !pm_regexp_char_is_eof(parser) && pm_char_is_hexadecimal_digit(*parser->cursor); index++) {
            parser->cursor++;
        }
    }
}

/**
 * Skip the digits of a \x escape, of which there are at most two. The cursor
 * should be pointing at the character after 'x'.
 */
static void
pm_regexp_parse_hex_escape(pm_regexp_parser_t *parser) {
    for (int index = 0; index < 2 && !pm_regexp_char_is_eof(parser) && pm_char_is_hexadecimal_digit(*parser->cursor); index++) {
        parser->cursor++;
    }
}

/**
 * A reference to a group, by its number or its name, as in \k<1>, \k<n>, \g<n>,
 * or the condition of (?(1)a|b).
 */
typedef struct {
    /** The start of the number or name as it is written. */
    const uint8_t *start;

    /** The end of the number or name as it is written. */
    const uint8_t *end;

    /**
     * The number of the group, which is negative when it counts back from the
     * reference, as in \k<-1>, or 0 when the group is named.
     */
    int32_t number;
} pm_regexp_reference_t;

/**
 * Whether the character at the cursor is a word character, for the messages
 * about the characters of a group number. Any character that is not ASCII
 * counts as one. That is exact for the encodings that are not Unicode, while in
 * UTF-8 a symbol that is not a word character gets the message of one.
 */
static bool
pm_regexp_word_char_p(const pm_regexp_parser_t *parser) {
    uint8_t byte = *parser->cursor;
    return byte >= 0x80 || pm_encoding_ascii_alnum_p(byte) || byte == '_';
}

/**
 * Read the number that the digits from start to end spell, the way the engine
 * reads them. Returns false if the number would overflow an int.
 */
static bool
pm_regexp_reference_number(const pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end, uint32_t *number) {
    *number = 0;

    while (start < end) {
        size_t width;
        uint32_t digit;
        if (!pm_regexp_digit(parser, start, &width, &digit)) break;
        if (!pm_regexp_number_append(number, digit)) return false;
        start += width;
    }

    return true;
}

/**
 * Parse a reference to a group by its number or its name, with the cursor after
 * the character that opens it, the way Onigmo's fetch_name reads a reference,
 * and consume the close character that ends it. This reads the group of a
 * call, as in \g<n>, and the number of the condition of a conditional group,
 * as in (?(1)a|b), whose close character is the ). A number must be all
 * digits, after an optional -, and must not be 0. Returns false after an
 * error.
 */
static bool
pm_regexp_parse_reference(pm_regexp_parser_t *parser, uint8_t close, pm_regexp_reference_t *reference) {
    const uint8_t *start = parser->cursor;

    if (parser->cursor >= parser->end || *parser->cursor == close) {
        PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "group name is empty");
        return false;
    }

    /* Whether the reference is a name, a number, or a - that no digit has
     * followed yet. */
    enum { NAME, NUMBER, SIGN } kind = NAME;
    const uint8_t *digits = start;

    size_t width;
    uint32_t digit;
    if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
        kind = NUMBER;
    } else if (*parser->cursor == '-') {
        kind = SIGN;
        digits = parser->cursor + 1;
    }

    pm_regexp_skip_char(parser);

    const uint8_t *name_end = parser->end;
    const pm_regexp_quoted_error_t *error = NULL;
    bool closed = false;

    while (parser->cursor < parser->end) {
        name_end = parser->cursor;
        uint8_t byte = *parser->cursor;

        if (byte == close || byte == ')') {
            pm_regexp_skip_char(parser);

            if (kind == SIGN) {
                error = &pm_regexp_invalid_group_name;
            } else {
                closed = (byte == close);
            }
            break;
        }

        if (kind != NAME) {
            if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
                kind = NUMBER;
                parser->cursor += width;
                continue;
            }

            error = pm_regexp_word_char_p(parser) ? &pm_regexp_invalid_group_name : &pm_regexp_invalid_char_in_group_name;
            pm_regexp_skip_char(parser);
            break;
        }

        pm_regexp_skip_char(parser);
    }

    if (error != NULL) {
        /* After an error, the engine still looks for the character that would
         * end the name, to quote the name up to it, or to the end of the
         * pattern when the name runs there. */
        while (parser->cursor < parser->end) {
            name_end = parser->cursor;
            uint8_t byte = *parser->cursor;
            pm_regexp_skip_char(parser);
            if (byte == close || byte == ')') break;
        }

        if (parser->cursor >= parser->end) name_end = parser->end;
        pm_regexp_parse_quoted_error(parser, start, name_end, error);
        return false;
    }

    if (!closed) {
        pm_regexp_parse_quoted_error(parser, start, parser->end, &pm_regexp_invalid_group_name);
        return false;
    }

    uint32_t number = 0;
    if (kind != NAME) {
        if (!pm_regexp_reference_number(parser, digits, name_end, &number)) {
            PM_REGEXP_PARSE_ERROR(parser, start, name_end, "too big number");
            return false;
        }

        if (number == 0) {
            pm_regexp_parse_quoted_error(parser, start, name_end, &pm_regexp_invalid_group_name);
            return false;
        }
    }

    reference->start = start;
    reference->end = name_end;
    reference->number = (kind == SIGN || *start == '-') ? -((int32_t) number) : (int32_t) number;
    return true;
}

/**
 * Parse a reference to a group by its number or its name, with the cursor after
 * the < or ' that opens it, the way Onigmo's fetch_name_with_level reads it,
 * and consume the close character that ends it. This reads the group of a
 * backreference, as in \k<n>, and the name of the condition of a conditional
 * group, as in (?(<n>)a|b). A reference can end with a level of recursion, as
 * in \k<n+1>. Returns false after an error.
 */
static bool
pm_regexp_parse_reference_with_level(pm_regexp_parser_t *parser, uint8_t close, pm_regexp_reference_t *reference) {
    const uint8_t *start = parser->cursor;

    if (parser->cursor >= parser->end || *parser->cursor == close) {
        PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "group name is empty");
        return false;
    }

    /* Whether the reference is a name, a number, or a - that no digit has
     * followed yet. */
    enum { NAME, NUMBER, SIGN } kind = NAME;
    const uint8_t *digits = start;

    size_t width;
    uint32_t digit;
    if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
        kind = NUMBER;
    } else if (*parser->cursor == '-') {
        kind = SIGN;
        digits = parser->cursor + 1;
    }

    bool negative = (kind == SIGN);
    pm_regexp_skip_char(parser);

    const uint8_t *name_end = parser->end;
    const pm_regexp_quoted_error_t *error = NULL;
    uint8_t terminator = 0;

    while (parser->cursor < parser->end) {
        name_end = parser->cursor;
        uint8_t byte = *parser->cursor;

        if (byte == close || byte == ')' || byte == '+' || byte == '-') {
            pm_regexp_skip_char(parser);
            terminator = byte;
            if (kind == SIGN) error = &pm_regexp_invalid_group_name;
            break;
        }

        if (kind != NAME) {
            if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
                kind = NUMBER;
                parser->cursor += width;
                continue;
            }

            /* The rest of the name is still read, as a name. */
            error = &pm_regexp_invalid_group_name;
            kind = NAME;
        }

        pm_regexp_skip_char(parser);
    }

    if (error == NULL && terminator != close) {
        bool valid = false;

        if (terminator == '+' || terminator == '-') {
            if (parser->cursor >= parser->end) {
                pm_regexp_parse_quoted_error(parser, start, name_end, &pm_regexp_invalid_char_in_group_name);
                return false;
            }

            if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
                uint32_t level = 0;

                while (parser->cursor < parser->end && pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
                    if (!pm_regexp_number_append(&level, digit)) {
                        PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "too big number");
                        return false;
                    }
                    parser->cursor += width;
                }

                if (parser->cursor < parser->end) {
                    uint8_t byte = *parser->cursor;
                    pm_regexp_skip_char(parser);
                    valid = (byte == close);
                }
            }
        }

        if (!valid) {
            pm_regexp_parse_quoted_error(parser, start, parser->end, &pm_regexp_invalid_group_name);
            return false;
        }
    }

    if (error != NULL) {
        pm_regexp_parse_quoted_error(parser, start, name_end, error);
        return false;
    }

    uint32_t number = 0;
    if (kind == NUMBER) {
        if (!pm_regexp_reference_number(parser, digits, name_end, &number)) {
            PM_REGEXP_PARSE_ERROR(parser, start, name_end, "too big number");
            return false;
        }

        if (number == 0) {
            pm_regexp_parse_quoted_error(parser, start, parser->end, &pm_regexp_invalid_group_name);
            return false;
        }
    }

    reference->start = start;
    reference->end = name_end;
    reference->number = negative ? -((int32_t) number) : (int32_t) number;
    return true;
}

/**
 * Count the groups with this name that have been opened so far.
 */
static size_t
pm_regexp_name_count(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    pm_regexp_names_t *names = &parser->names;
    size_t length = (size_t) (end - start);

    /* Small capture lists are cheaper to scan than to index. */
    if (names->size < 8) {
        size_t count = 0;
        for (size_t index = 0; index < names->size; index++) {
            const pm_regexp_name_t *name = &names->values[index];
            if (name->length == length && pm_memequal(name->start, start, length)) count++;
        }
        return count;
    }

    if (names->bindings == NULL) {
        pm_arena_t *arena = &parser->parser->scratch_arena;
        for (size_t index = 0; index < names->size; index++) {
            pm_regexp_name_bind(arena, names, index);
        }
    }

    pm_regexp_name_t name = { .start = start, .length = length };
    return pm_regexp_name_binding(names, name, pm_xxh3(start, length))->count;
}

/**
 * Check a reference that the engine resolves while it parses, against the
 * groups opened so far. A name must already be defined, as in (?<n>a)\k<n>,
 * and a number that counts back, as in (a)\k<-1>, must land on a group. A
 * number that counts forward is checked once the pattern is parsed. Returns
 * false after an error.
 */
static bool
pm_regexp_check_reference(pm_regexp_parser_t *parser, const pm_regexp_reference_t *reference) {
    if (reference->number == 0) {
        if (pm_regexp_name_count(parser, reference->start, reference->end) > 0) return true;

        pm_regexp_parse_quoted_error(parser, reference->start, reference->end, &pm_regexp_undefined_name);
        return false;
    }

    if (reference->number < 0 && (int64_t) parser->groups + 1 + reference->number <= 0) {
        PM_REGEXP_PARSE_ERROR(parser, reference->start, reference->end, "invalid backref number/name");
        return false;
    }

    return true;
}

/**
 * Check a call of a group that counts, as in \g<-1> or \g<+1>, against the
 * groups opened so far, the way the engine does while it parses. A call that
 * counts back must land on a group. Returns false after an error.
 */
static bool
pm_regexp_check_relative_call(pm_regexp_parser_t *parser, const pm_regexp_reference_t *reference, bool forward) {
    if (reference->number >= 0 && !forward) return true;

    int64_t number = reference->number > 0 ? reference->number - 1 : reference->number;
    if ((int64_t) parser->groups + 1 + number > 0) return true;

    PM_REGEXP_PARSE_ERROR(parser, reference->start, reference->end, "invalid backref number/name");
    return false;
}

/**
 * Keep a backreference or condition by number to check once the whole pattern
 * is parsed. One that counts back, as in \k<-1>, is to the group that many
 * before the groups opened so far. A reference by name was already checked.
 */
static void
pm_regexp_defer_reference(pm_regexp_parser_t *parser, const pm_regexp_reference_t *reference, pm_regexp_deferred_type_t type) {
    if (reference->number == 0) return;

    int64_t number = reference->number;
    if (number < 0) number += (int64_t) parser->groups + 1;
    pm_regexp_defer(parser, type, reference->start, reference->end, number);
}

/**
 * Check the references to groups that wait for the end of the pattern, the way
 * the engine checks them when it compiles the pattern. Numbered references
 * and calls are restricted when named groups are present, and numbers must
 * refer to existing groups. A call by name must name exactly one group.
 */
static void
pm_regexp_check_deferreds(pm_regexp_parser_t *parser) {
    bool named = parser->names.size > 0;

    for (size_t index = 0; index < parser->deferreds.size; index++) {
        const pm_regexp_deferred_t *deferred = &parser->deferreds.values[index];

        switch (deferred->type) {
            case PM_REGEXP_DEFERRED_NUMBER:
            case PM_REGEXP_DEFERRED_CONDITION_NUMBER: {
                bool out_of_range = deferred->number > (int64_t) parser->groups;
                /* With both named and unnamed captures, Onigmo checks
                 * condition bounds while renumbering the groups, before
                 * rejecting numbered conditions. */
                bool remap_error = deferred->type == PM_REGEXP_DEFERRED_CONDITION_NUMBER &&
                    parser->groups > parser->names.size && out_of_range;
                if (named && !remap_error) {
                    PM_REGEXP_PARSE_ERROR(parser, deferred->start, deferred->end, "numbered backref/call is not allowed. (use name)");
                } else if (out_of_range) {
                    PM_REGEXP_PARSE_ERROR(parser, deferred->start, deferred->end, "invalid backref number/name");
                }
                break;
            }
            case PM_REGEXP_DEFERRED_NAMED_NUMBER:
                if (deferred->number > (int64_t) parser->groups) {
                    PM_REGEXP_PARSE_ERROR(parser, deferred->start, deferred->end, "invalid backref number/name");
                }
                break;
            case PM_REGEXP_DEFERRED_CALL_NUMBER:
                if (named) {
                    PM_REGEXP_PARSE_ERROR(parser, deferred->start, deferred->end, "numbered backref/call is not allowed. (use name)");
                } else if (deferred->number > (int64_t) parser->groups) {
                    pm_regexp_parse_quoted_error(parser, deferred->start, deferred->end, &pm_regexp_undefined_group);
                }
                break;
            case PM_REGEXP_DEFERRED_CALL_NAME: {
                size_t count = pm_regexp_name_count(parser, deferred->start, deferred->end);

                if (count == 0) {
                    pm_regexp_parse_quoted_error(parser, deferred->start, deferred->end, &pm_regexp_undefined_name);
                } else if (count > 1) {
                    pm_regexp_parse_quoted_error(parser, deferred->start, deferred->end, &pm_regexp_multiplex_name);
                }
                break;
            }
        }
    }
}

/** The largest number of a backreference written as a backslash and digits. */
#define PM_REGEXP_BACKREF_MAXIMUM 1000

/**
 * Parse a backslash followed by a digit from 1 to 9, with the cursor on the
 * digit, the way Onigmo's fetch_token reads it. The digits are a backreference
 * when their number is at most 9 or at most the number of groups opened so
 * far, as in (a)\1. Otherwise an 8 or 9 is that character, and other digits
 * start an octal escape of up to three digits.
 */
static void
pm_regexp_parse_numbered_backref(pm_regexp_parser_t *parser) {
    const uint8_t *start = parser->cursor;
    uint32_t number = 0;
    bool too_big = false;

    while (parser->cursor < parser->end) {
        size_t width;
        uint32_t digit;
        if (!pm_regexp_digit(parser, parser->cursor, &width, &digit)) break;
        if (!pm_regexp_number_append(&number, digit)) too_big = true;
        parser->cursor += width;
    }

    if (!too_big && number <= PM_REGEXP_BACKREF_MAXIMUM && (number <= 9 || number <= parser->groups)) {
        pm_regexp_defer(parser, PM_REGEXP_DEFERRED_NUMBER, start, parser->cursor, number);
        return;
    }

    parser->cursor = start;
    if (*parser->cursor == '8' || *parser->cursor == '9') {
        parser->cursor++;
        return;
    }

    for (int index = 0; index < 3 && parser->cursor < parser->end && *parser->cursor >= '0' && *parser->cursor <= '7'; index++) {
        parser->cursor++;
    }
}

/**
 * Parse a backslash escape sequence in a regexp, handling \u (unicode),
 * \p/\P (property), \x (hex), and other single-character escapes. The lexer
 * writes each \M-, \C-, and \c escape in the content as the \x escape of its
 * byte, so those forms never reach here.
 */
static void
pm_regexp_parse_backslash_escape(pm_regexp_parser_t *parser) {
    if (pm_regexp_char_is_eof(parser)) return;

    switch (*parser->cursor) {
        case 'u':
            parser->cursor++; // skip 'u'
            pm_regexp_parse_unicode_escape(parser);
            break;
        case 'p':
        case 'P':
            pm_regexp_parse_property_escape(parser);
            break;
        case 'x':
            parser->cursor++; // skip 'x'
            pm_regexp_parse_hex_escape(parser);
            break;
        case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
            pm_regexp_parse_numbered_backref(parser);
            break;
        case 'k': {
            /* A backreference by number or name, as in \k<n> or \k'n'. Without
             * a < or ' after it, the k is a character. */
            parser->cursor++;
            if (parser->cursor >= parser->end || (*parser->cursor != '<' && *parser->cursor != '\'')) break;

            uint8_t close = (*parser->cursor++ == '<') ? '>' : '\'';
            pm_regexp_reference_t reference;
            if (pm_regexp_parse_reference_with_level(parser, close, &reference) && pm_regexp_check_reference(parser, &reference)) {
                pm_regexp_defer_reference(parser, &reference, PM_REGEXP_DEFERRED_NUMBER);
            }
            break;
        }
        case 'g': {
            /* A call of a group by number or name, as in \g<n> or \g'n'.
             * Without a < or ' after it, the g is a character. */
            parser->cursor++;
            if (parser->cursor >= parser->end || (*parser->cursor != '<' && *parser->cursor != '\'')) break;

            uint8_t close = (*parser->cursor++ == '<') ? '>' : '\'';

            /* \g<0> calls the whole pattern. A 0 or + before anything else is
             * dropped, so \g<01> calls group 1 and \g<+1> counts forward. */
            bool forward = false;
            if (parser->cursor < parser->end && *parser->cursor == '0') {
                parser->cursor++;
                if (parser->cursor < parser->end && *parser->cursor == close) {
                    parser->cursor++;
                    break;
                }
            } else if (parser->cursor < parser->end && *parser->cursor == '+') {
                parser->cursor++;
                forward = true;
            }

            pm_regexp_reference_t reference;
            if (pm_regexp_parse_reference(parser, close, &reference) && pm_regexp_check_relative_call(parser, &reference, forward)) {
                if (reference.number == 0 && !forward) {
                    pm_regexp_defer(parser, PM_REGEXP_DEFERRED_CALL_NAME, reference.start, reference.end, 0);
                } else {
                    /* A call that counts is to the group that many after the
                     * groups opened so far, or before them for a - . */
                    int64_t number = reference.number;
                    if (forward || number < 0) {
                        if (number > 0) number--;
                        number += (int64_t) parser->groups + 1;
                    }
                    pm_regexp_defer(parser, PM_REGEXP_DEFERRED_CALL_NUMBER, reference.start, reference.end, number);
                }
            }
            break;
        }
        default:
            parser->cursor++;
            break;
    }
}

/**
 * Read the character at the cursor and return its value, which is its bytes
 * joined into one number. For every supported encoding, these numbers order
 * characters the same way as the code points that the regular expression
 * engine compares. An invalid byte, which the lexer has already reported, is
 * read as a character of its own.
 */
static uint32_t
pm_regexp_parse_char_value(pm_regexp_parser_t *parser) {
    const uint8_t *cursor = parser->cursor;
    size_t width = 1;

    if (*cursor >= 0x80) {
        width = pm_encoding_char_width(parser->encoding, cursor, (ptrdiff_t) (parser->end - cursor));
        if (width == 0) width = 1;
    }

    uint32_t value = 0;
    for (size_t index = 0; index < width; index++) value = (value << 8) | cursor[index];

    parser->cursor += width;
    return value;
}

/**
 * The kinds of tokens in a character class.
 */
typedef enum {
    /** The end of the pattern, before the class is closed. */
    PM_REGEXP_CLASS_TOKEN_EOF,

    /** A character, written as itself or as an escape. */
    PM_REGEXP_CLASS_TOKEN_CHAR,

    /** A set of characters, like \d or \p{Alpha}. */
    PM_REGEXP_CLASS_TOKEN_SET,

    /** The ] that closes the class. */
    PM_REGEXP_CLASS_TOKEN_CLOSE,

    /** The - between the ends of a range. */
    PM_REGEXP_CLASS_TOKEN_RANGE,

    /** The && between two classes that are intersected. */
    PM_REGEXP_CLASS_TOKEN_AND,

    /** A [ that opens a class nested in this one. */
    PM_REGEXP_CLASS_TOKEN_OPEN,

    /** A [: that is followed by :], so may open a bracket like [:alpha:]. */
    PM_REGEXP_CLASS_TOKEN_POSIX_OPEN
} pm_regexp_class_token_type_t;

/**
 * A token in a character class.
 */
typedef struct {
    /** The kind of token. */
    pm_regexp_class_token_type_t type;

    /** Where the token starts in the pattern. */
    const uint8_t *start;

    /** The value of a character, as pm_regexp_parse_char_value reads it. */
    uint32_t value;

    /** Whether a character is written as an escape. */
    bool escaped;
} pm_regexp_class_token_t;

/**
 * Whether a [: in a character class is followed by :] before the class could
 * be closed. The cursor is just past the colon. A ] that comes first closes
 * the class instead, unless it is escaped.
 */
static bool
pm_regexp_posix_bracket_close_p(const pm_regexp_parser_t *parser, const uint8_t *cursor) {
    bool escaped = false;

    while (cursor < parser->end) {
        if (escaped) {
            escaped = false;
        } else if (*cursor == ':') {
            if (cursor + 1 < parser->end && cursor[1] == ']') return true;
        } else if (*cursor == ']') {
            return false;
        } else if (*cursor == '\\') {
            escaped = true;
        }

        size_t width = 1;
        if (*cursor >= 0x80) {
            width = pm_encoding_char_width(parser->encoding, cursor, (ptrdiff_t) (parser->end - cursor));
            if (width == 0) width = 1;
        }
        cursor += width;
    }

    return false;
}

/**
 * Read an escape in a character class. The cursor is just past the backslash.
 *
 * The lexer writes each \M-, \C-, and \c escape as the \x escape of its byte,
 * and the preprocessor writes each \u escape as a \x escape or as its bytes, so
 * those forms never reach here.
 */
static void
pm_regexp_class_token_escape(pm_regexp_parser_t *parser, pm_regexp_class_token_t *token) {
    token->type = PM_REGEXP_CLASS_TOKEN_CHAR;
    token->escaped = true;

    /* A backslash at the end of the pattern was already reported when the
     * escapes were read. */
    if (parser->cursor >= parser->end) {
        token->value = '\\';
        return;
    }

    uint32_t length;
    switch (*parser->cursor) {
        case 'w': case 'W': case 'd': case 'D': case 's': case 'S': case 'h': case 'H':
            parser->cursor++;
            token->type = PM_REGEXP_CLASS_TOKEN_SET;
            return;
        case 'p': case 'P':
            if (pm_regexp_parse_property_escape(parser)) {
                token->type = PM_REGEXP_CLASS_TOKEN_SET;
            } else {
                token->value = parser->cursor[-1];
            }
            return;
        case 'x':
            parser->cursor++;
            token->value = pm_regexp_scan_digits(parser->cursor, parser->end, 2, 16, &length);
            parser->cursor += length;
            return;
        case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7':
            token->value = pm_regexp_scan_digits(parser->cursor, parser->end, 3, 8, &length);
            parser->cursor += length;
            return;
        case 'n': parser->cursor++; token->value = '\n'; return;
        case 't': parser->cursor++; token->value = '\t'; return;
        case 'r': parser->cursor++; token->value = '\r'; return;
        case 'f': parser->cursor++; token->value = '\f'; return;
        case 'a': parser->cursor++; token->value = '\a'; return;
        case 'b': parser->cursor++; token->value = '\b'; return;
        case 'e': parser->cursor++; token->value = '\033'; return;
        case 'v': parser->cursor++; token->value = '\v'; return;
        default:
            token->value = pm_regexp_parse_char_value(parser);
            return;
    }
}

/**
 * Read the next token in a character class.
 */
static void
pm_regexp_class_token_fetch(pm_regexp_parser_t *parser, pm_regexp_class_token_t *token) {
    token->start = parser->cursor;
    token->escaped = false;

    if (parser->cursor >= parser->end) {
        token->type = PM_REGEXP_CLASS_TOKEN_EOF;
        return;
    }

    switch (*parser->cursor) {
        case ']':
            parser->cursor++;
            token->type = PM_REGEXP_CLASS_TOKEN_CLOSE;
            return;
        case '-':
            parser->cursor++;
            token->type = PM_REGEXP_CLASS_TOKEN_RANGE;
            return;
        case '&':
            if (parser->cursor + 1 < parser->end && parser->cursor[1] == '&') {
                parser->cursor += 2;
                token->type = PM_REGEXP_CLASS_TOKEN_AND;
                return;
            }
            break;
        case '[':
            parser->cursor++;
            token->type = PM_REGEXP_CLASS_TOKEN_OPEN;

            if (parser->cursor < parser->end && *parser->cursor == ':' && pm_regexp_posix_bracket_close_p(parser, parser->cursor + 1)) {
                parser->cursor++;
                token->type = PM_REGEXP_CLASS_TOKEN_POSIX_OPEN;
            }
            return;
        case '\\':
            parser->cursor++;
            pm_regexp_class_token_escape(parser, token);
            return;
        default:
            break;
    }

    token->type = PM_REGEXP_CLASS_TOKEN_CHAR;
    token->value = pm_regexp_parse_char_value(parser);
}

#define PM_REGEXP_POSIX_BRACKET_NAME(name_) { .name = name_, .length = sizeof(name_) - 1 }
typedef struct { char name[7]; uint8_t length; } pm_regexp_posix_bracket_name_t;

/**
 * The names of the POSIX brackets, like [:alpha:].
 */
static const pm_regexp_posix_bracket_name_t pm_regexp_posix_bracket_names[] = {
    PM_REGEXP_POSIX_BRACKET_NAME("alnum"),
    PM_REGEXP_POSIX_BRACKET_NAME("alpha"),
    PM_REGEXP_POSIX_BRACKET_NAME("blank"),
    PM_REGEXP_POSIX_BRACKET_NAME("cntrl"),
    PM_REGEXP_POSIX_BRACKET_NAME("digit"),
    PM_REGEXP_POSIX_BRACKET_NAME("graph"),
    PM_REGEXP_POSIX_BRACKET_NAME("lower"),
    PM_REGEXP_POSIX_BRACKET_NAME("print"),
    PM_REGEXP_POSIX_BRACKET_NAME("punct"),
    PM_REGEXP_POSIX_BRACKET_NAME("space"),
    PM_REGEXP_POSIX_BRACKET_NAME("upper"),
    PM_REGEXP_POSIX_BRACKET_NAME("xdigit"),
    PM_REGEXP_POSIX_BRACKET_NAME("ascii"),
    PM_REGEXP_POSIX_BRACKET_NAME("word")
};

#undef PM_REGEXP_POSIX_BRACKET_NAME

/**
 * The results of reading a POSIX bracket.
 */
typedef enum {
    /** The bracket is invalid, which has been reported. */
    PM_REGEXP_POSIX_BRACKET_INVALID,

    /** The [ is not a bracket, so it is a character of the class. */
    PM_REGEXP_POSIX_BRACKET_NONE,

    /** The bracket is valid, and the cursor is past it. */
    PM_REGEXP_POSIX_BRACKET_VALID
} pm_regexp_posix_bracket_t;

/**
 * Read a POSIX bracket, like [:alpha:] or [:^alpha:]. The cursor is just past
 * its [:, which starts at the given position.
 *
 * A known name that is not followed by :] is invalid. So is an unknown name
 * of up to 20 characters that is followed by :]. Anything else is not a
 * bracket at all.
 */
static pm_regexp_posix_bracket_t
pm_regexp_parse_posix_bracket(pm_regexp_parser_t *parser, const uint8_t *start) {
    const uint8_t *cursor = parser->cursor;
    const uint8_t *end = parser->end;
    if (cursor < end && *cursor == '^') cursor++;

    /* The shortest bracket name has 4 characters, so along with its :] and the
     * ] that closes the class, a bracket needs 7 characters. */
    size_t characters = 0;
    for (const uint8_t *count = cursor; count < end && characters < 7; characters++) {
        size_t width = (*count >= 0x80) ? pm_encoding_char_width(parser->encoding, count, (ptrdiff_t) (end - count)) : 1;
        count += (width == 0) ? 1 : width;
    }

    if (characters >= 7) {
        for (size_t index = 0; index < sizeof(pm_regexp_posix_bracket_names) / sizeof(pm_regexp_posix_bracket_names[0]); index++) {
            const pm_regexp_posix_bracket_name_t *bracket_name = pm_regexp_posix_bracket_names + index;
            uint8_t length = bracket_name->length;

            if ((size_t) (end - cursor) < length || !pm_memequal(cursor, bracket_name->name, length)) continue;

            cursor += length;
            if (end - cursor < 2 || cursor[0] != ':' || cursor[1] != ']') {
                PM_REGEXP_PARSE_ERROR(parser, start, cursor, "invalid POSIX bracket type");
                return PM_REGEXP_POSIX_BRACKET_INVALID;
            }

            parser->cursor = cursor + 2;
            return PM_REGEXP_POSIX_BRACKET_VALID;
        }
    }

    /* Look a little way ahead for the :] of an unknown name. */
    size_t count = 0;
    while (cursor < end && *cursor != ':' && *cursor != ']' && count++ < 20) {
        size_t width = (*cursor >= 0x80) ? pm_encoding_char_width(parser->encoding, cursor, (ptrdiff_t) (end - cursor)) : 1;
        cursor += (width == 0) ? 1 : width;
    }

    if (end - cursor >= 2 && cursor[0] == ':' && cursor[1] == ']') {
        PM_REGEXP_PARSE_ERROR(parser, start, cursor + 2, "invalid POSIX bracket type");
        return PM_REGEXP_POSIX_BRACKET_INVALID;
    }

    return PM_REGEXP_POSIX_BRACKET_NONE;
}

/**
 * Where a character class is in reading its values and ranges.
 */
typedef enum {
    /** No value yet, or none since the last &&. */
    PM_REGEXP_CLASS_STATE_START,

    /** A value, which a - may make the start of a range. */
    PM_REGEXP_CLASS_STATE_VALUE,

    /** The start of a range and its -, so the end comes next. */
    PM_REGEXP_CLASS_STATE_RANGE,

    /** A whole range. */
    PM_REGEXP_CLASS_STATE_COMPLETE
} pm_regexp_class_state_t;

/**
 * The state of reading a character class.
 */
typedef struct {
    /** Where the class is in reading its values and ranges. */
    pm_regexp_class_state_t state;

    /** Whether the last value is a set of characters, like \d. */
    bool set;

    /** The last value, if it is a character. */
    uint32_t value;

    /** Where the last value starts in the pattern. */
    const uint8_t *start;
} pm_regexp_class_t;

/**
 * Add a character to a character class. If it ends a range, the range must
 * not be empty. The character starts at the given position.
 */
static bool
pm_regexp_class_add_char(pm_regexp_parser_t *parser, pm_regexp_class_t *character_class, uint32_t value, const uint8_t *start) {
    switch (character_class->state) {
        case PM_REGEXP_CLASS_STATE_RANGE:
            if (character_class->value > value) {
                PM_REGEXP_PARSE_ERROR(parser, character_class->start, parser->cursor, "empty range in char class");
                return false;
            }
            character_class->state = PM_REGEXP_CLASS_STATE_COMPLETE;
            break;
        case PM_REGEXP_CLASS_STATE_VALUE:
            break;
        case PM_REGEXP_CLASS_STATE_START:
        case PM_REGEXP_CLASS_STATE_COMPLETE:
            character_class->state = PM_REGEXP_CLASS_STATE_VALUE;
            break;
    }

    character_class->set = false;
    character_class->value = value;
    character_class->start = start;
    return true;
}

/**
 * Add a set of characters, like \d, to a character class. A set can't end a
 * range. The set starts at the given position.
 */
static bool
pm_regexp_class_add_set(pm_regexp_parser_t *parser, pm_regexp_class_t *character_class, const uint8_t *start) {
    if (character_class->state == PM_REGEXP_CLASS_STATE_RANGE) {
        PM_REGEXP_PARSE_ERROR(parser, character_class->start, parser->cursor, "char-class value at end of range");
        return false;
    }

    character_class->state = PM_REGEXP_CLASS_STATE_VALUE;
    character_class->set = true;
    character_class->start = start;
    return true;
}

/**
 * Parse a character class, like [a-z] or [^\d&&[:alpha:]]. The cursor is just
 * past its [. Classes can nest, and the depth is how deeply this one is nested
 * in groups and other classes. Returns false at the first error.
 *
 * The named capture pass reads the content rather than the pattern. There an
 * escape like \u{61} or \xE3\x81\x82 is still its text, so the values and
 * ranges of the class aren't what the pattern holds. That pass only finds
 * where the class ends, and doesn't check its ranges.
 */
static bool
pm_regexp_parse_character_class(pm_regexp_parser_t *parser, uint16_t depth) {
    const uint8_t *open = parser->cursor - 1;

    if (depth >= PM_REGEXP_PARSE_DEPTH_MAX) {
        PM_REGEXP_PARSE_ERROR(parser, parser->start, parser->end, "parse depth limit over");
        return false;
    }

    if (pm_parser_stack_exhausted(parser->parser)) {
        pm_regexp_parse_stack_exhausted(parser);
        return false;
    }

    pm_regexp_class_token_t token;
    pm_regexp_class_token_fetch(parser, &token);

    if (token.type == PM_REGEXP_CLASS_TOKEN_CHAR && token.value == '^' && !token.escaped) {
        pm_regexp_class_token_fetch(parser, &token);
    }

    /* A ] right after the [ or [^ is a character of the class, as long as
     * another ] comes later in the pattern. Otherwise the class is empty. */
    if (token.type == PM_REGEXP_CLASS_TOKEN_CLOSE) {
        if (pm_memchr_boundary(parser->cursor, ']', (size_t) (parser->end - parser->cursor), parser->encoding) == NULL) {
            PM_REGEXP_PARSE_ERROR(parser, token.start, parser->cursor, "empty char-class");
            return false;
        }

        token.type = PM_REGEXP_CLASS_TOKEN_CHAR;
        token.value = ']';
    }

    pm_regexp_class_t character_class = { .state = PM_REGEXP_CLASS_STATE_START, .set = false, .value = 0, .start = token.start };

    while (token.type != PM_REGEXP_CLASS_TOKEN_CLOSE) {
        bool fetched = false;

        switch (token.type) {
            case PM_REGEXP_CLASS_TOKEN_EOF:
                PM_REGEXP_PARSE_ERROR(parser, open, parser->end, "premature end of char-class");
                return false;
            case PM_REGEXP_CLASS_TOKEN_CHAR:
                if (!pm_regexp_class_add_char(parser, &character_class, token.value, token.start)) return false;
                break;
            case PM_REGEXP_CLASS_TOKEN_SET:
                if (!pm_regexp_class_add_set(parser, &character_class, token.start)) return false;
                break;
            case PM_REGEXP_CLASS_TOKEN_POSIX_OPEN:
                switch (pm_regexp_parse_posix_bracket(parser, token.start)) {
                    case PM_REGEXP_POSIX_BRACKET_INVALID:
                        return false;
                    case PM_REGEXP_POSIX_BRACKET_NONE:
                        /* The [ is a character, and the class goes on from
                         * the colon after it. */
                        parser->cursor = token.start + 1;
                        if (!pm_regexp_class_add_char(parser, &character_class, '[', token.start)) return false;
                        break;
                    case PM_REGEXP_POSIX_BRACKET_VALID:
                        if (!pm_regexp_class_add_set(parser, &character_class, token.start)) return false;
                        break;
                }
                break;
            case PM_REGEXP_CLASS_TOKEN_RANGE: {
                const uint8_t *range = token.start;

                switch (character_class.state) {
                    case PM_REGEXP_CLASS_STATE_VALUE:
                        /* A - before the end of the class or a && is a
                         * character, as in [a-]. Otherwise it makes the
                         * value the start of a range, which a set can't be. */
                        pm_regexp_class_token_fetch(parser, &token);
                        fetched = true;

                        if (token.type == PM_REGEXP_CLASS_TOKEN_CLOSE || token.type == PM_REGEXP_CLASS_TOKEN_AND) {
                            if (!pm_regexp_class_add_char(parser, &character_class, '-', range)) return false;
                        } else if (character_class.set) {
                            PM_REGEXP_PARSE_ERROR(parser, character_class.start, parser->cursor, "unmatched range specifier in char-class");
                            return false;
                        } else {
                            character_class.state = PM_REGEXP_CLASS_STATE_RANGE;
                        }
                        break;
                    case PM_REGEXP_CLASS_STATE_RANGE:
                        /* A - after a - ends the range, as in [!--]. */
                        if (!pm_regexp_class_add_char(parser, &character_class, '-', range)) return false;
                        break;
                    case PM_REGEXP_CLASS_STATE_START:
                    case PM_REGEXP_CLASS_STATE_COMPLETE:
                        /* A - at the start of the class or after a range is a
                         * character, as in [-a] or [a-b-c]. */
                        pm_regexp_class_token_fetch(parser, &token);
                        fetched = true;
                        if (!pm_regexp_class_add_char(parser, &character_class, '-', range)) return false;
                        break;
                }
                break;
            }
            case PM_REGEXP_CLASS_TOKEN_OPEN:
                if (!pm_regexp_parse_character_class(parser, (uint16_t) (depth + 1))) return false;
                break;
            case PM_REGEXP_CLASS_TOKEN_AND:
                character_class.state = PM_REGEXP_CLASS_STATE_START;
                break;
            case PM_REGEXP_CLASS_TOKEN_CLOSE:
                break;
        }

        if (!fetched) pm_regexp_class_token_fetch(parser, &token);
    }

    return true;
}

// Forward declaration here since parsing groups needs to go back up the grammar
// to parse expressions within them.
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser, uint16_t depth);

/**
 * Parse the name of a named group, as in the n of (?<n>a) or (?'n'a), with the
 * cursor on its first character, the way Onigmo's fetch_name reads it, and
 * consume the > or ' that closes it. In Ruby any character can be part of a
 * name, but a name must not be empty, must not start with a digit or a -, and
 * must be closed before the next ). Returns false when the name is not closed,
 * which stops the walk. After any other error the walk goes on past the name,
 * to report the errors that follow it.
 */
static bool
pm_regexp_parse_group_name(pm_regexp_parser_t *parser, uint8_t close) {
    const uint8_t *start = parser->cursor;

    if (parser->cursor >= parser->end) {
        PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "group name is empty");
        return false;
    }

    if (*parser->cursor == close) {
        PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "group name is empty");
        parser->cursor++;
        return true;
    }

    size_t width;
    uint32_t digit;
    bool invalid = *parser->cursor == '-' || pm_regexp_digit(parser, parser->cursor, &width, &digit);

    /* The first character is never the end of the name, even when it is a ). */
    pm_regexp_skip_char(parser);
    while (parser->cursor < parser->end && *parser->cursor != close && *parser->cursor != ')') {
        pm_regexp_skip_char(parser);
    }

    if (invalid) {
        /* The engine quotes the name up to the character that would end it. */
        pm_regexp_parse_quoted_error(parser, start, parser->cursor, &pm_regexp_invalid_group_name);
        if (parser->cursor >= parser->end || *parser->cursor != close) return false;

        parser->groups++;
        parser->cursor++;
        return true;
    }

    if (parser->cursor >= parser->end || *parser->cursor != close) {
        /* A name that is not closed is quoted to the end of the pattern. */
        pm_regexp_parse_quoted_error(parser, start, parser->end, &pm_regexp_invalid_group_name);
        return false;
    }

    parser->groups++;
    pm_regexp_names_append(parser, (pm_regexp_name_t) { .start = start, .length = (size_t) (parser->cursor - start) });

    parser->cursor++;
    return true;
}

/**
 * Parse the condition of a conditional group, as in the 1 of (?(1)a|b), with
 * the cursor after its (. The condition is the number of a group, or the name
 * of one between < and > or between quotes. Returns false after an error.
 */
static bool
pm_regexp_parse_condition(pm_regexp_parser_t *parser, const uint8_t *group_start) {
    if (pm_regexp_char_is_eof(parser)) {
        PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "undefined group option");
        return false;
    }

    pm_regexp_reference_t reference;
    size_t width;
    uint32_t digit;
    if (pm_regexp_digit(parser, parser->cursor, &width, &digit)) {
        if (!pm_regexp_parse_reference(parser, ')', &reference)) return false;
        pm_regexp_defer_reference(parser, &reference, PM_REGEXP_DEFERRED_CONDITION_NUMBER);
        return true;
    }

    switch (*parser->cursor) {
        case '<':
        case '\'': {
            uint8_t close = (*parser->cursor++ == '<') ? '>' : '\'';
            if (!pm_regexp_parse_reference_with_level(parser, close, &reference)) return false;
            if (!pm_regexp_check_reference(parser, &reference)) return false;
            pm_regexp_defer_reference(parser, &reference, PM_REGEXP_DEFERRED_NAMED_NUMBER);

            /* The name must be followed by the ) that ends the condition. */
            if (parser->cursor >= parser->end || *parser->cursor != ')') {
                PM_REGEXP_PARSE_ERROR(parser, parser->cursor, parser->cursor, "undefined group option");
                return false;
            }

            parser->cursor++;
            return true;
        }
        default:
            PM_REGEXP_PARSE_ERROR(parser, parser->cursor, parser->cursor + 1, "invalid conditional pattern");
            return false;
    }
}

/**
 * Groups can have quite a few different patterns for syntax. They basically
 * just wrap a set of expressions, but they can potentially have options after a
 * question mark. If there _isn't_ a question mark, then it's just a set of
 * expressions. If there _is_, then here are the options:
 *
 * * (?#...)                       - inline comments
 * * (?:subexp)                    - non-capturing group
 * * (?=subexp)                    - positive lookahead
 * * (?!subexp)                    - negative lookahead
 * * (?>subexp)                    - atomic group
 * * (?~subexp)                    - absence operator
 * * (?<=subexp)                   - positive lookbehind
 * * (?<!subexp)                   - negative lookbehind
 * * (?<name>subexp)               - named capturing group
 * * (?'name'subexp)               - named capturing group
 * * (?(cond)yes-subexp)           - conditional expression
 * * (?(cond)yes-subexp|no-subexp) - conditional expression
 * * (?imxdau-imx)                 - turn on and off configuration
 * * (?imxdau-imx:subexp)          - turn on and off configuration for an expression
 *
 * A group like (?i) only sets options, for the rest of the group around it.
 * There is nothing for a quantifier to repeat after it, as in (?i)*, so this
 * sets options_only to tell the caller not to read one.
 */
static bool
pm_regexp_parse_group(pm_regexp_parser_t *parser, uint16_t depth, bool *options_only) {
    /* Every level of nested groups passes through here, so this bounds the
     * group recursion by the stack budget. The check lives here rather than
     * beside the depth check in pm_regexp_parse_expression because there it
     * stops that function from being inlined, which adds a frame to every
     * level of nesting. */
    if (pm_parser_stack_exhausted(parser->parser)) {
        pm_regexp_parse_stack_exhausted(parser);
        return false;
    }

    const uint8_t *group_start = parser->cursor;

    /* Whether the options of the group turn extended mode on (1) or off (-1),
     * or leave it as it is (0). */
    int extended = 0;

    /* Whether the group is conditional, as in (?(1)a|b), which can have at
     * most two alternatives: one for when its condition holds and one for when
     * it does not. */
    bool conditional = false;

    // First, parse any options for the group. A group without them captures.
    if (!pm_regexp_char_accept(parser, '?')) {
        parser->groups++;
    } else {
        if (pm_regexp_char_is_eof(parser)) {
            PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "end pattern in group");
            return false;
        }

        switch (*parser->cursor) {
            case '#': { // inline comments
                /* Find the ) that ends the comment the way Onigmo does. A
                 * backslash escapes the character after it, so (?#a\)) ends
                 * at its second ). */
                parser->cursor++;

                while (parser->cursor < parser->end) {
                    uint8_t byte = *parser->cursor;
                    pm_regexp_skip_char(parser);

                    if (byte == ')') return true;
                    if (byte == '\\' && parser->cursor < parser->end) pm_regexp_skip_char(parser);
                }

                PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "end pattern in group");
                return false;
            }
            case ':': // non-capturing group
            case '=': // positive lookahead
            case '!': // negative lookahead
            case '>': // atomic group
            case '~': // absence operator
                parser->cursor++;
                break;
            case '<':
                parser->cursor++;
                if (pm_regexp_char_is_eof(parser)) {
                    PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "end pattern with unmatched parenthesis");
                    return false;
                }

                switch (*parser->cursor) {
                    case '=': // positive lookbehind
                    case '!': // negative lookbehind
                        parser->cursor++;
                        break;
                    default: // named capture group
                        if (!pm_regexp_parse_group_name(parser, '>')) return false;
                        break;
                }
                break;
            case '\'': // named capture group
                parser->cursor++;
                if (!pm_regexp_parse_group_name(parser, '\'')) return false;
                break;
            case '(': // conditional expression
                parser->cursor++;
                if (!pm_regexp_parse_condition(parser, group_start)) return false;
                conditional = true;
                break;
            case 'i': case 'm': case 'x': case 'a': case 'd': case 'u': case '-': {
                /* Read the options the way Onigmo does. Each of i, m, and x is
                 * turned on, or off after a -, and a, d, and u can only be
                 * turned on. The options end at a :, which starts the
                 * subexpression that they apply to, or at a ), after which
                 * they apply to the rest of the group around this one. */
                bool negated = false;

                while (true) {
                    if (pm_regexp_char_is_eof(parser)) {
                        PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "end pattern in group");
                        return false;
                    }

                    uint8_t option = *parser->cursor;
                    if (option == ':' || option == ')') break;

                    switch (option) {
                        case '-':
                            negated = true;
                            break;
                        case 'x':
                            extended = negated ? -1 : 1;
                            break;
                        case 'i':
                        case 'm':
                            break;
                        case 'a':
                        case 'd':
                        case 'u':
                            if (!negated) break;
                            PRISM_FALLTHROUGH
                        default:
                            PM_REGEXP_PARSE_ERROR(parser, parser->cursor, parser->cursor + 1, "undefined group option");
                            return false;
                    }

                    parser->cursor++;
                }

                if (*parser->cursor == ')') {
                    if (extended != 0) parser->extended_mode = (extended > 0);
                    parser->cursor++;
                    *options_only = true;
                    return true;
                }

                /* The : that starts the subexpression. */
                parser->cursor++;
                break;
            }
            default:
                parser->cursor++;
                PM_REGEXP_PARSE_ERROR(parser, parser->cursor - 1, parser->cursor, "undefined group option");
                break;
        }
    }

    bool extended_mode = parser->extended_mode;
    if (extended != 0) parser->extended_mode = (extended > 0);

    // Now, parse the expressions within this group.
    size_t alternatives = 1;

    while (true) {
        pm_regexp_skip_extended_whitespace(parser);
        if (pm_regexp_char_is_eof(parser) || *parser->cursor == ')') break;

        if (!pm_regexp_parse_expression(parser, (uint16_t) (depth + 1))) {
            parser->extended_mode = extended_mode;
            return false;
        }

        if (pm_regexp_char_accept(parser, '|') && conditional && ++alternatives == 3) {
            PM_REGEXP_PARSE_ERROR(parser, parser->cursor - 1, parser->cursor, "invalid conditional pattern");
        }
    }

    // Finally, make sure we have a closing parenthesis.
    parser->extended_mode = extended_mode;
    if (pm_regexp_char_expect(parser, ')')) return true;

    PM_REGEXP_PARSE_ERROR(parser, group_start, parser->cursor, "end pattern with unmatched parenthesis");
    return false;
}

/**
 * item : anchor
 *      | match-posix-class
 *      | match-char-set
 *      | match-char-class
 *      | match-char-prop
 *      | match-char
 *      | match-any
 *      | group
 *      | quantified
 *      ;
 */
static bool
pm_regexp_parse_item(pm_regexp_parser_t *parser, uint16_t depth) {
    switch (*parser->cursor) {
        case '^':
        case '$':
            parser->cursor++;
            return pm_regexp_parse_quantifier(parser);
        case '\\':
            parser->cursor++;
            pm_regexp_parse_backslash_escape(parser);
            return pm_regexp_parse_quantifier(parser);
        case '(': {
            parser->cursor++;

            bool options_only = false;
            if (!pm_regexp_parse_group(parser, depth, &options_only)) return false;

            /* A quantifier after a group like (?i) is the next item, which
             * reports that it has nothing to repeat. */
            return options_only || pm_regexp_parse_quantifier(parser);
        }
        case '[':
            parser->cursor++;
            return pm_regexp_parse_character_class(parser, depth) && pm_regexp_parse_quantifier(parser);
        case '*':
        case '?':
        case '+':
            parser->cursor++;
            PM_REGEXP_PARSE_ERROR(parser, parser->cursor - 1, parser->cursor, "target of repeat operator is not specified");
            return true;
        case '{': {
            const uint8_t *start = parser->cursor++;

            switch (pm_regexp_parse_interval(parser)) {
                case PM_REGEXP_INTERVAL_INVALID:
                    return false;
                case PM_REGEXP_INTERVAL_NONE:
                    /* The { is a character. */
                    return pm_regexp_parse_quantifier(parser);
                case PM_REGEXP_INTERVAL_VALID:
                    PM_REGEXP_PARSE_ERROR(parser, start, parser->cursor, "target of repeat operator is not specified");
                    return true;
            }

            return true;
        }
        case ')':
            parser->cursor++;
            PM_REGEXP_PARSE_ERROR(parser, parser->cursor - 1, parser->cursor, "unmatched close parenthesis");
            return true;
        case '#':
            if (parser->extended_mode) {
                const uint8_t *newline = pm_memchr(parser->cursor, '\n', (size_t) (parser->end - parser->cursor));
                parser->cursor = newline != NULL ? newline + 1 : parser->end;
                return true;
            }
        PRISM_FALLTHROUGH
        default: {
            size_t width;
            if (!parser->encoding_changed) {
                width = pm_encoding_utf_8_char_width(parser->cursor, (ptrdiff_t) (parser->end - parser->cursor));
            } else {
                width = pm_encoding_char_width(parser->encoding, parser->cursor, (ptrdiff_t) (parser->end - parser->cursor));
            }

            if (width == 0) {
                /* An invalid character, which the lexer has already reported,
                 * is skipped a byte at a time. */
                if (*parser->cursor >= 0x80 && parser->encoding_changed) {
                    parser->cursor++;
                    return pm_regexp_parse_quantifier(parser);
                }
                return false;
            }

            parser->cursor += width;
            return pm_regexp_parse_quantifier(parser);
        }
    }
}

/**
 * expression : item*
 *            ;
 */
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser, uint16_t depth) {
    if (depth >= PM_REGEXP_PARSE_DEPTH_MAX) {
        PM_REGEXP_PARSE_ERROR(parser, parser->start, parser->end, "parse depth limit over");
        return false;
    }

    /* An alternative can be empty, as in /a||b/, so a | here ends it. */
    if (*parser->cursor != '|' && !pm_regexp_parse_item(parser, depth)) {
        return false;
    }

    while (true) {
        pm_regexp_skip_extended_whitespace(parser);
        if (pm_regexp_char_is_eof(parser) || *parser->cursor == '|') return true;

        /* A ) ends the group that this expression is in. Outside of every
         * group it is unmatched, as in /a)/, and the item reports it. */
        if (*parser->cursor == ')' && depth > 0) return true;

        if (!pm_regexp_parse_item(parser, depth)) return false;
    }
}

/**
 * pattern : EOF
 *         | expression EOF
 *         | expression '|' pattern
 *         ;
 */
static bool
pm_regexp_parse_pattern(pm_regexp_parser_t *parser) {
    do {
        pm_regexp_skip_extended_whitespace(parser);
        if (pm_regexp_char_is_eof(parser)) return true;
        if (!pm_regexp_parse_expression(parser, 0)) return false;
    } while (pm_regexp_char_accept(parser, '|'));

    return pm_regexp_char_is_eof(parser);
}

// ---------------------------------------------------------------------------
// Encoding validation
// ---------------------------------------------------------------------------

/** Report a preprocessing error at the whole regular expression. */
static void
pm_regexp_preprocess_error(const pm_regexp_t *regexp, const char *message, size_t message_length) {
    pm_regexp_error_with_content(regexp, regexp->location.start, regexp->location.length, message, message_length);
}

#define PM_REGEXP_PREPROCESS_ERROR(regexp_, message_) \
    pm_regexp_preprocess_error((regexp_), "" message_, sizeof(message_) - 1)

/**
 * Append an error of the given kind to the regular expression as a whole, where
 * the message of that kind ends with the content.
 */
static void
pm_regexp_error_kind_with_content(const pm_regexp_t *regexp, pm_diagnostic_id_t diag_id) {
    pm_parser_t *parser = regexp->parser;

    char letters[3];
    size_t letters_length = pm_regexp_option_letters(regexp->flags, letters);

    pm_buffer_t buffer = { 0 };
    pm_regexp_format_for_error(&buffer, regexp->encoding, regexp->source, regexp->size);
    pm_diagnostic_list_append_slice_slice(
        &parser->metadata_arena,
        &parser->error_list,
        regexp->location.start,
        regexp->location.length,
        diag_id,
        pm_diagnostic_slice(pm_buffer_value(&buffer), buffer.length),
        (pm_string_t) { .source = (const uint8_t *) letters, .length = letters_length }
    );
    pm_buffer_cleanup(&buffer);
}

/**
 * Whether the content holds a character that is not ASCII. An invalid
 * character does not count, since it is an error of its own, reported where it
 * is lexed.
 */
static bool
pm_regexp_non_ascii_p(const pm_encoding_t *encoding, const uint8_t *cursor, const uint8_t *end) {
    switch (encoding->kind) {
        case PM_ENCODING_KIND_ASCII:
            /* No byte that is not ASCII is a valid character. */
            return false;
        case PM_ENCODING_KIND_SINGLE_BYTE:
            /* Every byte that is not ASCII is a valid character. */
            for (; cursor < end; cursor++) {
                if (*cursor >= 0x80) return true;
            }
            return false;
        case PM_ENCODING_KIND_UTF_8:
            /* A byte that is not ASCII may begin an invalid character, which
             * is skipped a byte at a time as the lexer reports it. UTF-8 is
             * decoded directly, since it is by far the most common. */
            for (; cursor < end; cursor++) {
                if (*cursor >= 0x80 && pm_encoding_utf_8_char_width(cursor, end - cursor)) return true;
            }
            return false;
        default:
            /* The same as UTF-8, through the decoder of the encoding. */
            for (; cursor < end; cursor++) {
                if (*cursor >= 0x80 && pm_encoding_char_width(encoding, cursor, end - cursor)) return true;
            }
            return false;
    }
}

/**
 * Find the encoding option of a regular expression: /n, /u, /e, or /s. Return
 * its letter and set the encoding to the one it names. If there is none,
 * return '\0' and set the encoding to NULL.
 */
static char
pm_regexp_encoding_option(pm_node_flags_t flags, const pm_encoding_t **encoding) {
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        *encoding = PM_ENCODING_ASCII_8BIT_ENTRY;
        return 'n';
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        *encoding = PM_ENCODING_UTF_8_ENTRY;
        return 'u';
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        *encoding = PM_ENCODING_EUC_JP_ENTRY;
        return 'e';
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        *encoding = PM_ENCODING_WINDOWS_31J_ENTRY;
        return 's';
    }

    *encoding = NULL;
    return '\0';
}

/**
 * Pick the encoding to read the escapes of a regular expression in.
 *
 * If it has an encoding option like /u, use that encoding, as long as the
 * content has no non-ASCII characters in some other encoding. Otherwise, use
 * the encoding of the content. One exception: US-ASCII content with no option
 * is read as binary.
 *
 * The option encoding is NULL if the regular expression has no such option.
 */
static const pm_encoding_t *
pm_regexp_read_encoding(const pm_regexp_t *regexp, const pm_encoding_t *option_encoding) {
    const pm_encoding_t *content = regexp->encoding;

    if (option_encoding == NULL) {
        return (content == PM_ENCODING_US_ASCII_ENTRY) ? PM_ENCODING_ASCII_8BIT_ENTRY : content;
    }

    if (content == option_encoding || !pm_regexp_non_ascii_p(content, regexp->source, regexp->source + regexp->size)) return option_encoding;
    return content;
}

/**
 * Check the encoding option of a regular expression (/n, /u, /e, or /s)
 * against the characters written in it, before any of its escapes are read.
 * Every character that is not ASCII must already be in the encoding that the
 * option names, so the content must be in that one, which is the source
 * encoding unless the content joins strings in another encoding. When it is
 * not, the regular expression is still validated, in the encoding of its
 * content, except with /n, where such a character is an error of its own and
 * nothing more is checked.
 *
 * Returns the encoding that the rest of the regular expression is read in, as
 * pm_regexp_read_encoding gives it, or NULL if nothing more is checked.
 */
static const pm_encoding_t *
pm_regexp_check_option(const pm_regexp_t *regexp) {
    pm_parser_t *parser = regexp->parser;
    const pm_encoding_t *encoding;
    char option = pm_regexp_encoding_option(regexp->flags, &encoding);

    const pm_encoding_t *read_encoding = pm_regexp_read_encoding(regexp, encoding);
    if (option == '\0' || read_encoding == encoding) return read_encoding;

    pm_diagnostic_list_append_byte_slice(
        &parser->metadata_arena,
        &parser->error_list,
        regexp->location.start,
        regexp->location.length,
        PM_ERR_REGEXP_ENCODING_OPTION_MISMATCH,
        (uint8_t) option,
        pm_diagnostic_string(regexp->encoding->name)
    );
    if (option != 'n') return read_encoding;

    pm_regexp_error_kind_with_content(regexp, PM_ERR_REGEXP_NON_ESCAPED_MBC);
    return NULL;
}

/**
 * The state of reading the escapes of a regular expression, which finds the
 * encoding that its characters and escapes fix it to before its pattern is
 * parsed.
 */
typedef struct {
    /** The regular expression, whose content is read. */
    const pm_regexp_t *regexp;

    /** The end of the content. */
    const uint8_t *end;

    /** The encoding that the content is read in. */
    const pm_encoding_t *encoding;

    /**
     * The encoding that the characters and escapes read so far fix the
     * regular expression to, or NULL if none of them fixes it.
     */
    const pm_encoding_t *fixed_encoding;

    /**
     * Whether a property escape came before anything fixed the encoding,
     * which fixes it to the encoding that the content is read in.
     */
    bool has_property;

    /**
     * The pattern that the content preprocesses to. It is only written once
     * it first differs from the content, which it does for few regular
     * expressions. Until then, the content is the pattern.
     */
    pm_buffer_t pattern;

    /** The end of the content that the pattern holds so far. */
    const uint8_t *written;

    /** Whether the pattern differs from the content. */
    bool rewritten;

    /**
     * Where the pattern stops lining up with the content. In each place, the
     * content offset is in the pattern and the source offset is in the content.
     */
    pm_regexp_offsets_t offsets;
} pm_regexp_preprocessor_t;

/**
 * Start writing something into the pattern in place of the content at the
 * given position. The content before it is copied into the pattern first.
 */
static void
pm_regexp_preprocess_replace(pm_regexp_preprocessor_t *preprocessor, const uint8_t *from) {
    pm_buffer_append_bytes(&preprocessor->pattern, preprocessor->written, (size_t) (from - preprocessor->written));
    preprocessor->written = from;
}

/**
 * Finish writing something into the pattern in place of the content up to the
 * given position, and record where the two stop lining up.
 */
static void
pm_regexp_preprocess_resume(pm_regexp_preprocessor_t *preprocessor, const uint8_t *to) {
    preprocessor->written = to;
    preprocessor->rewritten = true;

    uint32_t pattern = (uint32_t) pm_buffer_length(&preprocessor->pattern);
    uint32_t content = (uint32_t) (to - preprocessor->regexp->source);
    pm_regexp_offsets_record(preprocessor->regexp->parser, &preprocessor->offsets, pattern, content, 0);
}

/**
 * Fix the regular expression to the given encoding, which a character or an
 * escape that is not ASCII calls for. Returns false if it was fixed to another
 * encoding already, which is an error for the caller to report.
 */
static bool
pm_regexp_preprocess_fix_encoding(pm_regexp_preprocessor_t *preprocessor, const pm_encoding_t *encoding) {
    if (preprocessor->fixed_encoding == NULL) preprocessor->fixed_encoding = encoding;
    return preprocessor->fixed_encoding == encoding;
}


/**
 * Read the escape at the cursor as the byte that it stands for, which is how
 * an escape of a byte that is not ASCII is read, along with the escapes after
 * it that complete its character. The lexer writes each \M-, \C-, and \c
 * escape in the content as the \x escape of its byte, so those forms never
 * reach here. Returns the byte, or -1 after reporting an error.
 */
static int
pm_regexp_preprocess_escaped_byte(pm_regexp_preprocessor_t *preprocessor, const uint8_t **parent_cursor) {
    const uint8_t *end = preprocessor->end;
    const uint8_t *cursor = *parent_cursor;
    uint32_t code;
    uint32_t length;

    if (cursor == end || *cursor++ != '\\') {
        PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "too short escaped multibyte character");
        return -1;
    }

    if (cursor == end) {
        PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "too short escape sequence");
        return -1;
    }

    switch (*cursor++) {
        case '\\': code = '\\'; break;
        case 'n': code = '\n'; break;
        case 't': code = '\t'; break;
        case 'r': code = '\r'; break;
        case 'f': code = '\f'; break;
        case 'v': code = '\v'; break;
        case 'a': code = '\a'; break;
        case 'e': code = '\033'; break;
        case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7':
            code = pm_regexp_scan_digits(cursor - 1, end, 3, 8, &length);
            cursor += length - 1;
            break;
        case 'x':
            code = pm_regexp_scan_digits(cursor, end, 2, 16, &length);
            if (length == 0) {
                PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid hex escape");
                return -1;
            }
            cursor += length;
            break;
        default:
            PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "unexpected escape sequence");
            return -1;
    }

    if (code > 0xFF) {
        PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid escape code");
        return -1;
    }

    *parent_cursor = cursor;
    return (int) code;
}

/**
 * Read the escape of a byte at the cursor, along with the escapes after it
 * that complete the character it begins.
 *
 * A character that is not ASCII fixes the regular expression to the encoding
 * that the content is read in, and goes into the pattern as its bytes. An
 * ASCII character keeps its escape, which the pattern reads the same way.
 */
static bool
pm_regexp_preprocess_escaped_char(pm_regexp_preprocessor_t *preprocessor, const uint8_t **parent_cursor) {
    const pm_encoding_t *encoding = preprocessor->encoding;
    const uint8_t *start = *parent_cursor;
    uint8_t bytes[8];
    size_t length = 0;

    do {
        int byte = pm_regexp_preprocess_escaped_byte(preprocessor, parent_cursor);
        if (byte < 0) return false;
        bytes[length++] = (uint8_t) byte;
    } while (length < sizeof(bytes) && pm_encoding_char_width(encoding, bytes, (ptrdiff_t) length) == 0 && pm_encoding_char_prefix_p(encoding, bytes, (ptrdiff_t) length));

    if (pm_encoding_char_width(encoding, bytes, (ptrdiff_t) length) == 0 && !pm_encoding_char_prefix_p(encoding, bytes, (ptrdiff_t) length)) {
        pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_INVALID_MULTIBYTE_ESCAPE);
        return false;
    }

    if (length > 1 || bytes[0] >= 0x80) {
        if (!pm_regexp_preprocess_fix_encoding(preprocessor, encoding)) {
            pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_ESCAPED_NON_ASCII_IN_UTF8);
            return false;
        }

        pm_regexp_preprocess_replace(preprocessor, start);
        pm_buffer_append_bytes(&preprocessor->pattern, bytes, length);
        pm_regexp_preprocess_resume(preprocessor, *parent_cursor);
    }

    return true;
}

/**
 * Read a code point of a \u escape and write it into the pattern. One that is
 * not ASCII fixes the regular expression to UTF-8 and goes into the pattern as
 * its UTF-8 bytes. An ASCII one goes in as a \x escape.
 */
static bool
pm_regexp_preprocess_code_point(pm_regexp_preprocessor_t *preprocessor, uint32_t value) {
    if ((value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
        pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_INVALID_UNICODE_RANGE);
        return false;
    }

    if (value < 0x80) {
        pm_buffer_append_byte_escape(&preprocessor->pattern, (uint8_t) value);
        return true;
    }

    if (!pm_regexp_preprocess_fix_encoding(preprocessor, PM_ENCODING_UTF_8_ENTRY)) {
        pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_UTF8_CHAR_NON_UTF8_REGEXP);
        return false;
    }

    pm_buffer_append_unicode_codepoint(&preprocessor->pattern, value);
    return true;
}

/**
 * Whether the byte is whitespace between the code points of a \u{...} escape.
 */
static PRISM_INLINE bool
pm_regexp_preprocess_space_p(uint8_t byte) {
    return byte == ' ' || (byte >= '\t' && byte <= '\r');
}

/**
 * Read the code points of a \u{...} escape, from the cursor after its brace up
 * to its closing brace.
 */
static bool
pm_regexp_preprocess_code_point_list(pm_regexp_preprocessor_t *preprocessor, const uint8_t **parent_cursor) {
    const uint8_t *end = preprocessor->end;
    const uint8_t *cursor = *parent_cursor;
    bool has_code_point = false;

    while (cursor < end && pm_regexp_preprocess_space_p(*cursor)) cursor++;

    while (true) {
        uint32_t length;
        uint32_t value = pm_regexp_scan_digits(cursor, end, UINT32_MAX, 16, &length);
        if (length == 0) break;

        /* The largest code point, 10FFFF, has six digits. */
        if (length > 6) {
            pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_INVALID_UNICODE_RANGE);
            return false;
        }
        cursor += length;

        if (!pm_regexp_preprocess_code_point(preprocessor, value)) return false;
        has_code_point = true;

        while (cursor < end && pm_regexp_preprocess_space_p(*cursor)) cursor++;
    }

    if (!has_code_point || cursor == end || *cursor++ != '}') {
        PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid Unicode list");
        return false;
    }

    *parent_cursor = cursor;
    return true;
}

/**
 * Whether the content needs to be preprocessed at all. Most regular
 * expressions don't, so this quick check lets them skip it.
 *
 * Only a byte that is not ASCII, or an escape of a byte, a code point, or a
 * property, can fix the encoding or be an error. Only those and comments make
 * the pattern differ from the content. Any # might start a comment, since an
 * option like (?x) can turn on extended mode anywhere.
 */
static bool
pm_regexp_preprocess_needed_p(const uint8_t *cursor, const uint8_t *end) {
    while (cursor < end) {
        uint8_t byte = *cursor++;

        switch (byte) {
            case '\\':
                /* A trailing backslash is an error. */
                if (cursor == end) return true;

                byte = *cursor++;
                switch (byte) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7':
                    case 'x': case 'u': case 'p': case 'P':
                        return true;
                    default:
                        break;
                }
                break;
            case '#':
                return true;
            default:
                break;
        }

        /* The byte last read, whether on its own or after a backslash, fixes
         * the encoding if it is not ASCII. */
        if (byte >= 0x80) return true;
    }

    return false;
}

/**
 * The ASCII bytes that reading the escapes of the content stops at. Every other
 * ASCII byte is a character that neither fixes the encoding nor starts an
 * escape or a comment, so it is skipped.
 */
static const bool pm_regexp_preprocess_stops[128] = {
    ['\\'] = true, ['#'] = true, ['['] = true, [']'] = true, ['('] = true, [')'] = true
};

/**
 * Read the content from the cursor, checking its escapes and finding the
 * encoding that its characters fix it to. Comments are skipped, both (?#...)
 * and, in extended mode, those from # to the end of the line, except that a
 * character that is not ASCII in a comment fixes a regular expression read in
 * UTF-8 to UTF-8. An invalid character that was lexed is an error of its own,
 * reported where it was lexed, so it is skipped a byte at a time; one in
 * content that was not lexed is an error here.
 *
 * Within a group that turns extended mode on or off for its subexpression, as
 * in (?x:...), this is called again for the subexpression, which reads up to
 * the parenthesis that its own count of open parentheses closes. The depth is
 * how many such groups enclose the content being read.
 */
static bool
pm_regexp_preprocess_scan(pm_regexp_preprocessor_t *preprocessor, const uint8_t **parent_cursor, bool extended, bool nested, uint16_t depth) {
    /* Groups nested this deeply are an error of the pattern, which its walk
     * reports. Past that depth, this leaves the cursor where it is, so that
     * the caller reads the escapes of the subexpression as part of its own
     * rather than this recursing without bound. */
    if (depth >= PM_REGEXP_PARSE_DEPTH_MAX) {
        return true;
    }

    const pm_regexp_t *regexp = preprocessor->regexp;
    if (pm_parser_stack_exhausted(regexp->parser)) {
        pm_parser_err_stack_exhausted(regexp->parser, regexp->location.start, regexp->location.length);
        return false;
    }

    const pm_encoding_t *encoding = preprocessor->encoding;
    const uint8_t *end = preprocessor->end;
    const uint8_t *cursor = *parent_cursor;

    uint32_t character_classes = 0;
    uint32_t parentheses = 1;

    while (cursor < end) {
        /* Every supported encoding is ASCII-compatible, so a byte below 0x80
         * at the start of a character is a character by itself. */
        while (cursor < end && *cursor < 0x80 && !pm_regexp_preprocess_stops[*cursor]) cursor++;
        if (cursor == end) break;

        switch (*cursor++) {
            case '\\': {
                if (cursor == end) {
                    PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "too short escape sequence");
                    return false;
                }

                if (*cursor >= 0x80) {
                    size_t width = pm_encoding_char_width(encoding, cursor, end - cursor);
                    if (width == 0) {
                        if (preprocessor->regexp->unlexed) {
                            PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid multibyte character");
                            return false;
                        }

                        cursor++;
                        break;
                    }

                    /* A backslash before a character of more than one byte
                     * is read along with the character. */
                    if (width > 1) {
                        cursor += width;
                        if (!pm_regexp_preprocess_fix_encoding(preprocessor, encoding)) {
                            PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "non ASCII character in UTF-8 regexp");
                            return false;
                        }
                        break;
                    }
                }

                switch (*cursor++) {
                    case '1': case '2': case '3': case '4': case '5': case '6': case '7': {
                        /* A backreference, or the octal escape of an ASCII
                         * character (up to 0x7F, the largest), is kept as it
                         * is, since the two cannot be told apart here. A
                         * larger value is the escape of a byte. */
                        uint32_t length;
                        if (pm_regexp_scan_digits(cursor - 1, end, 3, 8, &length) <= 0x7F) break;
                    }
                    PRISM_FALLTHROUGH
                    case '0': case 'x':
                        cursor -= 2;
                        if (!pm_regexp_preprocess_escaped_char(preprocessor, &cursor)) return false;
                        break;
                    case 'u':
                        if (cursor == end) {
                            PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "too short escape sequence");
                            return false;
                        }

                        /* The code points replace the escape in the pattern. */
                        pm_regexp_preprocess_replace(preprocessor, cursor - 2);

                        if (*cursor == '{') {
                            cursor++;
                            if (!pm_regexp_preprocess_code_point_list(preprocessor, &cursor)) return false;
                        } else {
                            uint32_t length;
                            uint32_t value = pm_regexp_scan_digits(cursor, end, 4, 16, &length);
                            if (length != 4) {
                                PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid Unicode escape");
                                return false;
                            }

                            cursor += 4;
                            if (!pm_regexp_preprocess_code_point(preprocessor, value)) return false;
                        }

                        pm_regexp_preprocess_resume(preprocessor, cursor);
                        break;
                    case 'p':
                    case 'P':
                        if (preprocessor->fixed_encoding == NULL) preprocessor->has_property = true;
                        break;
                    default:
                        break;
                }
                break;
            }
            case '#':
                if (extended && !character_classes) {
                    /* The comment and the newline that ends it are left out
                     * of the pattern. */
                    pm_regexp_preprocess_replace(preprocessor, cursor - 1);

                    while (cursor < end && *cursor != '\n') {
                        if (*cursor >= 0x80 && preprocessor->fixed_encoding == NULL && encoding == PM_ENCODING_UTF_8_ENTRY) {
                            preprocessor->fixed_encoding = encoding;
                        }
                        cursor++;
                    }
                    if (cursor < end) cursor++;

                    pm_regexp_preprocess_resume(preprocessor, cursor);
                }
                break;
            case '[':
                character_classes++;
                break;
            case ']':
                if (character_classes > 0) character_classes--;
                break;
            case ')':
                if (character_classes == 0 && nested && --parentheses == 0) {
                    *parent_cursor = cursor;
                    return true;
                }
                break;
            case '(':
                if (character_classes > 0) {
                    break;
                } else if (cursor + 1 < end && *cursor == '?' && cursor[1] == '#') {
                    const uint8_t *comment = cursor;
                    bool closed = false;

                    while (!closed && cursor < end) {
                        uint8_t byte = *cursor++;

                        if (byte == ')') {
                            closed = true;
                        } else if (byte == '\\' || byte >= 0x80) {
                            if (byte >= 0x80) {
                                if (preprocessor->fixed_encoding == NULL && encoding == PM_ENCODING_UTF_8_ENTRY) {
                                    preprocessor->fixed_encoding = encoding;
                                }
                                cursor--;
                            }

                            /* A backslash skips the character after it, so
                             * that it does not close the comment. */
                            if (cursor < end) {
                                size_t width = pm_encoding_char_width(encoding, cursor, end - cursor);
                                if (width == 0 && preprocessor->regexp->unlexed) {
                                    PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid multibyte character");
                                    return false;
                                }

                                cursor += (width == 0) ? 1 : width;
                            }
                        }
                    }

                    /* A comment is left out of the pattern. An unterminated
                     * one is read as the text that it holds, which is a
                     * syntax error of the pattern. */
                    if (closed) {
                        pm_regexp_preprocess_replace(preprocessor, comment - 1);
                        pm_regexp_preprocess_resume(preprocessor, cursor);
                    } else {
                        cursor = comment;
                    }
                } else if (cursor + 1 < end && *cursor == '?') {
                    /* Look through the options of the group for one that
                     * turns extended mode on or off. */
                    int extend = 0;
                    bool invert = false;
                    if (nested) parentheses++;

                    for (const uint8_t *option = cursor + 1; option < end; option++) {
                        switch (*option) {
                            case 'x':
                                extend = invert ? -1 : 1;
                                continue;
                            case '-':
                                invert = true;
                                continue;
                            case 'i': case 'm': case 'a': case 'd': case 'u':
                                continue;
                            case ':':
                            case ')':
                                if (extend == 0 || (extend == -1) != extended) break;

                                if (*option == ':') {
                                    if (!pm_regexp_preprocess_scan(preprocessor, &cursor, extend == 1, true, (uint16_t) (depth + 1))) return false;
                                } else {
                                    extended = (extend == 1);
                                }
                                break;
                            default:
                                break;
                        }
                        break;
                    }
                } else if (nested) {
                    parentheses++;
                }
                break;
            default: {
                /* Every other ASCII byte was skipped above, so this is the
                 * first byte of a character that is not ASCII. */
                size_t width = pm_encoding_char_width(encoding, cursor - 1, end - (cursor - 1));
                if (width == 0) {
                    if (preprocessor->regexp->unlexed) {
                        PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "invalid multibyte character");
                        return false;
                    }

                    break;
                }

                cursor += width - 1;
                if (!pm_regexp_preprocess_fix_encoding(preprocessor, encoding)) {
                    PM_REGEXP_PREPROCESS_ERROR(preprocessor->regexp, "non ASCII character in UTF-8 regexp");
                    return false;
                }
                break;
            }
        }
    }

    if (nested) *parent_cursor = cursor;
    return true;
}

/**
 * The options of a regular expression that fix its encoding, which affect how
 * the encoding is resolved from what its content fixes it to.
 */
typedef enum {
    /** No encoding option. */
    PM_REGEXP_ENCODING_OPTION_NONE,

    /** The /n option, which reads the content as binary. */
    PM_REGEXP_ENCODING_OPTION_BINARY,

    /** The /e, /s, or /u option, which fixes the encoding to its own. */
    PM_REGEXP_ENCODING_OPTION_FIXED
} pm_regexp_encoding_option_t;

/**
 * Resolve the encoding of the regular expression from the encoding that its
 * content is read in and the one that its content fixes it to. Returns NULL
 * after reporting an error if the two are incompatible with its options.
 */
static const pm_encoding_t *
pm_regexp_resolve_encoding(const pm_regexp_t *regexp, pm_regexp_encoding_option_t option, const pm_encoding_t *encoding, const pm_encoding_t *fixed_encoding) {
    if (fixed_encoding != NULL) {
        if ((option == PM_REGEXP_ENCODING_OPTION_FIXED && fixed_encoding != encoding) || (option == PM_REGEXP_ENCODING_OPTION_BINARY && fixed_encoding != PM_ENCODING_ASCII_8BIT_ENTRY)) {
            pm_regexp_error_kind_with_content(regexp, PM_ERR_REGEXP_INCOMPAT_CHAR_ENCODING);
            return NULL;
        }

        return fixed_encoding;
    }

    /* Without an encoding option, a regular expression that nothing fixes is
     * in US-ASCII, as is one with /n, whose content must then all be ASCII. */
    return (option == PM_REGEXP_ENCODING_OPTION_FIXED) ? encoding : PM_ENCODING_US_ASCII_ENTRY;
}

/**
 * Return the flag that marks the regular expression as being in the given
 * encoding, which it needs only when its options and the source encoding do not
 * already give it that one.
 */
static pm_node_flags_t
pm_regexp_encoding_flags(const pm_parser_t *parser, pm_node_flags_t flags, const pm_encoding_t *encoding) {
    const pm_encoding_t *implied;
    if (pm_regexp_encoding_option(flags, &implied) == '\0') implied = parser->encoding;

    if (encoding == implied) return 0;
    if (encoding == PM_ENCODING_UTF_8_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_UTF8_ENCODING;
    if (encoding == PM_ENCODING_ASCII_8BIT_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_BINARY_ENCODING;
    if (encoding == PM_ENCODING_US_ASCII_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_US_ASCII_ENCODING;
    return 0;
}

/**
 * Check the property escapes that the pattern holds against the encoding that
 * the pattern is parsed in, which its encoding option or the source decides.
 * In an encoding whose characters are Unicode code points, any property name
 * is accepted. EUC-JP and Shift_JIS know the POSIX properties and the script
 * properties, and every other encoding knows only the POSIX properties.
 */
static void
pm_regexp_check_properties(const pm_regexp_t *regexp, const pm_regexp_parser_t *regexp_parser) {
    pm_parser_t *parser = regexp->parser;
    const uint8_t *name;
    size_t length;

    switch (regexp_parser->encoding->kind) {
        case PM_ENCODING_KIND_UTF_8:
        case PM_ENCODING_KIND_CESU_8:
            return;
        case PM_ENCODING_KIND_EUC_JP:
        case PM_ENCODING_KIND_SHIFT_JIS:
            name = regexp_parser->unicode_property_name;
            length = regexp_parser->unicode_property_name_length;
            break;
        default:
            name = regexp_parser->property_name;
            length = regexp_parser->property_name_length;
            break;
    }

    if (name == NULL) return;

    char letters[3];
    size_t letters_length = pm_regexp_option_letters(regexp->flags, letters);

    pm_buffer_t formatted = { 0 };
    pm_regexp_format_for_error(&formatted, regexp->encoding, regexp->source, regexp->size);
    pm_diagnostic_list_append_slice_slice_slice(
        &parser->metadata_arena,
        &parser->error_list,
        regexp->location.start,
        regexp->location.length,
        PM_ERR_REGEXP_INVALID_CHAR_PROPERTY,
        pm_diagnostic_slice(name, length),
        pm_diagnostic_slice(formatted.value, formatted.length),
        (pm_string_t) { .source = (const uint8_t *) letters, .length = letters_length }
    );
    pm_buffer_cleanup(&formatted);
}

/**
 * Validate a regular expression, in the order that Ruby reads it, which stops
 * at the first of these steps that finds an error:
 *
 * 1. Check its encoding option against the characters written in it.
 * 2. Read its escapes, to find the encoding that they and its characters fix
 *    it to, and the pattern that they preprocess to.
 * 3. Resolve its encoding from that and its options.
 * 4. Parse the pattern in that encoding.
 *
 * The first three read the content, where the lexer keeps the escapes that the
 * regular expression engine reads as their text, so that escaped bytes can be
 * told from literal ones. The offsets map places in the content to places in
 * the source, starting at the given offset, for errors in the pattern. Without
 * them, those errors are reported at the whole regular expression. Returns the
 * flags of the encoding of the regular expression. If the next token is =~,
 * save the capture names until the Ruby parser has read the right operand.
 */
static pm_node_flags_t
pm_regexp_validate(const pm_regexp_t *regexp, const pm_regexp_offsets_t *offsets, uint32_t source_start, const pm_node_t *match_receiver) {
    pm_parser_t *parser = regexp->parser;
    const uint8_t *source = regexp->source;
    size_t size = regexp->size;
    pm_node_flags_t flags = regexp->flags;
    bool extended_mode = (flags & PM_REGULAR_EXPRESSION_FLAGS_EXTENDED) != 0;

    const pm_encoding_t *read_encoding = pm_regexp_check_option(regexp);
    if (read_encoding == NULL) return 0;

    pm_regexp_preprocessor_t preprocessor = {
        .regexp = regexp,
        .end = source + size,
        .encoding = read_encoding,
        .fixed_encoding = NULL,
        .has_property = false,
        .pattern = { 0 },
        .written = source,
        .rewritten = false,
        .offsets = { 0 }
    };

    const uint8_t *cursor = source;
    if (pm_regexp_preprocess_needed_p(source, source + size) && !pm_regexp_preprocess_scan(&preprocessor, &cursor, extended_mode, false, 0)) {
        pm_buffer_cleanup(&preprocessor.pattern);
        return 0;
    }

    /* A property escape before anything else fixes the encoding fixes it to
     * the one that the content is read in. */
    if (preprocessor.has_property && preprocessor.fixed_encoding == NULL) {
        preprocessor.fixed_encoding = read_encoding;
    }

    const pm_encoding_t *option_encoding;
    char letter = pm_regexp_encoding_option(flags, &option_encoding);

    pm_regexp_encoding_option_t option = PM_REGEXP_ENCODING_OPTION_NONE;
    if (letter == 'n') {
        option = PM_REGEXP_ENCODING_OPTION_BINARY;
    } else if (letter != '\0') {
        option = PM_REGEXP_ENCODING_OPTION_FIXED;
    }

    const pm_encoding_t *encoding = pm_regexp_resolve_encoding(regexp, option, read_encoding, preprocessor.fixed_encoding);
    if (encoding == NULL) {
        pm_buffer_cleanup(&preprocessor.pattern);
        return 0;
    }

    const uint8_t *pattern = source;
    size_t pattern_size = size;

    if (preprocessor.rewritten) {
        pm_regexp_preprocess_replace(&preprocessor, source + size);
        pattern = (const uint8_t *) pm_buffer_value(&preprocessor.pattern);
        pattern_size = pm_buffer_length(&preprocessor.pattern);
    }

    pm_regexp_parser_t regexp_parser = {
        .parser = parser,
        .regexp = regexp,
        .start = pattern,
        .cursor = pattern,
        .end = pattern + pattern_size,
        .pattern_offsets = preprocessor.rewritten ? &preprocessor.offsets : NULL,
        .offsets = offsets,
        .source_start = source_start,
        .location = regexp->location,
        .extended_mode = extended_mode,
        .encoding_changed = encoding != PM_ENCODING_UTF_8_ENTRY,
        .encoding = encoding,
        .property_name = NULL,
        .property_name_length = 0,
        .unicode_property_name = NULL,
        .unicode_property_name_length = 0
    };

    pm_regexp_parse_pattern(&regexp_parser);
    pm_regexp_check_deferreds(&regexp_parser);
    pm_regexp_check_properties(regexp, &regexp_parser);

    if (match_receiver != NULL && regexp_parser.names.size > 0) {
        pm_regexp_match_t *match = PM_ARENA_ALLOC(&parser->scratch_arena, pm_regexp_match_t);
        match->receiver = match_receiver;
        match->size = regexp_parser.names.size;
        match->captures = PM_ARENA_ALLOC_ARRAY(&parser->scratch_arena, pm_regexp_capture_t, match->size);

        for (size_t index = 0; index < match->size; index++) {
            const pm_regexp_name_t *name = &regexp_parser.names.values[index];
            uint32_t start = pm_regexp_source_offset(&regexp_parser, name->start, true);
            uint32_t end = pm_regexp_source_offset(&regexp_parser, name->start + name->length, false);
            const uint8_t *bytes = name->start;

            /* The rewritten pattern and joined content use temporary buffers. */
            if (preprocessor.rewritten || offsets == NULL) {
                uint8_t *copy = PM_ARENA_ALLOC_ARRAY(&parser->scratch_arena, uint8_t, name->length);
                memcpy(copy, bytes, name->length);
                bytes = copy;
            }

            match->captures[index] = (pm_regexp_capture_t) { .name = bytes, .length = name->length, .location = { .start = start, .length = end - start } };
        }

        parser->regexp_match = match;
    }

    pm_buffer_cleanup(&preprocessor.pattern);

    return pm_regexp_encoding_flags(parser, flags, encoding);
}

/**
 * Parse a regular expression and validate its encoding, returning the flags of
 * its encoding. The offsets are where its content stops lining up with the
 * source.
 */
pm_node_flags_t
pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, const pm_regexp_offsets_t *offsets) {
    const pm_regexp_t regexp = {
        .parser = parser,
        .source = pm_string_source(&node->unescaped),
        .size = pm_string_length(&node->unescaped),
        .encoding = parser->encoding,
        .flags = PM_NODE_FLAGS(node),
        .location = node->base.location,
        .unlexed = false
    };

    const pm_node_t *match_receiver = parser->current.type == PM_TOKEN_EQUAL_TILDE ? (const pm_node_t *) node : NULL;
    return pm_regexp_validate(&regexp, offsets, node->content_loc.start, match_receiver);
}

/**
 * Strings joined into one piece of content, along with its encoding.
 *
 * The strings are the literal parts of a regular expression, or the parts of
 * a string that it interpolates. The content takes the encoding of the first
 * string with a non-ASCII character. Every later string with a non-ASCII
 * character must be in that same encoding.
 */
typedef struct {
    /** The parser that the regular expression is in. */
    const pm_parser_t *parser;

    /** The bytes of the content. */
    pm_buffer_t buffer;

    /** The encoding of the content so far, or NULL before its first string. */
    const pm_encoding_t *encoding;

    /** Whether the content so far is all ASCII. */
    bool ascii_only;

    /**
     * The encoding of the first string that is not ASCII and is in another
     * encoding than the content before it, so that the two cannot be joined.
     * NULL if every string can be.
     */
    const pm_encoding_t *incompatible;
} pm_regexp_joined_t;

/**
 * Return the encoding of a string node. That is UTF-8 or binary if the string
 * forces one, and the source encoding otherwise.
 */
static const pm_encoding_t *
pm_regexp_string_encoding(const pm_parser_t *parser, const pm_string_node_t *node) {
    if (PM_NODE_FLAG_P(node, PM_STRING_FLAGS_FORCED_UTF8_ENCODING)) return PM_ENCODING_UTF_8_ENTRY;
    if (PM_NODE_FLAG_P(node, PM_STRING_FLAGS_FORCED_BINARY_ENCODING)) return PM_ENCODING_ASCII_8BIT_ENTRY;
    return parser->encoding;
}

/**
 * Join the given content, in the given encoding, to the content so far.
 */
static void
pm_regexp_join(pm_regexp_joined_t *joined, const uint8_t *source, size_t size, const pm_encoding_t *encoding) {
    pm_string_t content;
    pm_string_shared_init(&content, source, source + size);
    bool ascii_only = pm_string_ascii_only_p(&content);

    if (joined->encoding == NULL) {
        joined->encoding = encoding;
        joined->ascii_only = ascii_only;
    } else if (!ascii_only) {
        if (joined->ascii_only) {
            joined->encoding = encoding;
            joined->ascii_only = false;
        } else if (encoding != joined->encoding && joined->incompatible == NULL) {
            joined->incompatible = encoding;
        }
    }

    pm_buffer_append_string(&joined->buffer, (const char *) source, size);
}

/**
 * Join the given parts to the content. An interpolated string is joined part
 * by part. Every part must have a value known while parsing.
 */
static void
pm_regexp_join_string_parts(pm_regexp_joined_t *joined, const pm_node_list_t *parts) {
    for (size_t index = 0; index < parts->size; index++) {
        const pm_node_t *part = parts->nodes[index];

        switch (PM_NODE_TYPE(part)) {
            case PM_STRING_NODE: {
                const pm_string_node_t *string = (const pm_string_node_t *) part;
                pm_regexp_join(joined, pm_string_source(&string->unescaped), pm_string_length(&string->unescaped), pm_regexp_string_encoding(joined->parser, string));
                break;
            }
            case PM_INTERPOLATED_STRING_NODE:
                pm_regexp_join_string_parts(joined, &((const pm_interpolated_string_node_t *) part)->parts);
                break;
            case PM_EMBEDDED_STATEMENTS_NODE:
                pm_regexp_join_string_parts(joined, &((const pm_embedded_statements_node_t *) part)->statements->body);
                break;
            default:
                PRISM_ASSERT(false && "unexpected part of a string whose value is known");
                break;
        }
    }
}

/**
 * Report that two strings cannot be joined, because their encodings differ.
 */
static void
pm_regexp_error_incompatible(pm_parser_t *parser, pm_location_t location, const pm_encoding_t *left, const pm_encoding_t *right) {
    pm_diagnostic_list_append_slice_slice(
        &parser->metadata_arena,
        &parser->error_list,
        location.start,
        location.length,
        PM_ERR_REGEXP_INTERPOLATION_ENCODING,
        pm_diagnostic_string(left->name),
        pm_diagnostic_string(right->name)
    );
}

/**
 * A literal part of a regular expression with interpolation. That is either
 * the regular expression's own text, or an interpolated string whose value is
 * known while parsing. Each part is checked as a regular expression of its own.
 */
typedef struct {
    /** The part as a regular expression of its own. */
    pm_regexp_t regexp;

    /**
     * If the part interpolates an interpolated string, its parts are joined
     * here, and the buffer holds the content of the part.
     */
    pm_regexp_joined_t joined;
} pm_regexp_part_t;

/**
 * Read one part of a regular expression with interpolation into a literal
 * part. Return false if the part is not literal, like #{x}.
 *
 * The flags are the flags of the regular expression.
 */
static bool
pm_regexp_part_init(pm_regexp_part_t *part, pm_parser_t *parser, pm_node_flags_t flags, const pm_node_t *node) {
    part->joined = (pm_regexp_joined_t) { .parser = parser, .buffer = { 0 }, .encoding = NULL, .ascii_only = true, .incompatible = NULL };

    /* The lexer already reported invalid characters in the regular
     * expression's own text. Nothing has checked the value of a string that
     * it interpolates yet. */
    bool unlexed = false;
    if (PM_NODE_TYPE_P(node, PM_EMBEDDED_STATEMENTS_NODE)) {
        const pm_statements_node_t *statements = ((const pm_embedded_statements_node_t *) node)->statements;
        if (statements == NULL || statements->body.size != 1) return false;

        node = statements->body.nodes[0];
        unlexed = true;
    }

    const uint8_t *source;
    size_t size;
    const pm_encoding_t *encoding;

    switch (PM_NODE_TYPE(node)) {
        case PM_STRING_NODE: {
            const pm_string_node_t *string = (const pm_string_node_t *) node;
            source = pm_string_source(&string->unescaped);
            size = pm_string_length(&string->unescaped);
            encoding = pm_regexp_string_encoding(parser, string);
            break;
        }
        case PM_INTERPOLATED_STRING_NODE: {
            if (!PM_NODE_FLAG_P(node, PM_INTERPOLATED_STRING_NODE_FLAGS_STATIC_VALUE)) return false;
            pm_regexp_join_string_parts(&part->joined, &((const pm_interpolated_string_node_t *) node)->parts);

            source = (const uint8_t *) pm_buffer_value(&part->joined.buffer);
            size = pm_buffer_length(&part->joined.buffer);
            encoding = (part->joined.encoding == NULL) ? parser->encoding : part->joined.encoding;
            break;
        }
        default:
            return false;
    }

    /* In a US-ASCII source, a part of a regular expression without an
     * encoding option is binary, even the value of a UTF-8 string like
     * "あ". So the parts never conflict, and they join as binary. */
    const pm_encoding_t *option_encoding;
    if (parser->encoding == PM_ENCODING_US_ASCII_ENTRY && pm_regexp_encoding_option(flags, &option_encoding) == '\0') {
        encoding = PM_ENCODING_ASCII_8BIT_ENTRY;
    }

    /* Ruby reads each part without the options m, i, and x, so a part's
     * errors do not show them. */
    part->regexp = (pm_regexp_t) {
        .parser = parser,
        .source = source,
        .size = size,
        .encoding = encoding,
        .flags = flags & (pm_node_flags_t) ~(PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE | PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE | PM_REGULAR_EXPRESSION_FLAGS_EXTENDED),
        .location = node->location,
        .unlexed = unlexed
    };

    return true;
}

/**
 * Release what a literal part holds.
 */
static void
pm_regexp_part_cleanup(pm_regexp_part_t *part) {
    pm_buffer_cleanup(&part->joined.buffer);
}

/**
 * Check the escapes of one literal part on its own, without the options of the
 * regular expression. That way a comment under /x does not hide an escape.
 * Return whether the escapes are valid. If not, the error has been reported.
 */
static bool
pm_regexp_part_escapes_valid_p(const pm_regexp_t *regexp) {
    const uint8_t *source = regexp->source;
    if (!pm_regexp_preprocess_needed_p(source, source + regexp->size)) return true;

    const pm_encoding_t *option_encoding;
    pm_regexp_encoding_option(regexp->flags, &option_encoding);

    pm_regexp_preprocessor_t preprocessor = {
        .regexp = regexp,
        .end = source + regexp->size,
        .encoding = pm_regexp_read_encoding(regexp, option_encoding),
        .fixed_encoding = NULL,
        .has_property = false,
        .pattern = { 0 },
        .written = source,
        .rewritten = false,
        .offsets = { 0 }
    };

    const uint8_t *cursor = source;
    bool valid = pm_regexp_preprocess_scan(&preprocessor, &cursor, false, false, 0);

    pm_buffer_cleanup(&preprocessor.pattern);
    return valid;
}

/**
 * Validate a regular expression with interpolation, one literal part at a
 * time.
 *
 * For each part, check the encoding option against it, unless the regular
 * expression is a static literal. Then check the escapes of the part. Only the
 * first error in the escapes is reported.
 *
 * If it is a static literal, join its parts and validate the result as one
 * regular expression.
 */
void
pm_regexp_parse_interpolated(pm_parser_t *parser, const pm_interpolated_regular_expression_node_t *node) {
    pm_node_flags_t flags = PM_NODE_FLAGS(node);
    bool is_static = PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL);
    const pm_node_list_t *parts = &node->parts;
    /* A heredoc can split a regexp into several literal tokens. Those can
     * still introduce locals, unlike a regexp with actual interpolation. */
    bool match_receiver = parser->current.type == PM_TOKEN_EQUAL_TILDE;

    /* Each part that does not match the option is its own error, so the
     * option is checked against every part, even after an error. */
    const pm_encoding_t *option_encoding;
    bool check_option = !is_static && pm_regexp_encoding_option(flags, &option_encoding) != '\0';

    pm_regexp_joined_t joined = { .parser = parser, .buffer = { 0 }, .encoding = NULL, .ascii_only = true, .incompatible = NULL };
    bool valid = true;

    for (size_t index = 0; index < parts->size && (valid || check_option); index++) {
        match_receiver = match_receiver && PM_NODE_TYPE_P(parts->nodes[index], PM_STRING_NODE);
        pm_regexp_part_t part;
        if (!pm_regexp_part_init(&part, parser, flags, parts->nodes[index])) continue;

        if (check_option && part.joined.incompatible == NULL) pm_regexp_check_option(&part.regexp);

        /* After the first error, only the option is checked. */
        if (valid) {
            if (part.joined.incompatible != NULL) {
                pm_regexp_error_incompatible(parser, part.regexp.location, part.joined.encoding, part.joined.incompatible);
                valid = false;
            } else if (!pm_regexp_part_escapes_valid_p(&part.regexp)) {
                valid = false;
            } else if (is_static) {
                pm_regexp_join(&joined, part.regexp.source, part.regexp.size, part.regexp.encoding);
            }
        }

        pm_regexp_part_cleanup(&part);
    }

    if (valid && is_static) {
        if (joined.incompatible != NULL) {
            pm_regexp_error_incompatible(parser, node->base.location, joined.encoding, joined.incompatible);
        } else {
            /* Every part has been checked on its own. Any invalid character
             * left is in the regular expression's own text, and the lexer
             * reported it. The joined content does not line up with the
             * source, so errors are reported at the whole regular expression. */
            const pm_regexp_t regexp = {
                .parser = parser,
                .source = (const uint8_t *) pm_buffer_value(&joined.buffer),
                .size = pm_buffer_length(&joined.buffer),
                .encoding = (joined.encoding == NULL) ? parser->encoding : joined.encoding,
                .flags = flags,
                .location = node->base.location,
                .unlexed = false
            };

            pm_regexp_validate(&regexp, NULL, 0, match_receiver ? (const pm_node_t *) node : NULL);
        }
    }

    pm_buffer_cleanup(&joined.buffer);
}
