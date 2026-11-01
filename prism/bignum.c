#include "prism/internal/bignum.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * Multiplications where the shorter number has fewer words than this use the
 * schoolbook method, which is faster than Karatsuba's at small sizes.
 */
#define PM_BIGNUM_KARATSUBA_THRESHOLD 24

/*
 * Add right into left, in place. The sum must fit in left's length words.
 */
static void
pm_bignum_words_add(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    uint64_t carry = 0;
    uint32_t index = 0;

    for (; index < right_length; index++) {
        carry += (uint64_t) left[index] + right[index];
        left[index] = (uint32_t) carry;
        carry >>= 32;
    }

    for (; carry != 0; index++) {
        assert(index < left_length);
        carry += left[index];
        left[index] = (uint32_t) carry;
        carry >>= 32;
    }
}

/*
 * Subtract right from left, in place. Left must be at least right. A word minus
 * a word minus a borrow wraps around to a value with its top bit set exactly
 * when it is negative, so that bit is the next borrow.
 */
static void
pm_bignum_words_subtract(uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length) {
    uint64_t borrow = 0;
    uint32_t index = 0;

    for (; index < right_length; index++) {
        uint64_t difference = (uint64_t) left[index] - right[index] - borrow;
        left[index] = (uint32_t) difference;
        borrow = difference >> 63;
    }

    for (; borrow != 0; index++) {
        assert(index < left_length);
        uint64_t difference = (uint64_t) left[index] - borrow;
        left[index] = (uint32_t) difference;
        borrow = difference >> 63;
    }
}

/*
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

/*
 * Multiply left by right into result, which has room for left_length +
 * right_length words and overlaps neither. Above PM_BIGNUM_KARATSUBA_THRESHOLD
 * this uses Karatsuba's method: splitting each number into low and high halves
 * at the same word, low * low and high * high go straight into the bottom and
 * top of the result, and the middle term is (low + high) * (low + high) minus
 * those two, which takes three multiplications of half the size instead of
 * four.
 */
static void
pm_bignum_words_multiply(uint32_t *result, const uint32_t *left, uint32_t left_length, const uint32_t *right, uint32_t right_length, pm_bignum_scratch_t *scratch) {
    if (left_length < right_length) {
        const uint32_t *words = left;
        left = right;
        right = words;

        uint32_t length = left_length;
        left_length = right_length;
        right_length = length;
    }

    if (right_length < PM_BIGNUM_KARATSUBA_THRESHOLD) {
        pm_bignum_words_multiply_schoolbook(result, left, left_length, right, right_length);
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
            pm_bignum_words_multiply(product, left + offset, piece, right, right_length, scratch);
            pm_bignum_words_add(result + offset, left_length + right_length - offset, product, piece + right_length);
        }

        scratch->cursor = saved;
        return;
    }

    uint32_t half = right_length / 2;
    uint32_t left_high_length = left_length - half;
    uint32_t right_high_length = right_length - half;

    pm_bignum_words_multiply(result, left, half, right, half, scratch);
    pm_bignum_words_multiply(result + 2 * half, left + half, left_high_length, right + half, right_high_length, scratch);

    /* Each high half is at least as long as the low half, so adding the low
     * half into a copy of the high half needs at most one more word. */
    uint32_t *left_sum = pm_bignum_scratch_take(scratch, left_high_length + 1);
    memcpy(left_sum, left + half, sizeof(uint32_t) * left_high_length);
    left_sum[left_high_length] = 0;
    pm_bignum_words_add(left_sum, left_high_length + 1, left, half);

    uint32_t *right_sum = pm_bignum_scratch_take(scratch, right_high_length + 1);
    memcpy(right_sum, right + half, sizeof(uint32_t) * right_high_length);
    right_sum[right_high_length] = 0;
    pm_bignum_words_add(right_sum, right_high_length + 1, right, half);

    uint32_t middle_length = left_high_length + right_high_length + 2;
    uint32_t *middle = pm_bignum_scratch_take(scratch, middle_length);
    pm_bignum_words_multiply(middle, left_sum, left_high_length + 1, right_sum, right_high_length + 1, scratch);
    pm_bignum_words_subtract(middle, middle_length, result, 2 * half);
    pm_bignum_words_subtract(middle, middle_length, result + 2 * half, left_high_length + right_high_length);

    while (middle_length > 0 && middle[middle_length - 1] == 0) middle_length--;
    pm_bignum_words_add(result + half, left_length + right_length - half, middle, middle_length);

    scratch->cursor = saved;
}

/*
 * Add right into left, in place. The storage must have room for the sum, which
 * is at most one word longer than the longer of the two.
 */
void
pm_bignum_add(pm_bignum_t *left, const pm_bignum_t *right) {
    if (left->length < right->length) {
        memset(left->words + left->length, 0, sizeof(uint32_t) * (right->length - left->length));
        left->length = right->length;
    }

    uint64_t carry = 0;
    uint32_t index = 0;

    for (; index < right->length; index++) {
        carry += (uint64_t) left->words[index] + right->words[index];
        left->words[index] = (uint32_t) carry;
        carry >>= 32;
    }

    for (; carry != 0 && index < left->length; index++) {
        carry += left->words[index];
        left->words[index] = (uint32_t) carry;
        carry >>= 32;
    }

    if (carry != 0) left->words[left->length++] = (uint32_t) carry;
}

/*
 * Multiply left by right into result, whose storage has room for
 * left->length + right->length words and overlaps neither. Long numbers use
 * Karatsuba's method, which takes its temporaries from scratch.
 */
void
pm_bignum_multiply(pm_bignum_t *result, const pm_bignum_t *left, const pm_bignum_t *right, pm_bignum_scratch_t *scratch) {
    uint32_t length = left->length + right->length;
    pm_bignum_words_multiply(result->words, left->words, left->length, right->words, right->length, scratch);

    while (length > 0 && result->words[length - 1] == 0) length--;
    result->length = length;
}
