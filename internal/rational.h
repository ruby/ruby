/**                                                         \noop-*-C-*-vi:ft=c
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Rational.
 */
#ifndef INTERNAL_RATIONAL_H
#define INTERNAL_RATIONAL_H
#include "ruby/3/config.h"      /* for HAVE_LIBGMP */
#include "ruby/ruby.h"          /* for struct RBasic */
#include "internal/gc.h"        /* for RB_OBJ_WRITE */
#include "internal/numeric.h"   /* for INT_POSITIVE_P */
#include "ruby_assert.h"        /* for assert */

struct RRational {
    struct RBasic basic;
    VALUE num;
    VALUE den;
};

#define RRATIONAL(obj) (R_CAST(RRational)(obj))

/* rational.c */
VALUE rb_rational_canonicalize(VALUE x);
VALUE rb_rational_uminus(VALUE self);
VALUE rb_rational_plus(VALUE self, VALUE other);
VALUE rb_rational_mul(VALUE self, VALUE other);
VALUE rb_lcm(VALUE x, VALUE y);
VALUE rb_rational_reciprocal(VALUE x);
VALUE rb_cstr_to_rat(const char *, int);
VALUE rb_rational_abs(VALUE self);
VALUE rb_rational_cmp(VALUE self, VALUE other);
VALUE rb_rational_pow(VALUE self, VALUE other);
VALUE rb_numeric_quo(VALUE x, VALUE y);
VALUE rb_float_numerator(VALUE x);
VALUE rb_float_denominator(VALUE x);

static inline void RATIONAL_SET_NUM(VALUE r, VALUE n);
static inline void RATIONAL_SET_DEN(VALUE r, VALUE d);

RUBY_SYMBOL_EXPORT_BEGIN
/* rational.c (export) */
VALUE rb_gcd(VALUE x, VALUE y);
VALUE rb_gcd_normal(VALUE self, VALUE other);
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
VALUE rb_gcd_gmp(VALUE x, VALUE y);
#endif
RUBY_SYMBOL_EXPORT_END

static inline void
RATIONAL_SET_NUM(VALUE r, VALUE n)
{
    assert(RB_INTEGER_TYPE_P(n));
    RB_OBJ_WRITE(r, &RRATIONAL(r)->num, n);
}

static inline void
RATIONAL_SET_DEN(VALUE r, VALUE d)
{
    assert(RB_INTEGER_TYPE_P(d));
    assert(INT_POSITIVE_P(d));
    RB_OBJ_WRITE(r, &RRATIONAL(r)->den, d);
}

#endif /* INTERNAL_RATIONAL_H */
