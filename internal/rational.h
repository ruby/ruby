#ifndef INTERNAL_RATIONAL_H /* -*- C -*- */
#define INTERNAL_RATIONAL_H
/**
 * @file
 * @brief      Internal header for Rational.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/config.h"        /* for HAVE_LIBGMP */
#include "ruby/ruby.h"          /* for struct RBasic */

struct RRational {
    struct RBasic basic;
    VALUE num;
    VALUE den;
};

#define RRATIONAL(obj) (R_CAST(RRational)(obj))
#define RRATIONAL_SET_NUM(rat, n) RB_OBJ_WRITE((rat), &RRATIONAL(rat)->num, (n))
#define RRATIONAL_SET_DEN(rat, d) RB_OBJ_WRITE((rat), &RRATIONAL(rat)->den, (d))

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

RUBY_SYMBOL_EXPORT_BEGIN
/* rational.c (export) */
VALUE rb_gcd(VALUE x, VALUE y);
VALUE rb_gcd_normal(VALUE self, VALUE other);
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
VALUE rb_gcd_gmp(VALUE x, VALUE y);
#endif
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_RATIONAL_H */
