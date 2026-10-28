#include "prism/internal/integer.h"

#include "prism/internal/allocator.h"
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
 * An unsigned integer used as scratch space by the arithmetic below. Its words
 * are digits in whichever base the operation works in (1<<32 or 10**9), least
 * significant first. They always live on the heap and there is always at least
 * one, so the arithmetic needs no special cases for small values;
 * pm_integer_from_bignum converts a result into a pm_integer_t.
 */
typedef struct {
    /** The number of words. */
    uint32_t length;

    /** The words, least significant first. */
    uint32_t *words;
} pm_bignum_t;

/**
 * Free the words of a bignum.
 */
static void
pm_bignum_free(pm_bignum_t *bignum) {
    xfree(bignum->words);
}

/**
 * Adds two pm_bignum_t with the given base.
 * Return pm_bignum_t with words allocated. Not normalized.
 */
static void
big_add(pm_bignum_t *destination, const pm_bignum_t *left, const pm_bignum_t *right, uint64_t base) {
    uint32_t left_length = left->length;
    const uint32_t *left_words = left->words;

    uint32_t right_length = right->length;
    const uint32_t *right_words = right->words;

    uint32_t length = left_length < right_length ? right_length : left_length;
    uint32_t *words = (uint32_t *) xmalloc(sizeof(uint32_t) * (length + 1));
    if (words == NULL) PRISM_OOM();

    uint64_t carry = 0;
    for (size_t index = 0; index < length; index++) {
        uint64_t sum = carry + (index < left_length ? left_words[index] : 0) + (index < right_length ? right_words[index] : 0);
        words[index] = (uint32_t) (sum % base);
        carry = sum / base;
    }

    if (carry > 0) {
        words[length] = (uint32_t) carry;
        length++;
    }

    *destination = (pm_bignum_t) { length, words };
}

/**
 * Internal use for karatsuba_multiply. Calculates `a - b - c` with the given
 * base. Assume a, b, c, a - b - c all to be positive.
 * Return pm_bignum_t with words allocated. Not normalized.
 */
static void
big_sub2(pm_bignum_t *destination, const pm_bignum_t *a, const pm_bignum_t *b, const pm_bignum_t *c, uint64_t base) {
    uint32_t a_length = a->length;
    const uint32_t *a_words = a->words;

    uint32_t b_length = b->length;
    const uint32_t *b_words = b->words;

    uint32_t c_length = c->length;
    const uint32_t *c_words = c->words;

    uint32_t *words = (uint32_t*) xmalloc(sizeof(uint32_t) * a_length);
    if (words == NULL) PRISM_OOM();

    int64_t carry = 0;
    for (size_t index = 0; index < a_length; index++) {
        int64_t sub = (
            carry +
            a_words[index] -
            (index < b_length ? b_words[index] : 0) -
            (index < c_length ? c_words[index] : 0)
        );

        if (sub >= 0) {
            words[index] = (uint32_t) sub;
            carry = 0;
        } else {
            sub += 2 * (int64_t) base;
            words[index] = (uint32_t) ((uint64_t) sub % base);
            carry = sub / (int64_t) base - 2;
        }
    }

    while (a_length > 1 && words[a_length - 1] == 0) a_length--;
    *destination = (pm_bignum_t) { a_length, words };
}

/**
 * Multiply two pm_bignum_t with the given base using karatsuba algorithm.
 * Return pm_bignum_t with words allocated. Not normalized.
 */
static void
karatsuba_multiply(pm_bignum_t *destination, const pm_bignum_t *left, const pm_bignum_t *right, uint64_t base) {
    uint32_t left_length = left->length;
    uint32_t *left_words = left->words;

    uint32_t right_length = right->length;
    uint32_t *right_words = right->words;

    if (left_length > right_length) {
        uint32_t temporary_length = left_length;
        left_length = right_length;
        right_length = temporary_length;

        uint32_t *temporary_words = left_words;
        left_words = right_words;
        right_words = temporary_words;
    }

    if (left_length <= 10) {
        uint32_t length = left_length + right_length;
        uint32_t *words = (uint32_t *) xcalloc(length, sizeof(uint32_t));
        if (words == NULL) PRISM_OOM();

        for (size_t left_index = 0; left_index < left_length; left_index++) {
            uint32_t carry = 0;
            for (size_t right_index = 0; right_index < right_length; right_index++) {
                uint64_t product = (uint64_t) left_words[left_index] * right_words[right_index] + words[left_index + right_index] + carry;
                words[left_index + right_index] = (uint32_t) (product % base);
                carry = (uint32_t) (product / base);
            }
            words[left_index + right_length] = carry;
        }

        while (length > 1 && words[length - 1] == 0) length--;
        *destination = (pm_bignum_t) { length, words };
        return;
    }

    if (left_length * 2 <= right_length) {
        uint32_t *words = (uint32_t *) xcalloc(left_length + right_length, sizeof(uint32_t));
        if (words == NULL) PRISM_OOM();

        for (uint32_t start_offset = 0; start_offset < right_length; start_offset += left_length) {
            uint32_t end_offset = start_offset + left_length;
            if (end_offset > right_length) end_offset = right_length;

            pm_bignum_t sliced_left = {
                .length = left_length,
                .words = left_words
            };

            pm_bignum_t sliced_right = {
                .length = end_offset - start_offset,
                .words = right_words + start_offset
            };

            pm_bignum_t product;
            karatsuba_multiply(&product, &sliced_left, &sliced_right, base);

            uint32_t carry = 0;
            for (size_t index = 0; index < product.length; index++) {
                uint64_t sum = (uint64_t) words[start_offset + index] + product.words[index] + carry;
                words[start_offset + index] = (uint32_t) (sum % base);
                carry = (uint32_t) (sum / base);
            }

            if (carry > 0) words[start_offset + product.length] += carry;
            pm_bignum_free(&product);
        }

        *destination = (pm_bignum_t) { left_length + right_length, words };
        return;
    }

    uint32_t half = left_length / 2;
    pm_bignum_t x0 = { half, left_words };
    pm_bignum_t x1 = { left_length - half, left_words + half };
    pm_bignum_t y0 = { half, right_words };
    pm_bignum_t y1 = { right_length - half, right_words + half };

    pm_bignum_t z0 = { 0 };
    karatsuba_multiply(&z0, &x0, &y0, base);

    pm_bignum_t z2 = { 0 };
    karatsuba_multiply(&z2, &x1, &y1, base);

    // For simplicity to avoid considering negative values,
    // use `z1 = (x0 + x1) * (y0 + y1) - z0 - z2` instead of original karatsuba algorithm.
    pm_bignum_t x01 = { 0 };
    big_add(&x01, &x0, &x1, base);

    pm_bignum_t y01 = { 0 };
    big_add(&y01, &y0, &y1, base);

    pm_bignum_t xy = { 0 };
    karatsuba_multiply(&xy, &x01, &y01, base);

    pm_bignum_t z1;
    big_sub2(&z1, &xy, &z0, &z2, base);

    uint32_t length = left_length + right_length;
    uint32_t *words = (uint32_t*) xcalloc(length, sizeof(uint32_t));
    if (words == NULL) PRISM_OOM();

    assert(z0.words != NULL);
    memcpy(words, z0.words, sizeof(uint32_t) * z0.length);

    assert(z2.words != NULL);
    memcpy(words + 2 * half, z2.words, sizeof(uint32_t) * z2.length);

    uint32_t carry = 0;
    for(size_t index = 0; index < z1.length; index++) {
        uint64_t sum = (uint64_t) carry + words[index + half] + z1.words[index];
        words[index + half] = (uint32_t) (sum % base);
        carry = (uint32_t) (sum / base);
    }

    for(size_t index = half + z1.length; carry > 0; index++) {
        uint64_t sum = (uint64_t) carry + words[index];
        words[index] = (uint32_t) (sum % base);
        carry = (uint32_t) (sum / base);
    }

    while (length > 1 && words[length - 1] == 0) length--;
    pm_bignum_free(&z0);
    pm_bignum_free(&z1);
    pm_bignum_free(&z2);
    pm_bignum_free(&x01);
    pm_bignum_free(&y01);
    pm_bignum_free(&xy);

    *destination = (pm_bignum_t) { length, words };
}

/**
 * The values of a hexadecimal digit, where the index is the ASCII character.
 * Note that there's an odd exception here where _ is mapped to 0. This is
 * because it's possible for us to end up trying to parse a number that has
 * already had an error attached to it, and we want to provide _something_ to
 * the user.
 */
static const int8_t pm_integer_parse_digit_values[256] = {
//   0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 0x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 1x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 2x
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1, // 3x
    -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 4x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,  0, // 5x
    -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 6x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 7x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 8x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 9x
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Ax
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Bx
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Cx
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Dx
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Ex
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // Fx
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
 * Create a pm_bignum_t from uint64_t with the given base.
 */
static void
pm_bignum_from_uint64(pm_bignum_t *bignum, uint64_t value, uint64_t base) {
    uint32_t length = 0;
    uint64_t length_value = value;

    do {
        length++;
        length_value /= base;
    } while (length_value > 0);

    uint32_t *words = (uint32_t *) xmalloc(sizeof(uint32_t) * length);
    if (words == NULL) PRISM_OOM();

    for (size_t value_index = 0; value_index < length; value_index++) {
        words[value_index] = (uint32_t) (value % base);
        value /= base;
    }

    *bignum = (pm_bignum_t) { length, words };
}

/**
 * Move a bignum in base 1<<32 into an integer, dropping leading zero words.
 * An integer with at most two words stores them inline, so the bignum's words
 * are freed; a larger one takes ownership of them.
 */
static void
pm_integer_from_bignum(pm_integer_t *integer, pm_bignum_t *bignum) {
    uint32_t length = bignum->length;
    const uint32_t *words = bignum->words;
    while (length > 0 && words[length - 1] == 0) length--;

    if (length <= 2) {
        *integer = (pm_integer_t) {
            .length = length,
            .words = { .value = { length > 0 ? words[0] : 0, length > 1 ? words[1] : 0 } }
        };
        pm_bignum_free(bignum);
    } else {
        *integer = (pm_integer_t) { .length = length, .words = { .values = bignum->words } };
    }
}

/**
 * Convert base of the bignum.
 * In practice, it converts 10**9 to 1<<32 or 1<<32 to 10**9.
 */
static void
pm_bignum_convert_base(pm_bignum_t *destination, const pm_bignum_t *source, uint64_t base_from, uint64_t base_to) {
    uint32_t source_length = source->length;
    const uint32_t *source_words = source->words;

    size_t bigints_length = (source_length + 1) / 2;
    assert(bigints_length > 0);

    pm_bignum_t *bigints = (pm_bignum_t *) xcalloc(bigints_length, sizeof(pm_bignum_t));
    if (bigints == NULL) PRISM_OOM();

    for (size_t index = 0; index < source_length; index += 2) {
        uint64_t value = source_words[index] + base_from * (index + 1 < source_length ? source_words[index + 1] : 0);
        pm_bignum_from_uint64(&bigints[index / 2], value, base_to);
    }

    pm_bignum_t base = { 0 };
    pm_bignum_from_uint64(&base, base_from, base_to);

    while (bigints_length > 1) {
        pm_bignum_t next_base;
        karatsuba_multiply(&next_base, &base, &base, base_to);

        pm_bignum_free(&base);
        base = next_base;

        size_t next_length = (bigints_length + 1) / 2;
        pm_bignum_t *next_bigints = (pm_bignum_t *) xcalloc(next_length, sizeof(pm_bignum_t));
        if (next_bigints == NULL) PRISM_OOM();

        for (size_t bigints_index = 0; bigints_index < bigints_length; bigints_index += 2) {
            if (bigints_index + 1 == bigints_length) {
                next_bigints[bigints_index / 2] = bigints[bigints_index];
            } else {
                pm_bignum_t multiplied = { 0 };
                karatsuba_multiply(&multiplied, &base, &bigints[bigints_index + 1], base_to);

                big_add(&next_bigints[bigints_index / 2], &bigints[bigints_index], &multiplied, base_to);
                pm_bignum_free(&bigints[bigints_index]);
                pm_bignum_free(&bigints[bigints_index + 1]);
                pm_bignum_free(&multiplied);
            }
        }

        xfree_sized(bigints, bigints_length * sizeof(pm_bignum_t));
        bigints = next_bigints;
        bigints_length = next_length;
    }

    *destination = bigints[0];
    while (destination->length > 1 && destination->words[destination->length - 1] == 0) destination->length--;

    xfree_sized(bigints, bigints_length * sizeof(pm_bignum_t));
    pm_bignum_free(&base);
}

/**
 * Convert digits to integer with the given power-of-two base.
 */
static void
pm_integer_parse_powof2(pm_integer_t *integer, uint32_t base, const uint8_t *digits, size_t digits_length) {
    size_t bit = 1;
    while (base > (uint32_t) (1 << bit)) bit++;

    uint32_t length = (uint32_t) ((digits_length * bit + 31) / 32);
    uint32_t *words = (uint32_t *) xcalloc(length, sizeof(uint32_t));
    if (words == NULL) PRISM_OOM();

    for (size_t digit_index = 0; digit_index < digits_length; digit_index++) {
        size_t bit_position = bit * (digits_length - digit_index - 1);
        uint32_t value = digits[digit_index];

        size_t index = bit_position / 32;
        size_t shift = bit_position % 32;

        words[index] |= value << shift;
        if (32 - shift < bit) words[index + 1] |= value >> (32 - shift);
    }

    pm_integer_from_bignum(integer, &((pm_bignum_t) { length, words }));
}

/**
 * Convert decimal digits to pm_integer_t.
 */
static void
pm_integer_parse_decimal(pm_integer_t *integer, const uint8_t *digits, size_t digits_length) {
    const size_t batch = 9;
    const uint32_t length = (uint32_t) ((digits_length + batch - 1) / batch);

    uint32_t *words = (uint32_t *) xcalloc(length, sizeof(uint32_t));
    if (words == NULL) PRISM_OOM();

    uint32_t value = 0;
    for (size_t digits_index = 0; digits_index < digits_length; digits_index++) {
        value = value * 10 + digits[digits_index];

        size_t reverse_index = digits_length - digits_index - 1;
        if (reverse_index % batch == 0) {
            words[reverse_index / batch] = value;
            value = 0;
        }
    }

    // Convert base from 10**9 to 1<<32.
    pm_bignum_t converted = { 0 };
    pm_bignum_convert_base(&converted, &((pm_bignum_t) { length, words }), 1000000000, ((uint64_t) 1 << 32));
    xfree_sized(words, length * sizeof(uint32_t));

    pm_integer_from_bignum(integer, &converted);
}

/**
 * Parse a large integer from a string that does not fit into uint64_t.
 */
static void
pm_integer_parse_big(pm_integer_t *integer, uint32_t multiplier, const uint8_t *start, const uint8_t *end) {
    // Allocate an array to store digits.
    const size_t digits_capa = sizeof(uint8_t) * (size_t) (end - start);
    uint8_t *digits = xmalloc(digits_capa);
    if (digits == NULL) PRISM_OOM();

    size_t digits_length = 0;
    for (; start < end; start++) {
        if (*start == '_') continue;
        digits[digits_length++] = pm_integer_parse_digit(*start);
    }

    // Construct pm_integer_t from the digits.
    if (multiplier == 10) {
        pm_integer_parse_decimal(integer, digits, digits_length);
    } else {
        pm_integer_parse_powof2(integer, multiplier, digits, digits_length);
    }

    xfree_sized(digits, digits_capa);
}

/**
 * Parse an integer from a string. This assumes that the format of the integer
 * has already been validated, as internal validation checks are not performed
 * here.
 */
void
pm_integer_parse(pm_integer_t *integer, pm_integer_base_t base, const uint8_t *start, const uint8_t *end) {
    // Ignore unary +. Unary - is parsed differently and will not end up here.
    // Instead, it will modify the parsed integer later.
    if (*start == '+') start++;

    // Determine the multiplier from the base, and skip past any prefixes.
    uint32_t multiplier = 10;
    switch (base) {
        case PM_INTEGER_BASE_DEFAULT:
            while (start < end && *start == '0') start++; // 01 -> 1
            break;
        case PM_INTEGER_BASE_BINARY:
            start += 2; // 0b
            multiplier = 2;
            break;
        case PM_INTEGER_BASE_OCTAL:
            start++; // 0
            if (*start == '_' || *start == 'o' || *start == 'O') start++; // o
            multiplier = 8;
            break;
        case PM_INTEGER_BASE_DECIMAL:
            if (*start == '0' && (end - start) > 1) start += 2; // 0d
            break;
        case PM_INTEGER_BASE_HEXADECIMAL:
            start += 2; // 0x
            multiplier = 16;
            break;
        case PM_INTEGER_BASE_UNKNOWN:
            if (*start == '0' && (end - start) > 1) {
                switch (start[1]) {
                    case '_': start += 2; multiplier = 8; break;
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': start++; multiplier = 8; break;
                    case 'b': case 'B': start += 2; multiplier = 2; break;
                    case 'o': case 'O': start += 2; multiplier = 8; break;
                    case 'd': case 'D': start += 2; break;
                    case 'x': case 'X': start += 2; multiplier = 16; break;
                    default: assert(false && "unreachable"); break;
                }
            }
            break;
    }

    // It's possible that we've consumed everything at this point if there is an
    // invalid integer. If this is the case, we'll just return 0.
    if (start >= end) return;

    /* Accumulate into a uint64_t, which covers every integer whose words are
     * stored inline. value * multiplier + digit overflows exactly when value
     * is past limit, or equal to it with digit past limit_digit. */
    const uint64_t limit = UINT64_MAX / multiplier;
    const uint64_t limit_digit = UINT64_MAX % multiplier;

    const uint8_t *cursor = start;
    uint64_t value = (uint64_t) pm_integer_parse_digit(*cursor++);

    for (; cursor < end; cursor++) {
        if (*cursor == '_') continue;
        uint64_t digit = (uint64_t) pm_integer_parse_digit(*cursor);

        if (value > limit || (value == limit && digit > limit_digit)) {
            pm_integer_parse_big(integer, multiplier, start, end);
            return;
        }

        value = value * multiplier + digit;
    }

    *integer = pm_integer_uint64(value);
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

    if (left->length < right->length) return -1 * negative;
    if (left->length > right->length) return 1 * negative;

    uint32_t length;
    const uint32_t *left_words = pm_integer_words(left, &length);
    const uint32_t *right_words = pm_integer_words(right, &length);

    for (uint32_t index = 0; index < length; index++) {
        uint32_t value_index = length - index - 1;
        uint32_t left_value = left_words[value_index];
        uint32_t right_value = right_words[value_index];

        if (left_value < right_value) return -1 * negative;
        if (left_value > right_value) return 1 * negative;
    }

    return 0;
}

/**
 * Reduce a ratio of integers to its simplest form.
 */
void pm_integers_reduce(pm_integer_t *numerator, pm_integer_t *denominator) {
    // If either the numerator or denominator do not fit into a 32-bit integer,
    // then this function is a no-op. In the future, we may consider reducing
    // even the larger numbers, but for now we're going to keep it simple.
    if (
        // If the numerator doesn't fit into a 32-bit integer, return early.
        numerator->length > 1 ||
        // If the denominator doesn't fit into a 32-bit integer, return early.
        denominator->length > 1 ||
        // If the numerator is 0, then return early.
        numerator->length == 0 ||
        // If the denominator is 1, then return early.
        denominator->words.value[0] == 1
    ) return;

    // Find the greatest common divisor of the numerator and denominator.
    uint32_t divisor = numerator->words.value[0];
    uint32_t remainder = denominator->words.value[0];

    while (remainder != 0) {
        uint32_t temporary = remainder;
        remainder = divisor % remainder;
        divisor = temporary;
    }

    // Divide the numerator and denominator by the greatest common divisor.
    numerator->words.value[0] /= divisor;
    denominator->words.value[0] /= divisor;
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
        const uint64_t value = ((uint64_t) integer->words.value[0]) | ((uint64_t) integer->words.value[1] << 32);
        pm_buffer_append_format(buffer, "%" PRIu64, value);
        return;
    }

    // Otherwise, first we'll convert the base from 1<<32 to 10**9.
    pm_bignum_t converted = { 0 };
    pm_bignum_convert_base(&converted, &((pm_bignum_t) { integer->length, integer->words.values }), (uint64_t) 1 << 32, 1000000000);

    // Allocate a buffer that we'll copy the decimal digits into.
    const size_t digits_length = (size_t) converted.length * 9;
    char *digits = xcalloc(digits_length, sizeof(char));
    if (digits == NULL) PRISM_OOM();

    // Pack bigdecimal to digits.
    for (size_t value_index = 0; value_index < converted.length; value_index++) {
        uint32_t value = converted.words[value_index];

        for (size_t digit_index = 0; digit_index < 9; digit_index++) {
            digits[digits_length - 9 * value_index - digit_index - 1] = (char) ('0' + value % 10);
            value /= 10;
        }
    }

    size_t start_offset = 0;
    while (start_offset < digits_length - 1 && digits[start_offset] == '0') start_offset++;

    // Finally, append the string to the buffer and free the digits.
    pm_buffer_append_string(buffer, digits + start_offset, digits_length - start_offset);
    xfree_sized(digits, sizeof(char) * digits_length);
    pm_bignum_free(&converted);
}
