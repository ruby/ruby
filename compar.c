/************************************************

  compar.c -

  $Author: matz $
  $Date: 1994/10/14 06:19:05 $
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE M_Comparable;

static ID cmp;

static VALUE
Fcmp_eq(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t == 0) return TRUE;
    return FALSE;
}

static VALUE
Fcmp_gt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t > 0) return y;
    return FALSE;
}

static VALUE
Fcmp_ge(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t >= 0) return y;
    return FALSE;
}

static VALUE
Fcmp_lt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t < 0) return y;
    return FALSE;
}

static VALUE
Fcmp_le(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t <= 0) return y;
    return FALSE;
}

static VALUE
Fcmp_between(x, min, max)
    VALUE x, min, max;
{
    VALUE c = rb_funcall(x, cmp, 1, min);
    int t = NUM2INT(c);
    if (t < 0) return FALSE;

    c = rb_funcall(x, cmp, 1, min);
    t = NUM2INT(c);
    if (t > 0) return FALSE;
    return TRUE;
}

Init_Comparable()
{
    M_Comparable = rb_define_module("Comparable");
    rb_define_method(M_Comparable, "==", Fcmp_eq, 1);
    rb_define_method(M_Comparable, ">", Fcmp_gt, 1);
    rb_define_method(M_Comparable, ">=", Fcmp_ge, 1);
    rb_define_method(M_Comparable, "<", Fcmp_lt, 1);
    rb_define_method(M_Comparable, "<=", Fcmp_le, 1);
    rb_define_method(M_Comparable, "between", Fcmp_between, 2);

    cmp = rb_intern("<=>");
}
