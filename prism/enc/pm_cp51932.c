#include "prism/enc/pm_encoding.h"

static size_t
pm_encoding_cp51932_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        ((b[0] >= 0xa1 && b[0] <= 0xfe) || (b[0] == 0x8e)) &&
        (b[1] >= 0xa1 && b[1] <= 0xfe)
    ) {
        return 2;
    }

    return 0;
}

static size_t
pm_encoding_cp51932_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp51932_char_width(b, n) == 1) {
        return pm_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
pm_encoding_cp51932_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp51932_char_width(b, n) == 1) {
        return pm_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
pm_encoding_cp51932_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_cp51932_char_width(b, n) == 1) {
        return pm_encoding_ascii_isupper_char(b, n);
    } else {
        return 0;
    }
}

/** cp51932 encoding */
pm_encoding_t pm_encoding_cp51932 = {
    .name = "cp51932",
    .char_width = pm_encoding_cp51932_char_width,
    .alnum_char = pm_encoding_cp51932_alnum_char,
    .alpha_char = pm_encoding_cp51932_alpha_char,
    .isupper_char = pm_encoding_cp51932_isupper_char,
    .multibyte = true
};
