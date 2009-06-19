/*
  rational.c: Coded by Tadayoshi Funaba 2008,2009

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

static ID id_abs, id_cmp, id_convert, id_equal_p, id_expt, id_fdiv,
    id_floor, id_idiv, id_inspect, id_integer_p, id_negate, id_to_f,
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

fun1(abs)
fun1(floor)
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
fun2(fdiv)
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

/*
 * call-seq:
 *   rat.numerator  =>  integer
 *
 * Returns the numerator of _rat_ as an +Integer+ object.
 *
 * For example:
 *
 *     Rational(7).numerator         #=> 7
 *     Rational(7, 1).numerator      #=> 7
 *     Rational(4.3, 40.3).numerator #=> 4841369599423283
 *     Rational(9, -4).numerator     #=> -9
 *     Rational(-2, -10).numerator   #=> 1
 */
static VALUE
nurat_numerator(VALUE self)
{
    get_dat1(self);
    return dat->num;
}

/*
 * call-seq:
 *   rat.denominator  =>  integer
 *
 * Returns the denominator of _rat_ as an +Integer+ object. If _rat_ was
 * created without an explicit denominator, +1+ is returned.
 *
 * For example:
 *
 *     Rational(7).denominator         #=> 1
 *     Rational(7, 1).denominator      #=> 1
 *     Rational(4.3, 40.3).denominator #=> 45373766245757744
 *     Rational(9, -4).denominator     #=> 4
 *     Rational(-2, -10).denominator   #=> 5
 */
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

/*
 * call-seq:
 *   rat + numeric  =>  numeric_result
 *
 * Performs addition. The class of the resulting object depends on
 * the class of _numeric_ and on the magnitude of the
 * result.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3)  + Rational(2, 3)  #=> (4/3)
 *     Rational(900)   + Rational(1)     #=> (900/1)
 *     Rational(-2, 9) + Rational(-9, 2) #=> (-85/18)
 *     Rational(9, 8)  + 4               #=> (41/8)
 *     Rational(20, 9) + 9.8             #=> 12.022222222222222
 *     Rational(8, 7)  + 2**20           #=> (7340040/7)
 */

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

/*
 * call-seq:
 *   rat - numeric  =>  numeric_result
 *
 * Performs subtraction. The class of the resulting object depends on the
 * class of _numeric_ and on the magnitude of the result.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3)  - Rational(2, 3)  #=> (0/1)
 *     Rational(900)   - Rational(1)     #=> (899/1)
 *     Rational(-2, 9) - Rational(-9, 2) #=> (77/18)
 *     Rational(9, 8)  - 4               #=> (23/8)
 *     Rational(20, 9) - 9.8             #=> -7.577777777777778
 *     Rational(8, 7)  - 2**20           #=> (-7340024/7)
 */
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

/*
 * call-seq:
 *   rat * numeric  =>  numeric_result
 *
 * Performs multiplication. The class of the resulting object depends on
 * the class of _numeric_ and on the magnitude of the result.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3)  * Rational(2, 3)  #=> (4/9)
 *     Rational(900)   * Rational(1)     #=> (900/1)
 *     Rational(-2, 9) * Rational(-9, 2) #=> (1/1)
 *     Rational(9, 8)  * 4               #=> (9/2)
 *     Rational(20, 9) * 9.8             #=> 21.77777777777778
 *     Rational(8, 7)  * 2**20           #=> (8388608/7)
 */
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

/*
 * call-seq:
 *   rat / numeric     =>  numeric_result
 *   rat.quo(numeric)  =>  numeric_result
 *
 * Performs division. The class of the resulting object depends on the class
 * of _numeric_ and on the magnitude of the result.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object. A
 * +ZeroDivisionError+ is raised if _numeric_ is 0.
 *
 * For example:
 *
 *    Rational(2, 3)  / Rational(2, 3)  #=> (1/1)
 *    Rational(900)   / Rational(1)     #=> (900/1)
 *    Rational(-2, 9) / Rational(-9, 2) #=> (4/81)
 *    Rational(9, 8)  / 4               #=> (9/32)
 *    Rational(20, 9) / 9.8             #=> 0.22675736961451246
 *    Rational(8, 7)  / 2**20           #=> (1/917504)
 *    Rational(2, 13) / 0               #=> ZeroDivisionError: divided by zero
 *    Rational(2, 13) / 0.0             #=> Infinity
 */
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

/*
 * call-seq:
 *   rat.fdiv(numeric)  =>  float
 *
 * Performs float division: dividing _rat_ by _numeric_. The return value is a
 * +Float+ object.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3).fdiv(1)      #=> 0.6666666666666666
 *     Rational(2, 3).fdiv(0.5)    #=> 1.3333333333333333
 *     Rational(2).fdiv(3)         #=> 0.6666666666666666
 *     Rational(-9, 6.6).fdiv(6.6) #=> -0.20661157024793392
 *     Rational(-20).fdiv(0.0)     #=> -Infinity
 */
static VALUE
nurat_fdiv(VALUE self, VALUE other)
{
    return f_to_f(f_div(self, other));
}

/*
 * call-seq:
 *   rat ** numeric  =>  numeric_result
 *
 * Performs exponentiation, i.e. it raises _rat_ to the exponent _numeric_.
 * The class of the resulting object depends on the class of _numeric_ and on
 * the magnitude of the result. A +TypeError+ is raised unless _numeric_ is a
 * +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3)  ** Rational(2, 3)  #=> 0.7631428283688879
 *     Rational(900)   ** Rational(1)     #=> (900/1)
 *     Rational(-2, 9) ** Rational(-9, 2) #=> (4.793639101185069e-13-869.8739233809262i)
 *     Rational(9, 8)  ** 4               #=> (6561/4096)
 *     Rational(20, 9) ** 9.8             #=> 2503.325740344559
 *     Rational(3, 2)  ** 2**3            #=> (6561/256)
 *     Rational(2, 13) ** 0               #=> (1/1)
 *     Rational(2, 13) ** 0.0             #=> 1.0
 */
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
	if (f_negative_p(self))
	    return f_expt(rb_complex_new1(self), other); /* explicitly */
	return f_expt(f_to_f(self), other);
      default:
	return rb_num_coerce_bin(self, other, id_expt);
    }
}

/*
 * call-seq:
 *   rat <=> numeric  =>  -1, 0, +1
 *
 * Performs comparison. Returns -1, 0, or +1 depending on whether _rat_ is
 * less than, equal to, or greater than _numeric_. This is the basis for the
 * tests in +Comparable+.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(2, 3)  <=> Rational(2, 3)  #=> 0
 *     Rational(5)     <=> 5               #=> 0
 *     Rational(900)   <=> Rational(1)     #=> 1
 *     Rational(-2, 9) <=> Rational(-9, 2) #=> 1
 *     Rational(9, 8)  <=> 4               #=> -1
 *     Rational(20, 9) <=> 9.8             #=> -1
 *     Rational(5, 3)  <=> 'string'        #=> TypeError: String can't
 *                                         #   be coerced into Rational
 */
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

/*
 * call-seq:
 *   rat == numeric  =>  +true+ or +false+
 *
 * Tests for equality. Returns +true+ if _rat_ is equal to _numeric_; +false+
 * otherwise.
 *
 * For example:
 *
 *     Rational(2, 3)  == Rational(2, 3)  #=> +true+
 *     Rational(5)     == 5               #=> +true+
 *     Rational(7, 1)  == Rational(7)     #=> +true+
 *     Rational(-2, 9) == Rational(-9, 2) #=> +false+
 *     Rational(9, 8)  == 4               #=> +false+
 *     Rational(5, 3)  == 'string'        #=> +false+
 */
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

/*
 * call-seq:
 *   rat.div(numeric)  =>  integer
 *
 * Uses +/+ to divide _rat_ by _numeric_, then returns the floor of the result
 * as an +Integer+ object.
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object. A
 * +ZeroDivisionError+ is raised if _numeric_ is 0. A +FloatDomainError+ is
 * raised if _numeric_ is 0.0.
 *
 * For example:
 *
 *     Rational(2, 3).div(Rational(2, 3))   #=> 1
 *     Rational(-2, 9).div(Rational(-9, 2)) #=> 0
 *     Rational(3, 4).div(0.1)              #=> 7
 *     Rational(-9).div(9.9)                #=> -1
 *     Rational(3.12).div(0.5)              #=> 6
 *     Rational(200, 51).div(0)             #=> ZeroDivisionError:
 *                                          #   divided by zero
 */
static VALUE
nurat_idiv(VALUE self, VALUE other)
{
    return f_floor(f_div(self, other));
}

/*
 * call-seq:
 *   rat.modulo(numeric)  =>  numeric
 *   rat % numeric        =>  numeric
 *
 * Returns the modulo of _rat_ and _numeric_ as a +Numeric+ object.
 *
 *     x.modulo(y) means x-y*(x/y).floor
 *
 * A +TypeError+ is raised unless _numeric_ is a +Numeric+ object. A
 * +ZeroDivisionError+ is raised if _numeric_ is 0. A +FloatDomainError+ is
 * raised if _numeric_ is 0.0.
 *
 * For example:
 *
 *     Rational(2, 3)  % Rational(2, 3)  #=> (0/1)
 *     Rational(2)     % Rational(300)   #=> (2/1)
 *     Rational(-2, 9) % Rational(9, -2) #=> (-2/9)
 *     Rational(8.2)   % 3.2             #=> 1.799999999999999
 *     Rational(198.1) % 2.3e3           #=> 198.1
 *     Rational(2, 5)  % 0.0             #=> FloatDomainError: Infinity
 */
static VALUE
nurat_mod(VALUE self, VALUE other)
{
    VALUE val = f_floor(f_div(self, other));
    return f_sub(self, f_mul(other, val));
}

/*
 * call-seq:
 *   rat.divmod(numeric)  =>  array
 *
 * Returns a two-element +Array+ containing the quotient and modulus obtained
 * by dividing _rat_ by _numeric_. Both elements are +Numeric+.
 *
 * A +ZeroDivisionError+ is raised if _numeric_ is 0. A +FloatDomainError+ is
 * raised if _numeric_ is 0.0. A +TypeError+ is raised unless _numeric_ is a
 * +Numeric+ object.
 *
 * For example:
 *
 *     Rational(3).divmod(3)                   #=> [1, (0/1)]
 *     Rational(4).divmod(3)                   #=> [1, (1/1)]
 *     Rational(5).divmod(3)                   #=> [1, (2/1)]
 *     Rational(6).divmod(3)                   #=> [2, (0/1)]
 *     Rational(2, 3).divmod(Rational(2, 3))   #=> [1, (0/1)]
 *     Rational(-2, 9).divmod(Rational(9, -2)) #=> [0, (-2/9)]
 *     Rational(11.5).divmod(Rational(3.5))    #=> [3, (1/1)]
 */
static VALUE
nurat_divmod(VALUE self, VALUE other)
{
    VALUE val = f_floor(f_div(self, other));
    return rb_assoc_new(val, f_sub(self, f_mul(other, val)));
}

#if 0
/* :nodoc: */
static VALUE
nurat_quot(VALUE self, VALUE other)
{
    return f_truncate(f_div(self, other));
}
#endif

/*
 * call-seq:
 *   rat.remainder(numeric)  =>  numeric_result
 *
 * Returns the remainder of dividing _rat_ by _numeric_ as a +Numeric+ object.
 *
 *     x.remainder(y) means x-y*(x/y).truncate
 *
 * A +ZeroDivisionError+ is raised if _numeric_ is 0. A +FloatDomainError+ is
 * raised if the result is Infinity or NaN, or _numeric_ is 0.0. A +TypeError+
 * is raised unless _numeric_ is a +Numeric+ object.
 *
 * For example:
 *
 *     Rational(3, 4).remainder(Rational(3))   #=> (3/4)
 *     Rational(12,13).remainder(-8)           #=> (12/13)
 *     Rational(2,3).remainder(-Rational(3,2)) #=> (2/3)
 *     Rational(-5,7).remainder(7.1)           #=> -0.7142857142857143
 *     Rational(1).remainder(0)                # ZeroDivisionError:
 *                                             # divided by zero
 */
static VALUE
nurat_rem(VALUE self, VALUE other)
{
    VALUE val = f_truncate(f_div(self, other));
    return f_sub(self, f_mul(other, val));
}

#if 0
/* :nodoc: */
static VALUE
nurat_quotrem(VALUE self, VALUE other)
{
    VALUE val = f_truncate(f_div(self, other));
    return rb_assoc_new(val, f_sub(self, f_mul(other, val)));
}
#endif

#if 0
/* :nodoc: */
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


/*
 * call-seq:
 *   rat.to_i  =>  integer
 *
 * Returns _rat_ truncated to an integer as an +Integer+ object.
 *
 *  Equivalent to
 *  <i>rat</i>.<code>truncate(</code>.
 *
 * For example:
 *
 *   Rational(2, 3).to_i   #=> 0
 *   Rational(3).to_i      #=> 3
 *   Rational(300.6).to_i  #=> 300
 *   Rational(98,71).to_i  #=> 1
 *   Rational(-30,2).to_i  #=> -15
 */
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
    VALUE num, den, neg;

    get_dat1(self);

    num = dat->num;
    den = dat->den;
    neg = f_negative_p(num);

    if (neg)
	num = f_negate(num);

    num = f_add(f_mul(num, TWO), den);
    den = f_mul(den, TWO);
    num = f_idiv(num, den);

    if (neg)
	num = f_negate(num);

    return num;
}

static VALUE
nurat_round_common(int argc, VALUE *argv, VALUE self,
		   VALUE (*func)(VALUE))
{
    VALUE n, b, s;

    if (argc == 0)
	return (*func)(self);

    rb_scan_args(argc, argv, "01", &n);

    if (!k_integer_p(n))
	rb_raise(rb_eTypeError, "not an integer");

    b = f_expt(INT2FIX(10), n);
    s = f_mul(self, b);

    s = (*func)(s);

    s = f_div(f_rational_new_bang1(CLASS_OF(self), s), b);

    if (f_lt_p(n, ONE))
	s = f_to_i(s);

    return s;
}

/*
 * call-seq:
 *   rat.floor               =>  integer
 *   rat.floor(precision=0)  =>  numeric
 *
 * Returns the largest integer less than or equal to _rat_ as an +Integer+
 * object. Contrast with +Rational#ceil+.
 *
 * An optional _precision_ argument can be supplied as an +Integer+. If
 * _precision_ is positive the result is rounded downwards to that number of
 * decimal places. If _precision_ is negative, the result is rounded downwards
 * to the nearest 10**_precision_. By default _precision_ is equal to 0,
 * causing the result to be a whole number.
 *
 * For example:
 *
 *     Rational(2, 3).floor    #=> 0
 *     Rational(3).floor       #=> 3
 *     Rational(300.6).floor   #=> 300
 *     Rational(98,71).floor   #=> 1
 *     Rational(-30,2).floor   #=> -15
 *     Rational(-30,-11).floor #=> 2
 *
 *     Rational(-1.125).floor(2).to_f  #=> -1.13
 *     Rational(-1.125).floor(1).to_f  #=> -1.2
 *     Rational(-1.125).floor.to_f     #=> -2.0
 *     Rational(-1.125).floor(-1).to_f #=> -10.0
 *     Rational(-1.125).floor(-2).to_f #=> -100.0
 */
static VALUE
nurat_floor_n(int argc, VALUE *argv, VALUE self)
{
    return nurat_round_common(argc, argv, self, nurat_floor);
}

/*
 * call-seq:
 *   rat.ceil               =>  integer
 *   rat.ceil(precision=0)  =>  numeric
 *
 * Returns the smallest integer greater than or equal to _rat_ as an +Integer+
 * object. Contrast with +Rational#floor+.
 *
 * An optional _precision_ argument can be supplied as an +Integer+. If
 * _precision_ is positive the result is rounded upwards to that number of
 * decimal places. If _precision_ is negative, the result is rounded upwards
 * to the nearest 10**_precision_. By default _precision_ is equal to 0,
 * causing the result to be a whole number.
 *
 * For example:
 *
 *     Rational(2, 3).ceil    #=> 1
 *     Rational(3).ceil       #=> 3
 *     Rational(300.6).ceil   #=> 301
 *     Rational(98, 71).ceil  #=> 2
 *     Rational(-30, 2).ceil  #=> -15
 *     Rational(-30,-11).ceil #=> 3
 *
 *     Rational(-1.125).ceil(2).to_f  #=> -1.12
 *     Rational(-1.125).ceil(1).to_f  #=> -1.1
 *     Rational(-1.125).ceil.to_f     #=> -1.0
 *     Rational(-1.125).ceil(-1).to_f #=> 0.0
 *     Rational(-1.125).ceil(-2).to_f #=> 0.0
 */
static VALUE
nurat_ceil_n(int argc, VALUE *argv, VALUE self)
{
    return nurat_round_common(argc, argv, self, nurat_ceil);
}

/*
 * call-seq:
 *   rat.truncate               =>  integer
 *   rat.truncate(precision=0)  =>  numeric
 *
 * Truncates self to an integer and returns the result as an +Integer+ object.
 *
 * An optional _precision_ argument can be supplied as an +Integer+. If
 * _precision_ is positive the result is rounded downwards to that number of
 * decimal places. If _precision_ is negative, the result is rounded downwards
 * to the nearest 10**_precision_. By default _precision_ is equal to 0,
 * causing the result to be a whole number.
 *
 * For example:
 *
 *     Rational(2, 3).truncate     #=> 0
 *     Rational(3).truncate        #=> 3
 *     Rational(300.6).truncate    #=> 300
 *     Rational(98,71).truncate    #=> 1
 *     Rational(-30,2).truncate    #=> -15
 *     Rational(-30, -11).truncate #=> 2
 *
 *     Rational(-123.456).truncate(2).to_f  #=> -123.45
 *     Rational(-123.456).truncate(1).to_f  #=> -123.4
 *     Rational(-123.456).truncate.to_f     #=> -123.0
 *     Rational(-123.456).truncate(-1).to_f #=> -120.0
 *     Rational(-123.456).truncate(-2).to_f #=> -100.0
 */
static VALUE
nurat_truncate_n(int argc, VALUE *argv, VALUE self)
{
    return nurat_round_common(argc, argv, self, nurat_truncate);
}

/*
 * call-seq:
 *   rat.round               =>  integer
 *   rat.round(precision=0)  =>  numeric
 *
 * Rounds _rat_ to an integer, and returns the result as an +Integer+ object.
 *
 * An optional _precision_ argument can be supplied as an +Integer+. If
 * _precision_ is positive the result is rounded to that number of decimal
 * places. If _precision_ is negative, the result is rounded to the nearest
 * 10**_precision_. By default _precision_ is equal to 0, causing the result
 * to be a whole number.
 *
 * A +TypeError+ is raised if _integer_ is given and not an +Integer+ object.
 *
 * For example:
 *
 *     Rational(9, 3.3).round    #=> 3
 *     Rational(9, 3.3).round(1) #=> (27/10)
 *     Rational(9,3.3).round(2)  #=> (273/100)
 *     Rational(8, 7).round(5)   #=> (57143/50000)
 *     Rational(-20, -3).round   #=> 7
 *
 *     Rational(-123.456).round(2).to_f  #=> -123.46
 *     Rational(-123.456).round(1).to_f  #=> -123.5
 *     Rational(-123.456).round.to_f     #=> -123.0
 *     Rational(-123.456).round(-1).to_f #=> -120.0
 *     Rational(-123.456).round(-2).to_f #=> -100.0
 *
 */
static VALUE
nurat_round_n(int argc, VALUE *argv, VALUE self)
{
    return nurat_round_common(argc, argv, self, nurat_round);
}

/*
 * call-seq:
 *   rat.to_f  =>  float
 *
 * Converts _rat_ to a floating point number and returns the result as a
 * +Float+ object.
 *
 * For example:
 *
 *     Rational(2).to_f      #=> 2.0
 *     Rational(9, 4).to_f   #=> 2.25
 *     Rational(-3, 4).to_f  #=> -0.75
 *     Rational(20, 3).to_f  #=> 6.666666666666667
 */
static VALUE
nurat_to_f(VALUE self)
{
    get_dat1(self);
    return f_fdiv(dat->num, dat->den);
}

/*
 * call-seq:
 *   rat.to_r  =>  self
 *
 * Returns self, i.e. a +Rational+ object representing _rat_.
 *
 * For example:
 *
 *     Rational(2).to_r      #=> (2/1)
 *     Rational(-8, 6).to_r  #=> (-4/3)
 *     Rational(39.2).to_r   #=> (2758454771764429/70368744177664)
 */
static VALUE
nurat_to_r(VALUE self)
{
    return self;
}

static VALUE
nurat_hash(VALUE self)
{
    long v, h[3];
    VALUE n;

    get_dat1(self);
    h[0] = rb_hash(rb_obj_class(self));
    n = rb_hash(dat->num);
    h[1] = NUM2LONG(n);
    n = rb_hash(dat->den);
    h[2] = NUM2LONG(n);
    v = rb_memhash(h, sizeof(h));
    return LONG2FIX(v);
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

/*
 * call-seq:
 *   rat.to_s  =>  string
 *
 * Returns a +String+ representation of _rat_ in the form
 * "_numerator_/_denominator_".
 *
 * For example:
 *
 *     Rational(2).to_s      #=> "2/1"
 *     Rational(-8, 6).to_s  #=> "-4/3"
 *     Rational(0.5).to_s    #=> "1/2"
 */
static VALUE
nurat_to_s(VALUE self)
{
    return nurat_format(self, f_to_s);
}

/*
 * call-seq:
 *   rat.inspect  =>  string
 *
 * Returns a +String+ containing a human-readable representation of _rat_ in
 * the form "(_numerator_/_denominator_)".
 *
 * For example:
 *
 *     Rational(2).to_s      #=> "(2/1)"
 *     Rational(-8, 6).to_s  #=> "(-4/3)"
 *     Rational(0.5).to_s    #=> "(1/2)"
 */
static VALUE
nurat_inspect(VALUE self)
{
    VALUE s;

    s = rb_usascii_str_new2("(");
    rb_str_concat(s, nurat_format(self, f_inspect));
    rb_str_cat2(s, ")");

    return s;
}

/* :nodoc: */
static VALUE
nurat_marshal_dump(VALUE self)
{
    VALUE a;
    get_dat1(self);

    a = rb_assoc_new(dat->num, dat->den);
    rb_copy_generic_ivar(a, self);
    return a;
}

/* :nodoc: */
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

/*
 * call-seq:
 *   int.gcd(_int2_)  =>  integer
 *
 * Returns the greatest common divisor of _int_ and _int2_: the largest
 * positive integer that divides the two without a remainder. The result is an
 * +Integer+ object.
 *
 * An +ArgumentError+ is raised unless _int2_ is an +Integer+ object.
 *
 * For example:
 *
 *     2.gcd(2)      #=> 2
 *     -2.gcd(2)     #=> 2
 *     8.gcd(6)      #=> 2
 *     25.gcd(5)     #=> 5
 */
VALUE
rb_gcd(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_gcd(self, other);
}

/*
 * call-seq:
 *   int.lcm(_int2_)  =>  integer
 *
 * Returns the least common multiple (or "lowest common multiple") of _int_
 * and _int2_: the smallest positive integer that is a multiple of both
 * integers. The result is an +Integer+ object.
 *
 * An +ArgumentError+ is raised unless _int2_ is an +Integer+ object.
 *
 * For example:
 *
 *     2.lcm(2)      #=> 2
 *     -2.gcd(2)     #=> 2
 *     8.gcd(6)      #=> 24
 *     8.lcm(9)      #=> 72
 */
VALUE
rb_lcm(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_lcm(self, other);
}

/*
 * call-seq:
 *   int.gcdlcm(_int2_)  =>  array
 *
 * Returns a two-element +Array+ containing _int_.gcd(_int2_) and
 * _int_.lcm(_int2_) respectively. That is, the greatest common divisor of
 * _int_ and _int2_, then the least common multiple of _int_ and _int2_. Both
 * elements are +Integer+ objects.
 *
 * An +ArgumentError+ is raised unless _int2_ is an +Integer+ object.
 *
 * For example:
 *
 *     2.gcdlcm(2)      #=> [2, 2]
 *     -2.gcdlcm(2)     #=> [2, 2]
 *     8.gcdlcm(6)      #=> [2, 24]
 *     8.gcdlcm(9)      #=> [1, 72]
 *     9.gcdlcm(9**9)   #=> [9, 387420489]
 */
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

/*
 * call-seq:
 *   num.numerator  =>  integer
 *
 * Returns the numerator of _num_ as an +Integer+ object.
 */
static VALUE
numeric_numerator(VALUE self)
{
    return f_numerator(f_to_r(self));
}

/*
 * call-seq:
 *   num.denominator  =>  integer
 *
 * Returns the denominator of _num_ as an +Integer+ object.
 */
static VALUE
numeric_denominator(VALUE self)
{
    return f_denominator(f_to_r(self));
}

/*
 * call-seq:
 *   int.numerator  =>  self
 *
 * Returns self.
 */
static VALUE
integer_numerator(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *   int.numerator  =>  1
 *
 * Returns 1.
 */
static VALUE
integer_denominator(VALUE self)
{
    return INT2FIX(1);
}

/*
 * call-seq:
 *   flo.numerator  =>  integer
 *
 * Returns the numerator of _flo_ as an +Integer+ object.
 *
 * For example:
 *
 *     n = 0.3.numerator   #=> 5404319552844595  # machine dependent
 *     d = 0.3.denominator #=> 18014398509481984 # machine dependent
 *     n.fdiv(d)           #=> 0.3
 */
static VALUE
float_numerator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return self;
    return rb_call_super(0, 0);
}

/*
 * call-seq:
 *   flo.denominator  =>  integer
 *
 * Returns the denominator of _flo_ as an +Integer+ object.
 *
 * See Float#numerator.
 */
static VALUE
float_denominator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return INT2FIX(1);
    return rb_call_super(0, 0);
}

/*
 * call-seq:
 *   nil.to_r  =>  Rational(0, 1)
 *
 * Returns a +Rational+ object representing _nil_ as a rational number.
 *
 * For example:
 *
 *     nil.to_r    #=> (0/1)
 */
static VALUE
nilclass_to_r(VALUE self)
{
    return rb_rational_new1(INT2FIX(0));
}

/*
 * call-seq:
 *   int.to_r  =>  rational
 *
 * Returns a +Rational+ object representing _int_ as a rational number.
 *
 * For example:
 *
 *     1.to_r    #=> (1/1)
 *     12.to_r   #=> (12/1)
 */
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

/*
 * call-seq:
 *   flt.to_r  =>  rational
 *
 * Returns _flt_ as an +Rational+ object. Raises a +FloatDomainError+ if _flt_
 * is +Infinity+ or +NaN+.
 *
 * For example:
 *
 *     2.0.to_r      #=> (2/1)
 *     2.5.to_r      #=> (5/2)
 *     -0.75.to_r    #=> (-3/4)
 *     0.0.to_r      #=> (0/1)
 *     (1/0.0).to_r  #=> FloatDomainError: Infinity
 */
static VALUE
float_to_r(VALUE self)
{
    VALUE f, n;

    float_decode_internal(self, &f, &n);
    return f_mul(f, f_expt(INT2FIX(FLT_RADIX), n));
}

static VALUE rat_pat, an_e_pat, a_dot_pat, underscores_pat, an_underscore;

#define WS "\\s*"
#define DIGITS "(?:\\d(?:_\\d|\\d)*)"
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
	rb_raise(rb_eArgError, "invalid value for convert(): %s",
		 StringValuePtr(s));
    }
    return RARRAY_PTR(a)[0];
}

#define id_gsub rb_intern("gsub")
#define f_gsub(x,y,z) rb_funcall(x, id_gsub, 2, y, z)

/*
 * call-seq:
 *   str.to_r  =>  rational
 *
 * Returns a +Rational+ object representing _string_ as a rational number.
 * Leading and trailing whitespace is ignored. Underscores may be used to
 * separate numbers. If _string_ is not recognised as a rational, (0/1) is
 * returned.
 *
 * For example:
 *
 *     "2".to_r      #=> (2/1)
 *     "300/2".to_r  #=> (150/1)
 *     "-9.2/3".to_r #=> (-46/15)
 *     "  2/9 ".to_r #=> (2/9)
 *     "2_9".to_r    #=> (29/1)
 *     "?".to_r      #=> (0/1)
 */
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

    if (NIL_P(a1) || (argc == 2 && NIL_P(a2)))
	rb_raise(rb_eTypeError, "can't convert nil into Rational");

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
	if (!(k_numeric_p(a1) && k_integer_p(a1)))
	    return rb_convert_type(a1, T_RATIONAL, "Rational", "to_r");
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

/*
 * A +Rational+ object represents a rational number, which is any number that
 * can be expressed as the quotient a/b of two integers (where the denominator
 * is nonzero). Given that b may be equal to 1, every integer is rational.
 *
 * A +Rational+ object can be created with the +Rational()+ constructor:
 *
 *     Rational(1)      #=> (1/1)
 *     Rational(2, 3)   #=> (2/3)
 *     Rational(0.5)    #=> (1/2)
 *     Rational("2/7")  #=> (2/7)
 *     Rational("0.25") #=> (1/4)
 *     Rational(10e3)   #=> (10000/1)
 *
 * The first argument is the numerator, the second the denominator. If the
 * denominator is not supplied it defaults to 1. The arguments can be
 * +Numeric+ or +String+ objects.
 *
 *     Rational(12) == Rational(12, 1) #=> true
 *
 * A +ZeroDivisionError+ will be raised if 0 is specified as the denominator:
 *
 *     Rational(3, 0)  #=> ZeroDivisionError: divided by zero
 *
 * The numerator and denominator of a +Rational+ object can be retrieved with
 * the +Rational#numerator+ and +Rational#denominator+ accessors,
 * respectively.
 *
 *     rational = Rational(4, 7)  #=> (4/7)
 *     rational.numerator         #=> 4
 *     rational.denominator       #=> 7
 *
 * A +Rational+ is automatically reduced into its simplest form:
 *
 *     Rational(10, 2)            #=> (5/1)
 *
 * +Numeric+ and +String+ objects can be converted into a +Rational+ with
 * their +#to_r+ methods.
 *
 *     30.to_r          #=> (30/1)
 *     3.33.to_r        #=> (1874623344892969/562949953421312)
 *     '33/3'.to_r      #=> (11/1)
 *
 * The reverse operations work as you would expect:
 *
 *     Rational(30, 1).to_i                              #=> 30
 *     Rational(1874623344892969, 562949953421312).to_f  #=> 3.33
 *     Rational(11, 1).to_s                              #=> "11/1"
 *
 * +Rational+ objects can be compared with other +Numeric+ objects using the
 * normal semantics:
 *
 *     Rational(20, 10) == Rational(2, 1) #=> true
 *     Rational(10) > Rational(1)         #=> true
 *     Rational(9, 2) <=> Rational(8, 3)  #=> 1
 *
 * Similarly, standard mathematical operations support +Rational+ objects, too:
 *
 *     Rational(9, 2) * 2                #=> (9/1)
 *     Rational(12, 29) / Rational(2,3)  #=> (18/29)
 *     Rational(7,5) + Rational(60)      #=> (307/5)
 *     Rational(22, 5) - Rational(5, 22) #=> (459/110)
 *     Rational(2,3) ** 3                #=> (8/27)
 */
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
    id_fdiv = rb_intern("fdiv");
    id_floor = rb_intern("floor");
    id_idiv = rb_intern("div");
    id_inspect = rb_intern("inspect");
    id_integer_p = rb_intern("integer?");
    id_negate = rb_intern("-@");
    id_to_f = rb_intern("to_f");
    id_to_i = rb_intern("to_i");
    id_to_s = rb_intern("to_s");
    id_truncate = rb_intern("truncate");

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

#if 0
    rb_define_method(rb_cRational, "rational?", nurat_true, 0);
    rb_define_method(rb_cRational, "exact?", nurat_true, 0);
#endif

    rb_define_method(rb_cRational, "floor", nurat_floor_n, -1);
    rb_define_method(rb_cRational, "ceil", nurat_ceil_n, -1);
    rb_define_method(rb_cRational, "truncate", nurat_truncate_n, -1);
    rb_define_method(rb_cRational, "round", nurat_round_n, -1);

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
