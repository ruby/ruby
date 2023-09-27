#include "yarp/pack.h"

#include <stdbool.h>
#include <errno.h>

static uintmax_t
strtoumaxc(const char **format);

YP_EXPORTED_FUNCTION yp_pack_result
yp_pack_parse(yp_pack_variant variant, const char **format, const char *format_end,
                            yp_pack_type *type, yp_pack_signed *signed_type, yp_pack_endian *endian, yp_pack_size *size,
                            yp_pack_length_type *length_type, uint64_t *length, yp_pack_encoding *encoding) {

    if (*encoding == YP_PACK_ENCODING_START) {
        *encoding = YP_PACK_ENCODING_US_ASCII;
    }

    if (*format == format_end) {
            *type = YP_PACK_END;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            *length_type = YP_PACK_LENGTH_NA;
            return YP_PACK_OK;
    }

    *length_type = YP_PACK_LENGTH_FIXED;
    *length = 1;
    bool length_changed_allowed = true;

    char directive = **format;
    (*format)++;
    switch (directive) {
        case ' ':
        case '\t':
        case '\n':
        case '\v':
        case '\f':
        case '\r':
            *type = YP_PACK_SPACE;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            *length_type = YP_PACK_LENGTH_NA;
            *length = 0;
            return YP_PACK_OK;
        case '#':
            while ((*format < format_end) && (**format != '\n')) {
                (*format)++;
            }
            *type = YP_PACK_COMMENT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            *length_type = YP_PACK_LENGTH_NA;
            *length = 0;
            return YP_PACK_OK;
        case 'C':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_AGNOSTIC_ENDIAN;
            *size = YP_PACK_SIZE_8;
            break;
        case 'S':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_16;
            break;
        case 'L':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_32;
            break;
        case 'Q':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_64;
            break;
        case 'J':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_P;
            break;
        case 'c':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_AGNOSTIC_ENDIAN;
            *size = YP_PACK_SIZE_8;
            break;
        case 's':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_16;
            break;
        case 'l':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_32;
            break;
        case 'q':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_64;
            break;
        case 'j':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_P;
            break;
        case 'I':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_INT;
            break;
        case 'i':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_SIGNED;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_INT;
            break;
        case 'n':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_BIG_ENDIAN;
            *size = YP_PACK_SIZE_16;
            length_changed_allowed = false;
            break;
        case 'N':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_BIG_ENDIAN;
            *size = YP_PACK_SIZE_32;
            length_changed_allowed = false;
            break;
        case 'v':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_LITTLE_ENDIAN;
            *size = YP_PACK_SIZE_16;
            length_changed_allowed = false;
            break;
        case 'V':
            *type = YP_PACK_INTEGER;
            *signed_type = YP_PACK_UNSIGNED;
            *endian = YP_PACK_LITTLE_ENDIAN;
            *size = YP_PACK_SIZE_32;
            length_changed_allowed = false;
            break;
        case 'U':
            *type = YP_PACK_UTF8;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'w':
            *type = YP_PACK_BER;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'D':
        case 'd':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_64;
            break;
        case 'F':
        case 'f':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_NATIVE_ENDIAN;
            *size = YP_PACK_SIZE_32;
            break;
        case 'E':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_LITTLE_ENDIAN;
            *size = YP_PACK_SIZE_64;
            break;
        case 'e':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_LITTLE_ENDIAN;
            *size = YP_PACK_SIZE_32;
            break;
        case 'G':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_BIG_ENDIAN;
            *size = YP_PACK_SIZE_64;
            break;
        case 'g':
            *type = YP_PACK_FLOAT;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_BIG_ENDIAN;
            *size = YP_PACK_SIZE_32;
            break;
        case 'A':
            *type = YP_PACK_STRING_SPACE_PADDED;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'a':
            *type = YP_PACK_STRING_NULL_PADDED;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'Z':
            *type = YP_PACK_STRING_NULL_TERMINATED;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'B':
            *type = YP_PACK_STRING_MSB;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'b':
            *type = YP_PACK_STRING_LSB;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'H':
            *type = YP_PACK_STRING_HEX_HIGH;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'h':
            *type = YP_PACK_STRING_HEX_LOW;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'u':
            *type = YP_PACK_STRING_UU;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'M':
            *type = YP_PACK_STRING_MIME;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'm':
            *type = YP_PACK_STRING_BASE64;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'P':
            *type = YP_PACK_STRING_FIXED;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'p':
            *type = YP_PACK_STRING_POINTER;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case '@':
            *type = YP_PACK_MOVE;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'X':
            *type = YP_PACK_BACK;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case 'x':
            *type = YP_PACK_NULL;
            *signed_type = YP_PACK_SIGNED_NA;
            *endian = YP_PACK_ENDIAN_NA;
            *size = YP_PACK_SIZE_NA;
            break;
        case '%':
            return YP_PACK_ERROR_UNSUPPORTED_DIRECTIVE;
        default:
            return YP_PACK_ERROR_UNKNOWN_DIRECTIVE;
    }

    bool explicit_endian = false;

    while (*format < format_end) {
        switch (**format) {
            case '_':
            case '!':
                (*format)++;
                if (*type != YP_PACK_INTEGER || !length_changed_allowed) {
                    return YP_PACK_ERROR_BANG_NOT_ALLOWED;
                }
                switch (*size) {
                    case YP_PACK_SIZE_SHORT:
                    case YP_PACK_SIZE_INT:
                    case YP_PACK_SIZE_LONG:
                    case YP_PACK_SIZE_LONG_LONG:
                        break;
                    case YP_PACK_SIZE_16:
                        *size = YP_PACK_SIZE_SHORT;
                        break;
                    case YP_PACK_SIZE_32:
                        *size = YP_PACK_SIZE_LONG;
                        break;
                    case YP_PACK_SIZE_64:
                        *size = YP_PACK_SIZE_LONG_LONG;
                        break;
                    case YP_PACK_SIZE_P:
                        break;
                    default:
                        return YP_PACK_ERROR_BANG_NOT_ALLOWED;
                }
                break;
            case '<':
                (*format)++;
                if (explicit_endian) {
                    return YP_PACK_ERROR_DOUBLE_ENDIAN;
                }
                *endian = YP_PACK_LITTLE_ENDIAN;
                explicit_endian = true;
                break;
            case '>':
                (*format)++;
                if (explicit_endian) {
                    return YP_PACK_ERROR_DOUBLE_ENDIAN;
                }
                *endian = YP_PACK_BIG_ENDIAN;
                explicit_endian = true;
                break;
            default:
                goto exit_modifier_loop;
        }
    }

exit_modifier_loop:

    if (variant == YP_PACK_VARIANT_UNPACK && *type == YP_PACK_MOVE) {
        *length = 0;
    }

    if (*format < format_end) {
        if (**format == '*') {
            switch (*type) {
                case YP_PACK_NULL:
                case YP_PACK_BACK:
                    switch (variant) {
                        case YP_PACK_VARIANT_PACK:
                            *length_type = YP_PACK_LENGTH_FIXED;
                            break;
                        case YP_PACK_VARIANT_UNPACK:
                            *length_type = YP_PACK_LENGTH_MAX;
                            break;
                    }
                    *length = 0;
                    break;

                case YP_PACK_MOVE:
                    switch (variant) {
                        case YP_PACK_VARIANT_PACK:
                            *length_type = YP_PACK_LENGTH_FIXED;
                            break;
                        case YP_PACK_VARIANT_UNPACK:
                            *length_type = YP_PACK_LENGTH_RELATIVE;
                            break;
                    }
                    *length = 0;
                    break;

                case YP_PACK_STRING_UU:
                    *length_type = YP_PACK_LENGTH_FIXED;
                    *length = 0;
                    break;

                case YP_PACK_STRING_FIXED:
                    switch (variant) {
                        case YP_PACK_VARIANT_PACK:
                            *length_type = YP_PACK_LENGTH_FIXED;
                            *length = 1;
                            break;
                        case YP_PACK_VARIANT_UNPACK:
                            *length_type = YP_PACK_LENGTH_MAX;
                            *length = 0;
                            break;
                    }
                    break;

                case YP_PACK_STRING_MIME:
                case YP_PACK_STRING_BASE64:
                    *length_type = YP_PACK_LENGTH_FIXED;
                    *length = 1;
                    break;

                default:
                    *length_type = YP_PACK_LENGTH_MAX;
                    *length = 0;
                    break;
            }

            (*format)++;
        } else if (**format >= '0' && **format <= '9') {
            errno = 0;
            *length_type = YP_PACK_LENGTH_FIXED;
            #if UINTMAX_MAX < UINT64_MAX
                #error "YARP's design assumes uintmax_t is at least as large as uint64_t"
            #endif
            uintmax_t length_max = strtoumaxc(format);
            if (errno || length_max > UINT64_MAX) {
                return YP_PACK_ERROR_LENGTH_TOO_BIG;
            }
            *length = (uint64_t) length_max;
        }
    }

    switch (*type) {
        case YP_PACK_UTF8:
            /* if encoding is US-ASCII, upgrade to UTF-8 */
            if (*encoding == YP_PACK_ENCODING_US_ASCII) {
                *encoding = YP_PACK_ENCODING_UTF_8;
            }
            break;
        case YP_PACK_STRING_MIME:
        case YP_PACK_STRING_BASE64:
        case YP_PACK_STRING_UU:
            /* keep US-ASCII (do nothing) */
            break;
        default:
            /* fall back to BINARY */
            *encoding = YP_PACK_ENCODING_ASCII_8BIT;
            break;
    }

    return YP_PACK_OK;
}

YP_EXPORTED_FUNCTION size_t
yp_size_to_native(yp_pack_size size) {
    switch (size) {
        case YP_PACK_SIZE_SHORT:
            return sizeof(short);
        case YP_PACK_SIZE_INT:
            return sizeof(int);
        case YP_PACK_SIZE_LONG:
            return sizeof(long);
        case YP_PACK_SIZE_LONG_LONG:
            return sizeof(long long);
        case YP_PACK_SIZE_8:
            return 1;
        case YP_PACK_SIZE_16:
            return 2;
        case YP_PACK_SIZE_32:
            return 4;
        case YP_PACK_SIZE_64:
            return 8;
        case YP_PACK_SIZE_P:
            return sizeof(void *);
        default:
            return 0;
    }
}

static uintmax_t
strtoumaxc(const char **format) {
    uintmax_t value = 0;
    while (**format >= '0' && **format <= '9') {
        if (value > UINTMAX_MAX / 10) {
            errno = ERANGE;
        }
        value = value * 10 + ((uintmax_t) (**format - '0'));
        (*format)++;
    }
    return value;
}
