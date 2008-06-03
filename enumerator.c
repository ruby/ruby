/************************************************

  enumerator.c - provides Enumerator class

  $Author$

  Copyright (C) 2001-2003 Akinori MUSHA

  $Idaemons: /home/cvs/rb/enumerator/enumerator.c,v 1.1.1.1 2001/07/15 10:12:48 knu Exp $
  $RoughId: enumerator.c,v 1.6 2003/07/27 11:03:24 nobu Exp $
  $Id$

************************************************/

#include "ruby.h"

/*
 * Document-class: Enumerable::Enumerator
 *
 * A class which provides a method `each' to be used as an Enumerable
 * object.
 */
VALUE rb_cEnumerator;
static VALUE sym_each;

VALUE rb_eStopIteration;

struct enumerator {
    VALUE obj;
    ID    meth;
    VALUE proc;
    VALUE args;
    rb_block_call_func *iter;
};

static void enumerator_mark _((void *));
static void
enumerator_mark(p)
    void *p;
{
    struct enumerator *ptr = p;
    rb_gc_mark(ptr->obj);
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
    if (!ptr || ptr->obj == Qundef) {
	rb_raise(rb_eArgError, "uninitialized enumerator");
    }
    return ptr;
}

/*
 *  call-seq:
 *    obj.to_enum(method = :each, *args)
 *    obj.enum_for(method = :each, *args)
 *
 *  Returns Enumerable::Enumerator.new(self, method, *args).
 *
 *  e.g.:
 *
 *     str = "xyz"
 *
 *     enum = str.enum_for(:each_byte)
 *     a = enum.map {|b| '%02x' % b } #=> ["78", "79", "7a"]
 *
 *     # protects an array from being modified
 *     a = [1, 2, 3]
 *     some_method(a.to_enum)
 *
 */
static VALUE
obj_to_enum(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE meth = sym_each;

    if (argc > 0) {
	--argc;
	meth = *argv++;
    }
    return rb_enumeratorize(obj, meth, argc, argv);
}

static VALUE
each_slice_i(val, memo)
    VALUE val;
    VALUE *memo;
{
    VALUE ary = memo[0];
    VALUE v = Qnil;
    long size = (long)memo[1];

    rb_ary_push(ary, val);

    if (RARRAY_LEN(ary) == size) {
	v = rb_yield(ary);
	memo[0] = rb_ary_new2(size);
    }

    return v;
}

/*
 *  call-seq:
 *    e.each_slice(n) {...}
 *    e.each_slice(n)
 *
 *  Iterates the given block for each slice of <n> elements.  If no
 *  block is given, returns an enumerator.
 *
 *  e.g.:
 *      (1..10).each_slice(3) {|a| p a}
 *      # outputs below
 *      [1, 2, 3]
 *      [4, 5, 6]
 *      [7, 8, 9]
 *      [10]
 *
 */
static VALUE
enum_each_slice(obj, n)
    VALUE obj, n;
{
    long size = NUM2LONG(n);
    VALUE args[2], ary;

    if (size <= 0) rb_raise(rb_eArgError, "invalid slice size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_block_call(obj, SYM2ID(sym_each), 0, 0, each_slice_i, (VALUE)args);

    ary = args[0];
    if (RARRAY_LEN(ary) > 0) rb_yield(ary);

    return Qnil;
}

static VALUE
each_cons_i(val, memo)
    VALUE val;
    VALUE *memo;
{
    VALUE ary = memo[0];
    VALUE v = Qnil;
    long size = (long)memo[1];

    if (RARRAY_LEN(ary) == size) {
	rb_ary_shift(ary);
    }
    rb_ary_push(ary, val);
    if (RARRAY_LEN(ary) == size) {
	v = rb_yield(rb_ary_dup(ary));
    }
    return v;
}

/*
 *  call-seq:
 *    each_cons(n) {...}
 *    each_cons(n)
 *
 *  Iterates the given block for each array of consecutive <n>
 *  elements.  If no block is given, returns an enumerator.a
 *
 *  e.g.:
 *      (1..10).each_cons(3) {|a| p a}
 *      # outputs below
 *      [1, 2, 3]
 *      [2, 3, 4]
 *      [3, 4, 5]
 *      [4, 5, 6]
 *      [5, 6, 7]
 *      [6, 7, 8]
 *      [7, 8, 9]
 *      [8, 9, 10]
 *
 */
static VALUE
enum_each_cons(obj, n)
    VALUE obj, n;
{
    long size = NUM2LONG(n);
    VALUE args[2];

    if (size <= 0) rb_raise(rb_eArgError, "invalid size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_block_call(obj, SYM2ID(sym_each), 0, 0, each_cons_i, (VALUE)args);

    return Qnil;
}

static VALUE enumerator_allocate _((VALUE));
static VALUE
enumerator_allocate(klass)
    VALUE klass;
{
    struct enumerator *ptr;
    VALUE enum_obj;

    enum_obj = Data_Make_Struct(klass, struct enumerator,
				enumerator_mark, -1, ptr);
    ptr->obj = Qundef;

    return enum_obj;
}

static VALUE enumerator_each_i _((VALUE, VALUE));
static VALUE
enumerator_each_i(v, enum_obj)
    VALUE v;
    VALUE enum_obj;
{
    return rb_yield(v);
}

static VALUE
enumerator_init(enum_obj, obj, meth, argc, argv)
    VALUE enum_obj;
    VALUE obj;
    VALUE meth;
    int argc;
    VALUE *argv;
{
    struct enumerator *ptr;

    Data_Get_Struct(enum_obj, struct enumerator, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr->obj  = obj;
    ptr->meth = rb_to_id(meth);
    ptr->iter = enumerator_each_i;
    if (argc) ptr->args = rb_ary_new4(argc, argv);

    return enum_obj;
}

/*
 *  call-seq:
 *    Enumerable::Enumerator.new(obj, method = :each, *args)
 *
 *  Creates a new Enumerable::Enumerator object, which is to be
 *  used as an Enumerable object using the given object's given
 *  method with the given arguments.
 *
 *  Use of this method is discouraged.  Use Kernel#enum_for() instead.
 */
static VALUE
enumerator_initialize(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE recv, meth = sym_each;

    if (argc == 0)
	rb_raise(rb_eArgError, "wrong number of argument (0 for 1)");
    recv = *argv++;
    if (--argc) {
	meth = *argv++;
	--argc;
    }
    return enumerator_init(obj, recv, meth, argc, argv);
}

/* :nodoc: */
static VALUE
enumerator_init_copy(obj, orig)
    VALUE obj;
    VALUE orig;
{
    struct enumerator *ptr0, *ptr1;

    ptr0 = enumerator_ptr(orig);

    Data_Get_Struct(obj, struct enumerator, ptr1);

    if (!ptr1) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr1->obj  = ptr0->obj;
    ptr1->meth = ptr0->meth;
    ptr1->iter = ptr0->iter;
    ptr1->args = ptr0->args;

    return obj;
}

VALUE
rb_enumeratorize(obj, meth, argc, argv)
    VALUE obj;
    VALUE meth;
    int argc;
    VALUE *argv;
{
    return enumerator_init(enumerator_allocate(rb_cEnumerator), obj, meth, argc, argv);
}

/*
 *  call-seq:
 *    enum.each {...}
 *
 *  Iterates the given block using the object and the method specified
 *  in the first place.  If no block is given, returns self.
 *
 */
static VALUE
enumerator_each(obj)
    VALUE obj;
{
    struct enumerator *e;
    int argc = 0;
    VALUE *argv = 0;

    if (!rb_block_given_p()) return obj;
    e = enumerator_ptr(obj);
    if (e->args) {
	argc = RARRAY_LEN(e->args);
	argv = RARRAY_PTR(e->args);
    }
    return rb_block_call(e->obj, e->meth, argc, argv, e->iter, (VALUE)e);
}

static VALUE
enumerator_with_index_i(val, memo)
    VALUE val;
    VALUE *memo;
{
    val = rb_yield_values(2, val, INT2FIX(*memo));
    ++*memo;
    return val;
}

/*
 *  call-seq:
 *    e.with_index {|(*args), idx| ... }
 *    e.with_index
 *
 *  Iterates the given block for each elements with an index, which
 *  start from 0.  If no block is given, returns an enumerator.
 *
 */
static VALUE
enumerator_with_index(obj)
    VALUE obj;
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE memo = 0;
    int argc = 0;
    VALUE *argv = 0;

    RETURN_ENUMERATOR(obj, 0, 0);
    if (e->args) {
	argc = RARRAY_LEN(e->args);
	argv = RARRAY_PTR(e->args);
    }
    return rb_block_call(e->obj, e->meth, argc, argv,
			 enumerator_with_index_i, (VALUE)&memo);
}

/*
 * call-seq:
 *   e.next   => object
 *
 * Returns the next object in the enumerator, and move the internal
 * position forward.  When the position reached at the end, internal
 * position is rewinded then StopIteration is raised.
 *
 * Note that enumeration sequence by next method does not affect other
 * non-external enumeration methods, unless underlying iteration
 * methods itself has side-effect, e.g. IO#each_line.
 *
 * Caution: Calling this method causes the "generator" library to be
 * loaded.
 */

static VALUE
enumerator_next(obj)
    VALUE obj;
{
    rb_require("generator");
    return rb_funcall(obj, rb_intern("next"), 0, 0);
}

/*
 * call-seq:
 *   e.rewind   => e
 *
 * Rewinds the enumeration sequence by the next method.
 */

static VALUE
enumerator_rewind(obj)
    VALUE obj;
{
    rb_require("generator");
    return rb_funcall(obj, rb_intern("rewind"), 0, 0);
}

void
Init_Enumerator()
{
    rb_define_method(rb_mKernel, "to_enum", obj_to_enum, -1);
    rb_define_method(rb_mKernel, "enum_for", obj_to_enum, -1);

    rb_define_method(rb_mEnumerable, "each_slice", enum_each_slice, 1);
    rb_define_method(rb_mEnumerable, "enum_slice", enum_each_slice, 1);
    rb_define_method(rb_mEnumerable, "each_cons", enum_each_cons, 1);
    rb_define_method(rb_mEnumerable, "enum_cons", enum_each_cons, 1);

    rb_cEnumerator = rb_define_class_under(rb_mEnumerable, "Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_define_alloc_func(rb_cEnumerator, enumerator_allocate);
    rb_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_define_method(rb_cEnumerator, "initialize_copy", enumerator_init_copy, 1);
    rb_define_method(rb_cEnumerator, "each", enumerator_each, 0);
    rb_define_method(rb_cEnumerator, "each_with_index", enumerator_with_index, 0);
    rb_define_method(rb_cEnumerator, "with_index", enumerator_with_index, 0);
    rb_define_method(rb_cEnumerator, "next", enumerator_next, 0);
    rb_define_method(rb_cEnumerator, "rewind", enumerator_rewind, 0);

    rb_eStopIteration   = rb_define_class("StopIteration", rb_eIndexError);

    sym_each	 	= ID2SYM(rb_intern("each"));

    rb_provide("enumerator.so");	/* for backward compatibility */
}
