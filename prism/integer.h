/**
 * @file integer.h
 *
 * This module provides functions for working with arbitrary-sized integers.
 */
#ifndef PRISM_INTEGER_H
#define PRISM_INTEGER_H

#include "prism/compiler/inline.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * A structure represents an arbitrary-sized integer. The magnitude is stored as
 * 32-bit words, least significant first.
 */
typedef struct {
    /**
     * The number of words in the magnitude, with no leading zero words. Zero
     * has no words, so a zeroed pm_integer_t is always positive zero.
     */
    uint32_t length;

    /**
     * Whether or not the integer is negative.
     */
    bool negative;

    /**
     * The words of the magnitude. Read them through pm_integer_words rather
     * than directly.
     */
    union {
        /**
         * The words of an integer whose length is at most 2. Words past the
         * length are zero.
         */
        uint32_t value[2];

        /**
         * The words of an integer whose length is greater than 2.
         */
        uint32_t *values;
    } words;
} pm_integer_t;

/**
 * Return the words of an integer, least significant first.
 *
 * @param integer The integer to read.
 * @param length Set to the number of words returned, which is 0 for zero.
 * @returns A pointer to the words, valid for as long as the integer is.
 */
static PRISM_INLINE const uint32_t *
pm_integer_words(const pm_integer_t *integer, uint32_t *length) {
    *length = integer->length;

    if (integer->length <= 2) {
        return integer->words.value;
    } else {
        return integer->words.values;
    }
}

#endif
