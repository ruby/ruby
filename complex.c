/*
  complex.c: Coded by Tadayoshi Funaba 2008

  This implementation is based on Keiju Ishitsuka's Complex library
  which is written in ruby.
*/

#include "ruby.h"
#include <math.h>

#define NDEBUG
#include <assert.h>

#ifndef COMPLEX_NAME
#define COMPLEX_NAME "Complex"
#endif

#define ZERO INT2FIX(0)
#define ONE INT2FIX(1)
#define TWO INT2FIX(2)

VALUE rb_cComplex;

static ID id_Unify, id_abs, id_abs2, id_arg, id_cmp, id_conjugate,
    id_convert, id_denominator, id_divmod, id_equal_p, id_exact_p, id_expt,
    id_floor, id_hash, id_idiv, id_inspect, id_negate, id_new, id_new_bang,
    id_numerator, id_polar, id_quo, id_scalar_p, id_to_f, id_to_i, id_to_r,
    id_to_s, id_truncate;

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
    if (FIXNUM_P(y) && FIX2LONG(y) == 0)
	return x;
    else if (FIXNUM_P(x) && FIX2LONG(x) == 0)
	return y;
#endif
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
#ifndef PRESERVE_SIGNEDZERO
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
#endif
    return rb_funcall(x, '*', 1, y);
}

inline static VALUE
f_sub(VALUE x, VALUE y)
{
#ifndef PRESERVE_SIGNEDZERO
    if (FIXNUM_P(y) && FIX2LONG(y) == 0)
	return x;
#endif
    return rb_funcall(x, '-', 1, y);
}

binop(xor, '^')

fun1(abs)
fun1(abs2)
fun1(arg)
fun1(conjugate)
fun1(denominator)
fun1(exact_p)
fun1(floor)
fun1(hash)
fun1(inspect)
fun1(negate)
fun1(numerator)
fun1(polar)
fun1(scalar_p)

#define f_real_p f_scalar_p

fun1(to_f)
fun1(to_i)
fun1(to_r)
fun1(to_s)
fun1(truncate)

fun2(divmod)

inline static VALUE
f_equal_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) == FIX2LONG(y));
    return rb_funcall(x, id_equal_p, 1, y);
}

fun2(expt)
fun2(idiv)
fun2(quo)

inline static VALUE
f_negative_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) < 0);
    return rb_funcall(x, '<', 1, ZERO);
}

inline static VALUE
f_zero_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) == 0);
    return rb_funcall(x, id_equal_p, 1, ZERO);
}

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

inline static VALUE
k_complex_p(VALUE x)
{
    return f_kind_of_p(x, rb_cComplex);
}

#define get_dat1(x) \
    struct RComplex *dat;\
    dat = ((struct RComplex *)(x))

#define get_dat2(x,y) \
    struct RComplex *adat, *bdat;\
    adat = ((struct RComplex *)(x));\
    bdat = ((struct RComplex *)(y))

inline static VALUE
nucomp_s_new_internal(VALUE klass, VALUE real, VALUE image)
{
    NEWOBJ(obj, struct RComplex);
    OBJSETUP(obj, klass, T_COMPLEX);

    obj->real = real;
    obj->image = image;

    return (VALUE)obj;
}

static VALUE
nucomp_s_alloc(VALUE klass)
{
    return nucomp_s_new_internal(klass, ZERO, ZERO);
}

static VALUE
nucomp_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, image;

    switch (rb_scan_args(argc, argv, "11", &real, &image)) {
      case 1:
	if (!k_numeric_p(real))
	    real = f_to_i(real);
	image = ZERO;
	break;
      default:
	if (!k_numeric_p(real))
	    real = f_to_i(real);
	if (!k_numeric_p(image))
	    image = f_to_i(image);
	break;
    }

    return nucomp_s_new_internal(klass, real, image);
}

inline static VALUE
f_complex_new_bang1(VALUE klass, VALUE x)
{
    assert(!k_complex_p(x));
    return nucomp_s_new_internal(klass, x, ZERO);
}

inline static VALUE
f_complex_new_bang2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_complex_p(x));
    assert(!k_complex_p(y));
    return nucomp_s_new_internal(klass, x, y);
}

#define f_unify_p(klass) rb_const_defined(klass, id_Unify)

inline static void
nucomp_real_check(VALUE num)
{
    switch (TYPE(num)) {
      case T_FIXNUM:
      case T_BIGNUM:
      case T_FLOAT:
      case T_RATIONAL:
	break;
      default:
	if (!k_numeric_p(num) || !f_real_p(num))
	    rb_raise(rb_eArgError, "not a real");
    }
}

inline static VALUE
nucomp_s_canonicalize_internal(VALUE klass, VALUE real, VALUE image)
{
#define CL_CANON
#ifdef CL_CANON
    if (f_zero_p(image) && f_unify_p(klass) &&
	!k_float_p(real) && !k_float_p(image))
	return real;
#else
    if (f_zero_p(image) && f_unify_p(klass))
	return real;
#endif
    else if (f_real_p(real) && f_real_p(image))
	return nucomp_s_new_internal(klass, real, image);
    else if (f_real_p(real)) {
	get_dat1(image);

	return nucomp_s_new_internal(klass,
				     f_sub(real, dat->image),
				     f_add(ZERO, dat->real));
    }
    else if (f_real_p(image)) {
	get_dat1(real);

	return nucomp_s_new_internal(klass,
				     dat->real,
				     f_add(dat->image, image));
    }
    else {
	get_dat2(real, image);

	return nucomp_s_new_internal(klass,
				     f_sub(adat->real, bdat->image),
				     f_add(adat->image, bdat->real));
    }
}

#if 0
static VALUE
nucomp_s_canonicalize(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, image;

    switch (rb_scan_args(argc, argv, "11", &real, &image)) {
      case 1:
	nucomp_real_check(real);
	image = ZERO;
	break;
      default:
	nucomp_real_check(real);
	nucomp_real_check(image);
	break;
    }

    return nucomp_s_canonicalize_internal(klass, real, image);
}
#endif

static VALUE
nucomp_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE real, image;

    switch (rb_scan_args(argc, argv, "11", &real, &image)) {
      case 1:
	nucomp_real_check(real);
	image = ZERO;
	break;
      default:
	nucomp_real_check(real);
	nucomp_real_check(image);
	break;
    }

    return nucomp_s_canonicalize_internal(klass, real, image);
}

inline static VALUE
f_complex_new1(VALUE klass, VALUE x)
{
    assert(!k_complex_p(x));
    return nucomp_s_canonicalize_internal(klass, x, ZERO);
}

inline static VALUE
f_complex_new2(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_complex_p(x));
    return nucomp_s_canonicalize_internal(klass, x, y);
}

static VALUE
nucomp_f_complex(int argc, VALUE *argv, VALUE klass)
{
    return rb_funcall2(rb_cComplex, id_convert, argc, argv);
}

extern VALUE math_atan2(VALUE obj, VALUE x, VALUE y);
extern VALUE math_cos(VALUE obj, VALUE x);
extern VALUE math_cosh(VALUE obj, VALUE x);
extern VALUE math_exp(VALUE obj, VALUE x);
extern VALUE math_hypot(VALUE obj, VALUE x, VALUE y);
extern VALUE math_log(int argc, VALUE *argv);
extern VALUE math_sin(VALUE obj, VALUE x);
extern VALUE math_sinh(VALUE obj, VALUE x);
extern VALUE math_sqrt(VALUE obj, VALUE x);

#define m_atan2_bang(x,y) math_atan2(Qnil,x,y)
#define m_cos_bang(x) math_cos(Qnil,x)
#define m_cosh_bang(x) math_cosh(Qnil,x)
#define m_exp_bang(x) math_exp(Qnil,x)
#define m_hypot(x,y) math_hypot(Qnil,x,y)

static VALUE
m_log_bang(VALUE x)
{
    return math_log(1, &x);
}

#define m_sin_bang(x) math_sin(Qnil,x)
#define m_sinh_bang(x) math_sinh(Qnil,x)
#define m_sqrt_bang(x) math_sqrt(Qnil,x)

static VALUE
m_cos(VALUE x)
{
    get_dat1(x);

    if (f_real_p(x))
	return m_cos_bang(x);
    return f_complex_new2(rb_cComplex,
			  f_mul(m_cos_bang(dat->real),
				m_cosh_bang(dat->image)),
			  f_mul(f_negate(m_sin_bang(dat->real)),
				m_sinh_bang(dat->image)));
}

static VALUE
m_sin(VALUE x)
{
    get_dat1(x);

    if (f_real_p(x))
	return m_sin_bang(x);
    return f_complex_new2(rb_cComplex,
			  f_mul(m_sin_bang(dat->real),
				m_cosh_bang(dat->image)),
			  f_mul(m_cos_bang(dat->real),
				m_sinh_bang(dat->image)));
}

static VALUE
m_sqrt(VALUE x)
{
    if (f_real_p(x)) {
	if (!f_negative_p(x))
	    return m_sqrt_bang(x);
	return f_complex_new2(rb_cComplex, ZERO, m_sqrt_bang(f_negate(x)));
    }
    else {
	get_dat1(x);

	if (f_negative_p(dat->image))
	    return f_conjugate(m_sqrt(f_conjugate(x)));
	else {
	    VALUE a = f_abs(x);
	    return f_complex_new2(rb_cComplex,
				  m_sqrt_bang(f_div(f_add(a, dat->real), TWO)),
				  m_sqrt_bang(f_div(f_sub(a, dat->real), TWO)));
	}
    }
}

inline static VALUE
f_complex_polar(VALUE klass, VALUE x, VALUE y)
{
    assert(!k_complex_p(x));
    assert(!k_complex_p(y));
    return nucomp_s_canonicalize_internal(klass,
					  f_mul(x, m_cos(y)),
					  f_mul(x, m_sin(y)));
}

static VALUE
nucomp_s_polar(VALUE klass, VALUE abs, VALUE arg)
{
    return f_complex_polar(klass, abs, arg);
}

static VALUE
nucomp_real(VALUE self)
{
    get_dat1(self);
    return dat->real;
}

static VALUE
nucomp_image(VALUE self)
{
    get_dat1(self);
    return dat->image;
}

static VALUE
nucomp_negate(VALUE self)
{
  get_dat1(self);
  return f_complex_new2(CLASS_OF(self),
			f_negate(dat->real), f_negate(dat->image));
}

static VALUE
nucomp_add(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	VALUE real, image;

	get_dat2(self, other);

	real = f_add(adat->real, bdat->real);
	image = f_add(adat->image, bdat->image);

	return f_complex_new2(CLASS_OF(self), real, image);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_add(dat->real, other), dat->image);
    }
    return rb_num_coerce_bin(self, other, '+');
}

static VALUE
nucomp_sub(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	VALUE real, image;

	get_dat2(self, other);

	real = f_sub(adat->real, bdat->real);
	image = f_sub(adat->image, bdat->image);

	return f_complex_new2(CLASS_OF(self), real, image);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_sub(dat->real, other), dat->image);
    }
    return rb_num_coerce_bin(self, other, '-');
}

static VALUE
nucomp_mul(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	VALUE real, image;

	get_dat2(self, other);

	real = f_sub(f_mul(adat->real, bdat->real),
		     f_mul(adat->image, bdat->image));
	image = f_add(f_mul(adat->real, bdat->image),
		      f_mul(adat->image, bdat->real));

	return f_complex_new2(CLASS_OF(self), real, image);
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_mul(dat->real, other),
			      f_mul(dat->image, other));
    }
    return rb_num_coerce_bin(self, other, '*');
}

#define f_div f_quo

static VALUE
nucomp_div(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	get_dat2(self, other);

	if (TYPE(adat->real)  == T_FLOAT ||
	    TYPE(adat->image) == T_FLOAT ||
	    TYPE(bdat->real)  == T_FLOAT ||
	    TYPE(bdat->image) == T_FLOAT) {
	    VALUE magn = m_hypot(bdat->real, bdat->image);
	    VALUE tmp = f_complex_new_bang2(CLASS_OF(self),
					    f_div(bdat->real, magn),
					    f_div(bdat->image, magn));
	    return f_div(f_mul(self, f_conjugate(tmp)), magn);
	}
	return f_div(f_mul(self, f_conjugate(other)), f_abs2(other));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_complex_new2(CLASS_OF(self),
			      f_div(dat->real, other),
			      f_div(dat->image, other));
    }
    return rb_num_coerce_bin(self, other, '/');
}

#undef f_div
#define nucomp_quo nucomp_div

static VALUE
nucomp_fdiv(VALUE self, VALUE other)
{
    get_dat1(self);

    return f_div(f_complex_new2(CLASS_OF(self),
				f_to_f(dat->real),
				f_to_f(dat->image)), other);
}

static VALUE
nucomp_expt(VALUE self, VALUE other)
{
    if (f_zero_p(other))
	return f_complex_new_bang1(CLASS_OF(self), ONE);

    if (k_rational_p(other) && f_one_p(f_denominator(other)))
	other = f_numerator(other); /* good? */

    if (k_complex_p(other)) {
	VALUE a, r, theta, ore, oim, nr, ntheta;

	get_dat1(other);

	a = f_polar(self);
	r = RARRAY_PTR(a)[0];
	theta = RARRAY_PTR(a)[1];

	ore = dat->real;
	oim = dat->image;
	nr = m_exp_bang(f_sub(f_mul(ore, m_log_bang(r)),
			      f_mul(oim, theta)));
	ntheta = f_add(f_mul(theta, ore), f_mul(oim, m_log_bang(r)));
	return f_complex_polar(CLASS_OF(self), nr, ntheta);
    }
    if (k_integer_p(other)) {
	if (f_gt_p(other, ZERO)) {
	    VALUE x, z, n;

	    x = self;
	    z = x;
	    n = f_sub(other, ONE);

	    while (!f_zero_p(n)) {
		VALUE a;

		while (a = f_divmod(n, TWO),
		       f_zero_p(RARRAY_PTR(a)[1])) {
		    get_dat1(x);

		    x = f_complex_new2(CLASS_OF(self),
				       f_sub(f_mul(dat->real, dat->real),
					     f_mul(dat->image, dat->image)),
				       f_mul(f_mul(TWO, dat->real), dat->image));
		    n = RARRAY_PTR(a)[0];
		}
		z = f_mul(z, x);
		n = f_sub(n, ONE);
	    }
	    return z;
	}
	return f_expt(f_div(f_to_r(ONE), self), f_negate(other));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	VALUE a, r, theta;

	a = f_polar(self);
	r = RARRAY_PTR(a)[0];
	theta = RARRAY_PTR(a)[1];
	return f_complex_polar(CLASS_OF(self), f_expt(r, other),
			      f_mul(theta, other));
    }
    return rb_num_coerce_bin(self, other, id_expt);
}

static VALUE
nucomp_equal_p(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	get_dat2(self, other);

	return f_boolcast(f_equal_p(adat->real, bdat->real) &&
			  f_equal_p(adat->image, bdat->image));
    }
    if (k_numeric_p(other) && f_real_p(other)) {
	get_dat1(self);

	return f_boolcast(f_equal_p(dat->real, other) && f_zero_p(dat->image));
    }
    return f_equal_p(other, self);
}

static VALUE
nucomp_coerce(VALUE self, VALUE other)
{
    if (k_numeric_p(other) && f_real_p(other))
	return rb_assoc_new(f_complex_new_bang1(CLASS_OF(self), other), self);

    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
	     rb_obj_classname(other), rb_obj_classname(self));
    return Qnil;
}

static VALUE
nucomp_abs(VALUE self)
{
    get_dat1(self);
    return m_hypot(dat->real, dat->image);
}

static VALUE
nucomp_abs2(VALUE self)
{
    get_dat1(self);
    return f_add(f_mul(dat->real, dat->real),
		 f_mul(dat->image, dat->image));
}

static VALUE
nucomp_arg(VALUE self)
{
    get_dat1(self);
    return m_atan2_bang(dat->image, dat->real);
}

static VALUE
nucomp_rect(VALUE self)
{
    get_dat1(self);
    return rb_assoc_new(dat->real, dat->image);
}

static VALUE
nucomp_polar(VALUE self)
{
    return rb_assoc_new(f_abs(self), f_arg(self));
}

static VALUE
nucomp_conjugate(VALUE self)
{
    get_dat1(self);
    return f_complex_new2(CLASS_OF(self), dat->real, f_negate(dat->image));
}

#if 0
static VALUE
nucomp_true(VALUE self)
{
    return Qtrue;
}
#endif

static VALUE
nucomp_false(VALUE self)
{
    return Qfalse;
}

#if 0
static VALUE
nucomp_exact_p(VALUE self)
{
    get_dat1(self);
    return f_boolcast(f_exact_p(dat->real) && f_exact_p(dat->image));
}

static VALUE
nucomp_inexact_p(VALUE self)
{
    return f_boolcast(!nucomp_exact_p(self));
}
#endif

extern VALUE rb_lcm(VALUE x, VALUE y);

static VALUE
nucomp_denominator(VALUE self)
{
    get_dat1(self);
    return rb_lcm(f_denominator(dat->real), f_denominator(dat->image));
}

static VALUE
nucomp_numerator(VALUE self)
{
    VALUE cd;

    get_dat1(self);

    cd = f_denominator(self);
    return f_complex_new2(CLASS_OF(self),
			  f_mul(f_numerator(dat->real),
				f_div(cd, f_denominator(dat->real))),
			  f_mul(f_numerator(dat->image),
				f_div(cd, f_denominator(dat->image))));
}

static VALUE
nucomp_hash(VALUE self)
{
    get_dat1(self);
    return f_xor(f_hash(dat->real), f_hash(dat->image));
}

static VALUE
nucomp_eql_p(VALUE self, VALUE other)
{
    if (k_complex_p(other)) {
	get_dat2(self, other);

	return f_boolcast((CLASS_OF(adat->real) == CLASS_OF(bdat->real)) &&
			  (CLASS_OF(adat->image) == CLASS_OF(bdat->image)) &&
			  f_equal_p(self, other));

    }
    return Qfalse;
}

#ifndef HAVE_SIGNBIT
#ifdef signbit
#define HAVE_SIGNBIT 1
#endif
#endif

inline static VALUE
f_signbit(VALUE x)
{
    switch (TYPE(x)) {
      case T_FLOAT:
#ifdef HAVE_SIGNBIT
	return f_boolcast(signbit(RFLOAT_VALUE(x)));
#else
	{
	    char s[2];

	    (void)snprintf(s, sizeof s, "%.0f", RFLOAT_VALUE(x));

	    return f_boolcast(s[0] == '-');
	}
#endif
    }
    return f_negative_p(x);
}

inline static VALUE
f_tpositive_p(VALUE x)
{
    return f_boolcast(!f_signbit(x));
}

static VALUE
nucomp_to_s(VALUE self)
{
    VALUE s, impos;

    get_dat1(self);

    impos = f_tpositive_p(dat->image);

    s = f_to_s(dat->real);
    rb_str_cat2(s, !impos ? "-" : "+");

    rb_str_concat(s, f_to_s(f_abs(dat->image)));
    rb_str_cat2(s, "i");

    return s;
}

static VALUE
nucomp_inspect(VALUE self)
{
    VALUE s, impos;

    get_dat1(self);

    impos = f_tpositive_p(dat->image);

    s = rb_str_new2("(");
    rb_str_concat(s, f_inspect(dat->real));
    rb_str_cat2(s, !impos ? "-" : "+");

    rb_str_concat(s, f_inspect(f_abs(dat->image)));
    rb_str_cat2(s, "i)");

    return s;
}

static VALUE
nucomp_marshal_dump(VALUE self)
{
    get_dat1(self);
    return rb_assoc_new(dat->real, dat->image);
}

static VALUE
nucomp_marshal_load(VALUE self, VALUE a)
{
    get_dat1(self);
    dat->real = RARRAY_PTR(a)[0];
    dat->image = RARRAY_PTR(a)[1];
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
    return nucomp_s_polar(rb_cComplex, x, y);
}

static VALUE nucomp_s_convert(int argc, VALUE *argv, VALUE klass);

VALUE
rb_Complex(VALUE x, VALUE y)
{
    VALUE a[2];
    a[0] = x;
    a[1] = y;
    return nucomp_s_convert(2, a, rb_cComplex);
}

static VALUE
nucomp_to_i(VALUE self)
{
    get_dat1(self);

    if (k_float_p(dat->image) || !f_zero_p(dat->image)) {
	VALUE s = f_to_s(self);
	rb_raise(rb_eRangeError, "can't convert %s into Integer",
		 StringValuePtr(s));
    }
    return f_to_i(dat->real);
}

static VALUE
nucomp_to_f(VALUE self)
{
    get_dat1(self);

    if (k_float_p(dat->image) || !f_zero_p(dat->image)) {
	VALUE s = f_to_s(self);
	rb_raise(rb_eRangeError, "can't convert %s into Float",
		 StringValuePtr(s));
    }
    return f_to_f(dat->real);
}

static VALUE
nucomp_to_r(VALUE self)
{
    get_dat1(self);

    if (k_float_p(dat->image) || !f_zero_p(dat->image)) {
	VALUE s = f_to_s(self);
	rb_raise(rb_eRangeError, "can't convert %s into Rational",
		 StringValuePtr(s));
    }
    return f_to_r(dat->real);
}

static VALUE
nilclass_to_c(VALUE self)
{
    return rb_complex_new1(INT2FIX(0));
}

static VALUE
numeric_to_c(VALUE self)
{
    return rb_complex_new1(self);
}

static VALUE comp_pat0, comp_pat1, comp_pat2, a_slash, a_dot_and_an_e,
    null_string, underscores_pat, an_underscore;

#define WS "\\s*"
#define DIGITS "(?:\\d(?:_\\d|\\d)*)"
#define NUMERATOR "(?:" DIGITS "?\\.)?" DIGITS "(?:[eE][-+]?" DIGITS ")?"
#define DENOMINATOR DIGITS
#define NUMBER "[-+]?" NUMERATOR "(?:\\/" DENOMINATOR ")?"
#define NUMBERNOS NUMERATOR "(?:\\/" DENOMINATOR ")?"
#define PATTERN0 "\\A" WS "(" NUMBER ")@(" NUMBER ")" WS
#define PATTERN1 "\\A" WS "([-+])?(" NUMBER ")?[iIjJ]" WS
#define PATTERN2 "\\A" WS "(" NUMBER ")(([-+])(" NUMBERNOS ")?[iIjJ])?" WS

static void
make_patterns(void)
{
    static const char comp_pat0_source[] = PATTERN0;
    static const char comp_pat1_source[] = PATTERN1;
    static const char comp_pat2_source[] = PATTERN2;
    static const char underscores_pat_source[] = "_+";

    if (comp_pat0) return;

    comp_pat0 = rb_reg_new(comp_pat0_source, sizeof comp_pat0_source - 1, 0);
    rb_gc_register_mark_object(comp_pat0);

    comp_pat1 = rb_reg_new(comp_pat1_source, sizeof comp_pat1_source - 1, 0);
    rb_gc_register_mark_object(comp_pat1);

    comp_pat2 = rb_reg_new(comp_pat2_source, sizeof comp_pat2_source - 1, 0);
    rb_gc_register_mark_object(comp_pat2);

    a_slash = rb_str_new2("/");
    rb_gc_register_mark_object(a_slash);

    a_dot_and_an_e = rb_str_new2(".eE");
    rb_gc_register_mark_object(a_dot_and_an_e);

    null_string = rb_str_new2("");
    rb_gc_register_mark_object(null_string);

    underscores_pat = rb_reg_new(underscores_pat_source,
				 sizeof underscores_pat_source - 1, 0);
    rb_gc_register_mark_object(underscores_pat);

    an_underscore = rb_str_new2("_");
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

#define id_include_p rb_intern("include?")
#define f_include_p(x,y) rb_funcall(x, id_include_p, 1, y)

#define id_count rb_intern("count")
#define f_count(x,y) rb_funcall(x, id_count, 1, y)

#define id_gsub_bang rb_intern("gsub!")
#define f_gsub_bang(x,y,z) rb_funcall(x, id_gsub_bang, 2, y, z)

static VALUE
string_to_c_internal(VALUE self)
{
    VALUE s;

    s = self;

    if (RSTRING_LEN(s) == 0)
	return rb_assoc_new(Qnil, self);

    {
	VALUE m, sr, si, re, r, i;
	int po;

	m = f_match(comp_pat0, s);
	if (!NIL_P(m)) {
	  sr = f_aref(m, INT2FIX(1));
	  si = f_aref(m, INT2FIX(2));
	  re = f_post_match(m);
	  po = 1;
	}
	if (NIL_P(m)) {
	    m = f_match(comp_pat1, s);
	    if (!NIL_P(m)) {
		sr = Qnil;
		si = f_aref(m, INT2FIX(1));
		if (NIL_P(si))
		    si = rb_str_new2("");
		{
		    VALUE t;

		    t = f_aref(m, INT2FIX(2));
		    if (NIL_P(t))
			t = rb_str_new2("1");
		    rb_str_concat(si, t);
		}
		re = f_post_match(m);
		po = 0;
	    }
	}
	if (NIL_P(m)) {
	    m = f_match(comp_pat2, s);
	    if (NIL_P(m))
		return rb_assoc_new(Qnil, self);
	    sr = f_aref(m, INT2FIX(1));
	    if (NIL_P(f_aref(m, INT2FIX(2))))
		si = Qnil;
	    else {
		VALUE t;

		si = f_aref(m, INT2FIX(3));
		t = f_aref(m, INT2FIX(4));
		if (NIL_P(t))
		    t = rb_str_new2("1");
		rb_str_concat(si, t);
	    }
	    re = f_post_match(m);
	    po = 0;
	}
	r = INT2FIX(0);
	i = INT2FIX(0);
	if (!NIL_P(sr)) {
	    if (f_include_p(sr, a_slash))
		r = f_to_r(sr);
	    else if (f_gt_p(f_count(sr, a_dot_and_an_e), INT2FIX(0)))
		r = f_to_f(sr);
	    else
		r = f_to_i(sr);
	}
	if (!NIL_P(si)) {
	    if (f_include_p(si, a_slash))
		i = f_to_r(si);
	    else if (f_gt_p(f_count(si, a_dot_and_an_e), INT2FIX(0)))
		i = f_to_f(si);
	    else
		i = f_to_i(si);
	}
	if (po)
	    return rb_assoc_new(rb_complex_polar(r, i), re);
	else
	    return rb_assoc_new(rb_complex_new2(r, i), re);

    }
}

static VALUE
string_to_c_strict(VALUE self)
{
    VALUE a = string_to_c_internal(self);
    if (NIL_P(RARRAY_PTR(a)[0]) || RSTRING_LEN(RARRAY_PTR(a)[1]) > 0) {
	VALUE s = f_inspect(self);
	rb_raise(rb_eArgError, "invalid value for Complex: %s",
		 StringValuePtr(s));
    }
    return RARRAY_PTR(a)[0];
}

#define id_gsub rb_intern("gsub")
#define f_gsub(x,y,z) rb_funcall(x, id_gsub, 2, y, z)

static VALUE
string_to_c(VALUE self)
{
    VALUE s, a, backref;

    backref = rb_backref_get();
    rb_match_busy(backref);

    s = f_gsub(self, underscores_pat, an_underscore);
    a = string_to_c_internal(s);

    rb_backref_set(backref);

    if (!NIL_P(RARRAY_PTR(a)[0]))
	return RARRAY_PTR(a)[0];
    return rb_complex_new1(INT2FIX(0));
}

static VALUE
nucomp_s_convert(int argc, VALUE *argv, VALUE klass)
{
    VALUE a1, a2, backref;

    rb_scan_args(argc, argv, "02", &a1, &a2);

    backref = rb_backref_get();
    rb_match_busy(backref);

    switch (TYPE(a1)) {
      case T_FIXNUM:
      case T_BIGNUM:
      case T_FLOAT:
	break;
      case T_STRING:
	a1 = string_to_c_strict(a1);
	break;
    }

    switch (TYPE(a2)) {
      case T_FIXNUM:
      case T_BIGNUM:
      case T_FLOAT:
	break;
      case T_STRING:
	a2 = string_to_c_strict(a2);
	break;
    }

    rb_backref_set(backref);

    switch (TYPE(a1)) {
      case T_COMPLEX:
	{
	    get_dat1(a1);

	    if (!k_float_p(dat->image) && f_zero_p(dat->image))
		a1 = dat->real;
	}
    }

    switch (TYPE(a2)) {
      case T_COMPLEX:
	{
	    get_dat1(a2);

	    if (!k_float_p(dat->image) && f_zero_p(dat->image))
		a2 = dat->real;
	}
    }

    switch (TYPE(a1)) {
      case T_COMPLEX:
	if (NIL_P(a2) || f_zero_p(a2))
	    return a1;
    }

    {
	VALUE argv2[2];
	argv2[0] = a1;
	argv2[1] = a2;
	return nucomp_s_new(argc, argv2, klass);
    }
}

/* --- */

#define id_Complex rb_intern("Complex")

static VALUE
numeric_re(VALUE self)
{
    return rb_Complex1(self);
}

static VALUE
numeric_im(VALUE self)
{
    return rb_Complex2(ZERO, self);
}

static VALUE
numeric_real(VALUE self)
{
    return self;
}

static VALUE
numeric_image(VALUE self)
{
    return INT2FIX(0);
}

static VALUE
numeric_abs2(VALUE self)
{
    return f_mul(self, self);
}

#define id_PI rb_intern("PI")

static VALUE
numeric_arg(VALUE self)
{
    if (!f_negative_p(self))
	return INT2FIX(0);
    return rb_const_get(rb_mMath, id_PI);
}

static VALUE
numeric_rect(VALUE self)
{
    return rb_assoc_new(self, ZERO);
}

static VALUE
numeric_polar(VALUE self)
{
    return rb_assoc_new(f_abs(self), f_arg(self));
}

static VALUE
numeric_conjugate(VALUE self)
{
    return self;
}

void
Init_Complex(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    assert(fprintf(stderr, "assert() is now active\n"));

    id_Unify = rb_intern("Unify");
    id_abs = rb_intern("abs");
    id_abs2 = rb_intern("abs2");
    id_arg = rb_intern("arg");
    id_cmp = rb_intern("<=>");
    id_conjugate = rb_intern("conjugate");
    id_convert = rb_intern("convert");
    id_denominator = rb_intern("denominator");
    id_divmod = rb_intern("divmod");
    id_equal_p = rb_intern("==");
    id_exact_p = rb_intern("exact?");
    id_expt = rb_intern("**");
    id_floor = rb_intern("floor");
    id_hash = rb_intern("hash");
    id_idiv = rb_intern("div");
    id_inspect = rb_intern("inspect");
    id_negate = rb_intern("-@");
    id_new = rb_intern("new");
    id_new_bang = rb_intern("new!");
    id_numerator = rb_intern("numerator");
    id_polar = rb_intern("polar");
    id_quo = rb_intern("quo");
    id_scalar_p = rb_intern("scalar?");
    id_to_f = rb_intern("to_f");
    id_to_i = rb_intern("to_i");
    id_to_r = rb_intern("to_r");
    id_to_s = rb_intern("to_s");
    id_truncate = rb_intern("truncate");

    rb_cComplex = rb_define_class(COMPLEX_NAME, rb_cNumeric);

    rb_define_alloc_func(rb_cComplex, nucomp_s_alloc);
    rb_funcall(rb_cComplex, rb_intern("private_class_method"), 1,
	       ID2SYM(rb_intern("allocate")));

    rb_define_singleton_method(rb_cComplex, "new!", nucomp_s_new_bang, -1);
    rb_funcall(rb_cComplex, rb_intern("private_class_method"), 1,
	       ID2SYM(rb_intern("new!")));

    rb_define_singleton_method(rb_cComplex, "new", nucomp_s_new, -1);
    rb_funcall(rb_cComplex, rb_intern("private_class_method"), 1,
	       ID2SYM(rb_intern("new")));

    rb_define_singleton_method(rb_cComplex, "rectangular", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "rect", nucomp_s_new, -1);
    rb_define_singleton_method(rb_cComplex, "polar", nucomp_s_polar, 2);

    rb_define_global_function(COMPLEX_NAME, nucomp_f_complex, -1);

    rb_undef_method(rb_cComplex, "<");
    rb_undef_method(rb_cComplex, "<=");
    rb_undef_method(rb_cComplex, "<=>");
    rb_undef_method(rb_cComplex, ">");
    rb_undef_method(rb_cComplex, ">=");
    rb_undef_method(rb_cComplex, "between?");
    rb_undef_method(rb_cComplex, "divmod");
    rb_undef_method(rb_cComplex, "floor");
    rb_undef_method(rb_cComplex, "ceil");
    rb_undef_method(rb_cComplex, "modulo");
    rb_undef_method(rb_cComplex, "round");
    rb_undef_method(rb_cComplex, "step");
    rb_undef_method(rb_cComplex, "truncate");

#if NUBY
    rb_undef_method(rb_cComplex, "//");
#endif

    rb_define_method(rb_cComplex, "real", nucomp_real, 0);
    rb_define_method(rb_cComplex, "image", nucomp_image, 0);
    rb_define_method(rb_cComplex, "imag", nucomp_image, 0);

    rb_define_method(rb_cComplex, "-@", nucomp_negate, 0);
    rb_define_method(rb_cComplex, "+", nucomp_add, 1);
    rb_define_method(rb_cComplex, "-", nucomp_sub, 1);
    rb_define_method(rb_cComplex, "*", nucomp_mul, 1);
    rb_define_method(rb_cComplex, "/", nucomp_div, 1);
    rb_define_method(rb_cComplex, "quo", nucomp_quo, 1);
    rb_define_method(rb_cComplex, "fdiv", nucomp_fdiv, 1);
    rb_define_method(rb_cComplex, "**", nucomp_expt, 1);

    rb_define_method(rb_cComplex, "==", nucomp_equal_p, 1);
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
    rb_define_method(rb_cComplex, "conjugate", nucomp_conjugate, 0);
    rb_define_method(rb_cComplex, "conj", nucomp_conjugate, 0);
#if 0
    rb_define_method(rb_cComplex, "~", nucomp_conjugate, 0); /* gcc */
#endif

#if 0
    rb_define_method(rb_cComplex, "real?", nucomp_false, 0);
    rb_define_method(rb_cComplex, "complex?", nucomp_true, 0);
    rb_define_method(rb_cComplex, "exact?", nucomp_exact_p, 0);
    rb_define_method(rb_cComplex, "inexact?", nucomp_inexact_p, 0);
#endif
    rb_define_method(rb_cComplex, "scalar?", nucomp_false, 0);

    rb_define_method(rb_cComplex, "numerator", nucomp_numerator, 0);
    rb_define_method(rb_cComplex, "denominator", nucomp_denominator, 0);

    rb_define_method(rb_cComplex, "hash", nucomp_hash, 0);
    rb_define_method(rb_cComplex, "eql?", nucomp_eql_p, 1);

    rb_define_method(rb_cComplex, "to_s", nucomp_to_s, 0);
    rb_define_method(rb_cComplex, "inspect", nucomp_inspect, 0);

    rb_define_method(rb_cComplex, "marshal_dump", nucomp_marshal_dump, 0);
    rb_define_method(rb_cComplex, "marshal_load", nucomp_marshal_load, 1);

    /* --- */

    rb_define_method(rb_cComplex, "to_i", nucomp_to_i, 0);
    rb_define_method(rb_cComplex, "to_f", nucomp_to_f, 0);
    rb_define_method(rb_cComplex, "to_r", nucomp_to_r, 0);
    rb_define_method(rb_cNilClass, "to_c", nilclass_to_c, 0);
    rb_define_method(rb_cNumeric, "to_c", numeric_to_c, 0);

    make_patterns();

    rb_define_method(rb_cString, "to_c", string_to_c, 0);

    rb_define_singleton_method(rb_cComplex, "convert", nucomp_s_convert, -1);
    rb_funcall(rb_cComplex, rb_intern("private_class_method"), 1,
	       ID2SYM(rb_intern("convert")));

    /* --- */

    rb_define_method(rb_cNumeric, "re", numeric_re, 0);
    rb_define_method(rb_cNumeric, "im", numeric_im, 0);
    rb_define_method(rb_cNumeric, "real", numeric_real, 0);
    rb_define_method(rb_cNumeric, "image", numeric_image, 0);
    rb_define_method(rb_cNumeric, "imag", numeric_image, 0);
    rb_define_method(rb_cNumeric, "abs2", numeric_abs2, 0);
    rb_define_method(rb_cNumeric, "arg", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "angle", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "phase", numeric_arg, 0);
    rb_define_method(rb_cNumeric, "rectangular", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "rect", numeric_rect, 0);
    rb_define_method(rb_cNumeric, "polar", numeric_polar, 0);
    rb_define_method(rb_cNumeric, "conjugate", numeric_conjugate, 0);
    rb_define_method(rb_cNumeric, "conj", numeric_conjugate, 0);

    rb_define_const(rb_cComplex, "I",
		    f_complex_new_bang2(rb_cComplex, ZERO, ONE));
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
