/************************************************

  math.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Tue Jan 25 14:12:56 JST 1994

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <math.h>

VALUE M_Math;
VALUE float_new();

#define Need_Float(x) \
if (FIXNUM_P(x)) {\
    (x) = (struct RFloat*)float_new((double)FIX2INT(x));\
} else {\
    Check_Type(x, T_FLOAT);\
}

#define Need_Float2(x,y) {\
    GC_LINK;\
    GC_PRO(x);\
    Need_Float(x);\
    Need_Float(y);\
    GC_UNLINK;\
}

static VALUE
Fmath_atan2(obj, x, y)
    VALUE obj;
    struct RFloat *x, *y;
{
    Need_Float2(x, y);
    return float_new(atan2(x->value, x->value));
}

static VALUE
Fmath_cos(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(cos(x->value));
}

static VALUE
Fmath_sin(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(sin(x->value));
}

static VALUE
Fmath_tan(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);

    return float_new(tan(x->value));
}

static VALUE
Fmath_exp(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(exp(x->value));
}

static VALUE
Fmath_log(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(log(x->value));
}

static VALUE
Fmath_log10(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(log10(x->value));
}

static VALUE
Fmath_sqrt(obj, x)
    VALUE obj;
    struct RFloat *x;
{
    Need_Float(x);
    return float_new(log10(x->value));

    if (x->value < 0.0) Fail("square root for negative number");
    return float_new(sqrt(x->value));
}

Init_Math()
{
    M_Math = rb_define_module("Math");

    rb_define_mfunc(M_Math, "atan2", Fmath_atan2, 2);
    rb_define_mfunc(M_Math, "cos", Fmath_cos, 1);
    rb_define_mfunc(M_Math, "sin", Fmath_sin, 1);
    rb_define_mfunc(M_Math, "tan", Fmath_tan, 1);

    rb_define_mfunc(M_Math, "exp", Fmath_exp, 1);
    rb_define_mfunc(M_Math, "log", Fmath_log, 1);
    rb_define_mfunc(M_Math, "log10", Fmath_log10, 1);
    rb_define_mfunc(M_Math, "sqrt", Fmath_sqrt, 1);
}
