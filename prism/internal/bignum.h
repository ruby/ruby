/*
 * Arithmetic on arbitrary-precision unsigned integers stored as arrays of
 * 32-bit words.
 */
#ifndef PRISM_INTERNAL_BIGNUM_H
#define PRISM_INTERNAL_BIGNUM_H

#include "prism/compiler/inline.h"

#include <assert.h>
#include <stdint.h>

/*
 * An arbitrary-precision unsigned integer.
 */
typedef struct {
    /* The number of words in use. */
    uint32_t length;

    /* The words, least significant first. */
    uint32_t *words;
} pm_bignum_t;

/*
 * Multiply the number by multiplier and add addend, in place. A word times a
 * word plus a word is at most 2**64 - 2**32, so each intermediate product fits
 * in a uint64_t. A nonzero carry out of the top word becomes a new top word, so
 * the storage must have room for it.
 */
static PRISM_INLINE void
pm_bignum_mul_add(pm_bignum_t *bignum, uint32_t multiplier, uint32_t addend) {
    assert(multiplier != 0);
    uint64_t carry = addend;

    for (uint32_t index = 0; index < bignum->length; index++) {
        uint64_t product = (uint64_t) bignum->words[index] * multiplier + carry;
        bignum->words[index] = (uint32_t) product;
        carry = product >> 32;
    }

    if (carry != 0) bignum->words[bignum->length++] = (uint32_t) carry;
}

/*
 * Divide the number by divisor, in place, working down from the top word.
 * Returns the remainder. The remainder is always below the divisor, so shifting
 * it above the next word fits in a uint64_t, and since the divisor is a single
 * word the quotient is at most one word shorter. When inlined with a constant
 * divisor, the compiler replaces the division with a multiplication.
 */
static PRISM_INLINE uint32_t
pm_bignum_div(pm_bignum_t *bignum, uint32_t divisor) {
    assert(divisor != 0);
    uint64_t remainder = 0;

    for (uint32_t index = bignum->length; index > 0; index--) {
        uint64_t current = (remainder << 32) | bignum->words[index - 1];
        bignum->words[index - 1] = (uint32_t) (current / divisor);
        remainder = current % divisor;
    }

    if (bignum->length > 0 && bignum->words[bignum->length - 1] == 0) bignum->length--;
    return (uint32_t) remainder;
}

/*
 * Compare two numbers. Returns -1 if left is less than right, 0 if they are
 * equal, and 1 if left is greater than right.
 */
static PRISM_INLINE int
pm_bignum_compare(const pm_bignum_t *left, const pm_bignum_t *right) {
    if (left->length != right->length) return left->length < right->length ? -1 : 1;

    for (uint32_t index = left->length; index > 0; index--) {
        uint32_t left_word = left->words[index - 1];
        uint32_t right_word = right->words[index - 1];
        if (left_word != right_word) return left_word < right_word ? -1 : 1;
    }

    return 0;
}

#endif
