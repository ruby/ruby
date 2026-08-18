/*/
 * Copyright (c) 2009 The Go Authors. All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 * 
 *    1. Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *    2. Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following 
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *    3. Neither the name of Google Inc. nor the names of its contributors
 *       may be used to endorse or promote products derived from this 
 *       software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * Modifications:
 * 
 *    1. Added portable system-based intrinsics to prefer performance,
 *       along with fallbacks (such as de Bruijn) to support more systems.
 *    2. Added Ruby-specific logic and API calls to conform to existing
 *       call structures and expectations of callers.
 *    3. Used Ruby's internal bignum methods to implement dtoa and strtod 
 *       fallback when caller requests more precision than uscale can handle.
 *    4. Optimized text parsing with SIMD-within-a-register chunk checks, 
 *       inspired by David Lemire's approach.
 *    5. Added hex text parsing to support Ruby's expectations.
 *    6. Renames and refactors to satisfy Ruby's contribution standards.
 *    7. Added Clinger's fast path to parsing method.
 * 
 * Sources:
 *    1. Russ Cox's paper detailing uscale and its implementation can 
 *       be found at: https://research.swtch.com/fp
 *    2. Russ Cox's GitHub repository with benchmarks, with Go and C
 *       implementations, can be found at: https://github.com/rsc/fpfmt
 *    3. How to read floating point numbers accurately by William D.
 *       Clinger: https://dl.acm.org/doi/10.1145/989393.989430
/*/

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include "pow10.h"
#include "internal/bits.h"
#include "internal/numeric.h"
#include "internal/array.h"

typedef struct {
    uint64_t m;
    int e;
} FloatRep;

typedef struct {
    uint64_t hi;
    uint64_t lo;
} PmHiLo;

typedef struct {
    PmHiLo pm;
    int s;
} Scaler;

typedef struct {
    uint64_t val;
} Unrounded;

// outcome of parse()/parse_text(): mirrors original strtod's ERANGE contract
typedef enum {
    PARSE_OK = 0,
    PARSE_OVERFLOW,  // magnitude too large; result saturated to +-HUGE_VAL, caller should set errno = ERANGE
    PARSE_UNDERFLOW, // nonzero input rounds to +-0; caller should set errno = ERANGE
} ParseStatus;

#define DTOA_MAX_DIGITS 18

// these defines are utilized in ruby_hdtoa, and were derived from the same source. see copyright below
#define HEXP_MASK  0x7FFULL
#define HEXP_SHIFT 52
#define HDBL_ADJ   (1024 - 2) // DBL_MAX_EXP - 2
#define HSIGFIGS   ((53 + 3) / 4 + 1) // (DBL_MANT_DIG + 3) / 4 + 1; max hex digits, including leading "1"

///////////////////////////////////////////////////////////////////////////////////////////////////
// forward declarations (grouped by concern, not call order)
///////////////////////////////////////////////////////////////////////////////////////////////////
// Unrounded type methods
static Unrounded unrounded_make(uint64_t v);
static Unrounded unrounded_from_bool(bool b);
static Unrounded unrounded_or(Unrounded a, Unrounded b);
static Unrounded unrounded_and(Unrounded a, Unrounded b);
static Unrounded unrounded_shr(Unrounded a, int s);
static Unrounded unrounded_div(Unrounded u, uint64_t d);
static Unrounded unrounded_nudge(Unrounded u, int d);
static uint64_t unrounded_floor(Unrounded u);
static uint64_t unrounded_round(Unrounded u);
static uint64_t unrounded_ceil(Unrounded u);
static bool unrounded_ge(Unrounded a, Unrounded b);

// Go helper equivalents
static uint64_t float64_bits(double f);
static double float64_frombits(uint64_t b);
static int bits_len64(uint64_t x);
static uint64_t rotate_right64(uint64_t x, int s);
static uint64_t mul_hi64(uint64_t a, uint64_t b);
static int32_t ashr32(int32_t x, int n);

// fpfmt internal helpers
static FloatRep unpack64(double f);
static double pack64(uint64_t m, int e);
static int log10_pow2(int x);
static int log2_pow10(int x);
static Scaler prescale(int e, int p, int lp);
static Unrounded uscale(uint64_t x, Scaler c);
static Unrounded unmin(uint64_t x);
static int skewed(int e);
static FloatRep trim_zeros(FloatRep fr);

// fpfmt format helpers
static bool is_eight_digits(const char *chars);
static uint32_t parse_eight_digits(const char *chars);
static int ignore_leading_zeros(const char *chars);
static int digits(uint64_t d);
static void format_base10(char *a, uint64_t d, int n);

// fpfmt main methods
static FloatRep fixed_width(double f, int n);
static double parse(uint64_t d, int p, ParseStatus *status);
static int hex_digit_value(char c);
static double parse_text(const char *start, const char *end, const char **endptr, ParseStatus *status);
static FloatRep short_width(double f);
static bool parse_hex(const char *start, const char *end, const char **endptr, double *result);

// ruby-specific helpers
static char *dup_str(const char *s, char **rve);
static char *digits_to_str(uint64_t m, int ndigits, int e, int *decpt);
static char *rational_arith_dtoa(double d, int ndigits, bool fixed_point, int *decpt, char **rve);
static double rational_arith_strtod(const char *int_start, const char *int_end, const char *frac_start, const char *frac_end, int p, ParseStatus *status);
static VALUE round_half_even_quotient(VALUE num, VALUE den);

// ruby-specific API
char *ruby_dtoa(double d_, int mode, int ndigits, int *decpt, int *sign, char **rve);
char *ruby_hdtoa(double d, const char *xdigs, int ndigits, int *decpt, int *sign, char **rve);
double ruby_strtod(const char *str, char **endptr);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Unrounded type methods
///////////////////////////////////////////////////////////////////////////////////////////////////
// utilities
static Unrounded
unrounded_make(uint64_t v)
{
    Unrounded u;
    u.val = v;
    return u;
}

static Unrounded
unrounded_from_bool(bool b)
{
    return unrounded_make(b ? 1u : 0u);
}

// operators
static Unrounded
unrounded_or(Unrounded a, Unrounded b)
{
    return unrounded_make(a.val | b.val);
}

static Unrounded
unrounded_and(Unrounded a, Unrounded b)
{
    return unrounded_make(a.val & b.val);
}

static Unrounded
unrounded_shr(Unrounded a, int s)
{
    return unrounded_make(a.val >> s);
}

static bool
unrounded_ge(Unrounded a, Unrounded b)
{
    return a.val >= b.val;
}

// methods
static uint64_t
unrounded_floor(Unrounded u)
{
    return (u.val + 0) >> 2;
}

static uint64_t
unrounded_round(Unrounded u)
{
    return (u.val + 1 + ((u.val >> 2) & 1)) >> 2;
}

static uint64_t
unrounded_ceil(Unrounded u)
{
    return (u.val + 3) >> 2;
}

static Unrounded
unrounded_div(Unrounded u, uint64_t d)
{
    Unrounded q = unrounded_make(u.val / d);
    Unrounded existing_sticky = unrounded_and(u, unrounded_make(1));
    Unrounded new_sticky = unrounded_from_bool((u.val % d) != 0);
    return unrounded_or(unrounded_or(q, existing_sticky), new_sticky);
}

static Unrounded
unrounded_nudge(Unrounded u, int d)
{
    return unrounded_make(u.val + (uint64_t)d);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Go helper equivalents
///////////////////////////////////////////////////////////////////////////////////////////////////
static uint64_t
float64_bits(double f)
{
    uint64_t b;
    memcpy(&b, &f, 8);
    return b;
}

static double
float64_frombits(uint64_t b)
{
    double f;
    memcpy(&f, &b, 8);
    return f;
}

// bit length of x (0 for x == 0); intrinsic where available, else portable de Bruijn fallback
#if defined(_M_X64) && defined(_MSC_VER)
#include <intrin.h>
static int
bits_len64(uint64_t x)
{
    unsigned long index;
    if (!_BitScanReverse64(&index, x)) return 0;
    return (int)index + 1;
}
#elif defined(__GNUC__) || defined(__clang__)
static int
bits_len64(uint64_t x)
{
    if (x == 0) return 0;
    return 64 - __builtin_clzll(x);
}
#else
static const int debruijn64[64] = {
    0, 47,  1, 56, 48, 27,  2, 60, 57, 49, 41, 37, 28, 16,  3, 61,
    54, 58, 35, 52, 50, 42, 21, 44, 38, 32, 29, 23, 17, 11,  4, 62,
    46, 55, 26, 59, 40, 36, 15, 53, 34, 51, 20, 43, 31, 22, 10, 45,
    25, 39, 14, 33, 19, 30,  9, 24, 13, 18,  8, 12,  7,  6,  5, 63
};
static int
bits_len64(uint64_t x)
{
    if (x == 0) return 0;
    x |= x>>1; x |= x>>2; x |= x>>4; x |= x>>8; x |= x>>16; x |= x>>32;
    return debruijn64[(x * 0x03f79d71b4cb0a89ULL) >> 58] + 1;
}
#endif

static uint64_t
rotate_right64(uint64_t x, int s)
{
    return ((x >> s) | (x << (64 - s)));
}

// 64x64->128 split multiply, high 64 bits; intrinsic/__int128 where available, else portable fallback
#if defined(_M_X64) && defined(_MSC_VER)
#include <intrin.h>
static uint64_t
mul_hi64(uint64_t a, uint64_t b)
{
    uint64_t hi;
    _umul128(a, b, &hi);
    return hi;
}
#elif defined(__SIZEOF_INT128__) && ( \
    (defined(__clang__) && !defined(_MSC_VER)) || \
    (defined(__GNUC__) && !defined(__clang__) && !defined(__CUDACC__)))
static uint64_t
mul_hi64(uint64_t a, uint64_t b)
{
    return (uint64_t)(((unsigned __int128)a * b) >> 64);
}
#else
static uint64_t
mul_hi64(uint64_t a, uint64_t b)
{
    uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
    uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;

    uint64_t lo_lo = a_lo * b_lo;
    uint64_t hi_lo = a_hi * b_lo;
    uint64_t lo_hi = a_lo * b_hi;
    uint64_t hi_hi = a_hi * b_hi;

    uint64_t cross = (lo_lo >> 32) + (hi_lo & 0xFFFFFFFFu) + (lo_hi & 0xFFFFFFFFu);
    return hi_hi + (hi_lo >> 32) + (lo_hi >> 32) + (cross >> 32);
}
#endif

// arithmetic right shift on int32_t; valid for 1 <= n <= 31
static int32_t
ashr32(int32_t x, int n)
{
    uint32_t ux = (uint32_t)x;
    uint32_t shifted = ux >> n;
    if (x < 0) shifted |= (uint32_t)(~0u << (32 - n));
    return (int32_t)shifted;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// fpfmt internal helpers
///////////////////////////////////////////////////////////////////////////////////////////////////
static FloatRep
unpack64(double f)
{
    const int shift = 64 - 53; // = 11
    const int min_exp = -(1074 + shift); // = -1085, used for compensating e for shift in m

    // extract bits from incoming
    uint64_t b = float64_bits(f);

    // isolate stored 52-bit m, left-justify it to 64-bits, restore implicit leading 1
    uint64_t m = (1ULL << 63) | ((b & ((1ULL << 52) - 1)) << shift);

    // get raw stored exponent
    int e = (int)((b >> 52) & ((1ULL << shift) - 1));

    // subnormal handling
    if (e == 0) {
        // clear implicit leading 1
        m &= ~(1ULL << 63);

        // set e to left-justified form
        e = min_exp;

        // renormalizes by shifting m until it's left-justified, updating e to compensate
        int s = 64 - bits_len64(m);
        return (FloatRep){ m << s, e - s };
    }

    // normal path, unbias and compensate e for shift in m
    return (FloatRep){ m, (e - 1) + min_exp };
}

static double
pack64(uint64_t m, int e)
{
    // implicit leading 1 not present, already packed
    if ((m & (1ULL << 52)) == 0) return float64_frombits(m);

    // implicit leading 1 present, must clear it and construct biased e
    return float64_frombits((m & ~(1ULL << 52)) | ((uint64_t)(1075 + e) << 52));
}

static int
log10_pow2(int x)
{
    return ashr32((int32_t)((int64_t)x * 78913), 18);
}

static int
log2_pow10(int x)
{
    return ashr32((int32_t)((int64_t)x * 108853), 15);
}

static Scaler
prescale(int e, int p, int lp)
{
    // make sure p is within range of precomputed table
    RUBY_ASSERT_ALWAYS(p >= POW10_MIN && p <= POW10_MAX);

    uint64_t *res = POW10_TABLE[p - POW10_MIN];
    return (Scaler){ { res[0], res[1] }, -(e + lp + 3) };
}

static Unrounded
uscale(uint64_t x, Scaler c)
{
    // multiply for high 128 bits (split into hi/lo 64-bit halves)
    uint64_t hi = mul_hi64(x, c.pm.hi); // high 64 bits
    uint64_t mid = x * c.pm.hi; // low 64 bits, for sticky correction (wraps mod 2^64 -- well defined)

    // default sticky
    uint64_t sticky = 1;

    // if low bits of hi are zero, hi alone can't determine sticky, use pmLo to correct
    if ((hi & ((1ULL << c.s) - 1)) == 0) {
        // multiply for low 64 bits
        uint64_t low = mul_hi64(x, c.pm.lo);

        // nonzero bits means result is inexact
        sticky = (mid - low > 1);

        // if low > mid underflows, borrow from hi
        hi -= (mid < low);
    }

    // shift hi to result position, include sticky bit
    return unrounded_make((hi >> c.s) | sticky);
}

static Unrounded
unmin(uint64_t x)
{
    return unrounded_make((x << 2) - 2);
}

// approximates floor(e*log_10(2) - (log_10(4/3)) for skewed valid round-trip footprints
static int
skewed(int e)
{
    return ashr32((int32_t)((int64_t)e * 631305 - 261663), 21);
}

static FloatRep
trim_zeros(FloatRep fr)
{
    // precomputed divisions
    const uint64_t max_uint64 = ~0ULL;
    const uint64_t div1e8m = 0xc767074b22e90e21ULL;
    const uint64_t div1e4m = 0xd288ce703afb7e91ULL;
    const uint64_t div1e2m = 0x8f5c28f5c28f5c29ULL;
    const uint64_t div1e1m = 0xcccccccccccccccdULL;
    const uint64_t div1e8le = max_uint64 / 100000000;
    const uint64_t div1e4le = max_uint64 / 10000;
    const uint64_t div1e2le = max_uint64 / 100;
    const uint64_t div1e1le = max_uint64 / 10;

    uint64_t x = fr.m;
    int p = fr.e;

    uint64_t d;

    // try to cut 1 zero, or return.
    if ((d = rotate_right64(x * div1e1m, 1)) <= div1e1le) {
        x = d;
        p++;
    } else return (FloatRep){ x, p };

    // try to cut 8 zeros, then 4, then 2, then 1
    if ((d = rotate_right64(x * div1e8m, 8)) <= div1e8le) {
        x = d;
        p += 8;
    }
    if ((d = rotate_right64(x * div1e4m, 4)) <= div1e4le) {
        x = d;
        p += 4;
    }
    if ((d = rotate_right64(x * div1e2m, 2)) <= div1e2le) {
        x = d;
        p += 2;
    }
    if ((d = rotate_right64(x * div1e1m, 1)) <= div1e1le) {
        x = d;
        p += 1;
    }

    return (FloatRep){ x, p };
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// fpfmt format helpers
///////////////////////////////////////////////////////////////////////////////////////////////////
// digit to char lookup table
static const char i2a[] =
    "00010203040506070809"
    "10111213141516171819"
    "20212223242526272829"
    "30313233343536373839"
    "40414243444546474849"
    "50515253545556575859"
    "60616263646566676869"
    "70717273747576777879"
    "80818283848586878889"
    "90919293949596979899"
;

static bool
is_eight_digits(const char *chars)
{
    uint64_t val;
    memcpy(&val, chars, 8);
#if defined(WORDS_BIGENDIAN)
    val = swap64(val);
#endif

    bool hi_ok = (val & 0xF0F0F0F0F0F0F0F0ULL) == 0x3030303030303030ULL;
    bool lo_ok = ((val + 0x0606060606060606ULL) & 0xF0F0F0F0F0F0F0F0ULL) == 0x3030303030303030ULL;

    return hi_ok && lo_ok;
}

static uint32_t
parse_eight_digits(const char *chars)
{
    uint64_t val;
    memcpy(&val, chars, 8);
#if defined(WORDS_BIGENDIAN)
    val = swap64(val);
#endif

    val -= 0x3030303030303030ULL;
    val = (val * 10) + (val >> 8);
    uint64_t v2 = ((val & 0x000000FF000000FFULL) * 0x000F424000000064ULL) + (((val >> 16) & 0x000000FF000000FFULL) * 0x0000271000000001ULL);
    return (uint32_t)(v2 >> 32);
}

static int
ignore_leading_zeros(const char *chars)
{
    uint64_t val;
    memcpy(&val, chars, 8);
#if defined(WORDS_BIGENDIAN)
    val = swap64(val);
#endif

    uint64_t x = val ^ 0x3030303030303030ULL;
    if (x == 0) return 8;
    uint64_t lowest = x & (~x + 1);
    return (bits_len64(lowest) - 1) / 8;
}

static int
digits(uint64_t d)
{
    // approximate digit count from bit length, then correct for undershoot
    int n = log10_pow2(bits_len64(d));
    return n + (d >= UINT64_POW10[n]);
}

static void
format_base10(char *a, uint64_t d, int n)
{
    // peel off 8 digits at a time via the i2a lookup table, right to left
    while ((d >> 32) != 0) {
        uint32_t x = (uint32_t)(d % 100000000);
        d /= 100000000;
        uint32_t y = x % 10000;
        x /= 10000;
        uint32_t x1 = (x / 100) * 2;
        uint32_t x0 = (x % 100) * 2;
        uint32_t y1 = (y / 100) * 2;
        uint32_t y0 = (y % 100) * 2;
        memcpy(a + n - 8, i2a + x1, 2);
        memcpy(a + n - 6, i2a + x0, 2);
        memcpy(a + n - 4, i2a + y1, 2);
        memcpy(a + n - 2, i2a + y0, 2);
        n -= 8;
    }

    // remaining digits fit in 32 bits; peel off 4, then 2, then the last 1-2 by hand
    uint32_t h = (uint32_t)d;
    while (h >= 10000) {
        uint32_t x = h % 10000;
        h /= 10000;
        uint32_t x1 = (x / 100) * 2;
        uint32_t x0 = (x % 100) * 2;
        memcpy(a + n - 4, i2a + x1, 2);
        memcpy(a + n - 2, i2a + x0, 2);
        n -= 4;
    }
    if (h >= 100) {
        uint32_t x = h % 100;
        h /= 100;
        memcpy(a + n - 2, i2a + 2 * x, 2);
        n -= 2;
    }
    if (h >= 10) {
        memcpy(a + n - 2, i2a + 2 * h, 2);
        return;
    }
    a[n - 1] = (char)('0' + h);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// fpfmt main methods
///////////////////////////////////////////////////////////////////////////////////////////////////
static FloatRep
fixed_width(double f, int n)
{
    // checks for reasonable number of decimal digits requested
    RUBY_ASSERT_ALWAYS(n <= DTOA_MAX_DIGITS);

    // unpack mantissa and exponent from double
    FloatRep fr = unpack64(f);
    uint64_t m = fr.m;
    int e = fr.e;

    // find the power of 10 that scales f so d = f * 10^p is an n-digit integer
    int p = n - 1 - log10_pow2(e + 63);

    // compute m * 2^e * 10^p to scale base 2 to base 10
    Unrounded u = uscale(m, prescale(e, p, log2_pow10(p)));

    // round scaled value to nearest integer
    uint64_t d = unrounded_round(u);

    // if p is off by one because of approximation or rollover, divide by 10 and compensate p
    if (d >= UINT64_POW10[n]) {
        d = unrounded_round(unrounded_div(u, 10));
        p--;
    }
    return (FloatRep){ d, -p };
}

static double
parse(uint64_t d, int p, ParseStatus *status)
{
    *status = PARSE_OK;

    // checks if d fits in 19 digit limit
    RUBY_ASSERT_ALWAYS(d <= UINT64_POW10[19]);

    if (d == 0) return 0.0;

    // Clinger's fast path (https://dl.acm.org/doi/10.1145/989393.989430)
    if (d <= (1ULL << 53) - 1 && p >= -22 && p <= 22) {
        double fd = (double)d;
        return (p >= 0) ? fd * DOUBLE_POW10[p] : fd / DOUBLE_POW10[-p];
    }

    // lookup table bounds check
    if (p > POW10_MAX) { *status = PARSE_OVERFLOW; return HUGE_VAL; }
    if (p < POW10_MIN) { *status = PARSE_UNDERFLOW; return 0.0; }

    // get bit length of d
    int b = bits_len64(d);

    // cache for speed
    int lp = log2_pow10(p);

    // approximate exponent to scale d * 10^p into 53-bit integer range. cap at 1074 to handle subnormals
    int e = 53 - b - lp;
    if (e > 1074) e = 1074;

    // compute m * 2^e * 10^p after left-justifying d and compensating e respectively
    Scaler sc = prescale(e - (64 - b), p, lp);

    // underflow check; shift is outside of uscale's bounds
    if (sc.s < 0 || sc.s > 63) { *status = PARSE_UNDERFLOW; return 0.0; }

    Unrounded u = uscale(d << (64 - b), sc);

    // adjust u and p if approximation was off by one
    int adj = unrounded_ge(u, unmin(1ULL << 53)) ? 1 : 0;
    u = unrounded_or(unrounded_shr(u, adj), unrounded_and(u, unrounded_make(1)));
    e -= adj;

    // overflow check; scaled exponent no longer fits in exponent field
    if (e < -971) { *status = PARSE_OVERFLOW; return HUGE_VAL; }

    // round scaled value to nearest integer
    return pack64(unrounded_round(u), -e);
}

static double
parse_text(const char *start, const char *end, const char **endptr, ParseStatus *status)
{
    *status = PARSE_OK;
    const char *orig_start = start;

    // optional leading sign
    bool neg = false;
    if (start < end && (*start == '-' || *start == '+')) {
        neg = (*start == '-');
        start++;
    }

    // hex float literal ("0x1.8p3" etc). errno is intentionally left at PARSE_OK for hex over/underflow like legacy strtod hex path
    if (start + 1 < end && start[0] == '0' && (start[1] == 'x' || start[1] == 'X')) {
        double m;
        const char *hend;
        if (!parse_hex(start + 2, end, &hend, &m)) {
            *endptr = orig_start;
            return 0.0;
        }
        *endptr = hend;
        return neg ? -m : m;
    }

    /* accumulate digits into d; frac counts fractional digits to fold into p below; caps at 19 sig digits to avoid overflowing d.
       sticky tracks whether any digit beyond that cap was nonzero -- if so, d dropped real precision and parse_text falls back 
       to rational_arith_strtod's exact bignum arithmetic instead of trusting the truncated d */
    uint64_t d = 0;
    int ndigits = 0;
    int extra_int_digits = 0;
    int frac = 0;
    bool saw_digit = false;
    bool sticky = false;
    const char *s = start;

    while (ndigits == 0 && end - s >= 8) {
        int nz = ignore_leading_zeros(s);
        s += nz;
        if (nz > 0) saw_digit = true;
        if (nz < 8) break;
    }

    while (ndigits == 0 && s < end && *s >= '0' && *s <= '9') {
        int digit = *s - '0';
        s++;
        saw_digit = true;
        if (digit != 0) { d = (uint64_t)digit; ndigits = 1; break; }
    }

    while (ndigits > 0 && ndigits + 8 <= 19 && end - s >= 8 && is_eight_digits(s)) {
        d = d * 100000000ULL + parse_eight_digits(s);
        ndigits += 8;
        s += 8;
    }

    for (; s < end && ndigits < 19 && *s >= '0' && *s <= '9'; s++) {
        d = d * 10 + (uint64_t)(*s - '0');
        ndigits++;
    }

    // beyond the 19-digit cap: just counting digits and checking for a nonzero one now, skip 8 at a time when possible
    while (end - s >= 8 && is_eight_digits(s)) {
        if (!sticky) {
            uint64_t chunk;
            memcpy(&chunk, s, 8);
            if (chunk != 0x3030303030303030ULL) sticky = true;
        }
        extra_int_digits += 8;
        s += 8;
    }
    for (; s < end && *s >= '0' && *s <= '9'; s++) {
        extra_int_digits++;
        if (*s != '0') sticky = true;
    }

    /* digit spans for rational_arith_strtod's exact fallback, in case sticky ends up true --
       captured as raw text ranges rather than derived from the (possibly capped) counters
       above, so they're correct regardless of how many digits were actually kept in d */
    const char *int_end = s;
    const char *frac_start = s;
    const char *frac_end = s;

    if (s < end && *s == '.') {
        const char *dot = s;
        s++;
        frac_start = s;

        while (ndigits == 0 && end - s >= 8) {
            int nz = ignore_leading_zeros(s);
            s += nz;
            frac += nz;
            if (nz > 0) saw_digit = true;
            if (nz < 8) break;
        }

        while (ndigits == 0 && s < end && *s >= '0' && *s <= '9') {
            int digit = *s - '0';
            s++;
            frac++;
            saw_digit = true;
            if (digit != 0) { d = (uint64_t)digit; ndigits = 1; break; }
        }

        while (ndigits > 0 && ndigits + 8 <= 19 && end - s >= 8 && is_eight_digits(s)) {
            d = d * 100000000ULL + parse_eight_digits(s);
            ndigits += 8;
            frac += 8;
            s += 8;
        }

        for (; s < end && ndigits < 19 && *s >= '0' && *s <= '9'; s++) {
            d = d * 10 + (uint64_t)(*s - '0');
            ndigits++;
            frac++;
        }

        /* beyond the 19-digit cap: frac is intentionally not incremented here (these digits
           never entered d, so the fast path's exponent formula must not count them either) --
           just checking for a nonzero digit now, so skip 8 at a time when possible */
        while (end - s >= 8 && is_eight_digits(s)) {
            if (!sticky) {
                uint64_t chunk;
                memcpy(&chunk, s, 8);
                if (chunk != 0x3030303030303030ULL) sticky = true;
            }
            s += 8;
        }
        for (; s < end && *s >= '0' && *s <= '9'; s++) {
            if (*s != '0') sticky = true;
        }

        frac_end = s;

        // bare '.' with no digits on either side isn't a number -- don't consume the dot
        if (!saw_digit) s = dot;
    }

    if (!saw_digit) {
        *endptr = orig_start;
        return 0.0;
    }

    // optional exponent -- only consumed if at least one exponent digit follows
    int p = 0;
    if (s < end && (*s == 'e' || *s == 'E')) {
        const char *t = s + 1;
        int esign = 1;
        if (t < end && (*t == '-' || *t == '+')) {
            esign = (*t == '-') ? -1 : 1;
            t++;
        }

        bool saw_exp_digit = false;
        for (; t < end && *t >= '0' && *t <= '9'; t++) {
            saw_exp_digit = true;
            if (p < 100000) p = p * 10 + (*t - '0');
        }

        if (saw_exp_digit) {
            s = t;
            p *= esign;
        }
    }

    *endptr = s;

    if (d == 0) return neg ? -0.0 : 0.0;

    /* more than 19 significant digits in the source text -- d's fixed-width accumulator
       dropped some of them, which can round the wrong way in rare near-tie cases, so fall
       back to exact bignum arithmetic over every digit instead of the fast uint64_t path */
    double m = sticky ? rational_arith_strtod(start, int_end, frac_start, frac_end, p, status) : parse(d, p - frac + extra_int_digits, status);
    return neg ? -m : m;
}

static FloatRep
short_width(double f)
{
    const int min_exp = -1085;

    FloatRep fr = unpack64(f);
    uint64_t m = fr.m;
    int e = fr.e;

    // find [min, max), the interval that all rounds back to f; z=11 is unpack64's shift, so half a ULP is 1<<(z-1)
    uint64_t min;
    int p;
    int z = 11;
    if ((m == (1ULL << 63)) && (e > min_exp)) {
        // smallest normalized mantissa: interval below m is only a quarter-ULP, use skewed() for the asymmetry
        p = -skewed(e + z);
        min = m - (1ULL << (z - 2));
    } else {
        if (e < min_exp) z = 11 + (min_exp - e); // e clamped for subnormals, widen z so min doesn't underflow
        p = -log10_pow2(e + z);
        min = m - (1ULL << (z - 1));
    }

    uint64_t max = m + (1ULL << (z - 1));
    int odd = (int)(m >> z) & 1; // nudges boundary inward on ties, per round-to-even

    // scale interval to base 10, rounding inward so [dmin, dmax] still rounds back to f
    Scaler pre = prescale(e, p, log2_pow10(p));
    uint64_t dmin = unrounded_ceil(unrounded_nudge(uscale(min, pre), +odd));
    uint64_t dmax = unrounded_floor(unrounded_nudge(uscale(max, pre), -odd));

    // prefer one fewer digit if truncating dmax still lands in [dmin, dmax]
    uint64_t d = dmax / 10;
    if ((d * 10) >= dmin) return trim_zeros((FloatRep){ d, -(p - 1) });

    // otherwise fall back to dmin, or the value nearest m if more than one candidate remains
    d = dmin;
    if (d < dmax) d = unrounded_round(uscale(m, pre));
    return (FloatRep){ d, -p };
}

static int
hex_digit_value(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// hex float body (everything after "0x"/"0X"): hexdigits ['.' hexdigits] [('p'|'P') ['+'|'-'] digits].
static bool
parse_hex(const char *start, const char *end, const char **endptr, double *result)
{
    const char *s = start;
    if (s >= end || (hex_digit_value(*s) < 0 && *s != '.')) return false;

    double adj = 0.0, aadj = 1.0;
    int nd0 = -4;
    bool mantissa_started = false;
    int dv;

    // leading zeros before the first nonzero digit are pure skip
    while (s < end && (dv = hex_digit_value(*s)) >= 0) {
        if (!mantissa_started) {
            if (dv == 0) { s++; continue; }
            mantissa_started = true;
        }
        adj += aadj * dv;
        aadj /= 16;
        nd0 += 4;
        s++;
    }

    if (s < end && *s == '.') {
        s++;
        // fraction leading zeros only get to skip for free while the value seen so far is still zero
        if (!mantissa_started) while (s < end && *s == '0') { s++; nd0 -= 4; }
        while (s < end && (dv = hex_digit_value(*s)) >= 0) {
            adj += aadj * dv;
            s++;
            if ((aadj /= 16) == 0.0) {
                // below the precision of a double; consume the rest without touching adj
                while (s < end && hex_digit_value(*s) >= 0) s++;
                break;
            }
        }
    }

    if (s < end && (*s == 'p' || *s == 'P')) {
        const char *t = s + 1;
        int esign = 1;
        if (t < end && (*t == '-' || *t == '+')) {
            esign = (*t == '-') ? -1 : 1;
            t++;
        }
        int p = 0;
        bool saw_exp_digit = false;
        for (; t < end && *t >= '0' && *t <= '9'; t++) {
            saw_exp_digit = true;
            if (p < 100000) p = p * 10 + (*t - '0');
        }
        if (!saw_exp_digit) return false;
        s = t;
        nd0 += p * esign;
    }

    *endptr = s;
    *result = ldexp(adj, nd0);
    return true;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// ruby-specific helpers
///////////////////////////////////////////////////////////////////////////////////////////////////
static char *
dup_str(const char *s, char **rve)
{
    size_t len = strlen(s);
    char *buf = malloc(len + 1);
    if (!buf) return NULL;
    memcpy(buf, s, len + 1);
    if (rve) *rve = buf + len;
    return buf;
}

static char *
digits_to_str(uint64_t m, int ndigits, int e, int *decpt)
{
    char *buf = malloc((size_t)ndigits + 1);
    if (!buf) return NULL;
    format_base10(buf, m, ndigits);
    buf[ndigits] = '\0';
    *decpt = ndigits + e;
    return buf;
}

// round(num/den) to the nearest integer, ties to even, computed exactly via bignum divmod
static VALUE
round_half_even_quotient(VALUE num, VALUE den)
{
    VALUE num2 = rb_int_plus(rb_int_mul(num, LONG2FIX(2)), den);
    VALUE den2 = rb_int_mul(den, LONG2FIX(2));
    VALUE qr = rb_int_divmod(num2, den2);
    VALUE q = RARRAY_AREF(qr, 0);
    VALUE r = RARRAY_AREF(qr, 1);
    if (RTEST(rb_int_zero_p(r))) q = rb_int_and(q, LONG2FIX(~1));
    return q;
}

// arbitrary-precision fallback for ruby_dtoa()'s mode 2/3 requests that fpfmt can't serve
static char *
rational_arith_dtoa(double d, int ndigits, bool fixed_point, int *decpt, char **rve)
{
    FloatRep fr = unpack64(d);
    uint64_t m = fr.m;
    int e = fr.e;

    VALUE num, den;
    if (e >= 0) {
        num = rb_int_lshift(ULL2NUM(m), INT2FIX(e));
        den = LONG2FIX(1);
    } else {
        num = ULL2NUM(m);
        den = rb_int_lshift(LONG2FIX(1), INT2FIX(-e));
    }

    VALUE result_str;
    int digit_count, decpt_result;

    if (fixed_point) { // mode 3
        VALUE snum = num, sden = den;
        if (ndigits >= 0) snum = rb_int_mul(num, rb_int_pow(LONG2FIX(10), INT2FIX(ndigits)));
        else sden = rb_int_mul(den, rb_int_pow(LONG2FIX(10), INT2FIX(-ndigits)));

        VALUE q = round_half_even_quotient(snum, sden);

        if (RTEST(rb_int_zero_p(q))) {
            char *buf = malloc(1);
            if (!buf) return NULL;
            buf[0] = '\0';
            *decpt = 0;
            if (rve) *rve = buf;
            return buf;
        }

        result_str = rb_int2str(q, 10);
        digit_count = (int)RSTRING_LEN(result_str);
        decpt_result = digit_count - ndigits;
    } else { // mode 2
        int decpt_seed = 1 + log10_pow2(e + 63);

        result_str = Qnil;
        digit_count = 0;
        decpt_result = 0;

        // at most one retry; decpt_seed's log10_pow2 estimate is off by at most one digit
        for (int attempt = 0; attempt < 2; attempt++) {
            int p = ndigits - decpt_seed;

            // scale by 10^p into whichever side of the fraction keeps both integral
            VALUE snum = num, sden = den;
            if (p >= 0) snum = rb_int_mul(num, rb_int_pow(LONG2FIX(10), INT2FIX(p)));
            else        sden = rb_int_mul(den, rb_int_pow(LONG2FIX(10), INT2FIX(-p)));

            VALUE q = round_half_even_quotient(snum, sden);

            VALUE str = rb_int2str(q, 10);
            int len = (int)RSTRING_LEN(str);

            if (len == ndigits + 1) {
                VALUE pow10n = rb_int_pow(LONG2FIX(10), INT2FIX(ndigits));
                if (RTEST(rb_int_equal(q, pow10n))) { // carry cascade
                    q = rb_int_idiv(q, LONG2FIX(10));
                    result_str = rb_int2str(q, 10);
                    decpt_result = decpt_seed + 1;
                    digit_count = ndigits;
                    break;
                }
                if (attempt == 0) { // not a carry; retry with corrected exponent
                    decpt_seed += 1;
                    continue;
                }
                RUBY_ASSERT_ALWAYS(false); // invariant: still not a carry after one correction
            }
            if (len == ndigits - 1 && attempt == 0) {
                decpt_seed -= 1; // seed guessed one digit high; retry once with the corrected exponent
                continue;
            }

            RUBY_ASSERT_ALWAYS(len == ndigits); // invariant: after at most one retry, len must equal ndigits

            result_str = str;
            decpt_result = decpt_seed;
            digit_count = len;
            break;
        }
    }

    char *buf = malloc((size_t)digit_count + 1);
    if (!buf) return NULL;
    memcpy(buf, RSTRING_PTR(result_str), (size_t)digit_count);
    buf[digit_count] = '\0';

    // mirror ruby_dtoa()'s post-switch trim
    char *end = buf + digit_count;
    while (end > buf + 1 && end[-1] == '0') end--;
    *end = '\0';

    *decpt = decpt_result;
    if (rve) *rve = end;
    return buf;
}

// arbitrary-precision fallback for parse_text() for cases fpfmt can't serve
static double
rational_arith_strtod(const char *int_start, const char *int_end, const char *frac_start, const char *frac_end, int p, ParseStatus *status)
{
    long int_len = int_end - int_start;
    long frac_len = frac_end - frac_start;
    long total_len = int_len + frac_len;

    char *buf = malloc((size_t)total_len + 1);
    if (!buf) return HUGE_VAL;
    if (int_len > 0) memcpy(buf, int_start, (size_t)int_len);
    if (frac_len > 0) memcpy(buf + int_len, frac_start, (size_t)frac_len);
    buf[total_len] = '\0';

    VALUE numerator = rb_cstr_to_inum(buf, 10, 0);
    free(buf);

    /* exponent for the exact integer above: p already accounts for the digits kept in d,
       but here we're using every digit, so re-derive it from the true (uncapped) frac_len */
    int exp10 = p - (int)frac_len;

    VALUE num = numerator, den = LONG2FIX(1);
    if (exp10 >= 0) num = rb_int_mul(num, rb_int_pow(LONG2FIX(10), INT2FIX(exp10)));
    else den = rb_int_pow(LONG2FIX(10), INT2FIX(-exp10));

    /* rb_int_fdiv_double (the same primitive Rational#to_f is built on) is NOT reliably
       correctly-rounded for arbitrary bignum ratios -- e.g. Rational(65803600513127829623,
       10**12).to_f is off by one ULP. used here only to seed a binary exponent estimate */
    double approx = rb_int_fdiv_double(num, den);
    if (isinf(approx)) { *status = PARSE_OVERFLOW; return approx; }
    if (approx == 0.0) { *status = PARSE_UNDERFLOW; return 0.0; }

    int exp2;
    frexp(approx, &exp2);
    int k = 53 - exp2;
    if (k > 1074) k = 1074; // clamp for subnormals, mirroring parse()'s own e > 1074 clamp

    uint64_t mantissa = 0;
    for (int attempt = 0; attempt < 4; attempt++) {
        VALUE snum = num, sden = den;
        if (k >= 0) snum = rb_int_lshift(num, INT2FIX(k));
        else sden = rb_int_lshift(den, INT2FIX(-k));

        // mantissa = round(snum / sden) = round((num/den) * 2^k)
        VALUE q = round_half_even_quotient(snum, sden);

        mantissa = NUM2ULL(q);

        if (mantissa >= (1ULL << 53)) { k -= 1; continue; } // carry; retry with less headroom
        if (mantissa < (1ULL << 52) && k < 1074) { k += 1; continue; } // seed guessed short; retry
        break;
    }

    /* mantissa is exactly representable in a double (<= 2^53), and ldexp on an exact operand
       with an integer power-of-two exponent introduces no further rounding */
    double result = ldexp((double)mantissa, -k);
    if (isinf(result)) *status = PARSE_OVERFLOW;
    else if (result == 0.0) *status = PARSE_UNDERFLOW;
    return result;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// ruby-specific API
///////////////////////////////////////////////////////////////////////////////////////////////////
double
ruby_strtod(const char *str, char **endptr)
{
    const char *p = str;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\v' || *p == '\f' || *p == '\r') p++;

    errno = 0;
    const char *ep;
    ParseStatus status;
    double d = parse_text(p, p + strlen(p), &ep, &status);

    // no conversion performed
    if (ep == p) {
        if (endptr) *endptr = (char *)str;
        return 0.0;
    }

    if (status != PARSE_OK) errno = ERANGE;
    if (endptr) *endptr = (char *)ep;
    return d;
}

char *
ruby_dtoa(double d_, int mode, int ndigits, int *decpt, int *sign, char **rve)
{
    *sign = signbit(d_) ? 1 : 0;
    double d = *sign ? -d_ : d_;

    if (isnan(d) || isinf(d)) {
        *decpt = INT_MAX;
        return dup_str(isnan(d) ? "NaN" : "Infinity", rve);
    }
    if (d == 0.0) {
        *decpt = 1;
        return dup_str("0", rve);
    }

    FloatRep fr;
    int n;
    switch (mode) {
        case 0: case 1:
            fr = short_width(d);
            n = digits(fr.m);
            break;
        case 3:
            FloatRep probe = fixed_width(d, 1);
            int decpt_guess = 1 + probe.e;
            n = decpt_guess + ndigits;
            if (n < 0) {
                *decpt = 0;
                return dup_str("", rve);
            }
            if (n == 0 || n > DTOA_MAX_DIGITS) return rational_arith_dtoa(d, ndigits, true, decpt, rve);
            fr = fixed_width(d, n);

            // decimal point guess off by one due to decade boundary cross, retry
            if (n + fr.e != decpt_guess) {
                n = (n + fr.e) + ndigits;
                if (n < 0) {
                    *decpt = 0;
                    return dup_str("", rve);
                }
                if (n == 0 || n > DTOA_MAX_DIGITS) return rational_arith_dtoa(d, ndigits, true, decpt, rve);
                fr = fixed_width(d, n);
            }
            break;
        default: // mode 2 (%e/%g): max(1, ndigits) significant digits
            n = ndigits < 1 ? 1 : ndigits;
            if (n > DTOA_MAX_DIGITS) return rational_arith_dtoa(d, ndigits, false, decpt, rve);
            fr = fixed_width(d, n);
            break;
    }

    char *buf = digits_to_str(fr.m, n, fr.e, decpt);
    if (!buf) return NULL;

    char *e = buf + n;
    while (e > buf + 1 && e[-1] == '0') e--;
    *e = '\0';
    if (rve) *rve = e;
    return buf;
}

/*/
 * This section is derived from legacy code, was included in missing/dtoa.c.
 *
 * Copyright (c) 2004-2008 David Schultz <das@FreeBSD.ORG>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 * 
 * Modifications:
 *    1. Altered defines and replaced some helper methods to keep footprint small.
 *    2. Utilized some helpers previously defined in this file for fpfmt.
/*/

char *
ruby_hdtoa(double d, const char *xdigs, int ndigits, int *decpt, int *sign, char **rve)
{
    uint64_t bits = float64_bits(d);
    char *s, *s0;
    int bufsize;
    uint32_t manh, manl;

    // set sign for everything, including 0's and NaNs
    *sign = (int)(bits >> 63);
    bits &= ~(1ULL << 63); // clear sign bit
    d = float64_frombits(bits);

    if (isinf(d)) { // infinity
        *decpt = INT_MAX;
        return dup_str("Infinity", rve);
    }
    else if (isnan(d)) { // nan
        *decpt = INT_MAX;
        return dup_str("NaN", rve);
    }
    else if (d == 0.0) { // zero
        *decpt = 1;
        return dup_str("0", rve);
    }

    int biased_exp = (int)((bits >> HEXP_SHIFT) & HEXP_MASK);
    if (biased_exp) *decpt = biased_exp - HDBL_ADJ; // normal
    else { // subnormal
        d *= 0x1p514;
        bits = float64_bits(d);
        biased_exp = (int)((bits >> HEXP_SHIFT) & HEXP_MASK);
        *decpt = biased_exp - (514 + HDBL_ADJ);
    }

    // dtoa() compatibility
    if (ndigits == 0) ndigits = 1;

    // if expected to auto-size, allocate enough space for all digits
    bufsize = (ndigits > 0) ? ndigits : HSIGFIGS;
    s0 = (char *)malloc((size_t)bufsize + 1);
    if (!s0) return NULL;

    // round to the nearest desired number of digits
    if (HSIGFIGS > ndigits && ndigits > 0) {
        double redux = 1.0;
        int offset = 4 * ndigits + 1024 - 4 - 53;
        bits = (bits & ~(HEXP_MASK << HEXP_SHIFT)) | ((uint64_t)offset << HEXP_SHIFT);
        d = float64_frombits(bits);
        d += redux;
        d -= redux;
        bits = float64_bits(d);
        *decpt += (int)((bits >> HEXP_SHIFT) & HEXP_MASK) - offset;
    }

    manh = (uint32_t)((bits >> 32) & 0xFFFFF);
    manl = (uint32_t)(bits & 0xFFFFFFFF);
    *s0 = '1';
    for (s = s0 + 1; s < s0 + bufsize; s++) {
        *s = xdigs[(manh >> (20 - 4)) & 0xf];
        manh = (manh << 4) | (manl >> (32 - 4));
        manl <<= 4;
    }

    // if ndigits < 0, we are expected to auto-size the precision
    if (ndigits < 0) for (ndigits = HSIGFIGS; s0[ndigits - 1] == '0'; ndigits--);

    s = s0 + ndigits;
    *s = '\0';
    if (rve != NULL) *rve = s;
    return (s0);
}