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
    NEWOBJ_OF(obj, struct RComplex, klass, T_COMPLEX | (RGENGC_WB_PROTECTED_COMPLEX ? FL_WB_PROTECTED : 0));

    RCOMPLEX_SET_REAL(obj, real);
    RCOMPLEX_SET_IMAG(obj, imag);
    OBJ_FREEZE_RAW((VALUE)obj);

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

WARN_UNUSED_RESULT(inline static VALUE nucomp_real_check(VALUE num));
inline static VALUE
nucomp_real_check(VALUE num)
{
    if (!RB_INTEGER_TYPE_P(num) &&
        !RB_FLOAT_TYPE_P(num) &&
        !RB_TYPE_P(num, T_RATIONAL)) {
        if (RB_TYPE_P(num, T_COMPLEX) && nucomp_real_p(num)) {
            VALUE real = RCOMPLEX(num)->real;
            assert(!RB_TYPE_P(real, T_COMPLEX));
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
 *    Complex(x[, y], exception: true)  ->  numeric or nil
 *
 * Returns x+i*y;
 *
 *    Complex(1, 2)    #=> (1+2i)
 *    Complex('1+2i')  #=> (1+2i)
 *    Complex(nil)     #=> TypeError
 *    Complex(1, nil)  #=> TypeError
 *
 *    Complex(1, nil, exception: false)  #=> nil
 *    Complex('1+2', exception: false)   #=> nil
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
 *    cmp.real  ->  real
 *
 * Returns the real part.
 *
 *    Complex(7).real      #=> 7
 *    Complex(9, -4).real  #=> 9
 */
VALUE
rb_complex_real(VALUE self)
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
VALUE
rb_complex_imag(VALUE self)
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
VALUE
rb_complex_uminus(VALUE self)
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
VALUE
rb_complex_div(VALUE self, VALUE other)
{
    return f_divide(self, other, f_quo, id_quo);
}

#define nucomp_quo rb_complex_div

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
 *    cmp <=> object  ->  0, 1, -1, or nil
 *
 * If +cmp+'s imaginary part is zero, and +object+ is also a
 * real number (or a Complex number where the imaginary part is zero),
 * compare the real part of +cmp+ to object.  Otherwise, return nil.
 *
 *    Complex(2, 3)  <=> Complex(2, 3)   #=> nil
 *    Complex(2, 3)  <=> 1               #=> nil
 *    Complex(2)     <=> 1               #=> 1
 *    Complex(2)     <=> 2               #=> 0
 *    Complex(2)     <=> 3               #=> -1
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
 *    cmp.abs        ->  real
 *    cmp.magnitude  ->  real
 *
 * Returns the absolute part of its polar form.
 *
 *    Complex(-1).abs         #=> 1
 *    Complex(3.0, -4.0).abs  #=> 5.0
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
VALUE
rb_complex_arg(VALUE self)
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
VALUE
rb_complex_conjugate(VALUE self)
{
    get_dat1(self);
    return f_complex_new2(CLASS_OF(self), dat->real, f_negate(dat->imag));
}

/*
 * call-seq:
 *    Complex(1).real?     ->  false
 *    Complex(1, 2).real?  ->  false
 *
 * Returns false, even if the complex number has no imaginary part.
 */
static VALUE
nucomp_real_p_m(VALUE self)
{
    return Qfalse;
}

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
 * Returns +true+ if +cmp+'s real and imaginary parts are both finite numbers,
 * otherwise returns +false+.
 */
static VALUE
rb_complex_finite_p(VALUE self)
{
    get_dat1(self);

    return RBOOL(f_finite_p(dat->real) && f_finite_p(dat->imag));
}

/*
 * call-seq:
 *    cmp.infinite?  ->  nil or 1
 *
 * Returns +1+ if +cmp+'s real or imaginary part is an infinite number,
 * otherwise returns +nil+.
 *
 *  For example:
 *
 *     (1+1i).infinite?                   #=> nil
 *     (Float::INFINITY + 1i).infinite?   #=> 1
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
    OBJ_FREEZE_RAW(self);

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

    rb_check_arity(argc, 0, 1);

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

    s = RSTRING_PTR(self);

    if (!s || memchr(s, '\0', RSTRING_LEN(self))) {
        if (!raise) return Qnil;
        rb_raise(rb_eArgError, "string contains null byte");
    }

    if (s && s[RSTRING_LEN(self)]) {
        rb_str_modify(self);
        s = RSTRING_PTR(self);
        s[RSTRING_LEN(self)] = '\0';
    }

    if (!s)
        s = (char *)"";

    if (!parse_comp(s, 1, &num)) {
        if (!raise) return Qnil;
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
 * Polar form:
 *    include Math
 *    "1.0@0".to_c        #=> (1+0.0i)
 *    "1.0@#{PI/2}".to_c  #=> (0.0+1i)
 *    "1.0@#{PI}".to_c    #=> (-1+0.0i)
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
            if (!raise)
                return rb_protect(to_complex, a1, NULL);
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
 * You can create a \Complex object explicitly with:
 *
 * - A {complex literal}[rdoc-ref:syntax/literals.rdoc@Complex+Literals].
 *
 * You can convert certain objects to \Complex objects with:
 *
 * - \Method #Complex.
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
    rb_define_method(rb_cNilClass, "to_c", nilclass_to_c, 0);
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
     * The imaginary unit.
     */
    rb_define_const(rb_cComplex, "I",
                    f_complex_new_bang2(rb_cComplex, ZERO, ONE));

#if !USE_FLONUM
    rb_gc_register_mark_object(RFLOAT_0 = DBL2NUM(0.0));
#endif

    rb_provide("complex.so");	/* for backward compatibility */
}
