/**********************************************************************

  compar.c -

  $Author$
  $Date$
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_mComparable;

static ID cmp;

int
rb_cmpint(val)
    VALUE val;
{
    if (FIXNUM_P(val)) return FIX2INT(val);
    if (TYPE(val) == T_BIGNUM) {
	if (RBIGNUM(val)->sign) return 1;
	return -1;
    }
    if (RTEST(rb_funcall(val, '>', 1, INT2FIX(0)))) return 1;
    if (RTEST(rb_funcall(val, '<', 1, INT2FIX(0)))) return -1;
    return 0;
}

static VALUE
cmp_equal(x, y)
    VALUE x, y;
{
    int c;

    if (x == y) return Qtrue;
    c  = rb_funcall(x, cmp, 1, y);
    if (NIL_P(c)) return Qfalse;
    if (c == INT2FIX(0)) return Qtrue;
    if (rb_cmpint(c) == 0) return Qtrue;
    return Qfalse;
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
