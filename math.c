/**********************************************************************

  math.c -

  $Author$
  $Date$
  created at: Tue Jan 25 14:12:56 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include <math.h>
#include <errno.h>

VALUE rb_mMath;

#define Need_Float(x) (x) = rb_Float(x)
#define Need_Float2(x,y) do {\
    Need_Float(x);\
    Need_Float(y);\
} while (0)

static VALUE
math_atan2(obj, y, x)
    VALUE obj, x, y;
{
    Need_Float2(y, x);
    return rb_float_new(atan2(RFLOAT(y)->value, RFLOAT(x)->value));
}

static VALUE
math_cos(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(cos(RFLOAT(x)->value));
}

static VALUE
math_sin(obj, x)
    VALUE obj, x;
{
    Need_Float(x);

    return rb_float_new(sin(RFLOAT(x)->value));
}

static VALUE
math_tan(obj, x)
    VALUE obj, x;
{
    Need_Float(x);

    return rb_float_new(tan(RFLOAT(x)->value));
}

static VALUE
math_acos(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = acos(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("acos");
    }
    return rb_float_new(d);
}

static VALUE
math_asin(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = asin(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("asin");
    }
    return rb_float_new(d);
}

static VALUE
math_atan(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(atan(RFLOAT(x)->value));
}

#ifndef HAVE_COSH
double
cosh(x)
    double x;
{
    return (exp(x) + exp(-x)) / 2;
}
#endif

static VALUE
math_cosh(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    
    return rb_float_new(cosh(RFLOAT(x)->value));
}

#ifndef HAVE_SINH
double
sinh(x)
    double x;
{
    return (exp(x) - exp(-x)) / 2;
}
#endif

static VALUE
math_sinh(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(sinh(RFLOAT(x)->value));
}

#ifndef HAVE_TANH
double
tanh(x)
    double x;
{
    return sinh(x) / cosh(x);
}
#endif

static VALUE
math_tanh(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(tanh(RFLOAT(x)->value));
}

static VALUE
math_acosh(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = acosh(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("acosh");
    }
    return rb_float_new(d);
}

static VALUE
math_asinh(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(asinh(RFLOAT(x)->value));
}

static VALUE
math_atanh(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = atanh(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("atanh");
    }
    return rb_float_new(d);
}

static VALUE
math_exp(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(exp(RFLOAT(x)->value));
}

#if defined __CYGWIN__
# include <cygwin/version.h>
# if CYGWIN_VERSION_DLL_MAJOR < 1005
#  define nan(x) nan()
# endif
# define log(x) ((x) < 0.0 ? nan("") : log(x))
# define log10(x) ((x) < 0.0 ? nan("") : log10(x))
#endif

static VALUE
math_log(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = log(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("log");
    }
    return rb_float_new(d);
}

static VALUE
math_log10(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = log10(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("log10");
    }
    return rb_float_new(d);
}

static VALUE
math_sqrt(obj, x)
    VALUE obj, x;
{
    double d;

    Need_Float(x);
    errno = 0;
    d = sqrt(RFLOAT(x)->value);
    if (errno) {
	rb_sys_fail("sqrt");
    }
    return rb_float_new(d);
}

static VALUE
math_frexp(obj, x)
    VALUE obj, x;
{
    double d;
    int exp;

    Need_Float(x);
    
    d = frexp(RFLOAT(x)->value, &exp);
    return rb_assoc_new(rb_float_new(d), INT2NUM(exp));
}

static VALUE
math_ldexp(obj, x, n)
    VALUE obj, x, n;
{
    Need_Float(x);
    return rb_float_new(ldexp(RFLOAT(x)->value, NUM2INT(n)));
}

static VALUE
math_hypot(obj, x, y)
    VALUE obj, x, y;
{
    Need_Float2(x, y);
    return rb_float_new(hypot(RFLOAT(x)->value, RFLOAT(y)->value));
}

static VALUE
math_erf(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(erf(RFLOAT(x)->value));
}

static VALUE
math_erfc(obj, x)
    VALUE obj, x;
{
    Need_Float(x);
    return rb_float_new(erfc(RFLOAT(x)->value));
}

void
Init_Math()
{
    rb_mMath = rb_define_module("Math");

#ifdef M_PI
    rb_define_const(rb_mMath, "PI", rb_float_new(M_PI));
#else
    rb_define_const(rb_mMath, "PI", rb_float_new(atan(1.0)*4.0));
#endif

#ifdef M_E
    rb_define_const(rb_mMath, "E", rb_float_new(M_E));
#else
    rb_define_const(rb_mMath, "E", rb_float_new(exp(1.0)));
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
    rb_define_module_function(rb_mMath, "log", math_log, 1);
    rb_define_module_function(rb_mMath, "log10", math_log10, 1);
    rb_define_module_function(rb_mMath, "sqrt", math_sqrt, 1);

    rb_define_module_function(rb_mMath, "frexp", math_frexp, 1);
    rb_define_module_function(rb_mMath, "ldexp", math_ldexp, 2);

    rb_define_module_function(rb_mMath, "hypot", math_hypot, 2);

    rb_define_module_function(rb_mMath, "erf",  math_erf,  1);
    rb_define_module_function(rb_mMath, "erfc", math_erfc, 1);
}
