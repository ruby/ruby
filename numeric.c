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
    double f, d, xs = x * s;

    if (x > 0.0) {
	f = floor(xs);
	d = xs - f;
	if (d > 0.5)
	    d = 1.0;
	else if (d == 0.5 || ((double)((f + 0.5) / s) <= x))
	    d = fmod(f, 2.0);
	else
	    d = 0.0;
	x = f + d;
    }
    else if (x < 0.0) {
	f = ceil(xs);
	d = f - xs;
	if (d > 0.5)
	    d = 1.0;
	else if (d == 0.5 || ((double)((f - 0.5) / s) >= x))
	    d = fmod(-f, 2.0);
	else
	    d = 0.0;
	x = f - d;
    }
    return x;
}

static VALUE fix_uminus(VALUE num);
static VALUE fix_mul(VALUE x, VALUE y);
static VALUE fix_lshift(long, unsigned long);
static VALUE fix_rshift(long, unsigned long);
static VALUE int_pow(long x, unsigned long y);
static VALUE int_even_p(VALUE x);
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

    if (RB_TYPE_P(val, T_BIGNUM)) {
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
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
 *     num.coerce(numeric)  ->  array
 *
 *  If +numeric+ is the same type as +num+, returns an array
 *  <code>[numeric, num]</code>. Otherwise, returns an array with both
 *  +numeric+ and +num+ represented as Float objects.
 *
 *  This coercion mechanism is used by Ruby to handle mixed-type numeric
 *  operations: it is intended to find a compatible common type between the two
 *  operands of the operator.
 *
 *     1.coerce(2.5)   #=> [2.5, 1.0]
 *     1.2.coerce(3)   #=> [3.0, 1.2]
 *     1.coerce(2)     #=> [2, 1]
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
    if (ary == Qundef) {
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

VALUE
rb_num_coerce_relop(VALUE x, VALUE y, ID func)
{
    VALUE c, x0 = x, y0 = y;

    if (!do_coerce(&x, &y, FALSE) ||
	NIL_P(c = rb_funcall(x, func, 1, y))) {
	rb_cmperr(x0, y0);
	return Qnil;		/* not reached */
    }
    return c;
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
 *     num.clone(freeze: true)  ->  num
 *
 *  Returns the receiver.  +freeze+ cannot be +false+.
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
 *     num.dup  ->  num
 *
 *  Returns the receiver.
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
 *     +num  ->  num
 *
 *  Unary Plus---Returns the receiver.
 */

static VALUE
num_uplus(VALUE num)
{
    return num;
}

/*
 *  call-seq:
 *     num.i  ->  Complex(0, num)
 *
 *  Returns the corresponding imaginary number.
 *  Not available for complex numbers.
 *
 *     -42.i  #=> (0-42i)
 *     2.0.i  #=> (0+2.0i)
 */

static VALUE
num_imaginary(VALUE num)
{
    return rb_complex_new(INT2FIX(0), num);
}

/*
 *  call-seq:
 *     -num  ->  numeric
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
 *     num.fdiv(numeric)  ->  float
 *
 *  Returns float division.
 */

static VALUE
num_fdiv(VALUE x, VALUE y)
{
    return rb_funcall(rb_Float(x), '/', 1, y);
}

/*
 *  call-seq:
 *     num.div(numeric)  ->  integer
 *
 *  Uses +/+ to perform division, then converts the result to an integer.
 *  Numeric does not define the +/+ operator; this is left to subclasses.
 *
 *  Equivalent to <code>num.divmod(numeric)[0]</code>.
 *
 *  See Numeric#divmod.
 */

static VALUE
num_div(VALUE x, VALUE y)
{
    if (rb_equal(INT2FIX(0), y)) rb_num_zerodiv();
    return rb_funcall(num_funcall1(x, '/', y), rb_intern("floor"), 0);
}

/*
 *  call-seq:
 *     num.modulo(numeric)  ->  real
 *
 *  <code>x.modulo(y)</code> means <code>x-y*(x/y).floor</code>.
 *
 *  Equivalent to <code>num.divmod(numeric)[1]</code>.
 *
 *  See Numeric#divmod.
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
 *     num.remainder(numeric)  ->  real
 *
 *  <code>x.remainder(y)</code> means <code>x-y*(x/y).truncate</code>.
 *
 *  See Numeric#divmod.
 */

static VALUE
num_remainder(VALUE x, VALUE y)
{
    VALUE z = num_funcall1(x, '%', y);

    if ((!rb_equal(z, INT2FIX(0))) &&
	((rb_num_negative_int_p(x) &&
	  rb_num_positive_int_p(y)) ||
	 (rb_num_positive_int_p(x) &&
	  rb_num_negative_int_p(y)))) {
	return rb_funcall(z, '-', 1, y);
    }
    return z;
}

/*
 *  call-seq:
 *     num.divmod(numeric)  ->  array
 *
 *  Returns an array containing the quotient and modulus obtained by dividing
 *  +num+ by +numeric+.
 *
 *  If <code>q, r = x.divmod(y)</code>, then
 *
 *      q = floor(x/y)
 *      x = q*y + r
 *
 *  The quotient is rounded toward negative infinity, as shown in the
 *  following table:
 *
 *     a    |  b  |  a.divmod(b)  |   a/b   | a.modulo(b) | a.remainder(b)
 *    ------+-----+---------------+---------+-------------+---------------
 *     13   |  4  |   3,    1     |   3     |    1        |     1
 *    ------+-----+---------------+---------+-------------+---------------
 *     13   | -4  |  -4,   -3     |  -4     |   -3        |     1
 *    ------+-----+---------------+---------+-------------+---------------
 *    -13   |  4  |  -4,    3     |  -4     |    3        |    -1
 *    ------+-----+---------------+---------+-------------+---------------
 *    -13   | -4  |   3,   -1     |   3     |   -1        |    -1
 *    ------+-----+---------------+---------+-------------+---------------
 *     11.5 |  4  |   2,    3.5   |   2.875 |    3.5      |     3.5
 *    ------+-----+---------------+---------+-------------+---------------
 *     11.5 | -4  |  -3,   -0.5   |  -2.875 |   -0.5      |     3.5
 *    ------+-----+---------------+---------+-------------+---------------
 *    -11.5 |  4  |  -3,    0.5   |  -2.875 |    0.5      |    -3.5
 *    ------+-----+---------------+---------+-------------+---------------
 *    -11.5 | -4  |   2,   -3.5   |   2.875 |   -3.5      |    -3.5
 *
 *
 *  Examples
 *
 *     11.divmod(3)        #=> [3, 2]
 *     11.divmod(-3)       #=> [-4, -1]
 *     11.divmod(3.5)      #=> [3, 0.5]
 *     (-11).divmod(3.5)   #=> [-4, 3.0]
 *     11.5.divmod(3.5)    #=> [3, 1.0]
 */

static VALUE
num_divmod(VALUE x, VALUE y)
{
    return rb_assoc_new(num_div(x, y), num_modulo(x, y));
}

/*
 *  call-seq:
 *     num.real?  ->  true or false
 *
 *  Returns +true+ if +num+ is a real number (i.e. not Complex).
 */

static VALUE
num_real_p(VALUE num)
{
    return Qtrue;
}

/*
 *  call-seq:
 *     num.integer?  ->  true or false
 *
 *  Returns +true+ if +num+ is an Integer.
 *
 *      1.0.integer?   #=> false
 *      1.integer?     #=> true
 */

static VALUE
num_int_p(VALUE num)
{
    return Qfalse;
}

/*
 *  call-seq:
 *     num.abs        ->  numeric
 *     num.magnitude  ->  numeric
 *
 *  Returns the absolute value of +num+.
 *
 *     12.abs         #=> 12
 *     (-34.56).abs   #=> 34.56
 *     -34.56.abs     #=> 34.56
 *
 *  Numeric#magnitude is an alias for Numeric#abs.
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
 *     num.zero?  ->  true or false
 *
 *  Returns +true+ if +num+ has a zero value.
 */

static VALUE
num_zero_p(VALUE num)
{
    if (rb_equal(num, INT2FIX(0))) {
        return Qtrue;
    }
    return Qfalse;
}

static VALUE
int_zero_p(VALUE num)
{
    if (FIXNUM_P(num)) {
	if (FIXNUM_ZERO_P(num)) {
	    return Qtrue;
	}
    }
    else {
        assert(RB_TYPE_P(num, T_BIGNUM));
	if (rb_bigzero_p(num)) {
	    /* this should not happen usually */
	    return Qtrue;
	}
    }
    return Qfalse;
}

VALUE
rb_int_zero_p(VALUE num)
{
    return int_zero_p(num);
}

/*
 *  call-seq:
 *     num.nonzero?  ->  self or nil
 *
 *  Returns +self+ if +num+ is not zero, +nil+ otherwise.
 *
 *  This behavior is useful when chaining comparisons:
 *
 *     a = %w( z Bb bB bb BB a aA Aa AA A )
 *     b = a.sort {|a,b| (a.downcase <=> b.downcase).nonzero? || a <=> b }
 *     b   #=> ["A", "a", "AA", "Aa", "aA", "BB", "Bb", "bB", "bb", "z"]
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
 *     num.finite?  ->  true or false
 *
 *  Returns +true+ if +num+ is a finite number, otherwise returns +false+.
 */
static VALUE
num_finite_p(VALUE num)
{
    return Qtrue;
}

/*
 *  call-seq:
 *     num.infinite?  ->  -1, 1, or nil
 *
 *  Returns +nil+, -1, or 1 depending on whether the value is
 *  finite, <code>-Infinity</code>, or <code>+Infinity</code>.
 */
static VALUE
num_infinite_p(VALUE num)
{
    return Qnil;
}

/*
 *  call-seq:
 *     num.to_int  ->  integer
 *
 *  Invokes the child class's +to_i+ method to convert +num+ to an integer.
 *
 *      1.0.class          #=> Float
 *      1.0.to_int.class   #=> Integer
 *      1.0.to_i.class     #=> Integer
 */

static VALUE
num_to_int(VALUE num)
{
    return num_funcall0(num, id_to_i);
}

/*
 *  call-seq:
 *     num.positive?  ->  true or false
 *
 *  Returns +true+ if +num+ is greater than 0.
 */

static VALUE
num_positive_p(VALUE num)
{
    const ID mid = '>';

    if (FIXNUM_P(num)) {
	if (method_basic_p(rb_cInteger))
	    return (SIGNED_VALUE)num > (SIGNED_VALUE)INT2FIX(0) ? Qtrue : Qfalse;
    }
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	if (method_basic_p(rb_cInteger))
	    return BIGNUM_POSITIVE_P(num) && !rb_bigzero_p(num) ? Qtrue : Qfalse;
    }
    return rb_num_compare_with_zero(num, mid);
}

/*
 *  call-seq:
 *     num.negative?  ->  true or false
 *
 *  Returns +true+ if +num+ is less than 0.
 */

static VALUE
num_negative_p(VALUE num)
{
    return rb_num_negative_int_p(num) ? Qtrue : Qfalse;
}


/********************************************************************
 *
 * Document-class: Float
 *
 *  Float objects represent inexact real numbers using the native
 *  architecture's double-precision floating point representation.
 *
 *  Floating point has a different arithmetic and is an inexact number.
 *  So you should know its esoteric system. See following:
 *
 *  - https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html
 *  - https://github.com/rdp/ruby_tutorials_core/wiki/Ruby-Talk-FAQ#floats_imprecise
 *  - https://en.wikipedia.org/wiki/Floating_point#Accuracy_problems
 */

VALUE
rb_float_new_in_heap(double d)
{
    NEWOBJ_OF(flt, struct RFloat, rb_cFloat, T_FLOAT | (RGENGC_WB_PROTECTED_FLOAT ? FL_WB_PROTECTED : 0));

    flt->float_value = d;
    OBJ_FREEZE((VALUE)flt);
    return (VALUE)flt;
}

/*
 *  call-seq:
 *     float.to_s  ->  string
 *
 *  Returns a string containing a representation of +self+.
 *  As well as a fixed or exponential form of the +float+,
 *  the call may return +NaN+, +Infinity+, and +-Infinity+.
 */

static VALUE
flo_to_s(VALUE flt)
{
    enum {decimal_mant = DBL_MANT_DIG-DBL_DIG};
    enum {float_dig = DBL_DIG+1};
    char buf[float_dig + (decimal_mant + CHAR_BIT - 1) / CHAR_BIT + 10];
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
    xfree(p);
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
 *     float.coerce(numeric)  ->  array
 *
 *  Returns an array with both +numeric+ and +float+ represented as Float
 *  objects.
 *
 *  This is achieved by converting +numeric+ to a Float.
 *
 *     1.2.coerce(3)       #=> [3.0, 1.2]
 *     2.5.coerce(1.1)     #=> [1.1, 2.5]
 */

static VALUE
flo_coerce(VALUE x, VALUE y)
{
    return rb_assoc_new(rb_Float(y), x);
}

/*
 * call-seq:
 *    -float  ->  float
 *
 * Returns +float+, negated.
 */

VALUE
rb_float_uminus(VALUE flt)
{
    return DBL2NUM(-RFLOAT_VALUE(flt));
}

/*
 * call-seq:
 *   float + other  ->  float
 *
 * Returns a new Float which is the sum of +float+ and +other+.
 */

VALUE
rb_float_plus(VALUE x, VALUE y)
{
    if (RB_TYPE_P(y, T_FIXNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) + (double)FIX2LONG(y));
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) + rb_big2dbl(y));
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM(RFLOAT_VALUE(x) + RFLOAT_VALUE(y));
    }
    else {
	return rb_num_coerce_bin(x, y, '+');
    }
}

/*
 * call-seq:
 *   float - other  ->  float
 *
 * Returns a new Float which is the difference of +float+ and +other+.
 */

static VALUE
flo_minus(VALUE x, VALUE y)
{
    if (RB_TYPE_P(y, T_FIXNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) - (double)FIX2LONG(y));
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) - rb_big2dbl(y));
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM(RFLOAT_VALUE(x) - RFLOAT_VALUE(y));
    }
    else {
	return rb_num_coerce_bin(x, y, '-');
    }
}

/*
 * call-seq:
 *   float * other  ->  float
 *
 * Returns a new Float which is the product of +float+ and +other+.
 */

VALUE
rb_float_mul(VALUE x, VALUE y)
{
    if (RB_TYPE_P(y, T_FIXNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) * (double)FIX2LONG(y));
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return DBL2NUM(RFLOAT_VALUE(x) * rb_big2dbl(y));
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM(RFLOAT_VALUE(x) * RFLOAT_VALUE(y));
    }
    else {
	return rb_num_coerce_bin(x, y, '*');
    }
}

static bool
flo_iszero(VALUE f)
{
    return FLOAT_ZERO_P(f);
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

MJIT_FUNC_EXPORTED VALUE
rb_flo_div_flo(VALUE x, VALUE y)
{
    double num = RFLOAT_VALUE(x);
    double den = RFLOAT_VALUE(y);
    double ret = double_div_double(num, den);
    return DBL2NUM(ret);
}

/*
 * call-seq:
 *   float / other  ->  float
 *
 * Returns a new Float which is the result of dividing +float+ by +other+.
 */

VALUE
rb_float_div(VALUE x, VALUE y)
{
    double num = RFLOAT_VALUE(x);
    double den;
    double ret;

    if (RB_TYPE_P(y, T_FIXNUM)) {
        den = FIX2LONG(y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
        den = rb_big2dbl(y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
 *     float.fdiv(numeric)  ->  float
 *     float.quo(numeric)   ->  float
 *
 *  Returns <code>float / numeric</code>, same as Float#/.
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

MJIT_FUNC_EXPORTED double
ruby_float_mod(double x, double y)
{
    double mod;
    flodivmod(x, y, 0, &mod);
    return mod;
}

/*
 *  call-seq:
 *     float % other        ->  float
 *     float.modulo(other)  ->  float
 *
 *  Returns the modulo after division of +float+ by +other+.
 *
 *     6543.21.modulo(137)      #=> 104.21000000000004
 *     6543.21.modulo(137.24)   #=> 92.92999999999961
 */

static VALUE
flo_mod(VALUE x, VALUE y)
{
    double fy;

    if (RB_TYPE_P(y, T_FIXNUM)) {
	fy = (double)FIX2LONG(y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	fy = rb_big2dbl(y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
 *     float.divmod(numeric)  ->  array
 *
 *  See Numeric#divmod.
 *
 *     42.0.divmod(6)   #=> [7, 0.0]
 *     42.0.divmod(5)   #=> [8, 2.0]
 */

static VALUE
flo_divmod(VALUE x, VALUE y)
{
    double fy, div, mod;
    volatile VALUE a, b;

    if (RB_TYPE_P(y, T_FIXNUM)) {
	fy = (double)FIX2LONG(y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	fy = rb_big2dbl(y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
 * call-seq:
 *    float ** other  ->  float
 *
 * Raises +float+ to the power of +other+.
 *
 *    2.0**3   #=> 8.0
 */

VALUE
rb_float_pow(VALUE x, VALUE y)
{
    double dx, dy;
    if (y == INT2FIX(2)) {
	dx = RFLOAT_VALUE(x);
        return DBL2NUM(dx * dx);
    }
    else if (RB_TYPE_P(y, T_FIXNUM)) {
	dx = RFLOAT_VALUE(x);
	dy = (double)FIX2LONG(y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	dx = RFLOAT_VALUE(x);
	dy = rb_big2dbl(y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
 *     num.eql?(numeric)  ->  true or false
 *
 *  Returns +true+ if +num+ and +numeric+ are the same type and have equal
 *  values.  Contrast this with Numeric#==, which performs type conversions.
 *
 *     1 == 1.0        #=> true
 *     1.eql?(1.0)     #=> false
 *     1.0.eql?(1.0)   #=> true
 */

static VALUE
num_eql(VALUE x, VALUE y)
{
    if (TYPE(x) != TYPE(y)) return Qfalse;

    if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_eql(x, y);
    }

    return rb_equal(x, y);
}

/*
 *  call-seq:
 *     number <=> other  ->  0 or nil
 *
 *  Returns zero if +number+ equals +other+, otherwise returns +nil+.
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
    if (RTEST(result)) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     float == obj  ->  true or false
 *
 *  Returns +true+ only if +obj+ has the same value as +float+.
 *  Contrast this with Float#eql?, which requires +obj+ to be a Float.
 *
 *     1.0 == 1   #=> true
 *
 *  The result of <code>NaN == NaN</code> is undefined,
 *  so an implementation-dependent value is returned.
 */

MJIT_FUNC_EXPORTED VALUE
rb_float_equal(VALUE x, VALUE y)
{
    volatile double a, b;

    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        return rb_integer_float_eq(y, x);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
    return (a == b)?Qtrue:Qfalse;
}

#define flo_eq rb_float_equal
static VALUE rb_dbl_hash(double d);

/*
 * call-seq:
 *    float.hash  ->  integer
 *
 * Returns a hash code for this float.
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
 *     float <=> real  ->  -1, 0, +1, or nil
 *
 *  Returns -1, 0, or +1 depending on whether +float+ is
 *  less than, equal to, or greater than +real+.
 *  This is the basis for the tests in the Comparable module.
 *
 *  The result of <code>NaN <=> NaN</code> is undefined,
 *  so an implementation-dependent value is returned.
 *
 *  +nil+ is returned if the two values are incomparable.
 */

static VALUE
flo_cmp(VALUE x, VALUE y)
{
    double a, b;
    VALUE i;

    a = RFLOAT_VALUE(x);
    if (isnan(a)) return Qnil;
    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return LONG2FIX(-FIX2LONG(rel));
        return rel;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	b = RFLOAT_VALUE(y);
    }
    else {
	if (isinf(a) && (i = rb_check_funcall(y, rb_intern("infinite?"), 0, 0)) != Qundef) {
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

MJIT_FUNC_EXPORTED int
rb_float_cmp(VALUE x, VALUE y)
{
    return NUM2INT(flo_cmp(x, y));
}

/*
 * call-seq:
 *   float > real  ->  true or false
 *
 * Returns +true+ if +float+ is greater than +real+.
 *
 * The result of <code>NaN > NaN</code> is undefined,
 * so an implementation-dependent value is returned.
 */

VALUE
rb_float_gt(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return -FIX2LONG(rel) > 0 ? Qtrue : Qfalse;
        return Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
    return (a > b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   float >= real  ->  true or false
 *
 * Returns +true+ if +float+ is greater than or equal to +real+.
 *
 * The result of <code>NaN >= NaN</code> is undefined,
 * so an implementation-dependent value is returned.
 */

static VALUE
flo_ge(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return -FIX2LONG(rel) >= 0 ? Qtrue : Qfalse;
        return Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
    return (a >= b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   float < real  ->  true or false
 *
 * Returns +true+ if +float+ is less than +real+.
 *
 * The result of <code>NaN < NaN</code> is undefined,
 * so an implementation-dependent value is returned.
 */

static VALUE
flo_lt(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return -FIX2LONG(rel) < 0 ? Qtrue : Qfalse;
        return Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
    return (a < b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   float <= real  ->  true or false
 *
 * Returns +true+ if +float+ is less than or equal to +real+.
 *
 * The result of <code>NaN <= NaN</code> is undefined,
 * so an implementation-dependent value is returned.
 */

static VALUE
flo_le(VALUE x, VALUE y)
{
    double a, b;

    a = RFLOAT_VALUE(x);
    if (RB_TYPE_P(y, T_FIXNUM) || RB_TYPE_P(y, T_BIGNUM)) {
        VALUE rel = rb_integer_float_cmp(y, x);
        if (FIXNUM_P(rel))
            return -FIX2LONG(rel) <= 0 ? Qtrue : Qfalse;
        return Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
    return (a <= b)?Qtrue:Qfalse;
}

/*
 *  call-seq:
 *     float.eql?(obj)  ->  true or false
 *
 *  Returns +true+ only if +obj+ is a Float with the same value as +float+.
 *  Contrast this with Float#==, which performs type conversions.
 *
 *     1.0.eql?(1)   #=> false
 *
 *  The result of <code>NaN.eql?(NaN)</code> is undefined,
 *  so an implementation-dependent value is returned.
 */

MJIT_FUNC_EXPORTED VALUE
rb_float_eql(VALUE x, VALUE y)
{
    if (RB_TYPE_P(y, T_FLOAT)) {
	double a = RFLOAT_VALUE(x);
	double b = RFLOAT_VALUE(y);
#if MSC_VERSION_BEFORE(1300)
	if (isnan(a) || isnan(b)) return Qfalse;
#endif
	if (a == b)
	    return Qtrue;
    }
    return Qfalse;
}

#define flo_eql rb_float_eql

/*
 * call-seq:
 *    float.to_f  ->  self
 *
 * Since +float+ is already a Float, returns +self+.
 */

static VALUE
flo_to_f(VALUE num)
{
    return num;
}

/*
 *  call-seq:
 *     float.abs        ->  float
 *     float.magnitude  ->  float
 *
 *  Returns the absolute value of +float+.
 *
 *     (-34.56).abs   #=> 34.56
 *     -34.56.abs     #=> 34.56
 *     34.56.abs      #=> 34.56
 *
 *  Float#magnitude is an alias for Float#abs.
 */

VALUE
rb_float_abs(VALUE flt)
{
    double val = fabs(RFLOAT_VALUE(flt));
    return DBL2NUM(val);
}

/*
 *  call-seq:
 *     float.zero?  ->  true or false
 *
 *  Returns +true+ if +float+ is 0.0.
 */

static VALUE
flo_zero_p(VALUE num)
{
    return flo_iszero(num) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     float.nan?  ->  true or false
 *
 *  Returns +true+ if +float+ is an invalid IEEE floating point number.
 *
 *     a = -1.0      #=> -1.0
 *     a.nan?        #=> false
 *     a = 0.0/0.0   #=> NaN
 *     a.nan?        #=> true
 */

static VALUE
flo_is_nan_p(VALUE num)
{
    double value = RFLOAT_VALUE(num);

    return isnan(value) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     float.infinite?  ->  -1, 1, or nil
 *
 *  Returns +nil+, -1, or 1 depending on whether the value is
 *  finite, <code>-Infinity</code>, or <code>+Infinity</code>.
 *
 *     (0.0).infinite?        #=> nil
 *     (-1.0/0.0).infinite?   #=> -1
 *     (+1.0/0.0).infinite?   #=> 1
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
 *     float.finite?  ->  true or false
 *
 *  Returns +true+ if +float+ is a valid IEEE floating point number,
 *  i.e. it is not infinite and Float#nan? is +false+.
 */

VALUE
rb_flo_is_finite_p(VALUE num)
{
    double value = RFLOAT_VALUE(num);

#ifdef HAVE_ISFINITE
    if (!isfinite(value))
	return Qfalse;
#else
    if (isinf(value) || isnan(value))
	return Qfalse;
#endif

    return Qtrue;
}

/*
 *  call-seq:
 *     float.next_float  ->  float
 *
 *  Returns the next representable floating point number.
 *
 *  Float::MAX.next_float and Float::INFINITY.next_float is Float::INFINITY.
 *
 *  Float::NAN.next_float is Float::NAN.
 *
 *  For example:
 *
 *    0.01.next_float    #=> 0.010000000000000002
 *    1.0.next_float     #=> 1.0000000000000002
 *    100.0.next_float   #=> 100.00000000000001
 *
 *    0.01.next_float - 0.01     #=> 1.734723475976807e-18
 *    1.0.next_float - 1.0       #=> 2.220446049250313e-16
 *    100.0.next_float - 100.0   #=> 1.4210854715202004e-14
 *
 *    f = 0.01; 20.times { printf "%-20a %s\n", f, f.to_s; f = f.next_float }
 *    #=> 0x1.47ae147ae147bp-7 0.01
 *    #   0x1.47ae147ae147cp-7 0.010000000000000002
 *    #   0x1.47ae147ae147dp-7 0.010000000000000004
 *    #   0x1.47ae147ae147ep-7 0.010000000000000005
 *    #   0x1.47ae147ae147fp-7 0.010000000000000007
 *    #   0x1.47ae147ae148p-7  0.010000000000000009
 *    #   0x1.47ae147ae1481p-7 0.01000000000000001
 *    #   0x1.47ae147ae1482p-7 0.010000000000000012
 *    #   0x1.47ae147ae1483p-7 0.010000000000000014
 *    #   0x1.47ae147ae1484p-7 0.010000000000000016
 *    #   0x1.47ae147ae1485p-7 0.010000000000000018
 *    #   0x1.47ae147ae1486p-7 0.01000000000000002
 *    #   0x1.47ae147ae1487p-7 0.010000000000000021
 *    #   0x1.47ae147ae1488p-7 0.010000000000000023
 *    #   0x1.47ae147ae1489p-7 0.010000000000000024
 *    #   0x1.47ae147ae148ap-7 0.010000000000000026
 *    #   0x1.47ae147ae148bp-7 0.010000000000000028
 *    #   0x1.47ae147ae148cp-7 0.01000000000000003
 *    #   0x1.47ae147ae148dp-7 0.010000000000000031
 *    #   0x1.47ae147ae148ep-7 0.010000000000000033
 *
 *    f = 0.0
 *    100.times { f += 0.1 }
 *    f                           #=> 9.99999999999998       # should be 10.0 in the ideal world.
 *    10-f                        #=> 1.9539925233402755e-14 # the floating point error.
 *    10.0.next_float-10          #=> 1.7763568394002505e-15 # 1 ulp (unit in the last place).
 *    (10-f)/(10.0.next_float-10) #=> 11.0                   # the error is 11 ulp.
 *    (10-f)/(10*Float::EPSILON)  #=> 8.8                    # approximation of the above.
 *    "%a" % 10                   #=> "0x1.4p+3"
 *    "%a" % f                    #=> "0x1.3fffffffffff5p+3" # the last hex digit is 5.  16 - 5 = 11 ulp.
 */
static VALUE
flo_next_float(VALUE vx)
{
    double x, y;
    x = NUM2DBL(vx);
    y = nextafter(x, HUGE_VAL);
    return DBL2NUM(y);
}

/*
 *  call-seq:
 *     float.prev_float  ->  float
 *
 *  Returns the previous representable floating point number.
 *
 *  (-Float::MAX).prev_float and (-Float::INFINITY).prev_float is -Float::INFINITY.
 *
 *  Float::NAN.prev_float is Float::NAN.
 *
 *  For example:
 *
 *    0.01.prev_float    #=> 0.009999999999999998
 *    1.0.prev_float     #=> 0.9999999999999999
 *    100.0.prev_float   #=> 99.99999999999999
 *
 *    0.01 - 0.01.prev_float     #=> 1.734723475976807e-18
 *    1.0 - 1.0.prev_float       #=> 1.1102230246251565e-16
 *    100.0 - 100.0.prev_float   #=> 1.4210854715202004e-14
 *
 *    f = 0.01; 20.times { printf "%-20a %s\n", f, f.to_s; f = f.prev_float }
 *    #=> 0x1.47ae147ae147bp-7 0.01
 *    #   0x1.47ae147ae147ap-7 0.009999999999999998
 *    #   0x1.47ae147ae1479p-7 0.009999999999999997
 *    #   0x1.47ae147ae1478p-7 0.009999999999999995
 *    #   0x1.47ae147ae1477p-7 0.009999999999999993
 *    #   0x1.47ae147ae1476p-7 0.009999999999999992
 *    #   0x1.47ae147ae1475p-7 0.00999999999999999
 *    #   0x1.47ae147ae1474p-7 0.009999999999999988
 *    #   0x1.47ae147ae1473p-7 0.009999999999999986
 *    #   0x1.47ae147ae1472p-7 0.009999999999999985
 *    #   0x1.47ae147ae1471p-7 0.009999999999999983
 *    #   0x1.47ae147ae147p-7  0.009999999999999981
 *    #   0x1.47ae147ae146fp-7 0.00999999999999998
 *    #   0x1.47ae147ae146ep-7 0.009999999999999978
 *    #   0x1.47ae147ae146dp-7 0.009999999999999976
 *    #   0x1.47ae147ae146cp-7 0.009999999999999974
 *    #   0x1.47ae147ae146bp-7 0.009999999999999972
 *    #   0x1.47ae147ae146ap-7 0.00999999999999997
 *    #   0x1.47ae147ae1469p-7 0.009999999999999969
 *    #   0x1.47ae147ae1468p-7 0.009999999999999967
 */
static VALUE
flo_prev_float(VALUE vx)
{
    double x, y;
    x = NUM2DBL(vx);
    y = nextafter(x, -HUGE_VAL);
    return DBL2NUM(y);
}

/*
 *  call-seq:
 *     float.floor([ndigits])  ->  integer or float
 *
 *  Returns the largest number less than or equal to +float+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns a floating point number when +ndigits+ is positive,
 *  otherwise returns an integer.
 *
 *     1.2.floor      #=> 1
 *     2.0.floor      #=> 2
 *     (-1.2).floor   #=> -2
 *     (-2.0).floor   #=> -2
 *
 *     1.234567.floor(2)   #=> 1.23
 *     1.234567.floor(3)   #=> 1.234
 *     1.234567.floor(4)   #=> 1.2345
 *     1.234567.floor(5)   #=> 1.23456
 *
 *     34567.89.floor(-5)  #=> 0
 *     34567.89.floor(-4)  #=> 30000
 *     34567.89.floor(-3)  #=> 34000
 *     34567.89.floor(-2)  #=> 34500
 *     34567.89.floor(-1)  #=> 34560
 *     34567.89.floor(0)   #=> 34567
 *     34567.89.floor(1)   #=> 34567.8
 *     34567.89.floor(2)   #=> 34567.89
 *     34567.89.floor(3)   #=> 34567.89
 *
 *  Note that the limited precision of floating point arithmetic
 *  might lead to surprising results:
 *
 *     (0.3 / 0.1).floor  #=> 2 (!)
 */

static VALUE
flo_floor(int argc, VALUE *argv, VALUE num)
{
    double number, f;
    int ndigits = 0;

    if (rb_check_arity(argc, 0, 1)) {
	ndigits = NUM2INT(argv[0]);
    }
    number = RFLOAT_VALUE(num);
    if (number == 0.0) {
	return ndigits > 0 ? DBL2NUM(number) : INT2FIX(0);
    }
    if (ndigits > 0) {
	int binexp;
	frexp(number, &binexp);
	if (float_round_overflow(ndigits, binexp)) return num;
	if (number > 0.0 && float_round_underflow(ndigits, binexp))
	    return DBL2NUM(0.0);
	f = pow(10, ndigits);
	f = floor(number * f) / f;
	return DBL2NUM(f);
    }
    else {
	num = dbl2ival(floor(number));
	if (ndigits < 0) num = rb_int_floor(num, ndigits);
	return num;
    }
}

/*
 *  call-seq:
 *     float.ceil([ndigits])  ->  integer or float
 *
 *  Returns the smallest number greater than or equal to +float+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns a floating point number when +ndigits+ is positive,
 *  otherwise returns an integer.
 *
 *     1.2.ceil      #=> 2
 *     2.0.ceil      #=> 2
 *     (-1.2).ceil   #=> -1
 *     (-2.0).ceil   #=> -2
 *
 *     1.234567.ceil(2)   #=> 1.24
 *     1.234567.ceil(3)   #=> 1.235
 *     1.234567.ceil(4)   #=> 1.2346
 *     1.234567.ceil(5)   #=> 1.23457
 *
 *     34567.89.ceil(-5)  #=> 100000
 *     34567.89.ceil(-4)  #=> 40000
 *     34567.89.ceil(-3)  #=> 35000
 *     34567.89.ceil(-2)  #=> 34600
 *     34567.89.ceil(-1)  #=> 34570
 *     34567.89.ceil(0)   #=> 34568
 *     34567.89.ceil(1)   #=> 34567.9
 *     34567.89.ceil(2)   #=> 34567.89
 *     34567.89.ceil(3)   #=> 34567.89
 *
 *  Note that the limited precision of floating point arithmetic
 *  might lead to surprising results:
 *
 *     (2.1 / 0.7).ceil  #=> 4 (!)
 */

static VALUE
flo_ceil(int argc, VALUE *argv, VALUE num)
{
    int ndigits = 0;

    if (rb_check_arity(argc, 0, 1)) {
	ndigits = NUM2INT(argv[0]);
    }
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
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
 * Assumes num is an Integer, ndigits <= 0
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
    if (RB_TYPE_P(f, T_FLOAT)) {
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
    if (RB_TYPE_P(f, T_FLOAT)) {
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
    if (RB_TYPE_P(f, T_FLOAT)) {
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
    if (RB_TYPE_P(f, T_FLOAT)) {
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
 *     float.round([ndigits] [, half: mode])  ->  integer or float
 *
 *  Returns +float+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns a floating point number when +ndigits+ is positive,
 *  otherwise returns an integer.
 *
 *     1.4.round      #=> 1
 *     1.5.round      #=> 2
 *     1.6.round      #=> 2
 *     (-1.5).round   #=> -2
 *
 *     1.234567.round(2)   #=> 1.23
 *     1.234567.round(3)   #=> 1.235
 *     1.234567.round(4)   #=> 1.2346
 *     1.234567.round(5)   #=> 1.23457
 *
 *     34567.89.round(-5)  #=> 0
 *     34567.89.round(-4)  #=> 30000
 *     34567.89.round(-3)  #=> 35000
 *     34567.89.round(-2)  #=> 34600
 *     34567.89.round(-1)  #=> 34570
 *     34567.89.round(0)   #=> 34568
 *     34567.89.round(1)   #=> 34567.9
 *     34567.89.round(2)   #=> 34567.89
 *     34567.89.round(3)   #=> 34567.89
 *
 *  If the optional +half+ keyword argument is given,
 *  numbers that are half-way between two possible rounded values
 *  will be rounded according to the specified tie-breaking +mode+:
 *
 *  * <code>:up</code> or +nil+: round half away from zero (default)
 *  * <code>:down</code>: round half toward zero
 *  * <code>:even</code>: round half toward the nearest even number
 *
 *     2.5.round(half: :up)      #=> 3
 *     2.5.round(half: :down)    #=> 2
 *     2.5.round(half: :even)    #=> 2
 *     3.5.round(half: :up)      #=> 4
 *     3.5.round(half: :down)    #=> 3
 *     3.5.round(half: :even)    #=> 4
 *     (-2.5).round(half: :up)   #=> -3
 *     (-2.5).round(half: :down) #=> -2
 *     (-2.5).round(half: :even) #=> -2
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
 *     float.to_i    ->  integer
 *     float.to_int  ->  integer
 *
 *  Returns the +float+ truncated to an Integer.
 *
 *     1.2.to_i      #=> 1
 *     (-1.2).to_i   #=> -1
 *
 *  Note that the limited precision of floating point arithmetic
 *  might lead to surprising results:
 *
 *    (0.3 / 0.1).to_i  #=> 2 (!)
 *
 *  #to_int is an alias for #to_i.
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
 *     float.truncate([ndigits])  ->  integer or float
 *
 *  Returns +float+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns a floating point number when +ndigits+ is positive,
 *  otherwise returns an integer.
 *
 *     2.8.truncate           #=> 2
 *     (-2.8).truncate        #=> -2
 *     1.234567.truncate(2)   #=> 1.23
 *     34567.89.truncate(-2)  #=> 34500
 *
 *  Note that the limited precision of floating point arithmetic
 *  might lead to surprising results:
 *
 *     (0.3 / 0.1).truncate  #=> 2 (!)
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
 *     float.positive?  ->  true or false
 *
 *  Returns +true+ if +float+ is greater than 0.
 */

static VALUE
flo_positive_p(VALUE num)
{
    double f = RFLOAT_VALUE(num);
    return f > 0.0 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     float.negative?  ->  true or false
 *
 *  Returns +true+ if +float+ is less than 0.
 */

static VALUE
flo_negative_p(VALUE num)
{
    double f = RFLOAT_VALUE(num);
    return f < 0.0 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     num.floor([ndigits])  ->  integer or float
 *
 *  Returns the largest number less than or equal to +num+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Numeric implements this by converting its value to a Float and
 *  invoking Float#floor.
 */

static VALUE
num_floor(int argc, VALUE *argv, VALUE num)
{
    return flo_floor(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *     num.ceil([ndigits])  ->  integer or float
 *
 *  Returns the smallest number greater than or equal to +num+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Numeric implements this by converting its value to a Float and
 *  invoking Float#ceil.
 */

static VALUE
num_ceil(int argc, VALUE *argv, VALUE num)
{
    return flo_ceil(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *     num.round([ndigits])  ->  integer or float
 *
 *  Returns +num+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Numeric implements this by converting its value to a Float and
 *  invoking Float#round.
 */

static VALUE
num_round(int argc, VALUE* argv, VALUE num)
{
    return flo_round(argc, argv, rb_Float(num));
}

/*
 *  call-seq:
 *     num.truncate([ndigits])  ->  integer or float
 *
 *  Returns +num+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  Numeric implements this by converting its value to a Float and
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
    double n, err;

    if (unit == 0) {
        return HUGE_VAL;
    }
    n= (end - beg)/unit;
    err = (fabs(beg) + fabs(end) + fabs(end-beg)) / fabs(unit) * epsilon;
    if (isinf(unit)) {
	return unit > 0 ? beg <= end : beg >= end;
    }
    if (err>0.5) err=0.5;
    if (excl) {
	if (n<=0) return 0;
	if (n<1)
	    n = 0;
	else
	    n = floor(n - err);
    }
    else {
	if (n<0) return 0;
	n = floor(n + err);
    }
    return n+1;
}

int
ruby_float_step(VALUE from, VALUE to, VALUE step, int excl, int allow_endless)
{
    if (RB_TYPE_P(from, T_FLOAT) || RB_TYPE_P(to, T_FLOAT) || RB_TYPE_P(step, T_FLOAT)) {
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
    else if (RB_TYPE_P(from, T_FLOAT) || RB_TYPE_P(to, T_FLOAT) || RB_TYPE_P(step, T_FLOAT)) {
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
	if (!excl || RTEST(rb_funcall(rb_funcall(from, '+', 1, rb_funcall(result, '*', 1, step)), cmp, 1, to))) {
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	if (method_basic_p(rb_cInteger))
	    return BIGNUM_NEGATIVE_P(num);
    }

    r = rb_check_funcall(num, '>', 1, &zero);
    if (r == Qundef) {
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
	if (values[0] != Qundef) {
	    if (argc > 0) rb_raise(rb_eArgError, "to is given twice");
	    *to = values[0];
	}
	if (values[1] != Qundef) {
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
    if (by != Qundef) {
        *step = by;
    }
    else {
        /* compatibility */
        if (argc > 1 && NIL_P(*step)) {
            rb_raise(rb_eTypeError, "step must be numeric");
        }
        if (!allow_zero_step && rb_equal(*step, INT2FIX(0))) {
            rb_raise(rb_eArgError, "step can't be 0");
        }
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
 *     num.step(by: step, to: limit) {|i| block }   ->  self
 *     num.step(by: step, to: limit)                ->  an_enumerator
 *     num.step(by: step, to: limit)                ->  an_arithmetic_sequence
 *     num.step(limit=nil, step=1) {|i| block }     ->  self
 *     num.step(limit=nil, step=1)                  ->  an_enumerator
 *     num.step(limit=nil, step=1)                  ->  an_arithmetic_sequence
 *
 *  Invokes the given block with the sequence of numbers starting at +num+,
 *  incremented by +step+ (defaulted to +1+) on each call.
 *
 *  The loop finishes when the value to be passed to the block is greater than
 *  +limit+ (if +step+ is positive) or less than +limit+ (if +step+ is
 *  negative), where +limit+ is defaulted to infinity.
 *
 *  In the recommended keyword argument style, either or both of
 *  +step+ and +limit+ (default infinity) can be omitted.  In the
 *  fixed position argument style, zero as a step
 *  (i.e. <code>num.step(limit, 0)</code>) is not allowed for historical
 *  compatibility reasons.
 *
 *  If all the arguments are integers, the loop operates using an integer
 *  counter.
 *
 *  If any of the arguments are floating point numbers, all are converted
 *  to floats, and the loop is executed
 *  <i>floor(n + n*Float::EPSILON) + 1</i> times,
 *  where <i>n = (limit - num)/step</i>.
 *
 *  Otherwise, the loop starts at +num+, uses either the
 *  less-than (<code><</code>) or greater-than (<code>></code>) operator
 *  to compare the counter against +limit+,
 *  and increments itself using the <code>+</code> operator.
 *
 *  If no block is given, an Enumerator is returned instead.
 *  Especially, the enumerator is an Enumerator::ArithmeticSequence
 *  if both +limit+ and +step+ are kind of Numeric or <code>nil</code>.
 *
 *  For example:
 *
 *     p 1.step.take(4)
 *     p 10.step(by: -1).take(4)
 *     3.step(to: 5) {|i| print i, " " }
 *     1.step(10, 2) {|i| print i, " " }
 *     Math::E.step(to: Math::PI, by: 0.2) {|f| print f, " " }
 *
 *  Will produce:
 *
 *     [1, 2, 3, 4]
 *     [10, 9, 8, 7]
 *     3 4 5
 *     1 3 5 7 9
 *     2.718281828459045 2.9182818284590453 3.118281828459045
 */

static VALUE
num_step(int argc, VALUE *argv, VALUE from)
{
    VALUE to, step;
    int desc, inf;

    if (!rb_block_given_p()) {
        VALUE by = Qundef;

        num_step_extract_args(argc, argv, &to, &step, &by);
        if (by != Qundef) {
            step = by;
        }
        if (NIL_P(step)) {
            step = INT2FIX(1);
        }
        if ((NIL_P(to) || rb_obj_is_kind_of(to, rb_cNumeric)) &&
            rb_obj_is_kind_of(step, rb_cNumeric)) {
            return rb_arith_seq_new(from, ID2SYM(rb_frame_this_func()), argc, argv,
                                    num_step_size, from, to, step, FALSE);
        }

        return SIZED_ENUMERATOR(from, 2, ((VALUE [2]){to, step}), num_step_size);
    }

    desc = num_step_scan_args(argc, argv, &to, &step, TRUE, FALSE);
    if (rb_equal(step, INT2FIX(0))) {
	inf = 1;
    }
    else if (RB_TYPE_P(to, T_FLOAT)) {
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

    else if (RB_TYPE_P(val, T_FLOAT)) {
	if (RFLOAT_VALUE(val) < LONG_MAX_PLUS_ONE
	    && LONG_MIN_MINUS_ONE_IS_LESS_THAN(RFLOAT_VALUE(val))) {
	    return (long)RFLOAT_VALUE(val);
	}
	else {
	    FLOAT_OUT_OF_RANGE(val, "integer");
	}
    }
    else if (RB_TYPE_P(val, T_BIGNUM)) {
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
       rb_raise(rb_eTypeError, "no implicit conversion from nil to integer");
    }

    if (FIXNUM_P(val)) {
        long l = FIX2LONG(val); /* this is FIX2LONG, intended */
        if (wrap_p)
            *wrap_p = l < 0;
        return (unsigned long)l;
    }
    else if (RB_TYPE_P(val, T_FLOAT)) {
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
    else if (RB_TYPE_P(val, T_BIGNUM)) {
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
    rb_raise(rb_eRangeError, "integer %"PRIdVALUE " too %s to convert to `int'",
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
	    rb_raise(rb_eRangeError, "integer %ld too small to convert to `unsigned int'", (long)num);
    }
    else {
	/* plus */
	if (UINT_MAX < num)
	    rb_raise(rb_eRangeError, "integer %lu too big to convert to `unsigned int'", num);
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

    check_uint(num, rb_num_negative_int_p(val));
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
    rb_raise(rb_eRangeError, "integer %"PRIdVALUE " too %s to convert to `short'",
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
	    rb_raise(rb_eRangeError, "integer %ld too small to convert to `unsigned short'", (long)num);
    }
    else {
	/* plus */
	if (USHRT_MAX < num)
	    rb_raise(rb_eRangeError, "integer %lu too big to convert to `unsigned short'", num);
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

    check_ushort(num, rb_num_negative_int_p(val));
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

    else if (RB_TYPE_P(val, T_FLOAT)) {
	double d = RFLOAT_VALUE(val);
	if (d < LLONG_MAX_PLUS_ONE && (LLONG_MIN_MINUS_ONE_IS_LESS_THAN(d))) {
	    return (LONG_LONG)d;
	}
	else {
	    FLOAT_OUT_OF_RANGE(val, "long long");
	}
    }
    else if (RB_TYPE_P(val, T_BIGNUM)) {
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
    if (RB_TYPE_P(val, T_NIL)) {
	rb_raise(rb_eTypeError, "no implicit conversion from nil");
    }
    else if (RB_TYPE_P(val, T_FIXNUM)) {
	return (LONG_LONG)FIX2LONG(val); /* this is FIX2LONG, intended */
    }
    else if (RB_TYPE_P(val, T_FLOAT)) {
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
    else if (RB_TYPE_P(val, T_BIGNUM)) {
	return rb_big2ull(val);
    }
    else if (RB_TYPE_P(val, T_STRING)) {
	rb_raise(rb_eTypeError, "no implicit conversion from string");
    }
    else if (RB_TYPE_P(val, T_TRUE) || RB_TYPE_P(val, T_FALSE)) {
	rb_raise(rb_eTypeError, "no implicit conversion from boolean");
    }

    val = rb_to_int(val);
    return NUM2ULL(val);
}

#endif  /* HAVE_LONG_LONG */

/********************************************************************
 *
 * Document-class: Integer
 *
 *  Holds Integer values.  You cannot add a singleton method to an
 *  Integer object, any attempt to do so will raise a TypeError.
 *
 */

VALUE
rb_int_odd_p(VALUE num)
{
    if (FIXNUM_P(num)) {
	if (num & 2) {
	    return Qtrue;
	}
        return Qfalse;
    }
    else {
        assert(RB_TYPE_P(num, T_BIGNUM));
	return rb_big_odd_p(num);
    }
}

static VALUE
int_even_p(VALUE num)
{
    if (FIXNUM_P(num)) {
	if ((num & 2) == 0) {
	    return Qtrue;
	}
        return Qfalse;
    }
    else {
        assert(RB_TYPE_P(num, T_BIGNUM));
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
 *     int.allbits?(mask)  ->  true or false
 *
 *  Returns +true+ if all bits of <code>+int+ & +mask+</code> are 1.
 */

static VALUE
int_allbits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return rb_int_equal(rb_int_and(num, mask), mask);
}

/*
 *  call-seq:
 *     int.anybits?(mask)  ->  true or false
 *
 *  Returns +true+ if any bits of <code>+int+ & +mask+</code> are 1.
 */

static VALUE
int_anybits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return int_zero_p(rb_int_and(num, mask)) ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     int.nobits?(mask)  ->  true or false
 *
 *  Returns +true+ if no bits of <code>+int+ & +mask+</code> are 1.
 */

static VALUE
int_nobits_p(VALUE num, VALUE mask)
{
    mask = rb_to_int(mask);
    return int_zero_p(rb_int_and(num, mask));
}

/*
 *  Document-method: Integer#succ
 *  Document-method: Integer#next
 *  call-seq:
 *     int.next  ->  integer
 *     int.succ  ->  integer
 *
 *  Returns the successor of +int+,
 *  i.e. the Integer equal to <code>int+1</code>.
 *
 *     1.next      #=> 2
 *     (-1).next   #=> 0
 *     1.succ      #=> 2
 *     (-1).succ   #=> 0
 */

VALUE
rb_int_succ(VALUE num)
{
    if (FIXNUM_P(num)) {
	long i = FIX2LONG(num) + 1;
	return LONG2NUM(i);
    }
    if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_plus(num, INT2FIX(1));
    }
    return num_funcall1(num, '+', INT2FIX(1));
}

#define int_succ rb_int_succ

/*
 *  call-seq:
 *     int.pred  ->  integer
 *
 *  Returns the predecessor of +int+,
 *  i.e. the Integer equal to <code>int-1</code>.
 *
 *     1.pred      #=> 0
 *     (-1).pred   #=> -2
 */

static VALUE
rb_int_pred(VALUE num)
{
    if (FIXNUM_P(num)) {
	long i = FIX2LONG(num) - 1;
	return LONG2NUM(i);
    }
    if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_minus(num, INT2FIX(1));
    }
    return num_funcall1(num, '-', INT2FIX(1));
}

#define int_pred rb_int_pred

/*
 *  Document-method: Integer#chr
 *  call-seq:
 *     int.chr([encoding])  ->  string
 *
 *  Returns a string containing the character represented by the +int+'s value
 *  according to +encoding+.
 *
 *     65.chr    #=> "A"
 *     230.chr   #=> "\xE6"
 *     255.chr(Encoding::UTF_8)   #=> "\u00FF"
 */

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
		rb_raise(rb_eRangeError, "%d out of char range", i);
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


/*
 * Document-method: Integer#-@
 * call-seq:
 *    -int  ->  integer
 *
 * Returns +int+, negated.
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_uminus(num);
    }
    return num_funcall0(num, idUMinus);
}

/*
 *  Document-method: Integer#to_s
 *  call-seq:
 *     int.to_s(base=10)  ->  string
 *
 *  Returns a string containing the place-value representation of +int+
 *  with radix +base+ (between 2 and 36).
 *
 *     12345.to_s       #=> "12345"
 *     12345.to_s(2)    #=> "11000000111001"
 *     12345.to_s(8)    #=> "30071"
 *     12345.to_s(10)   #=> "12345"
 *     12345.to_s(16)   #=> "3039"
 *     12345.to_s(36)   #=> "9ix"
 *     78546939656932.to_s(36)  #=> "rubyrules"
 */

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

static VALUE
int_to_s(int argc, VALUE *argv, VALUE x)
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
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big2str(x, base);
    }

    return rb_any_to_s(x);
}

/*
 * Document-method: Integer#+
 * call-seq:
 *    int + numeric  ->  numeric_result
 *
 * Performs addition: the class of the resulting object depends on
 * the class of +numeric+.
 */

static VALUE
fix_plus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	return rb_fix_plus_fix(x, y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_plus(y, x);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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

VALUE
rb_int_plus(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_plus(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_plus(x, y);
    }
    return rb_num_coerce_bin(x, y, '+');
}

/*
 * Document-method: Integer#-
 * call-seq:
 *    int - numeric  ->  numeric_result
 *
 * Performs subtraction: the class of the resulting object depends on
 * the class of +numeric+.
 */

static VALUE
fix_minus(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	return rb_fix_minus_fix(x, y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	x = rb_int2big(FIX2LONG(x));
	return rb_big_minus(x, y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM((double)FIX2LONG(x) - RFLOAT_VALUE(y));
    }
    else {
	return rb_num_coerce_bin(x, y, '-');
    }
}

VALUE
rb_int_minus(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_minus(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_minus(x, y);
    }
    return rb_num_coerce_bin(x, y, '-');
}


#define SQRT_LONG_MAX HALF_LONG_MSB
/*tests if N*N would overflow*/
#define FIT_SQRT_LONG(n) (((n)<SQRT_LONG_MAX)&&((n)>=-SQRT_LONG_MAX))

/*
 * Document-method: Integer#*
 * call-seq:
 *    int * numeric  ->  numeric_result
 *
 * Performs multiplication: the class of the resulting object depends on
 * the class of +numeric+.
 */

static VALUE
fix_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	return rb_fix_mul_fix(x, y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	switch (x) {
	  case INT2FIX(0): return x;
	  case INT2FIX(1): return y;
	}
	return rb_big_mul(y, x);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM((double)FIX2LONG(x) * RFLOAT_VALUE(y));
    }
    else if (RB_TYPE_P(y, T_COMPLEX)) {
	return rb_complex_mul(y, x);
    }
    else {
	return rb_num_coerce_bin(x, y, '*');
    }
}

VALUE
rb_int_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_mul(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_mul(x, y);
    }
    return rb_num_coerce_bin(x, y, '*');
}

static double
fix_fdiv_double(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return double_div_double(FIX2LONG(x), FIX2LONG(y));
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
        return rb_big_fdiv_double(rb_int2big(FIX2LONG(x)), y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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
	if (!FIXNUM_ZERO_P(gcd)) {
	    x = rb_int_idiv(x, gcd);
	    y = rb_int_idiv(y, gcd);
	}
    }
    if (FIXNUM_P(x)) {
        return fix_fdiv_double(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
        return rb_big_fdiv_double(x, y);
    }
    else {
        return nan("");
    }
}

/*
 *  Document-method: Integer#fdiv
 *  call-seq:
 *     int.fdiv(numeric)  ->  float
 *
 *  Returns the floating point result of dividing +int+ by +numeric+.
 *
 *     654321.fdiv(13731)      #=> 47.652829364212366
 *     654321.fdiv(13731.24)   #=> 47.65199646936475
 *     -654321.fdiv(13731)     #=> -47.652829364212366
 */

VALUE
rb_int_fdiv(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return DBL2NUM(rb_int_fdiv_double(x, y));
    }
    return Qnil;
}

/*
 * Document-method: Integer#/
 * call-seq:
 *    int / numeric  ->  numeric_result
 *
 * Performs division: the class of the resulting object depends on
 * the class of +numeric+.
 */

static VALUE
fix_divide(VALUE x, VALUE y, ID op)
{
    if (FIXNUM_P(y)) {
	if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
	return rb_fix_div_fix(x, y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	x = rb_int2big(FIX2LONG(x));
	return rb_big_div(x, y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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

VALUE
rb_int_div(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_div(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_div(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#div
 * call-seq:
 *    int.div(numeric)  ->  integer
 *
 * Performs integer division: returns the integer result of dividing +int+
 * by +numeric+.
 */

static VALUE
fix_idiv(VALUE x, VALUE y)
{
    return fix_divide(x, y, id_div);
}

VALUE
rb_int_idiv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_idiv(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_idiv(x, y);
    }
    return num_div(x, y);
}

/*
 *  Document-method: Integer#%
 *  Document-method: Integer#modulo
 *  call-seq:
 *     int % other        ->  real
 *     int.modulo(other)  ->  real
 *
 *  Returns +int+ modulo +other+.
 *
 *  See Numeric#divmod for more information.
 */

static VALUE
fix_mod(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
	return rb_fix_mod_fix(x, y);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	x = rb_int2big(FIX2LONG(x));
	return rb_big_modulo(x, y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return DBL2NUM(ruby_float_mod((double)FIX2LONG(x), RFLOAT_VALUE(y)));
    }
    else {
	return rb_num_coerce_bin(x, y, '%');
    }
}

VALUE
rb_int_modulo(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_mod(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_modulo(x, y);
    }
    return num_modulo(x, y);
}

/*
 *  call-seq:
 *     int.remainder(numeric)  ->  real
 *
 *  Returns the remainder after dividing +int+ by +numeric+.
 *
 *  <code>x.remainder(y)</code> means <code>x-y*(x/y).truncate</code>.
 *
 *     5.remainder(3)     #=> 2
 *     -5.remainder(3)    #=> -2
 *     5.remainder(-3)    #=> 2
 *     -5.remainder(-3)   #=> -2
 *     5.remainder(1.5)   #=> 0.5
 *
 *  See Numeric#divmod.
 */

static VALUE
int_remainder(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return num_remainder(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_remainder(x, y);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#divmod
 *  call-seq:
 *     int.divmod(numeric)  ->  array
 *
 *  See Numeric#divmod.
 */
static VALUE
fix_divmod(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	VALUE div, mod;
	if (FIXNUM_ZERO_P(y)) rb_num_zerodiv();
	rb_fix_divmod_fix(x, y, &div, &mod);
	return rb_assoc_new(div, mod);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	x = rb_int2big(FIX2LONG(x));
	return rb_big_divmod(x, y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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

VALUE
rb_int_divmod(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_divmod(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_divmod(x, y);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#**
 *  call-seq:
 *     int ** numeric  ->  numeric_result
 *
 *  Raises +int+ to the power of +numeric+, which may be negative or
 *  fractional.
 *  The result may be an Integer, a Float, a Rational, or a complex number.
 *
 *     2 ** 3        #=> 8
 *     2 ** -1       #=> (1/2)
 *     2 ** 0.5      #=> 1.4142135623730951
 *     (-1) ** 0.5   #=> (0.0+1.0i)
 *
 *     123456789 ** 2     #=> 15241578750190521
 *     123456789 ** 1.2   #=> 5126464716.0993185
 *     123456789 ** -2    #=> (1/15241578750190521)
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
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	if (a == 1) return INT2FIX(1);
        if (a == -1) return INT2FIX(int_even_p(y) ? 1 : -1);
        if (BIGNUM_NEGATIVE_P(y)) return fix_pow_inverted(x, rb_big_uminus(y));
	if (a == 0) return INT2FIX(0);
	x = rb_int2big(FIX2LONG(x));
	return rb_big_pow(x, y);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
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

VALUE
rb_int_pow(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_pow(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
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

/*
 * Document-method: Integer#==
 * Document-method: Integer#===
 * call-seq:
 *    int == other  ->  true or false
 *
 * Returns +true+ if +int+ equals +other+ numerically.
 * Contrast this with Integer#eql?, which requires +other+ to be an Integer.
 *
 *    1 == 2     #=> false
 *    1 == 1.0   #=> true
 */

static VALUE
fix_equal(VALUE x, VALUE y)
{
    if (x == y) return Qtrue;
    if (FIXNUM_P(y)) return Qfalse;
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_eq(y, x);
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
        return rb_integer_float_eq(x, y);
    }
    else {
	return num_equal(x, y);
    }
}

VALUE
rb_int_equal(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_equal(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_eq(x, y);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#<=>
 *  call-seq:
 *     int <=> numeric  ->  -1, 0, +1, or nil
 *
 *  Comparison---Returns -1, 0, or +1 depending on whether +int+ is
 *  less than, equal to, or greater than +numeric+.
 *
 *  This is the basis for the tests in the Comparable module.
 *
 *  +nil+ is returned if the two values are incomparable.
 */

static VALUE
fix_cmp(VALUE x, VALUE y)
{
    if (x == y) return INT2FIX(0);
    if (FIXNUM_P(y)) {
	if (FIX2LONG(x) > FIX2LONG(y)) return INT2FIX(1);
	return INT2FIX(-1);
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	VALUE cmp = rb_big_cmp(y, x);
	switch (cmp) {
	  case INT2FIX(+1): return INT2FIX(-1);
	  case INT2FIX(-1): return INT2FIX(+1);
	}
	return cmp;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	return rb_integer_float_cmp(x, y);
    }
    else {
	return rb_num_coerce_cmp(x, y, id_cmp);
    }
}

VALUE
rb_int_cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_cmp(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_cmp(x, y);
    }
    else {
	rb_raise(rb_eNotImpError, "need to define `<=>' in %s", rb_obj_classname(x));
    }
}

/*
 * Document-method: Integer#>
 * call-seq:
 *    int > real  ->  true or false
 *
 * Returns +true+ if the value of +int+ is greater than that of +real+.
 */

static VALUE
fix_gt(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	if (FIX2LONG(x) > FIX2LONG(y)) return Qtrue;
	return Qfalse;
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_cmp(y, x) == INT2FIX(-1) ? Qtrue : Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
        return rb_integer_float_cmp(x, y) == INT2FIX(1) ? Qtrue : Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y, '>');
    }
}

VALUE
rb_int_gt(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_gt(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_gt(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#>=
 * call-seq:
 *    int >= real  ->  true or false
 *
 * Returns +true+ if the value of +int+ is greater than or equal to that of
 * +real+.
 */

static VALUE
fix_ge(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	if (FIX2LONG(x) >= FIX2LONG(y)) return Qtrue;
	return Qfalse;
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_cmp(y, x) != INT2FIX(+1) ? Qtrue : Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	VALUE rel = rb_integer_float_cmp(x, y);
	return rel == INT2FIX(1) || rel == INT2FIX(0) ? Qtrue : Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y, idGE);
    }
}

VALUE
rb_int_ge(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_ge(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_ge(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#<
 * call-seq:
 *    int < real  ->  true or false
 *
 * Returns +true+ if the value of +int+ is less than that of +real+.
 */

static VALUE
fix_lt(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	if (FIX2LONG(x) < FIX2LONG(y)) return Qtrue;
	return Qfalse;
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_cmp(y, x) == INT2FIX(+1) ? Qtrue : Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
        return rb_integer_float_cmp(x, y) == INT2FIX(-1) ? Qtrue : Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y, '<');
    }
}

static VALUE
int_lt(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_lt(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_lt(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#<=
 * call-seq:
 *    int <= real  ->  true or false
 *
 * Returns +true+ if the value of +int+ is less than or equal to that of
 * +real+.
 */

static VALUE
fix_le(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	if (FIX2LONG(x) <= FIX2LONG(y)) return Qtrue;
	return Qfalse;
    }
    else if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_cmp(y, x) != INT2FIX(-1) ? Qtrue : Qfalse;
    }
    else if (RB_TYPE_P(y, T_FLOAT)) {
	VALUE rel = rb_integer_float_cmp(x, y);
	return rel == INT2FIX(-1) || rel == INT2FIX(0) ? Qtrue : Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y, idLE);
    }
}

static VALUE
int_le(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_le(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_le(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#~
 * call-seq:
 *   ~int  ->  integer
 *
 * One's complement: returns a number where each bit is flipped.
 *
 * Inverts the bits in an Integer. As integers are conceptually of
 * infinite length, the result acts as if it had an infinite number of
 * one bits to the left. In hex representations, this is displayed
 * as two periods to the left of the digits.
 *
 *   sprintf("%X", ~0x1122334455)    #=> "..FEEDDCCBBAA"
 */

static VALUE
fix_comp(VALUE num)
{
    return ~num | FIXNUM_FLAG;
}

static VALUE
int_comp(VALUE num)
{
    if (FIXNUM_P(num)) {
	return fix_comp(num);
    }
    else if (RB_TYPE_P(num, T_BIGNUM)) {
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
    if (ret == Qundef) {
	/* show the original object, not coerced object */
	coerce_failed(x, y);
    }
    return ret;
}

/*
 * Document-method: Integer#&
 * call-seq:
 *   int & other_int  ->  integer
 *
 * Bitwise AND.
 */

static VALUE
fix_and(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	long val = FIX2LONG(x) & FIX2LONG(y);
	return LONG2NUM(val);
    }

    if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_and(y, x);
    }

    return rb_num_coerce_bit(x, y, '&');
}

VALUE
rb_int_and(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_and(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_and(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#|
 * call-seq:
 *   int | other_int  ->  integer
 *
 * Bitwise OR.
 */

static VALUE
fix_or(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	long val = FIX2LONG(x) | FIX2LONG(y);
	return LONG2NUM(val);
    }

    if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_or(y, x);
    }

    return rb_num_coerce_bit(x, y, '|');
}

static VALUE
int_or(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_or(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_or(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#^
 * call-seq:
 *   int ^ other_int  ->  integer
 *
 * Bitwise EXCLUSIVE OR.
 */

static VALUE
fix_xor(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	long val = FIX2LONG(x) ^ FIX2LONG(y);
	return LONG2NUM(val);
    }

    if (RB_TYPE_P(y, T_BIGNUM)) {
	return rb_big_xor(y, x);
    }

    return rb_num_coerce_bit(x, y, '^');
}

static VALUE
int_xor(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return fix_xor(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_xor(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#<<
 * call-seq:
 *   int << count  ->  integer
 *
 * Returns +int+ shifted left +count+ positions, or right if +count+
 * is negative.
 */

static VALUE
rb_fix_lshift(VALUE x, VALUE y)
{
    long val, width;

    val = NUM2LONG(x);
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

VALUE
rb_int_lshift(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return rb_fix_lshift(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_lshift(x, y);
    }
    return Qnil;
}

/*
 * Document-method: Integer#>>
 * call-seq:
 *   int >> count  ->  integer
 *
 * Returns +int+ shifted right +count+ positions, or left if +count+
 * is negative.
 */

static VALUE
rb_fix_rshift(VALUE x, VALUE y)
{
    long i, val;

    val = FIX2LONG(x);
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

static VALUE
rb_int_rshift(VALUE x, VALUE y)
{
    if (FIXNUM_P(x)) {
	return rb_fix_rshift(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return rb_big_rshift(x, y);
    }
    return Qnil;
}

MJIT_FUNC_EXPORTED VALUE
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
                if (RTEST(int_zero_p(rb_int_and(num, mask)))) {
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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
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
 *  Document-method: Integer#[]
 *  call-seq:
 *     int[n]    -> 0, 1
 *     int[n, m] -> num
 *     int[range] -> num
 *
 *  Bit Reference---Returns the <code>n</code>th bit in the
 *  binary representation of +int+, where <code>int[0]</code>
 *  is the least significant bit.
 *
 *     a = 0b11001100101010
 *     30.downto(0) {|n| print a[n] }
 *     #=> 0000000000000000011001100101010
 *
 *     a = 9**15
 *     50.downto(0) {|n| print a[n] }
 *     #=> 000101110110100000111000011110010100111100010111001
 *
 *  In principle, <code>n[i]</code> is equivalent to <code>(n >> i) & 1</code>.
 *  Thus, any negative index always returns zero:
 *
 *     p 255[-1] #=> 0
 *
 *  Range operations <code>n[i, len]</code> and <code>n[i..j]</code>
 *  are naturally extended.
 *
 *  * <code>n[i, len]</code> equals to <code>(n >> i) & ((1 << len) - 1)</code>.
 *  * <code>n[i..j]</code> equals to <code>(n >> i) & ((1 << (j - i + 1)) - 1)</code>.
 *  * <code>n[i...j]</code> equals to <code>(n >> i) & ((1 << (j - i)) - 1)</code>.
 *  * <code>n[i..]</code> equals to <code>(n >> i)</code>.
 *  * <code>n[..j]</code> is zero if <code>n & ((1 << (j + 1)) - 1)</code> is zero.  Otherwise, raises an ArgumentError.
 *  * <code>n[...j]</code> is zero if <code>n & ((1 << j) - 1)</code> is zero.  Otherwise, raises an ArgumentError.
 *
 *  Note that range operation may exhaust memory.
 *  For example, <code>-1[0, 1000000000000]</code> will raise NoMemoryError.
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
 *  Document-method: Integer#to_f
 *  call-seq:
 *     int.to_f  ->  float
 *
 *  Converts +int+ to a Float.  If +int+ doesn't fit in a Float,
 *  the result is infinity.
 */

static VALUE
int_to_f(VALUE num)
{
    double val;

    if (FIXNUM_P(num)) {
	val = (double)FIX2LONG(num);
    }
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	val = rb_big2dbl(num);
    }
    else {
	rb_raise(rb_eNotImpError, "Unknown subclass for to_f: %s", rb_obj_classname(num));
    }

    return DBL2NUM(val);
}

/*
 *  Document-method: Integer#abs
 *  Document-method: Integer#magnitude
 *  call-seq:
 *     int.abs        ->  integer
 *     int.magnitude  ->  integer
 *
 *  Returns the absolute value of +int+.
 *
 *     (-12345).abs   #=> 12345
 *     -12345.abs     #=> 12345
 *     12345.abs      #=> 12345
 *
 *  Integer#magnitude is an alias for Integer#abs.
 */

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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_abs(num);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#size
 *  call-seq:
 *     int.size  ->  int
 *
 *  Returns the number of bytes in the machine representation of +int+
 *  (machine dependent).
 *
 *     1.size               #=> 8
 *     -1.size              #=> 8
 *     2147483647.size      #=> 8
 *     (256**10 - 1).size   #=> 10
 *     (256**20 - 1).size   #=> 20
 *     (256**40 - 1).size   #=> 40
 */

static VALUE
fix_size(VALUE fix)
{
    return INT2FIX(sizeof(long));
}

static VALUE
int_size(VALUE num)
{
    if (FIXNUM_P(num)) {
	return fix_size(num);
    }
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_size_m(num);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#bit_length
 *  call-seq:
 *     int.bit_length  ->  integer
 *
 *  Returns the number of bits of the value of +int+.
 *
 *  "Number of bits" means the bit position of the highest bit
 *  which is different from the sign bit
 *  (where the least significant bit has bit position 1).
 *  If there is no such bit (zero or minus one), zero is returned.
 *
 *  I.e. this method returns <i>ceil(log2(int < 0 ? -int : int+1))</i>.
 *
 *     (-2**1000-1).bit_length   #=> 1001
 *     (-2**1000).bit_length     #=> 1000
 *     (-2**1000+1).bit_length   #=> 1000
 *     (-2**12-1).bit_length     #=> 13
 *     (-2**12).bit_length       #=> 12
 *     (-2**12+1).bit_length     #=> 12
 *     -0x101.bit_length         #=> 9
 *     -0x100.bit_length         #=> 8
 *     -0xff.bit_length          #=> 8
 *     -2.bit_length             #=> 1
 *     -1.bit_length             #=> 0
 *     0.bit_length              #=> 0
 *     1.bit_length              #=> 1
 *     0xff.bit_length           #=> 8
 *     0x100.bit_length          #=> 9
 *     (2**12-1).bit_length      #=> 12
 *     (2**12).bit_length        #=> 13
 *     (2**12+1).bit_length      #=> 13
 *     (2**1000-1).bit_length    #=> 1000
 *     (2**1000).bit_length      #=> 1001
 *     (2**1000+1).bit_length    #=> 1001
 *
 *  This method can be used to detect overflow in Array#pack as follows:
 *
 *     if n.bit_length < 32
 *       [n].pack("l") # no overflow
 *     else
 *       raise "overflow"
 *     end
 */

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
    else if (RB_TYPE_P(num, T_BIGNUM)) {
	return rb_big_bit_length(num);
    }
    return Qnil;
}

/*
 *  Document-method: Integer#digits
 *  call-seq:
 *     int.digits        ->  array
 *     int.digits(base)  ->  array
 *
 *  Returns the digits of +int+'s place-value representation
 *  with radix +base+ (default: 10).
 *  The digits are returned as an array with the least significant digit
 *  as the first array element.
 *
 *  +base+ must be greater than or equal to 2.
 *
 *     12345.digits      #=> [5, 4, 3, 2, 1]
 *     12345.digits(7)   #=> [4, 6, 6, 0, 5]
 *     12345.digits(100) #=> [45, 23, 1]
 *
 *     -12345.digits(7)  #=> Math::DomainError
 */

static VALUE
rb_fix_digits(VALUE fix, long base)
{
    VALUE digits;
    long x = FIX2LONG(fix);

    assert(x >= 0);

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
    VALUE digits;

    assert(!rb_num_negative_p(num));

    if (RB_TYPE_P(base, T_BIGNUM))
        base = rb_big_norm(base);

    if (FIXNUM_P(base) && FIX2LONG(base) < 2)
        rb_raise(rb_eArgError, "invalid radix %ld", FIX2LONG(base));
    else if (RB_TYPE_P(base, T_BIGNUM) && BIGNUM_NEGATIVE_P(base))
        rb_raise(rb_eArgError, "negative radix");

    if (FIXNUM_P(base) && FIXNUM_P(num))
        return rb_fix_digits(num, FIX2LONG(base));

    if (FIXNUM_P(num))
        return rb_ary_new_from_args(1, num);

    digits = rb_ary_new();
    while (!FIXNUM_P(num) || FIX2LONG(num) > 0) {
        VALUE qr = rb_int_divmod(num, base);
        rb_ary_push(digits, RARRAY_AREF(qr, 1));
        num = RARRAY_AREF(qr, 0);
    }

    return digits;
}

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
        if (RB_TYPE_P(base_value, T_BIGNUM))
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
    else if (RB_TYPE_P(num, T_BIGNUM))
        return rb_int_digits_bigbase(num, LONG2FIX(base));

    return Qnil;
}

/*
 *  Document-method: Integer#upto
 *  call-seq:
 *     int.upto(limit) {|i| block }  ->  self
 *     int.upto(limit)               ->  an_enumerator
 *
 *  Iterates the given block, passing in integer values from +int+ up to and
 *  including +limit+.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *     5.upto(10) {|i| print i, " " }   #=> 5 6 7 8 9 10
 */

static VALUE
int_upto_size(VALUE from, VALUE args, VALUE eobj)
{
    return ruby_num_interval_step_size(from, RARRAY_AREF(args, 0), INT2FIX(1), FALSE);
}

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
	if (NIL_P(c)) rb_cmperr(i, to);
    }
    return from;
}

/*
 *  Document-method: Integer#downto
 *  call-seq:
 *     int.downto(limit) {|i| block }  ->  self
 *     int.downto(limit)               ->  an_enumerator
 *
 *  Iterates the given block, passing in decreasing values from +int+ down to
 *  and including +limit+.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *     5.downto(1) { |n| print n, ".. " }
 *     puts "Liftoff!"
 *     #=> "5.. 4.. 3.. 2.. 1.. Liftoff!"
 */

static VALUE
int_downto_size(VALUE from, VALUE args, VALUE eobj)
{
    return ruby_num_interval_step_size(from, RARRAY_AREF(args, 0), INT2FIX(-1), FALSE);
}

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

/*
 *  Document-method: Integer#times
 *  call-seq:
 *     int.times {|i| block }  ->  self
 *     int.times               ->  an_enumerator
 *
 *  Iterates the given block +int+ times, passing in values from zero to
 *  <code>int - 1</code>.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *     5.times {|i| print i, " " }   #=> 0 1 2 3 4
 */

static VALUE
int_dotimes_size(VALUE num, VALUE args, VALUE eobj)
{
    if (FIXNUM_P(num)) {
	if (NUM2LONG(num) <= 0) return INT2FIX(0);
    }
    else {
	if (RTEST(rb_funcall(num, '<', 1, INT2FIX(0)))) return INT2FIX(0);
    }
    return num;
}

static VALUE
int_dotimes(VALUE num)
{
    RETURN_SIZED_ENUMERATOR(num, 0, 0, int_dotimes_size);

    if (FIXNUM_P(num)) {
	long i, end;

	end = FIX2LONG(num);
	for (i=0; i<end; i++) {
	    rb_yield_1(LONG2FIX(i));
	}
    }
    else {
	VALUE i = INT2FIX(0);

	for (;;) {
	    if (!RTEST(rb_funcall(i, '<', 1, num))) break;
	    rb_yield(i);
	    i = rb_funcall(i, '+', 1, INT2FIX(1));
	}
    }
    return num;
}

/*
 *  Document-method: Integer#round
 *  call-seq:
 *     int.round([ndigits] [, half: mode])  ->  integer or float
 *
 *  Returns +int+ rounded to the nearest value with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *     1.round           #=> 1
 *     1.round(2)        #=> 1
 *     15.round(-1)      #=> 20
 *     (-15).round(-1)   #=> -20
 *
 *  The optional +half+ keyword argument is available
 *  similar to Float#round.
 *
 *     25.round(-1, half: :up)      #=> 30
 *     25.round(-1, half: :down)    #=> 20
 *     25.round(-1, half: :even)    #=> 20
 *     35.round(-1, half: :up)      #=> 40
 *     35.round(-1, half: :down)    #=> 30
 *     35.round(-1, half: :even)    #=> 40
 *     (-25).round(-1, half: :up)   #=> -30
 *     (-25).round(-1, half: :down) #=> -20
 *     (-25).round(-1, half: :even) #=> -20
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
 *  Document-method: Integer#floor
 *  call-seq:
 *     int.floor([ndigits])  ->  integer or float
 *
 *  Returns the largest number less than or equal to +int+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *     1.floor           #=> 1
 *     1.floor(2)        #=> 1
 *     18.floor(-1)      #=> 10
 *     (-18).floor(-1)   #=> -20
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
 *  Document-method: Integer#ceil
 *  call-seq:
 *     int.ceil([ndigits])  ->  integer or float
 *
 *  Returns the smallest number greater than or equal to +int+ with
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *     1.ceil           #=> 1
 *     1.ceil(2)        #=> 1
 *     18.ceil(-1)      #=> 20
 *     (-18).ceil(-1)   #=> -10
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
 *  Document-method: Integer#truncate
 *  call-seq:
 *     int.truncate([ndigits])  ->  integer or float
 *
 *  Returns +int+ truncated (toward zero) to
 *  a precision of +ndigits+ decimal digits (default: 0).
 *
 *  When the precision is negative, the returned value is an integer
 *  with at least <code>ndigits.abs</code> trailing zeros.
 *
 *  Returns +self+ when +ndigits+ is zero or positive.
 *
 *     1.truncate           #=> 1
 *     1.truncate(2)        #=> 1
 *     18.truncate(-1)      #=> 10
 *     (-18).truncate(-1)   #=> -10
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

VALUE rb_big_isqrt(VALUE);

/*
 *  Document-method: Integer::sqrt
 *  call-seq:
 *     Integer.sqrt(n)  ->  integer
 *
 *  Returns the integer square root of the non-negative integer +n+,
 *  i.e. the largest non-negative integer less than or equal to the
 *  square root of +n+.
 *
 *    Integer.sqrt(0)        #=> 0
 *    Integer.sqrt(1)        #=> 1
 *    Integer.sqrt(24)       #=> 4
 *    Integer.sqrt(25)       #=> 5
 *    Integer.sqrt(10**400)  #=> 10**200
 *
 *  Equivalent to <code>Math.sqrt(n).floor</code>, except that
 *  the result of the latter code may differ from the true value
 *  due to the limited precision of floating point arithmetic.
 *
 *    Integer.sqrt(10**46)     #=> 100000000000000000000000
 *    Math.sqrt(10**46).floor  #=>  99999999999999991611392 (!)
 *
 *  If +n+ is not an Integer, it is converted to an Integer first.
 *  If +n+ is negative, a Math::DomainError is raised.
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
 * Numeric is the class from which all higher-level numeric classes should inherit.
 *
 * Numeric allows instantiation of heap-allocated objects. Other core numeric classes such as
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
 * For this reason, Numeric should be used when defining other numeric classes.
 *
 * Classes which inherit from Numeric must implement +coerce+, which returns a two-member
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
 */
void
Init_Numeric(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

#ifdef _UNICOSMP
    /* Turn off floating point exceptions for divide by zero, etc. */
    _set_Creg(0, 0);
#endif
    id_coerce = rb_intern("coerce");
    id_to = rb_intern("to");
    id_by = rb_intern("by");

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

    rb_define_method(rb_cNumeric, "real?", num_real_p, 0);
    rb_define_method(rb_cNumeric, "integer?", num_int_p, 0);
    rb_define_method(rb_cNumeric, "zero?", num_zero_p, 0);
    rb_define_method(rb_cNumeric, "nonzero?", num_nonzero_p, 0);
    rb_define_method(rb_cNumeric, "finite?", num_finite_p, 0);
    rb_define_method(rb_cNumeric, "infinite?", num_infinite_p, 0);

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

    rb_define_method(rb_cInteger, "to_s", int_to_s, -1);
    rb_define_alias(rb_cInteger, "inspect", "to_s");
    rb_define_method(rb_cInteger, "allbits?", int_allbits_p, 1);
    rb_define_method(rb_cInteger, "anybits?", int_anybits_p, 1);
    rb_define_method(rb_cInteger, "nobits?", int_nobits_p, 1);
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "times", int_dotimes, 0);
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

    rb_define_method(rb_cInteger, "-@", rb_int_uminus, 0);
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

    rb_define_method(rb_cInteger, "~", int_comp, 0);
    rb_define_method(rb_cInteger, "&", rb_int_and, 1);
    rb_define_method(rb_cInteger, "|", int_or,  1);
    rb_define_method(rb_cInteger, "^", int_xor, 1);
    rb_define_method(rb_cInteger, "[]", int_aref, -1);

    rb_define_method(rb_cInteger, "<<", rb_int_lshift, 1);
    rb_define_method(rb_cInteger, ">>", rb_int_rshift, 1);

    rb_define_method(rb_cInteger, "size", int_size, 0);
    rb_define_method(rb_cInteger, "digits", rb_int_digits, -1);

    /* An obsolete class, use Integer */
    rb_define_const(rb_cObject, "Fixnum", rb_cInteger);
    rb_deprecate_constant(rb_cObject, "Fixnum");

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
    rb_define_method(rb_cFloat, "-@", rb_float_uminus, 0);
    rb_define_method(rb_cFloat, "+", rb_float_plus, 1);
    rb_define_method(rb_cFloat, "-", flo_minus, 1);
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
    rb_define_method(rb_cFloat, "to_f", flo_to_f, 0);
    rb_define_method(rb_cFloat, "abs", rb_float_abs, 0);
    rb_define_method(rb_cFloat, "magnitude", rb_float_abs, 0);
    rb_define_method(rb_cFloat, "zero?", flo_zero_p, 0);

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
    rb_define_method(rb_cFloat, "positive?", flo_positive_p, 0);
    rb_define_method(rb_cFloat, "negative?", flo_negative_p, 0);
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

#include "integer.rbinc"
