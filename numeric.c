/************************************************

  numeric.c -

  $Author: matz $
  $Date: 1994/08/12 04:47:41 $
  created at: Fri Aug 13 18:33:09 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <math.h>

static ID coerce;
static ID to_i;

VALUE C_Numeric;
VALUE C_Float;
VALUE C_Integer;
VALUE C_Fixnum;

extern VALUE C_Range;
double big2dbl();

VALUE
float_new(d)
    double d;
{
    NEWOBJ(flt, struct RFloat);
    OBJSETUP(flt, C_Float, T_FLOAT);

    flt->value = d;
    return (VALUE)flt;
}

static
num_coerce_bin(x, mid, y)
    VALUE x, y;
    ID mid;
{
    return rb_funcall(rb_funcall(y, coerce, 1, x), mid, 1, y);
}

static VALUE
Fnum_uplus(num)
    VALUE num;
{
    return num;
}

static VALUE
Fnum_uminus(num)
    VALUE num;
{
    return rb_funcall(rb_funcall(num, coerce, 1, INT2FIX(0)), '-', 1, num);
}

static VALUE
Fnum_dot2(left, right)
    VALUE left, right;
{
    Need_Fixnum(left);
    Need_Fixnum(right);
    return range_new(C_Range, left, right);
}

static VALUE
Fnum_next(num)
    VALUE num;
{
    num = rb_funcall(num, rb_intern("to_i"), 0);
    return rb_funcall(num, '+', 1, INT2FIX(1));
}

VALUE
Fnum_upto(from, to)
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
Fnum_downto(from, to)
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
Fnum_step(from, to, step)
    VALUE from, to;
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
Fnum_dotimes(num)
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
Fnum_divmod(x, y)
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
Fnum_is_int(num)
    VALUE num;
{
    return FALSE;
}

static VALUE
Fflo_new(flt)
    struct RFloat *flt;
{
    Check_Type(flt, T_FLOAT);
    {
	NEWOBJ(flt2, struct RFloat);
	CLONESETUP(flt2, flt);

	flt2->value = flt->value;
	return (VALUE)flt2;
    }
}

static VALUE
Fflo_to_s(flt)
    struct RFloat *flt;
{
    char buf[32];

    sprintf(buf, "%g", flt->value);

    return str_new2(buf);
}

static VALUE
Fflo_coerce(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	return float_new((double)FIX2INT(y));
      case T_FLOAT:
	return y;
      case T_BIGNUM:
	return Fbig_to_f(y);
      default:
	Fail("can't coerce %s to Float", rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
    return Qnil;
}

static VALUE
Fflo_uminus(flt)
    struct RFloat *flt;
{
    return float_new(-flt->value);
}

static VALUE
Fflo_plus(x, y)
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
	return Fstr_plus(obj_as_string(x), y);
      default:
	return num_coerce_bin(x, '+', y);
    }
}

static VALUE
Fflo_minus(x, y)
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
	return num_coerce_bin(x, '-', y);
    }
}

static VALUE
Fflo_mul(x, y)
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
	return Fstr_times(y, INT2FIX((int)x->value));
      default:
	return num_coerce_bin(x, '*', y);
    }
}

static VALUE
Fflo_div(x, y)
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
	return num_coerce_bin(x, '/', y);
    }
}

static VALUE
Fflo_mod(x, y)
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
	return num_coerce_bin(x, '%', y);
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

Fflo_pow(x, y)
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
        return num_coerce_bin(x, rb_intern("**"), y);
    }
}

static VALUE
Fflo_eq(x, y)
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
	return num_coerce_bin(x, rb_intern("=="), y);
    }
}

static VALUE
Fflo_hash(num)
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
Fflo_cmp(x, y)
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
	return num_coerce_bin(x, rb_intern("<=>"), y);
    }
    if (a == b) return INT2FIX(0);
    if (a > b) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
Fflo_to_i(num)
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
Fflo_to_f(num)
    VALUE num;
{
    return num;
}

static VALUE
Fflo_clone(flt)
    struct RFloat *flt;
{
    VALUE flt2 = float_new(flt->value);
    CLONESETUP(flt2, flt);
    return flt2;
}

static VALUE
Fflo_abs(flt)
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
	break;

      case T_FLOAT:
	if (RFLOAT(val)->value <= (double) LONG_MAX
	    && RFLOAT(val)->value >= (double) LONG_MIN) {
	    return (int)(RFLOAT(val)->value);
	}
	else {
	    Fail("float %g out of rang of integer", RFLOAT(val)->value);
	}
	break;

      case T_BIGNUM:
	return big2int(val);

      default:
	val = rb_resque(to_integer, val, fail_to_integer, val);
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
Fint_is_int(num)
    VALUE num;
{
    return TRUE;
}

static VALUE
Fint_chr(num)
    VALUE num;
{
    char c;
    int i = NUM2INT(num);

    if (i < 0 || 0xff < i)
	Fail("%d out of char range", i);
    c = i;
    return str_new(&c, 1);
}

VALUE
Ffix_clone(num)
    VALUE num;
{
    return num;
}

static VALUE
Ffix_uminus(num)
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
Ffix_to_s(in)
    VALUE in;
{
    return fix2str(in, 10);
}

static VALUE
Ffix_plus(x, y)
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
		r = Fbig_plus(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) + y->value);
      default:
	return num_coerce_bin(x, '+', y);
    }
}

static VALUE
Ffix_minus(x, y)
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
		r = Fbig_minus(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) - y->value);
      default:
	return num_coerce_bin(x, '-', y);
    }
}

static VALUE
Ffix_mul(x, y)
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
		r = Fbig_mul(int2big(a), int2big(b));
	    }
	    return r;
	}
      case T_FLOAT:
	return float_new((double)FIX2INT(x) * y->value);
      default:
	return num_coerce_bin(x, '*', y);
    }
}

static VALUE
Ffix_div(x, y)
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
    return num_coerce_bin(x, '/', y);
}

static VALUE
Ffix_mod(x, y)
    VALUE x, y;
{
    int mod, i;

    if (TYPE(y) == T_FIXNUM) {
	i = FIX2INT(y);
	if (i == 0) Fail("devided by 0");
	i = FIX2INT(x)%i;
	return INT2FIX(i);
    }
    return num_coerce_bin(x, '%', y);
}

static VALUE
Ffix_pow(x, y)
    VALUE x, y;
{
    extern double pow();

    if (FIXNUM_P(y)) {
	int a, b;

	b = FIX2INT(y);
	if (b == 0) return INT2FIX(1);
	a = FIX2INT(x);
	if (b > 0) {
	    return Fbig_pow(int2big(a), y);
	}
	return float_new(pow((double)a, (double)b));
    }
    else if (NIL_P(y)) {
	return INT2FIX(1);
    }
    return num_coerce_bin(x, rb_intern("**"), y);
}

static VALUE
Ffix_equal(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return (FIX2INT(x) == FIX2INT(y))?TRUE:FALSE; 
    }
    else if (NIL_P(y)) {
	return Qnil;
    }
    else {
	return num_coerce_bin(x, rb_intern("=="), y);
    }
}

static VALUE
Ffix_cmp(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	int a = FIX2INT(x), b = FIX2INT(y);
	
	if (a == b) return INT2FIX(0);
	if (a > b) return INT2FIX(1);
	return INT2FIX(-1);
    }
    else {
	return num_coerce_bin(x, rb_intern("<=>"), y);
    }
}

static VALUE
Ffix_dot2(left, right)
    VALUE left, right;
{
    Need_Fixnum(right);
    return range_new(C_Range, left, right);
}

static VALUE
Ffix_rev(num)
    VALUE num;
{
    unsigned long val = FIX2UINT(num);

    val = ~val;
    return INT2FIX(val);
}

static VALUE
Ffix_and(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return Fbig_and(y, x);
    }
    val = NUM2INT(x) & NUM2INT(y);
    return int2inum(val);
}

static VALUE
Ffix_or(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return Fbig_or(y, x);
    }
    val = NUM2INT(x) | NUM2INT(y);
    return INT2FIX(val);
}

static VALUE
Ffix_xor(x, y)
    VALUE x, y;
{
    long val;

    if (TYPE(y) == T_BIGNUM) {
	return Fbig_xor(y, x);
    }
    val = NUM2INT(x) ^ NUM2INT(y);
    return INT2FIX(val);
}

static VALUE
Ffix_lshift(x, y)
    VALUE x, y;
{
    long val, width;

    val = NUM2INT(x);
    width = NUM2INT(y);
    if (width > (sizeof(VALUE)*CHAR_BIT-1)
	|| (unsigned)val>>(sizeof(VALUE)*CHAR_BIT-width) > 0) {
	return Fbig_lshift(int2big(val), y);
    }
    val = val << width;
    return int2inum(val);
}

static VALUE
Ffix_rshift(x, y)
    VALUE x, y;
{
    long val;

    val = RSHIFT(NUM2INT(x), NUM2INT(y));
    return INT2FIX(val);
}

static VALUE
Ffix_aref(fix, idx)
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
Ffix_to_i(num)
    VALUE num;
{
    return num;
}

static VALUE
Ffix_to_f(num)
    VALUE num;
{
    double val;

    val = (double)FIX2INT(num);

    return float_new(val);
}

static VALUE
Ffix_class(fix)
    VALUE fix;
{
    return C_Fixnum;
}

static Ffix_abs(fix)
    VALUE fix;
{
    int i = FIX2INT(fix);

    if (fix < 0) i = -i;

    return int2inum(fix);
}

static VALUE
Ffix_id2name(fix)
    VALUE fix;
{
    char *name = rb_id2name(FIX2UINT(fix));
    if (name) return str_new2(name);
    return Qnil;
}

static VALUE
Ffix_next(fix)
    VALUE fix;
{
    int i = FIX2INT(fix) + 1;

    return int2inum(i);
}

extern VALUE M_Comparable;
extern Fkrn_inspect();

Init_Numeric()
{
    coerce = rb_intern("coerce");
    to_i = rb_intern("to_i");

    C_Numeric = rb_define_class("Numeric", C_Object);
    rb_include_module(C_Numeric, M_Comparable);
    rb_define_method(C_Numeric, "+@", Fnum_uplus, 0);
    rb_define_method(C_Numeric, "-@", Fnum_uminus, 0);
    rb_define_method(C_Numeric, "..", Fnum_dot2, 1);
    rb_define_method(C_Numeric, "divmod", Fnum_divmod, 1);

    rb_define_method(C_Numeric, "next", Fnum_next, 0);
    rb_define_method(C_Numeric, "upto", Fnum_upto, 1);
    rb_define_method(C_Numeric, "downto", Fnum_downto, 1);
    rb_define_method(C_Numeric, "step", Fnum_step, 2);
    rb_define_method(C_Numeric, "times", Fnum_dotimes, 0);
    rb_define_method(C_Numeric, "is_integer", Fnum_is_int, 0);
    rb_define_method(C_Numeric, "_inspect", Fkrn_inspect, 0);

    C_Integer = rb_define_class("Integer", C_Numeric);
    rb_define_method(C_Integer, "is_integer", Fint_is_int, 0);
    rb_define_method(C_Integer, "chr", Fint_chr, 0);

    C_Fixnum = rb_define_class("Fixnum", C_Integer);
    rb_define_method(C_Fixnum, "to_s", Ffix_to_s, 0);
    rb_define_method(C_Fixnum, "class", Ffix_class, 0);
    rb_define_method(C_Fixnum, "clone", Ffix_clone, 0);

    rb_define_method(C_Fixnum, "id2name", Ffix_id2name, 0);

    rb_define_method(C_Fixnum, "-@", Ffix_uminus, 0);
    rb_define_method(C_Fixnum, "+", Ffix_plus, 1);
    rb_define_method(C_Fixnum, "-", Ffix_minus, 1);
    rb_define_method(C_Fixnum, "*", Ffix_mul, 1);
    rb_define_method(C_Fixnum, "/", Ffix_div, 1);
    rb_define_method(C_Fixnum, "%", Ffix_mod, 1);
    rb_define_method(C_Fixnum, "**", Ffix_pow, 1);

    rb_define_method(C_Fixnum, "abs", Ffix_abs, 0);

    rb_define_method(C_Fixnum, "==", Ffix_equal, 1);
    rb_define_method(C_Fixnum, "<=>", Ffix_cmp, 1);
    rb_define_method(C_Fixnum, "..", Ffix_dot2, 1);

    rb_define_method(C_Fixnum, "~", Ffix_rev, 0);
    rb_define_method(C_Fixnum, "&", Ffix_and, 1);
    rb_define_method(C_Fixnum, "|", Ffix_or,  1);
    rb_define_method(C_Fixnum, "^", Ffix_xor, 1);
    rb_define_method(C_Fixnum, "[]", Ffix_aref, 1);

    rb_define_method(C_Fixnum, "<<", Ffix_lshift, 1);
    rb_define_method(C_Fixnum, ">>", Ffix_rshift, 1);

    rb_define_method(C_Fixnum, "to_i", Ffix_to_i, 0);
    rb_define_method(C_Fixnum, "to_f", Ffix_to_f, 0);

    rb_define_method(C_Fixnum, "next", Ffix_next, 0);

    C_Float  = rb_define_class("Float", C_Numeric);
    rb_define_single_method(C_Float, "new", Fflo_new, 1);
    rb_define_method(C_Float, "clone", Fflo_clone, 0);
    rb_define_method(C_Float, "to_s", Fflo_to_s, 0);
    rb_define_method(C_Float, "coerce", Fflo_coerce, 1);
    rb_define_method(C_Float, "-@", Fflo_uminus, 0);
    rb_define_method(C_Float, "+", Fflo_plus, 1);
    rb_define_method(C_Float, "-", Fflo_minus, 1);
    rb_define_method(C_Float, "*", Fflo_mul, 1);
    rb_define_method(C_Float, "/", Fflo_div, 1);
    rb_define_method(C_Float, "%", Fflo_mod, 1);
    rb_define_method(C_Float, "**", Fflo_pow, 1);
    rb_define_method(C_Float, "==", Fflo_eq, 1);
    rb_define_method(C_Float, "<=>", Fflo_cmp, 1);
    rb_define_method(C_Float, "hash", Fflo_hash, 0);
    rb_define_method(C_Float, "to_i", Fflo_to_i, 0);
    rb_define_method(C_Float, "to_f", Fflo_to_f, 0);
    rb_define_method(C_Float, "abs", Fflo_abs, 0);
}
