/**********************************************************************

  numeric.c -

  $Author$
  $Date$
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include <math.h>
#include <stdio.h>
#if defined(__FreeBSD__) && __FreeBSD__ < 4
#include <floatingpoint.h>
#endif

static ID coerce;
static ID to_i;

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
    return rb_funcall(x[1], coerce, 1, x[0]);
}

static VALUE
coerce_rescue(x)
    VALUE *x;
{
    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_special_const_p(x[1])?
	     STR2CSTR(rb_inspect(x[1])):
	     rb_class2name(CLASS_OF(x[1])),
	     rb_class2name(CLASS_OF(x[0])));
    return Qnil;		/* dummy */
}

static void
do_coerce(x, y)
    VALUE *x, *y;
{
    VALUE ary;
    VALUE a[2];

    a[0] = *x; a[1] = *y;
    ary = rb_rescue2(coerce_body, (VALUE)a, coerce_rescue, (VALUE)a,
		     rb_eStandardError, rb_eNameError, 0);
    if (TYPE(ary) != T_ARRAY || RARRAY(ary)->len != 2) {
	rb_raise(rb_eTypeError, "coerce must return [x, y]");
    }

    *x = RARRAY(ary)->ptr[0];
    *y = RARRAY(ary)->ptr[1];
}

VALUE
rb_num_coerce_bin(x, y)
    VALUE x, y;
{
    do_coerce(&x, &y);
    return rb_funcall(x, rb_frame_last_func(), 1, y);
}

static VALUE
num_clone(x)
    VALUE x;
{
    /* Numerics are immutable values, which need not to copy */
    return x;
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
    do_coerce(&zero, &num);

    return rb_funcall(zero, '-', 1, num);
}

static VALUE
num_divmod(x, y)
    VALUE x, y;
{
    VALUE div, mod;

    div = rb_funcall(x, '/', 1, y);
    if (TYPE(div) == T_FLOAT) {
	double d = floor(RFLOAT(div)->value);

	if (RFLOAT(div)->value > d) {
	    div = rb_float_new(d);
	}
    }
    mod = rb_funcall(x, '%', 1, y);
    return rb_assoc_new(div, mod);
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

    if ((!RTEST(rb_equal(z, INT2FIX(0)))) &&
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
    if (RTEST(rb_equal(num, INT2FIX(0)))) {
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
    char buf[24];
    char *fmt = "%.10g";
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
    else if (avalue >= 1.0e10) {
	d1 = avalue;
	while (d1 > 10.0) d1 /= 10.0;
	d1 = modf(d1, &d2);
	if (d1 == 0) fmt = "%.1e";
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
num_equal(x, y)
    VALUE x, y;
{
    return rb_equal(y, x);
}

static VALUE
flo_eq(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	if (RFLOAT(x)->value == FIX2LONG(y)) return Qtrue;
	return Qfalse;
      case T_BIGNUM:
	return (RFLOAT(x)->value == rb_big2dbl(y))?Qtrue:Qfalse;
      case T_FLOAT:
	return (RFLOAT(x)->value == RFLOAT(y)->value)?Qtrue:Qfalse;
      default:
	return num_equal(x, y);
    }
}

static VALUE
flo_hash(num)
    VALUE num;
{
    double d;
    char *c;
    int i, hash;

    d = RFLOAT(num)->value;
    c = (char*)&d;
    for (hash=0, i=0; i<sizeof(double);i++) {
	hash += c[i] * 971;
    }
    if (hash < 0) hash = -hash;
    return INT2FIX(hash);
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
	return rb_num_coerce_bin(x, y);
    }
    if (a == b) return INT2FIX(0);
    if (a > b) return INT2FIX(1);
    if (a < b) return INT2FIX(-1);
    rb_raise(rb_eFloatDomainError, "comparing NaN");
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
	return rb_num_coerce_bin(x, y);
    }
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
	return rb_num_coerce_bin(x, y);
    }
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
	return rb_num_coerce_bin(x, y);
    }
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
	return rb_num_coerce_bin(x, y);
    }
    return (a <= b)?Qtrue:Qfalse;
}

static VALUE
flo_eql(x, y)
    VALUE x, y;
{
    if (TYPE(y) == T_FLOAT) {
	if (RFLOAT(x)->value == RFLOAT(y)->value) return Qtrue;
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

static VALUE flo_is_nan_p(num)
     VALUE num;
{     

  double value = RFLOAT(num)->value;

  return isnan(value) ? Qtrue : Qfalse;
}

static VALUE flo_is_infinite_p(num)
     VALUE num;
{     
  double value = RFLOAT(num)->value;

  if (isinf(value)) {
    return INT2FIX( value < 0 ? -1 : 1 );
  }

  return Qnil;
}

static VALUE flo_is_finite_p(num)
     VALUE num;
{     
  double value = RFLOAT(num)->value;

  if (isinf(value) || isnan(value))
    return Qfalse;
  
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
    return INT2FIX(val);
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
    return INT2FIX(val);
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
    return INT2FIX(val);
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
    return INT2FIX(val);
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

long
rb_num2long(val)
    VALUE val;
{
    if (NIL_P(val)) {
	rb_raise(rb_eTypeError, "no implicit conversion from nil");
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

      case T_STRING:
	rb_raise(rb_eTypeError, "no implicit conversion from string");
	return Qnil;		/* not reached */

      case T_TRUE:
      case T_FALSE:
	rb_raise(rb_eTypeError, "no implicit conversion from boolean");
	return Qnil;		/* not reached */

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
int
rb_num2int(val)
    VALUE val;
{
    long num = rb_num2long(val);

    if (num < INT_MIN || INT_MAX < num) {
	rb_raise(rb_eRangeError, "integer %ld too big to convert to `int'", num);
    }
    return (int)num;
}

int
rb_fix2int(val)
    VALUE val;
{
    long num = FIXNUM_P(val)?FIX2LONG(val):rb_num2long(val);

    if (num < INT_MIN || INT_MAX < num) {
	rb_raise(rb_eRangeError, "integer %ld too big to convert to `int'", num);
    }
    return (int)num;
}
#else
int
rb_num2int(val)
    VALUE val;
{
    return rb_num2long(val);
}

int
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
    return INT2FIX(v);
}

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
       return rb_funcall(x, rb_intern("to_i"), 0);
    default:
       rb_raise(rb_eTypeError, "failed to convert %s into Integer",
                rb_class2name(CLASS_OF(x)));
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
                rb_class2name(CLASS_OF(x)));
    }
}

static VALUE
fix_uminus(num)
    VALUE num;
{
    return rb_int2inum(-FIX2LONG(num));
}

VALUE
rb_fix2str(x, base)
    VALUE x;
    int base;
{
    char fmt[4], buf[22];

    fmt[0] = '%'; fmt[1] = 'l'; fmt[3] = '\0';
    if (base == 10) fmt[2] = 'd';
    else if (base == 16) fmt[2] = 'x';
    else if (base == 8) fmt[2] = 'o';
    else rb_fatal("fixnum cannot treat base %d", base);

    snprintf(buf, 22, fmt, FIX2LONG(x));
    return rb_str_new2(buf);
}

static VALUE
fix_to_s(in)
    VALUE in;
{
    return rb_fix2str(in, 10);
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
	r = INT2FIX(c);

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
	r = INT2FIX(c);

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
	r = INT2FIX(c);

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
fix_div(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long div;

	fixdivmod(FIX2LONG(x), FIX2LONG(y), &div, 0);
	return INT2NUM(div);
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
	return INT2NUM(mod);
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

	return rb_assoc_new(INT2NUM(div), INT2NUM(mod));
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
	return (x == y)?Qtrue:Qfalse;
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
	return rb_num_coerce_bin(x, y);
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
	return rb_num_coerce_bin(x, y);
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
	return rb_num_coerce_bin(x, y);
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
	return rb_num_coerce_bin(x, y);
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
	return rb_num_coerce_bin(x, y);
    }
}

static VALUE
fix_rev(num)
    VALUE num;
{
    long val = FIX2LONG(num);

    val = ~val;
    return rb_int2inum(val);
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
    return rb_int2inum(val);
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
    return rb_int2inum(val);
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
    return rb_int2inum(val);
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
	return fix_rshift(x, INT2FIX(-width));
    if (width > (sizeof(VALUE)*CHAR_BIT-1)
	|| ((unsigned long)val)>>(sizeof(VALUE)*CHAR_BIT-1-width) > 0) {
	return rb_big_lshift(rb_int2big(val), y);
    }
    val = val << width;
    return rb_int2inum(val);
}

static VALUE
fix_rshift(x, y)
    VALUE x, y;
{
    long i, val;

    i = NUM2LONG(y);
    if (i < 0)
	return fix_lshift(x, INT2FIX(-i));
    if (i == 0) return x;
    val = FIX2LONG(x);
    if (i >= sizeof(long)*CHAR_BIT-1) {
	if (val < 0) return INT2FIX(-1);
	return INT2FIX(0);
    }
    val = RSHIFT(val, i);
    return INT2FIX(val);
}

static VALUE
fix_aref(fix, idx)
    VALUE fix, idx;
{
    long val = FIX2LONG(fix);

    if (TYPE(idx) == T_BIGNUM) {
	if (!RBIGNUM(idx)->sign || val >= 0)
	    return INT2FIX(0);
	return INT2FIX(1);
    }
    else {
	int i = NUM2INT(idx);

	if (i < 0 || sizeof(VALUE)*CHAR_BIT-1 < i) {
	    if (val < 0) return INT2FIX(1);
	    return INT2FIX(0);
	}
	if (val & (1L<<i))
	    return INT2FIX(1);
	return INT2FIX(0);
    }
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
fix_type(fix)
    VALUE fix;
{
    return rb_cFixnum;
}

static VALUE
fix_abs(fix)
    VALUE fix;
{
    long i = FIX2LONG(fix);

    if (i < 0) i = -i;

    return rb_int2inum(i);
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
fix_succ(fix)
    VALUE fix;
{
    long i = FIX2LONG(fix) + 1;

    return rb_int2inum(i);
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
    VALUE i = from;

    for (;;) {
	if (RTEST(rb_funcall(i, '>', 1, to))) break;
	rb_yield(i);
	i = rb_funcall(i, '+', 1, INT2FIX(1));
    }
    return from;
}

static VALUE
int_downto(from, to)
    VALUE from, to;
{
    VALUE i = from;

    for (;;) {
	if (RTEST(rb_funcall(i, '<', 1, to))) break;
	rb_yield(i);
	i = rb_funcall(i, '-', 1, INT2FIX(1));
    }
    return from;
}

static VALUE
int_step(from, to, step)
    VALUE from, to, step;
{
    VALUE i = from;
    ID cmp;

    if (rb_equal(step, INT2FIX(0))) {
	rb_raise(rb_eArgError, "step cannot be 0");
    }

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
    return from;
}

static VALUE
int_dotimes(num)
    VALUE num;
{
    VALUE i = INT2FIX(0);

    for (;;) {
	if (!RTEST(rb_funcall(i, '<', 1, num))) break;
	rb_yield(i);
	i = rb_funcall(i, '+', 1, INT2FIX(1));
    }
    return num;
}

static VALUE
fix_upto(from, to)
    VALUE from, to;
{
    long i, end;

    if (!FIXNUM_P(to)) return int_upto(from, to);
    end = FIX2LONG(to);
    for (i = FIX2LONG(from); i <= end; i++) {
	rb_yield(INT2FIX(i));
    }

    return from;
}

VALUE
rb_fix_upto(from, to)
    VALUE from, to;
{
    return fix_upto(from, to);
}

static VALUE
fix_downto(from, to)
    VALUE from, to;
{
    long i, end;

    if (!FIXNUM_P(to)) return int_downto(from, to);
    end = FIX2LONG(to);
    for (i=FIX2LONG(from); i >= end; i--) {
	rb_yield(INT2FIX(i));
    }

    return from;
}

static VALUE
fix_step(from, to, step)
    VALUE from, to, step;
{
    long i, end, diff;

    if (!FIXNUM_P(to) || !FIXNUM_P(step))
	return int_step(from, to, step);

    i = FIX2LONG(from);
    end = FIX2LONG(to);
    diff = FIX2LONG(step);

    if (diff == 0) {
	rb_raise(rb_eArgError, "step cannot be 0");
    }
    if (diff > 0) {
	while (i <= end) {
	    rb_yield(INT2FIX(i));
	    i += diff;
	}
    }
    else {
	while (i >= end) {
	    rb_yield(INT2FIX(i));
	    i += diff;
	}
    }
    return from;
}

static VALUE
fix_dotimes(num)
    VALUE num;
{
    long i, end;

    end = FIX2LONG(num);
    for (i=0; i<end; i++) {
	rb_yield(INT2FIX(i));
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
    coerce = rb_intern("coerce");
    to_i = rb_intern("to_i");

    rb_eZeroDivError = rb_define_class("ZeroDivisionError", rb_eStandardError);
    rb_eFloatDomainError = rb_define_class("FloatDomainError", rb_eRangeError);
    rb_cNumeric = rb_define_class("Numeric", rb_cObject);

    rb_include_module(rb_cNumeric, rb_mComparable);
    rb_define_method(rb_cNumeric, "coerce", num_coerce, 1);
    rb_define_method(rb_cNumeric, "clone", num_clone, 0);

    rb_define_method(rb_cNumeric, "+@", num_uplus, 0);
    rb_define_method(rb_cNumeric, "-@", num_uminus, 0);
    rb_define_method(rb_cNumeric, "===", num_equal, 1);
    rb_define_method(rb_cNumeric, "eql?", num_eql, 1);
    rb_define_method(rb_cNumeric, "divmod", num_divmod, 1);
    rb_define_method(rb_cNumeric, "modulo", num_modulo, 1);
    rb_define_method(rb_cNumeric, "remainder", num_remainder, 1);
    rb_define_method(rb_cNumeric, "abs", num_abs, 0);

    rb_define_method(rb_cNumeric, "integer?", num_int_p, 0);
    rb_define_method(rb_cNumeric, "zero?", num_zero_p, 0);
    rb_define_method(rb_cNumeric, "nonzero?", num_nonzero_p, 0);

    rb_define_method(rb_cNumeric, "floor", num_floor, 0);
    rb_define_method(rb_cNumeric, "ceil", num_ceil, 0);
    rb_define_method(rb_cNumeric, "round", num_round, 0);
    rb_define_method(rb_cNumeric, "truncate", num_truncate, 0);

    rb_cInteger = rb_define_class("Integer", rb_cNumeric);
    rb_undef_method(CLASS_OF(rb_cInteger), "new");

    rb_define_method(rb_cInteger, "integer?", int_int_p, 0);
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "step", int_step, 2);
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

    rb_define_method(rb_cFixnum, "to_s", fix_to_s, 0);
    rb_define_method(rb_cFixnum, "type", fix_type, 0);

    rb_define_method(rb_cFixnum, "id2name", fix_id2name, 0);

    rb_define_method(rb_cFixnum, "-@", fix_uminus, 0);
    rb_define_method(rb_cFixnum, "+", fix_plus, 1);
    rb_define_method(rb_cFixnum, "-", fix_minus, 1);
    rb_define_method(rb_cFixnum, "*", fix_mul, 1);
    rb_define_method(rb_cFixnum, "/", fix_div, 1);
    rb_define_method(rb_cFixnum, "%", fix_mod, 1);
    rb_define_method(rb_cFixnum, "modulo", fix_mod, 1);
    rb_define_method(rb_cFixnum, "divmod", fix_divmod, 1);
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

    rb_define_method(rb_cFixnum, "succ", fix_succ, 0);
    rb_define_method(rb_cFixnum, "next", fix_succ, 0);
    rb_define_method(rb_cFixnum, "size", fix_size, 0);

    rb_define_method(rb_cFixnum, "upto", fix_upto, 1);
    rb_define_method(rb_cFixnum, "downto", fix_downto, 1);
    rb_define_method(rb_cFixnum, "step", fix_step, 2);
    rb_define_method(rb_cFixnum, "times", fix_dotimes, 0);
    rb_define_method(rb_cFixnum, "zero?", fix_zero_p, 0);

    rb_cFloat  = rb_define_class("Float", rb_cNumeric);

    rb_undef_method(CLASS_OF(rb_cFloat), "new");

    rb_define_singleton_method(rb_cFloat, "induced_from", rb_flo_induced_from, 1);
    rb_include_module(rb_cFloat, rb_mPrecision);

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
    rb_define_method(rb_cFloat, "floor", flo_floor, 0);
    rb_define_method(rb_cFloat, "ceil", flo_ceil, 0);
    rb_define_method(rb_cFloat, "round", flo_round, 0);
    rb_define_method(rb_cFloat, "truncate", flo_truncate, 0);

    rb_define_method(rb_cFloat, "nan?",      flo_is_nan_p, 0);
    rb_define_method(rb_cFloat, "infinite?", flo_is_infinite_p, 0);
    rb_define_method(rb_cFloat, "finite?",   flo_is_finite_p, 0);
}
