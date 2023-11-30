#include "prism/enc/pm_encoding.h"

static size_t
pm_encoding_big5_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        (b[0] >= 0xA1 && b[0] <= 0xFE) &&
        ((b[1] >= 0x40 && b[1] <= 0x7E) || (b[1] >= 0xA1 && b[1] <= 0xFE))
    ) {
        return 2;
    }

    return 0;
}

static size_t
pm_encoding_big5_alpha_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_big5_char_width(b, n) == 1) ? pm_encoding_ascii_alpha_char(b, n) : 0;
}

static size_t
pm_encoding_big5_alnum_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_big5_char_width(b, n) == 1) ? pm_encoding_ascii_alnum_char(b, n) : 0;
}

static bool
pm_encoding_big5_isupper_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_big5_char_width(b, n) == 1) && pm_encoding_ascii_isupper_char(b, n);
}

/** Big5 encoding */
pm_encoding_t pm_encoding_big5 = {
    .name = "Big5",
    .char_width = pm_encoding_big5_char_width,
    .alnum_char = pm_encoding_big5_alnum_char,
    .alpha_char = pm_encoding_big5_alpha_char,
    .isupper_char = pm_encoding_big5_isupper_char,
    .multibyte = true
};

/** CP950 encoding */
pm_encoding_t pm_encoding_cp950 = {
    .name = "CP950",
    .char_width = pm_encoding_big5_char_width,
    .alnum_char = pm_encoding_big5_alnum_char,
    .alpha_char = pm_encoding_big5_alpha_char,
    .isupper_char = pm_encoding_big5_isupper_char,
    .multibyte = true
};

/** Big5-HKSCS encoding */
pm_encoding_t pm_encoding_big5_hkscs = {
    .name = "Big5-HKSCS",
    .char_width = pm_encoding_big5_char_width,
    .alnum_char = pm_encoding_big5_alnum_char,
    .alpha_char = pm_encoding_big5_alpha_char,
    .isupper_char = pm_encoding_big5_isupper_char,
    .multibyte = true
};

/** CP951 encoding */
pm_encoding_t pm_encoding_cp951 = {
    .name = "CP951",
    .char_width = pm_encoding_big5_char_width,
    .alnum_char = pm_encoding_big5_alnum_char,
    .alpha_char = pm_encoding_big5_alpha_char,
    .isupper_char = pm_encoding_big5_isupper_char,
    .multibyte = true
};

/** Big5-UAO encoding */
pm_encoding_t pm_encoding_big5_uao = {
    .name = "Big5-UAO",
    .char_width = pm_encoding_big5_char_width,
    .alnum_char = pm_encoding_big5_alnum_char,
    .alpha_char = pm_encoding_big5_alpha_char,
    .isupper_char = pm_encoding_big5_isupper_char,
    .multibyte = true
};

static size_t
pm_encoding_emacs_mule_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the 1 byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the 2 byte characters.
    if ((n > 1) && (b[0] >= 0x81 && b[0] <= 0x8F) && (b[1] >= 0xA0)) {
        return 2;
    }

    // These are the 3 byte characters.
    if (
        (n > 2) &&
        (
            ((b[0] >= 0x90 && b[0] <= 0x99) && (b[1] >= 0xA0)) ||
            ((b[0] == 0x9A || b[0] == 0x9B) && (b[1] >= 0xE0 && b[1] <= 0xEF))
        ) &&
        (b[2] >= 0xA0)
    ) {
        return 3;
    }

    // These are the 4 byte characters.
    if (
        (n > 3) &&
        (
            ((b[0] == 0x9C) && (b[1] >= 0xF0) && (b[1] <= 0xF4)) ||
            ((b[0] == 0x9D) && (b[1] >= 0xF5) && (b[1] <= 0xFE))
        ) &&
        (b[2] >= 0xA0) && (b[3] >= 0xA0)
    ) {
        return 4;
    }

    return 0;
}

static size_t
pm_encoding_emacs_mule_alpha_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_emacs_mule_char_width(b, n) == 1) ? pm_encoding_ascii_alpha_char(b, n) : 0;
}

static size_t
pm_encoding_emacs_mule_alnum_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_emacs_mule_char_width(b, n) == 1) ? pm_encoding_ascii_alnum_char(b, n) : 0;
}

static bool
pm_encoding_emacs_mule_isupper_char(const uint8_t *b, ptrdiff_t n) {
    return (pm_encoding_emacs_mule_char_width(b, n) == 1) && pm_encoding_ascii_isupper_char(b, n);
}

/** Emacs-Mule encoding */
pm_encoding_t pm_encoding_emacs_mule = {
    .name = "Emacs-Mule",
    .char_width = pm_encoding_emacs_mule_char_width,
    .alnum_char = pm_encoding_emacs_mule_alnum_char,
    .alpha_char = pm_encoding_emacs_mule_alpha_char,
    .isupper_char = pm_encoding_emacs_mule_isupper_char,
    .multibyte = true
};

/** stateless-ISO-2022-JP encoding */
pm_encoding_t pm_encoding_stateless_iso_2022_jp = {
    .name = "stateless-ISO-2022-JP",
    .char_width = pm_encoding_emacs_mule_char_width,
    .alnum_char = pm_encoding_emacs_mule_alnum_char,
    .alpha_char = pm_encoding_emacs_mule_alpha_char,
    .isupper_char = pm_encoding_emacs_mule_isupper_char,
    .multibyte = true
};

/** stateless-ISO-2022-JP-KDDI encoding */
pm_encoding_t pm_encoding_stateless_iso_2022_jp_kddi = {
    .name = "stateless-ISO-2022-JP-KDDI",
    .char_width = pm_encoding_emacs_mule_char_width,
    .alnum_char = pm_encoding_emacs_mule_alnum_char,
    .alpha_char = pm_encoding_emacs_mule_alpha_char,
    .isupper_char = pm_encoding_emacs_mule_isupper_char,
    .multibyte = true
};
