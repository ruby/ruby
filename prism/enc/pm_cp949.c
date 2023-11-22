#include "prism/enc/pm_encoding.h"

static size_t
pm_encoding_cp949_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters
    if (*b < 0x81) {
        return 1;
    }

    // These are the double byte characters
    if (
        (n > 1) &&
        (b[0] >= 0x81 && b[0] <= 0xfe) &&
        (b[1] >= 0x41 && b[1] <= 0xfe)
    ) {
        return 2;
    }

    return 0;
}

static size_t
pm_encoding_cp949_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp949_char_width(b, n) == 1) {
        return pm_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
pm_encoding_cp949_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp949_char_width(b, n) == 1) {
        return pm_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
pm_encoding_cp949_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp949_char_width(b, n) == 1) {
        return pm_encoding_ascii_isupper_char(b, n);
    } else {
        return 0;
    }
}

/** cp949 encoding */
pm_encoding_t pm_encoding_cp949 = {
    .name = "cp949",
    .char_width = pm_encoding_cp949_char_width,
    .alnum_char = pm_encoding_cp949_alnum_char,
    .alpha_char = pm_encoding_cp949_alpha_char,
    .isupper_char = pm_encoding_cp949_isupper_char,
    .multibyte = true
};
