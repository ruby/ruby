#ifndef YARP_ENCODING_H
#define YARP_ENCODING_H

#include "yarp/defines.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// This struct defines the functions necessary to implement the encoding
// interface so we can determine how many bytes the subsequent character takes.
// Each callback should return the number of bytes, or 0 if the next bytes are
// invalid for the encoding and type.
typedef struct {
    const char *name;
    size_t (*char_width)(const char *c);
    size_t (*alpha_char)(const char *c);
    size_t (*alnum_char)(const char *c);
    bool (*isupper_char)(const char *c);
} yp_encoding_t;

// These bits define the location of each bit of metadata within the various
// lookup tables that are used to determine the properties of a character.
#define YP_ENCODING_ALPHABETIC_BIT 1 << 0
#define YP_ENCODING_ALPHANUMERIC_BIT 1 << 1
#define YP_ENCODING_UPPERCASE_BIT 1 << 2

// The function is shared between all of the encodings that use single bytes to
// represent characters. They don't have need of a dynamic function to determine
// their width.
size_t yp_encoding_single_char_width(YP_ATTRIBUTE_UNUSED const char *c);

// These functions are reused by some other encodings, so they are defined here
// so they can be shared.
size_t yp_encoding_ascii_alpha_char(const char *c);
size_t yp_encoding_ascii_alnum_char(const char *c);
bool yp_encoding_ascii_isupper_char(const char *c);

// These functions are shared between the actual encoding and the fast path in
// the parser so they need to be internally visible.
size_t yp_encoding_utf_8_alpha_char(const char *c);
size_t yp_encoding_utf_8_alnum_char(const char *c);

// This lookup table is referenced in both the UTF-8 encoding file and the
// parser directly in order to speed up the default encoding processing.
extern unsigned char yp_encoding_unicode_table[256];

// These are the encodings that are supported by the parser. They are defined in
// their own files in the src/enc directory.
extern yp_encoding_t yp_encoding_ascii;
extern yp_encoding_t yp_encoding_ascii_8bit;
extern yp_encoding_t yp_encoding_big5;
extern yp_encoding_t yp_encoding_euc_jp;
extern yp_encoding_t yp_encoding_gbk;
extern yp_encoding_t yp_encoding_iso_8859_1;
extern yp_encoding_t yp_encoding_iso_8859_2;
extern yp_encoding_t yp_encoding_iso_8859_3;
extern yp_encoding_t yp_encoding_iso_8859_4;
extern yp_encoding_t yp_encoding_iso_8859_5;
extern yp_encoding_t yp_encoding_iso_8859_6;
extern yp_encoding_t yp_encoding_iso_8859_7;
extern yp_encoding_t yp_encoding_iso_8859_8;
extern yp_encoding_t yp_encoding_iso_8859_9;
extern yp_encoding_t yp_encoding_iso_8859_10;
extern yp_encoding_t yp_encoding_iso_8859_11;
extern yp_encoding_t yp_encoding_iso_8859_13;
extern yp_encoding_t yp_encoding_iso_8859_14;
extern yp_encoding_t yp_encoding_iso_8859_15;
extern yp_encoding_t yp_encoding_iso_8859_16;
extern yp_encoding_t yp_encoding_koi8_r;
extern yp_encoding_t yp_encoding_shift_jis;
extern yp_encoding_t yp_encoding_utf_8;
extern yp_encoding_t yp_encoding_windows_31j;
extern yp_encoding_t yp_encoding_windows_1251;
extern yp_encoding_t yp_encoding_windows_1252;

#endif
