#include "ruby/internal/config.h"

#include <errno.h>
#include <float.h>
#include <stdint.h>
#include <string.h>

#include "internal.h"
#include "internal/bits.h"
#include "internal/float_conv.h"
#include "ruby/ruby.h"

#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_ARM64))
# include <intrin.h>            /* for _umul128 and __umulh */
#endif

#include "float_conv_table.h"

/*
 * The conversions here are for IEEE 754 binary64 only.  The callers
 * must use the functions in util.c when these are not available.
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

/*
 * The decimal to double conversion, by Eisel and Lemire.
 *
 * Daniel Lemire, "Number Parsing at a Gigabyte per Second", Software:
 * Practice and Experience 51 (8), 2021.  https://arxiv.org/abs/2101.11408
 *
 * Noble Mushtak, Daniel Lemire, "Fast Number Parsing Without Fallback",
 * Software: Practice and Experience 53 (7), 2023.
 * https://arxiv.org/abs/2212.06644
 *
 * This follows the fast_float library,
 * https://github.com/fastfloat/fast_float
 *
 *   Copyright (c) 2021 The fast_float authors
 *
 *   Licensed under the MIT License.
 */

/* The most decimal digits that always fit in uint64_t. */
#define SCAN_DIGITS_MAX 19

/* Exponents and fractions longer than this are left to ruby_strtod(). */
#define SCAN_EXPONENT_MAX (FLOAT_CONV_POW5_MAX - FLOAT_CONV_POW5_MIN)

#if defined(FLT_EVAL_METHOD) && FLT_EVAL_METHOD == 0
/* The powers of 10 that are exact in double. */
static const double exact_pow10[] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
};
# define EXACT_POW10_MAX ((int)numberof(exact_pow10) - 1)
#endif

/*
 * Sets +*result+ to the double that is the closest to w * 10**q and
 * returns true, if it is a normal number and is found for sure.  +w+
 * must not be zero.
 */
static bool
decimal_to_double(uint64_t w, int q, double *result)
{
#if FLOAT_CONV_IEEE754_BINARY64
    const uint64_t *pow5;
    uint64_t hi, lo, mantissa, bits;
    int lz, upperbit, power2;

#ifdef EXACT_POW10_MAX
    /* "1.50" is 15e-1 rather than 150e-2 */
    while (q < 0 && w % 10 == 0) {
        w /= 10;
        q++;
    }
    if (w <= DBL_HIDDEN_BIT << 1 &&
        -EXACT_POW10_MAX <= q && q <= EXACT_POW10_MAX) {
        /* both are exact, so the result is rounded only once */
        const double d = (double)w;
        *result = q < 0 ? d / exact_pow10[-q] : d * exact_pow10[q];
        return true;
    }
#endif
    if (q < FLOAT_CONV_POW5_MIN || q > FLOAT_CONV_POW5_MAX) return false;

    /* w * 5**q to the most significant 64 bits and some below */
    lz = (int)nlz_int64(w);
    w <<= lz;
    pow5 = float_conv_pow5[q - FLOAT_CONV_POW5_MIN];
    lo = mul_64x64(w, pow5[0], &hi);
    if ((hi & 0x1FF) == 0x1FF) {
        /* the bits to round may be affected by the lower half of 5**q */
        uint64_t hi2;
        (void)mul_64x64(w, pow5[1], &hi2);
        lo += hi2;
        if (hi2 > lo) hi++;
    }
    if (lo == UINT64_MAX && (q < -27 || q > 55)) {
        /*
         * The first paper leaves this case to a fallback, since the
         * product might be too inexact to be rounded.  The second one
         * proves that it never is, but ruby_strtod() is there anyway.
         */
        return false;
    }

    upperbit = (int)(hi >> 63);
    mantissa = hi >> (upperbit + 9);
    power2 = RSHIFT((152170 + 65536) * q, 16) + 63 + upperbit - lz + 1023;
    if (power2 <= 0) return false; /* subnormal */

    if (lo <= 1 && q >= -4 && q <= 23 && (mantissa & 3) == 1 &&
        (mantissa << (upperbit + 9)) == hi) {
        /* exactly at the halfway; round to even */
        mantissa &= ~UINT64_C(1);
    }
    mantissa += mantissa & 1;
    mantissa >>= 1;
    if (mantissa >= (DBL_HIDDEN_BIT << 1)) {
        mantissa = DBL_HIDDEN_BIT;
        power2++;
    }
    mantissa &= ~DBL_HIDDEN_BIT;
    if (power2 >= (1 << DBL_EXPONENT_BITS) - 1) return false; /* infinity */

    bits = mantissa | ((uint64_t)power2 << DBL_SIGNIFICAND_BITS);
    memcpy(result, &bits, sizeof(bits));
    return true;
#else
    return false;
#endif
}

/*
 * Converts the decimal number at the beginning of +str+ in the same
 * way as ruby_strtod(), if it is in a simple form: an optional sign,
 * digits, optional fraction digits after a period, and an optional
 * exponent; of SCAN_DIGITS_MAX significant digits at most; and is zero
 * or a normal number.
 *
 * Returns true if it is converted.  Otherwise returns false, with
 * nothing changed, and the caller must use ruby_strtod().
 */
bool
rb_float_scan_decimal(const char *str, char **endptr, double *result)
{
    const char *s = str;
    bool negative = false;
    uint64_t w = 0;
    int digits = 0, fraction = 0, exponent = 0;
    int dropped = 0; /* digits before the point that are not in w */
    int kept = 0; /* digits after the point that are in w */
    bool truncated = false;
    double d;

    while (*s == ' ' || ('\t' <= *s && *s <= '\r')) s++;
    if (*s == '-') {
        negative = true;
        s++;
    }
    else if (*s == '+') {
        s++;
    }
    if (!ISDIGIT(*s)) return false;
    if (*s == '0' && (s[1] == 'x' || s[1] == 'X')) return false;

    for (; ISDIGIT(*s); s++) {
        if (w == 0 && *s == '0') continue;
        if (digits < SCAN_DIGITS_MAX) {
            digits++;
            w = w * 10 + (uint64_t)(*s - '0');
        }
        else {
            if (++dropped > FLOAT_CONV_POW5_MAX) return false;
            truncated = true;
        }
    }
    if (*s == '.') {
        const char *const point = s++;
        if (!ISDIGIT(*s)) return false;
        for (; ISDIGIT(*s); s++) {
            if (w == 0 && *s == '0') continue;
            if (digits < SCAN_DIGITS_MAX) {
                digits++;
                w = w * 10 + (uint64_t)(*s - '0');
            }
            else {
                if (!truncated) kept = (int)(s - point) - 1;
                truncated = true;
            }
        }
        if (s - point > SCAN_EXPONENT_MAX) return false;
        fraction = truncated ? kept : (int)(s - point) - 1;
    }
    if (*s == 'e' || *s == 'E') {
        const char *t = s + 1;
        bool exponent_negative = false;
        if (*t == '-') {
            exponent_negative = true;
            t++;
        }
        else if (*t == '+') {
            t++;
        }
        if (!ISDIGIT(*t)) return false;
        for (; ISDIGIT(*t); t++) {
            if (exponent > SCAN_EXPONENT_MAX) return false;
            exponent = exponent * 10 + (*t - '0');
        }
        if (exponent_negative) exponent = -exponent;
        s = t;
    }

    exponent += dropped - fraction;
    if (w == 0) {
        d = 0.0;
    }
    else if (!decimal_to_double(w, exponent, &d)) {
        return false;
    }
    else if (truncated) {
        /*
         * The number is between w and w + 1, in the unit of the last
         * digit of w.  It is rounded to the same as these are, if these
         * are rounded to the same.
         */
        double d1;
        if (!decimal_to_double(w + 1, exponent, &d1) || d != d1) return false;
    }
    errno = 0;
    if (endptr) *endptr = (char *)s;
    *result = negative ? -d : d;
    return true;
}
