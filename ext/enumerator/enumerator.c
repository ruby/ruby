/************************************************

  enumerator.c - provides Enumerator class

  $Author$

  Copyright (C) 2001-2003 Akinori MUSHA

  $Idaemons: /home/cvs/rb/enumerator/enumerator.c,v 1.1.1.1 2001/07/15 10:12:48 knu Exp $
  $RoughId: enumerator.c,v 1.6 2003/07/27 11:03:24 nobu Exp $
  $Id$

************************************************/

#include "ruby.h"
#include "node.h"

static VALUE rb_cEnumerator;
static ID sym_each, sym_each_with_index, sym_each_slice, sym_each_cons;

static VALUE
proc_call(proc, args)
    VALUE proc, args;
{
    if (TYPE(args) != T_ARRAY) {
	args = rb_values_new(1, args);
    }
    return rb_proc_call(proc, args);
}

static VALUE
method_call(method, args)
    VALUE method, args;
{
    int argc = 0;
    VALUE *argv = 0;
    if (args) {
	argc = RARRAY(args)->len;
	argv = RARRAY(args)->ptr;
    }
    return rb_method_call(argc, argv, method);
}

struct enumerator {
    VALUE method;
    VALUE proc;
    VALUE args;
    VALUE (*iter)_((VALUE, struct enumerator *));
};

static void enumerator_mark _((void *));
static void
enumerator_mark(p)
    void *p;
{
    struct enumerator *ptr = p;
    rb_gc_mark(ptr->method);
    rb_gc_mark(ptr->proc);
    rb_gc_mark(ptr->args);
}

static struct enumerator *
enumerator_ptr(obj)
    VALUE obj;
{
    struct enumerator *ptr;

    Data_Get_Struct(obj, struct enumerator, ptr);
    if (RDATA(obj)->dmark != enumerator_mark) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %s (expected Enumerable::Enumerator)",
		 rb_obj_classname(obj));
    }
    if (!ptr) {
	rb_raise(rb_eArgError, "uninitialized enumerator");
    }
    return ptr;
}

static VALUE enumerator_iter_i _((VALUE, struct enumerator *));
static VALUE
enumerator_iter_i(i, e)
    VALUE i;
    struct enumerator *e;
{
    return rb_yield(proc_call(e->proc, i));
}

static VALUE
obj_to_enum(obj, enum_args)
    VALUE obj, enum_args;
{
    rb_ary_unshift(enum_args, obj);

    return rb_class_new_instance(RARRAY(enum_args)->len,
				 RARRAY(enum_args)->ptr,
				 rb_cEnumerator);
}

static VALUE
enumerator_enum_with_index(obj)
    VALUE obj;
{
    VALUE args[2];
    args[0] = obj;
    args[1] = sym_each_with_index;
    return rb_class_new_instance(2, args, rb_cEnumerator);
}

static VALUE
each_slice_i(val, memo)
    VALUE val;
    VALUE *memo;
{
    VALUE ary = memo[0];
    long size = (long)memo[1];

    rb_ary_push(ary, val);

    if (RARRAY(ary)->len == size) {
	rb_yield(ary);
	memo[0] = rb_ary_new2(size);
    }

    return Qnil;
}

static VALUE
enum_each_slice(obj, n)
    VALUE obj, n;
{
    long size = NUM2LONG(n);
    VALUE args[2], ary;

    if (size <= 0) rb_raise(rb_eArgError, "invalid slice size");

    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_iterate(rb_each, obj, each_slice_i, (VALUE)args);

    ary = args[0];
    if (RARRAY(ary)->len > 0) rb_yield(ary);

    return Qnil;
}

static VALUE
enumerator_enum_slice(obj, n)
    VALUE obj, n;
{
    VALUE args[2];
    args[0] = obj;
    args[1] = sym_each_slice;
    args[2] = n;
    return rb_class_new_instance(3, args, rb_cEnumerator);
}

static VALUE
each_cons_i(val, memo)
    VALUE val;
    VALUE *memo;
{
    VALUE ary = memo[0];
    long size = (long)memo[1];

    if (RARRAY(ary)->len == size) {
	rb_ary_shift(ary);
    }
    rb_ary_push(ary, val);
    if (RARRAY(ary)->len == size) {
	rb_yield(rb_ary_dup(ary));
    }
    return Qnil;
}

static VALUE
enum_each_cons(obj, n)
    VALUE obj, n;
{
    long size = NUM2LONG(n);
    VALUE args[2];

    if (size <= 0) rb_raise(rb_eArgError, "invalid size");
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_iterate(rb_each, obj, each_cons_i, (VALUE)args);

    return Qnil;
}

static VALUE
enumerator_enum_cons(obj, n)
    VALUE obj, n;
{
    VALUE args[2];
    args[0] = obj;
    args[1] = sym_each_cons;
    args[2] = n;
    return rb_class_new_instance(3, args, rb_cEnumerator);
}

static VALUE enumerator_allocate _((VALUE));
static VALUE
enumerator_allocate(klass)
    VALUE klass;
{
    struct enumerator *ptr;
    return Data_Make_Struct(rb_cEnumerator, struct enumerator,
			    enumerator_mark, -1, ptr);
}

static VALUE
enumerator_initialize(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE enum_obj, enum_method, enum_args;
    struct enumerator *ptr = enumerator_ptr(obj);

    rb_scan_args(argc, argv, "11*", &enum_obj, &enum_method, &enum_args);

    if (enum_method == Qnil)
	enum_method = sym_each;

    ptr->method = rb_obj_method(enum_obj, enum_method);
    if (rb_block_given_p()) {
	ptr->proc = rb_block_proc();
	ptr->iter = enumerator_iter_i;
    }
    else {
	ptr->iter = (VALUE (*) _((VALUE, struct enumerator *)))rb_yield;
    }
    ptr->args = enum_args;

    return obj;
}

static VALUE enumerator_iter _((VALUE));
static VALUE
enumerator_iter(memo)
    VALUE memo;
{
    struct enumerator *e = (struct enumerator *)memo;

    return method_call(e->method, e->args);
}

static VALUE
enumerator_each(obj)
    VALUE obj;
{
    struct enumerator *e = enumerator_ptr(obj);

    return rb_iterate(enumerator_iter, (VALUE)e, e->iter, (VALUE)e);
}

static VALUE
enumerator_with_index_i(val, memo)
    VALUE val, *memo;
{
    val = rb_yield_values(2, val, INT2FIX(*memo));
    ++*memo;
    return val;
}

static VALUE
enumerator_with_index(obj)
    VALUE obj;
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE memo = 0;

    return rb_iterate(enumerator_iter, (VALUE)e,
		      enumerator_with_index_i, (VALUE)&memo);
}

void
Init_enumerator()
{
    VALUE rb_mEnumerable;

    rb_define_method(rb_mKernel, "to_enum", obj_to_enum, -2);
    rb_define_method(rb_mKernel, "enum_for", obj_to_enum, -2);

    rb_mEnumerable = rb_path2class("Enumerable");

    rb_define_method(rb_mEnumerable, "enum_with_index", enumerator_enum_with_index, 0);
    rb_define_method(rb_mEnumerable, "each_slice", enum_each_slice, 1);
    rb_define_method(rb_mEnumerable, "enum_slice", enumerator_enum_slice, 1);
    rb_define_method(rb_mEnumerable, "each_cons", enum_each_cons, 1);
    rb_define_method(rb_mEnumerable, "enum_cons", enumerator_enum_cons, 1);

    rb_cEnumerator = rb_define_class_under(rb_mEnumerable, "Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_define_alloc_func(rb_cEnumerator, enumerator_allocate);
    rb_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_define_method(rb_cEnumerator, "each", enumerator_each, 0);
    rb_define_method(rb_cEnumerator, "with_index", enumerator_with_index, 0);

    sym_each		= ID2SYM(rb_intern("each"));
    sym_each_with_index	= ID2SYM(rb_intern("each_with_index"));
    sym_each_slice	= ID2SYM(rb_intern("each_slice"));
    sym_each_cons	= ID2SYM(rb_intern("each_cons"));
}
