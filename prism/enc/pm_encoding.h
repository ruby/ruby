#ifndef PRISM_ENCODING_H
#define PRISM_ENCODING_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// This struct defines the functions necessary to implement the encoding
// interface so we can determine how many bytes the subsequent character takes.
// Each callback should return the number of bytes, or 0 if the next bytes are
// invalid for the encoding and type.
typedef struct {
    // Return the number of bytes that the next character takes if it is valid
    // in the encoding. Does not read more than n bytes. It is assumed that n is
    // at least 1.
    size_t (*char_width)(const uint8_t *b, ptrdiff_t n);

    // Return the number of bytes that the next character takes if it is valid
    // in the encoding and is alphabetical. Does not read more than n bytes. It
    // is assumed that n is at least 1.
    size_t (*alpha_char)(const uint8_t *b, ptrdiff_t n);

    // Return the number of bytes that the next character takes if it is valid
    // in the encoding and is alphanumeric. Does not read more than n bytes. It
    // is assumed that n is at least 1.
    size_t (*alnum_char)(const uint8_t *b, ptrdiff_t n);

    // Return true if the next character is valid in the encoding and is an
    // uppercase character. Does not read more than n bytes. It is assumed that
    // n is at least 1.
    bool (*isupper_char)(const uint8_t *b, ptrdiff_t n);

    // The name of the encoding. This should correspond to a value that can be
    // passed to Encoding.find in Ruby.
    const char *name;

    // Return true if the encoding is a multibyte encoding.
    bool multibyte;
} pm_encoding_t;

// These bits define the location of each bit of metadata within the various
// lookup tables that are used to determine the properties of a character.
#define PRISM_ENCODING_ALPHABETIC_BIT 1 << 0
#define PRISM_ENCODING_ALPHANUMERIC_BIT 1 << 1
#define PRISM_ENCODING_UPPERCASE_BIT 1 << 2

// These functions are reused by some other encodings, so they are defined here
// so they can be shared.
size_t pm_encoding_ascii_alpha_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);
size_t pm_encoding_ascii_alnum_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);
bool pm_encoding_ascii_isupper_char(const uint8_t *b, PRISM_ATTRIBUTE_UNUSED ptrdiff_t n);

// These functions are shared between the actual encoding and the fast path in
// the parser so they need to be internally visible.
size_t pm_encoding_utf_8_alpha_char(const uint8_t *b, ptrdiff_t n);
size_t pm_encoding_utf_8_alnum_char(const uint8_t *b, ptrdiff_t n);

// This lookup table is referenced in both the UTF-8 encoding file and the
// parser directly in order to speed up the default encoding processing.
extern const uint8_t pm_encoding_unicode_table[256];

// These are the encodings that are supported by the parser. They are defined in
// their own files in the src/enc directory.
extern pm_encoding_t pm_encoding_ascii;
extern pm_encoding_t pm_encoding_ascii_8bit;
extern pm_encoding_t pm_encoding_big5;
extern pm_encoding_t pm_encoding_euc_jp;
extern pm_encoding_t pm_encoding_gbk;
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
extern pm_encoding_t pm_encoding_shift_jis;
extern pm_encoding_t pm_encoding_utf_8;
extern pm_encoding_t pm_encoding_utf8_mac;
extern pm_encoding_t pm_encoding_windows_31j;
extern pm_encoding_t pm_encoding_windows_1251;
extern pm_encoding_t pm_encoding_windows_1252;

#endif
