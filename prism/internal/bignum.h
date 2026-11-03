/*
 * Arithmetic on arbitrary-precision unsigned integers stored as arrays of
 * 32-bit words.
 */
#ifndef PRISM_INTERNAL_BIGNUM_H
#define PRISM_INTERNAL_BIGNUM_H

#include "prism/compiler/inline.h"

#include "prism/internal/assert.h"
#include "prism/internal/bit.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * The base of the words of a number.
 */
#define PM_BIGNUM_BINARY_BASE ((uint64_t) 1 << 32)

/*
 * The base of the words of a decimal number, each of which is nine digits.
 */
#define PM_BIGNUM_DECIMAL_BASE 1000000000

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
    PRISM_ASSERT(multiplier != 0);
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
    PRISM_ASSERT(divisor != 0);
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
 * Divide the number by divisor if it divides evenly, and return whether it did.
 * Otherwise the number is left unchanged: multiplying the quotient back and
 * adding the remainder restores it exactly.
 */
static PRISM_INLINE bool
pm_bignum_div_exact(pm_bignum_t *bignum, uint32_t divisor) {
    uint32_t remainder = pm_bignum_div(bignum, divisor);
    if (remainder == 0) return true;

    pm_bignum_mul_add(bignum, divisor, remainder);
    return false;
}

/*
 * Shift the number left by count bits, in place. The words grow by count / 32
 * plus possibly one more, so the storage must have room for them.
 */
static PRISM_INLINE void
pm_bignum_shift_left(pm_bignum_t *bignum, size_t count) {
    if (bignum->length == 0) return;

    uint32_t *words = bignum->words;
    uint32_t length = bignum->length;
    uint32_t word_shift = (uint32_t) (count / 32);
    uint32_t bit_shift = (uint32_t) (count % 32);

    /* Work down from the top word, so each word is read before the word that
     * replaces it is written. */
    uint32_t carry = bit_shift == 0 ? 0 : words[length - 1] >> (32 - bit_shift);
    for (uint32_t index = length; index > 0; index--) {
        uint32_t below = (bit_shift == 0 || index == 1) ? 0 : words[index - 2] >> (32 - bit_shift);
        words[index - 1 + word_shift] = (words[index - 1] << bit_shift) | below;
    }

    memset(words, 0, sizeof(uint32_t) * word_shift);
    bignum->length = length + word_shift;
    if (carry != 0) words[bignum->length++] = carry;
}

/*
 * Shift the number right by count bits, in place, dropping the bits that are
 * shifted out.
 */
static PRISM_INLINE void
pm_bignum_shift_right(pm_bignum_t *bignum, size_t count) {
    uint32_t *words = bignum->words;
    uint32_t word_shift = (uint32_t) (count / 32);
    uint32_t bit_shift = (uint32_t) (count % 32);

    if (word_shift >= bignum->length) {
        bignum->length = 0;
        return;
    }

    /* Work up from the bottom word, so each word is read before the word that
     * replaces it is written. */
    uint32_t length = bignum->length - word_shift;
    for (uint32_t index = 0; index < length; index++) {
        uint32_t above = (bit_shift == 0 || index + 1 == length) ? 0 : words[index + word_shift + 1] << (32 - bit_shift);
        words[index] = (words[index + word_shift] >> bit_shift) | above;
    }

    bignum->length = length;
    if (words[length - 1] == 0) bignum->length--;
}

/*
 * Return the number of trailing zero bits in a nonzero number. Its top word is
 * nonzero, so the scan for the first nonzero word stops within its length.
 */
static PRISM_INLINE uint64_t
pm_bignum_trailing_zeros(const pm_bignum_t *bignum) {
    PRISM_ASSERT(bignum->length > 0 && bignum->words[bignum->length - 1] != 0);

    uint32_t index = 0;
    while (bignum->words[index] == 0) index++;
    return (uint64_t) index * 32 + pm_ctzll(bignum->words[index]);
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

/*
 * Return the value of a number of at most two words. Words past the length may
 * hold stale values after an in-place operation, so only the words in use are
 * read.
 */
static PRISM_INLINE uint64_t
pm_bignum_uint64(const pm_bignum_t *bignum) {
    PRISM_ASSERT(bignum->length <= 2);
    return (bignum->length > 0 ? (uint64_t) bignum->words[0] : 0) | (bignum->length > 1 ? (uint64_t) bignum->words[1] << 32 : 0);
}

/*
 * Temporary words for the operations that need them, taken and given back in
 * stack order: an operation saves the cursor, takes what it needs, and
 * restores the cursor before it returns.
 */
typedef struct {
    /* The next free word. */
    uint32_t *cursor;

    /* One past the last word. */
    uint32_t *end;
} pm_bignum_scratch_t;

/*
 * Take count words from the scratch space.
 */
static PRISM_INLINE uint32_t *
pm_bignum_scratch_take(pm_bignum_scratch_t *scratch, uint32_t count) {
    PRISM_ASSERT((size_t) (scratch->end - scratch->cursor) >= count);
    uint32_t *words = scratch->cursor;
    scratch->cursor += count;
    return words;
}

/*
 * Add right into left, in place. The storage must have room for the sum, which
 * is at most one word longer than the longer of the two.
 */
void pm_bignum_add(pm_bignum_t *left, const pm_bignum_t *right);

/*
 * Multiply left by right into result, whose storage has room for
 * left->length + right->length words and overlaps neither. Long numbers use
 * Karatsuba's method, which takes its temporaries from scratch.
 */
void pm_bignum_multiply(pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch);

/*
 * Add right into left, in place, in base 10**9. The storage must have room for
 * the sum, which is at most one word longer than the longer of the two.
 */
void pm_bignum_decimal_add(pm_bignum_t *left, const pm_bignum_t *right);

/*
 * Multiply left by right into result, in base 10**9, whose storage has room
 * for left->length + right->length words and overlaps neither. Long numbers
 * use Karatsuba's method, which takes its temporaries from scratch.
 */
void pm_bignum_decimal_multiply(pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch);

#endif
