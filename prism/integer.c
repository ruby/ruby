#include "prism/internal/integer.h"

#include "prism/compiler/align.h"
#include "prism/compiler/inline.h"

#include "prism/internal/allocator.h"
#include "prism/internal/arena.h"
#include "prism/internal/bignum.h"
#include "prism/internal/bit.h"
#include "prism/internal/buffer.h"
#include "prism/internal/oom.h"

/* Include sys/types.h before inttypes.h to work around an issue with certain
 * versions of GCC and newlib which causes omission of PRIu64 and the other
 * 64-bit macros. */
#include <sys/types.h>
#include <inttypes.h>

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/**
 * When parsing long decimal digits, we switch to a divide-and-conquer approach
 * once it gets really long because we start to see the impact of an O(n^1.58)
 * vs an O(n^2) algorithm.
 */
#define PM_INTEGER_DIVIDE_THRESHOLD 224

/**
 * When printing integers of many words, we switch to a divide-and-conquer
 * approach for the same reason as parsing: the repeated division by 10**9 is
 * O(n^2), while the divide and conquer is O(n^1.58). Below this many words, the
 * scratch space and the powers of two that the divide and conquer needs cost
 * more than it saves.
 */
#define PM_INTEGER_STRING_THRESHOLD 48

/**
 * Within the divide and conquer, pieces of at most this many words are
 * converted by repeated division by 10**9. This is lower than
 * PM_INTEGER_STRING_THRESHOLD because the pieces share the scratch space and
 * the powers of two, so they do not pay for them again.
 */
#define PM_INTEGER_STRING_LEAF 8

/**
 * The values of a hexadecimal digit, where the index is the ASCII character.
 */
static const int8_t pm_integer_parse_digit_values[256] = {
/*   0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 0x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 1x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 2x */
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1, /* 3x */
    -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 4x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 5x */
    -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 6x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 7x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 8x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* 9x */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Ax */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Bx */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Cx */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Dx */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Ex */
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, /* Fx */
};

/**
 * Return the value of a hexadecimal digit in a uint8_t.
 */
static uint8_t
pm_integer_parse_digit(const uint8_t character) {
    int8_t value = pm_integer_parse_digit_values[character];
    assert(value != -1 && "invalid digit");

    return (uint8_t) value;
}

/**
 * Whether a character between the digits of a number is skipped. Underscores
 * separate digits, and the decimal point of a float rational like 1.5r does not
 * change its numerator, which is all of its digits.
 */
static PRISM_INLINE bool
pm_integer_separator(uint8_t character) {
    return character == '_' || character == '.';
}

/**
 * Store a bignum whose words are allocated in the arena, with room for capacity
 * words, into an integer. An integer with at most two words stores them inline,
 * so all of the arena words are given back; otherwise only the unused ones are.
 */
static void
pm_integer_from_bignum(pm_arena_t *arena, pm_integer_t *integer, const pm_bignum_t *bignum, uint32_t capacity) {
    if (bignum->length <= 2) {
        uint64_t value = pm_bignum_uint64(bignum);
        pm_arena_realloc(arena, bignum->words, 0, sizeof(uint32_t) * capacity, PRISM_ALIGNOF(uint32_t));
        *integer = pm_integer_uint64(value);
    } else {
        uint32_t *words = (uint32_t *) pm_arena_realloc(arena, bignum->words, sizeof(uint32_t) * bignum->length, sizeof(uint32_t) * capacity, PRISM_ALIGNOF(uint32_t));
        *integer = (pm_integer_t) { .length = bignum->length, .words = { .values = words } };
    }
}

/**
 * Parse the digits of an integer in a power-of-two base that does not fit in
 * two words. Every digit but the leading one contributes exactly the same number
 * of bits, so the exact number of words is known before parsing, and the digits
 * are packed directly into words allocated from the arena.
 */
static void
pm_integer_parse_powof2(pm_arena_t *arena, pm_integer_t *integer, uint32_t base, uint32_t digits, const uint8_t *start, const uint8_t *end) {
    static const uint8_t digit_bits[16] = { 0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4 };
    uint32_t leading_bits = digit_bits[pm_integer_parse_digit(*start)];

    uint32_t bit = (uint32_t) pm_ctzll(base);
    assert(bit >= 1 && bit <= 4);

    uint32_t length = (uint32_t) (((uint64_t) (digits - 1) * bit + leading_bits + 31) / 32);
    assert(length > 2);

    uint32_t *words = pm_arena_zalloc(arena, sizeof(uint32_t) * length, PRISM_ALIGNOF(uint32_t));
    uint64_t bit_position = 0;

    for (const uint8_t *cursor = end; cursor > start;) {
        if (pm_integer_separator(*--cursor)) continue;
        uint32_t value = pm_integer_parse_digit(*cursor);

        uint32_t index = (uint32_t) (bit_position / 32);
        uint32_t shift = (uint32_t) (bit_position % 32);

        words[index] |= value << shift;
        if (32 - shift < bit && index + 1 < length) words[index + 1] |= value >> (32 - shift);

        bit_position += bit;
    }

    *integer = (pm_integer_t) { .length = length, .words = { .values = words } };
}

/**
 * The number of words needed to hold a decimal integer with the given number
 * of digits. A number with d digits is below 10**d, so it needs at most:
 *
 *     d * log2(10) + 1
 *
 * bits, which rounds up to at most one word more than the whole words below
 * that count. To find log2(10), we approximate it as 3402/1024, which is
 * slightly greater than the actual value so it does not undercount.
 */
static PRISM_INLINE uint32_t
pm_integer_decimal_words(uint64_t digits) {
    return (uint32_t) ((digits * 3402 / 1024) / 32 + 1);
}

/**
 * The number of words of storage needed to convert nchunks chunks of nine
 * decimal digits, which is one word more than the value needs. The conversion
 * multiplies the high half by a power of ten into this storage, and
 * pm_bignum_multiply writes the sum of its factors' lengths before it trims a
 * zero top word. Each factor's length rounds its bits up to a whole word, so
 * that sum can be one word more than the product needs.
 */
static PRISM_INLINE uint32_t
pm_integer_chunks_words(uint32_t nchunks) {
    return pm_integer_decimal_words((uint64_t) nchunks * 9) + 1;
}

/**
 * Convert nchunks of nine decimal digits into a bignum. Do this by effectively
 * converting the base of the number from 10**9 to 2**32. The result's storage
 * must have room for pm_integer_chunks_words(nchunks) words.
 */
static void
pm_integer_parse_decimal_divide_chunks(pm_bignum_t *result, uint32_t nchunks, const uint32_t *chunks, const pm_bignum_t *powers, pm_bignum_scratch_t *scratch) {
    if (nchunks <= PM_INTEGER_DIVIDE_THRESHOLD) {
        result->length = 0;
        for (uint32_t index = nchunks; index > 0; index--) pm_bignum_mul_add(result, PM_BIGNUM_DECIMAL_BASE, chunks[index - 1]);
    } else {
        uint32_t level = pm_bsrll((uint64_t) nchunks - 1);
        uint32_t split = (uint32_t) 1 << level;

        uint32_t *saved = scratch->cursor;
        pm_bignum_t high = { .length = 0, .words = pm_bignum_scratch_take(scratch, pm_integer_chunks_words(nchunks - split)) };
        pm_integer_parse_decimal_divide_chunks(&high, nchunks - split, chunks + split, powers, scratch);

        assert(high.length + powers[level].length <= pm_integer_chunks_words(nchunks));
        pm_bignum_multiply(result, &high, &powers[level], scratch);
        scratch->cursor = saved;

        pm_bignum_t low = { .length = 0, .words = pm_bignum_scratch_take(scratch, pm_integer_chunks_words(split)) };
        pm_integer_parse_decimal_divide_chunks(&low, split, chunks, powers, scratch);
        pm_bignum_add(result, &low);
        scratch->cursor = saved;
    }
}

/**
 * Parse the digits of a decimal integer of more than
 * PM_INTEGER_DIVIDE_THRESHOLD chunks of nine digits by divide and conquer. The
 * digits are packed into chunks, the powers of ten that the splits need are
 * computed by repeated squaring, and the result is converted straight into
 * words allocated from the arena. Everything else lives in one block of
 * scratch space from the heap, sized for the worst case: the chunks, the
 * powers, and the halves and products of the deepest chain of splits, with
 * Karatsuba's temporaries bounded by 12 times the longer factor's length.
 */
static void
pm_integer_parse_decimal_divide(pm_arena_t *arena, pm_integer_t *integer, uint32_t digits, const uint8_t *start, const uint8_t *end) {
    uint32_t nchunks = (uint32_t) (((uint64_t) digits + 8) / 9);
    uint32_t capacity = pm_integer_chunks_words(nchunks);

    pm_bignum_t result = {
        .length = 0,
        .words = (uint32_t *) pm_arena_alloc(arena, sizeof(uint32_t) * capacity, PRISM_ALIGNOF(uint32_t))
    };

    /* The scratch space is about 12 times the number of chunks, which can
     * exceed 32 bits, and on a 32-bit platform its size in bytes can exceed
     * size_t. */
    uint64_t scratch_size = (uint64_t) nchunks + 12 * (uint64_t) capacity + 1024;
    if (scratch_size > SIZE_MAX / sizeof(uint32_t)) PRISM_OOM();

    uint32_t *allocation = (uint32_t *) xmalloc(sizeof(uint32_t) * (size_t) scratch_size);
    if (allocation == NULL) PRISM_OOM();
    pm_bignum_scratch_t scratch = { .cursor = allocation, .end = allocation + (size_t) scratch_size };

    /* Pack the digits into chunks of nine, least significant first. The most
     * significant chunk takes the leftover digits so the rest are exactly
     * nine. */
    uint32_t *chunks = pm_bignum_scratch_take(&scratch, nchunks);
    uint32_t chunk_size = digits % 9 == 0 ? 9 : digits % 9;
    uint32_t chunk_digits = 0;
    uint32_t chunk_index = nchunks;
    uint32_t chunk = 0;

    for (const uint8_t *cursor = start; cursor < end; cursor++) {
        if (pm_integer_separator(*cursor)) continue;
        chunk = chunk * 10 + pm_integer_parse_digit(*cursor);

        if (++chunk_digits == chunk_size) {
            chunks[--chunk_index] = chunk;
            chunk_size = 9;
            chunk_digits = 0;
            chunk = 0;
        }
    }
    assert(chunk_index == 0);

    /* powers[level] is 10**(9 * 2**level), for every level a split uses. */
    pm_bignum_t powers[64];
    uint32_t level = 0;
    powers[level].words = pm_bignum_scratch_take(&scratch, 1);
    powers[level].words[0] = PM_BIGNUM_DECIMAL_BASE;
    powers[level].length = 1;

    for (uint32_t split = 2; split < nchunks; split *= 2) {
        const pm_bignum_t *previous = &powers[level++];
        powers[level].words = pm_bignum_scratch_take(&scratch, 2 * previous->length);
        pm_bignum_multiply(&powers[level], previous, previous, &scratch);
    }

    pm_integer_parse_decimal_divide_chunks(&result, nchunks, chunks, powers, &scratch);
    xfree_sized(allocation, sizeof(uint32_t) * (size_t) scratch_size);

    assert(result.length > 2 && result.length <= capacity);
    pm_integer_from_bignum(arena, integer, &result, capacity);
}

/**
 * Parse the digits of a decimal integer that does not fit in two words. The
 * words are built in place in the arena: starting from zero, the number is
 * multiplied by 10**9 and the next nine digits are added, until every digit is
 * consumed. The first chunk takes the leftover digits so the rest are exactly
 * nine.
 */
static void
pm_integer_parse_decimal_schoolbook(pm_arena_t *arena, pm_integer_t *integer, uint32_t digits, const uint8_t *start, const uint8_t *end) {
    static const uint32_t powof10[10] = { 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000 };

    /* The words that turn out to be unneeded are given back to the arena
     * below. */
    uint32_t capacity = pm_integer_decimal_words(digits);
    pm_bignum_t bignum = {
        .length = 0,
        .words = (uint32_t *) pm_arena_alloc(arena, sizeof(uint32_t) * capacity, PRISM_ALIGNOF(uint32_t))
    };

    uint32_t chunk_size = digits % 9 == 0 ? 9 : digits % 9;
    uint32_t chunk_digits = 0;
    uint32_t chunk = 0;

    for (const uint8_t *cursor = start; cursor < end; cursor++) {
        if (pm_integer_separator(*cursor)) continue;
        chunk = chunk * 10 + pm_integer_parse_digit(*cursor);

        if (++chunk_digits == chunk_size) {
            pm_bignum_mul_add(&bignum, powof10[chunk_size], chunk);

            chunk_size = 9;
            chunk_digits = 0;
            chunk = 0;
        }
    }

    assert(bignum.length > 2 && bignum.length <= capacity);
    pm_integer_from_bignum(arena, integer, &bignum, capacity);
}

/**
 * Parse the digits of an integer in the given base, after any prefix.
 */
static void
pm_integer_parse_digits(pm_arena_t *arena, pm_integer_t *integer, uint32_t base, const uint8_t *start, const uint8_t *end) {
    /* Leading zeros do not change the value, so skip them here and the paths
     * below always start at a nonzero digit. */
    while (start < end && (*start == '0' || pm_integer_separator(*start))) start++;

    /* Everything has been consumed if the integer is zero, or if it is invalid
     * and has no digits. Either way the result is zero. */
    if (start >= end) {
        *integer = (pm_integer_t) { 0 };
        return;
    }

    /* Accumulate into a uint64_t, which covers every integer whose words are
     * stored inline. value * base + digit overflows exactly when value
     * is past limit, or equal to it with digit past limit_digit. */
    const uint64_t limit = UINT64_MAX / base;
    const uint64_t limit_digit = UINT64_MAX % base;

    const uint8_t *cursor = start;
    uint64_t value = (uint64_t) pm_integer_parse_digit(*cursor++);

    for (; cursor < end; cursor++) {
        if (pm_integer_separator(*cursor)) continue;
        uint64_t digit = (uint64_t) pm_integer_parse_digit(*cursor);

        if (value > limit || (value == limit && digit > limit_digit)) {
            uint32_t digits = 0;
            for (const uint8_t *scan = start; scan < end; scan++) {
                if (!pm_integer_separator(*scan)) digits++;
            }

            if (base != 10) {
                pm_integer_parse_powof2(arena, integer, base, digits, start, end);
            } else if (((uint64_t) digits + 8) / 9 > PM_INTEGER_DIVIDE_THRESHOLD) {
                pm_integer_parse_decimal_divide(arena, integer, digits, start, end);
            } else {
                pm_integer_parse_decimal_schoolbook(arena, integer, digits, start, end);
            }

            return;
        }

        value = value * base + digit;
    }

    *integer = pm_integer_uint64(value);
}

/**
 * Parse an integer from a string. This assumes that the format of the integer
 * has already been validated, as internal validation checks are not performed
 * here.
 */
void
pm_integer_parse(pm_arena_t *arena, pm_integer_t *integer, pm_integer_base_t base, const uint8_t *start, const uint8_t *end) {
    /* Ignore unary +. Unary - is parsed differently and will not end up here.
     * Instead, it will modify the parsed integer later. */
    if (*start == '+') start++;

    /* Skip past any prefixes. */
    switch (base) {
        case PM_INTEGER_BASE_BINARY:
            start += 2; /* 0b */
            break;
        case PM_INTEGER_BASE_OCTAL:
            start++; /* 0 */
            if (*start == '_' || *start == 'o' || *start == 'O') start++; /* o */
            break;
        case PM_INTEGER_BASE_DECIMAL:
            if (*start == '0' && (end - start) > 1) start += 2; /* 0d */
            break;
        case PM_INTEGER_BASE_HEXADECIMAL:
            start += 2; /* 0x */
            break;
    }

    pm_integer_parse_digits(arena, integer, (uint32_t) base, start, end);
}

/**
 * Parse a float rational literal like 1.5r, given its digits and decimal point
 * without the r suffix, into a numerator and denominator in lowest terms. Its
 * value is its digits read as an integer over 10**k, where k is the number of
 * digits after the decimal point. Since 10**k is 2**k * 5**k, the greatest
 * common divisor of the two is a power of two times a power of five, so the
 * fraction is reduced by dividing those out of the numerator and leaving them
 * out of the denominator.
 */
void
pm_integer_parse_rational(pm_arena_t *arena, pm_integer_t *numerator, pm_integer_t *denominator, const uint8_t *start, const uint8_t *end) {
    static const uint32_t powof5[14] = { 1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125, 9765625, 48828125, 244140625, 1220703125 };

    if (*start == '+') start++;

    const uint8_t *point = memchr(start, '.', (size_t) (end - start));
    assert(point != NULL);

    /* Each trailing zero after the decimal point divides both sides by 10, so
     * drop them before parsing. */
    while (end > point + 1 && (end[-1] == '0' || end[-1] == '_')) end--;

    uint32_t exponent = 0;
    for (const uint8_t *cursor = point + 1; cursor < end; cursor++) {
        if (*cursor != '_') exponent++;
    }

    pm_integer_parse_digits(arena, numerator, 10, start, end);
    uint32_t twos = 0;
    uint32_t fives = 0;

    if (numerator->length > 0 && exponent > 0) {
        uint32_t length = numerator->length;
        pm_bignum_t bignum = {
            .length = length,
            .words = length <= 2 ? numerator->words.value : numerator->words.values
        };

        uint64_t trailing = pm_bignum_trailing_zeros(&bignum);
        twos = trailing > exponent ? exponent : (uint32_t) trailing;
        pm_bignum_shift_right(&bignum, twos);

        /* 5**13 is the largest power of five that fits in a word, so divide by
         * it while it divides evenly before dividing by five alone. */
        while (exponent - fives >= 13 && pm_bignum_div_exact(&bignum, powof5[13])) fives += 13;
        while (fives < exponent && pm_bignum_div_exact(&bignum, 5)) fives++;

        if (length <= 2) {
            *numerator = pm_integer_uint64(pm_bignum_uint64(&bignum));
        } else {
            pm_integer_from_bignum(arena, numerator, &bignum, length);
        }
    }

    /* The denominator is what is left of 10**exponent. 2378/1024 is just above
     * log2(5), so this capacity never undercounts. */
    uint32_t remaining_fives = exponent - fives;
    uint32_t remaining_twos = exponent - twos;
    uint32_t capacity = (uint32_t) (((uint64_t) remaining_fives * 2378 / 1024 + remaining_twos + 32) / 32);

    pm_bignum_t bignum = {
        .length = 1,
        .words = (uint32_t *) pm_arena_alloc(arena, sizeof(uint32_t) * capacity, PRISM_ALIGNOF(uint32_t))
    };
    bignum.words[0] = 1;

    for (; remaining_fives >= 13; remaining_fives -= 13) pm_bignum_mul_add(&bignum, powof5[13], 0);
    if (remaining_fives > 0) pm_bignum_mul_add(&bignum, powof5[remaining_fives], 0);
    pm_bignum_shift_left(&bignum, remaining_twos);

    assert(bignum.length <= capacity);
    pm_integer_from_bignum(arena, denominator, &bignum, capacity);
}

/**
 * Return a view of the magnitude of an integer as a bignum. The view's words
 * point into the integer, so it must only be read.
 */
static pm_bignum_t
pm_integer_bignum(const pm_integer_t *integer) {
    uint32_t length;
    const uint32_t *words = pm_integer_words(integer, &length);
    return (pm_bignum_t) { .length = length, .words = (uint32_t *) words };
}

/**
 * Compare two integers. This function returns -1 if the left integer is less
 * than the right integer, 0 if they are equal, and 1 if the left integer is
 * greater than the right integer.
 */
int
pm_integer_compare(const pm_integer_t *left, const pm_integer_t *right) {
    if (left->negative != right->negative) return left->negative ? -1 : 1;
    int negative = left->negative ? -1 : 1;

    pm_bignum_t left_bignum = pm_integer_bignum(left);
    pm_bignum_t right_bignum = pm_integer_bignum(right);
    return pm_bignum_compare(&left_bignum, &right_bignum) * negative;
}

/**
 * The number of words of storage needed to convert an integer of length words
 * into base 10**9. The integer is below 2**(32 * length), so it needs at most:
 *
 *     32 * length * log10(2) / 9
 *
 * words in base 10**9, rounded up. To find 32 * log10(2) / 9, we approximate it
 * as 1097/1024, which is slightly greater than the actual value so it does not
 * undercount. As in pm_integer_chunks_words, the conversion multiplies the
 * high half by a power of two into this storage, which writes the sum of its
 * factors' lengths, and each factor's length rounds up on its own, so this is
 * one word more than the value needs.
 */
static PRISM_INLINE uint32_t
pm_integer_string_words(uint32_t length) {
    return (uint32_t) ((uint64_t) length * 1097 / 1024 + 2);
}

/**
 * Convert length words of a bignum into base 10**9. The result's storage must
 * have room for pm_integer_string_words(length) words. Up to
 * PM_INTEGER_STRING_LEAF words, a copy of the words is divided by 10**9
 * until nothing is left, and each remainder is the next word of the result.
 * Past it, the words split below the largest power of two less than length, at
 * 2**level words, so the value is high * 2**(32 * 2**level) + low with that
 * power of two already in base 10**9 in powers[level], and both halves convert
 * the same way.
 */
static void
pm_integer_string_convert(pm_bignum_t *result, const uint32_t *words, uint32_t length, const pm_bignum_t *powers, pm_bignum_scratch_t *scratch) {
    /* The low half of a split can have leading zero words. */
    while (length > 0 && words[length - 1] == 0) length--;
    uint32_t *saved = scratch->cursor;

    if (length <= PM_INTEGER_STRING_LEAF) {
        pm_bignum_t bignum = { .length = length, .words = pm_bignum_scratch_take(scratch, length) };
        memcpy(bignum.words, words, sizeof(uint32_t) * length);

        result->length = 0;
        while (bignum.length > 0) result->words[result->length++] = pm_bignum_div(&bignum, PM_BIGNUM_DECIMAL_BASE);
    } else {
        uint32_t level = pm_bsrll((uint64_t) length - 1);
        uint32_t split = (uint32_t) 1 << level;

        pm_bignum_t high = { .length = 0, .words = pm_bignum_scratch_take(scratch, pm_integer_string_words(length - split)) };
        pm_integer_string_convert(&high, words + split, length - split, powers, scratch);

        assert(high.length + powers[level].length <= pm_integer_string_words(length));
        pm_bignum_decimal_multiply(result, &high, &powers[level], scratch);
        scratch->cursor = saved;

        pm_bignum_t low = { .length = 0, .words = pm_bignum_scratch_take(scratch, pm_integer_string_words(split)) };
        pm_integer_string_convert(&low, words, split, powers, scratch);
        pm_bignum_decimal_add(result, &low);
    }

    scratch->cursor = saved;
}

/**
 * Convert the words of an integer of more than PM_INTEGER_STRING_THRESHOLD
 * words to a decimal string by divide and conquer. The powers of two that the
 * splits need are computed in base 10**9 by repeated squaring, and the integer
 * is converted into base 10**9, each word of which is nine digits. Everything
 * lives in one block of scratch space from the heap, sized for the worst case:
 * the result, the powers, and the halves and products of the deepest chain of
 * splits, with Karatsuba's temporaries bounded by 12 times the longer factor's
 * length.
 */
static void
pm_integer_string_divide(pm_buffer_t *buffer, const uint32_t *words, uint32_t length) {
    uint32_t capacity = pm_integer_string_words(length);

    /* The scratch space is about 13 times the number of words, which can
     * exceed 32 bits, and on a 32-bit platform its size in bytes can exceed
     * size_t. */
    uint64_t scratch_size = 12 * (uint64_t) capacity + 1024;
    if (scratch_size > SIZE_MAX / sizeof(uint32_t)) PRISM_OOM();

    uint32_t *allocation = (uint32_t *) xmalloc(sizeof(uint32_t) * (size_t) scratch_size);
    if (allocation == NULL) PRISM_OOM();
    pm_bignum_scratch_t scratch = { .cursor = allocation, .end = allocation + (size_t) scratch_size };

    pm_bignum_t result = { .length = 0, .words = pm_bignum_scratch_take(&scratch, capacity) };

    /* powers[level] is 2**(32 * 2**level) in base 10**9, for every level a
     * split uses. */
    pm_bignum_t powers[64];
    uint32_t level = 0;
    powers[level].words = pm_bignum_scratch_take(&scratch, 2);
    powers[level].words[0] = (uint32_t) (PM_BIGNUM_BINARY_BASE % PM_BIGNUM_DECIMAL_BASE);
    powers[level].words[1] = (uint32_t) (PM_BIGNUM_BINARY_BASE / PM_BIGNUM_DECIMAL_BASE);
    powers[level].length = 2;

    for (uint32_t split = 2; split < length; split *= 2) {
        const pm_bignum_t *previous = &powers[level++];
        powers[level] = (pm_bignum_t) { .length = 0, .words = pm_bignum_scratch_take(&scratch, 2 * previous->length) };
        pm_bignum_decimal_multiply(&powers[level], previous, previous, &scratch);
    }

    pm_integer_string_convert(&result, words, length, powers, &scratch);
    assert(result.length > 0 && result.length < capacity);

    /* Every word but the most significant is exactly nine digits, padded with
     * zeros. */
    pm_buffer_append_format(buffer, "%" PRIu32, result.words[result.length - 1]);

    for (uint32_t index = result.length - 1; index > 0; index--) {
        uint32_t word = result.words[index - 1];
        char digits[9];

        for (size_t digit = 9; digit > 0; digit--) {
            digits[digit - 1] = (char) ('0' + word % 10);
            word /= 10;
        }

        pm_buffer_append_string(buffer, digits, 9);
    }

    xfree_sized(allocation, sizeof(uint32_t) * (size_t) scratch_size);
}

/**
 * Convert an integer to a decimal string.
 */
void
pm_integer_string(pm_buffer_t *buffer, const pm_integer_t *integer) {
    if (integer->negative) {
        pm_buffer_append_byte(buffer, '-');
    }

    /* An integer whose words are inline fits in a uint64_t, so it can be
     * appended directly. */
    if (integer->length <= 2) {
        pm_buffer_append_format(buffer, "%" PRIu64, pm_integer_uint64_value(integer));
        return;
    }

    if (integer->length > PM_INTEGER_STRING_THRESHOLD) {
        pm_integer_string_divide(buffer, integer->words.values, integer->length);
        return;
    }

    /* Dividing by 10**9 yields the next nine digits from the remainder, least
     * significant first, so the digits are written from the end of the buffer
     * toward the front. The division is destructive, so it works on a copy. */
    const size_t words_size = sizeof(uint32_t) * integer->length;

    /* A number of n words has at most n * 32 * log10(2) + 1 decimal digits,
     * which is at most n * 10 for the three or more words that reach here. */
    const size_t capacity = (size_t) integer->length * 10;

    /* The copy of the words and the digits share one allocation, with the
     * words first so that they are aligned. */
    void *allocation = xmalloc(words_size + capacity);
    if (allocation == NULL) PRISM_OOM();

    pm_bignum_t bignum = { .length = integer->length, .words = (uint32_t *) allocation };
    memcpy(bignum.words, integer->words.values, words_size);

    char *digits = (char *) allocation + words_size;
    size_t offset = capacity;

    while (bignum.length > 0) {
        uint32_t remainder = pm_bignum_div(&bignum, PM_BIGNUM_DECIMAL_BASE);

        /* Every chunk but the most significant is exactly nine digits, padded
         * with zeros. The most significant chunk is nonzero and stops at its
         * leading digit. */
        for (size_t index = 0; index < 9 && (bignum.length > 0 || remainder > 0); index++) {
            digits[--offset] = (char) ('0' + remainder % 10);
            remainder /= 10;
        }
    }

    pm_buffer_append_string(buffer, digits + offset, capacity - offset);
    xfree_sized(allocation, words_size + capacity);
}
