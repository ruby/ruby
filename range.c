/************************************************

  range.c -

  $Author: matz $
  $Date: 1994/12/06 09:30:12 $
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE M_Comparable;
VALUE C_Range;

static ID next;

static VALUE
Srng_new(class, start, end)
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

VALUE
range_new(start, end)
    VALUE start, end;
{
    return Srng_new(C_Range, start, end);
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

struct upto_data {
    VALUE beg;
    VALUE end;
};

static rng_upto(data)
    struct upto_data *data;
{
    return rb_funcall(data->beg, rb_intern("upto"), 1, data->end);
}

static rng_upto_yield(v)
    VALUE v;
{
    rb_yield(v);
    return Qnil;
}

static VALUE
Frng_each(obj)
    VALUE obj;
{
    VALUE b, e, current;

    b = rb_iv_get(obj, "start");
    e = rb_iv_get(obj, "end");

    if (FIXNUM_P(b)) {		/* fixnum is a special case(for performance) */
	Fnum_upto(b, e);
    }
    else if (TYPE(b) == T_STRING) {
	Fstr_upto(b, e);
    }
    else {
	struct upto_data data;

	data.beg = b;
	data.end = e;

	rb_iterate(rng_upto, &data, rng_upto_yield, Qnil);
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
    VALUE args[4];

    args[0] = str_new2("%d..%d");
    args[1] = rb_iv_get(obj, "start");
    args[2] = rb_iv_get(obj, "end");
    return Fsprintf(3, args);
}

extern VALUE M_Enumerable;

Init_Range()
{
    C_Range = rb_define_class("Range", C_Object);
    rb_include_module(C_Range, M_Enumerable);
    rb_define_single_method(C_Range, "new", Srng_new, 2);
    rb_define_method(C_Range, "=~", Frng_match, 1);
    rb_define_method(C_Range, "each", Frng_each, 0);
    rb_define_method(C_Range, "start", Frng_start, 0);
    rb_define_method(C_Range, "end", Frng_end, 0);
    rb_define_method(C_Range, "to_s", Frng_to_s, 0);

    next = rb_intern("next");
}
