/**********************************************************************

  numeric.c -

  $Author$
  $Date$
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "env.h"
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

static VALUE
num_coerce(x, y)
    VALUE x, y;
{
    if (CLASS_OF(x) == CLASS_OF(y))
	return rb_assoc_new(y, x);
    return rb_assoc_new(rb_Float(y), rb_Float(x));
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

static VALUE
num_init_copy(x, y)
    VALUE x, y;
{
    /* Numerics are immutable values, which should not be copied */
    rb_raise(rb_eTypeError, "can't copy %s", rb_obj_classname(x));
    return Qnil;		/* not reached */
}

static VALUE
num_uplus(num)
    VALUE num;
{
    return num;
}

static VALUE
num_uminus(num)
    VALUE num;
{
    VALUE zero;

    zero = INT2FIX(0);
    do_coerce(&zero, &num, Qtrue);

    return rb_funcall(zero, '-', 1, num);
}

static VALUE
num_quo(x, y)
    VALUE x, y;
{
    return rb_funcall(x, '/', 1, y);
}

static VALUE
num_div(x, y)
    VALUE x, y;
{
    return rb_Integer(rb_funcall(x, '/', 1, y));
}

static VALUE
num_divmod(x, y)
    VALUE x, y;
{
    return rb_assoc_new(num_div(x, y), rb_funcall(x, '%', 1, y));
}

static VALUE
num_modulo(x, y)
    VALUE x, y;
{
    return rb_funcall(x, '%', 1, y);
}

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

static VALUE
num_int_p(num)
    VALUE num;
{
    return Qfalse;
}

static VALUE
num_abs(num)
    VALUE num;
{
    if (RTEST(rb_funcall(num, '<', 1, INT2FIX(0)))) {
	return rb_funcall(num, rb_intern("-@"), 0);
    }
    return num;
}

static VALUE
num_zero_p(num)
    VALUE num;
{
    if (rb_equal(num, INT2FIX(0))) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
num_nonzero_p(num)
    VALUE num;
{
    if (RTEST(rb_funcall(num, rb_intern("zero?"), 0, 0))) {
	return Qnil;
    }
    return num;
}

static VALUE
num_to_int(num)
    VALUE num;
{
    return rb_funcall(num, id_to_i, 0, 0);
}

VALUE
rb_float_new(d)
    double d;
{
    NEWOBJ(flt, struct RFloat);
    OBJSETUP(flt, rb_cFloat, T_FLOAT);

    flt->value = d;
    return (VALUE)flt;
}

static VALUE
flo_to_s(flt)
    VALUE flt;
{
    char buf[32];
    char *fmt = "%.15g";
    double value = RFLOAT(flt)->value;
    double avalue, d1, d2;

    if (isinf(value))
	return rb_str_new2(value < 0 ? "-Infinity" : "Infinity");
    else if(isnan(value))
	return rb_str_new2("NaN");
    
    avalue = fabs(value);
    if (avalue == 0.0) {
	fmt = "%.1f";
    }
    else if (avalue < 1.0e-3) {
	d1 = avalue;
	while (d1 < 1.0) d1 *= 10.0;
	d1 = modf(d1, &d2);
	if (d1 == 0) fmt = "%.1e";
    }    
    else if (avalue >= 1.0e15) {
	d1 = avalue;
	while (d1 > 10.0) d1 /= 10.0;
	d1 = modf(d1, &d2);
	if (d1 == 0) fmt = "%.1e";
	else fmt = "%.16e";
    }    
    else if ((d1 = modf(value, &d2)) == 0) {
	fmt = "%.1f";
    }
    sprintf(buf, fmt, value);

    return rb_str_new2(buf);
}

static VALUE
flo_coerce(x, y)
    VALUE x, y;
{
    return rb_assoc_new(rb_Float(y), x);
}

static VALUE
flo_uminus(flt)
    VALUE flt;
{
    return rb_float_new(-RFLOAT(flt)->value);
}

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
    div = (x - mod) / y;
    if (y*mod < 0) {
	mod += y;
	div -= 1.0;
    }
    if (modp) *modp = mod;
    if (divp) *divp = div;
}

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

static VALUE
flo_divmod(x, y)
    VALUE x, y;
{
    double fy, div, mod;

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
    return rb_assoc_new(rb_float_new(div), rb_float_new(mod));
}

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

static VALUE
num_eql(x, y)
    VALUE x, y;
{
    if (TYPE(x) != TYPE(y)) return Qfalse;

    return rb_equal(x, y);
}

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

static VALUE
flo_eq(x, y)
    VALUE x, y;
{
    double a, b;

    switch (TYPE(y)) {
      case T_FIXNUM:
	b = FIX2LONG(y);
	break;
      case T_BIGNUM:
	b = rb_big2dbl(y);
	break;
      case T_FLOAT:
	b = RFLOAT(y)->value;
	break;
      default:
	return num_equal(x, y);
    }
    a = RFLOAT(x)->value;
    if (isnan(a) || isnan(b)) return Qfalse;
    return (a == b)?Qtrue:Qfalse;
}

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
	hash += c[i] * 971;
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
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a) || isnan(b)) return Qfalse;
    return (a > b)?Qtrue:Qfalse;
}

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
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a) || isnan(b)) return Qfalse;
    return (a >= b)?Qtrue:Qfalse;
}

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
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a) || isnan(b)) return Qfalse;
    return (a < b)?Qtrue:Qfalse;
}

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
	break;

      default:
	return rb_num_coerce_relop(x, y);
    }
    if (isnan(a) || isnan(b)) return Qfalse;
    return (a <= b)?Qtrue:Qfalse;
}

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

static VALUE
flo_to_f(num)
    VALUE num;
{
    return num;
}

static VALUE
flo_abs(flt)
    VALUE flt;
{
    double val = fabs(RFLOAT(flt)->value);
    return rb_float_new(val);
}

static VALUE
flo_zero_p(num)
    VALUE num;
{
    if (RFLOAT(num)->value == 0.0) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
flo_is_nan_p(num)
     VALUE num;
{     
    double value = RFLOAT(num)->value;

    return isnan(value) ? Qtrue : Qfalse;
}

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

static VALUE
flo_round(num)
    VALUE num;
{
    double f = RFLOAT(num)->value;
    long val;

    if (f > 0.0) f = floor(f+0.5);
    if (f < 0.0) f = ceil(f-0.5);

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return LONG2FIX(val);
}

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

static VALUE
num_floor(num)
    VALUE num;
{
    return flo_floor(rb_Float(num));
}

static VALUE
num_ceil(num)
    VALUE num;
{
    return flo_ceil(rb_Float(num));
}

static VALUE
num_round(num)
    VALUE num;
{
    return flo_round(rb_Float(num));
}

static VALUE
num_truncate(num)
    VALUE num;
{
    return flo_truncate(rb_Float(num));
}

static VALUE
num_step(argc, argv, from)
    int argc;
    VALUE *argv;
    VALUE from;
{
    VALUE to, step;

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
	    rb_raise(rb_eArgError, "step cannot be 0");
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
    else if (TYPE(from) == T_FLOAT || TYPE(to) == T_FLOAT || TYPE(step) == T_FLOAT) {
	const double epsilon = DBL_EPSILON;
	double beg = NUM2DBL(from);
	double end = NUM2DBL(to);
	double unit = NUM2DBL(step);
	double n = (end - beg)/unit;
	double err = (fabs(beg) + fabs(end) + fabs(end-beg)) / fabs(unit) * epsilon;
	long i;

	if (err>0.5) err=0.5;
	n = floor(n + err) + 1;
	for (i=0; i<n; i++) {
	    rb_yield(rb_float_new(i*unit+beg));
	}
    }
    else {
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
	    if (s = strchr(buf, ' ')) *s = '\0';
	    rb_raise(rb_eRangeError, "float %s out of range of integer", buf);
	}

      case T_BIGNUM:
	return rb_big2long(val);

      case T_SYMBOL:
	rb_warning("treating Symbol as an integer");
	/* fall through */
      default:
	val = rb_to_int(val);
	return NUM2LONG(val);
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
check_uint(num)
    unsigned long num;
{
    if (num > UINT_MAX) {
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

    if (RTEST(rb_funcall(INT2FIX(0), '<', 1, val))) {
	check_uint(num);
    }
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
    if (FIX2LONG(val) > 0) {
	check_uint(num);
    }
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
	    if (s = strchr(buf, ' ')) *s = '\0';
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

static VALUE
int_to_i(num)
    VALUE num;
{
    return num;
}

static VALUE
int_int_p(num)
    VALUE num;
{
    return Qtrue;
}

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

static VALUE
rb_fix_induced_from(klass, x)
    VALUE klass, x;
{
    return rb_num2fix(x);
}

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

    if (base == 2) {
	/* rb_fix2str() does not handle binary */
	return rb_big2str(rb_int2big(FIX2INT(x)), 2);
    }
    return rb_fix2str(x, base);
}

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
	r = LONG2FIX(c);

	if (FIX2LONG(r) != c) {
	    r = rb_big_plus(rb_int2big(a), rb_int2big(b));
	}
	return r;
    }
    if (TYPE(y) == T_FLOAT) {
	return rb_float_new((double)FIX2LONG(x) + RFLOAT(y)->value);
    }
    return rb_num_coerce_bin(x, y);
}

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
	r = LONG2FIX(c);

	if (FIX2LONG(r) != c) {
	    r = rb_big_minus(rb_int2big(a), rb_int2big(b));
	}
	return r;
    }
    if (TYPE(y) == T_FLOAT) {
	return rb_float_new((double)FIX2LONG(x) - RFLOAT(y)->value);
    }
    return rb_num_coerce_bin(x, y);
}

static VALUE
fix_mul(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
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

static VALUE
fix_quo(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return rb_float_new((double)FIX2LONG(x) / (double)FIX2LONG(y));
    }
    return rb_num_coerce_bin(x, y);
}

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
fix_pow(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a, b;

	b = FIX2LONG(y);
	if (b == 0) return INT2FIX(1);
	if (b == 1) return x;
	a = FIX2LONG(x);
	if (b > 0) {
	    return rb_big_pow(rb_int2big(a), y);
	}
	return rb_float_new(pow((double)a, (double)b));
    }
    return rb_num_coerce_bin(x, y);
}

static VALUE
fix_equal(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return (FIX2LONG(x) == FIX2LONG(y))?Qtrue:Qfalse;
    }
    else {
	return num_equal(x, y);
    }
}

static VALUE
fix_cmp(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a = FIX2LONG(x), b = FIX2LONG(y);

	if (a == b) return INT2FIX(0);
	if (a > b) return INT2FIX(1);
	return INT2FIX(-1);
    }
    else {
	return rb_num_coerce_cmp(x, y);
    }
}

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

static VALUE
fix_rev(num)
    VALUE num;
{
    long val = FIX2LONG(num);

    val = ~val;
    return LONG2NUM(val);
}

static VALUE
fix_and(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return rb_big_and(y, x);
    }
    val = FIX2LONG(x) & NUM2LONG(y);
    return LONG2NUM(val);
}

static VALUE
fix_or(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return rb_big_or(y, x);
    }
    val = FIX2LONG(x) | NUM2LONG(y);
    return LONG2NUM(val);
}

static VALUE
fix_xor(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return rb_big_xor(y, x);
    }
    val = FIX2LONG(x) ^ NUM2LONG(y);
    return LONG2NUM(val);
}

static VALUE fix_rshift _((VALUE, VALUE));

static VALUE
fix_lshift(x, y)
    VALUE x, y;
{
    long val, width;

    val = NUM2LONG(x);
    width = NUM2LONG(y);
    if (width < 0)
	return fix_rshift(x, LONG2FIX(-width));
    if (width > (sizeof(VALUE)*CHAR_BIT-1)
	|| ((unsigned long)val)>>(sizeof(VALUE)*CHAR_BIT-1-width) > 0) {
	return rb_big_lshift(rb_int2big(val), y);
    }
    val = val << width;
    return LONG2NUM(val);
}

static VALUE
fix_rshift(x, y)
    VALUE x, y;
{
    long i, val;

    i = NUM2LONG(y);
    if (i < 0)
	return fix_lshift(x, LONG2FIX(-i));
    if (i == 0) return x;
    val = FIX2LONG(x);
    if (i >= sizeof(long)*CHAR_BIT-1) {
	if (val < 0) return INT2FIX(-1);
	return INT2FIX(0);
    }
    val = RSHIFT(val, i);
    return LONG2FIX(val);
}

static VALUE
fix_aref(fix, idx)
    VALUE fix, idx;
{
    long val = FIX2LONG(fix);
    long i;

    if (TYPE(idx) == T_BIGNUM) {
	idx = rb_big_norm(idx);
	if (!FIXNUM_P(idx)) {
	    if (!RBIGNUM(idx)->sign || val >= 0)
		return INT2FIX(0);
	    return INT2FIX(1);
	}
    }
    i = NUM2LONG(idx);

    if (i < 0) return INT2FIX(0);
    if (sizeof(VALUE)*CHAR_BIT-1 < i) {
	if (val < 0) return INT2FIX(1);
	return INT2FIX(0);
    }
    if (val & (1L<<i))
	return INT2FIX(1);
    return INT2FIX(0);
}

static VALUE
fix_to_f(num)
    VALUE num;
{
    double val;

    val = (double)FIX2LONG(num);

    return rb_float_new(val);
}

static VALUE
fix_abs(fix)
    VALUE fix;
{
    long i = FIX2LONG(fix);

    if (i < 0) i = -i;

    return LONG2NUM(i);
}

static VALUE
fix_id2name(fix)
    VALUE fix;
{
    char *name = rb_id2name(FIX2UINT(fix));
    if (name) return rb_str_new2(name);
    return Qnil;
}

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

static VALUE
fix_size(fix)
    VALUE fix;
{
    return INT2FIX(sizeof(long));
}

static VALUE
int_upto(from, to)
    VALUE from, to;
{
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

static VALUE
int_downto(from, to)
    VALUE from, to;
{
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
int_dotimes(num)
    VALUE num;
{
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

static VALUE
fix_zero_p(num)
    VALUE num;
{
    if (FIX2LONG(num) == 0) {
	return Qtrue;
    }
    return Qfalse;
}

void
Init_Numeric()
{
#if defined(__FreeBSD__) && __FreeBSD__ < 4
    /* allow divide by zero -- Inf */
    fpsetmask(fpgetmask() & ~(FP_X_DZ|FP_X_INV|FP_X_OFL));
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
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "times", int_dotimes, 0);
    rb_include_module(rb_cInteger, rb_mPrecision);
    rb_define_method(rb_cInteger, "succ", int_succ, 0);
    rb_define_method(rb_cInteger, "next", int_succ, 0);
    rb_define_method(rb_cInteger, "chr", int_chr, 0);
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

    rb_define_method(rb_cFixnum, "<<", fix_lshift, 1);
    rb_define_method(rb_cFixnum, ">>", fix_rshift, 1);

    rb_define_method(rb_cFixnum, "to_f", fix_to_f, 0);
    rb_define_method(rb_cFixnum, "size", fix_size, 0);
    rb_define_method(rb_cFixnum, "zero?", fix_zero_p, 0);

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
