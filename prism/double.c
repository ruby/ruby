#include "prism/internal/double.h"

#include "prism/internal/bignum.h"
#include "prism/internal/bit.h"

#include <assert.h>
#include <float.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/* The conversion builds the bits of the result directly, so it depends on the
 * layout of a binary64 double. */
#if FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MIN_EXP != -1021 || DBL_MAX_EXP != 1024
#error "prism requires IEEE 754 binary64 doubles"
#endif

/**
 * The number of leading significant digits that are converted exactly.
 */
#define PM_DOUBLE_DIGITS 768

/**
 * The number of words in each side of the division in the exact conversion.
 */
#define PM_DOUBLE_WORDS 84

/**
 * The explicit exponent stops growing once it reaches this. The literal's
 * digits can only shift the exponent by its length, so past this the value is
 * already infinity or zero, and capping it keeps the arithmetic far from
 * overflowing an int64_t.
 */
#define PM_DOUBLE_EXPONENT_MAXIMUM 100000000000000000

/**
 * The bits of positive infinity.
 */
#define PM_DOUBLE_INFINITY ((uint64_t) 0x7FF0000000000000)

/**
 * The largest power of five that fits in a word.
 */
#define PM_DOUBLE_POWER5_13 1220703125

/**
 * The powers of ten that are exactly representable as doubles.
 */
static const double pm_double_powers[] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
};

/**
 * Return the number of bits in a nonzero number.
 */
static uint64_t
pm_double_bit_length(const pm_bignum_t *bignum) {
    assert(bignum->length > 0);
    return (uint64_t) (bignum->length - 1) * 32 + pm_bsrll(bignum->words[bignum->length - 1]) + 1;
}

/**
 * Multiply the number by five to the given power, in place.
 */
static void
pm_double_multiply_powof5(pm_bignum_t *bignum, uint64_t power) {
    for (; power >= 13; power -= 13) pm_bignum_mul_add(bignum, PM_DOUBLE_POWER5_13, 0);

    uint32_t multiplier = 1;
    for (; power > 0; power--) multiplier *= 5;
    if (multiplier > 1) pm_bignum_mul_add(bignum, multiplier, 0);
}

/**
 * Divide the numerator by the divisor, where the quotient is known to fit in 64
 * bits. The divisor must have at least two words and its top bit set, and the
 * numerator must have room for one more word above its length.
 *
 * Returns the quotient, sets inexact if the remainder is nonzero, and leaves
 * the remainder in the numerator's low words, untrimmed.
 */
static uint64_t
pm_double_divide(pm_bignum_t *numerator, const pm_bignum_t *divisor, bool *inexact) {
    uint32_t *numerator_words = numerator->words;
    const uint32_t *divisor_words = divisor->words;
    uint32_t numerator_length = numerator->length;
    uint32_t divisor_length = divisor->length;

    assert(divisor_length >= 2 && numerator_length >= divisor_length && (divisor_words[divisor_length - 1] >> 31) == 1);

    uint64_t top = divisor_words[divisor_length - 1];
    uint64_t next = divisor_words[divisor_length - 2];
    uint64_t quotient = 0;
    numerator_words[numerator_length] = 0;

    for (uint32_t index = numerator_length - divisor_length + 1; index > 0; index--) {
        uint32_t *window = numerator_words + index - 1;
        uint64_t current = ((uint64_t) window[divisor_length] << 32) | window[divisor_length - 1];
        uint64_t estimate = current / top;
        uint64_t remainder = current % top;

        while (estimate > UINT32_MAX || estimate * next > ((remainder << 32) | window[divisor_length - 2])) {
            estimate--;
            remainder += top;
            if (remainder > UINT32_MAX) break;
        }

        /* A difference below zero wraps around, which sets its top bit. */
        uint64_t carry = 0;
        uint64_t borrow = 0;

        for (uint32_t offset = 0; offset < divisor_length; offset++) {
            uint64_t product = estimate * divisor_words[offset] + carry;
            carry = product >> 32;

            uint64_t difference = (uint64_t) window[offset] - (uint32_t) product - borrow;
            window[offset] = (uint32_t) difference;
            borrow = difference >> 63;
        }

        uint64_t difference = (uint64_t) window[divisor_length] - carry - borrow;
        window[divisor_length] = (uint32_t) difference;

        if ((difference >> 63) != 0) {
            estimate--;
            carry = 0;

            for (uint32_t offset = 0; offset < divisor_length; offset++) {
                uint64_t sum = (uint64_t) window[offset] + divisor_words[offset] + carry;
                window[offset] = (uint32_t) sum;
                carry = sum >> 32;
            }

            window[divisor_length] += (uint32_t) carry;
        }

        assert((quotient >> 32) == 0);
        quotient = (quotient << 32) | estimate;
    }

    for (uint32_t index = 0; index < divisor_length; index++) {
        if (numerator_words[index] != 0) {
            *inexact = true;
            break;
        }
    }

    return quotient;
}

/**
 * Return the bits of the double nearest to (mantissa + fraction) * 2**exponent,
 * rounding ties to even, where the fraction is in [0, 1) and inexact says
 * whether it is nonzero. When inexact is set the mantissa must have more bits
 * than a double keeps, so that the fraction only ever breaks ties.
 */
static uint64_t
pm_double_round(uint64_t mantissa, int64_t exponent, bool inexact) {
    assert(mantissa != 0);

    /* Drop the bits below the 53 that a double keeps, or below the smallest
     * subnormal if the value is that small. */
    int64_t shift = (int64_t) pm_bsrll(mantissa) + 1 - 53;
    if (shift < -1074 - exponent) shift = -1074 - exponent;

    uint64_t bits;
    if (shift <= 0) {
        assert(!inexact);
        bits = mantissa << -shift;
    } else if (shift > 64) {
        return 0;
    } else {
        uint64_t half = (uint64_t) 1 << (shift - 1);
        uint64_t rest = mantissa & (half - 1 + half);
        bits = shift == 64 ? 0 : mantissa >> shift;
        if (rest > half || (rest == half && (inexact || (bits & 1)))) bits++;
    }

    /* The bits hold the significand with its implicit bit, so adding the
     * exponent field on top makes that bit carry into it. That also moves a
     * subnormal that rounded up into the normal range, and a significand that
     * rounded up to 2**53 into the next binade. */
    int64_t scale = exponent + shift;
    if (scale > 971) return PM_DOUBLE_INFINITY;

    bits += (uint64_t) (scale + 1074) << 52;
    return bits < PM_DOUBLE_INFINITY ? bits : PM_DOUBLE_INFINITY;
}

/**
 * Return the bits of the double nearest to the significant digits at start
 * times 10**exponent. When there are at most 19 digits, value holds them.
 */
static uint64_t
pm_double_exact(const uint8_t *start, uint32_t digits, int64_t exponent, uint64_t value) {
    uint32_t numerator_words[PM_DOUBLE_WORDS] = { 0 };
    pm_bignum_t numerator = { .length = 0, .words = numerator_words };

    if (digits <= 19) {
        numerator_words[0] = (uint32_t) value;
        numerator_words[1] = (uint32_t) (value >> 32);
        numerator.length = value > UINT32_MAX ? 2 : 1;
    } else {
        uint32_t remaining = digits > PM_DOUBLE_DIGITS ? PM_DOUBLE_DIGITS : digits;
        uint32_t chunk = 0;
        uint32_t multiplier = 1;

        for (const uint8_t *cursor = start; remaining > 0; cursor++) {
            if (*cursor < '0' || *cursor > '9') continue;

            chunk = chunk * 10 + (uint32_t) (*cursor - '0');
            multiplier *= 10;
            remaining--;

            if (multiplier == 1000000000) {
                pm_bignum_mul_add(&numerator, multiplier, chunk);
                chunk = 0;
                multiplier = 1;
            }
        }

        if (digits > PM_DOUBLE_DIGITS) {
            chunk = chunk * 10 + 1;
            multiplier *= 10;
            exponent += (int64_t) (digits - PM_DOUBLE_DIGITS) - 1;
        }

        if (multiplier > 1) pm_bignum_mul_add(&numerator, multiplier, chunk);
    }

    bool inexact = false;
    uint64_t mantissa;
    int64_t binary;

    /* Since 10**exp is 5**exp * 2**exp, only the power of five needs
     * arithmetic; the power of 2 goes into the binary exponent. */
    if (exponent >= 0) {
        /* Multiply by the power of five and round the top 64 bits. */
        pm_double_multiply_powof5(&numerator, (uint64_t) exponent);

        uint64_t length = pm_double_bit_length(&numerator);
        binary = exponent;

        if (length > 64) {
            uint64_t dropped = length - 64;
            inexact = pm_bignum_trailing_zeros(&numerator) < dropped;
            pm_bignum_shift_right(&numerator, (size_t) dropped);
            binary += (int64_t) dropped;
        }

        mantissa = pm_bignum_uint64(&numerator);
    } else {
        /* Divide by the power of five and round the 64-bit quotient. */
        uint32_t denominator_words[PM_DOUBLE_WORDS];
        pm_bignum_t denominator = { .length = 1, .words = denominator_words };

        denominator_words[0] = 1;
        pm_double_multiply_powof5(&denominator, (uint64_t) -exponent);

        /* Shift the denominator so that its top bit is set and it has at least
         * two words, and the numerator so that it has 63 more bits than the
         * denominator. If the numerator is already longer than that, the
         * denominator shifts by more whole words instead. */
        int64_t numerator_bits = (int64_t) pm_double_bit_length(&numerator);
        int64_t denominator_bits = (int64_t) pm_double_bit_length(&denominator);

        int64_t denominator_shift = (32 - denominator_bits % 32) % 32;
        if (denominator_bits + denominator_shift == 32) denominator_shift += 32;

        int64_t numerator_shift = 63 + denominator_bits + denominator_shift - numerator_bits;
        if (numerator_shift < 0) {
            denominator_shift += (31 - numerator_shift) / 32 * 32;
            numerator_shift = 63 + denominator_bits + denominator_shift - numerator_bits;
        }

        pm_bignum_shift_left(&numerator, (size_t) numerator_shift);
        pm_bignum_shift_left(&denominator, (size_t) denominator_shift);
        assert(numerator.length < PM_DOUBLE_WORDS && denominator.length <= PM_DOUBLE_WORDS);

        mantissa = pm_double_divide(&numerator, &denominator, &inexact);
        binary = exponent + denominator_shift - numerator_shift;
    }

    return pm_double_round(mantissa, binary, inexact);
}

/**
 * Parse a decimal float literal into the nearest double, rounding ties to even.
 */
double
pm_double_parse(const uint8_t *start, const uint8_t *end, bool *out_of_range) {
    *out_of_range = false;
    if (start < end && *start == '+') start++;

    const uint8_t *first = NULL;
    const uint8_t *cursor = start;

    uint32_t digits = 0;
    uint32_t zeros = 0;

    uint64_t value = 0;
    int64_t exponent = 0;

    bool fraction = false;
    bool e = false;

    for (; !e && cursor < end; cursor++) {
        switch (*cursor) {
            case '_':
                break;
            case '.':
                fraction = true;
                break;
            case 'e': case 'E':
                e = true;
                break;
            case '0':
                if (fraction) exponent--;
                if (first != NULL) zeros++;
                break;
            case '1': case '2': case '3': case '4': case '5':
            case '6': case '7': case '8': case '9':
                if (fraction) exponent--;
                if (first == NULL) first = cursor;

                digits += zeros + 1;
                if (digits <= 19) {
                    for (; zeros > 0; zeros--) value *= 10;
                    value = value * 10 + (uint64_t) (*cursor - '0');
                } else {
                    zeros = 0;
                }
                break;
            default:
                assert(false && "unreachable");
                break;
        }
    }

    exponent += (int64_t) zeros;
    if (digits == 0) return 0.0;

    if (e) {
        bool positive = true;
        if (cursor < end && (*cursor == '+' || *cursor == '-')) {
            positive = *cursor == '+';
            cursor++;
        }

        int64_t power = 0;
        for (; cursor < end; cursor++) {
            if (*cursor != '_' && power < PM_DOUBLE_EXPONENT_MAXIMUM) power = power * 10 + (*cursor - '0');
        }

        exponent += positive ? power : -power;
    }

    int64_t magnitude = (int64_t) digits + exponent;
    uint64_t bits;

    if (magnitude > 309) {
        bits = PM_DOUBLE_INFINITY;
    } else if (magnitude < -323) {
        bits = 0;
    } else {
        /* When the digits and the power of ten are both exactly representable,
         * a single correctly rounded multiplication or division gives the
         * result. When the power is too large but the digits have room, part
         * of the power moves into the digits. This depends on the operation
         * rounding once, to a double, rather than to a wider type first. */
#if defined(FLT_EVAL_METHOD) && FLT_EVAL_METHOD == 0
        if (digits <= 19 && value <= ((uint64_t) 1 << 53)) {
            if (exponent >= -22 && exponent < 0) {
                return (double) value / pm_double_powers[-exponent];
            } else if (exponent >= 0 && exponent <= 22) {
                return (double) value * pm_double_powers[exponent];
            } else if (exponent > 22 && exponent <= 22 + 15) {
                uint64_t scaled = value;
                for (int64_t power = exponent; power > 22 && scaled <= ((uint64_t) 1 << 53); power--) scaled *= 10;
                if (scaled <= ((uint64_t) 1 << 53)) return (double) scaled * 1e22;
            }
        }
#endif

        bits = pm_double_exact(first, digits, exponent, value);
    }

    *out_of_range = bits == 0 || bits == PM_DOUBLE_INFINITY;

    double result;
    memcpy(&result, &bits, sizeof(double));
    return result;
}
