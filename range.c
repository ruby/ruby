/**********************************************************************

  range.c -

  $Author$
  $Date$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-2002 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_cRange;
static ID id_cmp, id_succ, id_beg, id_end, id_excl;

#define EXCL(r) RTEST(rb_ivar_get((r), id_excl))
#define SET_EXCL(r,v) rb_ivar_set((r), id_excl, (v)?Qtrue:Qfalse)

static VALUE
range_check(args)
    VALUE *args;
{
    if (!FIXNUM_P(args[0]) && !rb_obj_is_kind_of(args[0], rb_cNumeric)) {
	rb_funcall(args[0], id_cmp, 1, args[1]);
	/* rb_funcall(args[0], id_succ, 0, 0); */
    }
    return Qnil;
}

static VALUE
range_failed()
{
    rb_raise(rb_eArgError, "bad value for range");
    return Qnil;		/* dummy */
}

static void
range_init(range, beg, end, exclude_end)
    VALUE range, beg, end;
    int exclude_end;
{
    VALUE args[2];

    args[0] = beg; args[1] = end;
    if (!FIXNUM_P(beg) || !FIXNUM_P(end)) {
	rb_rescue(range_check, (VALUE)args, range_failed, 0);
    }

    SET_EXCL(range, exclude_end);
    rb_ivar_set(range, id_beg, beg);
    rb_ivar_set(range, id_end, end);
}

VALUE
rb_range_new(beg, end, exclude_end)
    VALUE beg, end;
    int exclude_end;
{
    VALUE range = rb_obj_alloc(rb_cRange);

    range_init(range, beg, end, exclude_end);
    return range;
}

static VALUE
range_initialize(argc, argv, range)
    int argc;
    VALUE *argv;
    VALUE range;
{
    VALUE beg, end, flags;
    
    rb_scan_args(argc, argv, "21", &beg, &end, &flags);
    /* Ranges are immutable, so that they should be initialized only once. */
    if (rb_ivar_defined(range, id_beg)) {
	rb_name_error(rb_intern("initialize"), "`initialize' called twice");
    }
    range_init(range, beg, end, RTEST(flags));
    return Qnil;
}

static VALUE
range_exclude_end_p(range)
    VALUE range;
{
    return EXCL(range)?Qtrue:Qfalse;
}

static VALUE
range_eq(range, obj)
    VALUE range, obj;
{
    if (range == obj) return Qtrue;
    if (!rb_obj_is_kind_of(obj, rb_cRange)) return Qfalse;

    if (!rb_equal(rb_ivar_get(range, id_beg), rb_ivar_get(obj, id_beg)))
	return Qfalse;
    if (!rb_equal(rb_ivar_get(range, id_end), rb_ivar_get(obj, id_end)))
	return Qfalse;

    if (EXCL(range) != EXCL(obj)) return Qfalse;

    return Qtrue;
}

static int
r_eq(a, b)
    VALUE a, b;
{
    if (a == b) return Qtrue;

    if (rb_funcall(a, id_cmp, 1, b) == INT2FIX(0))
	return Qtrue;
    return Qfalse;
}

static int
r_lt(a, b)
    VALUE a, b;
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (rb_cmpint(r) < 0) return Qtrue;
    return Qfalse;
}

static int
r_le(a, b)
    VALUE a, b;
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (rb_cmpint(r) <= 0) return Qtrue;
    return Qfalse;
}

static int
r_gt(a,b)
    VALUE a, b;
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (rb_cmpint(r) > 0) return Qtrue;
    return Qfalse;
}

static VALUE
range_eql(range, obj)
    VALUE range, obj;
{
    if (range == obj) return Qtrue;
    if (!rb_obj_is_kind_of(obj, rb_cRange)) return Qfalse;

    if (!rb_eql(rb_ivar_get(range, id_beg), rb_ivar_get(obj, id_beg)))
	return Qfalse;
    if (!rb_eql(rb_ivar_get(range, id_end), rb_ivar_get(obj, id_end)))
	return Qfalse;

    if (EXCL(range) != EXCL(obj)) return Qfalse;

    return Qtrue;
}

static VALUE
range_hash(range)
    VALUE range;
{
    long hash = EXCL(range);
    VALUE v;

    v = rb_hash(rb_ivar_get(range, id_beg));
    hash ^= v << 1;
    v = rb_hash(rb_ivar_get(range, id_end));
    hash ^= v << 9;
    hash ^= EXCL(range) << 24;

    return INT2FIX(hash);
}

static VALUE
str_step(args)
    VALUE *args;
{
    return rb_str_upto(args[0], args[1], EXCL(args[2]));
}

static VALUE
step_i(i, iter)
    VALUE i;
    long *iter;
{
    iter[0]--;
    if (iter[0] == 0) {
	rb_yield(i);
	iter[0] = iter[1];
    }
    return Qnil;
}

static void
range_each_func(range, func, v, e, arg)
    VALUE range;
    void (*func) _((VALUE, void*));
    void *arg;
{
    if (EXCL(range)) {
	while (r_lt(v, e)) {
	    if (r_eq(v, e)) break;
	    (*func)(v, arg);
	    v = rb_funcall(v, id_succ, 0, 0);
	}
    }
    else {
	while (r_le(v, e)) {
	    (*func)(v, arg);
	    if (r_eq(v, e)) break;
	    v = rb_funcall(v, id_succ, 0, 0);
	}
    }
}

static VALUE
range_step(argc, argv, range)
    int argc;
    VALUE *argv;
    VALUE range;
{
    VALUE b, e, step;
    long unit;

    b = rb_ivar_get(range, id_beg);
    e = rb_ivar_get(range, id_end);
    if (rb_scan_args(argc, argv, "01", &step) == 0) {
	step = INT2FIX(1);
    }

    unit = NUM2LONG(step);
    if (unit <= 0) {
	rb_raise(rb_eArgError, "step can't be <= 0");
    }
    if (FIXNUM_P(b) && FIXNUM_P(e)) { /* fixnums are special */
	long end = FIX2LONG(e);
	long i;

	if (!EXCL(range)) end += 1;
	for (i=FIX2LONG(b); i<end; i+=unit) {
	    rb_yield(INT2NUM(i));
	}
    }
    else if (rb_obj_is_kind_of(b, rb_cNumeric)) {
	ID c = rb_intern(EXCL(range) ? "<" : "<=");

	while (RTEST(rb_funcall(b, c, 1, e))) {
	    rb_yield(b);
	    b = rb_funcall(b, '+', 1, step);
	}
    }
    else if (TYPE(b) == T_STRING) {
	VALUE args[5];
	long iter[2];

	args[0] = b; args[1] = e; args[2] = range;
	iter[0] = 1; iter[1] = unit;
	rb_iterate((VALUE(*)_((VALUE)))str_step, (VALUE)args, step_i, (VALUE)iter);
    }
    else {
	long args[2];

	if (!rb_respond_to(b, id_succ)) {
	    rb_raise(rb_eTypeError, "cannot iterate from %s",
		     rb_class2name(CLASS_OF(b)));
	}
	args[0] = 1;
	args[1] = unit;
	range_each_func(range, step_i, b, e, args);
    }
    return range;
}

static void
each_i(v, arg)
    VALUE v;
    void *arg;
{
    rb_yield(v);
}

static VALUE
range_each(range)
    VALUE range;
{
    VALUE beg, end;

    beg = rb_ivar_get(range, id_beg);
    end = rb_ivar_get(range, id_end);

    if (!rb_respond_to(beg, id_succ)) {
	rb_raise(rb_eTypeError, "cannot iterate from %s",
		 rb_class2name(CLASS_OF(beg)));
    }
    if (TYPE(beg) == T_STRING) {
	VALUE args[5];
	long iter[2];

	args[0] = beg; args[1] = end; args[2] = range;
	iter[0] = 1; iter[1] = 1;
	rb_iterate((VALUE(*)_((VALUE)))str_step, (VALUE)args, step_i, (VALUE)iter);
    }
    else {
	range_each_func(range, each_i, beg, end, 0);
    }
    return range;
}

static VALUE
range_first(range)
    VALUE range;
{
    return rb_ivar_get(range, id_beg);
}

static VALUE
range_last(range)
    VALUE range;
{
    return rb_ivar_get(range, id_end);
}

VALUE
rb_range_beg_len(range, begp, lenp, len, err)
    VALUE range;
    long *begp, *lenp;
    long len;
    int err;
{
    long beg, end, b, e;

    if (!rb_obj_is_kind_of(range, rb_cRange)) return Qfalse;

    beg = b = NUM2LONG(rb_ivar_get(range, id_beg));
    end = e = NUM2LONG(rb_ivar_get(range, id_end));

    if (beg < 0) {
	beg += len;
	if (beg < 0) goto out_of_range;
    }
    if (err == 0 || err == 2) {
	if (beg > len) goto out_of_range;
	if (end > len || (!EXCL(range) && end == len))
	    end = len;
    }
    if (end < 0) {
	end += len;
	if (end < 0) {
	    if (beg == 0 && end == -1 && !EXCL(range)) {
		len = 0;
		goto length_set;
	    }
	    goto out_of_range;
	}
    }
    len = end - beg;
    if (!EXCL(range)) len++;	/* include end point */
    if (len < 0) goto out_of_range;

  length_set:
    *begp = beg;
    *lenp = len;

    return Qtrue;

  out_of_range:
    if (err) {
	rb_raise(rb_eRangeError, "%ld..%s%ld out of range",
		 b, EXCL(range)? "." : "", e);
    }
    return Qnil;
}

static VALUE
range_min(range)
    VALUE range;

{
    VALUE b, e, step;
    long unit;

    b = rb_ivar_get(range, id_beg);
    e = rb_ivar_get(range, id_end);

    if (r_le(b, e)) return b;
    return e;
}

static VALUE
range_max(range)
    VALUE range;
{
    VALUE b, e, step;
    long unit;

    b = rb_ivar_get(range, id_beg);
    e = rb_ivar_get(range, id_end);

    if (r_gt(b, e)) return b;
    return e;
}

static VALUE
range_to_s(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_obj_as_string(rb_ivar_get(range, id_beg));
    str2 = rb_obj_as_string(rb_ivar_get(range, id_end));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range)?3:2);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return str;
}

static VALUE
range_inspect(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_inspect(rb_ivar_get(range, id_beg));
    str2 = rb_inspect(rb_ivar_get(range, id_end));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range)?3:2);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return str;
}

static void
member_i(v, args)
    VALUE v;
    VALUE *args;
{
    if (rb_equal(v, args[0])) {
	args[1] = Qtrue;
    }
}

static VALUE
range_member(range, val)
    VALUE range, val;
{
    VALUE beg, end;
    VALUE args[2];

    beg = rb_ivar_get(range, id_beg);
    end = rb_ivar_get(range, id_end);

    if (!rb_respond_to(beg, id_succ)) {
	rb_raise(rb_eTypeError, "cannot iterate from %s",
		 rb_class2name(CLASS_OF(beg)));
    }
    args[0] = val;
    args[1] = Qfalse;
    range_each_func(range, member_i, beg, end, args);
    return args[1];
}

static VALUE
range_include(range, val)
    VALUE range, val;
{
    VALUE beg, end;

    beg = rb_ivar_get(range, id_beg);
    end = rb_ivar_get(range, id_end);
    if (r_gt(beg, val)) return Qfalse;
    if (EXCL(range)) {
	if (r_lt(val, end)) return Qtrue;
    }
    else {
	if (r_le(val, end)) return Qtrue;
    }
    return Qfalse;
}

void
Init_Range()
{
    rb_cRange = rb_define_class("Range", rb_cObject);
    rb_include_module(rb_cRange, rb_mEnumerable);
    rb_define_method(rb_cRange, "initialize", range_initialize, -1);
    rb_define_method(rb_cRange, "==", range_eq, 1);
    rb_define_method(rb_cRange, "===", range_member, 1);
    rb_define_method(rb_cRange, "eql?", range_eql, 1);
    rb_define_method(rb_cRange, "hash", range_hash, 0);
    rb_define_method(rb_cRange, "each", range_each, 0);
    rb_define_method(rb_cRange, "step", range_step, -1);
    rb_define_method(rb_cRange, "first", range_first, 0);
    rb_define_method(rb_cRange, "last", range_last, 0);
    rb_define_method(rb_cRange, "begin", range_first, 0);
    rb_define_method(rb_cRange, "end", range_last, 0);
    rb_define_method(rb_cRange, "min", range_min, 0);
    rb_define_method(rb_cRange, "max", range_max, 0);
    rb_define_method(rb_cRange, "to_s", range_to_s, 0);
    rb_define_method(rb_cRange, "inspect", range_inspect, 0);
    rb_define_alias(rb_cRange,  "to_ary", "to_a");

    rb_define_method(rb_cRange, "exclude_end?", range_exclude_end_p, 0);

    rb_define_method(rb_cRange, "member?", range_member, 1);
    rb_define_method(rb_cRange, "include?", range_include, 1);

    id_cmp = rb_intern("<=>");
    id_succ = rb_intern("succ");
    id_beg = rb_intern("begin");
    id_end = rb_intern("end");
    id_excl = rb_intern("excl");
}
