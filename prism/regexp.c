#include "prism/regexp.h"

// This is the parser that is going to handle parsing regular expressions.
typedef struct {
    const uint8_t *start;
    const uint8_t *cursor;
    const uint8_t *end;
    pm_string_list_t *named_captures;
    bool encoding_changed;
    pm_encoding_t *encoding;
} pm_regexp_parser_t;

// This initializes a new parser with the given source.
static void
pm_regexp_parser_init(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end, pm_string_list_t *named_captures, bool encoding_changed, pm_encoding_t *encoding) {
    *parser = (pm_regexp_parser_t) {
        .start = start,
        .cursor = start,
        .end = end,
        .named_captures = named_captures,
        .encoding_changed = encoding_changed,
        .encoding = encoding
    };
}

// This appends a new string to the list of named captures.
static void
pm_regexp_parser_named_capture(pm_regexp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    pm_string_t string;
    pm_string_shared_init(&string, start, end);
    pm_string_list_append(parser->named_captures, &string);
    pm_string_free(&string);
}

// Returns true if the next character is the end of the source.
static inline bool
pm_regexp_char_is_eof(pm_regexp_parser_t *parser) {
    return parser->cursor >= parser->end;
}

// Optionally accept a char and consume it if it exists.
static inline bool
pm_regexp_char_accept(pm_regexp_parser_t *parser, uint8_t value) {
    if (!pm_regexp_char_is_eof(parser) && *parser->cursor == value) {
        parser->cursor++;
        return true;
    }
    return false;
}

// Expect a character to be present and consume it.
static inline bool
pm_regexp_char_expect(pm_regexp_parser_t *parser, uint8_t value) {
    if (!pm_regexp_char_is_eof(parser) && *parser->cursor == value) {
        parser->cursor++;
        return true;
    }
    return false;
}

// This advances the current token to the next instance of the given character.
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

// Range quantifiers are a special class of quantifiers that look like
//
// * {digit}
// * {digit,}
// * {digit,digit}
// * {,digit}
//
// Unfortunately, if there are any spaces in between, then this just becomes a
// regular character match expression and we have to backtrack. So when this
// function first starts running, we'll create a "save" point and then attempt
// to parse the quantifier. If it fails, we'll restore the save point and
// return.
//
// The properly track everything, we're going to build a little state machine.
// It looks something like the following:
//
//                  ┌───────┐                 ┌─────────┐ ────────────┐
// ──── lbrace ───> │ start │ ──── digit ───> │ minimum │             │
//                  └───────┘                 └─────────┘ <─── digit ─┘
//                      │                       │    │
//   ┌───────┐          │                       │  rbrace
//   │ comma │ <───── comma  ┌──── comma ───────┘    │
//   └───────┘               V                       V
//      │             ┌─────────┐               ┌─────────┐
//      └── digit ──> │ maximum │ ── rbrace ──> │| final |│
//                    └─────────┘               └─────────┘
//                    │         ^
//                    └─ digit ─┘
//
// Note that by the time we've hit this function, the lbrace has already been
// consumed so we're in the start state.
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

// quantifier : star-quantifier
//            | plus-quantifier
//            | optional-quantifier
//            | range-quantifier
//            | <empty>
//            ;
static bool
pm_regexp_parse_quantifier(pm_regexp_parser_t *parser) {
    if (pm_regexp_char_is_eof(parser)) return true;

    switch (*parser->cursor) {
        case '*':
        case '+':
        case '?':
            parser->cursor++;
            return true;
        case '{':
            parser->cursor++;
            return pm_regexp_parse_range_quantifier(parser);
        default:
            // In this case there is no quantifier.
            return true;
    }
}

// match-posix-class : '[' '[' ':' '^'? CHAR+ ':' ']' ']'
//                   ;
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

// Forward declaration because character sets can be nested.
static bool
pm_regexp_parse_lbracket(pm_regexp_parser_t *parser);

// match-char-set : '[' '^'? (match-range | match-char)* ']'
//                ;
static bool
pm_regexp_parse_character_set(pm_regexp_parser_t *parser) {
    pm_regexp_char_accept(parser, '^');

    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ']') {
        switch (*parser->cursor++) {
            case '[':
                pm_regexp_parse_lbracket(parser);
                break;
            case '\\':
                if (!pm_regexp_char_is_eof(parser)) {
                    parser->cursor++;
                }
                break;
            default:
                // do nothing, we've already advanced the cursor
                break;
        }
    }

    return pm_regexp_char_expect(parser, ']');
}

// A left bracket can either mean a POSIX class or a character set.
static bool
pm_regexp_parse_lbracket(pm_regexp_parser_t *parser) {
    const uint8_t *reset = parser->cursor;

    if ((parser->cursor + 2 < parser->end) && parser->cursor[0] == '[' && parser->cursor[1] == ':') {
        parser->cursor++;
        if (pm_regexp_parse_posix_class(parser)) return true;

        parser->cursor = reset;
    }

    return pm_regexp_parse_character_set(parser);
}

// Forward declaration here since parsing groups needs to go back up the grammar
// to parse expressions within them.
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser);

// These are the states of the options that are configurable on the regular
// expression (or from within a group).
typedef enum {
    PM_REGEXP_OPTION_STATE_INVALID,
    PM_REGEXP_OPTION_STATE_TOGGLEABLE,
    PM_REGEXP_OPTION_STATE_ADDABLE,
    PM_REGEXP_OPTION_STATE_ADDED,
    PM_REGEXP_OPTION_STATE_REMOVED
} pm_regexp_option_state_t;

// These are the options that are configurable on the regular expression (or
// from within a group).
#define PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM 'a'
#define PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM 'x'
#define PRISM_REGEXP_OPTION_STATE_SLOTS (PRISM_REGEXP_OPTION_STATE_SLOT_MAXIMUM - PRISM_REGEXP_OPTION_STATE_SLOT_MINIMUM + 1)

// This is the set of options that are configurable on the regular expression.
typedef struct {
    uint8_t values[PRISM_REGEXP_OPTION_STATE_SLOTS];
} pm_regexp_options_t;

// Initialize a new set of options to their default values.
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

// Attempt to add the given option to the set of options. Returns true if it was
// added, false if it was already present.
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

// Attempt to remove the given option from the set of options. Returns true if
// it was removed, false if it was already absent.
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

// Groups can have quite a few different patterns for syntax. They basically
// just wrap a set of expressions, but they can potentially have options after a
// question mark. If there _isn't_ a question mark, then it's just a set of
// expressions. If there _is_, then here are the options:
//
// * (?#...)                       - inline comments
// * (?:subexp)                    - non-capturing group
// * (?=subexp)                    - positive lookahead
// * (?!subexp)                    - negative lookahead
// * (?>subexp)                    - atomic group
// * (?~subexp)                    - absence operator
// * (?<=subexp)                   - positive lookbehind
// * (?<!subexp)                   - negative lookbehind
// * (?<name>subexp)               - named capturing group
// * (?'name'subexp)               - named capturing group
// * (?(cond)yes-subexp)           - conditional expression
// * (?(cond)yes-subexp|no-subexp) - conditional expression
// * (?imxdau-imx)                 - turn on and off configuration
// * (?imxdau-imx:subexp)          - turn on and off configuration for an expression
//
static bool
pm_regexp_parse_group(pm_regexp_parser_t *parser) {
    // First, parse any options for the group.
    if (pm_regexp_char_accept(parser, '?')) {
        if (pm_regexp_char_is_eof(parser)) {
            return false;
        }
        pm_regexp_options_t options;
        pm_regexp_options_init(&options);

        switch (*parser->cursor) {
            case '#': { // inline comments
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
                        if (width == 0) return false;

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
                        pm_regexp_parser_named_capture(parser, start, parser->cursor - 1);
                        break;
                    }
                }
                break;
            case '\'': { // named capture group
                const uint8_t *start = ++parser->cursor;
                if (!pm_regexp_char_find(parser, '\'')) {
                    return false;
                }

                pm_regexp_parser_named_capture(parser, start, parser->cursor - 1);
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

                // If we hit a -, then we're done parsing options.
                if (*parser->cursor != '-') break;

                // Otherwise, fallthrough to the - case.
                /* fallthrough */
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
                break;
            default:
                return false;
        }
    }

    // Now, parse the expressions within this group.
    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ')') {
        if (!pm_regexp_parse_expression(parser)) {
            return false;
        }
        pm_regexp_char_accept(parser, '|');
    }

    // Finally, make sure we have a closing parenthesis.
    return pm_regexp_char_expect(parser, ')');
}

// item : anchor
//      | match-posix-class
//      | match-char-set
//      | match-char-class
//      | match-char-prop
//      | match-char
//      | match-any
//      | group
//      | quantified
//      ;
static bool
pm_regexp_parse_item(pm_regexp_parser_t *parser) {
    switch (*parser->cursor++) {
        case '^':
        case '$':
            return true;
        case '\\':
            if (!pm_regexp_char_is_eof(parser)) {
                parser->cursor++;
            }
            return pm_regexp_parse_quantifier(parser);
        case '(':
            return pm_regexp_parse_group(parser) && pm_regexp_parse_quantifier(parser);
        case '[':
            return pm_regexp_parse_lbracket(parser) && pm_regexp_parse_quantifier(parser);
        default:
            return pm_regexp_parse_quantifier(parser);
    }
}

// expression : item+
//            ;
static bool
pm_regexp_parse_expression(pm_regexp_parser_t *parser) {
    if (!pm_regexp_parse_item(parser)) {
        return false;
    }

    while (!pm_regexp_char_is_eof(parser) && *parser->cursor != ')' && *parser->cursor != '|') {
        if (!pm_regexp_parse_item(parser)) {
            return false;
        }
    }

    return true;
}

// pattern : EOF
//         | expression EOF
//         | expression '|' pattern
//         ;
static bool
pm_regexp_parse_pattern(pm_regexp_parser_t *parser) {
    return (
        (
            // Exit early if the pattern is empty.
            pm_regexp_char_is_eof(parser) ||
            // Parse the first expression in the pattern.
            pm_regexp_parse_expression(parser)
        ) &&
        (
            // Return now if we've parsed the entire pattern.
            pm_regexp_char_is_eof(parser) ||
            // Otherwise, we should have a pipe character.
            (pm_regexp_char_expect(parser, '|') && pm_regexp_parse_pattern(parser))
        )
    );
}

// Parse a regular expression and extract the names of all of the named capture
// groups.
PRISM_EXPORTED_FUNCTION bool
pm_regexp_named_capture_group_names(const uint8_t *source, size_t size, pm_string_list_t *named_captures, bool encoding_changed, pm_encoding_t *encoding) {
    pm_regexp_parser_t parser;
    pm_regexp_parser_init(&parser, source, source + size, named_captures, encoding_changed, encoding);
    return pm_regexp_parse_pattern(&parser);
}
