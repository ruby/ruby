/************************************************

  range.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE M_Comparable;
VALUE C_Range;

static ID next, eq;

VALUE
range_new(class, start, end)
    VALUE class, start, end;
{
    VALUE obj;

    if (!obj_is_kind_of(start, M_Comparable) || TYPE(start) != TYPE(end)) {
	Fail("bad value for range");
    }

    obj = obj_alloc(class);

    rb_iv_set(obj, "start", start);
    rb_iv_set(obj, "end", end);

    return obj;
}

static VALUE
Frng_match(rng, obj)
    VALUE rng, obj;
{
    VALUE beg, end;

    beg = rb_iv_get(rng, "start");
    end = rb_iv_get(rng, "end");

    if (FIXNUM_P(beg) && FIXNUM_P(obj)) {
	if (FIX2INT(beg) <= FIX2INT(obj) && FIX2INT(obj) <= FIX2INT(end)) {
	    return TRUE;
	}
	return FALSE;
    }
    else {
	if (rb_funcall(beg, rb_intern("<="), 1, obj) &&
	    rb_funcall(end, rb_intern(">="), 1, obj)) {
	    return TRUE;
	}
	return FALSE;
    }
}

static VALUE
Frng_each(obj)
    VALUE obj;
{
    VALUE b, e, current;

    b = rb_iv_get(obj, "start");
    e = rb_iv_get(obj, "end");

    if (FIXNUM_P(b)) {		/* fixnum is a special case(for performance) */
	int beg, end, i;

	beg = FIX2INT(b);
	end = FIX2INT(e);

	for (i=beg; i<=end; i++) {
	    rb_yield(INT2FIX(i));
	}
    }
    else {
	GC_LINK;
	GC_PRO3(current, b);
	for (;;) {
	    rb_yield(current);
	    if (rb_funcall(current, eq, 1, e)) break;
	    current = rb_funcall(current, next, 0);
	}
	GC_UNLINK;
    }

    return Qnil;
}

static VALUE
Frng_start(obj)
    VALUE obj;
{
    VALUE b;

    b = rb_iv_get(obj, "start");
    return b;
}

static VALUE
Frng_end(obj)
    VALUE obj;
{
    VALUE e;

    e = rb_iv_get(obj, "end");
    return e;
}

static VALUE
Frng_to_s(obj)
    VALUE obj;
{
    int beg, end;
    VALUE fmt, str, args[4];
    

    beg = rb_iv_get(obj, "start");
    end = rb_iv_get(obj, "end");

    GC_LINK;
    GC_PRO3(fmt, str_new2("%d..%d"));
    args[0] = obj; args[1] = fmt; args[2]= beg; args[3] = end;
    str = Fsprintf(4, args);
    GC_UNLINK;

    return str;
}

extern VALUE M_Enumerable;

Init_Range()
{
    C_Range = rb_define_class("Range", C_Object);
    rb_include_module(C_Range, M_Enumerable);
    rb_define_method(C_Range, "=~", Frng_match, 1);
    rb_define_method(C_Range, "each", Frng_each, 0);
    rb_define_method(C_Range, "start", Frng_start, 0);
    rb_define_method(C_Range, "end", Frng_end, 0);
    rb_define_method(C_Range, "to_s", Frng_to_s, 0);

    eq = rb_intern("==");
    next = rb_intern("next");
}
