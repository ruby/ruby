/* Exact decimal arithmetic in two tiers. Values with up to 15
   significant digits live inside a tagged 64-bit VALUE pointer,
   like Fixnum: no object, no allocation, no GC. Larger values
   promote to a heap object carrying a 128-bit scaled integer
   (39 digits, 18 decimal places).
   */

#include "ruby/internal/config.h"

#include <ctype.h>
#include <string.h>

#include "id.h"
#include "internal.h"
#include "internal/decimal.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/vm.h"
#include "shape.h"

#ifdef HAVE_INT128_T
typedef int128_t dec_i128;
typedef uint128_t dec_u128;
#else
#error "Decimal requires __int128 (available on all 64-bit GCC/Clang targets)"
#endif

#define DEC_PRECISION 18
#define DEC_MAX ((dec_i128)(((dec_u128)1 << 127) - 1))
#define DEC_MIN ((dec_i128)((dec_u128)1 << 127))
#define MASK64 ((dec_u128)0xFFFFFFFFFFFFFFFFULL)

VALUE rb_cDecimal;

static VALUE decimal_zero;
static VALUE decimal_scale_val;
static ID id_ceil, id_floor, id_remainder, id_round, id_truncate;
static ID id_i_raw;

static VALUE decimal_parse(const char *str, long slen, int raise);

static const uint64_t POW10[] = {
    1ULL, 10ULL, 100ULL, 1000ULL, 10000ULL, 100000ULL, 1000000ULL,
    10000000ULL, 100000000ULL, 1000000000ULL, 10000000000ULL,
    100000000000ULL, 1000000000000ULL, 10000000000000ULL,
    100000000000000ULL, 1000000000000000ULL, 10000000000000000ULL,
    100000000000000000ULL, 1000000000000000000ULL
};

/* Reciprocal table for division-free x / 10**n.
 *  div_pow10(x, n) = mulhi(x, RECIP10[n]) >> SHIFT10[n]. */
static const uint64_t RECIP10[19] = {
    UINT64_C(0),                     /* 10**0: identity */
    UINT64_C(0xCCCCCCCCCCCCCCCD), /* 10**1  */
    UINT64_C(0xA3D70A3D70A3D70B), /* 10**2  */
    UINT64_C(0x83126E978D4FDF3C), /* 10**3  */
    UINT64_C(0xD1B71758E219652C), /* 10**4  */
    UINT64_C(0xA7C5AC471B478424), /* 10**5  */
    UINT64_C(0x8637BD05AF6C69B6), /* 10**6  */
    UINT64_C(0xD6BF94D5E57A42BD), /* 10**7  */
    UINT64_C(0xABCC77118461CEFD), /* 10**8  */
    UINT64_C(0x89705F4136B4A598), /* 10**9  */
    UINT64_C(0xDBE6FECEBDEDD5BF), /* 10**10 */
    UINT64_C(0xAFEBFF0BCB24AAFF), /* 10**11 */
    UINT64_C(0x8CBCCC096F5088CC), /* 10**12 */
    UINT64_C(0xE12E13424BB40E14), /* 10**13 */
    UINT64_C(0xB424DC35095CD810), /* 10**14 */
    UINT64_C(0x901D7CF73AB0ACDA), /* 10**15 */
    UINT64_C(0xE69594BEC44DE15C), /* 10**16 */
    UINT64_C(0xB877AA3236A4B44A), /* 10**17 */
    UINT64_C(0x9392EE8E921D5D08)  /* 10**18 */
};

static const uint8_t SHIFT10[19] = {
    0, 3, 6, 9, 13, 16, 19, 23, 26, 29, 33, 36, 39, 43, 46, 49, 53, 56, 59
};

/* Estimated decimal digit count from __builtin_clzll result.
 *  May undercount by 1; correct with: if (v >= POW10[d]) d++. */
static const uint8_t DIGITS_CLZ[65] = {
    19, 19, 19, 19, 18, 18, 18, 17,  /* clz 0..7 */
    17, 17, 16, 16, 16, 16, 15, 15,  /* clz 8..15 */
    15, 14, 14, 14, 13, 13, 13, 13,  /* clz 16..23 */
    12, 12, 12, 11, 11, 11, 10, 10,  /* clz 24..31 */
    10, 10,  9,  9,  9,  8,  8,  8,  /* clz 32..39 */
     7,  7,  7,  7,  6,  6,  6,  5,  /* clz 40..47 */
     5,  5,  4,  4,  4,  4,  3,  3,  /* clz 48..55 */
     3,  2,  2,  2,  1,  1,  1,  1,  /* clz 56..63 */
     1                               /* clz 64 */
};

static inline uint64_t
div_pow10(uint64_t x, int n)
{
    if (n == 0) return x;
    return (uint64_t)((dec_u128)x * RECIP10[n] >> 64) >> SHIFT10[n];
}

static inline int
count_digits(uint64_t v)
{
    if (v == 0) return 1;
    int d = DIGITS_CLZ[__builtin_clzll(v)];
    if (v >= POW10[d]) d++;
    return d;
}

static inline dec_i128
dec_to_i128(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        dec_i128 v = (dec_i128)dec_bid_sig(self) *
                     (dec_i128)POW10[18 - dec_bid_scale(self)];
        return dec_bid_neg(self) ? -v : v;
    }
    return RDECIMAL(self)->value;
}

static inline uint64_t
strip_tz(uint64_t r, int *scale, int max)
{
    int s = *scale, n = 0;
    while (n < max && s > 0) {
        uint64_t q = div_pow10(r, 1);
        if (q * 10 != r) break;
        r = q;
        s--;
        n++;
    }
    *scale = s;
    return r;
}

static inline int
dec_integral_p(dec_i128 val)
{
    return val % DEC_SCALE == 0;
}

static inline int
dec_parse_ndigits(int argc, VALUE *argv)
{
    if (argc == 0) return 0;
    if (FIXNUM_P(argv[0])) return (int)FIX2LONG(argv[0]);
    return NUM2INT(argv[0]);
}

static inline VALUE
dec_rounding_shortcut(VALUE self, int ndigits)
{
    if (ndigits >= 18) return self;
    if (RB_DECIMAL_IMM_P(self) && dec_bid_scale(self) == 0) {
        if (ndigits >= 0) {
            if (ndigits == 0) {
                uint64_t sig = dec_bid_sig(self);
                if (dec_bid_neg(self))
                    return LONG2NUM(-(long)sig);
                return LONG2NUM((long)sig);
            }
            return self;
        }
    }
    else if (RB_DECIMAL_IMM_P(self) && ndigits > 0) {
        if (ndigits >= dec_bid_scale(self)) return self;
    }
    return Qundef;
}

static inline VALUE
dec_from_i128(dec_i128 val)
{
    if (val == 0) return decimal_zero;
    int neg = val < 0;
    dec_u128 abs = neg ? -(dec_u128)val : (dec_u128)val;
    if ((abs >> 64) == 0) {
        int scale = 18;
        uint64_t r = strip_tz((uint64_t)abs, &scale, 18);
        if (scale <= 15 && r <= DEC_BID_SIG_MAX)
            return dec_bid_encode(r, scale, neg);
    }
    NEWOBJ_OF_WITH_SHAPE(obj, struct RDecimal, rb_cDecimal,
                         T_DECIMAL | FL_WB_PROTECTED | FL_FREEZE,
                         SHAPE_ID_FL_FROZEN, sizeof(struct RDecimal), 0);
    obj->value = val;
    if (dec_integral_p(val))
        RBASIC((VALUE)obj)->flags |= DEC_FL_INTEGRAL;
    return (VALUE)obj;
}

static inline VALUE
dec_from_integer_val(long fixval)
{
    if (fixval == 0) return decimal_zero;
    int neg = fixval < 0;
    uint64_t abs = neg ? (uint64_t)(-(fixval + 1)) + 1 : (uint64_t)fixval;
    if (abs <= DEC_BID_SIG_MAX)
        return dec_bid_encode(abs, 0, neg);
    dec_i128 result;
    if (__builtin_mul_overflow((dec_i128)fixval, DEC_SCALE, &result))
        rb_raise(rb_eRangeError, "Decimal overflow");
    NEWOBJ_OF_WITH_SHAPE(obj, struct RDecimal, rb_cDecimal,
                         T_DECIMAL | FL_WB_PROTECTED | FL_FREEZE | DEC_FL_INTEGRAL,
                         SHAPE_ID_FL_FROZEN, sizeof(struct RDecimal), 0);
    obj->value = result;
    return (VALUE)obj;
}

static VALUE
i128_to_ruby(dec_i128 val)
{
    if (val >= LONG_MIN && val <= LONG_MAX)
        return LONG2NUM((long)val);

    dec_u128 v = (dec_u128)val;
    uint64_t words[2] = {(uint64_t)(v & MASK64), (uint64_t)(v >> 64)};
    return rb_integer_unpack(words, 2, 8, 0,
                             INTEGER_PACK_LITTLE_ENDIAN | INTEGER_PACK_2COMP);
}

static dec_i128
ruby_int_to_i128(VALUE integer)
{
    if (FIXNUM_P(integer))
        return (dec_i128)FIX2LONG(integer);
    uint64_t words[2];
    int ret = rb_integer_pack(integer, words, 2, 8, 0,
                              INTEGER_PACK_LITTLE_ENDIAN | INTEGER_PACK_2COMP);
    if (ret == 2 || ret == -2)
        rb_raise(rb_eRangeError, "Decimal overflow");
    return (dec_i128)((dec_u128)words[1] << 64 | words[0]);
}

static int
ruby_int_to_i128_noexc(VALUE integer, dec_i128 *out)
{
    if (FIXNUM_P(integer)) {
        *out = (dec_i128)FIX2LONG(integer);
        return 1;
    }
    uint64_t words[2];
    int ret = rb_integer_pack(integer, words, 2, 8, 0,
                              INTEGER_PACK_LITTLE_ENDIAN | INTEGER_PACK_2COMP);
    if (ret == 2 || ret == -2)
        return 0;
    *out = (dec_i128)((dec_u128)words[1] << 64 | words[0]);
    return 1;
}

static VALUE
dec_from_rational_scaled(VALUE rational, int raise)
{
    VALUE scaled = rb_funcall(rational, '*', 1, decimal_scale_val);
    VALUE truncated = rb_funcall(scaled, idTo_i, 0);
    if (!rb_equal(scaled, truncated)) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "precision exceeds 18 decimal places");
    }
    if (!raise) {
        dec_i128 val;
        if (!ruby_int_to_i128_noexc(truncated, &val))
            return Qnil;
        return dec_from_i128(val);
    }
    return dec_from_i128(ruby_int_to_i128(truncated));
}

static int
dec_i128_mul_pow10(dec_i128 *val, int exp)
{
    while (exp > 0) {
        int chunk = exp > 18 ? 18 : exp;
        dec_i128 next;
        if (__builtin_mul_overflow(*val, (dec_i128)POW10[chunk], &next))
            return 0;
        *val = next;
        exp -= chunk;
    }
    return 1;
}

static void
dec_i128_div_pow10(dec_i128 *val, int exp)
{
    while (exp > 0 && *val != 0) {
        int chunk = exp > 18 ? 18 : exp;
        *val /= (dec_i128)POW10[chunk];
        exp -= chunk;
    }
}

static VALUE
decimal_parse_float_string(const char *str, long slen, int raise)
{
    const char *p = str;
    const char *end = str + slen;
    const char *exp = memchr(str, 'e', slen);

    if (!exp)
        exp = memchr(str, 'E', slen);
    if (!exp)
        return decimal_parse(str, slen, raise);

    int neg = 0;
    if (p < exp && *p == '-') {
        neg = 1;
        p++;
    }
    else if (p < exp && *p == '+') {
        p++;
    }

    dec_i128 sig = 0;
    int frac_digits = 0;
    int seen_digit = 0;
    int seen_dot = 0;

    for (; p < exp; p++) {
        if (*p == '.') {
            if (seen_dot) {
                if (!raise) return Qnil;
                rb_raise(rb_eArgError, "invalid value for Decimal()");
            }
            seen_dot = 1;
            continue;
        }
        if (!isdigit((unsigned char)*p)) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "invalid value for Decimal()");
        }
        dec_i128 next;
        if (__builtin_mul_overflow(sig, 10, &next) ||
            __builtin_add_overflow(next, *p - '0', &next)) {
            if (!raise) return Qnil;
            rb_raise(rb_eRangeError, "Decimal overflow");
        }
        sig = next;
        seen_digit = 1;
        if (seen_dot)
            frac_digits++;
    }

    if (!seen_digit) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for Decimal()");
    }

    p = exp + 1;
    int exp_neg = 0;
    if (p < end && *p == '-') {
        exp_neg = 1;
        p++;
    }
    else if (p < end && *p == '+') {
        p++;
    }

    if (p >= end) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for Decimal()");
    }

    int exponent = 0;
    for (; p < end; p++) {
        if (!isdigit((unsigned char)*p)) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "invalid value for Decimal()");
        }
        if (exponent > 100000000) {
            if (!raise) return Qnil;
            rb_raise(rb_eRangeError, "Decimal overflow");
        }
        exponent = exponent * 10 + (*p - '0');
    }
    if (exp_neg)
        exponent = -exponent;

    if (sig == 0)
        return decimal_zero;

    dec_i128 raw = sig;
    int shift = DEC_PRECISION + exponent - frac_digits;
    if (shift >= 0) {
        if (!dec_i128_mul_pow10(&raw, shift)) {
            if (!raise) return Qnil;
            rb_raise(rb_eRangeError, "Decimal overflow");
        }
    }
    else {
        dec_i128 before = raw;
        dec_i128_div_pow10(&raw, -shift);
        dec_i128 check = raw;
        if (!dec_i128_mul_pow10(&check, -shift) || check != before) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "precision exceeds 18 decimal places");
        }
    }

    if (neg)
        raw = -raw;
    return dec_from_i128(raw);
}

static void
wide_mul_64(dec_u128 a, uint64_t b, dec_u128 *lo, dec_u128 *hi)
{
    dec_u128 ll = (uint64_t)a * (dec_u128)b;
    dec_u128 hl = (a >> 64) * (dec_u128)b;
    *lo = ll + (hl << 64);
    *hi = (hl >> 64) + (*lo < ll);
}

static void
wide_mul(dec_u128 a, dec_u128 b, dec_u128 *lo, dec_u128 *hi)
{
    if (__builtin_expect(b <= MASK64, 1)) {
        wide_mul_64(a, (uint64_t)b, lo, hi);
        return;
    }

    dec_u128 al = a & MASK64, ah = a >> 64;
    dec_u128 bl = b & MASK64, bh = b >> 64;
    dec_u128 ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;

    dec_u128 mid = lh + hl;
    int carry_mid = mid < lh;

    *lo = ll + (mid << 64);
    int carry_lo = *lo < ll;

    *hi = hh + (mid >> 64) + ((dec_u128)carry_mid << 64) + (dec_u128)carry_lo;
}

static int
wide_div(dec_u128 hi, dec_u128 lo, dec_u128 d, dec_u128 *result)
{
    if (d == 0) return -1;

    if (d <= MASK64) {
        uint64_t d64 = (uint64_t)d;
        if (hi == 0) {
            uint64_t lo_hi = (uint64_t)(lo >> 64);
            if (lo_hi == 0) {
                *result = (uint64_t)lo / d64;
                return 0;
            }
            uint64_t q1 = lo_hi / d64;
            uint64_t r1 = lo_hi - q1 * d64;
            dec_u128 tail = ((dec_u128)r1 << 64) | (uint64_t)lo;
            *result = ((dec_u128)q1 << 64) | (uint64_t)(tail / d64);
            return 0;
        }
        if (hi >= d) return -1;
        uint64_t r = (uint64_t)hi;
        dec_u128 mid = ((dec_u128)r << 64) | (lo >> 64);
        uint64_t q1 = (uint64_t)(mid / d64);
        uint64_t r1 = (uint64_t)(mid - (dec_u128)q1 * d64);
        dec_u128 tail = ((dec_u128)r1 << 64) | (uint64_t)lo;
        *result = ((dec_u128)q1 << 64) | (uint64_t)(tail / d64);
        return 0;
    }

    if (hi == 0) {
        *result = lo / d;
        return 0;
    }
    if (hi >= d) return -1;

    dec_u128 r = hi, q = 0;
    for (int i = 127; i >= 0; i--) {
        r = (r << 1) | ((lo >> i) & 1);
        if (r >= d) {
            r -= d;
            q |= (dec_u128)1 << i;
        }
    }
    *result = q;
    return 0;
}

static dec_i128
i128_wide_op(dec_i128 a, dec_i128 b, dec_u128 factor, dec_u128 divisor, int *overflow)
{
    int neg = (a < 0) ^ (b < 0);
    dec_u128 aa = a < 0 ? -(dec_u128)a : (dec_u128)a;
    dec_u128 lo, hi, q;
    wide_mul(aa, factor, &lo, &hi);
    if (wide_div(hi, lo, divisor, &q) != 0) {
        *overflow = 1;
        return 0;
    }
    dec_u128 limit = neg ? ((dec_u128)1 << 127) : (((dec_u128)1 << 127) - 1);
    if (q > limit) {
        *overflow = 1;
        return 0;
    }
    return neg ? (dec_i128)(~q + 1) : (dec_i128)q;
}

/* Barrett reduction: divide u128 by SCALE via precomputed reciprocal.
 *  q = (n * M) >> 315 where M = ceil(2^315 / 10**18). */
static inline dec_u128
div_by_scale_barrett(dec_u128 n)
{
    static const dec_u128 M_HI = ((dec_u128)0x9392ee8e921d5d07ULL << 64) | 0x3aff322e62439fcfULL;
    static const dec_u128 M_LO = ((dec_u128)0x32d7f344649470f9ULL << 64) | 0x0cac0c573bf9e1b6ULL;

    dec_u128 unused, lo_hi, hi_lo, hi_hi;
    wide_mul(n, M_LO, &unused, &lo_hi);
    wide_mul(n, M_HI, &hi_lo, &hi_hi);

    dec_u128 mid = lo_hi + hi_lo;
    dec_u128 carry = (mid < lo_hi) ? 1 : 0;

    dec_u128 top = hi_hi + carry;

    return top >> 59;
}

static dec_i128
i128_mul_scaled(dec_i128 a, dec_i128 b, int *overflow)
{
    int neg = (a < 0) ^ (b < 0);
    dec_u128 aa = a < 0 ? -(dec_u128)a : (dec_u128)a;
    dec_u128 bb = b < 0 ? -(dec_u128)b : (dec_u128)b;
    if (__builtin_expect(aa <= MASK64 && bb <= MASK64, 1)) {
        dec_u128 prod = (dec_u128)(uint64_t)aa * (uint64_t)bb;
        dec_u128 q = div_by_scale_barrett(prod);
        dec_u128 limit = neg ? ((dec_u128)1 << 127) : (((dec_u128)1 << 127) - 1);
        if (q > limit) {
            *overflow = 1;
            return 0;
        }
        return neg ? (dec_i128)(~q + 1) : (dec_i128)q;
    }
    return i128_wide_op(a, b, bb, (dec_u128)DEC_SCALE, overflow);
}

static dec_i128
i128_div_scaled(dec_i128 a, dec_i128 b, int *overflow)
{
    if (b == 0) {
        *overflow = 1;
        return 0;
    }
    if (a == 0) return 0;
    int neg = (a < 0) ^ (b < 0);
    dec_u128 aa = a < 0 ? -(dec_u128)a : (dec_u128)a;
    dec_u128 bb = b < 0 ? -(dec_u128)b : (dec_u128)b;
    if (__builtin_expect(aa <= MASK64, 1)) {
        dec_u128 num = (dec_u128)(uint64_t)aa * (uint64_t)DEC_SCALE;
        dec_u128 q = num / bb;
        dec_u128 limit = neg ? ((dec_u128)1 << 127) : (((dec_u128)1 << 127) - 1);
        if (q > limit) {
            *overflow = 1;
            return 0;
        }
        return neg ? (dec_i128)(~q + 1) : (dec_i128)q;
    }
    return i128_wide_op(a, b, (dec_u128)DEC_SCALE, bb, overflow);
}

static inline VALUE
bid_add(uint64_t sig1, int s1, int n1, uint64_t sig2, int s2, int n2)
{
    int s;
    dec_u128 w1, w2;
    if (s1 >= s2) {
        w1 = sig1;
        w2 = (dec_u128)sig2 * POW10[s1 - s2];
        s = s1;
    }
    else {
        w1 = (dec_u128)sig1 * POW10[s2 - s1];
        w2 = sig2;
        s = s2;
    }
    dec_u128 result;
    int neg;
    if (n1 == n2) {
        result = w1 + w2;
        neg = n1;
    }
    else if (w1 >= w2) {
        result = w1 - w2;
        neg = n1;
    }
    else {
        result = w2 - w1;
        neg = n2;
    }
    if (result == 0) return decimal_zero;
    if ((result >> 64) == 0) {
        uint64_t sig = strip_tz((uint64_t)result, &s, 15);
        if (sig <= DEC_BID_SIG_MAX)
            return dec_bid_encode(sig, s, neg);
    }
    return Qundef;
}

static inline int
bid_cmp(VALUE a, VALUE b)
{
    if (dec_bid_scale(a) == dec_bid_scale(b))
        return ((int64_t)a > (int64_t)b) - ((int64_t)a < (int64_t)b);
    int na = dec_bid_neg(a), nb = dec_bid_neg(b);
    uint64_t sa = dec_bid_sig(a), sb = dec_bid_sig(b);
    if (sa == 0 && sb == 0) return 0;
    if (sa == 0) return nb ? 1 : -1;
    if (sb == 0) return na ? -1 : 1;
    if (na != nb) return na ? -1 : 1;
    dec_u128 wa, wb;
    int sca = dec_bid_scale(a), scb = dec_bid_scale(b);
    if (sca > scb) {
        wa = sa;
        wb = (dec_u128)sb * POW10[sca - scb];
    }
    else {
        wa = (dec_u128)sa * POW10[scb - sca];
        wb = sb;
    }
    int cmp = (wa > wb) - (wa < wb);
    return na ? -cmp : cmp;
}

static inline int
decimal_check(VALUE v)
{
    return (int)__builtin_expect(decimal_p(v), 1);
}

static VALUE
decimal_s_alloc(VALUE klass)
{
    NEWOBJ_OF(obj, struct RDecimal, klass,
              T_DECIMAL | FL_WB_PROTECTED,
              sizeof(struct RDecimal), 0);
    RDECIMAL((VALUE)obj)->value = 0;
    return (VALUE)obj;
}

/*
 *  call-seq:
 *    decimal.scaled_value  ->  integer
 *
 *  Returns the internal 128-bit scaled integer (value * 10**18).
 *
 *    1.5d.scaled_value   #=> 1500000000000000000
 *    -42d.scaled_value   #=> -42000000000000000000
 */
static VALUE
decimal_scaled_value(VALUE self)
{
    return i128_to_ruby(dec_to_i128(self));
}

__attribute__((noinline))
static VALUE
decimal_from_bignum(VALUE integer)
{
    dec_i128 val = ruby_int_to_i128(integer), result;
    if (__builtin_mul_overflow(val, DEC_SCALE, &result))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(result);
}

VALUE
rb_decimal_from_integer(VALUE integer)
{
    if (FIXNUM_P(integer))
        return dec_from_integer_val(FIX2LONG(integer));
    return decimal_from_bignum(integer);
}

static VALUE
decimal_s_from_integer(VALUE klass, VALUE integer)
{
    (void)klass;
    return rb_decimal_from_integer(integer);
}

__attribute__((noinline, cold))
static VALUE
decimal_plus_slow(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other))
        other = rb_decimal_from_integer(other);
    else if (RB_FLOAT_TYPE_P(other))
        return DBL2NUM(rb_decimal_to_f_value(self) + NUM2DBL(other));
    else if (RB_TYPE_P(other, T_RATIONAL))
        other = rb_Decimal(other);
    else
        return rb_num_coerce_bin(self, other, '+');
    return rb_decimal_plus_dd(self, other);
}

/*
 *  call-seq:
 *    decimal + numeric  ->  numeric
 *
 *  Returns the sum of +self+ and +numeric+:
 *
 *    1.5d + 2.5d    #=> 4.0d
 *    1.5d + 1       #=> 2.5d
 *    1.5d + 0.5     #=> 2.0 (Float)
 */
VALUE
rb_decimal_plus(VALUE self, VALUE other)
{
    if (__builtin_expect(!decimal_check(other), 0))
        return decimal_plus_slow(self, other);
    return rb_decimal_plus_dd(self, other);
}

__attribute__((noinline, cold))
static VALUE
decimal_minus_slow(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other))
        other = rb_decimal_from_integer(other);
    else if (RB_FLOAT_TYPE_P(other))
        return DBL2NUM(rb_decimal_to_f_value(self) - NUM2DBL(other));
    else if (RB_TYPE_P(other, T_RATIONAL))
        other = rb_Decimal(other);
    else
        return rb_num_coerce_bin(self, other, '-');
    return rb_decimal_minus_dd(self, other);
}

/*
 *  call-seq:
 *    decimal - numeric  ->  numeric
 *
 *  Returns the difference of +self+ and +numeric+:
 *
 *    10.5d - 3.2d   #=> 7.3d
 *    10.5d - 1      #=> 9.5d
 *    10.5d - 0.5    #=> 10.0 (Float)
 */
VALUE
rb_decimal_minus(VALUE self, VALUE other)
{
    if (__builtin_expect(!decimal_check(other), 0))
        return decimal_minus_slow(self, other);
    return rb_decimal_minus_dd(self, other);
}

/*
 *  call-seq:
 *    -decimal  ->  decimal
 *
 *  Returns +self+, negated:
 *
 *    -(1.5d)   #=> -1.5d
 *    -(-1.5d)  #=> 1.5d
 */
VALUE
rb_decimal_uminus_dd(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        if (sig == 0) return self;
        return dec_bid_encode(sig, dec_bid_scale(self), !dec_bid_neg(self));
    }
    dec_i128 a = RDECIMAL(self)->value, r;
    if (__builtin_sub_overflow((dec_i128)0, a, &r))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

static VALUE
decimal_uminus(VALUE self)
{
    return rb_decimal_uminus_dd(self);
}

__attribute__((noinline, cold))
static VALUE
decimal_mul_slow(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other))
        other = rb_decimal_from_integer(other);
    else if (RB_FLOAT_TYPE_P(other))
        return DBL2NUM(rb_decimal_to_f_value(self) * NUM2DBL(other));
    else if (RB_TYPE_P(other, T_RATIONAL))
        other = rb_Decimal(other);
    else
        return rb_num_coerce_bin(self, other, '*');
    return rb_decimal_mul_dd(self, other);
}

/*
 *  call-seq:
 *    decimal * numeric  ->  numeric
 *
 *  Returns the product of +self+ and +numeric+:
 *
 *    2.5d * 4.0d    #=> 10.0d
 *    2.5d * 2       #=> 5.0d
 *    2.5d * 0.5     #=> 1.25 (Float)
 */
VALUE
rb_decimal_mul(VALUE self, VALUE other)
{
    if (__builtin_expect(!decimal_check(other), 0))
        return decimal_mul_slow(self, other);
    return rb_decimal_mul_dd(self, other);
}

__attribute__((noinline, cold))
static VALUE
decimal_div_slow(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other))
        other = rb_decimal_from_integer(other);
    else if (RB_FLOAT_TYPE_P(other))
        return DBL2NUM(rb_decimal_to_f_value(self) / NUM2DBL(other));
    else if (RB_TYPE_P(other, T_RATIONAL))
        other = rb_Decimal(other);
    else
        return rb_num_coerce_bin(self, other, '/');
    return rb_decimal_div_dd(self, other);
}

/*
 *  call-seq:
 *    decimal / numeric  ->  numeric
 *
 *  Returns the quotient of +self+ and +numeric+, truncated toward zero:
 *
 *    10.0d / 3.0d   #=> 3.333333333333333333d
 *    7.5d / 2       #=> 3.75d
 *    7.5d / 0.5     #=> 15.0 (Float)
 */
VALUE
rb_decimal_div(VALUE self, VALUE other)
{
    if (__builtin_expect(!decimal_check(other), 0))
        return decimal_div_slow(self, other);
    return rb_decimal_div_dd(self, other);
}

VALUE
rb_decimal_plus_dd(VALUE self, VALUE other)
{
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other)) {
        VALUE r = bid_add(dec_bid_sig(self), dec_bid_scale(self), dec_bid_neg(self),
                          dec_bid_sig(other), dec_bid_scale(other), dec_bid_neg(other));
        if (!UNDEF_P(r)) return r;
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    dec_i128 r;
    if (__builtin_add_overflow(a, b, &r))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

VALUE
rb_decimal_minus_dd(VALUE self, VALUE other)
{
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other)) {
        VALUE r = bid_add(dec_bid_sig(self), dec_bid_scale(self), dec_bid_neg(self),
                          dec_bid_sig(other), dec_bid_scale(other), !dec_bid_neg(other));
        if (!UNDEF_P(r)) return r;
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    dec_i128 r;
    if (__builtin_sub_overflow(a, b, &r))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

VALUE
rb_decimal_mul_dd(VALUE self, VALUE other)
{
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other)) {
        uint64_t sig1 = dec_bid_sig(self), sig2 = dec_bid_sig(other);
        if (sig1 == 0 || sig2 == 0) return decimal_zero;
        int s1 = dec_bid_scale(self), s2 = dec_bid_scale(other);
        int neg = dec_bid_neg(self) ^ dec_bid_neg(other);
        if (s1 == 0 && (dec_u128)sig1 * sig2 <= DEC_BID_SIG_MAX)
            return dec_bid_encode((uint64_t)((dec_u128)sig1 * sig2), s2, neg);
        if (s2 == 0 && (dec_u128)sig1 * sig2 <= DEC_BID_SIG_MAX)
            return dec_bid_encode((uint64_t)((dec_u128)sig1 * sig2), s1, neg);
        int s = s1 + s2;
        dec_u128 prod = (dec_u128)sig1 * sig2;
        if (s > 15 && prod > 0) {
            int excess = s - 15;
            dec_u128 orig = prod;
            if (excess <= 18 && (prod >> 64) == 0)
                prod = div_pow10((uint64_t)prod, excess);
            else
                prod /= (dec_u128)POW10[excess];
            if (prod * POW10[excess] != orig)
                goto mul_i128;
            s = 15;
        }
        if (prod <= DEC_BID_SIG_MAX) {
            uint64_t sig = strip_tz((uint64_t)prod, &s, 15);
            return dec_bid_encode(sig, s, neg);
        }
    }
  mul_i128:;
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (a == 0 || b == 0) return decimal_zero;
    if (a == DEC_SCALE) return other;
    if (b == DEC_SCALE) return self;
    int overflow = 0;
    dec_i128 r = i128_mul_scaled(a, b, &overflow);
    if (overflow) rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

VALUE
rb_decimal_div_dd(VALUE self, VALUE other)
{
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other)) {
        uint64_t sig1 = dec_bid_sig(self), sig2 = dec_bid_sig(other);
        if (sig2 == 0) rb_raise(rb_eZeroDivError, "Decimal division by zero");
        if (sig1 == 0) return decimal_zero;
        int s1 = dec_bid_scale(self), s2 = dec_bid_scale(other);
        int neg = dec_bid_neg(self) ^ dec_bid_neg(other);
        if (sig1 % sig2 == 0) {
            uint64_t quot = sig1 / sig2;
            int new_scale = s1 - s2;
            if (new_scale >= 0 && new_scale <= 15) {
                quot = strip_tz(quot, &new_scale, 15);
                if (quot <= DEC_BID_SIG_MAX)
                    return dec_bid_encode(quot, new_scale, neg);
            }
        }
        int avail = 15 - count_digits(sig1);
        if (avail > 0 && avail <= 18) {
            dec_u128 scaled = (dec_u128)sig1 * POW10[avail];
            if (scaled % sig2 == 0) {
                uint64_t quot = (uint64_t)(scaled / sig2);
                int new_scale = s1 - s2 + avail;
                if (new_scale >= 0 && new_scale <= 15 && quot <= DEC_BID_SIG_MAX) {
                    quot = strip_tz(quot, &new_scale, 15);
                    return dec_bid_encode(quot, new_scale, neg);
                }
            }
        }
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (b == 0) rb_raise(rb_eZeroDivError, "Decimal division by zero");
    if (b == DEC_SCALE) return self;
    int overflow = 0;
    dec_i128 r = i128_div_scaled(a, b, &overflow);
    if (overflow) rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

VALUE
rb_decimal_mod_dd(VALUE self, VALUE other)
{
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (b == 0) rb_raise(rb_eZeroDivError, "Decimal modulo by zero");
    dec_i128 r = a % b;
    if (r != 0 && ((r ^ b) < 0)) r += b;
    return dec_from_i128(r);
}

/*
 *  call-seq:
 *    decimal % numeric         ->  decimal
 *    decimal.modulo(numeric)   ->  decimal
 *
 *  Returns +self+ modulo +numeric+ using floored division:
 *
 *    10.0d % 3.0d    #=> 1.0d
 *    -10.0d % 3.0d   #=> 2.0d
 *    10.0d % -3.0d   #=> -2.0d
 */
static VALUE
decimal_mod(VALUE self, VALUE other)
{
    if (!decimal_check(other)) {
        if (RB_INTEGER_TYPE_P(other))
            other = rb_decimal_from_integer(other);
        else if (RB_TYPE_P(other, T_RATIONAL))
            other = rb_Decimal(other);
        else
            return rb_num_coerce_bin(self, other, '%');
    }
    return rb_decimal_mod_dd(self, other);
}

/*
 *  call-seq:
 *    decimal.divmod(numeric)  ->  array
 *
 *  Returns an array containing the quotient and modulus from
 *  floored division of +self+ by +numeric+:
 *
 *    11.0d.divmod(3.0d)    #=> [3, 2.0d]
 *    -11.0d.divmod(3.0d)   #=> [-4, 1.0d]
 *    11.0d.divmod(-3.0d)   #=> [-4, -1.0d]
 */
static VALUE
decimal_divmod(VALUE self, VALUE other)
{
    if (!decimal_check(other)) {
        if (RB_INTEGER_TYPE_P(other))
            other = rb_decimal_from_integer(other);
        else if (RB_TYPE_P(other, T_RATIONAL))
            other = rb_Decimal(other);
        else
            return rb_num_coerce_bin(self, other, idDivmod);
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (b == 0) rb_raise(rb_eZeroDivError, "Decimal divmod by zero");
    dec_i128 q = a / b;
    dec_i128 r = a - q * b;
    if (r != 0 && ((r ^ b) < 0)) {
        q--;
        r += b;
    }
    VALUE pair[2] = {i128_to_ruby(q), dec_from_i128(r)};
    return rb_ary_new_from_values(2, pair);
}

/*
 *  call-seq:
 *    decimal.div(numeric)  ->  integer
 *
 *  Returns the integer quotient from floored division of +self+
 *  by +numeric+:
 *
 *    11.0d.div(3.0d)    #=> 3
 *    -11.0d.div(3.0d)   #=> -4
 *    11.0d.div(-3.0d)   #=> -4
 */
static VALUE
decimal_div_int(VALUE self, VALUE other)
{
    if (!decimal_check(other)) {
        if (RB_INTEGER_TYPE_P(other))
            other = rb_decimal_from_integer(other);
        else if (RB_TYPE_P(other, T_RATIONAL))
            other = rb_Decimal(other);
        else
            return rb_num_coerce_bin(self, other, idDiv);
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (b == 0) rb_raise(rb_eZeroDivError, "Decimal div by zero");
    dec_i128 q = a / b;
    dec_i128 r = a - q * b;
    if (r != 0 && ((r ^ b) < 0)) q--;
    return i128_to_ruby(q);
}

/*
 *  call-seq:
 *    decimal ** exponent  ->  decimal
 *
 *  Returns +self+ raised to the Integer power +exponent+:
 *
 *    2.0d ** 10     #=> 1024.0d
 *    2.0d ** -1     #=> 0.5d
 *    2.0d ** 0      #=> 1.0d
 */
static VALUE
decimal_pow(VALUE self, VALUE exp_val)
{
    if (!FIXNUM_P(exp_val) && !RB_TYPE_P(exp_val, T_BIGNUM))
        rb_raise(rb_eTypeError, "Decimal#** supports only Integer exponents");

    long exp = FIXNUM_P(exp_val) ? FIX2LONG(exp_val) : NUM2LONG(exp_val);
    int neg = exp < 0;
    if (neg) {
        if (exp == LONG_MIN) rb_raise(rb_eRangeError, "Decimal overflow");
        exp = -exp;
    }
    if (exp == 0) return dec_from_i128(DEC_SCALE);
    if (!neg && exp == 1) return self;

    int overflow = 0;
    dec_i128 base = dec_to_i128(self);
    dec_i128 result = DEC_SCALE;
    while (exp > 0) {
        if (exp & 1) {
            result = i128_mul_scaled(result, base, &overflow);
            if (overflow) rb_raise(rb_eRangeError, "Decimal overflow");
        }
        exp >>= 1;
        if (exp > 0) {
            base = i128_mul_scaled(base, base, &overflow);
            if (overflow) rb_raise(rb_eRangeError, "Decimal overflow");
        }
    }
    if (neg) {
        if (result == 0)
            rb_raise(rb_eZeroDivError, "Decimal division by zero");
        result = i128_div_scaled(DEC_SCALE, result, &overflow);
        if (overflow) rb_raise(rb_eRangeError, "Decimal overflow");
    }
    return dec_from_i128(result);
}

/*
 *  call-seq:
 *    decimal.fdiv(numeric)  ->  float
 *
 *  Performs division and returns the value as a \Float.
 *
 *    2.0d.fdiv(3.0d)   #=> 0.6666666666666666
 *    1.0d.fdiv(0.5)    #=> 2.0
 */
static VALUE
decimal_fdiv(VALUE self, VALUE other)
{
    return rb_funcall(rb_decimal_to_f(self), '/', 1, other);
}

/*
 *  call-seq:
 *    decimal.remainder(numeric)  ->  decimal
 *
 *  Returns the remainder of +self+ divided by +numeric+
 *  (truncated toward zero):
 *
 *    10.0d.remainder(3.0d)    #=> 1.0d
 *    -10.0d.remainder(3.0d)   #=> -1.0d
 *    10.0d.remainder(-3.0d)   #=> 1.0d
 */
static VALUE
decimal_remainder(VALUE self, VALUE other)
{
    if (!decimal_check(other)) {
        if (RB_INTEGER_TYPE_P(other))
            other = rb_decimal_from_integer(other);
        else if (RB_TYPE_P(other, T_RATIONAL))
            other = rb_Decimal(other);
        else
            return rb_num_coerce_bin(self, other, id_remainder);
    }
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (b == 0) rb_raise(rb_eZeroDivError, "Decimal remainder by zero");
    return dec_from_i128(a % b);
}

/*
 *  call-seq:
 *    decimal <=> other  ->  -1, 0, 1, or nil
 *
 *  Compares +self+ and +other+.
 *
 *  Returns:
 *
 *  - +-1+, if +self+ is less than +other+.
 *  - +0+, if the two values are the same.
 *  - +1+, if +self+ is greater than +other+.
 *  - +nil+, if the two values are incomparable.
 *
 *    1.0d <=> 2.0d   #=> -1
 *    1.0d <=> 1.0d   #=> 0
 *    2.0d <=> 1.0d   #=> 1
 *    1.0d <=> "foo"  #=> nil
 */
/* Both arguments must be Decimal. Returns a tagged Fixnum and never
 * allocates, so YJIT calls this without jit_prepare_call_with_gc. */
VALUE
rb_decimal_cmp_dd(VALUE self, VALUE other)
{
    if (self == other) return INT2FIX(0);
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
        return INT2FIX(bid_cmp(self, other));
    dec_i128 a = dec_to_i128(self);
    dec_i128 b = dec_to_i128(other);
    if (a < b) return INT2FIX(-1);
    if (a > b) return INT2FIX(1);
    return INT2FIX(0);
}

static VALUE
decimal_cmp(VALUE self, VALUE other)
{
    if (decimal_check(other))
        return rb_decimal_cmp_dd(self, other);
    if (rb_obj_is_kind_of(other, rb_cNumeric)) {
        VALUE self_r = rb_funcall(self, idTo_r, 0);
        return rb_funcall(self_r, idCmp, 1, other);
    }
    return Qnil;
}

static VALUE
decimal_relop(VALUE self, VALUE other, int op)
{
    VALUE cmp = decimal_cmp(self, other);
    if (NIL_P(cmp)) rb_cmperr(self, other);
    int c = FIX2INT(cmp);
    switch (op) {
      case '<':  return RBOOL(c < 0);
      case 'L':  return RBOOL(c <= 0);
      case '>':  return RBOOL(c > 0);
      case 'G':  return RBOOL(c >= 0);
      default:   return Qnil;
    }
}

/*
 *  call-seq:
 *    decimal < other -> true or false
 *
 *  Returns +true+ if +self+ is less than +other+, +false+ otherwise.
 */
static VALUE
decimal_lt(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
            return RBOOL(bid_cmp(self, other) < 0);
        return RBOOL(dec_to_i128(self) < dec_to_i128(other));
    }
    if (rb_obj_is_kind_of(other, rb_cNumeric))
        return decimal_relop(self, other, '<');
    return rb_num_coerce_relop(self, other, '<');
}

/*
 *  call-seq:
 *    decimal <= other -> true or false
 *
 *  Returns +true+ if +self+ is less than or equal to +other+, +false+ otherwise.
 */
static VALUE
decimal_le(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
            return RBOOL(bid_cmp(self, other) <= 0);
        return RBOOL(dec_to_i128(self) <= dec_to_i128(other));
    }
    if (rb_obj_is_kind_of(other, rb_cNumeric))
        return decimal_relop(self, other, 'L');
    return rb_num_coerce_relop(self, other, idLE);
}

/*
 *  call-seq:
 *    decimal > other -> true or false
 *
 *  Returns +true+ if +self+ is greater than +other+, +false+ otherwise.
 */
static VALUE
decimal_gt(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
            return RBOOL(bid_cmp(self, other) > 0);
        return RBOOL(dec_to_i128(self) > dec_to_i128(other));
    }
    if (rb_obj_is_kind_of(other, rb_cNumeric))
        return decimal_relop(self, other, '>');
    return rb_num_coerce_relop(self, other, '>');
}

/*
 *  call-seq:
 *    decimal >= other -> true or false
 *
 *  Returns +true+ if +self+ is greater than or equal to +other+, +false+ otherwise.
 */
static VALUE
decimal_ge(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
            return RBOOL(bid_cmp(self, other) >= 0);
        return RBOOL(dec_to_i128(self) >= dec_to_i128(other));
    }
    if (rb_obj_is_kind_of(other, rb_cNumeric))
        return decimal_relop(self, other, 'G');
    return rb_num_coerce_relop(self, other, idGE);
}

/*
 *  call-seq:
 *    decimal.hash  ->  integer
 *
 *  Returns the integer hash value for +self+.
 *
 *    1.5d.hash == 1.5d.hash   #=> true
 */
static VALUE
decimal_hash(VALUE self)
{
    dec_i128 v = dec_to_i128(self);
    st_index_t h = rb_hash_start((st_index_t)((dec_u128)v & MASK64));
    h = rb_hash_uint(h, (st_index_t)((dec_u128)v >> 64));
    h = rb_hash_end(h);
    return ST2FIX(h);
}

/*
 *  call-seq:
 *    decimal == other  ->  true or false
 *
 *  Returns +true+ if +other+ has the same value as +self+.
 *  Compares with other numeric types via <=>.
 *
 *    1.0d == 1.0d   #=> true
 *    1.0d == 1      #=> true
 *    0.5d == 0.5    #=> true
 */
static VALUE
decimal_eq(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        if (self == other) return Qtrue;
        if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
            return RBOOL(bid_cmp(self, other) == 0);
        return RBOOL(dec_to_i128(self) == dec_to_i128(other));
    }
    if (rb_obj_is_kind_of(other, rb_cNumeric)) {
        VALUE cmp = decimal_cmp(self, other);
        return RBOOL(cmp == INT2FIX(0));
    }
    return Qfalse;
}

/*
 *  call-seq:
 *    decimal.eql?(other)  ->  true or false
 *
 *  Returns +true+ if +other+ is a \Decimal with the same value:
 *
 *    1.0d.eql?(1.0d)   #=> true
 *    1.0d.eql?(1)      #=> false
 *    1.0d.eql?(1.0)    #=> false
 */
static VALUE
decimal_eql(VALUE self, VALUE other)
{
    if (!decimal_check(other)) return Qfalse;
    if (self == other) return Qtrue;
    if (RB_DECIMAL_IMM_P(self) && RB_DECIMAL_IMM_P(other))
        return RBOOL(bid_cmp(self, other) == 0);
    return RBOOL(dec_to_i128(self) == dec_to_i128(other));
}

/*
 *  call-seq:
 *     decimal.zero?  ->  true or false
 *
 *  Returns +true+ if +self+ has a zero value.
 *
 *     0.0d.zero?    #=> true
 *     0.1d.zero?    #=> false
 */
static VALUE
decimal_zero_p(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self))
        return RBOOL(dec_bid_sig(self) == 0);
    return RBOOL(RDECIMAL(self)->value == 0);
}

/*
 *  call-seq:
 *     decimal.positive?  ->  true or false
 *
 *  Returns +true+ if +self+ is greater than 0.
 */
static VALUE
decimal_positive_p(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self))
        return RBOOL(!dec_bid_neg(self) && dec_bid_sig(self) != 0);
    return RBOOL(RDECIMAL(self)->value > 0);
}

/*
 *  call-seq:
 *     decimal.negative?  ->  true or false
 *
 *  Returns +true+ if +self+ is less than 0.
 */
static VALUE
decimal_negative_p(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self))
        return RBOOL(dec_bid_neg(self) && dec_bid_sig(self) != 0);
    return RBOOL(RDECIMAL(self)->value < 0);
}

/*
 *  call-seq:
 *     decimal.integer?  ->  true or false
 *
 *  Returns +true+ if +self+ has no fractional part.
 *
 *     42.0d.integer?    #=> true
 *     42.5d.integer?    #=> false
 */
static VALUE
decimal_integer_p(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self))
        return RBOOL(dec_bid_scale(self) == 0);
    if (RBASIC(self)->flags & DEC_FL_INTEGRAL) return Qtrue;
    return RBOOL(RDECIMAL(self)->value % DEC_SCALE == 0);
}

/*
 *  call-seq:
 *     decimal.finite?  ->  true
 *
 *  Returns +true+. Decimal values are always finite.
 */
static VALUE
decimal_finite_p(VALUE self)
{
    (void)self;
    return Qtrue;
}

/*
 *  call-seq:
 *     decimal.infinite?  ->  nil
 *
 *  Returns +nil+. Decimal values are never infinite.
 */
static VALUE
decimal_infinite_p(VALUE self)
{
    (void)self;
    return Qnil;
}

/*
 *  call-seq:
 *     decimal.abs  ->  decimal
 *
 *  Returns the absolute value of +self+.
 *
 *     (-1.5d).abs   #=> 1.5d
 *     (1.5d).abs    #=> 1.5d
 */
VALUE
rb_decimal_abs(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        if (!dec_bid_neg(self)) return self;
        return dec_bid_encode(dec_bid_sig(self), dec_bid_scale(self), 0);
    }
    dec_i128 a = RDECIMAL(self)->value, r;
    if (a >= 0) return self;
    if (__builtin_sub_overflow((dec_i128)0, a, &r))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(r);
}

/*
 *  call-seq:
 *    decimal.fix  ->  decimal
 *
 *  Returns the integer part of +self+ as a \Decimal.
 *
 *    1.9d.fix    #=> 1.0d
 *    -1.9d.fix   #=> -1.0d
 */
static VALUE
decimal_fix(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        int scale = dec_bid_scale(self);
        if (scale == 0) return self;
        uint64_t sig = dec_bid_sig(self) / POW10[scale];
        return dec_bid_encode(sig, 0, dec_bid_neg(self));
    }
    dec_i128 v = RDECIMAL(self)->value;
    return dec_from_i128((v / DEC_SCALE) * DEC_SCALE);
}

/*
 *  call-seq:
 *    decimal.frac  ->  decimal
 *
 *  Returns the fractional part of +self+ as a \Decimal.
 *
 *    1.9d.frac    #=> 0.9d
 *    -1.9d.frac   #=> -0.9d
 */
static VALUE
decimal_frac(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        int scale = dec_bid_scale(self);
        if (scale == 0) return decimal_zero;
        uint64_t sig = dec_bid_sig(self);
        uint64_t whole = sig / POW10[scale];
        uint64_t frac_sig = sig - whole * POW10[scale];
        if (frac_sig == 0) return decimal_zero;
        return dec_bid_encode(frac_sig, scale, dec_bid_neg(self));
    }
    return dec_from_i128(RDECIMAL(self)->value % DEC_SCALE);
}

/*
 *  call-seq:
 *    decimal.floor([ndigits])  ->  integer or decimal
 *
 *  Returns the largest number less than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Returns a \Decimal when +ndigits+ is positive,
 *  otherwise returns an \Integer.
 *
 *    1.9d.floor      #=> 1
 *    -1.9d.floor     #=> -2
 *    1.555d.floor(2) #=> 1.55d
 */
static VALUE
decimal_floor(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    int ndigits = dec_parse_ndigits(argc, argv);
    VALUE shortcut = dec_rounding_shortcut(self, ndigits);
    if (!UNDEF_P(shortcut)) return shortcut;

    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        int neg = dec_bid_neg(self);
        if (ndigits == 0) {
            uint64_t q = div_pow10(sig, scale);
            int has_frac = (sig != q * POW10[scale]);
            if (neg && has_frac) q++;
            return neg ? LONG2NUM(-(long)q) : LONG2NUM((long)q);
        }
        if (ndigits > 0 && ndigits < scale) {
            int drop = scale - ndigits;
            uint64_t q = div_pow10(sig, drop);
            uint64_t trunc_sig = q * POW10[drop];
            if (neg && sig != trunc_sig) trunc_sig += POW10[drop];
            if (trunc_sig <= DEC_BID_SIG_MAX)
                return dec_bid_encode(trunc_sig, scale, neg);
        }
    }

    dec_i128 v = dec_to_i128(self);

    if (ndigits <= 0) {
        dec_i128 q = v / DEC_SCALE;
        if (v < 0 && v - q * DEC_SCALE != 0) q--;
        VALUE result = i128_to_ruby(q);
        if (ndigits == 0) return result;
        return rb_funcall(result, id_floor, 1, INT2FIX(ndigits));
    }

    dec_i128 factor = (dec_i128)POW10[18 - ndigits];
    dec_i128 q = v / factor;
    if (v < 0 && v - q * factor != 0) q--;
    dec_i128 result;
    if (__builtin_mul_overflow(q, factor, &result))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(result);
}

/*
 *  call-seq:
 *    decimal.ceil([ndigits])  ->  integer or decimal
 *
 *  Returns the smallest number greater than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Returns a \Decimal when +ndigits+ is positive,
 *  otherwise returns an \Integer.
 *
 *    1.1d.ceil       #=> 2
 *    -1.9d.ceil      #=> -1
 *    1.555d.ceil(2)  #=> 1.56d
 */
static VALUE
decimal_ceil(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    int ndigits = dec_parse_ndigits(argc, argv);
    VALUE shortcut = dec_rounding_shortcut(self, ndigits);
    if (!UNDEF_P(shortcut)) return shortcut;

    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        int neg = dec_bid_neg(self);
        if (ndigits == 0) {
            uint64_t q = div_pow10(sig, scale);
            int has_frac = (sig != q * POW10[scale]);
            if (!neg && has_frac) q++;
            return neg ? LONG2NUM(-(long)q) : LONG2NUM((long)q);
        }
        if (ndigits > 0 && ndigits < scale) {
            int drop = scale - ndigits;
            uint64_t q = div_pow10(sig, drop);
            uint64_t trunc_sig = q * POW10[drop];
            if (!neg && sig != trunc_sig) trunc_sig += POW10[drop];
            if (trunc_sig <= DEC_BID_SIG_MAX)
                return dec_bid_encode(trunc_sig, scale, neg);
        }
    }

    dec_i128 v = dec_to_i128(self);

    if (ndigits <= 0) {
        dec_i128 q = v / DEC_SCALE;
        dec_i128 r = v - q * DEC_SCALE;
        if (r < 0) {
            q--;
            r += DEC_SCALE;
        }
        if (r != 0) q++;
        VALUE result = i128_to_ruby(q);
        if (ndigits == 0) return result;
        return rb_funcall(result, id_ceil, 1, INT2FIX(ndigits));
    }

    dec_i128 factor = (dec_i128)POW10[18 - ndigits];
    dec_i128 q = v / factor;
    dec_i128 r = v - q * factor;
    if (r < 0) {
        q--;
        r += factor;
    }
    if (r == 0) return self;
    dec_i128 result;
    if (__builtin_mul_overflow(q + 1, factor, &result))
        rb_raise(rb_eRangeError, "Decimal overflow");
    return dec_from_i128(result);
}

/*
 *  call-seq:
 *    decimal.truncate([ndigits])  ->  integer or decimal
 *
 *  Returns +self+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Returns a \Decimal when +ndigits+ is positive,
 *  otherwise returns an \Integer.
 *
 *    1.9d.truncate       #=> 1
 *    -1.9d.truncate      #=> -1
 *    1.555d.truncate(2)  #=> 1.55d
 */
static VALUE
decimal_truncate(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    int ndigits = dec_parse_ndigits(argc, argv);
    VALUE shortcut = dec_rounding_shortcut(self, ndigits);
    if (!UNDEF_P(shortcut)) return shortcut;

    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        int neg = dec_bid_neg(self);
        if (ndigits == 0) {
            uint64_t q = div_pow10(sig, scale);
            return neg ? LONG2NUM(-(long)q) : LONG2NUM((long)q);
        }
        if (ndigits > 0 && ndigits < scale) {
            int drop = scale - ndigits;
            uint64_t q = div_pow10(sig, drop);
            uint64_t trunc_sig = q * POW10[drop];
            if (trunc_sig <= DEC_BID_SIG_MAX)
                return dec_bid_encode(trunc_sig, scale, neg);
        }
    }

    dec_i128 v = dec_to_i128(self);

    if (ndigits <= 0) {
        dec_i128 q = v / DEC_SCALE;
        VALUE result = i128_to_ruby(q);
        if (ndigits == 0) return result;
        return rb_funcall(result, id_truncate, 1, INT2FIX(ndigits));
    }

    dec_i128 factor = (dec_i128)POW10[18 - ndigits];
    return dec_from_i128((v / factor) * factor);
}

/*
 *  call-seq:
 *    decimal.round([ndigits], half: :up)  ->  integer or decimal
 *
 *  Returns +self+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  The +half+ keyword specifies how to break ties:
 *  - +:up+ (default): round away from zero.
 *  - +:down+: round toward zero.
 *  - +:even+: round to the nearest even digit.
 *
 *  Returns a \Decimal when +ndigits+ is positive,
 *  otherwise returns an \Integer.
 *
 *    1.5d.round       #=> 2
 *    1.5d.round(half: :down)  #=> 1
 *    2.5d.round(half: :even)  #=> 2
 *    1.555d.round(2)  #=> 1.56d
 */
static VALUE
decimal_round(int argc, VALUE *argv, VALUE self)
{
    /* Skip rb_scan_args when called as round(n) with no keyword. */
    int ndigits = 0;
    enum ruby_num_rounding_mode mode = RUBY_NUM_ROUND_DEFAULT;
    if (argc == 1 && FIXNUM_P(argv[0])) {
        ndigits = (int)FIX2LONG(argv[0]);
    }
    else {
        VALUE nd = Qnil, opts = Qnil;
        rb_scan_args(argc, argv, "01:", &nd, &opts);
        ndigits = NIL_P(nd) ? 0 : NUM2INT(nd);
        mode = rb_num_get_rounding_option(opts);
    }

    if (RB_DECIMAL_IMM_P(self) && dec_bid_scale(self) == 0) {
        if (ndigits > 0) return self;
        if (ndigits == 0) {
            uint64_t sig = dec_bid_sig(self);
            if (dec_bid_neg(self))
                return LONG2NUM(-(long)sig);
            return LONG2NUM((long)sig);
        }
    }
    else if (!RB_DECIMAL_IMM_P(self) && RDECIMAL(self)->value % DEC_SCALE == 0) {
        if (ndigits > 0) return self;
        if (ndigits == 0) return i128_to_ruby(RDECIMAL(self)->value / DEC_SCALE);
    }

    if (ndigits >= 18) return self;

    if (ndigits < 0) {
        VALUE integer = i128_to_ruby(dec_to_i128(self) / DEC_SCALE);
        return rb_funcallv_kw(integer, id_round, argc, argv, RB_PASS_CALLED_KEYWORDS);
    }

    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        int neg = dec_bid_neg(self);
        if (ndigits < scale) {
            int drop = scale - ndigits;
            uint64_t divisor = POW10[drop];
            uint64_t q = div_pow10(sig, drop);
            uint64_t remainder = sig - q * divisor;
            uint64_t half = divisor / 2;
            int round_up;
            if (remainder > half)
                round_up = 1;
            else if (remainder < half)
                round_up = 0;
            else
                round_up = (mode == RUBY_NUM_ROUND_HALF_UP) ||
                           (mode == RUBY_NUM_ROUND_HALF_EVEN && (q & 1));
            if (round_up) q++;
            if (ndigits == 0)
                return neg ? LONG2NUM(-(long)q) : LONG2NUM((long)q);
            uint64_t new_sig = q * divisor;
            int new_scale = scale;
            new_sig = strip_tz(new_sig, &new_scale, 15);
            if (new_sig <= DEC_BID_SIG_MAX)
                return dec_bid_encode(new_sig, new_scale, neg);
        }
    }

    dec_i128 v = dec_to_i128(self);
    int neg = v < 0;

    uint64_t factor = (uint64_t)POW10[18 - ndigits];
    uint64_t half_factor = factor / 2;
    dec_u128 abs_v = neg ? -(dec_u128)v : (dec_u128)v;
    /* Schoolbook 128/64 using two native 64-bit divisions. */
    uint64_t v_hi = (uint64_t)(abs_v >> 64);
    uint64_t v_lo = (uint64_t)abs_v;
    uint64_t q_hi = v_hi / factor;
    uint64_t r_hi = v_hi - q_hi * factor;
    dec_u128 mid = ((dec_u128)r_hi << 64) | v_lo;
    uint64_t q_lo = (uint64_t)(mid / factor);
    dec_u128 q = ((dec_u128)q_hi << 64) | q_lo;
    uint64_t remainder = (uint64_t)(mid - (dec_u128)q_lo * factor);

    int round_up;
    if (remainder > half_factor)
        round_up = 1;
    else if (remainder < half_factor)
        round_up = 0;
    else /* exact half */
        round_up = (mode == RUBY_NUM_ROUND_HALF_UP) ||
                   (mode == RUBY_NUM_ROUND_HALF_EVEN && (q & 1));

    if (round_up) q++;

    dec_i128 result;
    if (__builtin_mul_overflow((dec_i128)q, factor, &result))
        rb_raise(rb_eRangeError, "Decimal overflow");
    if (neg) result = -result;

    if (ndigits == 0) return i128_to_ruby(result / DEC_SCALE);
    return dec_from_i128(result);
}

double
rb_decimal_to_f_value(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        double sig = (double)dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        double v = (scale == 0) ? sig : sig / (double)POW10[scale];
        return dec_bid_neg(self) ? -v : v;
    }
    return (double)RDECIMAL(self)->value / (double)DEC_SCALE;
}

/*
 *  call-seq:
 *    decimal.to_f  ->  float
 *
 *  Returns the value as a \Float.
 *
 *    2.5d.to_f       #=> 2.5
 *    Decimal(1).to_f  #=> 1.0
 *    (-0.75d).to_f    #=> -0.75
 */
VALUE
rb_decimal_to_f(VALUE self)
{
    return DBL2NUM(rb_decimal_to_f_value(self));
}

/*
 *  call-seq:
 *    decimal.to_i  ->  integer
 *
 *  Returns the truncated value as an \Integer.
 *
 *  Equivalent to Decimal#truncate.
 *
 *    2.9d.to_i    #=> 2
 *    (-2.9d).to_i  #=> -2
 *    300.6d.to_i   #=> 300
 */
static VALUE
decimal_to_i(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        int scale = dec_bid_scale(self);
        uint64_t sig = dec_bid_sig(self);
        uint64_t whole = (scale == 0) ? sig : sig / POW10[scale];
        if (dec_bid_neg(self))
            return LONG2NUM(-(long)whole);
        return LONG2NUM((long)whole);
    }
    return i128_to_ruby(RDECIMAL(self)->value / DEC_SCALE);
}

/*
 *  call-seq:
 *    decimal.to_r  ->  rational
 *
 *  Returns the value as an exact \Rational.
 *
 *    0.5d.to_r     #=> (1/2)
 *    1.0d.to_r     #=> (1/1)
 *    0.75d.to_r    #=> (3/4)
 */
static VALUE
decimal_to_r(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        VALUE num = LONG2NUM(dec_bid_neg(self) ? -(long)sig : (long)sig);
        VALUE den = rb_int2inum(POW10[scale]);
        return rb_rational_new(num, den);
    }
    VALUE num = i128_to_ruby(dec_to_i128(self));
    VALUE den = decimal_scale_val;
    return rb_rational_new(num, den);
}

/*
 *  call-seq:
 *    decimal.to_s  ->  string
 *
 *  Returns a string representation of +self+.
 *
 *    2.5d.to_s       #=> "2.5"
 *    42.0d.to_s      #=> "42.0"
 *    (-0.75d).to_s   #=> "-0.75"
 */
static VALUE
decimal_to_s(VALUE self)
{
    if (RB_DECIMAL_IMM_P(self)) {
        uint64_t sig = dec_bid_sig(self);
        int scale = dec_bid_scale(self);
        int neg = dec_bid_neg(self);
        char buf[32];
        char *p = buf;
        if (neg && sig != 0) *p++ = '-';
        if (scale == 0) {
            int len = snprintf(p, sizeof(buf) - (p - buf), "%llu.0",
                               (unsigned long long)sig);
            return rb_usascii_str_new(buf, (p - buf) + len);
        }
        uint64_t whole = sig / POW10[scale];
        uint64_t frac = sig - whole * POW10[scale];
        int wlen = snprintf(p, sizeof(buf) - (p - buf), "%llu.",
                            (unsigned long long)whole);
        p += wlen;
        char frac_buf[16];
        for (int i = scale - 1; i >= 0; i--) {
            frac_buf[i] = '0' + (int)(frac % 10);
            frac /= 10;
        }
        int frac_len = scale;
        while (frac_len > 1 && frac_buf[frac_len - 1] == '0')
            frac_len--;
        for (int i = 0; i < frac_len; i++)
            *p++ = frac_buf[i];
        return rb_usascii_str_new(buf, p - buf);
    }

    dec_i128 v = RDECIMAL(self)->value;
    int neg = v < 0;
    dec_u128 abs_val = neg ? -(dec_u128)v : (dec_u128)v;
    dec_u128 whole = abs_val / (dec_u128)DEC_SCALE;
    uint64_t frac = (uint64_t)(abs_val % (dec_u128)DEC_SCALE);

    char buf[64];
    char *p = buf;

    if (neg) *p++ = '-';

    if (whole == 0) {
        *p++ = '0';
    }
    else {
        char tmp[42];
        int i = 0;
        if (whole <= UINT64_MAX) {
            uint64_t w = (uint64_t)whole;
            while (w > 0) {
                tmp[i++] = '0' + (int)(w % 10);
                w /= 10;
            }
        }
        else {
            dec_u128 w = whole;
            while (w > 0) {
                tmp[i++] = '0' + (int)(w % 10);
                w /= 10;
            }
        }
        for (int j = i - 1; j >= 0; j--)
            *p++ = tmp[j];
    }

    *p++ = '.';

    if (frac == 0) {
        *p++ = '0';
    }
    else {
        char frac_buf[19];
        uint64_t f = frac;
        for (int i = 17; i >= 0; i--) {
            frac_buf[i] = '0' + (int)(f % 10);
            f /= 10;
        }
        int frac_len = 18;
        while (frac_len > 1 && frac_buf[frac_len - 1] == '0')
            frac_len--;
        for (int i = 0; i < frac_len; i++)
            *p++ = frac_buf[i];
    }

    return rb_usascii_str_new(buf, p - buf);
}

/*
 *  call-seq:
 *    decimal.inspect  ->  string
 *
 *  Returns the value as a string for inspection, with a +d+ suffix.
 *
 *    2.5d.inspect       #=> "2.5d"
 *    42.0d.inspect      #=> "42.0d"
 *    (-0.75d).inspect   #=> "-0.75d"
 */
static VALUE
decimal_inspect(VALUE self)
{
    VALUE s = decimal_to_s(self);
    rb_str_cat2(s, "d");
    return s;
}

/*
 *  call-seq:
 *    decimal.to_dec  ->  self
 *
 *  Returns +self+.
 *
 *    1.5d.to_dec   #=> 1.5d
 */
static VALUE
decimal_to_dec(VALUE self)
{
    return self;
}

/*
 *  call-seq:
 *    decimal.coerce(other)  ->  array
 *
 *  Returns a 2-element array <tt>[other_as_decimal, self]</tt> when +other+
 *  is an \Integer or \Rational, or <tt>[other, self_as_float]</tt> when
 *  +other+ is a \Float.
 *
 *    1.5d.coerce(2)      #=> [2.0d, 1.5d]
 *    1.5d.coerce(0.5)    #=> [0.5, 1.5]
 */
static VALUE
decimal_coerce(VALUE self, VALUE other)
{
    if (decimal_check(other)) {
        return rb_assoc_new(other, self);
    }
    if (RB_INTEGER_TYPE_P(other)) {
        return rb_assoc_new(rb_decimal_from_integer(other), self);
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
        return rb_assoc_new(dec_from_rational_scaled(other, TRUE), self);
    }
    else if (RB_FLOAT_TYPE_P(other)) {
        return rb_assoc_new(other, rb_decimal_to_f(self));
    }

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
             rb_obj_classname(other), rb_obj_classname(self));
    return Qnil;
}

static VALUE
decimal_parse(const char *str, long slen, int raise)
{
    const char *p = str;
    const char *end = str + slen;

    while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r'))
        p++;

    while (end > p && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\n' || end[-1] == '\r'))
        end--;

    if (p >= end) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for Decimal()");
    }

    int neg = 0;
    if (*p == '-') {
        neg = 1;
        p++;
    }
    else if (*p == '+') {
        p++;
    }

    if (p >= end) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for Decimal()");
    }

    const char *dot = memchr(p, '.', end - p);

    const char *whole_start = p;
    const char *whole_end = dot ? dot : end;

    if (whole_start >= whole_end && !dot) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for Decimal()");
    }

    dec_i128 whole = 0;
    for (const char *c = whole_start; c < whole_end; c++) {
        if (*c == '_') {
            if (c == whole_start || c + 1 >= whole_end ||
                !isdigit((unsigned char)c[-1]) || !isdigit((unsigned char)c[1])) {
                if (!raise) return Qnil;
                rb_raise(rb_eArgError, "invalid value for Decimal()");
            }
            continue;
        }
        if (!isdigit((unsigned char)*c)) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "invalid value for Decimal()");
        }
        dec_i128 next;
        if (__builtin_mul_overflow(whole, 10, &next) ||
            __builtin_add_overflow(next, *c - '0', &next)) {
            if (!raise) return Qnil;
            rb_raise(rb_eRangeError, "Decimal overflow");
        }
        whole = next;
    }

    dec_i128 frac = 0;
    int frac_digits = 0;
    if (dot) {
        const char *frac_start = dot + 1;

        if (whole_start >= whole_end && frac_start >= end) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "invalid value for Decimal()");
        }

        for (const char *c = frac_start; c < end; c++) {
            if (*c == '_') {
                if (c == frac_start || c + 1 >= end ||
                    !isdigit((unsigned char)c[-1]) || !isdigit((unsigned char)c[1])) {
                    if (!raise) return Qnil;
                    rb_raise(rb_eArgError, "invalid value for Decimal()");
                }
                continue;
            }
            if (!isdigit((unsigned char)*c)) {
                if (!raise) return Qnil;
                rb_raise(rb_eArgError, "invalid value for Decimal()");
            }
            if (frac_digits >= DEC_PRECISION) {
                if (*c != '0') {
                    if (!raise) return Qnil;
                    rb_raise(rb_eArgError, "precision exceeds 18 decimal places");
                }
                continue;
            }
            frac = frac * 10 + (*c - '0');
            frac_digits++;
        }
    }
    if (frac_digits < DEC_PRECISION)
        frac *= (dec_i128)POW10[DEC_PRECISION - frac_digits];

    dec_i128 raw;
    if (__builtin_mul_overflow(whole, DEC_SCALE, &raw)) {
        if (!raise) return Qnil;
        rb_raise(rb_eRangeError, "Decimal overflow");
    }
    if (__builtin_add_overflow(raw, frac, &raw)) {
        if (!raise) return Qnil;
        rb_raise(rb_eRangeError, "Decimal overflow");
    }
    if (neg) raw = -raw;

    if (frac == 0) {
        if (whole == 0) return decimal_zero;
        if (whole <= DEC_BID_SIG_MAX)
            return dec_bid_encode((uint64_t)whole, 0, neg);
    }
    else if ((whole >> 64) == 0 && (dec_u128)frac >> 64 == 0) {
        uint64_t frac64 = (uint64_t)frac;
        int frac_scale = DEC_PRECISION;
        if (frac64 != 0)
            frac64 = strip_tz(frac64, &frac_scale, DEC_PRECISION);
        int actual_frac_digits = frac_scale;
        if (actual_frac_digits <= 15) {
            dec_u128 sig = (dec_u128)(uint64_t)whole * POW10[actual_frac_digits] + frac64;
            if (sig <= DEC_BID_SIG_MAX)
                return dec_bid_encode((uint64_t)sig, actual_frac_digits, neg);
        }
    }
    return dec_from_i128(raw);
}

static VALUE
decimal_convert(VALUE klass, VALUE input, int raise)
{
    (void)klass;

    if (decimal_check(input))
        return input;

    if (RB_INTEGER_TYPE_P(input)) {
        if (!raise) {
            dec_i128 val, result;
            if (!ruby_int_to_i128_noexc(input, &val))
                return Qnil;
            if (__builtin_mul_overflow(val, DEC_SCALE, &result))
                return Qnil;
            return dec_from_i128(result);
        }
        return rb_decimal_from_integer(input);
    }

    if (RB_FLOAT_TYPE_P(input)) {
        double dbl = RFLOAT_VALUE(input);
        if (isnan(dbl) || isinf(dbl)) {
            if (!raise) return Qnil;
            rb_raise(rb_eArgError, "can't convert %s Float into Decimal",
                     isnan(dbl) ? "NaN" : "Infinity");
        }
        VALUE str = rb_funcall(input, idTo_s, 0);
        return decimal_parse_float_string(RSTRING_PTR(str), RSTRING_LEN(str), raise);
    }

    if (RB_TYPE_P(input, T_STRING)) {
        const char *s = RSTRING_PTR(input);
        long len = RSTRING_LEN(input);
        if (memchr(s, 'e', len) || memchr(s, 'E', len))
            return decimal_parse_float_string(s, len, raise);
        return decimal_parse(s, len, raise);
    }

    if (RB_TYPE_P(input, T_RATIONAL))
        return dec_from_rational_scaled(input, raise);

    if (RB_TYPE_P(input, T_COMPLEX)) {
        if (RTEST(rb_funcall(rb_complex_imag(input), idEq, 1, INT2FIX(0))))
            return decimal_convert(klass, rb_complex_real(input), raise);
        if (!raise) return Qnil;
        return dec_from_rational_scaled(rb_funcall(input, idTo_r, 0), raise);
    }

    if (rb_obj_is_kind_of(input, rb_cNumeric))
        return dec_from_rational_scaled(rb_funcall(input, idTo_r, 0), raise);

    if (!raise) return Qnil;
    rb_raise(rb_eTypeError, "can't convert %s into Decimal",
             rb_obj_classname(input));
    return Qnil;
}

/*
 *  call-seq:
 *    Decimal(arg, exception: true)  ->  decimal or nil
 *
 *  Returns +arg+ as a \Decimal.
 *
 *    Decimal(42)        #=> 42.0d
 *    Decimal("19.99")   #=> 19.99d
 *    Decimal(0.1)       #=> 0.1d
 *
 *    Decimal("bad", exception: false)  #=> nil
 *    Decimal("bad")                    # ArgumentError
 */
static VALUE
decimal_f_decimal(int argc, VALUE *argv, VALUE klass)
{
    VALUE input, opts = Qnil;
    int raise = TRUE;

    rb_scan_args(argc, argv, "1:", &input, &opts);
    if (!NIL_P(opts)) {
        raise = rb_opts_exception_p(opts, raise);
    }
    return decimal_convert(rb_cDecimal, input, raise);
}

/* :nodoc: */
static VALUE
decimal_marshal_dump(VALUE self)
{
    return i128_to_ruby(dec_to_i128(self));
}

/* :nodoc: */
static VALUE
decimal_marshal_load(VALUE self, VALUE raw)
{
    rb_check_frozen(self);
    rb_ivar_set(self, id_i_raw, raw);
    return self;
}

/* :nodoc: */
static VALUE
decimal_dumper(VALUE self)
{
    return self;
}

/* :nodoc: */
static VALUE
decimal_loader(VALUE self, VALUE a)
{
    VALUE raw = rb_ivar_get(a, id_i_raw);
    if (NIL_P(raw))
        raw = INT2FIX(0);
    dec_i128 val = ruby_int_to_i128(raw);
    RDECIMAL(self)->value = val;
    if (dec_integral_p(val))
        RBASIC(self)->flags |= DEC_FL_INTEGRAL;
    OBJ_FREEZE(self);
    return self;
}

VALUE
rb_Decimal(VALUE val)
{
    return decimal_convert(rb_cDecimal, val, TRUE);
}

VALUE
rb_decimal_from_str(VALUE str)
{
    const char *s = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    if (memchr(s, 'e', len) || memchr(s, 'E', len))
        return decimal_parse_float_string(s, len, TRUE);
    return decimal_parse(s, len, TRUE);
}

/*
 *  call-seq:
 *    to_dec -> decimal
 *
 *  Returns the value as a \Decimal.
 *
 *    42.to_dec   #=> 42.0d
 */
static VALUE
integer_to_dec(VALUE self)
{
    return rb_decimal_from_integer(self);
}

/*
 *  call-seq:
 *    to_dec -> decimal
 *
 *  Returns the value as a \Decimal.
 *
 *    0.5.to_dec   #=> 0.5d
 */
static VALUE
float_to_dec(VALUE self)
{
    return rb_Decimal(self);
}

/*
 *  call-seq:
 *    to_dec -> decimal
 *
 *  Returns the value as a \Decimal.
 *
 *    "19.99".to_dec   #=> 19.99d
 */
static VALUE
string_to_dec(VALUE self)
{
    const char *s = RSTRING_PTR(self);
    long len = RSTRING_LEN(self);
    if (memchr(s, 'e', len) || memchr(s, 'E', len))
        return decimal_parse_float_string(s, len, TRUE);
    return decimal_parse(s, len, TRUE);
}

/*
 *  A \Decimal object represents an exact base-10 number with
 *  18 decimal places of precision, stored as a 128-bit scaled integer.
 *
 *  Humans record measurements in base 10. When a recipe says 2.3 grams
 *  of salt or a GPS shows 26.2 miles, those values are exact in decimal.
 *  The problem with \Float isn't that it can't represent physical
 *  reality -- it's that it can't faithfully represent what a human
 *  wrote down.
 *
 *  You can create a \Decimal object explicitly with:
 *
 *  - A {decimal literal}[rdoc-ref:syntax/literals.rdoc@Decimal+Literals].
 *  - Method #Decimal.
 *
 *  You can convert certain objects to \Decimal with:
 *
 *  - Method Integer#to_dec, Float#to_dec, Rational#to_dec or String#to_dec.
 *
 *  Examples
 *
 *    1.5d              #=> 1.5d
 *    42d               #=> 42.0d
 *    Decimal(42)       #=> 42.0d
 *    Decimal("19.99")  #=> 19.99d
 *    Decimal(0.1)      #=> 0.1d
 *    42.to_dec         #=> 42.0d
 *
 *  \Decimal is an exact base-10 type, which means arithmetic on recorded
 *  values doesn't introduce error that wasn't in the data.
 *
 *    # Float accumulates binary rounding error:
 *    10.times.inject(0) {|t| t + 0.1 }             #=> 0.9999999999999999
 *
 *    # Decimal preserves the recorded values exactly:
 *    10.times.inject(0d) {|t| t + 0.1d }            #=> 1.0d
 *
 *  Comparisons work as expected without epsilon hacks:
 *
 *    0.1 + 0.2 == 0.3          #=> false (Float)
 *    0.1d + 0.2d == 0.3d       #=> true  (Decimal)
 *
 *  == When to Use \Decimal vs \Float
 *
 *  Use \Decimal when values originate as human-written base-10 numbers:
 *  prices, dosages, distances, weights, sensor readouts on a display.
 *  \Decimal preserves them faithfully -- no formatting tricks to
 *  display round-trip, no epsilon comparisons, no accumulated drift.
 *
 *  Use \Float when values originate from continuous mathematical
 *  functions (trigonometry, logarithms, square roots). Those results
 *  are irrational and inherently approximate no matter what
 *  representation you use.  \Float's dynamic range and hardware
 *  acceleration make it the right tool there.
 *
 *  When an expression mixes \Decimal with an inexact type, the result
 *  follows the inexact type (matching how \Rational behaves):
 *
 *    Decimal("19.99") + 1       #=> 20.99d  (Integer promotes to Decimal)
 *    Decimal("19.99") + 1.0     #=> 20.99   (Float wins, returns Float)
 *
 *  == Note on +0d+
 *
 *  The literal <tt>0d</tt> is Ruby's existing prefix for a decimal-base
 *  integer (like <tt>0x</tt> for hex or <tt>0b</tt> for binary), so it
 *  cannot also mean <tt>Decimal(0)</tt>.  Use <tt>0.0d</tt> or
 *  <tt>Decimal(0)</tt> for a zero \Decimal value.
 *
 *  == What's Here
 *
 *  First, what's elsewhere:
 *
 *  - Class \Decimal inherits from class
 *    {Numeric}[rdoc-ref:Numeric@Whats-Here].
 *  - Includes (indirectly) module
 *    {Comparable}[rdoc-ref:Comparable@Whats-Here].
 *
 *  Here, class \Decimal has methods for:
 *
 *  === Querying
 *
 *  - #zero?: Returns whether +self+ is zero.
 *  - #positive?: Returns whether +self+ is positive.
 *  - #negative?: Returns whether +self+ is negative.
 *  - #integer?: Returns whether +self+ has no fractional part.
 *  - #finite?: Returns +true+ (always finite).
 *  - #infinite?: Returns +nil+ (never infinite).
 *  - #hash: Returns the integer hash value for +self+.
 *  - #scaled_value: Returns the internal 128-bit value as an \Integer.
 *
 *  === Comparing
 *
 *  - #<=>: Returns whether +self+ is less than, equal to
 *    or greater than the given argument.
 *  - #==: Returns whether +self+ is equal to the given argument.
 *  - #eql?: Returns whether +self+ is equal to the given argument
 *    and both are \Decimal.
 *
 *  === Converting
 *
 *  - #to_f: Returns +self+ as a \Float.
 *  - #to_i: Returns +self+ truncated to an \Integer.
 *  - #to_r: Returns +self+ as an exact \Rational.
 *  - #to_dec: Returns +self+.
 *  - #to_s: Returns a string representation of +self+ (<tt>"42.42"</tt>).
 *  - #inspect: Returns a string with the +d+ suffix (<tt>"42.42d"</tt>).
 *
 *  === Rounding
 *
 *  - #ceil: Returns the smallest \Integer not less than +self+.
 *  - #floor: Returns the largest \Integer not greater than +self+.
 *  - #round: Returns +self+ rounded to the nearest value
 *    with the given precision.
 *  - #truncate: Returns +self+ truncated toward zero.
 *
 *  === Performing Arithmetic
 *
 *  - #+: Returns the sum of +self+ and the given numeric.
 *  - #-: Returns the difference of +self+ and the given numeric.
 *  - #*: Returns the product of +self+ and the given numeric.
 *  - #/: Returns the quotient of +self+ and the given numeric.
 *  - #**: Returns +self+ raised to the given \Integer power.
 *  - #-@: Returns the negation of +self+.
 *  - #abs: Returns the absolute value of +self+.
 *  - #quo: Returns the quotient of +self+ and the given numeric.
 *  - #div: Returns the integer quotient of +self+ and the given numeric.
 *  - #modulo (aliased as #%): Returns +self+ modulo the given numeric.
 *  - #divmod: Returns the quotient and modulus of +self+.
 *  - #remainder: Returns the remainder of +self+ divided by the given numeric.
 *  - #fdiv: Returns the \Float quotient of +self+ and the given numeric.
 *
 *  === Decomposing
 *
 *  - #fix: Returns the integer part of +self+ as a \Decimal.
 *  - #frac: Returns the fractional part of +self+ as a \Decimal.
 *  - #deconstruct: Returns <tt>[whole, frac]</tt> for pattern matching.
 *  - #deconstruct_keys: Returns <tt>{whole:, frac:}</tt> for pattern matching.
 *
 */

void
Init_Decimal(void)
{
    VALUE compat;

    id_ceil      = rb_intern_const("ceil");
    id_floor     = rb_intern_const("floor");
    id_remainder = rb_intern_const("remainder");
    id_round     = rb_intern_const("round");
    id_truncate  = rb_intern_const("truncate");
    id_i_raw     = rb_intern_const("@raw");

    rb_cDecimal = rb_define_class("Decimal", rb_cNumeric);

    rb_define_alloc_func(rb_cDecimal, decimal_s_alloc);

    decimal_zero = dec_bid_encode(0, 0, 0);

    decimal_scale_val = rb_int2inum(1000000000000000000LL);
    rb_gc_register_mark_object(decimal_scale_val);

    rb_define_global_function("Decimal", decimal_f_decimal, -1);

    rb_undef_method(CLASS_OF(rb_cDecimal), "new");
    rb_undef_method(CLASS_OF(rb_cDecimal), "allocate");
    rb_define_method(rb_cDecimal, "scaled_value", decimal_scaled_value, 0);
    rb_define_private_method(rb_singleton_class(rb_cDecimal), "from_integer",
                             decimal_s_from_integer, 1);

    rb_define_method(rb_cDecimal, "+", rb_decimal_plus, 1);
    rb_define_method(rb_cDecimal, "-", rb_decimal_minus, 1);
    rb_define_method(rb_cDecimal, "-@", decimal_uminus, 0);
    rb_define_method(rb_cDecimal, "*", rb_decimal_mul, 1);
    rb_define_method(rb_cDecimal, "/", rb_decimal_div, 1);
    rb_define_method(rb_cDecimal, "quo", rb_decimal_div, 1);
    rb_define_method(rb_cDecimal, "%", decimal_mod, 1);
    rb_define_method(rb_cDecimal, "modulo", decimal_mod, 1);
    rb_define_method(rb_cDecimal, "divmod", decimal_divmod, 1);
    rb_define_method(rb_cDecimal, "div", decimal_div_int, 1);
    rb_define_method(rb_cDecimal, "**", decimal_pow, 1);
    rb_define_method(rb_cDecimal, "fdiv", decimal_fdiv, 1);
    rb_define_method(rb_cDecimal, "remainder", decimal_remainder, 1);

    rb_define_method(rb_cDecimal, "<=>", decimal_cmp, 1);
    rb_define_method(rb_cDecimal, "<", decimal_lt, 1);
    rb_define_method(rb_cDecimal, "<=", decimal_le, 1);
    rb_define_method(rb_cDecimal, ">", decimal_gt, 1);
    rb_define_method(rb_cDecimal, ">=", decimal_ge, 1);
    rb_define_method(rb_cDecimal, "==", decimal_eq, 1);
    rb_define_method(rb_cDecimal, "===", decimal_eq, 1);
    rb_define_method(rb_cDecimal, "hash", decimal_hash, 0);
    rb_define_method(rb_cDecimal, "eql?", decimal_eql, 1);

    rb_define_method(rb_cDecimal, "integer?", decimal_integer_p, 0);
    rb_define_method(rb_cDecimal, "zero?", decimal_zero_p, 0);
    rb_define_method(rb_cDecimal, "positive?", decimal_positive_p, 0);
    rb_define_method(rb_cDecimal, "negative?", decimal_negative_p, 0);
    rb_define_method(rb_cDecimal, "finite?", decimal_finite_p, 0);
    rb_define_method(rb_cDecimal, "infinite?", decimal_infinite_p, 0);
    rb_define_method(rb_cDecimal, "abs", rb_decimal_abs, 0);

    rb_define_method(rb_cDecimal, "fix", decimal_fix, 0);
    rb_define_method(rb_cDecimal, "frac", decimal_frac, 0);

    rb_define_method(rb_cDecimal, "floor", decimal_floor, -1);
    rb_define_method(rb_cDecimal, "ceil", decimal_ceil, -1);
    rb_define_method(rb_cDecimal, "truncate", decimal_truncate, -1);
    rb_define_method(rb_cDecimal, "round", decimal_round, -1);

    rb_define_method(rb_cDecimal, "to_f", rb_decimal_to_f, 0);
    rb_define_method(rb_cDecimal, "to_i", decimal_to_i, 0);
    rb_define_method(rb_cDecimal, "to_r", decimal_to_r, 0);
    rb_define_method(rb_cDecimal, "to_s", decimal_to_s, 0);
    rb_define_method(rb_cDecimal, "inspect", decimal_inspect, 0);
    rb_define_method(rb_cDecimal, "to_dec", decimal_to_dec, 0);

    rb_define_method(rb_cDecimal, "coerce", decimal_coerce, 1);

    rb_define_method(rb_cInteger, "to_dec", integer_to_dec, 0);
    rb_define_method(rb_cFloat, "to_dec", float_to_dec, 0);
    rb_define_method(rb_cString, "to_dec", string_to_dec, 0);

    rb_define_private_method(rb_cDecimal, "marshal_dump", decimal_marshal_dump, 0);
    /* :nodoc: */
    compat = rb_define_class_under(rb_cDecimal, "compatible", rb_cObject);
    rb_define_private_method(compat, "marshal_load", decimal_marshal_load, 1);
    rb_marshal_define_compat(rb_cDecimal, compat, decimal_dumper, decimal_loader);

    rb_define_const(rb_cDecimal, "SCALE", rb_int2inum(1000000000000000000LL));
    rb_define_const(rb_cDecimal, "PRECISION", INT2FIX(DEC_PRECISION));
    rb_define_const(rb_cDecimal, "MAX", dec_from_i128(DEC_MAX));
    rb_define_const(rb_cDecimal, "MIN", dec_from_i128(DEC_MIN));

}

#include "decimal.rbinc"
