#include "prism/enc/pm_encoding.h"

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ASCII character.
 */
static uint8_t pm_encoding_ascii_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Bx
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Cx
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Dx
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ex
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-1 character.
 */
static uint8_t pm_encoding_iso_8859_1_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-2 character.
 */
static uint8_t pm_encoding_iso_8859_2_table[256] = {
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
    0, 7, 0, 7, 0, 7, 7, 0, 0, 7, 7, 7, 7, 0, 7, 7, // Ax
    0, 3, 0, 3, 0, 3, 3, 0, 0, 3, 3, 3, 3, 0, 3, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-3 character.
 */
static uint8_t pm_encoding_iso_8859_3_table[256] = {
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
    0, 7, 0, 0, 0, 0, 7, 0, 0, 7, 7, 7, 7, 0, 0, 7, // Ax
    0, 3, 0, 0, 0, 3, 3, 0, 0, 3, 3, 3, 3, 0, 0, 3, // Bx
    7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    0, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    0, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-4 character.
 */
static uint8_t pm_encoding_iso_8859_4_table[256] = {
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
    0, 7, 3, 7, 0, 7, 7, 0, 0, 7, 7, 7, 7, 0, 7, 0, // Ax
    0, 3, 0, 3, 0, 3, 3, 0, 0, 3, 3, 3, 3, 7, 3, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-5 character.
 */
static uint8_t pm_encoding_iso_8859_5_table[256] = {
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
    0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 7, 7, // Ax
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-6 character.
 */
static uint8_t pm_encoding_iso_8859_6_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Bx
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Cx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-7 character.
 */
static uint8_t pm_encoding_iso_8859_7_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 0, 7, 0, 7, 7, 7, 0, 7, 0, 7, 7, // Bx
    3, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 3, 3, 3, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-8 character.
 */
static uint8_t pm_encoding_iso_8859_8_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Bx
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Cx
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-9 character.
 */
static uint8_t pm_encoding_iso_8859_9_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-10 character.
 */
static uint8_t pm_encoding_iso_8859_10_table[256] = {
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
    0, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 0, 7, 7, // Ax
    0, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 0, 3, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-11 character.
 */
static uint8_t pm_encoding_iso_8859_11_table[256] = {
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

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-13 character.
 */
static uint8_t pm_encoding_iso_8859_13_table[256] = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7, 0, 0, 0, 0, 7, // Ax
    0, 0, 0, 0, 0, 3, 0, 0, 3, 0, 3, 0, 0, 0, 0, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 0, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-14 character.
 */
static uint8_t pm_encoding_iso_8859_14_table[256] = {
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
    0, 7, 3, 0, 7, 3, 7, 0, 7, 0, 7, 3, 7, 0, 0, 7, // Ax
    7, 3, 7, 3, 7, 3, 0, 7, 3, 3, 3, 7, 3, 7, 3, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-15 character.
 */
static uint8_t pm_encoding_iso_8859_15_table[256] = {
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
    0, 0, 0, 0, 0, 0, 7, 0, 3, 0, 3, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 7, 3, 0, 0, 3, 0, 3, 0, 7, 3, 7, 0, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding ISO-8859-16 character.
 */
static uint8_t pm_encoding_iso_8859_16_table[256] = {
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
    0, 7, 3, 7, 0, 0, 7, 0, 3, 0, 7, 0, 7, 0, 3, 7, // Ax
    0, 0, 7, 3, 7, 0, 0, 0, 3, 3, 3, 0, 7, 3, 7, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding KOI8-R character.
 */
static uint8_t pm_encoding_koi8_r_table[256] = {
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
    0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Bx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Cx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Dx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Ex
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding windows-1251 character.
 */
static uint8_t pm_encoding_windows_1251_table[256] = {
//  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 1x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 2x
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, // 3x
    0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // 4x
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, // 5x
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // 6x
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, // 7x
    7, 7, 0, 3, 0, 0, 0, 0, 0, 0, 7, 0, 7, 7, 7, 7, // 8x
    3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 3, 3, 3, 3, // 9x
    0, 7, 3, 7, 0, 7, 0, 0, 7, 0, 7, 0, 0, 0, 0, 7, // Ax
    0, 0, 7, 3, 3, 3, 0, 0, 3, 0, 3, 0, 3, 7, 3, 3, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Each element of the following table contains a bitfield that indicates a
 * piece of information about the corresponding windows-1252 character.
 */
static uint8_t pm_encoding_windows_1252_table[256] = {
//  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 1x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 2x
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, // 3x
    0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // 4x
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, // 5x
    0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // 6x
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, // 7x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7, 0, 7, 0, // 8x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 3, 0, 3, 7, // 9x
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Ax
    0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, // Bx
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, // Cx
    7, 7, 7, 7, 7, 7, 7, 0, 7, 7, 7, 7, 7, 7, 7, 3, // Dx
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // Ex
    3, 3, 3, 3, 3, 3, 3, 0, 3, 3, 3, 3, 3, 3, 3, 3, // Fx
};

/**
 * Returns the size of the next character in the ASCII encoding. This basically
 * means that if the top bit is not set, the character is 1 byte long.
 */
static size_t
pm_encoding_ascii_char_width(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return *b < 0x80 ? 1 : 0;
}

/**
 * Return the size of the next character in the ASCII encoding if it is an
 * alphabetical character.
 */
size_t
pm_encoding_ascii_alpha_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return (pm_encoding_ascii_table[*b] & PRISM_ENCODING_ALPHABETIC_BIT);
}

/**
 * Return the size of the next character in the ASCII encoding if it is an
 * alphanumeric character.
 */
size_t
pm_encoding_ascii_alnum_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return (pm_encoding_ascii_table[*b] & PRISM_ENCODING_ALPHANUMERIC_BIT) ? 1 : 0;
}

/**
 * Return true if the next character in the ASCII encoding if it is an uppercase
 * character.
 */
bool
pm_encoding_ascii_isupper_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return (pm_encoding_ascii_table[*b] & PRISM_ENCODING_UPPERCASE_BIT);
}

/**
 * For a lot of encodings the default is that they are a single byte long no
 * matter what the codepoint, so this function is shared between them.
 */
static size_t
pm_encoding_single_char_width(PRISM_ATTRIBUTE_UNUSED const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return 1;
}

/**
 * Returns the size of the next character in the KOI-8 encoding. This means
 * checking if it's a valid codepoint in KOI-8 and if it is returning 1.
 */
static size_t
pm_encoding_koi8_r_char_width(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {
    return ((*b >= 0x20 && *b <= 0x7E) || (*b >= 0x80)) ? 1 : 0;
}

#define PRISM_ENCODING_TABLE(name) \
    static size_t pm_encoding_ ##name ## _alpha_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {           \
        return (pm_encoding_ ##name ## _table[*b] & PRISM_ENCODING_ALPHABETIC_BIT);           \
    }                                                                                                         \
    static size_t pm_encoding_ ##name ## _alnum_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {           \
        return (pm_encoding_ ##name ## _table[*b] & PRISM_ENCODING_ALPHANUMERIC_BIT) ? 1 : 0; \
    }                                                                                                         \
    static bool pm_encoding_ ##name ## _isupper_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n) {           \
        return (pm_encoding_ ##name ## _table[*b] & PRISM_ENCODING_UPPERCASE_BIT);            \
    }

PRISM_ENCODING_TABLE(iso_8859_1)
PRISM_ENCODING_TABLE(iso_8859_2)
PRISM_ENCODING_TABLE(iso_8859_3)
PRISM_ENCODING_TABLE(iso_8859_4)
PRISM_ENCODING_TABLE(iso_8859_5)
PRISM_ENCODING_TABLE(iso_8859_6)
PRISM_ENCODING_TABLE(iso_8859_7)
PRISM_ENCODING_TABLE(iso_8859_8)
PRISM_ENCODING_TABLE(iso_8859_9)
PRISM_ENCODING_TABLE(iso_8859_10)
PRISM_ENCODING_TABLE(iso_8859_11)
PRISM_ENCODING_TABLE(iso_8859_13)
PRISM_ENCODING_TABLE(iso_8859_14)
PRISM_ENCODING_TABLE(iso_8859_15)
PRISM_ENCODING_TABLE(iso_8859_16)
PRISM_ENCODING_TABLE(koi8_r)
PRISM_ENCODING_TABLE(windows_1251)
PRISM_ENCODING_TABLE(windows_1252)

#undef PRISM_ENCODING_TABLE

/** ASCII encoding */
pm_encoding_t pm_encoding_ascii = {
    .name = "ascii",
    .char_width = pm_encoding_ascii_char_width,
    .alnum_char = pm_encoding_ascii_alnum_char,
    .alpha_char = pm_encoding_ascii_alpha_char,
    .isupper_char = pm_encoding_ascii_isupper_char,
    .multibyte = false
};

/** ASCII-8BIT encoding */
pm_encoding_t pm_encoding_ascii_8bit = {
    .name = "ascii-8bit",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_ascii_alnum_char,
    .alpha_char = pm_encoding_ascii_alpha_char,
    .isupper_char = pm_encoding_ascii_isupper_char,
    .multibyte = false
};

/** ISO-8859-1 */
pm_encoding_t pm_encoding_iso_8859_1 = {
    .name = "iso-8859-1",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_1_alnum_char,
    .alpha_char = pm_encoding_iso_8859_1_alpha_char,
    .isupper_char = pm_encoding_iso_8859_1_isupper_char,
    .multibyte = false
};

/** ISO-8859-2 */
pm_encoding_t pm_encoding_iso_8859_2 = {
    .name = "iso-8859-2",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_2_alnum_char,
    .alpha_char = pm_encoding_iso_8859_2_alpha_char,
    .isupper_char = pm_encoding_iso_8859_2_isupper_char,
    .multibyte = false
};

/** ISO-8859-3 */
pm_encoding_t pm_encoding_iso_8859_3 = {
    .name = "iso-8859-3",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_3_alnum_char,
    .alpha_char = pm_encoding_iso_8859_3_alpha_char,
    .isupper_char = pm_encoding_iso_8859_3_isupper_char,
    .multibyte = false
};

/** ISO-8859-4 */
pm_encoding_t pm_encoding_iso_8859_4 = {
    .name = "iso-8859-4",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_4_alnum_char,
    .alpha_char = pm_encoding_iso_8859_4_alpha_char,
    .isupper_char = pm_encoding_iso_8859_4_isupper_char,
    .multibyte = false
};

/** ISO-8859-5 */
pm_encoding_t pm_encoding_iso_8859_5 = {
    .name = "iso-8859-5",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_5_alnum_char,
    .alpha_char = pm_encoding_iso_8859_5_alpha_char,
    .isupper_char = pm_encoding_iso_8859_5_isupper_char,
    .multibyte = false
};

/** ISO-8859-6 */
pm_encoding_t pm_encoding_iso_8859_6 = {
    .name = "iso-8859-6",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_6_alnum_char,
    .alpha_char = pm_encoding_iso_8859_6_alpha_char,
    .isupper_char = pm_encoding_iso_8859_6_isupper_char,
    .multibyte = false
};

/** ISO-8859-7 */
pm_encoding_t pm_encoding_iso_8859_7 = {
    .name = "iso-8859-7",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_7_alnum_char,
    .alpha_char = pm_encoding_iso_8859_7_alpha_char,
    .isupper_char = pm_encoding_iso_8859_7_isupper_char,
    .multibyte = false
};

/** ISO-8859-8 */
pm_encoding_t pm_encoding_iso_8859_8 = {
    .name = "iso-8859-8",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_8_alnum_char,
    .alpha_char = pm_encoding_iso_8859_8_alpha_char,
    .isupper_char = pm_encoding_iso_8859_8_isupper_char,
    .multibyte = false
};

/** ISO-8859-9 */
pm_encoding_t pm_encoding_iso_8859_9 = {
    .name = "iso-8859-9",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_9_alnum_char,
    .alpha_char = pm_encoding_iso_8859_9_alpha_char,
    .isupper_char = pm_encoding_iso_8859_9_isupper_char,
    .multibyte = false
};

/** ISO-8859-10 */
pm_encoding_t pm_encoding_iso_8859_10 = {
    .name = "iso-8859-10",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_10_alnum_char,
    .alpha_char = pm_encoding_iso_8859_10_alpha_char,
    .isupper_char = pm_encoding_iso_8859_10_isupper_char,
    .multibyte = false
};

/** ISO-8859-11 */
pm_encoding_t pm_encoding_iso_8859_11 = {
    .name = "iso-8859-11",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_11_alnum_char,
    .alpha_char = pm_encoding_iso_8859_11_alpha_char,
    .isupper_char = pm_encoding_iso_8859_11_isupper_char,
    .multibyte = false
};

/** ISO-8859-13 */
pm_encoding_t pm_encoding_iso_8859_13 = {
    .name = "iso-8859-13",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_13_alnum_char,
    .alpha_char = pm_encoding_iso_8859_13_alpha_char,
    .isupper_char = pm_encoding_iso_8859_13_isupper_char,
    .multibyte = false
};

/** ISO-8859-14 */
pm_encoding_t pm_encoding_iso_8859_14 = {
    .name = "iso-8859-14",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_14_alnum_char,
    .alpha_char = pm_encoding_iso_8859_14_alpha_char,
    .isupper_char = pm_encoding_iso_8859_14_isupper_char,
    .multibyte = false
};

/** ISO-8859-15 */
pm_encoding_t pm_encoding_iso_8859_15 = {
    .name = "iso-8859-15",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_15_alnum_char,
    .alpha_char = pm_encoding_iso_8859_15_alpha_char,
    .isupper_char = pm_encoding_iso_8859_15_isupper_char,
    .multibyte = false
};

/** ISO-8859-16 */
pm_encoding_t pm_encoding_iso_8859_16 = {
    .name = "iso-8859-16",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_iso_8859_16_alnum_char,
    .alpha_char = pm_encoding_iso_8859_16_alpha_char,
    .isupper_char = pm_encoding_iso_8859_16_isupper_char,
    .multibyte = false
};

/** KOI8-R */
pm_encoding_t pm_encoding_koi8_r = {
    .name = "koi8-r",
    .char_width = pm_encoding_koi8_r_char_width,
    .alnum_char = pm_encoding_koi8_r_alnum_char,
    .alpha_char = pm_encoding_koi8_r_alpha_char,
    .isupper_char = pm_encoding_koi8_r_isupper_char,
    .multibyte = false
};

/** Windows-1251 */
pm_encoding_t pm_encoding_windows_1251 = {
    .name = "windows-1251",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_windows_1251_alnum_char,
    .alpha_char = pm_encoding_windows_1251_alpha_char,
    .isupper_char = pm_encoding_windows_1251_isupper_char,
    .multibyte = false
};

/** Windows-1252 */
pm_encoding_t pm_encoding_windows_1252 = {
    .name = "windows-1252",
    .char_width = pm_encoding_single_char_width,
    .alnum_char = pm_encoding_windows_1252_alnum_char,
    .alpha_char = pm_encoding_windows_1252_alpha_char,
    .isupper_char = pm_encoding_windows_1252_isupper_char,
    .multibyte = false
};
