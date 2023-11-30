/**
 * @file encoding.h
 *
 * The encoding interface and implementations used by the parser.
 */
#ifndef PRISM_ENCODING_H
#define PRISM_ENCODING_H

#include "prism/defines.h"
#include "prism/util/pm_strncasecmp.h"

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

/**
 * This is the default encoding for Ruby source files. We keep a specific
 * visible pointer around to it so that prism.c can compare it against the
 * default.
 */
extern pm_encoding_t pm_encoding_utf_8;

/**
 * Parse the given name of an encoding and return a pointer to the corresponding
 * encoding struct if one can be found, otherwise return NULL.
 *
 * @param start A pointer to the first byte of the name.
 * @param end A pointer to the last byte of the name.
 * @returns A pointer to the encoding it finds, otherwise NULL.
 */
pm_encoding_t * pm_encoding_find(const uint8_t *start, const uint8_t *end);

#endif
