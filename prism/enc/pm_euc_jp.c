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
            ((b[0] == 0x8E) || (b[0] >= 0xA1 && b[0] <= 0xFE)) &&
            (b[1] >= 0xA1 && b[1] <= 0xFE)
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
    .name = "EUC-JP",
    .char_width = pm_encoding_euc_jp_char_width,
    .alnum_char = pm_encoding_euc_jp_alnum_char,
    .alpha_char = pm_encoding_euc_jp_alpha_char,
    .isupper_char = pm_encoding_euc_jp_isupper_char,
    .multibyte = true
};

/** eucJP-ms encoding */
pm_encoding_t pm_encoding_euc_jp_ms = {
    .name = "eucJP-ms",
    .char_width = pm_encoding_euc_jp_char_width,
    .alnum_char = pm_encoding_euc_jp_alnum_char,
    .alpha_char = pm_encoding_euc_jp_alpha_char,
    .isupper_char = pm_encoding_euc_jp_isupper_char,
    .multibyte = true
};

/** EUC-JIS-2004 encoding */
pm_encoding_t pm_encoding_euc_jis_2004 = {
    .name = "EUC-JIS-2004",
    .char_width = pm_encoding_euc_jp_char_width,
    .alnum_char = pm_encoding_euc_jp_alnum_char,
    .alpha_char = pm_encoding_euc_jp_alpha_char,
    .isupper_char = pm_encoding_euc_jp_isupper_char,
    .multibyte = true
};

/** CP51932 encoding */
pm_encoding_t pm_encoding_cp51932 = {
    .name = "CP51932",
    .char_width = pm_encoding_euc_jp_char_width,
    .alnum_char = pm_encoding_euc_jp_alnum_char,
    .alpha_char = pm_encoding_euc_jp_alpha_char,
    .isupper_char = pm_encoding_euc_jp_isupper_char,
    .multibyte = true
};

static size_t
pm_encoding_euc_kr_char_width(const uint8_t *b, ptrdiff_t n) {
    // These are the single byte characters.
    if (*b < 0x80) {
        return 1;
    }

    // These are the double byte characters.
    if (
        (n > 1) &&
        (
            (b[0] >= 0xA1 && b[0] <= 0xFE) &&
            (b[1] >= 0xA1 && b[1] <= 0xFE)
        )
    ) {
        return 2;
    }

    return 0;
}

static size_t
pm_encoding_euc_kr_alpha_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_kr_char_width(b, n) == 1) {
        return pm_encoding_ascii_alpha_char(b, n);
    } else {
        return 0;
    }
}

static size_t
pm_encoding_euc_kr_alnum_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_kr_char_width(b, n) == 1) {
        return pm_encoding_ascii_alnum_char(b, n);
    } else {
        return 0;
    }
}

static bool
pm_encoding_euc_kr_isupper_char(const uint8_t *b, ptrdiff_t n) {
    if (pm_encoding_euc_kr_char_width(b, n) == 1) {
        return pm_encoding_ascii_isupper_char(b, n);
    } else {
        return 0;
    }
}

/** EUC-KR encoding */
pm_encoding_t pm_encoding_euc_kr = {
    .name = "EUC-KR",
    .char_width = pm_encoding_euc_kr_char_width,
    .alnum_char = pm_encoding_euc_kr_alnum_char,
    .alpha_char = pm_encoding_euc_kr_alpha_char,
    .isupper_char = pm_encoding_euc_kr_isupper_char,
    .multibyte = true
};

/** GB2312 encoding */
pm_encoding_t pm_encoding_gb2312 = {
    .name = "GB2312",
    .char_width = pm_encoding_euc_kr_char_width,
    .alnum_char = pm_encoding_euc_kr_alnum_char,
    .alpha_char = pm_encoding_euc_kr_alpha_char,
    .isupper_char = pm_encoding_euc_kr_isupper_char,
    .multibyte = true
};

/** GB12345 encoding */
pm_encoding_t pm_encoding_gb12345 = {
    .name = "GB12345",
    .char_width = pm_encoding_euc_kr_char_width,
    .alnum_char = pm_encoding_euc_kr_alnum_char,
    .alpha_char = pm_encoding_euc_kr_alpha_char,
    .isupper_char = pm_encoding_euc_kr_isupper_char,
    .multibyte = true
};
