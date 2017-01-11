/*
  complex.c: Coded by Tadayoshi Funaba 2008-2012

  This implementation is based on Keiju Ishitsuka's Complex library
  which is written in ruby.
*/

#include "ruby/config.h"
#if defined _MSC_VER
/* Microsoft Visual C does not define M_PI and others by default */
# define _USE_MATH_DEFINES 1
#endif
#include <math.h>
#include "internal.h"

#define NDEBUG
#include "ruby_assert.h"

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)
#define RFLOAT_0 DBL2NUM(0)
#if defined(HAVE_SIGNBIT) && defined(__GNUC__) && defined(__sun) && \
    !defined(signbit)
extern int signbit(double);
#endif

VALUE rb_cComplex;

static VALUE nucomp_abs(VALUE self);
static VALUE nucomp_arg(VALUE self);

static ID id_abs, id_arg,
    id_denominator, id_expt, id_fdiv,
    id_negate, id_numerator, id_quo,
    id_real_p, id_to_f, id_to_i, id_to_r,
    id_i_real, id_i_imag,
    id_finite_p, id_infinite_p, id_rationalize,
    id_PI;

#define f_boolcast(x) ((x) ? Qtrue : Qfalse)

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

#define math1(n) \
inline static VALUE \
m_##n(VALUE x)\
{\
    return rb_funcall(rb_mMath, id_##n, 1, x);\
}

#define math2(n) \
inline static VALUE \
m_##n(VALUE x, VALUE y)\
{\
    return rb_funcall(rb_mMath, id_##n, 2, x, y);\
}

#define PRESERVE_SIGNEDZERO

inline static VALUE
f_add(VALUE x, VALUE y)
{
#ifndef PRESERVE_SIGNEDZERO
    if (FIXNUM_P(y) && FIXNUM_ZERO_P(y))
	return x;
    else if (FIXNUM_P(x) && FIXNUM_ZERO_P(x))
	return y;
#endif
    return rb_funcall(x, '+', 1, y);
}

inline static VALUE
f_div(VALUE x, VALUE y)
{
    if (FIXNUM_P(y) && FIX2LONG(y) == 1)
	return x;
    return rb_funcall(x, '/', 1, y);
}

inline static int
f_gt_p(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x)) {
        if (FIXNUM_P(x) && FIXNUM_P(y))
            return (SIGNED_VALUE)x > (SIGNED_VALUE)y;
        return RTEST(rb_int_gt(x, y));
    }
    else if (RB_FLOAT_TYPE_P(x))
        return RTEST(rb_float_gt(x, y));
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        int const cmp = rb_cmpint(rb_rational_cmp(x, y), x, y);
        return cmp > 0;
    }
    return RTEST(rb_funcall(x, '>', 1, y));
}

inline static VALUE
f_mul(VALUE x, VALUE y)
{
#ifndef PRESERVE_SIGNEDZERO
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
    }
#endif
    return rb_funcall(x, '*', 1, y);
}

inline static VALUE
f_sub(VALUE x, VALUE y)
{
#ifndef PRESERVE_SIGNEDZERO
    if (FIXNUM_P(y) && FIXNUM_ZERO_P(y))
	return x;
#endif
    return rb_funcall(x, '-', 1, y);
}

fun1(abs)
fun1(arg)
fun1(denominator)

static VALUE nucomp_negate(VALUE self);

inline static VALUE
f_negate(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return rb_int_uminus(x);
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return rb_float_uminus(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        return rb_rational_uminus(x);
    }
    else if (RB_TYPE_P(x, T_COMPLEX)) {
        return nucomp_negate(x);
    }
    return rb_funcall(x, id_negate, 0);
}

fun1(numerator)
fun1(real_p)

inline static VALUE
f_to_i(VALUE x)
{
    if (RB_TYPE_P(x, T_STRING))
	return rb_str_to_inum(x, 10, 0);
    return rb_funcall(x, id_to_i, 0);
}
inline static VALUE
f_to_f(VALUE x)
{
    if (RB_TYPE_P(x, T_STRING))
	return DBL2NUM(rb_str_to_dbl(x, 0));
    return rb_funcall(x, id_to_f, 0);
}

fun1(to_r)

inline static int
f_eqeq_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return x == y;
    else if (RB_FLOAT_TYPE_P(x) || RB_FLOAT_TYPE_P(y))
	return NUM2DBL(x) == NUM2DBL(y);
    return (int)rb_equal(x, y);
}

fun2(expt)
fun2(fdiv)
fun2(quo)

inline static int
f_negative_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x))
        return INT_NEGATIVE_P(x);
    else if (RB_FLOAT_TYPE_P(x))
        return RFLOAT_VALUE(x) < 0.0;
    else if (RB_TYPE_P(x, T_RATIONAL))
        return INT_NEGATIVE_P(RRATIONAL(x)->num);
    return rb_num_negative_p(x);
}

#define f_positive_p(x) (!f_negative_p(x))

inline static int
f_zero_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return FIXNUM_ZERO_P(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        const VALUE num = RRATIONAL(x)->num;
        return FIXNUM_ZERO_P(num);
    }
    return (int)rb_equal(x, ZERO);
}

#define f_nonzero_p(x) (!f_zero_p(x))

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

#define k_exact_p(x) (!RB_FLOAT_TYPE_P(x))

#define k_exact_zero_p(x) (k_exact_p(x) && f_zero_p(x))

#define get_dat1(x) \
    struct RComplex *dat = RCOMPLEX(x)

#define get_dat2(x,y) \
    struct RComplex *adat = RCOMPLEX(x), *bdat = RCOMPLEX(y)

inline static VALUE
nucomp_s_new_internal(VALUE klass, VALUE real, VALUE imag)
{
    NEWOBJ_OF(obj, struct RComplex, klass, T_COMPLEX | (RGENGC_WB_PROTECTED_COMPLEX ? FL_WB_PROTECTED : 0));

    RCOMPLEX_SET_REAL(obj, real);
    RCOMPLEX_SET_IMAG(obj, imag);

    return (VALUE)obj;
}

static VALUE
nucomp_s_alloc(VALUE klass)
{
    return nucomp_s_new_internal(klass, ZERO, ZERO);
}

#if 0
static VALUE
nucomp_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, imag;

    switch (rb_scan_args(argc, argv, "11", &real, &imag)) {
      case 1:
	if (!k_numeric_p(real))
	    real = f_to_i(real);
	imag = ZERO;
	break;
      default:
	if (!k_numeric_p(real))
	    real = f_to_i(real);
	if (!k_numeric_p(imag))
	    imag = f_to_i(imag);
	break;
    }

    return nucomp_s_new_internal(klass, real, imag);
}
#endif

inline static VALUE
f_complex_new_bang1(VALUE klass, VALUE x)
{
    assert(!RB_TYPE_P(x, T_COMPLEX));
    return nucomp_s_new_internal(klass, x, ZERO);
}

inline static VALUE
f_complex_new_bang2(VALUE klass, VALUE x, VALUE y)
{
    assert(!RB_TYPE_P(x, T_COMPLEX));
    assert(!RB_TYPE_P(y, T_COMPLEX));
    return nucomp_s_new_internal(klass, x, y);
}

#ifdef CANONICALIZATION_FOR_MATHN
#define CANON
#endif

#ifdef CANON
static int canonicalization = 0;

RUBY_FUNC_EXPORTED void
nucomp_canonicalization(int f)
{
    canonicalization = f;
}
#else
#define canonicalization 0
#endif

inline static void
nucomp_real_check(VALUE num)
{
    if (!RB_INTEGER_TYPE_P(num) &&
	!RB_FLOAT_TYPE_P(num) &&
	!RB_TYPE_P(num, T_RATIONAL)) {
	if (!k_numeric_p(num) || !f_real_p(num))
	    rb_raise(rb_eTypeError, "not a real");
    }
}

inline static VALUE
nucomp_s_canonicalize_internal(VALUE klass, VALUE real, VALUE imag)
{
#ifdef CANON
#define CL_CANON
#ifdef CL_CANON
    if (k_exact_zero_p(imag) && canonicalization)
	return real;
#else
    if (f_zero_p(imag) && canonicalization)
	return real;
#endif
#endif
    if (f_real_p(real) && f_real_p(imag))
	return nucomp_s_new_internal(klass, real, imag);
    else if (f_real_p(real)) {
	get_dat1(imag);

	return nucomp_s_new_internal(klass,
				     f_sub(real, dat->imag),
				     f_add(ZERO, dat->real));
    }
    else if (f_real_p(imag)) {
	get_dat1(real);

	return nucomp_s_new_internal(klass,
				     dat->real,
				     f_add(dat->imag, imag));
    }
    else {
	get_dat2(real, imag);

	return nucomp_s_new_internal(klass,
				     f_sub(adat->real, bdat->imag),
				     f_add(adat->imag, bdat->real));
    }
}

/*
 * call-seq:
 *    Complex.rect(real[, imag])         ->  complex
 *    Complex.rectangular(real[, imag])  ->  complex
 *
 * Returns a complex object which denotes the given rectangular form.
 *
 *    Complex.rectangular(1, 2)  #=> (1+2i)
 */
static VALUE
nucomp_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, imag;

    switch (rb_scan_args(argc, argv, "11", &real, &imag)) {
      case 1:
	nucomp_real_check(real);
	imag = ZERO;
	break;
      default:
	nucomp_real_check(real);
	nucomp_real_check(imag);
	break;
    }

    return nucomp_s_canonicalize_internal(klass, real, imag);
}

inline static VALUE
f_complex_new2(VALUE klass, VALUE x, VALUE y)
{
    assert(!RB_TYPE_P(x, T_COMPLEX));
    return nucomp_s_canonicalize_internal(klass, x, y);
}

static VALUE nucomp_s_convert(int argc, VALUE *argv, VALUE klass);

/*
 * call-seq:
 *    Complex(x[, y])  ->  numeric
 *
 * Returns x+i*y;
 *
 *    Complex(1, 2)    #=> (1+2i)
 *    Complex('1+2i')  #=> (1+2i)
 *    Complex(nil)     #=> TypeError
 *    Complex(1, nil)  #=> TypeError
 *
 * Syntax of string form:
 *
 *   string form = extra spaces , complex , extra spaces ;
 *   complex = real part | [ sign ] , imaginary part
 *           | real part , sign , imaginary part
 *           | rational , "@" , rational ;
 *   real part = rational ;
 *   imaginary part = imaginary unit | unsigned rational , imaginary unit ;
 *   rational = [ sign ] , unsigned rational ;
 *   unsigned rational = numerator | numerator , "/" , denominator ;
 *   numerator = integer part | fractional part | integer part , fractional part ;
 *   denominator = digits ;
 *   integer part = digits ;
 *   fractional part = "." , digits , [ ( "e" | "E" ) , [ sign ] , digits ] ;
 *   imaginary unit = "i" | "I" | "j" | "J" ;
 *   sign = "-" | "+" ;
 *   digits = digit , { digit | "_" , digit };
 *   digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
 *   extra spaces = ? \s* ? ;
 *
 * See String#to_c.
 */
static VALUE
nucomp_f_complex(int argc, VALUE *argv, VALUE klass)
{
    return nucomp_s_convert(argc, argv, rb_cComplex);
}

#define imp1(n) \
inline static VALUE \
m_##n##_bang(VALUE x)\
{\
    return rb_math_##n(x);\
}

imp1(cos)
imp1(cosh)
imp1(exp)

static VALUE
m_log_bang(VALUE x)
{
    return rb_math_log(1, &x);
}

imp1(sin)
imp1(sinh)

static VALUE
m_cos(VALUE x)
{
    if (f_real_p(x))
	return m_cos_bang(x);
    {
	get_dat1(x);
	return f_complex_new2(rb_cComplex,
			      f_mul(m_cos_bang(dat->real),
				    m_cosh_bang(dat->imag)),
			      f_mul(f_negate(m_sin_bang(dat->real)),
				    m_sinh_bang(dat->imag)));
    }
}

static VALUE
m_sin(VALUE x)
{
    if (f_real_p(x))
	return m_sin_bang(x);
    {
	get_dat1(x);
	return f_complex_new2(rb_cComplex,
			      f_mul(m_sin_bang(dat->real),
				    m_cosh_bang(dat->imag)),
			      f_mul(m_cos_bang(dat->real),
				    m_sinh_bang(dat->imag)));
    }
}

#if 0
imp1(sqrt)

VALUE
rb_complex_sqrt(VALUE x)
{
    int pos;
    VALUE a, re, im;
    get_dat1(x);

    pos = f_positive_p(dat->imag);
    a = f_abs(x);
    re = m_sqrt_bang(f_div(f_add(a, dat->real), TWO));
    im = m_sqrt_bang(f_div(f_sub(a, dat->real), TWO));
    if (!pos) im = f_negate(im);
    return f_complex_new2(rb_cComplex, re, im);
}

static VALUE
m_sqrt(VALUE x)
{
    if (f_real_p(x)) {
	if (f_positive_p(x))
	    return m_sqrt_bang(x);
	return f_complex_new2(rb_cComplex, ZERO, m_sqrt_bang(f_negate(x)));
    }
    return rb_complex_sqrt(x);
}
#endif

static VALUE
f_complex_polar(VALUE klass, VALUE x, VALUE y)
{
    assert(!RB_TYPE_P(x, T_COMPLEX));
    assert(!RB_TYPE_P(y, T_COMPLEX));
    if (f_zero_p(x) || f_zero_p(y)) {
	if (canonicalization) return x;
	return nucomp_s_new_internal(klass, x, RFLOAT_0);
    }
    if (RB_FLOAT_TYPE_P(y)) {
	const double arg = RFLOAT_VALUE(y);
	if (arg == M_PI) {
	    x = f_negate(x);
	    if (canonicalization) return x;
	    y = RFLOAT_0;
	}
	else if (arg == M_PI_2) {
	    y = x;
	    x = RFLOAT_0;
	}
	else if (arg == M_PI_2+M_PI) {
	    y = f_negate(x);
	    x = RFLOAT_0;
	}
	else if (RB_FLOAT_TYPE_P(x)) {
	    const double abs = RFLOAT_VALUE(x);
	    const double real = abs * cos(arg), imag = abs * sin(arg);
	    x = DBL2NUM(real);
	    if (canonicalization && imag == 0.0) return x;
	    y = DBL2NUM(imag);
	}
	else {
	    y = f_mul(x, DBL2NUM(sin(arg)));
	    x = f_mul(x, DBL2NUM(cos(arg)));
	    if (canonicalization && f_zero_p(y)) return x;
	}
	return nucomp_s_new_internal(klass, x, y);
    }
    return nucomp_s_canonicalize_internal(klass,
					  f_mul(x, m_cos(y)),
					  f_mul(x, m_sin(y)));
}

/*
 * call-seq:
 *    Complex.polar(abs[, arg])  ->  complex
 *
 * Returns a complex object which denotes the given polar form.
 *
 *    Complex.polar(3, 0)            #=> (3.0+0.0i)
 *    Complex.polar(3, Math::PI/2)   #=> (1.836909530733566e-16+3.0i)
 *    Complex.polar(3, Math::PI)     #=> (-3.0+3.673819061467132e-16i)
 *    Complex.polar(3, -Math::PI/2)  #=> (1.836909530733566e-16-3.0i)
 */
static VALUE
nucomp_s_polar(int argc, VALUE *argv, VALUE klass)
{
    VALUE abs, arg;

    switch (rb_scan_args(argc, argv, "11", &abs, &arg)) {
      case 1:
	nucomp_real_check(abs);
	if (canonicalization) return abs;
	return nucomp_s_new_internal(klass, abs, ZERO);
      default:
	nucomp_real_check(abs);
	nucomp_real_check(arg);
	break;
    }
    return f_complex_polar(klass, abs, arg);
}

/*
 * call-seq:
 *    cmp.real  ->  real
 *
 * Returns the real part.
 *
 *    Complex(7).real      #=> 7
 *    Complex(9, -4).real  #=> 9
 */
static VALUE
nucomp_real(VALUE self)
{
    get_dat1(self);
    return dat->real;
}

/*
 * call-seq:
 *    cmp.imag       ->  real
 *    cmp.imaginary  ->  real
 *
 * Returns the imaginary part.
 *
 *    Complex(7).imaginary      #=> 0
 *    Complex(9, -4).imaginary  #=> -4
 */
static VALUE
nucomp_imag(VALUE self)
{
    get_dat1(self);
    return dat->imag;
}

/*
 * call-seq:
 *    -cmp  ->  complex
 *
 * Returns negation of the value.
 *
 *    -Complex(1, 2)  #=> (-1-2i)
 */
static VALUE
nucomp_negate(VALUE self)
{
  get_dat1(self);
  return f_complex_new2(CLASS_OF(self),
			f_negate(dat->real), f_negate(dat->imag));
}

/*
 * call-seq:
 *    cmp + numeric  ->  complex
 *
 * Performs addition.
 *
 *    Complex(2, 3)  + Complex(2, 3)   #=> (4+6i)
 *    Complex(900)   + Complex(1)      #=> (901+0i)
 *    Complex(-2, 9) + Complex(-9, 2)  #=> (-11+11i)
 *    Complex(9, 8)  + 4               #=> (13+8i)
 *    Complex(20, 9) + 9.8             #=> (29.8+9i)
 */
VALUE
rb_complex_plus(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	VALUE real, imag;

	get_dat2(self, other);

	real = f_add(adat->real, bdat->real);
	imag = f_add(adat->imag, bdat->imag);

	return f_complex_new2(CLASS_OF(self), real, imag);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_add(dat->real, other), dat->imag);
    }
    return rb_num_coerce_bin(self, other, '+');
}

/*
 * call-seq:
 *    cmp - numeric  ->  complex
 *
 * Performs subtraction.
 *
 *    Complex(2, 3)  - Complex(2, 3)   #=> (0+0i)
 *    Complex(900)   - Complex(1)      #=> (899+0i)
 *    Complex(-2, 9) - Complex(-9, 2)  #=> (7+7i)
 *    Complex(9, 8)  - 4               #=> (5+8i)
 *    Complex(20, 9) - 9.8             #=> (10.2+9i)
 */
static VALUE
nucomp_sub(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	VALUE real, imag;

	get_dat2(self, other);

	real = f_sub(adat->real, bdat->real);
	imag = f_sub(adat->imag, bdat->imag);

	return f_complex_new2(CLASS_OF(self), real, imag);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_sub(dat->real, other), dat->imag);
    }
    return rb_num_coerce_bin(self, other, '-');
}

static VALUE
safe_mul(VALUE a, VALUE b, int az, int bz)
{
    double v;
    if (!az && bz && RB_FLOAT_TYPE_P(a) && (v = RFLOAT_VALUE(a), !isnan(v))) {
	a = signbit(v) ? DBL2NUM(-1.0) : DBL2NUM(1.0);
    }
    if (!bz && az && RB_FLOAT_TYPE_P(b) && (v = RFLOAT_VALUE(b), !isnan(v))) {
	b = signbit(v) ? DBL2NUM(-1.0) : DBL2NUM(1.0);
    }
    return f_mul(a, b);
}

/*
 * call-seq:
 *    cmp * numeric  ->  complex
 *
 * Performs multiplication.
 *
 *    Complex(2, 3)  * Complex(2, 3)   #=> (-5+12i)
 *    Complex(900)   * Complex(1)      #=> (900+0i)
 *    Complex(-2, 9) * Complex(-9, 2)  #=> (0-85i)
 *    Complex(9, 8)  * 4               #=> (36+32i)
 *    Complex(20, 9) * 9.8             #=> (196.0+88.2i)
 */
VALUE
rb_complex_mul(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	VALUE real, imag;
	VALUE areal, aimag, breal, bimag;
	int arzero, aizero, brzero, bizero;

	get_dat2(self, other);

	arzero = f_zero_p(areal = adat->real);
	aizero = f_zero_p(aimag = adat->imag);
	brzero = f_zero_p(breal = bdat->real);
	bizero = f_zero_p(bimag = bdat->imag);
	real = f_sub(safe_mul(areal, breal, arzero, brzero),
		     safe_mul(aimag, bimag, aizero, bizero));
	imag = f_add(safe_mul(areal, bimag, arzero, bizero),
		     safe_mul(aimag, breal, aizero, brzero));

	return f_complex_new2(CLASS_OF(self), real, imag);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_mul(dat->real, other),
			      f_mul(dat->imag, other));
    }
    return rb_num_coerce_bin(self, other, '*');
}
#define nucomp_mul rb_complex_mul

inline static VALUE
f_divide(VALUE self, VALUE other,
	 VALUE (*func)(VALUE, VALUE), ID id)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	int flo;
	get_dat2(self, other);

	flo = (RB_FLOAT_TYPE_P(adat->real) || RB_FLOAT_TYPE_P(adat->imag) ||
	       RB_FLOAT_TYPE_P(bdat->real) || RB_FLOAT_TYPE_P(bdat->imag));

	if (f_gt_p(f_abs(bdat->real), f_abs(bdat->imag))) {
	    VALUE r, n;

	    r = (*func)(bdat->imag, bdat->real);
	    n = f_mul(bdat->real, f_add(ONE, f_mul(r, r)));
	    if (flo)
		return f_complex_new2(CLASS_OF(self),
				      (*func)(self, n),
				      (*func)(f_negate(f_mul(self, r)), n));
	    return f_complex_new2(CLASS_OF(self),
				  (*func)(f_add(adat->real,
						f_mul(adat->imag, r)), n),
				  (*func)(f_sub(adat->imag,
						f_mul(adat->real, r)), n));
	}
	else {
	    VALUE r, n;

	    r = (*func)(bdat->real, bdat->imag);
	    n = f_mul(bdat->imag, f_add(ONE, f_mul(r, r)));
	    if (flo)
		return f_complex_new2(CLASS_OF(self),
				      (*func)(f_mul(self, r), n),
				      (*func)(f_negate(self), n));
	    return f_complex_new2(CLASS_OF(self),
				  (*func)(f_add(f_mul(adat->real, r),
						adat->imag), n),
				  (*func)(f_sub(f_mul(adat->imag, r),
						adat->real), n));
	}
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      (*func)(dat->real, other),
			      (*func)(dat->imag, other));
    }
    return rb_num_coerce_bin(self, other, id);
}

#define rb_raise_zerodiv() rb_raise(rb_eZeroDivError, "divided by 0")

/*
 * call-seq:
 *    cmp / numeric     ->  complex
 *    cmp.quo(numeric)  ->  complex
 *
 * Performs division.
 *
 *    Complex(2, 3)  / Complex(2, 3)   #=> ((1/1)+(0/1)*i)
 *    Complex(900)   / Complex(1)      #=> ((900/1)+(0/1)*i)
 *    Complex(-2, 9) / Complex(-9, 2)  #=> ((36/85)-(77/85)*i)
 *    Complex(9, 8)  / 4               #=> ((9/4)+(2/1)*i)
 *    Complex(20, 9) / 9.8             #=> (2.0408163265306123+0.9183673469387754i)
 */
static VALUE
nucomp_div(VALUE self, VALUE other)
{
    return f_divide(self, other, f_quo, id_quo);
}

#define nucomp_quo nucomp_div

/*
 * call-seq:
 *    cmp.fdiv(numeric)  ->  complex
 *
 * Performs division as each part is a float, never returns a float.
 *
 *    Complex(11, 22).fdiv(3)  #=> (3.6666666666666665+7.333333333333333i)
 */
static VALUE
nucomp_fdiv(VALUE self, VALUE other)
{
    return f_divide(self, other, f_fdiv, id_fdiv);
}

inline static VALUE
f_reciprocal(VALUE x)
{
    return f_quo(ONE, x);
}

/*
 * call-seq:
 *    cmp ** numeric  ->  complex
 *
 * Performs exponentiation.
 *
 *    Complex('i') ** 2              #=> (-1+0i)
 *    Complex(-8) ** Rational(1, 3)  #=> (1.0000000000000002+1.7320508075688772i)
 */
static VALUE
nucomp_expt(VALUE self, VALUE other)
{
    if (k_numeric_p(other) && k_exact_zero_p(other))
	return f_complex_new_bang1(CLASS_OF(self), ONE);

    if (RB_TYPE_P(other, T_RATIONAL) && RRATIONAL(other)->den == LONG2FIX(1))
	other = RRATIONAL(other)->num; /* c14n */

    if (RB_TYPE_P(other, T_COMPLEX)) {
	get_dat1(other);

	if (k_exact_zero_p(dat->imag))
	    other = dat->real; /* c14n */
    }

    if (RB_TYPE_P(other, T_COMPLEX)) {
	VALUE r, theta, nr, ntheta;

	get_dat1(other);

	r = f_abs(self);
	theta = f_arg(self);

	nr = m_exp_bang(f_sub(f_mul(dat->real, m_log_bang(r)),
			      f_mul(dat->imag, theta)));
	ntheta = f_add(f_mul(theta, dat->real),
		       f_mul(dat->imag, m_log_bang(r)));
	return f_complex_polar(CLASS_OF(self), nr, ntheta);
    }
    if (FIXNUM_P(other)) {
	if (f_gt_p(other, ZERO)) {
	    VALUE x, z;
	    long n;

	    x = self;
	    z = x;
	    n = FIX2LONG(other) - 1;

	    while (n) {
		long q, r;

		while (1) {
		    get_dat1(x);

		    q = n / 2;
		    r = n % 2;

		    if (r)
			break;

		    x = nucomp_s_new_internal(CLASS_OF(self),
				       f_sub(f_mul(dat->real, dat->real),
					     f_mul(dat->imag, dat->imag)),
				       f_mul(f_mul(TWO, dat->real), dat->imag));
		    n = q;
		}
		z = f_mul(z, x);
		n--;
	    }
	    return z;
	}
	return f_expt(f_reciprocal(self), rb_int_uminus(other));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	VALUE r, theta;

	if (RB_TYPE_P(other, T_BIGNUM))
	    rb_warn("in a**b, b may be too big");

	r = f_abs(self);
	theta = f_arg(self);

	return f_complex_polar(CLASS_OF(self), f_expt(r, other),
			       f_mul(theta, other));
    }
    return rb_num_coerce_bin(self, other, id_expt);
}

/*
 * call-seq:
 *    cmp == object  ->  true or false
 *
 * Returns true if cmp equals object numerically.
 *
 *    Complex(2, 3)  == Complex(2, 3)   #=> true
 *    Complex(5)     == 5               #=> true
 *    Complex(0)     == 0.0             #=> true
 *    Complex('1/3') == 0.33            #=> false
 *    Complex('1/2') == '1/2'           #=> false
 */
static VALUE
nucomp_eqeq_p(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	get_dat2(self, other);

	return f_boolcast(f_eqeq_p(adat->real, bdat->real) &&
			  f_eqeq_p(adat->imag, bdat->imag));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_boolcast(f_eqeq_p(dat->real, other) && f_zero_p(dat->imag));
    }
    return f_boolcast(f_eqeq_p(other, self));
}

/* :nodoc: */
static VALUE
nucomp_coerce(VALUE self, VALUE other)
{
    if (k_numeric_p(other) && f_real_p(other))
	return rb_assoc_new(f_complex_new_bang1(CLASS_OF(self), other), self);
    if (RB_TYPE_P(other, T_COMPLEX))
	return rb_assoc_new(other, self);

    rb_raise(rb_eTypeError, "%"PRIsVALUE" can't be coerced into %"PRIsVALUE,
	     rb_obj_class(other), rb_obj_class(self));
    return Qnil;
}

/*
 * call-seq:
 *    cmp.abs        ->  real
 *    cmp.magnitude  ->  real
 *
 * Returns the absolute part of its polar form.
 *
 *    Complex(-1).abs         #=> 1
 *    Complex(3.0, -4.0).abs  #=> 5.0
 */
static VALUE
nucomp_abs(VALUE self)
{
    get_dat1(self);

    if (f_zero_p(dat->real)) {
	VALUE a = f_abs(dat->imag);
	if (RB_FLOAT_TYPE_P(dat->real) && !RB_FLOAT_TYPE_P(dat->imag))
	    a = f_to_f(a);
	return a;
    }
    if (f_zero_p(dat->imag)) {
	VALUE a = f_abs(dat->real);
	if (!RB_FLOAT_TYPE_P(dat->real) && RB_FLOAT_TYPE_P(dat->imag))
	    a = f_to_f(a);
	return a;
    }
    return rb_math_hypot(dat->real, dat->imag);
}

/*
 * call-seq:
 *    cmp.abs2  ->  real
 *
 * Returns square of the absolute value.
 *
 *    Complex(-1).abs2         #=> 1
 *    Complex(3.0, -4.0).abs2  #=> 25.0
 */
static VALUE
nucomp_abs2(VALUE self)
{
    get_dat1(self);
    return f_add(f_mul(dat->real, dat->real),
		 f_mul(dat->imag, dat->imag));
}

/*
 * call-seq:
 *    cmp.arg    ->  float
 *    cmp.angle  ->  float
 *    cmp.phase  ->  float
 *
 * Returns the angle part of its polar form.
 *
 *    Complex.polar(3, Math::PI/2).arg  #=> 1.5707963267948966
 */
static VALUE
nucomp_arg(VALUE self)
{
    get_dat1(self);
    return rb_math_atan2(dat->imag, dat->real);
}

/*
 * call-seq:
 *    cmp.rect         ->  array
 *    cmp.rectangular  ->  array
 *
 * Returns an array; [cmp.real, cmp.imag].
 *
 *    Complex(1, 2).rectangular  #=> [1, 2]
 */
static VALUE
nucomp_rect(VALUE self)
{
    get_dat1(self);
    return rb_assoc_new(dat->real, dat->imag);
}

/*
 * call-seq:
 *    cmp.polar  ->  array
 *
 * Returns an array; [cmp.abs, cmp.arg].
 *
 *    Complex(1, 2).polar  #=> [2.23606797749979, 1.1071487177940904]
 */
static VALUE
nucomp_polar(VALUE self)
{
    return rb_assoc_new(f_abs(self), f_arg(self));
}

/*
 * call-seq:
 *    cmp.conj       ->  complex
 *    cmp.conjugate  ->  complex
 *
 * Returns the complex conjugate.
 *
 *    Complex(1, 2).conjugate  #=> (1-2i)
 */
static VALUE
nucomp_conj(VALUE self)
{
    get_dat1(self);
    return f_complex_new2(CLASS_OF(self), dat->real, f_negate(dat->imag));
}

#if 0
/* :nodoc: */
static VALUE
nucomp_true(VALUE self)
{
    return Qtrue;
}
#endif

/*
 * call-seq:
 *    cmp.real?  ->  false
 *
 * Returns false.
 */
static VALUE
nucomp_false(VALUE self)
{
    return Qfalse;
}

#if 0
/* :nodoc: */
static VALUE
nucomp_exact_p(VALUE self)
{
    get_dat1(self);
    return f_boolcast(k_exact_p(dat->real) && k_exact_p(dat->imag));
}

/* :nodoc: */
static VALUE
nucomp_inexact_p(VALUE self)
{
    return f_boolcast(!nucomp_exact_p(self));
}
#endif

/*
 * call-seq:
 *    cmp.denominator  ->  integer
 *
 * Returns the denominator (lcm of both denominator - real and imag).
 *
 * See numerator.
 */
static VALUE
nucomp_denominator(VALUE self)
{
    get_dat1(self);
    return rb_lcm(f_denominator(dat->real), f_denominator(dat->imag));
}

/*
 * call-seq:
 *    cmp.numerator  ->  numeric
 *
 * Returns the numerator.
 *
 *        1   2       3+4i  <-  numerator
 *        - + -i  ->  ----
 *        2   3        6    <-  denominator
 *
 *    c = Complex('1/2+2/3i')  #=> ((1/2)+(2/3)*i)
 *    n = c.numerator          #=> (3+4i)
 *    d = c.denominator        #=> 6
 *    n / d                    #=> ((1/2)+(2/3)*i)
 *    Complex(Rational(n.real, d), Rational(n.imag, d))
 *                             #=> ((1/2)+(2/3)*i)
 * See denominator.
 */
static VALUE
nucomp_numerator(VALUE self)
{
    VALUE cd;

    get_dat1(self);

    cd = f_denominator(self);
    return f_complex_new2(CLASS_OF(self),
			  f_mul(f_numerator(dat->real),
				f_div(cd, f_denominator(dat->real))),
			  f_mul(f_numerator(dat->imag),
				f_div(cd, f_denominator(dat->imag))));
}

/* :nodoc: */
static VALUE
nucomp_hash(VALUE self)
{
    st_index_t v, h[2];
    VALUE n;

    get_dat1(self);
    n = rb_hash(dat->real);
    h[0] = NUM2LONG(n);
    n = rb_hash(dat->imag);
    h[1] = NUM2LONG(n);
    v = rb_memhash(h, sizeof(h));
    return LONG2FIX(v);
}

/* :nodoc: */
static VALUE
nucomp_eql_p(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
	get_dat2(self, other);

	return f_boolcast((CLASS_OF(adat->real) == CLASS_OF(bdat->real)) &&
			  (CLASS_OF(adat->imag) == CLASS_OF(bdat->imag)) &&
			  f_eqeq_p(self, other));

    }
    return Qfalse;
}

inline static int
f_signbit(VALUE x)
{
    if (RB_FLOAT_TYPE_P(x)) {
	double f = RFLOAT_VALUE(x);
	return !isnan(f) && signbit(f);
    }
    return f_negative_p(x);
}

inline static int
f_tpositive_p(VALUE x)
{
    return !f_signbit(x);
}

static VALUE
f_format(VALUE self, VALUE (*func)(VALUE))
{
    VALUE s;
    int impos;

    get_dat1(self);

    impos = f_tpositive_p(dat->imag);

    s = (*func)(dat->real);
    rb_str_cat2(s, !impos ? "-" : "+");

    rb_str_concat(s, (*func)(f_abs(dat->imag)));
    if (!rb_isdigit(RSTRING_PTR(s)[RSTRING_LEN(s) - 1]))
	rb_str_cat2(s, "*");
    rb_str_cat2(s, "i");

    return s;
}

/*
 * call-seq:
 *    cmp.to_s  ->  string
 *
 * Returns the value as a string.
 *
 *    Complex(2).to_s                       #=> "2+0i"
 *    Complex('-8/6').to_s                  #=> "-4/3+0i"
 *    Complex('1/2i').to_s                  #=> "0+1/2i"
 *    Complex(0, Float::INFINITY).to_s      #=> "0+Infinity*i"
 *    Complex(Float::NAN, Float::NAN).to_s  #=> "NaN+NaN*i"
 */
static VALUE
nucomp_to_s(VALUE self)
{
    return f_format(self, rb_String);
}

/*
 * call-seq:
 *    cmp.inspect  ->  string
 *
 * Returns the value as a string for inspection.
 *
 *    Complex(2).inspect                       #=> "(2+0i)"
 *    Complex('-8/6').inspect                  #=> "((-4/3)+0i)"
 *    Complex('1/2i').inspect                  #=> "(0+(1/2)*i)"
 *    Complex(0, Float::INFINITY).inspect      #=> "(0+Infinity*i)"
 *    Complex(Float::NAN, Float::NAN).inspect  #=> "(NaN+NaN*i)"
 */
static VALUE
nucomp_inspect(VALUE self)
{
    VALUE s;

    s = rb_usascii_str_new2("(");
    rb_str_concat(s, f_format(self, rb_inspect));
    rb_str_cat2(s, ")");

    return s;
}

#define FINITE_TYPE_P(v) (RB_INTEGER_TYPE_P(v) || RB_TYPE_P(v, T_RATIONAL))

/*
 * call-seq:
 *    cmp.finite?  ->  true or false
 *
 * Returns +true+ if +cmp+'s magnitude is finite number,
 * oterwise returns +false+.
 */
static VALUE
rb_complex_finite_p(VALUE self)
{
    VALUE magnitude = nucomp_abs(self);

    if (FINITE_TYPE_P(magnitude)) {
	return Qtrue;
    }
    else if (RB_FLOAT_TYPE_P(magnitude)) {
	const double f = RFLOAT_VALUE(magnitude);
	return isinf(f) ? Qfalse : Qtrue;
    }
    else {
	return rb_funcall(magnitude, id_finite_p, 0);
    }
}

/*
 * call-seq:
 *    cmp.infinite?  ->  nil or 1 or -1
 *
 * Returns values corresponding to the value of +cmp+'s magnitude:
 *
 * +finite+::    +nil+
 * ++Infinity+:: ++1+
 *
 *  For example:
 *
 *     (1+1i).infinite?                   #=> nil
 *     (Float::INFINITY + 1i).infinite?   #=> 1
 */
static VALUE
rb_complex_infinite_p(VALUE self)
{
    VALUE magnitude = nucomp_abs(self);

    if (FINITE_TYPE_P(magnitude)) {
	return Qnil;
    }
    if (RB_FLOAT_TYPE_P(magnitude)) {
	const double f = RFLOAT_VALUE(magnitude);
	if (isinf(f)) {
	    return INT2FIX(f < 0 ? -1 : 1);
	}
	return Qnil;
    }
    else {
	return rb_funcall(magnitude, id_infinite_p, 0);
    }
}

/* :nodoc: */
static VALUE
nucomp_dumper(VALUE self)
{
    return self;
}

/* :nodoc: */
static VALUE
nucomp_loader(VALUE self, VALUE a)
{
    get_dat1(self);

    RCOMPLEX_SET_REAL(dat, rb_ivar_get(a, id_i_real));
    RCOMPLEX_SET_IMAG(dat, rb_ivar_get(a, id_i_imag));

    return self;
}

/* :nodoc: */
static VALUE
nucomp_marshal_dump(VALUE self)
{
    VALUE a;
    get_dat1(self);

    a = rb_assoc_new(dat->real, dat->imag);
    rb_copy_generic_ivar(a, self);
    return a;
}

/* :nodoc: */
static VALUE
nucomp_marshal_load(VALUE self, VALUE a)
{
    Check_Type(a, T_ARRAY);
    if (RARRAY_LEN(a) != 2)
	rb_raise(rb_eArgError, "marshaled complex must have an array whose length is 2 but %ld", RARRAY_LEN(a));
    rb_ivar_set(self, id_i_real, RARRAY_AREF(a, 0));
    rb_ivar_set(self, id_i_imag, RARRAY_AREF(a, 1));
    return self;
}

/* --- */

VALUE
rb_complex_raw(VALUE x, VALUE y)
{
    return nucomp_s_new_internal(rb_cComplex, x, y);
}

VALUE
rb_complex_new(VALUE x, VALUE y)
{
    return nucomp_s_canonicalize_internal(rb_cComplex, x, y);
}

VALUE
rb_complex_polar(VALUE x, VALUE y)
{
    return f_complex_polar(rb_cComplex, x, y);
}

VALUE
rb_Complex(VALUE x, VALUE y)
{
    VALUE a[2];
    a[0] = x;
    a[1] = y;
    return nucomp_s_convert(2, a, rb_cComplex);
}

VALUE
rb_complex_set_real(VALUE cmp, VALUE r)
{
    RCOMPLEX_SET_REAL(cmp, r);
    return cmp;
}

VALUE
rb_complex_set_imag(VALUE cmp, VALUE i)
{
    RCOMPLEX_SET_IMAG(cmp, i);
    return cmp;
}

VALUE
rb_complex_abs(VALUE cmp)
{
    return nucomp_abs(cmp);
}

/*
 * call-seq:
 *    cmp.to_i  ->  integer
 *
 * Returns the value as an integer if possible (the imaginary part
 * should be exactly zero).
 *
 *    Complex(1, 0).to_i    #=> 1
 *    Complex(1, 0.0).to_i  # RangeError
 *    Complex(1, 2).to_i    # RangeError
 */
static VALUE
nucomp_to_i(VALUE self)
{
    get_dat1(self);

    if (!k_exact_zero_p(dat->imag)) {
	rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Integer",
		 self);
    }
    return f_to_i(dat->real);
}

/*
 * call-seq:
 *    cmp.to_f  ->  float
 *
 * Returns the value as a float if possible (the imaginary part should
 * be exactly zero).
 *
 *    Complex(1, 0).to_f    #=> 1.0
 *    Complex(1, 0.0).to_f  # RangeError
 *    Complex(1, 2).to_f    # RangeError
 */
static VALUE
nucomp_to_f(VALUE self)
{
    get_dat1(self);

    if (!k_exact_zero_p(dat->imag)) {
	rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Float",
		 self);
    }
    return f_to_f(dat->real);
}

/*
 * call-seq:
 *    cmp.to_r  ->  rational
 *
 * Returns the value as a rational if possible (the imaginary part
 * should be exactly zero).
 *
 *    Complex(1, 0).to_r    #=> (1/1)
 *    Complex(1, 0.0).to_r  # RangeError
 *    Complex(1, 2).to_r    # RangeError
 *
 * See rationalize.
 */
static VALUE
nucomp_to_r(VALUE self)
{
    get_dat1(self);

    if (!k_exact_zero_p(dat->imag)) {
	rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Rational",
		 self);
    }
    return f_to_r(dat->real);
}

/*
 * call-seq:
 *    cmp.rationalize([eps])  ->  rational
 *
 * Returns the value as a rational if possible (the imaginary part
 * should be exactly zero).
 *
 *    Complex(1.0/3, 0).rationalize  #=> (1/3)
 *    Complex(1, 0.0).rationalize    # RangeError
 *    Complex(1, 2).rationalize      # RangeError
 *
 * See to_r.
 */
static VALUE
nucomp_rationalize(int argc, VALUE *argv, VALUE self)
{
    get_dat1(self);

    rb_scan_args(argc, argv, "01", NULL);

    if (!k_exact_zero_p(dat->imag)) {
       rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Rational",
                self);
    }
    return rb_funcallv(dat->real, id_rationalize, argc, argv);
}

/*
 * call-seq:
 *    complex.to_c  ->  self
 *
 * Returns self.
 *
 *    Complex(2).to_c      #=> (2+0i)
 *    Complex(-8, 6).to_c  #=> (-8+6i)
 */
static VALUE
nucomp_to_c(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *    nil.to_c  ->  (0+0i)
 *
 * Returns zero as a complex.
 */
static VALUE
nilclass_to_c(VALUE self)
{
    return rb_complex_new1(INT2FIX(0));
}

/*
 * call-seq:
 *    num.to_c  ->  complex
 *
 * Returns the value as a complex.
 */
static VALUE
numeric_to_c(VALUE self)
{
    return rb_complex_new1(self);
}

#include <ctype.h>

inline static int
issign(int c)
{
    return (c == '-' || c == '+');
}

static int
read_sign(const char **s,
	  char **b)
{
    int sign = '?';

    if (issign(**s)) {
	sign = **b = **s;
	(*s)++;
	(*b)++;
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
	    char **b)
{
    int us = 1;

    if (!isdecimal(**s))
	return 0;

    while (isdecimal(**s) || **s == '_') {
	if (**s == '_') {
	    if (strict) {
		if (us)
		    return 0;
	    }
	    us = 1;
	}
	else {
	    **b = **s;
	    (*b)++;
	    us = 0;
	}
	(*s)++;
    }
    if (us)
	do {
	    (*s)--;
	} while (**s == '_');
    return 1;
}

inline static int
islettere(int c)
{
    return (c == 'e' || c == 'E');
}

static int
read_num(const char **s, int strict,
	 char **b)
{
    if (**s != '.') {
	if (!read_digits(s, strict, b))
	    return 0;
    }

    if (**s == '.') {
	**b = **s;
	(*s)++;
	(*b)++;
	if (!read_digits(s, strict, b)) {
	    (*b)--;
	    return 0;
	}
    }

    if (islettere(**s)) {
	**b = **s;
	(*s)++;
	(*b)++;
	read_sign(s, b);
	if (!read_digits(s, strict, b)) {
	    (*b)--;
	    return 0;
	}
    }
    return 1;
}

inline static int
read_den(const char **s, int strict,
	 char **b)
{
    if (!read_digits(s, strict, b))
	return 0;
    return 1;
}

static int
read_rat_nos(const char **s, int strict,
	     char **b)
{
    if (!read_num(s, strict, b))
	return 0;
    if (**s == '/') {
	**b = **s;
	(*s)++;
	(*b)++;
	if (!read_den(s, strict, b)) {
	    (*b)--;
	    return 0;
	}
    }
    return 1;
}

static int
read_rat(const char **s, int strict,
	 char **b)
{
    read_sign(s, b);
    if (!read_rat_nos(s, strict, b))
	return 0;
    return 1;
}

inline static int
isimagunit(int c)
{
    return (c == 'i' || c == 'I' ||
	    c == 'j' || c == 'J');
}

static VALUE
str2num(char *s)
{
    if (strchr(s, '/'))
	return rb_cstr_to_rat(s, 0);
    if (strpbrk(s, ".eE"))
	return DBL2NUM(rb_cstr_to_dbl(s, 0));
    return rb_cstr_to_inum(s, 10, 0);
}

static int
read_comp(const char **s, int strict,
	  VALUE *ret, char **b)
{
    char *bb;
    int sign;
    VALUE num, num2;

    bb = *b;

    sign = read_sign(s, b);

    if (isimagunit(**s)) {
	(*s)++;
	num = INT2FIX((sign == '-') ? -1 : + 1);
	*ret = rb_complex_new2(ZERO, num);
	return 1; /* e.g. "i" */
    }

    if (!read_rat_nos(s, strict, b)) {
	**b = '\0';
	num = str2num(bb);
	*ret = rb_complex_new2(num, ZERO);
	return 0; /* e.g. "-" */
    }
    **b = '\0';
    num = str2num(bb);

    if (isimagunit(**s)) {
	(*s)++;
	*ret = rb_complex_new2(ZERO, num);
	return 1; /* e.g. "3i" */
    }

    if (**s == '@') {
	int st;

	(*s)++;
	bb = *b;
	st = read_rat(s, strict, b);
	**b = '\0';
	if (strlen(bb) < 1 ||
	    !isdecimal(*(bb + strlen(bb) - 1))) {
	    *ret = rb_complex_new2(num, ZERO);
	    return 0; /* e.g. "1@-" */
	}
	num2 = str2num(bb);
	*ret = rb_complex_polar(num, num2);
	if (!st)
	    return 0; /* e.g. "1@2." */
	else
	    return 1; /* e.g. "1@2" */
    }

    if (issign(**s)) {
	bb = *b;
	sign = read_sign(s, b);
	if (isimagunit(**s))
	    num2 = INT2FIX((sign == '-') ? -1 : + 1);
	else {
	    if (!read_rat_nos(s, strict, b)) {
		*ret = rb_complex_new2(num, ZERO);
		return 0; /* e.g. "1+xi" */
	    }
	    **b = '\0';
	    num2 = str2num(bb);
	}
	if (!isimagunit(**s)) {
	    *ret = rb_complex_new2(num, ZERO);
	    return 0; /* e.g. "1+3x" */
	}
	(*s)++;
	*ret = rb_complex_new2(num, num2);
	return 1; /* e.g. "1+2i" */
    }
    /* !(@, - or +) */
    {
	*ret = rb_complex_new2(num, ZERO);
	return 1; /* e.g. "3" */
    }
}

inline static void
skip_ws(const char **s)
{
    while (isspace((unsigned char)**s))
	(*s)++;
}

static int
parse_comp(const char *s, int strict,
	   VALUE *num)
{
    char *buf, *b;
    VALUE tmp;
    int ret = 1;

    buf = ALLOCV_N(char, tmp, strlen(s) + 1);
    b = buf;

    skip_ws(&s);
    if (!read_comp(&s, strict, num, &b)) {
	ret = 0;
    }
    else {
	skip_ws(&s);

	if (strict)
	    if (*s != '\0')
		ret = 0;
    }
    ALLOCV_END(tmp);

    return ret;
}

static VALUE
string_to_c_strict(VALUE self)
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

    if (!parse_comp(s, 1, &num)) {
	rb_raise(rb_eArgError, "invalid value for convert(): %+"PRIsVALUE,
		 self);
    }

    return num;
}

/*
 * call-seq:
 *    str.to_c  ->  complex
 *
 * Returns a complex which denotes the string form.  The parser
 * ignores leading whitespaces and trailing garbage.  Any digit
 * sequences can be separated by an underscore.  Returns zero for null
 * or garbage string.
 *
 *    '9'.to_c           #=> (9+0i)
 *    '2.5'.to_c         #=> (2.5+0i)
 *    '2.5/1'.to_c       #=> ((5/2)+0i)
 *    '-3/2'.to_c        #=> ((-3/2)+0i)
 *    '-i'.to_c          #=> (0-1i)
 *    '45i'.to_c         #=> (0+45i)
 *    '3-4i'.to_c        #=> (3-4i)
 *    '-4e2-4e-2i'.to_c  #=> (-400.0-0.04i)
 *    '-0.0-0.0i'.to_c   #=> (-0.0-0.0i)
 *    '1/2+3/4i'.to_c    #=> ((1/2)+(3/4)*i)
 *    'ruby'.to_c        #=> (0+0i)
 *
 * See Kernel.Complex.
 */
static VALUE
string_to_c(VALUE self)
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

    (void)parse_comp(s, 0, &num);

    return num;
}

static VALUE
nucomp_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, backref;

    rb_scan_args(argc, argv, "11", &a1, &a2);

    if (NIL_P(a1) || (argc == 2 && NIL_P(a2)))
	rb_raise(rb_eTypeError, "can't convert nil into Complex");

    backref = rb_backref_get();
    rb_match_busy(backref);

    if (RB_TYPE_P(a1, T_STRING)) {
	a1 = string_to_c_strict(a1);
    }

    if (RB_TYPE_P(a2, T_STRING)) {
	a2 = string_to_c_strict(a2);
    }

    rb_backref_set(backref);

    if (RB_TYPE_P(a1, T_COMPLEX)) {
	{
	    get_dat1(a1);

	    if (k_exact_zero_p(dat->imag))
		a1 = dat->real;
	}
    }

    if (RB_TYPE_P(a2, T_COMPLEX)) {
	{
	    get_dat1(a2);

	    if (k_exact_zero_p(dat->imag))
		a2 = dat->real;
	}
    }

    if (RB_TYPE_P(a1, T_COMPLEX)) {
	if (argc == 1 || (k_exact_zero_p(a2)))
	    return a1;
    }

    if (argc == 1) {
	if (k_numeric_p(a1) && !f_real_p(a1))
	    return a1;
	/* should raise exception for consistency */
	if (!k_numeric_p(a1))
	    return rb_convert_type(a1, T_COMPLEX, "Complex", "to_c");
    }
    else {
	if ((k_numeric_p(a1) && k_numeric_p(a2)) &&
	    (!f_real_p(a1) || !f_real_p(a2)))
	    return f_add(a1,
			 f_mul(a2,
			       f_complex_new_bang2(rb_cComplex, ZERO, ONE)));
    }

    {
	VALUE argv2[2];
	argv2[0] = a1;
	argv2[1] = a2;
	return nucomp_s_new(argc, argv2, klass);
    }
}

/* --- */

/*
 * call-seq:
 *    num.real  ->  self
 *
 * Returns self.
 */
static VALUE
numeric_real(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *    num.imag       ->  0
 *    num.imaginary  ->  0
 *
 * Returns zero.
 */
static VALUE
numeric_imag(VALUE self)
{
    return INT2FIX(0);
}

/*
 * call-seq:
 *    num.abs2  ->  real
 *
 * Returns square of self.
 */
static VALUE
numeric_abs2(VALUE self)
{
    return f_mul(self, self);
}

/*
 * call-seq:
 *    num.arg    ->  0 or float
 *    num.angle  ->  0 or float
 *    num.phase  ->  0 or float
 *
 * Returns 0 if the value is positive, pi otherwise.
 */
static VALUE
numeric_arg(VALUE self)
{
    if (f_positive_p(self))
        return INT2FIX(0);
    return DBL2NUM(M_PI);
}

/*
 * call-seq:
 *    num.rect  ->  array
 *    num.rectangular  ->  array
 *
 * Returns an array; [num, 0].
 */
static VALUE
numeric_rect(VALUE self)
{
    return rb_assoc_new(self, INT2FIX(0));
}

static VALUE float_arg(VALUE self);

/*
 * call-seq:
 *    num.polar  ->  array
 *
 * Returns an array; [num.abs, num.arg].
 */
static VALUE
numeric_polar(VALUE self)
{
    VALUE abs, arg;

    if (RB_INTEGER_TYPE_P(self)) {
        abs = rb_int_abs(self);
        arg = numeric_arg(self);
    }
    else if (RB_FLOAT_TYPE_P(self)) {
        abs = rb_float_abs(self);
        arg = float_arg(self);
    }
    else if (RB_TYPE_P(self, T_RATIONAL)) {
        abs = rb_rational_abs(self);
        arg = numeric_arg(self);
    }
    else {
        abs = f_abs(self);
        arg = f_arg(self);
    }
    return rb_assoc_new(abs, arg);
}

/*
 * call-seq:
 *    num.conj       ->  self
 *    num.conjugate  ->  self
 *
 * Returns self.
 */
static VALUE
numeric_conj(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *    flo.arg    ->  0 or float
 *    flo.angle  ->  0 or float
 *    flo.phase  ->  0 or float
 *
 * Returns 0 if the value is positive, pi otherwise.
 */
static VALUE
float_arg(VALUE self)
{
    if (isnan(RFLOAT_VALUE(self)))
	return self;
    if (f_tpositive_p(self))
	return INT2FIX(0);
    return rb_const_get(rb_mMath, id_PI);
}

/*
 * A complex number can be represented as a paired real number with
 * imaginary unit; a+bi.  Where a is real part, b is imaginary part
 * and i is imaginary unit.  Real a equals complex a+0i
 * mathematically.
 *
 * Complex object can be created as literal, and also by using
 * Kernel#Complex, Complex::rect, Complex::polar or to_c method.
 *
 *    2+1i                 #=> (2+1i)
 *    Complex(1)           #=> (1+0i)
 *    Complex(2, 3)        #=> (2+3i)
 *    Complex.polar(2, 3)  #=> (-1.9799849932008908+0.2822400161197344i)
 *    3.to_c               #=> (3+0i)
 *
 * You can also create complex object from floating-point numbers or
 * strings.
 *
 *    Complex(0.3)         #=> (0.3+0i)
 *    Complex('0.3-0.5i')  #=> (0.3-0.5i)
 *    Complex('2/3+3/4i')  #=> ((2/3)+(3/4)*i)
 *    Complex('1@2')       #=> (-0.4161468365471424+0.9092974268256817i)
 *
 *    0.3.to_c             #=> (0.3+0i)
 *    '0.3-0.5i'.to_c      #=> (0.3-0.5i)
 *    '2/3+3/4i'.to_c      #=> ((2/3)+(3/4)*i)
 *    '1@2'.to_c           #=> (-0.4161468365471424+0.9092974268256817i)
 *
 * A complex object is either an exact or an inexact number.
 *
 *    Complex(1, 1) / 2    #=> ((1/2)+(1/2)*i)
 *    Complex(1, 1) / 2.0  #=> (0.5+0.5i)
 */
void
Init_Complex(void)
{
    VALUE compat;
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    assert(fprintf(stderr, "assert() is now active\n"));

    id_abs = rb_intern("abs");
    id_arg = rb_intern("arg");
    id_denominator = rb_intern("denominator");
    id_expt = rb_intern("**");
    id_fdiv = rb_intern("fdiv");
    id_negate = rb_intern("-@");
    id_numerator = rb_intern("numerator");
    id_quo = rb_intern("quo");
    id_real_p = rb_intern("real?");
    id_to_f = rb_intern("to_f");
    id_to_i = rb_intern("to_i");
    id_to_r = rb_intern("to_r");
    id_i_real = rb_intern("@real");
    id_i_imag = rb_intern("@image"); /* @image, not @imag */
    id_finite_p = rb_intern("finite?");
    id_infinite_p = rb_intern("infinite?");
    id_rationalize = rb_intern("rationalize");
    id_PI = rb_intern("PI");

    rb_cComplex = rb_define_class("Complex", rb_cNumeric);

    rb_define_alloc_func(rb_cComplex, nucomp_s_alloc);
    rb_undef_method(CLASS_OF(rb_cComplex), "allocate");

#if 0
    rb_define_private_method(CLASS_OF(rb_cComplex), "new!", nucomp_s_new_bang, -1);
    rb_define_private_method(CLASS_OF(rb_cComplex), "new", nucomp_s_new, -1);
#else
    rb_undef_method(CLASS_OF(rb_cComplex), "new");
#endif

    rb_define_singleton_method(rb_cComplex, "rectangular", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "rect", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "polar", nucomp_s_polar, -1);

    rb_define_global_function("Complex", nucomp_f_complex, -1);

    rb_undef_methods_from(rb_cComplex, rb_mComparable);
    rb_undef_method(rb_cComplex, "%");
    rb_undef_method(rb_cComplex, "<=>");
    rb_undef_method(rb_cComplex, "div");
    rb_undef_method(rb_cComplex, "divmod");
    rb_undef_method(rb_cComplex, "floor");
    rb_undef_method(rb_cComplex, "ceil");
    rb_undef_method(rb_cComplex, "modulo");
    rb_undef_method(rb_cComplex, "remainder");
    rb_undef_method(rb_cComplex, "round");
    rb_undef_method(rb_cComplex, "step");
    rb_undef_method(rb_cComplex, "truncate");
    rb_undef_method(rb_cComplex, "i");

    rb_define_method(rb_cComplex, "real", nucomp_real, 0);
    rb_define_method(rb_cComplex, "imaginary", nucomp_imag, 0);
    rb_define_method(rb_cComplex, "imag", nucomp_imag, 0);

    rb_define_method(rb_cComplex, "-@", nucomp_negate, 0);
    rb_define_method(rb_cComplex, "+", rb_complex_plus, 1);
    rb_define_method(rb_cComplex, "-", nucomp_sub, 1);
    rb_define_method(rb_cComplex, "*", nucomp_mul, 1);
    rb_define_method(rb_cComplex, "/", nucomp_div, 1);
    rb_define_method(rb_cComplex, "quo", nucomp_quo, 1);
    rb_define_method(rb_cComplex, "fdiv", nucomp_fdiv, 1);
    rb_define_method(rb_cComplex, "**", nucomp_expt, 1);

    rb_define_method(rb_cComplex, "==", nucomp_eqeq_p, 1);
    rb_define_method(rb_cComplex, "coerce", nucomp_coerce, 1);

    rb_define_method(rb_cComplex, "abs", nucomp_abs, 0);
    rb_define_method(rb_cComplex, "magnitude", nucomp_abs, 0);
    rb_define_method(rb_cComplex, "abs2", nucomp_abs2, 0);
    rb_define_method(rb_cComplex, "arg", nucomp_arg, 0);
    rb_define_method(rb_cComplex, "angle", nucomp_arg, 0);
    rb_define_method(rb_cComplex, "phase", nucomp_arg, 0);
    rb_define_method(rb_cComplex, "rectangular", nucomp_rect, 0);
    rb_define_method(rb_cComplex, "rect", nucomp_rect, 0);
    rb_define_method(rb_cComplex, "polar", nucomp_polar, 0);
    rb_define_method(rb_cComplex, "conjugate", nucomp_conj, 0);
    rb_define_method(rb_cComplex, "conj", nucomp_conj, 0);
#if 0
    rb_define_method(rb_cComplex, "~", nucomp_conj, 0); /* gcc */
#endif

    rb_define_method(rb_cComplex, "real?", nucomp_false, 0);
#if 0
    rb_define_method(rb_cComplex, "complex?", nucomp_true, 0);
    rb_define_method(rb_cComplex, "exact?", nucomp_exact_p, 0);
    rb_define_method(rb_cComplex, "inexact?", nucomp_inexact_p, 0);
#endif

    rb_define_method(rb_cComplex, "numerator", nucomp_numerator, 0);
    rb_define_method(rb_cComplex, "denominator", nucomp_denominator, 0);

    rb_define_method(rb_cComplex, "hash", nucomp_hash, 0);
    rb_define_method(rb_cComplex, "eql?", nucomp_eql_p, 1);

    rb_define_method(rb_cComplex, "to_s", nucomp_to_s, 0);
    rb_define_method(rb_cComplex, "inspect", nucomp_inspect, 0);

    rb_undef_method(rb_cComplex, "positive?");
    rb_undef_method(rb_cComplex, "negative?");

    rb_define_method(rb_cComplex, "finite?", rb_complex_finite_p, 0);
    rb_define_method(rb_cComplex, "infinite?", rb_complex_infinite_p, 0);

    rb_define_private_method(rb_cComplex, "marshal_dump", nucomp_marshal_dump, 0);
    compat = rb_define_class_under(rb_cComplex, "compatible", rb_cObject); /* :nodoc: */
    rb_define_private_method(compat, "marshal_load", nucomp_marshal_load, 1);
    rb_marshal_define_compat(rb_cComplex, compat, nucomp_dumper, nucomp_loader);

    /* --- */

    rb_define_method(rb_cComplex, "to_i", nucomp_to_i, 0);
    rb_define_method(rb_cComplex, "to_f", nucomp_to_f, 0);
    rb_define_method(rb_cComplex, "to_r", nucomp_to_r, 0);
    rb_define_method(rb_cComplex, "rationalize", nucomp_rationalize, -1);
    rb_define_method(rb_cComplex, "to_c", nucomp_to_c, 0);
    rb_define_method(rb_cNilClass, "to_c", nilclass_to_c, 0);
    rb_define_method(rb_cNumeric, "to_c", numeric_to_c, 0);

    rb_define_method(rb_cString, "to_c", string_to_c, 0);

    rb_define_private_method(CLASS_OF(rb_cComplex), "convert", nucomp_s_convert, -1);

    /* --- */

    rb_define_method(rb_cNumeric, "real", numeric_real, 0);
    rb_define_method(rb_cNumeric, "imaginary", numeric_imag, 0);
    rb_define_method(rb_cNumeric, "imag", numeric_imag, 0);
    rb_define_method(rb_cNumeric, "abs2", numeric_abs2, 0);
    rb_define_method(rb_cNumeric, "arg", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "angle", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "phase", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "rectangular", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "rect", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "polar", numeric_polar, 0);
    rb_define_method(rb_cNumeric, "conjugate", numeric_conj, 0);
    rb_define_method(rb_cNumeric, "conj", numeric_conj, 0);

    rb_define_method(rb_cFloat, "arg", float_arg, 0);
    rb_define_method(rb_cFloat, "angle", float_arg, 0);
    rb_define_method(rb_cFloat, "phase", float_arg, 0);

    /*
     * The imaginary unit.
     */
    rb_define_const(rb_cComplex, "I",
		    f_complex_new_bang2(rb_cComplex, ZERO, ONE));

    rb_provide("complex.so");	/* for backward compatibility */
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
