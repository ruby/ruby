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
rb_cmpint(val, a, b)
    VALUE val, a, b;
{
    if (NIL_P(val)) {
	rb_cmperr(a, b);
    }
    if (FIXNUM_P(val)) return FIX2INT(val);
    if (TYPE(val) == T_BIGNUM) {
	if (RBIGNUM(val)->sign) return 1;
	return -1;
    }
    if (RTEST(rb_funcall(val, '>', 1, INT2FIX(0)))) return 1;
    if (RTEST(rb_funcall(val, '<', 1, INT2FIX(0)))) return -1;
    return 0;
}

void
rb_cmperr(x, y)
    VALUE x, y;
{
    const char *classname;

    if (SPECIAL_CONST_P(y)) {
	y = rb_inspect(y);
	classname = StringValuePtr(y);
    }
    else {
	classname = rb_obj_classname(y);
    }
    rb_raise(rb_eArgError, "comparison of %s with %s failed",
	     rb_obj_classname(x), classname);
}

#define cmperr() (rb_cmperr(x, y), Qnil)

static VALUE
cmp_eq(a)
    VALUE *a;
{
    VALUE c = rb_funcall(a[0], cmp, 1, a[1]);

    if (NIL_P(c)) return Qnil;
    if (rb_cmpint(c, a[0], a[1]) == 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_failed()
{
    return Qnil;
}

static VALUE
cmp_equal(x, y)
    VALUE x, y;
{
    VALUE a[2];

    if (x == y) return Qtrue;

    a[0] = x; a[1] = y;
    return rb_rescue(cmp_eq, (VALUE)a, cmp_failed, 0);
}

static VALUE
cmp_gt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return cmperr();
    if (rb_cmpint(c, x, y) > 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_ge(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return cmperr();
    if (rb_cmpint(c, x, y) >= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_lt(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return cmperr();
    if (rb_cmpint(c, x, y) < 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_le(x, y)
    VALUE x, y;
{
    VALUE c = rb_funcall(x, cmp, 1, y);

    if (NIL_P(c)) return cmperr();
    if (rb_cmpint(c, x, y) <= 0) return Qtrue;
    return Qfalse;
}

static VALUE
cmp_between(x, min, max)
    VALUE x, min, max;
{
    if (RTEST(cmp_lt(x, min))) return Qfalse;
    if (RTEST(cmp_gt(x, max))) return Qfalse;
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
