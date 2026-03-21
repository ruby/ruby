#ifndef INTERNAL_DECIMAL_H                              /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_DECIMAL_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met. Consult the file for details.
 * @brief      Internal header for Decimal.
 */
#include "ruby/ruby.h"          /* for struct RBasic */

/* Heap fallback for values > 15 significant digits. */
struct RDecimal {
    struct RBasic basic;
    int128_t __attribute__((aligned(8))) value;
};

#define DEC_SCALE       ((int128_t)1000000000000000000LL)
#define DEC_FL_INTEGRAL RUBY_FL_USER1

#define RDECIMAL(obj) ((struct RDecimal *)(obj))

/* BID (Binary Integer Decimal) immediate encoding.
 *
 * Tag byte 0x84: (val & 0xFF) == 0x84, collision-free with all
 * existing Ruby special constants (Fixnum, Flonum, Symbol, nil,
 * true, false, undef).
 *
 * Layout (64-bit VALUE):
 *   bit 63      = sign (0=positive, 1=negative)
 *   bits 62:12  = significand (51 bits, unsigned, max ~2.25 * 10^15)
 *   bits 11:8   = scale (4 bits, 0..15 decimal places)
 *   bits 7:0    = 0x84 (tag)
 */
#define DEC_BID_TAG      0x84
#define DEC_BID_SIG_MAX  ((uint64_t)((1ULL << 51) - 1))

static inline VALUE
dec_bid_encode(uint64_t sig, int scale, int neg)
{
    return (VALUE)(((uint64_t)neg << 63) | (sig << 12) |
                   ((uint64_t)scale << 8) | DEC_BID_TAG);
}

static inline uint64_t
dec_bid_sig(VALUE v)
{
    return (v >> 12) & DEC_BID_SIG_MAX;
}

static inline int
dec_bid_scale(VALUE v)
{
    return (int)((v >> 8) & 0xF);
}

static inline int
dec_bid_neg(VALUE v)
{
    return (int)(v >> 63);
}

static inline int
decimal_p(VALUE v)
{
    return RB_DECIMAL_IMM_P(v) || RB_TYPE_P(v, T_DECIMAL);
}

VALUE rb_decimal_plus(VALUE x, VALUE y);
VALUE rb_decimal_minus(VALUE x, VALUE y);
VALUE rb_decimal_mul(VALUE x, VALUE y);
VALUE rb_decimal_div(VALUE x, VALUE y);
VALUE rb_decimal_plus_dd(VALUE x, VALUE y);
VALUE rb_decimal_minus_dd(VALUE x, VALUE y);
VALUE rb_decimal_mul_dd(VALUE x, VALUE y);
VALUE rb_decimal_div_dd(VALUE x, VALUE y);
VALUE rb_decimal_cmp_dd(VALUE x, VALUE y);
VALUE rb_decimal_mod_dd(VALUE x, VALUE y);
VALUE rb_decimal_uminus_dd(VALUE x);
VALUE rb_decimal_abs(VALUE self);
VALUE rb_decimal_to_f(VALUE self);
VALUE rb_decimal_from_integer(VALUE val);
double rb_decimal_to_f_value(VALUE self);

#endif /* INTERNAL_DECIMAL_H */
