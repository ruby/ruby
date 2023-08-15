#include "yarp/enc/yp_encoding.h"

typedef uint16_t yp_windows_31j_codepoint_t;

static yp_windows_31j_codepoint_t
yp_windows_31j_codepoint(const char *c, ptrdiff_t n, size_t *width) {
    const unsigned char *uc = (const unsigned char *) c;

    // These are the single byte characters.
    if (*uc < 0x80 || (*uc >= 0xA1 && *uc <= 0xDF)) {
        *width = 1;
        return *uc;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        ((uc[0] >= 0x81 && uc[0] <= 0x9F) || (uc[0] >= 0xE0 && uc[0] <= 0xFC)) &&
        (uc[1] >= 0x40 && uc[1] <= 0xFC)
    ) {
        *width = 2;
        return (yp_windows_31j_codepoint_t) (uc[0] << 8 | uc[1]);
    }

    *width = 0;
    return 0;
}

static size_t
yp_encoding_windows_31j_char_width(const char *c, ptrdiff_t n) {
    size_t width;
    yp_windows_31j_codepoint(c, n, &width);

    return width;
}

static size_t
yp_encoding_windows_31j_alpha_char(const char *c, ptrdiff_t n) {
    size_t width;
    yp_windows_31j_codepoint_t codepoint = yp_windows_31j_codepoint(c, n, &width);

    if (width == 1) {
        const char value = (const char) codepoint;
        return yp_encoding_ascii_alpha_char(&value, n);
    } else {
        return 0;
    }
}

static size_t
yp_encoding_windows_31j_alnum_char(const char *c, ptrdiff_t n) {
    size_t width;
    yp_windows_31j_codepoint_t codepoint = yp_windows_31j_codepoint(c, n, &width);

    if (width == 1) {
        const char value = (const char) codepoint;
        return yp_encoding_ascii_alnum_char(&value, n);
    } else {
        return 0;
    }
}

static bool
yp_encoding_windows_31j_isupper_char(const char *c, ptrdiff_t n) {
    size_t width;
    yp_windows_31j_codepoint_t codepoint = yp_windows_31j_codepoint(c, n, &width);

    if (width == 1) {
        const char value = (const char) codepoint;
        return yp_encoding_ascii_isupper_char(&value, n);
    } else {
        return false;
    }
}

yp_encoding_t yp_encoding_windows_31j = {
    .name = "windows-31j",
    .char_width = yp_encoding_windows_31j_char_width,
    .alnum_char = yp_encoding_windows_31j_alnum_char,
    .alpha_char = yp_encoding_windows_31j_alpha_char,
    .isupper_char = yp_encoding_windows_31j_isupper_char,
    .multibyte = true
};
