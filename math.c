/**********************************************************************

  math.c -

  $Author$
  created at: Tue Jan 25 14:12:56 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#ifdef _MSC_VER
# define _USE_MATH_DEFINES 1
#endif

#include <errno.h>
#include <float.h>
#include <math.h>

#include "internal.h"
#include "internal/bignum.h"
#include "internal/complex.h"
#include "internal/math.h"
#include "internal/object.h"
#include "internal/vm.h"

VALUE rb_mMath;
VALUE rb_eMathDomainError;

#define Get_Double(x) rb_num_to_dbl(x)

#define domain_error(msg) \
    rb_raise(rb_eMathDomainError, "Numerical argument is out of domain - " msg)
#define domain_check_min(val, min, msg) \
    ((val) < (min) ? domain_error(msg) : (void)0)
#define domain_check_range(val, min, max, msg) \
    ((val) < (min) || (max) < (val) ? domain_error(msg) : (void)0)

/*
 *  call-seq:
 *     Math.atan2(y, x)  -> Float
 *
 *  Computes the arc tangent given +y+ and +x+.
 *  Returns a Float in the range -PI..PI. Return value is a angle
 *  in radians between the positive x-axis of cartesian plane
 *  and the point given by the coordinates (+x+, +y+) on it.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: [-PI, PI]
 *
 *    Math.atan2(-0.0, -1.0) #=> -3.141592653589793
 *    Math.atan2(-1.0, -1.0) #=> -2.356194490192345
 *    Math.atan2(-1.0, 0.0)  #=> -1.5707963267948966
 *    Math.atan2(-1.0, 1.0)  #=> -0.7853981633974483
 *    Math.atan2(-0.0, 1.0)  #=> -0.0
 *    Math.atan2(0.0, 1.0)   #=> 0.0
 *    Math.atan2(1.0, 1.0)   #=> 0.7853981633974483
 *    Math.atan2(1.0, 0.0)   #=> 1.5707963267948966
 *    Math.atan2(1.0, -1.0)  #=> 2.356194490192345
 *    Math.atan2(0.0, -1.0)  #=> 3.141592653589793
 *    Math.atan2(INFINITY, INFINITY)   #=> 0.7853981633974483
 *    Math.atan2(INFINITY, -INFINITY)  #=> 2.356194490192345
 *    Math.atan2(-INFINITY, INFINITY)  #=> -0.7853981633974483
 *    Math.atan2(-INFINITY, -INFINITY) #=> -2.356194490192345
 *
 */

static VALUE
math_atan2(VALUE unused_obj, VALUE y, VALUE x)
{
    double dx, dy;
    dx = Get_Double(x);
    dy = Get_Double(y);
    if (dx == 0.0 && dy == 0.0) {
	if (!signbit(dx))
	    return DBL2NUM(dy);
        if (!signbit(dy))
	    return DBL2NUM(M_PI);
	return DBL2NUM(-M_PI);
    }
#ifndef ATAN2_INF_C99
    if (isinf(dx) && isinf(dy)) {
	/* optimization for FLONUM */
	if (dx < 0.0) {
	    const double dz = (3.0 * M_PI / 4.0);
	    return (dy < 0.0) ? DBL2NUM(-dz) : DBL2NUM(dz);
	}
	else {
	    const double dz = (M_PI / 4.0);
	    return (dy < 0.0) ? DBL2NUM(-dz) : DBL2NUM(dz);
	}
    }
#endif
    return DBL2NUM(atan2(dy, dx));
}


/*
 *  call-seq:
 *     Math.cos(x)    -> Float
 *
 *  Computes the cosine of +x+ (expressed in radians).
 *  Returns a Float in the range -1.0..1.0.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: [-1, 1]
 *
 *    Math.cos(Math::PI) #=> -1.0
 *
 */

static VALUE
math_cos(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(cos(Get_Double(x)));
}

/*
 *  call-seq:
 *     Math.sin(x)    -> Float
 *
 *  Computes the sine of +x+ (expressed in radians).
 *  Returns a Float in the range -1.0..1.0.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: [-1, 1]
 *
 *    Math.sin(Math::PI/2) #=> 1.0
 *
 */

static VALUE
math_sin(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(sin(Get_Double(x)));
}


/*
 *  call-seq:
 *     Math.tan(x)    -> Float
 *
 *  Computes the tangent of +x+ (expressed in radians).
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.tan(0) #=> 0.0
 *
 */

static VALUE
math_tan(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(tan(Get_Double(x)));
}

/*
 *  call-seq:
 *     Math.acos(x)    -> Float
 *
 *  Computes the arc cosine of +x+. Returns 0..PI.
 *
 *  Domain: [-1, 1]
 *
 *  Codomain: [0, PI]
 *
 *    Math.acos(0) == Math::PI/2  #=> true
 *
 */

static VALUE
math_acos(VALUE unused_obj, VALUE x)
{
    double d;

    d = Get_Double(x);
    domain_check_range(d, -1.0, 1.0, "acos");
    return DBL2NUM(acos(d));
}

/*
 *  call-seq:
 *     Math.asin(x)    -> Float
 *
 *  Computes the arc sine of +x+. Returns -PI/2..PI/2.
 *
 *  Domain: [-1, -1]
 *
 *  Codomain: [-PI/2, PI/2]
 *
 *    Math.asin(1) == Math::PI/2  #=> true
 */

static VALUE
math_asin(VALUE unused_obj, VALUE x)
{
    double d;

    d = Get_Double(x);
    domain_check_range(d, -1.0, 1.0, "asin");
    return DBL2NUM(asin(d));
}

/*
 *  call-seq:
 *     Math.atan(x)    -> Float
 *
 *  Computes the arc tangent of +x+. Returns -PI/2..PI/2.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-PI/2, PI/2)
 *
 *    Math.atan(0) #=> 0.0
 */

static VALUE
math_atan(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(atan(Get_Double(x)));
}

#ifndef HAVE_COSH
double
cosh(double x)
{
    return (exp(x) + exp(-x)) / 2;
}
#endif

/*
 *  call-seq:
 *     Math.cosh(x)    -> Float
 *
 *  Computes the hyperbolic cosine of +x+ (expressed in radians).
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: [1, INFINITY)
 *
 *    Math.cosh(0) #=> 1.0
 *
 */

static VALUE
math_cosh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(cosh(Get_Double(x)));
}

#ifndef HAVE_SINH
double
sinh(double x)
{
    return (exp(x) - exp(-x)) / 2;
}
#endif

/*
 *  call-seq:
 *     Math.sinh(x)    -> Float
 *
 *  Computes the hyperbolic sine of +x+ (expressed in radians).
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.sinh(0) #=> 0.0
 *
 */

static VALUE
math_sinh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(sinh(Get_Double(x)));
}

#ifndef HAVE_TANH
double
tanh(double x)
{
# if defined(HAVE_SINH) && defined(HAVE_COSH)
    const double c = cosh(x);
    if (!isinf(c)) return sinh(x) / c;
# else
    const double e = exp(x+x);
    if (!isinf(e)) return (e - 1) / (e + 1);
# endif
    return x > 0 ? 1.0 : -1.0;
}
#endif

/*
 *  call-seq:
 *     Math.tanh(x)    -> Float
 *
 *  Computes the hyperbolic tangent of +x+ (expressed in radians).
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-1, 1)
 *
 *    Math.tanh(0) #=> 0.0
 *
 */

static VALUE
math_tanh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(tanh(Get_Double(x)));
}

/*
 *  call-seq:
 *     Math.acosh(x)    -> Float
 *
 *  Computes the inverse hyperbolic cosine of +x+.
 *
 *  Domain: [1, INFINITY)
 *
 *  Codomain: [0, INFINITY)
 *
 *    Math.acosh(1) #=> 0.0
 *
 */

static VALUE
math_acosh(VALUE unused_obj, VALUE x)
{
    double d;

    d = Get_Double(x);
    domain_check_min(d, 1.0, "acosh");
    return DBL2NUM(acosh(d));
}

/*
 *  call-seq:
 *     Math.asinh(x)    -> Float
 *
 *  Computes the inverse hyperbolic sine of +x+.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.asinh(1) #=> 0.881373587019543
 *
 */

static VALUE
math_asinh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(asinh(Get_Double(x)));
}

/*
 *  call-seq:
 *     Math.atanh(x)    -> Float
 *
 *  Computes the inverse hyperbolic tangent of +x+.
 *
 *  Domain: (-1, 1)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *   Math.atanh(1) #=> Infinity
 *
 */

static VALUE
math_atanh(VALUE unused_obj, VALUE x)
{
    double d;

    d = Get_Double(x);
    domain_check_range(d, -1.0, +1.0, "atanh");
    /* check for pole error */
    if (d == -1.0) return DBL2NUM(-HUGE_VAL);
    if (d == +1.0) return DBL2NUM(+HUGE_VAL);
    return DBL2NUM(atanh(d));
}

/*
 *  call-seq:
 *     Math.exp(x)    -> Float
 *
 *  Returns e**x.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (0, INFINITY)
 *
 *    Math.exp(0)       #=> 1.0
 *    Math.exp(1)       #=> 2.718281828459045
 *    Math.exp(1.5)     #=> 4.4816890703380645
 *
 */

static VALUE
math_exp(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(exp(Get_Double(x)));
}

#if defined __CYGWIN__
# include <cygwin/version.h>
# if CYGWIN_VERSION_DLL_MAJOR < 1005
#  define nan(x) nan()
# endif
# define log(x) ((x) < 0.0 ? nan("") : log(x))
# define log10(x) ((x) < 0.0 ? nan("") : log10(x))
#endif

#ifndef M_LN2
# define M_LN2 0.693147180559945309417232121458176568
#endif
#ifndef M_LN10
# define M_LN10 2.30258509299404568401799145468436421
#endif

static double math_log1(VALUE x);
FUNC_MINIMIZED(static VALUE math_log(int, const VALUE *, VALUE));

/*
 *  call-seq:
 *     Math.log(x)          -> Float
 *     Math.log(x, base)    -> Float
 *
 *  Returns the logarithm of +x+.
 *  If additional second argument is given, it will be the base
 *  of logarithm. Otherwise it is +e+ (for the natural logarithm).
 *
 *  Domain: (0, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.log(0)          #=> -Infinity
 *    Math.log(1)          #=> 0.0
 *    Math.log(Math::E)    #=> 1.0
 *    Math.log(Math::E**3) #=> 3.0
 *    Math.log(12, 3)      #=> 2.2618595071429146
 *
 */

static VALUE
math_log(int argc, const VALUE *argv, VALUE unused_obj)
{
    return rb_math_log(argc, argv);
}

VALUE
rb_math_log(int argc, const VALUE *argv)
{
    VALUE x, base;
    double d;

    rb_scan_args(argc, argv, "11", &x, &base);
    d = math_log1(x);
    if (argc == 2) {
	d /= math_log1(base);
    }
    return DBL2NUM(d);
}

static double
get_double_rshift(VALUE x, size_t *pnumbits)
{
    size_t numbits;

    if (RB_BIGNUM_TYPE_P(x) && BIGNUM_POSITIVE_P(x) &&
            DBL_MAX_EXP <= (numbits = rb_absint_numwords(x, 1, NULL))) {
        numbits -= DBL_MANT_DIG;
        x = rb_big_rshift(x, SIZET2NUM(numbits));
    }
    else {
	numbits = 0;
    }
    *pnumbits = numbits;
    return Get_Double(x);
}

static double
math_log1(VALUE x)
{
    size_t numbits;
    double d = get_double_rshift(x, &numbits);

    domain_check_min(d, 0.0, "log");
    /* check for pole error */
    if (d == 0.0) return -HUGE_VAL;

    return log(d) + numbits * M_LN2; /* log(d * 2 ** numbits) */
}

#ifndef log2
#ifndef HAVE_LOG2
double
log2(double x)
{
    return log10(x)/log10(2.0);
}
#else
extern double log2(double);
#endif
#endif

/*
 *  call-seq:
 *     Math.log2(x)    -> Float
 *
 *  Returns the base 2 logarithm of +x+.
 *
 *  Domain: (0, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.log2(1)      #=> 0.0
 *    Math.log2(2)      #=> 1.0
 *    Math.log2(32768)  #=> 15.0
 *    Math.log2(65536)  #=> 16.0
 *
 */

static VALUE
math_log2(VALUE unused_obj, VALUE x)
{
    size_t numbits;
    double d = get_double_rshift(x, &numbits);

    domain_check_min(d, 0.0, "log2");
    /* check for pole error */
    if (d == 0.0) return DBL2NUM(-HUGE_VAL);

    return DBL2NUM(log2(d) + numbits); /* log2(d * 2 ** numbits) */
}

/*
 *  call-seq:
 *     Math.log10(x)    -> Float
 *
 *  Returns the base 10 logarithm of +x+.
 *
 *  Domain: (0, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    Math.log10(1)       #=> 0.0
 *    Math.log10(10)      #=> 1.0
 *    Math.log10(10**100) #=> 100.0
 *
 */

static VALUE
math_log10(VALUE unused_obj, VALUE x)
{
    size_t numbits;
    double d = get_double_rshift(x, &numbits);

    domain_check_min(d, 0.0, "log10");
    /* check for pole error */
    if (d == 0.0) return DBL2NUM(-HUGE_VAL);

    return DBL2NUM(log10(d) + numbits * log10(2)); /* log10(d * 2 ** numbits) */
}

static VALUE rb_math_sqrt(VALUE x);

/*
 *  call-seq:
 *     Math.sqrt(x)    -> Float
 *
 *  Returns the non-negative square root of +x+.
 *
 *  Domain: [0, INFINITY)
 *
 *  Codomain:[0, INFINITY)
 *
 *    0.upto(10) {|x|
 *      p [x, Math.sqrt(x), Math.sqrt(x)**2]
 *    }
 *    #=> [0, 0.0, 0.0]
 *    #   [1, 1.0, 1.0]
 *    #   [2, 1.4142135623731, 2.0]
 *    #   [3, 1.73205080756888, 3.0]
 *    #   [4, 2.0, 4.0]
 *    #   [5, 2.23606797749979, 5.0]
 *    #   [6, 2.44948974278318, 6.0]
 *    #   [7, 2.64575131106459, 7.0]
 *    #   [8, 2.82842712474619, 8.0]
 *    #   [9, 3.0, 9.0]
 *    #   [10, 3.16227766016838, 10.0]
 *
 *  Note that the limited precision of floating point arithmetic
 *  might lead to surprising results:
 *
 *    Math.sqrt(10**46).to_i  #=> 99999999999999991611392 (!)
 *
 *  See also BigDecimal#sqrt and Integer.sqrt.
 */

static VALUE
math_sqrt(VALUE unused_obj, VALUE x)
{
    return rb_math_sqrt(x);
}

inline static VALUE
f_negative_p(VALUE x)
{
    if (FIXNUM_P(x))
        return RBOOL(FIX2LONG(x) < 0);
    return rb_funcall(x, '<', 1, INT2FIX(0));
}
inline static VALUE
f_signbit(VALUE x)
{
    if (RB_FLOAT_TYPE_P(x)) {
        double f = RFLOAT_VALUE(x);
        return RBOOL(!isnan(f) && signbit(f));
    }
    return f_negative_p(x);
}

static VALUE
rb_math_sqrt(VALUE x)
{
    double d;

    if (RB_TYPE_P(x, T_COMPLEX)) {
	VALUE neg = f_signbit(RCOMPLEX(x)->imag);
	double re = Get_Double(RCOMPLEX(x)->real), im;
	d = Get_Double(rb_complex_abs(x));
	im = sqrt((d - re) / 2.0);
	re = sqrt((d + re) / 2.0);
	if (neg) im = -im;
	return rb_complex_new(DBL2NUM(re), DBL2NUM(im));
    }
    d = Get_Double(x);
    domain_check_min(d, 0.0, "sqrt");
    if (d == 0.0) return DBL2NUM(0.0);
    return DBL2NUM(sqrt(d));
}

/*
 *  call-seq:
 *     Math.cbrt(x)    -> Float
 *
 *  Returns the cube root of +x+.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-INFINITY, INFINITY)
 *
 *    -9.upto(9) {|x|
 *      p [x, Math.cbrt(x), Math.cbrt(x)**3]
 *    }
 *    #=> [-9, -2.0800838230519, -9.0]
 *    #   [-8, -2.0, -8.0]
 *    #   [-7, -1.91293118277239, -7.0]
 *    #   [-6, -1.81712059283214, -6.0]
 *    #   [-5, -1.7099759466767, -5.0]
 *    #   [-4, -1.5874010519682, -4.0]
 *    #   [-3, -1.44224957030741, -3.0]
 *    #   [-2, -1.25992104989487, -2.0]
 *    #   [-1, -1.0, -1.0]
 *    #   [0, 0.0, 0.0]
 *    #   [1, 1.0, 1.0]
 *    #   [2, 1.25992104989487, 2.0]
 *    #   [3, 1.44224957030741, 3.0]
 *    #   [4, 1.5874010519682, 4.0]
 *    #   [5, 1.7099759466767, 5.0]
 *    #   [6, 1.81712059283214, 6.0]
 *    #   [7, 1.91293118277239, 7.0]
 *    #   [8, 2.0, 8.0]
 *    #   [9, 2.0800838230519, 9.0]
 *
 */

static VALUE
math_cbrt(VALUE unused_obj, VALUE x)
{
    double f = Get_Double(x);
    double r = cbrt(f);
#if defined __GLIBC__
    if (isfinite(r) && !(f == 0.0 && r == 0.0)) {
	r = (2.0 * r + (f / r / r)) / 3.0;
    }
#endif
    return DBL2NUM(r);
}

/*
 *  call-seq:
 *     Math.frexp(x)    -> [fraction, exponent]
 *
 *  Returns a two-element array containing the normalized fraction (a Float)
 *  and exponent (an Integer) of +x+.
 *
 *     fraction, exponent = Math.frexp(1234)   #=> [0.6025390625, 11]
 *     fraction * 2**exponent                  #=> 1234.0
 */

static VALUE
math_frexp(VALUE unused_obj, VALUE x)
{
    double d;
    int exp;

    d = frexp(Get_Double(x), &exp);
    return rb_assoc_new(DBL2NUM(d), INT2NUM(exp));
}

/*
 *  call-seq:
 *     Math.ldexp(fraction, exponent) -> float
 *
 *  Returns the value of +fraction+*(2**+exponent+).
 *
 *     fraction, exponent = Math.frexp(1234)
 *     Math.ldexp(fraction, exponent)   #=> 1234.0
 */

static VALUE
math_ldexp(VALUE unused_obj, VALUE x, VALUE n)
{
    return DBL2NUM(ldexp(Get_Double(x), NUM2INT(n)));
}

/*
 *  call-seq:
 *     Math.hypot(x, y)    -> Float
 *
 *  Returns sqrt(x**2 + y**2), the hypotenuse of a right-angled triangle with
 *  sides +x+ and +y+.
 *
 *     Math.hypot(3, 4)   #=> 5.0
 */

static VALUE
math_hypot(VALUE unused_obj, VALUE x, VALUE y)
{
    return DBL2NUM(hypot(Get_Double(x), Get_Double(y)));
}

/*
 * call-seq:
 *    Math.erf(x)  -> Float
 *
 *  Calculates the error function of +x+.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (-1, 1)
 *
 *    Math.erf(0) #=> 0.0
 *
 */

static VALUE
math_erf(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(erf(Get_Double(x)));
}

/*
 * call-seq:
 *    Math.erfc(x)  -> Float
 *
 *  Calculates the complementary error function of x.
 *
 *  Domain: (-INFINITY, INFINITY)
 *
 *  Codomain: (0, 2)
 *
 *    Math.erfc(0) #=> 1.0
 *
 */

static VALUE
math_erfc(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(erfc(Get_Double(x)));
}

/*
 * call-seq:
 *    Math.gamma(x)  -> Float
 *
 *  Calculates the gamma function of x.
 *
 *  Note that gamma(n) is the same as fact(n-1) for integer n > 0.
 *  However gamma(n) returns float and can be an approximation.
 *
 *   def fact(n) (1..n).inject(1) {|r,i| r*i } end
 *   1.upto(26) {|i| p [i, Math.gamma(i), fact(i-1)] }
 *   #=> [1, 1.0, 1]
 *   #   [2, 1.0, 1]
 *   #   [3, 2.0, 2]
 *   #   [4, 6.0, 6]
 *   #   [5, 24.0, 24]
 *   #   [6, 120.0, 120]
 *   #   [7, 720.0, 720]
 *   #   [8, 5040.0, 5040]
 *   #   [9, 40320.0, 40320]
 *   #   [10, 362880.0, 362880]
 *   #   [11, 3628800.0, 3628800]
 *   #   [12, 39916800.0, 39916800]
 *   #   [13, 479001600.0, 479001600]
 *   #   [14, 6227020800.0, 6227020800]
 *   #   [15, 87178291200.0, 87178291200]
 *   #   [16, 1307674368000.0, 1307674368000]
 *   #   [17, 20922789888000.0, 20922789888000]
 *   #   [18, 355687428096000.0, 355687428096000]
 *   #   [19, 6.402373705728e+15, 6402373705728000]
 *   #   [20, 1.21645100408832e+17, 121645100408832000]
 *   #   [21, 2.43290200817664e+18, 2432902008176640000]
 *   #   [22, 5.109094217170944e+19, 51090942171709440000]
 *   #   [23, 1.1240007277776077e+21, 1124000727777607680000]
 *   #   [24, 2.5852016738885062e+22, 25852016738884976640000]
 *   #   [25, 6.204484017332391e+23, 620448401733239439360000]
 *   #   [26, 1.5511210043330954e+25, 15511210043330985984000000]
 *
 */

static VALUE
math_gamma(VALUE unused_obj, VALUE x)
{
    static const double fact_table[] = {
        /* fact(0) */ 1.0,
        /* fact(1) */ 1.0,
        /* fact(2) */ 2.0,
        /* fact(3) */ 6.0,
        /* fact(4) */ 24.0,
        /* fact(5) */ 120.0,
        /* fact(6) */ 720.0,
        /* fact(7) */ 5040.0,
        /* fact(8) */ 40320.0,
        /* fact(9) */ 362880.0,
        /* fact(10) */ 3628800.0,
        /* fact(11) */ 39916800.0,
        /* fact(12) */ 479001600.0,
        /* fact(13) */ 6227020800.0,
        /* fact(14) */ 87178291200.0,
        /* fact(15) */ 1307674368000.0,
        /* fact(16) */ 20922789888000.0,
        /* fact(17) */ 355687428096000.0,
        /* fact(18) */ 6402373705728000.0,
        /* fact(19) */ 121645100408832000.0,
        /* fact(20) */ 2432902008176640000.0,
        /* fact(21) */ 51090942171709440000.0,
        /* fact(22) */ 1124000727777607680000.0,
        /* fact(23)=25852016738884976640000 needs 56bit mantissa which is
         * impossible to represent exactly in IEEE 754 double which have
         * 53bit mantissa. */
    };
    enum {NFACT_TABLE = numberof(fact_table)};
    double d;
    d = Get_Double(x);
    /* check for domain error */
    if (isinf(d)) {
	if (signbit(d)) domain_error("gamma");
	return DBL2NUM(HUGE_VAL);
    }
    if (d == 0.0) {
	return signbit(d) ? DBL2NUM(-HUGE_VAL) : DBL2NUM(HUGE_VAL);
    }
    if (d == floor(d)) {
	domain_check_min(d, 0.0, "gamma");
	if (1.0 <= d && d <= (double)NFACT_TABLE) {
	    return DBL2NUM(fact_table[(int)d - 1]);
	}
    }
    return DBL2NUM(tgamma(d));
}

/*
 * call-seq:
 *    Math.lgamma(x)  -> [float, -1 or 1]
 *
 *  Calculates the logarithmic gamma of +x+ and the sign of gamma of +x+.
 *
 *  Math.lgamma(x) is the same as
 *   [Math.log(Math.gamma(x).abs), Math.gamma(x) < 0 ? -1 : 1]
 *  but avoids overflow by Math.gamma(x) for large x.
 *
 *    Math.lgamma(0) #=> [Infinity, 1]
 *
 */

static VALUE
math_lgamma(VALUE unused_obj, VALUE x)
{
    double d;
    int sign=1;
    VALUE v;
    d = Get_Double(x);
    /* check for domain error */
    if (isinf(d)) {
	if (signbit(d)) domain_error("lgamma");
	return rb_assoc_new(DBL2NUM(HUGE_VAL), INT2FIX(1));
    }
    if (d == 0.0) {
	VALUE vsign = signbit(d) ? INT2FIX(-1) : INT2FIX(+1);
	return rb_assoc_new(DBL2NUM(HUGE_VAL), vsign);
    }
    v = DBL2NUM(lgamma_r(d, &sign));
    return rb_assoc_new(v, INT2FIX(sign));
}


#define exp1(n) \
VALUE \
rb_math_##n(VALUE x)\
{\
    return math_##n(0, x);\
}

#define exp2(n) \
VALUE \
rb_math_##n(VALUE x, VALUE y)\
{\
    return math_##n(0, x, y);\
}

exp2(atan2)
exp1(cos)
exp1(cosh)
exp1(exp)
exp2(hypot)
exp1(sin)
exp1(sinh)
#if 0
exp1(sqrt)
#endif


/*
 *  Document-class: Math::DomainError
 *
 *  Raised when a mathematical function is evaluated outside of its
 *  domain of definition.
 *
 *  For example, since +cos+ returns values in the range -1..1,
 *  its inverse function +acos+ is only defined on that interval:
 *
 *     Math.acos(42)
 *
 *  <em>produces:</em>
 *
 *     Math::DomainError: Numerical argument is out of domain - "acos"
 */

/*
 *  Document-class: Math
 *
 *  The Math module contains module functions for basic
 *  trigonometric and transcendental functions. See class
 *  Float for a list of constants that
 *  define Ruby's floating point accuracy.
 *
 *  Domains and codomains are given only for real (not complex) numbers.
 */


void
InitVM_Math(void)
{
    rb_mMath = rb_define_module("Math");
    rb_eMathDomainError = rb_define_class_under(rb_mMath, "DomainError", rb_eStandardError);

    /*  Definition of the mathematical constant PI as a Float number. */
    rb_define_const(rb_mMath, "PI", DBL2NUM(M_PI));

#ifdef M_E
    /*  Definition of the mathematical constant E for Euler's number (e) as a Float number. */
    rb_define_const(rb_mMath, "E", DBL2NUM(M_E));
#else
    rb_define_const(rb_mMath, "E", DBL2NUM(exp(1.0)));
#endif

    rb_define_module_function(rb_mMath, "atan2", math_atan2, 2);
    rb_define_module_function(rb_mMath, "cos", math_cos, 1);
    rb_define_module_function(rb_mMath, "sin", math_sin, 1);
    rb_define_module_function(rb_mMath, "tan", math_tan, 1);

    rb_define_module_function(rb_mMath, "acos", math_acos, 1);
    rb_define_module_function(rb_mMath, "asin", math_asin, 1);
    rb_define_module_function(rb_mMath, "atan", math_atan, 1);

    rb_define_module_function(rb_mMath, "cosh", math_cosh, 1);
    rb_define_module_function(rb_mMath, "sinh", math_sinh, 1);
    rb_define_module_function(rb_mMath, "tanh", math_tanh, 1);

    rb_define_module_function(rb_mMath, "acosh", math_acosh, 1);
    rb_define_module_function(rb_mMath, "asinh", math_asinh, 1);
    rb_define_module_function(rb_mMath, "atanh", math_atanh, 1);

    rb_define_module_function(rb_mMath, "exp", math_exp, 1);
    rb_define_module_function(rb_mMath, "log", math_log, -1);
    rb_define_module_function(rb_mMath, "log2", math_log2, 1);
    rb_define_module_function(rb_mMath, "log10", math_log10, 1);
    rb_define_module_function(rb_mMath, "sqrt", math_sqrt, 1);
    rb_define_module_function(rb_mMath, "cbrt", math_cbrt, 1);

    rb_define_module_function(rb_mMath, "frexp", math_frexp, 1);
    rb_define_module_function(rb_mMath, "ldexp", math_ldexp, 2);

    rb_define_module_function(rb_mMath, "hypot", math_hypot, 2);

    rb_define_module_function(rb_mMath, "erf",  math_erf,  1);
    rb_define_module_function(rb_mMath, "erfc", math_erfc, 1);

    rb_define_module_function(rb_mMath, "gamma", math_gamma, 1);
    rb_define_module_function(rb_mMath, "lgamma", math_lgamma, 1);
}

void
Init_Math(void)
{
    InitVM(Math);
}
