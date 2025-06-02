/*
  complex.c: Coded by Tadayoshi Funaba 2008-2012

  This implementation is based on Keiju Ishitsuka's Complex library
  which is written in ruby.
*/

#include "ruby/internal/config.h"

#if defined _MSC_VER
/* Microsoft Visual C does not define M_PI and others by default */
# define _USE_MATH_DEFINES 1
#endif

#include <ctype.h>
#include <math.h>

#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/class.h"
#include "internal/complex.h"
#include "internal/math.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/rational.h"
#include "internal/string.h"
#include "ruby_assert.h"

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)
#if USE_FLONUM
#define RFLOAT_0 DBL2NUM(0)
#else
static VALUE RFLOAT_0;
#endif

VALUE rb_cComplex;

static ID id_abs, id_arg,
    id_denominator, id_numerator,
    id_real_p, id_i_real, id_i_imag,
    id_finite_p, id_infinite_p, id_rationalize,
    id_PI;
#define id_to_i idTo_i
#define id_to_r idTo_r
#define id_negate idUMinus
#define id_expt idPow
#define id_to_f idTo_f
#define id_quo idQuo
#define id_fdiv idFdiv

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

#define PRESERVE_SIGNEDZERO

inline static VALUE
f_add(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x) &&
        LIKELY(rb_method_basic_definition_p(rb_cInteger, idPLUS))) {
        if (FIXNUM_ZERO_P(x))
            return y;
        if (FIXNUM_ZERO_P(y))
            return x;
        return rb_int_plus(x, y);
    }
    else if (RB_FLOAT_TYPE_P(x) &&
             LIKELY(rb_method_basic_definition_p(rb_cFloat, idPLUS))) {
        if (FIXNUM_ZERO_P(y))
            return x;
        return rb_float_plus(x, y);
    }
    else if (RB_TYPE_P(x, T_RATIONAL) &&
             LIKELY(rb_method_basic_definition_p(rb_cRational, idPLUS))) {
        if (FIXNUM_ZERO_P(y))
            return x;
        return rb_rational_plus(x, y);
    }

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
    if (RB_INTEGER_TYPE_P(x) &&
        LIKELY(rb_method_basic_definition_p(rb_cInteger, idMULT))) {
        if (FIXNUM_ZERO_P(y))
            return ZERO;
        if (FIXNUM_ZERO_P(x) && RB_INTEGER_TYPE_P(y))
            return ZERO;
        if (x == ONE) return y;
        if (y == ONE) return x;
        return rb_int_mul(x, y);
    }
    else if (RB_FLOAT_TYPE_P(x) &&
             LIKELY(rb_method_basic_definition_p(rb_cFloat, idMULT))) {
        if (y == ONE) return x;
        return rb_float_mul(x, y);
    }
    else if (RB_TYPE_P(x, T_RATIONAL) &&
             LIKELY(rb_method_basic_definition_p(rb_cRational, idMULT))) {
        if (y == ONE) return x;
        return rb_rational_mul(x, y);
    }
    else if (LIKELY(rb_method_basic_definition_p(CLASS_OF(x), idMULT))) {
        if (y == ONE) return x;
    }
    return rb_funcall(x, '*', 1, y);
}

inline static VALUE
f_sub(VALUE x, VALUE y)
{
    if (FIXNUM_ZERO_P(y) &&
        LIKELY(rb_method_basic_definition_p(CLASS_OF(x), idMINUS))) {
        return x;
    }
    return rb_funcall(x, '-', 1, y);
}

inline static VALUE
f_abs(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return rb_int_abs(x);
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return rb_float_abs(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        return rb_rational_abs(x);
    }
    else if (RB_TYPE_P(x, T_COMPLEX)) {
        return rb_complex_abs(x);
    }
    return rb_funcall(x, id_abs, 0);
}

static VALUE numeric_arg(VALUE self);
static VALUE float_arg(VALUE self);

inline static VALUE
f_arg(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return numeric_arg(x);
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return float_arg(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        return numeric_arg(x);
    }
    else if (RB_TYPE_P(x, T_COMPLEX)) {
        return rb_complex_arg(x);
    }
    return rb_funcall(x, id_arg, 0);
}

inline static VALUE
f_numerator(VALUE x)
{
    if (RB_TYPE_P(x, T_RATIONAL)) {
        return RRATIONAL(x)->num;
    }
    if (RB_FLOAT_TYPE_P(x)) {
        return rb_float_numerator(x);
    }
    return x;
}

inline static VALUE
f_denominator(VALUE x)
{
    if (RB_TYPE_P(x, T_RATIONAL)) {
        return RRATIONAL(x)->den;
    }
    if (RB_FLOAT_TYPE_P(x)) {
        return rb_float_denominator(x);
    }
    return INT2FIX(1);
}

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
        return rb_complex_uminus(x);
    }
    return rb_funcall(x, id_negate, 0);
}

static bool nucomp_real_p(VALUE self);

static inline bool
f_real_p(VALUE x)
{
    if (RB_INTEGER_TYPE_P(x)) {
        return true;
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return true;
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        return true;
    }
    else if (RB_TYPE_P(x, T_COMPLEX)) {
        return nucomp_real_p(x);
    }
    return rb_funcall(x, id_real_p, 0);
}

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

static VALUE
f_quo(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(x))
        return rb_numeric_quo(x, y);
    if (RB_FLOAT_TYPE_P(x))
        return rb_float_div(x, y);
    if (RB_TYPE_P(x, T_RATIONAL))
        return rb_numeric_quo(x, y);

    return rb_funcallv(x, id_quo, 1, &y);
}

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

inline static bool
f_zero_p(VALUE x)
{
    if (RB_FLOAT_TYPE_P(x)) {
        return FLOAT_ZERO_P(x);
    }
    else if (RB_INTEGER_TYPE_P(x)) {
        return FIXNUM_ZERO_P(x);
    }
    else if (RB_TYPE_P(x, T_RATIONAL)) {
        const VALUE num = RRATIONAL(x)->num;
        return FIXNUM_ZERO_P(num);
    }
    return rb_equal(x, ZERO) != 0;
}

#define f_nonzero_p(x) (!f_zero_p(x))

static inline bool
always_finite_type_p(VALUE x)
{
    if (FIXNUM_P(x)) return true;
    if (FLONUM_P(x)) return true; /* Infinity can't be a flonum */
    return (RB_INTEGER_TYPE_P(x) || RB_TYPE_P(x, T_RATIONAL));
}

inline static int
f_finite_p(VALUE x)
{
    if (always_finite_type_p(x)) {
        return TRUE;
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return isfinite(RFLOAT_VALUE(x));
    }
    return RTEST(rb_funcallv(x, id_finite_p, 0, 0));
}

inline static int
f_infinite_p(VALUE x)
{
    if (always_finite_type_p(x)) {
        return FALSE;
    }
    else if (RB_FLOAT_TYPE_P(x)) {
        return isinf(RFLOAT_VALUE(x));
    }
    return RTEST(rb_funcallv(x, id_infinite_p, 0, 0));
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

#define k_exact_p(x) (!RB_FLOAT_TYPE_P(x))

#define k_exact_zero_p(x) (k_exact_p(x) && f_zero_p(x))

#define get_dat1(x) \
    struct RComplex *dat = RCOMPLEX(x)

#define get_dat2(x,y) \
    struct RComplex *adat = RCOMPLEX(x), *bdat = RCOMPLEX(y)

inline static VALUE
nucomp_s_new_internal(VALUE klass, VALUE real, VALUE imag)
{
    NEWOBJ_OF(obj, struct RComplex, klass,
            T_COMPLEX | (RGENGC_WB_PROTECTED_COMPLEX ? FL_WB_PROTECTED : 0), sizeof(struct RComplex), 0);

    RCOMPLEX_SET_REAL(obj, real);
    RCOMPLEX_SET_IMAG(obj, imag);
    OBJ_FREEZE((VALUE)obj);

    return (VALUE)obj;
}

static VALUE
nucomp_s_alloc(VALUE klass)
{
    return nucomp_s_new_internal(klass, ZERO, ZERO);
}

inline static VALUE
f_complex_new_bang1(VALUE klass, VALUE x)
{
    RUBY_ASSERT(!RB_TYPE_P(x, T_COMPLEX));
    return nucomp_s_new_internal(klass, x, ZERO);
}

inline static VALUE
f_complex_new_bang2(VALUE klass, VALUE x, VALUE y)
{
    RUBY_ASSERT(!RB_TYPE_P(x, T_COMPLEX));
    RUBY_ASSERT(!RB_TYPE_P(y, T_COMPLEX));
    return nucomp_s_new_internal(klass, x, y);
}

WARN_UNUSED_RESULT(inline static VALUE nucomp_real_check(VALUE num));
inline static VALUE
nucomp_real_check(VALUE num)
{
    if (!RB_INTEGER_TYPE_P(num) &&
        !RB_FLOAT_TYPE_P(num) &&
        !RB_TYPE_P(num, T_RATIONAL)) {
        if (RB_TYPE_P(num, T_COMPLEX) && nucomp_real_p(num)) {
            VALUE real = RCOMPLEX(num)->real;
            RUBY_ASSERT(!RB_TYPE_P(real, T_COMPLEX));
            return real;
        }
        if (!k_numeric_p(num) || !f_real_p(num))
            rb_raise(rb_eTypeError, "not a real");
    }
    return num;
}

inline static VALUE
nucomp_s_canonicalize_internal(VALUE klass, VALUE real, VALUE imag)
{
    int complex_r, complex_i;
    complex_r = RB_TYPE_P(real, T_COMPLEX);
    complex_i = RB_TYPE_P(imag, T_COMPLEX);
    if (!complex_r && !complex_i) {
        return nucomp_s_new_internal(klass, real, imag);
    }
    else if (!complex_r) {
        get_dat1(imag);

        return nucomp_s_new_internal(klass,
                                     f_sub(real, dat->imag),
                                     f_add(ZERO, dat->real));
    }
    else if (!complex_i) {
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
 *   Complex.rect(real, imag = 0) -> complex
 *
 * Returns a new \Complex object formed from the arguments,
 * each of which must be an instance of Numeric,
 * or an instance of one of its subclasses:
 * \Complex, Float, Integer, Rational;
 * see {Rectangular Coordinates}[rdoc-ref:Complex@Rectangular+Coordinates]:
 *
 *   Complex.rect(3)             # => (3+0i)
 *   Complex.rect(3, Math::PI)   # => (3+3.141592653589793i)
 *   Complex.rect(-3, -Math::PI) # => (-3-3.141592653589793i)
 *
 * \Complex.rectangular is an alias for \Complex.rect.
 */
static VALUE
nucomp_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, imag;

    switch (rb_scan_args(argc, argv, "11", &real, &imag)) {
      case 1:
        real = nucomp_real_check(real);
        imag = ZERO;
        break;
      default:
        real = nucomp_real_check(real);
        imag = nucomp_real_check(imag);
        break;
    }

    return nucomp_s_new_internal(klass, real, imag);
}

inline static VALUE
f_complex_new2(VALUE klass, VALUE x, VALUE y)
{
    if (RB_TYPE_P(x, T_COMPLEX)) {
        get_dat1(x);
        x = dat->real;
        y = f_add(dat->imag, y);
    }
    return nucomp_s_canonicalize_internal(klass, x, y);
}

static VALUE nucomp_convert(VALUE klass, VALUE a1, VALUE a2, int raise);
static VALUE nucomp_s_convert(int argc, VALUE *argv, VALUE klass);

/*
 * call-seq:
 *   Complex(real, imag = 0, exception: true) -> complex or nil
 *   Complex(s, exception: true) -> complex or nil
 *
 * Returns a new \Complex object if the arguments are valid;
 * otherwise raises an exception if +exception+ is +true+;
 * otherwise returns +nil+.
 *
 * With Numeric arguments +real+ and +imag+,
 * returns <tt>Complex.rect(real, imag)</tt> if the arguments are valid.
 *
 * With string argument +s+, returns a new \Complex object if the argument is valid;
 * the string may have:
 *
 * - One or two numeric substrings,
 *   each of which specifies a Complex, Float, Integer, Numeric, or Rational value,
 *   specifying {rectangular coordinates}[rdoc-ref:Complex@Rectangular+Coordinates]:
 *
 *   - Sign-separated real and imaginary numeric substrings
 *     (with trailing character <tt>'i'</tt>):
 *
 *       Complex('1+2i')  # => (1+2i)
 *       Complex('+1+2i') # => (1+2i)
 *       Complex('+1-2i') # => (1-2i)
 *       Complex('-1+2i') # => (-1+2i)
 *       Complex('-1-2i') # => (-1-2i)
 *
 *   - Real-only numeric string (without trailing character <tt>'i'</tt>):
 *
 *       Complex('1')  # => (1+0i)
 *       Complex('+1') # => (1+0i)
 *       Complex('-1') # => (-1+0i)
 *
 *   - Imaginary-only numeric string (with trailing character <tt>'i'</tt>):
 *
 *       Complex('1i')  # => (0+1i)
 *       Complex('+1i') # => (0+1i)
 *       Complex('-1i') # => (0-1i)
 *
 * - At-sign separated real and imaginary rational substrings,
 *   each of which specifies a Rational value,
 *   specifying {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates]:
 *
 *     Complex('1/2@3/4')   # => (0.36584443443691045+0.34081938001166706i)
 *     Complex('+1/2@+3/4') # => (0.36584443443691045+0.34081938001166706i)
 *     Complex('+1/2@-3/4') # => (0.36584443443691045-0.34081938001166706i)
 *     Complex('-1/2@+3/4') # => (-0.36584443443691045-0.34081938001166706i)
 *     Complex('-1/2@-3/4') # => (-0.36584443443691045+0.34081938001166706i)
 *
 */
static VALUE
nucomp_f_complex(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, opts = Qnil;
    int raise = TRUE;

    if (rb_scan_args(argc, argv, "11:", &a1, &a2, &opts) == 1) {
        a2 = Qundef;
    }
    if (!NIL_P(opts)) {
        raise = rb_opts_exception_p(opts, raise);
    }
    if (argc > 0 && CLASS_OF(a1) == rb_cComplex && UNDEF_P(a2)) {
        return a1;
    }
    return nucomp_convert(rb_cComplex, a1, a2, raise);
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
    if (!RB_TYPE_P(x, T_COMPLEX))
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
    if (!RB_TYPE_P(x, T_COMPLEX))
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

static VALUE
f_complex_polar_real(VALUE klass, VALUE x, VALUE y)
{
    if (f_zero_p(x) || f_zero_p(y)) {
        return nucomp_s_new_internal(klass, x, RFLOAT_0);
    }
    if (RB_FLOAT_TYPE_P(y)) {
        const double arg = RFLOAT_VALUE(y);
        if (arg == M_PI) {
            x = f_negate(x);
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
            y = DBL2NUM(imag);
        }
        else {
            const double ax = sin(arg), ay = cos(arg);
            y = f_mul(x, DBL2NUM(ax));
            x = f_mul(x, DBL2NUM(ay));
        }
        return nucomp_s_new_internal(klass, x, y);
    }
    return nucomp_s_canonicalize_internal(klass,
                                          f_mul(x, m_cos(y)),
                                          f_mul(x, m_sin(y)));
}

static VALUE
f_complex_polar(VALUE klass, VALUE x, VALUE y)
{
    x = nucomp_real_check(x);
    y = nucomp_real_check(y);
    return f_complex_polar_real(klass, x, y);
}

#ifdef HAVE___COSPI
# define cospi(x) __cospi(x)
#else
# define cospi(x) cos((x) * M_PI)
#endif
#ifdef HAVE___SINPI
# define sinpi(x) __sinpi(x)
#else
# define sinpi(x) sin((x) * M_PI)
#endif
/* returns a Complex or Float of ang*PI-rotated abs */
VALUE
rb_dbl_complex_new_polar_pi(double abs, double ang)
{
    double fi;
    const double fr = modf(ang, &fi);
    int pos = fr == +0.5;

    if (pos || fr == -0.5) {
        if ((modf(fi / 2.0, &fi) != fr) ^ pos) abs = -abs;
        return rb_complex_new(RFLOAT_0, DBL2NUM(abs));
    }
    else if (fr == 0.0) {
        if (modf(fi / 2.0, &fi) != 0.0) abs = -abs;
        return DBL2NUM(abs);
    }
    else {
        const double real = abs * cospi(ang), imag = abs * sinpi(ang);
        return rb_complex_new(DBL2NUM(real), DBL2NUM(imag));
    }
}

/*
 * call-seq:
 *   Complex.polar(abs, arg = 0) -> complex
 *
 * Returns a new \Complex object formed from the arguments,
 * each of which must be an instance of Numeric,
 * or an instance of one of its subclasses:
 * \Complex, Float, Integer, Rational.
 * Argument +arg+ is given in radians;
 * see {Polar Coordinates}[rdoc-ref:Complex@Polar+Coordinates]:
 *
 *   Complex.polar(3)        # => (3+0i)
 *   Complex.polar(3, 2.0)   # => (-1.2484405096414273+2.727892280477045i)
 *   Complex.polar(-3, -2.0) # => (1.2484405096414273+2.727892280477045i)
 *
 */
static VALUE
nucomp_s_polar(int argc, VALUE *argv, VALUE klass)
{
    VALUE abs, arg;

    argc = rb_scan_args(argc, argv, "11", &abs, &arg);
    abs = nucomp_real_check(abs);
    if (argc == 2) {
        arg = nucomp_real_check(arg);
    }
    else {
        arg = ZERO;
    }
    return f_complex_polar_real(klass, abs, arg);
}

/*
 * call-seq:
 *   real -> numeric
 *
 * Returns the real value for +self+:
 *
 *   Complex.rect(7).real     # => 7
 *   Complex.rect(9, -4).real # => 9
 *
 * If +self+ was created with
 * {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.polar(1, Math::PI/4).real # => 0.7071067811865476 # Square root of 2.
 *
 */
VALUE
rb_complex_real(VALUE self)
{
    get_dat1(self);
    return dat->real;
}

/*
 * call-seq:
 *   imag -> numeric
 *
 * Returns the imaginary value for +self+:
 *
 *   Complex.rect(7).imag     # => 0
 *   Complex.rect(9, -4).imag # => -4
 *
 * If +self+ was created with
 * {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.polar(1, Math::PI/4).imag # => 0.7071067811865476 # Square root of 2.
 *
 */
VALUE
rb_complex_imag(VALUE self)
{
    get_dat1(self);
    return dat->imag;
}

/*
 * call-seq:
 *   -complex -> new_complex
 *
 * Returns the negation of +self+, which is the negation of each of its parts:
 *
 *   -Complex.rect(1, 2)   # => (-1-2i)
 *   -Complex.rect(-1, -2) # => (1+2i)
 *
 */
VALUE
rb_complex_uminus(VALUE self)
{
    get_dat1(self);
    return f_complex_new2(CLASS_OF(self),
                          f_negate(dat->real), f_negate(dat->imag));
}

/*
 * call-seq:
 *   complex + numeric -> new_complex
 *
 * Returns the sum of +self+ and +numeric+:
 *
 *   Complex.rect(2, 3)  + Complex.rect(2, 3)  # => (4+6i)
 *   Complex.rect(900)   + Complex.rect(1)     # => (901+0i)
 *   Complex.rect(-2, 9) + Complex.rect(-9, 2) # => (-11+11i)
 *   Complex.rect(9, 8)  + 4                   # => (13+8i)
 *   Complex.rect(20, 9) + 9.8                 # => (29.8+9i)
 *
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
 *   complex - numeric -> new_complex
 *
 * Returns the difference of +self+ and +numeric+:
 *
 *   Complex.rect(2, 3)  - Complex.rect(2, 3)  # => (0+0i)
 *   Complex.rect(900)   - Complex.rect(1)     # => (899+0i)
 *   Complex.rect(-2, 9) - Complex.rect(-9, 2) # => (7+7i)
 *   Complex.rect(9, 8)  - 4                   # => (5+8i)
 *   Complex.rect(20, 9) - 9.8                 # => (10.2+9i)
 *
 */
VALUE
rb_complex_minus(VALUE self, VALUE other)
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
safe_mul(VALUE a, VALUE b, bool az, bool bz)
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

static void
comp_mul(VALUE areal, VALUE aimag, VALUE breal, VALUE bimag, VALUE *real, VALUE *imag)
{
    bool arzero = f_zero_p(areal);
    bool aizero = f_zero_p(aimag);
    bool brzero = f_zero_p(breal);
    bool bizero = f_zero_p(bimag);
    *real = f_sub(safe_mul(areal, breal, arzero, brzero),
                  safe_mul(aimag, bimag, aizero, bizero));
    *imag = f_add(safe_mul(areal, bimag, arzero, bizero),
                  safe_mul(aimag, breal, aizero, brzero));
}

/*
 * call-seq:
 *   complex * numeric -> new_complex
 *
 * Returns the product of +self+ and +numeric+:
 *
 *   Complex.rect(2, 3)  * Complex.rect(2, 3)  # => (-5+12i)
 *   Complex.rect(900)   * Complex.rect(1)     # => (900+0i)
 *   Complex.rect(-2, 9) * Complex.rect(-9, 2) # => (0-85i)
 *   Complex.rect(9, 8)  * 4                   # => (36+32i)
 *   Complex.rect(20, 9) * 9.8                 # => (196.0+88.2i)
 *
 */
VALUE
rb_complex_mul(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
        VALUE real, imag;
        get_dat2(self, other);

        comp_mul(adat->real, adat->imag, bdat->real, bdat->imag, &real, &imag);

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

inline static VALUE
f_divide(VALUE self, VALUE other,
         VALUE (*func)(VALUE, VALUE), ID id)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
        VALUE r, n, x, y;
        int flo;
        get_dat2(self, other);

        flo = (RB_FLOAT_TYPE_P(adat->real) || RB_FLOAT_TYPE_P(adat->imag) ||
               RB_FLOAT_TYPE_P(bdat->real) || RB_FLOAT_TYPE_P(bdat->imag));

        if (f_gt_p(f_abs(bdat->real), f_abs(bdat->imag))) {
            r = (*func)(bdat->imag, bdat->real);
            n = f_mul(bdat->real, f_add(ONE, f_mul(r, r)));
            x = (*func)(f_add(adat->real, f_mul(adat->imag, r)), n);
            y = (*func)(f_sub(adat->imag, f_mul(adat->real, r)), n);
        }
        else {
            r = (*func)(bdat->real, bdat->imag);
            n = f_mul(bdat->imag, f_add(ONE, f_mul(r, r)));
            x = (*func)(f_add(f_mul(adat->real, r), adat->imag), n);
            y = (*func)(f_sub(f_mul(adat->imag, r), adat->real), n);
        }
        if (!flo) {
            x = rb_rational_canonicalize(x);
            y = rb_rational_canonicalize(y);
        }
        return f_complex_new2(CLASS_OF(self), x, y);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
        VALUE x, y;
        get_dat1(self);
        x = rb_rational_canonicalize((*func)(dat->real, other));
        y = rb_rational_canonicalize((*func)(dat->imag, other));
        return f_complex_new2(CLASS_OF(self), x, y);
    }
    return rb_num_coerce_bin(self, other, id);
}

#define rb_raise_zerodiv() rb_raise(rb_eZeroDivError, "divided by 0")

/*
 * call-seq:
 *   complex / numeric -> new_complex
 *
 * Returns the quotient of +self+ and +numeric+:
 *
 *   Complex.rect(2, 3)  / Complex.rect(2, 3)  # => (1+0i)
 *   Complex.rect(900)   / Complex.rect(1)     # => (900+0i)
 *   Complex.rect(-2, 9) / Complex.rect(-9, 2) # => ((36/85)-(77/85)*i)
 *   Complex.rect(9, 8)  / 4                   # => ((9/4)+2i)
 *   Complex.rect(20, 9) / 9.8                 # => (2.0408163265306123+0.9183673469387754i)
 *
 */
VALUE
rb_complex_div(VALUE self, VALUE other)
{
    return f_divide(self, other, f_quo, id_quo);
}

#define nucomp_quo rb_complex_div

/*
 * call-seq:
 *   fdiv(numeric) -> new_complex
 *
 * Returns <tt>Complex.rect(self.real/numeric, self.imag/numeric)</tt>:
 *
 *   Complex.rect(11, 22).fdiv(3) # => (3.6666666666666665+7.333333333333333i)
 *
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

static VALUE
zero_for(VALUE x)
{
    if (RB_FLOAT_TYPE_P(x))
        return DBL2NUM(0);
    if (RB_TYPE_P(x, T_RATIONAL))
        return rb_rational_new(INT2FIX(0), INT2FIX(1));

    return INT2FIX(0);
}

static VALUE
complex_pow_for_special_angle(VALUE self, VALUE other)
{
    if (!rb_integer_type_p(other)) {
        return Qundef;
    }

    get_dat1(self);
    VALUE x = Qundef;
    int dir;
    if (f_zero_p(dat->imag)) {
        x = dat->real;
        dir = 0;
    }
    else if (f_zero_p(dat->real)) {
        x = dat->imag;
        dir = 2;
    }
    else if (f_eqeq_p(dat->real, dat->imag)) {
        x = dat->real;
        dir = 1;
    }
    else if (f_eqeq_p(dat->real, f_negate(dat->imag))) {
        x = dat->imag;
        dir = 3;
    }
    else {
        dir = 0;
    }

    if (UNDEF_P(x)) return x;

    if (f_negative_p(x)) {
        x = f_negate(x);
        dir += 4;
    }

    VALUE zx;
    if (dir % 2 == 0) {
        zx = rb_num_pow(x, other);
    }
    else {
        zx = rb_num_pow(
            rb_funcall(rb_int_mul(TWO, x), '*', 1, x),
            rb_int_div(other, TWO)
        );
        if (rb_int_odd_p(other)) {
            zx = rb_funcall(zx, '*', 1, x);
        }
    }
    static const int dirs[][2] = {
        {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}
    };
    int z_dir = FIX2INT(rb_int_modulo(rb_int_mul(INT2FIX(dir), other), INT2FIX(8)));

    VALUE zr = Qfalse, zi = Qfalse;
    switch (dirs[z_dir][0]) {
      case 0: zr = zero_for(zx); break;
      case 1: zr = zx; break;
      case -1: zr = f_negate(zx); break;
    }
    switch (dirs[z_dir][1]) {
      case 0: zi = zero_for(zx); break;
      case 1: zi = zx; break;
      case -1: zi = f_negate(zx); break;
    }
    return nucomp_s_new_internal(CLASS_OF(self), zr, zi);
}


/*
 * call-seq:
 *   complex ** numeric -> new_complex
 *
 * Returns +self+ raised to power +numeric+:
 *
 *   Complex.rect(0, 1) ** 2            # => (-1+0i)
 *   Complex.rect(-8) ** Rational(1, 3) # => (1.0000000000000002+1.7320508075688772i)
 *
 */
VALUE
rb_complex_pow(VALUE self, VALUE other)
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

    if (other == ONE) {
        get_dat1(self);
        return nucomp_s_new_internal(CLASS_OF(self), dat->real, dat->imag);
    }

    VALUE result = complex_pow_for_special_angle(self, other);
    if (!UNDEF_P(result)) return result;

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
        long n = FIX2LONG(other);
        if (n == 0) {
            return nucomp_s_new_internal(CLASS_OF(self), ONE, ZERO);
        }
        if (n < 0) {
            self = f_reciprocal(self);
            other = rb_int_uminus(other);
            n = -n;
        }
        {
            get_dat1(self);
            VALUE xr = dat->real, xi = dat->imag, zr = xr, zi = xi;

            if (f_zero_p(xi)) {
                zr = rb_num_pow(zr, other);
            }
            else if (f_zero_p(xr)) {
                zi = rb_num_pow(zi, other);
                if (n & 2) zi = f_negate(zi);
                if (!(n & 1)) {
                    VALUE tmp = zr;
                    zr = zi;
                    zi = tmp;
                }
            }
            else {
                while (--n) {
                    long q, r;

                    for (; q = n / 2, r = n % 2, r == 0; n = q) {
                        VALUE tmp = f_sub(f_mul(xr, xr), f_mul(xi, xi));
                        xi = f_mul(f_mul(TWO, xr), xi);
                        xr = tmp;
                    }
                    comp_mul(zr, zi, xr, xi, &zr, &zi);
                }
            }
            return nucomp_s_new_internal(CLASS_OF(self), zr, zi);
        }
    }
    if (k_numeric_p(other) && f_real_p(other)) {
        VALUE r, theta;

        if (RB_BIGNUM_TYPE_P(other))
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
 *   complex == object -> true or false
 *
 * Returns +true+ if <tt>self.real == object.real</tt>
 * and <tt>self.imag == object.imag</tt>:
 *
 *   Complex.rect(2, 3)  == Complex.rect(2.0, 3.0) # => true
 *
 */
static VALUE
nucomp_eqeq_p(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
        get_dat2(self, other);

        return RBOOL(f_eqeq_p(adat->real, bdat->real) &&
                          f_eqeq_p(adat->imag, bdat->imag));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
        get_dat1(self);

        return RBOOL(f_eqeq_p(dat->real, other) && f_zero_p(dat->imag));
    }
    return RBOOL(f_eqeq_p(other, self));
}

static bool
nucomp_real_p(VALUE self)
{
    get_dat1(self);
    return f_zero_p(dat->imag);
}

/*
 * call-seq:
 *   complex <=> object -> -1, 0, 1, or nil
 *
 * Returns:
 *
 * - <tt>self.real <=> object.real</tt> if both of the following are true:
 *
 *   - <tt>self.imag == 0</tt>.
 *   - <tt>object.imag == 0</tt>. # Always true if object is numeric but not complex.
 *
 * - +nil+ otherwise.
 *
 * Examples:
 *
 *   Complex.rect(2) <=> 3                  # => -1
 *   Complex.rect(2) <=> 2                  # => 0
 *   Complex.rect(2) <=> 1                  # => 1
 *   Complex.rect(2, 1) <=> 1               # => nil # self.imag not zero.
 *   Complex.rect(1) <=> Complex.rect(1, 1) # => nil # object.imag not zero.
 *   Complex.rect(1) <=> 'Foo'              # => nil # object.imag not defined.
 *
 */
static VALUE
nucomp_cmp(VALUE self, VALUE other)
{
    if (!k_numeric_p(other)) {
        return rb_num_coerce_cmp(self, other, idCmp);
    }
    if (!nucomp_real_p(self)) {
        return Qnil;
    }
    if (RB_TYPE_P(other, T_COMPLEX)) {
        if (nucomp_real_p(other)) {
            get_dat2(self, other);
            return rb_funcall(adat->real, idCmp, 1, bdat->real);
        }
    }
    else {
        get_dat1(self);
        if (f_real_p(other)) {
            return rb_funcall(dat->real, idCmp, 1, other);
        }
        else {
            return rb_num_coerce_cmp(dat->real, other, idCmp);
        }
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
nucomp_coerce(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX))
        return rb_assoc_new(other, self);
    if (k_numeric_p(other) && f_real_p(other))
        return rb_assoc_new(f_complex_new_bang1(CLASS_OF(self), other), self);

    rb_raise(rb_eTypeError, "%"PRIsVALUE" can't be coerced into %"PRIsVALUE,
             rb_obj_class(other), rb_obj_class(self));
    return Qnil;
}

/*
 * call-seq:
 *   abs -> float
 *
 * Returns the absolute value (magnitude) for +self+;
 * see {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates]:
 *
 *   Complex.polar(-1, 0).abs # => 1.0
 *
 * If +self+ was created with
 * {rectangular coordinates}[rdoc-ref:Complex@Rectangular+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.rectangular(1, 1).abs # => 1.4142135623730951 # The square root of 2.
 *
 */
VALUE
rb_complex_abs(VALUE self)
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
 *   abs2 -> float
 *
 * Returns square of the absolute value (magnitude) for +self+;
 * see {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates]:
 *
 *   Complex.polar(2, 2).abs2 # => 4.0
 *
 * If +self+ was created with
 * {rectangular coordinates}[rdoc-ref:Complex@Rectangular+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.rectangular(1.0/3, 1.0/3).abs2 # => 0.2222222222222222
 *
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
 *   arg -> float
 *
 * Returns the argument (angle) for +self+ in radians;
 * see {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates]:
 *
 *   Complex.polar(3, Math::PI/2).arg  # => 1.57079632679489660
 *
 * If +self+ was created with
 * {rectangular coordinates}[rdoc-ref:Complex@Rectangular+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.polar(1, 1.0/3).arg # => 0.33333333333333326
 *
 */
VALUE
rb_complex_arg(VALUE self)
{
    get_dat1(self);
    return rb_math_atan2(dat->imag, dat->real);
}

/*
 * call-seq:
 *   rect -> array
 *
 * Returns the array <tt>[self.real, self.imag]</tt>:
 *
 *   Complex.rect(1, 2).rect # => [1, 2]
 *
 * See {Rectangular Coordinates}[rdoc-ref:Complex@Rectangular+Coordinates].
 *
 * If +self+ was created with
 * {polar coordinates}[rdoc-ref:Complex@Polar+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.polar(1.0, 1.0).rect # => [0.5403023058681398, 0.8414709848078965]
 *
 *
 * Complex#rectangular is an alias for Complex#rect.
 */
static VALUE
nucomp_rect(VALUE self)
{
    get_dat1(self);
    return rb_assoc_new(dat->real, dat->imag);
}

/*
 * call-seq:
 *   polar -> array
 *
 * Returns the array <tt>[self.abs, self.arg]</tt>:
 *
 *   Complex.polar(1, 2).polar # => [1.0, 2.0]
 *
 * See {Polar Coordinates}[rdoc-ref:Complex@Polar+Coordinates].
 *
 * If +self+ was created with
 * {rectangular coordinates}[rdoc-ref:Complex@Rectangular+Coordinates], the returned value
 * is computed, and may be inexact:
 *
 *   Complex.rect(1, 1).polar # => [1.4142135623730951, 0.7853981633974483]
 *
 */
static VALUE
nucomp_polar(VALUE self)
{
    return rb_assoc_new(f_abs(self), f_arg(self));
}

/*
 * call-seq:
 *   conj -> complex
 *
 * Returns the conjugate of +self+, <tt>Complex.rect(self.imag, self.real)</tt>:
 *
 *   Complex.rect(1, 2).conj # => (1-2i)
 *
 */
VALUE
rb_complex_conjugate(VALUE self)
{
    get_dat1(self);
    return f_complex_new2(CLASS_OF(self), dat->real, f_negate(dat->imag));
}

/*
 * call-seq:
 *   real? -> false
 *
 * Returns +false+; for compatibility with Numeric#real?.
 */
static VALUE
nucomp_real_p_m(VALUE self)
{
    return Qfalse;
}

/*
 * call-seq:
 *   denominator -> integer
 *
 * Returns the denominator of +self+, which is
 * the {least common multiple}[https://en.wikipedia.org/wiki/Least_common_multiple]
 * of <tt>self.real.denominator</tt> and <tt>self.imag.denominator</tt>:
 *
 *   Complex.rect(Rational(1, 2), Rational(2, 3)).denominator # => 6
 *
 * Note that <tt>n.denominator</tt> of a non-rational numeric is +1+.
 *
 * Related: Complex#numerator.
 */
static VALUE
nucomp_denominator(VALUE self)
{
    get_dat1(self);
    return rb_lcm(f_denominator(dat->real), f_denominator(dat->imag));
}

/*
 * call-seq:
 *   numerator -> new_complex
 *
 * Returns the \Complex object created from the numerators
 * of the real and imaginary parts of +self+,
 * after converting each part to the
 * {lowest common denominator}[https://en.wikipedia.org/wiki/Lowest_common_denominator]
 * of the two:
 *
 *   c = Complex.rect(Rational(2, 3), Rational(3, 4)) # => ((2/3)+(3/4)*i)
 *   c.numerator                                      # => (8+9i)
 *
 * In this example, the lowest common denominator of the two parts is 12;
 * the two converted parts may be thought of as \Rational(8, 12) and \Rational(9, 12),
 * whose numerators, respectively, are 8 and 9;
 * so the returned value of <tt>c.numerator</tt> is <tt>Complex.rect(8, 9)</tt>.
 *
 * Related: Complex#denominator.
 */
static VALUE
nucomp_numerator(VALUE self)
{
    VALUE cd;

    get_dat1(self);

    cd = nucomp_denominator(self);
    return f_complex_new2(CLASS_OF(self),
                          f_mul(f_numerator(dat->real),
                                f_div(cd, f_denominator(dat->real))),
                          f_mul(f_numerator(dat->imag),
                                f_div(cd, f_denominator(dat->imag))));
}

/* :nodoc: */
st_index_t
rb_complex_hash(VALUE self)
{
    st_index_t v, h[2];
    VALUE n;

    get_dat1(self);
    n = rb_hash(dat->real);
    h[0] = NUM2LONG(n);
    n = rb_hash(dat->imag);
    h[1] = NUM2LONG(n);
    v = rb_memhash(h, sizeof(h));
    return v;
}

/*
 * :call-seq:
 *   hash -> integer
 *
 * Returns the integer hash value for +self+.
 *
 * Two \Complex objects created from the same values will have the same hash value
 * (and will compare using #eql?):
 *
 *   Complex.rect(1, 2).hash == Complex.rect(1, 2).hash # => true
 *
 */
static VALUE
nucomp_hash(VALUE self)
{
    return ST2FIX(rb_complex_hash(self));
}

/* :nodoc: */
static VALUE
nucomp_eql_p(VALUE self, VALUE other)
{
    if (RB_TYPE_P(other, T_COMPLEX)) {
        get_dat2(self, other);

        return RBOOL((CLASS_OF(adat->real) == CLASS_OF(bdat->real)) &&
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
f_format(VALUE self, VALUE s, VALUE (*func)(VALUE))
{
    int impos;

    get_dat1(self);

    impos = f_tpositive_p(dat->imag);

    rb_str_concat(s, (*func)(dat->real));
    rb_str_cat2(s, !impos ? "-" : "+");

    rb_str_concat(s, (*func)(f_abs(dat->imag)));
    if (!rb_isdigit(RSTRING_PTR(s)[RSTRING_LEN(s) - 1]))
        rb_str_cat2(s, "*");
    rb_str_cat2(s, "i");

    return s;
}

/*
 * call-seq:
 *   to_s -> string
 *
 * Returns a string representation of +self+:
 *
 *   Complex.rect(2).to_s                      # => "2+0i"
 *   Complex.rect(-8, 6).to_s                  # => "-8+6i"
 *   Complex.rect(0, Rational(1, 2)).to_s      # => "0+1/2i"
 *   Complex.rect(0, Float::INFINITY).to_s     # => "0+Infinity*i"
 *   Complex.rect(Float::NAN, Float::NAN).to_s # => "NaN+NaN*i"
 *
 */
static VALUE
nucomp_to_s(VALUE self)
{
    return f_format(self, rb_usascii_str_new2(""), rb_String);
}

/*
 * call-seq:
 *   inspect -> string
 *
 * Returns a string representation of +self+:
 *
 *   Complex.rect(2).inspect                      # => "(2+0i)"
 *   Complex.rect(-8, 6).inspect                  # => "(-8+6i)"
 *   Complex.rect(0, Rational(1, 2)).inspect      # => "(0+(1/2)*i)"
 *   Complex.rect(0, Float::INFINITY).inspect     # => "(0+Infinity*i)"
 *   Complex.rect(Float::NAN, Float::NAN).inspect # => "(NaN+NaN*i)"
 *
 */
static VALUE
nucomp_inspect(VALUE self)
{
    VALUE s;

    s = rb_usascii_str_new2("(");
    f_format(self, s, rb_inspect);
    rb_str_cat2(s, ")");

    return s;
}

#define FINITE_TYPE_P(v) (RB_INTEGER_TYPE_P(v) || RB_TYPE_P(v, T_RATIONAL))

/*
 * call-seq:
 *   finite? -> true or false
 *
 * Returns +true+ if both <tt>self.real.finite?</tt> and <tt>self.imag.finite?</tt>
 * are true, +false+ otherwise:
 *
 *   Complex.rect(1, 1).finite?               # => true
 *   Complex.rect(Float::INFINITY, 0).finite? # => false
 *
 * Related: Numeric#finite?, Float#finite?.
 */
static VALUE
rb_complex_finite_p(VALUE self)
{
    get_dat1(self);

    return RBOOL(f_finite_p(dat->real) && f_finite_p(dat->imag));
}

/*
 * call-seq:
 *   infinite? -> 1 or nil
 *
 * Returns +1+ if either <tt>self.real.infinite?</tt> or <tt>self.imag.infinite?</tt>
 * is true, +nil+ otherwise:
 *
 *   Complex.rect(Float::INFINITY, 0).infinite? # => 1
 *   Complex.rect(1, 1).infinite?               # => nil
 *
 * Related: Numeric#infinite?, Float#infinite?.
 */
static VALUE
rb_complex_infinite_p(VALUE self)
{
    get_dat1(self);

    if (!f_infinite_p(dat->real) && !f_infinite_p(dat->imag)) {
        return Qnil;
    }
    return ONE;
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
    OBJ_FREEZE(self);

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
rb_complex_new_polar(VALUE x, VALUE y)
{
    return f_complex_polar(rb_cComplex, x, y);
}

VALUE
rb_complex_polar(VALUE x, VALUE y)
{
    return rb_complex_new_polar(x, y);
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
rb_dbl_complex_new(double real, double imag)
{
    return rb_complex_raw(DBL2NUM(real), DBL2NUM(imag));
}

/*
 * call-seq:
 *   to_i -> integer
 *
 * Returns the value of <tt>self.real</tt> as an Integer, if possible:
 *
 *   Complex.rect(1, 0).to_i              # => 1
 *   Complex.rect(1, Rational(0, 1)).to_i # => 1
 *
 * Raises RangeError if <tt>self.imag</tt> is not exactly zero
 * (either <tt>Integer(0)</tt> or <tt>Rational(0, _n_)</tt>).
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
 *   to_f -> float
 *
 * Returns the value of <tt>self.real</tt> as a Float, if possible:
 *
 *   Complex.rect(1, 0).to_f              # => 1.0
 *   Complex.rect(1, Rational(0, 1)).to_f # => 1.0
 *
 * Raises RangeError if <tt>self.imag</tt> is not exactly zero
 * (either <tt>Integer(0)</tt> or <tt>Rational(0, _n_)</tt>).
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
 *   to_r -> rational
 *
 * Returns the value of <tt>self.real</tt> as a Rational, if possible:
 *
 *   Complex.rect(1, 0).to_r              # => (1/1)
 *   Complex.rect(1, Rational(0, 1)).to_r # => (1/1)
 *   Complex.rect(1, 0.0).to_r            # => (1/1)
 *
 * Raises RangeError if <tt>self.imag</tt> is not exactly zero
 * (either <tt>Integer(0)</tt> or <tt>Rational(0, _n_)</tt>)
 * and <tt>self.imag.to_r</tt> is not exactly zero.
 *
 * Related: Complex#rationalize.
 */
static VALUE
nucomp_to_r(VALUE self)
{
    get_dat1(self);

    if (RB_FLOAT_TYPE_P(dat->imag) && FLOAT_ZERO_P(dat->imag)) {
        /* Do nothing here */
    }
    else if (!k_exact_zero_p(dat->imag)) {
        VALUE imag = rb_check_convert_type_with_id(dat->imag, T_RATIONAL, "Rational", idTo_r);
        if (NIL_P(imag) || !k_exact_zero_p(imag)) {
            rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Rational",
                     self);
        }
    }
    return f_to_r(dat->real);
}

/*
 * call-seq:
 *   rationalize(epsilon = nil) -> rational
 *
 * Returns a Rational object whose value is exactly or approximately
 * equivalent to that of <tt>self.real</tt>.
 *
 * With no argument +epsilon+ given, returns a \Rational object
 * whose value is exactly equal to that of <tt>self.real.rationalize</tt>:
 *
 *   Complex.rect(1, 0).rationalize              # => (1/1)
 *   Complex.rect(1, Rational(0, 1)).rationalize # => (1/1)
 *   Complex.rect(3.14159, 0).rationalize        # => (314159/100000)
 *
 * With argument +epsilon+ given, returns a \Rational object
 * whose value is exactly or approximately equal to that of <tt>self.real</tt>
 * to the given precision:
 *
 *   Complex.rect(3.14159, 0).rationalize(0.1)          # => (16/5)
 *   Complex.rect(3.14159, 0).rationalize(0.01)         # => (22/7)
 *   Complex.rect(3.14159, 0).rationalize(0.001)        # => (201/64)
 *   Complex.rect(3.14159, 0).rationalize(0.0001)       # => (333/106)
 *   Complex.rect(3.14159, 0).rationalize(0.00001)      # => (355/113)
 *   Complex.rect(3.14159, 0).rationalize(0.000001)     # => (7433/2366)
 *   Complex.rect(3.14159, 0).rationalize(0.0000001)    # => (9208/2931)
 *   Complex.rect(3.14159, 0).rationalize(0.00000001)   # => (47460/15107)
 *   Complex.rect(3.14159, 0).rationalize(0.000000001)  # => (76149/24239)
 *   Complex.rect(3.14159, 0).rationalize(0.0000000001) # => (314159/100000)
 *   Complex.rect(3.14159, 0).rationalize(0.0)          # => (3537115888337719/1125899906842624)
 *
 * Related: Complex#to_r.
 */
static VALUE
nucomp_rationalize(int argc, VALUE *argv, VALUE self)
{
    get_dat1(self);

    rb_check_arity(argc, 0, 1);

    if (!k_exact_zero_p(dat->imag)) {
       rb_raise(rb_eRangeError, "can't convert %"PRIsVALUE" into Rational",
                self);
    }
    return rb_funcallv(dat->real, id_rationalize, argc, argv);
}

/*
 * call-seq:
 *   to_c -> self
 *
 * Returns +self+.
 */
static VALUE
nucomp_to_c(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *   to_c -> complex
 *
 * Returns +self+ as a Complex object.
 */
static VALUE
numeric_to_c(VALUE self)
{
    return rb_complex_new1(self);
}

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
            if (us) {
                if (strict) return 0;
                break;
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
        *ret = rb_complex_new_polar(num, num2);
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
parse_comp(const char *s, int strict, VALUE *num)
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
string_to_c_strict(VALUE self, int raise)
{
    char *s;
    VALUE num;

    rb_must_asciicompat(self);

    if (raise) {
        s = StringValueCStr(self);
    }
    else if (!(s = rb_str_to_cstr(self))) {
        return Qnil;
    }

    if (!parse_comp(s, TRUE, &num)) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "invalid value for convert(): %+"PRIsVALUE,
                 self);
    }

    return num;
}

/*
 * call-seq:
 *   to_c -> complex
 *
 * Returns +self+ interpreted as a Complex object;
 * leading whitespace and trailing garbage are ignored:
 *
 *   '9'.to_c                 # => (9+0i)
 *   '2.5'.to_c               # => (2.5+0i)
 *   '2.5/1'.to_c             # => ((5/2)+0i)
 *   '-3/2'.to_c              # => ((-3/2)+0i)
 *   '-i'.to_c                # => (0-1i)
 *   '45i'.to_c               # => (0+45i)
 *   '3-4i'.to_c              # => (3-4i)
 *   '-4e2-4e-2i'.to_c        # => (-400.0-0.04i)
 *   '-0.0-0.0i'.to_c         # => (-0.0-0.0i)
 *   '1/2+3/4i'.to_c          # => ((1/2)+(3/4)*i)
 *   '1.0@0'.to_c             # => (1+0.0i)
 *   "1.0@#{Math::PI/2}".to_c # => (0.0+1i)
 *   "1.0@#{Math::PI}".to_c   # => (-1+0.0i)
 *
 * Returns \Complex zero if the string cannot be converted:
 *
 *   'ruby'.to_c        # => (0+0i)
 *
 * See Kernel#Complex.
 */
static VALUE
string_to_c(VALUE self)
{
    VALUE num;

    rb_must_asciicompat(self);

    (void)parse_comp(rb_str_fill_terminator(self, 1), FALSE, &num);

    return num;
}

static VALUE
to_complex(VALUE val)
{
    return rb_convert_type(val, T_COMPLEX, "Complex", "to_c");
}

static VALUE
nucomp_convert(VALUE klass, VALUE a1, VALUE a2, int raise)
{
    if (NIL_P(a1) || NIL_P(a2)) {
        if (!raise) return Qnil;
        rb_raise(rb_eTypeError, "can't convert nil into Complex");
    }

    if (RB_TYPE_P(a1, T_STRING)) {
        a1 = string_to_c_strict(a1, raise);
        if (NIL_P(a1)) return Qnil;
    }

    if (RB_TYPE_P(a2, T_STRING)) {
        a2 = string_to_c_strict(a2, raise);
        if (NIL_P(a2)) return Qnil;
    }

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
        if (UNDEF_P(a2) || (k_exact_zero_p(a2)))
            return a1;
    }

    if (UNDEF_P(a2)) {
        if (k_numeric_p(a1) && !f_real_p(a1))
            return a1;
        /* should raise exception for consistency */
        if (!k_numeric_p(a1)) {
            if (!raise) {
                a1 = rb_protect(to_complex, a1, NULL);
                rb_set_errinfo(Qnil);
                return a1;
            }
            return to_complex(a1);
        }
    }
    else {
        if ((k_numeric_p(a1) && k_numeric_p(a2)) &&
            (!f_real_p(a1) || !f_real_p(a2)))
            return f_add(a1,
                         f_mul(a2,
                               f_complex_new_bang2(rb_cComplex, ZERO, ONE)));
    }

    {
        int argc;
        VALUE argv2[2];
        argv2[0] = a1;
        if (UNDEF_P(a2)) {
            argv2[1] = Qnil;
            argc = 1;
        }
        else {
            if (!raise && !RB_INTEGER_TYPE_P(a2) && !RB_FLOAT_TYPE_P(a2) && !RB_TYPE_P(a2, T_RATIONAL))
                return Qnil;
            argv2[1] = a2;
            argc = 2;
        }
        return nucomp_s_new(argc, argv2, klass);
    }
}

static VALUE
nucomp_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2;

    if (rb_scan_args(argc, argv, "11", &a1, &a2) == 1) {
        a2 = Qundef;
    }

    return nucomp_convert(klass, a1, a2, TRUE);
}

/*
 * call-seq:
 *   abs2 -> real
 *
 * Returns the square of +self+.
 */
static VALUE
numeric_abs2(VALUE self)
{
    return f_mul(self, self);
}

/*
 * call-seq:
 *   arg -> 0 or Math::PI
 *
 * Returns zero if +self+ is positive, Math::PI otherwise.
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
 *   rect -> array
 *
 * Returns array <tt>[self, 0]</tt>.
 */
static VALUE
numeric_rect(VALUE self)
{
    return rb_assoc_new(self, INT2FIX(0));
}

/*
 * call-seq:
 *   polar -> array
 *
 * Returns array <tt>[self.abs, self.arg]</tt>.
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
 *   arg -> 0 or Math::PI
 *
 * Returns 0 if +self+ is positive, Math::PI otherwise.
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
 * A \Complex object houses a pair of values,
 * given when the object is created as either <i>rectangular coordinates</i>
 * or <i>polar coordinates</i>.
 *
 * == Rectangular Coordinates
 *
 * The rectangular coordinates of a complex number
 * are called the _real_ and _imaginary_ parts;
 * see {Complex number definition}[https://en.wikipedia.org/wiki/Complex_number#Definition_and_basic_operations].
 *
 * You can create a \Complex object from rectangular coordinates with:
 *
 * - A {complex literal}[rdoc-ref:syntax/literals.rdoc@Complex+Literals].
 * - Method Complex.rect.
 * - Method Kernel#Complex, either with numeric arguments or with certain string arguments.
 * - Method String#to_c, for certain strings.
 *
 * Note that each of the stored parts may be a an instance one of the classes
 * Complex, Float, Integer, or Rational;
 * they may be retrieved:
 *
 * - Separately, with methods Complex#real and Complex#imaginary.
 * - Together, with method Complex#rect.
 *
 * The corresponding (computed) polar values may be retrieved:
 *
 * - Separately, with methods Complex#abs and Complex#arg.
 * - Together, with method Complex#polar.
 *
 * == Polar Coordinates
 *
 * The polar coordinates of a complex number
 * are called the _absolute_ and _argument_ parts;
 * see {Complex polar plane}[https://en.wikipedia.org/wiki/Complex_number#Polar_form].
 *
 * In this class, the argument part
 * in expressed {radians}[https://en.wikipedia.org/wiki/Radian]
 * (not {degrees}[https://en.wikipedia.org/wiki/Degree_(angle)]).
 *
 * You can create a \Complex object from polar coordinates with:
 *
 * - Method Complex.polar.
 * - Method Kernel#Complex, with certain string arguments.
 * - Method String#to_c, for certain strings.
 *
 * Note that each of the stored parts may be a an instance one of the classes
 * Complex, Float, Integer, or Rational;
 * they may be retrieved:
 *
 * - Separately, with methods Complex#abs and Complex#arg.
 * - Together, with method Complex#polar.
 *
 * The corresponding (computed) rectangular values may be retrieved:
 *
 * - Separately, with methods Complex#real and Complex#imag.
 * - Together, with method Complex#rect.
 *
 * == What's Here
 *
 * First, what's elsewhere:
 *
 * - Class \Complex inherits (directly or indirectly)
 *   from classes {Numeric}[rdoc-ref:Numeric@What-27s+Here]
 *   and {Object}[rdoc-ref:Object@What-27s+Here].
 * - Includes (indirectly) module {Comparable}[rdoc-ref:Comparable@What-27s+Here].
 *
 * Here, class \Complex has methods for:
 *
 * === Creating \Complex Objects
 *
 * - ::polar: Returns a new \Complex object based on given polar coordinates.
 * - ::rect (and its alias ::rectangular):
 *   Returns a new \Complex object based on given rectangular coordinates.
 *
 * === Querying
 *
 * - #abs (and its alias #magnitude): Returns the absolute value for +self+.
 * - #arg (and its aliases #angle and #phase):
 *   Returns the argument (angle) for +self+ in radians.
 * - #denominator: Returns the denominator of +self+.
 * - #finite?: Returns whether both +self.real+ and +self.image+ are finite.
 * - #hash: Returns the integer hash value for +self+.
 * - #imag (and its alias #imaginary): Returns the imaginary value for +self+.
 * - #infinite?: Returns whether +self.real+ or +self.image+ is infinite.
 * - #numerator: Returns the numerator of +self+.
 * - #polar: Returns the array <tt>[self.abs, self.arg]</tt>.
 * - #inspect: Returns a string representation of +self+.
 * - #real: Returns the real value for +self+.
 * - #real?: Returns +false+; for compatibility with Numeric#real?.
 * - #rect (and its alias #rectangular):
 *   Returns the array <tt>[self.real, self.imag]</tt>.
 *
 * === Comparing
 *
 * - #<=>: Returns whether +self+ is less than, equal to, or greater than the given argument.
 * - #==: Returns whether +self+ is equal to the given argument.
 *
 * === Converting
 *
 * - #rationalize: Returns a Rational object whose value is exactly
 *   or approximately equivalent to that of <tt>self.real</tt>.
 * - #to_c: Returns +self+.
 * - #to_d: Returns the value as a BigDecimal object.
 * - #to_f: Returns the value of <tt>self.real</tt> as a Float, if possible.
 * - #to_i: Returns the value of <tt>self.real</tt> as an Integer, if possible.
 * - #to_r: Returns the value of <tt>self.real</tt> as a Rational, if possible.
 * - #to_s: Returns a string representation of +self+.
 *
 * === Performing Complex Arithmetic
 *
 * - #*: Returns the product of +self+ and the given numeric.
 * - #**: Returns +self+ raised to power of the given numeric.
 * - #+: Returns the sum of +self+ and the given numeric.
 * - #-: Returns the difference of +self+ and the given numeric.
 * - #-@: Returns the negation of +self+.
 * - #/: Returns the quotient of +self+ and the given numeric.
 * - #abs2: Returns square of the absolute value (magnitude) for +self+.
 * - #conj (and its alias #conjugate): Returns the conjugate of +self+.
 * - #fdiv: Returns <tt>Complex.rect(self.real/numeric, self.imag/numeric)</tt>.
 *
 * === Working with JSON
 *
 * - ::json_create: Returns a new \Complex object,
 *   deserialized from the given serialized hash.
 * - #as_json: Returns a serialized hash constructed from +self+.
 * - #to_json: Returns a JSON string representing +self+.
 *
 * These methods are provided by the {JSON gem}[https://github.com/ruby/json]. To make these methods available:
 *
 *   require 'json/add/complex'
 *
 */
void
Init_Complex(void)
{
    VALUE compat;
    id_abs = rb_intern_const("abs");
    id_arg = rb_intern_const("arg");
    id_denominator = rb_intern_const("denominator");
    id_numerator = rb_intern_const("numerator");
    id_real_p = rb_intern_const("real?");
    id_i_real = rb_intern_const("@real");
    id_i_imag = rb_intern_const("@image"); /* @image, not @imag */
    id_finite_p = rb_intern_const("finite?");
    id_infinite_p = rb_intern_const("infinite?");
    id_rationalize = rb_intern_const("rationalize");
    id_PI = rb_intern_const("PI");

    rb_cComplex = rb_define_class("Complex", rb_cNumeric);

    rb_define_alloc_func(rb_cComplex, nucomp_s_alloc);
    rb_undef_method(CLASS_OF(rb_cComplex), "allocate");

    rb_undef_method(CLASS_OF(rb_cComplex), "new");

    rb_define_singleton_method(rb_cComplex, "rectangular", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "rect", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "polar", nucomp_s_polar, -1);

    rb_define_global_function("Complex", nucomp_f_complex, -1);

    rb_undef_methods_from(rb_cComplex, RCLASS_ORIGIN(rb_mComparable));
    rb_undef_method(rb_cComplex, "%");
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

    rb_define_method(rb_cComplex, "real", rb_complex_real, 0);
    rb_define_method(rb_cComplex, "imaginary", rb_complex_imag, 0);
    rb_define_method(rb_cComplex, "imag", rb_complex_imag, 0);

    rb_define_method(rb_cComplex, "-@", rb_complex_uminus, 0);
    rb_define_method(rb_cComplex, "+", rb_complex_plus, 1);
    rb_define_method(rb_cComplex, "-", rb_complex_minus, 1);
    rb_define_method(rb_cComplex, "*", rb_complex_mul, 1);
    rb_define_method(rb_cComplex, "/", rb_complex_div, 1);
    rb_define_method(rb_cComplex, "quo", nucomp_quo, 1);
    rb_define_method(rb_cComplex, "fdiv", nucomp_fdiv, 1);
    rb_define_method(rb_cComplex, "**", rb_complex_pow, 1);

    rb_define_method(rb_cComplex, "==", nucomp_eqeq_p, 1);
    rb_define_method(rb_cComplex, "<=>", nucomp_cmp, 1);
    rb_define_method(rb_cComplex, "coerce", nucomp_coerce, 1);

    rb_define_method(rb_cComplex, "abs", rb_complex_abs, 0);
    rb_define_method(rb_cComplex, "magnitude", rb_complex_abs, 0);
    rb_define_method(rb_cComplex, "abs2", nucomp_abs2, 0);
    rb_define_method(rb_cComplex, "arg", rb_complex_arg, 0);
    rb_define_method(rb_cComplex, "angle", rb_complex_arg, 0);
    rb_define_method(rb_cComplex, "phase", rb_complex_arg, 0);
    rb_define_method(rb_cComplex, "rectangular", nucomp_rect, 0);
    rb_define_method(rb_cComplex, "rect", nucomp_rect, 0);
    rb_define_method(rb_cComplex, "polar", nucomp_polar, 0);
    rb_define_method(rb_cComplex, "conjugate", rb_complex_conjugate, 0);
    rb_define_method(rb_cComplex, "conj", rb_complex_conjugate, 0);

    rb_define_method(rb_cComplex, "real?", nucomp_real_p_m, 0);

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
    /* :nodoc: */
    compat = rb_define_class_under(rb_cComplex, "compatible", rb_cObject);
    rb_define_private_method(compat, "marshal_load", nucomp_marshal_load, 1);
    rb_marshal_define_compat(rb_cComplex, compat, nucomp_dumper, nucomp_loader);

    rb_define_method(rb_cComplex, "to_i", nucomp_to_i, 0);
    rb_define_method(rb_cComplex, "to_f", nucomp_to_f, 0);
    rb_define_method(rb_cComplex, "to_r", nucomp_to_r, 0);
    rb_define_method(rb_cComplex, "rationalize", nucomp_rationalize, -1);
    rb_define_method(rb_cComplex, "to_c", nucomp_to_c, 0);
    rb_define_method(rb_cNumeric, "to_c", numeric_to_c, 0);

    rb_define_method(rb_cString, "to_c", string_to_c, 0);

    rb_define_private_method(CLASS_OF(rb_cComplex), "convert", nucomp_s_convert, -1);

    rb_define_method(rb_cNumeric, "abs2", numeric_abs2, 0);
    rb_define_method(rb_cNumeric, "arg", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "angle", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "phase", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "rectangular", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "rect", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "polar", numeric_polar, 0);

    rb_define_method(rb_cFloat, "arg", float_arg, 0);
    rb_define_method(rb_cFloat, "angle", float_arg, 0);
    rb_define_method(rb_cFloat, "phase", float_arg, 0);

    /*
     * Equivalent
     * to <tt>Complex.rect(0, 1)</tt>:
     *
     *   Complex::I # => (0+1i)
     *
     */
    rb_define_const(rb_cComplex, "I",
                    f_complex_new_bang2(rb_cComplex, ZERO, ONE));

#if !USE_FLONUM
    rb_vm_register_global_object(RFLOAT_0 = DBL2NUM(0.0));
#endif

    rb_provide("complex.so");	/* for backward compatibility */
}
