/************************************************

  math.c -

  $Author: matz $
  $Date: 1996/12/25 09:28:03 $
  created at: Tue Jan 25 14:12:56 JST 1994

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <math.h>

VALUE mMath;
VALUE float_new();
VALUE f_float();

#define Need_Float(x) \
if (FIXNUM_P(x)) {\
    (x) = (struct RFloat*)float_new((double)FIX2INT(x));\
} else {\
    (x) = (struct RFloat*)f_float(x, x);\
}

#define Need_Float2(x,y) {\
    Need_Float(x);\
    Need_Float(y);\
}

static VALUE
math_atan2(obj, x, y)
    VALUE obj;
    struct RFloat *x, *y;
{
    Need_Float2(x, y);
    return float_new(atan2(x->value, y->value));
}

static VALUE
math_cos(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(cos(x->value));
}

static VALUE
math_sin(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(sin(x->value));
}

static VALUE
math_tan(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(tan(x->value));
}

static VALUE
math_exp(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(exp(x->value));
}

static VALUE
math_log(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(log(x->value));
}

static VALUE
math_log10(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(log10(x->value));
}

static VALUE
math_sqrt(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    if (x->value < 0.0) ArgError("square root for negative number");
    return float_new(sqrt(x->value));
}

void
Init_Math()
{
    mMath = rb_define_module("Math");

#ifdef M_PI
    rb_define_const(mMath, "PI", float_new(M_PI));
#else
    rb_define_const(mMath, "PI", float_new(atan(1.0)*4.0));
#endif

#ifdef M_E
    rb_define_const(mMath, "E", float_new(M_E));
#else
    rb_define_const(mMath, "E", float_new(exp(1.0)));
#endif

    rb_define_module_function(mMath, "atan2", math_atan2, 2);
    rb_define_module_function(mMath, "cos", math_cos, 1);
    rb_define_module_function(mMath, "sin", math_sin, 1);
    rb_define_module_function(mMath, "tan", math_tan, 1);

    rb_define_module_function(mMath, "exp", math_exp, 1);
    rb_define_module_function(mMath, "log", math_log, 1);
    rb_define_module_function(mMath, "log10", math_log10, 1);
    rb_define_module_function(mMath, "sqrt", math_sqrt, 1);
}
