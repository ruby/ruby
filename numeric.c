/************************************************

  numeric.c -

  $Author$
  $Date$
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <math.h>
#include <stdio.h>

static ID coerce;
static ID to_i;

VALUE rb_cNumeric;
VALUE rb_cFloat;
VALUE rb_cInteger;
VALUE rb_cFixnum;

VALUE rb_eZeroDiv;

ID rb_frame_last_func();
VALUE rb_float_new();
double rb_big2dbl();

void
rb_num_zerodiv()
{
    rb_raise(rb_eZeroDiv, "divided by 0");
}

static VALUE
num_coerce(x, y)
    VALUE x, y;
{
    if (CLASS_OF(x) == CLASS_OF(y))
	return rb_assoc_new(x, y);
    return rb_assoc_new(rb_Float(x), rb_Float(y));
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
}

static void
do_coerce(x, y)
    VALUE *x, *y;
{
    VALUE ary;
    VALUE a[2];

    a[0] = *x; a[1] = *y;
    ary = rb_rescue(coerce_body, (VALUE)a, coerce_rescue, (VALUE)a);
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
	return Qfalse;
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
    char *s;

    sprintf(buf, "%-.10g", RFLOAT(flt)->value);
    if (s = strchr(buf, ' ')) *s = '\0';
    s = buf; if (s[0] == '-') s++;
    if (strchr(s, '.') == 0 &&
	strcmp(s, "Inf") != 0 &&
	strcmp(s, "NaN") != 0) {
	int len = strlen(buf);
	char *ind = strchr(buf, 'e');

	if (ind) {
	    memmove(ind+2, ind, len-(ind-buf)+1);
	    ind[0] = '.';
	    ind[1] = '0';
	} else {
	    strcat(buf, ".0");
	}
    }

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

static VALUE
flo_modulo(x, y, modulo)
    VALUE x, y;
    int modulo;
{
    double value, result;

    switch (TYPE(y)) {
      case T_FIXNUM:
	value = (double)FIX2LONG(y);
	break;
      case T_BIGNUM:
	value = rb_big2dbl(y);
	break;
      case T_FLOAT:
	value = RFLOAT(y)->value;
	break;
      default:
	return rb_num_coerce_bin(x, y);
    }

#ifdef HAVE_FMOD
    result = fmod(RFLOAT(x)->value, value);
#else
    {
	double value1 = RFLOAT(x)->value;
	double value2;

	modf(value1/value, &value2);
	result = value1 - value2 * value;
    }
#endif
    if (modulo &&
	(RFLOAT(x)->value < 0.0) != (result < 0.0) && result != 0.0) {
	result += value;
    }
    return rb_float_new(result);
}

static VALUE
flo_mod(x, y)
    VALUE x, y;
{
    return flo_modulo(x,y,1);
}

static VALUE
flo_remainder(x, y)
    VALUE x, y;
{
    return flo_modulo(x,y,0);
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
    return INT2FIX(-1);
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
flo_to_i(num)
    VALUE num;
{
    double f = RFLOAT(num)->value;
    long val;

    if (!FIXABLE(f)) {
	return rb_dbl2big(f);
    }
    val = f;
    return INT2FIX(val);
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
to_integer(val)
    VALUE val;
{
    return rb_funcall(val, to_i, 0);
}

static VALUE
fail_to_integer(val)
    VALUE val;
{
    rb_raise(rb_eTypeError, "failed to convert %s into Integer",
	     rb_class2name(CLASS_OF(val)));
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
	    rb_raise(rb_eTypeError, "float %s out of rang of integer", buf);
	}

      case T_BIGNUM:
	return rb_big2long(val);

      case T_STRING:
	rb_raise(rb_eTypeError, "no implicit conversion from string");
	return Qnil;		/* not reached */

      default:
	val = rb_rescue(to_integer, val, fail_to_integer, val);
	if (!rb_obj_is_kind_of(val, rb_cInteger)) {
	    rb_raise(rb_eTypeError, "`to_i' need to return integer");
	}
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
	rb_raise(rb_eArgError, "integer %d too big to convert to `int'", num);
    }
    return (int)num;
}

int
rb_fix2int(val)
    VALUE val;
{
    long num = FIXNUM_P(val)?FIX2LONG(val):rb_num2long(val);

    if (num < INT_MIN || INT_MAX < num) {
	rb_raise(rb_eArgError, "integer %d too big to convert to `int'", num);
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
	rb_raise(rb_eTypeError, "integer %d out of range of fixnum", v);
    return INT2FIX(v);
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
	rb_raise(rb_eTypeError, "%d out of char range", i);
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
    return rb_funcall(x, rb_intern("to_i"), 0);
}

static VALUE
rb_flo_induced_from(klass, x)
    VALUE klass, x;
{
    return rb_funcall(x, rb_intern("to_f"), 0);
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

static VALUE
fix_div(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long i;

	i = FIX2LONG(y);
	if (i == 0) rb_num_zerodiv();
	i = FIX2LONG(x)/i;
	return INT2FIX(i);
    }
    return rb_num_coerce_bin(x, y);
}

static VALUE
fix_modulo(x, y, modulo)
    VALUE x, y;
{
    long i;

    if (FIXNUM_P(y)) {
	i = FIX2LONG(y);
	if (i == 0) rb_num_zerodiv();
	i = FIX2LONG(x)%i;
	if (modulo &&
	    (FIX2LONG(x) < 0) != (FIX2LONG(y) < 0) &&
	    i != 0) {
	    i += FIX2LONG(y);
	}
	return INT2FIX(i);
    }
    return rb_num_coerce_bin(x, y);
}

static VALUE
fix_mod(x, y)
    VALUE x, y;
{
    return fix_modulo(x, y, 1);
}

static VALUE
fix_remainder(x, y)
    VALUE x, y;
{
    return fix_modulo(x, y, 0);
}

static VALUE
fix_pow(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	long a, b;

	b = FIX2LONG(y);
	if (b == 0) return INT2FIX(1);
	a = FIX2LONG(x);
	if (b > 0) {
	    return rb_big_pow(rb_int2big(a), y);
	}
	return rb_float_new(pow((double)a, (double)b));
    }
    else if (NIL_P(y)) {
	return INT2FIX(1);
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
    unsigned long val = FIX2ULONG(num);

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

static VALUE
fix_lshift(x, y)
    VALUE x, y;
{
    long val;
    int width;

    val = NUM2LONG(x);
    width = NUM2INT(y);
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
    if (i < sizeof(long) * 8) {
	val = RSHIFT(FIX2LONG(x), i);
	return INT2FIX(val);
    }

    return INT2FIX(0);
}

static VALUE
fix_aref(fix, idx)
    VALUE fix, idx;
{
    unsigned long val = FIX2LONG(fix);
    int i = FIX2LONG(idx);

    if (i < 0 || sizeof(VALUE)*CHAR_BIT-1 < i)
	return INT2FIX(0);
    if (val & (1<<i))
	return INT2FIX(1);
    return INT2FIX(0);
}

static VALUE
fix_to_i(num)
    VALUE num;
{
    return num;
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

    if (NUM2INT(step) == 0) {
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
    coerce = rb_intern("coerce");
    to_i = rb_intern("to_i");

    rb_eZeroDiv = rb_define_class("ZeroDivisionError", rb_eStandardError);
    rb_cNumeric = rb_define_class("Numeric", rb_cObject);

    rb_include_module(rb_cNumeric, rb_mComparable);
    rb_define_method(rb_cNumeric, "coerce", num_coerce, 1);
    rb_define_method(rb_cNumeric, "clone", num_clone, 0);

    rb_define_method(rb_cNumeric, "+@", num_uplus, 0);
    rb_define_method(rb_cNumeric, "-@", num_uminus, 0);
    rb_define_method(rb_cNumeric, "eql?", num_eql, 1);
    rb_define_method(rb_cNumeric, "divmod", num_divmod, 1);
    rb_define_method(rb_cNumeric, "abs", num_abs, 0);

    rb_define_method(rb_cNumeric, "integer?", num_int_p, 0);
    rb_define_method(rb_cNumeric, "zero?", num_zero_p, 0);
    rb_define_method(rb_cNumeric, "nonzero?", num_nonzero_p, 0);

    rb_cInteger = rb_define_class("Integer", rb_cNumeric);
    rb_define_method(rb_cInteger, "integer?", int_int_p, 0);
    rb_define_method(rb_cInteger, "upto", int_upto, 1);
    rb_define_method(rb_cInteger, "downto", int_downto, 1);
    rb_define_method(rb_cInteger, "step", int_step, 2);
    rb_define_method(rb_cInteger, "times", int_dotimes, 0);
    rb_include_module(rb_cInteger, rb_mPrecision);
    rb_define_method(rb_cInteger, "succ", int_succ, 0);
    rb_define_method(rb_cInteger, "next", int_succ, 0);
    rb_define_method(rb_cInteger, "chr", int_chr, 0);

    rb_cFixnum = rb_define_class("Fixnum", rb_cInteger);
    rb_include_module(rb_cFixnum, rb_mPrecision);
    rb_define_singleton_method(rb_cFixnum, "induced_from", rb_fix_induced_from, 1);
    rb_define_singleton_method(rb_cInteger, "induced_from", rb_int_induced_from, 1);

    rb_undef_method(CLASS_OF(rb_cFixnum), "new");

    rb_define_method(rb_cFixnum, "to_s", fix_to_s, 0);
    rb_define_method(rb_cFixnum, "type", fix_type, 0);

    rb_define_method(rb_cFixnum, "id2name", fix_id2name, 0);

    rb_define_method(rb_cFixnum, "-@", fix_uminus, 0);
    rb_define_method(rb_cFixnum, "+", fix_plus, 1);
    rb_define_method(rb_cFixnum, "-", fix_minus, 1);
    rb_define_method(rb_cFixnum, "*", fix_mul, 1);
    rb_define_method(rb_cFixnum, "/", fix_div, 1);
    rb_define_method(rb_cFixnum, "%", fix_mod, 1);
    rb_define_method(rb_cFixnum, "remainder", fix_remainder, 1);
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

    rb_define_method(rb_cFixnum, "to_i", fix_to_i, 0);
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
    rb_define_method(rb_cFloat, "remainder", flo_remainder, 1);
    rb_define_method(rb_cFloat, "**", flo_pow, 1);
    rb_define_method(rb_cFloat, "==", flo_eq, 1);
    rb_define_method(rb_cFloat, "<=>", flo_cmp, 1);
    rb_define_method(rb_cFloat, ">",  flo_gt, 1);
    rb_define_method(rb_cFloat, ">=", flo_ge, 1);
    rb_define_method(rb_cFloat, "<",  flo_lt, 1);
    rb_define_method(rb_cFloat, "<=", flo_le, 1);
    rb_define_method(rb_cFloat, "eql?", flo_eql, 1);
    rb_define_method(rb_cFloat, "hash", flo_hash, 0);
    rb_define_method(rb_cFloat, "to_i", flo_to_i, 0);
    rb_define_method(rb_cFloat, "to_f", flo_to_f, 0);
    rb_define_method(rb_cFloat, "abs", flo_abs, 0);
    rb_define_method(rb_cFloat, "zero?", flo_zero_p, 0);

    rb_define_method(rb_cFloat, "floor", flo_floor, 0);
    rb_define_method(rb_cFloat, "ceil", flo_ceil, 0);
    rb_define_method(rb_cFloat, "round", flo_round, 0);
}
