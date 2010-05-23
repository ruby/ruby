/*
  rational.c: Coded by Tadayoshi Funaba 2008

  This implementation is based on Keiju Ishitsuka's Rational library
  which is written in ruby.
*/

#include "ruby.h"
#include <math.h>
#include <float.h>

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#define NDEBUG
#include <assert.h>

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)

VALUE rb_cRational;

static ID id_abs, id_cmp, id_convert, id_equal_p, id_expt, id_floor,
    id_hash, id_idiv, id_inspect, id_integer_p, id_negate, id_to_f,
    id_to_i, id_to_s, id_truncate;

#define f_boolcast(x) ((x) ? Qtrue : Qfalse)

#define binop(n,op) \
inline static VALUE \
f_##n(VALUE x, VALUE y)\
{\
  return rb_funcall(x, op, 1, y);\
}

#define fun1(n) \
inline static VALUE \
f_##n(VALUE x)\
{\
    return rb_funcall(x, id_##n, 0);\
}

#define fun2(n) \
inline static VALUE \
f_##n(VALUE x, VALUE y)\
{\
    return rb_funcall(x, id_##n, 1, y);\
}

inline static VALUE
f_add(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIX2LONG(y) == 0)
	return x;
    else if (FIXNUM_P(x) && FIX2LONG(x) == 0)
	return y;
    return rb_funcall(x, '+', 1, y);
}

inline static VALUE
f_cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
	long c = FIX2LONG(x) - FIX2LONG(y);
	if (c > 0)
	    c = 1;
	else if (c < 0)
	    c = -1;
	return INT2FIX(c);
    }
    return rb_funcall(x, id_cmp, 1, y);
}

inline static VALUE
f_div(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIX2LONG(y) == 1)
	return x;
    return rb_funcall(x, '/', 1, y);
}

inline static VALUE
f_gt_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) > FIX2LONG(y));
    return rb_funcall(x, '>', 1, y);
}

inline static VALUE
f_lt_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) < FIX2LONG(y));
    return rb_funcall(x, '<', 1, y);
}

binop(mod, '%')

inline static VALUE
f_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	long iy = FIX2LONG(y);
	if (iy == 0) {
	    if (FIXNUM_P(x) || TYPE(x) == T_BIGNUM)
		return ZERO;
	}
	else if (iy == 1)
	    return x;
    }
    else if (FIXNUM_P(x)) {
	long ix = FIX2LONG(x);
	if (ix == 0) {
	    if (FIXNUM_P(y) || TYPE(y) == T_BIGNUM)
		return ZERO;
	}
	else if (ix == 1)
	    return y;
    }
    return rb_funcall(x, '*', 1, y);
}

inline static VALUE
f_sub(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIX2LONG(y) == 0)
	return x;
    return rb_funcall(x, '-', 1, y);
}

binop(xor, '^')

fun1(abs)
fun1(floor)
fun1(hash)
fun1(inspect)
fun1(integer_p)
fun1(negate)
fun1(to_f)
fun1(to_i)
fun1(to_s)
fun1(truncate)

inline static VALUE
f_equal_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) == FIX2LONG(y));
    return rb_funcall(x, id_equal_p, 1, y);
}

fun2(expt)
fun2(idiv)

inline static VALUE
f_negative_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) < 0);
    return rb_funcall(x, '<', 1, ZERO);
}

#define f_positive_p(x) (!f_negative_p(x))

inline static VALUE
f_zero_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) == 0);
    return rb_funcall(x, id_equal_p, 1, ZERO);
}

#define f_nonzero_p(x) (!f_zero_p(x))

inline static VALUE
f_one_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) == 1);
    return rb_funcall(x, id_equal_p, 1, ONE);
}

inline static VALUE
f_kind_of_p(VALUE x, VALUE c)
{
    return rb_obj_is_kind_of(x, c);
}

inline static VALUE
k_numeric_p(VALUE x)
{
    return f_kind_of_p(x, rb_cNumeric);
}

inline static VALUE
k_integer_p(VALUE x)
{
    return f_kind_of_p(x, rb_cInteger);
}

inline static VALUE
k_float_p(VALUE x)
{
    return f_kind_of_p(x, rb_cFloat);
}

inline static VALUE
k_rational_p(VALUE x)
{
    return f_kind_of_p(x, rb_cRational);
}

#define k_exact_p(x) (!k_float_p(x))
#define k_inexact_p(x) k_float_p(x)

#ifndef NDEBUG
#define f_gcd f_gcd_orig
#endif

inline static long
i_gcd(long x, long y)
{
    if (x < 0)
	x = -x;
    if (y < 0)
	y = -y;

    if (x == 0)
	return y;
    if (y == 0)
	return x;

    while (x > 0) {
	long t = x;
	x = y % x;
	y = t;
    }
    return y;
}

inline static VALUE
f_gcd(VALUE x, VALUE y)
{
    VALUE z;

    if (FIXNUM_P(x) && FIXNUM_P(y))
	return LONG2NUM(i_gcd(FIX2LONG(x), FIX2LONG(y)));

    if (f_negative_p(x))
	x = f_negate(x);
    if (f_negative_p(y))
	y = f_negate(y);

    if (f_zero_p(x))
	return y;
    if (f_zero_p(y))
	return x;

    for (;;) {
	if (FIXNUM_P(x)) {
	    if (FIX2LONG(x) == 0)
		return y;
	    if (FIXNUM_P(y))
		return LONG2NUM(i_gcd(FIX2LONG(x), FIX2LONG(y)));
	}
	z = x;
	x = f_mod(y, x);
	y = z;
    }
    /* NOTREACHED */
}

#ifndef NDEBUG
#undef f_gcd

inline static VALUE
f_gcd(VALUE x, VALUE y)
{
    VALUE r = f_gcd_orig(x, y);
    if (f_nonzero_p(r)) {
	assert(f_zero_p(f_mod(x, r)));
	assert(f_zero_p(f_mod(y, r)));
    }
    return r;
}
#endif

inline static VALUE
f_lcm(VALUE x, VALUE y)
{
    if (f_zero_p(x) || f_zero_p(y))
	return ZERO;
    return f_abs(f_mul(f_div(x, f_gcd(x, y)), y));
}

#define get_dat1(x) \
    struct RRational *dat;\
    dat = ((struct RRational *)(x))

#define get_dat2(x,y) \
    struct RRational *adat, *bdat;\
    adat = ((struct RRational *)(x));\
    bdat = ((struct RRational *)(y))

inline static VALUE
nurat_s_new_internal(VALUE klass, VALUE num, VALUE den)
{
    NEWOBJ(obj, struct RRational);
    OBJSETUP(obj, klass, T_RATIONAL);

    obj->num = num;
    obj->den = den;

    return (VALUE)obj;
}

static VALUE
nurat_s_alloc(VALUE klass)
{
    return nurat_s_new_internal(klass, ZERO, ONE);
}

#define rb_raise_zerodiv() rb_raise(rb_eZeroDivError, "divided by zero")

#if 0
static VALUE
nurat_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE num, den;

    switch (rb_scan_args(argc, argv, "11", &num, &den)) {
      case 1:
	if (!k_integer_p(num))
	    num = f_to_i(num);
	den = ONE;
	break;
      default:
	if (!k_integer_p(num))
	    num = f_to_i(num);
	if (!k_integer_p(den))
	    den = f_to_i(den);

	switch (FIX2INT(f_cmp(den, ZERO))) {
	  case -1:
	    num = f_negate(num);
	    den = f_negate(den);
	    break;
	  case 0:
	    rb_raise_zerodiv();
	    break;
	}
	break;
    }

    return nurat_s_new_internal(klass, num, den);
}
#endif

inline static VALUE
f_rational_new_bang1(VALUE klass, VALUE x)
{
    return nurat_s_new_internal(klass, x, ONE);
}

inline static VALUE
f_rational_new_bang2(VALUE klass, VALUE x, VALUE y)
{
    assert(f_positive_p(y));
    assert(f_nonzero_p(y));
    return nurat_s_new_internal(klass, x, y);
}

#ifdef CANONICALIZATION_FOR_MATHN
#define CANON
#endif

#ifdef CANON
static int canonicalization = 0;

void
nurat_canonicalization(int f)
{
    canonicalization = f;
}
#endif

inline static void
nurat_int_check(VALUE num)
{
    switch (TYPE(num)) {
      case T_FIXNUM:
      case T_BIGNUM:
	break;
      default:
	if (!k_numeric_p(num) || !f_integer_p(num))
	    rb_raise(rb_eArgError, "not an integer");
    }
}

inline static VALUE
nurat_int_value(VALUE num)
{
    nurat_int_check(num);
    if (!k_integer_p(num))
	num = f_to_i(num);
    return num;
}

inline static VALUE
nurat_s_canonicalize_internal(VALUE klass, VALUE num, VALUE den)
{
    VALUE gcd;

    switch (FIX2INT(f_cmp(den, ZERO))) {
      case -1:
	num = f_negate(num);
	den = f_negate(den);
	break;
      case 0:
	rb_raise_zerodiv();
	break;
    }

    gcd = f_gcd(num, den);
    num = f_idiv(num, gcd);
    den = f_idiv(den, gcd);

#ifdef CANON
    if (f_one_p(den) && canonicalization)
	return num;
#endif
    return nurat_s_new_internal(klass, num, den);
}

inline static VALUE
nurat_s_canonicalize_internal_no_reduce(VALUE klass, VALUE num, VALUE den)
{
    switch (FIX2INT(f_cmp(den, ZERO))) {
      case -1:
	num = f_negate(num);
	den = f_negate(den);
	break;
      case 0:
	rb_raise_zerodiv();
	break;
    }

#ifdef CANON
    if (f_one_p(den) && canonicalization)
	return num;
#endif
    return nurat_s_new_internal(klass, num, den);
}

static VALUE
nurat_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE num, den;

    switch (rb_scan_args(argc, argv, "11", &num, &den)) {
      case 1:
	num = nurat_int_value(num);
	den = ONE;
	break;
      default:
	num = nurat_int_value(num);
	den = nurat_int_value(den);
	break;
    }

    return nurat_s_canonicalize_internal(klass, num, den);
}

inline static VALUE
f_rational_new1(VALUE klass, VALUE x)
{
    assert(!k_rational_p(x));
    return nurat_s_canonicalize_internal(klass, x, ONE);
}

inline static VALUE
f_rational_new2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_rational_p(x));
    assert(!k_rational_p(y));
    return nurat_s_canonicalize_internal(klass, x, y);
}

inline static VALUE
f_rational_new_no_reduce1(VALUE klass, VALUE x)
{
    assert(!k_rational_p(x));
    return nurat_s_canonicalize_internal_no_reduce(klass, x, ONE);
}

inline static VALUE
f_rational_new_no_reduce2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_rational_p(x));
    assert(!k_rational_p(y));
    return nurat_s_canonicalize_internal_no_reduce(klass, x, y);
}

static VALUE
nurat_f_rational(int argc, VALUE *argv, VALUE klass)
{
    return rb_funcall2(rb_cRational, id_convert, argc, argv);
}

static VALUE
nurat_numerator(VALUE self)
{
    get_dat1(self);
    return dat->num;
}

static VALUE
nurat_denominator(VALUE self)
{
    get_dat1(self);
    return dat->den;
}

#ifndef NDEBUG
#define f_imul f_imul_orig
#endif

inline static VALUE
f_imul(long a, long b)
{
    VALUE r;
    long c;

    if (a == 0 || b == 0)
	return ZERO;
    else if (a == 1)
	return LONG2NUM(b);
    else if (b == 1)
	return LONG2NUM(a);

    c = a * b;
    r = LONG2NUM(c);
    if (NUM2LONG(r) != c || (c / a) != b)
	r = rb_big_mul(rb_int2big(a), rb_int2big(b));
    return r;
}

#ifndef NDEBUG
#undef f_imul

inline static VALUE
f_imul(long x, long y)
{
    VALUE r = f_imul_orig(x, y);
    assert(f_equal_p(r, f_mul(LONG2NUM(x), LONG2NUM(y))));
    return r;
}
#endif

inline static VALUE
f_addsub(VALUE self, VALUE anum, VALUE aden, VALUE bnum, VALUE bden, int k)
{
    VALUE num, den;

    if (FIXNUM_P(anum) && FIXNUM_P(aden) &&
	FIXNUM_P(bnum) && FIXNUM_P(bden)) {
	long an = FIX2LONG(anum);
	long ad = FIX2LONG(aden);
	long bn = FIX2LONG(bnum);
	long bd = FIX2LONG(bden);
	long ig = i_gcd(ad, bd);

	VALUE g = LONG2NUM(ig);
	VALUE a = f_imul(an, bd / ig);
	VALUE b = f_imul(bn, ad / ig);
	VALUE c;

	if (k == '+')
	    c = f_add(a, b);
	else
	    c = f_sub(a, b);

	b = f_idiv(aden, g);
	g = f_gcd(c, g);
	num = f_idiv(c, g);
	a = f_idiv(bden, g);
	den = f_mul(a, b);
    }
    else {
	VALUE g = f_gcd(aden, bden);
	VALUE a = f_mul(anum, f_idiv(bden, g));
	VALUE b = f_mul(bnum, f_idiv(aden, g));
	VALUE c;

	if (k == '+')
	    c = f_add(a, b);
	else
	    c = f_sub(a, b);

	b = f_idiv(aden, g);
	g = f_gcd(c, g);
	num = f_idiv(c, g);
	a = f_idiv(bden, g);
	den = f_mul(a, b);
    }
    return f_rational_new_no_reduce2(CLASS_OF(self), num, den);
}

static VALUE
nurat_add(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    return f_addsub(self,
			    dat->num, dat->den,
			    other, ONE, '+');
	}
      case T_FLOAT:
	return f_add(f_to_f(self), other);
      case T_RATIONAL:
	{
	    get_dat2(self, other);

	    return f_addsub(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '+');
	}
      default:
	return rb_num_coerce_bin(self, other, '+');
    }
}

static VALUE
nurat_sub(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    return f_addsub(self,
			    dat->num, dat->den,
			    other, ONE, '-');
	}
      case T_FLOAT:
	return f_sub(f_to_f(self), other);
      case T_RATIONAL:
	{
	    get_dat2(self, other);

	    return f_addsub(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '-');
	}
      default:
	return rb_num_coerce_bin(self, other, '-');
    }
}

inline static VALUE
f_muldiv(VALUE self, VALUE anum, VALUE aden, VALUE bnum, VALUE bden, int k)
{
    VALUE num, den;

    if (k == '/') {
	VALUE t;

	if (f_negative_p(bnum)) {
	    anum = f_negate(anum);
	    bnum = f_negate(bnum);
	}
	t = bnum;
	bnum = bden;
	bden = t;
    }

    if (FIXNUM_P(anum) && FIXNUM_P(aden) &&
	FIXNUM_P(bnum) && FIXNUM_P(bden)) {
	long an = FIX2LONG(anum);
	long ad = FIX2LONG(aden);
	long bn = FIX2LONG(bnum);
	long bd = FIX2LONG(bden);
	long g1 = i_gcd(an, bd);
	long g2 = i_gcd(ad, bn);

	num = f_imul(an / g1, bn / g2);
	den = f_imul(ad / g2, bd / g1);
    }
    else {
	VALUE g1 = f_gcd(anum, bden);
	VALUE g2 = f_gcd(aden, bnum);

	num = f_mul(f_idiv(anum, g1), f_idiv(bnum, g2));
	den = f_mul(f_idiv(aden, g2), f_idiv(bden, g1));
    }
    return f_rational_new_no_reduce2(CLASS_OF(self), num, den);
}

static VALUE
nurat_mul(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    return f_muldiv(self,
			    dat->num, dat->den,
			    other, ONE, '*');
	}
      case T_FLOAT:
	return f_mul(f_to_f(self), other);
      case T_RATIONAL:
	{
	    get_dat2(self, other);

	    return f_muldiv(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '*');
	}
      default:
	return rb_num_coerce_bin(self, other, '*');
    }
}

static VALUE
nurat_div(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	if (f_zero_p(other))
	    rb_raise_zerodiv();
	{
	    get_dat1(self);

	    return f_muldiv(self,
			    dat->num, dat->den,
			    other, ONE, '/');
	}
      case T_FLOAT:
	return rb_funcall(f_to_f(self), '/', 1, other);
      case T_RATIONAL:
	if (f_zero_p(other))
	    rb_raise_zerodiv();
	{
	    get_dat2(self, other);

	    return f_muldiv(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '/');
	}
      default:
	return rb_num_coerce_bin(self, other, '/');
    }
}

static VALUE
nurat_fdiv(VALUE self, VALUE other)
{
    return f_div(f_to_f(self), other);
}

static VALUE
nurat_expt(VALUE self, VALUE other)
{
    if (k_exact_p(other) && f_zero_p(other))
	return f_rational_new_bang1(CLASS_OF(self), ONE);

    if (k_rational_p(other)) {
	get_dat1(other);

	if (f_one_p(dat->den))
	    other = dat->num; /* good? */
    }

    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    VALUE num, den;

	    get_dat1(self);

	    switch (FIX2INT(f_cmp(other, ZERO))) {
	      case 1:
		num = f_expt(dat->num, other);
		den = f_expt(dat->den, other);
		break;
	      case -1:
		num = f_expt(dat->den, f_negate(other));
		den = f_expt(dat->num, f_negate(other));
		break;
	      default:
		num = ONE;
		den = ONE;
		break;
	    }
	    return f_rational_new2(CLASS_OF(self), num, den);
	}
      case T_FLOAT:
      case T_RATIONAL:
	return f_expt(f_to_f(self), other);
      default:
	return rb_num_coerce_bin(self, other, id_expt);
    }
}

static VALUE
nurat_cmp(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    if (FIXNUM_P(dat->den) && FIX2LONG(dat->den) == 1)
		return f_cmp(dat->num, other);
	    return f_cmp(self, f_rational_new_bang1(CLASS_OF(self), other));
	}
      case T_FLOAT:
	return f_cmp(f_to_f(self), other);
      case T_RATIONAL:
	{
	    VALUE num1, num2;

	    get_dat2(self, other);

	    if (FIXNUM_P(adat->num) && FIXNUM_P(adat->den) &&
		FIXNUM_P(bdat->num) && FIXNUM_P(bdat->den)) {
		num1 = f_imul(FIX2LONG(adat->num), FIX2LONG(bdat->den));
		num2 = f_imul(FIX2LONG(bdat->num), FIX2LONG(adat->den));
	    }
	    else {
		num1 = f_mul(adat->num, bdat->den);
		num2 = f_mul(bdat->num, adat->den);
	    }
	    return f_cmp(f_sub(num1, num2), ZERO);
	}
      default:
	return rb_num_coerce_bin(self, other, id_cmp);
    }
}

static VALUE
nurat_equal_p(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    if (f_zero_p(dat->num) && f_zero_p(other))
		return Qtrue;

	    if (!FIXNUM_P(dat->den))
		return Qfalse;
	    if (FIX2LONG(dat->den) != 1)
		return Qfalse;
	    if (f_equal_p(dat->num, other))
		return Qtrue;
	    return Qfalse;
	}
      case T_FLOAT:
	return f_equal_p(f_to_f(self), other);
      case T_RATIONAL:
	{
	    get_dat2(self, other);

	    if (f_zero_p(adat->num) && f_zero_p(bdat->num))
		return Qtrue;

	    return f_boolcast(f_equal_p(adat->num, bdat->num) &&
			      f_equal_p(adat->den, bdat->den));
	}
      default:
	return f_equal_p(other, self);
    }
}

static VALUE
nurat_coerce(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	return rb_assoc_new(f_rational_new_bang1(CLASS_OF(self), other), self);
      case T_FLOAT:
	return rb_assoc_new(other, f_to_f(self));
      case T_RATIONAL:
	return rb_assoc_new(other, self);
      case T_COMPLEX:
	if (k_exact_p(RCOMPLEX(other)->imag) && f_zero_p(RCOMPLEX(other)->imag))
	    return rb_assoc_new(f_rational_new_bang1
				(CLASS_OF(self), RCOMPLEX(other)->real), self);
    }

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_obj_classname(other), rb_obj_classname(self));
    return Qnil;
}

static VALUE
nurat_idiv(VALUE self, VALUE other)
{
    return f_floor(f_div(self, other));
}

static VALUE
nurat_mod(VALUE self, VALUE other)
{
    VALUE val = f_floor(f_div(self, other));
    return f_sub(self, f_mul(other, val));
}

static VALUE
nurat_divmod(VALUE self, VALUE other)
{
    VALUE val = f_floor(f_div(self, other));
    return rb_assoc_new(val, f_sub(self, f_mul(other, val)));
}

#if 0
static VALUE
nurat_quot(VALUE self, VALUE other)
{
    return f_truncate(f_div(self, other));
}
#endif

static VALUE
nurat_rem(VALUE self, VALUE other)
{
    VALUE val = f_truncate(f_div(self, other));
    return f_sub(self, f_mul(other, val));
}

#if 0
static VALUE
nurat_quotrem(VALUE self, VALUE other)
{
    VALUE val = f_truncate(f_div(self, other));
    return rb_assoc_new(val, f_sub(self, f_mul(other, val)));
}
#endif

static VALUE
nurat_abs(VALUE self)
{
    if (f_positive_p(self))
	return self;
    return f_negate(self);
}

#if 0
static VALUE
nurat_true(VALUE self)
{
    return Qtrue;
}
#endif

static VALUE
nurat_floor(VALUE self)
{
    get_dat1(self);
    return f_idiv(dat->num, dat->den);
}

static VALUE
nurat_ceil(VALUE self)
{
    get_dat1(self);
    return f_negate(f_idiv(f_negate(dat->num), dat->den));
}

static VALUE
nurat_truncate(VALUE self)
{
    get_dat1(self);
    if (f_negative_p(dat->num))
	return f_negate(f_idiv(f_negate(dat->num), dat->den));
    return f_idiv(dat->num, dat->den);
}

static VALUE
nurat_round(VALUE self)
{
    get_dat1(self);

    if (f_negative_p(dat->num)) {
	VALUE num, den;

	num = f_negate(dat->num);
	num = f_add(f_mul(num, TWO), dat->den);
	den = f_mul(dat->den, TWO);
	return f_negate(f_idiv(num, den));
    }
    else {
	VALUE num = f_add(f_mul(dat->num, TWO), dat->den);
	VALUE den = f_mul(dat->den, TWO);
	return f_idiv(num, den);
    }
}

#define f_size(x) rb_funcall(x, rb_intern("size"), 0)
#define f_rshift(x,y) rb_funcall(x, rb_intern(">>"), 1, y)

inline static long
i_ilog2(VALUE x)
{
    long q, r, fx;

    assert(!f_lt_p(x, ONE));

    q = (NUM2LONG(f_size(x)) - sizeof(long)) * 8 + 1;

    if (q > 0)
	x = f_rshift(x, LONG2NUM(q));

    fx = NUM2LONG(x);

    r = -1;
    while (fx) {
	fx >>= 1;
	r += 1;
    }

    return q + r;
}

static long ml;

static VALUE
nurat_to_f(VALUE self)
{
    VALUE num, den;
    int minus = 0;
    long nl, dl, ne, de;
    int e;
    double f;

    {
	get_dat1(self);

	if (f_zero_p(dat->num))
	    return rb_float_new(0.0);

	num = dat->num;
	den = dat->den;
    }

    if (f_negative_p(num)) {
	num = f_negate(num);
	minus = 1;
    }

    nl = i_ilog2(num);
    dl = i_ilog2(den);

    ne = 0;
    if (nl > ml) {
	ne = nl - ml;
	num = f_rshift(num, LONG2NUM(ne));
    }

    de = 0;
    if (dl > ml) {
	de = dl - ml;
	den = f_rshift(den, LONG2NUM(de));
    }

    e = (int)(ne - de);

    if ((e > DBL_MAX_EXP) || (e < DBL_MIN_EXP)) {
	rb_warning("%s out of Float range", rb_obj_classname(self));
	return rb_float_new(e > 0 ? HUGE_VAL : 0.0);
    }

    f = NUM2DBL(num) / NUM2DBL(den);
    if (minus)
	f = -f;
    f = ldexp(f, e);

    if (isinf(f) || isnan(f))
	rb_warning("%s out of Float range", rb_obj_classname(self));

    return rb_float_new(f);
}

static VALUE
nurat_to_r(VALUE self)
{
    return self;
}

static VALUE
nurat_hash(VALUE self)
{
    get_dat1(self);
    return f_xor(f_hash(dat->num), f_hash(dat->den));
}

static VALUE
nurat_format(VALUE self, VALUE (*func)(VALUE))
{
    VALUE s;
    get_dat1(self);

    s = (*func)(dat->num);
    rb_str_cat2(s, "/");
    rb_str_concat(s, (*func)(dat->den));

    return s;
}

static VALUE
nurat_to_s(VALUE self)
{
    return nurat_format(self, f_to_s);
}

static VALUE
nurat_inspect(VALUE self)
{
    VALUE s;

    s = rb_usascii_str_new2("(");
    rb_str_concat(s, nurat_format(self, f_inspect));
    rb_str_cat2(s, ")");

    return s;
}

static VALUE
nurat_marshal_dump(VALUE self)
{
    VALUE a;
    get_dat1(self);

    a = rb_assoc_new(dat->num, dat->den);
    rb_copy_generic_ivar(a, self);
    return a;
}

static VALUE
nurat_marshal_load(VALUE self, VALUE a)
{
    get_dat1(self);
    dat->num = RARRAY_PTR(a)[0];
    dat->den = RARRAY_PTR(a)[1];
    rb_copy_generic_ivar(self, a);

    if (f_zero_p(dat->den))
	rb_raise_zerodiv();

    return self;
}

/* --- */

VALUE
rb_gcd(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_gcd(self, other);
}

VALUE
rb_lcm(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_lcm(self, other);
}

VALUE
rb_gcdlcm(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return rb_assoc_new(f_gcd(self, other), f_lcm(self, other));
}

VALUE
rb_rational_raw(VALUE x, VALUE y)
{
    return nurat_s_new_internal(rb_cRational, x, y);
}

VALUE
rb_rational_new(VALUE x, VALUE y)
{
    return nurat_s_canonicalize_internal(rb_cRational, x, y);
}

static VALUE nurat_s_convert(int argc, VALUE *argv, VALUE klass);

VALUE
rb_Rational(VALUE x, VALUE y)
{
    VALUE a[2];
    a[0] = x;
    a[1] = y;
    return nurat_s_convert(2, a, rb_cRational);
}

#define id_numerator rb_intern("numerator")
#define f_numerator(x) rb_funcall(x, id_numerator, 0)

#define id_denominator rb_intern("denominator")
#define f_denominator(x) rb_funcall(x, id_denominator, 0)

#define id_to_r rb_intern("to_r")
#define f_to_r(x) rb_funcall(x, id_to_r, 0)

static VALUE
numeric_numerator(VALUE self)
{
    return f_numerator(f_to_r(self));
}

static VALUE
numeric_denominator(VALUE self)
{
    return f_denominator(f_to_r(self));
}

static VALUE
integer_numerator(VALUE self)
{
    return self;
}

static VALUE
integer_denominator(VALUE self)
{
    return INT2FIX(1);
}

static VALUE
float_numerator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return self;
    return rb_call_super(0, 0);
}

static VALUE
float_denominator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return INT2FIX(1);
    return rb_call_super(0, 0);
}

static VALUE
nilclass_to_r(VALUE self)
{
    return rb_rational_new1(INT2FIX(0));
}

static VALUE
integer_to_r(VALUE self)
{
    return rb_rational_new1(self);
}

static void
float_decode_internal(VALUE self, VALUE *rf, VALUE *rn)
{
    double f;
    int n;

    f = frexp(RFLOAT_VALUE(self), &n);
    f = ldexp(f, DBL_MANT_DIG);
    n -= DBL_MANT_DIG;
    *rf = rb_dbl2big(f);
    *rn = INT2FIX(n);
}

#if 0
static VALUE
float_decode(VALUE self)
{
    VALUE f, n;

    float_decode_internal(self, &f, &n);
    return rb_assoc_new(f, n);
}
#endif

static VALUE
float_to_r(VALUE self)
{
    VALUE f, n;

    float_decode_internal(self, &f, &n);
    return f_mul(f, f_expt(INT2FIX(FLT_RADIX), n));
}

static VALUE rat_pat, an_e_pat, a_dot_pat, underscores_pat, an_underscore;

#define WS "\\s*"
#define DIGITS "(?:[0-9](?:_[0-9]|[0-9])*)"
#define NUMERATOR "(?:" DIGITS "?\\.)?" DIGITS "(?:[eE][-+]?" DIGITS ")?"
#define DENOMINATOR DIGITS
#define PATTERN "\\A" WS "([-+])?(" NUMERATOR ")(?:\\/(" DENOMINATOR "))?" WS

static void
make_patterns(void)
{
    static const char rat_pat_source[] = PATTERN;
    static const char an_e_pat_source[] = "[eE]";
    static const char a_dot_pat_source[] = "\\.";
    static const char underscores_pat_source[] = "_+";

    if (rat_pat) return;

    rat_pat = rb_reg_new(rat_pat_source, sizeof rat_pat_source - 1, 0);
    rb_gc_register_mark_object(rat_pat);

    an_e_pat = rb_reg_new(an_e_pat_source, sizeof an_e_pat_source - 1, 0);
    rb_gc_register_mark_object(an_e_pat);

    a_dot_pat = rb_reg_new(a_dot_pat_source, sizeof a_dot_pat_source - 1, 0);
    rb_gc_register_mark_object(a_dot_pat);

    underscores_pat = rb_reg_new(underscores_pat_source,
				 sizeof underscores_pat_source - 1, 0);
    rb_gc_register_mark_object(underscores_pat);

    an_underscore = rb_usascii_str_new2("_");
    rb_gc_register_mark_object(an_underscore);
}

#define id_match rb_intern("match")
#define f_match(x,y) rb_funcall(x, id_match, 1, y)

#define id_aref rb_intern("[]")
#define f_aref(x,y) rb_funcall(x, id_aref, 1, y)

#define id_post_match rb_intern("post_match")
#define f_post_match(x) rb_funcall(x, id_post_match, 0)

#define id_split rb_intern("split")
#define f_split(x,y) rb_funcall(x, id_split, 1, y)

#include <ctype.h>

static VALUE
string_to_r_internal(VALUE self)
{
    VALUE s, m;

    s = self;

    if (RSTRING_LEN(s) == 0)
	return rb_assoc_new(Qnil, self);

    m = f_match(rat_pat, s);

    if (!NIL_P(m)) {
	VALUE v, ifp, exp, ip, fp;
	VALUE si = f_aref(m, INT2FIX(1));
	VALUE nu = f_aref(m, INT2FIX(2));
	VALUE de = f_aref(m, INT2FIX(3));
	VALUE re = f_post_match(m);

	{
	    VALUE a;

	    a = f_split(nu, an_e_pat);
	    ifp = RARRAY_PTR(a)[0];
	    if (RARRAY_LEN(a) != 2)
		exp = Qnil;
	    else
		exp = RARRAY_PTR(a)[1];

	    a = f_split(ifp, a_dot_pat);
	    ip = RARRAY_PTR(a)[0];
	    if (RARRAY_LEN(a) != 2)
		fp = Qnil;
	    else
		fp = RARRAY_PTR(a)[1];
	}

	v = rb_rational_new1(f_to_i(ip));

	if (!NIL_P(fp)) {
	    char *p = StringValuePtr(fp);
	    long count = 0;
	    VALUE l;

	    while (*p) {
		if (rb_isdigit(*p))
		    count++;
		p++;
	    }

	    l = f_expt(INT2FIX(10), LONG2NUM(count));
	    v = f_mul(v, l);
	    v = f_add(v, f_to_i(fp));
	    v = f_div(v, l);
	}
	if (!NIL_P(si) && *StringValuePtr(si) == '-')
	    v = f_negate(v);
	if (!NIL_P(exp))
	    v = f_mul(v, f_expt(INT2FIX(10), f_to_i(exp)));
#if 0
	if (!NIL_P(de) && (!NIL_P(fp) || !NIL_P(exp)))
	    return rb_assoc_new(v, rb_usascii_str_new2("dummy"));
#endif
	if (!NIL_P(de))
	    v = f_div(v, f_to_i(de));

	return rb_assoc_new(v, re);
    }
    return rb_assoc_new(Qnil, self);
}

static VALUE
string_to_r_strict(VALUE self)
{
    VALUE a = string_to_r_internal(self);
    if (NIL_P(RARRAY_PTR(a)[0]) || RSTRING_LEN(RARRAY_PTR(a)[1]) > 0) {
	VALUE s = f_inspect(self);
	rb_raise(rb_eArgError, "invalid value for Rational: %s",
		 StringValuePtr(s));
    }
    return RARRAY_PTR(a)[0];
}

#define id_gsub rb_intern("gsub")
#define f_gsub(x,y,z) rb_funcall(x, id_gsub, 2, y, z)

static VALUE
string_to_r(VALUE self)
{
    VALUE s, a, backref;

    backref = rb_backref_get();
    rb_match_busy(backref);

    s = f_gsub(self, underscores_pat, an_underscore);
    a = string_to_r_internal(s);

    rb_backref_set(backref);

    if (!NIL_P(RARRAY_PTR(a)[0]))
	return RARRAY_PTR(a)[0];
    return rb_rational_new1(INT2FIX(0));
}

#define id_to_r rb_intern("to_r")
#define f_to_r(x) rb_funcall(x, id_to_r, 0)

static VALUE
nurat_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, backref;

    rb_scan_args(argc, argv, "11", &a1, &a2);

    switch (TYPE(a1)) {
      case T_COMPLEX:
	if (k_exact_p(RCOMPLEX(a1)->imag) && f_zero_p(RCOMPLEX(a1)->imag))
	    a1 = RCOMPLEX(a1)->real;
    }

    switch (TYPE(a2)) {
      case T_COMPLEX:
	if (k_exact_p(RCOMPLEX(a2)->imag) && f_zero_p(RCOMPLEX(a2)->imag))
	    a2 = RCOMPLEX(a2)->real;
    }

    backref = rb_backref_get();
    rb_match_busy(backref);

    switch (TYPE(a1)) {
      case T_FIXNUM:
      case T_BIGNUM:
	break;
      case T_FLOAT:
	a1 = f_to_r(a1);
	break;
      case T_STRING:
	a1 = string_to_r_strict(a1);
	break;
    }

    switch (TYPE(a2)) {
      case T_FIXNUM:
      case T_BIGNUM:
	break;
      case T_FLOAT:
	a2 = f_to_r(a2);
	break;
      case T_STRING:
	a2 = string_to_r_strict(a2);
	break;
    }

    rb_backref_set(backref);

    switch (TYPE(a1)) {
      case T_RATIONAL:
	if (argc == 1 || (k_exact_p(a2) && f_one_p(a2)))
	    return a1;
    }

    if (argc == 1) {
	if (k_numeric_p(a1) && !f_integer_p(a1))
	    return a1;
    }
    else {
	if ((k_numeric_p(a1) && k_numeric_p(a2)) &&
	    (!f_integer_p(a1) || !f_integer_p(a2)))
	    return f_div(a1, a2);
    }

    {
	VALUE argv2[2];
	argv2[0] = a1;
	argv2[1] = a2;
	return nurat_s_new(argc, argv2, klass);
    }
}

void
Init_Rational(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    assert(fprintf(stderr, "assert() is now active\n"));

    id_abs = rb_intern("abs");
    id_cmp = rb_intern("<=>");
    id_convert = rb_intern("convert");
    id_equal_p = rb_intern("==");
    id_expt = rb_intern("**");
    id_floor = rb_intern("floor");
    id_hash = rb_intern("hash");
    id_idiv = rb_intern("div");
    id_inspect = rb_intern("inspect");
    id_integer_p = rb_intern("integer?");
    id_negate = rb_intern("-@");
    id_to_f = rb_intern("to_f");
    id_to_i = rb_intern("to_i");
    id_to_s = rb_intern("to_s");
    id_truncate = rb_intern("truncate");

    ml = (long)(log(DBL_MAX) / log(2.0) - 1);

    rb_cRational = rb_define_class("Rational", rb_cNumeric);

    rb_define_alloc_func(rb_cRational, nurat_s_alloc);
    rb_undef_method(CLASS_OF(rb_cRational), "allocate");

#if 0
    rb_define_private_method(CLASS_OF(rb_cRational), "new!", nurat_s_new_bang, -1);
    rb_define_private_method(CLASS_OF(rb_cRational), "new", nurat_s_new, -1);
#else
    rb_undef_method(CLASS_OF(rb_cRational), "new");
#endif

    rb_define_global_function("Rational", nurat_f_rational, -1);

    rb_define_method(rb_cRational, "numerator", nurat_numerator, 0);
    rb_define_method(rb_cRational, "denominator", nurat_denominator, 0);

    rb_define_method(rb_cRational, "+", nurat_add, 1);
    rb_define_method(rb_cRational, "-", nurat_sub, 1);
    rb_define_method(rb_cRational, "*", nurat_mul, 1);
    rb_define_method(rb_cRational, "/", nurat_div, 1);
    rb_define_method(rb_cRational, "quo", nurat_div, 1);
    rb_define_method(rb_cRational, "fdiv", nurat_fdiv, 1);
    rb_define_method(rb_cRational, "**", nurat_expt, 1);

    rb_define_method(rb_cRational, "<=>", nurat_cmp, 1);
    rb_define_method(rb_cRational, "==", nurat_equal_p, 1);
    rb_define_method(rb_cRational, "coerce", nurat_coerce, 1);

    rb_define_method(rb_cRational, "div", nurat_idiv, 1);

#if 0 /* NUBY */
    rb_define_method(rb_cRational, "//", nurat_idiv, 1);
#endif

    rb_define_method(rb_cRational, "modulo", nurat_mod, 1);
    rb_define_method(rb_cRational, "%", nurat_mod, 1);
    rb_define_method(rb_cRational, "divmod", nurat_divmod, 1);

#if 0
    rb_define_method(rb_cRational, "quot", nurat_quot, 1);
#endif
    rb_define_method(rb_cRational, "remainder", nurat_rem, 1);
#if 0
    rb_define_method(rb_cRational, "quotrem", nurat_quotrem, 1);
#endif

    rb_define_method(rb_cRational, "abs", nurat_abs, 0);

#if 0
    rb_define_method(rb_cRational, "rational?", nurat_true, 0);
    rb_define_method(rb_cRational, "exact?", nurat_true, 0);
#endif

    rb_define_method(rb_cRational, "floor", nurat_floor, 0);
    rb_define_method(rb_cRational, "ceil", nurat_ceil, 0);
    rb_define_method(rb_cRational, "truncate", nurat_truncate, 0);
    rb_define_method(rb_cRational, "round", nurat_round, 0);

    rb_define_method(rb_cRational, "to_i", nurat_truncate, 0);
    rb_define_method(rb_cRational, "to_f", nurat_to_f, 0);
    rb_define_method(rb_cRational, "to_r", nurat_to_r, 0);

    rb_define_method(rb_cRational, "hash", nurat_hash, 0);

    rb_define_method(rb_cRational, "to_s", nurat_to_s, 0);
    rb_define_method(rb_cRational, "inspect", nurat_inspect, 0);

    rb_define_method(rb_cRational, "marshal_dump", nurat_marshal_dump, 0);
    rb_define_method(rb_cRational, "marshal_load", nurat_marshal_load, 1);

    /* --- */

    rb_define_method(rb_cInteger, "gcd", rb_gcd, 1);
    rb_define_method(rb_cInteger, "lcm", rb_lcm, 1);
    rb_define_method(rb_cInteger, "gcdlcm", rb_gcdlcm, 1);

    rb_define_method(rb_cNumeric, "numerator", numeric_numerator, 0);
    rb_define_method(rb_cNumeric, "denominator", numeric_denominator, 0);

    rb_define_method(rb_cInteger, "numerator", integer_numerator, 0);
    rb_define_method(rb_cInteger, "denominator", integer_denominator, 0);

    rb_define_method(rb_cFloat, "numerator", float_numerator, 0);
    rb_define_method(rb_cFloat, "denominator", float_denominator, 0);

    rb_define_method(rb_cNilClass, "to_r", nilclass_to_r, 0);
    rb_define_method(rb_cInteger, "to_r", integer_to_r, 0);
    rb_define_method(rb_cFloat, "to_r", float_to_r, 0);

    make_patterns();

    rb_define_method(rb_cString, "to_r", string_to_r, 0);

    rb_define_private_method(CLASS_OF(rb_cRational), "convert", nurat_s_convert, -1);
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
