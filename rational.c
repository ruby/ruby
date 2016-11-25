/*
  rational.c: Coded by Tadayoshi Funaba 2008-2012

  This implementation is based on Keiju Ishitsuka's Rational library
  which is written in ruby.
*/

#include "internal.h"
#include <math.h>
#include <float.h>

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#define NDEBUG
#include "ruby_assert.h"

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
#define USE_GMP
#include <gmp.h>
#endif

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)

#define GMP_GCD_DIGITS 1

#define INT_POSITIVE_P(x) (FIXNUM_P(x) ? FIXNUM_POSITIVE_P(x) : BIGNUM_POSITIVE_P(x))
#define INT_ZERO_P(x) (FIXNUM_P(x) ? FIXNUM_ZERO_P(x) : rb_bigzero_p(x))

VALUE rb_cRational;

static ID id_abs, id_idiv, id_integer_p, id_to_i,
    id_i_num, id_i_den;

#define f_boolcast(x) ((x) ? Qtrue : Qfalse)
#define f_inspect rb_inspect
#define f_to_s rb_obj_as_string

#define binop(n,op) \
inline static VALUE \
f_##n(VALUE x, VALUE y)\
{\
  return rb_funcall(x, (op), 1, y);\
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
    if (FIXNUM_P(y) && FIXNUM_ZERO_P(y))
	return x;
    else if (FIXNUM_P(x) && FIXNUM_ZERO_P(x))
	return y;
    return rb_funcall(x, '+', 1, y);
}

inline static VALUE
f_div(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIX2LONG(y) == 1)
	return x;
    if (RB_INTEGER_TYPE_P(x))
	return rb_int_div(x, y);
    return rb_funcall(x, '/', 1, y);
}

inline static int
f_lt_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return (SIGNED_VALUE)x < (SIGNED_VALUE)y;
    return RTEST(rb_funcall(x, '<', 1, y));
}

#ifndef NDEBUG
/* f_mod is used only in f_gcd defined when NDEBUG is not defined */
binop(mod, '%')
#endif

inline static VALUE
f_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	long iy = FIX2LONG(y);
	if (iy == 0) {
	    if (RB_INTEGER_TYPE_P(x))
		return ZERO;
	}
	else if (iy == 1)
	    return x;
    }
    else if (FIXNUM_P(x)) {
	long ix = FIX2LONG(x);
	if (ix == 0) {
	    if (RB_INTEGER_TYPE_P(y))
		return ZERO;
	}
	else if (ix == 1)
	    return y;
	return rb_int_mul(x, y);
    }
    else if (RB_TYPE_P(x, T_BIGNUM))
	return rb_int_mul(x, y);
    return rb_funcall(x, '*', 1, y);
}

inline static VALUE
f_sub(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIXNUM_ZERO_P(y))
	return x;
    return rb_funcall(x, '-', 1, y);
}

inline static VALUE
f_abs(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x))
	return rb_int_abs(x);
    return rb_funcall(x, id_abs, 0);
}

fun1(integer_p)

inline static VALUE
f_to_i(VALUE x)
{
    if (RB_TYPE_P(x, T_STRING))
	return rb_str_to_inum(x, 10, 0);
    return rb_funcall(x, id_to_i, 0);
}

inline static VALUE
f_eqeq_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return x == y;
    return (int)rb_equal(x, y);
}

fun2(idiv)

#define f_expt10(x) rb_int_pow(INT2FIX(10), x)

inline static int
f_zero_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
	return FIXNUM_ZERO_P(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
	VALUE num = RRATIONAL(x)->num;

	return FIXNUM_ZERO_P(num);
    }
    return (int)rb_equal(x, ZERO);
}

#define f_nonzero_p(x) (!f_zero_p(x))

inline static int
f_one_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
	return x == LONG2FIX(1);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
	VALUE num = RRATIONAL(x)->num;
	VALUE den = RRATIONAL(x)->den;

	return num == LONG2FIX(1) && den == LONG2FIX(1);
    }
    return (int)rb_equal(x, ONE);
}

inline static int
f_minus_one_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
	return x == LONG2FIX(-1);
    }
    else if (RB_TYPE_P(x, T_BIGNUM)) {
	return Qfalse;
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
	VALUE num = RRATIONAL(x)->num;
	VALUE den = RRATIONAL(x)->den;

	return num == LONG2FIX(-1) && den == LONG2FIX(1);
    }
    return (int)rb_equal(x, INT2FIX(-1));
}

inline static int
f_kind_of_p(VALUE x, VALUE c)
{
    return (int)rb_obj_is_kind_of(x, c);
}

inline static int
k_numeric_p(VALUE x)
{
    return f_kind_of_p(x, rb_cNumeric);
}

inline static int
k_integer_p(VALUE x)
{
    return RB_INTEGER_TYPE_P(x);
}

inline static int
k_float_p(VALUE x)
{
    return RB_FLOAT_TYPE_P(x);
}

inline static int
k_rational_p(VALUE x)
{
    return RB_TYPE_P(x, T_RATIONAL);
}

#define k_exact_p(x) (!k_float_p(x))
#define k_inexact_p(x) k_float_p(x)

#define k_exact_zero_p(x) (k_exact_p(x) && f_zero_p(x))
#define k_exact_one_p(x) (k_exact_p(x) && f_one_p(x))

#ifdef USE_GMP
VALUE
rb_gcd_gmp(VALUE x, VALUE y)
{
    const size_t nails = (sizeof(BDIGIT)-SIZEOF_BDIGIT)*CHAR_BIT;
    mpz_t mx, my, mz;
    size_t count;
    VALUE z;
    long zn;

    mpz_init(mx);
    mpz_init(my);
    mpz_init(mz);
    mpz_import(mx, BIGNUM_LEN(x), -1, sizeof(BDIGIT), 0, nails, BIGNUM_DIGITS(x));
    mpz_import(my, BIGNUM_LEN(y), -1, sizeof(BDIGIT), 0, nails, BIGNUM_DIGITS(y));

    mpz_gcd(mz, mx, my);

    zn = (mpz_sizeinbase(mz, 16) + SIZEOF_BDIGIT*2 - 1) / (SIZEOF_BDIGIT*2);
    z = rb_big_new(zn, 1);
    mpz_export(BIGNUM_DIGITS(z), &count, -1, sizeof(BDIGIT), 0, nails, mz);

    return rb_big_norm(z);
}
#endif

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
f_gcd_normal(VALUE x, VALUE y)
{
    VALUE z;

    if (FIXNUM_P(x) && FIXNUM_P(y))
	return LONG2NUM(i_gcd(FIX2LONG(x), FIX2LONG(y)));

    if (INT_NEGATIVE_P(x))
	x = rb_int_uminus(x);
    if (INT_NEGATIVE_P(y))
	y = rb_int_uminus(y);

    if (INT_ZERO_P(x))
	return y;
    if (INT_ZERO_P(y))
	return x;

    for (;;) {
	if (FIXNUM_P(x)) {
	    if (FIXNUM_ZERO_P(x))
		return y;
	    if (FIXNUM_P(y))
		return LONG2NUM(i_gcd(FIX2LONG(x), FIX2LONG(y)));
	}
	z = x;
	x = rb_int_modulo(y, x);
	y = z;
    }
    /* NOTREACHED */
}

VALUE
rb_gcd_normal(VALUE x, VALUE y)
{
    return f_gcd_normal(x, y);
}

inline static VALUE
f_gcd(VALUE x, VALUE y)
{
#ifdef USE_GMP
    if (RB_TYPE_P(x, T_BIGNUM) && RB_TYPE_P(y, T_BIGNUM)) {
        size_t xn = BIGNUM_LEN(x);
        size_t yn = BIGNUM_LEN(y);
        if (GMP_GCD_DIGITS <= xn || GMP_GCD_DIGITS <= yn)
            return rb_gcd_gmp(x, y);
    }
#endif
    return f_gcd_normal(x, y);
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
    if (INT_ZERO_P(x) || INT_ZERO_P(y))
	return ZERO;
    return f_abs(f_mul(f_div(x, f_gcd(x, y)), y));
}

#define get_dat1(x) \
    struct RRational *dat = RRATIONAL(x)

#define get_dat2(x,y) \
    struct RRational *adat = RRATIONAL(x), *bdat = RRATIONAL(y)

#define RRATIONAL_SET_NUM(rat, n) RB_OBJ_WRITE((rat), &((struct RRational *)(rat))->num,(n))
#define RRATIONAL_SET_DEN(rat, d) RB_OBJ_WRITE((rat), &((struct RRational *)(rat))->den,(d))

inline static VALUE
nurat_s_new_internal(VALUE klass, VALUE num, VALUE den)
{
    NEWOBJ_OF(obj, struct RRational, klass, T_RATIONAL | (RGENGC_WB_PROTECTED_RATIONAL ? FL_WB_PROTECTED : 0));

    RRATIONAL_SET_NUM(obj, num);
    RRATIONAL_SET_DEN(obj, den);

    return (VALUE)obj;
}

static VALUE
nurat_s_alloc(VALUE klass)
{
    return nurat_s_new_internal(klass, ZERO, ONE);
}

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

        if (INT_NEGATIVE_P(den)) {
	    num = rb_int_uminus(num);
	    den = rb_int_uminus(den);
        }
        else if (INT_ZERO_P(den)) {
            rb_num_zerodiv();
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

#ifdef CANONICALIZATION_FOR_MATHN
#define CANON
#endif

#ifdef CANON
static int canonicalization = 0;

RUBY_FUNC_EXPORTED void
nurat_canonicalization(int f)
{
    canonicalization = f;
}
#endif

inline static void
nurat_int_check(VALUE num)
{
    if (!RB_INTEGER_TYPE_P(num)) {
	if (!k_numeric_p(num) || !f_integer_p(num))
	    rb_raise(rb_eTypeError, "not an integer");
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

static void
nurat_canonicalize(VALUE *num, VALUE *den)
{
    assert(num != NULL && RB_INTEGER_TYPE_P(*num));
    assert(den != NULL && RB_INTEGER_TYPE_P(*den));
    if (INT_NEGATIVE_P(*den)) {
        *num = rb_int_uminus(*num);
        *den = rb_int_uminus(*den);
    }
    else if (INT_ZERO_P(*den)) {
        rb_num_zerodiv();
    }
}

inline static VALUE
nurat_s_canonicalize_internal(VALUE klass, VALUE num, VALUE den)
{
    VALUE gcd;

    nurat_canonicalize(&num, &den);
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
    nurat_canonicalize(&num, &den);

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
f_rational_new2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_rational_p(x));
    assert(!k_rational_p(y));
    return nurat_s_canonicalize_internal(klass, x, y);
}

inline static VALUE
f_rational_new_no_reduce2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_rational_p(x));
    assert(!k_rational_p(y));
    return nurat_s_canonicalize_internal_no_reduce(klass, x, y);
}

static VALUE nurat_s_convert(int argc, VALUE *argv, VALUE klass);
/*
 * call-seq:
 *    Rational(x[, y])  ->  numeric
 *
 * Returns x/y;
 *
 *    Rational(1, 2)   #=> (1/2)
 *    Rational('1/2')  #=> (1/2)
 *    Rational(nil)    #=> TypeError
 *    Rational(1, nil) #=> TypeError
 *
 * Syntax of string form:
 *
 *   string form = extra spaces , rational , extra spaces ;
 *   rational = [ sign ] , unsigned rational ;
 *   unsigned rational = numerator | numerator , "/" , denominator ;
 *   numerator = integer part | fractional part | integer part , fractional part ;
 *   denominator = digits ;
 *   integer part = digits ;
 *   fractional part = "." , digits , [ ( "e" | "E" ) , [ sign ] , digits ] ;
 *   sign = "-" | "+" ;
 *   digits = digit , { digit | "_" , digit } ;
 *   digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
 *   extra spaces = ? \s* ? ;
 *
 * See String#to_r.
 */
static VALUE
nurat_f_rational(int argc, VALUE *argv, VALUE klass)
{
    return nurat_s_convert(argc, argv, rb_cRational);
}

/*
 * call-seq:
 *    rat.numerator  ->  integer
 *
 * Returns the numerator.
 *
 *    Rational(7).numerator        #=> 7
 *    Rational(7, 1).numerator     #=> 7
 *    Rational(9, -4).numerator    #=> -9
 *    Rational(-2, -10).numerator  #=> 1
 */
static VALUE
nurat_numerator(VALUE self)
{
    get_dat1(self);
    return dat->num;
}

/*
 * call-seq:
 *    rat.denominator  ->  integer
 *
 * Returns the denominator (always positive).
 *
 *    Rational(7).denominator             #=> 1
 *    Rational(7, 1).denominator          #=> 1
 *    Rational(9, -4).denominator         #=> 4
 *    Rational(-2, -10).denominator       #=> 5
 *    rat.numerator.gcd(rat.denominator)  #=> 1
 */
static VALUE
nurat_denominator(VALUE self)
{
    get_dat1(self);
    return dat->den;
}

/*
 * call-seq:
 *    -rat  ->  rational
 *
 * Negates +rat+.
 */
VALUE
rb_rational_uminus(VALUE self)
{
    const int unused = (assert(RB_TYPE_P(self, T_RATIONAL)), 0);
    get_dat1(self);
    (void)unused;
    return f_rational_new2(CLASS_OF(self), rb_int_uminus(dat->num), dat->den);
}

#ifndef NDEBUG
#define f_imul f_imul_orig
#endif

inline static VALUE
f_imul(long a, long b)
{
    VALUE r;

    if (a == 0 || b == 0)
	return ZERO;
    else if (a == 1)
	return LONG2NUM(b);
    else if (b == 1)
	return LONG2NUM(a);

    if (MUL_OVERFLOW_LONG_P(a, b))
	r = rb_big_mul(rb_int2big(a), rb_int2big(b));
    else
        r = LONG2NUM(a * b);
    return r;
}

#ifndef NDEBUG
#undef f_imul

inline static VALUE
f_imul(long x, long y)
{
    VALUE r = f_imul_orig(x, y);
    assert(f_eqeq_p(r, f_mul(LONG2NUM(x), LONG2NUM(y))));
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
	    c = rb_int_plus(a, b);
	else
	    c = rb_int_minus(a, b);

	b = rb_int_idiv(aden, g);
	g = f_gcd(c, g);
	num = rb_int_idiv(c, g);
	a = rb_int_idiv(bden, g);
	den = rb_int_mul(a, b);
    }
    else {
	VALUE g = f_gcd(aden, bden);
	VALUE a = rb_int_mul(anum, rb_int_idiv(bden, g));
	VALUE b = rb_int_mul(bnum, rb_int_idiv(aden, g));
	VALUE c;

	if (k == '+')
	    c = rb_int_plus(a, b);
	else
	    c = rb_int_minus(a, b);

	b = rb_int_idiv(aden, g);
	g = f_gcd(c, g);
	num = rb_int_idiv(c, g);
	a = rb_int_idiv(bden, g);
	den = rb_int_mul(a, b);
    }
    return f_rational_new_no_reduce2(CLASS_OF(self), num, den);
}

static double nurat_to_double(VALUE self);
/*
 * call-seq:
 *    rat + numeric  ->  numeric
 *
 * Performs addition.
 *
 *    Rational(2, 3)  + Rational(2, 3)   #=> (4/3)
 *    Rational(900)   + Rational(1)      #=> (900/1)
 *    Rational(-2, 9) + Rational(-9, 2)  #=> (-85/18)
 *    Rational(9, 8)  + 4                #=> (41/8)
 *    Rational(20, 9) + 9.8              #=> 12.022222222222222
 */
VALUE
rb_rational_plus(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	{
	    get_dat1(self);

	    return f_rational_new_no_reduce2(CLASS_OF(self),
					     rb_int_plus(dat->num, rb_int_mul(other, dat->den)),
					     dat->den);
	}
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	return DBL2NUM(nurat_to_double(self) + RFLOAT_VALUE(other));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	{
	    get_dat2(self, other);

	    return f_addsub(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '+');
	}
    }
    else {
	return rb_num_coerce_bin(self, other, '+');
    }
}

/*
 * call-seq:
 *    rat - numeric  ->  numeric
 *
 * Performs subtraction.
 *
 *    Rational(2, 3)  - Rational(2, 3)   #=> (0/1)
 *    Rational(900)   - Rational(1)      #=> (899/1)
 *    Rational(-2, 9) - Rational(-9, 2)  #=> (77/18)
 *    Rational(9, 8)  - 4                #=> (23/8)
 *    Rational(20, 9) - 9.8              #=> -7.577777777777778
 */
static VALUE
nurat_sub(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	{
	    get_dat1(self);

	    return f_rational_new_no_reduce2(CLASS_OF(self),
					     rb_int_minus(dat->num, rb_int_mul(other, dat->den)),
					     dat->den);
	}
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	return DBL2NUM(nurat_to_double(self) - RFLOAT_VALUE(other));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	{
	    get_dat2(self, other);

	    return f_addsub(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '-');
	}
    }
    else {
	return rb_num_coerce_bin(self, other, '-');
    }
}

inline static VALUE
f_muldiv(VALUE self, VALUE anum, VALUE aden, VALUE bnum, VALUE bden, int k)
{
    VALUE num, den;

    assert(RB_TYPE_P(self, T_RATIONAL));
    assert(RB_INTEGER_TYPE_P(anum));
    assert(RB_INTEGER_TYPE_P(aden));
    assert(RB_INTEGER_TYPE_P(bnum));
    assert(RB_INTEGER_TYPE_P(bden));

    if (k == '/') {
	VALUE t;

	if (INT_NEGATIVE_P(bnum)) {
	    anum = rb_int_uminus(anum);
	    bnum = rb_int_uminus(bnum);
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

	num = rb_int_mul(rb_int_idiv(anum, g1), rb_int_idiv(bnum, g2));
	den = rb_int_mul(rb_int_idiv(aden, g2), rb_int_idiv(bden, g1));
    }
    return f_rational_new_no_reduce2(CLASS_OF(self), num, den);
}

/*
 * call-seq:
 *    rat * numeric  ->  numeric
 *
 * Performs multiplication.
 *
 *    Rational(2, 3)  * Rational(2, 3)   #=> (4/9)
 *    Rational(900)   * Rational(1)      #=> (900/1)
 *    Rational(-2, 9) * Rational(-9, 2)  #=> (1/1)
 *    Rational(9, 8)  * 4                #=> (9/2)
 *    Rational(20, 9) * 9.8              #=> 21.77777777777778
 */
static VALUE
nurat_mul(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	{
	    get_dat1(self);

	    return f_muldiv(self,
			    dat->num, dat->den,
			    other, ONE, '*');
	}
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	return DBL2NUM(nurat_to_double(self) * RFLOAT_VALUE(other));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	{
	    get_dat2(self, other);

	    return f_muldiv(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '*');
	}
    }
    else {
	return rb_num_coerce_bin(self, other, '*');
    }
}

/*
 * call-seq:
 *    rat / numeric     ->  numeric
 *    rat.quo(numeric)  ->  numeric
 *
 * Performs division.
 *
 *    Rational(2, 3)  / Rational(2, 3)   #=> (1/1)
 *    Rational(900)   / Rational(1)      #=> (900/1)
 *    Rational(-2, 9) / Rational(-9, 2)  #=> (4/81)
 *    Rational(9, 8)  / 4                #=> (9/32)
 *    Rational(20, 9) / 9.8              #=> 0.22675736961451246
 */
static VALUE
nurat_div(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	if (f_zero_p(other))
            rb_num_zerodiv();
	{
	    get_dat1(self);

	    return f_muldiv(self,
			    dat->num, dat->den,
			    other, ONE, '/');
	}
    }
    else if (RB_FLOAT_TYPE_P(other))
	return DBL2NUM(nurat_to_double(self) / RFLOAT_VALUE(other));
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	if (f_zero_p(other))
            rb_num_zerodiv();
	{
	    get_dat2(self, other);

	    if (f_one_p(self))
		return f_rational_new_no_reduce2(CLASS_OF(self),
						 bdat->den, bdat->num);

	    return f_muldiv(self,
			    adat->num, adat->den,
			    bdat->num, bdat->den, '/');
	}
    }
    else {
	return rb_num_coerce_bin(self, other, '/');
    }
}

static VALUE nurat_to_f(VALUE self);

/*
 * call-seq:
 *    rat.fdiv(numeric)  ->  float
 *
 * Performs division and returns the value as a float.
 *
 *    Rational(2, 3).fdiv(1)       #=> 0.6666666666666666
 *    Rational(2, 3).fdiv(0.5)     #=> 1.3333333333333333
 *    Rational(2).fdiv(3)          #=> 0.6666666666666666
 */
static VALUE
nurat_fdiv(VALUE self, VALUE other)
{
    VALUE div;
    if (f_zero_p(other))
	return DBL2NUM(nurat_to_double(self) / 0.0);
    if (FIXNUM_P(other) && other == LONG2FIX(1))
	return nurat_to_f(self);
    div = nurat_div(self, other);
    if (RB_TYPE_P(div, T_RATIONAL))
	return nurat_to_f(div);
    if (RB_FLOAT_TYPE_P(div))
	return div;
    return rb_funcall(div, rb_intern("to_f"), 0);
}

inline static VALUE
f_odd_p(VALUE integer)
{
    if (rb_funcall(integer, '%', 1, INT2FIX(2)) != INT2FIX(0)) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 * call-seq:
 *    rat ** numeric  ->  numeric
 *
 * Performs exponentiation.
 *
 *    Rational(2)    ** Rational(3)    #=> (8/1)
 *    Rational(10)   ** -2             #=> (1/100)
 *    Rational(10)   ** -2.0           #=> 0.01
 *    Rational(-4)   ** Rational(1,2)  #=> (1.2246063538223773e-16+2.0i)
 *    Rational(1, 2) ** 0              #=> (1/1)
 *    Rational(1, 2) ** 0.0            #=> 1.0
 */
static VALUE
nurat_expt(VALUE self, VALUE other)
{
    if (k_numeric_p(other) && k_exact_zero_p(other))
	return f_rational_new_bang1(CLASS_OF(self), ONE);

    if (k_rational_p(other)) {
	get_dat1(other);

	if (f_one_p(dat->den))
	    other = dat->num; /* c14n */
    }

    /* Deal with special cases of 0**n and 1**n */
    if (k_numeric_p(other) && k_exact_p(other)) {
	get_dat1(self);
	if (f_one_p(dat->den)) {
	    if (f_one_p(dat->num)) {
		return f_rational_new_bang1(CLASS_OF(self), ONE);
	    }
	    else if (f_minus_one_p(dat->num) && RB_INTEGER_TYPE_P(other)) {
		return f_rational_new_bang1(CLASS_OF(self), INT2FIX(f_odd_p(other) ? -1 : 1));
	    }
	    else if (INT_ZERO_P(dat->num)) {
		if (rb_num_negative_p(other)) {
                    rb_num_zerodiv();
		}
		else {
		    return f_rational_new_bang1(CLASS_OF(self), ZERO);
		}
	    }
	}
    }

    /* General case */
    if (FIXNUM_P(other)) {
	{
	    VALUE num, den;

	    get_dat1(self);

            if (INT_POSITIVE_P(other)) {
		num = rb_int_pow(dat->num, other);
		den = rb_int_pow(dat->den, other);
            }
            else if (INT_NEGATIVE_P(other)) {
		num = rb_int_pow(dat->den, rb_int_uminus(other));
		den = rb_int_pow(dat->num, rb_int_uminus(other));
            }
            else {
		num = ONE;
		den = ONE;
	    }
	    return f_rational_new2(CLASS_OF(self), num, den);
	}
    }
    else if (RB_TYPE_P(other, T_BIGNUM)) {
	rb_warn("in a**b, b may be too big");
	return rb_float_pow(nurat_to_f(self), other);
    }
    else if (RB_FLOAT_TYPE_P(other) || RB_TYPE_P(other, T_RATIONAL)) {
	return rb_float_pow(nurat_to_f(self), other);
    }
    else {
	return rb_num_coerce_bin(self, other, rb_intern("**"));
    }
}

/*
 * call-seq:
 *    rational <=> numeric  ->  -1, 0, +1 or nil
 *
 * Performs comparison and returns -1, 0, or +1.
 *
 * +nil+ is returned if the two values are incomparable.
 *
 *    Rational(2, 3)  <=> Rational(2, 3)  #=> 0
 *    Rational(5)     <=> 5               #=> 0
 *    Rational(2,3)   <=> Rational(1,3)   #=> 1
 *    Rational(1,3)   <=> 1               #=> -1
 *    Rational(1,3)   <=> 0.3             #=> 1
 */
VALUE
rb_rational_cmp(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	{
	    get_dat1(self);

	    if (dat->den == LONG2FIX(1))
		return rb_int_cmp(dat->num, other); /* c14n */
	    other = f_rational_new_bang1(CLASS_OF(self), other);
	    goto other_is_rational;
	}
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	return rb_dbl_cmp(nurat_to_double(self), RFLOAT_VALUE(other));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	other_is_rational:
	{
	    VALUE num1, num2;

	    get_dat2(self, other);

	    if (FIXNUM_P(adat->num) && FIXNUM_P(adat->den) &&
		FIXNUM_P(bdat->num) && FIXNUM_P(bdat->den)) {
		num1 = f_imul(FIX2LONG(adat->num), FIX2LONG(bdat->den));
		num2 = f_imul(FIX2LONG(bdat->num), FIX2LONG(adat->den));
	    }
	    else {
		num1 = rb_int_mul(adat->num, bdat->den);
		num2 = rb_int_mul(bdat->num, adat->den);
	    }
	    return rb_int_cmp(rb_int_minus(num1, num2), ZERO);
	}
    }
    else {
	return rb_num_coerce_cmp(self, other, rb_intern("<=>"));
    }
}

/*
 * call-seq:
 *    rat == object  ->  true or false
 *
 * Returns true if rat equals object numerically.
 *
 *    Rational(2, 3)  == Rational(2, 3)   #=> true
 *    Rational(5)     == 5                #=> true
 *    Rational(0)     == 0.0              #=> true
 *    Rational('1/3') == 0.33             #=> false
 *    Rational('1/2') == '1/2'            #=> false
 */
static VALUE
nurat_eqeq_p(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	{
	    get_dat1(self);

	    if (INT_ZERO_P(dat->num) && INT_ZERO_P(other))
		return Qtrue;

	    if (!FIXNUM_P(dat->den))
		return Qfalse;
	    if (FIX2LONG(dat->den) != 1)
		return Qfalse;
	    return rb_int_equal(dat->num, other);
	}
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	const double d = nurat_to_double(self);
	return f_boolcast(FIXNUM_ZERO_P(rb_dbl_cmp(d, RFLOAT_VALUE(other))));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	{
	    get_dat2(self, other);

	    if (INT_ZERO_P(adat->num) && INT_ZERO_P(bdat->num))
		return Qtrue;

	    return f_boolcast(rb_int_equal(adat->num, bdat->num) &&
			      rb_int_equal(adat->den, bdat->den));
	}
    }
    else {
	return rb_equal(other, self);
    }
}

/* :nodoc: */
static VALUE
nurat_coerce(VALUE self, VALUE other)
{
    if (RB_INTEGER_TYPE_P(other)) {
	return rb_assoc_new(f_rational_new_bang1(CLASS_OF(self), other), self);
    }
    else if (RB_FLOAT_TYPE_P(other)) {
        return rb_assoc_new(other, nurat_to_f(self));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	return rb_assoc_new(other, self);
    }
    else if (RB_TYPE_P(other, T_COMPLEX)) {
	if (k_exact_zero_p(RCOMPLEX(other)->imag))
	    return rb_assoc_new(f_rational_new_bang1
				(CLASS_OF(self), RCOMPLEX(other)->real), self);
	else
	    return rb_assoc_new(other, rb_Complex(self, INT2FIX(0)));
    }

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_obj_classname(other), rb_obj_classname(self));
    return Qnil;
}

#if 0
/* :nodoc: */
static VALUE
nurat_idiv(VALUE self, VALUE other)
{
    return f_idiv(self, other);
}

/* :nodoc: */
static VALUE
nurat_quot(VALUE self, VALUE other)
{
    return f_truncate(f_div(self, other));
}

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

/*
 *  call-seq:
 *     rat.positive? ->  true or false
 *
 *  Returns +true+ if +rat+ is greater than 0.
 */
static VALUE
nurat_positive_p(VALUE self)
{
    get_dat1(self);
    return f_boolcast(INT_POSITIVE_P(dat->num));
}

/*
 *  call-seq:
 *     rat.negative? ->  true or false
 *
 *  Returns +true+ if +rat+ is less than 0.
 */
static VALUE
nurat_negative_p(VALUE self)
{
    get_dat1(self);
    return f_boolcast(INT_NEGATIVE_P(dat->num));
}

/*
 *  call-seq:
 *     rat.abs       -> rat
 *     rat.magnitude -> rat
 *
 *  Returns the absolute value of +rat+.
 *
 *  (1/2r).abs    #=> 1/2r
 *  (-1/2r).abs   #=> 1/2r
 *
 *  Rational#magnitude is an alias of Rational#abs.
 */

VALUE
rb_rational_abs(VALUE self)
{
    get_dat1(self);
    if (INT_NEGATIVE_P(dat->num)) {
        VALUE num = rb_int_abs(dat->num);
        return nurat_s_canonicalize_internal_no_reduce(CLASS_OF(self), num, dat->den);
    }
    return self;
}

static VALUE
nurat_floor(VALUE self)
{
    get_dat1(self);
    return rb_int_idiv(dat->num, dat->den);
}

static VALUE
nurat_ceil(VALUE self)
{
    get_dat1(self);
    return rb_int_uminus(rb_int_idiv(rb_int_uminus(dat->num), dat->den));
}

/*
 * call-seq:
 *    rat.to_i  ->  integer
 *
 * Returns the truncated value as an integer.
 *
 * Equivalent to
 *    rat.truncate.
 *
 *    Rational(2, 3).to_i   #=> 0
 *    Rational(3).to_i      #=> 3
 *    Rational(300.6).to_i  #=> 300
 *    Rational(98,71).to_i  #=> 1
 *    Rational(-30,2).to_i  #=> -15
 */
static VALUE
nurat_truncate(VALUE self)
{
    get_dat1(self);
    if (INT_NEGATIVE_P(dat->num))
	return rb_int_uminus(rb_int_idiv(rb_int_uminus(dat->num), dat->den));
    return rb_int_idiv(dat->num, dat->den);
}

static VALUE
nurat_round_half_up(VALUE self)
{
    VALUE num, den, neg;

    get_dat1(self);

    num = dat->num;
    den = dat->den;
    neg = INT_NEGATIVE_P(num);

    if (neg)
	num = rb_int_uminus(num);

    num = rb_int_plus(rb_int_mul(num, TWO), den);
    den = rb_int_mul(den, TWO);
    num = rb_int_idiv(num, den);

    if (neg)
	num = rb_int_uminus(num);

    return num;
}

static VALUE
nurat_round_half_down(VALUE self)
{
    VALUE num, den, neg;

    get_dat1(self);

    num = dat->num;
    den = dat->den;
    neg = INT_NEGATIVE_P(num);

    if (neg)
	num = rb_int_uminus(num);

    num = rb_int_plus(rb_int_mul(num, TWO), den);
    num = rb_int_minus(num, ONE);
    den = rb_int_mul(den, TWO);
    num = rb_int_idiv(num, den);

    if (neg)
	num = rb_int_uminus(num);

    return num;
}

static VALUE
nurat_round_half_even(VALUE self)
{
    VALUE num, den, neg, qr;

    get_dat1(self);

    num = dat->num;
    den = dat->den;
    neg = INT_NEGATIVE_P(num);

    if (neg)
	num = rb_int_uminus(num);

    num = rb_int_plus(rb_int_mul(num, TWO), den);
    den = rb_int_mul(den, TWO);
    qr = rb_int_divmod(num, den);
    num = RARRAY_AREF(qr, 0);
    if (INT_ZERO_P(RARRAY_AREF(qr, 1)))
	num = rb_int_and(num, LONG2FIX(((int)~1)));

    if (neg)
	num = rb_int_uminus(num);

    return num;
}

static VALUE
f_round_common(int argc, VALUE *argv, VALUE self, VALUE (*func)(VALUE))
{
    VALUE n, b, s;

    if (argc == 0)
	return (*func)(self);

    rb_scan_args(argc, argv, "01", &n);

    if (!k_integer_p(n))
	rb_raise(rb_eTypeError, "not an integer");

    b = f_expt10(n);
    s = nurat_mul(self, b);

    if (k_float_p(s)) {
	if (INT_NEGATIVE_P(n))
	    return ZERO;
	return self;
    }

    if (!k_rational_p(s)) {
	s = f_rational_new_bang1(CLASS_OF(self), s);
    }

    s = (*func)(s);

    s = nurat_div(f_rational_new_bang1(CLASS_OF(self), s), b);

    if (RB_TYPE_P(s, T_RATIONAL) && FIX2INT(rb_int_cmp(n, ONE)) < 0)
	s = nurat_truncate(s);

    return s;
}

/*
 * call-seq:
 *    rat.floor               ->  integer
 *    rat.floor(precision=0)  ->  rational
 *
 * Returns the truncated value (toward negative infinity).
 *
 *    Rational(3).floor      #=> 3
 *    Rational(2, 3).floor   #=> 0
 *    Rational(-3, 2).floor  #=> -1
 *
 *           decimal      -  1  2  3 . 4  5  6
 *                          ^  ^  ^  ^   ^  ^
 *          precision      -3 -2 -1  0  +1 +2
 *
 *    '%f' % Rational('-123.456').floor(+1)  #=> "-123.500000"
 *    '%f' % Rational('-123.456').floor(-1)  #=> "-130.000000"
 */
static VALUE
nurat_floor_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_floor);
}

/*
 * call-seq:
 *    rat.ceil               ->  integer
 *    rat.ceil(precision=0)  ->  rational
 *
 * Returns the truncated value (toward positive infinity).
 *
 *    Rational(3).ceil      #=> 3
 *    Rational(2, 3).ceil   #=> 1
 *    Rational(-3, 2).ceil  #=> -1
 *
 *           decimal      -  1  2  3 . 4  5  6
 *                          ^  ^  ^  ^   ^  ^
 *          precision      -3 -2 -1  0  +1 +2
 *
 *    '%f' % Rational('-123.456').ceil(+1)  #=> "-123.400000"
 *    '%f' % Rational('-123.456').ceil(-1)  #=> "-120.000000"
 */
static VALUE
nurat_ceil_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_ceil);
}

/*
 * call-seq:
 *    rat.truncate               ->  integer
 *    rat.truncate(precision=0)  ->  rational
 *
 * Returns the truncated value (toward zero).
 *
 *    Rational(3).truncate      #=> 3
 *    Rational(2, 3).truncate   #=> 0
 *    Rational(-3, 2).truncate  #=> -1
 *
 *           decimal      -  1  2  3 . 4  5  6
 *                          ^  ^  ^  ^   ^  ^
 *          precision      -3 -2 -1  0  +1 +2
 *
 *    '%f' % Rational('-123.456').truncate(+1)  #=>  "-123.400000"
 *    '%f' % Rational('-123.456').truncate(-1)  #=>  "-120.000000"
 */
static VALUE
nurat_truncate_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_truncate);
}

/*
 * call-seq:
 *    rat.round               ->  integer
 *    rat.round(precision=0)  ->  rational
 *
 * Returns the truncated value (toward the nearest integer;
 * 0.5 => 1; -0.5 => -1).
 *
 *    Rational(3).round      #=> 3
 *    Rational(2, 3).round   #=> 1
 *    Rational(-3, 2).round  #=> -2
 *
 *           decimal      -  1  2  3 . 4  5  6
 *                          ^  ^  ^  ^   ^  ^
 *          precision      -3 -2 -1  0  +1 +2
 *
 *    '%f' % Rational('-123.456').round(+1)  #=> "-123.500000"
 *    '%f' % Rational('-123.456').round(-1)  #=> "-120.000000"
 */
static VALUE
nurat_round_n(int argc, VALUE *argv, VALUE self)
{
    VALUE opt;
    enum ruby_num_rounding_mode mode = (
	argc = rb_scan_args(argc, argv, "*:", NULL, &opt),
	rb_num_get_rounding_option(opt));
    VALUE (*round_func)(VALUE) = ROUND_FUNC(mode, nurat_round);
    return f_round_common(argc, argv, self, round_func);
}

static double
nurat_to_double(VALUE self)
{
    get_dat1(self);
    return rb_int_fdiv_double(dat->num, dat->den);
}

/*
 * call-seq:
 *    rat.to_f  ->  float
 *
 * Return the value as a float.
 *
 *    Rational(2).to_f      #=> 2.0
 *    Rational(9, 4).to_f   #=> 2.25
 *    Rational(-3, 4).to_f  #=> -0.75
 *    Rational(20, 3).to_f  #=> 6.666666666666667
 */
static VALUE
nurat_to_f(VALUE self)
{
    return DBL2NUM(nurat_to_double(self));
}

/*
 * call-seq:
 *    rat.to_r  ->  self
 *
 * Returns self.
 *
 *    Rational(2).to_r      #=> (2/1)
 *    Rational(-8, 6).to_r  #=> (-4/3)
 */
static VALUE
nurat_to_r(VALUE self)
{
    return self;
}

#define id_ceil rb_intern("ceil")
#define f_ceil(x) rb_funcall((x), id_ceil, 0)

#define id_quo rb_intern("quo")
#define f_quo(x,y) rb_funcall((x), id_quo, 1, (y))

#define f_reciprocal(x) f_quo(ONE, (x))

/*
  The algorithm here is the method described in CLISP.  Bruno Haible has
  graciously given permission to use this algorithm.  He says, "You can use
  it, if you present the following explanation of the algorithm."

  Algorithm (recursively presented):
    If x is a rational number, return x.
    If x = 0.0, return 0.
    If x < 0.0, return (- (rationalize (- x))).
    If x > 0.0:
      Call (integer-decode-float x). It returns a m,e,s=1 (mantissa,
      exponent, sign).
      If m = 0 or e >= 0: return x = m*2^e.
      Search a rational number between a = (m-1/2)*2^e and b = (m+1/2)*2^e
      with smallest possible numerator and denominator.
      Note 1: If m is a power of 2, we ought to take a = (m-1/4)*2^e.
        But in this case the result will be x itself anyway, regardless of
        the choice of a. Therefore we can simply ignore this case.
      Note 2: At first, we need to consider the closed interval [a,b].
        but since a and b have the denominator 2^(|e|+1) whereas x itself
        has a denominator <= 2^|e|, we can restrict the search to the open
        interval (a,b).
      So, for given a and b (0 < a < b) we are searching a rational number
      y with a <= y <= b.
      Recursive algorithm fraction_between(a,b):
        c := (ceiling a)
        if c < b
          then return c       ; because a <= c < b, c integer
          else
            ; a is not integer (otherwise we would have had c = a < b)
            k := c-1          ; k = floor(a), k < a < b <= k+1
            return y = k + 1/fraction_between(1/(b-k), 1/(a-k))
                              ; note 1 <= 1/(b-k) < 1/(a-k)

  You can see that we are actually computing a continued fraction expansion.

  Algorithm (iterative):
    If x is rational, return x.
    Call (integer-decode-float x). It returns a m,e,s (mantissa,
      exponent, sign).
    If m = 0 or e >= 0, return m*2^e*s. (This includes the case x = 0.0.)
    Create rational numbers a := (2*m-1)*2^(e-1) and b := (2*m+1)*2^(e-1)
    (positive and already in lowest terms because the denominator is a
    power of two and the numerator is odd).
    Start a continued fraction expansion
      p[-1] := 0, p[0] := 1, q[-1] := 1, q[0] := 0, i := 0.
    Loop
      c := (ceiling a)
      if c >= b
        then k := c-1, partial_quotient(k), (a,b) := (1/(b-k),1/(a-k)),
             goto Loop
    finally partial_quotient(c).
    Here partial_quotient(c) denotes the iteration
      i := i+1, p[i] := c*p[i-1]+p[i-2], q[i] := c*q[i-1]+q[i-2].
    At the end, return s * (p[i]/q[i]).
    This rational number is already in lowest terms because
    p[i]*q[i-1]-p[i-1]*q[i] = (-1)^i.
*/

static void
nurat_rationalize_internal(VALUE a, VALUE b, VALUE *p, VALUE *q)
{
    VALUE c, k, t, p0, p1, p2, q0, q1, q2;

    p0 = ZERO;
    p1 = ONE;
    q0 = ONE;
    q1 = ZERO;

    while (1) {
	c = f_ceil(a);
	if (f_lt_p(c, b))
	    break;
	k = f_sub(c, ONE);
	p2 = f_add(f_mul(k, p1), p0);
	q2 = f_add(f_mul(k, q1), q0);
	t = f_reciprocal(f_sub(b, k));
	b = f_reciprocal(f_sub(a, k));
	a = t;
	p0 = p1;
	q0 = q1;
	p1 = p2;
	q1 = q2;
    }
    *p = f_add(f_mul(c, p1), p0);
    *q = f_add(f_mul(c, q1), q0);
}

/*
 * call-seq:
 *    rat.rationalize       ->  self
 *    rat.rationalize(eps)  ->  rational
 *
 * Returns a simpler approximation of the value if the optional
 * argument eps is given (rat-|eps| <= result <= rat+|eps|), self
 * otherwise.
 *
 *    r = Rational(5033165, 16777216)
 *    r.rationalize                    #=> (5033165/16777216)
 *    r.rationalize(Rational('0.01'))  #=> (3/10)
 *    r.rationalize(Rational('0.1'))   #=> (1/3)
 */
static VALUE
nurat_rationalize(int argc, VALUE *argv, VALUE self)
{
    VALUE e, a, b, p, q;

    if (argc == 0)
	return self;

    if (nurat_negative_p(self))
	return rb_rational_uminus(nurat_rationalize(argc, argv, rb_rational_uminus(self)));

    rb_scan_args(argc, argv, "01", &e);
    e = f_abs(e);
    a = f_sub(self, e);
    b = f_add(self, e);

    if (f_eqeq_p(a, b))
	return self;

    nurat_rationalize_internal(a, b, &p, &q);
    return f_rational_new2(CLASS_OF(self), p, q);
}

/* :nodoc: */
static VALUE
nurat_hash(VALUE self)
{
    st_index_t v, h[2];
    VALUE n;

    get_dat1(self);
    n = rb_hash(dat->num);
    h[0] = NUM2LONG(n);
    n = rb_hash(dat->den);
    h[1] = NUM2LONG(n);
    v = rb_memhash(h, sizeof(h));
    return LONG2FIX(v);
}

static VALUE
f_format(VALUE self, VALUE (*func)(VALUE))
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
 *    rat.to_s  ->  string
 *
 * Returns the value as a string.
 *
 *    Rational(2).to_s      #=> "2/1"
 *    Rational(-8, 6).to_s  #=> "-4/3"
 *    Rational('1/2').to_s  #=> "1/2"
 */
static VALUE
nurat_to_s(VALUE self)
{
    return f_format(self, f_to_s);
}

/*
 * call-seq:
 *    rat.inspect  ->  string
 *
 * Returns the value as a string for inspection.
 *
 *    Rational(2).inspect      #=> "(2/1)"
 *    Rational(-8, 6).inspect  #=> "(-4/3)"
 *    Rational('1/2').inspect  #=> "(1/2)"
 */
static VALUE
nurat_inspect(VALUE self)
{
    VALUE s;

    s = rb_usascii_str_new2("(");
    rb_str_concat(s, f_format(self, f_inspect));
    rb_str_cat2(s, ")");

    return s;
}

/* :nodoc: */
static VALUE
nurat_dumper(VALUE self)
{
    return self;
}

/* :nodoc: */
static VALUE
nurat_loader(VALUE self, VALUE a)
{
    VALUE num, den;

    get_dat1(self);
    num = rb_ivar_get(a, id_i_num);
    den = rb_ivar_get(a, id_i_den);
    nurat_int_check(num);
    nurat_int_check(den);
    nurat_canonicalize(&num, &den);
    RRATIONAL_SET_NUM(dat, num);
    RRATIONAL_SET_DEN(dat, den);

    return self;
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
    VALUE num, den;

    rb_check_frozen(self);
    rb_check_trusted(self);

    Check_Type(a, T_ARRAY);
    if (RARRAY_LEN(a) != 2)
	rb_raise(rb_eArgError, "marshaled rational must have an array whose length is 2 but %ld", RARRAY_LEN(a));

    num = RARRAY_AREF(a, 0);
    den = RARRAY_AREF(a, 1);
    nurat_int_check(num);
    nurat_int_check(den);
    nurat_canonicalize(&num, &den);
    rb_ivar_set(self, id_i_num, num);
    rb_ivar_set(self, id_i_den, den);

    return self;
}

/* --- */

VALUE
rb_rational_reciprocal(VALUE x)
{
    get_dat1(x);
    return f_rational_new_no_reduce2(CLASS_OF(x), dat->den, dat->num);
}

/*
 * call-seq:
 *    int.gcd(int2)  ->  integer
 *
 * Returns the greatest common divisor (always positive).  0.gcd(x)
 * and x.gcd(0) return abs(x).
 *
 *    2.gcd(2)                    #=> 2
 *    3.gcd(-7)                   #=> 1
 *    ((1<<31)-1).gcd((1<<61)-1)  #=> 1
 */
VALUE
rb_gcd(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_gcd(self, other);
}

/*
 * call-seq:
 *    int.lcm(int2)  ->  integer
 *
 * Returns the least common multiple (always positive).  0.lcm(x) and
 * x.lcm(0) return zero.
 *
 *    2.lcm(2)                    #=> 2
 *    3.lcm(-7)                   #=> 21
 *    ((1<<31)-1).lcm((1<<61)-1)  #=> 4951760154835678088235319297
 */
VALUE
rb_lcm(VALUE self, VALUE other)
{
    other = nurat_int_value(other);
    return f_lcm(self, other);
}

/*
 * call-seq:
 *    int.gcdlcm(int2)  ->  array
 *
 * Returns an array; [int.gcd(int2), int.lcm(int2)].
 *
 *    2.gcdlcm(2)                    #=> [2, 2]
 *    3.gcdlcm(-7)                   #=> [1, 21]
 *    ((1<<31)-1).gcdlcm((1<<61)-1)  #=> [1, 4951760154835678088235319297]
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

VALUE
rb_Rational(VALUE x, VALUE y)
{
    VALUE a[2];
    a[0] = x;
    a[1] = y;
    return nurat_s_convert(2, a, rb_cRational);
}

VALUE
rb_rational_num(VALUE rat)
{
    return nurat_numerator(rat);
}

VALUE
rb_rational_den(VALUE rat)
{
    return nurat_denominator(rat);
}

#define id_numerator rb_intern("numerator")
#define f_numerator(x) rb_funcall((x), id_numerator, 0)

#define id_denominator rb_intern("denominator")
#define f_denominator(x) rb_funcall((x), id_denominator, 0)

#define id_to_r rb_intern("to_r")
#define f_to_r(x) rb_funcall((x), id_to_r, 0)

/*
 * call-seq:
 *    num.numerator  ->  integer
 *
 * Returns the numerator.
 */
static VALUE
numeric_numerator(VALUE self)
{
    return f_numerator(f_to_r(self));
}

/*
 * call-seq:
 *    num.denominator  ->  integer
 *
 * Returns the denominator (always positive).
 */
static VALUE
numeric_denominator(VALUE self)
{
    return f_denominator(f_to_r(self));
}


/*
 *  call-seq:
 *     num.quo(int_or_rat)   ->  rat
 *     num.quo(flo)          ->  flo
 *
 *  Returns most exact division (rational for integers, float for floats).
 */

static VALUE
numeric_quo(VALUE x, VALUE y)
{
    if (RB_FLOAT_TYPE_P(y)) {
        return rb_funcall(x, rb_intern("fdiv"), 1, y);
    }

#ifdef CANON
    if (canonicalization) {
        x = rb_rational_raw1(x);
    }
    else
#endif
    {
        x = rb_convert_type(x, T_RATIONAL, "Rational", "to_r");
    }
    return nurat_div(x, y);
}


/*
 * call-seq:
 *    int.numerator  ->  self
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
 *    int.denominator  ->  1
 *
 * Returns 1.
 */
static VALUE
integer_denominator(VALUE self)
{
    return INT2FIX(1);
}

static VALUE float_to_r(VALUE self);
/*
 * call-seq:
 *    flo.numerator  ->  integer
 *
 * Returns the numerator.  The result is machine dependent.
 *
 *    n = 0.3.numerator    #=> 5404319552844595
 *    d = 0.3.denominator  #=> 18014398509481984
 *    n.fdiv(d)            #=> 0.3
 */
static VALUE
float_numerator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return self;
    return nurat_numerator(float_to_r(self));
}

/*
 * call-seq:
 *    flo.denominator  ->  integer
 *
 * Returns the denominator (always positive).  The result is machine
 * dependent.
 *
 * See numerator.
 */
static VALUE
float_denominator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    if (isinf(d) || isnan(d))
	return INT2FIX(1);
    return nurat_denominator(float_to_r(self));
}

/*
 * call-seq:
 *    nil.to_r  ->  (0/1)
 *
 * Returns zero as a rational.
 */
static VALUE
nilclass_to_r(VALUE self)
{
    return rb_rational_new1(INT2FIX(0));
}

/*
 * call-seq:
 *    nil.rationalize([eps])  ->  (0/1)
 *
 * Returns zero as a rational.  The optional argument eps is always
 * ignored.
 */
static VALUE
nilclass_rationalize(int argc, VALUE *argv, VALUE self)
{
    rb_scan_args(argc, argv, "01", NULL);
    return nilclass_to_r(self);
}

/*
 * call-seq:
 *    int.to_r  ->  rational
 *
 * Returns the value as a rational.
 *
 *    1.to_r        #=> (1/1)
 *    (1<<64).to_r  #=> (18446744073709551616/1)
 */
static VALUE
integer_to_r(VALUE self)
{
    return rb_rational_new1(self);
}

/*
 * call-seq:
 *    int.rationalize([eps])  ->  rational
 *
 * Returns the value as a rational.  The optional argument eps is
 * always ignored.
 */
static VALUE
integer_rationalize(int argc, VALUE *argv, VALUE self)
{
    rb_scan_args(argc, argv, "01", NULL);
    return integer_to_r(self);
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
 *    flt.to_r  ->  rational
 *
 * Returns the value as a rational.
 *
 * NOTE: 0.3.to_r isn't the same as '0.3'.to_r.  The latter is
 * equivalent to '3/10'.to_r, but the former isn't so.
 *
 *    2.0.to_r    #=> (2/1)
 *    2.5.to_r    #=> (5/2)
 *    -0.75.to_r  #=> (-3/4)
 *    0.0.to_r    #=> (0/1)
 *
 * See rationalize.
 */
static VALUE
float_to_r(VALUE self)
{
    VALUE f, n;

    float_decode_internal(self, &f, &n);
#if FLT_RADIX == 2
    {
	long ln = FIX2LONG(n);

	if (ln == 0)
	    return rb_rational_new1(f);
	if (ln > 0)
	    return rb_rational_new1(rb_int_lshift(f, n));
	ln = -ln;
	return rb_rational_new2(f, rb_int_lshift(ONE, INT2FIX(ln)));
    }
#else
    f = rb_int_mul(f, rb_int_pow(INT2FIX(FLT_RADIX), n));
    if (RB_TYPE_P(f, T_RATIONAL))
	return f;
    return rb_rational_new1(f);
#endif
}

VALUE
rb_flt_rationalize_with_prec(VALUE flt, VALUE prec)
{
    VALUE e, a, b, p, q;

    e = f_abs(prec);
    a = f_sub(flt, e);
    b = f_add(flt, e);

    if (f_eqeq_p(a, b))
        return float_to_r(flt);

    nurat_rationalize_internal(a, b, &p, &q);
    return rb_rational_new2(p, q);
}

VALUE
rb_flt_rationalize(VALUE flt)
{
    VALUE a, b, f, n, p, q;

    float_decode_internal(flt, &f, &n);
    if (INT_ZERO_P(f) || FIX2INT(n) >= 0)
        return rb_rational_new1(rb_int_lshift(f, n));

#if FLT_RADIX == 2
    {
        VALUE two_times_f, den;

        two_times_f = rb_int_mul(TWO, f);
        den = rb_int_lshift(ONE, rb_int_minus(ONE, n));

        a = rb_rational_new2(rb_int_minus(two_times_f, ONE), den);
        b = rb_rational_new2(rb_int_plus(two_times_f, ONE), den);
    }
#else
    {
        VALUE radix_times_f, den;

        radix_times_f = rb_int_mul(INT2FIX(FLT_RADIX), f);
        den = rb_int_pow(INT2FIX(FLT_RADIX), rb_int_minus(ONE, n));

        a = rb_rational_new2(rb_int_minus(radix_times_f, INT2FIX(FLT_RADIX - 1)), den);
        b = rb_rational_new2(rb_int_plus(radix_times_f, INT2FIX(FLT_RADIX - 1)), den);
    }
#endif

    if (nurat_eqeq_p(a, b))
        return float_to_r(flt);

    nurat_rationalize_internal(a, b, &p, &q);
    return rb_rational_new2(p, q);
}

/*
 * call-seq:
 *    flt.rationalize([eps])  ->  rational
 *
 * Returns a simpler approximation of the value (flt-|eps| <= result
 * <= flt+|eps|).  if the optional eps is not given, it will be chosen
 * automatically.
 *
 *    0.3.rationalize          #=> (3/10)
 *    1.333.rationalize        #=> (1333/1000)
 *    1.333.rationalize(0.01)  #=> (4/3)
 *
 * See to_r.
 */
static VALUE
float_rationalize(int argc, VALUE *argv, VALUE self)
{
    VALUE e;
    double d = RFLOAT_VALUE(self);

    if (d < 0.0)
        return rb_rational_uminus(float_rationalize(argc, argv, DBL2NUM(-d)));

    rb_scan_args(argc, argv, "01", &e);

    if (argc != 0) {
        return rb_flt_rationalize_with_prec(self, e);
    }
    else {
        return rb_flt_rationalize(self);
    }
}

#include <ctype.h>

inline static int
issign(int c)
{
    return (c == '-' || c == '+');
}

static int
read_sign(const char **s)
{
    int sign = '?';

    if (issign(**s)) {
	sign = **s;
	(*s)++;
    }
    return sign;
}

inline static int
isdecimal(int c)
{
    return isdigit((unsigned char)c);
}

static int
read_digits(const char **s, int strict,
	    VALUE *num, int *count)
{
    char *b, *bb;
    int us = 1, ret = 1;
    VALUE tmp;

    if (!isdecimal(**s)) {
	*num = ZERO;
	return 0;
    }

    bb = b = ALLOCV_N(char, tmp, strlen(*s) + 1);

    while (isdecimal(**s) || **s == '_') {
	if (**s == '_') {
	    if (strict) {
		if (us) {
		    ret = 0;
		    goto conv;
		}
	    }
	    us = 1;
	}
	else {
	    if (count)
		(*count)++;
	    *b++ = **s;
	    us = 0;
	}
	(*s)++;
    }
    if (us)
	do {
	    (*s)--;
	} while (**s == '_');
  conv:
    *b = '\0';
    *num = rb_cstr_to_inum(bb, 10, 0);
    ALLOCV_END(tmp);
    return ret;
}

inline static int
islettere(int c)
{
    return (c == 'e' || c == 'E');
}

static int
read_num(const char **s, int numsign, int strict,
	 VALUE *num)
{
    VALUE ip, fp, exp;

    *num = rb_rational_new2(ZERO, ONE);
    exp = Qnil;

    if (**s != '.') {
	if (!read_digits(s, strict, &ip, NULL))
	    return 0;
	*num = rb_rational_new2(ip, ONE);
    }

    if (**s == '.') {
	int count = 0;

	(*s)++;
	if (!read_digits(s, strict, &fp, &count))
	    return 0;
	{
	    VALUE l = f_expt10(INT2NUM(count));
#ifdef CANON
	    if (canonicalization) {
		*num = rb_int_mul(*num, l);
		*num = rb_int_plus(*num, fp);
		*num = rb_rational_new2(*num, l);
	    }
	    else
#endif
	    {
		*num = nurat_mul(*num, l);
		*num = rb_rational_plus(*num, fp);
		*num = nurat_div(*num, l);
	    }
	}
    }

    if (islettere(**s)) {
	int expsign;

	(*s)++;
	expsign = read_sign(s);
	if (!read_digits(s, strict, &exp, NULL))
	    return 0;
	if (expsign == '-')
	    exp = rb_int_uminus(exp);
    }

    if (numsign == '-')
	*num = rb_rational_uminus(*num);
    if (!NIL_P(exp)) {
	VALUE l = f_expt10(exp);
	*num = nurat_mul(*num, l);
    }
    return 1;
}

inline static int
read_den(const char **s, int strict,
	 VALUE *num)
{
    if (!read_digits(s, strict, num, NULL))
	return 0;
    return 1;
}

static int
read_rat_nos(const char **s, int sign, int strict,
	     VALUE *num)
{
    VALUE den;

    if (!read_num(s, sign, strict, num))
	return 0;
    if (**s == '/') {
	(*s)++;
	if (!read_den(s, strict, &den))
	    return 0;
	if (!(FIXNUM_P(den) && FIX2LONG(den) == 1))
	    *num = nurat_div(*num, den);
    }
    return 1;
}

static int
read_rat(const char **s, int strict,
	 VALUE *num)
{
    int sign;

    sign = read_sign(s);
    if (!read_rat_nos(s, sign, strict, num))
	return 0;
    return 1;
}

inline static void
skip_ws(const char **s)
{
    while (isspace((unsigned char)**s))
	(*s)++;
}

static int
parse_rat(const char *s, int strict,
	  VALUE *num)
{
    skip_ws(&s);
    if (!read_rat(&s, strict, num))
	return 0;
    skip_ws(&s);

    if (strict)
	if (*s != '\0')
	    return 0;
    return 1;
}

static VALUE
string_to_r_strict(VALUE self)
{
    char *s;
    VALUE num;

    rb_must_asciicompat(self);

    s = RSTRING_PTR(self);

    if (!s || memchr(s, '\0', RSTRING_LEN(self)))
	rb_raise(rb_eArgError, "string contains null byte");

    if (s && s[RSTRING_LEN(self)]) {
	rb_str_modify(self);
	s = RSTRING_PTR(self);
	s[RSTRING_LEN(self)] = '\0';
    }

    if (!s)
	s = (char *)"";

    if (!parse_rat(s, 1, &num)) {
	rb_raise(rb_eArgError, "invalid value for convert(): %+"PRIsVALUE,
		 self);
    }

    if (RB_FLOAT_TYPE_P(num))
	rb_raise(rb_eFloatDomainError, "Infinity");
    return num;
}

/*
 * call-seq:
 *    str.to_r  ->  rational
 *
 * Returns a rational which denotes the string form.  The parser
 * ignores leading whitespaces and trailing garbage.  Any digit
 * sequences can be separated by an underscore.  Returns zero for null
 * or garbage string.
 *
 * NOTE: '0.3'.to_r isn't the same as 0.3.to_r.  The former is
 * equivalent to '3/10'.to_r, but the latter isn't so.
 *
 *    '  2  '.to_r       #=> (2/1)
 *    '300/2'.to_r       #=> (150/1)
 *    '-9.2'.to_r        #=> (-46/5)
 *    '-9.2e2'.to_r      #=> (-920/1)
 *    '1_234_567'.to_r   #=> (1234567/1)
 *    '21 june 09'.to_r  #=> (21/1)
 *    '21/06/09'.to_r    #=> (7/2)
 *    'bwv 1079'.to_r    #=> (0/1)
 *
 * See Kernel.Rational.
 */
static VALUE
string_to_r(VALUE self)
{
    char *s;
    VALUE num;

    rb_must_asciicompat(self);

    s = RSTRING_PTR(self);

    if (s && s[RSTRING_LEN(self)]) {
	rb_str_modify(self);
	s = RSTRING_PTR(self);
	s[RSTRING_LEN(self)] = '\0';
    }

    if (!s)
	s = (char *)"";

    (void)parse_rat(s, 0, &num);

    if (RB_FLOAT_TYPE_P(num))
	rb_raise(rb_eFloatDomainError, "Infinity");
    return num;
}

VALUE
rb_cstr_to_rat(const char *s, int strict) /* for complex's internal */
{
    VALUE num;

    (void)parse_rat(s, strict, &num);

    if (RB_FLOAT_TYPE_P(num))
	rb_raise(rb_eFloatDomainError, "Infinity");
    return num;
}

static VALUE
nurat_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, backref;

    rb_scan_args(argc, argv, "11", &a1, &a2);

    if (NIL_P(a1) || (argc == 2 && NIL_P(a2)))
	rb_raise(rb_eTypeError, "can't convert nil into Rational");

    if (RB_TYPE_P(a1, T_COMPLEX)) {
	if (k_exact_zero_p(RCOMPLEX(a1)->imag))
	    a1 = RCOMPLEX(a1)->real;
    }

    if (RB_TYPE_P(a2, T_COMPLEX)) {
	if (k_exact_zero_p(RCOMPLEX(a2)->imag))
	    a2 = RCOMPLEX(a2)->real;
    }

    backref = rb_backref_get();
    rb_match_busy(backref);

    if (RB_FLOAT_TYPE_P(a1)) {
	a1 = float_to_r(a1);
    }
    else if (RB_TYPE_P(a1, T_STRING)) {
	a1 = string_to_r_strict(a1);
    }

    if (RB_FLOAT_TYPE_P(a2)) {
	a2 = float_to_r(a2);
    }
    else if (RB_TYPE_P(a2, T_STRING)) {
	a2 = string_to_r_strict(a2);
    }

    rb_backref_set(backref);

    if (RB_TYPE_P(a1, T_RATIONAL)) {
	if (argc == 1 || (k_exact_one_p(a2)))
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
 * A rational number can be represented as a paired integer number;
 * a/b (b>0).  Where a is numerator and b is denominator.  Integer a
 * equals rational a/1 mathematically.
 *
 * In ruby, you can create rational object with Rational, to_r,
 * rationalize method or suffixing r to a literal.  The return values will be irreducible.
 *
 *    Rational(1)      #=> (1/1)
 *    Rational(2, 3)   #=> (2/3)
 *    Rational(4, -6)  #=> (-2/3)
 *    3.to_r           #=> (3/1)
 *    2/3r             #=> (2/3)
 *
 * You can also create rational object from floating-point numbers or
 * strings.
 *
 *    Rational(0.3)    #=> (5404319552844595/18014398509481984)
 *    Rational('0.3')  #=> (3/10)
 *    Rational('2/3')  #=> (2/3)
 *
 *    0.3.to_r         #=> (5404319552844595/18014398509481984)
 *    '0.3'.to_r       #=> (3/10)
 *    '2/3'.to_r       #=> (2/3)
 *    0.3.rationalize  #=> (3/10)
 *
 * A rational object is an exact number, which helps you to write
 * program without any rounding errors.
 *
 *    10.times.inject(0){|t,| t + 0.1}              #=> 0.9999999999999999
 *    10.times.inject(0){|t,| t + Rational('0.1')}  #=> (1/1)
 *
 * However, when an expression has inexact factor (numerical value or
 * operation), will produce an inexact result.
 *
 *    Rational(10) / 3   #=> (10/3)
 *    Rational(10) / 3.0 #=> 3.3333333333333335
 *
 *    Rational(-8) ** Rational(1, 3)
 *                       #=> (1.0000000000000002+1.7320508075688772i)
 */
void
Init_Rational(void)
{
    VALUE compat;
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    assert(fprintf(stderr, "assert() is now active\n"));

    id_abs = rb_intern("abs");
    id_idiv = rb_intern("div");
    id_integer_p = rb_intern("integer?");
    id_to_i = rb_intern("to_i");
    id_i_num = rb_intern("@numerator");
    id_i_den = rb_intern("@denominator");

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

    rb_define_method(rb_cRational, "-@", rb_rational_uminus, 0);
    rb_define_method(rb_cRational, "+", rb_rational_plus, 1);
    rb_define_method(rb_cRational, "-", nurat_sub, 1);
    rb_define_method(rb_cRational, "*", nurat_mul, 1);
    rb_define_method(rb_cRational, "/", nurat_div, 1);
    rb_define_method(rb_cRational, "quo", nurat_div, 1);
    rb_define_method(rb_cRational, "fdiv", nurat_fdiv, 1);
    rb_define_method(rb_cRational, "**", nurat_expt, 1);

    rb_define_method(rb_cRational, "<=>", rb_rational_cmp, 1);
    rb_define_method(rb_cRational, "==", nurat_eqeq_p, 1);
    rb_define_method(rb_cRational, "coerce", nurat_coerce, 1);

#if 0
    rb_define_method(rb_cRational, "quot", nurat_quot, 1);
    rb_define_method(rb_cRational, "quotrem", nurat_quotrem, 1);
#endif

#if 0
    rb_define_method(rb_cRational, "rational?", nurat_true, 0);
    rb_define_method(rb_cRational, "exact?", nurat_true, 0);
#endif
    rb_define_method(rb_cRational, "positive?", nurat_positive_p, 0);
    rb_define_method(rb_cRational, "negative?", nurat_negative_p, 0);
    rb_define_method(rb_cRational, "abs", rb_rational_abs, 0);
    rb_define_method(rb_cRational, "magnitude", rb_rational_abs, 0);

    rb_define_method(rb_cRational, "floor", nurat_floor_n, -1);
    rb_define_method(rb_cRational, "ceil", nurat_ceil_n, -1);
    rb_define_method(rb_cRational, "truncate", nurat_truncate_n, -1);
    rb_define_method(rb_cRational, "round", nurat_round_n, -1);

    rb_define_method(rb_cRational, "to_i", nurat_truncate, 0);
    rb_define_method(rb_cRational, "to_f", nurat_to_f, 0);
    rb_define_method(rb_cRational, "to_r", nurat_to_r, 0);
    rb_define_method(rb_cRational, "rationalize", nurat_rationalize, -1);

    rb_define_method(rb_cRational, "hash", nurat_hash, 0);

    rb_define_method(rb_cRational, "to_s", nurat_to_s, 0);
    rb_define_method(rb_cRational, "inspect", nurat_inspect, 0);

    rb_define_private_method(rb_cRational, "marshal_dump", nurat_marshal_dump, 0);
    compat = rb_define_class_under(rb_cRational, "compatible", rb_cObject);
    rb_define_private_method(compat, "marshal_load", nurat_marshal_load, 1);
    rb_marshal_define_compat(rb_cRational, compat, nurat_dumper, nurat_loader);

    /* --- */

    rb_define_method(rb_cInteger, "gcd", rb_gcd, 1);
    rb_define_method(rb_cInteger, "lcm", rb_lcm, 1);
    rb_define_method(rb_cInteger, "gcdlcm", rb_gcdlcm, 1);

    rb_define_method(rb_cNumeric, "numerator", numeric_numerator, 0);
    rb_define_method(rb_cNumeric, "denominator", numeric_denominator, 0);
    rb_define_method(rb_cNumeric, "quo", numeric_quo, 1);

    rb_define_method(rb_cInteger, "numerator", integer_numerator, 0);
    rb_define_method(rb_cInteger, "denominator", integer_denominator, 0);

    rb_define_method(rb_cFloat, "numerator", float_numerator, 0);
    rb_define_method(rb_cFloat, "denominator", float_denominator, 0);

    rb_define_method(rb_cNilClass, "to_r", nilclass_to_r, 0);
    rb_define_method(rb_cNilClass, "rationalize", nilclass_rationalize, -1);
    rb_define_method(rb_cInteger, "to_r", integer_to_r, 0);
    rb_define_method(rb_cInteger, "rationalize", integer_rationalize, -1);
    rb_define_method(rb_cFloat, "to_r", float_to_r, 0);
    rb_define_method(rb_cFloat, "rationalize", float_rationalize, -1);

    rb_define_method(rb_cString, "to_r", string_to_r, 0);

    rb_define_private_method(CLASS_OF(rb_cRational), "convert", nurat_s_convert, -1);

    rb_provide("rational.so");	/* for backward compatibility */
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
