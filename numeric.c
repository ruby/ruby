/************************************************

  numeric.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:42 $
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <math.h>

static ID coerce;
static ID to_i;

VALUE cNumeric;
VALUE cFloat;
VALUE cInteger;
VALUE cFixnum;

ID rb_frame_last_func();
double big2dbl();

VALUE
float_new(d)
    double d;
{
    NEWOBJ(flt, struct RFloat);
    OBJSETUP(flt, cFloat, T_FLOAT);

    flt->value = d;
    return (VALUE)flt;
}

static VALUE
num_coerce_bin(x, y)
    VALUE x, y;
{
    return rb_funcall(rb_funcall(y, coerce, 1, x),
		      rb_frame_last_func(), 1, y);
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
    return rb_funcall(rb_funcall(num, coerce, 1, INT2FIX(0)), 1, num);
}

static VALUE
num_next(num)
    VALUE num;
{
    num = rb_funcall(num, rb_intern("to_i"), 0);
    return rb_funcall(num, '+', 1, INT2FIX(1));
}

VALUE
num_upto(from, to)
    VALUE from, to;
{
    int i, end;

    end = NUM2INT(to);
    for (i = NUM2INT(from); i <= end; i++) {
	rb_yield(INT2FIX(i));
    }

    return from;
}

static VALUE
num_downto(from, to)
    VALUE from, to;
{
    int i, end;

    end = NUM2INT(to);
    for (i=NUM2INT(from); i >= end; i--) {
	rb_yield(INT2FIX(i));
    }

    return from;
}

static VALUE
num_step(from, to, step)
    VALUE from, to, step;
{
    int i, end, diff;

    end = NUM2INT(to);
    diff = NUM2INT(step);

    if (diff == 0) {
	Fail("step cannot be 0");
    }
    else if (diff > 0) {
	for (i=NUM2INT(from); i <= end; i+=diff) {
	    rb_yield(INT2FIX(i));
	}
    }
    else {
	for (i=NUM2INT(from); i >= end; i+=diff) {
	    rb_yield(INT2FIX(i));
	}
    }
    return from;
}

static VALUE
num_dotimes(num)
    VALUE num;
{
    int i, end;

    end = NUM2INT(num);
    for (i=0; i<end; i++) {
	rb_yield(INT2FIX(i));
    }
    return num;
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
	    div = float_new(d);
	}
    }
    mod = rb_funcall(x, '%', 1, y);
    return assoc_new(div, mod);
}

static VALUE
num_int_p(num)
    VALUE num;
{
    return FALSE;
}

static VALUE
num_chr(num)
    VALUE num;
{
    char c;
    int i = NUM2INT(num);

    if (i < 0 || 0xff < i)
	Fail("%d out of char range", i);
    c = i;
    return str_new(&c, 1);
}

static VALUE
flo_to_s(flt)
    struct RFloat *flt;
{
    char buf[32];

    sprintf(buf, "%g", flt->value);

    return str_new2(buf);
}

static VALUE
flo_coerce(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return float_new((double)FIX2INT(y));
      case T_FLOAT:
	return y;
      case T_BIGNUM:
	return big_to_f(y);
      default:
	Fail("can't coerce %s to Float", rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
    return Qnil;
}

static VALUE
flo_uminus(flt)
    struct RFloat *flt;
{
    return float_new(-flt->value);
}

static VALUE
flo_plus(x, y)
    struct RFloat *x, *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return float_new(x->value + (double)FIX2INT(y));
      case T_BIGNUM:
	return float_new(x->value + big2dbl(y));
      case T_FLOAT:
	return float_new(x->value + y->value);
      case T_STRING:
	return str_plus(obj_as_string(x), y);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
flo_minus(x, y)
    struct RFloat *x, *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return float_new(x->value - (double)FIX2INT(y));
      case T_BIGNUM:
	return float_new(x->value - big2dbl(y));
      case T_FLOAT:
	return float_new(x->value - y->value);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
flo_mul(x, y)
    struct RFloat *x, *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return float_new(x->value * (double)FIX2INT(y));
      case T_BIGNUM:
	return float_new(x->value * big2dbl(y));
      case T_FLOAT:
	return float_new(x->value * y->value);
      case T_STRING:
	return str_times(y, INT2FIX((int)x->value));
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
flo_div(x, y)
    struct RFloat *x, *y;
{
    int f_y;
    double d;

    switch (TYPE(y)) {
      case T_FIXNUM:
	f_y = FIX2INT(y);
	if (f_y == 0) Fail("devided by 0");
	return float_new(x->value / (double)f_y);
      case T_BIGNUM:
	d = big2dbl(y);
	if (d == 0.0) Fail("devided by 0");
	return float_new(x->value + d);
      case T_FLOAT:
	if (y->value == 0.0) Fail("devided by 0");
	return float_new(x->value / y->value);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
flo_mod(x, y)
    struct RFloat *x, *y;
{
    double value;

    switch (TYPE(y)) {
      case T_FIXNUM:
	value = (double)FIX2INT(y);
	break;
      case T_BIGNUM:
	value = big2dbl(y);
	break;
      case T_FLOAT:
	value = y->value;
	break;
      default:
	return num_coerce_bin(x, y);
    }
#ifdef HAVE_FMOD
    {
	value = fmod(x->value, value);
    }
#else
    {
	double value1 = x->value;
	double value2;

	modf(value1/value, &value2);
	value = value1 - value2 * value;
    }
#endif

    return float_new(value);
}

VALUE
flo_pow(x, y)
    struct RFloat *x, *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
        return float_new(pow(x->value, (double)FIX2INT(y)));
      case T_BIGNUM:
	return float_new(pow(x->value, big2dbl(y)));
      case T_FLOAT:
        return float_new(pow(x->value, y->value));
      default:
        return num_coerce_bin(x, y);
    }
}

struct xy {
    VALUE x, y;
};

static VALUE
eq(arg)
    struct xy *arg;
{
    return rb_funcall(arg->y, rb_intern("=="), 1, arg->x);
}

static VALUE
eq_rescue()
{
    return FALSE;
}

static VALUE
num_equal(x, y)
    VALUE x, y;
{
    struct xy arg;
    arg.x = x; arg.y = y;
    return rb_rescue(eq, &arg, eq_rescue, Qnil);
}

static VALUE
flo_eq(x, y)
    struct RFloat *x, *y;
{
    switch (TYPE(y)) {
      case T_NIL:
	return Qnil;
      case T_FIXNUM:
	if (x->value == FIX2INT(y)) return TRUE;
	return FALSE;
      case T_BIGNUM:
	return float_new(x->value == big2dbl(y));
      case T_FLOAT:
	return (x->value == y->value)?TRUE:FALSE;
      default:
	return num_equal(x, y);
    }
}

static VALUE
flo_hash(num)
    struct RFloat *num;
{
    double d;
    char *c;
    int i, hash;

    d = num->value;
    c = (char*)&d;
    for (hash=0, i=0; i<sizeof(double);i++) {
	hash += c[i] * 971;
    }
    if (hash < 0) hash = -hash;
    return INT2FIX(hash);
}

static VALUE
flo_cmp(x, y)
    struct RFloat *x, *y;
{
    double a, b;

    a = x->value;
    switch (TYPE(y)) {
      case T_FIXNUM:
	b = (double)FIX2INT(y);
	break;

      case T_BIGNUM:
	b = big2dbl(y);
	break;

      case T_FLOAT:
	b = y->value;
	break;

      default:
	return num_coerce_bin(x, y);
    }
    if (a == b) return INT2FIX(0);
    if (a > b) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
flo_to_i(num)
    struct RFloat *num;
{
    double f = num->value;
    int val;

    if (!FIXABLE(f)) {
	return dbl2big(f);
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
    struct RFloat *flt;
{
    double val = fabs(flt->value);
    return float_new(val);
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
    Fail("failed to convert %s into integer", rb_class2name(CLASS_OF(val)));
}

int
num2int(val)
    VALUE val;
{
    if (val == Qnil) return 0;

    switch (TYPE(val)) {
      case T_FIXNUM:
	return FIX2INT(val);

      case T_FLOAT:
	if (RFLOAT(val)->value <= (double) LONG_MAX
	    && RFLOAT(val)->value >= (double) LONG_MIN) {
	    return (int)(RFLOAT(val)->value);
	}
	else {
	    Fail("float %g out of rang of integer", RFLOAT(val)->value);
	    return Qnil;	/* not reached */
	}

      case T_BIGNUM:
	return big2int(val);

      default:
	val = rb_rescue(to_integer, val, fail_to_integer, val);
	return NUM2INT(val);
    }
}

VALUE
num2fix(val)
    VALUE val;
{
    int v;

    if (val == Qnil) return INT2FIX(0);
    switch (TYPE(val)) {
      case T_FIXNUM:
	return val;

      case T_FLOAT:
      case T_BIGNUM:
      default:
	v = num2int(val);
	if (!FIXABLE(v))
	    Fail("integer %d out of rang of Fixnum", v);
	return INT2FIX(v);
    }
}

static VALUE
int_int_p(num)
    VALUE num;
{
    return TRUE;
}

static VALUE
fix_uminus(num)
    VALUE num;
{
    return int2inum(-FIX2INT(num));
}

VALUE
fix2str(x, base)
    VALUE x;
    int base;
{
    char fmt[3], buf[12];

    fmt[0] = '%'; fmt[2] = '\0';
    if (base == 10) fmt[1] = 'd';
    else if (base == 16) fmt[1] = 'x';
    else if (base == 8) fmt[1] = 'o';
    else Fail("fixnum cannot treat base %d", base);

    sprintf(buf, fmt, FIX2INT(x));
    return str_new2(buf);
}

VALUE
fix_to_s(in)
    VALUE in;
{
    return fix2str(in, 10);
}

static VALUE
fix_plus(x, y)
    VALUE x;
    struct RFloat *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	{
	    int a, b, c;
	    VALUE r;

	    a = FIX2INT(x);
	    b = FIX2INT(y);
	    c = a + b;
	    r = INT2FIX(c);

	    if (FIX2INT(r) != c) {
		r = big_plus(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) + y->value);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_minus(x, y)
    VALUE x;
    struct RFloat *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	{
	    int a, b, c;
	    VALUE r;

	    a = FIX2INT(x);
	    b = FIX2INT(y);
	    c = a - b;
	    r = INT2FIX(c);

	    if (FIX2INT(r) != c) {
		r = big_minus(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) - y->value);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_mul(x, y)
    VALUE x;
    struct RFloat *y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	{
	    int a = FIX2INT(x), b = FIX2INT(y);
	    int c = a * b;
	    VALUE r = INT2FIX(c);

	    if (FIX2INT(r) != c) {
		r = big_mul(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) * y->value);
      default:
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_div(x, y)
    VALUE x;
    struct RFloat *y;
{
    int i;

    if (TYPE(y) == T_FIXNUM) {
	i = FIX2INT(y);
	if (i == 0) Fail("devided by 0");
	i = FIX2INT(x)/i;
	return INT2FIX(i);
    }
    return num_coerce_bin(x, y);
}

static VALUE
fix_mod(x, y)
    VALUE x, y;
{
    int i;

    if (TYPE(y) == T_FIXNUM) {
	i = FIX2INT(y);
	if (i == 0) Fail("devided by 0");
	i = FIX2INT(x)%i;
	return INT2FIX(i);
    }
    return num_coerce_bin(x, y);
}

static VALUE
fix_pow(x, y)
    VALUE x, y;
{
    extern double pow();

    if (FIXNUM_P(y)) {
	int a, b;

	b = FIX2INT(y);
	if (b == 0) return INT2FIX(1);
	a = FIX2INT(x);
	if (b > 0) {
	    return big_pow(int2big(a), y);
	}
	return float_new(pow((double)a, (double)b));
    }
    else if (NIL_P(y)) {
	return INT2FIX(1);
    }
    return num_coerce_bin(x, y);
}

static VALUE
fix_equal(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return (FIX2INT(x) == FIX2INT(y))?TRUE:FALSE;
    }
    else if (NIL_P(y)) {
	return Qnil;
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
	int a = FIX2INT(x), b = FIX2INT(y);

	if (a == b) return INT2FIX(0);
	if (a > b) return INT2FIX(1);
	return INT2FIX(-1);
    }
    else {
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_gt(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	int a = FIX2INT(x), b = FIX2INT(y);

	if (a > b) return TRUE;
	return FALSE;
    }
    else {
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_ge(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	int a = FIX2INT(x), b = FIX2INT(y);

	if (a >= b) return TRUE;
	return FALSE;
    }
    else {
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_lt(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	int a = FIX2INT(x), b = FIX2INT(y);

	if (a < b) return TRUE;
	return FALSE;
    }
    else {
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_le(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	int a = FIX2INT(x), b = FIX2INT(y);

	if (a <= b) return TRUE;
	return FALSE;
    }
    else {
	return num_coerce_bin(x, y);
    }
}

static VALUE
fix_rev(num)
    VALUE num;
{
    unsigned long val = FIX2UINT(num);

    val = ~val;
    return INT2FIX(val);
}

static VALUE
fix_and(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return big_and(y, x);
    }
    val = NUM2INT(x) & NUM2INT(y);
    return int2inum(val);
}

static VALUE
fix_or(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return big_or(y, x);
    }
    val = NUM2INT(x) | NUM2INT(y);
    return INT2FIX(val);
}

static VALUE
fix_xor(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return big_xor(y, x);
    }
    val = NUM2INT(x) ^ NUM2INT(y);
    return INT2FIX(val);
}

static VALUE
fix_lshift(x, y)
    VALUE x, y;
{
    long val, width;

    val = NUM2INT(x);
    width = NUM2INT(y);
    if (width > (sizeof(VALUE)*CHAR_BIT-1)
	|| (unsigned)val>>(sizeof(VALUE)*CHAR_BIT-width) > 0) {
	return big_lshift(int2big(val), y);
    }
    val = val << width;
    return int2inum(val);
}

static VALUE
fix_rshift(x, y)
    VALUE x, y;
{
    long val;

    val = RSHIFT(NUM2INT(x), NUM2INT(y));
    return INT2FIX(val);
}

static VALUE
fix_aref(fix, idx)
    VALUE fix, idx;
{
    unsigned long val = FIX2INT(fix);
    int i = FIX2INT(idx);

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

    val = (double)FIX2INT(num);

    return float_new(val);
}

static VALUE
fix_type(fix)
    VALUE fix;
{
    return cFixnum;
}

static VALUE
fix_abs(fix)
    VALUE fix;
{
    int i = FIX2INT(fix);

    if (i < 0) i = -i;

    return int2inum(i);
}

static VALUE
fix_id2name(fix)
    VALUE fix;
{
    char *name = rb_id2name(FIX2UINT(fix));
    if (name) return str_new2(name);
    return Qnil;
}

static VALUE
fix_next(fix)
    VALUE fix;
{
    int i = FIX2INT(fix) + 1;

    return int2inum(i);
}

extern VALUE mComparable;

void
Init_Numeric()
{
    coerce = rb_intern("coerce");
    to_i = rb_intern("to_i");

    cNumeric = rb_define_class("Numeric", cObject);

    rb_undef_method(CLASS_OF(cNumeric), "new");

    rb_include_module(cNumeric, mComparable);
    rb_define_method(cNumeric, "+@", num_uplus, 0);
    rb_define_method(cNumeric, "-@", num_uminus, 0);
    rb_define_method(cNumeric, "divmod", num_divmod, 1);

    rb_define_method(cNumeric, "next", num_next, 0);
    rb_define_method(cNumeric, "upto", num_upto, 1);
    rb_define_method(cNumeric, "downto", num_downto, 1);
    rb_define_method(cNumeric, "step", num_step, 2);
    rb_define_method(cNumeric, "times", num_dotimes, 0);
    rb_define_method(cNumeric, "integer?", num_int_p, 0);
    rb_define_method(cNumeric, "chr", num_chr, 0);

    cInteger = rb_define_class("Integer", cNumeric);
    rb_define_method(cInteger, "integer?", int_int_p, 0);

    cFixnum = rb_define_class("Fixnum", cInteger);

    rb_define_method(cFixnum, "to_s", fix_to_s, 0);
    rb_define_method(cFixnum, "type", fix_type, 0);

    rb_define_method(cFixnum, "id2name", fix_id2name, 0);

    rb_define_method(cFixnum, "-@", fix_uminus, 0);
    rb_define_method(cFixnum, "+", fix_plus, 1);
    rb_define_method(cFixnum, "-", fix_minus, 1);
    rb_define_method(cFixnum, "*", fix_mul, 1);
    rb_define_method(cFixnum, "/", fix_div, 1);
    rb_define_method(cFixnum, "%", fix_mod, 1);
    rb_define_method(cFixnum, "**", fix_pow, 1);

    rb_define_method(cFixnum, "abs", fix_abs, 0);

    rb_define_method(cFixnum, "==", fix_equal, 1);
    rb_define_method(cFixnum, "<=>", fix_cmp, 1);
    rb_define_method(cFixnum, ">",  fix_gt, 1);
    rb_define_method(cFixnum, ">=", fix_ge, 1);
    rb_define_method(cFixnum, "<",  fix_lt, 1);
    rb_define_method(cFixnum, "<=", fix_le, 1);

    rb_define_method(cFixnum, "~", fix_rev, 0);
    rb_define_method(cFixnum, "&", fix_and, 1);
    rb_define_method(cFixnum, "|", fix_or,  1);
    rb_define_method(cFixnum, "^", fix_xor, 1);
    rb_define_method(cFixnum, "[]", fix_aref, 1);

    rb_define_method(cFixnum, "<<", fix_lshift, 1);
    rb_define_method(cFixnum, ">>", fix_rshift, 1);

    rb_define_method(cFixnum, "to_i", fix_to_i, 0);
    rb_define_method(cFixnum, "to_f", fix_to_f, 0);

    rb_define_method(cFixnum, "next", fix_next, 0);

    cFloat  = rb_define_class("Float", cNumeric);

    rb_define_method(cFloat, "to_s", flo_to_s, 0);
    rb_define_method(cFloat, "coerce", flo_coerce, 1);
    rb_define_method(cFloat, "-@", flo_uminus, 0);
    rb_define_method(cFloat, "+", flo_plus, 1);
    rb_define_method(cFloat, "-", flo_minus, 1);
    rb_define_method(cFloat, "*", flo_mul, 1);
    rb_define_method(cFloat, "/", flo_div, 1);
    rb_define_method(cFloat, "%", flo_mod, 1);
    rb_define_method(cFloat, "**", flo_pow, 1);
    rb_define_method(cFloat, "==", flo_eq, 1);
    rb_define_method(cFloat, "<=>", flo_cmp, 1);
    rb_define_method(cFloat, "hash", flo_hash, 0);
    rb_define_method(cFloat, "to_i", flo_to_i, 0);
    rb_define_method(cFloat, "to_f", flo_to_f, 0);
    rb_define_method(cFloat, "abs", flo_abs, 0);
}
