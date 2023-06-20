#include "yarp/enc/yp_encoding.h"

// Each element of the following table contains a bitfield that indicates a
// piece of information about the corresponding ISO-8859-11 character.
static unsigned char yp_encoding_iso_8859_11_table[256] = {
//  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 1x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 2x
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, // 3x
    0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // 4x
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, // 5x
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // 6x
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, // 7x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 8x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 9x
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ax
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Bx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Cx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, // Fx
};

static size_t
yp_encoding_iso_8859_11_alpha_char(const char *c) {
    const unsigned char v = (const unsigned char) *c;
    return (yp_encoding_iso_8859_11_table[v] & YP_ENCODING_ALPHABETIC_BIT) ? 1 : 0;
}

static size_t
yp_encoding_iso_8859_11_alnum_char(const char *c) {
    const unsigned char v = (const unsigned char) *c;
    return (yp_encoding_iso_8859_11_table[v] & YP_ENCODING_ALPHANUMERIC_BIT) ? 1 : 0;
}

static bool
yp_encoding_iso_8859_11_isupper_char(const char *c) {
    const unsigned char v = (const unsigned char) *c;
    return (yp_encoding_iso_8859_11_table[v] & YP_ENCODING_UPPERCASE_BIT) ? true : false;
}

yp_encoding_t yp_encoding_iso_8859_11 = {
    .name = "iso-8859-11",
    .char_width = yp_encoding_single_char_width,
    .alnum_char = yp_encoding_iso_8859_11_alnum_char,
    .alpha_char = yp_encoding_iso_8859_11_alpha_char,
    .isupper_char = yp_encoding_iso_8859_11_isupper_char
};
