#include "ruby/internal/config.h"

#include <float.h>
#include <stdint.h>
#include <string.h>

#include "internal.h"
#include "internal/float_conv.h"
#include "ruby/ruby.h"

#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_ARM64))
# include <intrin.h>            /* for _umul128 and __umulh */
#endif

#include "float_conv_table.h"

/*
 * The conversion here is for IEEE 754 binary64 only.  The callers must
 * use the functions in util.c when it is not available.
 */
#if defined(DBL_MANT_DIG) && DBL_MANT_DIG == 53 && \
    defined(DBL_MAX_EXP) && DBL_MAX_EXP == 1024 && FLT_RADIX == 2
# define FLOAT_CONV_IEEE754_BINARY64 1
#else
# define FLOAT_CONV_IEEE754_BINARY64 0
#endif

#define DBL_SIGNIFICAND_BITS 52
#define DBL_EXPONENT_BITS 11
#define DBL_EXPONENT_BIAS 1075 /* for the significand as an integer */
#define DBL_HIDDEN_BIT (UINT64_C(1) << DBL_SIGNIFICAND_BITS)

/* The low half of the product of +a+ and +b+; the high half in +*hi+. */
static inline uint64_t
mul_64x64(uint64_t a, uint64_t b, uint64_t *hi)
{
#if defined(HAVE_UINT128_T)
    const uint128_t p = (uint128_t)a * b;
    *hi = (uint64_t)(p >> 64);
    return (uint64_t)p;
#elif defined(_MSC_VER) && defined(_M_X64)
    return _umul128(a, b, hi);
#elif defined(_MSC_VER) && defined(_M_ARM64)
    *hi = __umulh(a, b);
    return a * b;
#else
    const uint64_t a0 = (uint32_t)a, a1 = a >> 32;
    const uint64_t b0 = (uint32_t)b, b1 = b >> 32;
    const uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
    const uint64_t mid = p10 + (p00 >> 32) + (uint32_t)p01;
    *hi = p11 + (mid >> 32) + (p01 >> 32);
    return (mid << 32) | (uint32_t)p00;
#endif
}

/*
 * The shortest digits, by Schubfach.
 *
 * Raffaello Giulietti, "The Schubfach way to render doubles",
 * https://drive.google.com/file/d/1gp5xv4CAa78SVgCeWfGqqI4FfYYYuNFb
 *
 * This follows schubfach_64.cc of Drachennest,
 * https://github.com/abolz/Drachennest
 *
 *   Copyright 2020 Alexander Bolz
 *
 *   Distributed under the Boost Software License, Version 1.0.
 *   (See https://www.boost.org/LICENSE_1_0.txt)
 */

/* floor(log2(10**e)) for -1233 <= e <= 1233 */
static inline int
floor_log2_pow10(int e)
{
    return RSHIFT(e * 1741647, 19);
}

/* floor(log10(2**e)) for -1500 <= e <= 1500 */
static inline int
floor_log10_pow2(int e)
{
    return RSHIFT(e * 1262611, 22);
}

/* floor(log10(3/4 * 2**e)) for -1500 <= e <= 1500 */
static inline int
floor_log10_three_quarters_pow2(int e)
{
    return RSHIFT(e * 1262611 - 524031, 22);
}

/*
 * floor(g * cp / 2**128) where g is the 128 bits of +pow10+, with its
 * least significant bit set if the product has any lower bit, so that
 * the result can be rounded later.
 */
static inline uint64_t
round_to_odd(const uint64_t pow10[2], uint64_t cp)
{
    uint64_t x_hi, y_hi, y_lo, z;

    (void)mul_64x64(pow10[1], cp, &x_hi);
    y_lo = mul_64x64(pow10[0], cp, &y_hi);
    z = y_lo + x_hi;
    y_hi += (z < y_lo);
    return y_hi | (z > 1);
}

/*
 * Writes to +buf+ the shortest decimal digits that are converted back
 * to +d+, the closest ones to +d+ if there are many, and returns the
 * number of the digits, which is RB_FLOAT_SHORTEST_DIGITS_MAX at most.
 * The digits are not terminated.  The value is 0.DIGITS * 10**(*decpt),
 * as the mode 0 of ruby_dtoa().  +d+ must be finite, positive and not
 * zero.
 *
 * Returns 0 without writing anything if double is not IEEE 754 binary64.
 */
int
rb_float_shortest_digits(double d, char *buf, int *decpt)
{
#if FLOAT_CONV_IEEE754_BINARY64
    uint64_t bits, c, m;
    int q, k, n;
    const uint64_t significand_mask = DBL_HIDDEN_BIT - 1;
    const int exponent_mask = (1 << DBL_EXPONENT_BITS) - 1;
    uint64_t ieee_significand;
    int ieee_exponent;

    memcpy(&bits, &d, sizeof(bits));
    ieee_significand = bits & significand_mask;
    ieee_exponent = (int)(bits >> DBL_SIGNIFICAND_BITS) & exponent_mask;

    if (ieee_exponent != 0) {
        c = DBL_HIDDEN_BIT | ieee_significand;
        q = ieee_exponent - DBL_EXPONENT_BIAS;
    }
    else {
        c = ieee_significand;
        q = 1 - DBL_EXPONENT_BIAS;
    }

    if (0 <= -q && -q <= DBL_SIGNIFICAND_BITS &&
        (c & ((UINT64_C(1) << -q) - 1)) == 0) {
        /* an integer less than 2**53 */
        m = c >> -q;
        k = 0;
    }
    else {
        /* the bounds of the rounding interval of d, times 4 */
        const bool even = (c & 1) == 0;
        const bool lower_is_closer =
            (ieee_significand == 0 && ieee_exponent > 1);
        const uint64_t cbl = 4 * c - 2 + lower_is_closer;
        const uint64_t cb = 4 * c;
        const uint64_t cbr = 4 * c + 2;
        const uint64_t *pow10;
        uint64_t vbl, vb, vbr, lower, upper, s;
        int h;

        /* 10**k is the unit of the shorter of the candidates */
        k = lower_is_closer ?
            floor_log10_three_quarters_pow2(q) : floor_log10_pow2(q);
        h = q + floor_log2_pow10(-k) + 1;
        pow10 = float_conv_pow10[-k - FLOAT_CONV_POW10_MIN];

        /* the bounds and d in the unit of 10**k / 4 */
        vbl = round_to_odd(pow10, cbl << h);
        vb = round_to_odd(pow10, cb << h);
        vbr = round_to_odd(pow10, cbr << h);
        lower = vbl + !even;
        upper = vbr - !even;

        s = vb / 4;
        m = 0;
        if (s >= 10) {
            /* a multiple of 10**(k + 1) in the interval, if any */
            const uint64_t sp = s / 10;
            const bool down_inside = lower <= 40 * sp;
            const bool up_inside = 40 * sp + 40 <= upper;
            if (down_inside != up_inside) {
                m = sp + up_inside;
                k++;
            }
        }
        if (m == 0) {
            const bool down_inside = lower <= 4 * s;
            const bool up_inside = 4 * s + 4 <= upper;
            if (down_inside != up_inside) {
                m = s + up_inside;
            }
            else {
                /* both or none are in; the closer, or the even */
                const uint64_t mid = 4 * s + 2;
                const bool up = vb > mid || (vb == mid && (s & 1) != 0);
                m = s + up;
            }
        }
    }

    while (m % 10 == 0) {
        m /= 10;
        k++;
    }

    n = 0;
    {
        char digits[RB_FLOAT_SHORTEST_DIGITS_MAX];
        char *p = digits + sizeof(digits);
        do {
            *--p = (char)('0' + m % 10);
            m /= 10;
        } while (m != 0);
        n = (int)(digits + sizeof(digits) - p);
        memcpy(buf, p, n);
    }
    *decpt = n + k;
    return n;
#else
    return 0;
#endif
}
