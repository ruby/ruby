#include "prism/internal/bignum.h"

#include "prism/compiler/force_inline.h"
#include "prism/internal/assert.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/**
 * Multiplications where the shorter number has fewer words than this use the
 * schoolbook method, which is faster than Karatsuba's at small sizes.
 */
#define PM_BIGNUM_KARATSUBA_THRESHOLD 24

/**
 * Add right into left, in place, in the given base, where left is at least as
 * long. Returns the carry out of left's length words. Two words plus a carry
 * are below twice the base, so each sum fits in a uint64_t and carries at most
 * one into the next word.
 */
static PRISM_FORCE_INLINE uint32_t
pm_bignum_base_words_add(uint64_t base, uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    uint32_t carry = 0;
    uint32_t index = 0;

    for (; index < right_length; index++) {
        uint64_t sum = (uint64_t) left[index] + right[index] + carry;
        carry = sum >= base;
        left[index] = (uint32_t) (carry ? sum - base : sum);
    }

    for (; carry != 0 && index < left_length; index++) {
        uint64_t sum = (uint64_t) left[index] + 1;
        carry = sum == base;
        left[index] = (uint32_t) (carry ? 0 : sum);
    }

    return carry;
}

/**
 * Subtract right from left, in place, in the given base. Left must be at least
 * right. A word plus the base fits in a uint64_t, so borrowing does too.
 */
static PRISM_FORCE_INLINE void
pm_bignum_base_words_subtract(uint64_t base, uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    (void) left_length;
    uint32_t borrow = 0;
    uint32_t index = 0;

    for (; index < right_length; index++) {
        uint64_t subtrahend = (uint64_t) right[index] + borrow;
        borrow = left[index] < subtrahend;
        left[index] = (uint32_t) (borrow ? left[index] + base - subtrahend : left[index] - subtrahend);
    }

    for (; borrow != 0; index++) {
        PRISM_ASSERT(index < left_length);
        borrow = left[index] == 0;
        left[index] = (uint32_t) (borrow ? base - 1 : left[index] - 1);
    }
}

/**
 * Add right into left, in place, in base 2**32, where left is at least as
 * long. Returns the carry out of left's length words.
 */
static uint32_t
pm_bignum_words_add(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    return pm_bignum_base_words_add(PM_BIGNUM_BINARY_BASE, left, left_length, right, right_length);
}

/**
 * Add right into left, in place, in base 10**9, where left is at least as
 * long. Returns the carry out of left's length words.
 */
static uint32_t
pm_bignum_decimal_words_add(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    return pm_bignum_base_words_add(PM_BIGNUM_DECIMAL_BASE, left, left_length, right, right_length);
}

/**
 * Subtract right from left, in place, in base 2**32. Left must be at least
 * right.
 */
static void
pm_bignum_words_subtract(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    pm_bignum_base_words_subtract(PM_BIGNUM_BINARY_BASE, left, left_length, right, right_length);
}

/**
 * Subtract right from left, in place, in base 10**9. Left must be at least
 * right.
 */
static void
pm_bignum_decimal_words_subtract(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    pm_bignum_base_words_subtract(PM_BIGNUM_DECIMAL_BASE, left, left_length, right, right_length);
}

/**
 * Multiply left by right into result, which has room for left_length +
 * right_length words and overlaps neither, using the schoolbook method. A word
 * times a word plus two words is at most 2**64 - 1, so each step fits in a
 * uint64_t.
 */
static void
pm_bignum_words_multiply_schoolbook(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    memset(result, 0, sizeof(uint32_t) * (left_length + right_length));

    for (uint32_t right_index = 0; right_index < right_length; right_index++) {
        uint64_t carry = 0;

        for (uint32_t left_index = 0; left_index < left_length; left_index++) {
            carry += (uint64_t) left[left_index] * right[right_index] + result[left_index + right_index];
            result[left_index + right_index] = (uint32_t) carry;
            carry >>= 32;
        }

        result[right_index + left_length] = (uint32_t) carry;
    }
}

/**
 * The number of products of two words in base 10**9 that can be added to a
 * word before the sum could overflow a uint64_t: 18 * (10**9 - 1)**2 plus
 * 10**9 - 1 is just below 1.8 * 10**19, while 2**64 is just above
 * 1.84 * 10**19.
 */
#define PM_BIGNUM_DECIMAL_PRODUCTS 18

/**
 * Multiply left by right into result, in base 10**9, which has room for
 * left_length + right_length words and overlaps neither, using the schoolbook
 * method. Dividing by 10**9 is what costs the most here, so each word of the
 * result is computed in one go as the sum of the products of the pairs of
 * words that land on it, which only divides once every
 * PM_BIGNUM_DECIMAL_PRODUCTS products to keep the sum in a uint64_t, and once
 * more to carry into the next word.
 */
static void
pm_bignum_decimal_words_multiply_schoolbook(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    if (left_length == 0 || right_length == 0) {
        memset(result, 0, sizeof(uint32_t) * (left_length + right_length));
        return;
    }

    /* The sum of every column is below its number of products times 10**18,
     * and there are fewer than 2**29 products in a column, so the carry into
     * the next column is below 2**29 * 10**9 and fits in a uint64_t. */
    uint64_t carry = 0;

    for (uint32_t index = 0; index < left_length + right_length - 1; index++) {
        uint32_t left_start = index < right_length ? 0 : index - right_length + 1;
        uint32_t left_end = index < left_length ? index + 1 : left_length;

        uint64_t low = 0;
        uint64_t high = 0;
        uint32_t products = 0;

        for (uint32_t left_index = left_start; left_index < left_end; left_index++) {
            low += (uint64_t) left[left_index] * right[index - left_index];

            if (++products == PM_BIGNUM_DECIMAL_PRODUCTS) {
                high += low / PM_BIGNUM_DECIMAL_BASE;
                low %= PM_BIGNUM_DECIMAL_BASE;
                products = 0;
            }
        }

        low += carry % PM_BIGNUM_DECIMAL_BASE;
        high += carry / PM_BIGNUM_DECIMAL_BASE;

        result[index] = (uint32_t) (low % PM_BIGNUM_DECIMAL_BASE);
        carry = high + low / PM_BIGNUM_DECIMAL_BASE;
    }

    /* The product is below 10**(9 * (left_length + right_length)), so what is
     * left over is the top word. */
    PRISM_ASSERT(carry < PM_BIGNUM_DECIMAL_BASE);
    result[left_length + right_length - 1] = (uint32_t) carry;
}

static void pm_bignum_words_multiply(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch);
static void pm_bignum_decimal_words_multiply(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch);

/**
 * The helpers below take the base of the words, 2**32 or 10**9, as a
 * parameter, but are always inlined into callers that pass a constant, so the
 * choice is made at compile time and every call they make is direct.
 */

/**
 * Add right into left in the given base. Returns the carry out of left's
 * length words.
 */
static PRISM_FORCE_INLINE uint32_t
pm_bignum_radix_add(uint64_t base, uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    return base == PM_BIGNUM_DECIMAL_BASE ? pm_bignum_decimal_words_add(left, left_length, right, right_length) : pm_bignum_words_add(left, left_length, right, right_length);
}

/**
 * Subtract right from left in the given base.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_subtract(uint64_t base, uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    if (base == PM_BIGNUM_DECIMAL_BASE) {
        pm_bignum_decimal_words_subtract(left, left_length, right, right_length);
    } else {
        pm_bignum_words_subtract(left, left_length, right, right_length);
    }
}

/**
 * Multiply left by right with the schoolbook method in the given base.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_multiply_schoolbook(uint64_t base, uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    if (base == PM_BIGNUM_DECIMAL_BASE) {
        pm_bignum_decimal_words_multiply_schoolbook(result, left, left_length, right, right_length);
    } else {
        pm_bignum_words_multiply_schoolbook(result, left, left_length, right, right_length);
    }
}

/**
 * Multiply left by right in the given base.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_multiply(uint64_t base, uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch) {
    if (base == PM_BIGNUM_DECIMAL_BASE) {
        pm_bignum_decimal_words_multiply(result, left, left_length, right, right_length, scratch);
    } else {
        pm_bignum_words_multiply(result, left, left_length, right, right_length, scratch);
    }
}

/**
 * Multiply left by right into result, which has room for left_length +
 * right_length words and overlaps neither, in the given base. Above
 * PM_BIGNUM_KARATSUBA_THRESHOLD this uses Karatsuba's method: splitting each
 * number into low and high halves at the same word, low * low and high * high
 * go straight into the bottom and top of the result, and the middle term is
 * (low + high) * (low + high) minus those two, which takes three
 * multiplications of half the size instead of four. None of this depends on
 * the base, only the additions, subtractions, and schoolbook multiplications
 * that it is built from.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_karatsuba(uint64_t base, uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch) {
    if (left_length < right_length) {
        const uint32_t *words = left;
        left = right;
        right = words;

        uint32_t length = left_length;
        left_length = right_length;
        right_length = length;
    }

    if (right_length < PM_BIGNUM_KARATSUBA_THRESHOLD) {
        pm_bignum_radix_multiply_schoolbook(base, result, left, left_length, right, right_length);
        return;
    }

    uint32_t *saved = scratch->cursor;

    /* When left is at least twice as long, splitting both at the same word
     * would leave the halves badly mismatched, so instead multiply right by
     * each right-sized piece of left and add the products into the result. */
    if (left_length >= 2 * right_length) {
        memset(result, 0, sizeof(uint32_t) * (left_length + right_length));
        uint32_t *product = pm_bignum_scratch_take(scratch, 2 * right_length);

        for (uint32_t offset = 0; offset < left_length; offset += right_length) {
            uint32_t piece = left_length - offset < right_length ? left_length - offset : right_length;
            pm_bignum_radix_multiply(base, product, left + offset, piece, right, right_length, scratch);
            pm_bignum_radix_add(base, result + offset, left_length + right_length - offset, product, piece + right_length);
        }

        scratch->cursor = saved;
        return;
    }

    uint32_t half = right_length / 2;
    uint32_t left_high_length = left_length - half;
    uint32_t right_high_length = right_length - half;

    pm_bignum_radix_multiply(base, result, left, half, right, half, scratch);
    pm_bignum_radix_multiply(base, result + 2 * half, left + half, left_high_length, right + half, right_high_length, scratch);

    /* Each high half is at least as long as the low half, so adding the low
     * half into a copy of the high half needs at most one more word. */
    uint32_t *left_sum = pm_bignum_scratch_take(scratch, left_high_length + 1);
    memcpy(left_sum, left + half, sizeof(uint32_t) * left_high_length);
    left_sum[left_high_length] = 0;
    pm_bignum_radix_add(base, left_sum, left_high_length + 1, left, half);

    uint32_t *right_sum = pm_bignum_scratch_take(scratch, right_high_length + 1);
    memcpy(right_sum, right + half, sizeof(uint32_t) * right_high_length);
    right_sum[right_high_length] = 0;
    pm_bignum_radix_add(base, right_sum, right_high_length + 1, right, half);

    uint32_t middle_length = left_high_length + right_high_length + 2;
    uint32_t *middle = pm_bignum_scratch_take(scratch, middle_length);
    pm_bignum_radix_multiply(base, middle, left_sum, left_high_length + 1, right_sum, right_high_length + 1, scratch);
    pm_bignum_radix_subtract(base, middle, middle_length, result, 2 * half);
    pm_bignum_radix_subtract(base, middle, middle_length, result + 2 * half, left_high_length + right_high_length);

    while (middle_length > 0 && middle[middle_length - 1] == 0) middle_length--;
    pm_bignum_radix_add(base, result + half, left_length + right_length - half, middle, middle_length);

    scratch->cursor = saved;
}

/**
 * Multiply left by right into result in base 2**32, which has room for
 * left_length + right_length words and overlaps neither.
 */
static void
pm_bignum_words_multiply(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch) {
    pm_bignum_radix_karatsuba(PM_BIGNUM_BINARY_BASE, result, left, left_length, right, right_length, scratch);
}

/**
 * Multiply left by right into result in base 10**9, which has room for
 * left_length + right_length words and overlaps neither.
 */
static void
pm_bignum_decimal_words_multiply(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch) {
    pm_bignum_radix_karatsuba(PM_BIGNUM_DECIMAL_BASE, result, left, left_length, right, right_length, scratch);
}

/**
 * Add right into left, in place, in the given base. Left is zero-extended to
 * the length of right if it is shorter, and a carry out of the top becomes a
 * new top word.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_add_bignum(uint64_t base, pm_bignum_t *left, const pm_bignum_t *right) {
    if (left->length < right->length) {
        memset(left->words + left->length, 0, sizeof(uint32_t) * (right->length - left->length));
        left->length = right->length;
    }

    uint32_t carry = pm_bignum_radix_add(base, left->words, left->length, right->words, right->length);
    if (carry != 0) left->words[left->length++] = carry;
}

/**
 * Multiply left by right into result, in the given base, and trim the zero
 * words off the top of the product.
 */
static PRISM_FORCE_INLINE void
pm_bignum_radix_multiply_bignum(uint64_t base, pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch) {
    uint32_t length = left->length + right->length;
    pm_bignum_radix_multiply(base, result->words, left->words, left->length, right->words, right->length, scratch);

    while (length > 0 && result->words[length - 1] == 0) length--;
    result->length = length;
}

/**
 * Add right into left, in place. The storage must have room for the sum, which
 * is at most one word longer than the longer of the two.
 */
void
pm_bignum_add(pm_bignum_t *left, const pm_bignum_t *right) {
    pm_bignum_radix_add_bignum(PM_BIGNUM_BINARY_BASE, left, right);
}

/**
 * Multiply left by right into result, whose storage has room for
 * left->length + right->length words and overlaps neither. Long numbers use
 * Karatsuba's method, which takes its temporaries from scratch.
 */
void
pm_bignum_multiply(pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch) {
    pm_bignum_radix_multiply_bignum(PM_BIGNUM_BINARY_BASE, result, left, right, scratch);
}

/**
 * Add right into left, in place, in base 10**9. The storage must have room for
 * the sum, which is at most one word longer than the longer of the two.
 */
void
pm_bignum_decimal_add(pm_bignum_t *left, const pm_bignum_t *right) {
    pm_bignum_radix_add_bignum(PM_BIGNUM_DECIMAL_BASE, left, right);
}

/**
 * Multiply left by right into result, in base 10**9, whose storage has room
 * for left->length + right->length words and overlaps neither. Long numbers
 * use Karatsuba's method, which takes its temporaries from scratch.
 */
void
pm_bignum_decimal_multiply(pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch) {
    pm_bignum_radix_multiply_bignum(PM_BIGNUM_DECIMAL_BASE, result, left, right, scratch);
}
