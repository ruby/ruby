#include "prism/regexp.h"
#include "prism/diagnostic.h"
#include "prism/util/pm_buffer.h"
#include "prism/util/pm_strncasecmp.h"

/** The maximum depth of nested groups allowed in a regular expression. */
#define PM_REGEXP_PARSE_DEPTH_MAX 4096

/**
 * This is the parser that is going to handle parsing regular expressions.
 */
typedef struct {
    /** The parser that is currently being used. */
    pm_parser_t *parser;

    /** A pointer to the start of the source that we are parsing. */
    const uint8_t *start;

    /** A pointer to the current position in the source. */
    const uint8_t *cursor;

    /** A pointer to the end of the source that we are parsing. */
    const uint8_t *end;

    /** The encoding of the source. */
    const pm_encoding_t *encoding;

    /** The callback to call when a named capture group is found. */
    pm_regexp_name_callback_t name_callback;

    /** The data to pass to the name callback. */
    pm_regexp_name_data_t *name_data;

    /** The start of the regexp node (for error locations). */
    const uint8_t *node_start;

    /** The end of the regexp node (for error locations). */
    const uint8_t *node_end;

    /**
     * The explicit encoding determined by escape sequences. NULL if no
     * encoding-setting escape has been seen, UTF-8 for `\u` escapes, or the
     * source encoding for `\x` escapes.
     */
    const pm_encoding_t *explicit_encoding;

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

    /** Buffer of hex escape byte values >= 0x80, separated by 0x00 sentinels. */
    pm_buffer_t hex_escape_buffer;

    /** Count of non-ASCII literal bytes (not from escapes). */
    uint32_t non_ascii_literal_count;

    /**
     * Whether or not the regular expression currently being parsed is in
     * extended mode, wherein whitespace is ignored and comments are allowed.
     */
    bool extended_mode;

    /** Whether the encoding has changed from the default. */
    bool encoding_changed;

    /** Whether the source content is shared (for named capture callback). */
    bool shared;

    /** Whether a `\u{...}` escape with value >= 0x80 was seen. */
    bool has_unicode_escape;

    /** Whether a `\xNN` escape (or `\M-x`, etc.) with value >= 0x80 was seen. */
    bool has_hex_escape;

    /**
     * Tracks whether the last encoding-setting escape was `\u` (true) or `\x`
     * (false). This matters for error messages when both types are mixed.
     */
    bool last_escape_was_unicode;

    /** Whether any `\p{...}` or `\P{...}` property escape was found. */
    bool has_property_escape;

    /** Whether a Unicode-only property escape was found (not POSIX or script). */
    bool has_unicode_property_escape;

    /** Whether a `\u` escape with invalid range (surrogate or > 0x10FFFF) was seen. */
    bool invalid_unicode_range;

    /** Whether we are accumulating consecutive hex escape bytes. */
    bool hex_group_active;

    /** Whether an invalid multibyte character was found during parsing. */
    bool has_invalid_multibyte;
} pm_regexp_parser_t;

/**
 * Append a syntax error to the parser's error list. If the source is shared
 * (points into the original source), we can point to the exact error location.
 * Otherwise, we point to the whole regexp node.
 */
static inline void
pm_regexp_parse_error(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end, const char *message) {
    pm_parser_t *pm = parser->parser;
    uint32_t loc_start, loc_length;

    if (parser->shared) {
        loc_start = (uint32_t) (start - pm->start);
        loc_length = (uint32_t) (end - start);
    } else {
        loc_start = (uint32_t) (parser->node_start - pm->start);
        loc_length = (uint32_t) (parser->node_end - parser->node_start);
    }

    pm_diagnostic_list_append_format(&pm->error_list, loc_start, loc_length, PM_ERR_REGEXP_PARSE_ERROR, message);
}

/**
 * Append a formatted diagnostic error with proper shared/non-shared location
 * handling. This is a macro because we need variadic args for the format string.
 */
#define pm_regexp_parse_error_format(parser_, err_start_, err_end_, diag_id, ...) \
    do { \
        pm_parser_t *pm__ = (parser_)->parser; \
        uint32_t loc_start__, loc_length__; \
        if ((parser_)->shared) { \
            loc_start__ = (uint32_t) ((err_start_) - pm__->start); \
            loc_length__ = (uint32_t) ((err_end_) - (err_start_)); \
        } else { \
            loc_start__ = (uint32_t) ((parser_)->node_start - pm__->start); \
            loc_length__ = (uint32_t) ((parser_)->node_end - (parser_)->node_start); \
        } \
        pm_diagnostic_list_append_format(&pm__->error_list, loc_start__, loc_length__, diag_id, __VA_ARGS__); \
    } while (0)

/**
 * This appends a new string to the list of named captures. This function
 * assumes the caller has already checked the validity of the name callback.
 */
static void
pm_regexp_parser_named_capture(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    pm_string_t string;
    pm_string_shared_init(&string, start, end);
    parser->name_callback(parser->parser, &string, parser->shared, parser->name_data);
    pm_string_free(&string);
}

/**
 * Returns true if the next character is the end of the source.
 */
static inline bool
pm_regexp_char_is_eof(pm_regexp_parser_t *parser) {
    return parser->cursor >= parser->end;
}

/**
 * Optionally accept a char and consume it if it exists.
 */
static inline bool
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
static inline bool
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
 * Mark a group boundary in the hex escape byte buffer. When consecutive hex
 * escape bytes >= 0x80 are followed by a non-hex-escape, this appends a 0x00
 * sentinel to separate the groups for later multibyte validation.
 */
static inline void
pm_regexp_hex_group_boundary(pm_regexp_parser_t *parser) {
    if (parser->hex_group_active) {
        pm_buffer_append_byte(&parser->hex_escape_buffer, 0x00);
        parser->hex_group_active = false;
    }
}

/**
 * Track a hex escape byte value >= 0x80 for multibyte validation.
 */
static inline void
pm_regexp_track_hex_escape(pm_regexp_parser_t *parser, uint8_t byte) {
    if (byte >= 0x80) {
        pm_buffer_append_byte(&parser->hex_escape_buffer, byte);
        parser->hex_group_active = true;
        parser->has_hex_escape = true;

        parser->explicit_encoding = parser->encoding;
        parser->last_escape_was_unicode = false;
    } else {
        pm_regexp_hex_group_boundary(parser);
    }
}

/**
 * Parse a hex digit character and return its value, or -1 if not a hex digit.
 */
static inline int
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
    assert(*parser->cursor == 'p' || *parser->cursor == 'P');

    if (parser->cursor + 1 < parser->end && parser->cursor[1] == '{') {
        const uint8_t *name_start = parser->cursor + 2;
        const uint8_t *search = name_start;

        while (search < parser->end && *search != '}') search++;

        if (search < parser->end) {
            size_t name_length = (size_t) (search - name_start);
            parser->has_property_escape = true;

            pm_regexp_property_type_t type = pm_regexp_classify_property(name_start, name_length);

            // Track the first non-POSIX property name (for /n error messages).
            if (type >= PM_REGEXP_PROPERTY_SCRIPT && parser->property_name == NULL) {
                parser->property_name = name_start;
                parser->property_name_length = name_length;
            }

            // Track the first Unicode-only property name (for /e, /s error messages).
            if (type == PM_REGEXP_PROPERTY_UNICODE) {
                parser->has_unicode_property_escape = true;
                if (parser->unicode_property_name == NULL) {
                    parser->unicode_property_name = name_start;
                    parser->unicode_property_name_length = name_length;
                }
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
 * Validate and skip a \u escape sequence in a regular expression. The cursor
 * should be pointing at the character after 'u' when this is called. This
 * handles both the \u{NNNN MMMM} and \uNNNN forms. Also tracks encoding
 * state for validation.
 */
static void
pm_regexp_parse_unicode_escape(pm_regexp_parser_t *parser) {
    const uint8_t *escape_start = parser->cursor - 2; // points to '\'

    if (pm_regexp_char_is_eof(parser)) {
        pm_regexp_parse_error(parser, escape_start, parser->cursor, "invalid Unicode escape");
        return;
    }

    if (*parser->cursor == '{') {
        parser->cursor++; // skip '{'

        // Skip leading whitespace.
        while (!pm_regexp_char_is_eof(parser) && pm_char_is_whitespace(*parser->cursor)) {
            parser->cursor++;
        }

        bool has_codepoint = false;

        while (!pm_regexp_char_is_eof(parser) && *parser->cursor != '}') {
            // Parse the hex digits to compute the codepoint value.
            uint32_t value = 0;
            size_t hex_count = 0;

            int digit;
            while (!pm_regexp_char_is_eof(parser) && (digit = pm_regexp_hex_digit_value(*parser->cursor)) >= 0) {
                value = (value << 4) | (uint32_t) digit;
                hex_count++;
                parser->cursor++;
            }

            if (hex_count == 0) {
                // Skip to '}' or end of regexp to find the full extent.
                while (!pm_regexp_char_is_eof(parser) && *parser->cursor != '}') {
                    parser->cursor++;
                }

                const uint8_t *escape_end = parser->cursor;
                if (!pm_regexp_char_is_eof(parser)) {
                    escape_end++;
                    parser->cursor++; // skip '}'
                }

                pm_regexp_parse_error_format(parser, escape_start, escape_end, PM_ERR_ESCAPE_INVALID_UNICODE_LIST, (int) (escape_end - escape_start), (const char *) escape_start);
                return;
            }

            if (hex_count > 6) {
                pm_regexp_parse_error(parser, escape_start, parser->cursor, "invalid Unicode range");
            }

            // Track encoding state for this codepoint.
            if (value >= 0x80) {
                parser->has_unicode_escape = true;
                parser->explicit_encoding = PM_ENCODING_UTF_8_ENTRY;
                parser->last_escape_was_unicode = true;
                pm_regexp_hex_group_boundary(parser);
            }

            // Check for invalid Unicode range (surrogates or > 0x10FFFF).
            if (value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
                parser->invalid_unicode_range = true;
            }

            has_codepoint = true;

            // Skip whitespace between codepoints.
            while (!pm_regexp_char_is_eof(parser) && pm_char_is_whitespace(*parser->cursor)) {
                parser->cursor++;
            }
        }

        if (pm_regexp_char_is_eof(parser)) {
            pm_regexp_parse_error(parser, escape_start, parser->cursor, "unterminated Unicode escape");
        } else {
            if (!has_codepoint) {
                pm_regexp_parse_error_format(parser, escape_start, parser->cursor + 1, PM_ERR_ESCAPE_INVALID_UNICODE_LIST, (int) (parser->cursor + 1 - escape_start), (const char *) escape_start);
            }
            parser->cursor++; // skip '}'
        }
    } else {
        // \uNNNN form — need exactly 4 hex digits.
        uint32_t value = 0;
        size_t hex_count = 0;

        int digit;
        while (hex_count < 4 && !pm_regexp_char_is_eof(parser) && (digit = pm_regexp_hex_digit_value(*parser->cursor)) >= 0) {
            value = (value << 4) | (uint32_t) digit;
            hex_count++;
            parser->cursor++;
        }

        if (hex_count < 4) {
            pm_regexp_parse_error(parser, escape_start, parser->cursor, "invalid Unicode escape");
        } else if (value >= 0x80) {
            parser->has_unicode_escape = true;
            parser->explicit_encoding = PM_ENCODING_UTF_8_ENTRY;
            parser->last_escape_was_unicode = true;
            pm_regexp_hex_group_boundary(parser);
        }

        // Check for invalid Unicode range.
        if (hex_count == 4 && (value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF))) {
            parser->invalid_unicode_range = true;
        }
    }
}

// Forward declaration because character sets can be nested.
static bool
pm_regexp_parse_lbracket(pm_regexp_parser_t *parser, uint16_t depth);

/**
 * Parse a \x escape and return the byte value. The cursor should be pointing
 * at the character after 'x'. Returns -1 if no hex digits follow.
 */
static int
pm_regexp_parse_hex_escape(pm_regexp_parser_t *parser) {
    int value = -1;

    if (!pm_regexp_char_is_eof(parser)) {
        int digit = pm_regexp_hex_digit_value(*parser->cursor);
        if (digit >= 0) {
            value = digit;
            parser->cursor++;

            if (!pm_regexp_char_is_eof(parser)) {
                digit = pm_regexp_hex_digit_value(*parser->cursor);
                if (digit >= 0) {
                    value = (value << 4) | digit;
                    parser->cursor++;
                }
            }
        }
    }

    if (value >= 0) {
        pm_regexp_track_hex_escape(parser, (uint8_t) value);
    }

    return value;
}

/**
 * Parse a backslash escape sequence in a regexp, handling \u (unicode),
 * \p/\P (property), \x (hex), and other single-character escapes. Also
 * tracks encoding state for \M-x and \C-\M-x escapes.
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
        case 'M':
            // \M-x produces (x | 0x80), always >= 0x80
            if (parser->cursor + 2 < parser->end && parser->cursor[1] == '-') {
                parser->cursor += 2; // skip 'M-'
                if (!pm_regexp_char_is_eof(parser)) {
                    if (*parser->cursor == '\\') {
                        parser->cursor++;
                        // \M-\C-x or \M-\cx — the resulting byte is always >= 0x80
                        // We just need to track it as a hex escape >= 0x80.
                        pm_regexp_parse_backslash_escape(parser);
                    } else {
                        parser->cursor++;
                    }
                    // \M-x always produces a byte >= 0x80
                    pm_regexp_track_hex_escape(parser, 0x80);
                }
            } else {
                parser->cursor++;
            }
            break;
        case 'C':
            // \C-x produces (x & 0x1F)
            if (parser->cursor + 2 < parser->end && parser->cursor[1] == '-') {
                parser->cursor += 2; // skip 'C-'
                if (!pm_regexp_char_is_eof(parser)) {
                    if (*parser->cursor == '\\') {
                        parser->cursor++;
                        pm_regexp_parse_backslash_escape(parser);
                    } else {
                        parser->cursor++;
                    }
                }
            } else {
                parser->cursor++;
            }
            break;
        case 'c':
            // \cx produces (x & 0x1F)
            parser->cursor++; // skip 'c'
            if (!pm_regexp_char_is_eof(parser)) {
                if (*parser->cursor == '\\') {
                    parser->cursor++;
                    pm_regexp_parse_backslash_escape(parser);
                } else {
                    parser->cursor++;
                }
            }
            break;
        default:
            pm_regexp_hex_group_boundary(parser);
            parser->cursor++;
            break;
    }
}

/**
 * Check if a byte at the current position is a non-ASCII byte in a multibyte
 * encoding that produces an invalid character. If so, emit an error at the
 * byte location immediately.
 */
static void
pm_regexp_parse_invalid_multibyte(pm_regexp_parser_t *parser, const uint8_t *cursor) {
    uint8_t byte = *cursor;
    if (byte >= 0x80 && parser->encoding_changed && parser->encoding->multibyte) {
        size_t width = parser->encoding->char_width(cursor, (ptrdiff_t) (parser->end - cursor));
        if (width > 1) {
            parser->cursor += width - 1;
        } else if (width == 0) {
            parser->has_invalid_multibyte = true;
            pm_regexp_parse_error_format(parser, cursor, cursor + 1, PM_ERR_INVALID_MULTIBYTE_CHAR, parser->encoding->name);
        }
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
                pm_regexp_parse_lbracket(parser, (uint16_t) (depth + 1));
                break;
            case '\\':
                pm_regexp_parse_backslash_escape(parser);
                break;
            default:
                // We've already advanced the cursor by one byte. If the byte
                // was >= 0x80 in a multibyte encoding, we may need to consume
                // additional continuation bytes and validate the character.
                if (*(parser->cursor - 1) >= 0x80) {
                    parser->non_ascii_literal_count++;
                }
                pm_regexp_parse_invalid_multibyte(parser, parser->cursor - 1);
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

                if (parser->encoding_changed && parser->encoding->multibyte) {
                    bool escaped = false;

                    // Here we're going to take a slow path and iterate through
                    // each multibyte character to find the close paren. We do
                    // this because \ can be a trailing byte in some encodings.
                    while (parser->cursor < parser->end) {
                        if (!escaped && *parser->cursor == ')') {
                            parser->cursor++;
                            return true;
                        }

                        size_t width = parser->encoding->char_width(parser->cursor, (ptrdiff_t) (parser->end - parser->cursor));
                        if (width == 0) {
                            if (*parser->cursor >= 0x80) {
                                parser->has_invalid_multibyte = true;
                                pm_regexp_parse_error_format(parser, parser->cursor, parser->cursor + 1, PM_ERR_INVALID_MULTIBYTE_CHAR, parser->encoding->name);
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
                width = parser->encoding->char_width(parser->cursor, (ptrdiff_t) (parser->end - parser->cursor));
            }

            if (width == 0) {
                if (*parser->cursor >= 0x80 && parser->encoding_changed) {
                    if (parser->encoding->multibyte) {
                        // Invalid multibyte character in a multibyte encoding.
                        // Emit the error at the byte location immediately.
                        parser->has_invalid_multibyte = true;
                        pm_regexp_parse_error_format(parser, parser->cursor, parser->cursor + 1, PM_ERR_INVALID_MULTIBYTE_CHAR, parser->encoding->name);
                    } else {
                        // Non-ASCII byte in a single-byte encoding (e.g.,
                        // US-ASCII). Count it for later error reporting.
                        parser->non_ascii_literal_count++;
                    }
                    parser->cursor++;
                    return pm_regexp_parse_quantifier(parser);
                }
                return false;
            }

            // Count non-ASCII literal bytes.
            for (size_t i = 0; i < width; i++) {
                if (parser->cursor[i] >= 0x80) parser->non_ascii_literal_count++;
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
 * Validate that groups of hex escape bytes in the buffer form valid multibyte
 * characters in the given encoding. Groups are separated by 0x00 sentinels.
 */
static bool
pm_regexp_validate_hex_escapes(const pm_encoding_t *encoding, const pm_buffer_t *buffer) {
    const uint8_t *data = (const uint8_t *) pm_buffer_value(buffer);
    size_t len = pm_buffer_length(buffer);
    size_t i = 0;

    while (i < len) {
        size_t group_start = i;
        while (i < len && data[i] != 0x00) i++;

        for (size_t j = group_start; j < i; ) {
            size_t width = encoding->char_width(data + j, (ptrdiff_t) (i - j));
            if (width == 0) return false;
            j += width;
        }

        if (i < len) i++; // skip sentinel
    }

    return true;
}

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
        } else if (encoding->multibyte) {
            size_t width = encoding->char_width(source + index, (ptrdiff_t) (length - index));

            if (width > 1) {
                pm_buffer_append_string(buffer, "\\x{", 3);
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
 * Emit an encoding validation error on the regexp node.
 */
#define PM_REGEXP_ENCODING_ERROR(parser, diag_id, ...) \
    pm_diagnostic_list_append_format( \
        &(parser)->parser->error_list, \
        (uint32_t) ((parser)->node_start - (parser)->parser->start), \
        (uint32_t) ((parser)->node_end - (parser)->node_start), \
        diag_id, __VA_ARGS__)

/**
 * Validate encoding for a regexp with an encoding modifier (/e, /s, /u, /n).
 *
 * The decision tree is:
 *
 * 1. No escape-set encoding (explicit_encoding == NULL):
 *    a. ASCII-only content: validate property escapes, return forced US-ASCII
 *       for /n or the modifier flags for others.
 *    b. US-ASCII source with non-ASCII literals: emit per-byte errors.
 *    c. Source encoding differs from modifier encoding: emit mismatch error.
 *
 * 2. Mixed \u and \x escapes: emit the appropriate conflict error depending
 *    on the modifier and which escape type was last.
 *
 * 3. \u escape with non-/u modifier: incompatible encoding error.
 *
 * 4. Validate that hex escape byte sequences form valid multibyte characters
 *    in the modifier's encoding.
 */
static pm_node_flags_t
pm_regexp_validate_encoding_modifier(pm_regexp_parser_t *parser, bool ascii_only, pm_node_flags_t flags, char modifier, const pm_encoding_t *modifier_encoding, const char *source_start, int source_length) {

    if (parser->explicit_encoding == NULL) {
        if (ascii_only) {
            // Check property escapes against the modifier's encoding tier.
            // /n (ASCII-8BIT): only POSIX properties are valid.
            // /e, /s: POSIX and script properties are valid.
            // /u: all properties are valid.
            if (modifier == 'n' && parser->property_name != NULL) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_INVALID_CHAR_PROPERTY,
                    (int) parser->property_name_length, (const char *) parser->property_name,
                    source_length, source_start);
            } else if (modifier != 'u' && parser->has_unicode_property_escape) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_INVALID_CHAR_PROPERTY,
                    (int) parser->unicode_property_name_length, (const char *) parser->unicode_property_name,
                    source_length, source_start);
            }
            return modifier == 'n' ? PM_REGULAR_EXPRESSION_FLAGS_FORCED_US_ASCII_ENCODING : flags;
        }

        if (parser->encoding == PM_ENCODING_US_ASCII_ENTRY) {
            for (uint32_t i = 0; i < parser->non_ascii_literal_count; i++) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_CHAR, parser->encoding->name);
            }
        } else if (parser->encoding != modifier_encoding) {
            PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_ENCODING_OPTION_MISMATCH, modifier, parser->encoding->name);

            if (modifier == 'n' && !ascii_only) {
                pm_buffer_t formatted = { 0 };
                pm_regexp_format_for_error(&formatted, parser->encoding, (const uint8_t *) source_start, (size_t) source_length);
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_NON_ESCAPED_MBC, (int) formatted.length, (const char *) formatted.value);
                pm_buffer_free(&formatted);
            }
        }

        return flags;
    }

    // Mixed unicode + hex escapes.
    if (parser->has_unicode_escape && parser->has_hex_escape) {
        if (modifier == 'n') {
            if (parser->last_escape_was_unicode) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_UTF8_CHAR_NON_UTF8_REGEXP, source_length, source_start);
            } else {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_ESCAPED_NON_ASCII_IN_UTF8, source_length, source_start);
            }
        } else {
            if (!pm_regexp_validate_hex_escapes(modifier_encoding, &parser->hex_escape_buffer)) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_ESCAPE, source_length, source_start);
            }
        }

        return flags;
    }

    if (modifier != 'u' && parser->explicit_encoding == PM_ENCODING_UTF_8_ENTRY) {
        if (parser->last_escape_was_unicode) {
            PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_INCOMPAT_CHAR_ENCODING, source_length, source_start);
        } else if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) {
            PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_INCOMPAT_CHAR_ENCODING, source_length, source_start);
        }
    }

    if (modifier != 'n' && !pm_regexp_validate_hex_escapes(modifier_encoding, &parser->hex_escape_buffer)) {
        PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_ESCAPE, source_length, source_start);
    }

    return flags;
}

/**
 * Validate encoding for a regexp without a modifier and compute the encoding
 * flags to set on the node.
 *
 * The decision tree is:
 *
 * 1. If a modifier (/n, /u, /e, /s) is present, delegate to
 *    pm_regexp_validate_encoding_modifier.
 * 2. Invalid multibyte chars or unicode ranges: suppress further checks (errors
 *    were already emitted during parsing).
 * 3. US-ASCII source with non-ASCII literals: emit per-byte errors.
 * 4. ASCII-only content: return forced US-ASCII (or forced UTF-8 if \p{...}).
 * 5. Escape-set encoding present: validate hex escapes against the target
 *    encoding, handle mixed \u + \x conflicts, and return the appropriate
 *    forced encoding flag.
 */
static pm_node_flags_t
pm_regexp_validate_encoding(pm_regexp_parser_t *parser, bool ascii_only, pm_node_flags_t flags, const char *source_start, int source_length) {

    // Invalid multibyte characters suppress further validation.
    // Errors were already emitted at the byte locations during parsing.
    if (parser->has_invalid_multibyte) {
        return flags;
    }

    if (parser->invalid_unicode_range) {
        PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_INVALID_UNICODE_RANGE, source_length, source_start);
        return flags;
    }

    // Check modifier flags first.
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        return pm_regexp_validate_encoding_modifier(parser, ascii_only, flags, 'n', PM_ENCODING_ASCII_8BIT_ENTRY, source_start, source_length);
    }
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        return pm_regexp_validate_encoding_modifier(parser, ascii_only, flags, 'u', PM_ENCODING_UTF_8_ENTRY, source_start, source_length);
    }
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        return pm_regexp_validate_encoding_modifier(parser, ascii_only, flags, 'e', PM_ENCODING_EUC_JP_ENTRY, source_start, source_length);
    }
    if (flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        return pm_regexp_validate_encoding_modifier(parser, ascii_only, flags, 's', PM_ENCODING_WINDOWS_31J_ENTRY, source_start, source_length);
    }

    // No modifier — check for non-ASCII literals in US-ASCII encoding.
    if (parser->encoding == PM_ENCODING_US_ASCII_ENTRY && parser->explicit_encoding == NULL && !ascii_only) {
        for (uint32_t i = 0; i < parser->non_ascii_literal_count; i++) {
            PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_CHAR, parser->encoding->name);
        }
    }

    // ASCII-only regexps get downgraded to US-ASCII, unless property escapes
    // force UTF-8.
    if (ascii_only) {
        if (parser->has_property_escape) {
            return PM_REGULAR_EXPRESSION_FLAGS_FORCED_UTF8_ENCODING;
        }
        return PM_REGULAR_EXPRESSION_FLAGS_FORCED_US_ASCII_ENCODING;
    }

    // Check explicit encoding from escape sequences.
    if (parser->explicit_encoding != NULL) {
        // Mixed unicode + hex escapes without modifier.
        if (parser->has_unicode_escape && parser->has_hex_escape && parser->encoding != PM_ENCODING_UTF_8_ENTRY) {
            if (parser->encoding != PM_ENCODING_US_ASCII_ENTRY &&
                parser->encoding != PM_ENCODING_ASCII_8BIT_ENTRY &&
                !pm_regexp_validate_hex_escapes(parser->encoding, &parser->hex_escape_buffer)) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_ESCAPE, source_length, source_start);
            } else if (parser->last_escape_was_unicode) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_UTF8_CHAR_NON_UTF8_REGEXP, source_length, source_start);
            } else {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_REGEXP_ESCAPED_NON_ASCII_IN_UTF8, source_length, source_start);
            }

            return 0;
        }

        if (parser->explicit_encoding == PM_ENCODING_UTF_8_ENTRY) {
            if (!pm_regexp_validate_hex_escapes(parser->explicit_encoding, &parser->hex_escape_buffer)) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_ESCAPE, source_length, source_start);
            }

            return PM_REGULAR_EXPRESSION_FLAGS_FORCED_UTF8_ENCODING;
        } else if (parser->encoding == PM_ENCODING_US_ASCII_ENTRY) {
            return PM_REGULAR_EXPRESSION_FLAGS_FORCED_BINARY_ENCODING;
        } else {
            if (!pm_regexp_validate_hex_escapes(parser->explicit_encoding, &parser->hex_escape_buffer)) {
                PM_REGEXP_ENCODING_ERROR(parser, PM_ERR_INVALID_MULTIBYTE_ESCAPE, source_length, source_start);
            }
        }
    }

    return 0;
}

/**
 * Parse a regular expression, validate its encoding, and optionally extract
 * named capture groups. Encoding validation walks the raw source (content_loc)
 * to distinguish escape-produced bytes from literal bytes. Named capture
 * extraction walks the unescaped content since escape sequences in group names
 * (e.g., line continuations) have already been processed by the lexer.
 */
PRISM_EXPORTED_FUNCTION pm_node_flags_t
pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, pm_regexp_name_callback_t name_callback, pm_regexp_name_data_t *name_data) {
    const uint8_t *source = parser->start + node->content_loc.start;
    size_t size = node->content_loc.length;
    bool extended_mode = PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EXTENDED);
    pm_node_flags_t flags = PM_NODE_FLAGS(node);

    const uint8_t *node_start = parser->start + node->base.location.start;
    const uint8_t *node_end = parser->start + node->base.location.start + node->base.location.length;

    // First pass: walk raw source for encoding validation (no name extraction).
    pm_regexp_parser_t regexp_parser = {
        .parser = parser,
        .start = source,
        .cursor = source,
        .end = source + size,
        .extended_mode = extended_mode,
        .encoding_changed = parser->encoding_changed,
        .encoding = parser->encoding,
        .name_callback = NULL,
        .name_data = NULL,
        .shared = true,
        .node_start = node_start,
        .node_end = node_end,
        .has_unicode_escape = false,
        .has_hex_escape = false,
        .last_escape_was_unicode = false,
        .explicit_encoding = NULL,
        .has_property_escape = false,
        .has_unicode_property_escape = false,
        .property_name = NULL,
        .property_name_length = 0,
        .unicode_property_name = NULL,
        .unicode_property_name_length = 0,
        .non_ascii_literal_count = 0,
        .invalid_unicode_range = false,
        .hex_escape_buffer = { 0 },
        .hex_group_active = false,
        .has_invalid_multibyte = false,
    };

    pm_regexp_parse_pattern(&regexp_parser);

    // Compute ascii_only from the regexp parser's tracked state. We cannot
    // use node->unescaped for this because regexp unescaped content preserves
    // escape text (e.g., \x80 is 4 ASCII chars), not the binary values.
    bool ascii_only = !regexp_parser.has_hex_escape && !regexp_parser.has_unicode_escape && regexp_parser.non_ascii_literal_count == 0;
    // Use the unescaped content for error messages to match CRuby's format,
    // where Ruby escapes like \M-\C-? are resolved to bytes but regexp escapes
    // like \u{80} are preserved as text.
    const char *error_source = (const char *) pm_string_source(&node->unescaped);
    int error_source_length = (int) pm_string_length(&node->unescaped);
    pm_node_flags_t encoding_flags = pm_regexp_validate_encoding(&regexp_parser, ascii_only, flags, error_source, error_source_length);
    pm_buffer_free(&regexp_parser.hex_escape_buffer);

    // Second pass: walk unescaped content for named capture extraction.
    if (name_callback != NULL) {
        bool shared = node->unescaped.type == PM_STRING_SHARED;
        pm_regexp_parse_named_captures(parser, pm_string_source(&node->unescaped), pm_string_length(&node->unescaped), shared, extended_mode, name_callback, name_data);
    }

    return encoding_flags;
}

/**
 * Parse an interpolated regular expression for named capture groups only.
 * This is used for the =~ operator with interpolated regexps where we don't
 * have a pm_regular_expression_node_t. No encoding validation is performed.
 *
 * Note: The encoding-tracking fields (has_unicode_escape, has_hex_escape, etc.)
 * are initialized but not used for the result. They exist because the parsing
 * functions (pm_regexp_parse_backslash_escape, etc.) unconditionally update
 * them as they walk through the content.
 */
void
pm_regexp_parse_named_captures(pm_parser_t *parser, const uint8_t *source, size_t size, bool shared, bool extended_mode, pm_regexp_name_callback_t name_callback, pm_regexp_name_data_t *name_data) {
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
        .shared = shared,
        .node_start = source,
        .node_end = source + size,
        .has_unicode_escape = false,
        .has_hex_escape = false,
        .last_escape_was_unicode = false,
        .explicit_encoding = NULL,
        .has_property_escape = false,
        .has_unicode_property_escape = false,
        .property_name = NULL,
        .property_name_length = 0,
        .unicode_property_name = NULL,
        .unicode_property_name_length = 0,
        .non_ascii_literal_count = 0,
        .invalid_unicode_range = false,
        .hex_escape_buffer = { 0 },
        .hex_group_active = false,
        .has_invalid_multibyte = false,
    };

    pm_regexp_parse_pattern(&regexp_parser);
    pm_buffer_free(&regexp_parser.hex_escape_buffer);
}
