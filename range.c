/************************************************

  range.c -

  $Author: matz $
  $Date: 1994/12/06 09:30:12 $
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE mComparable;
static VALUE cRange;

static ID upto;

static VALUE
range_s_new(class, start, end)
    VALUE class, start, end;
{
    VALUE obj;

    if (!(FIXNUM_P(start) && FIXNUM_P(end))
	&& (TYPE(start) != TYPE(end)
	    || CLASS_OF(start) != CLASS_OF(end)
	    || !rb_responds_to(start, upto))) {
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
    return range_s_new(cRange, start, end);
}

static VALUE
range_match(rng, obj)
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

static VALUE
range_upto(data)
    struct upto_data *data;
{
    return rb_funcall(data->beg, upto, 1, data->end);
}

static VALUE
range_upto_yield(v)
    VALUE v;
{
    rb_yield(v);
    return Qnil;
}

static VALUE
range_each(obj)
    VALUE obj;
{
    VALUE b, e;

    b = rb_iv_get(obj, "start");
    e = rb_iv_get(obj, "end");

    if (FIXNUM_P(b)) {		/* fixnum is a special case(for performance) */
	num_upto(b, e);
    }
    else if (TYPE(b) == T_STRING) {
	str_upto(b, e);
    }
    else {
	struct upto_data data;

	data.beg = b;
	data.end = e;

	rb_iterate(range_upto, &data, range_upto_yield, Qnil);
    }

    return Qnil;
}

static VALUE
range_start(obj)
    VALUE obj;
{
    VALUE b;

    b = rb_iv_get(obj, "start");
    return b;
}

static VALUE
range_end(obj)
    VALUE obj;
{
    VALUE e;

    e = rb_iv_get(obj, "end");
    return e;
}

static VALUE
range_to_s(obj)
    VALUE obj;
{
    VALUE args[4];

    args[0] = str_new2("%d..%d");
    args[1] = rb_iv_get(obj, "start");
    args[2] = rb_iv_get(obj, "end");
    return f_sprintf(3, args);
}

VALUE
range_beg_end(range, begp, endp)
    VALUE range;
    int *begp, *endp;
{
    int beg, end;

    if (!obj_is_kind_of(range, cRange)) return FALSE;

    beg = rb_iv_get(range, "start"); *begp = NUM2INT(beg);
    end = rb_iv_get(range, "end");   *endp = NUM2INT(end);
    return TRUE;
}

extern VALUE mEnumerable;

void
Init_Range()
{
    cRange = rb_define_class("Range", cObject);
    rb_include_module(cRange, mEnumerable);
    rb_define_singleton_method(cRange, "new", range_s_new, 2);
    rb_define_method(cRange, "=~", range_match, 1);
    rb_define_method(cRange, "each", range_each, 0);
    rb_define_method(cRange, "start", range_start, 0);
    rb_define_method(cRange, "end", range_end, 0);
    rb_define_method(cRange, "to_s", range_to_s, 0);

    upto = rb_intern("upto");
}
