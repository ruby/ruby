#include "yarp.h"

/******************************************************************************/
/* Character checks                                                           */
/******************************************************************************/

static inline bool
yp_char_is_hexadecimal_digits(const uint8_t *string, size_t length) {
    for (size_t index = 0; index < length; index++) {
        if (!yp_char_is_hexadecimal_digit(string[index])) {
            return false;
        }
    }
    return true;
}

// We don't call the char_width function unless we have to because it's
// expensive to go through the indirection of the function pointer. Instead we
// provide a fast path that will check if we can just return 1.
static inline size_t
yp_char_width(yp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    if (parser->encoding_changed || (*start >= 0x80)) {
        return parser->encoding.char_width(start, end - start);
    } else {
        return 1;
    }
}

/******************************************************************************/
/* Lookup tables for characters                                               */
/******************************************************************************/

// This is a lookup table for unescapes that only take up a single character.
static const uint8_t unescape_chars[] = {
    ['\''] = '\'',
    ['\\'] = '\\',
    ['a'] = '\a',
    ['b'] = '\b',
    ['e'] = '\033',
    ['f'] = '\f',
    ['n'] = '\n',
    ['r'] = '\r',
    ['s'] = ' ',
    ['t'] = '\t',
    ['v'] = '\v'
};

// This is a lookup table for whether or not an ASCII character is printable.
static const bool ascii_printable_chars[] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0
};

static inline bool
char_is_ascii_printable(const uint8_t b) {
    return (b < 0x80) && ascii_printable_chars[b];
}

/******************************************************************************/
/* Unescaping for segments                                                    */
/******************************************************************************/

// Scan the 1-3 digits of octal into the value. Returns the number of digits
// scanned.
static inline size_t
unescape_octal(const uint8_t *backslash, uint8_t *value, const uint8_t *end) {
    *value = (uint8_t) (backslash[1] - '0');
    if (backslash + 2 >= end || !yp_char_is_octal_digit(backslash[2])) {
        return 2;
    }
    *value = (uint8_t) ((*value << 3) | (backslash[2] - '0'));
    if (backslash + 3 >= end || !yp_char_is_octal_digit(backslash[3])) {
        return 3;
    }
    *value = (uint8_t) ((*value << 3) | (backslash[3] - '0'));
    return 4;
}

// Convert a hexadecimal digit into its equivalent value.
static inline uint8_t
unescape_hexadecimal_digit(const uint8_t value) {
    return (uint8_t) ((value <= '9') ? (value - '0') : (value & 0x7) + 9);
}

// Scan the 1-2 digits of hexadecimal into the value. Returns the number of
// digits scanned.
static inline size_t
unescape_hexadecimal(const uint8_t *backslash, uint8_t *value, const uint8_t *end, yp_list_t *error_list) {
    *value = 0;
    if (backslash + 2 >= end || !yp_char_is_hexadecimal_digit(backslash[2])) {
        if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_HEXADECIMAL);
        return 2;
    }
    *value = unescape_hexadecimal_digit(backslash[2]);
    if (backslash + 3 >=  end || !yp_char_is_hexadecimal_digit(backslash[3])) {
        return 3;
    }
    *value = (uint8_t) ((*value << 4) | unescape_hexadecimal_digit(backslash[3]));
    return 4;
}

// Scan the 4 digits of a Unicode escape into the value. Returns the number of
// digits scanned. This function assumes that the characters have already been
// validated.
static inline void
unescape_unicode(const uint8_t *string, size_t length, uint32_t *value) {
    *value = 0;
    for (size_t index = 0; index < length; index++) {
        if (index != 0) *value <<= 4;
        *value |= unescape_hexadecimal_digit(string[index]);
    }
}

// Accepts the pointer to the string to write the unicode value along with the
// 32-bit value to write. Writes the UTF-8 representation of the value to the
// string and returns the number of bytes written.
static inline size_t
unescape_unicode_write(uint8_t *dest, uint32_t value, const uint8_t *start, const uint8_t *end, yp_list_t *error_list) {
    if (value <= 0x7F) {
        // 0xxxxxxx
        dest[0] = (uint8_t) value;
        return 1;
    }

    if (value <= 0x7FF) {
        // 110xxxxx 10xxxxxx
        dest[0] = (uint8_t) (0xC0 | (value >> 6));
        dest[1] = (uint8_t) (0x80 | (value & 0x3F));
        return 2;
    }

    if (value <= 0xFFFF) {
        // 1110xxxx 10xxxxxx 10xxxxxx
        dest[0] = (uint8_t) (0xE0 | (value >> 12));
        dest[1] = (uint8_t) (0x80 | ((value >> 6) & 0x3F));
        dest[2] = (uint8_t) (0x80 | (value & 0x3F));
        return 3;
    }

    // At this point it must be a 4 digit UTF-8 representation. If it's not, then
    // the input is invalid.
    if (value <= 0x10FFFF) {
        // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        dest[0] = (uint8_t) (0xF0 | (value >> 18));
        dest[1] = (uint8_t) (0x80 | ((value >> 12) & 0x3F));
        dest[2] = (uint8_t) (0x80 | ((value >> 6) & 0x3F));
        dest[3] = (uint8_t) (0x80 | (value & 0x3F));
        return 4;
    }

    // If we get here, then the value is too big. This is an error, but we don't
    // want to just crash, so instead we'll add an error to the error list and put
    // in a replacement character instead.
    if (error_list) yp_diagnostic_list_append(error_list, start, end, YP_ERR_ESCAPE_INVALID_UNICODE);
    dest[0] = 0xEF;
    dest[1] = 0xBF;
    dest[2] = 0xBD;
    return 3;
}

typedef enum {
    YP_UNESCAPE_FLAG_NONE = 0,
    YP_UNESCAPE_FLAG_CONTROL = 1,
    YP_UNESCAPE_FLAG_META = 2,
    YP_UNESCAPE_FLAG_EXPECT_SINGLE = 4
} yp_unescape_flag_t;

// Unescape a single character value based on the given flags.
static inline uint8_t
unescape_char(uint8_t value, const uint8_t flags) {
    if (flags & YP_UNESCAPE_FLAG_CONTROL) {
        value &= 0x1f;
    }

    if (flags & YP_UNESCAPE_FLAG_META) {
        value |= 0x80;
    }

    return value;
}

// Read a specific escape sequence into the given destination.
static const uint8_t *
unescape(
    yp_parser_t *parser,
    uint8_t *dest,
    size_t *dest_length,
    const uint8_t *backslash,
    const uint8_t *end,
    const uint8_t flags,
    yp_list_t *error_list
) {
    switch (backslash[1]) {
        case 'a':
        case 'b':
        case 'e':
        case 'f':
        case 'n':
        case 'r':
        case 's':
        case 't':
        case 'v':
            if (dest) {
                dest[(*dest_length)++] = unescape_char(unescape_chars[backslash[1]], flags);
            }
            return backslash + 2;
        // \nnn         octal bit pattern, where nnn is 1-3 octal digits ([0-7])
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9': {
            uint8_t value;
            const uint8_t *cursor = backslash + unescape_octal(backslash, &value, end);

            if (dest) {
                dest[(*dest_length)++] = unescape_char(value, flags);
            }
            return cursor;
        }
        // \xnn         hexadecimal bit pattern, where nn is 1-2 hexadecimal digits ([0-9a-fA-F])
        case 'x': {
            uint8_t value;
            const uint8_t *cursor = backslash + unescape_hexadecimal(backslash, &value, end, error_list);

            if (dest) {
                dest[(*dest_length)++] = unescape_char(value, flags);
            }
            return cursor;
        }
        // \u{nnnn ...} Unicode character(s), where each nnnn is 1-6 hexadecimal digits ([0-9a-fA-F])
        // \unnnn       Unicode character, where nnnn is exactly 4 hexadecimal digits ([0-9a-fA-F])
        case 'u': {
            if ((flags & YP_UNESCAPE_FLAG_CONTROL) | (flags & YP_UNESCAPE_FLAG_META)) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_UNICODE_CM_FLAGS);
                return backslash + 2;
            }

            if ((backslash + 3) < end && backslash[2] == '{') {
                const uint8_t *unicode_cursor = backslash + 3;
                const uint8_t *extra_codepoints_start = NULL;
                int codepoints_count = 0;

                unicode_cursor += yp_strspn_whitespace(unicode_cursor, end - unicode_cursor);

                while ((unicode_cursor < end) && (*unicode_cursor != '}')) {
                    const uint8_t *unicode_start = unicode_cursor;
                    size_t hexadecimal_length = yp_strspn_hexadecimal_digit(unicode_cursor, end - unicode_cursor);

                    // \u{nnnn} character literal allows only 1-6 hexadecimal digits
                    if (hexadecimal_length > 6) {
                        if (error_list) yp_diagnostic_list_append(error_list, unicode_cursor, unicode_cursor + hexadecimal_length, YP_ERR_ESCAPE_INVALID_UNICODE_LONG);
                    }
                    // there are not hexadecimal characters
                    else if (hexadecimal_length == 0) {
                        if (error_list) yp_diagnostic_list_append(error_list, unicode_cursor, unicode_cursor + hexadecimal_length, YP_ERR_ESCAPE_INVALID_UNICODE);
                        return unicode_cursor;
                    }

                    unicode_cursor += hexadecimal_length;

                    codepoints_count++;
                    if (flags & YP_UNESCAPE_FLAG_EXPECT_SINGLE && codepoints_count == 2)
                        extra_codepoints_start = unicode_start;

                    uint32_t value;
                    unescape_unicode(unicode_start, (size_t) (unicode_cursor - unicode_start), &value);
                    if (dest) {
                        *dest_length += unescape_unicode_write(dest + *dest_length, value, unicode_start, unicode_cursor, error_list);
                    }

                    unicode_cursor += yp_strspn_whitespace(unicode_cursor, end - unicode_cursor);
                }

                // ?\u{nnnn} character literal should contain only one codepoint and cannot be like ?\u{nnnn mmmm}
                if (flags & YP_UNESCAPE_FLAG_EXPECT_SINGLE && codepoints_count > 1) {
                    if (error_list) yp_diagnostic_list_append(error_list, extra_codepoints_start, unicode_cursor - 1, YP_ERR_ESCAPE_INVALID_UNICODE_LITERAL);
                }

                if (unicode_cursor < end && *unicode_cursor == '}') {
                    unicode_cursor++;
                } else {
                    if (error_list) yp_diagnostic_list_append(error_list, backslash, unicode_cursor, YP_ERR_ESCAPE_INVALID_UNICODE_TERM);
                }

                return unicode_cursor;
            }
            else if ((backslash + 5) < end && yp_char_is_hexadecimal_digits(backslash + 2, 4)) {
                uint32_t value;
                unescape_unicode(backslash + 2, 4, &value);

                if (dest) {
                    *dest_length += unescape_unicode_write(dest + *dest_length, value, backslash + 2, backslash + 6, error_list);
                }
                return backslash + 6;
            }

            if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_UNICODE);
            return backslash + 2;
        }
        // \c\M-x       meta control character, where x is an ASCII printable character
        // \c?          delete, ASCII 7Fh (DEL)
        // \cx          control character, where x is an ASCII printable character
        case 'c':
            if (backslash + 2 >= end) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL);
                return end;
            }

            if (flags & YP_UNESCAPE_FLAG_CONTROL) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL_REPEAT);
                return backslash + 2;
            }

            switch (backslash[2]) {
                case '\\':
                    return unescape(parser, dest, dest_length, backslash + 2, end, flags | YP_UNESCAPE_FLAG_CONTROL, error_list);
                case '?':
                    if (dest) {
                        dest[(*dest_length)++] = unescape_char(0x7f, flags);
                    }
                    return backslash + 3;
                default: {
                    if (!char_is_ascii_printable(backslash[2])) {
                        if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL);
                        return backslash + 2;
                    }

                    if (dest) {
                        dest[(*dest_length)++] = unescape_char(backslash[2], flags | YP_UNESCAPE_FLAG_CONTROL);
                    }
                    return backslash + 3;
                }
            }
        // \C-x         control character, where x is an ASCII printable character
        // \C-?         delete, ASCII 7Fh (DEL)
        case 'C':
            if (backslash + 3 >= end) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL);
                return end;
            }

            if (flags & YP_UNESCAPE_FLAG_CONTROL) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL_REPEAT);
                return backslash + 2;
            }

            if (backslash[2] != '-') {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_CONTROL);
                return backslash + 2;
            }

            switch (backslash[3]) {
                case '\\':
                    return unescape(parser, dest, dest_length, backslash + 3, end, flags | YP_UNESCAPE_FLAG_CONTROL, error_list);
                case '?':
                    if (dest) {
                        dest[(*dest_length)++] = unescape_char(0x7f, flags);
                    }
                    return backslash + 4;
                default:
                    if (!char_is_ascii_printable(backslash[3])) {
                        if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_CONTROL);
                        return backslash + 2;
                    }

                    if (dest) {
                        dest[(*dest_length)++] = unescape_char(backslash[3], flags | YP_UNESCAPE_FLAG_CONTROL);
                    }
                    return backslash + 4;
            }
        // \M-\C-x      meta control character, where x is an ASCII printable character
        // \M-\cx       meta control character, where x is an ASCII printable character
        // \M-x         meta character, where x is an ASCII printable character
        case 'M': {
            if (backslash + 3 >= end) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 1, YP_ERR_ESCAPE_INVALID_META);
                return end;
            }

            if (flags & YP_UNESCAPE_FLAG_META) {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_META_REPEAT);
                return backslash + 2;
            }

            if (backslash[2] != '-') {
                if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_META);
                return backslash + 2;
            }

            if (backslash[3] == '\\') {
                return unescape(parser, dest, dest_length, backslash + 3, end, flags | YP_UNESCAPE_FLAG_META, error_list);
            }

            if (char_is_ascii_printable(backslash[3])) {
                if (dest) {
                    dest[(*dest_length)++] = unescape_char(backslash[3], flags | YP_UNESCAPE_FLAG_META);
                }
                return backslash + 4;
            }

            if (error_list) yp_diagnostic_list_append(error_list, backslash, backslash + 2, YP_ERR_ESCAPE_INVALID_META);
            return backslash + 3;
        }
        // \n
        case '\n':
            return backslash + 2;
        // \r
        case '\r':
            if (backslash + 2 < end && backslash[2] == '\n') {
                return backslash + 3;
            }
        /* fallthrough */
        // In this case we're escaping something that doesn't need escaping.
        default: {
            size_t width = yp_char_width(parser, backslash + 1, end);

            if (dest) {
                memcpy(dest + *dest_length, backslash + 1, width);
                *dest_length += width;
            }

            return backslash + 1 + width;
        }
    }
}

/******************************************************************************/
/* Public functions and entrypoints                                           */
/******************************************************************************/

// Unescape the contents of the given token into the given string using the
// given unescape mode. The supported escapes are:
//
// \a             bell, ASCII 07h (BEL)
// \b             backspace, ASCII 08h (BS)
// \t             horizontal tab, ASCII 09h (TAB)
// \n             newline (line feed), ASCII 0Ah (LF)
// \v             vertical tab, ASCII 0Bh (VT)
// \f             form feed, ASCII 0Ch (FF)
// \r             carriage return, ASCII 0Dh (CR)
// \e             escape, ASCII 1Bh (ESC)
// \s             space, ASCII 20h (SPC)
// \\             backslash
// \nnn           octal bit pattern, where nnn is 1-3 octal digits ([0-7])
// \xnn           hexadecimal bit pattern, where nn is 1-2 hexadecimal digits ([0-9a-fA-F])
// \unnnn         Unicode character, where nnnn is exactly 4 hexadecimal digits ([0-9a-fA-F])
// \u{nnnn ...}   Unicode character(s), where each nnnn is 1-6 hexadecimal digits ([0-9a-fA-F])
// \cx or \C-x    control character, where x is an ASCII printable character
// \M-x           meta character, where x is an ASCII printable character
// \M-\C-x        meta control character, where x is an ASCII printable character
// \M-\cx         same as above
// \c\M-x         same as above
// \c? or \C-?    delete, ASCII 7Fh (DEL)
//
static void
yp_unescape_manipulate_string_or_char_literal(yp_parser_t *parser, yp_string_t *string, yp_unescape_type_t unescape_type, bool expect_single_codepoint) {
    if (unescape_type == YP_UNESCAPE_NONE) {
        // If we're not unescaping then we can reference the source directly.
        return;
    }

    const uint8_t *backslash = yp_memchr(string->source, '\\', string->length, parser->encoding_changed, &parser->encoding);

    if (backslash == NULL) {
        // Here there are no escapes, so we can reference the source directly.
        return;
    }

    // Here we have found an escape character, so we need to handle all escapes
    // within the string.
    uint8_t *allocated = malloc(string->length);
    if (allocated == NULL) {
        yp_diagnostic_list_append(&parser->error_list, string->source, string->source + string->length, YP_ERR_MALLOC_FAILED);
        return;
    }

    // This is the memory address where we're putting the unescaped string.
    uint8_t *dest = allocated;
    size_t dest_length = 0;

    // This is the current position in the source string that we're looking at.
    // It's going to move along behind the backslash so that we can copy each
    // segment of the string that doesn't contain an escape.
    const uint8_t *cursor = string->source;
    const uint8_t *end = string->source + string->length;

    // For each escape found in the source string, we will handle it and update
    // the moving cursor->backslash window.
    while (backslash != NULL && backslash + 1 < end) {
        assert(dest_length < string->length);

        // This is the size of the segment of the string from the previous escape
        // or the start of the string to the current escape.
        size_t segment_size = (size_t) (backslash - cursor);

        // Here we're going to copy everything up until the escape into the
        // destination buffer.
        memcpy(dest + dest_length, cursor, segment_size);
        dest_length += segment_size;

        switch (backslash[1]) {
            case '\\':
            case '\'':
                dest[dest_length++] = unescape_chars[backslash[1]];
                cursor = backslash + 2;
                break;
            default:
                if (unescape_type == YP_UNESCAPE_MINIMAL) {
                    // In this case we're escaping something that doesn't need escaping.
                    dest[dest_length++] = '\\';
                    cursor = backslash + 1;
                    break;
                }

                // This is the only type of unescaping left. In this case we need to
                // handle all of the different unescapes.
                assert(unescape_type == YP_UNESCAPE_ALL);

                uint8_t flags = YP_UNESCAPE_FLAG_NONE;
                if (expect_single_codepoint) {
                    flags |= YP_UNESCAPE_FLAG_EXPECT_SINGLE;
                }

                cursor = unescape(parser, dest, &dest_length, backslash, end, flags, &parser->error_list);
                break;
        }

        if (end > cursor) {
            backslash = yp_memchr(cursor, '\\', (size_t) (end - cursor), parser->encoding_changed, &parser->encoding);
        } else {
            backslash = NULL;
        }
    }

    // We need to copy the final segment of the string after the last escape.
    if (end > cursor) {
        memcpy(dest + dest_length, cursor, (size_t) (end - cursor));
    } else {
        cursor = end;
    }

    // If the string was already allocated, then we need to free that memory
    // here. That's because we're about to override it with the escaped string.
    yp_string_free(string);

    // We also need to update the length at the end. This is because every escape
    // reduces the length of the final string, and we don't want garbage at the
    // end.
    yp_string_owned_init(string, allocated, dest_length + ((size_t) (end - cursor)));
}

YP_EXPORTED_FUNCTION void
yp_unescape_manipulate_string(yp_parser_t *parser, yp_string_t *string, yp_unescape_type_t unescape_type) {
    yp_unescape_manipulate_string_or_char_literal(parser, string, unescape_type, false);
}

void
yp_unescape_manipulate_char_literal(yp_parser_t *parser, yp_string_t *string, yp_unescape_type_t unescape_type) {
    yp_unescape_manipulate_string_or_char_literal(parser, string, unescape_type, true);
}

// This function is similar to yp_unescape_manipulate_string, except it doesn't
// actually perform any string manipulations. Instead, it calculates how long
// the unescaped character is, and returns that value
size_t
yp_unescape_calculate_difference(yp_parser_t *parser, const uint8_t *backslash, yp_unescape_type_t unescape_type, bool expect_single_codepoint) {
    assert(unescape_type != YP_UNESCAPE_NONE);

    if (backslash + 1 >= parser->end) {
        return 0;
    }

    switch (backslash[1]) {
        case '\\':
        case '\'':
            return 2;
        default: {
            if (unescape_type == YP_UNESCAPE_MINIMAL) {
                return 1 + yp_char_width(parser, backslash + 1, parser->end);
            }

            // This is the only type of unescaping left. In this case we need to
            // handle all of the different unescapes.
            assert(unescape_type == YP_UNESCAPE_ALL);

            uint8_t flags = YP_UNESCAPE_FLAG_NONE;
            if (expect_single_codepoint) {
                flags |= YP_UNESCAPE_FLAG_EXPECT_SINGLE;
            }

            const uint8_t *cursor = unescape(parser, NULL, 0, backslash, parser->end, flags, NULL);
            assert(cursor > backslash);

            return (size_t) (cursor - backslash);
        }
    }
}

// This is one of the main entry points into the extension. It accepts a source
// string, a type of unescaping, and a pointer to a result string. It returns a
// boolean indicating whether or not the unescaping was successful.
YP_EXPORTED_FUNCTION bool
yp_unescape_string(const uint8_t *start, size_t length, yp_unescape_type_t unescape_type, yp_string_t *result) {
    yp_parser_t parser;
    yp_parser_init(&parser, start, length, NULL);

    yp_string_shared_init(result, start, start + length);
    yp_unescape_manipulate_string(&parser, result, unescape_type);

    bool success = yp_list_empty_p(&parser.error_list);
    yp_parser_free(&parser);

    return success;
}
