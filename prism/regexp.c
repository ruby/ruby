#include "prism/internal/regexp.h"

#include "prism/compiler/inline.h"
#include "prism/compiler/fallthrough.h"
#include "prism/internal/assert.h"
#include "prism/internal/buffer.h"
#include "prism/internal/char.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/memchr.h"
#include "prism/internal/parser.h"
#include "prism/internal/stringy.h"
#include "prism/internal/strncasecmp.h"

#include <string.h>

/** The maximum depth of nested groups allowed in a regular expression. */
#define PM_REGEXP_PARSE_DEPTH_MAX 4096

/**
 * This is the parser that is going to handle parsing regular expressions.
 */
typedef struct {
    /** The parser that is currently being used. */
    pm_parser_t *parser;

    /** A pointer to the start of the unescaped content that we are parsing. */
    const uint8_t *start;

    /** A pointer to the current position in the content. */
    const uint8_t *cursor;

    /** A pointer to the end of the content that we are parsing. */
    const uint8_t *end;

    /**
     * Where the content stops lining up with the source, for reporting errors
     * at their place in the source. NULL when errors are not reported.
     */
    const pm_regexp_offsets_t *offsets;

    /** The offset in the source of the start of the content. */
    uint32_t source_start;

    /** The encoding of the source. */
    const pm_encoding_t *encoding;

    /** The callback to call when a named capture group is found. */
    pm_regexp_name_callback_t name_callback;

    /** The data to pass to the name callback. */
    void *name_data;

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

    /**
     * Whether syntax errors are reported. The named capture pass walks content
     * whose errors the validation pass has already reported, and that may be
     * joined from several pieces with no offsets back to the source, so it
     * reports nothing.
     */
    bool report_errors;
} pm_regexp_parser_t;

/**
 * Return the offset in the source of the given position in the content, as the
 * start (or else the end) of a range. Each byte after a recorded place is at
 * the same distance from it in the source as in the content, and a position in
 * text that the lexer wrote in place of an escape is kept within that escape.
 * At a recorded place, the escape before it wrote nothing at that position, so
 * a range that starts there starts at the escape, and one that ends there ends
 * after it.
 */
static uint32_t
pm_regexp_source_offset(const pm_regexp_parser_t *parser, const uint8_t *position, bool start) {
    const pm_regexp_offset_t *values = parser->offsets->values;
    size_t size = parser->offsets->size;
    uint32_t content = (uint32_t) (position - parser->start);

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

    uint32_t source = (from == 0) ? (parser->source_start + content) : (values[from - 1].source + (content - values[from - 1].content));
    if (from < size && source > values[from].source) source = values[from].source;

    return source;
}

/**
 * Append a syntax error to the parser's error list, at the place in the source
 * of the given range of the content. Errors are only reported when
 * report_errors is set.
 */
static PRISM_INLINE void
pm_regexp_parse_error(pm_regexp_parser_t *regexp_parser, const uint8_t *start, const uint8_t *end, const char *message) {
    if (regexp_parser->report_errors) {
        pm_parser_t *parser = regexp_parser->parser;
        uint32_t source_start = pm_regexp_source_offset(regexp_parser, start, true);
        uint32_t source_end = pm_regexp_source_offset(regexp_parser, end, false);
        pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, source_start, source_end - source_start, PM_ERR_REGEXP_PARSE_ERROR, message);
    }
}

/**
 * Report that the stack budget was used up while parsing the regular
 * expression. Unlike other errors, this is reported even when report_errors is
 * not set, because giving up early there would silently drop the named
 * captures that the rest of the regular expression defines. In that case there
 * are no offsets into the source, so the error is reported at the token that
 * the parser is on instead.
 */
static void
pm_regexp_parse_stack_exhausted(pm_regexp_parser_t *regexp_parser) {
    pm_parser_t *parser = regexp_parser->parser;

    if (regexp_parser->report_errors) {
        uint32_t source_start = pm_regexp_source_offset(regexp_parser, regexp_parser->start, true);
        uint32_t source_end = pm_regexp_source_offset(regexp_parser, regexp_parser->end, false);
        pm_parser_err_stack_exhausted(parser, source_start, source_end - source_start);
    } else {
        pm_parser_err_stack_exhausted(parser, (uint32_t) (parser->current.start - parser->start), (uint32_t) (parser->current.end - parser->current.start));
    }
}

/**
 * This appends a new string to the list of named captures. This function
 * assumes the caller has already checked the validity of the name callback.
 */
static void
pm_regexp_parser_named_capture(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    pm_string_t string;
    pm_string_shared_init(&string, start, end);
    parser->name_callback(parser->parser, &string, parser->name_data);
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
 * This advances the current token to the next instance of the given character.
 */
static bool
pm_regexp_char_find(pm_regexp_parser_t *parser, uint8_t value) {
    if (pm_regexp_char_is_eof(parser)) {
        return false;
    }

    const uint8_t *end = (const uint8_t *) pm_memchr(parser->cursor, value, (size_t) (parser->end - parser->cursor), parser->encoding_changed, parser->encoding);
    if (end == NULL) {
        return false;
    }

    parser->cursor = end + 1;
    return true;
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
 * Range quantifiers are a special class of quantifiers that look like
 *
 * * {digit}
 * * {digit,}
 * * {digit,digit}
 * * {,digit}
 *
 * If there are any spaces in between, then this just becomes a regular
 * character match expression and we have to backtrack. So when this function
 * first starts running, we'll create a "save" point and then attempt to parse
 * the quantifier. If it fails, we'll restore the save point and return.
 *
 * To properly track everything, we're going to build a little state machine.
 * It looks something like the following:
 *
 *                  +-------+                 +---------+ ------------+
 * ---- lbrace ---> | start | ---- digit ---> | minimum |             |
 *                  +-------+                 +---------+ <--- digit -+
 *                      |                       |    |
 *   +-------+          |                       |  rbrace
 *   | comma | <----- comma  +---- comma -------+    |
 *   +-------+               V                       V
 *      |             +---------+               +---------+
 *      +-- digit --> | maximum | -- rbrace --> || final ||
 *                    +---------+               +---------+
 *                    |         ^
 *                    +- digit -+
 *
 * Note that by the time we've hit this function, the lbrace has already been
 * consumed so we're in the start state.
 */
static bool
pm_regexp_parse_range_quantifier(pm_regexp_parser_t *parser) {
    const uint8_t *savepoint = parser->cursor;

    enum {
        PM_REGEXP_RANGE_QUANTIFIER_STATE_START,
        PM_REGEXP_RANGE_QUANTIFIER_STATE_MINIMUM,
        PM_REGEXP_RANGE_QUANTIFIER_STATE_MAXIMUM,
        PM_REGEXP_RANGE_QUANTIFIER_STATE_COMMA
    } state = PM_REGEXP_RANGE_QUANTIFIER_STATE_START;

    while (1) {
        if (parser->cursor >= parser->end) {
            parser->cursor = savepoint;
            return true;
        }

        switch (state) {
            case PM_REGEXP_RANGE_QUANTIFIER_STATE_START:
                switch (*parser->cursor) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                        parser->cursor++;
                        state = PM_REGEXP_RANGE_QUANTIFIER_STATE_MINIMUM;
                        break;
                    case ',':
                        parser->cursor++;
                        state = PM_REGEXP_RANGE_QUANTIFIER_STATE_COMMA;
                        break;
                    default:
                        parser->cursor = savepoint;
                        return true;
                }
                break;
            case PM_REGEXP_RANGE_QUANTIFIER_STATE_MINIMUM:
                switch (*parser->cursor) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                        parser->cursor++;
                        break;
                    case ',':
                        parser->cursor++;
                        state = PM_REGEXP_RANGE_QUANTIFIER_STATE_MAXIMUM;
                        break;
                    case '}':
                        parser->cursor++;
                        return true;
                    default:
                        parser->cursor = savepoint;
                        return true;
                }
                break;
            case PM_REGEXP_RANGE_QUANTIFIER_STATE_COMMA:
                switch (*parser->cursor) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                        parser->cursor++;
                        state = PM_REGEXP_RANGE_QUANTIFIER_STATE_MAXIMUM;
                        break;
                    default:
                        parser->cursor = savepoint;
                        return true;
                }
                break;
            case PM_REGEXP_RANGE_QUANTIFIER_STATE_MAXIMUM:
                switch (*parser->cursor) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
                        parser->cursor++;
                        break;
                    case '}':
                        parser->cursor++;
                        return true;
                    default:
                        parser->cursor = savepoint;
                        return true;
                }
                break;
        }
    }

    return true;
}

/**
 * quantifier : star-quantifier
 *            | plus-quantifier
 *            | optional-quantifier
 *            | range-quantifier
 *            | <empty>
 *            ;
 */
static bool
pm_regexp_parse_quantifier(pm_regexp_parser_t *parser) {
    while (!pm_regexp_char_is_eof(parser)) {
        switch (*parser->cursor) {
            case '*':
            case '+':
            case '?':
                parser->cursor++;
                break;
            case '{':
                parser->cursor++;
                if (!pm_regexp_parse_range_quantifier(parser)) return false;
                break;
            default:
                // In this case there is no quantifier.
                return true;
        }
    }

    return true;
}

/**
 * match-posix-class : '[' '[' ':' '^'? CHAR+ ':' ']' ']'
 *                   ;
 */
static bool
pm_regexp_parse_posix_class(pm_regexp_parser_t *parser) {
    if (!pm_regexp_char_expect(parser, ':')) {
        return false;
    }

    pm_regexp_char_accept(parser, '^');

    return (
        pm_regexp_char_find(parser, ':') &&
        pm_regexp_char_expect(parser, ']') &&
        pm_regexp_char_expect(parser, ']')
    );
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

    if (parser->cursor + 1 < parser->end && parser->cursor[1] == '{') {
        const uint8_t *name_start = parser->cursor + 2;
        const uint8_t *search = name_start;

        while (search < parser->end && *search != '}') search++;

        if (search < parser->end) {
            size_t name_length = (size_t) (search - name_start);
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

            parser->cursor = search + 1; // skip past '}'
            return true;
        }
    }

    // Not a property escape, just skip the single character after '\'.
    parser->cursor++;
    return false;
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

// Forward declaration because character sets can be nested.
static bool
pm_regexp_parse_lbracket(pm_regexp_parser_t *parser, uint16_t depth);

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
        default:
            parser->cursor++;
            break;
    }
}

/**
 * Skip the rest of the character that begins at the given byte, which the
 * cursor is just past, if it is a character of more than one byte. Its later
 * bytes may look like ASCII in some encodings, so they must not be read as
 * characters of their own. An invalid character, which the lexer has already
 * reported, is skipped a byte at a time.
 */
static void
pm_regexp_parse_multibyte_char(pm_regexp_parser_t *parser, const uint8_t *cursor) {
    if (*cursor >= 0x80 && parser->encoding_changed && pm_encoding_multibyte_p(parser->encoding)) {
        size_t width = pm_encoding_char_width(parser->encoding, cursor, (ptrdiff_t) (parser->end - cursor));
        if (width > 1) parser->cursor += width - 1;
    }
}

/**
 * match-char-set : '[' '^'? (match-range | match-char)* ']'
 *                ;
 */
static bool
pm_regexp_parse_character_set(pm_regexp_parser_t *parser, uint16_t depth) {
    pm_regexp_char_accept(parser, '^');

    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ']') {
        switch (*parser->cursor++) {
            case '[':
                if (!pm_regexp_parse_lbracket(parser, (uint16_t) (depth + 1))) return false;
                break;
            case '\\':
                pm_regexp_parse_backslash_escape(parser);
                break;
            default:
                pm_regexp_parse_multibyte_char(parser, parser->cursor - 1);
                break;
        }
    }

    return pm_regexp_char_expect(parser, ']');
}

/**
 * A left bracket can either mean a POSIX class or a character set.
 */
static bool
pm_regexp_parse_lbracket(pm_regexp_parser_t *parser, uint16_t depth) {
    if (depth >= PM_REGEXP_PARSE_DEPTH_MAX) {
        pm_regexp_parse_error(parser, parser->start, parser->end, "parse depth limit over");
        return false;
    }

    if (pm_parser_stack_exhausted(parser->parser)) {
        pm_regexp_parse_stack_exhausted(parser);
        return false;
    }

    if ((parser->cursor < parser->end) && parser->cursor[0] == ']') {
        parser->cursor++;
        pm_regexp_parse_error(parser, parser->cursor - 1, parser->cursor, "empty char-class");
        return true;
    }

    const uint8_t *reset = parser->cursor;

    if ((parser->cursor + 2 < parser->end) && parser->cursor[0] == '[' && parser->cursor[1] == ':') {
        parser->cursor++;
        if (pm_regexp_parse_posix_class(parser)) return true;

        parser->cursor = reset;
    }

    return pm_regexp_parse_character_set(parser, depth);
}

// Forward declaration here since parsing groups needs to go back up the grammar
// to parse expressions within them.
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser, uint16_t depth);

/**
 * These are the states of the options that are configurable on the regular
 * expression (or from within a group).
 */
typedef enum {
    PM_REGEXP_OPTION_STATE_INVALID,
    PM_REGEXP_OPTION_STATE_TOGGLEABLE,
    PM_REGEXP_OPTION_STATE_ADDABLE,
    PM_REGEXP_OPTION_STATE_ADDED,
    PM_REGEXP_OPTION_STATE_REMOVED
} pm_regexp_option_state_t;

// These are the options that are configurable on the regular expression (or
// from within a group).

/** The minimum character value for a regexp option slot. */
#define PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM 'a'

/** The maximum character value for a regexp option slot. */
#define PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM 'x'

/** The number of regexp option slots. */
#define PRISM_REGEXP_OPTION_STATE_SLOTS (PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM + 1)

/**
 * This is the set of options that are configurable on the regular expression.
 */
typedef struct {
    /** The current state of each option. */
    uint8_t values[PRISM_REGEXP_OPTION_STATE_SLOTS];
} pm_regexp_options_t;

/**
 * Initialize a new set of options to their default values.
 */
static void
pm_regexp_options_init(pm_regexp_options_t *options) {
    memset(options, PM_REGEXP_OPTION_STATE_INVALID, sizeof(uint8_t) * PRISM_REGEXP_OPTION_STATE_SLOTS);
    options->values['i' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_TOGGLEABLE;
    options->values['m' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_TOGGLEABLE;
    options->values['x' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_TOGGLEABLE;
    options->values['d' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_ADDABLE;
    options->values['a' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_ADDABLE;
    options->values['u' - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM] = PM_REGEXP_OPTION_STATE_ADDABLE;
}

/**
 * Attempt to add the given option to the set of options. Returns true if it was
 * added, false if it was already present.
 */
static bool
pm_regexp_options_add(pm_regexp_options_t *options, uint8_t key) {
    if (key >= PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM && key <= PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM) {
        key = (uint8_t) (key - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM);

        switch (options->values[key]) {
            case PM_REGEXP_OPTION_STATE_INVALID:
            case PM_REGEXP_OPTION_STATE_REMOVED:
                return false;
            case PM_REGEXP_OPTION_STATE_TOGGLEABLE:
            case PM_REGEXP_OPTION_STATE_ADDABLE:
                options->values[key] = PM_REGEXP_OPTION_STATE_ADDED;
                return true;
            case PM_REGEXP_OPTION_STATE_ADDED:
                return true;
        }
    }

    return false;
}

/**
 * Attempt to remove the given option from the set of options. Returns true if
 * it was removed, false if it was already absent.
 */
static bool
pm_regexp_options_remove(pm_regexp_options_t *options, uint8_t key) {
    if (key >= PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM && key <= PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM) {
        key = (uint8_t) (key - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM);

        switch (options->values[key]) {
            case PM_REGEXP_OPTION_STATE_INVALID:
            case PM_REGEXP_OPTION_STATE_ADDABLE:
                return false;
            case PM_REGEXP_OPTION_STATE_TOGGLEABLE:
            case PM_REGEXP_OPTION_STATE_ADDED:
            case PM_REGEXP_OPTION_STATE_REMOVED:
                options->values[key] = PM_REGEXP_OPTION_STATE_REMOVED;
                return true;
        }
    }

    return false;
}

/**
 * True if the given key is set in the options.
 */
static uint8_t
pm_regexp_options_state(pm_regexp_options_t *options, uint8_t key) {
    if (key >= PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM && key <= PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM) {
        key = (uint8_t) (key - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM);
        return options->values[key];
    }

    return false;
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
 */
static bool
pm_regexp_parse_group(pm_regexp_parser_t *parser, uint16_t depth) {
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

    pm_regexp_options_t options;
    pm_regexp_options_init(&options);

    // First, parse any options for the group.
    if (pm_regexp_char_accept(parser, '?')) {
        if (pm_regexp_char_is_eof(parser)) {
            pm_regexp_parse_error(parser, group_start, parser->cursor, "end pattern in group");
            return false;
        }

        switch (*parser->cursor) {
            case '#': { // inline comments
                parser->cursor++;
                if (pm_regexp_char_is_eof(parser)) {
                    pm_regexp_parse_error(parser, group_start, parser->cursor, "end pattern in group");
                    return false;
                }

                if (parser->encoding_changed && pm_encoding_multibyte_p(parser->encoding)) {
                    bool escaped = false;

                    // Here we're going to take a slow path and iterate through
                    // each multibyte character to find the close paren. We do
                    // this because \ can be a trailing byte in some encodings.
                    while (parser->cursor < parser->end) {
                        if (!escaped && *parser->cursor == ')') {
                            parser->cursor++;
                            return true;
                        }

                        size_t width = pm_encoding_char_width(parser->encoding, parser->cursor, (ptrdiff_t) (parser->end - parser->cursor));
                        if (width == 0) {
                            /* An invalid character, which the lexer has
                             * already reported, is skipped a byte at a
                             * time. */
                            if (*parser->cursor >= 0x80) {
                                parser->cursor++;
                                continue;
                            }
                            return false;
                        }

                        escaped = (width == 1) && (*parser->cursor == '\\');
                        parser->cursor += width;
                    }

                    return false;
                } else {
                    // Here we can take the fast path and use memchr to find the
                    // next ) because we are safe checking backward for \ since
                    // it cannot be a trailing character.
                    bool found = pm_regexp_char_find(parser, ')');

                    while (found && (parser->start <= parser->cursor - 2) && (*(parser->cursor - 2) == '\\')) {
                        found = pm_regexp_char_find(parser, ')');
                    }

                    return found;
                }
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
                    pm_regexp_parse_error(parser, group_start, parser->cursor, "end pattern with unmatched parenthesis");
                    return false;
                }

                switch (*parser->cursor) {
                    case '=': // positive lookbehind
                    case '!': // negative lookbehind
                        parser->cursor++;
                        break;
                    default: { // named capture group
                        const uint8_t *start = parser->cursor;
                        if (!pm_regexp_char_find(parser, '>')) {
                            return false;
                        }

                        if (parser->cursor - start == 1) {
                            pm_regexp_parse_error(parser, start, parser->cursor, "group name is empty");
                        }

                        if (parser->name_callback != NULL) {
                            pm_regexp_parser_named_capture(parser, start, parser->cursor - 1);
                        }

                        break;
                    }
                }
                break;
            case '\'': { // named capture group
                const uint8_t *start = ++parser->cursor;
                if (!pm_regexp_char_find(parser, '\'')) {
                    return false;
                }

                if (parser->name_callback != NULL) {
                    pm_regexp_parser_named_capture(parser, start, parser->cursor - 1);
                }

                break;
            }
            case '(': // conditional expression
                if (!pm_regexp_char_find(parser, ')')) {
                    return false;
                }
                break;
            case 'i': case 'm': case 'x': case 'd': case 'a': case 'u': // options
                while (!pm_regexp_char_is_eof(parser) && *parser->cursor != '-' && *parser->cursor != ':' && *parser->cursor != ')') {
                    if (!pm_regexp_options_add(&options, *parser->cursor)) {
                        return false;
                    }
                    parser->cursor++;
                }

                if (pm_regexp_char_is_eof(parser)) {
                    return false;
                }

                // If we are at the end of the group of options and there is no
                // subexpression, then we are going to be setting the options
                // for the parent group. In this case we are safe to return now.
                if (*parser->cursor == ')') {
                    if (pm_regexp_options_state(&options, 'x') == PM_REGEXP_OPTION_STATE_ADDED) {
                        parser->extended_mode = true;
                    }

                    parser->cursor++;
                    return true;
                }

                // If we hit a -, then we're done parsing options.
                if (*parser->cursor != '-') break;

                PRISM_FALLTHROUGH
            case '-':
                parser->cursor++;
                while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ':' && *parser->cursor != ')') {
                    if (!pm_regexp_options_remove(&options, *parser->cursor)) {
                        return false;
                    }
                    parser->cursor++;
                }

                if (pm_regexp_char_is_eof(parser)) {
                    return false;
                }

                // If we are at the end of the group of options and there is no
                // subexpression, then we are going to be setting the options
                // for the parent group. In this case we are safe to return now.
                if (*parser->cursor == ')') {
                    switch (pm_regexp_options_state(&options, 'x')) {
                        case PM_REGEXP_OPTION_STATE_ADDED:
                            parser->extended_mode = true;
                            break;
                        case PM_REGEXP_OPTION_STATE_REMOVED:
                            parser->extended_mode = false;
                            break;
                    }

                    parser->cursor++;
                    return true;
                }

                break;
            default:
                parser->cursor++;
                pm_regexp_parse_error(parser, parser->cursor - 1, parser->cursor, "undefined group option");
                break;
        }
    }

    bool extended_mode = parser->extended_mode;
    switch (pm_regexp_options_state(&options, 'x')) {
        case PM_REGEXP_OPTION_STATE_ADDED:
            parser->extended_mode = true;
            break;
        case PM_REGEXP_OPTION_STATE_REMOVED:
            parser->extended_mode = false;
            break;
    }

    // Now, parse the expressions within this group.
    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ')') {
        if (!pm_regexp_parse_expression(parser, (uint16_t) (depth + 1))) {
            parser->extended_mode = extended_mode;
            return false;
        }
        pm_regexp_char_accept(parser, '|');
    }

    // Finally, make sure we have a closing parenthesis.
    parser->extended_mode = extended_mode;
    if (pm_regexp_char_expect(parser, ')')) return true;

    pm_regexp_parse_error(parser, group_start, parser->cursor, "end pattern with unmatched parenthesis");
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
        case '(':
            parser->cursor++;
            return pm_regexp_parse_group(parser, depth) && pm_regexp_parse_quantifier(parser);
        case '[':
            parser->cursor++;
            return pm_regexp_parse_lbracket(parser, depth) && pm_regexp_parse_quantifier(parser);
        case '*':
        case '?':
        case '+':
            parser->cursor++;
            pm_regexp_parse_error(parser, parser->cursor - 1, parser->cursor, "target of repeat operator is not specified");
            return true;
        case ')':
            parser->cursor++;
            pm_regexp_parse_error(parser, parser->cursor - 1, parser->cursor, "unmatched close parenthesis");
            return true;
        case '#':
            if (parser->extended_mode) {
                if (!pm_regexp_char_find(parser, '\n')) parser->cursor = parser->end;
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
 * expression : item+
 *            ;
 */
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser, uint16_t depth) {
    if (depth >= PM_REGEXP_PARSE_DEPTH_MAX) {
        pm_regexp_parse_error(parser, parser->start, parser->end, "parse depth limit over");
        return false;
    }

    if (!pm_regexp_parse_item(parser, depth)) {
        return false;
    }

    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ')' && *parser->cursor != '|') {
        if (!pm_regexp_parse_item(parser, depth)) {
            return false;
        }
    }

    return true;
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
        if (pm_regexp_char_is_eof(parser)) return true;
        if (!pm_regexp_parse_expression(parser, 0)) return false;
    } while (pm_regexp_char_accept(parser, '|'));

    return pm_regexp_char_is_eof(parser);
}

// ---------------------------------------------------------------------------
// Encoding validation
// ---------------------------------------------------------------------------

/**
 * Format regexp source content for use in error messages, hex-escaping
 * non-ASCII bytes.
 */
static void
pm_regexp_format_for_error(pm_buffer_t *buffer, const pm_encoding_t *encoding, const uint8_t *source, size_t length) {
    size_t index = 0;

    if (encoding == PM_ENCODING_UTF_8_ENTRY) {
        pm_buffer_append_string(buffer, (const char *) source, length);
        return;
    }

    while (index < length) {
        if (source[index] < 0x80) {
            pm_buffer_append_byte(buffer, source[index]);
            index++;
        } else if (pm_encoding_multibyte_p(encoding)) {
            size_t width = pm_encoding_char_width(encoding, source + index, (ptrdiff_t) (length - index));

            if (width > 1) {
                PM_BUFFER_APPEND_LITERAL(buffer, "\\x{");
                for (size_t i = 0; i < width; i++) {
                    pm_buffer_append_format(buffer, "%02X", source[index + i]);
                }
                pm_buffer_append_byte(buffer, '}');
                index += width;
            } else {
                pm_buffer_append_format(buffer, "\\x%02X", source[index]);
                index++;
            }
        } else {
            pm_buffer_append_format(buffer, "\\x%02X", source[index]);
            index++;
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

    /** The flags of the regular expression, which hold its options. */
    pm_node_flags_t flags;

    /** Where errors about the regular expression as a whole are reported. */
    pm_location_t location;
} pm_regexp_t;

/**
 * Append an error to the regular expression as a whole, followed by its
 * content, which is how errors are reported once its pattern has been read but
 * before it is parsed. The message is written out with the content, since the
 * same error kind holds any of these messages.
 */
static void
pm_regexp_error_with_content(const pm_regexp_t *regexp, const char *message) {
    pm_parser_t *parser = regexp->parser;

    pm_buffer_t buffer = { 0 };
    pm_buffer_append_string(&buffer, message, strlen(message));
    pm_buffer_append_string(&buffer, ": /", 3);
    pm_regexp_format_for_error(&buffer, parser->encoding, regexp->source, regexp->size);
    pm_buffer_append_byte(&buffer, '/');
    pm_buffer_append_byte(&buffer, '\0');

    pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, regexp->location.start, regexp->location.length, PM_ERR_REGEXP_PARSE_ERROR, pm_buffer_value(&buffer));
    pm_buffer_cleanup(&buffer);
}

/**
 * Append an error of the given kind to the regular expression as a whole, where
 * the message of that kind ends with the content.
 */
static void
pm_regexp_error_kind_with_content(const pm_regexp_t *regexp, pm_diagnostic_id_t diag_id) {
    pm_parser_t *parser = regexp->parser;

    pm_buffer_t buffer = { 0 };
    pm_regexp_format_for_error(&buffer, parser->encoding, regexp->source, regexp->size);
    pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, regexp->location.start, regexp->location.length, diag_id, (int) buffer.length, pm_buffer_value(&buffer));
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
 * Check the encoding option of a regular expression (/n, /u, /e, or /s)
 * against the characters written in it, before any of its escapes are read.
 * Every character that is not ASCII must already be in the encoding that the
 * option names, so the source encoding must be that one. When it is not, the
 * regular expression is still validated, in the source encoding, except with
 * /n, where such a character is an error of its own and nothing more is
 * checked.
 *
 * Returns the encoding that the rest of the regular expression is read in, or
 * NULL if nothing more is checked. That is the encoding of the option, if any.
 * Without one it is the source encoding, except that content in a US-ASCII
 * source is read as binary, since any byte that is not ASCII in it is invalid
 * and has already been reported.
 */
static const pm_encoding_t *
pm_regexp_check_option(const pm_regexp_t *regexp) {
    pm_parser_t *parser = regexp->parser;
    pm_node_flags_t flags = regexp->flags;
    const pm_encoding_t *encoding;
    char option;

    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        option = 'n';
        encoding = PM_ENCODING_ASCII_8BIT_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        option = 'u';
        encoding = PM_ENCODING_UTF_8_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        option = 'e';
        encoding = PM_ENCODING_EUC_JP_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        option = 's';
        encoding = PM_ENCODING_WINDOWS_31J_ENTRY;
    } else {
        return (parser->encoding == PM_ENCODING_US_ASCII_ENTRY) ? PM_ENCODING_ASCII_8BIT_ENTRY : parser->encoding;
    }

    if (parser->encoding == encoding || !pm_regexp_non_ascii_p(parser->encoding, regexp->source, regexp->source + regexp->size)) return encoding;

    pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, regexp->location.start, regexp->location.length, PM_ERR_REGEXP_ENCODING_OPTION_MISMATCH, option, parser->encoding->name);
    if (option != 'n') return parser->encoding;

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
} pm_regexp_preprocessor_t;

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
 * Return the value of the digits at the cursor in the given base, reading at
 * most maximum of them, and set length to how many were read.
 */
static uint32_t
pm_regexp_preprocess_digits(const uint8_t *cursor, const uint8_t *end, uint32_t maximum, uint32_t base, uint32_t *length) {
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
        pm_regexp_error_with_content(preprocessor->regexp, "too short escaped multibyte character");
        return -1;
    }

    if (cursor == end) {
        pm_regexp_error_with_content(preprocessor->regexp, "too short escape sequence");
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
            code = pm_regexp_preprocess_digits(cursor - 1, end, 3, 8, &length);
            cursor += length - 1;
            break;
        case 'x':
            code = pm_regexp_preprocess_digits(cursor, end, 2, 16, &length);
            if (length == 0) {
                pm_regexp_error_with_content(preprocessor->regexp, "invalid hex escape");
                return -1;
            }
            cursor += length;
            break;
        default:
            pm_regexp_error_with_content(preprocessor->regexp, "unexpected escape sequence");
            return -1;
    }

    if (code > 0xFF) {
        pm_regexp_error_with_content(preprocessor->regexp, "invalid escape code");
        return -1;
    }

    *parent_cursor = cursor;
    return (int) code;
}

/**
 * Read the escape of a byte at the cursor, along with the escapes after it
 * that complete the character it begins. A character that is not ASCII fixes
 * the regular expression to the encoding that the content is read in.
 */
static bool
pm_regexp_preprocess_escaped_char(pm_regexp_preprocessor_t *preprocessor, const uint8_t **parent_cursor) {
    const pm_encoding_t *encoding = preprocessor->encoding;
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
    }

    return true;
}

/**
 * Read a code point of a \u escape. One that is not ASCII fixes the regular
 * expression to UTF-8.
 */
static bool
pm_regexp_preprocess_code_point(pm_regexp_preprocessor_t *preprocessor, uint32_t value) {
    if ((value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
        pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_INVALID_UNICODE_RANGE);
        return false;
    }

    if (value >= 0x80) {
        if (!pm_regexp_preprocess_fix_encoding(preprocessor, PM_ENCODING_UTF_8_ENTRY)) {
            pm_regexp_error_kind_with_content(preprocessor->regexp, PM_ERR_REGEXP_UTF8_CHAR_NON_UTF8_REGEXP);
            return false;
        }
    }

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
        uint32_t value = pm_regexp_preprocess_digits(cursor, end, UINT32_MAX, 16, &length);
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
        pm_regexp_error_with_content(preprocessor->regexp, "invalid Unicode list");
        return false;
    }

    *parent_cursor = cursor;
    return true;
}

/**
 * Whether the escapes of the content need to be read at all. Only a byte that
 * is not ASCII, or an escape of a byte, a code point, or a property, can fix
 * the encoding or be an error, and most regular expressions have neither, so
 * this quicker check lets them skip the reading.
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
 * UTF-8 to UTF-8.
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
                    pm_regexp_error_with_content(preprocessor->regexp, "too short escape sequence");
                    return false;
                }

                if (*cursor >= 0x80) {
                    size_t width = pm_encoding_char_width(encoding, cursor, end - cursor);
                    if (width == 0) {
                        cursor++;
                        break;
                    }

                    /* A backslash before a character of more than one byte
                     * is read along with the character. */
                    if (width > 1) {
                        cursor += width;
                        if (!pm_regexp_preprocess_fix_encoding(preprocessor, encoding)) {
                            pm_regexp_error_with_content(preprocessor->regexp, "non ASCII character in UTF-8 regexp");
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
                        if (pm_regexp_preprocess_digits(cursor - 1, end, 3, 8, &length) <= 0x7F) break;
                    }
                    PRISM_FALLTHROUGH
                    case '0': case 'x':
                        cursor -= 2;
                        if (!pm_regexp_preprocess_escaped_char(preprocessor, &cursor)) return false;
                        break;
                    case 'u':
                        if (cursor == end) {
                            pm_regexp_error_with_content(preprocessor->regexp, "too short escape sequence");
                            return false;
                        }

                        if (*cursor == '{') {
                            cursor++;
                            if (!pm_regexp_preprocess_code_point_list(preprocessor, &cursor)) return false;
                        } else {
                            uint32_t length;
                            uint32_t value = pm_regexp_preprocess_digits(cursor, end, 4, 16, &length);
                            if (length != 4) {
                                pm_regexp_error_with_content(preprocessor->regexp, "invalid Unicode escape");
                                return false;
                            }

                            cursor += 4;
                            if (!pm_regexp_preprocess_code_point(preprocessor, value)) return false;
                        }
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
                    while (cursor < end && *cursor != '\n') {
                        if (*cursor >= 0x80 && preprocessor->fixed_encoding == NULL && encoding == PM_ENCODING_UTF_8_ENTRY) {
                            preprocessor->fixed_encoding = encoding;
                        }
                        cursor++;
                    }
                    if (cursor < end) cursor++;
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
                                cursor += (width == 0) ? 1 : width;
                            }
                        }
                    }

                    /* An unterminated comment is read as the text that it
                     * holds, which is a syntax error of the pattern. */
                    if (!closed) cursor = comment;
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
                 * first byte of a character that is not ASCII. An invalid
                 * character is an error of its own, reported where it is
                 * lexed, so it is skipped a byte at a time. */
                size_t width = pm_encoding_char_width(encoding, cursor - 1, end - (cursor - 1));
                if (width == 0) break;

                cursor += width - 1;
                if (!pm_regexp_preprocess_fix_encoding(preprocessor, encoding)) {
                    pm_regexp_error_with_content(preprocessor->regexp, "non ASCII character in UTF-8 regexp");
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

    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        implied = PM_ENCODING_ASCII_8BIT_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        implied = PM_ENCODING_UTF_8_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        implied = PM_ENCODING_EUC_JP_ENTRY;
    } else if (flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        implied = PM_ENCODING_WINDOWS_31J_ENTRY;
    } else {
        implied = parser->encoding;
    }

    if (encoding == implied) return 0;
    if (encoding == PM_ENCODING_UTF_8_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_UTF8_ENCODING;
    if (encoding == PM_ENCODING_ASCII_8BIT_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_BINARY_ENCODING;
    if (encoding == PM_ENCODING_US_ASCII_ENTRY) return PM_REGULAR_EXPRESSION_FLAGS_FORCED_US_ASCII_ENCODING;
    return 0;
}

/**
 * Check the property escapes that the pattern holds against the encoding
 * option of the regular expression. With /n only POSIX properties are valid,
 * and with /e or /s script properties are as well.
 */
static void
pm_regexp_check_properties(const pm_regexp_t *regexp, const pm_regexp_parser_t *regexp_parser) {
    pm_parser_t *parser = regexp->parser;
    pm_node_flags_t flags = regexp->flags;
    const uint8_t *name = NULL;
    size_t length = 0;

    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        name = regexp_parser->property_name;
        length = regexp_parser->property_name_length;
    } else if (flags & (PM_REGULAR_EXPRESSION_FLAGS_EUC_JP | PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J)) {
        name = regexp_parser->unicode_property_name;
        length = regexp_parser->unicode_property_name_length;
    }

    if (name == NULL) return;

    pm_buffer_t formatted = { 0 };
    pm_regexp_format_for_error(&formatted, parser->encoding, regexp->source, regexp->size);
    pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, regexp->location.start, regexp->location.length, PM_ERR_REGEXP_INVALID_CHAR_PROPERTY, (int) length, (const char *) name, (int) formatted.length, (const char *) formatted.value);
    pm_buffer_cleanup(&formatted);
}

/**
 * Validate a regular expression, in the order that Ruby reads it, which stops
 * at the first of these steps that finds an error:
 *
 * 1. Check its encoding option against the characters written in it.
 * 2. Read its escapes, to find the encoding that they and its characters fix
 *    it to.
 * 3. Resolve its encoding from that and its options.
 * 4. Parse its pattern.
 *
 * Each of these reads the content, where the lexer keeps the escapes that the
 * regular expression engine reads as their text, so that escaped bytes can be
 * told from literal ones. The offsets map places in the content to places in
 * the source, starting at the given offset, for errors in the pattern. Returns
 * the flags of the encoding of the regular expression.
 */
static pm_node_flags_t
pm_regexp_validate(const pm_regexp_t *regexp, const pm_regexp_offsets_t *offsets, uint32_t source_start) {
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
        .has_property = false
    };

    const uint8_t *cursor = source;
    if (pm_regexp_preprocess_needed_p(source, source + size) && !pm_regexp_preprocess_scan(&preprocessor, &cursor, extended_mode, false, 0)) return 0;

    /* A property escape before anything else fixes the encoding fixes it to
     * the one that the content is read in. */
    if (preprocessor.has_property && preprocessor.fixed_encoding == NULL) {
        preprocessor.fixed_encoding = read_encoding;
    }

    pm_regexp_encoding_option_t option = PM_REGEXP_ENCODING_OPTION_NONE;
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        option = PM_REGEXP_ENCODING_OPTION_BINARY;
    } else if (flags & (PM_REGULAR_EXPRESSION_FLAGS_UTF_8 | PM_REGULAR_EXPRESSION_FLAGS_EUC_JP | PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J)) {
        option = PM_REGEXP_ENCODING_OPTION_FIXED;
    }

    const pm_encoding_t *encoding = pm_regexp_resolve_encoding(regexp, option, read_encoding, preprocessor.fixed_encoding);
    if (encoding == NULL) return 0;

    pm_regexp_parser_t regexp_parser = {
        .parser = parser,
        .start = source,
        .cursor = source,
        .end = source + size,
        .offsets = offsets,
        .source_start = source_start,
        .extended_mode = extended_mode,
        .encoding_changed = parser->encoding_changed,
        .encoding = parser->encoding,
        .name_callback = NULL,
        .name_data = NULL,
        .report_errors = true,
        .property_name = NULL,
        .property_name_length = 0,
        .unicode_property_name = NULL,
        .unicode_property_name_length = 0
    };

    pm_regexp_parse_pattern(&regexp_parser);
    pm_regexp_check_properties(regexp, &regexp_parser);

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
        .flags = PM_NODE_FLAGS(node),
        .location = node->base.location
    };

    return pm_regexp_validate(&regexp, offsets, node->content_loc.start);
}

/**
 * Parse the unescaped content of a regular expression for named capture groups
 * only, for the receiver of a =~ operator. No errors are reported, since the
 * regular expression is validated when it is parsed.
 */
void
pm_regexp_parse_named_captures(pm_parser_t *parser, const uint8_t *source, size_t size, bool extended_mode, pm_regexp_name_callback_t name_callback, void *name_data) {
    pm_regexp_parser_t regexp_parser = {
        .parser = parser,
        .start = source,
        .cursor = source,
        .end = source + size,
        .extended_mode = extended_mode,
        .encoding_changed = parser->encoding_changed,
        .encoding = parser->encoding,
        .name_callback = name_callback,
        .name_data = name_data,
        .report_errors = false,
        .property_name = NULL,
        .property_name_length = 0,
        .unicode_property_name = NULL,
        .unicode_property_name_length = 0
    };

    pm_regexp_parse_pattern(&regexp_parser);
}
