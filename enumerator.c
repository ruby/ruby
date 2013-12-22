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
static ID id_rewind, id_each, id_new, id_initialize, id_yield, id_call, id_size, id_to_enum;
static ID id_eqq, id_next, id_result, id_lazy, id_receiver, id_arguments, id_memo, id_method, id_force;
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
    VALUE size;
    rb_enumerator_size_func *size_fn;
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
    rb_gc_mark(ptr->size);
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
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
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
 *   obj.to_enum(method = :each, *args)                 -> enum
 *   obj.enum_for(method = :each, *args)                -> enum
 *   obj.to_enum(method = :each, *args) {|*args| block} -> enum
 *   obj.enum_for(method = :each, *args){|*args| block} -> enum
 *
 * Creates a new Enumerator which will enumerate by calling +method+ on
 * +obj+, passing +args+ if any.
 *
 * If a block is given, it will be used to calculate the size of
 * the enumerator without the need to iterate it (see Enumerator#size).
 *
 * === Examples
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
 * It is typical to call to_enum when defining methods for
 * a generic Enumerable, in case no block is passed.
 *
 * Here is such an example, with parameter passing and a sizing block:
 *
 *   module Enumerable
 *     # a generic method to repeat the values of any enumerable
 *     def repeat(n)
 *       raise ArgumentError, "#{n} is negative!" if n < 0
 *       unless block_given?
 *         return to_enum(__method__, n) do # __method__ is :repeat here
 *           sz = size     # Call size and multiply by n...
 *           sz * n if sz  # but return nil if size itself is nil
 *         end
 *       end
 *       each do |*val|
 *         n.times { yield *val }
 *       end
 *     end
 *   end
 *
 *   %i[hello world].repeat(2) { |w| puts w }
 *     # => Prints 'hello', 'hello', 'world', 'world'
 *   enum = (1..14).repeat(3)
 *     # => returns an Enumerator when called without a block
 *   enum.first(4) # => [1, 1, 1, 2]
 *   enum.size # => 42
 */
static VALUE
obj_to_enum(int argc, VALUE *argv, VALUE obj)
{
    VALUE enumerator, meth = sym_each;

    if (argc > 0) {
	--argc;
	meth = *argv++;
    }
    enumerator = rb_enumeratorize_with_size(obj, meth, argc, argv, 0);
    if (rb_block_given_p()) {
	enumerator_ptr(enumerator)->size = rb_block_proc();
    }
    return enumerator;
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
enumerator_init(VALUE enum_obj, VALUE obj, VALUE meth, int argc, VALUE *argv, rb_enumerator_size_func *size_fn, VALUE size)
{
    struct enumerator *ptr;

    rb_check_frozen(enum_obj);
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
    ptr->size = size;
    ptr->size_fn = size_fn;

    return enum_obj;
}

/*
 * call-seq:
 *   Enumerator.new(size = nil) { |yielder| ... }
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
 * The optional parameter can be used to specify how to calculate the size
 * in a lazy fashion (see Enumerator#size). It can either be a value or
 * a callable object.
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
    VALUE size = Qnil;

    if (rb_block_given_p()) {
	rb_check_arity(argc, 0, 1);
	recv = generator_init(generator_allocate(rb_cGenerator), rb_block_proc());
	if (argc) {
            if (NIL_P(argv[0]) || rb_respond_to(argv[0], id_call) ||
                (RB_TYPE_P(argv[0], T_FLOAT) && RFLOAT_VALUE(argv[0]) == INFINITY)) {
                size = argv[0];
            }
            else {
                size = rb_to_int(argv[0]);
            }
            argc = 0;
        }
    }
    else {
	rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
	rb_warn("Enumerator.new without a block is deprecated; use Object#to_enum");
	recv = *argv++;
	if (--argc) {
	    meth = *argv++;
	    --argc;
	}
    }

    return enumerator_init(obj, recv, meth, argc, argv, 0, size);
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
    ptr1->size  = ptr0->size;
    ptr1->size_fn  = ptr0->size_fn;

    return obj;
}

/*
 * For backwards compatibility; use rb_enumeratorize_with_size
 */
VALUE
rb_enumeratorize(VALUE obj, VALUE meth, int argc, VALUE *argv)
{
    return rb_enumeratorize_with_size(obj, meth, argc, argv, 0);
}

static VALUE
lazy_to_enum_i(VALUE self, VALUE meth, int argc, VALUE *argv, rb_enumerator_size_func *size_fn);

VALUE
rb_enumeratorize_with_size(VALUE obj, VALUE meth, int argc, VALUE *argv, rb_enumerator_size_func *size_fn)
{
    /* Similar effect as calling obj.to_enum, i.e. dispatching to either
       Kernel#to_enum vs Lazy#to_enum */
    if (RTEST(rb_obj_is_kind_of(obj, rb_cLazy)))
	return lazy_to_enum_i(obj, meth, argc, argv, size_fn);
    else
	return enumerator_init(enumerator_allocate(rb_cEnumerator),
			       obj, meth, argc, argv, size_fn, Qnil);
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
 *   enum.each { |elm| block }                    -> obj
 *   enum.each                                    -> enum
 *   enum.each(*appending_args) { |elm| block }   -> obj
 *   enum.each(*appending_args)                   -> an_enumerator
 *
 * Iterates over the block according to how this Enumerator was constructed.
 * If no block and no arguments are given, returns self.
 *
 * === Examples
 *
 *   "Hello, world!".scan(/\w+/)                     #=> ["Hello", "world"]
 *   "Hello, world!".to_enum(:scan, /\w+/).to_a      #=> ["Hello", "world"]
 *   "Hello, world!".to_enum(:scan).each(/\w+/).to_a #=> ["Hello", "world"]
 *
 *   obj = Object.new
 *
 *   def obj.each_arg(a, b=:b, *rest)
 *     yield a
 *     yield b
 *     yield rest
 *     :method_returned
 *   end
 *
 *   enum = obj.to_enum :each_arg, :a, :x
 *
 *   enum.each.to_a                  #=> [:a, :x, []]
 *   enum.each.equal?(enum)          #=> true
 *   enum.each { |elm| elm }         #=> :method_returned
 *
 *   enum.each(:y, :z).to_a          #=> [:a, :x, [:y, :z]]
 *   enum.each(:y, :z).equal?(enum)  #=> false
 *   enum.each(:y, :z) { |elm| elm } #=> :method_returned
 *
 */
static VALUE
enumerator_each(int argc, VALUE *argv, VALUE obj)
{
    if (argc > 0) {
	struct enumerator *e = enumerator_ptr(obj = rb_obj_dup(obj));
	VALUE args = e->args;
	if (args) {
#if SIZEOF_INT < SIZEOF_LONG
	    /* check int range overflow */
	    rb_long2int(RARRAY_LEN(args) + argc);
#endif
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
enumerator_with_index_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    NODE *memo = (NODE *)m;
    VALUE idx = memo->u1.value;
    memo->u1.value = rb_int_succ(idx);

    if (argc <= 1)
	return rb_yield_values(2, val, idx);

    return rb_yield_values(2, rb_ary_new4(argc, argv), idx);
}

static VALUE
enumerator_size(VALUE obj);

static VALUE
enumerator_enum_size(VALUE obj, VALUE args, VALUE eobj)
{
    return enumerator_size(obj);
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
    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enumerator_enum_size);
    if (NIL_P(memo))
	memo = INT2FIX(0);
    else
	memo = rb_to_int(memo);
    return enumerator_block_call(obj, enumerator_with_index_i, (VALUE)NEW_MEMO(memo, 0, 0));
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
enumerator_with_object_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, memo))
{
    if (argc <= 1)
	return rb_yield_values(2, val, memo);

    return rb_yield_values(2, rb_ary_new4(argc, argv), memo);
}

/*
 * call-seq:
 *   e.each_with_object(obj) {|(*args), obj| ... }
 *   e.each_with_object(obj)
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
    RETURN_SIZED_ENUMERATOR(obj, 1, &memo, enumerator_enum_size);
    enumerator_block_call(obj, enumerator_with_object_i, memo);

    return memo;
}

static VALUE
next_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, obj))
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
        return RARRAY_AREF(args, 0);

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
 *   # Array#map passes the array's elements to "yield" and collects the
 *   # results of "yield" as an array.
 *   # Following example shows that "next" returns the passed elements and
 *   # values passed to "feed" are collected as an array which can be
 *   # obtained by StopIteration#result.
 *   e = [1,2,3].map
 *   p e.next           #=> 1
 *   e.feed "a"
 *   p e.next           #=> 2
 *   e.feed "b"
 *   p e.next           #=> 3
 *   e.feed "c"
 *   begin
 *     e.next
 *   rescue StopIteration
 *     p $!.result      #=> ["a", "b", "c"]
 *   end
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

static VALUE append_method(VALUE obj, VALUE str, ID default_method, VALUE default_args);

static VALUE
inspect_enumerator(VALUE obj, VALUE dummy, int recur)
{
    struct enumerator *e;
    VALUE eobj, str, cname;

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, e);

    cname = rb_obj_class(obj);

    if (!e || e->obj == Qundef) {
	return rb_sprintf("#<%"PRIsVALUE": uninitialized>", rb_class_path(cname));
    }

    if (recur) {
	str = rb_sprintf("#<%"PRIsVALUE": ...>", rb_class_path(cname));
	OBJ_TAINT(str);
	return str;
    }

    eobj = rb_attr_get(obj, id_receiver);
    if (NIL_P(eobj)) {
	eobj = e->obj;
    }

    /* (1..100).each_cons(2) => "#<Enumerator: 1..100:each_cons(2)>" */
    str = rb_sprintf("#<%"PRIsVALUE": %+"PRIsVALUE, rb_class_path(cname), eobj);
    append_method(obj, str, e->meth, e->args);

    rb_str_buf_cat2(str, ">");

    return str;
}

static VALUE
append_method(VALUE obj, VALUE str, ID default_method, VALUE default_args)
{
    VALUE method, eargs;

    method = rb_attr_get(obj, id_method);
    if (method != Qfalse) {
	ID mid = default_method;
	if (!NIL_P(method)) {
	    Check_Type(method, T_SYMBOL);
	    mid = SYM2ID(method);
	}
	rb_str_buf_cat2(str, ":");
	rb_str_buf_append(str, rb_id2str(mid));
    }

    eargs = rb_attr_get(obj, id_arguments);
    if (NIL_P(eargs)) {
	eargs = default_args;
    }
    if (eargs != Qfalse) {
	long   argc = RARRAY_LEN(eargs);
	const VALUE *argv = RARRAY_CONST_PTR(eargs); /* WB: no new reference */

	if (argc > 0) {
	    rb_str_buf_cat2(str, "(");

	    while (argc--) {
		VALUE arg = *argv++;

		rb_str_append(str, rb_inspect(arg));
		rb_str_buf_cat2(str, argc > 0 ? ", " : ")");
		OBJ_INFECT(str, arg);
	    }
	}
    }

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
 * call-seq:
 *   e.size          -> int, Float::INFINITY or nil
 *
 * Returns the size of the enumerator, or +nil+ if it can't be calculated lazily.
 *
 *   (1..100).to_a.permutation(4).size # => 94109400
 *   loop.size # => Float::INFINITY
 *   (1..100).drop_while.size # => nil
 */

static VALUE
enumerator_size(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    int argc = 0;
    const VALUE *argv = NULL;
    VALUE size;

    if (e->size_fn) {
	return (*e->size_fn)(e->obj, e->args, obj);
    }
    if (e->args) {
	argc = (int)RARRAY_LEN(e->args);
	argv = RARRAY_CONST_PTR(e->args);
    }
    size = rb_check_funcall(e->size, id_call, argc, argv);
    if (size != Qundef) return size;
    return e->size;
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
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
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
yielder_yield_i(RB_BLOCK_CALL_FUNC_ARGLIST(obj, memo))
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
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
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

    rb_check_frozen(obj);
    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr);

    if (!ptr) {
	rb_raise(rb_eArgError, "unallocated generator");
    }

    ptr->proc = proc;

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
static VALUE
enum_size(VALUE self)
{
    VALUE r = rb_check_funcall(self, id_size, 0, 0);
    return (r == Qundef) ? Qnil : r;
}

static VALUE
lazyenum_size(VALUE self, VALUE args, VALUE eobj)
{
    return enum_size(self);
}

static VALUE
lazy_size(VALUE self)
{
    return enum_size(rb_ivar_get(self, id_receiver));
}

static VALUE
lazy_receiver_size(VALUE generator, VALUE args, VALUE lazy)
{
    return lazy_size(lazy);
}

static VALUE
lazy_init_iterator(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
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
	result = rb_yield_values2(len, RARRAY_CONST_PTR(args));
	RB_GC_GUARD(args);
    }
    if (result == Qundef) rb_iter_break();
    return Qnil;
}

static VALUE
lazy_init_block_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    rb_block_call(m, id_each, argc-1, argv+1, lazy_init_iterator, val);
    return Qnil;
}

/*
 * call-seq:
 *   Lazy.new(obj, size=nil) { |yielder, *values| ... }
 *
 * Creates a new Lazy enumerator. When the enumerator is actually enumerated
 * (e.g. by calling #force), +obj+ will be enumerated and each value passed
 * to the given block. The block can yield values back using +yielder+.
 * For example, to create a method +filter_map+ in both lazy and
 * non-lazy fashions:
 *
 *   module Enumerable
 *     def filter_map(&block)
 *       map(&block).compact
 *     end
 *   end
 *
 *   class Enumerator::Lazy
 *     def filter_map
 *       Lazy.new(self) do |yielder, *values|
 *         result = yield *values
 *         yielder << result if result
 *       end
 *     end
 *   end
 *
 *   (1..Float::INFINITY).lazy.filter_map{|i| i*i if i.even?}.first(5)
 *       # => [4, 16, 36, 64, 100]
 */
static VALUE
lazy_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE obj, size = Qnil;
    VALUE generator;

    rb_check_arity(argc, 1, 2);
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy new without a block");
    }
    obj = argv[0];
    if (argc > 1) {
	size = argv[1];
    }
    generator = generator_allocate(rb_cGenerator);
    rb_block_call(generator, id_initialize, 0, 0, lazy_init_block_i, obj);
    enumerator_init(self, generator, sym_each, 0, 0, 0, size);
    rb_ivar_set(self, id_receiver, obj);

    return self;
}

static VALUE
lazy_set_method(VALUE lazy, VALUE args, rb_enumerator_size_func *size_fn)
{
    ID id = rb_frame_this_func();
    struct enumerator *e = enumerator_ptr(lazy);
    rb_ivar_set(lazy, id_method, ID2SYM(id));
    if (NIL_P(args)) {
	/* Qfalse indicates that the arguments are empty */
	rb_ivar_set(lazy, id_arguments, Qfalse);
    }
    else {
	rb_ivar_set(lazy, id_arguments, args);
    }
    e->size_fn = size_fn;
    return lazy;
}

/*
 * call-seq:
 *   e.lazy -> lazy_enumerator
 *
 * Returns a lazy enumerator, whose methods map/collect,
 * flat_map/collect_concat, select/find_all, reject, grep, zip, take,
 * take_while, drop, and drop_while enumerate values only on an
 * as-needed basis.  However, if a block is given to zip, values
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
    VALUE result = lazy_to_enum_i(obj, sym_each, 0, 0, lazyenum_size);
    /* Qfalse indicates that the Enumerator::Lazy has no method name */
    rb_ivar_set(result, id_method, Qfalse);
    return result;
}

static VALUE
lazy_to_enum_i(VALUE obj, VALUE meth, int argc, VALUE *argv, rb_enumerator_size_func *size_fn)
{
    return enumerator_init(enumerator_allocate(rb_cLazy),
			   obj, meth, argc, argv, size_fn, Qnil);
}

/*
 * call-seq:
 *   lzy.to_enum(method = :each, *args)                 -> lazy_enum
 *   lzy.enum_for(method = :each, *args)                -> lazy_enum
 *   lzy.to_enum(method = :each, *args) {|*args| block} -> lazy_enum
 *   lzy.enum_for(method = :each, *args){|*args| block} -> lazy_enum
 *
 * Similar to Kernel#to_enum, except it returns a lazy enumerator.
 * This makes it easy to define Enumerable methods that will
 * naturally remain lazy if called from a lazy enumerator.
 *
 * For example, continuing from the example in Kernel#to_enum:
 *
 *   # See Kernel#to_enum for the definition of repeat
 *   r = 1..Float::INFINITY
 *   r.repeat(2).first(5) # => [1, 1, 2, 2, 3]
 *   r.repeat(2).class # => Enumerator
 *   r.repeat(2).map{|n| n ** 2}.first(5) # => endless loop!
 *   # works naturally on lazy enumerator:
 *   r.lazy.repeat(2).class # => Enumerator::Lazy
 *   r.lazy.repeat(2).map{|n| n ** 2}.first(5) # => [1, 1, 4, 4, 9]
 */

static VALUE
lazy_to_enum(int argc, VALUE *argv, VALUE self)
{
    VALUE lazy, meth = sym_each;

    if (argc > 0) {
	--argc;
	meth = *argv++;
    }
    lazy = lazy_to_enum_i(self, meth, argc, argv, 0);
    if (rb_block_given_p()) {
	enumerator_ptr(lazy)->size = rb_block_proc();
    }
    return lazy;
}

static VALUE
lazy_map_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE result = rb_yield_values2(argc - 1, &argv[1]);

    rb_funcall(argv[0], id_yield, 1, result);
    return Qnil;
}

static VALUE
lazy_map(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy map without a block");
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_map_func, 0),
			   Qnil, lazy_receiver_size);
}

static VALUE
lazy_flat_map_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, yielder))
{
    return rb_funcall2(yielder, id_yield, argc, argv);
}

static VALUE
lazy_flat_map_each(VALUE obj, VALUE yielder)
{
    rb_block_call(obj, id_each, 0, 0, lazy_flat_map_i, yielder);
    return Qnil;
}

static VALUE
lazy_flat_map_to_ary(VALUE obj, VALUE yielder)
{
    VALUE ary = rb_check_array_type(obj);
    if (NIL_P(ary)) {
	rb_funcall(yielder, id_yield, 1, obj);
    }
    else {
	long i;
	for (i = 0; i < RARRAY_LEN(ary); i++) {
	    rb_funcall(yielder, id_yield, 1, RARRAY_AREF(ary, i));
	}
    }
    return Qnil;
}

static VALUE
lazy_flat_map_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE result = rb_yield_values2(argc - 1, &argv[1]);
    if (RB_TYPE_P(result, T_ARRAY)) {
	long i;
	for (i = 0; i < RARRAY_LEN(result); i++) {
	    rb_funcall(argv[0], id_yield, 1, RARRAY_AREF(result, i));
	}
    }
    else {
	if (rb_respond_to(result, id_force) && rb_respond_to(result, id_each)) {
	    lazy_flat_map_each(result, argv[0]);
	}
	else {
	    lazy_flat_map_to_ary(result, argv[0]);
	}
    }
    return Qnil;
}

/*
 *  call-seq:
 *     lazy.collect_concat { |obj| block } -> a_lazy_enumerator
 *     lazy.flat_map       { |obj| block } -> a_lazy_enumerator
 *
 *  Returns a new lazy enumerator with the concatenated results of running
 *  <i>block</i> once for every element in <i>lazy</i>.
 *
 *    ["foo", "bar"].lazy.flat_map {|i| i.each_char.lazy}.force
 *    #=> ["f", "o", "o", "b", "a", "r"]
 *
 *  A value <i>x</i> returned by <i>block</i> is decomposed if either of
 *  the following conditions is true:
 *
 *    a) <i>x</i> responds to both each and force, which means that
 *       <i>x</i> is a lazy enumerator.
 *    b) <i>x</i> is an array or responds to to_ary.
 *
 *  Otherwise, <i>x</i> is contained as-is in the return value.
 *
 *    [{a:1}, {b:2}].lazy.flat_map {|i| i}.force
 *    #=> [{:a=>1}, {:b=>2}]
 */
static VALUE
lazy_flat_map(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy flat_map without a block");
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_flat_map_func, 0),
			   Qnil, 0);
}

static VALUE
lazy_select_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE element = rb_enum_values_pack(argc - 1, argv + 1);

    if (RTEST(rb_yield(element))) {
	return rb_funcall(argv[0], id_yield, 1, element);
    }
    return Qnil;
}

static VALUE
lazy_select(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy select without a block");
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_select_func, 0),
			   Qnil, 0);
}

static VALUE
lazy_reject_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE element = rb_enum_values_pack(argc - 1, argv + 1);

    if (!RTEST(rb_yield(element))) {
	return rb_funcall(argv[0], id_yield, 1, element);
    }
    return Qnil;
}

static VALUE
lazy_reject(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy reject without a block");
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_reject_func, 0),
			   Qnil, 0);
}

static VALUE
lazy_grep_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE i = rb_enum_values_pack(argc - 1, argv + 1);
    VALUE result = rb_funcall(m, id_eqq, 1, i);

    if (RTEST(result)) {
	rb_funcall(argv[0], id_yield, 1, i);
    }
    return Qnil;
}

static VALUE
lazy_grep_iter(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE i = rb_enum_values_pack(argc - 1, argv + 1);
    VALUE result = rb_funcall(m, id_eqq, 1, i);

    if (RTEST(result)) {
	rb_funcall(argv[0], id_yield, 1, rb_yield(i));
    }
    return Qnil;
}

static VALUE
lazy_grep(VALUE obj, VALUE pattern)
{
    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 rb_block_given_p() ?
					 lazy_grep_iter : lazy_grep_func,
					 pattern),
			   rb_ary_new3(1, pattern), 0);
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
lazy_zip_arrays_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, arrays))
{
    VALUE yielder, ary, memo;
    long i, count;

    yielder = argv[0];
    memo = rb_attr_get(yielder, id_memo);
    count = NIL_P(memo) ? 0 : NUM2LONG(memo);

    ary = rb_ary_new2(RARRAY_LEN(arrays) + 1);
    rb_ary_push(ary, argv[1]);
    for (i = 0; i < RARRAY_LEN(arrays); i++) {
	rb_ary_push(ary, rb_ary_entry(RARRAY_AREF(arrays, i), count));
    }
    rb_funcall(yielder, id_yield, 1, ary);
    rb_ivar_set(yielder, id_memo, LONG2NUM(++count));
    return Qnil;
}

static VALUE
lazy_zip_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, zip_args))
{
    VALUE yielder, ary, arg, v;
    long i;

    yielder = argv[0];
    arg = rb_attr_get(yielder, id_memo);
    if (NIL_P(arg)) {
	arg = rb_ary_new2(RARRAY_LEN(zip_args));
	for (i = 0; i < RARRAY_LEN(zip_args); i++) {
	    rb_ary_push(arg, rb_funcall(RARRAY_AREF(zip_args, i), id_to_enum, 0));
	}
	rb_ivar_set(yielder, id_memo, arg);
    }

    ary = rb_ary_new2(RARRAY_LEN(arg) + 1);
    v = Qnil;
    if (--argc > 0) {
	++argv;
	v = argc > 1 ? rb_ary_new_from_values(argc, argv) : *argv;
    }
    rb_ary_push(ary, v);
    for (i = 0; i < RARRAY_LEN(arg); i++) {
	v = rb_rescue2(call_next, RARRAY_AREF(arg, i), next_stopped, 0,
		       rb_eStopIteration, (VALUE)0);
	rb_ary_push(ary, v);
    }
    rb_funcall(yielder, id_yield, 1, ary);
    return Qnil;
}

static VALUE
lazy_zip(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary, v;
    long i;
    rb_block_call_func *func = lazy_zip_arrays_func;

    if (rb_block_given_p()) {
	return rb_call_super(argc, argv);
    }

    ary = rb_ary_new2(argc);
    for (i = 0; i < argc; i++) {
	v = rb_check_array_type(argv[i]);
	if (NIL_P(v)) {
	    for (; i < argc; i++) {
		if (!rb_respond_to(argv[i], id_each)) {
		    rb_raise(rb_eTypeError, "wrong argument type %s (must respond to :each)",
			rb_obj_classname(argv[i]));
		}
	    }
	    ary = rb_ary_new4(argc, argv);
	    func = lazy_zip_func;
	    break;
	}
	rb_ary_push(ary, v);
    }

    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 func, ary),
			   ary, lazy_receiver_size);
}

static VALUE
lazy_take_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, args))
{
    long remain;
    VALUE memo = rb_attr_get(argv[0], id_memo);
    if (NIL_P(memo)) {
	memo = args;
    }

    rb_funcall2(argv[0], id_yield, argc - 1, argv + 1);
    if ((remain = NUM2LONG(memo)-1) == 0) {
	return Qundef;
    }
    else {
	rb_ivar_set(argv[0], id_memo, LONG2NUM(remain));
	return Qnil;
    }
}

static VALUE
lazy_take_size(VALUE generator, VALUE args, VALUE lazy)
{
    VALUE receiver = lazy_size(lazy);
    long len = NUM2LONG(RARRAY_AREF(rb_ivar_get(lazy, id_arguments), 0));
    if (NIL_P(receiver) || (FIXNUM_P(receiver) && FIX2LONG(receiver) < len))
	return receiver;
    return LONG2NUM(len);
}

static VALUE
lazy_take(VALUE obj, VALUE n)
{
    long len = NUM2LONG(n);
    VALUE lazy;

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to take negative size");
    }
    if (len == 0) {
	VALUE len = INT2FIX(0);
	lazy = lazy_to_enum_i(obj, sym_cycle, 1, &len, 0);
    }
    else {
	lazy = rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_take_func, n);
    }
    return lazy_set_method(lazy, rb_ary_new3(1, n), lazy_take_size);
}

static VALUE
lazy_take_while_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, args))
{
    VALUE result = rb_yield_values2(argc - 1, &argv[1]);
    if (!RTEST(result)) return Qundef;
    rb_funcall2(argv[0], id_yield, argc - 1, argv + 1);
    return Qnil;
}

static VALUE
lazy_take_while(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy take_while without a block");
    }
    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_take_while_func, 0),
			   Qnil, 0);
}

static VALUE
lazy_drop_size(VALUE generator, VALUE args, VALUE lazy)
{
    long len = NUM2LONG(RARRAY_AREF(rb_ivar_get(lazy, id_arguments), 0));
    VALUE receiver = lazy_size(lazy);
    if (NIL_P(receiver))
	return receiver;
    if (FIXNUM_P(receiver)) {
	len = FIX2LONG(receiver) - len;
	return LONG2FIX(len < 0 ? 0 : len);
    }
    return rb_funcall(receiver, '-', 1, LONG2NUM(len));
}

static VALUE
lazy_drop_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, args))
{
    long remain;
    VALUE memo = rb_attr_get(argv[0], id_memo);
    if (NIL_P(memo)) {
	memo = args;
    }
    if ((remain = NUM2LONG(memo)) == 0) {
	rb_funcall2(argv[0], id_yield, argc - 1, argv + 1);
    }
    else {
	rb_ivar_set(argv[0], id_memo, LONG2NUM(--remain));
    }
    return Qnil;
}

static VALUE
lazy_drop(VALUE obj, VALUE n)
{
    long len = NUM2LONG(n);

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to drop negative size");
    }
    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_drop_func, n),
			   rb_ary_new3(1, n), lazy_drop_size);
}

static VALUE
lazy_drop_while_func(RB_BLOCK_CALL_FUNC_ARGLIST(val, args))
{
    VALUE memo = rb_attr_get(argv[0], id_memo);
    if (NIL_P(memo) && !RTEST(rb_yield_values2(argc - 1, &argv[1]))) {
	rb_ivar_set(argv[0], id_memo, memo = Qtrue);
    }
    if (memo == Qtrue) {
	rb_funcall2(argv[0], id_yield, argc - 1, argv + 1);
    }
    return Qnil;
}

static VALUE
lazy_drop_while(VALUE obj)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "tried to call lazy drop_while without a block");
    }
    return lazy_set_method(rb_block_call(rb_cLazy, id_new, 1, &obj,
					 lazy_drop_while_func, 0),
			   Qnil, 0);
}

static VALUE
lazy_super(int argc, VALUE *argv, VALUE lazy)
{
    return enumerable_lazy(rb_call_super(argc, argv));
}

static VALUE
lazy_lazy(VALUE obj)
{
    return obj;
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
    rb_define_method(rb_cEnumerator, "size", enumerator_size, 0);

    /* Lazy */
    rb_cLazy = rb_define_class_under(rb_cEnumerator, "Lazy", rb_cEnumerator);
    rb_define_method(rb_mEnumerable, "lazy", enumerable_lazy, 0);
    rb_define_method(rb_cLazy, "initialize", lazy_initialize, -1);
    rb_define_method(rb_cLazy, "to_enum", lazy_to_enum, -1);
    rb_define_method(rb_cLazy, "enum_for", lazy_to_enum, -1);
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
    rb_define_method(rb_cLazy, "lazy", lazy_lazy, 0);
    rb_define_method(rb_cLazy, "chunk", lazy_super, -1);
    rb_define_method(rb_cLazy, "slice_before", lazy_super, -1);

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
    id_size = rb_intern("size");
    id_yield = rb_intern("yield");
    id_new = rb_intern("new");
    id_initialize = rb_intern("initialize");
    id_next = rb_intern("next");
    id_result = rb_intern("result");
    id_lazy = rb_intern("lazy");
    id_eqq = rb_intern("===");
    id_receiver = rb_intern("receiver");
    id_arguments = rb_intern("arguments");
    id_memo = rb_intern("memo");
    id_method = rb_intern("method");
    id_force = rb_intern("force");
    id_to_enum = rb_intern("to_enum");
    sym_each = ID2SYM(id_each);
    sym_cycle = ID2SYM(rb_intern("cycle"));

    InitVM(Enumerator);
}
