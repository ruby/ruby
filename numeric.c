/**********************************************************************

  numeric.c -

  $Author$
  $Date$
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "env.h"
#include <ctype.h>
#include <math.h>
#include <stdio.h>

#if defined(__FreeBSD__) && __FreeBSD__ < 4
#include <floatingpoint.h>
#endif

#ifdef HAVE_FLOAT_H
#include <float.h>
#endif

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

/* use IEEE 64bit values if not defined */
#ifndef FLT_RADIX
#define FLT_RADIX 2
#endif
#ifndef FLT_ROUNDS
#define FLT_ROUNDS 1
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

extern double round _((double));

#ifndef HAVE_ROUND
double
round(x)
    double x;
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

static ID id_coerce, id_to_i, id_eq;

VALUE rb_cNumeric;
VALUE rb_cFloat;
VALUE rb_cInteger;
VALUE rb_cFixnum;

VALUE rb_eZeroDivError;
VALUE rb_eFloatDomainError;

void
rb_num_zerodiv()
{
    rb_raise(rb_eZeroDivError, "divided by 0");
}


/*
 *  call-seq:
 *     num.coerce(numeric)   => array
 *
 *  If <i>aNumeric</i> is the same type as <i>num</i>, returns an array
 *  containing <i>aNumeric</i> and <i>num</i>. Otherwise, returns an
 *  array with both <i>aNumeric</i> and <i>num</i> represented as
 *  <code>Float</code> objects. This coercion mechanism is used by
 *  Ruby to handle mixed-type numeric operations: it is intended to
 *  find a compatible common type between the two operands of the operator.
 *
 *     1.coerce(2.5)   #=> [2.5, 1.0]
 *     1.2.coerce(3)   #=> [3.0, 1.2]
 *     1.coerce(2)     #=> [2, 1]
 */

static VALUE
num_coerce(x, y)
    VALUE x, y;
{
    if (CLASS_OF(x) == CLASS_OF(y))
	return rb_assoc_new(y, x);
    x = rb_Float(x);
    y = rb_Float(y);
    return rb_assoc_new(y, x);
}

static VALUE
coerce_body(x)
    VALUE *x;
{
    return rb_funcall(x[1], id_coerce, 1, x[0]);
}

static VALUE
coerce_rescue(x)
    VALUE *x;
{
    volatile VALUE v = rb_inspect(x[1]);

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_special_const_p(x[1])?
	     RSTRING(v)->ptr:
	     rb_obj_classname(x[1]),
	     rb_obj_classname(x[0]));
    return Qnil;		/* dummy */
}

static int
do_coerce(x, y, err)
    VALUE *x, *y;
    int err;
{
    VALUE ary;
    VALUE a[2];

    a[0] = *x; a[1] = *y;

    ary = rb_rescue(coerce_body, (VALUE)a, err?coerce_rescue:0, (VALUE)a);
    if (TYPE(ary) != T_ARRAY || RARRAY(ary)->len != 2) {
	if (err) {
	    rb_raise(rb_eTypeError, "coerce must return [x, y]");
	}
	return Qfalse;
    }

    *x = RARRAY(ary)->ptr[0];
    *y = RARRAY(ary)->ptr[1];
    return Qtrue;
}

VALUE
rb_num_coerce_bin(x, y)
    VALUE x, y;
{
    do_coerce(&x, &y, Qtrue);
    return rb_funcall(x, ruby_frame->orig_func, 1, y);
}

VALUE
rb_num_coerce_cmp(x, y)
    VALUE x, y;
{
    if (do_coerce(&x, &y, Qfalse))
	return rb_funcall(x, ruby_frame->orig_func, 1, y);
    return Qnil;
}

VALUE
rb_num_coerce_relop(x, y)
    VALUE x, y;
{
    VALUE c, x0 = x, y0 = y;

    if (!do_coerce(&x, &y, Qfalse) ||
	NIL_P(c = rb_funcall(x, ruby_frame->orig_func, 1, y))) {
	rb_cmperr(x0, y0);
	return Qnil;		/* not reached */
    }
    return c;
}

/*
 * Trap attempts to add methods to <code>Numeric</code> objects. Always
 * raises a <code>TypeError</code>
 */

static VALUE
num_sadded(x, name)
    VALUE x, name;
{
    ruby_frame = ruby_frame->prev; /* pop frame for "singleton_method_added" */
    /* Numerics should be values; singleton_methods should not be added to them */
    rb_raise(rb_eTypeError,
	     "can't define singleton method \"%s\" for %s",
	     rb_id2name(rb_to_id(name)),
	     rb_obj_classname(x));
    return Qnil;		/* not reached */
}

/* :nodoc: */
static VALUE
num_init_copy(x, y)
    VALUE x, y;
{
    /* Numerics are immutable values, which should not be copied */
    rb_raise(rb_eTypeError, "can't copy %s", rb_obj_classname(x));
    return Qnil;		/* not reached */
}

/*
 *  call-seq:
 *     +num    => num
 *
 *  Unary Plus---Returns the receiver's value.
 */

static VALUE
num_uplus(num)
    VALUE num;
{
    return num;
}

/*
 *  call-seq:
 *     -num    => numeric
 *
 *  Unary Minus---Returns the receiver's value, negated.
 */

static VALUE
num_uminus(num)
    VALUE num;
{
    VALUE zero;

    zero = INT2FIX(0);
    do_coerce(&zero, &num, Qtrue);

    return rb_funcall(zero, '-', 1, num);
}

/*
 *  call-seq:
 *     num.quo(numeric)    =>   result
 *     num.fdiv(numeric)   =>   result
 *
 *  Equivalent to <code>Numeric#/</code>, but overridden in subclasses.
 */

static VALUE
num_quo(x, y)
    VALUE x, y;
{
    return rb_funcall(x, '/', 1, y);
}


static VALUE num_floor _((VALUE));

/*
 *  call-seq:
 *     num.div(numeric)    => integer
 *
 *  Uses <code>/</code> to perform division, then converts the result to
 *  an integer. <code>Numeric</code> does not define the <code>/</code>
 *  operator; this is left to subclasses.
 */

static VALUE
num_div(x, y)
    VALUE x, y;
{
    return num_floor(rb_funcall(x, '/', 1, y));
}



/*
 *  call-seq:
 *     num.divmod( aNumeric ) -> anArray
 *
 *  Returns an array containing the quotient and modulus obtained by
 *  dividing <i>num</i> by <i>aNumeric</i>. If <code>q, r =
 *  x.divmod(y)</code>, then
 *
 *      q = floor(float(x)/float(y))
 *      x = q*y + r
 *
 *  The quotient is rounded toward -infinity, as shown in the following table:
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
 *     11.divmod(3)         #=> [3, 2]
 *     11.divmod(-3)        #=> [-4, -1]
 *     11.divmod(3.5)       #=> [3, 0.5]
 *     (-11).divmod(3.5)    #=> [-4, 3.0]
 *     (11.5).divmod(3.5)   #=> [3, 1.0]
 */

static VALUE
num_divmod(x, y)
    VALUE x, y;
{
    return rb_assoc_new(num_div(x, y), rb_funcall(x, '%', 1, y));
}

/*
 *  call-seq:
 *     num.modulo(numeric)    => result
 *
 *  Equivalent to
 *  <i>num</i>.<code>divmod(</code><i>aNumeric</i><code>)[1]</code>.
 */

static VALUE
num_modulo(x, y)
    VALUE x, y;
{
    return rb_funcall(x, '%', 1, y);
}

/*
 *  call-seq:
 *     num.remainder(numeric)    => result
 *
 *  <code>x.remainder(y)</code> means <code>x-y*(x/y).truncate.</code>
 *
 *  The differences between <code>remainder</code> and modulo
 *  (<code>%</code>) are shown in the table under <code>Numeric#divmod</code>.
 */

static VALUE
num_remainder(x, y)
    VALUE x, y;
{
    VALUE z = rb_funcall(x, '%', 1, y);

    if ((!rb_equal(z, INT2FIX(0))) &&
	((RTEST(rb_funcall(x, '<', 1, INT2FIX(0))) &&
	  RTEST(rb_funcall(y, '>', 1, INT2FIX(0)))) ||
	 (RTEST(rb_funcall(x, '>', 1, INT2FIX(0))) &&
	  RTEST(rb_funcall(y, '<', 1, INT2FIX(0)))))) {
	return rb_funcall(z, '-', 1, y);
    }
    return z;
}

/*
 *  call-seq:
 *     num.integer? -> true or false
 *
 *  Returns <code>true</code> if <i>num</i> is an <code>Integer</code>
 *  (including <code>Fixnum</code> and <code>Bignum</code>).
 */

static VALUE
num_int_p(num)
    VALUE num;
{
    return Qfalse;
}

/*
 *  call-seq:
 *     num.abs   => num or numeric
 *
 *  Returns the absolute value of <i>num</i>.
 *
 *     12.abs         #=> 12
 *     (-34.56).abs   #=> 34.56
 *     -34.56.abs     #=> 34.56
 */

static VALUE
num_abs(num)
    VALUE num;
{
    if (RTEST(rb_funcall(num, '<', 1, INT2FIX(0)))) {
	return rb_funcall(num, rb_intern("-@"), 0);
    }
    return num;
}


/*
 *  call-seq:
 *     num.zero?    => true or false
 *
 *  Returns <code>true</code> if <i>num</i> has a zero value.
 */

static VALUE
num_zero_p(num)
    VALUE num;
{
    if (rb_equal(num, INT2FIX(0))) {
	return Qtrue;
    }
    return Qfalse;
}


/*
 *  call-seq:
 *     num.nonzero?    => num or nil
 *
 *  Returns <i>num</i> if <i>num</i> is not zero, <code>nil</code>
 *  otherwise. This behavior is useful when chaining comparisons:
 *
 *     a = %w( z Bb bB bb BB a aA Aa AA A )
 *     b = a.sort {|a,b| (a.downcase <=> b.downcase).nonzero? || a <=> b }
 *     b   #=> ["A", "a", "AA", "Aa", "aA", "BB", "Bb", "bB", "bb", "z"]
 */

static VALUE
num_nonzero_p(num)
    VALUE num;
{
    if (RTEST(rb_funcall(num, rb_intern("zero?"), 0, 0))) {
	return Qnil;
    }
    return num;
}

/*
 *  call-seq:
 *     num.to_int    => integer
 *
 *  Invokes the child class's <code>to_i</code> method to convert
 *  <i>num</i> to an integer.
 */

static VALUE
num_to_int(num)
    VALUE num;
{
    return rb_funcall(num, id_to_i, 0, 0);
}


/********************************************************************
 *
 * Document-class: Float
 *
 *  <code>Float</code> objects represent real numbers using the native
 *  architecture's double-precision floating point representation.
 */

VALUE
rb_float_new(d)
    double d;
{
    NEWOBJ(flt, struct RFloat);
    OBJSETUP(flt, rb_cFloat, T_FLOAT);

    flt->value = d;
    return (VALUE)flt;
}

/*
 *  call-seq:
 *     flt.to_s    => string
 *
 *  Returns a string containing a representation of self. As well as a
 *  fixed or exponential form of the number, the call may return
 *  ``<code>NaN</code>'', ``<code>Infinity</code>'', and
 *  ``<code>-Infinity</code>''.
 */

static VALUE
flo_to_s(flt)
    VALUE flt;
{
    char buf[32];
    double value = RFLOAT(flt)->value;
    char *p, *e;

    if (isinf(value))
	return rb_str_new2(value < 0 ? "-Infinity" : "Infinity");
    else if(isnan(value))
	return rb_str_new2("NaN");

    sprintf(buf, "%#.15g", value); /* ensure to print decimal point */
    if (!(e = strchr(buf, 'e'))) {
	e = buf + strlen(buf);
    }
    if (!ISDIGIT(e[-1])) { /* reformat if ended with decimal point (ex 111111111111111.) */
	sprintf(buf, "%#.14e", value);
	if (!(e = strchr(buf, 'e'))) {
	    e = buf + strlen(buf);
	}
    }
    p = e;
    while (p[-1]=='0' && ISDIGIT(p[-2]))
	p--;
    memmove(p, e, strlen(e)+1);
    return rb_str_new2(buf);
}

/*
 * MISSING: documentation
 */

static VALUE
flo_coerce(x, y)
    VALUE x, y;
{
    return rb_assoc_new(rb_Float(y), x);
}

/*
 * call-seq:
 *    -float   => float
 *
 * Returns float, negated.
 */

static VALUE
flo_uminus(flt)
    VALUE flt;
{
    return rb_float_new(-RFLOAT(flt)->value);
}

/*
 * call-seq:
 *   float + other   => float
 *
 * Returns a new float which is the sum of <code>float</code>
 * and <code>other</code>.
 */

static VALUE
flo_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return rb_float_new(RFLOAT(x)->value + (double)FIX2LONG(y));
      case T_BIGNUM:
	return rb_float_new(RFLOAT(x)->value + rb_big2dbl(y));
      case T_FLOAT:
	return rb_float_new(RFLOAT(x)->value + RFLOAT(y)->value);
      default:
	return rb_num_coerce_bin(x, y);
    }
}

/*
 * call-seq:
 *   float + other   => float
 *
 * Returns a new float which is the difference of <code>float</code>
 * and <code>other</code>.
 */

static VALUE
flo_minus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return rb_float_new(RFLOAT(x)->value - (double)FIX2LONG(y));
      case T_BIGNUM:
	return rb_float_new(RFLOAT(x)->value - rb_big2dbl(y));
      case T_FLOAT:
	return rb_float_new(RFLOAT(x)->value - RFLOAT(y)->value);
      default:
	return rb_num_coerce_bin(x, y);
    }
}

/*
 * call-seq:
 *   float * other   => float
 *
 * Returns a new float which is the product of <code>float</code>
 * and <code>other</code>.
 */

static VALUE
flo_mul(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return rb_float_new(RFLOAT(x)->value * (double)FIX2LONG(y));
      case T_BIGNUM:
	return rb_float_new(RFLOAT(x)->value * rb_big2dbl(y));
      case T_FLOAT:
	return rb_float_new(RFLOAT(x)->value * RFLOAT(y)->value);
      default:
	return rb_num_coerce_bin(x, y);
    }
}

/*
 * call-seq:
 *   float / other   => float
 *
 * Returns a new float which is the result of dividing
 * <code>float</code> by <code>other</code>.
 */

static VALUE
flo_div(x, y)
    VALUE x, y;
{
    long f_y;
    double d;

    switch (TYPE(y)) {
      case T_FIXNUM:
	f_y = FIX2LONG(y);
	return rb_float_new(RFLOAT(x)->value / (double)f_y);
      case T_BIGNUM:
	d = rb_big2dbl(y);
	return rb_float_new(RFLOAT(x)->value / d);
      case T_FLOAT:
	return rb_float_new(RFLOAT(x)->value / RFLOAT(y)->value);
      default:
	return rb_num_coerce_bin(x, y);
    }
}


static void
flodivmod(x, y, divp, modp)
    double x, y;
    double *divp, *modp;
{
    double div, mod;

#ifdef HAVE_FMOD
    mod = fmod(x, y);
#else
    {
	double z;

	modf(x/y, &z);
	mod = x - z * y;
    }
#endif
    if (isinf(x) && !isinf(y) && !isnan(y))
	div = x;
    else
	div = (x - mod) / y;
    if (y*mod < 0) {
	mod += y;
	div -= 1.0;
    }
    if (modp) *modp = mod;
    if (divp) *divp = div;
}


/*
 *  call-seq:
 *     flt % other         => float
 *     flt.modulo(other)   => float
 *
 *  Return the modulo after division of <code>flt</code> by <code>other</code>.
 *
 *     6543.21.modulo(137)      #=> 104.21
 *     6543.21.modulo(137.24)   #=> 92.9299999999996
 */

static VALUE
flo_mod(x, y)
    VALUE x, y;
{
    double fy, mod;

    switch (TYPE(y)) {
      case T_FIXNUM:
	fy = (double)FIX2LONG(y);
	break;
      case T_BIGNUM:
	fy = rb_big2dbl(y);
	break;
      case T_FLOAT:
	fy = RFLOAT(y)->value;
	break;
      default:
	return rb_num_coerce_bin(x, y);
    }
    flodivmod(RFLOAT(x)->value, fy, 0, &mod);
    return rb_float_new(mod);
}

/*
 *  call-seq:
 *     flt.divmod(numeric)    => array
 *
 *  See <code>Numeric#divmod</code>.
 */

static VALUE
flo_divmod(x, y)
    VALUE x, y;
{
    double fy, div, mod, val;
    volatile VALUE a, b;

    switch (TYPE(y)) {
      case T_FIXNUM:
	fy = (double)FIX2LONG(y);
	break;
      case T_BIGNUM:
	fy = rb_big2dbl(y);
	break;
      case T_FLOAT:
	fy = RFLOAT(y)->value;
	break;
      default:
	return rb_num_coerce_bin(x, y);
    }
    flodivmod(RFLOAT(x)->value, fy, &div, &mod);
    if (FIXABLE(div)) {
        val = round(div);
	a = LONG2FIX(val);
    }
    else {
	a = rb_dbl2big(div);
    }
    b = rb_float_new(mod);
    return rb_assoc_new(a, b);
}

/*
 * call-seq:
 *
 *  flt ** other   => float
 *
 * Raises <code>float</code> the <code>other</code> power.
 */

static VALUE
flo_pow(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
        return rb_float_new(pow(RFLOAT(x)->value, (double)FIX2LONG(y)));
      case T_BIGNUM:
	return rb_float_new(pow(RFLOAT(x)->value, rb_big2dbl(y)));
      case T_FLOAT:
        return rb_float_new(pow(RFLOAT(x)->value, RFLOAT(y)->value));
      default:
        return rb_num_coerce_bin(x, y);
    }
}

/*
 *  call-seq:
 *     num.eql?(numeric)    => true or false
 *
 *  Returns <code>true</code> if <i>num</i> and <i>numeric</i> are the
 *  same type and have equal values.
 *
 *     1 == 1.0          #=> true
 *     1.eql?(1.0)       #=> false
 *     (1.0).eql?(1.0)   #=> true
 */

static VALUE
num_eql(x, y)
    VALUE x, y;
{
    if (TYPE(x) != TYPE(y)) return Qfalse;

    return rb_equal(x, y);
}

/*
 *  call-seq:
 *     num <=> other -> 0 or nil
 *
 *  Returns zero if <i>num</i> equals <i>other</i>, <code>nil</code>
 *  otherwise.
 */

static VALUE
num_cmp(x, y)
    VALUE x, y;
{
    if (x == y) return INT2FIX(0);
    return Qnil;
}

static VALUE
num_equal(x, y)
    VALUE x, y;
{
    if (x == y) return Qtrue;
    return rb_funcall(y, id_eq, 1, x);
}

/*
 *  call-seq:
 *     flt == obj   => true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> has the same value
 *  as <i>flt</i>. Contrast this with <code>Float#eql?</code>, which
 *  requires <i>obj</i> to be a <code>Float</code>.
 *
 *     1.0 == 1   #=> true
 *
 */

static VALUE
flo_eq(x, y)
    VALUE x, y;
{
    volatile double a, b;

    switch (TYPE(y)) {
      case T_FIXNUM:
	b = FIX2LONG(y);
	break;
      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;
      case T_FLOAT:
	b = RFLOAT(y)->value;
	if (isnan(b)) return Qfalse;
	break;
      default:
	return num_equal(x, y);
    }
    a = RFLOAT(x)->value;
    if (isnan(a)) return Qfalse;
    return (a == b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   flt.hash   => integer
 *
 * Returns a hash code for this float.
 */

static VALUE
flo_hash(num)
    VALUE num;
{
    double d;
    char *c;
    int i, hash;

    d = RFLOAT(num)->value;
    if (d == 0) d = fabs(d);
    c = (char*)&d;
    for (hash=0, i=0; i<sizeof(double);i++) {
	hash = (hash * 971) ^ (unsigned char)c[i];
    }
    if (hash < 0) hash = -hash;
    return INT2FIX(hash);
}

VALUE
rb_dbl_cmp(a, b)
    double a, b;
{
    if (isnan(a) || isnan(b)) return Qnil;
    if (a == b) return INT2FIX(0);
    if (a > b) return INT2FIX(1);
    if (a < b) return INT2FIX(-1);
    return Qnil;
}

/*
 *  call-seq:
 *     flt <=> numeric   => -1, 0, +1 or nil
 *
 *  Returns -1, 0, or +1 depending on whether <i>flt</i> is less than,
 *  equal to, or greater than <i>numeric</i>. This is the basis for the
 *  tests in <code>Comparable</code>.
 */

static VALUE
flo_cmp(x, y)
    VALUE x, y;
{
    double a, b;

    a = RFLOAT(x)->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;

      case T_FLOAT:
	b = RFLOAT(y)->value;
	break;

      default:
	return rb_num_coerce_cmp(x, y);
    }
    return rb_dbl_cmp(a, b);
}

/*
 * call-seq:
 *   flt > other    =>  true or false
 *
 * <code>true</code> if <code>flt</code> is greater than <code>other</code>.
 */

static VALUE
flo_gt(x, y)
    VALUE x, y;
{
    double a, b;

    a = RFLOAT(x)->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;

      case T_FLOAT:
	b = RFLOAT(y)->value;
	if (isnan(b)) return Qfalse;
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a)) return Qfalse;
    return (a > b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   flt >= other    =>  true or false
 *
 * <code>true</code> if <code>flt</code> is greater than
 * or equal to <code>other</code>.
 */

static VALUE
flo_ge(x, y)
    VALUE x, y;
{
    double a, b;

    a = RFLOAT(x)->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;

      case T_FLOAT:
	b = RFLOAT(y)->value;
	if (isnan(b)) return Qfalse;
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a)) return Qfalse;
    return (a >= b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   flt < other    =>  true or false
 *
 * <code>true</code> if <code>flt</code> is less than <code>other</code>.
 */

static VALUE
flo_lt(x, y)
    VALUE x, y;
{
    double a, b;

    a = RFLOAT(x)->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;

      case T_FLOAT:
	b = RFLOAT(y)->value;
	if (isnan(b)) return Qfalse;
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a)) return Qfalse;
    return (a < b)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   flt <= other    =>  true or false
 *
 * <code>true</code> if <code>flt</code> is less than
 * or equal to <code>other</code>.
 */

static VALUE
flo_le(x, y)
    VALUE x, y;
{
    double a, b;

    a = RFLOAT(x)->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;

      case T_FLOAT:
	b = RFLOAT(y)->value;
	if (isnan(b)) return Qfalse;
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a)) return Qfalse;
    return (a <= b)?Qtrue:Qfalse;
}

/*
 *  call-seq:
 *     flt.eql?(obj)   => true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> is a
 *  <code>Float</code> with the same value as <i>flt</i>. Contrast this
 *  with <code>Float#==</code>, which performs type conversions.
 *
 *     1.0.eql?(1)   #=> false
 */

static VALUE
flo_eql(x, y)
    VALUE x, y;
{
    if (TYPE(y) == T_FLOAT) {
	double a = RFLOAT(x)->value;
	double b = RFLOAT(y)->value;

	if (isnan(a) || isnan(b)) return Qfalse;
	if (a == b) return Qtrue;
    }
    return Qfalse;
}

/*
 * call-seq:
 *   flt.to_f   => flt
 *
 * As <code>flt</code> is already a float, returns <i>self</i>.
 */

static VALUE
flo_to_f(num)
    VALUE num;
{
    return num;
}

/*
 *  call-seq:
 *     flt.abs    => float
 *
 *  Returns the absolute value of <i>flt</i>.
 *
 *     (-34.56).abs   #=> 34.56
 *     -34.56.abs     #=> 34.56
 *
 */

static VALUE
flo_abs(flt)
    VALUE flt;
{
    double val = fabs(RFLOAT(flt)->value);
    return rb_float_new(val);
}

/*
 *  call-seq:
 *     flt.zero? -> true or false
 *
 *  Returns <code>true</code> if <i>flt</i> is 0.0.
 *
 */

static VALUE
flo_zero_p(num)
    VALUE num;
{
    if (RFLOAT(num)->value == 0.0) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     flt.nan? -> true or false
 *
 *  Returns <code>true</code> if <i>flt</i> is an invalid IEEE floating
 *  point number.
 *
 *     a = -1.0      #=> -1.0
 *     a.nan?        #=> false
 *     a = 0.0/0.0   #=> NaN
 *     a.nan?        #=> true
 */

static VALUE
flo_is_nan_p(num)
     VALUE num;
{
    double value = RFLOAT(num)->value;

    return isnan(value) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     flt.infinite? -> nil, -1, +1
 *
 *  Returns <code>nil</code>, -1, or +1 depending on whether <i>flt</i>
 *  is finite, -infinity, or +infinity.
 *
 *     (0.0).infinite?        #=> nil
 *     (-1.0/0.0).infinite?   #=> -1
 *     (+1.0/0.0).infinite?   #=> 1
 */

static VALUE
flo_is_infinite_p(num)
     VALUE num;
{
    double value = RFLOAT(num)->value;

    if (isinf(value)) {
	return INT2FIX( value < 0 ? -1 : 1 );
    }

    return Qnil;
}

/*
 *  call-seq:
 *     flt.finite? -> true or false
 *
 *  Returns <code>true</code> if <i>flt</i> is a valid IEEE floating
 *  point number (it is not infinite, and <code>nan?</code> is
 *  <code>false</code>).
 *
 */

static VALUE
flo_is_finite_p(num)
     VALUE num;
{
    double value = RFLOAT(num)->value;

#if HAVE_FINITE
    if (!finite(value))
	return Qfalse;
#else
    if (isinf(value) || isnan(value))
	return Qfalse;
#endif

    return Qtrue;
}

/*
 *  call-seq:
 *     flt.floor   => integer
 *
 *  Returns the largest integer less than or equal to <i>flt</i>.
 *
 *     1.2.floor      #=> 1
 *     2.0.floor      #=> 2
 *     (-1.2).floor   #=> -2
 *     (-2.0).floor   #=> -2
 */

static VALUE
flo_floor(num)
    VALUE num;
{
    double f = floor(RFLOAT(num)->value);
    long val;

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return LONG2FIX(val);
}

/*
 *  call-seq:
 *     flt.ceil    => integer
 *
 *  Returns the smallest <code>Integer</code> greater than or equal to
 *  <i>flt</i>.
 *
 *     1.2.ceil      #=> 2
 *     2.0.ceil      #=> 2
 *     (-1.2).ceil   #=> -1
 *     (-2.0).ceil   #=> -2
 */

static VALUE
flo_ceil(num)
    VALUE num;
{
    double f = ceil(RFLOAT(num)->value);
    long val;

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return LONG2FIX(val);
}

/*
 *  call-seq:
 *     flt.round   => integer
 *
 *  Rounds <i>flt</i> to the nearest integer. Equivalent to:
 *
 *     def round
 *       return (self+0.5).floor if self > 0.0
 *       return (self-0.5).ceil  if self < 0.0
 *       return 0
 *     end
 *
 *     1.5.round      #=> 2
 *     (-1.5).round   #=> -2
 *
 */

static VALUE
flo_round(num)
    VALUE num;
{
    double f = RFLOAT(num)->value;
    long val;

    f = round(f);

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return LONG2FIX(val);
}

/*
 *  call-seq:
 *     flt.to_i       => integer
 *     flt.to_int     => integer
 *     flt.truncate   => integer
 *
 *  Returns <i>flt</i> truncated to an <code>Integer</code>.
 */

static VALUE
flo_truncate(num)
    VALUE num;
{
    double f = RFLOAT(num)->value;
    long val;

    if (f > 0.0) f = floor(f);
    if (f < 0.0) f = ceil(f);

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return LONG2FIX(val);
}


/*
 *  call-seq:
 *     num.floor    => integer
 *
 *  Returns the largest integer less than or equal to <i>num</i>.
 *  <code>Numeric</code> implements this by converting <i>anInteger</i>
 *  to a <code>Float</code> and invoking <code>Float#floor</code>.
 *
 *     1.floor      #=> 1
 *     (-1).floor   #=> -1
 */

static VALUE
num_floor(num)
    VALUE num;
{
    return flo_floor(rb_Float(num));
}


/*
 *  call-seq:
 *     num.ceil    => integer
 *
 *  Returns the smallest <code>Integer</code> greater than or equal to
 *  <i>num</i>. Class <code>Numeric</code> achieves this by converting
 *  itself to a <code>Float</code> then invoking
 *  <code>Float#ceil</code>.
 *
 *     1.ceil        #=> 1
 *     1.2.ceil      #=> 2
 *     (-1.2).ceil   #=> -1
 *     (-1.0).ceil   #=> -1
 */

static VALUE
num_ceil(num)
    VALUE num;
{
    return flo_ceil(rb_Float(num));
}

/*
 *  call-seq:
 *     num.round    => integer
 *
 *  Rounds <i>num</i> to the nearest integer. <code>Numeric</code>
 *  implements this by converting itself to a
 *  <code>Float</code> and invoking <code>Float#round</code>.
 */

static VALUE
num_round(num)
    VALUE num;
{
    return flo_round(rb_Float(num));
}

/*
 *  call-seq:
 *     num.truncate    => integer
 *
 *  Returns <i>num</i> truncated to an integer. <code>Numeric</code>
 *  implements this by converting its value to a float and invoking
 *  <code>Float#truncate</code>.
 */

static VALUE
num_truncate(num)
    VALUE num;
{
    return flo_truncate(rb_Float(num));
}


int ruby_float_step _((VALUE from, VALUE to, VALUE step, int excl));

int
ruby_float_step(from, to, step, excl)
    VALUE from, to, step;
    int excl;
{
    if (TYPE(from) == T_FLOAT || TYPE(to) == T_FLOAT || TYPE(step) == T_FLOAT) {
	const double epsilon = DBL_EPSILON;
	double beg = NUM2DBL(from);
	double end = NUM2DBL(to);
	double unit = NUM2DBL(step);
	double n = (end - beg)/unit;
	double err = (fabs(beg) + fabs(end) + fabs(end-beg)) / fabs(unit) * epsilon;
	long i;

	if (err>0.5) err=0.5;
	n = floor(n + err);
	if (!excl) n++;
	for (i=0; i<n; i++) {
	    rb_yield(rb_float_new(i*unit+beg));
	}
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     num.step(limit, step ) {|i| block }     => num
 *
 *  Invokes <em>block</em> with the sequence of numbers starting at
 *  <i>num</i>, incremented by <i>step</i> on each call. The loop
 *  finishes when the value to be passed to the block is greater than
 *  <i>limit</i> (if <i>step</i> is positive) or less than
 *  <i>limit</i> (if <i>step</i> is negative). If all the arguments are
 *  integers, the loop operates using an integer counter. If any of the
 *  arguments are floating point numbers, all are converted to floats,
 *  and the loop is executed <i>floor(n + n*epsilon)+ 1</i> times,
 *  where <i>n = (limit - num)/step</i>. Otherwise, the loop
 *  starts at <i>num</i>, uses either the <code><</code> or
 *  <code>></code> operator to compare the counter against
 *  <i>limit</i>, and increments itself using the <code>+</code>
 *  operator.
 *
 *     1.step(10, 2) { |i| print i, " " }
 *     Math::E.step(Math::PI, 0.2) { |f| print f, " " }
 *
 *  <em>produces:</em>
 *
 *     1 3 5 7 9
 *     2.71828182845905 2.91828182845905 3.11828182845905
 */

static VALUE
num_step(argc, argv, from)
    int argc;
    VALUE *argv;
    VALUE from;
{
    VALUE to, step;

    RETURN_ENUMERATOR(from, argc, argv);

    if (argc == 1) {
	to = argv[0];
	step = INT2FIX(1);
    }
    else {
	if (argc == 2) {
	    to = argv[0];
	    step = argv[1];
	}
	else {
	    rb_raise(rb_eArgError, "wrong number of arguments");
	}
	if (rb_equal(step, INT2FIX(0))) {
	    rb_raise(rb_eArgError, "step can't be 0");
	}
    }

    if (FIXNUM_P(from) && FIXNUM_P(to) && FIXNUM_P(step)) {
	long i, end, diff;

	i = FIX2LONG(from);
	end = FIX2LONG(to);
	diff = FIX2LONG(step);

	if (diff > 0) {
	    while (i <= end) {
		rb_yield(LONG2FIX(i));
		i += diff;
	    }
	}
	else {
	    while (i >= end) {
		rb_yield(LONG2FIX(i));
		i += diff;
	    }
	}
    }
    else if (!ruby_float_step(from, to, step, Qfalse)) {
	VALUE i = from;
	ID cmp;

	if (RTEST(rb_funcall(step, '>', 1, INT2FIX(0)))) {
	    cmp = '>';
	}
	else {
	    cmp = '<';
	}
	for (;;) {
	    if (RTEST(rb_funcall(i, cmp, 1, to))) break;
	    rb_yield(i);
	    i = rb_funcall(i, '+', 1, step);
	}
    }
    return from;
}

long
rb_num2long(val)
    VALUE val;
{
  again:
    if (NIL_P(val)) {
	rb_raise(rb_eTypeError, "no implicit conversion from nil to integer");
    }

    if (FIXNUM_P(val)) return FIX2LONG(val);

    switch (TYPE(val)) {
      case T_FLOAT:
	if (RFLOAT(val)->value <= (double)LONG_MAX
	    && RFLOAT(val)->value >= (double)LONG_MIN) {
	    return (long)(RFLOAT(val)->value);
	}
	else {
	    char buf[24];
	    char *s;

	    sprintf(buf, "%-.10g", RFLOAT(val)->value);
	    if ((s = strchr(buf, ' ')) != 0) *s = '\0';
	    rb_raise(rb_eRangeError, "float %s out of range of integer", buf);
	}

      case T_BIGNUM:
	return rb_big2long(val);

      default:
	val = rb_to_int(val);
	goto again;
    }
}

unsigned long
rb_num2ulong(val)
    VALUE val;
{
    if (TYPE(val) == T_BIGNUM) {
	return rb_big2ulong(val);
    }
    return (unsigned long)rb_num2long(val);
}

#if SIZEOF_INT < SIZEOF_LONG
static void
check_int(num)
    long num;
{
    const char *s;

    if (num < INT_MIN) {
	s = "small";
    }
    else if (num > INT_MAX) {
	s = "big";
    }
    else {
	return;
    }
    rb_raise(rb_eRangeError, "integer %ld too %s to convert to `int'", num, s);
}

static void
check_uint(num, sign)
    unsigned long num;
    VALUE sign;
{
    static const unsigned long mask = ~(unsigned long)UINT_MAX;

    if (RTEST(sign)) {
	/* minus */
	if ((num & mask) != mask || (num & ~mask) <= INT_MAX + 1UL)
	    rb_raise(rb_eRangeError, "integer %ld too small to convert to `unsigned int'", num);
    }
    else {
	/* plus */
	if ((num & mask) != 0)
	    rb_raise(rb_eRangeError, "integer %lu too big to convert to `unsigned int'", num);
    }
}

long
rb_num2int(val)
    VALUE val;
{
    long num = rb_num2long(val);

    check_int(num);
    return num;
}

long
rb_fix2int(val)
    VALUE val;
{
    long num = FIXNUM_P(val)?FIX2LONG(val):rb_num2long(val);

    check_int(num);
    return num;
}

unsigned long
rb_num2uint(val)
    VALUE val;
{
    unsigned long num = rb_num2ulong(val);

    check_uint(num, rb_funcall(val, '<', 1, INT2FIX(0)));
    return num;
}

unsigned long
rb_fix2uint(val)
    VALUE val;
{
    unsigned long num;

    if (!FIXNUM_P(val)) {
        return rb_num2uint(val);
    }
    num = FIX2ULONG(val);

    check_uint(num, rb_funcall(val, '<', 1, INT2FIX(0)));
    return num;
}
#else
long
rb_num2int(val)
    VALUE val;
{
    return rb_num2long(val);
}

long
rb_fix2int(val)
    VALUE val;
{
    return FIX2INT(val);
}
#endif

VALUE
rb_num2fix(val)
    VALUE val;
{
    long v;

    if (FIXNUM_P(val)) return val;

    v = rb_num2long(val);
    if (!FIXABLE(v))
	rb_raise(rb_eRangeError, "integer %ld out of range of fixnum", v);
    return LONG2FIX(v);
}

#if HAVE_LONG_LONG

LONG_LONG
rb_num2ll(val)
    VALUE val;
{
    if (NIL_P(val)) {
	rb_raise(rb_eTypeError, "no implicit conversion from nil");
    }

    if (FIXNUM_P(val)) return (LONG_LONG)FIX2LONG(val);

    switch (TYPE(val)) {
    case T_FLOAT:
	if (RFLOAT(val)->value <= (double)LLONG_MAX
	    && RFLOAT(val)->value >= (double)LLONG_MIN) {
	    return (LONG_LONG)(RFLOAT(val)->value);
	}
	else {
	    char buf[24];
	    char *s;

	    sprintf(buf, "%-.10g", RFLOAT(val)->value);
	    if ((s = strchr(buf, ' ')) != 0) *s = '\0';
	    rb_raise(rb_eRangeError, "float %s out of range of long long", buf);
	}

    case T_BIGNUM:
	return rb_big2ll(val);

    case T_STRING:
	rb_raise(rb_eTypeError, "no implicit conversion from string");
	return Qnil;            /* not reached */

    case T_TRUE:
    case T_FALSE:
	rb_raise(rb_eTypeError, "no implicit conversion from boolean");
	return Qnil;		/* not reached */

      default:
	  val = rb_to_int(val);
	  return NUM2LL(val);
    }
}

unsigned LONG_LONG
rb_num2ull(val)
    VALUE val;
{
    if (TYPE(val) == T_BIGNUM) {
	return rb_big2ull(val);
    }
    return (unsigned LONG_LONG)rb_num2ll(val);
}

#endif  /* HAVE_LONG_LONG */


/*
 * Document-class: Integer
 *
 *  <code>Integer</code> is the basis for the two concrete classes that
 *  hold whole numbers, <code>Bignum</code> and <code>Fixnum</code>.
 *
 */


/*
 *  call-seq:
 *     int.to_i      => int
 *     int.to_int    => int
 *     int.floor     => int
 *     int.ceil      => int
 *     int.round     => int
 *     int.truncate  => int
 *
 *  As <i>int</i> is already an <code>Integer</code>, all these
 *  methods simply return the receiver.
 */

static VALUE
int_to_i(num)
    VALUE num;
{
    return num;
}

/*
 *  call-seq:
 *     int.integer? -> true
 *
 *  Always returns <code>true</code>.
 */

static VALUE
int_int_p(num)
    VALUE num;
{
    return Qtrue;
}

/*
 *  call-seq:
 *     int.odd? -> true or false
 *
 *  Returns <code>true</code> if <i>int</i> is an odd number.
 */

static VALUE
int_odd_p(num)
    VALUE num;
{
    if (rb_funcall(num, '%', 1, INT2FIX(2)) != INT2FIX(0)) {
        return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     int.even? -> true or false
 *
 *  Returns <code>true</code> if <i>int</i> is an even number.
 */

static VALUE
int_even_p(num)
    VALUE num;
{
    if (rb_funcall(num, '%', 1, INT2FIX(2)) == INT2FIX(0)) {
        return Qtrue;
    }
    return Qfalse;
}


/*
 *  call-seq:
 *     int.next    => integer
 *     int.succ    => integer
 *
 *  Returns the <code>Integer</code> equal to <i>int</i> + 1.
 *
 *     1.next      #=> 2
 *     (-1).next   #=> 0
 */

static VALUE
int_succ(num)
    VALUE num;
{
    if (FIXNUM_P(num)) {
	long i = FIX2LONG(num) + 1;
	return LONG2NUM(i);
    }
    return rb_funcall(num, '+', 1, INT2FIX(1));
}

/*
 *  call-seq:
 *     int.pred    => integer
 *
 *  Returns the <code>Integer</code> equal to <i>int</i> - 1.
 *
 *     1.pred      #=> 0
 *     (-1).pred   #=> -2
 */

static VALUE
int_pred(num)
    VALUE num;
{
    if (FIXNUM_P(num)) {
        long i = FIX2LONG(num) - 1;
        return LONG2NUM(i);
    }
    return rb_funcall(num, '-', 1, INT2FIX(1));
}

/*
 *  call-seq:
 *     int.chr    => string
 *
 *  Returns a string containing the ASCII character represented by the
 *  receiver's value.
 *
 *     65.chr    #=> "A"
 *     ?a.chr    #=> "a"
 *     230.chr   #=> "\346"
 */

static VALUE
int_chr(num)
    VALUE num;
{
    char c;
    long i = NUM2LONG(num);

    if (i < 0 || 0xff < i)
	rb_raise(rb_eRangeError, "%ld out of char range", i);
    c = i;
    return rb_str_new(&c, 1);
}

/*
 *  call-seq:
 *     int.ord    => int
 *
 *  Returns the int itself.
 *
 *     ?a.ord    #=> 97
 *
 *  This method is intended for compatibility to
 *  character constant in Ruby 1.9.
 *  For example, ?a.ord returns 97 both in 1.8 and 1.9.
 */

static VALUE
int_ord(num)
    VALUE num;
{
    return num;
}

/********************************************************************
 *
 * Document-class: Fixnum
 *
 *  A <code>Fixnum</code> holds <code>Integer</code> values that can be
 *  represented in a native machine word (minus 1 bit). If any operation
 *  on a <code>Fixnum</code> exceeds this range, the value is
 *  automatically converted to a <code>Bignum</code>.
 *
 *  <code>Fixnum</code> objects have immediate value. This means that
 *  when they are assigned or passed as parameters, the actual object is
 *  passed, rather than a reference to that object. Assignment does not
 *  alias <code>Fixnum</code> objects. There is effectively only one
 *  <code>Fixnum</code> object instance for any given integer value, so,
 *  for example, you cannot add a singleton method to a
 *  <code>Fixnum</code>.
 */


/*
 * call-seq:
 *   Fixnum.induced_from(obj)    =>  fixnum
 *
 * Convert <code>obj</code> to a Fixnum. Works with numeric parameters.
 * Also works with Symbols, but this is deprecated.
 */

static VALUE
rb_fix_induced_from(klass, x)
    VALUE klass, x;
{
    return rb_num2fix(x);
}

/*
 * call-seq:
 *   Integer.induced_from(obj)    =>  fixnum, bignum
 *
 * Convert <code>obj</code> to an Integer.
 */

static VALUE
rb_int_induced_from(klass, x)
    VALUE klass, x;
{
    switch (TYPE(x)) {
    case T_FIXNUM:
    case T_BIGNUM:
       return x;
    case T_FLOAT:
       return rb_funcall(x, id_to_i, 0);
    default:
       rb_raise(rb_eTypeError, "failed to convert %s into Integer",
                rb_obj_classname(x));
    }
}

/*
 * call-seq:
 *   Float.induced_from(obj)    =>  float
 *
 * Convert <code>obj</code> to a float.
 */

static VALUE
rb_flo_induced_from(klass, x)
    VALUE klass, x;
{
    switch (TYPE(x)) {
    case T_FIXNUM:
    case T_BIGNUM:
       return rb_funcall(x, rb_intern("to_f"), 0);
    case T_FLOAT:
       return x;
    default:
       rb_raise(rb_eTypeError, "failed to convert %s into Float",
                rb_obj_classname(x));
    }
}

/*
 * call-seq:
 *   -fix   =>  integer
 *
 * Negates <code>fix</code> (which might return a Bignum).
 */

static VALUE
fix_uminus(num)
    VALUE num;
{
    return LONG2NUM(-FIX2LONG(num));
}

VALUE
rb_fix2str(x, base)
    VALUE x;
    int base;
{
    extern const char ruby_digitmap[];
    char buf[SIZEOF_LONG*CHAR_BIT + 2], *b = buf + sizeof buf;
    long val = FIX2LONG(x);
    int neg = 0;

    if (base < 2 || 36 < base) {
	rb_raise(rb_eArgError, "illegal radix %d", base);
    }
    if (val == 0) {
	return rb_str_new2("0");
    }
    if (val < 0) {
	val = -val;
	neg = 1;
    }
    *--b = '\0';
    do {
	*--b = ruby_digitmap[(int)(val % base)];
    } while (val /= base);
    if (neg) {
	*--b = '-';
    }

    return rb_str_new2(b);
}

/*
 *  call-seq:
 *     fix.to_s( base=10 ) -> aString
 *
 *  Returns a string containing the representation of <i>fix</i> radix
 *  <i>base</i> (between 2 and 36).
 *
 *     12345.to_s       #=> "12345"
 *     12345.to_s(2)    #=> "11000000111001"
 *     12345.to_s(8)    #=> "30071"
 *     12345.to_s(10)   #=> "12345"
 *     12345.to_s(16)   #=> "3039"
 *     12345.to_s(36)   #=> "9ix"
 *
 */
static VALUE
fix_to_s(argc, argv, x)
    int argc;
    VALUE *argv;
    VALUE x;
{
    VALUE b;
    int base;

    rb_scan_args(argc, argv, "01", &b);
    if (argc == 0) base = 10;
    else base = NUM2INT(b);

    return rb_fix2str(x, base);
}

/*
 * call-seq:
 *   fix + numeric   =>  numeric_result
 *
 * Performs addition: the class of the resulting object depends on
 * the class of <code>numeric</code> and on the magnitude of the
 * result.
 */

static VALUE
fix_plus(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a, b, c;
	VALUE r;

	a = FIX2LONG(x);
	b = FIX2LONG(y);
	c = a + b;
	r = LONG2NUM(c);

	return r;
    }
    if (TYPE(y) == T_FLOAT) {
	return rb_float_new((double)FIX2LONG(x) + RFLOAT(y)->value);
    }
    return rb_num_coerce_bin(x, y);
}

/*
 * call-seq:
 *   fix - numeric   =>  numeric_result
 *
 * Performs subtraction: the class of the resulting object depends on
 * the class of <code>numeric</code> and on the magnitude of the
 * result.
 */

static VALUE
fix_minus(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a, b, c;
	VALUE r;

	a = FIX2LONG(x);
	b = FIX2LONG(y);
	c = a - b;
	r = LONG2NUM(c);

	return r;
    }
    if (TYPE(y) == T_FLOAT) {
	return rb_float_new((double)FIX2LONG(x) - RFLOAT(y)->value);
    }
    return rb_num_coerce_bin(x, y);
}

/*
 * call-seq:
 *   fix * numeric   =>  numeric_result
 *
 * Performs multiplication: the class of the resulting object depends on
 * the class of <code>numeric</code> and on the magnitude of the
 * result.
 */

static VALUE
fix_mul(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
#ifdef __HP_cc
        /* avoids an optimization bug of HP aC++/ANSI C B3910B A.06.05 [Jul 25 2005] */
        volatile
#endif
	long a, b, c;
	VALUE r;

	a = FIX2LONG(x);
	if (a == 0) return x;

	b = FIX2LONG(y);
	c = a * b;
	r = LONG2FIX(c);

	if (FIX2LONG(r) != c || c/a != b) {
	    r = rb_big_mul(rb_int2big(a), rb_int2big(b));
	}
	return r;
    }
    if (TYPE(y) == T_FLOAT) {
	return rb_float_new((double)FIX2LONG(x) * RFLOAT(y)->value);
    }
    return rb_num_coerce_bin(x, y);
}

static void
fixdivmod(x, y, divp, modp)
    long x, y;
    long *divp, *modp;
{
    long div, mod;

    if (y == 0) rb_num_zerodiv();
    if (y < 0) {
	if (x < 0)
	    div = -x / -y;
	else
	    div = - (x / -y);
    }
    else {
	if (x < 0)
	    div = - (-x / y);
	else
	    div = x / y;
    }
    mod = x - div*y;
    if ((mod < 0 && y > 0) || (mod > 0 && y < 0)) {
	mod += y;
	div -= 1;
    }
    if (divp) *divp = div;
    if (modp) *modp = mod;
}

/*
 *  call-seq:
 *     fix.quo(numeric)    => float
 *     fix.fdiv(numeric)   => float
 *
 *  Returns the floating point result of dividing <i>fix</i> by
 *  <i>numeric</i>.
 *
 *     654321.quo(13731)      #=> 47.6528293642124
 *     654321.quo(13731.24)   #=> 47.6519964693647
 *
 */

static VALUE
fix_quo(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return rb_float_new((double)FIX2LONG(x) / (double)FIX2LONG(y));
    }
    return rb_num_coerce_bin(x, y);
}

/*
 * call-seq:
 *   fix / numeric      =>  numeric_result
 *   fix.div(numeric)   =>  numeric_result
 *
 * Performs division: the class of the resulting object depends on
 * the class of <code>numeric</code> and on the magnitude of the
 * result.
 */

static VALUE
fix_div(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long div;

	fixdivmod(FIX2LONG(x), FIX2LONG(y), &div, 0);
	return LONG2NUM(div);
    }
    return rb_num_coerce_bin(x, y);
}

/*
 *  call-seq:
 *    fix % other         => Numeric
 *    fix.modulo(other)   => Numeric
 *
 *  Returns <code>fix</code> modulo <code>other</code>.
 *  See <code>Numeric.divmod</code> for more information.
 */

static VALUE
fix_mod(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long mod;

	fixdivmod(FIX2LONG(x), FIX2LONG(y), 0, &mod);
	return LONG2NUM(mod);
    }
    return rb_num_coerce_bin(x, y);
}

/*
 *  call-seq:
 *     fix.divmod(numeric)    => array
 *
 *  See <code>Numeric#divmod</code>.
 */
static VALUE
fix_divmod(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long div, mod;

	fixdivmod(FIX2LONG(x), FIX2LONG(y), &div, &mod);

	return rb_assoc_new(LONG2NUM(div), LONG2NUM(mod));
    }
    return rb_num_coerce_bin(x, y);
}

static VALUE
int_pow(x, y)
    long x;
    unsigned long y;
{
    int neg = x < 0;
    long z = 1;

    if (neg) x = -x;
    if (y & 1)
	z = x;
    else
	neg = 0;
    y &= ~1;
    do {
	while (y % 2 == 0) {
	    long x2 = x * x;
	    if (x2/x != x || !POSFIXABLE(x2)) {
		VALUE v;
	      bignum:
		v = rb_big_pow(rb_int2big(x), LONG2NUM(y));
		if (z != 1) v = rb_big_mul(rb_int2big(neg ? -z : z), v);
		return v;
	    }
	    x = x2;
	    y >>= 1;
	}
	{
	    long xz = x * z;
	    if (!POSFIXABLE(xz) || xz / x != z) {
		goto bignum;
	    }
	    z = xz;
	}
    } while (--y);
    if (neg) z = -z;
    return LONG2NUM(z);
}

/*
 *  call-seq:
 *    fix ** other         => Numeric
 *
 *  Raises <code>fix</code> to the <code>other</code> power, which may
 *  be negative or fractional.
 *
 *    2 ** 3      #=> 8
 *    2 ** -1     #=> 0.5
 *    2 ** 0.5    #=> 1.4142135623731
 */

static VALUE
fix_pow(x, y)
    VALUE x, y;
{
    static const double zero = 0.0;
    long a = FIX2LONG(x);

    if (FIXNUM_P(y)) {
	long b = FIX2LONG(y);

	if (b == 0) return INT2FIX(1);
	if (b == 1) return x;
	if (a == 0) {
	    if (b > 0) return INT2FIX(0);
	    return rb_float_new(1.0 / zero);
	}
	if (a == 1) return INT2FIX(1);
	if (a == -1) {
	    if (b % 2 == 0)
		return INT2FIX(1);
	    else
		return INT2FIX(-1);
	}
	if (b > 0) {
	    return int_pow(a, b);
	}
	return rb_float_new(pow((double)a, (double)b));
    }
    switch (TYPE(y)) {
      case T_BIGNUM:
	if (a == 0) return INT2FIX(0);
	if (a == 1) return INT2FIX(1);
	if (a == -1) {
	    if (int_even_p(y)) return INT2FIX(1);
	    else return INT2FIX(-1);
	}
	x = rb_int2big(FIX2LONG(x));
	return rb_big_pow(x, y);
      case T_FLOAT:
	if (RFLOAT(y)->value == 0.0) return rb_float_new(1.0);
	if (a == 0) {
	    return rb_float_new(RFLOAT(y)->value < 0 ? (1.0 / zero) : 0.0);
	}
	if (a == 1) return rb_float_new(1.0);
	return rb_float_new(pow((double)a, RFLOAT(y)->value));
      default:
	return rb_num_coerce_bin(x, y);
    }
}

/*
 * call-seq:
 *   fix == other
 *
 * Return <code>true</code> if <code>fix</code> equals <code>other</code>
 * numerically.
 *
 *   1 == 2      #=> false
 *   1 == 1.0    #=> true
 */

static VALUE
fix_equal(x, y)
    VALUE x, y;
{
    if (x == y) return Qtrue;
    if (FIXNUM_P(y)) return Qfalse;
    return num_equal(x, y);
}

/*
 *  call-seq:
 *     fix <=> numeric    => -1, 0, +1 or nil
 *
 *  Comparison---Returns -1, 0, or +1 depending on whether <i>fix</i> is
 *  less than, equal to, or greater than <i>numeric</i>. This is the
 *  basis for the tests in <code>Comparable</code>.
 */

static VALUE
fix_cmp(x, y)
    VALUE x, y;
{
    if (x == y) return INT2FIX(0);
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a > b) return INT2FIX(1);
	return INT2FIX(-1);
    }
    else {
	return rb_num_coerce_cmp(x, y);
    }
}

/*
 * call-seq:
 *   fix > other     => true or false
 *
 * Returns <code>true</code> if the value of <code>fix</code> is
 * greater than that of <code>other</code>.
 */

static VALUE
fix_gt(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a > b) return Qtrue;
	return Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y);
    }
}

/*
 * call-seq:
 *   fix >= other     => true or false
 *
 * Returns <code>true</code> if the value of <code>fix</code> is
 * greater than or equal to that of <code>other</code>.
 */

static VALUE
fix_ge(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a >= b) return Qtrue;
	return Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y);
    }
}

/*
 * call-seq:
 *   fix < other     => true or false
 *
 * Returns <code>true</code> if the value of <code>fix</code> is
 * less than that of <code>other</code>.
 */

static VALUE
fix_lt(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a < b) return Qtrue;
	return Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y);
    }
}

/*
 * call-seq:
 *   fix <= other     => true or false
 *
 * Returns <code>true</code> if the value of <code>fix</code> is
 * less thanor equal to that of <code>other</code>.
 */

static VALUE
fix_le(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a <= b) return Qtrue;
	return Qfalse;
    }
    else {
	return rb_num_coerce_relop(x, y);
    }
}

/*
 * call-seq:
 *   ~fix     => integer
 *
 * One's complement: returns a number where each bit is flipped.
 */

static VALUE
fix_rev(num)
    VALUE num;
{
    long val = FIX2LONG(num);

    val = ~val;
    return LONG2NUM(val);
}

static VALUE
fix_coerce(x)
    VALUE x;
{
    while (!FIXNUM_P(x) && TYPE(x) != T_BIGNUM) {
	x = rb_to_int(x);
    }
    return x;
}

/*
 * call-seq:
 *   fix & other     => integer
 *
 * Bitwise AND.
 */

static VALUE
fix_and(x, y)
    VALUE x, y;
{
    long val;

    if (!FIXNUM_P(y = fix_coerce(y))) {
	return rb_big_and(y, x);
    }
    val = FIX2LONG(x) & FIX2LONG(y);
    return LONG2NUM(val);
}

/*
 * call-seq:
 *   fix | other     => integer
 *
 * Bitwise OR.
 */

static VALUE
fix_or(x, y)
    VALUE x, y;
{
    long val;

    if (!FIXNUM_P(y = fix_coerce(y))) {
	return rb_big_or(y, x);
    }
    val = FIX2LONG(x) | FIX2LONG(y);
    return LONG2NUM(val);
}

/*
 * call-seq:
 *   fix ^ other     => integer
 *
 * Bitwise EXCLUSIVE OR.
 */

static VALUE
fix_xor(x, y)
    VALUE x, y;
{
    long val;

    if (!FIXNUM_P(y = fix_coerce(y))) {
	return rb_big_xor(y, x);
    }
    val = FIX2LONG(x) ^ FIX2LONG(y);
    return LONG2NUM(val);
}

static VALUE fix_lshift _((long, unsigned long));
static VALUE fix_rshift _((long, unsigned long));

/*
 * call-seq:
 *   fix << count     => integer
 *
 * Shifts _fix_ left _count_ positions (right if _count_ is negative).
 */

static VALUE
rb_fix_lshift(x, y)
    VALUE x, y;
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
fix_lshift(val, width)
    long val;
    unsigned long width;
{
    if (width > (sizeof(VALUE)*CHAR_BIT-1)
	|| ((unsigned long)val)>>(sizeof(VALUE)*CHAR_BIT-1-width) > 0) {
	return rb_big_lshift(rb_int2big(val), ULONG2NUM(width));
    }
    val = val << width;
    return LONG2NUM(val);
}

/*
 * call-seq:
 *   fix >> count     => integer
 *
 * Shifts _fix_ right _count_ positions (left if _count_ is negative).
 */

static VALUE
rb_fix_rshift(x, y)
    VALUE x, y;
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

/*
 *  call-seq:
 *     fix[n]     => 0, 1
 *
 *  Bit Reference---Returns the <em>n</em>th bit in the binary
 *  representation of <i>fix</i>, where <i>fix</i>[0] is the least
 *  significant bit.
 *
 *     a = 0b11001100101010
 *     30.downto(0) do |n| print a[n] end
 *
 *  <em>produces:</em>
 *
 *     0000000000000000011001100101010
 */

static VALUE
fix_aref(fix, idx)
    VALUE fix, idx;
{
    long val = FIX2LONG(fix);
    long i;

    if (!FIXNUM_P(idx = fix_coerce(idx))) {
	idx = rb_big_norm(idx);
	if (!FIXNUM_P(idx)) {
	    if (!RBIGNUM(idx)->sign || val >= 0)
		return INT2FIX(0);
	    return INT2FIX(1);
	}
    }
    i = FIX2LONG(idx);

    if (i < 0) return INT2FIX(0);
    if (sizeof(VALUE)*CHAR_BIT-1 < i) {
	if (val < 0) return INT2FIX(1);
	return INT2FIX(0);
    }
    if (val & (1L<<i))
	return INT2FIX(1);
    return INT2FIX(0);
}

/*
 *  call-seq:
 *     fix.to_f -> float
 *
 *  Converts <i>fix</i> to a <code>Float</code>.
 *
 */

static VALUE
fix_to_f(num)
    VALUE num;
{
    double val;

    val = (double)FIX2LONG(num);

    return rb_float_new(val);
}

/*
 *  call-seq:
 *     fix.abs -> aFixnum
 *
 *  Returns the absolute value of <i>fix</i>.
 *
 *     -12345.abs   #=> 12345
 *     12345.abs    #=> 12345
 *
 */

static VALUE
fix_abs(fix)
    VALUE fix;
{
    long i = FIX2LONG(fix);

    if (i < 0) i = -i;

    return LONG2NUM(i);
}

/*
 *  call-seq:
 *     fix.id2name -> string or nil
 *
 *  Returns the name of the object whose symbol id is <i>fix</i>. If
 *  there is no symbol in the symbol table with this value, returns
 *  <code>nil</code>. <code>id2name</code> has nothing to do with the
 *  <code>Object.id</code> method. See also <code>Fixnum#to_sym</code>,
 *  <code>String#intern</code>, and class <code>Symbol</code>.
 *
 *     symbol = :@inst_var    #=> :@inst_var
 *     id     = symbol.to_i   #=> 9818
 *     id.id2name             #=> "@inst_var"
 */

static VALUE
fix_id2name(fix)
    VALUE fix;
{
    const char *name = rb_id2name(FIX2UINT(fix));
    if (name) return rb_str_new2(name);
    return Qnil;
}


/*
 *  call-seq:
 *     fix.to_sym -> aSymbol
 *
 *  Returns the symbol whose integer value is <i>fix</i>. See also
 *  <code>Fixnum#id2name</code>.
 *
 *     fred = :fred.to_i
 *     fred.id2name   #=> "fred"
 *     fred.to_sym    #=> :fred
 */

static VALUE
fix_to_sym(fix)
    VALUE fix;
{
    ID id = FIX2UINT(fix);

    if (rb_id2name(id)) {
	return ID2SYM(id);
    }
    return Qnil;
}


/*
 *  call-seq:
 *     fix.size -> fixnum
 *
 *  Returns the number of <em>bytes</em> in the machine representation
 *  of a <code>Fixnum</code>.
 *
 *     1.size            #=> 4
 *     -1.size           #=> 4
 *     2147483647.size   #=> 4
 */

static VALUE
fix_size(fix)
    VALUE fix;
{
    return INT2FIX(sizeof(long));
}

/*
 *  call-seq:
 *     int.upto(limit) {|i| block }     => int
 *
 *  Iterates <em>block</em>, passing in integer values from <i>int</i>
 *  up to and including <i>limit</i>.
 *
 *     5.upto(10) { |i| print i, " " }
 *
 *  <em>produces:</em>
 *
 *     5 6 7 8 9 10
 */

static VALUE
int_upto(from, to)
    VALUE from, to;
{
    RETURN_ENUMERATOR(from, 1, &to);

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
 *  call-seq:
 *     int.downto(limit) {|i| block }     => int
 *
 *  Iterates <em>block</em>, passing decreasing values from <i>int</i>
 *  down to and including <i>limit</i>.
 *
 *     5.downto(1) { |n| print n, ".. " }
 *     print "  Liftoff!\n"
 *
 *  <em>produces:</em>
 *
 *     5.. 4.. 3.. 2.. 1..   Liftoff!
 */

static VALUE
int_downto(from, to)
    VALUE from, to;
{
    RETURN_ENUMERATOR(from, 1, &to);

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
 *  call-seq:
 *     int.times {|i| block }     => int
 *
 *  Iterates block <i>int</i> times, passing in values from zero to
 *  <i>int</i> - 1.
 *
 *     5.times do |i|
 *       print i, " "
 *     end
 *
 *  <em>produces:</em>
 *
 *     0 1 2 3 4
 */

static VALUE
int_dotimes(num)
    VALUE num;
{
    RETURN_ENUMERATOR(num, 0, 0);

    if (FIXNUM_P(num)) {
	long i, end;

	end = FIX2LONG(num);
	for (i=0; i<end; i++) {
	    rb_yield(LONG2FIX(i));
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
 *  call-seq:
 *     fix.zero?    => true or false
 *
 *  Returns <code>true</code> if <i>fix</i> is zero.
 *
 */

static VALUE
fix_zero_p(num)
    VALUE num;
{
    if (FIX2LONG(num) == 0) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     fix.odd? -> true or false
 *
 *  Returns <code>true</code> if <i>fix</i> is an odd number.
 */

static VALUE
fix_odd_p(num)
    VALUE num;
{
    if (num & 2) {
        return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     fix.even? -> true or false
 *
 *  Returns <code>true</code> if <i>fix</i> is an even number.
 */

static VALUE
fix_even_p(num)
    VALUE num;
{
    if (num & 2) {
        return Qfalse;
    }
    return Qtrue;
}

void
Init_Numeric()
{
#if defined(__FreeBSD__) && __FreeBSD__ < 4
    /* allow divide by zero -- Inf */
    fpsetmask(fpgetmask() & ~(FP_X_DZ|FP_X_INV|FP_X_OFL));
#elif defined(_UNICOSMP)
    /* Turn off floating point exceptions for divide by zero, etc. */
    _set_Creg(0, 0);
#elif defined(__BORLANDC__)
    /* Turn off floating point exceptions for overflow, etc. */
    _control87(MCW_EM, MCW_EM);
    _control87(_control87(0,0),0x1FFF);
#endif
    id_coerce = rb_intern("coerce");
    id_to_i = rb_intern("to_i");
    id_eq = rb_intern("==");

    rb_eZeroDivError = rb_define_class("ZeroDivisionError", rb_eStandardError);
    rb_eFloatDomainError = rb_define_class("FloatDomainError", rb_eRangeError);
    rb_cNumeric = rb_define_class("Numeric", rb_cObject);

    rb_define_method(rb_cNumeric, "singleton_method_added", num_sadded, 1);
    rb_include_module(rb_cNumeric, rb_mComparable);
    rb_define_method(rb_cNumeric, "initialize_copy", num_init_copy, 1);
    rb_define_method(rb_cNumeric, "coerce", num_coerce, 1);

    rb_define_method(rb_cNumeric, "+@", num_uplus, 0);
    rb_define_method(rb_cNumeric, "-@", num_uminus, 0);
    rb_define_method(rb_cNumeric, "<=>", num_cmp, 1);
    rb_define_method(rb_cNumeric, "eql?", num_eql, 1);
    rb_define_method(rb_cNumeric, "quo", num_quo, 1);
    rb_define_method(rb_cNumeric, "fdiv", num_quo, 1);
    rb_define_method(rb_cNumeric, "div", num_div, 1);
    rb_define_method(rb_cNumeric, "divmod", num_divmod, 1);
    rb_define_method(rb_cNumeric, "modulo", num_modulo, 1);
    rb_define_method(rb_cNumeric, "remainder", num_remainder, 1);
    rb_define_method(rb_cNumeric, "abs", num_abs, 0);
    rb_define_method(rb_cNumeric, "to_int", num_to_int, 0);

    rb_define_method(rb_cNumeric, "integer?", num_int_p, 0);
    rb_define_method(rb_cNumeric, "zero?", num_zero_p, 0);
    rb_define_method(rb_cNumeric, "nonzero?", num_nonzero_p, 0);

    rb_define_method(rb_cNumeric, "floor", num_floor, 0);
    rb_define_method(rb_cNumeric, "ceil", num_ceil, 0);
    rb_define_method(rb_cNumeric, "round", num_round, 0);
    rb_define_method(rb_cNumeric, "truncate", num_truncate, 0);
    rb_define_method(rb_cNumeric, "step", num_step, -1);

    rb_cInteger = rb_define_class("Integer", rb_cNumeric);
    rb_undef_alloc_func(rb_cInteger);
    rb_undef_method(CLASS_OF(rb_cInteger), "new");

    rb_define_method(rb_cInteger, "integer?", int_int_p, 0);
    rb_define_method(rb_cInteger, "odd?", int_odd_p, 0);
    rb_define_method(rb_cInteger, "even?", int_even_p, 0);
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "times", int_dotimes, 0);
    rb_include_module(rb_cInteger, rb_mPrecision);
    rb_define_method(rb_cInteger, "succ", int_succ, 0);
    rb_define_method(rb_cInteger, "next", int_succ, 0);
    rb_define_method(rb_cInteger, "pred", int_pred, 0);
    rb_define_method(rb_cInteger, "chr", int_chr, 0);
    rb_define_method(rb_cInteger, "ord", int_ord, 0);
    rb_define_method(rb_cInteger, "to_i", int_to_i, 0);
    rb_define_method(rb_cInteger, "to_int", int_to_i, 0);
    rb_define_method(rb_cInteger, "floor", int_to_i, 0);
    rb_define_method(rb_cInteger, "ceil", int_to_i, 0);
    rb_define_method(rb_cInteger, "round", int_to_i, 0);
    rb_define_method(rb_cInteger, "truncate", int_to_i, 0);

    rb_cFixnum = rb_define_class("Fixnum", rb_cInteger);
    rb_include_module(rb_cFixnum, rb_mPrecision);
    rb_define_singleton_method(rb_cFixnum, "induced_from", rb_fix_induced_from, 1);
    rb_define_singleton_method(rb_cInteger, "induced_from", rb_int_induced_from, 1);

    rb_define_method(rb_cFixnum, "to_s", fix_to_s, -1);

    rb_define_method(rb_cFixnum, "id2name", fix_id2name, 0);
    rb_define_method(rb_cFixnum, "to_sym", fix_to_sym, 0);

    rb_define_method(rb_cFixnum, "-@", fix_uminus, 0);
    rb_define_method(rb_cFixnum, "+", fix_plus, 1);
    rb_define_method(rb_cFixnum, "-", fix_minus, 1);
    rb_define_method(rb_cFixnum, "*", fix_mul, 1);
    rb_define_method(rb_cFixnum, "/", fix_div, 1);
    rb_define_method(rb_cFixnum, "div", fix_div, 1);
    rb_define_method(rb_cFixnum, "%", fix_mod, 1);
    rb_define_method(rb_cFixnum, "modulo", fix_mod, 1);
    rb_define_method(rb_cFixnum, "divmod", fix_divmod, 1);
    rb_define_method(rb_cFixnum, "quo", fix_quo, 1);
    rb_define_method(rb_cFixnum, "fdiv", fix_quo, 1);
    rb_define_method(rb_cFixnum, "**", fix_pow, 1);

    rb_define_method(rb_cFixnum, "abs", fix_abs, 0);

    rb_define_method(rb_cFixnum, "==", fix_equal, 1);
    rb_define_method(rb_cFixnum, "<=>", fix_cmp, 1);
    rb_define_method(rb_cFixnum, ">",  fix_gt, 1);
    rb_define_method(rb_cFixnum, ">=", fix_ge, 1);
    rb_define_method(rb_cFixnum, "<",  fix_lt, 1);
    rb_define_method(rb_cFixnum, "<=", fix_le, 1);

    rb_define_method(rb_cFixnum, "~", fix_rev, 0);
    rb_define_method(rb_cFixnum, "&", fix_and, 1);
    rb_define_method(rb_cFixnum, "|", fix_or,  1);
    rb_define_method(rb_cFixnum, "^", fix_xor, 1);
    rb_define_method(rb_cFixnum, "[]", fix_aref, 1);

    rb_define_method(rb_cFixnum, "<<", rb_fix_lshift, 1);
    rb_define_method(rb_cFixnum, ">>", rb_fix_rshift, 1);

    rb_define_method(rb_cFixnum, "to_f", fix_to_f, 0);
    rb_define_method(rb_cFixnum, "size", fix_size, 0);
    rb_define_method(rb_cFixnum, "zero?", fix_zero_p, 0);
    rb_define_method(rb_cFixnum, "odd?", fix_odd_p, 0);
    rb_define_method(rb_cFixnum, "even?", fix_even_p, 0);

    rb_cFloat  = rb_define_class("Float", rb_cNumeric);

    rb_undef_alloc_func(rb_cFloat);
    rb_undef_method(CLASS_OF(rb_cFloat), "new");

    rb_define_singleton_method(rb_cFloat, "induced_from", rb_flo_induced_from, 1);
    rb_include_module(rb_cFloat, rb_mPrecision);

    rb_define_const(rb_cFloat, "ROUNDS", INT2FIX(FLT_ROUNDS));
    rb_define_const(rb_cFloat, "RADIX", INT2FIX(FLT_RADIX));
    rb_define_const(rb_cFloat, "MANT_DIG", INT2FIX(DBL_MANT_DIG));
    rb_define_const(rb_cFloat, "DIG", INT2FIX(DBL_DIG));
    rb_define_const(rb_cFloat, "MIN_EXP", INT2FIX(DBL_MIN_EXP));
    rb_define_const(rb_cFloat, "MAX_EXP", INT2FIX(DBL_MAX_EXP));
    rb_define_const(rb_cFloat, "MIN_10_EXP", INT2FIX(DBL_MIN_10_EXP));
    rb_define_const(rb_cFloat, "MAX_10_EXP", INT2FIX(DBL_MAX_10_EXP));
    rb_define_const(rb_cFloat, "MIN", rb_float_new(DBL_MIN));
    rb_define_const(rb_cFloat, "MAX", rb_float_new(DBL_MAX));
    rb_define_const(rb_cFloat, "EPSILON", rb_float_new(DBL_EPSILON));

    rb_define_method(rb_cFloat, "to_s", flo_to_s, 0);
    rb_define_method(rb_cFloat, "coerce", flo_coerce, 1);
    rb_define_method(rb_cFloat, "-@", flo_uminus, 0);
    rb_define_method(rb_cFloat, "+", flo_plus, 1);
    rb_define_method(rb_cFloat, "-", flo_minus, 1);
    rb_define_method(rb_cFloat, "*", flo_mul, 1);
    rb_define_method(rb_cFloat, "/", flo_div, 1);
    rb_define_method(rb_cFloat, "%", flo_mod, 1);
    rb_define_method(rb_cFloat, "modulo", flo_mod, 1);
    rb_define_method(rb_cFloat, "divmod", flo_divmod, 1);
    rb_define_method(rb_cFloat, "**", flo_pow, 1);
    rb_define_method(rb_cFloat, "==", flo_eq, 1);
    rb_define_method(rb_cFloat, "<=>", flo_cmp, 1);
    rb_define_method(rb_cFloat, ">",  flo_gt, 1);
    rb_define_method(rb_cFloat, ">=", flo_ge, 1);
    rb_define_method(rb_cFloat, "<",  flo_lt, 1);
    rb_define_method(rb_cFloat, "<=", flo_le, 1);
    rb_define_method(rb_cFloat, "eql?", flo_eql, 1);
    rb_define_method(rb_cFloat, "hash", flo_hash, 0);
    rb_define_method(rb_cFloat, "to_f", flo_to_f, 0);
    rb_define_method(rb_cFloat, "abs", flo_abs, 0);
    rb_define_method(rb_cFloat, "zero?", flo_zero_p, 0);

    rb_define_method(rb_cFloat, "to_i", flo_truncate, 0);
    rb_define_method(rb_cFloat, "to_int", flo_truncate, 0);
    rb_define_method(rb_cFloat, "floor", flo_floor, 0);
    rb_define_method(rb_cFloat, "ceil", flo_ceil, 0);
    rb_define_method(rb_cFloat, "round", flo_round, 0);
    rb_define_method(rb_cFloat, "truncate", flo_truncate, 0);

    rb_define_method(rb_cFloat, "nan?",      flo_is_nan_p, 0);
    rb_define_method(rb_cFloat, "infinite?", flo_is_infinite_p, 0);
    rb_define_method(rb_cFloat, "finite?",   flo_is_finite_p, 0);
}
