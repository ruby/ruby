/************************************************

  range.c -

  $Author$
  $Date$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE rb_cRange;
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
    rb_raise(rb_eArgError, "bad value for range");
}

static VALUE
range_s_new(klass, beg, end)
    VALUE klass, beg, end;
{
    VALUE obj;

    if (!FIXNUM_P(beg) || !FIXNUM_P(end)) {
	VALUE args[2];

	args[0] = beg; args[1] = end;
	rb_rescue(range_check, (VALUE)args, range_failed, 0);
    }

    obj = rb_obj_alloc(klass);

    rb_ivar_set(obj, id_beg, beg);
    rb_ivar_set(obj, id_end, end);
    rb_obj_call_init(obj);

    return obj;
}

VALUE
rb_range_new(beg, end)
    VALUE beg, end;
{
    return range_s_new(rb_cRange, beg, end);
}

static VALUE
range_eqq(rng, obj)
    VALUE rng, obj;
{
    VALUE beg, end;

    beg = rb_ivar_get(rng, id_beg);
    end = rb_ivar_get(rng, id_end);

    if (FIXNUM_P(beg) && FIXNUM_P(obj) && FIXNUM_P(end)) {
	if (FIX2INT(beg) <= FIX2INT(obj) && FIX2INT(obj) <= FIX2INT(end)) {
	    return Qtrue;
	}
	return Qfalse;
    }
    else {
	if (RTEST(rb_funcall(beg, rb_intern("<="), 1, obj)) &&
	    RTEST(rb_funcall(end, rb_intern(">="), 1, obj))) {
	    return Qtrue;
	}
	return Qfalse;
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
    return rb_funcall(data->beg, id_upto, 1, data->end);
}

static VALUE
range_each(obj)
    VALUE obj;
{
    VALUE b, e;

    b = rb_ivar_get(obj, id_beg);
    e = rb_ivar_get(obj, id_end);

    if (FIXNUM_P(b)) {		/* fixnum is a special case(for performance) */
	rb_fix_upto(b, e);
    }
    else {
	struct upto_data data;

	data.beg = b;
	data.end = e;

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
rb_range_beg_end(range, begp, endp)
    VALUE range;
    int *begp, *endp;
{
    VALUE beg, end;

    if (!rb_obj_is_kind_of(range, rb_cRange)) return Qfalse;

    beg = rb_ivar_get(range, id_beg); *begp = NUM2INT(beg);
    end = rb_ivar_get(range, id_end);   *endp = NUM2INT(end);
    return Qtrue;
}

static VALUE
range_to_s(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_obj_as_string(rb_ivar_get(range, id_beg));
    str2 = rb_obj_as_string(rb_ivar_get(range, id_end));
    rb_str_cat(str, "..", 2);
    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str;
}

static VALUE
range_inspect(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_inspect(rb_ivar_get(range, id_beg));
    str2 = rb_inspect(rb_ivar_get(range, id_end));
    rb_str_cat(str, "..", 2);
    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str;
}

static VALUE
range_length(rng)
    VALUE rng;
{
    VALUE beg, end;
    VALUE size;

    beg = rb_ivar_get(rng, id_beg);
    end = rb_ivar_get(rng, id_end);

    if (RTEST(rb_funcall(beg, '>', 1, end))) {
	return INT2FIX(0);
    }
    if (!rb_obj_is_kind_of(beg, rb_cNumeric)) {
	return rb_enum_length(rng);
    }
    size = rb_funcall(end, '-', 1, beg);
    size = rb_funcall(size, '+', 1, INT2FIX(1));

    return size;
}

void
Init_Range()
{
    rb_cRange = rb_define_class("Range", rb_cObject);
    rb_include_module(rb_cRange, rb_mEnumerable);
    rb_define_singleton_method(rb_cRange, "new", range_s_new, 2);
    rb_define_method(rb_cRange, "===", range_eqq, 1);
    rb_define_method(rb_cRange, "each", range_each, 0);
    rb_define_method(rb_cRange, "first", range_first, 0);
    rb_define_method(rb_cRange, "last", range_last, 0);
    rb_define_method(rb_cRange, "begin", range_first, 0);
    rb_define_method(rb_cRange, "end", range_last, 0);
    rb_define_method(rb_cRange, "to_s", range_to_s, 0);
    rb_define_method(rb_cRange, "inspect", range_inspect, 0);

    rb_define_method(rb_cRange, "length", range_length, 0);
    rb_define_method(rb_cRange, "size", range_length, 0);

    id_upto = rb_intern("upto");
    id_cmp = rb_intern("<=>");
    id_beg = rb_intern("begin");
    id_end = rb_intern("end");
}
