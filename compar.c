/************************************************

  compar.c -

  $Author$
  $Date$
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE rb_mComparable;

static ID cmp;

static VALUE
cmp_eq(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t == 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_gt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t > 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_ge(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t >= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_lt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t < 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_le(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);
    int t = NUM2INT(c);

    if (t <= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_between(x, min, max)
    VALUE x, min, max;
{
    VALUE c = rb_funcall(x, cmp, 1, min);
    long t = NUM2LONG(c);
    if (t < 0) return Qfalse;

    c = rb_funcall(x, cmp, 1, max);
    t = NUM2LONG(c);
    if (t > 0) return Qfalse;
    return Qtrue;
}

void
Init_Comparable()
{
    rb_mComparable = rb_define_module("Comparable");
    rb_define_method(rb_mComparable, "==", cmp_eq, 1);
    rb_define_method(rb_mComparable, ">", cmp_gt, 1);
    rb_define_method(rb_mComparable, ">=", cmp_ge, 1);
    rb_define_method(rb_mComparable, "<", cmp_lt, 1);
    rb_define_method(rb_mComparable, "<=", cmp_le, 1);
    rb_define_method(rb_mComparable, "between?", cmp_between, 2);

    cmp = rb_intern("<=>");
}
