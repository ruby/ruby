/**********************************************************************

  compar.c -

  $Author$
  $Date$
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_mComparable;

static ID cmp;

static VALUE
cmp_eq(a)
    VALUE *a;
{
    VALUE c = rb_funcall(a[0], cmp, 1, a[1]);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c) == 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_failed()
{
    return Qfalse;
}

static VALUE
cmp_equal(x, y)
    VALUE x, y;
{
    VALUE a[2];

    if (x == y) return Qtrue;

    a[0] = x; a[1] = y;
    return rb_rescue2(cmp_eq, (VALUE)a, cmp_failed, 0,
		      rb_eStandardError, rb_eNameError, 0);
}

static VALUE
cmp_gt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c) > 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_ge(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c) >= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_lt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c) < 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_le(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c) <= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_between(x, min, max)
    VALUE x, min, max;
{
    if (cmp_lt(x, min)) return Qfalse;
    if (cmp_gt(x, max)) return Qfalse;
    return Qtrue;
}

void
Init_Comparable()
{
    rb_mComparable = rb_define_module("Comparable");
    rb_define_method(rb_mComparable, "==", cmp_equal, 1);
    rb_define_method(rb_mComparable, ">", cmp_gt, 1);
    rb_define_method(rb_mComparable, ">=", cmp_ge, 1);
    rb_define_method(rb_mComparable, "<", cmp_lt, 1);
    rb_define_method(rb_mComparable, "<=", cmp_le, 1);
    rb_define_method(rb_mComparable, "between?", cmp_between, 2);

    cmp = rb_intern("<=>");
}
