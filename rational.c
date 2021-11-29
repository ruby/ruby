/*
  rational.c: Coded by Tadayoshi Funaba 2008-2012

  This implementation is based on Keiju Ishitsuka's Rational library
  which is written in ruby.
*/

#include "ruby/internal/config.h"

#include <ctype.h>
#include <float.h>
#include <math.h>

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
#define USE_GMP
#include <gmp.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/complex.h"
#include "internal/gc.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/rational.h"
#include "ruby_assert.h"

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)

#define GMP_GCD_DIGITS 1

#define INT_ZERO_P(x) (FIXNUM_P(x) ? FIXNUM_ZERO_P(x) : rb_bigzero_p(x))

VALUE rb_cRational;

static ID id_abs, id_integer_p,
    id_i_num, id_i_den;

#define id_idiv idDiv
#define id_to_i idTo_i

#define f_inspect rb_inspect
#define f_to_s rb_obj_as_string

static VALUE nurat_to_f(VALUE self);
static VALUE float_to_r(VALUE self);

inline static VALUE
f_add(VALUE x, VALUE y)
{
    if (FIXNUM_ZERO_P(y))
	return x;
    if (FIXNUM_ZERO_P(x))
	return y;
    if (RB_INTEGER_TYPE_P(x))
        return rb_int_plus(x, y);
    return rb_funcall(x, '+', 1, y);
}

inline static VALUE
f_div(VALUE x, VALUE y)
{
    if (y == ONE)
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
    if (RB_INTEGER_TYPE_P(x)) {
        VALUE r = rb_int_cmp(x, y);
        if (!NIL_P(r)) return rb_int_negative_p(r);
    }
    return RTEST(rb_funcall(x, '<', 1, y));
}

#ifndef NDEBUG
/* f_mod is used only in f_gcd defined when NDEBUG is not defined */
inline static VALUE
f_mod(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x))
        return rb_int_modulo(x, y);
    return rb_funcall(x, '%', 1, y);
}
#endif

inline static VALUE
f_mul(VALUE x, VALUE y)
{
    if (FIXNUM_ZERO_P(y) && RB_INTEGER_TYPE_P(x))
	return ZERO;
    if (y == ONE) return x;
    if (FIXNUM_ZERO_P(x) && RB_INTEGER_TYPE_P(y))
	return ZERO;
    if (x == ONE) return y;
    else if (RB_INTEGER_TYPE_P(x))
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


inline static int
f_integer_p(VALUE x)
{
    return RB_INTEGER_TYPE_P(x);
}

inline static VALUE
f_to_i(VALUE x)
{
    if (RB_TYPE_P(x, T_STRING))
	return rb_str_to_inum(x, 10, 0);
    return rb_funcall(x, id_to_i, 0);
}

inline static int
f_eqeq_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return x == y;
    if (RB_INTEGER_TYPE_P(x))
        return RTEST(rb_int_equal(x, y));
    return (int)rb_equal(x, y);
}

inline static VALUE
f_idiv(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x))
	return rb_int_idiv(x, y);
    return rb_funcall(x, id_idiv, 1, y);
}

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
    else if (RB_BIGNUM_TYPE_P(x)) {
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

    mpz_clear(mx);
    mpz_clear(my);

    zn = (mpz_sizeinbase(mz, 16) + SIZEOF_BDIGIT*2 - 1) / (SIZEOF_BDIGIT*2);
    z = rb_big_new(zn, 1);
    mpz_export(BIGNUM_DIGITS(z), &count, -1, sizeof(BDIGIT), 0, nails, mz);

    mpz_clear(mz);

    return rb_big_norm(z);
}
#endif

#ifndef NDEBUG
#define f_gcd f_gcd_orig
#endif

inline static long
i_gcd(long x, long y)
{
    unsigned long u, v, t;
    int shift;

    if (x < 0)
	x = -x;
    if (y < 0)
	y = -y;

    if (x == 0)
	return y;
    if (y == 0)
	return x;

    u = (unsigned long)x;
    v = (unsigned long)y;
    for (shift = 0; ((u | v) & 1) == 0; ++shift) {
	u >>= 1;
	v >>= 1;
    }

    while ((u & 1) == 0)
	u >>= 1;

    do {
	while ((v & 1) == 0)
	    v >>= 1;

	if (u > v) {
	    t = v;
	    v = u;
	    u = t;
	}
	v = v - u;
    } while (v != 0);

    return (long)(u << shift);
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
    if (RB_BIGNUM_TYPE_P(x) && RB_BIGNUM_TYPE_P(y)) {
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

inline static VALUE
nurat_s_new_internal(VALUE klass, VALUE num, VALUE den)
{
    NEWOBJ_OF(obj, struct RRational, klass, T_RATIONAL | (RGENGC_WB_PROTECTED_RATIONAL ? FL_WB_PROTECTED : 0));

    RATIONAL_SET_NUM((VALUE)obj, num);
    RATIONAL_SET_DEN((VALUE)obj, den);
    OBJ_FREEZE_RAW((VALUE)obj);

    return (VALUE)obj;
}

static VALUE
nurat_s_alloc(VALUE klass)
{
    return nurat_s_new_internal(klass, ZERO, ONE);
}

inline static VALUE
f_rational_new_bang1(VALUE klass, VALUE x)
{
    return nurat_s_new_internal(klass, x, ONE);
}

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
    assert(num); assert(RB_INTEGER_TYPE_P(*num));
    assert(den); assert(RB_INTEGER_TYPE_P(*den));
    if (INT_NEGATIVE_P(*den)) {
        *num = rb_int_uminus(*num);
        *den = rb_int_uminus(*den);
    }
    else if (INT_ZERO_P(*den)) {
        rb_num_zerodiv();
    }
}

static void
nurat_reduce(VALUE *x, VALUE *y)
{
    VALUE gcd;
    if (*x == ONE || *y == ONE) return;
    gcd = f_gcd(*x, *y);
    *x = f_idiv(*x, gcd);
    *y = f_idiv(*y, gcd);
}

inline static VALUE
nurat_s_canonicalize_internal(VALUE klass, VALUE num, VALUE den)
{
    nurat_canonicalize(&num, &den);
    nurat_reduce(&num, &den);

    return nurat_s_new_internal(klass, num, den);
}

inline static VALUE
nurat_s_canonicalize_internal_no_reduce(VALUE klass, VALUE num, VALUE den)
{
    nurat_canonicalize(&num, &den);

    return nurat_s_new_internal(klass, num, den);
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

static VALUE nurat_convert(VALUE klass, VALUE numv, VALUE denv, int raise);
static VALUE nurat_s_convert(int argc, VALUE *argv, VALUE klass);

/*
 * call-seq:
 *    Rational(x, y, exception: true)  ->  rational or nil
 *    Rational(arg, exception: true)   ->  rational or nil
 *
 * Returns +x/y+ or +arg+ as a Rational.
 *
 *    Rational(2, 3)   #=> (2/3)
 *    Rational(5)      #=> (5/1)
 *    Rational(0.5)    #=> (1/2)
 *    Rational(0.3)    #=> (5404319552844595/18014398509481984)
 *
 *    Rational("2/3")  #=> (2/3)
 *    Rational("0.3")  #=> (3/10)
 *
 *    Rational("10 cents")  #=> ArgumentError
 *    Rational(nil)         #=> TypeError
 *    Rational(1, nil)      #=> TypeError
 *
 *    Rational("10 cents", exception: false)  #=> nil
 *
 * Syntax of the string form:
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
 * See also String#to_r.
 */
static VALUE
nurat_f_rational(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, opts = Qnil;
    int raise = TRUE;

    if (rb_scan_args(argc, argv, "11:", &a1, &a2, &opts) == 1) {
        a2 = Qundef;
    }
    if (!NIL_P(opts)) {
        raise = rb_opts_exception_p(opts, raise);
    }
    return nurat_convert(rb_cRational, a1, a2, raise);
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
    else if (RB_INTEGER_TYPE_P(anum) && RB_INTEGER_TYPE_P(aden) &&
             RB_INTEGER_TYPE_P(bnum) && RB_INTEGER_TYPE_P(bden)) {
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
    else {
        double a = NUM2DBL(anum) / NUM2DBL(aden);
        double b = NUM2DBL(bnum) / NUM2DBL(bden);
        double c = k == '+' ? a + b : a - b;
        return DBL2NUM(c);
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
 *    Rational(900)   + Rational(1)      #=> (901/1)
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
 *    Rational(9, 8)  - 4                #=> (-23/8)
 *    Rational(20, 9) - 9.8              #=> -7.577777777777778
 */
VALUE
rb_rational_minus(VALUE self, VALUE other)
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

    /* Integer#** can return Rational with Float right now */
    if (RB_FLOAT_TYPE_P(anum) || RB_FLOAT_TYPE_P(aden) ||
        RB_FLOAT_TYPE_P(bnum) || RB_FLOAT_TYPE_P(bden)) {
        double an = NUM2DBL(anum), ad = NUM2DBL(aden);
        double bn = NUM2DBL(bnum), bd = NUM2DBL(bden);
        double x = (an * bn) / (ad * bd);
        return DBL2NUM(x);
    }

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
VALUE
rb_rational_mul(VALUE self, VALUE other)
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
VALUE
rb_rational_div(VALUE self, VALUE other)
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
    else if (RB_FLOAT_TYPE_P(other)) {
        VALUE v = nurat_to_f(self);
        return rb_flo_div_flo(v, other);
    }
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

/*
 * call-seq:
 *    rat.fdiv(numeric)  ->  float
 *
 * Performs division and returns the value as a Float.
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
        return rb_rational_div(self, rb_float_new(0.0));
    if (FIXNUM_P(other) && other == LONG2FIX(1))
	return nurat_to_f(self);
    div = rb_rational_div(self, other);
    if (RB_TYPE_P(div, T_RATIONAL))
	return nurat_to_f(div);
    if (RB_FLOAT_TYPE_P(div))
	return div;
    return rb_funcall(div, idTo_f, 0);
}

/*
 * call-seq:
 *    rat ** numeric  ->  numeric
 *
 * Performs exponentiation.
 *
 *    Rational(2)    ** Rational(3)     #=> (8/1)
 *    Rational(10)   ** -2              #=> (1/100)
 *    Rational(10)   ** -2.0            #=> 0.01
 *    Rational(-4)   ** Rational(1, 2)  #=> (0.0+2.0i)
 *    Rational(1, 2) ** 0               #=> (1/1)
 *    Rational(1, 2) ** 0.0             #=> 1.0
 */
VALUE
rb_rational_pow(VALUE self, VALUE other)
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
		return f_rational_new_bang1(CLASS_OF(self), INT2FIX(rb_int_odd_p(other) ? -1 : 1));
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
	    if (RB_FLOAT_TYPE_P(num)) { /* infinity due to overflow */
		if (RB_FLOAT_TYPE_P(den))
		    return DBL2NUM(nan(""));
		return num;
	    }
	    if (RB_FLOAT_TYPE_P(den)) { /* infinity due to overflow */
		num = ZERO;
		den = ONE;
	    }
	    return f_rational_new2(CLASS_OF(self), num, den);
	}
    }
    else if (RB_BIGNUM_TYPE_P(other)) {
	rb_warn("in a**b, b may be too big");
	return rb_float_pow(nurat_to_f(self), other);
    }
    else if (RB_FLOAT_TYPE_P(other) || RB_TYPE_P(other, T_RATIONAL)) {
	return rb_float_pow(nurat_to_f(self), other);
    }
    else {
	return rb_num_coerce_bin(self, other, idPow);
    }
}
#define nurat_expt rb_rational_pow

/*
 * call-seq:
 *    rational <=> numeric  ->  -1, 0, +1, or nil
 *
 * Returns -1, 0, or +1 depending on whether +rational+ is
 * less than, equal to, or greater than +numeric+.
 *
 * +nil+ is returned if the two values are incomparable.
 *
 *    Rational(2, 3) <=> Rational(2, 3)  #=> 0
 *    Rational(5)    <=> 5               #=> 0
 *    Rational(2, 3) <=> Rational(1, 3)  #=> 1
 *    Rational(1, 3) <=> 1               #=> -1
 *    Rational(1, 3) <=> 0.3             #=> 1
 *
 *    Rational(1, 3) <=> "0.3"           #=> nil
 */
VALUE
rb_rational_cmp(VALUE self, VALUE other)
{
    switch (TYPE(other)) {
      case T_FIXNUM:
      case T_BIGNUM:
	{
	    get_dat1(self);

	    if (dat->den == LONG2FIX(1))
		return rb_int_cmp(dat->num, other); /* c14n */
	    other = f_rational_new_bang1(CLASS_OF(self), other);
            /* FALLTHROUGH */
	}

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
		num1 = rb_int_mul(adat->num, bdat->den);
		num2 = rb_int_mul(bdat->num, adat->den);
	    }
	    return rb_int_cmp(rb_int_minus(num1, num2), ZERO);
	}

      case T_FLOAT:
        return rb_dbl_cmp(nurat_to_double(self), RFLOAT_VALUE(other));

      default:
	return rb_num_coerce_cmp(self, other, idCmp);
    }
}

/*
 * call-seq:
 *    rat == object  ->  true or false
 *
 * Returns +true+ if +rat+ equals +object+ numerically.
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
        get_dat1(self);

        if (RB_INTEGER_TYPE_P(dat->num) && RB_INTEGER_TYPE_P(dat->den)) {
	    if (INT_ZERO_P(dat->num) && INT_ZERO_P(other))
		return Qtrue;

	    if (!FIXNUM_P(dat->den))
		return Qfalse;
	    if (FIX2LONG(dat->den) != 1)
		return Qfalse;
	    return rb_int_equal(dat->num, other);
	}
        else {
            const double d = nurat_to_double(self);
            return RBOOL(FIXNUM_ZERO_P(rb_dbl_cmp(d, NUM2DBL(other))));
        }
    }
    else if (RB_FLOAT_TYPE_P(other)) {
	const double d = nurat_to_double(self);
	return RBOOL(FIXNUM_ZERO_P(rb_dbl_cmp(d, RFLOAT_VALUE(other))));
    }
    else if (RB_TYPE_P(other, T_RATIONAL)) {
	{
	    get_dat2(self, other);

	    if (INT_ZERO_P(adat->num) && INT_ZERO_P(bdat->num))
		return Qtrue;

	    return RBOOL(rb_int_equal(adat->num, bdat->num) &&
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
	if (!k_exact_zero_p(RCOMPLEX(other)->imag))
	    return rb_assoc_new(other, rb_Complex(self, INT2FIX(0)));
        other = RCOMPLEX(other)->real;
        if (RB_FLOAT_TYPE_P(other)) {
            other = float_to_r(other);
            RBASIC_SET_CLASS(other, CLASS_OF(self));
        }
        else {
            other = f_rational_new_bang1(CLASS_OF(self), other);
        }
        return rb_assoc_new(other, self);
    }

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_obj_classname(other), rb_obj_classname(self));
    return Qnil;
}

/*
 *  call-seq:
 *     rat.positive?  ->  true or false
 *
 *  Returns +true+ if +rat+ is greater than 0.
 */
static VALUE
nurat_positive_p(VALUE self)
{
    get_dat1(self);
    return RBOOL(INT_POSITIVE_P(dat->num));
}

/*
 *  call-seq:
 *     rat.negative?  ->  true or false
 *
 *  Returns +true+ if +rat+ is less than 0.
 */
static VALUE
nurat_negative_p(VALUE self)
{
    get_dat1(self);
    return RBOOL(INT_NEGATIVE_P(dat->num));
}

/*
 *  call-seq:
 *     rat.abs        ->  rational
 *     rat.magnitude  ->  rational
 *
 *  Returns the absolute value of +rat+.
 *
 *     (1/2r).abs    #=> (1/2)
 *     (-1/2r).abs   #=> (1/2)
 *
 *  Rational#magnitude is an alias for Rational#abs.
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
 * Equivalent to Rational#truncate.
 *
 *    Rational(2, 3).to_i    #=> 0
 *    Rational(3).to_i       #=> 3
 *    Rational(300.6).to_i   #=> 300
 *    Rational(98, 71).to_i  #=> 1
 *    Rational(-31, 2).to_i  #=> -15
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

    if (rb_check_arity(argc, 0, 1) == 0)
	return (*func)(self);

    n = argv[0];

    if (!k_integer_p(n))
	rb_raise(rb_eTypeError, "not an integer");

    b = f_expt10(n);
    s = rb_rational_mul(self, b);

    if (k_float_p(s)) {
	if (INT_NEGATIVE_P(n))
	    return ZERO;
	return self;
    }

    if (!k_rational_p(s)) {
	s = f_rational_new_bang1(CLASS_OF(self), s);
    }

    s = (*func)(s);

    s = rb_rational_div(f_rational_new_bang1(CLASS_OF(self), s), b);

    if (RB_TYPE_P(s, T_RATIONAL) && FIX2INT(rb_int_cmp(n, ONE)) < 0)
	s = nurat_truncate(s);

    return s;
}

VALUE
rb_rational_floor(VALUE self, int ndigits)
{
    if (ndigits == 0) {
        return nurat_floor(self);
    }
    else {
        VALUE n = INT2NUM(ndigits);
        return f_round_common(1, &n, self, nurat_floor);
    }
}

/*
 * call-seq:
 *    rat.floor([ndigits])  ->  integer or rational
 *
 * Returns the largest number less than or equal to +rat+ with
 * a precision of +ndigits+ decimal digits (default: 0).
 *
 * When the precision is negative, the returned value is an integer
 * with at least <code>ndigits.abs</code> trailing zeros.
 *
 * Returns a rational when +ndigits+ is positive,
 * otherwise returns an integer.
 *
 *    Rational(3).floor      #=> 3
 *    Rational(2, 3).floor   #=> 0
 *    Rational(-3, 2).floor  #=> -2
 *
 *      #    decimal      -  1  2  3 . 4  5  6
 *      #                   ^  ^  ^  ^   ^  ^
 *      #   precision      -3 -2 -1  0  +1 +2
 *
 *    Rational('-123.456').floor(+1).to_f  #=> -123.5
 *    Rational('-123.456').floor(-1)       #=> -130
 */
static VALUE
nurat_floor_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_floor);
}

/*
 * call-seq:
 *    rat.ceil([ndigits])  ->  integer or rational
 *
 * Returns the smallest number greater than or equal to +rat+ with
 * a precision of +ndigits+ decimal digits (default: 0).
 *
 * When the precision is negative, the returned value is an integer
 * with at least <code>ndigits.abs</code> trailing zeros.
 *
 * Returns a rational when +ndigits+ is positive,
 * otherwise returns an integer.
 *
 *    Rational(3).ceil      #=> 3
 *    Rational(2, 3).ceil   #=> 1
 *    Rational(-3, 2).ceil  #=> -1
 *
 *      #    decimal      -  1  2  3 . 4  5  6
 *      #                   ^  ^  ^  ^   ^  ^
 *      #   precision      -3 -2 -1  0  +1 +2
 *
 *    Rational('-123.456').ceil(+1).to_f  #=> -123.4
 *    Rational('-123.456').ceil(-1)       #=> -120
 */
static VALUE
nurat_ceil_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_ceil);
}

/*
 * call-seq:
 *    rat.truncate([ndigits])  ->  integer or rational
 *
 * Returns +rat+ truncated (toward zero) to
 * a precision of +ndigits+ decimal digits (default: 0).
 *
 * When the precision is negative, the returned value is an integer
 * with at least <code>ndigits.abs</code> trailing zeros.
 *
 * Returns a rational when +ndigits+ is positive,
 * otherwise returns an integer.
 *
 *    Rational(3).truncate      #=> 3
 *    Rational(2, 3).truncate   #=> 0
 *    Rational(-3, 2).truncate  #=> -1
 *
 *      #    decimal      -  1  2  3 . 4  5  6
 *      #                   ^  ^  ^  ^   ^  ^
 *      #   precision      -3 -2 -1  0  +1 +2
 *
 *    Rational('-123.456').truncate(+1).to_f  #=> -123.4
 *    Rational('-123.456').truncate(-1)       #=> -120
 */
static VALUE
nurat_truncate_n(int argc, VALUE *argv, VALUE self)
{
    return f_round_common(argc, argv, self, nurat_truncate);
}

/*
 * call-seq:
 *    rat.round([ndigits] [, half: mode])  ->  integer or rational
 *
 * Returns +rat+ rounded to the nearest value with
 * a precision of +ndigits+ decimal digits (default: 0).
 *
 * When the precision is negative, the returned value is an integer
 * with at least <code>ndigits.abs</code> trailing zeros.
 *
 * Returns a rational when +ndigits+ is positive,
 * otherwise returns an integer.
 *
 *    Rational(3).round      #=> 3
 *    Rational(2, 3).round   #=> 1
 *    Rational(-3, 2).round  #=> -2
 *
 *      #    decimal      -  1  2  3 . 4  5  6
 *      #                   ^  ^  ^  ^   ^  ^
 *      #   precision      -3 -2 -1  0  +1 +2
 *
 *    Rational('-123.456').round(+1).to_f  #=> -123.5
 *    Rational('-123.456').round(-1)       #=> -120
 *
 * The optional +half+ keyword argument is available
 * similar to Float#round.
 *
 *    Rational(25, 100).round(1, half: :up)    #=> (3/10)
 *    Rational(25, 100).round(1, half: :down)  #=> (1/5)
 *    Rational(25, 100).round(1, half: :even)  #=> (1/5)
 *    Rational(35, 100).round(1, half: :up)    #=> (2/5)
 *    Rational(35, 100).round(1, half: :down)  #=> (3/10)
 *    Rational(35, 100).round(1, half: :even)  #=> (2/5)
 *    Rational(-25, 100).round(1, half: :up)   #=> (-3/10)
 *    Rational(-25, 100).round(1, half: :down) #=> (-1/5)
 *    Rational(-25, 100).round(1, half: :even) #=> (-1/5)
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

VALUE
rb_flo_round_by_rational(int argc, VALUE *argv, VALUE num)
{
    return nurat_to_f(nurat_round_n(argc, argv, float_to_r(num)));
}

static double
nurat_to_double(VALUE self)
{
    get_dat1(self);
    if (!RB_INTEGER_TYPE_P(dat->num) || !RB_INTEGER_TYPE_P(dat->den)) {
        return NUM2DBL(dat->num) / NUM2DBL(dat->den);
    }
    return rb_int_fdiv_double(dat->num, dat->den);
}

/*
 * call-seq:
 *    rat.to_f  ->  float
 *
 * Returns the value as a Float.
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
static VALUE
f_ceil(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x))
        return x;
    if (RB_FLOAT_TYPE_P(x))
        return rb_float_ceil(x, 0);

    return rb_funcall(x, id_ceil, 0);
}

#define id_quo idQuo
static VALUE
f_quo(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x))
        return rb_int_div(x, y);
    if (RB_FLOAT_TYPE_P(x))
        return DBL2NUM(RFLOAT_VALUE(x) / RFLOAT_VALUE(y));

    return rb_funcallv(x, id_quo, 1, &y);
}

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
 * argument +eps+ is given (rat-|eps| <= result <= rat+|eps|),
 * self otherwise.
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
    VALUE rat = self;
    get_dat1(self);

    if (rb_check_arity(argc, 0, 1) == 0)
	return self;

    e = f_abs(argv[0]);

    if (INT_NEGATIVE_P(dat->num)) {
        rat = f_rational_new2(RBASIC_CLASS(self), rb_int_uminus(dat->num), dat->den);
    }

    a = FIXNUM_ZERO_P(e) ? rat : rb_rational_minus(rat, e);
    b = FIXNUM_ZERO_P(e) ? rat : rb_rational_plus(rat, e);

    if (f_eqeq_p(a, b))
	return self;

    nurat_rationalize_internal(a, b, &p, &q);
    if (rat != self) {
        RATIONAL_SET_NUM(rat, rb_int_uminus(p));
        RATIONAL_SET_DEN(rat, q);
        return rat;
    }
    return f_rational_new2(CLASS_OF(self), p, q);
}

/* :nodoc: */
st_index_t
rb_rational_hash(VALUE self)
{
    st_index_t v, h[2];
    VALUE n;

    get_dat1(self);
    n = rb_hash(dat->num);
    h[0] = NUM2LONG(n);
    n = rb_hash(dat->den);
    h[1] = NUM2LONG(n);
    v = rb_memhash(h, sizeof(h));
    return v;
}

static VALUE
nurat_hash(VALUE self)
{
    return ST2FIX(rb_rational_hash(self));
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
    RATIONAL_SET_NUM((VALUE)dat, num);
    RATIONAL_SET_DEN((VALUE)dat, den);
    OBJ_FREEZE_RAW(self);

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

VALUE
rb_rational_reciprocal(VALUE x)
{
    get_dat1(x);
    return nurat_convert(CLASS_OF(x), dat->den, dat->num, FALSE);
}

/*
 * call-seq:
 *    int.gcd(other_int)  ->  integer
 *
 * Returns the greatest common divisor of the two integers.
 * The result is always positive. 0.gcd(x) and x.gcd(0) return x.abs.
 *
 *    36.gcd(60)                  #=> 12
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
 *    int.lcm(other_int)  ->  integer
 *
 * Returns the least common multiple of the two integers.
 * The result is always positive. 0.lcm(x) and x.lcm(0) return zero.
 *
 *    36.lcm(60)                  #=> 180
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
 *    int.gcdlcm(other_int)  ->  array
 *
 * Returns an array with the greatest common divisor and
 * the least common multiple of the two integers, [gcd, lcm].
 *
 *    36.gcdlcm(60)                  #=> [12, 180]
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
    if (! RB_INTEGER_TYPE_P(x))
        x = rb_to_int(x);
    if (! RB_INTEGER_TYPE_P(y))
        y = rb_to_int(y);
    if (INT_NEGATIVE_P(y)) {
        x = rb_int_uminus(x);
        y = rb_int_uminus(y);
    }
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

#define id_to_r idTo_r
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
 *  Returns the most exact division (rational for integers, float for floats).
 */

VALUE
rb_numeric_quo(VALUE x, VALUE y)
{
    if (RB_TYPE_P(x, T_COMPLEX)) {
        return rb_complex_div(x, y);
    }

    if (RB_FLOAT_TYPE_P(y)) {
        return rb_funcallv(x, idFdiv, 1, &y);
    }

    x = rb_convert_type(x, T_RATIONAL, "Rational", "to_r");
    return rb_rational_div(x, y);
}

VALUE
rb_rational_canonicalize(VALUE x)
{
    if (RB_TYPE_P(x, T_RATIONAL)) {
        get_dat1(x);
        if (f_one_p(dat->den)) return dat->num;
    }
    return x;
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

/*
 * call-seq:
 *    flo.numerator  ->  integer
 *
 * Returns the numerator.  The result is machine dependent.
 *
 *    n = 0.3.numerator    #=> 5404319552844595
 *    d = 0.3.denominator  #=> 18014398509481984
 *    n.fdiv(d)            #=> 0.3
 *
 * See also Float#denominator.
 */
VALUE
rb_float_numerator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    VALUE r;
    if (!isfinite(d))
	return self;
    r = float_to_r(self);
    return nurat_numerator(r);
}

/*
 * call-seq:
 *    flo.denominator  ->  integer
 *
 * Returns the denominator (always positive).  The result is machine
 * dependent.
 *
 * See also Float#numerator.
 */
VALUE
rb_float_denominator(VALUE self)
{
    double d = RFLOAT_VALUE(self);
    VALUE r;
    if (!isfinite(d))
	return INT2FIX(1);
    r = float_to_r(self);
    return nurat_denominator(r);
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
 * Returns zero as a rational.  The optional argument +eps+ is always
 * ignored.
 */
static VALUE
nilclass_rationalize(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
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
 * Returns the value as a rational.  The optional argument +eps+ is
 * always ignored.
 */
static VALUE
integer_rationalize(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    return integer_to_r(self);
}

static void
float_decode_internal(VALUE self, VALUE *rf, int *n)
{
    double f;

    f = frexp(RFLOAT_VALUE(self), n);
    f = ldexp(f, DBL_MANT_DIG);
    *n -= DBL_MANT_DIG;
    *rf = rb_dbl2big(f);
}

/*
 * call-seq:
 *    flt.to_r  ->  rational
 *
 * Returns the value as a rational.
 *
 *    2.0.to_r    #=> (2/1)
 *    2.5.to_r    #=> (5/2)
 *    -0.75.to_r  #=> (-3/4)
 *    0.0.to_r    #=> (0/1)
 *    0.3.to_r    #=> (5404319552844595/18014398509481984)
 *
 * NOTE: 0.3.to_r isn't the same as "0.3".to_r.  The latter is
 * equivalent to "3/10".to_r, but the former isn't so.
 *
 *    0.3.to_r   == 3/10r  #=> false
 *    "0.3".to_r == 3/10r  #=> true
 *
 * See also Float#rationalize.
 */
static VALUE
float_to_r(VALUE self)
{
    VALUE f;
    int n;

    float_decode_internal(self, &f, &n);
#if FLT_RADIX == 2
    if (n == 0)
        return rb_rational_new1(f);
    if (n > 0)
        return rb_rational_new1(rb_int_lshift(f, INT2FIX(n)));
    n = -n;
    return rb_rational_new2(f, rb_int_lshift(ONE, INT2FIX(n)));
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
    VALUE a, b, f, p, q, den;
    int n;

    float_decode_internal(flt, &f, &n);
    if (INT_ZERO_P(f) || n >= 0)
        return rb_rational_new1(rb_int_lshift(f, INT2FIX(n)));

    {
        VALUE radix_times_f;

        radix_times_f = rb_int_mul(INT2FIX(FLT_RADIX), f);
#if FLT_RADIX == 2 && 0
        den = rb_int_lshift(ONE, INT2FIX(1-n));
#else
        den = rb_int_positive_pow(FLT_RADIX, 1-n);
#endif

        a = rb_int_minus(radix_times_f, INT2FIX(FLT_RADIX - 1));
        b = rb_int_plus(radix_times_f, INT2FIX(FLT_RADIX - 1));
    }

    if (f_eqeq_p(a, b))
        return float_to_r(flt);

    a = rb_rational_new2(a, den);
    b = rb_rational_new2(b, den);
    nurat_rationalize_internal(a, b, &p, &q);
    return rb_rational_new2(p, q);
}

/*
 * call-seq:
 *    flt.rationalize([eps])  ->  rational
 *
 * Returns a simpler approximation of the value (flt-|eps| <= result
 * <= flt+|eps|).  If the optional argument +eps+ is not given,
 * it will be chosen automatically.
 *
 *    0.3.rationalize          #=> (3/10)
 *    1.333.rationalize        #=> (1333/1000)
 *    1.333.rationalize(0.01)  #=> (4/3)
 *
 * See also Float#to_r.
 */
static VALUE
float_rationalize(int argc, VALUE *argv, VALUE self)
{
    double d = RFLOAT_VALUE(self);
    VALUE rat;
    int neg = d < 0.0;
    if (neg) self = DBL2NUM(-d);

    if (rb_check_arity(argc, 0, 1)) {
        rat = rb_flt_rationalize_with_prec(self, argv[0]);
    }
    else {
        rat = rb_flt_rationalize(self);
    }
    if (neg) RATIONAL_SET_NUM(rat, rb_int_uminus(RRATIONAL(rat)->num));
    return rat;
}

inline static int
issign(int c)
{
    return (c == '-' || c == '+');
}

static int
read_sign(const char **s, const char *const e)
{
    int sign = '?';

    if (*s < e && issign(**s)) {
	sign = **s;
	(*s)++;
    }
    return sign;
}

inline static int
islettere(int c)
{
    return (c == 'e' || c == 'E');
}

static VALUE
negate_num(VALUE num)
{
    if (FIXNUM_P(num)) {
	return rb_int_uminus(num);
    }
    else {
	BIGNUM_NEGATE(num);
	return rb_big_norm(num);
    }
}

static int
read_num(const char **s, const char *const end, VALUE *num, VALUE *nexp)
{
    VALUE fp = ONE, exp, fn = ZERO, n = ZERO;
    int expsign = 0, ok = 0;
    char *e;

    *nexp = ZERO;
    *num = ZERO;
    if (*s < end && **s != '.') {
	n = rb_int_parse_cstr(*s, end-*s, &e, NULL,
			      10, RB_INT_PARSE_UNDERSCORE);
	if (NIL_P(n))
	    return 0;
	*s = e;
	*num = n;
	ok = 1;
    }

    if (*s < end && **s == '.') {
	size_t count = 0;

	(*s)++;
	fp = rb_int_parse_cstr(*s, end-*s, &e, &count,
			       10, RB_INT_PARSE_UNDERSCORE);
	if (NIL_P(fp))
	    return 1;
	*s = e;
	{
            VALUE l = f_expt10(*nexp = SIZET2NUM(count));
	    n = n == ZERO ? fp : rb_int_plus(rb_int_mul(*num, l), fp);
	    *num = n;
	    fn = SIZET2NUM(count);
	}
	ok = 1;
    }

    if (ok && *s + 1 < end && islettere(**s)) {
	(*s)++;
	expsign = read_sign(s, end);
	exp = rb_int_parse_cstr(*s, end-*s, &e, NULL,
				10, RB_INT_PARSE_UNDERSCORE);
	if (NIL_P(exp))
	    return 1;
	*s = e;
	if (exp != ZERO) {
	    if (expsign == '-') {
		if (fn != ZERO) exp = rb_int_plus(exp, fn);
	    }
	    else {
		if (fn != ZERO) exp = rb_int_minus(exp, fn);
                exp = negate_num(exp);
	    }
            *nexp = exp;
	}
    }

    return ok;
}

inline static const char *
skip_ws(const char *s, const char *e)
{
    while (s < e && isspace((unsigned char)*s))
	++s;
    return s;
}

static VALUE
parse_rat(const char *s, const char *const e, int strict, int raise)
{
    int sign;
    VALUE num, den, nexp, dexp;

    s = skip_ws(s, e);
    sign = read_sign(&s, e);

    if (!read_num(&s, e, &num, &nexp)) {
	if (strict) return Qnil;
	return nurat_s_alloc(rb_cRational);
    }
    den = ONE;
    if (s < e && *s == '/') {
	s++;
        if (!read_num(&s, e, &den, &dexp)) {
	    if (strict) return Qnil;
            den = ONE;
	}
	else if (den == ZERO) {
            if (!raise) return Qnil;
	    rb_num_zerodiv();
	}
	else if (strict && skip_ws(s, e) != e) {
	    return Qnil;
	}
	else {
            nexp = rb_int_minus(nexp, dexp);
	    nurat_reduce(&num, &den);
	}
    }
    else if (strict && skip_ws(s, e) != e) {
	return Qnil;
    }

    if (nexp != ZERO) {
        if (INT_NEGATIVE_P(nexp)) {
            VALUE mul;
            if (FIXNUM_P(nexp)) {
                mul = f_expt10(LONG2NUM(-FIX2LONG(nexp)));
                if (! RB_FLOAT_TYPE_P(mul)) {
                    num = rb_int_mul(num, mul);
                    goto reduce;
                }
            }
            return sign == '-' ? DBL2NUM(-HUGE_VAL) : DBL2NUM(HUGE_VAL);
        }
        else {
            VALUE div;
            if (FIXNUM_P(nexp)) {
                div = f_expt10(nexp);
                if (! RB_FLOAT_TYPE_P(div)) {
                    den = rb_int_mul(den, div);
                    goto reduce;
                }
            }
            return sign == '-' ? DBL2NUM(-0.0) : DBL2NUM(+0.0);
        }
      reduce:
        nurat_reduce(&num, &den);
    }

    if (sign == '-') {
	num = negate_num(num);
    }

    return rb_rational_raw(num, den);
}

static VALUE
string_to_r_strict(VALUE self, int raise)
{
    VALUE num;

    rb_must_asciicompat(self);

    num = parse_rat(RSTRING_PTR(self), RSTRING_END(self), 1, raise);
    if (NIL_P(num)) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for convert(): %+"PRIsVALUE,
                 self);
    }

    if (RB_FLOAT_TYPE_P(num) && !FLOAT_ZERO_P(num)) {
        if (!raise) return Qnil;
        rb_raise(rb_eFloatDomainError, "Infinity");
    }
    return num;
}

/*
 * call-seq:
 *    str.to_r  ->  rational
 *
 * Returns the result of interpreting leading characters in +str+
 * as a rational.  Leading whitespace and extraneous characters
 * past the end of a valid number are ignored.
 * Digit sequences can be separated by an underscore.
 * If there is not a valid number at the start of +str+,
 * zero is returned.  This method never raises an exception.
 *
 *    '  2  '.to_r       #=> (2/1)
 *    '300/2'.to_r       #=> (150/1)
 *    '-9.2'.to_r        #=> (-46/5)
 *    '-9.2e2'.to_r      #=> (-920/1)
 *    '1_234_567'.to_r   #=> (1234567/1)
 *    '21 June 09'.to_r  #=> (21/1)
 *    '21/06/09'.to_r    #=> (7/2)
 *    'BWV 1079'.to_r    #=> (0/1)
 *
 * NOTE: "0.3".to_r isn't the same as 0.3.to_r.  The former is
 * equivalent to "3/10".to_r, but the latter isn't so.
 *
 *    "0.3".to_r == 3/10r  #=> true
 *    0.3.to_r   == 3/10r  #=> false
 *
 * See also Kernel#Rational.
 */
static VALUE
string_to_r(VALUE self)
{
    VALUE num;

    rb_must_asciicompat(self);

    num = parse_rat(RSTRING_PTR(self), RSTRING_END(self), 0, TRUE);

    if (RB_FLOAT_TYPE_P(num) && !FLOAT_ZERO_P(num))
	rb_raise(rb_eFloatDomainError, "Infinity");
    return num;
}

VALUE
rb_cstr_to_rat(const char *s, int strict) /* for complex's internal */
{
    VALUE num;

    num = parse_rat(s, s + strlen(s), strict, TRUE);

    if (RB_FLOAT_TYPE_P(num) && !FLOAT_ZERO_P(num))
	rb_raise(rb_eFloatDomainError, "Infinity");
    return num;
}

static VALUE
to_rational(VALUE val)
{
    return rb_convert_type_with_id(val, T_RATIONAL, "Rational", idTo_r);
}

static VALUE
nurat_convert(VALUE klass, VALUE numv, VALUE denv, int raise)
{
    VALUE a1 = numv, a2 = denv;
    int state;

    assert(a1 != Qundef);

    if (NIL_P(a1) || NIL_P(a2)) {
        if (!raise) return Qnil;
        rb_raise(rb_eTypeError, "can't convert nil into Rational");
    }

    if (RB_TYPE_P(a1, T_COMPLEX)) {
        if (k_exact_zero_p(RCOMPLEX(a1)->imag))
            a1 = RCOMPLEX(a1)->real;
    }

    if (RB_TYPE_P(a2, T_COMPLEX)) {
        if (k_exact_zero_p(RCOMPLEX(a2)->imag))
            a2 = RCOMPLEX(a2)->real;
    }

    if (RB_INTEGER_TYPE_P(a1)) {
        // nothing to do
    }
    else if (RB_FLOAT_TYPE_P(a1)) {
        a1 = float_to_r(a1);
    }
    else if (RB_TYPE_P(a1, T_RATIONAL)) {
        // nothing to do
    }
    else if (RB_TYPE_P(a1, T_STRING)) {
        a1 = string_to_r_strict(a1, raise);
        if (!raise && NIL_P(a1)) return Qnil;
    }
    else if (!rb_respond_to(a1, idTo_r)) {
        VALUE tmp = rb_protect(rb_check_to_int, a1, NULL);
        rb_set_errinfo(Qnil);
        if (!NIL_P(tmp)) {
            a1 = tmp;
        }
    }

    if (RB_INTEGER_TYPE_P(a2)) {
        // nothing to do
    }
    else if (RB_FLOAT_TYPE_P(a2)) {
        a2 = float_to_r(a2);
    }
    else if (RB_TYPE_P(a2, T_RATIONAL)) {
        // nothing to do
    }
    else if (RB_TYPE_P(a2, T_STRING)) {
        a2 = string_to_r_strict(a2, raise);
        if (!raise && NIL_P(a2)) return Qnil;
    }
    else if (a2 != Qundef && !rb_respond_to(a2, idTo_r)) {
        VALUE tmp = rb_protect(rb_check_to_int, a2, NULL);
        rb_set_errinfo(Qnil);
        if (!NIL_P(tmp)) {
            a2 = tmp;
        }
    }

    if (RB_TYPE_P(a1, T_RATIONAL)) {
        if (a2 == Qundef || (k_exact_one_p(a2)))
            return a1;
    }

    if (a2 == Qundef) {
        if (!RB_INTEGER_TYPE_P(a1)) {
            if (!raise) {
                VALUE result = rb_protect(to_rational, a1, NULL);
                rb_set_errinfo(Qnil);
                return result;
            }
            return to_rational(a1);
        }
    }
    else {
        if (!k_numeric_p(a1)) {
            if (!raise) {
                a1 = rb_protect(to_rational, a1, &state);
                if (state) {
                    rb_set_errinfo(Qnil);
                    return Qnil;
                }
            }
            else {
                a1 = rb_check_convert_type_with_id(a1, T_RATIONAL, "Rational", idTo_r);
            }
        }
        if (!k_numeric_p(a2)) {
            if (!raise) {
                a2 = rb_protect(to_rational, a2, &state);
                if (state) {
                    rb_set_errinfo(Qnil);
                    return Qnil;
                }
            }
            else {
                a2 = rb_check_convert_type_with_id(a2, T_RATIONAL, "Rational", idTo_r);
            }
        }
        if ((k_numeric_p(a1) && k_numeric_p(a2)) &&
                (!f_integer_p(a1) || !f_integer_p(a2))) {
            VALUE tmp = rb_protect(to_rational, a1, &state);
            if (!state) {
                a1 = tmp;
            }
            else {
                rb_set_errinfo(Qnil);
            }
            return f_div(a1, a2);
        }
    }

    a1 = nurat_int_value(a1);

    if (a2 == Qundef) {
        a2 = ONE;
    }
    else if (!k_integer_p(a2) && !raise) {
        return Qnil;
    }
    else {
        a2 = nurat_int_value(a2);
    }


    return nurat_s_canonicalize_internal(klass, a1, a2);
}

static VALUE
nurat_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2;

    if (rb_scan_args(argc, argv, "11", &a1, &a2) == 1) {
        a2 = Qundef;
    }

    return nurat_convert(klass, a1, a2, TRUE);
}

/*
 * A rational number can be represented as a pair of integer numbers:
 * a/b (b>0), where a is the numerator and b is the denominator.
 * Integer a equals rational a/1 mathematically.
 *
 * You can create a \Rational object explicitly with:
 *
 * - A {rational literal}[doc/syntax/literals_rdoc.html#label-Rational+Literals].
 *
 * You can convert certain objects to Rationals with:
 *
 * - \Method {Rational}[Kernel.html#method-i-Rational].
 *
 * Examples
 *
 *    Rational(1)      #=> (1/1)
 *    Rational(2, 3)   #=> (2/3)
 *    Rational(4, -6)  #=> (-2/3) # Reduced.
 *    3.to_r           #=> (3/1)
 *    2/3r             #=> (2/3)
 *
 * You can also create rational objects from floating-point numbers or
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
 * programs without any rounding errors.
 *
 *    10.times.inject(0) {|t| t + 0.1 }              #=> 0.9999999999999999
 *    10.times.inject(0) {|t| t + Rational('0.1') }  #=> (1/1)
 *
 * However, when an expression includes an inexact component (numerical value
 * or operation), it will produce an inexact result.
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
    id_abs = rb_intern_const("abs");
    id_integer_p = rb_intern_const("integer?");
    id_i_num = rb_intern_const("@numerator");
    id_i_den = rb_intern_const("@denominator");

    rb_cRational = rb_define_class("Rational", rb_cNumeric);

    rb_define_alloc_func(rb_cRational, nurat_s_alloc);
    rb_undef_method(CLASS_OF(rb_cRational), "allocate");

    rb_undef_method(CLASS_OF(rb_cRational), "new");

    rb_define_global_function("Rational", nurat_f_rational, -1);

    rb_define_method(rb_cRational, "numerator", nurat_numerator, 0);
    rb_define_method(rb_cRational, "denominator", nurat_denominator, 0);

    rb_define_method(rb_cRational, "-@", rb_rational_uminus, 0);
    rb_define_method(rb_cRational, "+", rb_rational_plus, 1);
    rb_define_method(rb_cRational, "-", rb_rational_minus, 1);
    rb_define_method(rb_cRational, "*", rb_rational_mul, 1);
    rb_define_method(rb_cRational, "/", rb_rational_div, 1);
    rb_define_method(rb_cRational, "quo", rb_rational_div, 1);
    rb_define_method(rb_cRational, "fdiv", nurat_fdiv, 1);
    rb_define_method(rb_cRational, "**", nurat_expt, 1);

    rb_define_method(rb_cRational, "<=>", rb_rational_cmp, 1);
    rb_define_method(rb_cRational, "==", nurat_eqeq_p, 1);
    rb_define_method(rb_cRational, "coerce", nurat_coerce, 1);

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
    /* :nodoc: */
    compat = rb_define_class_under(rb_cRational, "compatible", rb_cObject);
    rb_define_private_method(compat, "marshal_load", nurat_marshal_load, 1);
    rb_marshal_define_compat(rb_cRational, compat, nurat_dumper, nurat_loader);

    rb_define_method(rb_cInteger, "gcd", rb_gcd, 1);
    rb_define_method(rb_cInteger, "lcm", rb_lcm, 1);
    rb_define_method(rb_cInteger, "gcdlcm", rb_gcdlcm, 1);

    rb_define_method(rb_cNumeric, "numerator", numeric_numerator, 0);
    rb_define_method(rb_cNumeric, "denominator", numeric_denominator, 0);
    rb_define_method(rb_cNumeric, "quo", rb_numeric_quo, 1);

    rb_define_method(rb_cInteger, "numerator", integer_numerator, 0);
    rb_define_method(rb_cInteger, "denominator", integer_denominator, 0);

    rb_define_method(rb_cFloat, "numerator", rb_float_numerator, 0);
    rb_define_method(rb_cFloat, "denominator", rb_float_denominator, 0);

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
