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
    VALUE proc;
    VALUE args;
    rb_block_call_func *iter;
};

static VALUE rb_cGenerator, rb_cYielder;

struct generator {
    VALUE proc;
};

struct yielder {
    VALUE proc;
};

static VALUE generator_allocate _((VALUE klass));
static VALUE generator_init _((VALUE obj, VALUE proc));

/*
 * Enumerator
 */

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
		 "wrong argument type %s (expected Enumerator)",
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

    rb_block_call(obj, id_each, 0, 0, each_slice_i, (VALUE)args);

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

    rb_block_call(obj, id_each, 0, 0, each_cons_i, (VALUE)args);

    return Qnil;
}

static VALUE
each_with_object_i(val, memo)
    VALUE val, memo;
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
enum_each_with_object(obj, memo)
    VALUE obj, memo;
{
    RETURN_ENUMERATOR(obj, 1, &memo);

    rb_block_call(obj, id_each, 0, 0, each_with_object_i, memo);

    return memo;
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
enumerator_initialize(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
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

static VALUE
enumerator_with_object_i(val, memo)
    VALUE val, memo;
{
    return rb_yield_values(2, val, memo);
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
enumerator_with_object(obj, memo)
    VALUE obj, memo;
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

static int
require_generator()
{
    static int done = 0;

    if (done)
	return 0; /* not the first time */
    rb_require("generator");
    done = 1;
    return 1; /* the first time */
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
 * Caution: Calling this method causes the "generator" library to be
 * loaded.
 */

static VALUE
enumerator_next(obj)
    VALUE obj;
{
    if (require_generator()) {
	/*
	 * Call the new rewind method that the generator library
	 * redefines.
	 */
	return rb_funcall(obj, rb_intern("next"), 0, 0);
    } else {
	rb_raise(rb_eRuntimeError, "unexpected call; the generator library must have failed in redefining this method");
    }
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
enumerator_rewind(obj)
    VALUE obj;
{
    if (require_generator()) {
	/*
	 * Call the new rewind method that the generator library
	 * redefines.
	 */
	return rb_funcall(obj, rb_intern("rewind"), 0, 0);
    } else {
	/*
	 * Once the generator library is loaded and the rewind method
	 * is overridden, this method changes itself to a secret knob
	 * to rewind the internal object. (black magic!)
	 */
	struct enumerator *e;

	e = enumerator_ptr(obj);
	if (rb_respond_to(e->obj, id_rewind))
	    rb_funcall(e->obj, id_rewind, 0);
	return obj;
    }
}

static VALUE inspect_enumerator _((VALUE obj, VALUE dummy, int));
static VALUE
inspect_enumerator(obj, dummy, recur)
    VALUE obj, dummy;
    int recur;
{
    struct enumerator *e = enumerator_ptr(obj);
    const char *cname = rb_obj_classname(obj);
    VALUE eobj, str;
    int tainted;

    if (recur) {
	str = rb_str_buf_new2("#<");
	rb_str_buf_cat2(str, cname);
	rb_str_buf_cat2(str, ": ...>");
	OBJ_TAINT(str);
	return str;
    }

    eobj = e->obj;

    tainted = OBJ_TAINTED(eobj);

    /* (1..100).each_cons(2) => "#<Enumerator: 1..100:each_cons(2)>" */
    str = rb_str_buf_new2("#<");
    rb_str_buf_cat2(str, cname);
    rb_str_buf_cat2(str, ": ");
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
	}
    }

    rb_str_buf_cat2(str, ">");

    if (tainted) OBJ_TAINT(str);
    return str;
}

/*
 * call-seq:
 *   e.inspect  => string
 *
 *  Create a printable version of <i>e</i>.
 */

static VALUE
enumerator_inspect(obj)
    VALUE obj;
{
    return rb_exec_recursive(inspect_enumerator, obj, 0);
}

/*
 * Yielder
 */

static void yielder_mark _((void *));

static void
yielder_mark(void *p)
{
    struct yielder *ptr = p;
    rb_gc_mark(ptr->proc);
}

static struct yielder *yielder_ptr _((VALUE));

static struct yielder *
yielder_ptr(obj)
    VALUE obj;
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

static VALUE yielder_allocate _((VALUE));

/* :nodoc: */
static VALUE
yielder_allocate(klass)
    VALUE klass;
{
    struct yielder *ptr;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct yielder, yielder_mark, -1, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
yielder_init(obj, proc)
    VALUE obj, proc;
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
yielder_initialize(obj)
    VALUE obj;
{
    rb_need_block();

    return yielder_init(obj, rb_block_proc());
}

/* :nodoc: */
static VALUE
yielder_yield(obj, args)
    VALUE obj, args;
{
    struct yielder *ptr = yielder_ptr(obj);

    rb_proc_call(ptr->proc, args);

    return obj;
}

static VALUE yielder_new_i _((VALUE));
static VALUE
yielder_new_i(dummy)
    VALUE dummy;
{
    return yielder_init(yielder_allocate(rb_cYielder), rb_block_proc());
}

static VALUE
yielder_yield_i(obj, memo)
    VALUE obj, memo;
{
    return rb_yield(obj);
}

static VALUE
yielder_new()
{
    return rb_iterate(yielder_new_i, (VALUE)0, yielder_yield_i, (VALUE)0);
}

/*
 * Generator
 */

static void generator_mark _((void *));

static void
generator_mark(p)
    void *p;
{
    struct generator *ptr = p;
    rb_gc_mark(ptr->proc);
}

static struct generator *
generator_ptr(obj)
    VALUE obj;
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

static VALUE generator_allocate _((VALUE));

/* :nodoc: */
static VALUE
generator_allocate(klass)
    VALUE klass;
{
    struct generator *ptr;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct generator, generator_mark, -1, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
generator_init(obj, proc)
    VALUE obj, proc;
{
    struct generator *ptr;

    Data_Get_Struct(obj, struct generator, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated generator");
    }

    ptr->proc = proc;

    return obj;
}

VALUE rb_obj_is_proc _((VALUE));

/* :nodoc: */
static VALUE
generator_initialize(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
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
generator_init_copy(obj, orig)
    VALUE obj, orig;
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
generator_each(obj)
    VALUE obj;
{
    struct generator *ptr = generator_ptr(obj);
    VALUE yielder;

    yielder = yielder_new();

    rb_proc_call(ptr->proc, rb_ary_new3(1, yielder));

    return obj;
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
    rb_define_method(rb_mEnumerable, "each_with_object", enum_each_with_object, 1);

    rb_cEnumerator = rb_define_class("Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_define_alloc_func(rb_cEnumerator, enumerator_allocate);
    rb_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_define_method(rb_cEnumerator, "initialize_copy", enumerator_init_copy, 1);
    rb_define_method(rb_cEnumerator, "each", enumerator_each, 0);
    rb_define_method(rb_cEnumerator, "each_with_index", enumerator_with_index, 0);
    rb_define_method(rb_cEnumerator, "each_with_object", enumerator_with_object, 1);
    rb_define_method(rb_cEnumerator, "with_index", enumerator_with_index, 0);
    rb_define_method(rb_cEnumerator, "with_object", enumerator_with_object, 1);
    rb_define_method(rb_cEnumerator, "next", enumerator_next, 0);
    rb_define_method(rb_cEnumerator, "rewind", enumerator_rewind, 0);
    rb_define_method(rb_cEnumerator, "inspect", enumerator_inspect, 0);

    rb_eStopIteration   = rb_define_class("StopIteration", rb_eIndexError);

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

    /* backward compatibility */
    rb_provide("enumerator.so");
    rb_define_const(rb_mEnumerable, "Enumerator", rb_cEnumerator);
}
