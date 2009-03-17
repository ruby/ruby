/************************************************

  enumerator.c - provides Enumerator class

  $Author$

  Copyright (C) 2001-2003 Akinori MUSHA

  $Idaemons: /home/cvs/rb/enumerator/enumerator.c,v 1.1.1.1 2001/07/15 10:12:48 knu Exp $
  $RoughId: enumerator.c,v 1.6 2003/07/27 11:03:24 nobu Exp $
  $Id$

************************************************/

#include "ruby/ruby.h"

/*
 * Document-class: Enumerator
 *
 * A class which provides a method `each' to be used as an Enumerable
 * object.
 */
VALUE rb_cEnumerator;
static ID id_rewind, id_each;
static VALUE sym_each;

VALUE rb_eStopIteration;

struct enumerator {
    VALUE obj;
    ID    meth;
    VALUE args;
    VALUE fib;
    VALUE dst;
    VALUE no_next;
};

static VALUE rb_cGenerator, rb_cYielder;

struct generator {
    VALUE proc;
};

struct yielder {
    VALUE proc;
};

static VALUE generator_allocate(VALUE klass);
static VALUE generator_init(VALUE obj, VALUE proc);

/*
 * Enumerator
 */
static void
enumerator_mark(void *p)
{
    struct enumerator *ptr = p;
    rb_gc_mark(ptr->obj);
    rb_gc_mark(ptr->args);
    rb_gc_mark(ptr->fib);
    rb_gc_mark(ptr->dst);
}

static struct enumerator *
enumerator_ptr(VALUE obj)
{
    struct enumerator *ptr;

    Data_Get_Struct(obj, struct enumerator, ptr);
    if (RDATA(obj)->dmark != enumerator_mark) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %s (expected %s)",
		 rb_obj_classname(obj), rb_class2name(rb_cEnumerator));
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
 *  Returns Enumerator.new(self, method, *args).
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
obj_to_enum(int argc, VALUE *argv, VALUE obj)
{
    VALUE meth = sym_each;

    if (argc > 0) {
	--argc;
	meth = *argv++;
    }
    return rb_enumeratorize(obj, meth, argc, argv);
}

static VALUE
each_slice_i(VALUE val, VALUE *memo)
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
enum_each_slice(VALUE obj, VALUE n)
{
    long size = NUM2LONG(n);
    VALUE args[2], ary;

    if (size <= 0) rb_raise(rb_eArgError, "invalid slice size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_block_call(obj, id_each, 0, 0, each_slice_i, (VALUE)args);

    ary = args[0];
    if (RARRAY_LEN(ary) > 0) rb_yield(ary);

    return Qnil;
}

static VALUE
each_cons_i(VALUE val, VALUE *memo)
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
 *  elements.  If no block is given, returns an enumerator.
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
enum_each_cons(VALUE obj, VALUE n)
{
    long size = NUM2LONG(n);
    VALUE args[2];

    if (size <= 0) rb_raise(rb_eArgError, "invalid size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_block_call(obj, id_each, 0, 0, each_cons_i, (VALUE)args);

    return Qnil;
}

static VALUE
each_with_object_i(VALUE val, VALUE memo)
{
    return rb_yield_values(2, val, memo);
}

/*
 *  call-seq:
 *    each_with_object(obj) {|(*args), memo_obj| ... }
 *    each_with_object(obj)
 *
 *  Iterates the given block for each element with an arbitrary
 *  object given, and returns the initially given object.

 *  If no block is given, returns an enumerator.
 *
 *  e.g.:
 *      evens = (1..10).each_with_object([]) {|i, a| a << i*2 }
 *      # => [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
 *
 */
static VALUE
enum_each_with_object(VALUE obj, VALUE memo)
{
    RETURN_ENUMERATOR(obj, 1, &memo);

    rb_block_call(obj, id_each, 0, 0, each_with_object_i, memo);

    return memo;
}

static VALUE
enumerator_allocate(VALUE klass)
{
    struct enumerator *ptr;
    VALUE enum_obj;

    enum_obj = Data_Make_Struct(klass, struct enumerator, enumerator_mark, -1, ptr);
    ptr->obj = Qundef;

    return enum_obj;
}

static VALUE
enumerator_each_i(VALUE v, VALUE enum_obj, int argc, VALUE *argv)
{
    return rb_yield_values2(argc, argv);
}

static VALUE
enumerator_init(VALUE enum_obj, VALUE obj, VALUE meth, int argc, VALUE *argv)
{
    struct enumerator *ptr;

    Data_Get_Struct(enum_obj, struct enumerator, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr->obj  = obj;
    ptr->meth = rb_to_id(meth);
    if (argc) ptr->args = rb_ary_new4(argc, argv);
    ptr->fib = 0;
    ptr->dst = Qnil;
    ptr->no_next = Qfalse;

    return enum_obj;
}

/*
 *  call-seq:
 *    Enumerator.new(obj, method = :each, *args)
 *    Enumerator.new { |y| ... }
 *
 *  Creates a new Enumerator object, which is to be used as an
 *  Enumerable object iterating in a given way.
 *
 *  In the first form, a generated Enumerator iterates over the given
 *  object using the given method with the given arguments passed.
 *  Use of this form is discouraged.  Use Kernel#enum_for(), alias
 *  to_enum, instead.
 *
 *    e = Enumerator.new(ObjectSpace, :each_object)
 *        #-> ObjectSpace.enum_for(:each_object)
 *
 *    e.select { |obj| obj.is_a?(Class) }  #=> array of all classes
 *
 *  In the second form, iteration is defined by the given block, in
 *  which a "yielder" object given as block parameter can be used to
 *  yield a value by calling the +yield+ method, alias +<<+.
 *
 *    fib = Enumerator.new { |y|
 *      a = b = 1
 *      loop {
 *        y << a
 *        a, b = b, a + b
 *      }
 *    }
 *
 *    p fib.take(10) #=> [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
 */
static VALUE
enumerator_initialize(int argc, VALUE *argv, VALUE obj)
{
    VALUE recv, meth = sym_each;

    if (argc == 0) {
	if (!rb_block_given_p())
	    rb_raise(rb_eArgError, "wrong number of argument (0 for 1+)");

	recv = generator_init(generator_allocate(rb_cGenerator), rb_block_proc());
    } else {
	recv = *argv++;
	if (--argc) {
	    meth = *argv++;
	    --argc;
	}
    }

    return enumerator_init(obj, recv, meth, argc, argv);
}

/* :nodoc: */
static VALUE
enumerator_init_copy(VALUE obj, VALUE orig)
{
    struct enumerator *ptr0, *ptr1;

    ptr0 = enumerator_ptr(orig);
    if (ptr0->fib) {
	/* Fibers cannot be copied */
	rb_raise(rb_eTypeError, "can't copy execution context");
    }

    Data_Get_Struct(obj, struct enumerator, ptr1);

    if (!ptr1) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr1->obj  = ptr0->obj;
    ptr1->meth = ptr0->meth;
    ptr1->args = ptr0->args;
    ptr1->fib  = 0;

    return obj;
}

VALUE
rb_enumeratorize(VALUE obj, VALUE meth, int argc, VALUE *argv)
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
enumerator_each(VALUE obj)
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
    return rb_block_call(e->obj, e->meth, argc, argv,
			 enumerator_each_i, (VALUE)e);
}

static VALUE
enumerator_with_index_i(VALUE val, VALUE *memo, int argc, VALUE *argv)
{
    VALUE idx;

    idx = INT2FIX(*memo);
    ++*memo;

    if (argc <= 1)
	return rb_yield_values(2, val, idx);

    return rb_yield_values(2, rb_ary_new4(argc, argv), idx);
}

/*
 *  call-seq:
 *    e.with_index(offset = 0) {|(*args), idx| ... }
 *    e.with_index(offset = 0)
 *
 *  Iterates the given block for each element with an index, which
 *  starts from +offset+.  If no block is given, returns an enumerator.
 *
 */
static VALUE
enumerator_with_index(int argc, VALUE *argv, VALUE obj)
{
    struct enumerator *e;
    VALUE memo;

    rb_scan_args(argc, argv, "01", &memo);
    RETURN_ENUMERATOR(obj, argc, argv);
    memo = NIL_P(memo) ? 0 : (VALUE)NUM2LONG(memo);
    e = enumerator_ptr(obj);
    if (e->args) {
	argc = RARRAY_LEN(e->args);
	argv = RARRAY_PTR(e->args);
    }
    else {
	argc = 0;
	argv = NULL;
    }
    return rb_block_call(e->obj, e->meth, argc, argv,
			 enumerator_with_index_i, (VALUE)&memo);
}

/*
 *  call-seq:
 *    e.each_with_index {|(*args), idx| ... }
 *    e.each_with_index
 *
 *  Same as Enumeartor#with_index, except each_with_index does not
 *  receive an offset argument.
 *
 */
static VALUE
enumerator_each_with_index(VALUE obj)
{
    return enumerator_with_index(0, NULL, obj);
}

static VALUE
enumerator_with_object_i(VALUE val, VALUE memo, int argc, VALUE *argv)
{
    if (argc <= 1)
	return rb_yield_values(2, val, memo);

    return rb_yield_values(2, rb_ary_new4(argc, argv), memo);
}

/*
 *  call-seq:
 *    e.with_object(obj) {|(*args), memo_obj| ... }
 *    e.with_object(obj)
 *
 *  Iterates the given block for each element with an arbitrary
 *  object given, and returns the initially given object.
 *
 *  If no block is given, returns an enumerator.
 *
 */
static VALUE
enumerator_with_object(VALUE obj, VALUE memo)
{
    struct enumerator *e;
    int argc = 0;
    VALUE *argv = 0;

    RETURN_ENUMERATOR(obj, 1, &memo);
    e = enumerator_ptr(obj);
    if (e->args) {
	argc = RARRAY_LEN(e->args);
	argv = RARRAY_PTR(e->args);
    }
    rb_block_call(e->obj, e->meth, argc, argv,
		  enumerator_with_object_i, memo);

    return memo;
}

static VALUE
next_ii(VALUE i, VALUE obj, int argc, VALUE *argv)
{
    rb_fiber_yield(argc, argv);
    return Qnil;
}

static VALUE
next_i(VALUE curr, VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE nil = Qnil;

    rb_block_call(obj, id_each, 0, 0, next_ii, obj);
    e->no_next = Qtrue;
    return rb_fiber_yield(1, &nil);
}

static void
next_init(VALUE obj, struct enumerator *e)
{
    VALUE curr = rb_fiber_current();
    e->dst = curr;
    e->fib = rb_fiber_new(next_i, obj);
}

/*
 * call-seq:
 *   e.next   => object
 *
 * Returns the next object in the enumerator, and move the internal
 * position forward.  When the position reached at the end, internal
 * position is rewound then StopIteration is raised.
 *
 * Note that enumeration sequence by next method does not affect other
 * non-external enumeration methods, unless underlying iteration
 * methods itself has side-effect, e.g. IO#each_line.
 *
 */

static VALUE
enumerator_next(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE curr, v;
    curr = rb_fiber_current();

    if (!e->fib || !rb_fiber_alive_p(e->fib)) {
	next_init(obj, e);
    }

    v = rb_fiber_resume(e->fib, 1, &curr);
    if (e->no_next) {
	e->fib = 0;
	e->dst = Qnil;
	e->no_next = Qfalse;
	rb_raise(rb_eStopIteration, "iteration reached at end");
    }
    return v;
}

/*
 * call-seq:
 *   e.rewind   => e
 *
 * Rewinds the enumeration sequence by the next method.
 *
 * If the enclosed object responds to a "rewind" method, it is called.
 */

static VALUE
enumerator_rewind(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);

    if (rb_respond_to(e->obj, id_rewind))
	rb_funcall(e->obj, id_rewind, 0);

    e->fib = 0;
    e->dst = Qnil;
    e->no_next = Qfalse;
    return obj;
}

static VALUE
inspect_enumerator(VALUE obj, VALUE dummy, int recur)
{
    struct enumerator *e = enumerator_ptr(obj);
    const char *cname = rb_obj_classname(obj);
    VALUE eobj, str;
    int tainted, untrusted;

    if (recur) {
	str = rb_sprintf("#<%s: ...>", cname);
	OBJ_TAINT(str);
	return str;
    }

    eobj = e->obj;

    tainted   = OBJ_TAINTED(eobj);
    untrusted = OBJ_UNTRUSTED(eobj);

    /* (1..100).each_cons(2) => "#<Enumerator: 1..100:each_cons(2)>" */
    str = rb_sprintf("#<%s: ", cname);
    rb_str_concat(str, rb_inspect(eobj));
    rb_str_buf_cat2(str, ":");
    rb_str_buf_cat2(str, rb_id2name(e->meth));

    if (e->args) {
	int    argc = RARRAY_LEN(e->args);
	VALUE *argv = RARRAY_PTR(e->args);

	rb_str_buf_cat2(str, "(");

	while (argc--) {
	    VALUE arg = *argv++;

	    rb_str_concat(str, rb_inspect(arg));
	    rb_str_buf_cat2(str, argc > 0 ? ", " : ")");

	    if (OBJ_TAINTED(arg)) tainted = Qtrue;
	    if (OBJ_UNTRUSTED(arg)) untrusted = Qtrue;
	}
    }

    rb_str_buf_cat2(str, ">");

    if (tainted) OBJ_TAINT(str);
    if (untrusted) OBJ_UNTRUST(str);
    return str;
}

/*
 * call-seq:
 *   e.inspect  => string
 *
 *  Create a printable version of <i>e</i>.
 */

static VALUE
enumerator_inspect(VALUE obj)
{
    return rb_exec_recursive(inspect_enumerator, obj, 0);
}

/*
 * Yielder
 */
static void
yielder_mark(void *p)
{
    struct yielder *ptr = p;
    rb_gc_mark(ptr->proc);
}

static struct yielder *
yielder_ptr(VALUE obj)
{
    struct yielder *ptr;

    Data_Get_Struct(obj, struct yielder, ptr);
    if (RDATA(obj)->dmark != yielder_mark) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %s (expected %s)",
		 rb_obj_classname(obj), rb_class2name(rb_cYielder));
    }
    if (!ptr || ptr->proc == Qundef) {
	rb_raise(rb_eArgError, "uninitialized yielder");
    }
    return ptr;
}

/* :nodoc: */
static VALUE
yielder_allocate(VALUE klass)
{
    struct yielder *ptr;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct yielder, yielder_mark, -1, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
yielder_init(VALUE obj, VALUE proc)
{
    struct yielder *ptr;

    Data_Get_Struct(obj, struct yielder, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated yielder");
    }

    ptr->proc = proc;

    return obj;
}

/* :nodoc: */
static VALUE
yielder_initialize(VALUE obj)
{
    rb_need_block();

    return yielder_init(obj, rb_block_proc());
}

/* :nodoc: */
static VALUE
yielder_yield(VALUE obj, VALUE args)
{
    struct yielder *ptr = yielder_ptr(obj);

    rb_proc_call(ptr->proc, args);

    return obj;
}

static VALUE
yielder_new_i(VALUE dummy)
{
    return yielder_init(yielder_allocate(rb_cYielder), rb_block_proc());
}

static VALUE
yielder_yield_i(VALUE obj, VALUE memo, int argc, VALUE *argv)
{
    return rb_yield_values2(argc, argv);
}

static VALUE
yielder_new(void)
{
    return rb_iterate(yielder_new_i, (VALUE)0, yielder_yield_i, (VALUE)0);
}

/*
 * Generator
 */
static void
generator_mark(void *p)
{
    struct generator *ptr = p;
    rb_gc_mark(ptr->proc);
}

static struct generator *
generator_ptr(VALUE obj)
{
    struct generator *ptr;

    Data_Get_Struct(obj, struct generator, ptr);
    if (RDATA(obj)->dmark != generator_mark) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %s (expected %s)",
		 rb_obj_classname(obj), rb_class2name(rb_cGenerator));
    }
    if (!ptr || ptr->proc == Qundef) {
	rb_raise(rb_eArgError, "uninitialized generator");
    }
    return ptr;
}

/* :nodoc: */
static VALUE
generator_allocate(VALUE klass)
{
    struct generator *ptr;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct generator, generator_mark, -1, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
generator_init(VALUE obj, VALUE proc)
{
    struct generator *ptr;

    Data_Get_Struct(obj, struct generator, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated generator");
    }

    ptr->proc = proc;

    return obj;
}

VALUE rb_obj_is_proc(VALUE proc);

/* :nodoc: */
static VALUE
generator_initialize(int argc, VALUE *argv, VALUE obj)
{
    VALUE proc;

    if (argc == 0) {
	rb_need_block();

	proc = rb_block_proc();
    } else {
	rb_scan_args(argc, argv, "1", &proc);

	if (!rb_obj_is_proc(proc))
	    rb_raise(rb_eTypeError,
		     "wrong argument type %s (expected Proc)",
		     rb_obj_classname(proc));

	if (rb_block_given_p()) {
	    rb_warn("given block not used");
	}
    }

    return generator_init(obj, proc);
}

/* :nodoc: */
static VALUE
generator_init_copy(VALUE obj, VALUE orig)
{
    struct generator *ptr0, *ptr1;

    ptr0 = generator_ptr(orig);

    Data_Get_Struct(obj, struct generator, ptr1);

    if (!ptr1) {
	rb_raise(rb_eArgError, "unallocated generator");
    }

    ptr1->proc = ptr0->proc;

    return obj;
}

/* :nodoc: */
static VALUE
generator_each(VALUE obj)
{
    struct generator *ptr = generator_ptr(obj);
    VALUE yielder;

    yielder = yielder_new();

    rb_proc_call(ptr->proc, rb_ary_new3(1, yielder));

    return obj;
}

void
Init_Enumerator(void)
{
    rb_define_method(rb_mKernel, "to_enum", obj_to_enum, -1);
    rb_define_method(rb_mKernel, "enum_for", obj_to_enum, -1);

    rb_define_method(rb_mEnumerable, "each_slice", enum_each_slice, 1);
    rb_define_method(rb_mEnumerable, "each_cons", enum_each_cons, 1);
    rb_define_method(rb_mEnumerable, "each_with_object", enum_each_with_object, 1);

    rb_cEnumerator = rb_define_class("Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_define_alloc_func(rb_cEnumerator, enumerator_allocate);
    rb_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_define_method(rb_cEnumerator, "initialize_copy", enumerator_init_copy, 1);
    rb_define_method(rb_cEnumerator, "each", enumerator_each, 0);
    rb_define_method(rb_cEnumerator, "each_with_index", enumerator_each_with_index, 0);
    rb_define_method(rb_cEnumerator, "each_with_object", enumerator_with_object, 1);
    rb_define_method(rb_cEnumerator, "with_index", enumerator_with_index, -1);
    rb_define_method(rb_cEnumerator, "with_object", enumerator_with_object, 1);
    rb_define_method(rb_cEnumerator, "next", enumerator_next, 0);
    rb_define_method(rb_cEnumerator, "rewind", enumerator_rewind, 0);
    rb_define_method(rb_cEnumerator, "inspect", enumerator_inspect, 0);

    rb_eStopIteration = rb_define_class("StopIteration", rb_eIndexError);

    /* Generator */
    rb_cGenerator = rb_define_class_under(rb_cEnumerator, "Generator", rb_cObject);
    rb_include_module(rb_cGenerator, rb_mEnumerable);
    rb_define_alloc_func(rb_cGenerator, generator_allocate);
    rb_define_method(rb_cGenerator, "initialize", generator_initialize, -1);
    rb_define_method(rb_cGenerator, "initialize_copy", generator_init_copy, 1);
    rb_define_method(rb_cGenerator, "each", generator_each, 0);

    /* Yielder */
    rb_cYielder = rb_define_class_under(rb_cEnumerator, "Yielder", rb_cObject);
    rb_define_alloc_func(rb_cYielder, yielder_allocate);
    rb_define_method(rb_cYielder, "initialize", yielder_initialize, 0);
    rb_define_method(rb_cYielder, "yield", yielder_yield, -2);
    rb_define_method(rb_cYielder, "<<", yielder_yield, -2);

    id_rewind = rb_intern("rewind");
    id_each = rb_intern("each");
    sym_each = ID2SYM(id_each);

    rb_provide("enumerator.so");	/* for backward compatibility */
}
