/**
 * @file pm_encoding.h
 *
 * The encoding interface and implementations used by the parser.
 */
#ifndef PRISM_ENCODING_H
#define PRISM_ENCODING_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * This struct defines the functions necessary to implement the encoding
 * interface so we can determine how many bytes the subsequent character takes.
 * Each callback should return the number of bytes, or 0 if the next bytes are
 * invalid for the encoding and type.
 */
typedef struct {
    /**
     * Return the number of bytes that the next character takes if it is valid
     * in the encoding. Does not read more than n bytes. It is assumed that n is
     * at least 1.
     */
    size_t (*char_width)(const uint8_t *b, ptrdiff_t n);

    /**
     * Return the number of bytes that the next character takes if it is valid
     * in the encoding and is alphabetical. Does not read more than n bytes. It
     * is assumed that n is at least 1.
     */
    size_t (*alpha_char)(const uint8_t *b, ptrdiff_t n);

    /**
     * Return the number of bytes that the next character takes if it is valid
     * in the encoding and is alphanumeric. Does not read more than n bytes. It
     * is assumed that n is at least 1.
     */
    size_t (*alnum_char)(const uint8_t *b, ptrdiff_t n);

    /**
     * Return true if the next character is valid in the encoding and is an
     * uppercase character. Does not read more than n bytes. It is assumed that
     * n is at least 1.
     */
    bool (*isupper_char)(const uint8_t *b, ptrdiff_t n);

    /**
     * The name of the encoding. This should correspond to a value that can be
     * passed to Encoding.find in Ruby.
     */
    const char *name;

    /**
     * Return true if the encoding is a multibyte encoding.
     */
    bool multibyte;
} pm_encoding_t;

/**
 * All of the lookup tables use the first bit of each embedded byte to indicate
 * whether the codepoint is alphabetical.
 */
#define PRISM_ENCODING_ALPHABETIC_BIT 1 << 0

/**
 * All of the lookup tables use the second bit of each embedded byte to indicate
 * whether the codepoint is alphanumeric.
 */
#define PRISM_ENCODING_ALPHANUMERIC_BIT 1 << 1

/**
 * All of the lookup tables use the third bit of each embedded byte to indicate
 * whether the codepoint is uppercase.
 */
#define PRISM_ENCODING_UPPERCASE_BIT 1 << 2

/**
 * Return the size of the next character in the ASCII encoding if it is an
 * alphabetical character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns The number of bytes that the next character takes if it is valid in
 *     the encoding, or 0 if it is not.
 */
size_t pm_encoding_ascii_alpha_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);

/**
 * Return the size of the next character in the ASCII encoding if it is an
 * alphanumeric character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns The number of bytes that the next character takes if it is valid in
 *     the encoding, or 0 if it is not.
 */
size_t pm_encoding_ascii_alnum_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);

/**
 * Return true if the next character in the ASCII encoding if it is an uppercase
 * character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns True if the next character is valid in the encoding and is an
 *     uppercase character, or false if it is not.
 */
bool pm_encoding_ascii_isupper_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);

/**
 * Return the size of the next character in the UTF-8 encoding if it is an
 * alphabetical character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns The number of bytes that the next character takes if it is valid in
 *     the encoding, or 0 if it is not.
 */
size_t pm_encoding_utf_8_alpha_char(const uint8_t *b, ptrdiff_t n);

/**
 * Return the size of the next character in the UTF-8 encoding if it is an
 * alphanumeric character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns The number of bytes that the next character takes if it is valid in
 *     the encoding, or 0 if it is not.
 */
size_t pm_encoding_utf_8_alnum_char(const uint8_t *b, ptrdiff_t n);

/**
 * Return true if the next character in the UTF-8 encoding if it is an uppercase
 * character.
 *
 * @param b The bytes to read.
 * @param n The number of bytes that can be read.
 * @returns True if the next character is valid in the encoding and is an
 *     uppercase character, or false if it is not.
 */
bool pm_encoding_utf_8_isupper_char(const uint8_t *b, ptrdiff_t n);

/**
 * This lookup table is referenced in both the UTF-8 encoding file and the
 * parser directly in order to speed up the default encoding processing. It is
 * used to indicate whether a character is alphabetical, alphanumeric, or
 * uppercase in unicode mappings.
 */
extern const uint8_t pm_encoding_unicode_table[256];

// Below are the encodings that are supported by the parser. They are defined in
// their own files in the src/enc directory.

extern pm_encoding_t pm_encoding_ascii;
extern pm_encoding_t pm_encoding_ascii_8bit;
extern pm_encoding_t pm_encoding_big5;
extern pm_encoding_t pm_encoding_big5_hkscs;
extern pm_encoding_t pm_encoding_big5_uao;
extern pm_encoding_t pm_encoding_cp51932;
extern pm_encoding_t pm_encoding_cp850;
extern pm_encoding_t pm_encoding_cp852;
extern pm_encoding_t pm_encoding_cp855;
extern pm_encoding_t pm_encoding_euc_jp;
extern pm_encoding_t pm_encoding_gb1988;
extern pm_encoding_t pm_encoding_gbk;
extern pm_encoding_t pm_encoding_ibm437;
extern pm_encoding_t pm_encoding_ibm720;
extern pm_encoding_t pm_encoding_ibm737;
extern pm_encoding_t pm_encoding_ibm775;
extern pm_encoding_t pm_encoding_ibm852;
extern pm_encoding_t pm_encoding_ibm855;
extern pm_encoding_t pm_encoding_ibm857;
extern pm_encoding_t pm_encoding_ibm860;
extern pm_encoding_t pm_encoding_ibm861;
extern pm_encoding_t pm_encoding_ibm862;
extern pm_encoding_t pm_encoding_ibm863;
extern pm_encoding_t pm_encoding_ibm864;
extern pm_encoding_t pm_encoding_ibm865;
extern pm_encoding_t pm_encoding_ibm866;
extern pm_encoding_t pm_encoding_ibm869;
extern pm_encoding_t pm_encoding_iso_8859_1;
extern pm_encoding_t pm_encoding_iso_8859_2;
extern pm_encoding_t pm_encoding_iso_8859_3;
extern pm_encoding_t pm_encoding_iso_8859_4;
extern pm_encoding_t pm_encoding_iso_8859_5;
extern pm_encoding_t pm_encoding_iso_8859_6;
extern pm_encoding_t pm_encoding_iso_8859_7;
extern pm_encoding_t pm_encoding_iso_8859_8;
extern pm_encoding_t pm_encoding_iso_8859_9;
extern pm_encoding_t pm_encoding_iso_8859_10;
extern pm_encoding_t pm_encoding_iso_8859_11;
extern pm_encoding_t pm_encoding_iso_8859_13;
extern pm_encoding_t pm_encoding_iso_8859_14;
extern pm_encoding_t pm_encoding_iso_8859_15;
extern pm_encoding_t pm_encoding_iso_8859_16;
extern pm_encoding_t pm_encoding_koi8_r;
extern pm_encoding_t pm_encoding_mac_cent_euro;
extern pm_encoding_t pm_encoding_mac_croatian;
extern pm_encoding_t pm_encoding_mac_cyrillic;
extern pm_encoding_t pm_encoding_mac_greek;
extern pm_encoding_t pm_encoding_mac_iceland;
extern pm_encoding_t pm_encoding_mac_roman;
extern pm_encoding_t pm_encoding_mac_romania;
extern pm_encoding_t pm_encoding_mac_thai;
extern pm_encoding_t pm_encoding_mac_turkish;
extern pm_encoding_t pm_encoding_mac_ukraine;
extern pm_encoding_t pm_encoding_shift_jis;
extern pm_encoding_t pm_encoding_tis_620;
extern pm_encoding_t pm_encoding_utf_8;
extern pm_encoding_t pm_encoding_utf8_mac;
extern pm_encoding_t pm_encoding_windows_1250;
extern pm_encoding_t pm_encoding_windows_1251;
extern pm_encoding_t pm_encoding_windows_1252;
extern pm_encoding_t pm_encoding_windows_1253;
extern pm_encoding_t pm_encoding_windows_1254;
extern pm_encoding_t pm_encoding_windows_1255;
extern pm_encoding_t pm_encoding_windows_1256;
extern pm_encoding_t pm_encoding_windows_1257;
extern pm_encoding_t pm_encoding_windows_1258;
extern pm_encoding_t pm_encoding_windows_31j;
extern pm_encoding_t pm_encoding_windows_874;

#endif
