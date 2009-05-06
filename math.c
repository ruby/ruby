/**********************************************************************

  math.c -

  $Author$
  created at: Tue Jan 25 14:12:56 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include <math.h>
#include <errno.h>

VALUE rb_mMath;

extern VALUE rb_to_float(VALUE val);
#define Need_Float(x) do {if (TYPE(x) != T_FLOAT) {(x) = rb_to_float(x);}} while(0)
#define Need_Float2(x,y) do {\
    Need_Float(x);\
    Need_Float(y);\
} while (0)

static void
domain_check(double x, double y, const char *msg)
{
    while(1) {
	if (errno) {
	    rb_sys_fail(msg);
	}
	if (isnan(y)) {
	    if (isnan(x)) break;
#if defined(EDOM)
	    errno = EDOM;
#elif defined(ERANGE)
	    errno = ERANGE;
#endif
	    continue;
	}
	break;
    }
}

static void
infinity_check(VALUE arg, double res, const char *msg)
{
    while(1) {
	if (errno) {
	    rb_sys_fail(msg);
	}
	if (isinf(res) && !isinf(RFLOAT_VALUE(arg))) {
#if defined(EDOM)
	    errno = EDOM;
#elif defined(ERANGE)
	    errno = ERANGE;
#endif
	    continue;
	}
	break;
    }
}

/*
 *  call-seq:
 *     Math.atan2(y, x)  => float
 *
 *  Computes the arc tangent given <i>y</i> and <i>x</i>. Returns
 *  -PI..PI.
 *
 */

static VALUE
math_atan2(VALUE obj, VALUE y, VALUE x)
{
    Need_Float2(y, x);
    return DBL2NUM(atan2(RFLOAT_VALUE(y), RFLOAT_VALUE(x)));
}


/*
 *  call-seq:
 *     Math.cos(x)    => float
 *
 *  Computes the cosine of <i>x</i> (expressed in radians). Returns
 *  -1..1.
 */

static VALUE
math_cos(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(cos(RFLOAT_VALUE(x)));
}

/*
 *  call-seq:
 *     Math.sin(x)    => float
 *
 *  Computes the sine of <i>x</i> (expressed in radians). Returns
 *  -1..1.
 */

static VALUE
math_sin(VALUE obj, VALUE x)
{
    Need_Float(x);

    return DBL2NUM(sin(RFLOAT_VALUE(x)));
}


/*
 *  call-seq:
 *     Math.tan(x)    => float
 *
 *  Returns the tangent of <i>x</i> (expressed in radians).
 */

static VALUE
math_tan(VALUE obj, VALUE x)
{
    Need_Float(x);

    return DBL2NUM(tan(RFLOAT_VALUE(x)));
}

/*
 *  call-seq:
 *     Math.acos(x)    => float
 *
 *  Computes the arc cosine of <i>x</i>. Returns 0..PI.
 */

static VALUE
math_acos(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = acos(d0);
    domain_check(d0, d, "acos");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.asin(x)    => float
 *
 *  Computes the arc sine of <i>x</i>. Returns -{PI/2} .. {PI/2}.
 */

static VALUE
math_asin(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = asin(d0);
    domain_check(d0, d, "asin");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.atan(x)    => float
 *
 *  Computes the arc tangent of <i>x</i>. Returns -{PI/2} .. {PI/2}.
 */

static VALUE
math_atan(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(atan(RFLOAT_VALUE(x)));
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
 *     Math.cosh(x)    => float
 *
 *  Computes the hyperbolic cosine of <i>x</i> (expressed in radians).
 */

static VALUE
math_cosh(VALUE obj, VALUE x)
{
    Need_Float(x);

    return DBL2NUM(cosh(RFLOAT_VALUE(x)));
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
 *     Math.sinh(x)    => float
 *
 *  Computes the hyperbolic sine of <i>x</i> (expressed in
 *  radians).
 */

static VALUE
math_sinh(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(sinh(RFLOAT_VALUE(x)));
}

#ifndef HAVE_TANH
double
tanh(double x)
{
    return sinh(x) / cosh(x);
}
#endif

/*
 *  call-seq:
 *     Math.tanh()    => float
 *
 *  Computes the hyperbolic tangent of <i>x</i> (expressed in
 *  radians).
 */

static VALUE
math_tanh(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(tanh(RFLOAT_VALUE(x)));
}

/*
 *  call-seq:
 *     Math.acosh(x)    => float
 *
 *  Computes the inverse hyperbolic cosine of <i>x</i>.
 */

static VALUE
math_acosh(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = acosh(d0);
    domain_check(d0, d, "acosh");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.asinh(x)    => float
 *
 *  Computes the inverse hyperbolic sine of <i>x</i>.
 */

static VALUE
math_asinh(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(asinh(RFLOAT_VALUE(x)));
}

/*
 *  call-seq:
 *     Math.atanh(x)    => float
 *
 *  Computes the inverse hyperbolic tangent of <i>x</i>.
 */

static VALUE
math_atanh(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = atanh(d0);
    domain_check(d0, d, "atanh");
    infinity_check(x, d, "atanh");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.exp(x)    => float
 *
 *  Returns e**x.
 */

static VALUE
math_exp(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(exp(RFLOAT_VALUE(x)));
}

#if defined __CYGWIN__
# include <cygwin/version.h>
# if CYGWIN_VERSION_DLL_MAJOR < 1005
#  define nan(x) nan()
# endif
# define log(x) ((x) < 0.0 ? nan("") : log(x))
# define log10(x) ((x) < 0.0 ? nan("") : log10(x))
#endif

/*
 *  call-seq:
 *     Math.log(numeric)    => float
 *     Math.log(num,base)   => float
 *
 *  Returns the natural logarithm of <i>numeric</i>.
 *  If additional second argument is given, it will be the base
 *  of logarithm.
 */

static VALUE
math_log(int argc, VALUE *argv)
{
    VALUE x, base;
    double d0, d;

    rb_scan_args(argc, argv, "11", &x, &base);
    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = log(d0);
    if (argc == 2) {
	Need_Float(base);
	d /= log(RFLOAT_VALUE(base));
    }
    domain_check(d0, d, "log");
    infinity_check(x, d, "log");
    return DBL2NUM(d);
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
 *     Math.log2(numeric)    => float
 *
 *  Returns the base 2 logarithm of <i>numeric</i>.
 */

static VALUE
math_log2(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = log2(d0);
    domain_check(d0, d, "log2");
    infinity_check(x, d, "log2");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.log10(numeric)    => float
 *
 *  Returns the base 10 logarithm of <i>numeric</i>.
 */

static VALUE
math_log10(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = log10(d0);
    domain_check(d0, d, "log10");
    infinity_check(x, d, "log10");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.sqrt(numeric)    => float
 *
 *  Returns the non-negative square root of <i>numeric</i>.
 *
 *    0.upto(10) {|x|
 *      p [x, Math.sqrt(x), Math.sqrt(x)**2]
 *    }
 *    #=>
 *    [0, 0.0, 0.0]
 *    [1, 1.0, 1.0]
 *    [2, 1.4142135623731, 2.0]
 *    [3, 1.73205080756888, 3.0]
 *    [4, 2.0, 4.0]
 *    [5, 2.23606797749979, 5.0]
 *    [6, 2.44948974278318, 6.0]
 *    [7, 2.64575131106459, 7.0]
 *    [8, 2.82842712474619, 8.0]
 *    [9, 3.0, 9.0]
 *    [10, 3.16227766016838, 10.0]
 *
 */

static VALUE
math_sqrt(VALUE obj, VALUE x)
{
    double d0, d;

    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = sqrt(d0);
    domain_check(d0, d, "sqrt");
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Math.cbrt(numeric)    => float
 *
 *  Returns the cube root of <i>numeric</i>.
 *
 *    -9.upto(9) {|x|
 *      p [x, Math.cbrt(x), Math.cbrt(x)**3]
 *    }
 *    #=>
 *    [-9, -2.0800838230519, -9.0]
 *    [-8, -2.0, -8.0]
 *    [-7, -1.91293118277239, -7.0]
 *    [-6, -1.81712059283214, -6.0]
 *    [-5, -1.7099759466767, -5.0]
 *    [-4, -1.5874010519682, -4.0]
 *    [-3, -1.44224957030741, -3.0]
 *    [-2, -1.25992104989487, -2.0]
 *    [-1, -1.0, -1.0]
 *    [0, 0.0, 0.0]
 *    [1, 1.0, 1.0]
 *    [2, 1.25992104989487, 2.0]
 *    [3, 1.44224957030741, 3.0]
 *    [4, 1.5874010519682, 4.0]
 *    [5, 1.7099759466767, 5.0]
 *    [6, 1.81712059283214, 6.0]
 *    [7, 1.91293118277239, 7.0]
 *    [8, 2.0, 8.0]
 *    [9, 2.0800838230519, 9.0]
 *
 */

static VALUE
math_cbrt(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(cbrt(RFLOAT_VALUE(x)));
}

/*
 *  call-seq:
 *     Math.frexp(numeric)    => [ fraction, exponent ]
 *
 *  Returns a two-element array containing the normalized fraction (a
 *  <code>Float</code>) and exponent (a <code>Fixnum</code>) of
 *  <i>numeric</i>.
 *
 *     fraction, exponent = Math.frexp(1234)   #=> [0.6025390625, 11]
 *     fraction * 2**exponent                  #=> 1234.0
 */

static VALUE
math_frexp(VALUE obj, VALUE x)
{
    double d;
    int exp;

    Need_Float(x);

    d = frexp(RFLOAT_VALUE(x), &exp);
    return rb_assoc_new(DBL2NUM(d), INT2NUM(exp));
}

/*
 *  call-seq:
 *     Math.ldexp(flt, int) -> float
 *
 *  Returns the value of <i>flt</i>*(2**<i>int</i>).
 *
 *     fraction, exponent = Math.frexp(1234)
 *     Math.ldexp(fraction, exponent)   #=> 1234.0
 */

static VALUE
math_ldexp(VALUE obj, VALUE x, VALUE n)
{
    Need_Float(x);
    return DBL2NUM(ldexp(RFLOAT_VALUE(x), NUM2INT(n)));
}

/*
 *  call-seq:
 *     Math.hypot(x, y)    => float
 *
 *  Returns sqrt(x**2 + y**2), the hypotenuse of a right-angled triangle
 *  with sides <i>x</i> and <i>y</i>.
 *
 *     Math.hypot(3, 4)   #=> 5.0
 */

static VALUE
math_hypot(VALUE obj, VALUE x, VALUE y)
{
    Need_Float2(x, y);
    return DBL2NUM(hypot(RFLOAT_VALUE(x), RFLOAT_VALUE(y)));
}

/*
 * call-seq:
 *    Math.erf(x)  => float
 *
 *  Calculates the error function of x.
 */

static VALUE
math_erf(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(erf(RFLOAT_VALUE(x)));
}

/*
 * call-seq:
 *    Math.erfc(x)  => float
 *
 *  Calculates the complementary error function of x.
 */

static VALUE
math_erfc(VALUE obj, VALUE x)
{
    Need_Float(x);
    return DBL2NUM(erfc(RFLOAT_VALUE(x)));
}

/*
 * call-seq:
 *    Math.gamma(x)  => float
 *
 *  Calculates the gamma function of x.
 *
 *  Note that gamma(n) is same as fact(n-1) for integer n >= 0.
 *  However gamma(n) returns float and possibly has error in calculation.
 *
 *   def fact(n) (1..n).inject(1) {|r,i| r*i } end
 *   0.upto(25) {|i| p [i, Math.gamma(i+1), fact(i)] }
 *   #=>
 *   [0, 1.0, 1]
 *   [1, 1.0, 1]
 *   [2, 2.0, 2]
 *   [3, 6.0, 6]
 *   [4, 24.0, 24]
 *   [5, 120.0, 120]
 *   [6, 720.0, 720]
 *   [7, 5040.0, 5040]
 *   [8, 40320.0, 40320]
 *   [9, 362880.0, 362880]
 *   [10, 3628800.0, 3628800]
 *   [11, 39916800.0, 39916800]
 *   [12, 479001600.0, 479001600]
 *   [13, 6227020800.0, 6227020800]
 *   [14, 87178291200.0, 87178291200]
 *   [15, 1307674368000.0, 1307674368000]
 *   [16, 20922789888000.0, 20922789888000]
 *   [17, 355687428096000.0, 355687428096000]
 *   [18, 6.402373705728e+15, 6402373705728000]
 *   [19, 1.21645100408832e+17, 121645100408832000]
 *   [20, 2.43290200817664e+18, 2432902008176640000]
 *   [21, 5.109094217170944e+19, 51090942171709440000]
 *   [22, 1.1240007277776077e+21, 1124000727777607680000]
 *   [23, 2.5852016738885062e+22, 25852016738884976640000]
 *   [24, 6.204484017332391e+23, 620448401733239439360000]
 *   [25, 1.5511210043330954e+25, 15511210043330985984000000]
 *
 */

static VALUE
math_gamma(VALUE obj, VALUE x)
{
    static double fact_table[] = {
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
         * impossible to represent exactly in IEEE 754 double. */
    };
    double d0, d;
    double intpart, fracpart;
    Need_Float(x);
    d0 = RFLOAT_VALUE(x);
    fracpart = modf(d0, &intpart);
    if (fracpart == 0.0 &&
            0 < intpart &&
            (size_t)intpart <= sizeof(fact_table)/sizeof(*fact_table)) {
        return DBL2NUM(fact_table[(int)intpart - 1]);
    }
    errno = 0;
    d = tgamma(d0);
    domain_check(d0, d, "gamma");
    return DBL2NUM(d);
}

/*
 * call-seq:
 *    Math.lgamma(x)  => [float, -1 or 1]
 *
 *  Calculates the logarithmic gamma of x and
 *  the sign of gamma of x.
 *
 *  Math.lgamma(x) is same as
 *   [Math.log(Math.gamma(x).abs), Math.gamma(x) < 0 ? -1 : 1]
 *  but avoid overflow by Math.gamma(x) for large x.
 */

static VALUE
math_lgamma(VALUE obj, VALUE x)
{
    double d0, d;
    int sign;
    VALUE v;
    Need_Float(x);
    errno = 0;
    d0 = RFLOAT_VALUE(x);
    d = lgamma_r(d0, &sign);
    domain_check(d0, d, "lgamma");
    v = DBL2NUM(d);
    return rb_assoc_new(v, INT2FIX(sign));
}


#define exp1(n) \
VALUE \
rb_math_##n(VALUE x)\
{\
    return math_##n(rb_mMath, x);\
}

#define exp2(n) \
VALUE \
rb_math_##n(VALUE x, VALUE y)\
{\
    return math_##n(rb_mMath, x, y);\
}

exp2(atan2)
exp1(cos)
exp1(cosh)
exp1(exp)
exp2(hypot)

VALUE
rb_math_log(int argc, VALUE *argv)
{
    return math_log(argc, argv);
}

exp1(sin)
exp1(sinh)
exp1(sqrt)


/*
 *  The <code>Math</code> module contains module functions for basic
 *  trigonometric and transcendental functions. See class
 *  <code>Float</code> for a list of constants that
 *  define Ruby's floating point accuracy.
 */


void
Init_Math(void)
{
    rb_mMath = rb_define_module("Math");

#ifdef M_PI
    rb_define_const(rb_mMath, "PI", DBL2NUM(M_PI));
#else
    rb_define_const(rb_mMath, "PI", DBL2NUM(atan(1.0)*4.0));
#endif

#ifdef M_E
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
