#include "yarp/enc/yp_encoding.h"

static size_t
yp_encoding_windows_31j_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80 || (*b >= 0xA1 && *b <= 0xDF)) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        ((b[0] >= 0x81 && b[0] <= 0x9F) || (b[0] >= 0xE0 && b[0] <= 0xFC)) &&
        (b[1] >= 0x40 && b[1] <= 0xFC)
    ) {
        return 2;
    }

    return 0;
}

static size_t
yp_encoding_windows_31j_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_windows_31j_char_width(b, n) == 1) {
        return yp_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
yp_encoding_windows_31j_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_windows_31j_char_width(b, n) == 1) {
        return yp_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
yp_encoding_windows_31j_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_windows_31j_char_width(b, n) == 1) {
        return yp_encoding_ascii_isupper_char(b, n);
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
