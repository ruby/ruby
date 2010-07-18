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
 *
 * An enumerator can be created by following methods.
 * - Kernel#to_enum
 * - Kernel#enum_for
 * - Enumerator.new
 *
 * Also, most iteration methods without a block returns an enumerator.
 * For example, Array#map returns an enumerator if a block is not given.
 * The enumerator has the with_index method.
 * So ary.map.with_index works as follows.
 *
 *   p %w[foo bar baz].map.with_index {|w,i| "#{i}:#{w}" }
 *   #=> ["0:foo", "1:bar", "2:baz"]
 *
 * An enumerator object can be used as an external iterator.
 * I.e.  Enumerator#next returns the next value of the iterator.
 * Enumerator#next raises StopIteration at end.
 *
 *   e = [1,2,3].each   # returns an enumerator object.
 *   p e.next   #=> 1
 *   p e.next   #=> 2
 *   p e.next   #=> 3
 *   p e.next   #raises StopIteration
 *
 * An external iterator can be used to implement an internal iterator as follows.
 *
 *   def ext_each(e)
 *     while true
 *       begin
 *         vs = e.next_values
 *       rescue StopIteration
 *         return $!.result
 *       end
 *       y = yield(*vs)
 *       e.feed y
 *     end
 *   end
 *
 *   o = Object.new
 *   def o.each
 *     p yield
 *     p yield(1)
 *     p yield(1, 2)
 *     3
 *   end
 *
 *   # use o.each as an internal iterator directly.
 *   p o.each {|*x| p x; [:b, *x] }
 *   #=> [], [:b], [1], [:b, 1], [1, 2], [:b, 1, 2], 3
 *
 *   # convert o.each to an external iterator for
 *   # implementing an internal iterator.
 *   p ext_each(o.to_enum) {|*x| p x; [:b, *x] }
 *   #=> [], [:b], [1], [:b, 1], [1, 2], [:b, 1, 2], 3
 *
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
    VALUE lookahead;
    VALUE feedvalue;
    VALUE stop_exc;
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
    rb_gc_mark(ptr->lookahead);
    rb_gc_mark(ptr->feedvalue);
    rb_gc_mark(ptr->stop_exc);
}

#define enumerator_free RUBY_TYPED_DEFAULT_FREE

static size_t
enumerator_memsize(const void *p)
{
    return p ? sizeof(struct enumerator) : 0;
}

static const rb_data_type_t enumerator_data_type = {
    "enumerator",
    {
	enumerator_mark,
	enumerator_free,
	enumerator_memsize,
    },
};

static struct enumerator *
enumerator_ptr(VALUE obj)
{
    struct enumerator *ptr;

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, ptr);
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
enumerator_allocate(VALUE klass)
{
    struct enumerator *ptr;
    VALUE enum_obj;

    enum_obj = TypedData_Make_Struct(klass, struct enumerator, &enumerator_data_type, ptr);
    ptr->obj = Qundef;

    return enum_obj;
}

static VALUE
enumerator_init(VALUE enum_obj, VALUE obj, VALUE meth, int argc, VALUE *argv)
{
    struct enumerator *ptr;

    TypedData_Get_Struct(enum_obj, struct enumerator, &enumerator_data_type, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr->obj  = obj;
    ptr->meth = rb_to_id(meth);
    if (argc) ptr->args = rb_ary_new4(argc, argv);
    ptr->fib = 0;
    ptr->dst = Qnil;
    ptr->lookahead = Qundef;
    ptr->feedvalue = Qundef;
    ptr->stop_exc = Qfalse;

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
    }
    else {
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

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, ptr1);

    if (!ptr1) {
	rb_raise(rb_eArgError, "unallocated enumerator");
    }

    ptr1->obj  = ptr0->obj;
    ptr1->meth = ptr0->meth;
    ptr1->args = ptr0->args;
    ptr1->fib  = 0;
    ptr1->lookahead  = Qundef;
    ptr1->feedvalue  = Qundef;

    return obj;
}

VALUE
rb_enumeratorize(VALUE obj, VALUE meth, int argc, VALUE *argv)
{
    return enumerator_init(enumerator_allocate(rb_cEnumerator), obj, meth, argc, argv);
}

static VALUE
enumerator_block_call(VALUE obj, rb_block_call_func *func, VALUE arg)
{
    int argc = 0;
    VALUE *argv = 0;
    const struct enumerator *e = enumerator_ptr(obj);
    ID meth = e->meth;

    if (e->args) {
	argc = RARRAY_LENINT(e->args);
	argv = RARRAY_PTR(e->args);
    }
    return rb_block_call(e->obj, meth, argc, argv, func, arg);
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
    if (!rb_block_given_p()) return obj;
    return enumerator_block_call(obj, 0, obj);
}

static VALUE
enumerator_with_index_i(VALUE val, VALUE m, int argc, VALUE *argv)
{
    VALUE idx;
    VALUE *memo = (VALUE *)m;

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
    VALUE memo;

    rb_scan_args(argc, argv, "01", &memo);
    RETURN_ENUMERATOR(obj, argc, argv);
    memo = NIL_P(memo) ? 0 : (VALUE)NUM2LONG(memo);
    return enumerator_block_call(obj, enumerator_with_index_i, (VALUE)&memo);
}

/*
 *  call-seq:
 *    e.each_with_index {|(*args), idx| ... }
 *    e.each_with_index
 *
 *  Same as Enumerator#with_index, except each_with_index does not
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
    RETURN_ENUMERATOR(obj, 1, &memo);
    enumerator_block_call(obj, enumerator_with_object_i, memo);

    return memo;
}

static VALUE
next_ii(VALUE i, VALUE obj, int argc, VALUE *argv)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE feedvalue = Qnil;
    VALUE args = rb_ary_new4(argc, argv);
    rb_fiber_yield(1, &args);
    if (e->feedvalue != Qundef) {
        feedvalue = e->feedvalue;
        e->feedvalue = Qundef;
    }
    return feedvalue;
}

static VALUE
next_i(VALUE curr, VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE nil = Qnil;
    VALUE result;

    result = rb_block_call(obj, id_each, 0, 0, next_ii, obj);
    e->stop_exc = rb_exc_new2(rb_eStopIteration, "iteration reached an end");
    rb_ivar_set(e->stop_exc, rb_intern("result"), result);
    return rb_fiber_yield(1, &nil);
}

static void
next_init(VALUE obj, struct enumerator *e)
{
    VALUE curr = rb_fiber_current();
    e->dst = curr;
    e->fib = rb_fiber_new(next_i, obj);
    e->lookahead = Qundef;
}

static VALUE
get_next_values(VALUE obj, struct enumerator *e)
{
    VALUE curr, vs;

    if (e->stop_exc)
	rb_exc_raise(e->stop_exc);

    curr = rb_fiber_current();

    if (!e->fib || !rb_fiber_alive_p(e->fib)) {
	next_init(obj, e);
    }

    vs = rb_fiber_resume(e->fib, 1, &curr);
    if (e->stop_exc) {
	e->fib = 0;
	e->dst = Qnil;
	e->lookahead = Qundef;
	e->feedvalue = Qundef;
	rb_exc_raise(e->stop_exc);
    }
    return vs;
}

/*
 * call-seq:
 *   e.next_values   -> array
 *
 * Returns the next object as an array in the enumerator,
 * and move the internal position forward.
 * When the position reached at the end, StopIteration is raised.
 *
 * This method can be used to distinguish <code>yield</code> and <code>yield nil</code>.
 *
 *   o = Object.new
 *   def o.each
 *     yield
 *     yield 1
 *     yield 1, 2
 *     yield nil
 *     yield [1, 2]
 *   end
 *   e = o.to_enum
 *   p e.next_values
 *   p e.next_values
 *   p e.next_values
 *   p e.next_values
 *   p e.next_values
 *   e = o.to_enum
 *   p e.next
 *   p e.next
 *   p e.next
 *   p e.next
 *   p e.next
 *
 *   ## yield args       next_values      next
 *   #  yield            []               nil
 *   #  yield 1          [1]              1
 *   #  yield 1, 2       [1, 2]           [1, 2]
 *   #  yield nil        [nil]            nil
 *   #  yield [1, 2]     [[1, 2]]         [1, 2]
 *
 * Note that enumeration sequence by next_values method does not affect other
 * non-external enumeration methods, unless underlying iteration
 * methods itself has side-effect, e.g. IO#each_line.
 *
 */

static VALUE
enumerator_next_values(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE vs;

    if (e->lookahead != Qundef) {
        vs = e->lookahead;
        e->lookahead = Qundef;
        return vs;
    }

    return get_next_values(obj, e);
}

static VALUE
ary2sv(VALUE args, int dup)
{
    if (TYPE(args) != T_ARRAY)
        return args;

    switch (RARRAY_LEN(args)) {
      case 0:
        return Qnil;

      case 1:
        return RARRAY_PTR(args)[0];

      default:
        if (dup)
            return rb_ary_dup(args);
        return args;
    }
}

/*
 * call-seq:
 *   e.next   -> object
 *
 * Returns the next object in the enumerator, and move the internal
 * position forward.  When the position reached at the end, StopIteration
 * is raised.
 *
 *   a = [1,2,3]
 *   e = a.to_enum
 *   p e.next   #=> 1
 *   p e.next   #=> 2
 *   p e.next   #=> 3
 *   p e.next   #raises StopIteration
 *
 * Note that enumeration sequence by next method does not affect other
 * non-external enumeration methods, unless underlying iteration
 * methods itself has side-effect, e.g. IO#each_line.
 *
 */

static VALUE
enumerator_next(VALUE obj)
{
    VALUE vs = enumerator_next_values(obj);
    return ary2sv(vs, 0);
}

static VALUE
enumerator_peek_values(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);

    if (e->lookahead == Qundef) {
        e->lookahead = get_next_values(obj, e);
    }
    return e->lookahead;
}

/*
 * call-seq:
 *   e.peek_values   -> array
 *
 * Returns the next object as an array in the enumerator,
 * but don't move the internal position forward.
 * When the position reached at the end, StopIteration is raised.
 *
 *   o = Object.new
 *   def o.each
 *     yield
 *     yield 1
 *     yield 1, 2
 *   end
 *   e = o.to_enum
 *   p e.peek_values    #=> []
 *   e.next
 *   p e.peek_values    #=> [1]
 *   p e.peek_values    #=> [1]
 *   e.next
 *   p e.peek_values    #=> [1, 2]
 *   e.next
 *   p e.peek_values    # raises StopIteration
 *
 */

static VALUE
enumerator_peek_values_m(VALUE obj)
{
    return rb_ary_dup(enumerator_peek_values(obj));
}

/*
 * call-seq:
 *   e.peek   -> object
 *
 * Returns the next object in the enumerator, but don't move the internal
 * position forward.  When the position reached at the end, StopIteration
 * is raised.
 *
 *   a = [1,2,3]
 *   e = a.to_enum
 *   p e.next   #=> 1
 *   p e.peek   #=> 2
 *   p e.peek   #=> 2
 *   p e.peek   #=> 2
 *   p e.next   #=> 2
 *   p e.next   #=> 3
 *   p e.next   #raises StopIteration
 *
 */

static VALUE
enumerator_peek(VALUE obj)
{
    VALUE vs = enumerator_peek_values(obj);
    return ary2sv(vs, 1);
}

/*
 * call-seq:
 *   e.feed obj   -> nil
 *
 * Set the value for the next yield in the enumerator returns.
 *
 * If the value is not set, the yield returns nil.
 *
 * This value is cleared after used.
 *
 *   o = Object.new
 *   def o.each
 *     # (2)
 *     x = yield
 *     p x          #=> "foo"
 *     # (5)
 *     x = yield
 *     p x          #=> nil
 *     # (7)
 *     x = yield
 *     # not reached
 *     p x
 *   end
 *   e = o.to_enum
 *   # (1)
 *   e.next
 *   # (3)
 *   e.feed "foo"
 *   # (4)
 *   e.next
 *   # (6)
 *   e.next
 *   # (8)
 *
 */

static VALUE
enumerator_feed(VALUE obj, VALUE v)
{
    struct enumerator *e = enumerator_ptr(obj);

    if (e->feedvalue != Qundef) {
	rb_raise(rb_eTypeError, "feed value already set");
    }
    e->feedvalue = v;

    return Qnil;
}

/*
 * call-seq:
 *   e.rewind   -> e
 *
 * Rewinds the enumeration sequence by the next method.
 *
 * If the enclosed object responds to a "rewind" method, it is called.
 */

static VALUE
enumerator_rewind(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);

    rb_check_funcall(e->obj, id_rewind, 0, 0);

    e->fib = 0;
    e->dst = Qnil;
    e->lookahead = Qundef;
    e->feedvalue = Qundef;
    e->stop_exc = Qfalse;
    return obj;
}

static VALUE
inspect_enumerator(VALUE obj, VALUE dummy, int recur)
{
    struct enumerator *e;
    const char *cname;
    VALUE eobj, str;
    int tainted, untrusted;

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, e);

    cname = rb_obj_classname(obj);

    if (!e || e->obj == Qundef) {
	return rb_sprintf("#<%s: uninitialized>", cname);
    }

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
	long   argc = RARRAY_LEN(e->args);
	VALUE *argv = RARRAY_PTR(e->args);

	rb_str_buf_cat2(str, "(");

	while (argc--) {
	    VALUE arg = *argv++;

	    rb_str_concat(str, rb_inspect(arg));
	    rb_str_buf_cat2(str, argc > 0 ? ", " : ")");

	    if (OBJ_TAINTED(arg)) tainted = TRUE;
	    if (OBJ_UNTRUSTED(arg)) untrusted = TRUE;
	}
    }

    rb_str_buf_cat2(str, ">");

    if (tainted) OBJ_TAINT(str);
    if (untrusted) OBJ_UNTRUST(str);
    return str;
}

/*
 * call-seq:
 *   e.inspect  -> string
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

#define yielder_free RUBY_TYPED_DEFAULT_FREE

static size_t
yielder_memsize(const void *p)
{
    return p ? sizeof(struct yielder) : 0;
}

static const rb_data_type_t yielder_data_type = {
    "yielder",
    {
	yielder_mark,
	yielder_free,
	yielder_memsize,
    },
};

static struct yielder *
yielder_ptr(VALUE obj)
{
    struct yielder *ptr;

    TypedData_Get_Struct(obj, struct yielder, &yielder_data_type, ptr);
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

    obj = TypedData_Make_Struct(klass, struct yielder, &yielder_data_type, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
yielder_init(VALUE obj, VALUE proc)
{
    struct yielder *ptr;

    TypedData_Get_Struct(obj, struct yielder, &yielder_data_type, ptr);

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

    return rb_proc_call(ptr->proc, args);
}

/* :nodoc: */
static VALUE yielder_yield_push(VALUE obj, VALUE args)
{
    yielder_yield(obj, args);
    return obj;
}

static VALUE
yielder_yield_i(VALUE obj, VALUE memo, int argc, VALUE *argv)
{
    return rb_yield_values2(argc, argv);
}

static VALUE
yielder_new(void)
{
    return yielder_init(yielder_allocate(rb_cYielder), rb_proc_new(yielder_yield_i, 0));
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

#define generator_free RUBY_TYPED_DEFAULT_FREE

static size_t
generator_memsize(const void *p)
{
    return p ? sizeof(struct generator) : 0;
}

static const rb_data_type_t generator_data_type = {
    "generator",
    {
	generator_mark,
	generator_free,
	generator_memsize,
    },
};

static struct generator *
generator_ptr(VALUE obj)
{
    struct generator *ptr;

    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr);
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

    obj = TypedData_Make_Struct(klass, struct generator, &generator_data_type, ptr);
    ptr->proc = Qundef;

    return obj;
}

static VALUE
generator_init(VALUE obj, VALUE proc)
{
    struct generator *ptr;

    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr);

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

    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr1);

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

    return rb_proc_call(ptr->proc, rb_ary_new3(1, yielder));
}

/*
 *  Document-class: StopIteration
 *
 *  Raised to stop the iteration, in particular by Enumerator#next. It is
 *  rescued by Kernel#loop.
 *
 *     loop do
 *       puts "Hello"
 *       raise StopIteration
 *       puts "World"
 *     end
 *     puts "Done!"
 *
 *  <em>produces:</em>
 *
 *     Hello
 *     Done!
 */

/*
 * call-seq:
 *   stopiteration.result       -> value
 *
 * Returns the return value of the iterator.
 *
 *   o = Object.new
 *   def o.each
 *     yield 1
 *     yield 2
 *     yield 3
 *     100
 *   end
 *   e = o.to_enum
 *   p e.next                   #=> 1
 *   p e.next                   #=> 2
 *   p e.next                   #=> 3
 *   begin
 *     e.next
 *   rescue StopIteration
 *     p $!.result              #=> 100
 *   end
 *
 */
static VALUE
stop_result(VALUE self)
{
    return rb_attr_get(self, rb_intern("result"));
}

void
Init_Enumerator(void)
{
    rb_define_method(rb_mKernel, "to_enum", obj_to_enum, -1);
    rb_define_method(rb_mKernel, "enum_for", obj_to_enum, -1);

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
    rb_define_method(rb_cEnumerator, "next_values", enumerator_next_values, 0);
    rb_define_method(rb_cEnumerator, "peek_values", enumerator_peek_values_m, 0);
    rb_define_method(rb_cEnumerator, "next", enumerator_next, 0);
    rb_define_method(rb_cEnumerator, "peek", enumerator_peek, 0);
    rb_define_method(rb_cEnumerator, "feed", enumerator_feed, 1);
    rb_define_method(rb_cEnumerator, "rewind", enumerator_rewind, 0);
    rb_define_method(rb_cEnumerator, "inspect", enumerator_inspect, 0);

    rb_eStopIteration = rb_define_class("StopIteration", rb_eIndexError);
    rb_define_method(rb_eStopIteration, "result", stop_result, 0);

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
    rb_define_method(rb_cYielder, "<<", yielder_yield_push, -2);

    id_rewind = rb_intern("rewind");
    id_each = rb_intern("each");
    sym_each = ID2SYM(id_each);

    rb_provide("enumerator.so");	/* for backward compatibility */
}
