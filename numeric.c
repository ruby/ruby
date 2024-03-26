/**********************************************************************

  numeric.c -

  $Author$
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <assert.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>

#ifdef HAVE_FLOAT_H
#include <float.h>
#endif

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/compilers.h"
#include "internal/complex.h"
#include "internal/enumerator.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/rational.h"
#include "internal/string.h"
#include "internal/util.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "builtin.h"

/* use IEEE 64bit values if not defined */
#ifndef FLT_RADIX
#define FLT_RADIX 2
#endif
#ifndef DBL_MIN
#define DBL_MIN 2.2250738585072014e-308
#endif
#ifndef DBL_MAX
#define DBL_MAX 1.7976931348623157e+308
#endif
#ifndef DBL_MIN_EXP
#define DBL_MIN_EXP (-1021)
#endif
#ifndef DBL_MAX_EXP
#define DBL_MAX_EXP 1024
#endif
#ifndef DBL_MIN_10_EXP
#define DBL_MIN_10_EXP (-307)
#endif
#ifndef DBL_MAX_10_EXP
#define DBL_MAX_10_EXP 308
#endif
#ifndef DBL_DIG
#define DBL_DIG 15
#endif
#ifndef DBL_MANT_DIG
#define DBL_MANT_DIG 53
#endif
#ifndef DBL_EPSILON
#define DBL_EPSILON 2.2204460492503131e-16
#endif

#ifndef USE_RB_INFINITY
#elif !defined(WORDS_BIGENDIAN) /* BYTE_ORDER == LITTLE_ENDIAN */
const union bytesequence4_or_float rb_infinity = {{0x00, 0x00, 0x80, 0x7f}};
#else
const union bytesequence4_or_float rb_infinity = {{0x7f, 0x80, 0x00, 0x00}};
#endif

#ifndef USE_RB_NAN
#elif !defined(WORDS_BIGENDIAN) /* BYTE_ORDER == LITTLE_ENDIAN */
const union bytesequence4_or_float rb_nan = {{0x00, 0x00, 0xc0, 0x7f}};
#else
const union bytesequence4_or_float rb_nan = {{0x7f, 0xc0, 0x00, 0x00}};
#endif

#ifndef HAVE_ROUND
double
round(double x)
{
    double f;

    if (x > 0.0) {
        f = floor(x);
        x = f + (x - f >= 0.5);
    }
    else if (x < 0.0) {
        f = ceil(x);
        x = f - (f - x >= 0.5);
    }
    return x;
}
#endif

static double
round_half_up(double x, double s)
{
    double f, xs = x * s;

    f = round(xs);
    if (s == 1.0) return f;
    if (x > 0) {
        if ((double)((f + 0.5) / s) <= x) f += 1;
        x = f;
    }
    else {
        if ((double)((f - 0.5) / s) >= x) f -= 1;
        x = f;
    }
    return x;
}

static double
round_half_down(double x, double s)
{
    double f, xs = x * s;

    f = round(xs);
    if (x > 0) {
        if ((double)((f - 0.5) / s) >= x) f -= 1;
        x = f;
    }
    else {
        if ((double)((f + 0.5) / s) <= x) f += 1;
        x = f;
    }
    return x;
}

static double
round_half_even(double x, double s)
{
    double u, v, us, vs, f, d, uf;

    v = modf(x, &u);
    us = u * s;
    vs = v * s;

    if (x > 0.0) {
        f = floor(vs);
        uf = us + f;
        d = vs - f;
        if (d > 0.5)
            d = 1.0;
        else if (d == 0.5 || ((double)((uf + 0.5) / s) <= x))
            d = fmod(uf, 2.0);
        else
            d = 0.0;
        x = f + d;
    }
    else if (x < 0.0) {
        f = ceil(vs);
        uf = us + f;
        d = f - vs;
        if (d > 0.5)
            d = 1.0;
        else if (d == 0.5 || ((double)((uf - 0.5) / s) >= x))
            d = fmod(-uf, 2.0);
        else
            d = 0.0;
        x = f - d;
    }
    return us + x;
}

static VALUE fix_lshift(long, unsigned long);
static VALUE fix_rshift(long, unsigned long);
static VALUE int_pow(long x, unsigned long y);
static VALUE rb_int_floor(VALUE num, int ndigits);
static VALUE rb_int_ceil(VALUE num, int ndigits);
static VALUE flo_to_i(VALUE num);
static int float_round_overflow(int ndigits, int binexp);
static int float_round_underflow(int ndigits, int binexp);

static ID id_coerce;
#define id_div idDiv
#define id_divmod idDivmod
#define id_to_i idTo_i
#define id_eq  idEq
#define id_cmp idCmp

VALUE rb_cNumeric;
VALUE rb_cFloat;
VALUE rb_cInteger;

VALUE rb_eZeroDivError;
VALUE rb_eFloatDomainError;

static ID id_to, id_by;

void
rb_num_zerodiv(void)
{
    rb_raise(rb_eZeroDivError, "divided by 0");
}

enum ruby_num_rounding_mode
rb_num_get_rounding_option(VALUE opts)
{
    static ID round_kwds[1];
    VALUE rounding;
    VALUE str;
    const char *s;

    if (!NIL_P(opts)) {
        if (!round_kwds[0]) {
            round_kwds[0] = rb_intern_const("half");
        }
        if (!rb_get_kwargs(opts, round_kwds, 0, 1, &rounding)) goto noopt;
        if (SYMBOL_P(rounding)) {
            str = rb_sym2str(rounding);
        }
        else if (NIL_P(rounding)) {
            goto noopt;
        }
        else if (!RB_TYPE_P(str = rounding, T_STRING)) {
            str = rb_check_string_type(rounding);
            if (NIL_P(str)) goto invalid;
        }
        rb_must_asciicompat(str);
        s = RSTRING_PTR(str);
        switch (RSTRING_LEN(str)) {
          case 2:
            if (rb_memcicmp(s, "up", 2) == 0)
                return RUBY_NUM_ROUND_HALF_UP;
            break;
          case 4:
            if (rb_memcicmp(s, "even", 4) == 0)
                return RUBY_NUM_ROUND_HALF_EVEN;
            if (strncasecmp(s, "down", 4) == 0)
                return RUBY_NUM_ROUND_HALF_DOWN;
            break;
        }
      invalid:
        rb_raise(rb_eArgError, "invalid rounding mode: % "PRIsVALUE, rounding);
    }
  noopt:
    return RUBY_NUM_ROUND_DEFAULT;
}

/* experimental API */
int
rb_num_to_uint(VALUE val, unsigned int *ret)
{
#define NUMERR_TYPE     1
#define NUMERR_NEGATIVE 2
#define NUMERR_TOOLARGE 3
    if (FIXNUM_P(val)) {
        long v = FIX2LONG(val);
#if SIZEOF_INT < SIZEOF_LONG
        if (v > (long)UINT_MAX) return NUMERR_TOOLARGE;
#endif
        if (v < 0) return NUMERR_NEGATIVE;
        *ret = (unsigned int)v;
        return 0;
    }

    if (RB_BIGNUM_TYPE_P(val)) {
        if (BIGNUM_NEGATIVE_P(val)) return NUMERR_NEGATIVE;
#if SIZEOF_INT < SIZEOF_LONG
        /* long is 64bit */
        return NUMERR_TOOLARGE;
#else
        /* long is 32bit */
        if (rb_absint_size(val, NULL) > sizeof(int)) return NUMERR_TOOLARGE;
        *ret = (unsigned int)rb_big2ulong((VALUE)val);
        return 0;
#endif
    }
    return NUMERR_TYPE;
}

#define method_basic_p(klass) rb_method_basic_definition_p(klass, mid)

static inline int
int_pos_p(VALUE num)
{
    if (FIXNUM_P(num)) {
        return FIXNUM_POSITIVE_P(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return BIGNUM_POSITIVE_P(num);
    }
    rb_raise(rb_eTypeError, "not an Integer");
}

static inline int
int_neg_p(VALUE num)
{
    if (FIXNUM_P(num)) {
        return FIXNUM_NEGATIVE_P(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return BIGNUM_NEGATIVE_P(num);
    }
    rb_raise(rb_eTypeError, "not an Integer");
}

int
rb_int_positive_p(VALUE num)
{
    return int_pos_p(num);
}

int
rb_int_negative_p(VALUE num)
{
    return int_neg_p(num);
}

int
rb_num_negative_p(VALUE num)
{
    return rb_num_negative_int_p(num);
}

static VALUE
num_funcall_op_0(VALUE x, VALUE arg, int recursive)
{
    ID func = (ID)arg;
    if (recursive) {
        const char *name = rb_id2name(func);
        if (ISALNUM(name[0])) {
            rb_name_error(func, "%"PRIsVALUE".%"PRIsVALUE,
                          x, ID2SYM(func));
        }
        else if (name[0] && name[1] == '@' && !name[2]) {
            rb_name_error(func, "%c%"PRIsVALUE,
                          name[0], x);
        }
        else {
            rb_name_error(func, "%"PRIsVALUE"%"PRIsVALUE,
                          ID2SYM(func), x);
        }
    }
    return rb_funcallv(x, func, 0, 0);
}

static VALUE
num_funcall0(VALUE x, ID func)
{
    return rb_exec_recursive(num_funcall_op_0, x, (VALUE)func);
}

NORETURN(static void num_funcall_op_1_recursion(VALUE x, ID func, VALUE y));

static void
num_funcall_op_1_recursion(VALUE x, ID func, VALUE y)
{
    const char *name = rb_id2name(func);
    if (ISALNUM(name[0])) {
        rb_name_error(func, "%"PRIsVALUE".%"PRIsVALUE"(%"PRIsVALUE")",
                      x, ID2SYM(func), y);
    }
    else {
        rb_name_error(func, "%"PRIsVALUE"%"PRIsVALUE"%"PRIsVALUE,
                      x, ID2SYM(func), y);
    }
}

static VALUE
num_funcall_op_1(VALUE y, VALUE arg, int recursive)
{
    ID func = (ID)((VALUE *)arg)[0];
    VALUE x = ((VALUE *)arg)[1];
    if (recursive) {
        num_funcall_op_1_recursion(x, func, y);
    }
    return rb_funcall(x, func, 1, y);
}

static VALUE
num_funcall1(VALUE x, ID func, VALUE y)
{
    VALUE args[2];
    args[0] = (VALUE)func;
    args[1] = x;
    return rb_exec_recursive_paired(num_funcall_op_1, y, x, (VALUE)args);
}

/*
 *  call-seq:
 *    coerce(other) -> array
 *
 *  Returns a 2-element array containing two numeric elements,
 *  formed from the two operands +self+ and +other+,
 *  of a common compatible type.
 *
 *  Of the Core and Standard Library classes,
 *  Integer, Rational, and Complex use this implementation.
 *
 *  Examples:
 *
 *    i = 2                    # => 2
 *    i.coerce(3)              # => [3, 2]
 *    i.coerce(3.0)            # => [3.0, 2.0]
 *    i.coerce(Rational(1, 2)) # => [0.5, 2.0]
 *    i.coerce(Complex(3, 4))  # Raises RangeError.
 *
 *    r = Rational(5, 2)       # => (5/2)
 *    r.coerce(2)              # => [(2/1), (5/2)]
 *    r.coerce(2.0)            # => [2.0, 2.5]
 *    r.coerce(Rational(2, 3)) # => [(2/3), (5/2)]
 *    r.coerce(Complex(3, 4))  # => [(3+4i), ((5/2)+0i)]
 *
 *    c = Complex(2, 3)        # => (2+3i)
 *    c.coerce(2)              # => [(2+0i), (2+3i)]
 *    c.coerce(2.0)            # => [(2.0+0i), (2+3i)]
 *    c.coerce(Rational(1, 2)) # => [((1/2)+0i), (2+3i)]
 *    c.coerce(Complex(3, 4))  # => [(3+4i), (2+3i)]
 *
 *  Raises an exception if any type conversion fails.
 *
 */

static VALUE
num_coerce(VALUE x, VALUE y)
{
    if (CLASS_OF(x) == CLASS_OF(y))
        return rb_assoc_new(y, x);
    x = rb_Float(x);
    y = rb_Float(y);
    return rb_assoc_new(y, x);
}

NORETURN(static void coerce_failed(VALUE x, VALUE y));
static void
coerce_failed(VALUE x, VALUE y)
{
    if (SPECIAL_CONST_P(y) || SYMBOL_P(y) || RB_FLOAT_TYPE_P(y)) {
        y = rb_inspect(y);
    }
    else {
        y = rb_obj_class(y);
    }
    rb_raise(rb_eTypeError, "%"PRIsVALUE" can't be coerced into %"PRIsVALUE,
             y, rb_obj_class(x));
}

static int
do_coerce(VALUE *x, VALUE *y, int err)
{
    VALUE ary = rb_check_funcall(*y, id_coerce, 1, x);
    if (UNDEF_P(ary)) {
        if (err) {
            coerce_failed(*x, *y);
        }
        return FALSE;
    }
    if (!err && NIL_P(ary)) {
        return FALSE;
    }
    if (!RB_TYPE_P(ary, T_ARRAY) || RARRAY_LEN(ary) != 2) {
        rb_raise(rb_eTypeError, "coerce must return [x, y]");
    }

    *x = RARRAY_AREF(ary, 0);
    *y = RARRAY_AREF(ary, 1);
    return TRUE;
}

VALUE
rb_num_coerce_bin(VALUE x, VALUE y, ID func)
{
    do_coerce(&x, &y, TRUE);
    return rb_funcall(x, func, 1, y);
}

VALUE
rb_num_coerce_cmp(VALUE x, VALUE y, ID func)
{
    if (do_coerce(&x, &y, FALSE))
        return rb_funcall(x, func, 1, y);
    return Qnil;
}

static VALUE
ensure_cmp(VALUE c, VALUE x, VALUE y)
{
    if (NIL_P(c)) rb_cmperr(x, y);
    return c;
}

VALUE
rb_num_coerce_relop(VALUE x, VALUE y, ID func)
{
    VALUE x0 = x, y0 = y;

    if (!do_coerce(&x, &y, FALSE)) {
        rb_cmperr(x0, y0);
        UNREACHABLE_RETURN(Qnil);
    }
    return ensure_cmp(rb_funcall(x, func, 1, y), x0, y0);
}

NORETURN(static VALUE num_sadded(VALUE x, VALUE name));

/*
 * :nodoc:
 *
 * Trap attempts to add methods to Numeric objects. Always raises a TypeError.
 *
 * Numerics should be values; singleton_methods should not be added to them.
 */

static VALUE
num_sadded(VALUE x, VALUE name)
{
    ID mid = rb_to_id(name);
    /* ruby_frame = ruby_frame->prev; */ /* pop frame for "singleton_method_added" */
    rb_remove_method_id(rb_singleton_class(x), mid);
    rb_raise(rb_eTypeError,
             "can't define singleton method \"%"PRIsVALUE"\" for %"PRIsVALUE,
             rb_id2str(mid),
             rb_obj_class(x));

    UNREACHABLE_RETURN(Qnil);
}

#if 0
/*
 *  call-seq:
 *    clone(freeze: true) -> self
 *
 *  Returns +self+.
 *
 *  Raises an exception if the value for +freeze+ is neither +true+ nor +nil+.
 *
 *  Related: Numeric#dup.
 *
 */
static VALUE
num_clone(int argc, VALUE *argv, VALUE x)
{
    return rb_immutable_obj_clone(argc, argv, x);
}
#else
# define num_clone rb_immutable_obj_clone
#endif

#if 0
/*
 *  call-seq:
 *    dup -> self
 *
 *  Returns +self+.
 *
 *  Related: Numeric#clone.
 *
 */
static VALUE
num_dup(VALUE x)
{
    return x;
}
#else
# define num_dup num_uplus
#endif

/*
 *  call-seq:
 *    +self -> self
 *
 *  Returns +self+.
 *
 */

static VALUE
num_uplus(VALUE num)
{
    return num;
}

/*
 *  call-seq:
 *    i -> complex
 *
 *  Returns <tt>Complex(0, self)</tt>:
 *
 *    2.i              # => (0+2i)
 *    -2.i             # => (0-2i)
 *    2.0.i            # => (0+2.0i)
 *    Rational(1, 2).i # => (0+(1/2)*i)
 *    Complex(3, 4).i  # Raises NoMethodError.
 *
 */

static VALUE
num_imaginary(VALUE num)
{
    return rb_complex_new(INT2FIX(0), num);
}

/*
 *  call-seq:
 *    -self -> numeric
 *
 *  Unary Minus---Returns the receiver, negated.
 */

static VALUE
num_uminus(VALUE num)
{
    VALUE zero;

    zero = INT2FIX(0);
    do_coerce(&zero, &num, TRUE);

    return num_funcall1(zero, '-', num);
}

/*
 *  call-seq:
 *    fdiv(other) -> float
 *
 *  Returns the quotient <tt>self/other</tt> as a float,
 *  using method +/+ in the derived class of +self+.
 *  (\Numeric itself does not define method +/+.)
 *
 *  Of the Core and Standard Library classes,
 *  only BigDecimal uses this implementation.
 *
 */

static VALUE
num_fdiv(VALUE x, VALUE y)
{
    return rb_funcall(rb_Float(x), '/', 1, y);
}

/*
 *  call-seq:
 *    div(other) -> integer
 *
 *  Returns the quotient <tt>self/other</tt> as an integer (via +floor+),
 *  using method +/+ in the derived class of +self+.
 *  (\Numeric itself does not define method +/+.)
 *
 *  Of the Core and Standard Library classes,
 *  Only Float and Rational use this implementation.
 *
 */

static VALUE
num_div(VALUE x, VALUE y)
{
    if (rb_equal(INT2FIX(0), y)) rb_num_zerodiv();
    return rb_funcall(num_funcall1(x, '/', y), rb_intern("floor"), 0);
}

/*
 *  call-seq:
 *    self % other -> real_numeric
 *
 *  Returns +self+ modulo +other+ as a real number.
 *
 *  Of the Core and Standard Library classes,
 *  only Rational uses this implementation.
 *
 *  For Rational +r+ and real number +n+, these expressions are equivalent:
 *
 *    r % n
 *    r-n*(r/n).floor
 *    r.divmod(n)[1]
 *
 *  See Numeric#divmod.
 *
 *  Examples:
 *
 *    r = Rational(1, 2)    # => (1/2)
 *    r2 = Rational(2, 3)   # => (2/3)
 *    r % r2                # => (1/2)
 *    r % 2                 # => (1/2)
 *    r % 2.0               # => 0.5
 *
 *    r = Rational(301,100) # => (301/100)
 *    r2 = Rational(7,5)    # => (7/5)
 *    r % r2                # => (21/100)
 *    r % -r2               # => (-119/100)
 *    (-r) % r2             # => (119/100)
 *    (-r) %-r2             # => (-21/100)
 *
 */

static VALUE
num_modulo(VALUE x, VALUE y)
{
    VALUE q = num_funcall1(x, id_div, y);
    return rb_funcall(x, '-', 1,
                      rb_funcall(y, '*', 1, q));
}

/*
 *  call-seq:
 *    remainder(other) -> real_number
 *
 *  Returns the remainder after dividing +self+ by +other+.
 *
 *  Of the Core and Standard Library classes,
 *  only Float and Rational use this implementation.
 *
 *  Examples:
 *
 *    11.0.remainder(4)              # => 3.0
 *    11.0.remainder(-4)             # => 3.0
 *    -11.0.remainder(4)             # => -3.0
 *    -11.0.remainder(-4)            # => -3.0
 *
 *    12.0.remainder(4)              # => 0.0
 *    12.0.remainder(-4)             # => 0.0
 *    -12.0.remainder(4)             # => -0.0
 *    -12.0.remainder(-4)            # => -0.0
 *
 *    13.0.remainder(4.0)            # => 1.0
 *    13.0.remainder(Rational(4, 1)) # => 1.0
 *
 *    Rational(13, 1).remainder(4)   # => (1/1)
 *    Rational(13, 1).remainder(-4)  # => (1/1)
 *    Rational(-13, 1).remainder(4)  # => (-1/1)
 *    Rational(-13, 1).remainder(-4) # => (-1/1)
 *
 */

static VALUE
num_remainder(VALUE x, VALUE y)
{
    if (!rb_obj_is_kind_of(y, rb_cNumeric)) {
        do_coerce(&x, &y, TRUE);
    }
    VALUE z = num_funcall1(x, '%', y);

    if ((!rb_equal(z, INT2FIX(0))) &&
        ((rb_num_negative_int_p(x) &&
          rb_num_positive_int_p(y)) ||
         (rb_num_positive_int_p(x) &&
          rb_num_negative_int_p(y)))) {
        if (RB_FLOAT_TYPE_P(y)) {
            if (isinf(RFLOAT_VALUE(y))) {
                return x;
            }
        }
        return rb_funcall(z, '-', 1, y);
    }
    return z;
}

/*
 *  call-seq:
 *    divmod(other) -> array
 *
 *  Returns a 2-element array <tt>[q, r]</tt>, where
 *
 *    q = (self/other).floor                  # Quotient
 *    r = self % other                        # Remainder
 *
 *  Of the Core and Standard Library classes,
 *  only Rational uses this implementation.
 *
 *  Examples:
 *
 *    Rational(11, 1).divmod(4)               # => [2, (3/1)]
 *    Rational(11, 1).divmod(-4)              # => [-3, (-1/1)]
 *    Rational(-11, 1).divmod(4)              # => [-3, (1/1)]
 *    Rational(-11, 1).divmod(-4)             # => [2, (-3/1)]
 *
 *    Rational(12, 1).divmod(4)               # => [3, (0/1)]
 *    Rational(12, 1).divmod(-4)              # => [-3, (0/1)]
 *    Rational(-12, 1).divmod(4)              # => [-3, (0/1)]
 *    Rational(-12, 1).divmod(-4)             # => [3, (0/1)]
 *
 *    Rational(13, 1).divmod(4.0)             # => [3, 1.0]
 *    Rational(13, 1).divmod(Rational(4, 11)) # => [35, (3/11)]
 */

static VALUE
num_divmod(VALUE x, VALUE y)
{
    return rb_assoc_new(num_div(x, y), num_modulo(x, y));
}

/*
 *  call-seq:
 *    abs -> numeric
 *
 *  Returns the absolute value of +self+.
 *
 *    12.abs        #=> 12
 *    (-34.56).abs  #=> 34.56
 *    -34.56.abs    #=> 34.56
 *
 */

static VALUE
num_abs(VALUE num)
{
    if (rb_num_negative_int_p(num)) {
        return num_funcall0(num, idUMinus);
    }
    return num;
}

/*
 *  call-seq:
 *    zero? -> true or false
 *
 *  Returns +true+ if +zero+ has a zero value, +false+ otherwise.
 *
 *  Of the Core and Standard Library classes,
 *  only Rational and Complex use this implementation.
 *
 */

static VALUE
num_zero_p(VALUE num)
{
    return rb_equal(num, INT2FIX(0));
}

static bool
int_zero_p(VALUE num)
{
    if (FIXNUM_P(num)) {
        return FIXNUM_ZERO_P(num);
    }
    RUBY_ASSERT(RB_BIGNUM_TYPE_P(num));
    return rb_bigzero_p(num);
}

VALUE
rb_int_zero_p(VALUE num)
{
    return RBOOL(int_zero_p(num));
}

/*
 *  call-seq:
 *    nonzero?  ->  self or nil
 *
 *  Returns +self+ if +self+ is not a zero value, +nil+ otherwise;
 *  uses method <tt>zero?</tt> for the evaluation.
 *
 *  The returned +self+ allows the method to be chained:
 *
 *    a = %w[z Bb bB bb BB a aA Aa AA A]
 *    a.sort {|a, b| (a.downcase <=> b.downcase).nonzero? || a <=> b }
 *    # => ["A", "a", "AA", "Aa", "aA", "BB", "Bb", "bB", "bb", "z"]
 *
 *  Of the Core and Standard Library classes,
 *  Integer, Float, Rational, and Complex use this implementation.
 *
 */

static VALUE
num_nonzero_p(VALUE num)
{
    if (RTEST(num_funcall0(num, rb_intern("zero?")))) {
        return Qnil;
    }
    return num;
}

/*
 *  call-seq:
 *    to_int -> integer
 *
 *  Returns +self+ as an integer;
 *  converts using method +to_i+ in the derived class.
 *
 *  Of the Core and Standard Library classes,
 *  only Rational and Complex use this implementation.
 *
 *  Examples:
 *
 *    Rational(1, 2).to_int # => 0
 *    Rational(2, 1).to_int # => 2
 *    Complex(2, 0).to_int  # => 2
 *    Complex(2, 1)         # Raises RangeError (non-zero imaginary part)
 *
 */

static VALUE
num_to_int(VALUE num)
{
    return num_funcall0(num, id_to_i);
}

/*
 *  call-seq:
 *    positive? -> true or false
 *
 *  Returns +true+ if +self+ is greater than 0, +false+ otherwise.
 *
 */

static VALUE
num_positive_p(VALUE num)
{
    const ID mid = '>';

    if (FIXNUM_P(num)) {
        if (method_basic_p(rb_cInteger))
            return RBOOL((SIGNED_VALUE)num > (SIGNED_VALUE)INT2FIX(0));
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        if (method_basic_p(rb_cInteger))
            return RBOOL(BIGNUM_POSITIVE_P(num) && !rb_bigzero_p(num));
    }
    return rb_num_compare_with_zero(num, mid);
}

/*
 *  call-seq:
 *    negative? -> true or false
 *
 *  Returns +true+ if +self+ is less than 0, +false+ otherwise.
 *
 */

static VALUE
num_negative_p(VALUE num)
{
    return RBOOL(rb_num_negative_int_p(num));
}


/********************************************************************
 *
 *  Document-class: Float
 *
 *  A \Float object represents a sometimes-inexact real number using the native
 *  architecture's double-precision floating point representation.
 *
 *  Floating point has a different arithmetic and is an inexact number.
 *  So you should know its esoteric system. See following:
 *
 *  - https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html
 *  - https://github.com/rdp/ruby_tutorials_core/wiki/Ruby-Talk-FAQ#-why-are-rubys-floats-imprecise
 *  - https://en.wikipedia.org/wiki/Floating_point#Accuracy_problems
 *
 *  You can create a \Float object explicitly with:
 *
 *  - A {floating-point literal}[rdoc-ref:syntax/literals.rdoc@Float+Literals].
 *
 *  You can convert certain objects to Floats with:
 *
 *  - \Method #Float.
 *
 *  == What's Here
 *
 *  First, what's elsewhere. \Class \Float:
 *
 *  - Inherits from
 *    {class Numeric}[rdoc-ref:Numeric@What-27s+Here]
 *    and {class Object}[rdoc-ref:Object@What-27s+Here].
 *  - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
 *
 *  Here, class \Float provides methods for:
 *
 *  - {Querying}[rdoc-ref:Float@Querying]
 *  - {Comparing}[rdoc-ref:Float@Comparing]
 *  - {Converting}[rdoc-ref:Float@Converting]
 *
 *  === Querying
 *
 *  - #finite?: Returns whether +self+ is finite.
 *  - #hash: Returns the integer hash code for +self+.
 *  - #infinite?: Returns whether +self+ is infinite.
 *  - #nan?: Returns whether +self+ is a NaN (not-a-number).
 *
 *  === Comparing
 *
 *  - #<: Returns whether +self+ is less than the given value.
 *  - #<=: Returns whether +self+ is less than or equal to the given value.
 *  - #<=>: Returns a number indicating whether +self+ is less than, equal
 *    to, or greater than the given value.
 *  - #== (aliased as #=== and #eql?): Returns whether +self+ is equal to
 *    the given value.
 *  - #>: Returns whether +self+ is greater than the given value.
 *  - #>=: Returns whether +self+ is greater than or equal to the given value.
 *
 *  === Converting
 *
 *  - #% (aliased as #modulo): Returns +self+ modulo the given value.
 *  - #*: Returns the product of +self+ and the given value.
 *  - #**: Returns the value of +self+ raised to the power of the given value.
 *  - #+: Returns the sum of +self+ and the given value.
 *  - #-: Returns the difference of +self+ and the given value.
 *  - #/: Returns the quotient of +self+ and the given value.
 *  - #ceil: Returns the smallest number greater than or equal to +self+.
 *  - #coerce: Returns a 2-element array containing the given value converted to a \Float
 *    and +self+
 *  - #divmod: Returns a 2-element array containing the quotient and remainder
 *    results of dividing +self+ by the given value.
 *  - #fdiv: Returns the \Float result of dividing +self+ by the given value.
 *  - #floor: Returns the greatest number smaller than or equal to +self+.
 *  - #next_float: Returns the next-larger representable \Float.
 *  - #prev_float: Returns the next-smaller representable \Float.
 *  - #quo: Returns the quotient from dividing +self+ by the given value.
 *  - #round: Returns +self+ rounded to the nearest value, to a given precision.
 *  - #to_i (aliased as #to_int): Returns +self+ truncated to an Integer.
 *  - #to_s (aliased as #inspect): Returns a string containing the place-value
 *    representation of +self+ in the given radix.
 *  - #truncate: Returns +self+ truncated to a given precision.
 *
 */

VALUE
rb_float_new_in_heap(double d)
{
    NEWOBJ_OF(flt, struct RFloat, rb_cFloat, T_FLOAT | (RGENGC_WB_PROTECTED_FLOAT ? FL_WB_PROTECTED : 0), sizeof(struct RFloat), 0);

#if SIZEOF_DOUBLE <= SIZEOF_VALUE
    flt->float_value = d;
#else
    union {
        double d;
        rb_float_value_type v;
    } u = {d};
    flt->float_value = u.v;
#endif
    OBJ_FREEZE((VALUE)flt);
    return (VALUE)flt;
}

/*
 *  call-seq:
 *    to_s -> string
 *
 *  Returns a string containing a representation of +self+;
 *  depending of the value of +self+, the string representation
 *  may contain:
 *
 *  - A fixed-point number.
 *  - A number in "scientific notation" (containing an exponent).
 *  - 'Infinity'.
 *  - '-Infinity'.
 *  - 'NaN' (indicating not-a-number).
 *
 *    3.14.to_s         # => "3.14"
 *    (10.1**50).to_s   # => "1.644631821843879e+50"
 *    (10.1**500).to_s  # => "Infinity"
 *    (-10.1**500).to_s # => "-Infinity"
 *    (0.0/0.0).to_s    # => "NaN"
 *
 */

static VALUE
flo_to_s(VALUE flt)
{
    enum {decimal_mant = DBL_MANT_DIG-DBL_DIG};
    enum {float_dig = DBL_DIG+1};
    char buf[float_dig + roomof(decimal_mant, CHAR_BIT) + 10];
    double value = RFLOAT_VALUE(flt);
    VALUE s;
    char *p, *e;
    int sign, decpt, digs;

    if (isinf(value)) {
        static const char minf[] = "-Infinity";
        const int pos = (value > 0); /* skip "-" */
        return rb_usascii_str_new(minf+pos, strlen(minf)-pos);
    }
    else if (isnan(value))
        return rb_usascii_str_new2("NaN");

    p = ruby_dtoa(value, 0, 0, &decpt, &sign, &e);
    s = sign ? rb_usascii_str_new_cstr("-") : rb_usascii_str_new(0, 0);
    if ((digs = (int)(e - p)) >= (int)sizeof(buf)) digs = (int)sizeof(buf) - 1;
    memcpy(buf, p, digs);
    free(p);
    if (decpt > 0) {
        if (decpt < digs) {
            memmove(buf + decpt + 1, buf + decpt, digs - decpt);
            buf[decpt] = '.';
            rb_str_cat(s, buf, digs + 1);
        }
        else if (decpt <= DBL_DIG) {
            long len;
            char *ptr;
            rb_str_cat(s, buf, digs);
            rb_str_resize(s, (len = RSTRING_LEN(s)) + decpt - digs + 2);
            ptr = RSTRING_PTR(s) + len;
            if (decpt > digs) {
                memset(ptr, '0', decpt - digs);
                ptr += decpt - digs;
            }
            memcpy(ptr, ".0", 2);
        }
        else {
            goto exp;
        }
    }
    else if (decpt > -4) {
        long len;
        char *ptr;
        rb_str_cat(s, "0.", 2);
        rb_str_resize(s, (len = RSTRING_LEN(s)) - decpt + digs);
        ptr = RSTRING_PTR(s);
        memset(ptr += len, '0', -decpt);
        memcpy(ptr -= decpt, buf, digs);
    }
    else {
        goto exp;
    }
    return s;

  exp:
    if (digs > 1) {
        memmove(buf + 2, buf + 1, digs - 1);
    }
    else {
        buf[2] = '0';
        digs++;
    }
    buf[1] = '.';
    rb_str_cat(s, buf, digs + 1);
    rb_str_catf(s, "e%+03d", decpt - 1);
    return s;
}

/*
 *  call-seq:
 *    coerce(other) -> array
 *
 *  Returns a 2-element array containing +other+ converted to a \Float
 *  and +self+:
 *
 *    f = 3.14                 # => 3.14
 *    f.coerce(2)              # => [2.0, 3.14]
 *    f.coerce(2.0)            # => [2.0, 3.14]
 *    f.coerce(Rational(1, 2)) # => [0.5, 3.14]
 *    f.coerce(Complex(1, 0))  # => [1.0, 3.14]
 *
 *  Raises an exception if a type conversion fails.
 *
 */

static VALUE
flo_coerce(VALUE x, VALUE y)
{
    return rb_assoc_new(rb_Float(y), x);
}

VALUE
rb_float_uminus(VALUE flt)
{
    return DBL2NUM(-RFLOAT_VALUE(flt));
}

/*
 *  call-seq:
 *    self + other -> numeric
 *
 *  Returns a new \Float which is the sum of +self+ and +other+:
 *
 *    f = 3.14
 *    f + 1                 # => 4.140000000000001
 *    f + 1.0               # => 4.140000000000001
 *    f + Rational(1, 1)    # => 4.140000000000001
 *    f + Complex(1, 0)     # => (4.140000000000001+0i)
 *
 */

VALUE
rb_float_plus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) + (double)FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) + rb_big2dbl(y));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) + RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '+');
    }
}

/*
 *  call-seq:
 *    self - other -> numeric
 *
 *  Returns a new \Float which is the difference of +self+ and +other+:
 *
 *    f = 3.14
 *    f - 1                 # => 2.14
 *    f - 1.0               # => 2.14
 *    f - Rational(1, 1)    # => 2.14
 *    f - Complex(1, 0)     # => (2.14+0i)
 *
 */

VALUE
rb_float_minus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) - (double)FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) - rb_big2dbl(y));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) - RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '-');
    }
}

/*
 *  call-seq:
 *    self * other -> numeric
 *
 *  Returns a new \Float which is the product of +self+ and +other+:
 *
 *    f = 3.14
 *    f * 2              # => 6.28
 *    f * 2.0            # => 6.28
 *    f * Rational(1, 2) # => 1.57
 *    f * Complex(2, 0)  # => (6.28+0.0i)
 */

VALUE
rb_float_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) * (double)FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) * rb_big2dbl(y));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(RFLOAT_VALUE(x) * RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '*');
    }
}

static double
double_div_double(double x, double y)
{
    if (LIKELY(y != 0.0)) {
        return x / y;
    }
    else if (x == 0.0) {
        return nan("");
    }
    else {
        double z = signbit(y) ? -1.0 : 1.0;
        return x * z * HUGE_VAL;
    }
}

VALUE
rb_flo_div_flo(VALUE x, VALUE y)
{
    double num = RFLOAT_VALUE(x);
    double den = RFLOAT_VALUE(y);
    double ret = double_div_double(num, den);
    return DBL2NUM(ret);
}

/*
 *  call-seq:
 *    self / other -> numeric
 *
 *  Returns a new \Float which is the result of dividing +self+ by +other+:
 *
 *    f = 3.14
 *    f / 2              # => 1.57
 *    f / 2.0            # => 1.57
 *    f / Rational(2, 1) # => 1.57
 *    f / Complex(2, 0)  # => (1.57+0.0i)
 *
 */

VALUE
rb_float_div(VALUE x, VALUE y)
{
    double num = RFLOAT_VALUE(x);
    double den;
    double ret;

    if (FIXNUM_P(y)) {
        den = FIX2LONG(y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        den = rb_big2dbl(y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        den = RFLOAT_VALUE(y);
    }
    else {
        return rb_num_coerce_bin(x, y, '/');
    }

    ret = double_div_double(num, den);
    return DBL2NUM(ret);
}

/*
 *  call-seq:
 *    quo(other) -> numeric
 *
 *  Returns the quotient from dividing +self+ by +other+:
 *
 *    f = 3.14
 *    f.quo(2)              # => 1.57
 *    f.quo(-2)             # => -1.57
 *    f.quo(Rational(2, 1)) # => 1.57
 *    f.quo(Complex(2, 0))  # => (1.57+0.0i)
 *
 */

static VALUE
flo_quo(VALUE x, VALUE y)
{
    return num_funcall1(x, '/', y);
}

static void
flodivmod(double x, double y, double *divp, double *modp)
{
    double div, mod;

    if (isnan(y)) {
        /* y is NaN so all results are NaN */
        if (modp) *modp = y;
        if (divp) *divp = y;
        return;
    }
    if (y == 0.0) rb_num_zerodiv();
    if ((x == 0.0) || (isinf(y) && !isinf(x)))
        mod = x;
    else {
#ifdef HAVE_FMOD
        mod = fmod(x, y);
#else
        double z;

        modf(x/y, &z);
        mod = x - z * y;
#endif
    }
    if (isinf(x) && !isinf(y))
        div = x;
    else {
        div = (x - mod) / y;
        if (modp && divp) div = round(div);
    }
    if (y*mod < 0) {
        mod += y;
        div -= 1.0;
    }
    if (modp) *modp = mod;
    if (divp) *divp = div;
}

/*
 * Returns the modulo of division of x by y.
 * An error will be raised if y == 0.
 */

double
ruby_float_mod(double x, double y)
{
    double mod;
    flodivmod(x, y, 0, &mod);
    return mod;
}

/*
 *  call-seq:
 *    self % other -> float
 *
 *  Returns +self+ modulo +other+ as a float.
 *
 *  For float +f+ and real number +r+, these expressions are equivalent:
 *
 *    f % r
 *    f-r*(f/r).floor
 *    f.divmod(r)[1]
 *
 *  See Numeric#divmod.
 *
 *  Examples:
 *
 *    10.0 % 2              # => 0.0
 *    10.0 % 3              # => 1.0
 *    10.0 % 4              # => 2.0
 *
 *    10.0 % -2             # => 0.0
 *    10.0 % -3             # => -2.0
 *    10.0 % -4             # => -2.0
 *
 *    10.0 % 4.0            # => 2.0
 *    10.0 % Rational(4, 1) # => 2.0
 *
 */

static VALUE
flo_mod(VALUE x, VALUE y)
{
    double fy;

    if (FIXNUM_P(y)) {
        fy = (double)FIX2LONG(y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        fy = rb_big2dbl(y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        fy = RFLOAT_VALUE(y);
    }
    else {
        return rb_num_coerce_bin(x, y, '%');
    }
    return DBL2NUM(ruby_float_mod(RFLOAT_VALUE(x), fy));
}

static VALUE
dbl2ival(double d)
{
    if (FIXABLE(d)) {
        return LONG2FIX((long)d);
    }
    return rb_dbl2big(d);
}

/*
 *  call-seq:
 *    divmod(other) -> array
 *
 *  Returns a 2-element array <tt>[q, r]</tt>, where
 *
 *    q = (self/other).floor      # Quotient
 *    r = self % other            # Remainder
 *
 *  Examples:
 *
 *    11.0.divmod(4)              # => [2, 3.0]
 *    11.0.divmod(-4)             # => [-3, -1.0]
 *    -11.0.divmod(4)             # => [-3, 1.0]
 *    -11.0.divmod(-4)            # => [2, -3.0]
 *
 *    12.0.divmod(4)              # => [3, 0.0]
 *    12.0.divmod(-4)             # => [-3, 0.0]
 *    -12.0.divmod(4)             # => [-3, -0.0]
 *    -12.0.divmod(-4)            # => [3, -0.0]
 *
 *    13.0.divmod(4.0)            # => [3, 1.0]
 *    13.0.divmod(Rational(4, 1)) # => [3, 1.0]
 *
 */

static VALUE
flo_divmod(VALUE x, VALUE y)
{
    double fy, div, mod;
    volatile VALUE a, b;

    if (FIXNUM_P(y)) {
        fy = (double)FIX2LONG(y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        fy = rb_big2dbl(y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        fy = RFLOAT_VALUE(y);
    }
    else {
        return rb_num_coerce_bin(x, y, id_divmod);
    }
    flodivmod(RFLOAT_VALUE(x), fy, &div, &mod);
    a = dbl2ival(div);
    b = DBL2NUM(mod);
    return rb_assoc_new(a, b);
}

/*
 *  call-seq:
 *    self ** other -> numeric
 *
 *  Raises +self+ to the power of +other+:
 *
 *    f = 3.14
 *    f ** 2              # => 9.8596
 *    f ** -2             # => 0.1014239928597509
 *    f ** 2.1            # => 11.054834900588839
 *    f ** Rational(2, 1) # => 9.8596
 *    f ** Complex(2, 0)  # => (9.8596+0i)
 *
 */

VALUE
rb_float_pow(VALUE x, VALUE y)
{
    double dx, dy;
    if (y == INT2FIX(2)) {
        dx = RFLOAT_VALUE(x);
        return DBL2NUM(dx * dx);
    }
    else if (FIXNUM_P(y)) {
        dx = RFLOAT_VALUE(x);
        dy = (double)FIX2LONG(y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        dx = RFLOAT_VALUE(x);
        dy = rb_big2dbl(y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        dx = RFLOAT_VALUE(x);
        dy = RFLOAT_VALUE(y);
        if (dx < 0 && dy != round(dy))
            return rb_dbl_complex_new_polar_pi(pow(-dx, dy), dy);
    }
    else {
        return rb_num_coerce_bin(x, y, idPow);
    }
    return DBL2NUM(pow(dx, dy));
}

/*
 *  call-seq:
 *    eql?(other) -> true or false
 *
 *  Returns +true+ if +self+ and +other+ are the same type and have equal values.
 *
 *  Of the Core and Standard Library classes,
 *  only Integer, Rational, and Complex use this implementation.
 *
 *  Examples:
 *
 *    1.eql?(1)              # => true
 *    1.eql?(1.0)            # => false
 *    1.eql?(Rational(1, 1)) # => false
 *    1.eql?(Complex(1, 0))  # => false
 *
 *  \Method +eql?+ is different from <tt>==</tt> in that +eql?+ requires matching types,
 *  while <tt>==</tt> does not.
 *
 */

static VALUE
num_eql(VALUE x, VALUE y)
{
    if (TYPE(x) != TYPE(y)) return Qfalse;

    if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_eql(x, y);
    }

    return rb_equal(x, y);
}

/*
 *  call-seq:
 *    self <=> other -> zero or nil
 *
 *  Returns zero if +self+ is the same as +other+, +nil+ otherwise.
 *
 *  No subclass in the Ruby Core or Standard Library uses this implementation.
 *
 */

static VALUE
num_cmp(VALUE x, VALUE y)
{
    if (x == y) return INT2FIX(0);
    return Qnil;
}

static VALUE
num_equal(VALUE x, VALUE y)
{
    VALUE result;
    if (x == y) return Qtrue;
    result = num_funcall1(y, id_eq, x);
    return RBOOL(RTEST(result));
}

/*
 *  call-seq:
 *     self == other -> true or false
 *
 *  Returns +true+ if +other+ has the same value as +self+, +false+ otherwise:
 *
 *     2.0 == 2              # => true
 *     2.0 == 2.0            # => true
 *     2.0 == Rational(2, 1) # => true
 *     2.0 == Complex(2, 0)  # => true
 *
 *  <tt>Float::NAN == Float::NAN</tt> returns an implementation-dependent value.
 *
 *  Related: Float#eql? (requires +other+ to be a \Float).
 *
 */

VALUE
rb_float_equal(VALUE x, VALUE y)
{
    volatile double a, b;

    if (RB_INTEGER_TYPE_P(y)) {
        return rb_integer_float_eq(y, x);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(b)) return Qfalse;
#endif
    }
    else {
        return num_equal(x, y);
    }
    a = RFLOAT_VALUE(x);
#if MSC_VERSION_BEFORE(1300)
    if (isnan(a)) return Qfalse;
#endif
    return RBOOL(a == b);
}

#define flo_eq rb_float_equal
static VALUE rb_dbl_hash(double d);

/*
 * call-seq:
 *    hash -> integer
 *
 * Returns the integer hash value for +self+.
 *
 * See also Object#hash.
 */

static VALUE
flo_hash(VALUE num)
{
    return rb_dbl_hash(RFLOAT_VALUE(num));
}

static VALUE
rb_dbl_hash(double d)
{
    return ST2FIX(rb_dbl_long_hash(d));
}

VALUE
rb_dbl_cmp(double a, double b)
{
    if (isnan(a) || isnan(b)) return Qnil;
    if (a == b) return INT2FIX(0);
    if (a > b) return INT2FIX(1);
    if (a < b) return INT2FIX(-1);
    return Qnil;
}

/*
 *  call-seq:
 *     self <=> other ->  -1, 0, +1, or nil
 *
 *  Returns a value that depends on the numeric relation
 *  between +self+ and +other+:
 *
 *  - -1, if +self+ is less than +other+.
 *  - 0, if +self+ is equal to +other+.
 *  - 1, if +self+ is greater than +other+.
 *  - +nil+, if the two values are incommensurate.
 *
 *  Examples:
 *
 *    2.0 <=> 2              # => 0
 *    2.0 <=> 2.0            # => 0
 *    2.0 <=> Rational(2, 1) # => 0
 *    2.0 <=> Complex(2, 0)  # => 0
 *    2.0 <=> 1.9            # => 1
 *    2.0 <=> 2.1            # => -1
 *    2.0 <=> 'foo'          # => nil
 *
 *  This is the basis for the tests in the Comparable module.
 *
 *  <tt>Float::NAN <=> Float::NAN</tt> returns an implementation-dependent value.
 *
 */

static VALUE
flo_cmp(VALUE x, VALUE y)
{
    double a, b;
    VALUE i;

    a = RFLOAT_VALUE(x);
    if (isnan(a)) return Qnil;
    if (RB_INTEGER_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return LONG2FIX(-FIX2LONG(rel));
        return rel;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
    }
    else {
        if (isinf(a) && !UNDEF_P(i = rb_check_funcall(y, rb_intern("infinite?"), 0, 0))) {
            if (RTEST(i)) {
                int j = rb_cmpint(i, x, y);
                j = (a > 0.0) ? (j > 0 ? 0 : +1) : (j < 0 ? 0 : -1);
                return INT2FIX(j);
            }
            if (a > 0.0) return INT2FIX(1);
            return INT2FIX(-1);
        }
        return rb_num_coerce_cmp(x, y, id_cmp);
    }
    return rb_dbl_cmp(a, b);
}

int
rb_float_cmp(VALUE x, VALUE y)
{
    return NUM2INT(ensure_cmp(flo_cmp(x, y), x, y));
}

/*
 *  call-seq:
 *    self > other -> true or false
 *
 *  Returns +true+ if +self+ is numerically greater than +other+:
 *
 *    2.0 > 1              # => true
 *    2.0 > 1.0            # => true
 *    2.0 > Rational(1, 2) # => true
 *    2.0 > 2.0            # => false
 *
 *  <tt>Float::NAN > Float::NAN</tt> returns an implementation-dependent value.
 *
 */

VALUE
rb_float_gt(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_INTEGER_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return RBOOL(-FIX2LONG(rel) > 0);
        return Qfalse;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(b)) return Qfalse;
#endif
    }
    else {
        return rb_num_coerce_relop(x, y, '>');
    }
#if MSC_VERSION_BEFORE(1300)
    if (isnan(a)) return Qfalse;
#endif
    return RBOOL(a > b);
}

/*
 *  call-seq:
 *    self >= other -> true or false
 *
 *  Returns +true+ if +self+ is numerically greater than or equal to +other+:
 *
 *    2.0 >= 1              # => true
 *    2.0 >= 1.0            # => true
 *    2.0 >= Rational(1, 2) # => true
 *    2.0 >= 2.0            # => true
 *    2.0 >= 2.1            # => false
 *
 *  <tt>Float::NAN >= Float::NAN</tt> returns an implementation-dependent value.
 *
 */

static VALUE
flo_ge(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_TYPE_P(y, T_FIXNUM) || RB_BIGNUM_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return RBOOL(-FIX2LONG(rel) >= 0);
        return Qfalse;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(b)) return Qfalse;
#endif
    }
    else {
        return rb_num_coerce_relop(x, y, idGE);
    }
#if MSC_VERSION_BEFORE(1300)
    if (isnan(a)) return Qfalse;
#endif
    return RBOOL(a >= b);
}

/*
 *  call-seq:
 *    self < other -> true or false
 *
 *  Returns +true+ if +self+ is numerically less than +other+:
 *
 *    2.0 < 3              # => true
 *    2.0 < 3.0            # => true
 *    2.0 < Rational(3, 1) # => true
 *    2.0 < 2.0            # => false
 *
 *  <tt>Float::NAN < Float::NAN</tt> returns an implementation-dependent value.
 *
 */

static VALUE
flo_lt(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_INTEGER_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return RBOOL(-FIX2LONG(rel) < 0);
        return Qfalse;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(b)) return Qfalse;
#endif
    }
    else {
        return rb_num_coerce_relop(x, y, '<');
    }
#if MSC_VERSION_BEFORE(1300)
    if (isnan(a)) return Qfalse;
#endif
    return RBOOL(a < b);
}

/*
 *  call-seq:
 *    self <= other -> true or false
 *
 *  Returns +true+ if +self+ is numerically less than or equal to +other+:
 *
 *    2.0 <= 3              # => true
 *    2.0 <= 3.0            # => true
 *    2.0 <= Rational(3, 1) # => true
 *    2.0 <= 2.0            # => true
 *    2.0 <= 1.0            # => false
 *
 *  <tt>Float::NAN <= Float::NAN</tt> returns an implementation-dependent value.
 *
 */

static VALUE
flo_le(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_INTEGER_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return RBOOL(-FIX2LONG(rel) <= 0);
        return Qfalse;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(b)) return Qfalse;
#endif
    }
    else {
        return rb_num_coerce_relop(x, y, idLE);
    }
#if MSC_VERSION_BEFORE(1300)
    if (isnan(a)) return Qfalse;
#endif
    return RBOOL(a <= b);
}

/*
 *  call-seq:
 *    eql?(other) -> true or false
 *
 *  Returns +true+ if +other+ is a \Float with the same value as +self+,
 *  +false+ otherwise:
 *
 *    2.0.eql?(2.0)            # => true
 *    2.0.eql?(1.0)            # => false
 *    2.0.eql?(1)              # => false
 *    2.0.eql?(Rational(2, 1)) # => false
 *    2.0.eql?(Complex(2, 0))  # => false
 *
 *  <tt>Float::NAN.eql?(Float::NAN)</tt> returns an implementation-dependent value.
 *
 *  Related: Float#== (performs type conversions).
 */

VALUE
rb_float_eql(VALUE x, VALUE y)
{
    if (RB_FLOAT_TYPE_P(y)) {
        double a = RFLOAT_VALUE(x);
        double b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
        if (isnan(a) || isnan(b)) return Qfalse;
#endif
    return RBOOL(a == b);
    }
    return Qfalse;
}

#define flo_eql rb_float_eql

VALUE
rb_float_abs(VALUE flt)
{
    double val = fabs(RFLOAT_VALUE(flt));
    return DBL2NUM(val);
}

/*
 *  call-seq:
 *    nan? -> true or false
 *
 *  Returns +true+ if +self+ is a NaN, +false+ otherwise.
 *
 *     f = -1.0     #=> -1.0
 *     f.nan?       #=> false
 *     f = 0.0/0.0  #=> NaN
 *     f.nan?       #=> true
 */

static VALUE
flo_is_nan_p(VALUE num)
{
    double value = RFLOAT_VALUE(num);

    return RBOOL(isnan(value));
}

/*
 *  call-seq:
 *    infinite? -> -1, 1, or nil
 *
 *  Returns:
 *
 *  - 1, if +self+ is <tt>Infinity</tt>.
 *  - -1 if +self+ is <tt>-Infinity</tt>.
 *  - +nil+, otherwise.
 *
 *  Examples:
 *
 *    f = 1.0/0.0  # => Infinity
 *    f.infinite?  # => 1
 *    f = -1.0/0.0 # => -Infinity
 *    f.infinite?  # => -1
 *    f = 1.0      # => 1.0
 *    f.infinite?  # => nil
 *    f = 0.0/0.0  # => NaN
 *    f.infinite?  # => nil
 *
 */

VALUE
rb_flo_is_infinite_p(VALUE num)
{
    double value = RFLOAT_VALUE(num);

    if (isinf(value)) {
        return INT2FIX( value < 0 ? -1 : 1 );
    }

    return Qnil;
}

/*
 *  call-seq:
 *    finite? -> true or false
 *
 *  Returns +true+ if +self+ is not +Infinity+, +-Infinity+, or +NaN+,
 *  +false+ otherwise:
 *
 *    f = 2.0      # => 2.0
 *    f.finite?    # => true
 *    f = 1.0/0.0  # => Infinity
 *    f.finite?    # => false
 *    f = -1.0/0.0 # => -Infinity
 *    f.finite?    # => false
 *    f = 0.0/0.0  # => NaN
 *    f.finite?    # => false
 *
 */

VALUE
rb_flo_is_finite_p(VALUE num)
{
    double value = RFLOAT_VALUE(num);

    return RBOOL(isfinite(value));
}

static VALUE
flo_nextafter(VALUE flo, double value)
{
    double x, y;
    x = NUM2DBL(flo);
    y = nextafter(x, value);
    return DBL2NUM(y);
}

/*
 *  call-seq:
 *    next_float -> float
 *
 *  Returns the next-larger representable \Float.
 *
 *  These examples show the internally stored values (64-bit hexadecimal)
 *  for each \Float +f+ and for the corresponding <tt>f.next_float</tt>:
 *
 *    f = 0.0      # 0x0000000000000000
 *    f.next_float # 0x0000000000000001
 *
 *    f = 0.01     # 0x3f847ae147ae147b
 *    f.next_float # 0x3f847ae147ae147c
 *
 *  In the remaining examples here, the output is shown in the usual way
 *  (result +to_s+):
 *
 *    0.01.next_float    # => 0.010000000000000002
 *    1.0.next_float     # => 1.0000000000000002
 *    100.0.next_float   # => 100.00000000000001
 *
 *    f = 0.01
 *    (0..3).each_with_index {|i| printf "%2d %-20a %s\n", i, f, f.to_s; f = f.next_float }
 *
 *  Output:
 *
 *     0 0x1.47ae147ae147bp-7 0.01
 *     1 0x1.47ae147ae147cp-7 0.010000000000000002
 *     2 0x1.47ae147ae147dp-7 0.010000000000000004
 *     3 0x1.47ae147ae147ep-7 0.010000000000000005
 *
 *    f = 0.0; 100.times { f += 0.1 }
 *    f                           # => 9.99999999999998       # should be 10.0 in the ideal world.
 *    10-f                        # => 1.9539925233402755e-14 # the floating point error.
 *    10.0.next_float-10          # => 1.7763568394002505e-15 # 1 ulp (unit in the last place).
 *    (10-f)/(10.0.next_float-10) # => 11.0                   # the error is 11 ulp.
 *    (10-f)/(10*Float::EPSILON)  # => 8.8                    # approximation of the above.
 *    "%a" % 10                   # => "0x1.4p+3"
 *    "%a" % f                    # => "0x1.3fffffffffff5p+3" # the last hex digit is 5.  16 - 5 = 11 ulp.
 *
 *  Related: Float#prev_float
 *
 */
static VALUE
flo_next_float(VALUE vx)
{
    return flo_nextafter(vx, HUGE_VAL);
}

/*
 *  call-seq:
 *     float.prev_float  ->  float
 *
 *  Returns the next-smaller representable \Float.
 *
 *  These examples show the internally stored values (64-bit hexadecimal)
 *  for each \Float +f+ and for the corresponding <tt>f.pev_float</tt>:
 *
 *    f = 5e-324   # 0x0000000000000001
 *    f.prev_float # 0x0000000000000000
 *
 *    f = 0.01     # 0x3f847ae147ae147b
 *    f.prev_float # 0x3f847ae147ae147a
 *
 *  In the remaining examples here, the output is shown in the usual way
 *  (result +to_s+):
 *
 *    0.01.prev_float   # => 0.009999999999999998
 *    1.0.prev_float    # => 0.9999999999999999
 *    100.0.prev_float  # => 99.99999999999999
 *
 *    f = 0.01
 *    (0..3).each_with_index {|i| printf "%2d %-20a %s\n", i, f, f.to_s; f = f.prev_float }
 *
 *  Output:
 *
 *     0 0x1.47ae147ae147bp-7 0.01
 *     1 0x1.47ae147ae147ap-7 0.009999999999999998
 *     2 0x1.47ae147ae1479p-7 0.009999999999999997
 *     3 0x1.47ae147ae1478p-7 0.009999999999999995
 *
 *  Related: Float#next_float.
 *
 */
static VALUE
flo_prev_float(VALUE vx)
{
    return flo_nextafter(vx, -HUGE_VAL);
}

VALUE
rb_float_floor(VALUE num, int ndigits)
{
    double number;
    number = RFLOAT_VALUE(num);
    if (number == 0.0) {
        return ndigits > 0 ? DBL2NUM(number) : INT2FIX(0);
    }
    if (ndigits > 0) {
        int binexp;
        double f, mul, res;
        frexp(number, &binexp);
        if (float_round_overflow(ndigits, binexp)) return num;
        if (number > 0.0 && float_round_underflow(ndigits, binexp))
            return DBL2NUM(0.0);
        f = pow(10, ndigits);
        mul = floor(number * f);
        res = (mul + 1) / f;
        if (res > number)
            res = mul / f;
        return DBL2NUM(res);
    }
    else {
        num = dbl2ival(floor(number));
        if (ndigits < 0) num = rb_int_floor(num, ndigits);
        return num;
    }
}

static int
flo_ndigits(int argc, VALUE *argv)
{
    if (rb_check_arity(argc, 0, 1)) {
        return NUM2INT(argv[0]);
    }
    return 0;
}

/*
 *  call-seq:
 *    floor(ndigits = 0) -> float or integer
 *
 *  Returns the largest number less than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is positive, returns a float with +ndigits+
 *  digits after the decimal point (as available):
 *
 *    f = 12345.6789
 *    f.floor(1) # => 12345.6
 *    f.floor(3) # => 12345.678
 *    f = -12345.6789
 *    f.floor(1) # => -12345.7
 *    f.floor(3) # => -12345.679
 *
 *  When +ndigits+ is non-positive, returns an integer with at least
 *  <code>ndigits.abs</code> trailing zeros:
 *
 *    f = 12345.6789
 *    f.floor(0)  # => 12345
 *    f.floor(-3) # => 12000
 *    f = -12345.6789
 *    f.floor(0)  # => -12346
 *    f.floor(-3) # => -13000
 *
 *  Note that the limited precision of floating-point arithmetic
 *  may lead to surprising results:
 *
 *     (0.3 / 0.1).floor  #=> 2 (!)
 *
 *  Related: Float#ceil.
 *
 */

static VALUE
flo_floor(int argc, VALUE *argv, VALUE num)
{
    int ndigits = flo_ndigits(argc, argv);
    return rb_float_floor(num, ndigits);
}

/*
 *  call-seq:
 *    ceil(ndigits = 0) -> float or integer
 *
 *  Returns the smallest number greater than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is positive, returns a float with +ndigits+
 *  digits after the decimal point (as available):
 *
 *    f = 12345.6789
 *    f.ceil(1) # => 12345.7
 *    f.ceil(3) # => 12345.679
 *    f = -12345.6789
 *    f.ceil(1) # => -12345.6
 *    f.ceil(3) # => -12345.678
 *
 *  When +ndigits+ is non-positive, returns an integer with at least
 *  <code>ndigits.abs</code> trailing zeros:
 *
 *    f = 12345.6789
 *    f.ceil(0)  # => 12346
 *    f.ceil(-3) # => 13000
 *    f = -12345.6789
 *    f.ceil(0)  # => -12345
 *    f.ceil(-3) # => -12000
 *
 *  Note that the limited precision of floating-point arithmetic
 *  may lead to surprising results:
 *
 *     (2.1 / 0.7).ceil  #=> 4 (!)
 *
 *  Related: Float#floor.
 *
 */

static VALUE
flo_ceil(int argc, VALUE *argv, VALUE num)
{
    int ndigits = flo_ndigits(argc, argv);
    return rb_float_ceil(num, ndigits);
}

VALUE
rb_float_ceil(VALUE num, int ndigits)
{
    double number, f;

    number = RFLOAT_VALUE(num);
    if (number == 0.0) {
        return ndigits > 0 ? DBL2NUM(number) : INT2FIX(0);
    }
    if (ndigits > 0) {
        int binexp;
        frexp(number, &binexp);
        if (float_round_overflow(ndigits, binexp)) return num;
        if (number < 0.0 && float_round_underflow(ndigits, binexp))
            return DBL2NUM(0.0);
        f = pow(10, ndigits);
        f = ceil(number * f) / f;
        return DBL2NUM(f);
    }
    else {
        num = dbl2ival(ceil(number));
        if (ndigits < 0) num = rb_int_ceil(num, ndigits);
        return num;
    }
}

static int
int_round_zero_p(VALUE num, int ndigits)
{
    long bytes;
    /* If 10**N / 2 > num, then return 0 */
    /* We have log_256(10) > 0.415241 and log_256(1/2) = -0.125, so */
    if (FIXNUM_P(num)) {
        bytes = sizeof(long);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        bytes = rb_big_size(num);
    }
    else {
        bytes = NUM2LONG(rb_funcall(num, idSize, 0));
    }
    return (-0.415241 * ndigits - 0.125 > bytes);
}

static SIGNED_VALUE
int_round_half_even(SIGNED_VALUE x, SIGNED_VALUE y)
{
    SIGNED_VALUE z = +(x + y / 2) / y;
    if ((z * y - x) * 2 == y) {
        z &= ~1;
    }
    return z * y;
}

static SIGNED_VALUE
int_round_half_up(SIGNED_VALUE x, SIGNED_VALUE y)
{
    return (x + y / 2) / y * y;
}

static SIGNED_VALUE
int_round_half_down(SIGNED_VALUE x, SIGNED_VALUE y)
{
    return (x + y / 2 - 1) / y * y;
}

static int
int_half_p_half_even(VALUE num, VALUE n, VALUE f)
{
    return (int)rb_int_odd_p(rb_int_idiv(n, f));
}

static int
int_half_p_half_up(VALUE num, VALUE n, VALUE f)
{
    return int_pos_p(num);
}

static int
int_half_p_half_down(VALUE num, VALUE n, VALUE f)
{
    return int_neg_p(num);
}

/*
 * Assumes num is an \Integer, ndigits <= 0
 */
static VALUE
rb_int_round(VALUE num, int ndigits, enum ruby_num_rounding_mode mode)
{
    VALUE n, f, h, r;

    if (int_round_zero_p(num, ndigits)) {
        return INT2FIX(0);
    }

    f = int_pow(10, -ndigits);
    if (FIXNUM_P(num) && FIXNUM_P(f)) {
        SIGNED_VALUE x = FIX2LONG(num), y = FIX2LONG(f);
        int neg = x < 0;
        if (neg) x = -x;
        x = ROUND_CALL(mode, int_round, (x, y));
        if (neg) x = -x;
        return LONG2NUM(x);
    }
    if (RB_FLOAT_TYPE_P(f)) {
        /* then int_pow overflow */
        return INT2FIX(0);
    }
    h = rb_int_idiv(f, INT2FIX(2));
    r = rb_int_modulo(num, f);
    n = rb_int_minus(num, r);
    r = rb_int_cmp(r, h);
    if (FIXNUM_POSITIVE_P(r) ||
        (FIXNUM_ZERO_P(r) && ROUND_CALL(mode, int_half_p, (num, n, f)))) {
        n = rb_int_plus(n, f);
    }
    return n;
}

static VALUE
rb_int_floor(VALUE num, int ndigits)
{
    VALUE f;

    if (int_round_zero_p(num, ndigits))
        return INT2FIX(0);
    f = int_pow(10, -ndigits);
    if (FIXNUM_P(num) && FIXNUM_P(f)) {
        SIGNED_VALUE x = FIX2LONG(num), y = FIX2LONG(f);
        int neg = x < 0;
        if (neg) x = -x + y - 1;
        x = x / y * y;
        if (neg) x = -x;
        return LONG2NUM(x);
    }
    if (RB_FLOAT_TYPE_P(f)) {
        /* then int_pow overflow */
        return INT2FIX(0);
    }
    return rb_int_minus(num, rb_int_modulo(num, f));
}

static VALUE
rb_int_ceil(VALUE num, int ndigits)
{
    VALUE f;

    if (int_round_zero_p(num, ndigits))
        return INT2FIX(0);
    f = int_pow(10, -ndigits);
    if (FIXNUM_P(num) && FIXNUM_P(f)) {
        SIGNED_VALUE x = FIX2LONG(num), y = FIX2LONG(f);
        int neg = x < 0;
        if (neg) x = -x;
        else x += y - 1;
        x = (x / y) * y;
        if (neg) x = -x;
        return LONG2NUM(x);
    }
    if (RB_FLOAT_TYPE_P(f)) {
        /* then int_pow overflow */
        return INT2FIX(0);
    }
    return rb_int_plus(num, rb_int_minus(f, rb_int_modulo(num, f)));
}

VALUE
rb_int_truncate(VALUE num, int ndigits)
{
    VALUE f;
    VALUE m;

    if (int_round_zero_p(num, ndigits))
        return INT2FIX(0);
    f = int_pow(10, -ndigits);
    if (FIXNUM_P(num) && FIXNUM_P(f)) {
        SIGNED_VALUE x = FIX2LONG(num), y = FIX2LONG(f);
        int neg = x < 0;
        if (neg) x = -x;
        x = x / y * y;
        if (neg) x = -x;
        return LONG2NUM(x);
    }
    if (RB_FLOAT_TYPE_P(f)) {
        /* then int_pow overflow */
        return INT2FIX(0);
    }
    m = rb_int_modulo(num, f);
    if (int_neg_p(num)) {
        return rb_int_plus(num, rb_int_minus(f, m));
    }
    else {
        return rb_int_minus(num, m);
    }
}

/*
 *  call-seq:
 *    round(ndigits = 0, half: :up) -> integer or float
 *
 *  Returns +self+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is non-negative, returns a float with +ndigits+
 *  after the decimal point (as available):
 *
 *    f = 12345.6789
 *    f.round(1) # => 12345.7
 *    f.round(3) # => 12345.679
 *    f = -12345.6789
 *    f.round(1) # => -12345.7
 *    f.round(3) # => -12345.679
 *
 *  When +ndigits+ is negative, returns an integer
 *  with at least <tt>ndigits.abs</tt> trailing zeros:
 *
 *    f = 12345.6789
 *    f.round(0)  # => 12346
 *    f.round(-3) # => 12000
 *    f = -12345.6789
 *    f.round(0)  # => -12346
 *    f.round(-3) # => -12000
 *
 *  If keyword argument +half+ is given,
 *  and +self+ is equidistant from the two candidate values,
 *  the rounding is according to the given +half+ value:
 *
 *  - +:up+ or +nil+: round away from zero:
 *
 *      2.5.round(half: :up)      # => 3
 *      3.5.round(half: :up)      # => 4
 *      (-2.5).round(half: :up)   # => -3
 *
 *  - +:down+: round toward zero:
 *
 *      2.5.round(half: :down)    # => 2
 *      3.5.round(half: :down)    # => 3
 *      (-2.5).round(half: :down) # => -2
 *
 *  - +:even+: round toward the candidate whose last nonzero digit is even:
 *
 *      2.5.round(half: :even)    # => 2
 *      3.5.round(half: :even)    # => 4
 *      (-2.5).round(half: :even) # => -2
 *
 *  Raises and exception if the value for +half+ is invalid.
 *
 *  Related: Float#truncate.
 *
 */

static VALUE
flo_round(int argc, VALUE *argv, VALUE num)
{
    double number, f, x;
    VALUE nd, opt;
    int ndigits = 0;
    enum ruby_num_rounding_mode mode;

    if (rb_scan_args(argc, argv, "01:", &nd, &opt)) {
        ndigits = NUM2INT(nd);
    }
    mode = rb_num_get_rounding_option(opt);
    number = RFLOAT_VALUE(num);
    if (number == 0.0) {
        return ndigits > 0 ? DBL2NUM(number) : INT2FIX(0);
    }
    if (ndigits < 0) {
        return rb_int_round(flo_to_i(num), ndigits, mode);
    }
    if (ndigits == 0) {
        x = ROUND_CALL(mode, round, (number, 1.0));
        return dbl2ival(x);
    }
    if (isfinite(number)) {
        int binexp;
        frexp(number, &binexp);
        if (float_round_overflow(ndigits, binexp)) return num;
        if (float_round_underflow(ndigits, binexp)) return DBL2NUM(0);
        if (ndigits > 14) {
            /* In this case, pow(10, ndigits) may not be accurate. */
            return rb_flo_round_by_rational(argc, argv, num);
        }
        f = pow(10, ndigits);
        x = ROUND_CALL(mode, round, (number, f));
        return DBL2NUM(x / f);
    }
    return num;
}

static int
float_round_overflow(int ndigits, int binexp)
{
    enum {float_dig = DBL_DIG+2};

/* Let `exp` be such that `number` is written as:"0.#{digits}e#{exp}",
   i.e. such that  10 ** (exp - 1) <= |number| < 10 ** exp
   Recall that up to float_dig digits can be needed to represent a double,
   so if ndigits + exp >= float_dig, the intermediate value (number * 10 ** ndigits)
   will be an integer and thus the result is the original number.
   If ndigits + exp <= 0, the result is 0 or "1e#{exp}", so
   if ndigits + exp < 0, the result is 0.
   We have:
        2 ** (binexp-1) <= |number| < 2 ** binexp
        10 ** ((binexp-1)/log_2(10)) <= |number| < 10 ** (binexp/log_2(10))
        If binexp >= 0, and since log_2(10) = 3.322259:
           10 ** (binexp/4 - 1) < |number| < 10 ** (binexp/3)
           floor(binexp/4) <= exp <= ceil(binexp/3)
        If binexp <= 0, swap the /4 and the /3
        So if ndigits + floor(binexp/(4 or 3)) >= float_dig, the result is number
        If ndigits + ceil(binexp/(3 or 4)) < 0 the result is 0
*/
    if (ndigits >= float_dig - (binexp > 0 ? binexp / 4 : binexp / 3 - 1)) {
        return TRUE;
    }
    return FALSE;
}

static int
float_round_underflow(int ndigits, int binexp)
{
    if (ndigits < - (binexp > 0 ? binexp / 3 + 1 : binexp / 4)) {
        return TRUE;
    }
    return FALSE;
}

/*
 *  call-seq:
 *    to_i -> integer
 *
 *  Returns +self+ truncated to an Integer.
 *
 *    1.2.to_i    # => 1
 *    (-1.2).to_i # => -1
 *
 *  Note that the limited precision of floating-point arithmetic
 *  may lead to surprising results:
 *
 *    (0.3 / 0.1).to_i  # => 2 (!)
 *
 */

static VALUE
flo_to_i(VALUE num)
{
    double f = RFLOAT_VALUE(num);

    if (f > 0.0) f = floor(f);
    if (f < 0.0) f = ceil(f);

    return dbl2ival(f);
}

/*
 *  call-seq:
 *    truncate(ndigits = 0) -> float or integer
 *
 *  Returns +self+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is positive, returns a float with +ndigits+ digits
 *  after the decimal point (as available):
 *
 *    f = 12345.6789
 *    f.truncate(1) # => 12345.6
 *    f.truncate(3) # => 12345.678
 *    f = -12345.6789
 *    f.truncate(1) # => -12345.6
 *    f.truncate(3) # => -12345.678
 *
 *  When +ndigits+ is negative, returns an integer
 *  with at least <tt>ndigits.abs</tt> trailing zeros:
 *
 *    f = 12345.6789
 *    f.truncate(0)  # => 12345
 *    f.truncate(-3) # => 12000
 *    f = -12345.6789
 *    f.truncate(0)  # => -12345
 *    f.truncate(-3) # => -12000
 *
 *  Note that the limited precision of floating-point arithmetic
 *  may lead to surprising results:
 *
 *     (0.3 / 0.1).truncate  #=> 2 (!)
 *
 *  Related: Float#round.
 *
 */
static VALUE
flo_truncate(int argc, VALUE *argv, VALUE num)
{
    if (signbit(RFLOAT_VALUE(num)))
        return flo_ceil(argc, argv, num);
    else
        return flo_floor(argc, argv, num);
}

/*
 *  call-seq:
 *    floor(digits = 0) -> integer or float
 *
 *  Returns the largest number that is less than or equal to +self+ with
 *  a precision of +digits+ decimal digits.
 *
 *  \Numeric implements this by converting +self+ to a Float and
 *  invoking Float#floor.
 */

static VALUE
num_floor(int argc, VALUE *argv, VALUE num)
{
    return flo_floor(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *    ceil(digits = 0) -> integer or float
 *
 *  Returns the smallest number that is greater than or equal to +self+ with
 *  a precision of +digits+ decimal digits.
 *
 *  \Numeric implements this by converting +self+ to a Float and
 *  invoking Float#ceil.
 */

static VALUE
num_ceil(int argc, VALUE *argv, VALUE num)
{
    return flo_ceil(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *    round(digits = 0) -> integer or float
 *
 *  Returns +self+ rounded to the nearest value with
 *  a precision of +digits+ decimal digits.
 *
 *  \Numeric implements this by converting +self+ to a Float and
 *  invoking Float#round.
 */

static VALUE
num_round(int argc, VALUE* argv, VALUE num)
{
    return flo_round(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *    truncate(digits = 0) -> integer or float
 *
 *  Returns +self+ truncated (toward zero) to
 *  a precision of +digits+ decimal digits.
 *
 *  \Numeric implements this by converting +self+ to a Float and
 *  invoking Float#truncate.
 */

static VALUE
num_truncate(int argc, VALUE *argv, VALUE num)
{
    return flo_truncate(argc, argv, rb_Float(num));
}

double
ruby_float_step_size(double beg, double end, double unit, int excl)
{
    const double epsilon = DBL_EPSILON;
    double d, n, err;

    if (unit == 0) {
        return HUGE_VAL;
    }
    if (isinf(unit)) {
        return unit > 0 ? beg <= end : beg >= end;
    }
    n= (end - beg)/unit;
    err = (fabs(beg) + fabs(end) + fabs(end-beg)) / fabs(unit) * epsilon;
    if (err>0.5) err=0.5;
    if (excl) {
        if (n<=0) return 0;
        if (n<1)
            n = 0;
        else
            n = floor(n - err);
        d = +((n + 1) * unit) + beg;
        if (beg < end) {
            if (d < end)
                n++;
        }
        else if (beg > end) {
            if (d > end)
                n++;
        }
    }
    else {
        if (n<0) return 0;
        n = floor(n + err);
        d = +((n + 1) * unit) + beg;
        if (beg < end) {
            if (d <= end)
                n++;
        }
        else if (beg > end) {
            if (d >= end)
               n++;
        }
    }
    return n+1;
}

int
ruby_float_step(VALUE from, VALUE to, VALUE step, int excl, int allow_endless)
{
    if (RB_FLOAT_TYPE_P(from) || RB_FLOAT_TYPE_P(to) || RB_FLOAT_TYPE_P(step)) {
        double unit = NUM2DBL(step);
        double beg = NUM2DBL(from);
        double end = (allow_endless && NIL_P(to)) ? (unit < 0 ? -1 : 1)*HUGE_VAL : NUM2DBL(to);
        double n = ruby_float_step_size(beg, end, unit, excl);
        long i;

        if (isinf(unit)) {
            /* if unit is infinity, i*unit+beg is NaN */
            if (n) rb_yield(DBL2NUM(beg));
        }
        else if (unit == 0) {
            VALUE val = DBL2NUM(beg);
            for (;;)
                rb_yield(val);
        }
        else {
            for (i=0; i<n; i++) {
                double d = i*unit+beg;
                if (unit >= 0 ? end < d : d < end) d = end;
                rb_yield(DBL2NUM(d));
            }
        }
        return TRUE;
    }
    return FALSE;
}

VALUE
ruby_num_interval_step_size(VALUE from, VALUE to, VALUE step, int excl)
{
    if (FIXNUM_P(from) && FIXNUM_P(to) && FIXNUM_P(step)) {
        long delta, diff;

        diff = FIX2LONG(step);
        if (diff == 0) {
            return DBL2NUM(HUGE_VAL);
        }
        delta = FIX2LONG(to) - FIX2LONG(from);
        if (diff < 0) {
            diff = -diff;
            delta = -delta;
        }
        if (excl) {
            delta--;
        }
        if (delta < 0) {
            return INT2FIX(0);
        }
        return ULONG2NUM(delta / diff + 1UL);
    }
    else if (RB_FLOAT_TYPE_P(from) || RB_FLOAT_TYPE_P(to) || RB_FLOAT_TYPE_P(step)) {
        double n = ruby_float_step_size(NUM2DBL(from), NUM2DBL(to), NUM2DBL(step), excl);

        if (isinf(n)) return DBL2NUM(n);
        if (POSFIXABLE(n)) return LONG2FIX((long)n);
        return rb_dbl2big(n);
    }
    else {
        VALUE result;
        ID cmp = '>';
        switch (rb_cmpint(rb_num_coerce_cmp(step, INT2FIX(0), id_cmp), step, INT2FIX(0))) {
          case 0: return DBL2NUM(HUGE_VAL);
          case -1: cmp = '<'; break;
        }
        if (RTEST(rb_funcall(from, cmp, 1, to))) return INT2FIX(0);
        result = rb_funcall(rb_funcall(to, '-', 1, from), id_div, 1, step);
        if (!excl || RTEST(rb_funcall(to, cmp, 1, rb_funcall(from, '+', 1, rb_funcall(result, '*', 1, step))))) {
            result = rb_funcall(result, '+', 1, INT2FIX(1));
        }
        return result;
    }
}

static int
num_step_negative_p(VALUE num)
{
    const ID mid = '<';
    VALUE zero = INT2FIX(0);
    VALUE r;

    if (FIXNUM_P(num)) {
        if (method_basic_p(rb_cInteger))
            return (SIGNED_VALUE)num < 0;
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        if (method_basic_p(rb_cInteger))
            return BIGNUM_NEGATIVE_P(num);
    }

    r = rb_check_funcall(num, '>', 1, &zero);
    if (UNDEF_P(r)) {
        coerce_failed(num, INT2FIX(0));
    }
    return !RTEST(r);
}

static int
num_step_extract_args(int argc, const VALUE *argv, VALUE *to, VALUE *step, VALUE *by)
{
    VALUE hash;

    argc = rb_scan_args(argc, argv, "02:", to, step, &hash);
    if (!NIL_P(hash)) {
        ID keys[2];
        VALUE values[2];
        keys[0] = id_to;
        keys[1] = id_by;
        rb_get_kwargs(hash, keys, 0, 2, values);
        if (!UNDEF_P(values[0])) {
            if (argc > 0) rb_raise(rb_eArgError, "to is given twice");
            *to = values[0];
        }
        if (!UNDEF_P(values[1])) {
            if (argc > 1) rb_raise(rb_eArgError, "step is given twice");
            *by = values[1];
        }
    }

    return argc;
}

static int
num_step_check_fix_args(int argc, VALUE *to, VALUE *step, VALUE by, int fix_nil, int allow_zero_step)
{
    int desc;
    if (!UNDEF_P(by)) {
        *step = by;
    }
    else {
        /* compatibility */
        if (argc > 1 && NIL_P(*step)) {
            rb_raise(rb_eTypeError, "step must be numeric");
        }
    }
    if (!allow_zero_step && rb_equal(*step, INT2FIX(0))) {
        rb_raise(rb_eArgError, "step can't be 0");
    }
    if (NIL_P(*step)) {
        *step = INT2FIX(1);
    }
    desc = num_step_negative_p(*step);
    if (fix_nil && NIL_P(*to)) {
        *to = desc ? DBL2NUM(-HUGE_VAL) : DBL2NUM(HUGE_VAL);
    }
    return desc;
}

static int
num_step_scan_args(int argc, const VALUE *argv, VALUE *to, VALUE *step, int fix_nil, int allow_zero_step)
{
    VALUE by = Qundef;
    argc = num_step_extract_args(argc, argv, to, step, &by);
    return num_step_check_fix_args(argc, to, step, by, fix_nil, allow_zero_step);
}

static VALUE
num_step_size(VALUE from, VALUE args, VALUE eobj)
{
    VALUE to, step;
    int argc = args ? RARRAY_LENINT(args) : 0;
    const VALUE *argv = args ? RARRAY_CONST_PTR(args) : 0;

    num_step_scan_args(argc, argv, &to, &step, TRUE, FALSE);

    return ruby_num_interval_step_size(from, to, step, FALSE);
}

/*
 *  call-seq:
 *    step(to = nil, by = 1) {|n| ... } ->  self
 *    step(to = nil, by = 1)            ->  enumerator
 *    step(to = nil, by: 1) {|n| ... }  ->  self
 *    step(to = nil, by: 1)             ->  enumerator
 *    step(by: 1, to: ) {|n| ... }      ->  self
 *    step(by: 1, to: )                 ->  enumerator
 *    step(by: , to: nil) {|n| ... }    ->  self
 *    step(by: , to: nil)               ->  enumerator
 *
 * Generates a sequence of numbers; with a block given, traverses the sequence.
 *
 * Of the Core and Standard Library classes,
 * Integer, Float, and Rational use this implementation.
 *
 * A quick example:
 *
 *   squares = []
 *   1.step(by: 2, to: 10) {|i| squares.push(i*i) }
 *   squares # => [1, 9, 25, 49, 81]
 *
 * The generated sequence:
 *
 * - Begins with +self+.
 * - Continues at intervals of +by+ (which may not be zero).
 * - Ends with the last number that is within or equal to +to+;
 *   that is, less than or equal to +to+ if +by+ is positive,
 *   greater than or equal to +to+ if +by+ is negative.
 *   If +to+ is +nil+, the sequence is of infinite length.
 *
 * If a block is given, calls the block with each number in the sequence;
 * returns +self+. If no block is given, returns an Enumerator::ArithmeticSequence.
 *
 * <b>Keyword Arguments</b>
 *
 * With keyword arguments +by+ and +to+,
 * their values (or defaults) determine the step and limit:
 *
 *   # Both keywords given.
 *   squares = []
 *   4.step(by: 2, to: 10) {|i| squares.push(i*i) }    # => 4
 *   squares # => [16, 36, 64, 100]
 *   cubes = []
 *   3.step(by: -1.5, to: -3) {|i| cubes.push(i*i*i) } # => 3
 *   cubes   # => [27.0, 3.375, 0.0, -3.375, -27.0]
 *   squares = []
 *   1.2.step(by: 0.2, to: 2.0) {|f| squares.push(f*f) }
 *   squares # => [1.44, 1.9599999999999997, 2.5600000000000005, 3.24, 4.0]
 *
 *   squares = []
 *   Rational(6/5).step(by: 0.2, to: 2.0) {|r| squares.push(r*r) }
 *   squares # => [1.0, 1.44, 1.9599999999999997, 2.5600000000000005, 3.24, 4.0]
 *
 *   # Only keyword to given.
 *   squares = []
 *   4.step(to: 10) {|i| squares.push(i*i) }           # => 4
 *   squares # => [16, 25, 36, 49, 64, 81, 100]
 *   # Only by given.
 *
 *   # Only keyword by given
 *   squares = []
 *   4.step(by:2) {|i| squares.push(i*i); break if i > 10 }
 *   squares # => [16, 36, 64, 100, 144]
 *
 *   # No block given.
 *   e = 3.step(by: -1.5, to: -3) # => (3.step(by: -1.5, to: -3))
 *   e.class                      # => Enumerator::ArithmeticSequence
 *
 * <b>Positional Arguments</b>
 *
 * With optional positional arguments +to+ and +by+,
 * their values (or defaults) determine the step and limit:
 *
 *   squares = []
 *   4.step(10, 2) {|i| squares.push(i*i) }    # => 4
 *   squares # => [16, 36, 64, 100]
 *   squares = []
 *   4.step(10) {|i| squares.push(i*i) }
 *   squares # => [16, 25, 36, 49, 64, 81, 100]
 *   squares = []
 *   4.step {|i| squares.push(i*i); break if i > 10 }  # => nil
 *   squares # => [16, 25, 36, 49, 64, 81, 100, 121]
 *
 * <b>Implementation Notes</b>
 *
 * If all the arguments are integers, the loop operates using an integer
 * counter.
 *
 * If any of the arguments are floating point numbers, all are converted
 * to floats, and the loop is executed
 * <i>floor(n + n*Float::EPSILON) + 1</i> times,
 * where <i>n = (limit - self)/step</i>.
 *
 */

static VALUE
num_step(int argc, VALUE *argv, VALUE from)
{
    VALUE to, step;
    int desc, inf;

    if (!rb_block_given_p()) {
        VALUE by = Qundef;

        num_step_extract_args(argc, argv, &to, &step, &by);
        if (!UNDEF_P(by)) {
            step = by;
        }
        if (NIL_P(step)) {
            step = INT2FIX(1);
        }
        else if (rb_equal(step, INT2FIX(0))) {
            rb_raise(rb_eArgError, "step can't be 0");
        }
        if ((NIL_P(to) || rb_obj_is_kind_of(to, rb_cNumeric)) &&
            rb_obj_is_kind_of(step, rb_cNumeric)) {
            return rb_arith_seq_new(from, ID2SYM(rb_frame_this_func()), argc, argv,
                                    num_step_size, from, to, step, FALSE);
        }

        return SIZED_ENUMERATOR_KW(from, 2, ((VALUE [2]){to, step}), num_step_size, FALSE);
    }

    desc = num_step_scan_args(argc, argv, &to, &step, TRUE, FALSE);
    if (rb_equal(step, INT2FIX(0))) {
        inf = 1;
    }
    else if (RB_FLOAT_TYPE_P(to)) {
        double f = RFLOAT_VALUE(to);
        inf = isinf(f) && (signbit(f) ? desc : !desc);
    }
    else inf = 0;

    if (FIXNUM_P(from) && (inf || FIXNUM_P(to)) && FIXNUM_P(step)) {
        long i = FIX2LONG(from);
        long diff = FIX2LONG(step);

        if (inf) {
            for (;; i += diff)
                rb_yield(LONG2FIX(i));
        }
        else {
            long end = FIX2LONG(to);

            if (desc) {
                for (; i >= end; i += diff)
                    rb_yield(LONG2FIX(i));
            }
            else {
                for (; i <= end; i += diff)
                    rb_yield(LONG2FIX(i));
            }
        }
    }
    else if (!ruby_float_step(from, to, step, FALSE, FALSE)) {
        VALUE i = from;

        if (inf) {
            for (;; i = rb_funcall(i, '+', 1, step))
                rb_yield(i);
        }
        else {
            ID cmp = desc ? '<' : '>';

            for (; !RTEST(rb_funcall(i, cmp, 1, to)); i = rb_funcall(i, '+', 1, step))
                rb_yield(i);
        }
    }
    return from;
}

static char *
out_of_range_float(char (*pbuf)[24], VALUE val)
{
    char *const buf = *pbuf;
    char *s;

    snprintf(buf, sizeof(*pbuf), "%-.10g", RFLOAT_VALUE(val));
    if ((s = strchr(buf, ' ')) != 0) *s = '\0';
    return buf;
}

#define FLOAT_OUT_OF_RANGE(val, type) do { \
    char buf[24]; \
    rb_raise(rb_eRangeError, "float %s out of range of "type, \
             out_of_range_float(&buf, (val))); \
} while (0)

#define LONG_MIN_MINUS_ONE ((double)LONG_MIN-1)
#define LONG_MAX_PLUS_ONE (2*(double)(LONG_MAX/2+1))
#define ULONG_MAX_PLUS_ONE (2*(double)(ULONG_MAX/2+1))
#define LONG_MIN_MINUS_ONE_IS_LESS_THAN(n) \
  (LONG_MIN_MINUS_ONE == (double)LONG_MIN ? \
   LONG_MIN <= (n): \
   LONG_MIN_MINUS_ONE < (n))

long
rb_num2long(VALUE val)
{
  again:
    if (NIL_P(val)) {
        rb_raise(rb_eTypeError, "no implicit conversion from nil to integer");
    }

    if (FIXNUM_P(val)) return FIX2LONG(val);

    else if (RB_FLOAT_TYPE_P(val)) {
        if (RFLOAT_VALUE(val) < LONG_MAX_PLUS_ONE
            && LONG_MIN_MINUS_ONE_IS_LESS_THAN(RFLOAT_VALUE(val))) {
            return (long)RFLOAT_VALUE(val);
        }
        else {
            FLOAT_OUT_OF_RANGE(val, "integer");
        }
    }
    else if (RB_BIGNUM_TYPE_P(val)) {
        return rb_big2long(val);
    }
    else {
        val = rb_to_int(val);
        goto again;
    }
}

static unsigned long
rb_num2ulong_internal(VALUE val, int *wrap_p)
{
  again:
    if (NIL_P(val)) {
       rb_raise(rb_eTypeError, "no implicit conversion of nil into Integer");
    }

    if (FIXNUM_P(val)) {
        long l = FIX2LONG(val); /* this is FIX2LONG, intended */
        if (wrap_p)
            *wrap_p = l < 0;
        return (unsigned long)l;
    }
    else if (RB_FLOAT_TYPE_P(val)) {
        double d = RFLOAT_VALUE(val);
        if (d < ULONG_MAX_PLUS_ONE && LONG_MIN_MINUS_ONE_IS_LESS_THAN(d)) {
            if (wrap_p)
                *wrap_p = d <= -1.0; /* NUM2ULONG(v) uses v.to_int conceptually.  */
            if (0 <= d)
                return (unsigned long)d;
            return (unsigned long)(long)d;
        }
        else {
            FLOAT_OUT_OF_RANGE(val, "integer");
        }
    }
    else if (RB_BIGNUM_TYPE_P(val)) {
        {
            unsigned long ul = rb_big2ulong(val);
            if (wrap_p)
                *wrap_p = BIGNUM_NEGATIVE_P(val);
            return ul;
        }
    }
    else {
        val = rb_to_int(val);
        goto again;
    }
}

unsigned long
rb_num2ulong(VALUE val)
{
    return rb_num2ulong_internal(val, NULL);
}

void
rb_out_of_int(SIGNED_VALUE num)
{
    rb_raise(rb_eRangeError, "integer %"PRIdVALUE " too %s to convert to 'int'",
             num, num < 0 ? "small" : "big");
}

#if SIZEOF_INT < SIZEOF_LONG
static void
check_int(long num)
{
    if ((long)(int)num != num) {
        rb_out_of_int(num);
    }
}

static void
check_uint(unsigned long num, int sign)
{
    if (sign) {
        /* minus */
        if (num < (unsigned long)INT_MIN)
            rb_raise(rb_eRangeError, "integer %ld too small to convert to 'unsigned int'", (long)num);
    }
    else {
        /* plus */
        if (UINT_MAX < num)
            rb_raise(rb_eRangeError, "integer %lu too big to convert to 'unsigned int'", num);
    }
}

long
rb_num2int(VALUE val)
{
    long num = rb_num2long(val);

    check_int(num);
    return num;
}

long
rb_fix2int(VALUE val)
{
    long num = FIXNUM_P(val)?FIX2LONG(val):rb_num2long(val);

    check_int(num);
    return num;
}

unsigned long
rb_num2uint(VALUE val)
{
    int wrap;
    unsigned long num = rb_num2ulong_internal(val, &wrap);

    check_uint(num, wrap);
    return num;
}

unsigned long
rb_fix2uint(VALUE val)
{
    unsigned long num;

    if (!FIXNUM_P(val)) {
        return rb_num2uint(val);
    }
    num = FIX2ULONG(val);

    check_uint(num, FIXNUM_NEGATIVE_P(val));
    return num;
}
#else
long
rb_num2int(VALUE val)
{
    return rb_num2long(val);
}

long
rb_fix2int(VALUE val)
{
    return FIX2INT(val);
}

unsigned long
rb_num2uint(VALUE val)
{
    return rb_num2ulong(val);
}

unsigned long
rb_fix2uint(VALUE val)
{
    return RB_FIX2ULONG(val);
}
#endif

NORETURN(static void rb_out_of_short(SIGNED_VALUE num));
static void
rb_out_of_short(SIGNED_VALUE num)
{
    rb_raise(rb_eRangeError, "integer %"PRIdVALUE " too %s to convert to 'short'",
             num, num < 0 ? "small" : "big");
}

static void
check_short(long num)
{
    if ((long)(short)num != num) {
        rb_out_of_short(num);
    }
}

static void
check_ushort(unsigned long num, int sign)
{
    if (sign) {
        /* minus */
        if (num < (unsigned long)SHRT_MIN)
            rb_raise(rb_eRangeError, "integer %ld too small to convert to 'unsigned short'", (long)num);
    }
    else {
        /* plus */
        if (USHRT_MAX < num)
            rb_raise(rb_eRangeError, "integer %lu too big to convert to 'unsigned short'", num);
    }
}

short
rb_num2short(VALUE val)
{
    long num = rb_num2long(val);

    check_short(num);
    return num;
}

short
rb_fix2short(VALUE val)
{
    long num = FIXNUM_P(val)?FIX2LONG(val):rb_num2long(val);

    check_short(num);
    return num;
}

unsigned short
rb_num2ushort(VALUE val)
{
    int wrap;
    unsigned long num = rb_num2ulong_internal(val, &wrap);

    check_ushort(num, wrap);
    return num;
}

unsigned short
rb_fix2ushort(VALUE val)
{
    unsigned long num;

    if (!FIXNUM_P(val)) {
        return rb_num2ushort(val);
    }
    num = FIX2ULONG(val);

    check_ushort(num, FIXNUM_NEGATIVE_P(val));
    return num;
}

VALUE
rb_num2fix(VALUE val)
{
    long v;

    if (FIXNUM_P(val)) return val;

    v = rb_num2long(val);
    if (!FIXABLE(v))
        rb_raise(rb_eRangeError, "integer %ld out of range of fixnum", v);
    return LONG2FIX(v);
}

#if HAVE_LONG_LONG

#define LLONG_MIN_MINUS_ONE ((double)LLONG_MIN-1)
#define LLONG_MAX_PLUS_ONE (2*(double)(LLONG_MAX/2+1))
#define ULLONG_MAX_PLUS_ONE (2*(double)(ULLONG_MAX/2+1))
#ifndef ULLONG_MAX
#define ULLONG_MAX ((unsigned LONG_LONG)LLONG_MAX*2+1)
#endif
#define LLONG_MIN_MINUS_ONE_IS_LESS_THAN(n) \
  (LLONG_MIN_MINUS_ONE == (double)LLONG_MIN ? \
   LLONG_MIN <= (n): \
   LLONG_MIN_MINUS_ONE < (n))

LONG_LONG
rb_num2ll(VALUE val)
{
    if (NIL_P(val)) {
        rb_raise(rb_eTypeError, "no implicit conversion from nil");
    }

    if (FIXNUM_P(val)) return (LONG_LONG)FIX2LONG(val);

    else if (RB_FLOAT_TYPE_P(val)) {
        double d = RFLOAT_VALUE(val);
        if (d < LLONG_MAX_PLUS_ONE && (LLONG_MIN_MINUS_ONE_IS_LESS_THAN(d))) {
            return (LONG_LONG)d;
        }
        else {
            FLOAT_OUT_OF_RANGE(val, "long long");
        }
    }
    else if (RB_BIGNUM_TYPE_P(val)) {
        return rb_big2ll(val);
    }
    else if (RB_TYPE_P(val, T_STRING)) {
        rb_raise(rb_eTypeError, "no implicit conversion from string");
    }
    else if (RB_TYPE_P(val, T_TRUE) || RB_TYPE_P(val, T_FALSE)) {
        rb_raise(rb_eTypeError, "no implicit conversion from boolean");
    }

    val = rb_to_int(val);
    return NUM2LL(val);
}

unsigned LONG_LONG
rb_num2ull(VALUE val)
{
    if (NIL_P(val)) {
        rb_raise(rb_eTypeError, "no implicit conversion of nil into Integer");
    }
    else if (FIXNUM_P(val)) {
        return (LONG_LONG)FIX2LONG(val); /* this is FIX2LONG, intended */
    }
    else if (RB_FLOAT_TYPE_P(val)) {
        double d = RFLOAT_VALUE(val);
        if (d < ULLONG_MAX_PLUS_ONE && LLONG_MIN_MINUS_ONE_IS_LESS_THAN(d)) {
            if (0 <= d)
                return (unsigned LONG_LONG)d;
            return (unsigned LONG_LONG)(LONG_LONG)d;
        }
        else {
            FLOAT_OUT_OF_RANGE(val, "unsigned long long");
        }
    }
    else if (RB_BIGNUM_TYPE_P(val)) {
        return rb_big2ull(val);
    }
    else {
        val = rb_to_int(val);
        return NUM2ULL(val);
    }
}

#endif  /* HAVE_LONG_LONG */

/********************************************************************
 *
 * Document-class: Integer
 *
 * An \Integer object represents an integer value.
 *
 * You can create an \Integer object explicitly with:
 *
 * - An {integer literal}[rdoc-ref:syntax/literals.rdoc@Integer+Literals].
 *
 * You can convert certain objects to Integers with:
 *
 * - \Method #Integer.
 *
 * An attempt to add a singleton method to an instance of this class
 * causes an exception to be raised.
 *
 * == What's Here
 *
 * First, what's elsewhere. \Class \Integer:
 *
 * - Inherits from
 *   {class Numeric}[rdoc-ref:Numeric@What-27s+Here]
 *   and {class Object}[rdoc-ref:Object@What-27s+Here].
 * - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
 *
 * Here, class \Integer provides methods for:
 *
 * - {Querying}[rdoc-ref:Integer@Querying]
 * - {Comparing}[rdoc-ref:Integer@Comparing]
 * - {Converting}[rdoc-ref:Integer@Converting]
 * - {Other}[rdoc-ref:Integer@Other]
 *
 * === Querying
 *
 * - #allbits?: Returns whether all bits in +self+ are set.
 * - #anybits?: Returns whether any bits in +self+ are set.
 * - #nobits?: Returns whether no bits in +self+ are set.
 *
 * === Comparing
 *
 * - #<: Returns whether +self+ is less than the given value.
 * - #<=: Returns whether +self+ is less than or equal to the given value.
 * - #<=>: Returns a number indicating whether +self+ is less than, equal
 *   to, or greater than the given value.
 * - #== (aliased as #===): Returns whether +self+ is equal to the given
 *                           value.
 * - #>: Returns whether +self+ is greater than the given value.
 * - #>=: Returns whether +self+ is greater than or equal to the given value.
 *
 * === Converting
 *
 * - ::sqrt: Returns the integer square root of the given value.
 * - ::try_convert: Returns the given value converted to an \Integer.
 * - #% (aliased as #modulo): Returns +self+ modulo the given value.
 * - #&: Returns the bitwise AND of +self+ and the given value.
 * - #*: Returns the product of +self+ and the given value.
 * - #**: Returns the value of +self+ raised to the power of the given value.
 * - #+: Returns the sum of +self+ and the given value.
 * - #-: Returns the difference of +self+ and the given value.
 * - #/: Returns the quotient of +self+ and the given value.
 * - #<<: Returns the value of +self+ after a leftward bit-shift.
 * - #>>: Returns the value of +self+ after a rightward bit-shift.
 * - #[]: Returns a slice of bits from +self+.
 * - #^: Returns the bitwise EXCLUSIVE OR of +self+ and the given value.
 * - #ceil: Returns the smallest number greater than or equal to +self+.
 * - #chr: Returns a 1-character string containing the character
 *   represented by the value of +self+.
 * - #digits: Returns an array of integers representing the base-radix digits
 *   of +self+.
 * - #div: Returns the integer result of dividing +self+ by the given value.
 * - #divmod: Returns a 2-element array containing the quotient and remainder
 *   results of dividing +self+ by the given value.
 * - #fdiv: Returns the Float result of dividing +self+ by the given value.
 * - #floor: Returns the greatest number smaller than or equal to +self+.
 * - #pow: Returns the modular exponentiation of +self+.
 * - #pred: Returns the integer predecessor of +self+.
 * - #remainder: Returns the remainder after dividing +self+ by the given value.
 * - #round: Returns +self+ rounded to the nearest value with the given precision.
 * - #succ (aliased as #next): Returns the integer successor of +self+.
 * - #to_f: Returns +self+ converted to a Float.
 * - #to_s (aliased as #inspect): Returns a string containing the place-value
 *   representation of +self+ in the given radix.
 * - #truncate: Returns +self+ truncated to the given precision.
 * - #|: Returns the bitwise OR of +self+ and the given value.
 *
 * === Other
 *
 * - #downto: Calls the given block with each integer value from +self+
 *   down to the given value.
 * - #times: Calls the given block +self+ times with each integer
 *   in <tt>(0..self-1)</tt>.
 * - #upto: Calls the given block with each integer value from +self+
 *   up to the given value.
 *
 */

VALUE
rb_int_odd_p(VALUE num)
{
    if (FIXNUM_P(num)) {
        return RBOOL(num & 2);
    }
    else {
        RUBY_ASSERT(RB_BIGNUM_TYPE_P(num));
        return rb_big_odd_p(num);
    }
}

static VALUE
int_even_p(VALUE num)
{
    if (FIXNUM_P(num)) {
        return RBOOL((num & 2) == 0);
    }
    else {
        RUBY_ASSERT(RB_BIGNUM_TYPE_P(num));
        return rb_big_even_p(num);
    }
}

VALUE
rb_int_even_p(VALUE num)
{
    return int_even_p(num);
}

/*
 *  call-seq:
 *    allbits?(mask) -> true or false
 *
 *  Returns +true+ if all bits that are set (=1) in +mask+
 *  are also set in +self+; returns +false+ otherwise.
 *
 *  Example values:
 *
 *    0b1010101  self
 *    0b1010100  mask
 *    0b1010100  self & mask
 *         true  self.allbits?(mask)
 *
 *    0b1010100  self
 *    0b1010101  mask
 *    0b1010100  self & mask
 *        false  self.allbits?(mask)
 *
 *  Related: Integer#anybits?, Integer#nobits?.
 *
 */

static VALUE
int_allbits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return rb_int_equal(rb_int_and(num, mask), mask);
}

/*
 *  call-seq:
 *    anybits?(mask) -> true or false
 *
 *  Returns +true+ if any bit that is set (=1) in +mask+
 *  is also set in +self+; returns +false+ otherwise.
 *
 *  Example values:
 *
 *    0b10000010  self
 *    0b11111111  mask
 *    0b10000010  self & mask
 *          true  self.anybits?(mask)
 *
 *    0b00000000  self
 *    0b11111111  mask
 *    0b00000000  self & mask
 *         false  self.anybits?(mask)
 *
 *  Related: Integer#allbits?, Integer#nobits?.
 *
 */

static VALUE
int_anybits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return RBOOL(!int_zero_p(rb_int_and(num, mask)));
}

/*
 *  call-seq:
 *    nobits?(mask) -> true or false
 *
 *  Returns +true+ if no bit that is set (=1) in +mask+
 *  is also set in +self+; returns +false+ otherwise.
 *
 *  Example values:
 *
 *    0b11110000  self
 *    0b00001111  mask
 *    0b00000000  self & mask
 *          true  self.nobits?(mask)
 *
 *    0b00000001  self
 *    0b11111111  mask
 *    0b00000001  self & mask
 *         false  self.nobits?(mask)
 *
 *  Related: Integer#allbits?, Integer#anybits?.
 *
 */

static VALUE
int_nobits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return RBOOL(int_zero_p(rb_int_and(num, mask)));
}

/*
 *  call-seq:
 *    succ -> next_integer
 *
 *  Returns the successor integer of +self+ (equivalent to <tt>self + 1</tt>):
 *
 *    1.succ  #=> 2
 *    -1.succ #=> 0
 *
 *  Related: Integer#pred (predecessor value).
 */

VALUE
rb_int_succ(VALUE num)
{
    if (FIXNUM_P(num)) {
        long i = FIX2LONG(num) + 1;
        return LONG2NUM(i);
    }
    if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_plus(num, INT2FIX(1));
    }
    return num_funcall1(num, '+', INT2FIX(1));
}

#define int_succ rb_int_succ

/*
 *  call-seq:
 *    pred -> next_integer
 *
 *  Returns the predecessor of +self+ (equivalent to <tt>self - 1</tt>):
 *
 *    1.pred  #=> 0
 *    -1.pred #=> -2
 *
 *  Related: Integer#succ (successor value).
 *
 */

static VALUE
rb_int_pred(VALUE num)
{
    if (FIXNUM_P(num)) {
        long i = FIX2LONG(num) - 1;
        return LONG2NUM(i);
    }
    if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_minus(num, INT2FIX(1));
    }
    return num_funcall1(num, '-', INT2FIX(1));
}

#define int_pred rb_int_pred

VALUE
rb_enc_uint_chr(unsigned int code, rb_encoding *enc)
{
    int n;
    VALUE str;
    switch (n = rb_enc_codelen(code, enc)) {
      case ONIGERR_INVALID_CODE_POINT_VALUE:
        rb_raise(rb_eRangeError, "invalid codepoint 0x%X in %s", code, rb_enc_name(enc));
        break;
      case ONIGERR_TOO_BIG_WIDE_CHAR_VALUE:
      case 0:
        rb_raise(rb_eRangeError, "%u out of char range", code);
        break;
    }
    str = rb_enc_str_new(0, n, enc);
    rb_enc_mbcput(code, RSTRING_PTR(str), enc);
    if (rb_enc_precise_mbclen(RSTRING_PTR(str), RSTRING_END(str), enc) != n) {
        rb_raise(rb_eRangeError, "invalid codepoint 0x%X in %s", code, rb_enc_name(enc));
    }
    return str;
}

/*  call-seq:
 *   chr           -> string
 *   chr(encoding) -> string
 *
 *  Returns a 1-character string containing the character
 *  represented by the value of +self+, according to the given +encoding+.
 *
 *    65.chr                   # => "A"
 *    0.chr                    # => "\x00"
 *    255.chr                  # => "\xFF"
 *    string = 255.chr(Encoding::UTF_8)
 *    string.encoding          # => Encoding::UTF_8
 *
 *  Raises an exception if +self+ is negative.
 *
 *  Related: Integer#ord.
 *
 */

static VALUE
int_chr(int argc, VALUE *argv, VALUE num)
{
    char c;
    unsigned int i;
    rb_encoding *enc;

    if (rb_num_to_uint(num, &i) == 0) {
    }
    else if (FIXNUM_P(num)) {
        rb_raise(rb_eRangeError, "%ld out of char range", FIX2LONG(num));
    }
    else {
        rb_raise(rb_eRangeError, "bignum out of char range");
    }

    switch (argc) {
      case 0:
        if (0xff < i) {
            enc = rb_default_internal_encoding();
            if (!enc) {
                rb_raise(rb_eRangeError, "%u out of char range", i);
            }
            goto decode;
        }
        c = (char)i;
        if (i < 0x80) {
            return rb_usascii_str_new(&c, 1);
        }
        else {
            return rb_str_new(&c, 1);
        }
      case 1:
        break;
      default:
        rb_error_arity(argc, 0, 1);
    }
    enc = rb_to_encoding(argv[0]);
    if (!enc) enc = rb_ascii8bit_encoding();
  decode:
    return rb_enc_uint_chr(i, enc);
}

/*
 * Fixnum
 */

static VALUE
fix_uminus(VALUE num)
{
    return LONG2NUM(-FIX2LONG(num));
}

VALUE
rb_int_uminus(VALUE num)
{
    if (FIXNUM_P(num)) {
        return fix_uminus(num);
    }
    else {
        RUBY_ASSERT(RB_BIGNUM_TYPE_P(num));
        return rb_big_uminus(num);
    }
}

VALUE
rb_fix2str(VALUE x, int base)
{
    char buf[SIZEOF_VALUE*CHAR_BIT + 1], *const e = buf + sizeof buf, *b = e;
    long val = FIX2LONG(x);
    unsigned long u;
    int neg = 0;

    if (base < 2 || 36 < base) {
        rb_raise(rb_eArgError, "invalid radix %d", base);
    }
#if SIZEOF_LONG < SIZEOF_VOIDP
# if SIZEOF_VOIDP == SIZEOF_LONG_LONG
    if ((val >= 0 && (x & 0xFFFFFFFF00000000ull)) ||
        (val < 0 && (x & 0xFFFFFFFF00000000ull) != 0xFFFFFFFF00000000ull)) {
        rb_bug("Unnormalized Fixnum value %p", (void *)x);
    }
# else
    /* should do something like above code, but currently ruby does not know */
    /* such platforms */
# endif
#endif
    if (val == 0) {
        return rb_usascii_str_new2("0");
    }
    if (val < 0) {
        u = 1 + (unsigned long)(-(val + 1)); /* u = -val avoiding overflow */
        neg = 1;
    }
    else {
        u = val;
    }
    do {
        *--b = ruby_digitmap[(int)(u % base)];
    } while (u /= base);
    if (neg) {
        *--b = '-';
    }

    return rb_usascii_str_new(b, e - b);
}

static VALUE rb_fix_to_s_static[10];

VALUE
rb_fix_to_s(VALUE x)
{
    long i = FIX2LONG(x);
    if (i >= 0 && i < 10) {
        return rb_fix_to_s_static[i];
    }
    return rb_fix2str(x, 10);
}

/*
 *  call-seq:
 *    to_s(base = 10)  ->  string
 *
 *  Returns a string containing the place-value representation of +self+
 *  in radix +base+ (in 2..36).
 *
 *    12345.to_s               # => "12345"
 *    12345.to_s(2)            # => "11000000111001"
 *    12345.to_s(8)            # => "30071"
 *    12345.to_s(10)           # => "12345"
 *    12345.to_s(16)           # => "3039"
 *    12345.to_s(36)           # => "9ix"
 *    78546939656932.to_s(36)  # => "rubyrules"
 *
 *  Raises an exception if +base+ is out of range.
 */

VALUE
rb_int_to_s(int argc, VALUE *argv, VALUE x)
{
    int base;

    if (rb_check_arity(argc, 0, 1))
        base = NUM2INT(argv[0]);
    else
        base = 10;
    return rb_int2str(x, base);
}

VALUE
rb_int2str(VALUE x, int base)
{
    if (FIXNUM_P(x)) {
        return rb_fix2str(x, base);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big2str(x, base);
    }

    return rb_any_to_s(x);
}

static VALUE
fix_plus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return rb_fix_plus_fix(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_plus(y, x);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM((double)FIX2LONG(x) + RFLOAT_VALUE(y));
    }
    else if (RB_TYPE_P(y, T_COMPLEX)) {
        return rb_complex_plus(y, x);
    }
    else {
        return rb_num_coerce_bin(x, y, '+');
    }
}

VALUE
rb_fix_plus(VALUE x, VALUE y)
{
    return fix_plus(x, y);
}

/*
 *  call-seq:
 *    self + numeric -> numeric_result
 *
 *  Performs addition:
 *
 *    2 + 2              # => 4
 *    -2 + 2             # => 0
 *    -2 + -2            # => -4
 *    2 + 2.0            # => 4.0
 *    2 + Rational(2, 1) # => (4/1)
 *    2 + Complex(2, 0)  # => (4+0i)
 *
 */

VALUE
rb_int_plus(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_plus(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_plus(x, y);
    }
    return rb_num_coerce_bin(x, y, '+');
}

static VALUE
fix_minus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return rb_fix_minus_fix(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        x = rb_int2big(FIX2LONG(x));
        return rb_big_minus(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM((double)FIX2LONG(x) - RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '-');
    }
}

/*
 *  call-seq:
 *    self - numeric -> numeric_result
 *
 *  Performs subtraction:
 *
 *    4 - 2              # => 2
 *    -4 - 2             # => -6
 *    -4 - -2            # => -2
 *    4 - 2.0            # => 2.0
 *    4 - Rational(2, 1) # => (2/1)
 *    4 - Complex(2, 0)  # => (2+0i)
 *
 */

VALUE
rb_int_minus(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_minus(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_minus(x, y);
    }
    return rb_num_coerce_bin(x, y, '-');
}


#define SQRT_LONG_MAX HALF_LONG_MSB
/*tests if N*N would overflow*/
#define FIT_SQRT_LONG(n) (((n)<SQRT_LONG_MAX)&&((n)>=-SQRT_LONG_MAX))

static VALUE
fix_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return rb_fix_mul_fix(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        switch (x) {
          case INT2FIX(0): return x;
          case INT2FIX(1): return y;
        }
        return rb_big_mul(y, x);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM((double)FIX2LONG(x) * RFLOAT_VALUE(y));
    }
    else if (RB_TYPE_P(y, T_COMPLEX)) {
        return rb_complex_mul(y, x);
    }
    else {
        return rb_num_coerce_bin(x, y, '*');
    }
}

/*
 *  call-seq:
 *    self * numeric -> numeric_result
 *
 *  Performs multiplication:
 *
 *    4 * 2              # => 8
 *    4 * -2             # => -8
 *    -4 * 2             # => -8
 *    4 * 2.0            # => 8.0
 *    4 * Rational(1, 3) # => (4/3)
 *    4 * Complex(2, 0)  # => (8+0i)
 */

VALUE
rb_int_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_mul(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_mul(x, y);
    }
    return rb_num_coerce_bin(x, y, '*');
}

static double
fix_fdiv_double(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        long iy = FIX2LONG(y);
#if SIZEOF_LONG * CHAR_BIT > DBL_MANT_DIG
        if ((iy < 0 ? -iy : iy) >= (1L << DBL_MANT_DIG)) {
            return rb_big_fdiv_double(rb_int2big(FIX2LONG(x)), rb_int2big(iy));
        }
#endif
        return double_div_double(FIX2LONG(x), iy);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_fdiv_double(rb_int2big(FIX2LONG(x)), y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return double_div_double(FIX2LONG(x), RFLOAT_VALUE(y));
    }
    else {
        return NUM2DBL(rb_num_coerce_bin(x, y, idFdiv));
    }
}

double
rb_int_fdiv_double(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(y) && !FIXNUM_ZERO_P(y)) {
        VALUE gcd = rb_gcd(x, y);
        if (!FIXNUM_ZERO_P(gcd) && gcd != INT2FIX(1)) {
            x = rb_int_idiv(x, gcd);
            y = rb_int_idiv(y, gcd);
        }
    }
    if (FIXNUM_P(x)) {
        return fix_fdiv_double(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_fdiv_double(x, y);
    }
    else {
        return nan("");
    }
}

/*
 *  call-seq:
 *    fdiv(numeric) -> float
 *
 *  Returns the Float result of dividing +self+ by +numeric+:
 *
 *    4.fdiv(2)      # => 2.0
 *    4.fdiv(-2)      # => -2.0
 *    -4.fdiv(2)      # => -2.0
 *    4.fdiv(2.0)      # => 2.0
 *    4.fdiv(Rational(3, 4))      # => 5.333333333333333
 *
 *  Raises an exception if +numeric+ cannot be converted to a Float.
 *
 */

VALUE
rb_int_fdiv(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return DBL2NUM(rb_int_fdiv_double(x, y));
    }
    return Qnil;
}

static VALUE
fix_divide(VALUE x, VALUE y, ID op)
{
    if (FIXNUM_P(y)) {
        if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
        return rb_fix_div_fix(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        x = rb_int2big(FIX2LONG(x));
        return rb_big_div(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
            if (op == '/') {
                double d = FIX2LONG(x);
                return rb_flo_div_flo(DBL2NUM(d), y);
            }
            else {
                VALUE v;
                if (RFLOAT_VALUE(y) == 0) rb_num_zerodiv();
                v = fix_divide(x, y, '/');
                return flo_floor(0, 0, v);
            }
    }
    else {
        if (RB_TYPE_P(y, T_RATIONAL) &&
            op == '/' && FIX2LONG(x) == 1)
            return rb_rational_reciprocal(y);
        return rb_num_coerce_bin(x, y, op);
    }
}

static VALUE
fix_div(VALUE x, VALUE y)
{
    return fix_divide(x, y, '/');
}

/*
 * call-seq:
 *   self / numeric -> numeric_result
 *
 * Performs division; for integer +numeric+, truncates the result to an integer:
 *
 *   4 / 3              # => 1
 *   4 / -3             # => -2
 *   -4 / 3             # => -2
 *   -4 / -3            # => 1
 *
 *  For other +numeric+, returns non-integer result:
 *
 *   4 / 3.0            # => 1.3333333333333333
 *   4 / Rational(3, 1) # => (4/3)
 *   4 / Complex(3, 0)  # => ((4/3)+0i)
 *
 */

VALUE
rb_int_div(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_div(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_div(x, y);
    }
    return Qnil;
}

static VALUE
fix_idiv(VALUE x, VALUE y)
{
    return fix_divide(x, y, id_div);
}

/*
 *  call-seq:
 *    div(numeric)  -> integer
 *
 * Performs integer division; returns the integer result of dividing +self+
 * by +numeric+:
 *
 *    4.div(3)              # => 1
 *    4.div(-3)             # => -2
 *    -4.div(3)             # => -2
 *    -4.div(-3)            # => 1
 *    4.div(3.0)            # => 1
 *    4.div(Rational(3, 1)) # => 1
 *
 * Raises an exception if +numeric+ does not have method +div+.
 *
 */

VALUE
rb_int_idiv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_idiv(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_idiv(x, y);
    }
    return num_div(x, y);
}

static VALUE
fix_mod(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
        return rb_fix_mod_fix(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        x = rb_int2big(FIX2LONG(x));
        return rb_big_modulo(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(ruby_float_mod((double)FIX2LONG(x), RFLOAT_VALUE(y)));
    }
    else {
        return rb_num_coerce_bin(x, y, '%');
    }
}

/*
 *  call-seq:
 *    self % other -> real_number
 *
 *  Returns +self+ modulo +other+ as a real number.
 *
 *  For integer +n+ and real number +r+, these expressions are equivalent:
 *
 *    n % r
 *    n-r*(n/r).floor
 *    n.divmod(r)[1]
 *
 *  See Numeric#divmod.
 *
 *  Examples:
 *
 *    10 % 2              # => 0
 *    10 % 3              # => 1
 *    10 % 4              # => 2
 *
 *    10 % -2             # => 0
 *    10 % -3             # => -2
 *    10 % -4             # => -2
 *
 *    10 % 3.0            # => 1.0
 *    10 % Rational(3, 1) # => (1/1)
 *
 */
VALUE
rb_int_modulo(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_mod(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_modulo(x, y);
    }
    return num_modulo(x, y);
}

/*
 *  call-seq:
 *    remainder(other) -> real_number
 *
 *  Returns the remainder after dividing +self+ by +other+.
 *
 *  Examples:
 *
 *    11.remainder(4)              # => 3
 *    11.remainder(-4)             # => 3
 *    -11.remainder(4)             # => -3
 *    -11.remainder(-4)            # => -3
 *
 *    12.remainder(4)              # => 0
 *    12.remainder(-4)             # => 0
 *    -12.remainder(4)             # => 0
 *    -12.remainder(-4)            # => 0
 *
 *    13.remainder(4.0)            # => 1.0
 *    13.remainder(Rational(4, 1)) # => (1/1)
 *
 */

static VALUE
int_remainder(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        if (FIXNUM_P(y)) {
            VALUE z = fix_mod(x, y);
            RUBY_ASSERT(FIXNUM_P(z));
            if (z != INT2FIX(0) && (SIGNED_VALUE)(x ^ y) < 0)
                z = fix_minus(z, y);
            return z;
        }
        else if (!RB_BIGNUM_TYPE_P(y)) {
            return num_remainder(x, y);
        }
        x = rb_int2big(FIX2LONG(x));
    }
    else if (!RB_BIGNUM_TYPE_P(x)) {
        return Qnil;
    }
    return rb_big_remainder(x, y);
}

static VALUE
fix_divmod(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        VALUE div, mod;
        if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
        rb_fix_divmod_fix(x, y, &div, &mod);
        return rb_assoc_new(div, mod);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        x = rb_int2big(FIX2LONG(x));
        return rb_big_divmod(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        {
            double div, mod;
            volatile VALUE a, b;

            flodivmod((double)FIX2LONG(x), RFLOAT_VALUE(y), &div, &mod);
            a = dbl2ival(div);
            b = DBL2NUM(mod);
            return rb_assoc_new(a, b);
        }
    }
    else {
        return rb_num_coerce_bin(x, y, id_divmod);
    }
}

/*
 *  call-seq:
 *    divmod(other) -> array
 *
 *  Returns a 2-element array <tt>[q, r]</tt>, where
 *
 *    q = (self/other).floor    # Quotient
 *    r = self % other          # Remainder
 *
 *  Examples:
 *
 *    11.divmod(4)              # => [2, 3]
 *    11.divmod(-4)             # => [-3, -1]
 *    -11.divmod(4)             # => [-3, 1]
 *    -11.divmod(-4)            # => [2, -3]
 *
 *    12.divmod(4)              # => [3, 0]
 *    12.divmod(-4)             # => [-3, 0]
 *    -12.divmod(4)             # => [-3, 0]
 *    -12.divmod(-4)            # => [3, 0]
 *
 *    13.divmod(4.0)            # => [3, 1.0]
 *    13.divmod(Rational(4, 1)) # => [3, (1/1)]
 *
 */
VALUE
rb_int_divmod(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_divmod(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_divmod(x, y);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    self ** numeric -> numeric_result
 *
 *  Raises +self+ to the power of +numeric+:
 *
 *    2 ** 3              # => 8
 *    2 ** -3             # => (1/8)
 *    -2 ** 3             # => -8
 *    -2 ** -3            # => (-1/8)
 *    2 ** 3.3            # => 9.849155306759329
 *    2 ** Rational(3, 1) # => (8/1)
 *    2 ** Complex(3, 0)  # => (8+0i)
 *
 */

static VALUE
int_pow(long x, unsigned long y)
{
    int neg = x < 0;
    long z = 1;

    if (y == 0) return INT2FIX(1);
    if (y == 1) return LONG2NUM(x);
    if (neg) x = -x;
    if (y & 1)
        z = x;
    else
        neg = 0;
    y &= ~1;
    do {
        while (y % 2 == 0) {
            if (!FIT_SQRT_LONG(x)) {
                goto bignum;
            }
            x = x * x;
            y >>= 1;
        }
        {
            if (MUL_OVERFLOW_FIXNUM_P(x, z)) {
                goto bignum;
            }
            z = x * z;
        }
    } while (--y);
    if (neg) z = -z;
    return LONG2NUM(z);

    VALUE v;
  bignum:
    v = rb_big_pow(rb_int2big(x), LONG2NUM(y));
    if (RB_FLOAT_TYPE_P(v)) /* infinity due to overflow */
        return v;
    if (z != 1) v = rb_big_mul(rb_int2big(neg ? -z : z), v);
    return v;
}

VALUE
rb_int_positive_pow(long x, unsigned long y)
{
    return int_pow(x, y);
}

static VALUE
fix_pow_inverted(VALUE x, VALUE minusb)
{
    if (x == INT2FIX(0)) {
        rb_num_zerodiv();
        UNREACHABLE_RETURN(Qundef);
    }
    else {
        VALUE y = rb_int_pow(x, minusb);

        if (RB_FLOAT_TYPE_P(y)) {
            double d = pow((double)FIX2LONG(x), RFLOAT_VALUE(y));
            return DBL2NUM(1.0 / d);
        }
        else {
            return rb_rational_raw(INT2FIX(1), y);
        }
    }
}

static VALUE
fix_pow(VALUE x, VALUE y)
{
    long a = FIX2LONG(x);

    if (FIXNUM_P(y)) {
        long b = FIX2LONG(y);

        if (a == 1) return INT2FIX(1);
        if (a == -1) return INT2FIX(b % 2 ? -1 : 1);
        if (b <  0) return fix_pow_inverted(x, fix_uminus(y));
        if (b == 0) return INT2FIX(1);
        if (b == 1) return x;
        if (a == 0) return INT2FIX(0);
        return int_pow(a, b);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        if (a == 1) return INT2FIX(1);
        if (a == -1) return INT2FIX(int_even_p(y) ? 1 : -1);
        if (BIGNUM_NEGATIVE_P(y)) return fix_pow_inverted(x, rb_big_uminus(y));
        if (a == 0) return INT2FIX(0);
        x = rb_int2big(FIX2LONG(x));
        return rb_big_pow(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        double dy = RFLOAT_VALUE(y);
        if (dy == 0.0) return DBL2NUM(1.0);
        if (a == 0) {
            return DBL2NUM(dy < 0 ? HUGE_VAL : 0.0);
        }
        if (a == 1) return DBL2NUM(1.0);
        if (a < 0 && dy != round(dy))
            return rb_dbl_complex_new_polar_pi(pow(-(double)a, dy), dy);
        return DBL2NUM(pow((double)a, dy));
    }
    else {
        return rb_num_coerce_bin(x, y, idPow);
    }
}

/*
 *  call-seq:
 *    self ** numeric -> numeric_result
 *
 *  Raises +self+ to the power of +numeric+:
 *
 *    2 ** 3              # => 8
 *    2 ** -3             # => (1/8)
 *    -2 ** 3             # => -8
 *    -2 ** -3            # => (-1/8)
 *    2 ** 3.3            # => 9.849155306759329
 *    2 ** Rational(3, 1) # => (8/1)
 *    2 ** Complex(3, 0)  # => (8+0i)
 *
 */
VALUE
rb_int_pow(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_pow(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_pow(x, y);
    }
    return Qnil;
}

VALUE
rb_num_pow(VALUE x, VALUE y)
{
    VALUE z = rb_int_pow(x, y);
    if (!NIL_P(z)) return z;
    if (RB_FLOAT_TYPE_P(x)) return rb_float_pow(x, y);
    if (SPECIAL_CONST_P(x)) return Qnil;
    switch (BUILTIN_TYPE(x)) {
      case T_COMPLEX:
        return rb_complex_pow(x, y);
      case T_RATIONAL:
        return rb_rational_pow(x, y);
      default:
        break;
    }
    return Qnil;
}

static VALUE
fix_equal(VALUE x, VALUE y)
{
    if (x == y) return Qtrue;
    if (FIXNUM_P(y)) return Qfalse;
    else if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_eq(y, x);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return rb_integer_float_eq(x, y);
    }
    else {
        return num_equal(x, y);
    }
}

/*
 *  call-seq:
 *    self == other -> true or false
 *
 *  Returns +true+ if +self+ is numerically equal to +other+; +false+ otherwise.
 *
 *    1 == 2     #=> false
 *    1 == 1.0   #=> true
 *
 *  Related: Integer#eql? (requires +other+ to be an \Integer).
 */

VALUE
rb_int_equal(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_equal(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_eq(x, y);
    }
    return Qnil;
}

static VALUE
fix_cmp(VALUE x, VALUE y)
{
    if (x == y) return INT2FIX(0);
    if (FIXNUM_P(y)) {
        if (FIX2LONG(x) > FIX2LONG(y)) return INT2FIX(1);
        return INT2FIX(-1);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        VALUE cmp = rb_big_cmp(y, x);
        switch (cmp) {
          case INT2FIX(+1): return INT2FIX(-1);
          case INT2FIX(-1): return INT2FIX(+1);
        }
        return cmp;
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return rb_integer_float_cmp(x, y);
    }
    else {
        return rb_num_coerce_cmp(x, y, id_cmp);
    }
}

/*
 *  call-seq:
 *    self <=> other  ->  -1, 0, +1, or nil
 *
 *  Returns:
 *
 *  - -1, if +self+ is less than +other+.
 *  - 0, if +self+ is equal to +other+.
 *  - 1, if +self+ is greater then +other+.
 *  - +nil+, if +self+ and +other+ are incomparable.
 *
 *  Examples:
 *
 *    1 <=> 2              # => -1
 *    1 <=> 1              # => 0
 *    1 <=> 0              # => 1
 *    1 <=> 'foo'          # => nil
 *
 *    1 <=> 1.0            # => 0
 *    1 <=> Rational(1, 1) # => 0
 *    1 <=> Complex(1, 0)  # => 0
 *
 *  This method is the basis for comparisons in module Comparable.
 *
 */

VALUE
rb_int_cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_cmp(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_cmp(x, y);
    }
    else {
        rb_raise(rb_eNotImpError, "need to define '<=>' in %s", rb_obj_classname(x));
    }
}

static VALUE
fix_gt(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return RBOOL(FIX2LONG(x) > FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return RBOOL(rb_big_cmp(y, x) == INT2FIX(-1));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return RBOOL(rb_integer_float_cmp(x, y) == INT2FIX(1));
    }
    else {
        return rb_num_coerce_relop(x, y, '>');
    }
}

/*
 *  call-seq:
 *    self > other -> true or false
 *
 * Returns +true+ if the value of +self+ is greater than that of +other+:
 *
 *    1 > 0              # => true
 *    1 > 1              # => false
 *    1 > 2              # => false
 *    1 > 0.5            # => true
 *    1 > Rational(1, 2) # => true
 *
 *  Raises an exception if the comparison cannot be made.
 *
 */

VALUE
rb_int_gt(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_gt(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_gt(x, y);
    }
    return Qnil;
}

static VALUE
fix_ge(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return RBOOL(FIX2LONG(x) >= FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return RBOOL(rb_big_cmp(y, x) != INT2FIX(+1));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(x, y);
        return RBOOL(rel == INT2FIX(1) || rel == INT2FIX(0));
    }
    else {
        return rb_num_coerce_relop(x, y, idGE);
    }
}

/*
 *  call-seq:
 *    self >= real -> true or false
 *
 *  Returns +true+ if the value of +self+ is greater than or equal to
 *  that of +other+:
 *
 *    1 >= 0              # => true
 *    1 >= 1              # => true
 *    1 >= 2              # => false
 *    1 >= 0.5            # => true
 *    1 >= Rational(1, 2) # => true
 *
 *  Raises an exception if the comparison cannot be made.
 *
 */

VALUE
rb_int_ge(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_ge(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_ge(x, y);
    }
    return Qnil;
}

static VALUE
fix_lt(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return RBOOL(FIX2LONG(x) < FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return RBOOL(rb_big_cmp(y, x) == INT2FIX(+1));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return RBOOL(rb_integer_float_cmp(x, y) == INT2FIX(-1));
    }
    else {
        return rb_num_coerce_relop(x, y, '<');
    }
}

/*
 * call-seq:
 *    self < other -> true or false
 *
 * Returns +true+ if the value of +self+ is less than that of +other+:
 *
 *    1 < 0              # => false
 *    1 < 1              # => false
 *    1 < 2              # => true
 *    1 < 0.5            # => false
 *    1 < Rational(1, 2) # => false
 *
 *  Raises an exception if the comparison cannot be made.
 *
 */

static VALUE
int_lt(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_lt(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_lt(x, y);
    }
    return Qnil;
}

static VALUE
fix_le(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return RBOOL(FIX2LONG(x) <= FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return RBOOL(rb_big_cmp(y, x) != INT2FIX(-1));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        VALUE rel = rb_integer_float_cmp(x, y);
        return RBOOL(rel == INT2FIX(-1) || rel == INT2FIX(0));
    }
    else {
        return rb_num_coerce_relop(x, y, idLE);
    }
}

/*
 * call-seq:
 *    self <= real -> true or false
 *
 *  Returns +true+ if the value of +self+ is less than or equal to
 *  that of +other+:
 *
 *    1 <= 0              # => false
 *    1 <= 1              # => true
 *    1 <= 2              # => true
 *    1 <= 0.5            # => false
 *    1 <= Rational(1, 2) # => false
 *
 *  Raises an exception if the comparison cannot be made.
 *
 */

static VALUE
int_le(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_le(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_le(x, y);
    }
    return Qnil;
}

static VALUE
fix_comp(VALUE num)
{
    return ~num | FIXNUM_FLAG;
}

VALUE
rb_int_comp(VALUE num)
{
    if (FIXNUM_P(num)) {
        return fix_comp(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_comp(num);
    }
    return Qnil;
}

static VALUE
num_funcall_bit_1(VALUE y, VALUE arg, int recursive)
{
    ID func = (ID)((VALUE *)arg)[0];
    VALUE x = ((VALUE *)arg)[1];
    if (recursive) {
        num_funcall_op_1_recursion(x, func, y);
    }
    return rb_check_funcall(x, func, 1, &y);
}

VALUE
rb_num_coerce_bit(VALUE x, VALUE y, ID func)
{
    VALUE ret, args[3];

    args[0] = (VALUE)func;
    args[1] = x;
    args[2] = y;
    do_coerce(&args[1], &args[2], TRUE);
    ret = rb_exec_recursive_paired(num_funcall_bit_1,
                                   args[2], args[1], (VALUE)args);
    if (UNDEF_P(ret)) {
        /* show the original object, not coerced object */
        coerce_failed(x, y);
    }
    return ret;
}

static VALUE
fix_and(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        long val = FIX2LONG(x) & FIX2LONG(y);
        return LONG2NUM(val);
    }

    if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_and(y, x);
    }

    return rb_num_coerce_bit(x, y, '&');
}

/*
 *  call-seq:
 *    self & other ->  integer
 *
 *  Bitwise AND; each bit in the result is 1 if both corresponding bits
 *  in +self+ and +other+ are 1, 0 otherwise:
 *
 *    "%04b" % (0b0101 & 0b0110) # => "0100"
 *
 *  Raises an exception if +other+ is not an \Integer.
 *
 *  Related: Integer#| (bitwise OR), Integer#^ (bitwise EXCLUSIVE OR).
 *
 */

VALUE
rb_int_and(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_and(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_and(x, y);
    }
    return Qnil;
}

static VALUE
fix_or(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        long val = FIX2LONG(x) | FIX2LONG(y);
        return LONG2NUM(val);
    }

    if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_or(y, x);
    }

    return rb_num_coerce_bit(x, y, '|');
}

/*
 *  call-seq:
 *   self | other -> integer
 *
 *  Bitwise OR; each bit in the result is 1 if either corresponding bit
 *  in +self+ or +other+ is 1, 0 otherwise:
 *
 *    "%04b" % (0b0101 | 0b0110) # => "0111"
 *
 *  Raises an exception if +other+ is not an \Integer.
 *
 *  Related: Integer#& (bitwise AND), Integer#^ (bitwise EXCLUSIVE OR).
 *
 */

static VALUE
int_or(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_or(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_or(x, y);
    }
    return Qnil;
}

static VALUE
fix_xor(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        long val = FIX2LONG(x) ^ FIX2LONG(y);
        return LONG2NUM(val);
    }

    if (RB_BIGNUM_TYPE_P(y)) {
        return rb_big_xor(y, x);
    }

    return rb_num_coerce_bit(x, y, '^');
}

/*
 *  call-seq:
 *    self ^ other -> integer
 *
 *  Bitwise EXCLUSIVE OR; each bit in the result is 1 if the corresponding bits
 *  in +self+ and +other+ are different, 0 otherwise:
 *
 *    "%04b" % (0b0101 ^ 0b0110) # => "0011"
 *
 *  Raises an exception if +other+ is not an \Integer.
 *
 *  Related: Integer#& (bitwise AND), Integer#| (bitwise OR).
 *
 */

static VALUE
int_xor(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return fix_xor(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_xor(x, y);
    }
    return Qnil;
}

static VALUE
rb_fix_lshift(VALUE x, VALUE y)
{
    long val, width;

    val = NUM2LONG(x);
    if (!val) return (rb_to_int(y), INT2FIX(0));
    if (!FIXNUM_P(y))
        return rb_big_lshift(rb_int2big(val), y);
    width = FIX2LONG(y);
    if (width < 0)
        return fix_rshift(val, (unsigned long)-width);
    return fix_lshift(val, width);
}

static VALUE
fix_lshift(long val, unsigned long width)
{
    if (width > (SIZEOF_LONG*CHAR_BIT-1)
        || ((unsigned long)val)>>(SIZEOF_LONG*CHAR_BIT-1-width) > 0) {
        return rb_big_lshift(rb_int2big(val), ULONG2NUM(width));
    }
    val = val << width;
    return LONG2NUM(val);
}

/*
 *  call-seq:
 *    self << count -> integer
 *
 *  Returns +self+ with bits shifted +count+ positions to the left,
 *  or to the right if +count+ is negative:
 *
 *    n = 0b11110000
 *    "%08b" % (n << 1)  # => "111100000"
 *    "%08b" % (n << 3)  # => "11110000000"
 *    "%08b" % (n << -1) # => "01111000"
 *    "%08b" % (n << -3) # => "00011110"
 *
 *  Related: Integer#>>.
 *
 */

VALUE
rb_int_lshift(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return rb_fix_lshift(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_lshift(x, y);
    }
    return Qnil;
}

static VALUE
rb_fix_rshift(VALUE x, VALUE y)
{
    long i, val;

    val = FIX2LONG(x);
    if (!val) return (rb_to_int(y), INT2FIX(0));
    if (!FIXNUM_P(y))
        return rb_big_rshift(rb_int2big(val), y);
    i = FIX2LONG(y);
    if (i == 0) return x;
    if (i < 0)
        return fix_lshift(val, (unsigned long)-i);
    return fix_rshift(val, i);
}

static VALUE
fix_rshift(long val, unsigned long i)
{
    if (i >= sizeof(long)*CHAR_BIT-1) {
        if (val < 0) return INT2FIX(-1);
        return INT2FIX(0);
    }
    val = RSHIFT(val, i);
    return LONG2FIX(val);
}

/*
 *  call-seq:
 *    self >> count -> integer
 *
 *  Returns +self+ with bits shifted +count+ positions to the right,
 *  or to the left if +count+ is negative:
 *
 *    n = 0b11110000
 *    "%08b" % (n >> 1)  # => "01111000"
 *    "%08b" % (n >> 3)  # => "00011110"
 *    "%08b" % (n >> -1) # => "111100000"
 *    "%08b" % (n >> -3) # => "11110000000"
 *
 *  Related: Integer#<<.
 *
 */

VALUE
rb_int_rshift(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
        return rb_fix_rshift(x, y);
    }
    else if (RB_BIGNUM_TYPE_P(x)) {
        return rb_big_rshift(x, y);
    }
    return Qnil;
}

VALUE
rb_fix_aref(VALUE fix, VALUE idx)
{
    long val = FIX2LONG(fix);
    long i;

    idx = rb_to_int(idx);
    if (!FIXNUM_P(idx)) {
        idx = rb_big_norm(idx);
        if (!FIXNUM_P(idx)) {
            if (!BIGNUM_SIGN(idx) || val >= 0)
                return INT2FIX(0);
            return INT2FIX(1);
        }
    }
    i = FIX2LONG(idx);

    if (i < 0) return INT2FIX(0);
    if (SIZEOF_LONG*CHAR_BIT-1 <= i) {
        if (val < 0) return INT2FIX(1);
        return INT2FIX(0);
    }
    if (val & (1L<<i))
        return INT2FIX(1);
    return INT2FIX(0);
}


/* copied from "r_less" in range.c */
/* compares _a_ and _b_ and returns:
 * < 0: a < b
 * = 0: a = b
 * > 0: a > b or non-comparable
 */
static int
compare_indexes(VALUE a, VALUE b)
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (NIL_P(r))
        return INT_MAX;
    return rb_cmpint(r, a, b);
}

static VALUE
generate_mask(VALUE len)
{
    return rb_int_minus(rb_int_lshift(INT2FIX(1), len), INT2FIX(1));
}

static VALUE
int_aref1(VALUE num, VALUE arg)
{
    VALUE orig_num = num, beg, end;
    int excl;

    if (rb_range_values(arg, &beg, &end, &excl)) {
        if (NIL_P(beg)) {
            /* beginless range */
            if (!RTEST(num_negative_p(end))) {
                if (!excl) end = rb_int_plus(end, INT2FIX(1));
                VALUE mask = generate_mask(end);
                if (int_zero_p(rb_int_and(num, mask))) {
                    return INT2FIX(0);
                }
                else {
                    rb_raise(rb_eArgError, "The beginless range for Integer#[] results in infinity");
                }
            }
            else {
                return INT2FIX(0);
            }
        }
        num = rb_int_rshift(num, beg);

        int cmp = compare_indexes(beg, end);
        if (!NIL_P(end) && cmp < 0) {
            VALUE len = rb_int_minus(end, beg);
            if (!excl) len = rb_int_plus(len, INT2FIX(1));
            VALUE mask = generate_mask(len);
            num = rb_int_and(num, mask);
        }
        else if (cmp == 0) {
            if (excl) return INT2FIX(0);
            num = orig_num;
            arg = beg;
            goto one_bit;
        }
        return num;
    }

one_bit:
    if (FIXNUM_P(num)) {
        return rb_fix_aref(num, arg);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_aref(num, arg);
    }
    return Qnil;
}

static VALUE
int_aref2(VALUE num, VALUE beg, VALUE len)
{
    num = rb_int_rshift(num, beg);
    VALUE mask = generate_mask(len);
    num = rb_int_and(num, mask);
    return num;
}

/*
 *  call-seq:
 *     self[offset]    -> 0 or 1
 *     self[offset, size] -> integer
 *     self[range] -> integer
 *
 *  Returns a slice of bits from +self+.
 *
 *  With argument +offset+, returns the bit at the given offset,
 *  where offset 0 refers to the least significant bit:
 *
 *    n = 0b10 # => 2
 *    n[0]     # => 0
 *    n[1]     # => 1
 *    n[2]     # => 0
 *    n[3]     # => 0
 *
 *  In principle, <code>n[i]</code> is equivalent to <code>(n >> i) & 1</code>.
 *  Thus, negative index always returns zero:
 *
 *     255[-1] # => 0
 *
 *  With arguments +offset+ and +size+, returns +size+ bits from +self+,
 *  beginning at +offset+ and including bits of greater significance:
 *
 *    n = 0b111000       # => 56
 *    "%010b" % n[0, 10] # => "0000111000"
 *    "%010b" % n[4, 10] # => "0000000011"
 *
 *  With argument +range+, returns <tt>range.size</tt> bits from +self+,
 *  beginning at <tt>range.begin</tt> and including bits of greater significance:
 *
 *    n = 0b111000      # => 56
 *    "%010b" % n[0..9] # => "0000111000"
 *    "%010b" % n[4..9] # => "0000000011"
 *
 *  Raises an exception if the slice cannot be constructed.
 */

static VALUE
int_aref(int const argc, VALUE * const argv, VALUE const num)
{
    rb_check_arity(argc, 1, 2);
    if (argc == 2) {
        return int_aref2(num, argv[0], argv[1]);
    }
    return int_aref1(num, argv[0]);

    return Qnil;
}

/*
 *  call-seq:
 *    to_f -> float
 *
 *  Converts +self+ to a Float:
 *
 *    1.to_f  # => 1.0
 *    -1.to_f # => -1.0
 *
 *  If the value of +self+ does not fit in a Float,
 *  the result is infinity:
 *
 *    (10**400).to_f  # => Infinity
 *    (-10**400).to_f # => -Infinity
 *
 */

static VALUE
int_to_f(VALUE num)
{
    double val;

    if (FIXNUM_P(num)) {
        val = (double)FIX2LONG(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        val = rb_big2dbl(num);
    }
    else {
        rb_raise(rb_eNotImpError, "Unknown subclass for to_f: %s", rb_obj_classname(num));
    }

    return DBL2NUM(val);
}

static VALUE
fix_abs(VALUE fix)
{
    long i = FIX2LONG(fix);

    if (i < 0) i = -i;

    return LONG2NUM(i);
}

VALUE
rb_int_abs(VALUE num)
{
    if (FIXNUM_P(num)) {
        return fix_abs(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_abs(num);
    }
    return Qnil;
}

static VALUE
fix_size(VALUE fix)
{
    return INT2FIX(sizeof(long));
}

VALUE
rb_int_size(VALUE num)
{
    if (FIXNUM_P(num)) {
        return fix_size(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_size_m(num);
    }
    return Qnil;
}

static VALUE
rb_fix_bit_length(VALUE fix)
{
    long v = FIX2LONG(fix);
    if (v < 0)
        v = ~v;
    return LONG2FIX(bit_length(v));
}

VALUE
rb_int_bit_length(VALUE num)
{
    if (FIXNUM_P(num)) {
        return rb_fix_bit_length(num);
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        return rb_big_bit_length(num);
    }
    return Qnil;
}

static VALUE
rb_fix_digits(VALUE fix, long base)
{
    VALUE digits;
    long x = FIX2LONG(fix);

    RUBY_ASSERT(x >= 0);

    if (base < 2)
        rb_raise(rb_eArgError, "invalid radix %ld", base);

    if (x == 0)
        return rb_ary_new_from_args(1, INT2FIX(0));

    digits = rb_ary_new();
    while (x > 0) {
        long q = x % base;
        rb_ary_push(digits, LONG2NUM(q));
        x /= base;
    }

    return digits;
}

static VALUE
rb_int_digits_bigbase(VALUE num, VALUE base)
{
    VALUE digits, bases;

    RUBY_ASSERT(!rb_num_negative_p(num));

    if (RB_BIGNUM_TYPE_P(base))
        base = rb_big_norm(base);

    if (FIXNUM_P(base) && FIX2LONG(base) < 2)
        rb_raise(rb_eArgError, "invalid radix %ld", FIX2LONG(base));
    else if (RB_BIGNUM_TYPE_P(base) && BIGNUM_NEGATIVE_P(base))
        rb_raise(rb_eArgError, "negative radix");

    if (FIXNUM_P(base) && FIXNUM_P(num))
        return rb_fix_digits(num, FIX2LONG(base));

    if (FIXNUM_P(num))
        return rb_ary_new_from_args(1, num);

    if (int_lt(rb_int_div(rb_int_bit_length(num), rb_int_bit_length(base)), INT2FIX(50))) {
        digits = rb_ary_new();
        while (!FIXNUM_P(num) || FIX2LONG(num) > 0) {
            VALUE qr = rb_int_divmod(num, base);
            rb_ary_push(digits, RARRAY_AREF(qr, 1));
            num = RARRAY_AREF(qr, 0);
        }
        return digits;
    }

    bases = rb_ary_new();
    for (VALUE b = base; int_lt(b, num) == Qtrue; b = rb_int_mul(b, b)) {
        rb_ary_push(bases, b);
    }
    digits = rb_ary_new_from_args(1, num);
    while (RARRAY_LEN(bases)) {
        VALUE b = rb_ary_pop(bases);
        long i, last_idx = RARRAY_LEN(digits) - 1;
        for(i = last_idx; i >= 0; i--) {
            VALUE n = RARRAY_AREF(digits, i);
            VALUE divmod = rb_int_divmod(n, b);
            VALUE div = RARRAY_AREF(divmod, 0);
            VALUE mod = RARRAY_AREF(divmod, 1);
            if (i != last_idx || div != INT2FIX(0)) rb_ary_store(digits, 2 * i + 1,  div);
            rb_ary_store(digits, 2 * i, mod);
        }
    }

    return digits;
}

/*
 *  call-seq:
 *    digits(base = 10) -> array_of_integers
 *
 *  Returns an array of integers representing the +base+-radix
 *  digits of +self+;
 *  the first element of the array represents the least significant digit:
 *
 *    12345.digits      # => [5, 4, 3, 2, 1]
 *    12345.digits(7)   # => [4, 6, 6, 0, 5]
 *    12345.digits(100) # => [45, 23, 1]
 *
 *  Raises an exception if +self+ is negative or +base+ is less than 2.
 *
 */

static VALUE
rb_int_digits(int argc, VALUE *argv, VALUE num)
{
    VALUE base_value;
    long base;

    if (rb_num_negative_p(num))
        rb_raise(rb_eMathDomainError, "out of domain");

    if (rb_check_arity(argc, 0, 1)) {
        base_value = rb_to_int(argv[0]);
        if (!RB_INTEGER_TYPE_P(base_value))
            rb_raise(rb_eTypeError, "wrong argument type %s (expected Integer)",
                     rb_obj_classname(argv[0]));
        if (RB_BIGNUM_TYPE_P(base_value))
            return rb_int_digits_bigbase(num, base_value);

        base = FIX2LONG(base_value);
        if (base < 0)
            rb_raise(rb_eArgError, "negative radix");
        else if (base < 2)
            rb_raise(rb_eArgError, "invalid radix %ld", base);
    }
    else
        base = 10;

    if (FIXNUM_P(num))
        return rb_fix_digits(num, base);
    else if (RB_BIGNUM_TYPE_P(num))
        return rb_int_digits_bigbase(num, LONG2FIX(base));

    return Qnil;
}

static VALUE
int_upto_size(VALUE from, VALUE args, VALUE eobj)
{
    return ruby_num_interval_step_size(from, RARRAY_AREF(args, 0), INT2FIX(1), FALSE);
}

/*
 *  call-seq:
 *    upto(limit) {|i| ... } -> self
 *    upto(limit)            ->  enumerator
 *
 *  Calls the given block with each integer value from +self+ up to +limit+;
 *  returns +self+:
 *
 *    a = []
 *    5.upto(10) {|i| a << i }              # => 5
 *    a                                     # => [5, 6, 7, 8, 9, 10]
 *    a = []
 *    -5.upto(0) {|i| a << i }              # => -5
 *    a                                     # => [-5, -4, -3, -2, -1, 0]
 *    5.upto(4) {|i| fail 'Cannot happen' } # => 5
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
int_upto(VALUE from, VALUE to)
{
    RETURN_SIZED_ENUMERATOR(from, 1, &to, int_upto_size);
    if (FIXNUM_P(from) && FIXNUM_P(to)) {
        long i, end;

        end = FIX2LONG(to);
        for (i = FIX2LONG(from); i <= end; i++) {
            rb_yield(LONG2FIX(i));
        }
    }
    else {
        VALUE i = from, c;

        while (!(c = rb_funcall(i, '>', 1, to))) {
            rb_yield(i);
            i = rb_funcall(i, '+', 1, INT2FIX(1));
        }
        ensure_cmp(c, i, to);
    }
    return from;
}

static VALUE
int_downto_size(VALUE from, VALUE args, VALUE eobj)
{
    return ruby_num_interval_step_size(from, RARRAY_AREF(args, 0), INT2FIX(-1), FALSE);
}

/*
 *  call-seq:
 *    downto(limit) {|i| ... } -> self
 *    downto(limit)            ->  enumerator
 *
 *  Calls the given block with each integer value from +self+ down to +limit+;
 *  returns +self+:
 *
 *    a = []
 *    10.downto(5) {|i| a << i }              # => 10
 *    a                                       # => [10, 9, 8, 7, 6, 5]
 *    a = []
 *    0.downto(-5) {|i| a << i }              # => 0
 *    a                                       # => [0, -1, -2, -3, -4, -5]
 *    4.downto(5) {|i| fail 'Cannot happen' } # => 4
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
int_downto(VALUE from, VALUE to)
{
    RETURN_SIZED_ENUMERATOR(from, 1, &to, int_downto_size);
    if (FIXNUM_P(from) && FIXNUM_P(to)) {
        long i, end;

        end = FIX2LONG(to);
        for (i=FIX2LONG(from); i >= end; i--) {
            rb_yield(LONG2FIX(i));
        }
    }
    else {
        VALUE i = from, c;

        while (!(c = rb_funcall(i, '<', 1, to))) {
            rb_yield(i);
            i = rb_funcall(i, '-', 1, INT2FIX(1));
        }
        if (NIL_P(c)) rb_cmperr(i, to);
    }
    return from;
}

static VALUE
int_dotimes_size(VALUE num, VALUE args, VALUE eobj)
{
    return int_neg_p(num) ? INT2FIX(0) : num;
}

/*
 *  call-seq:
 *    round(ndigits= 0, half: :up) -> integer
 *
 *  Returns +self+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is negative, the returned value
 *  has at least <tt>ndigits.abs</tt> trailing zeros:
 *
 *    555.round(-1)      # => 560
 *    555.round(-2)      # => 600
 *    555.round(-3)      # => 1000
 *    -555.round(-2)     # => -600
 *    555.round(-4)      # => 0
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *    555.round     # => 555
 *    555.round(1)  # => 555
 *    555.round(50) # => 555
 *
 *  If keyword argument +half+ is given,
 *  and +self+ is equidistant from the two candidate  values,
 *  the rounding is according to the given +half+ value:
 *
 *  - +:up+ or +nil+: round away from zero:
 *
 *      25.round(-1, half: :up)      # => 30
 *      (-25).round(-1, half: :up)   # => -30
 *
 *  - +:down+: round toward zero:
 *
 *      25.round(-1, half: :down)    # => 20
 *      (-25).round(-1, half: :down) # => -20
 *
 *
 *  - +:even+: round toward the candidate whose last nonzero digit is even:
 *
 *      25.round(-1, half: :even)    # => 20
 *      15.round(-1, half: :even)    # => 20
 *      (-25).round(-1, half: :even) # => -20
 *
 *  Raises and exception if the value for +half+ is invalid.
 *
 *  Related: Integer#truncate.
 *
 */

static VALUE
int_round(int argc, VALUE* argv, VALUE num)
{
    int ndigits;
    int mode;
    VALUE nd, opt;

    if (!rb_scan_args(argc, argv, "01:", &nd, &opt)) return num;
    ndigits = NUM2INT(nd);
    mode = rb_num_get_rounding_option(opt);
    if (ndigits >= 0) {
        return num;
    }
    return rb_int_round(num, ndigits, mode);
}

/*
 *  call-seq:
 *    floor(ndigits = 0) -> integer
 *
 *  Returns the largest number less than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is negative, the returned value
 *  has at least <tt>ndigits.abs</tt> trailing zeros:
 *
 *    555.floor(-1)  # => 550
 *    555.floor(-2)  # => 500
 *    -555.floor(-2) # => -600
 *    555.floor(-3)  # => 0
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *    555.floor     # => 555
 *    555.floor(50) # => 555
 *
 *  Related: Integer#ceil.
 *
 */

static VALUE
int_floor(int argc, VALUE* argv, VALUE num)
{
    int ndigits;

    if (!rb_check_arity(argc, 0, 1)) return num;
    ndigits = NUM2INT(argv[0]);
    if (ndigits >= 0) {
        return num;
    }
    return rb_int_floor(num, ndigits);
}

/*
 *  call-seq:
 *    ceil(ndigits = 0) -> integer
 *
 *  Returns the smallest number greater than or equal to +self+ with
 *  a precision of +ndigits+ decimal digits.
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros:
 *
 *    555.ceil(-1)  # => 560
 *    555.ceil(-2)  # => 600
 *    -555.ceil(-2) # => -500
 *    555.ceil(-3)  # => 1000
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *     555.ceil     # => 555
 *     555.ceil(50) # => 555
 *
 *  Related: Integer#floor.
 *
 */

static VALUE
int_ceil(int argc, VALUE* argv, VALUE num)
{
    int ndigits;

    if (!rb_check_arity(argc, 0, 1)) return num;
    ndigits = NUM2INT(argv[0]);
    if (ndigits >= 0) {
        return num;
    }
    return rb_int_ceil(num, ndigits);
}

/*
 *  call-seq:
 *    truncate(ndigits = 0) -> integer
 *
 *  Returns +self+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits.
 *
 *  When +ndigits+ is negative, the returned value
 *  has at least <tt>ndigits.abs</tt> trailing zeros:
 *
 *    555.truncate(-1)  # => 550
 *    555.truncate(-2)  # => 500
 *    -555.truncate(-2) # => -500
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *    555.truncate     # => 555
 *    555.truncate(50) # => 555
 *
 *  Related: Integer#round.
 *
 */

static VALUE
int_truncate(int argc, VALUE* argv, VALUE num)
{
    int ndigits;

    if (!rb_check_arity(argc, 0, 1)) return num;
    ndigits = NUM2INT(argv[0]);
    if (ndigits >= 0) {
        return num;
    }
    return rb_int_truncate(num, ndigits);
}

#define DEFINE_INT_SQRT(rettype, prefix, argtype) \
rettype \
prefix##_isqrt(argtype n) \
{ \
    if (!argtype##_IN_DOUBLE_P(n)) { \
        unsigned int b = bit_length(n); \
        argtype t; \
        rettype x = (rettype)(n >> (b/2+1)); \
        x |= ((rettype)1LU << (b-1)/2); \
        while ((t = n/x) < (argtype)x) x = (rettype)((x + t) >> 1); \
        return x; \
    } \
    return (rettype)sqrt(argtype##_TO_DOUBLE(n)); \
}

#if SIZEOF_LONG*CHAR_BIT > DBL_MANT_DIG
# define RB_ULONG_IN_DOUBLE_P(n) ((n) < (1UL << DBL_MANT_DIG))
#else
# define RB_ULONG_IN_DOUBLE_P(n) 1
#endif
#define RB_ULONG_TO_DOUBLE(n) (double)(n)
#define RB_ULONG unsigned long
DEFINE_INT_SQRT(unsigned long, rb_ulong, RB_ULONG)

#if 2*SIZEOF_BDIGIT > SIZEOF_LONG
# if 2*SIZEOF_BDIGIT*CHAR_BIT > DBL_MANT_DIG
#   define BDIGIT_DBL_IN_DOUBLE_P(n) ((n) < ((BDIGIT_DBL)1UL << DBL_MANT_DIG))
# else
#   define BDIGIT_DBL_IN_DOUBLE_P(n) 1
# endif
# ifdef ULL_TO_DOUBLE
#   define BDIGIT_DBL_TO_DOUBLE(n) ULL_TO_DOUBLE(n)
# else
#   define BDIGIT_DBL_TO_DOUBLE(n) (double)(n)
# endif
DEFINE_INT_SQRT(BDIGIT, rb_bdigit_dbl, BDIGIT_DBL)
#endif

#define domain_error(msg) \
    rb_raise(rb_eMathDomainError, "Numerical argument is out of domain - " #msg)

/*
 *  call-seq:
 *    Integer.sqrt(numeric) -> integer
 *
 *  Returns the integer square root of the non-negative integer +n+,
 *  which is the largest non-negative integer less than or equal to the
 *  square root of +numeric+.
 *
 *    Integer.sqrt(0)       # => 0
 *    Integer.sqrt(1)       # => 1
 *    Integer.sqrt(24)      # => 4
 *    Integer.sqrt(25)      # => 5
 *    Integer.sqrt(10**400) # => 10**200
 *
 *  If +numeric+ is not an \Integer, it is converted to an \Integer:
 *
 *    Integer.sqrt(Complex(4, 0))  # => 2
 *    Integer.sqrt(Rational(4, 1)) # => 2
 *    Integer.sqrt(4.0)            # => 2
 *    Integer.sqrt(3.14159)        # => 1
 *
 *  This method is equivalent to <tt>Math.sqrt(numeric).floor</tt>,
 *  except that the result of the latter code may differ from the true value
 *  due to the limited precision of floating point arithmetic.
 *
 *    Integer.sqrt(10**46)    # => 100000000000000000000000
 *    Math.sqrt(10**46).floor # => 99999999999999991611392
 *
 *  Raises an exception if +numeric+ is negative.
 *
 */

static VALUE
rb_int_s_isqrt(VALUE self, VALUE num)
{
    unsigned long n, sq;
    num = rb_to_int(num);
    if (FIXNUM_P(num)) {
        if (FIXNUM_NEGATIVE_P(num)) {
            domain_error("isqrt");
        }
        n = FIX2ULONG(num);
        sq = rb_ulong_isqrt(n);
        return LONG2FIX(sq);
    }
    else {
        size_t biglen;
        if (RBIGNUM_NEGATIVE_P(num)) {
            domain_error("isqrt");
        }
        biglen = BIGNUM_LEN(num);
        if (biglen == 0) return INT2FIX(0);
#if SIZEOF_BDIGIT <= SIZEOF_LONG
        /* short-circuit */
        if (biglen == 1) {
            n = BIGNUM_DIGITS(num)[0];
            sq = rb_ulong_isqrt(n);
            return ULONG2NUM(sq);
        }
#endif
        return rb_big_isqrt(num);
    }
}

/*
 * call-seq:
 *   Integer.try_convert(object) -> object, integer, or nil
 *
 * If +object+ is an \Integer object, returns +object+.
 *   Integer.try_convert(1) # => 1
 *
 * Otherwise if +object+ responds to <tt>:to_int</tt>,
 * calls <tt>object.to_int</tt> and returns the result.
 *   Integer.try_convert(1.25) # => 1
 *
 * Returns +nil+ if +object+ does not respond to <tt>:to_int</tt>
 *   Integer.try_convert([]) # => nil
 *
 * Raises an exception unless <tt>object.to_int</tt> returns an \Integer object.
 */
static VALUE
int_s_try_convert(VALUE self, VALUE num)
{
    return rb_check_integer_type(num);
}

/*
 *  Document-class: ZeroDivisionError
 *
 *  Raised when attempting to divide an integer by 0.
 *
 *     42 / 0   #=> ZeroDivisionError: divided by 0
 *
 *  Note that only division by an exact 0 will raise the exception:
 *
 *     42 /  0.0   #=> Float::INFINITY
 *     42 / -0.0   #=> -Float::INFINITY
 *     0  /  0.0   #=> NaN
 */

/*
 *  Document-class: FloatDomainError
 *
 *  Raised when attempting to convert special float values (in particular
 *  +Infinity+ or +NaN+) to numerical classes which don't support them.
 *
 *     Float::INFINITY.to_r   #=> FloatDomainError: Infinity
 */

/*
 * Document-class: Numeric
 *
 * \Numeric is the class from which all higher-level numeric classes should inherit.
 *
 * \Numeric allows instantiation of heap-allocated objects. Other core numeric classes such as
 * Integer are implemented as immediates, which means that each Integer is a single immutable
 * object which is always passed by value.
 *
 *   a = 1
 *   1.object_id == a.object_id   #=> true
 *
 * There can only ever be one instance of the integer +1+, for example. Ruby ensures this
 * by preventing instantiation. If duplication is attempted, the same instance is returned.
 *
 *   Integer.new(1)                   #=> NoMethodError: undefined method `new' for Integer:Class
 *   1.dup                            #=> 1
 *   1.object_id == 1.dup.object_id   #=> true
 *
 * For this reason, \Numeric should be used when defining other numeric classes.
 *
 * Classes which inherit from \Numeric must implement +coerce+, which returns a two-member
 * Array containing an object that has been coerced into an instance of the new class
 * and +self+ (see #coerce).
 *
 * Inheriting classes should also implement arithmetic operator methods (<code>+</code>,
 * <code>-</code>, <code>*</code> and <code>/</code>) and the <code><=></code> operator (see
 * Comparable). These methods may rely on +coerce+ to ensure interoperability with
 * instances of other numeric classes.
 *
 *   class Tally < Numeric
 *     def initialize(string)
 *       @string = string
 *     end
 *
 *     def to_s
 *       @string
 *     end
 *
 *     def to_i
 *       @string.size
 *     end
 *
 *     def coerce(other)
 *       [self.class.new('|' * other.to_i), self]
 *     end
 *
 *     def <=>(other)
 *       to_i <=> other.to_i
 *     end
 *
 *     def +(other)
 *       self.class.new('|' * (to_i + other.to_i))
 *     end
 *
 *     def -(other)
 *       self.class.new('|' * (to_i - other.to_i))
 *     end
 *
 *     def *(other)
 *       self.class.new('|' * (to_i * other.to_i))
 *     end
 *
 *     def /(other)
 *       self.class.new('|' * (to_i / other.to_i))
 *     end
 *   end
 *
 *   tally = Tally.new('||')
 *   puts tally * 2            #=> "||||"
 *   puts tally > 1            #=> true
 *
 * == What's Here
 *
 * First, what's elsewhere. \Class \Numeric:
 *
 * - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 * - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
 *
 * Here, class \Numeric provides methods for:
 *
 * - {Querying}[rdoc-ref:Numeric@Querying]
 * - {Comparing}[rdoc-ref:Numeric@Comparing]
 * - {Converting}[rdoc-ref:Numeric@Converting]
 * - {Other}[rdoc-ref:Numeric@Other]
 *
 * === Querying
 *
 * - #finite?: Returns true unless +self+ is infinite or not a number.
 * - #infinite?: Returns -1, +nil+ or +1, depending on whether +self+
 *   is <tt>-Infinity<tt>, finite, or <tt>+Infinity</tt>.
 * - #integer?: Returns whether +self+ is an integer.
 * - #negative?: Returns whether +self+ is negative.
 * - #nonzero?: Returns whether +self+ is not zero.
 * - #positive?: Returns whether +self+ is positive.
 * - #real?: Returns whether +self+ is a real value.
 * - #zero?: Returns whether +self+ is zero.
 *
 * === Comparing
 *
 * - #<=>: Returns:
 *
 *   - -1 if  +self+ is less than the given value.
 *   - 0 if +self+ is equal to the given value.
 *   - 1 if +self+ is greater than the given value.
 *   - +nil+ if +self+ and the given value are not comparable.
 *
 * - #eql?: Returns whether +self+ and the given value have the same value and type.
 *
 * === Converting
 *
 * - #% (aliased as #modulo): Returns the remainder of +self+ divided by the given value.
 * - #-@: Returns the value of +self+, negated.
 * - #abs (aliased as #magnitude): Returns the absolute value of +self+.
 * - #abs2: Returns the square of +self+.
 * - #angle (aliased as #arg and #phase): Returns 0 if +self+ is positive,
 *   Math::PI otherwise.
 * - #ceil: Returns the smallest number greater than or equal to +self+,
 *   to a given precision.
 * - #coerce: Returns array <tt>[coerced_self, coerced_other]</tt>
 *   for the given other value.
 * - #conj (aliased as #conjugate): Returns the complex conjugate of +self+.
 * - #denominator: Returns the denominator (always positive)
 *   of the Rational representation of +self+.
 * - #div: Returns the value of +self+ divided by the given value
 *   and converted to an integer.
 * - #divmod: Returns array <tt>[quotient, modulus]</tt> resulting
 *   from dividing +self+ the given divisor.
 * - #fdiv: Returns the Float result of dividing +self+ by the given divisor.
 * - #floor: Returns the largest number less than or equal to +self+,
 *   to a given precision.
 * - #i: Returns the Complex object <tt>Complex(0, self)</tt>.
 *   the given value.
 * - #imaginary (aliased as #imag): Returns the imaginary part of the +self+.
 * - #numerator: Returns the numerator of the Rational representation of +self+;
 *   has the same sign as +self+.
 * - #polar: Returns the array <tt>[self.abs, self.arg]</tt>.
 * - #quo: Returns the value of +self+ divided by the given value.
 * - #real: Returns the real part of +self+.
 * - #rect (aliased as #rectangular): Returns the array <tt>[self, 0]</tt>.
 * - #remainder: Returns <tt>self-arg*(self/arg).truncate</tt> for the given +arg+.
 * - #round: Returns the value of +self+ rounded to the nearest value
 *   for the given a precision.
 * - #to_c: Returns the Complex representation of +self+.
 * - #to_int: Returns the Integer representation of +self+, truncating if necessary.
 * - #truncate: Returns +self+ truncated (toward zero) to a given precision.
 *
 * === Other
 *
 * - #clone: Returns +self+; does not allow freezing.
 * - #dup (aliased as #+@): Returns +self+.
 * - #step: Invokes the given block with the sequence of specified numbers.
 *
 */
void
Init_Numeric(void)
{
#ifdef _UNICOSMP
    /* Turn off floating point exceptions for divide by zero, etc. */
    _set_Creg(0, 0);
#endif
    id_coerce = rb_intern_const("coerce");
    id_to = rb_intern_const("to");
    id_by = rb_intern_const("by");

    rb_eZeroDivError = rb_define_class("ZeroDivisionError", rb_eStandardError);
    rb_eFloatDomainError = rb_define_class("FloatDomainError", rb_eRangeError);
    rb_cNumeric = rb_define_class("Numeric", rb_cObject);

    rb_define_method(rb_cNumeric, "singleton_method_added", num_sadded, 1);
    rb_include_module(rb_cNumeric, rb_mComparable);
    rb_define_method(rb_cNumeric, "coerce", num_coerce, 1);
    rb_define_method(rb_cNumeric, "clone", num_clone, -1);
    rb_define_method(rb_cNumeric, "dup", num_dup, 0);

    rb_define_method(rb_cNumeric, "i", num_imaginary, 0);
    rb_define_method(rb_cNumeric, "+@", num_uplus, 0);
    rb_define_method(rb_cNumeric, "-@", num_uminus, 0);
    rb_define_method(rb_cNumeric, "<=>", num_cmp, 1);
    rb_define_method(rb_cNumeric, "eql?", num_eql, 1);
    rb_define_method(rb_cNumeric, "fdiv", num_fdiv, 1);
    rb_define_method(rb_cNumeric, "div", num_div, 1);
    rb_define_method(rb_cNumeric, "divmod", num_divmod, 1);
    rb_define_method(rb_cNumeric, "%", num_modulo, 1);
    rb_define_method(rb_cNumeric, "modulo", num_modulo, 1);
    rb_define_method(rb_cNumeric, "remainder", num_remainder, 1);
    rb_define_method(rb_cNumeric, "abs", num_abs, 0);
    rb_define_method(rb_cNumeric, "magnitude", num_abs, 0);
    rb_define_method(rb_cNumeric, "to_int", num_to_int, 0);

    rb_define_method(rb_cNumeric, "zero?", num_zero_p, 0);
    rb_define_method(rb_cNumeric, "nonzero?", num_nonzero_p, 0);

    rb_define_method(rb_cNumeric, "floor", num_floor, -1);
    rb_define_method(rb_cNumeric, "ceil", num_ceil, -1);
    rb_define_method(rb_cNumeric, "round", num_round, -1);
    rb_define_method(rb_cNumeric, "truncate", num_truncate, -1);
    rb_define_method(rb_cNumeric, "step", num_step, -1);
    rb_define_method(rb_cNumeric, "positive?", num_positive_p, 0);
    rb_define_method(rb_cNumeric, "negative?", num_negative_p, 0);

    rb_cInteger = rb_define_class("Integer", rb_cNumeric);
    rb_undef_alloc_func(rb_cInteger);
    rb_undef_method(CLASS_OF(rb_cInteger), "new");
    rb_define_singleton_method(rb_cInteger, "sqrt", rb_int_s_isqrt, 1);
    rb_define_singleton_method(rb_cInteger, "try_convert", int_s_try_convert, 1);

    rb_define_method(rb_cInteger, "to_s", rb_int_to_s, -1);
    rb_define_alias(rb_cInteger, "inspect", "to_s");
    rb_define_method(rb_cInteger, "allbits?", int_allbits_p, 1);
    rb_define_method(rb_cInteger, "anybits?", int_anybits_p, 1);
    rb_define_method(rb_cInteger, "nobits?", int_nobits_p, 1);
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "succ", int_succ, 0);
    rb_define_method(rb_cInteger, "next", int_succ, 0);
    rb_define_method(rb_cInteger, "pred", int_pred, 0);
    rb_define_method(rb_cInteger, "chr", int_chr, -1);
    rb_define_method(rb_cInteger, "to_f", int_to_f, 0);
    rb_define_method(rb_cInteger, "floor", int_floor, -1);
    rb_define_method(rb_cInteger, "ceil", int_ceil, -1);
    rb_define_method(rb_cInteger, "truncate", int_truncate, -1);
    rb_define_method(rb_cInteger, "round", int_round, -1);
    rb_define_method(rb_cInteger, "<=>", rb_int_cmp, 1);

    rb_define_method(rb_cInteger, "+", rb_int_plus, 1);
    rb_define_method(rb_cInteger, "-", rb_int_minus, 1);
    rb_define_method(rb_cInteger, "*", rb_int_mul, 1);
    rb_define_method(rb_cInteger, "/", rb_int_div, 1);
    rb_define_method(rb_cInteger, "div", rb_int_idiv, 1);
    rb_define_method(rb_cInteger, "%", rb_int_modulo, 1);
    rb_define_method(rb_cInteger, "modulo", rb_int_modulo, 1);
    rb_define_method(rb_cInteger, "remainder", int_remainder, 1);
    rb_define_method(rb_cInteger, "divmod", rb_int_divmod, 1);
    rb_define_method(rb_cInteger, "fdiv", rb_int_fdiv, 1);
    rb_define_method(rb_cInteger, "**", rb_int_pow, 1);

    rb_define_method(rb_cInteger, "pow", rb_int_powm, -1); /* in bignum.c */

    rb_define_method(rb_cInteger, "===", rb_int_equal, 1);
    rb_define_method(rb_cInteger, "==", rb_int_equal, 1);
    rb_define_method(rb_cInteger, ">", rb_int_gt, 1);
    rb_define_method(rb_cInteger, ">=", rb_int_ge, 1);
    rb_define_method(rb_cInteger, "<", int_lt, 1);
    rb_define_method(rb_cInteger, "<=", int_le, 1);

    rb_define_method(rb_cInteger, "&", rb_int_and, 1);
    rb_define_method(rb_cInteger, "|", int_or,  1);
    rb_define_method(rb_cInteger, "^", int_xor, 1);
    rb_define_method(rb_cInteger, "[]", int_aref, -1);

    rb_define_method(rb_cInteger, "<<", rb_int_lshift, 1);
    rb_define_method(rb_cInteger, ">>", rb_int_rshift, 1);

    rb_define_method(rb_cInteger, "digits", rb_int_digits, -1);

#define fix_to_s_static(n) do { \
        VALUE lit = rb_fstring_literal(#n); \
        rb_fix_to_s_static[n] = lit; \
        rb_vm_register_global_object(lit); \
        RB_GC_GUARD(lit); \
    } while (0)

    fix_to_s_static(0);
    fix_to_s_static(1);
    fix_to_s_static(2);
    fix_to_s_static(3);
    fix_to_s_static(4);
    fix_to_s_static(5);
    fix_to_s_static(6);
    fix_to_s_static(7);
    fix_to_s_static(8);
    fix_to_s_static(9);

#undef fix_to_s_static

    rb_cFloat  = rb_define_class("Float", rb_cNumeric);

    rb_undef_alloc_func(rb_cFloat);
    rb_undef_method(CLASS_OF(rb_cFloat), "new");

    /*
     *	The base of the floating point, or number of unique digits used to
     *	represent the number.
     *
     *  Usually defaults to 2 on most systems, which would represent a base-10 decimal.
     */
    rb_define_const(rb_cFloat, "RADIX", INT2FIX(FLT_RADIX));
    /*
     * The number of base digits for the +double+ data type.
     *
     * Usually defaults to 53.
     */
    rb_define_const(rb_cFloat, "MANT_DIG", INT2FIX(DBL_MANT_DIG));
    /*
     *	The minimum number of significant decimal digits in a double-precision
     *	floating point.
     *
     *	Usually defaults to 15.
     */
    rb_define_const(rb_cFloat, "DIG", INT2FIX(DBL_DIG));
    /*
     *	The smallest possible exponent value in a double-precision floating
     *	point.
     *
     *	Usually defaults to -1021.
     */
    rb_define_const(rb_cFloat, "MIN_EXP", INT2FIX(DBL_MIN_EXP));
    /*
     *	The largest possible exponent value in a double-precision floating
     *	point.
     *
     *	Usually defaults to 1024.
     */
    rb_define_const(rb_cFloat, "MAX_EXP", INT2FIX(DBL_MAX_EXP));
    /*
     *	The smallest negative exponent in a double-precision floating point
     *	where 10 raised to this power minus 1.
     *
     *	Usually defaults to -307.
     */
    rb_define_const(rb_cFloat, "MIN_10_EXP", INT2FIX(DBL_MIN_10_EXP));
    /*
     *	The largest positive exponent in a double-precision floating point where
     *	10 raised to this power minus 1.
     *
     *	Usually defaults to 308.
     */
    rb_define_const(rb_cFloat, "MAX_10_EXP", INT2FIX(DBL_MAX_10_EXP));
    /*
     *	The smallest positive normalized number in a double-precision floating point.
     *
     *	Usually defaults to 2.2250738585072014e-308.
     *
     *	If the platform supports denormalized numbers,
     *	there are numbers between zero and Float::MIN.
     *	0.0.next_float returns the smallest positive floating point number
     *	including denormalized numbers.
     */
    rb_define_const(rb_cFloat, "MIN", DBL2NUM(DBL_MIN));
    /*
     *	The largest possible integer in a double-precision floating point number.
     *
     *	Usually defaults to 1.7976931348623157e+308.
     */
    rb_define_const(rb_cFloat, "MAX", DBL2NUM(DBL_MAX));
    /*
     *	The difference between 1 and the smallest double-precision floating
     *	point number greater than 1.
     *
     *	Usually defaults to 2.2204460492503131e-16.
     */
    rb_define_const(rb_cFloat, "EPSILON", DBL2NUM(DBL_EPSILON));
    /*
     *	An expression representing positive infinity.
     */
    rb_define_const(rb_cFloat, "INFINITY", DBL2NUM(HUGE_VAL));
    /*
     *	An expression representing a value which is "not a number".
     */
    rb_define_const(rb_cFloat, "NAN", DBL2NUM(nan("")));

    rb_define_method(rb_cFloat, "to_s", flo_to_s, 0);
    rb_define_alias(rb_cFloat, "inspect", "to_s");
    rb_define_method(rb_cFloat, "coerce", flo_coerce, 1);
    rb_define_method(rb_cFloat, "+", rb_float_plus, 1);
    rb_define_method(rb_cFloat, "-", rb_float_minus, 1);
    rb_define_method(rb_cFloat, "*", rb_float_mul, 1);
    rb_define_method(rb_cFloat, "/", rb_float_div, 1);
    rb_define_method(rb_cFloat, "quo", flo_quo, 1);
    rb_define_method(rb_cFloat, "fdiv", flo_quo, 1);
    rb_define_method(rb_cFloat, "%", flo_mod, 1);
    rb_define_method(rb_cFloat, "modulo", flo_mod, 1);
    rb_define_method(rb_cFloat, "divmod", flo_divmod, 1);
    rb_define_method(rb_cFloat, "**", rb_float_pow, 1);
    rb_define_method(rb_cFloat, "==", flo_eq, 1);
    rb_define_method(rb_cFloat, "===", flo_eq, 1);
    rb_define_method(rb_cFloat, "<=>", flo_cmp, 1);
    rb_define_method(rb_cFloat, ">",  rb_float_gt, 1);
    rb_define_method(rb_cFloat, ">=", flo_ge, 1);
    rb_define_method(rb_cFloat, "<",  flo_lt, 1);
    rb_define_method(rb_cFloat, "<=", flo_le, 1);
    rb_define_method(rb_cFloat, "eql?", flo_eql, 1);
    rb_define_method(rb_cFloat, "hash", flo_hash, 0);

    rb_define_method(rb_cFloat, "to_i", flo_to_i, 0);
    rb_define_method(rb_cFloat, "to_int", flo_to_i, 0);
    rb_define_method(rb_cFloat, "floor", flo_floor, -1);
    rb_define_method(rb_cFloat, "ceil", flo_ceil, -1);
    rb_define_method(rb_cFloat, "round", flo_round, -1);
    rb_define_method(rb_cFloat, "truncate", flo_truncate, -1);

    rb_define_method(rb_cFloat, "nan?",      flo_is_nan_p, 0);
    rb_define_method(rb_cFloat, "infinite?", rb_flo_is_infinite_p, 0);
    rb_define_method(rb_cFloat, "finite?",   rb_flo_is_finite_p, 0);
    rb_define_method(rb_cFloat, "next_float", flo_next_float, 0);
    rb_define_method(rb_cFloat, "prev_float", flo_prev_float, 0);
}

#undef rb_float_value
double
rb_float_value(VALUE v)
{
    return rb_float_value_inline(v);
}

#undef rb_float_new
VALUE
rb_float_new(double d)
{
    return rb_float_new_inline(d);
}

#include "numeric.rbinc"
