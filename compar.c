/************************************************

  compar.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE M_Comparable;

static ID cmp;

static VALUE
Fcmp_eq(this, other)
    VALUE this, other;
{
    VALUE c = rb_funcall(this, cmp, 1, other);
    int t = NUM2INT(c);

    if (t == 0) return TRUE;
    return FALSE;
}

static VALUE
Fcmp_gt(this, other)
    VALUE this, other;
{
    VALUE c = rb_funcall(this, cmp, 1, other);
    int t = NUM2INT(c);

    if (t > 0) return other;
    return FALSE;
}

static VALUE
Fcmp_ge(this, other)
    VALUE this, other;
{
    VALUE c = rb_funcall(this, cmp, 1, other);
    int t = NUM2INT(c);

    if (t >= 0) return other;
    return FALSE;
}

static VALUE
Fcmp_lt(this, other)
    VALUE this, other;
{
    VALUE c = rb_funcall(this, cmp, 1, other);
    int t = NUM2INT(c);

    if (t < 0) return other;
    return FALSE;
}

static VALUE
Fcmp_le(this, other)
    VALUE this, other;
{
    VALUE c = rb_funcall(this, cmp, 1, other);
    int t = NUM2INT(c);

    if (t <= 0) return other;
    return FALSE;
}

static VALUE
Fcmp_between(this, min, max)
    VALUE this, min, max;
{
    VALUE c = rb_funcall(this, cmp, 1, min);
    int t = NUM2INT(c);
    if (t < 0) return FALSE;

    c = rb_funcall(this, cmp, 1, min);
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
