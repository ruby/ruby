/************************************************

  range.c -

  $Author$
  $Date$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

static VALUE cRange;
static ID id_upto, id_cmp;
static ID id_beg, id_end;

static VALUE
range_check(args)
    VALUE *args;
{
    rb_funcall(args[0], id_cmp, 1, args[1]);
    return Qnil;
}

static VALUE
range_failed()
{
    ArgError("bad value for range");
}

static VALUE
range_s_new(klass, first, last)
    VALUE klass, first, last;
{
    VALUE obj;
    VALUE args[2];

    args[0] = first; args[1] = last;
    rb_rescue(range_check, (VALUE)args, range_failed, 0);

    obj = obj_alloc(klass);

    rb_ivar_set(obj, id_beg, first);
    rb_ivar_set(obj, id_end, last);
    obj_call_init(obj);

    return obj;
}

VALUE
range_new(first, last)
    VALUE first, last;
{
    return range_s_new(cRange, first, last);
}

static VALUE
range_eqq(rng, obj)
    VALUE rng, obj;
{
    VALUE first, last;

    first = rb_ivar_get(rng, id_beg);
    last = rb_ivar_get(rng, id_end);

    if (FIXNUM_P(first) && FIXNUM_P(obj) && FIXNUM_P(last)) {
	if (FIX2INT(first) <= FIX2INT(obj) && FIX2INT(obj) <= FIX2INT(last)) {
	    return TRUE;
	}
	return FALSE;
    }
    else {
	if (RTEST(rb_funcall(first, rb_intern("<="), 1, obj)) &&
	    RTEST(rb_funcall(last, rb_intern(">="), 1, obj))) {
	    return TRUE;
	}
	return FALSE;
    }
}

struct upto_data {
    VALUE first;
    VALUE last;
};

static VALUE
range_upto(data)
    struct upto_data *data;
{
    return rb_funcall(data->first, id_upto, 1, data->last);
}

static VALUE
range_each(obj)
    VALUE obj;
{
    VALUE b, e;

    b = rb_ivar_get(obj, id_beg);
    e = rb_ivar_get(obj, id_end);

    if (FIXNUM_P(b)) {		/* fixnum is a special case(for performance) */
	num_upto(b, e);
    }
    else {
	struct upto_data data;

	data.first = b;
	data.last = e;

	rb_iterate(range_upto, (VALUE)&data, rb_yield, 0);
    }

    return Qnil;
}

static VALUE
range_first(obj)
    VALUE obj;
{
    VALUE b;

    b = rb_ivar_get(obj, id_beg);
    return b;
}

static VALUE
range_last(obj)
    VALUE obj;
{
    VALUE e;

    e = rb_ivar_get(obj, id_end);
    return e;
}

VALUE
range_beg_end(range, begp, endp)
    VALUE range;
    int *begp, *endp;
{
    VALUE first, last;

    if (!obj_is_kind_of(range, cRange)) return FALSE;

    first = rb_ivar_get(range, id_beg); *begp = NUM2INT(first);
    last = rb_ivar_get(range, id_end);   *endp = NUM2INT(last);
    return TRUE;
}

static VALUE
range_to_s(range)
    VALUE range;
{
    VALUE str, str2;

    str = obj_as_string(rb_ivar_get(range, id_beg));
    str2 = obj_as_string(rb_ivar_get(range, id_end));
    str_cat(str, "..", 2);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str;
}

static VALUE
range_inspect(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_inspect(rb_ivar_get(range, id_beg));
    str2 = rb_inspect(rb_ivar_get(range, id_end));
    str_cat(str, "..", 2);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str;
}

VALUE enum_length();

static VALUE
range_length(rng)
    VALUE rng;
{
    VALUE first, last;
    VALUE size;

    first = rb_ivar_get(rng, id_beg);
    last = rb_ivar_get(rng, id_end);

    if (RTEST(rb_funcall(first, '>', 1, last))) {
	return INT2FIX(0);
    }
    if (!obj_is_kind_of(first, cNumeric)) {
	return enum_length(rng);
    }
    size = rb_funcall(last, '-', 1, first);
    size = rb_funcall(size, '+', 1, INT2FIX(1));

    return size;
}

void
Init_Range()
{
    cRange = rb_define_class("Range", cObject);
    rb_include_module(cRange, mEnumerable);
    rb_define_singleton_method(cRange, "new", range_s_new, 2);
    rb_define_method(cRange, "===", range_eqq, 1);
    rb_define_method(cRange, "each", range_each, 0);
    rb_define_method(cRange, "first", range_first, 0);
    rb_define_method(cRange, "last", range_last, 0);
    rb_define_method(cRange, "to_s", range_to_s, 0);
    rb_define_method(cRange, "inspect", range_inspect, 0);

    rb_define_method(cRange, "length", range_length, 0);
    rb_define_method(cRange, "size", range_length, 0);

    id_upto = rb_intern("upto");
    id_cmp = rb_intern("<=>");
    id_beg = rb_intern("first");
    id_end = rb_intern("last");
}
