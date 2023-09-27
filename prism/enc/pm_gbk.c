#include "yarp/enc/yp_encoding.h"

static size_t
yp_encoding_gbk_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        (
            ((b[0] >= 0xA1 && b[0] <= 0xA9) && (b[1] >= 0xA1 && b[1] <= 0xFE)) || // GBK/1
            ((b[0] >= 0xB0 && b[0] <= 0xF7) && (b[1] >= 0xA1 && b[1] <= 0xFE)) || // GBK/2
            ((b[0] >= 0x81 && b[0] <= 0xA0) && (b[1] >= 0x40 && b[1] <= 0xFE) && (b[1] != 0x7F)) || // GBK/3
            ((b[0] >= 0xAA && b[0] <= 0xFE) && (b[1] >= 0x40 && b[1] <= 0xA0) && (b[1] != 0x7F)) || // GBK/4
            ((b[0] >= 0xA8 && b[0] <= 0xA9) && (b[1] >= 0x40 && b[1] <= 0xA0) && (b[1] != 0x7F)) // GBK/5
        )
    ) {
        return 2;
    }

    return 0;
}

static size_t
yp_encoding_gbk_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_gbk_char_width(b, n) == 1) {
        return yp_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
yp_encoding_gbk_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_gbk_char_width(b, n) == 1) {
        return yp_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
yp_encoding_gbk_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (yp_encoding_gbk_char_width(b, n) == 1) {
        return yp_encoding_ascii_isupper_char(b, n);
    } else {
        return false;
    }
}

yp_encoding_t yp_encoding_gbk = {
    .name = "gbk",
    .char_width = yp_encoding_gbk_char_width,
    .alnum_char = yp_encoding_gbk_alnum_char,
    .alpha_char = yp_encoding_gbk_alpha_char,
    .isupper_char = yp_encoding_gbk_isupper_char,
    .multibyte = true
};
