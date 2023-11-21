#include "prism/enc/pm_encoding.h"

static size_t
pm_encoding_euc_jp_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        (
            ((b[0] == 0x8E) && (b[1] >= 0xA1 && b[1] <= 0xFE)) ||
            ((b[0] >= 0xA1 && b[0] <= 0xFE) && (b[1] >= 0xA1 && b[1] <= 0xFE))
        )
    ) {
        return 2;
    }

    // These are the triple byte characters.
    if (
        (n > 2) &&
        (b[0] == 0x8F) &&
        (b[1] >= 0xA1 && b[2] <= 0xFE) &&
        (b[2] >= 0xA1 && b[2] <= 0xFE)
    ) {
        return 3;
    }

    return 0;
}

static size_t
pm_encoding_euc_jp_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_jp_char_width(b, n) == 1) {
        return pm_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
pm_encoding_euc_jp_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_jp_char_width(b, n) == 1) {
        return pm_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
pm_encoding_euc_jp_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_jp_char_width(b, n) == 1) {
        return pm_encoding_ascii_isupper_char(b, n);
    } else {
        return 0;
    }
}

/** EUC-JP encoding */
pm_encoding_t pm_encoding_euc_jp = {
    .name = "euc-jp",
    .char_width = pm_encoding_euc_jp_char_width,
    .alnum_char = pm_encoding_euc_jp_alnum_char,
    .alpha_char = pm_encoding_euc_jp_alpha_char,
    .isupper_char = pm_encoding_euc_jp_isupper_char,
    .multibyte = true
};
