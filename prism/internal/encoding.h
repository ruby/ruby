#ifndef PRISM_INTERNAL_ENCODING_H
#define PRISM_INTERNAL_ENCODING_H

#include "prism/compiler/inline.h"
#include "prism/excludes.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * The ways in which an encoding answers questions about its characters. Every
 * kind after UTF-8 is a multibyte encoding that is ASCII below 0x80 and whose
 * other characters take the forms listed for it in encoding.c.
 */
typedef enum {
    /* Every byte is a character, with the properties in its table. */
    PM_ENCODING_KIND_SINGLE_BYTE,

    /* Every byte below 0x80 is a character, and every other byte is invalid. */
    PM_ENCODING_KIND_ASCII,

    /* UTF-8, whose characters have the properties of their code points. */
    PM_ENCODING_KIND_UTF_8,

    /* EUC-JP and the encodings that share its forms. */
    PM_ENCODING_KIND_EUC_JP,

    /* Shift_JIS and the encodings that share its forms. */
    PM_ENCODING_KIND_SHIFT_JIS,

    /* Big5 and the encodings that share its forms. */
    PM_ENCODING_KIND_BIG5,

    /* CESU-8, whose characters have the properties of their code points. */
    PM_ENCODING_KIND_CESU_8,

    /* CP949. */
    PM_ENCODING_KIND_CP949,

    /* Emacs-Mule and the encodings that share its forms. */
    PM_ENCODING_KIND_EMACS_MULE,

    /* EUC-KR and the encodings that share its forms. */
    PM_ENCODING_KIND_EUC_KR,

    /* EUC-TW. */
    PM_ENCODING_KIND_EUC_TW,

    /* GB18030. */
    PM_ENCODING_KIND_GB18030,

    /* GBK. */
    PM_ENCODING_KIND_GBK
} pm_encoding_kind_t;

/*
 * An encoding that prism can parse source in. It holds what the answers to the
 * questions about its characters come from, which pm_encoding_char_width and
 * the functions after it read.
 */
typedef struct {
    /*
     * The name of the encoding. This should correspond to a value that can be
     * passed to Encoding.find in Ruby.
     */
    const char *name;

    /* The PRISM_ENCODING_*_BIT properties of each byte as a character. */
    const uint8_t *table;

    /*
     * How the encoding answers questions about its characters, as a
     * pm_encoding_kind_t stored in a byte to keep the table of encodings small.
     */
    uint8_t kind;
} pm_encoding_t;

/*
 * Return true if the encoding is a multibyte encoding. Every kind other than
 * single-byte and ASCII has characters that span more than one byte.
 */
static PRISM_INLINE bool
pm_encoding_multibyte_p(const pm_encoding_t *encoding) {
    return encoding->kind != PM_ENCODING_KIND_SINGLE_BYTE && encoding->kind != PM_ENCODING_KIND_ASCII;
}

/*
 * All of the lookup tables use the first bit of each embedded byte to indicate
 * whether the codepoint is alphabetical.
 */
#define PRISM_ENCODING_ALPHABETIC_BIT (1 << 0)

/*
 * All of the lookup tables use the second bit of each embedded byte to indicate
 * whether the codepoint is alphanumeric.
 */
#define PRISM_ENCODING_ALPHANUMERIC_BIT (1 << 1)

/*
 * All of the lookup tables use the third bit of each embedded byte to indicate
 * whether the codepoint is uppercase.
 */
#define PRISM_ENCODING_UPPERCASE_BIT (1 << 2)

/*
 * Return the number of bytes in the next character in the given encoding, or 0
 * if the bytes do not form one.
 */
size_t pm_encoding_char_width(const pm_encoding_t *encoding, const uint8_t *b, ptrdiff_t n);

/*
 * Return the number of bytes in the next character in the given encoding if it
 * has the given PRISM_ENCODING_*_BIT property, or 0 otherwise.
 */
size_t pm_encoding_property_char(const pm_encoding_t *encoding, uint8_t property, const uint8_t *b, ptrdiff_t n);

/*
 * Return the number of bytes in the next character in the given encoding if it
 * is alphabetical, or 0 otherwise.
 */
static PRISM_INLINE size_t
pm_encoding_alpha_char(const pm_encoding_t *encoding, const uint8_t *b, ptrdiff_t n) {
    return pm_encoding_property_char(encoding, PRISM_ENCODING_ALPHABETIC_BIT, b, n);
}

/*
 * Return the number of bytes in the next character in the given encoding if it
 * is alphanumeric, or 0 otherwise.
 */
static PRISM_INLINE size_t
pm_encoding_alnum_char(const pm_encoding_t *encoding, const uint8_t *b, ptrdiff_t n) {
    return pm_encoding_property_char(encoding, PRISM_ENCODING_ALPHANUMERIC_BIT, b, n);
}

/*
 * Return true if the next character in the given encoding is uppercase.
 */
static PRISM_INLINE bool
pm_encoding_isupper_char(const pm_encoding_t *encoding, const uint8_t *b, ptrdiff_t n) {
    return pm_encoding_property_char(encoding, PRISM_ENCODING_UPPERCASE_BIT, b, n) != 0;
}

/* Return the size of the next character in the UTF-8 encoding. */
size_t pm_encoding_utf_8_char_width(const uint8_t *b, ptrdiff_t n);

/*
 * Return the size of the next character in the UTF-8 encoding if it is an
 * alphabetical character.
 */
size_t pm_encoding_utf_8_alpha_char(const uint8_t *b, ptrdiff_t n);

/*
 * Return the size of the next character in the UTF-8 encoding if it is an
 * alphanumeric character.
 */
size_t pm_encoding_utf_8_alnum_char(const uint8_t *b, ptrdiff_t n);

/*
 * Return true if the next character in the UTF-8 encoding if it is an uppercase
 * character.
 */
bool pm_encoding_utf_8_isupper_char(const uint8_t *b, ptrdiff_t n);

/*
 * This lookup table indicates whether a US-ASCII character is alphabetical,
 * alphanumeric, or uppercase. It is referenced in both the UTF-8 encoding
 * functions and the parser directly in order to speed up processing ASCII
 * bytes in the default encoding, since every ASCII character is encoded as
 * itself in UTF-8.
 */
extern const uint8_t pm_encoding_ascii_table[256];

/* These are all of the encodings that prism supports. */
typedef enum {
    PM_ENCODING_UTF_8 = 0,
    PM_ENCODING_US_ASCII,
    PM_ENCODING_ASCII_8BIT,
    PM_ENCODING_EUC_JP,
    PM_ENCODING_WINDOWS_31J,

/* We optionally support excluding the full set of encodings to only support the
 * minimum necessary to process Ruby code without encoding comments. */
#ifndef PRISM_ENCODING_EXCLUDE_FULL
    PM_ENCODING_BIG5,
    PM_ENCODING_BIG5_HKSCS,
    PM_ENCODING_BIG5_UAO,
    PM_ENCODING_CESU_8,
    PM_ENCODING_CP51932,
    PM_ENCODING_CP850,
    PM_ENCODING_CP852,
    PM_ENCODING_CP855,
    PM_ENCODING_CP949,
    PM_ENCODING_CP950,
    PM_ENCODING_CP951,
    PM_ENCODING_EMACS_MULE,
    PM_ENCODING_EUC_JP_MS,
    PM_ENCODING_EUC_JIS_2004,
    PM_ENCODING_EUC_KR,
    PM_ENCODING_EUC_TW,
    PM_ENCODING_GB12345,
    PM_ENCODING_GB18030,
    PM_ENCODING_GB1988,
    PM_ENCODING_GB2312,
    PM_ENCODING_GBK,
    PM_ENCODING_IBM437,
    PM_ENCODING_IBM720,
    PM_ENCODING_IBM737,
    PM_ENCODING_IBM775,
    PM_ENCODING_IBM852,
    PM_ENCODING_IBM855,
    PM_ENCODING_IBM857,
    PM_ENCODING_IBM860,
    PM_ENCODING_IBM861,
    PM_ENCODING_IBM862,
    PM_ENCODING_IBM863,
    PM_ENCODING_IBM864,
    PM_ENCODING_IBM865,
    PM_ENCODING_IBM866,
    PM_ENCODING_IBM869,
    PM_ENCODING_ISO_8859_1,
    PM_ENCODING_ISO_8859_2,
    PM_ENCODING_ISO_8859_3,
    PM_ENCODING_ISO_8859_4,
    PM_ENCODING_ISO_8859_5,
    PM_ENCODING_ISO_8859_6,
    PM_ENCODING_ISO_8859_7,
    PM_ENCODING_ISO_8859_8,
    PM_ENCODING_ISO_8859_9,
    PM_ENCODING_ISO_8859_10,
    PM_ENCODING_ISO_8859_11,
    PM_ENCODING_ISO_8859_13,
    PM_ENCODING_ISO_8859_14,
    PM_ENCODING_ISO_8859_15,
    PM_ENCODING_ISO_8859_16,
    PM_ENCODING_KOI8_R,
    PM_ENCODING_KOI8_U,
    PM_ENCODING_MAC_CENT_EURO,
    PM_ENCODING_MAC_CROATIAN,
    PM_ENCODING_MAC_CYRILLIC,
    PM_ENCODING_MAC_GREEK,
    PM_ENCODING_MAC_ICELAND,
    PM_ENCODING_MAC_JAPANESE,
    PM_ENCODING_MAC_ROMAN,
    PM_ENCODING_MAC_ROMANIA,
    PM_ENCODING_MAC_THAI,
    PM_ENCODING_MAC_TURKISH,
    PM_ENCODING_MAC_UKRAINE,
    PM_ENCODING_SHIFT_JIS,
    PM_ENCODING_SJIS_DOCOMO,
    PM_ENCODING_SJIS_KDDI,
    PM_ENCODING_SJIS_SOFTBANK,
    PM_ENCODING_STATELESS_ISO_2022_JP,
    PM_ENCODING_STATELESS_ISO_2022_JP_KDDI,
    PM_ENCODING_TIS_620,
    PM_ENCODING_UTF8_MAC,
    PM_ENCODING_UTF8_DOCOMO,
    PM_ENCODING_UTF8_KDDI,
    PM_ENCODING_UTF8_SOFTBANK,
    PM_ENCODING_WINDOWS_1250,
    PM_ENCODING_WINDOWS_1251,
    PM_ENCODING_WINDOWS_1252,
    PM_ENCODING_WINDOWS_1253,
    PM_ENCODING_WINDOWS_1254,
    PM_ENCODING_WINDOWS_1255,
    PM_ENCODING_WINDOWS_1256,
    PM_ENCODING_WINDOWS_1257,
    PM_ENCODING_WINDOWS_1258,
    PM_ENCODING_WINDOWS_874,
#endif

    PM_ENCODING_MAXIMUM
} pm_encoding_type_t;

/* This is the table of all of the encodings that prism supports. */
extern const pm_encoding_t pm_encodings[PM_ENCODING_MAXIMUM];

/*
 * This is the default UTF-8 encoding. We need a reference to it to quickly
 * create parsers.
 */
#define PM_ENCODING_UTF_8_ENTRY (&pm_encodings[PM_ENCODING_UTF_8])

/*
 * This is the US-ASCII encoding. We need a reference to it to be able to
 * compare against it when a string is being created because it could possibly
 * need to fall back to ASCII-8BIT.
 */
#define PM_ENCODING_US_ASCII_ENTRY (&pm_encodings[PM_ENCODING_US_ASCII])

/*
 * This is the ASCII-8BIT encoding. We need a reference to it so that pm_strpbrk
 * can compare against it because invalid multibyte characters are not a thing
 * in this encoding. It is also needed for handling Regexp encoding flags.
 */
#define PM_ENCODING_ASCII_8BIT_ENTRY (&pm_encodings[PM_ENCODING_ASCII_8BIT])

/*
 * This is the EUC-JP encoding. We need a reference to it to quickly process
 * regular expression modifiers.
 */
#define PM_ENCODING_EUC_JP_ENTRY (&pm_encodings[PM_ENCODING_EUC_JP])

/*
 * This is the Windows-31J encoding. We need a reference to it to quickly
 * process regular expression modifiers.
 */
#define PM_ENCODING_WINDOWS_31J_ENTRY (&pm_encodings[PM_ENCODING_WINDOWS_31J])

/*
 * Parse the given name of an encoding and return a pointer to the corresponding
 * encoding struct if one can be found, otherwise return NULL.
 */
const pm_encoding_t * pm_encoding_find(const uint8_t *start, const uint8_t *end);

#endif
