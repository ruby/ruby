/************************************************

  compar.c -

  $Author$
  $Date$
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE mComparable;

static ID cmp;

static VALUE
cmp_eq(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t == 0) return TRUE;
    return FALSE;
}

static VALUE
cmp_gt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t > 0) return TRUE;
    return FALSE;
}

static VALUE
cmp_ge(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t >= 0) return TRUE;
    return FALSE;
}

static VALUE
cmp_lt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t < 0) return TRUE;
    return FALSE;
}

static VALUE
cmp_le(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t <= 0) return TRUE;
    return FALSE;
}

static VALUE
cmp_between(x, min, max)
    VALUE x, min, max;
{
    VALUE c = rb_funcall(x, cmp, 1, min);
    int t = NUM2INT(c);
    if (t < 0) return FALSE;

    c = rb_funcall(x, cmp, 1, max);
    t = NUM2INT(c);
    if (t > 0) return FALSE;
    return TRUE;
}

void
Init_Comparable()
{
    mComparable = rb_define_module("Comparable");
    rb_define_method(mComparable, "==", cmp_eq, 1);
    rb_define_method(mComparable, ">", cmp_gt, 1);
    rb_define_method(mComparable, ">=", cmp_ge, 1);
    rb_define_method(mComparable, "<", cmp_lt, 1);
    rb_define_method(mComparable, "<=", cmp_le, 1);
    rb_define_method(mComparable, "between?", cmp_between, 2);

    cmp = rb_intern("<=>");
}
