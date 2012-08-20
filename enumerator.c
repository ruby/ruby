/************************************************

  enumerator.c - provides Enumerator class

  $Author$

  Copyright (C) 2001-2003 Akinori MUSHA

  $Idaemons: /home/cvs/rb/enumerator/enumerator.c,v 1.1.1.1 2001/07/15 10:12:48 knu Exp $
  $RoughId: enumerator.c,v 1.6 2003/07/27 11:03:24 nobu Exp $
  $Id$

************************************************/

#include "ruby/ruby.h"
#include "node.h"
#include "internal.h"

/*
 * Document-class: Enumerator
 *
 * A class which allows both internal and external iteration.
 *
 * An Enumerator can be created by the following methods.
 * - Kernel#to_enum
 * - Kernel#enum_for
 * - Enumerator.new
 *
 * Most methods have two forms: a block form where the contents
 * are evaluated for each item in the enumeration, and a non-block form
 * which returns a new Enumerator wrapping the iteration.
 *
 *   enumerator = %w(one two three).each
 *   puts enumerator.class # => Enumerator
 *
 *   enumerator.each_with_object("foo") do |item, obj|
 *     puts "#{obj}: #{item}"
 *   end
 *
 *   # foo: one
 *   # foo: two
 *   # foo: three
 *
 *   enum_with_obj = enumerator.each_with_object("foo")
 *   puts enum_with_obj.class # => Enumerator
 *
 *   enum_with_obj.each do |item, obj|
 *     puts "#{obj}: #{item}"
 *   end
 *
 *   # foo: one
 *   # foo: two
 *   # foo: three
 *
 * This allows you to chain Enumerators together.  For example, you
 * can map a list's elements to strings containing the index
 * and the element as a string via:
 *
 *   puts %w[foo bar baz].map.with_index { |w, i| "#{i}:#{w}" }
 *   # => ["0:foo", "1:bar", "2:baz"]
 *
 * An Enumerator can also be used as an external iterator.
 * For example, Enumerator#next returns the next value of the iterator
 * or raises StopIteration if the Enumerator is at the end.
 *
 *   e = [1,2,3].each   # returns an enumerator object.
 *   puts e.next   # => 1
 *   puts e.next   # => 2
 *   puts e.next   # => 3
 *   puts e.next   # raises StopIteration
 *
 * You can use this to implement an internal iterator as follows:
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
 *
 *   def o.each
 *     puts yield
 *     puts yield(1)
 *     puts yield(1, 2)
 *     3
 *   end
 *
 *   # use o.each as an internal iterator directly.
 *   puts o.each {|*x| puts x; [:b, *x] }
 *   # => [], [:b], [1], [:b, 1], [1, 2], [:b, 1, 2], 3
 *
 *   # convert o.each to an external iterator for
 *   # implementing an internal iterator.
 *   puts ext_each(o.to_enum) {|*x| puts x; [:b, *x] }
 *   # => [], [:b], [1], [:b, 1], [1, 2], [:b, 1, 2], 3
 *
 */
VALUE rb_cEnumerator;
VALUE rb_cLazy;
static ID id_rewind, id_each, id_new, id_initialize, id_yield, id_call;
static ID id_eqq, id_next, id_result, id_lazy, id_receiver, id_arguments, id_method;
static VALUE sym_each, sym_cycle;

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
    VALUE procs;
};

static VALUE rb_cGenerator, rb_cYielder;

struct generator {
    VALUE proc;
    VALUE obj;
    VALUE hybrid;
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
    rb_gc_mark(ptr->procs);
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
 * call-seq:
 *   obj.to_enum(method = :each, *args)
 *   obj.enum_for(method = :each, *args)
 *
 * Creates a new Enumerator which will enumerate by on calling +method+ on
 * +obj+.
 *
 * +method+:: the method to call on +obj+ to generate the enumeration
 * +args+:: arguments that will be passed in +method+ <i>in addition</i>
 *          to the item itself.  Note that the number of args
 *          must not exceed the number expected by +method+
 *
 * === Example
 *
 *   str = "xyz"
 *
 *   enum = str.enum_for(:each_byte)
 *   enum.each { |b| puts b }
 *   # => 120
 *   # => 121
 *   # => 122
 *
 *   # protect an array from being modified by some_method
 *   a = [1, 2, 3]
 *   some_method(a.to_enum)
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
 * call-seq:
 *   Enumerator.new { |yielder| ... }
 *   Enumerator.new(obj, method = :each, *args)
 *
 * Creates a new Enumerator object, which can be used as an
 * Enumerable.
 *
 * In the first form, iteration is defined by the given block, in
 * which a "yielder" object, given as block parameter, can be used to
 * yield a value by calling the +yield+ method (aliased as +<<+):
 *
 *   fib = Enumerator.new do |y|
 *     a = b = 1
 *     loop do
 *       y << a
 *       a, b = b, a + b
 *     end
 *   end
 *
 *   p fib.take(10) # => [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
 *
 * The block form can be used to create a lazy enumeration that only processes
 * elements as-needed.  The generic pattern for this is:
 *
 *    Enumerator.new do |yielder|
 *      source.each do |source_item|
 *        # process source_item and append the yielder
 *      end
 *    end
 *
 * This can be used with infinite streams to support multiple chains:
 *
 *   class Fib
 *     def initialize(a = 1, b = 1)
 *       @a, @b = a, b
 *     end
 *
 *     def each
 *       a, b = @a, @b
 *       yield a
 *       while true
 *         yield b
 *         a, b = b, a+b
 *       end
 *     end
 *   end
 *
 *   def lazy_select enum
 *     Enumerator.new do |y|
 *       enum.each do |e|
 *         y << e if yield e
 *       end
 *     end
 *   end
 *
 *   def lazy_map enum
 *     Enumerator.new do |y|
 *       enum.each do |e|
 *         y << yield(e)
 *       end
 *     end
 *   end
 *
 *   even_fibs   = lazy_select(Fibs.new) { |x| x % 2 == 0 }
 *   string_fibs = lazy_map(even_fibs)   { |x| "<#{x}>" }
 *   string_fibs.each_with_index do |fib, i|
 *     puts "#{i}: #{fib}"
 *     break if i >= 3
 *   end
 *
 * This allows output even though the Fib produces an infinite sequence of
 * Fibonacci numbers:
 *
 *   0: <2>
 *   1: <8>
 *   2: <34>
 *   3: <144>
 *
 * In the second, deprecated, form, a generated Enumerator iterates over the
 * given object using the given method with the given arguments passed.
 *
 * Use of this form is discouraged.  Use Kernel#enum_for or Kernel#to_enum
 * instead.
 *
 *   e = Enumerator.new(ObjectSpace, :each_object)
 *       #-> ObjectSpace.enum_for(:each_object)
 *
 *   e.select { |obj| obj.is_a?(Class) }  #=> array of all classes
 *
 */
static VALUE
enumerator_initialize(int argc, VALUE *argv, VALUE obj)
{
    VALUE recv, meth = sym_each;

    if (argc == 0) {
	if (!rb_block_given_p())
	    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);

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

    if (!OBJ_INIT_COPY(obj, orig)) return obj;
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
    ptr1->procs = ptr0->procs;

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
 * call-seq:
 *   enum.each {...}
 *
 * Iterates over the block according to how this Enumerable was constructed.
 * If no block is given, returns self.
 *
 */
static VALUE
enumerator_each(int argc, VALUE *argv, VALUE obj)
{
    if (argc > 0) {
	struct enumerator *e = enumerator_ptr(obj = rb_obj_dup(obj));
	VALUE args = e->args;
	if (args) {
	    args = rb_ary_dup(args);
	    rb_ary_cat(args, argv, argc);
	}
	else {
	    args = rb_ary_new4(argc, argv);
	}
	e->args = args;
    }
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
 * call-seq:
 *   e.with_index(offset = 0) {|(*args), idx| ... }
 *   e.with_index(offset = 0)
 *
 * Iterates the given block for each element with an index, which
 * starts from +offset+.  If no block is given, returns a new Enumerator
 * that includes the index, starting from +offset+
 *
 * +offset+:: the starting index to use
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
 * call-seq:
 *   e.each_with_index {|(*args), idx| ... }
 *   e.each_with_index
 *
 * Same as Enumerator#with_index(0), i.e. there is no starting offset.
 *
 * If no block is given, a new Enumerator is returned that includes the index.
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
 * call-seq:
 *   e.with_object(obj) {|(*args), obj| ... }
 *   e.with_object(obj)
 *
 * Iterates the given block for each element with an arbitrary object, +obj+,
 * and returns +obj+
 *
 * If no block is given, returns a new Enumerator.
 *
 * === Example
 *
 *   to_three = Enumerator.new do |y|
 *     3.times do |x|
 *       y << x
 *     end
 *   end
 *
 *   to_three_with_string = to_three.with_object("foo")
 *   to_three_with_string.each do |x,string|
 *     puts "#{string}: #{x}"
 *   end
 *
 *   # => foo:0
 *   # => foo:1
 *   # => foo:2
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
    rb_ivar_set(e->stop_exc, id_result, result);
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
 * Returns the next object as an array in the enumerator, and move the
 * internal position forward.  When the position reached at the end,
 * StopIteration is raised.
 *
 * This method can be used to distinguish <code>yield</code> and <code>yield
 * nil</code>.
 *
 * === Example
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
 * Note that +next_values+ does not affect other non-external enumeration
 * methods unless underlying iteration method itself has side-effect, e.g.
 * IO#each_line.
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
    if (!RB_TYPE_P(args, T_ARRAY))
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
 * Returns the next object in the enumerator, and move the internal position
 * forward.  When the position reached at the end, StopIteration is raised.
 *
 * === Example
 *
 *   a = [1,2,3]
 *   e = a.to_enum
 *   p e.next   #=> 1
 *   p e.next   #=> 2
 *   p e.next   #=> 3
 *   p e.next   #raises StopIteration
 *
 * Note that enumeration sequence by +next+ does not affect other non-external
 * enumeration methods, unless the underlying iteration methods itself has
 * side-effect, e.g. IO#each_line.
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
 * Returns the next object as an array, similar to Enumerator#next_values, but
 * doesn't move the internal position forward.  If the position is already at
 * the end, StopIteration is raised.
 *
 * === Example
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
 * Returns the next object in the enumerator, but doesn't move the internal
 * position forward.  If the position is already at the end, StopIteration
 * is raised.
 *
 * === Example
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
 * Sets the value to be returned by the next yield inside +e+.
 *
 * If the value is not set, the yield returns nil.
 *
 * This value is cleared after being yielded.
 *
 *   o = Object.new
 *   def o.each
 *     x = yield         # (2) blocks
 *     p x               # (5) => "foo"
 *     x = yield         # (6) blocks
 *     p x               # (8) => nil
 *     x = yield         # (9) blocks
 *     p x               # not reached w/o another e.next
 *   end
 *
 *   e = o.to_enum
 *   e.next              # (1)
 *   e.feed "foo"        # (3)
 *   e.next              # (4)
 *   e.next              # (7)
 *                       # (10)
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
 * Rewinds the enumeration sequence to the beginning.
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
    rb_gc_mark(ptr->obj);
    rb_gc_mark(ptr->hybrid);
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
    ptr->hybrid = Qtrue;

    return obj;
}

/* :nodoc: */
static VALUE
generator_initialize(int argc, VALUE *argv, VALUE obj)
{
    VALUE proc;

    if (argc == 0) {
	rb_need_block();

	proc = rb_block_proc();
    }
    else {
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

    if (!OBJ_INIT_COPY(obj, orig)) return obj;

    ptr0 = generator_ptr(orig);

    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr1);

    if (!ptr1) {
	rb_raise(rb_eArgError, "unallocated generator");
    }

    ptr1->proc = ptr0->proc;
    ptr1->obj = ptr0->obj;

    return obj;
}

/* :nodoc: */
static VALUE
generator_each(int argc, VALUE *argv, VALUE obj)
{
    struct generator *ptr = generator_ptr(obj);
    VALUE args = rb_ary_new2(argc + 1);

    rb_ary_push(args, yielder_new());
    if (argc > 0) {
	rb_ary_cat(args, argv, argc);
    }

    return rb_proc_call(ptr->proc, args);
}

/* Lazy Enumerator methods */

struct proc_entry {
    VALUE proc;
    VALUE type;
    VALUE memo;
};

enum proc_entry_type {
    T_PROC_MAP        = 0,
    T_PROC_SELECT     = 1,
    T_PROC_TAKE       = 2,
    T_PROC_DROP       = 3,
    T_PROC_TAKE_WHILE = 4,
    T_PROC_DROP_WHILE = 5,
    T_PROC_REJECT     = 6,
    T_PROC_GREP       = 7
};

static void
proc_entry_mark(void *p)
{
    struct proc_entry *ptr = p;
    rb_gc_mark(ptr->proc);
    rb_gc_mark(ptr->type);
    rb_gc_mark(ptr->memo);
}

#define proc_entry_free RUBY_TYPED_DEFAULT_FREE

static size_t
proc_entry_memsize(const void *p)
{
    return p ? sizeof(struct proc_entry) : 0;
}

static const rb_data_type_t proc_entry_data_type = {
    "proc_entry",
    {
	proc_entry_mark,
	proc_entry_free,
	proc_entry_memsize,
    },
};

static VALUE
process_element(VALUE procs_array, VALUE yielder, int argc, VALUE* argv)
{
    VALUE result = rb_enum_values_pack(argc, argv);
    struct proc_entry *entry;
    VALUE *procs = RARRAY_PTR(procs_array);
    VALUE move_next = Qtrue;
    VALUE break_point = Qfalse;
    NODE *memo;
    long i = 0;

    for (i = 0; i < RARRAY_LEN(procs_array); i++) {
        TypedData_Get_Struct(procs[i], struct proc_entry, &proc_entry_data_type, entry);
        if (RTEST(move_next)) {
            switch ((enum proc_entry_type) entry->type) {
                case T_PROC_MAP:
                    result = rb_proc_call_with_block(entry->proc, 1, &result, Qnil);
                    break;
                case T_PROC_SELECT:
                    move_next = rb_proc_call_with_block(entry->proc, 1, &result, Qnil);
                    break;
                case T_PROC_TAKE:
                    memo = RNODE(entry->memo);
                    if (memo->u3.cnt == 0) {
                        move_next = Qfalse;
                        break_point = Qtrue;
                    } else if (--memo->u3.cnt == 0) {
                        memo->u3.cnt = memo->u2.argc;
                        break_point = Qtrue;
                    }
                    break;
                case T_PROC_DROP:
                    memo = RNODE(entry->memo);
                    if (memo->u3.cnt-- > 0) {
                        move_next = Qfalse;
                    }
                    break;
                case T_PROC_TAKE_WHILE:
                    move_next = rb_proc_call_with_block(entry->proc, 1, &result, Qnil);
                    if (!RTEST(move_next)) result = Qundef;
                    break;
                case T_PROC_DROP_WHILE:
                    memo = RNODE(entry->memo);
                    if (!memo->u3.state) {
                        move_next = !RTEST(rb_proc_call_with_block(entry->proc, 1, &result, Qnil));
                        if (move_next) memo->u3.state = TRUE;
                    }
                    break;
                case T_PROC_REJECT:
                    move_next = !RTEST(rb_proc_call_with_block(entry->proc, 1, &result, Qnil));
                    break;
                case T_PROC_GREP:
                    move_next = rb_funcall(entry->memo, id_eqq, 1, result);

                    if (RTEST(move_next) && entry->proc) {
                        result = rb_proc_call_with_block(entry->proc, 1, &result, Qnil);
                    }
                    break;
            }
        }
    }

    if (RTEST(move_next)) {
        rb_funcall2(yielder, id_yield, 1, &result);
    }
    if (RTEST(break_point)) {
        rb_iter_break();
    }
    return result;
}
static VALUE
lazy_init_iterator(VALUE val, VALUE m, int argc, VALUE *argv)
{
    VALUE result;

    if (argc == 1) {
	VALUE args[2];
        args[0] = m;
        args[1] = val;
        result = rb_yield_values2(2, args);
    }
    else {
	VALUE args;
	int len = rb_long2int((long)argc + 1);

	args = rb_ary_tmp_new(len);
	rb_ary_push(args, m);
	if (argc > 0) {
	    rb_ary_cat(args, argv, argc);
	}
	result = rb_yield_values2(len, RARRAY_PTR(args));
	RB_GC_GUARD(args);
    }
    if (result == Qundef) rb_iter_break();
    return Qnil;
}

static VALUE
lazy_init_yielder(VALUE val, VALUE m, int argc, VALUE *argv)
{
    VALUE yielder = RARRAY_PTR(m)[0];
    VALUE procs = RARRAY_PTR(m)[1];

    process_element(procs, yielder, argc, argv);
    return Qnil;
}

static VALUE
lazy_init_block_i(VALUE val, VALUE m, int argc, VALUE *argv)
{
    rb_block_call(rb_ary_entry(m, 0), id_each, argc-1, argv+1,
            lazy_init_iterator, val);
    return Qnil;
}

static VALUE
lazy_init_block(VALUE val, VALUE m, int argc, VALUE *argv)
{
    rb_block_call(rb_ary_entry(m, 0), id_each, argc-1, argv+1,
            lazy_init_yielder, rb_ary_new3(2, val, rb_ary_entry(m, 1)));
    return Qnil;
}

static VALUE
lazy_generator_init(VALUE enumerator, VALUE procs)
{
    VALUE generator;
    VALUE obj;
    struct generator *gen_ptr;
    struct generator *old_gen_ptr;
    struct enumerator *e = enumerator_ptr(enumerator);

    old_gen_ptr = generator_ptr(e->obj);
    if (old_gen_ptr->hybrid) {
        obj = enumerator;
    } else {
        obj = old_gen_ptr->obj;
    }

    generator = generator_allocate(rb_cGenerator);

    rb_block_call(generator, id_initialize, 0, 0, lazy_init_block,
		  rb_ary_new3(2, obj, procs));

    gen_ptr = generator_ptr(generator);
    gen_ptr->obj = obj;

    return generator;
}

static VALUE
create_proc_entry(enum proc_entry_type proc_type, VALUE memo)
{
    struct proc_entry *entry;
    VALUE entry_obj;

    entry_obj = TypedData_Make_Struct(rb_cObject, struct proc_entry,
            &proc_entry_data_type, entry);
    if (rb_block_given_p()) {
        entry->proc = rb_block_proc();
    }
    entry->type = proc_type;
    entry->memo = memo;

    return entry_obj;
}

static VALUE
lazy_add_proc(VALUE enum_obj, enum proc_entry_type proc_type, VALUE memo)
{
    struct enumerator *ptr;
    VALUE entry;

    entry = create_proc_entry(proc_type, memo);
    ptr = enumerator_ptr(enum_obj);
    rb_ary_push(ptr->procs, entry);

    return entry;
}

static VALUE
lazy_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE obj, meth;
    VALUE generator;
    VALUE procs;
    struct enumerator *ptr;
    int offset;

    if (argc < 1) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1..)", argc);
    }
    else {
	obj = argv[0];
	if (argc == 1) {
	    meth = sym_each;
	    offset = 1;
	}
	else {
	    meth = argv[1];
	    offset = 2;
	}
    }
    procs = rb_ary_new();

    generator = generator_allocate(rb_cGenerator);
    rb_block_call(generator, id_initialize, 0, 0,
		  (rb_block_given_p() ? lazy_init_block_i : lazy_init_block),
                  rb_ary_new3(2, obj, procs));
    enumerator_init(self, generator, meth, argc - offset, argv + offset);
    ptr = enumerator_ptr(self);
    ptr->procs = procs;

    rb_ivar_set(self, id_receiver, obj);
    return self;
}

static VALUE
lazy_set_method(VALUE lazy, VALUE args)
{
    ID id = rb_frame_this_func();
    rb_ivar_set(lazy, id_method, ID2SYM(id));
    if (NIL_P(args)) {
	/* Qfalse indicates that the arguments are empty */
	rb_ivar_set(lazy, id_arguments, Qfalse);
    }
    else {
	rb_ivar_set(lazy, id_arguments, args);
    }
    return lazy;
}

/*
 * call-seq:
 *   e.lazy -> lazy_enumerator
 *
 * Returns a lazy enumerator, whose methods map/collect,
 * flat_map/collect_concat, select/find_all, reject, grep, zip, take,
 * take_while, drop, drop_while, and cycle enumerate values only on an
 * as-needed basis.  However, if a block is given to zip or cycle, values
 * are enumerated immediately.
 *
 * === Example
 *
 * The following program finds pythagorean triples:
 *
 *   def pythagorean_triples
 *     (1..Float::INFINITY).lazy.flat_map {|z|
 *       (1..z).flat_map {|x|
 *         (x..z).select {|y|
 *           x**2 + y**2 == z**2
 *         }.map {|y|
 *           [x, y, z]
 *         }
 *       }
 *     }
 *   end
 *   # show first ten pythagorean triples
 *   p pythagorean_triples.take(10).force # take is lazy, so force is needed
 *   p pythagorean_triples.first(10)      # first is eager
 *   # show pythagorean triples less than 100
 *   p pythagorean_triples.take_while { |*, z| z < 100 }.force
 */
static VALUE
enumerable_lazy(VALUE obj)
{
    VALUE result;

    result = rb_class_new_instance(1, &obj, rb_cLazy);
    /* Qfalse indicates that the Enumerator::Lazy has no method name */

    rb_ivar_set(result, id_method, Qfalse);
    return result;
}

static VALUE
lazy_copy(int argc, VALUE *argv, VALUE obj)
{
    struct enumerator *e;
    struct enumerator *new_e;
    struct generator *g;
    VALUE new_obj;
    VALUE new_generator;
    VALUE new_procs;

    e = enumerator_ptr(obj);
    new_procs = rb_ary_new4(RARRAY_LEN(e->procs), RARRAY_PTR(e->procs));
    new_generator = lazy_generator_init(obj, new_procs);
    g = generator_ptr(new_generator);
    g->hybrid = Qfalse;

    new_obj = enumerator_init_copy(enumerator_allocate(rb_cLazy), obj);
    new_e = enumerator_ptr(new_obj);
    new_e->obj = new_generator;
    new_e->procs = new_procs;
    new_e->meth = rb_to_id(sym_each);

    if (argc > 0) {
        new_e->meth = rb_to_id(*argv++);
        new_e->args = rb_ary_new4(argc - 1, argv);
    } else {
        new_e->meth = id_each;
        new_e->args = rb_ary_new4(argc, argv);
    }

    return new_obj;
}

static VALUE
lazy_map(VALUE obj)
{
    VALUE new_enum;
    VALUE entry;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy map without a block");
    }

    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_MAP, Qnil);
    lazy_set_method(entry, Qnil);

    return new_enum;
}

static VALUE
lazy_flat_map_i(VALUE i, VALUE yielder, int argc, VALUE *argv)
{
    return rb_funcall2(yielder, id_yield, argc, argv);
}

static VALUE
lazy_flat_map_each(VALUE obj)
{
    NODE *memo = RNODE(obj);
    rb_block_call(memo->u1.value, id_each, 0, 0, lazy_flat_map_i,
		  memo->u2.value);
    return Qnil;
}

static VALUE
lazy_flat_map_to_ary(VALUE obj)
{
    NODE *memo = RNODE(obj);
    VALUE ary = rb_check_array_type(memo->u1.value);
    if (NIL_P(ary)) {
	rb_funcall(memo->u2.value, id_yield, 1, memo->u1.value);
    }
    else {
	long i;
	for (i = 0; i < RARRAY_LEN(ary); i++) {
	    rb_funcall(memo->u2.value, id_yield, 1, RARRAY_PTR(ary)[i]);
	}
    }
    return Qnil;
}

static VALUE
lazy_flat_map_func(VALUE val, VALUE m, int argc, VALUE *argv)
{
    VALUE result = rb_yield_values2(argc - 1, &argv[1]);
    if (RB_TYPE_P(result, T_ARRAY)) {
	long i;
	for (i = 0; i < RARRAY_LEN(result); i++) {
	    rb_funcall(argv[0], id_yield, 1, RARRAY_PTR(result)[i]);
	}
    }
    else {
	NODE *memo;
	memo = NEW_MEMO(result, argv[0], 0);
	rb_rescue2(lazy_flat_map_each, (VALUE) memo,
		   lazy_flat_map_to_ary, (VALUE) memo,
		   rb_eNoMethodError, (VALUE)0);
    }
    return Qnil;
}

static VALUE
lazy_flat_map(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy flat_map without a block");
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_flat_map_func, 0),
			   Qnil);
}

static VALUE
lazy_select(VALUE obj)
{
    VALUE new_enum;
    VALUE entry;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy select without a block");
    }

    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_SELECT, Qnil);
    lazy_set_method(entry, Qnil);

    return new_enum;
}

static VALUE
lazy_reject(VALUE obj)
{
    VALUE new_enum, entry;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy reject without a block");
    }

    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_REJECT, Qnil);
    lazy_set_method(entry, Qnil);

    return new_enum;
}

static VALUE
lazy_grep(VALUE obj, VALUE pattern)
{
    VALUE new_enum, entry;

    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_GREP, pattern);
    lazy_set_method(entry, rb_ary_new3(1, pattern));

    return new_enum;
}

static VALUE
call_next(VALUE obj)
{
    return rb_funcall(obj, id_next, 0);
}

static VALUE
next_stopped(VALUE obj)
{
    return Qnil;
}

static VALUE
lazy_zip_func(VALUE val, VALUE arg, int argc, VALUE *argv)
{
    VALUE yielder, ary, v;
    long i;

    yielder = argv[0];
    ary = rb_ary_new2(RARRAY_LEN(arg) + 1);
    rb_ary_push(ary, argv[1]);
    for (i = 0; i < RARRAY_LEN(arg); i++) {
	v = rb_rescue2(call_next, RARRAY_PTR(arg)[i], next_stopped, 0,
		       rb_eStopIteration, (VALUE)0);
	rb_ary_push(ary, v);
    }
    rb_funcall(yielder, id_yield, 1, ary);
    return Qnil;
}

static VALUE
lazy_zip(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary;
    int i;

    if (rb_block_given_p()) {
	return rb_call_super(argc, argv);
    }
    ary = rb_ary_new2(argc);
    for (i = 0; i < argc; i++) {
	rb_ary_push(ary, rb_funcall(argv[i], id_lazy, 0));
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_zip_func, ary),
			   rb_ary_new4(argc, argv));
}

static VALUE
lazy_take(VALUE obj, VALUE n)
{
    NODE *memo;
    long len = NUM2LONG(n);
    VALUE new_enum;
    int argc = 0;
    VALUE argv[2];
    VALUE entry;

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to take negative size");
    }

    if (len == 0) {
       argv[0] = sym_cycle;
       argv[1] = INT2NUM(0);
       argc = 2;
    }

    memo = NEW_MEMO(0, len, len);
    new_enum = lazy_copy(argc, argv, obj);
    entry = lazy_add_proc(new_enum, T_PROC_TAKE, (VALUE) memo);
    lazy_set_method(entry, rb_ary_new3(1, n));

    return new_enum;
}

static VALUE
lazy_take_while(VALUE obj)
{
    VALUE new_enum, entry;

    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_TAKE_WHILE, Qnil);
    lazy_set_method(entry, Qnil);

    return new_enum;
}

static VALUE
lazy_drop(VALUE obj, VALUE n)
{
    NODE *memo;
    long len = NUM2LONG(n);
    VALUE new_enum, entry;

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    memo = NEW_MEMO(0, 0, len);
    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_DROP, (VALUE) memo);
    lazy_set_method(entry, rb_ary_new3(1, n));

    return new_enum;
}

static VALUE
lazy_drop_while(VALUE obj)
{
    NODE *memo;
    VALUE new_enum, entry;

    memo = NEW_MEMO(0, 0, FALSE);
    new_enum = lazy_copy(0, 0, obj);
    entry = lazy_add_proc(new_enum, T_PROC_DROP_WHILE, (VALUE) memo);
    lazy_set_method(entry, Qnil);

    return new_enum;
}

static VALUE
lazy_cycle_func(VALUE val, VALUE m, int argc, VALUE *argv)
{
    return rb_funcall2(argv[0], id_yield, argc - 1, argv + 1);
}

static VALUE
lazy_cycle(int argc, VALUE *argv, VALUE obj)
{
    VALUE args;
    int len = rb_long2int((long)argc + 2);

    if (rb_block_given_p()) {
	return rb_call_super(argc, argv);
    }
    args = rb_ary_tmp_new(len);
    rb_ary_push(args, obj);
    rb_ary_push(args, sym_cycle);
    if (argc > 0) {
	rb_ary_cat(args, argv, argc);
    }
    return lazy_set_method(rb_block_call(rb_cLazy, id_new, len,
					 RARRAY_PTR(args), lazy_cycle_func,
					 args /* prevent from GC */),
			   rb_ary_new4(argc, argv));
}

static VALUE
lazy_lazy(VALUE obj)
{
    return obj;
}

static VALUE
append_method(VALUE obj, VALUE str, ID default_method)
{
    VALUE method;

    method = rb_attr_get(obj, id_method);
    if (NIL_P(method)) {
        rb_str_buf_cat2(str, ":");
        rb_str_buf_cat2(str, rb_id2name(default_method));
    }
    else if (method != Qfalse) {
        Check_Type(method, T_SYMBOL);
        rb_str_buf_cat2(str, ":");
        rb_str_buf_cat2(str, rb_id2name(SYM2ID(method)));
    }
    return str;
}

static VALUE
append_args(VALUE obj, VALUE str, VALUE default_args)
{
    VALUE eargs;
    int tainted, untrusted;

    eargs = rb_attr_get(obj, id_arguments);
    if (NIL_P(eargs)) {
        eargs = default_args;
    }
    if (eargs != Qfalse) {
        long   argc = RARRAY_LEN(eargs);
        VALUE *argv = RARRAY_PTR(eargs);

        if (argc > 0) {
            rb_str_buf_cat2(str, "(");

            while (argc--) {
                VALUE arg = *argv++;

                rb_str_concat(str, rb_inspect(arg));
                rb_str_buf_cat2(str, argc > 0 ? ", " : ")");

                if (OBJ_TAINTED(arg)) tainted = TRUE;
                if (OBJ_UNTRUSTED(arg)) untrusted = TRUE;
            }
        }
    }

    if (tainted) { OBJ_TAINT(str); }
    if (untrusted) { OBJ_UNTRUST(str); }
    return str;
}

static VALUE
inspect_enumerator(VALUE obj, VALUE dummy, int recur)
{
    struct enumerator *e;
    struct generator *g;
    const char *cname;
    VALUE eobj, str;
    int tainted, untrusted;
    VALUE *procs;
    int i;

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

    if (e->procs && RARRAY_LEN(e->procs) > 0) {
        g = generator_ptr(e->obj);
        eobj = g->obj;
    } else {
        eobj = rb_attr_get(obj, id_receiver);
        if (NIL_P(eobj)) {
            eobj = e->obj;
        }
    }

    tainted   = OBJ_TAINTED(eobj);
    untrusted = OBJ_UNTRUSTED(eobj);

    /* (1..100).each_cons(2) => "#<Enumerator: 1..100:each_cons(2)>"
     * In case procs chained enumerator traversing all proc entries manually 
     */
    if (e->procs && RARRAY_LEN(e->procs) > 0) {
        if (strcmp(rb_obj_classname(eobj), cname) == 0) {
            str = rb_inspect(eobj);
        } else {
            str = rb_sprintf("#<%s: ", cname);
            rb_str_concat(str, rb_inspect(eobj));
            rb_str_buf_cat2(str, ">");
        }
        procs = RARRAY_PTR(e->procs);
        for (i = 0; i < RARRAY_LEN(e->procs); i++) {
            str = rb_str_concat(rb_sprintf("#<%s: ", cname), str);
            append_method(procs[i], str, e->meth);
            append_args(procs[i], str, e->args);
            rb_str_buf_cat2(str, ">");
        }
    } else {
        str = rb_sprintf("#<%s: ", cname);
        rb_str_concat(str, rb_inspect(eobj));
        append_method(obj, str, e->meth);
        append_args(obj, str, e->args);

        rb_str_buf_cat2(str, ">");
    }


    if (tainted) OBJ_TAINT(str);
    if (untrusted) OBJ_UNTRUST(str);
    return str;
}

/*
 * call-seq:
 *   e.inspect  -> string
 *
 * Creates a printable version of <i>e</i>.
 */

static VALUE
enumerator_inspect(VALUE obj)
{
    return rb_exec_recursive(inspect_enumerator, obj, 0);
}
/*
 * Document-class: StopIteration
 *
 * Raised to stop the iteration, in particular by Enumerator#next. It is
 * rescued by Kernel#loop.
 *
 *   loop do
 *     puts "Hello"
 *     raise StopIteration
 *     puts "World"
 *   end
 *   puts "Done!"
 *
 * <em>produces:</em>
 *
 *   Hello
 *   Done!
 */

/*
 * call-seq:
 *   result       -> value
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
 *
 *   e = o.to_enum
 *
 *   puts e.next                   #=> 1
 *   puts e.next                   #=> 2
 *   puts e.next                   #=> 3
 *
 *   begin
 *     e.next
 *   rescue StopIteration => ex
 *     puts ex.result              #=> 100
 *   end
 *
 */

static VALUE
stop_result(VALUE self)
{
    return rb_attr_get(self, id_result);
}

void
InitVM_Enumerator(void)
{
    rb_define_method(rb_mKernel, "to_enum", obj_to_enum, -1);
    rb_define_method(rb_mKernel, "enum_for", obj_to_enum, -1);

    rb_cEnumerator = rb_define_class("Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_define_alloc_func(rb_cEnumerator, enumerator_allocate);
    rb_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_define_method(rb_cEnumerator, "initialize_copy", enumerator_init_copy, 1);
    rb_define_method(rb_cEnumerator, "each", enumerator_each, -1);
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

    /* Lazy */
    rb_cLazy = rb_define_class_under(rb_cEnumerator, "Lazy", rb_cEnumerator);
    rb_define_method(rb_mEnumerable, "lazy", enumerable_lazy, 0);
    rb_define_method(rb_cLazy, "initialize", lazy_initialize, -1);
    rb_define_method(rb_cLazy, "map", lazy_map, 0);
    rb_define_method(rb_cLazy, "collect", lazy_map, 0);
    rb_define_method(rb_cLazy, "flat_map", lazy_flat_map, 0);
    rb_define_method(rb_cLazy, "collect_concat", lazy_flat_map, 0);
    rb_define_method(rb_cLazy, "select", lazy_select, 0);
    rb_define_method(rb_cLazy, "find_all", lazy_select, 0);
    rb_define_method(rb_cLazy, "reject", lazy_reject, 0);
    rb_define_method(rb_cLazy, "grep", lazy_grep, 1);
    rb_define_method(rb_cLazy, "zip", lazy_zip, -1);
    rb_define_method(rb_cLazy, "take", lazy_take, 1);
    rb_define_method(rb_cLazy, "take_while", lazy_take_while, 0);
    rb_define_method(rb_cLazy, "drop", lazy_drop, 1);
    rb_define_method(rb_cLazy, "drop_while", lazy_drop_while, 0);
    rb_define_method(rb_cLazy, "cycle", lazy_cycle, -1);
    rb_define_method(rb_cLazy, "lazy", lazy_lazy, 0);

    rb_define_alias(rb_cLazy, "force", "to_a");

    rb_eStopIteration = rb_define_class("StopIteration", rb_eIndexError);
    rb_define_method(rb_eStopIteration, "result", stop_result, 0);

    /* Generator */
    rb_cGenerator = rb_define_class_under(rb_cEnumerator, "Generator", rb_cObject);
    rb_include_module(rb_cGenerator, rb_mEnumerable);
    rb_define_alloc_func(rb_cGenerator, generator_allocate);
    rb_define_method(rb_cGenerator, "initialize", generator_initialize, -1);
    rb_define_method(rb_cGenerator, "initialize_copy", generator_init_copy, 1);
    rb_define_method(rb_cGenerator, "each", generator_each, -1);

    /* Yielder */
    rb_cYielder = rb_define_class_under(rb_cEnumerator, "Yielder", rb_cObject);
    rb_define_alloc_func(rb_cYielder, yielder_allocate);
    rb_define_method(rb_cYielder, "initialize", yielder_initialize, 0);
    rb_define_method(rb_cYielder, "yield", yielder_yield, -2);
    rb_define_method(rb_cYielder, "<<", yielder_yield_push, -2);

    rb_provide("enumerator.so");	/* for backward compatibility */
}

void
Init_Enumerator(void)
{
    id_rewind = rb_intern("rewind");
    id_each = rb_intern("each");
    id_call = rb_intern("call");
    id_yield = rb_intern("yield");
    id_new = rb_intern("new");
    id_initialize = rb_intern("initialize");
    id_next = rb_intern("next");
    id_result = rb_intern("result");
    id_lazy = rb_intern("lazy");
    id_eqq = rb_intern("===");
    id_receiver = rb_intern("receiver");
    id_arguments = rb_intern("arguments");
    id_method = rb_intern("method");
    sym_each = ID2SYM(id_each);
    sym_cycle = ID2SYM(rb_intern("cycle"));

    InitVM(Enumerator);
}
