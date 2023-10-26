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
 *     Math.atan2(y, x) -> float
 *
 *  Returns the {arc tangent}[https://en.wikipedia.org/wiki/Atan2] of +y+ and +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain of +y+: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Domain of +x+: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-PI, PI]</tt>.
 *
 *  Examples:
 *
 *    atan2(-1.0, -1.0) # => -2.356194490192345  # -3*PI/4
 *    atan2(-1.0, 0.0)  # => -1.5707963267948966 # -PI/2
 *    atan2(-1.0, 1.0)  # => -0.7853981633974483 # -PI/4
 *    atan2(0.0, -1.0)  # => 3.141592653589793   # PI
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
 *    Math.cos(x) -> float
 *
 *  Returns the
 *  {cosine}[https://en.wikipedia.org/wiki/Sine_and_cosine] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>(-INFINITY, INFINITY)</tt>.
 *  - Range: <tt>[-1.0, 1.0]</tt>.
 *
 *  Examples:
 *
 *    cos(-PI)   # => -1.0
 *    cos(-PI/2) # => 6.123031769111886e-17 # 0.0000000000000001
 *    cos(0.0)   # => 1.0
 *    cos(PI/2)  # => 6.123031769111886e-17 # 0.0000000000000001
 *    cos(PI)    # => -1.0
 *
 */

static VALUE
math_cos(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(cos(Get_Double(x)));
}

/*
 *  call-seq:
 *    Math.sin(x) -> float
 *
 *  Returns the
 *  {sine}[https://en.wikipedia.org/wiki/Sine_and_cosine] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>(-INFINITY, INFINITY)</tt>.
 *  - Range: <tt>[-1.0, 1.0]</tt>.
 *
 *  Examples:
 *
 *    sin(-PI)   # => -1.2246063538223773e-16 # -0.0000000000000001
 *    sin(-PI/2) # => -1.0
 *    sin(0.0)   # => 0.0
 *    sin(PI/2)  # => 1.0
 *    sin(PI)    # => 1.2246063538223773e-16  # 0.0000000000000001
 *
 */

static VALUE
math_sin(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(sin(Get_Double(x)));
}


/*
 *  call-seq:
 *    Math.tan(x) -> float
 *
 *  Returns the
 *  {tangent}[https://en.wikipedia.org/wiki/Trigonometric_functions] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>(-INFINITY, INFINITY)</tt>.
 *  - Range: <tt>(-INFINITY, INFINITY)</tt>.
 *
 *  Examples:
 *
 *    tan(-PI)   # => 1.2246467991473532e-16  # -0.0000000000000001
 *    tan(-PI/2) # => -1.633123935319537e+16  # -16331239353195370.0
 *    tan(0.0)   # => 0.0
 *    tan(PI/2)  # => 1.633123935319537e+16   # 16331239353195370.0
 *    tan(PI)    # => -1.2246467991473532e-16 # -0.0000000000000001
 *
 */

static VALUE
math_tan(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(tan(Get_Double(x)));
}

#define math_arc(num, func) \
    double d; \
    d = Get_Double((num)); \
    domain_check_range(d, -1.0, 1.0, #func); \
    return DBL2NUM(func(d));

/*
 *  call-seq:
 *     Math.acos(x) -> float
 *
 *  Returns the {arc cosine}[https://en.wikipedia.org/wiki/Inverse_trigonometric_functions] of +x+.
 *
 *  - Domain: <tt>[-1, 1]</tt>.
 *  - Range: <tt>[0, PI]</tt>.
 *
 *  Examples:
 *
 *    acos(-1.0) # => 3.141592653589793  # PI
 *    acos(0.0)  # => 1.5707963267948966 # PI/2
 *    acos(1.0)  # => 0.0
 *
 */

static VALUE
math_acos(VALUE unused_obj, VALUE x)
{
    math_arc(x, acos)
}

/*
 *  call-seq:
 *     Math.asin(x) -> float
 *
 *  Returns the {arc sine}[https://en.wikipedia.org/wiki/Inverse_trigonometric_functions] of +x+.
 *
 *  - Domain: <tt>[-1, -1]</tt>.
 *  - Range: <tt>[-PI/2, PI/2]</tt>.
 *
 *  Examples:
 *
 *    asin(-1.0) # => -1.5707963267948966 # -PI/2
 *    asin(0.0)  # => 0.0
 *    asin(1.0)  # => 1.5707963267948966  # PI/2
 *
 */

static VALUE
math_asin(VALUE unused_obj, VALUE x)
{
    math_arc(x, asin)
}

/*
 *  call-seq:
 *     Math.atan(x)    -> Float
 *
 *  Returns the {arc tangent}[https://en.wikipedia.org/wiki/Inverse_trigonometric_functions] of +x+.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-PI/2, PI/2]  </tt>.
 *
 *  Examples:
 *
 *    atan(-INFINITY) # => -1.5707963267948966 # -PI2
 *    atan(-PI)       # => -1.2626272556789115
 *    atan(-PI/2)     # => -1.0038848218538872
 *    atan(0.0)       # => 0.0
 *    atan(PI/2)      # => 1.0038848218538872
 *    atan(PI)        # => 1.2626272556789115
 *    atan(INFINITY)  # => 1.5707963267948966  # PI/2
 *
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
 *    Math.cosh(x) -> float
 *
 *  Returns the {hyperbolic cosine}[https://en.wikipedia.org/wiki/Hyperbolic_functions] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[1, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    cosh(-INFINITY) # => Infinity
 *    cosh(0.0)       # => 1.0
 *    cosh(INFINITY)  # => Infinity
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
 *    Math.sinh(x) -> float
 *
 *  Returns the {hyperbolic sine}[https://en.wikipedia.org/wiki/Hyperbolic_functions] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    sinh(-INFINITY) # => -Infinity
 *    sinh(0.0)       # => 0.0
 *    sinh(INFINITY)  # => Infinity
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
 *    Math.tanh(x) -> float
 *
 *  Returns the {hyperbolic tangent}[https://en.wikipedia.org/wiki/Hyperbolic_functions] of +x+
 *  in {radians}[https://en.wikipedia.org/wiki/Trigonometric_functions#Radians_versus_degrees].
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-1, 1]</tt>.
 *
 *  Examples:
 *
 *    tanh(-INFINITY) # => -1.0
 *    tanh(0.0)       # => 0.0
 *    tanh(INFINITY)  # => 1.0
 *
 */

static VALUE
math_tanh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(tanh(Get_Double(x)));
}

/*
 *  call-seq:
 *    Math.acosh(x) -> float
 *
 *  Returns the {inverse hyperbolic cosine}[https://en.wikipedia.org/wiki/Inverse_hyperbolic_functions] of +x+.
 *
 *  - Domain: <tt>[1, INFINITY]</tt>.
 *  - Range: <tt>[0, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    acosh(1.0)      # => 0.0
 *    acosh(INFINITY) # => Infinity
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
 *    Math.asinh(x) -> float
 *
 *  Returns the {inverse hyperbolic sine}[https://en.wikipedia.org/wiki/Inverse_hyperbolic_functions] of +x+.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    asinh(-INFINITY) # => -Infinity
 *    asinh(0.0)       # => 0.0
 *    asinh(INFINITY)  # => Infinity
 *
 */

static VALUE
math_asinh(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(asinh(Get_Double(x)));
}

/*
 *  call-seq:
 *    Math.atanh(x) -> float
 *
 *  Returns the {inverse hyperbolic tangent}[https://en.wikipedia.org/wiki/Inverse_hyperbolic_functions] of +x+.
 *
 *  - Domain: <tt>[-1, 1]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    atanh(-1.0) # => -Infinity
 *    atanh(0.0)  # => 0.0
 *    atanh(1.0)  # => Infinity
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
 *    Math.exp(x) -> float
 *
 *  Returns +e+ raised to the +x+ power.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[0, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    exp(-INFINITY) # => 0.0
 *    exp(-1.0)      # => 0.36787944117144233 # 1.0/E
 *    exp(0.0)       # => 1.0
 *    exp(0.5)       # => 1.6487212707001282  # sqrt(E)
 *    exp(1.0)       # => 2.718281828459045   # E
 *    exp(2.0)       # => 7.38905609893065    # E**2
 *    exp(INFINITY)  # => Infinity
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

FUNC_MINIMIZED(static VALUE math_log(int, const VALUE *, VALUE));

/*
 *  call-seq:
 *    Math.log(x, base = Math::E) -> Float
 *
 *  Returns the base +base+ {logarithm}[https://en.wikipedia.org/wiki/Logarithm] of +x+.
 *
 *  - Domain: <tt>[0, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY)]</tt>.
 *
 *  Examples:
 *
 *    log(0.0)        # => -Infinity
 *    log(1.0)        # => 0.0
 *    log(E)          # => 1.0
 *    log(INFINITY)   # => Infinity
 *
 *    log(0.0, 2.0)   # => -Infinity
 *    log(1.0, 2.0)   # => 0.0
 *    log(2.0, 2.0)   # => 1.0
 *
 *    log(0.0, 10.0)  # => -Infinity
 *    log(1.0, 10.0)  # => 0.0
 *    log(10.0, 10.0) # => 1.0
 *
 */

static VALUE
math_log(int argc, const VALUE *argv, VALUE unused_obj)
{
    return rb_math_log(argc, argv);
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
math_log_split(VALUE x, size_t *numbits)
{
    double d = get_double_rshift(x, numbits);

    domain_check_min(d, 0.0, "log");
    return d;
}

#if defined(log2) || defined(HAVE_LOG2)
# define log_intermediate log2
#else
# define log_intermediate log10
double log2(double x);
#endif

VALUE
rb_math_log(int argc, const VALUE *argv)
{
    VALUE x, base;
    double d;
    size_t numbits;

    argc = rb_scan_args(argc, argv, "11", &x, &base);
    d = math_log_split(x, &numbits);
    if (argc == 2) {
        size_t numbits_2;
        double b = math_log_split(base, &numbits_2);
        /* check for pole error */
        if (d == 0.0) {
            // Already DomainError if b < 0.0
            return b ? DBL2NUM(-HUGE_VAL) : DBL2NUM(NAN);
        }
        else if (b == 0.0) {
            return DBL2NUM(-0.0);
        }
        d = log_intermediate(d) / log_intermediate(b);
        d += (numbits - numbits_2) / log2(b);
    }
    else {
        /* check for pole error */
        if (d == 0.0) return DBL2NUM(-HUGE_VAL);
        d = log(d);
        d += numbits * M_LN2;
    }
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
 *    Math.log2(x) -> float
 *
 *  Returns the base 2 {logarithm}[https://en.wikipedia.org/wiki/Logarithm] of +x+.
 *
 *  - Domain: <tt>[0, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    log2(0.0)      # => -Infinity
 *    log2(1.0)      # => 0.0
 *    log2(2.0)      # => 1.0
 *    log2(INFINITY) # => Infinity
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
 *    Math.log10(x) -> float
 *
 *  Returns the base 10 {logarithm}[https://en.wikipedia.org/wiki/Logarithm] of +x+.
 *
 *  - Domain: <tt>[0, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    log10(0.0)      # => -Infinity
 *    log10(1.0)      # => 0.0
 *    log10(10.0)     # => 1.0
 *    log10(INFINITY) # => Infinity
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
 *    Math.sqrt(x) -> float
 *
 *  Returns the principal (non-negative) {square root}[https://en.wikipedia.org/wiki/Square_root] of +x+.
 *
 *  - Domain: <tt>[0, INFINITY]</tt>.
 *  - Range: <tt>[0, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    sqrt(0.0)      # => 0.0
 *    sqrt(0.5)      # => 0.7071067811865476
 *    sqrt(1.0)      # => 1.0
 *    sqrt(2.0)      # => 1.4142135623730951
 *    sqrt(4.0)      # => 2.0
 *    sqrt(9.0)      # => 3.0
 *    sqrt(INFINITY) # => Infinity
 *
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
 *    Math.cbrt(x) -> float
 *
 *  Returns the {cube root}[https://en.wikipedia.org/wiki/Cube_root] of +x+.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    cbrt(-INFINITY) # => -Infinity
 *    cbrt(-27.0)     # => -3.0
 *    cbrt(-8.0)      # => -2.0
 *    cbrt(-2.0)      # => -1.2599210498948732
 *    cbrt(1.0)       # => 1.0
 *    cbrt(0.0)       # => 0.0
 *    cbrt(1.0)       # => 1.0
 *    cbrt(2.0)       # => 1.2599210498948732
 *    cbrt(8.0)       # => 2.0
 *    cbrt(27.0)      # => 3.0
 *    cbrt(INFINITY)  # => Infinity
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
 *    Math.frexp(x) -> [fraction, exponent]
 *
 *  Returns a 2-element array containing the normalized signed float +fraction+
 *  and integer +exponent+ of +x+ such that:
 *
 *    x = fraction * 2**exponent
 *
 *  See {IEEE 754 double-precision binary floating-point format: binary64}[https://en.wikipedia.org/wiki/Double-precision_floating-point_format#IEEE_754_double-precision_binary_floating-point_format:_binary64].
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    frexp(-INFINITY) # => [-Infinity, -1]
 *    frexp(-2.0)      # => [-0.5, 2]
 *    frexp(-1.0)      # => [-0.5, 1]
 *    frexp(0.0)       # => [0.0, 0]
 *    frexp(1.0)       # => [0.5, 1]
 *    frexp(2.0)       # => [0.5, 2]
 *    frexp(INFINITY)  # => [Infinity, -1]
 *
 *  Related: Math.ldexp (inverse of Math.frexp).
 *
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
 *    Math.ldexp(fraction, exponent) -> float
 *
 *  Returns the value of <tt>fraction * 2**exponent</tt>.
 *
 *  - Domain of +fraction+: <tt>[0.0, 1.0)</tt>.
 *  - Domain of +exponent+: <tt>[0, 1024]</tt>
 *    (larger values are equivalent to 1024).
 *
 *  See {IEEE 754 double-precision binary floating-point format: binary64}[https://en.wikipedia.org/wiki/Double-precision_floating-point_format#IEEE_754_double-precision_binary_floating-point_format:_binary64].
 *
 *  Examples:
 *
 *    ldexp(-INFINITY, -1) # => -Infinity
 *    ldexp(-0.5, 2)       # => -2.0
 *    ldexp(-0.5, 1)       # => -1.0
 *    ldexp(0.0, 0)        # => 0.0
 *    ldexp(-0.5, 1)       # => 1.0
 *    ldexp(-0.5, 2)       # => 2.0
 *    ldexp(INFINITY, -1)  # => Infinity
 *
 *  Related: Math.frexp (inverse of Math.ldexp).
 *
 */

static VALUE
math_ldexp(VALUE unused_obj, VALUE x, VALUE n)
{
    return DBL2NUM(ldexp(Get_Double(x), NUM2INT(n)));
}

/*
 *  call-seq:
 *    Math.hypot(a, b) -> float
 *
 *  Returns <tt>sqrt(a**2 + b**2)</tt>,
 *  which is the length of the longest side +c+ (the hypotenuse)
 *  of the right triangle whose other sides have lengths +a+ and +b+.
 *
 *  - Domain of +a+: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Domain of +ab: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[0, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    hypot(0.0, 1.0)       # => 1.0
 *    hypot(1.0, 1.0)       # => 1.4142135623730951 # sqrt(2.0)
 *    hypot(3.0, 4.0)       # => 5.0
 *    hypot(5.0, 12.0)      # => 13.0
 *    hypot(1.0, sqrt(3.0)) # => 1.9999999999999998 # Near 2.0
 *
 *  Note that if either argument is +INFINITY+ or <tt>-INFINITY</tt>,
 *  the result is +Infinity+.
 *
 */

static VALUE
math_hypot(VALUE unused_obj, VALUE x, VALUE y)
{
    return DBL2NUM(hypot(Get_Double(x), Get_Double(y)));
}

/*
 * call-seq:
 *   Math.erf(x) -> float
 *
 *  Returns the value of the {Gauss error function}[https://en.wikipedia.org/wiki/Error_function] for +x+.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[-1, 1]</tt>.
 *
 *  Examples:
 *
 *    erf(-INFINITY) # => -1.0
 *    erf(0.0)       # => 0.0
 *    erf(INFINITY)  # => 1.0
 *
 *  Related: Math.erfc.
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
 *  Returns the value of the {complementary error function}[https://en.wikipedia.org/wiki/Error_function#Complementary_error_function] for +x+.
 *
 *  - Domain: <tt>[-INFINITY, INFINITY]</tt>.
 *  - Range: <tt>[0, 2]</tt>.
 *
 *  Examples:
 *
 *    erfc(-INFINITY) # => 2.0
 *    erfc(0.0)       # => 1.0
 *    erfc(INFINITY)  # => 0.0
 *
 *  Related: Math.erf.
 *
 */

static VALUE
math_erfc(VALUE unused_obj, VALUE x)
{
    return DBL2NUM(erfc(Get_Double(x)));
}

/*
 * call-seq:
 *   Math.gamma(x) -> float
 *
 *  Returns the value of the {gamma function}[https://en.wikipedia.org/wiki/Gamma_function] for +x+.
 *
 *  - Domain: <tt>(-INFINITY, INFINITY]</tt> excluding negative integers.
 *  - Range: <tt>[-INFINITY, INFINITY]</tt>.
 *
 *  Examples:
 *
 *    gamma(-2.5)      # => -0.9453087204829431
 *    gamma(-1.5)      # => 2.3632718012073513
 *    gamma(-0.5)      # => -3.5449077018110375
 *    gamma(0.0)      # => Infinity
 *    gamma(1.0)      # => 1.0
 *    gamma(2.0)      # => 1.0
 *    gamma(3.0)      # => 2.0
 *    gamma(4.0)      # => 6.0
 *    gamma(5.0)      # => 24.0
 *
 *  Related: Math.lgamma.
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
 *   Math.lgamma(x) -> [float, -1 or 1]
 *
 *  Returns a 2-element array equivalent to:
 *
 *    [Math.log(Math.gamma(x).abs), Math.gamma(x) < 0 ? -1 : 1]
 *
 *  See {logarithmic gamma function}[https://en.wikipedia.org/wiki/Gamma_function#The_log-gamma_function].
 *
 *  - Domain: <tt>(-INFINITY, INFINITY]</tt>.
 *  - Range of first element: <tt>(-INFINITY, INFINITY]</tt>.
 *  - Second element is -1 or 1.
 *
 *  Examples:
 *
 *    lgamma(-4.0) # => [Infinity, -1]
 *    lgamma(-3.0) # => [Infinity, -1]
 *    lgamma(-2.0) # => [Infinity, -1]
 *    lgamma(-1.0) # => [Infinity, -1]
 *    lgamma(0.0)  # => [Infinity, 1]
 *
 *    lgamma(1.0)  # => [0.0, 1]
 *    lgamma(2.0)  # => [0.0, 1]
 *    lgamma(3.0)  # => [0.6931471805599436, 1]
 *    lgamma(4.0)  # => [1.7917594692280545, 1]
 *
 *    lgamma(-2.5) # => [-0.05624371649767279, -1]
 *    lgamma(-1.5) # => [0.8600470153764797, 1]
 *    lgamma(-0.5) # => [1.265512123484647, -1]
 *    lgamma(0.5)  # => [0.5723649429247004, 1]
 *    lgamma(1.5)  # => [-0.12078223763524676, 1]
 *    lgamma(2.5)      # => [0.2846828704729205, 1]
 *
 *  Related: Math.gamma.
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
 *  :include: doc/math/math.rdoc
 *
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
