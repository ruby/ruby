/************************************************

  enumerator.c - provides Enumerator class

  $Author$

  Copyright (C) 2001-2003 Akinori MUSHA

  $Idaemons: /home/cvs/rb/enumerator/enumerator.c,v 1.1.1.1 2001/07/15 10:12:48 knu Exp $
  $RoughId: enumerator.c,v 1.6 2003/07/27 11:03:24 nobu Exp $
  $Id$

************************************************/

#include "ruby/internal/config.h"

#ifdef HAVE_FLOAT_H
#include <float.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/enumerator.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/imemo.h"
#include "internal/numeric.h"
#include "internal/range.h"
#include "internal/rational.h"
#include "ruby/ruby.h"

/*
 * Document-class: Enumerator
 *
 * A class which allows both internal and external iteration.
 *
 * An Enumerator can be created by the following methods.
 * - Object#to_enum
 * - Object#enum_for
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
 * == External Iteration
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
 * +next+, +next_values+, +peek+, and +peek_values+ are the only methods
 * which use external iteration (and Array#zip(Enumerable-not-Array) which uses +next+ internally).
 *
 * These methods do not affect other internal enumeration methods,
 * unless the underlying iteration method itself has side-effect, e.g. IO#each_line.
 *
 * FrozenError will be raised if these methods are called against a frozen enumerator.
 * Since +rewind+ and +feed+ also change state for external iteration,
 * these methods may raise FrozenError too.
 *
 * External iteration differs *significantly* from internal iteration
 * due to using a Fiber:
 * - The Fiber adds some overhead compared to internal enumeration.
 * - The stacktrace will only include the stack from the Enumerator, not above.
 * - Fiber-local variables are *not* inherited inside the Enumerator Fiber,
 *   which instead starts with no Fiber-local variables.
 * - Fiber storage variables *are* inherited and are designed
 *   to handle Enumerator Fibers. Assigning to a Fiber storage variable
 *   only affects the current Fiber, so if you want to change state
 *   in the caller Fiber of the Enumerator Fiber, you need to use an
 *   extra indirection (e.g., use some object in the Fiber storage
 *   variable and mutate some ivar of it).
 *
 * Concretely:
 *
 *   Thread.current[:fiber_local] = 1
 *   Fiber[:storage_var] = 1
 *   e = Enumerator.new do |y|
 *     p Thread.current[:fiber_local] # for external iteration: nil, for internal iteration: 1
 *     p Fiber[:storage_var] # => 1, inherited
 *     Fiber[:storage_var] += 1
 *     y << 42
 *   end
 *
 *   p e.next # => 42
 *   p Fiber[:storage_var] # => 1 (it ran in a different Fiber)
 *
 *   e.each { p _1 }
 *   p Fiber[:storage_var] # => 2 (it ran in the same Fiber/"stack" as the current Fiber)
 *
 * == Convert External Iteration to Internal Iteration
 *
 * You can use an external iterator to implement an internal iterator as follows:
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
static VALUE rb_cLazy;
static ID id_rewind, id_new, id_to_enum, id_each_entry;
static ID id_next, id_result, id_receiver, id_arguments, id_memo, id_method, id_force;
static ID id_begin, id_end, id_step, id_exclude_end;
static VALUE sym_each, sym_cycle, sym_yield;

static VALUE lazy_use_super_method;

extern ID ruby_static_id_cause;

#define id_call idCall
#define id_cause ruby_static_id_cause
#define id_each idEach
#define id_eqq idEqq
#define id_initialize idInitialize
#define id_size idSize

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
    VALUE procs;
    rb_enumerator_size_func *size_fn;
    int kw_splat;
};

RUBY_REFERENCES(enumerator_refs) = {
    RUBY_REF_EDGE(struct enumerator, obj),
    RUBY_REF_EDGE(struct enumerator, args),
    RUBY_REF_EDGE(struct enumerator, fib),
    RUBY_REF_EDGE(struct enumerator, dst),
    RUBY_REF_EDGE(struct enumerator, lookahead),
    RUBY_REF_EDGE(struct enumerator, feedvalue),
    RUBY_REF_EDGE(struct enumerator, stop_exc),
    RUBY_REF_EDGE(struct enumerator, size),
    RUBY_REF_EDGE(struct enumerator, procs),
    RUBY_REF_END
};

static VALUE rb_cGenerator, rb_cYielder, rb_cEnumProducer;

struct generator {
    VALUE proc;
    VALUE obj;
};

struct yielder {
    VALUE proc;
};

struct producer {
    VALUE init;
    VALUE proc;
};

typedef struct MEMO *lazyenum_proc_func(VALUE, struct MEMO *, VALUE, long);
typedef VALUE lazyenum_size_func(VALUE, VALUE);
typedef int lazyenum_precheck_func(VALUE proc_entry);
typedef struct {
    lazyenum_proc_func *proc;
    lazyenum_size_func *size;
    lazyenum_precheck_func *precheck;
} lazyenum_funcs;

struct proc_entry {
    VALUE proc;
    VALUE memo;
    const lazyenum_funcs *fn;
};

static VALUE generator_allocate(VALUE klass);
static VALUE generator_init(VALUE obj, VALUE proc);

static VALUE rb_cEnumChain;

struct enum_chain {
    VALUE enums;
    long pos;
};

static VALUE rb_cEnumProduct;

struct enum_product {
    VALUE enums;
};

VALUE rb_cArithSeq;

static const rb_data_type_t enumerator_data_type = {
    "enumerator",
    {
        RUBY_REFS_LIST_PTR(enumerator_refs),
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // Nothing allocated externally, so don't need a memsize function
        NULL,
    },
    0, NULL, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_DECL_MARKING | RUBY_TYPED_EMBEDDABLE
};

static struct enumerator *
enumerator_ptr(VALUE obj)
{
    struct enumerator *ptr;

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->obj)) {
        rb_raise(rb_eArgError, "uninitialized enumerator");
    }
    return ptr;
}

static void
proc_entry_mark(void *p)
{
    struct proc_entry *ptr = p;
    rb_gc_mark_movable(ptr->proc);
    rb_gc_mark_movable(ptr->memo);
}

static void
proc_entry_compact(void *p)
{
    struct proc_entry *ptr = p;
    ptr->proc = rb_gc_location(ptr->proc);
    ptr->memo = rb_gc_location(ptr->memo);
}

static const rb_data_type_t proc_entry_data_type = {
    "proc_entry",
    {
        proc_entry_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // Nothing allocated externally, so don't need a memsize function
        proc_entry_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static struct proc_entry *
proc_entry_ptr(VALUE proc_entry)
{
    struct proc_entry *ptr;

    TypedData_Get_Struct(proc_entry, struct proc_entry, &proc_entry_data_type, ptr);

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
 * +obj+, passing +args+ if any. What was _yielded_ by method becomes
 * values of enumerator.
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
 *   # String#split in block form is more memory-effective:
 *   very_large_string.split("|") { |chunk| return chunk if chunk.include?('DATE') }
 *   # This could be rewritten more idiomatically with to_enum:
 *   very_large_string.to_enum(:split, "|").lazy.grep(/DATE/).first
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
        RB_OBJ_WRITE(enumerator, &enumerator_ptr(enumerator)->size, rb_block_proc());
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
enumerator_init(VALUE enum_obj, VALUE obj, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *size_fn, VALUE size, int kw_splat)
{
    struct enumerator *ptr;

    rb_check_frozen(enum_obj);
    TypedData_Get_Struct(enum_obj, struct enumerator, &enumerator_data_type, ptr);

    if (!ptr) {
        rb_raise(rb_eArgError, "unallocated enumerator");
    }

    RB_OBJ_WRITE(enum_obj, &ptr->obj, obj);
    ptr->meth = rb_to_id(meth);
    if (argc) RB_OBJ_WRITE(enum_obj, &ptr->args, rb_ary_new4(argc, argv));
    ptr->fib = 0;
    ptr->dst = Qnil;
    ptr->lookahead = Qundef;
    ptr->feedvalue = Qundef;
    ptr->stop_exc = Qfalse;
    RB_OBJ_WRITE(enum_obj, &ptr->size, size);
    ptr->size_fn = size_fn;
    ptr->kw_splat = kw_splat;

    return enum_obj;
}

static VALUE
convert_to_feasible_size_value(VALUE obj)
{
    if (NIL_P(obj)) {
        return obj;
    }
    else if (rb_respond_to(obj, id_call)) {
        return obj;
    }
    else if (RB_FLOAT_TYPE_P(obj) && RFLOAT_VALUE(obj) == HUGE_VAL) {
        return obj;
    }
    else {
        return rb_to_int(obj);
    }
}

/*
 * call-seq:
 *   Enumerator.new(size = nil) { |yielder| ... }
 *
 * Creates a new Enumerator object, which can be used as an
 * Enumerable.
 *
 * Iteration is defined by the given block, in
 * which a "yielder" object, given as block parameter, can be used to
 * yield a value by calling the +yield+ method (aliased as <code><<</code>):
 *
 *   fib = Enumerator.new do |y|
 *     a = b = 1
 *     loop do
 *       y << a
 *       a, b = b, a + b
 *     end
 *   end
 *
 *   fib.take(10) # => [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
 *
 * The optional parameter can be used to specify how to calculate the size
 * in a lazy fashion (see Enumerator#size). It can either be a value or
 * a callable object.
 */
static VALUE
enumerator_initialize(int argc, VALUE *argv, VALUE obj)
{
    VALUE iter = rb_block_proc();
    VALUE recv = generator_init(generator_allocate(rb_cGenerator), iter);
    VALUE arg0 = rb_check_arity(argc, 0, 1) ? argv[0] : Qnil;
    VALUE size = convert_to_feasible_size_value(arg0);

    return enumerator_init(obj, recv, sym_each, 0, 0, 0, size, false);
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

    RB_OBJ_WRITE(obj, &ptr1->obj, ptr0->obj);
    ptr1->meth = ptr0->meth;
    RB_OBJ_WRITE(obj, &ptr1->args, ptr0->args);
    ptr1->fib  = 0;
    ptr1->lookahead  = Qundef;
    ptr1->feedvalue  = Qundef;
    RB_OBJ_WRITE(obj, &ptr1->size, ptr0->size);
    ptr1->size_fn  = ptr0->size_fn;

    return obj;
}

/*
 * For backwards compatibility; use rb_enumeratorize_with_size
 */
VALUE
rb_enumeratorize(VALUE obj, VALUE meth, int argc, const VALUE *argv)
{
    return rb_enumeratorize_with_size(obj, meth, argc, argv, 0);
}

static VALUE lazy_to_enum_i(VALUE self, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *size_fn, int kw_splat);
static int lazy_precheck(VALUE procs);

VALUE
rb_enumeratorize_with_size_kw(VALUE obj, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *size_fn, int kw_splat)
{
    VALUE base_class = rb_cEnumerator;

    if (RTEST(rb_obj_is_kind_of(obj, rb_cLazy))) {
        base_class = rb_cLazy;
    }
    else if (RTEST(rb_obj_is_kind_of(obj, rb_cEnumChain))) {
        obj = enumerator_init(enumerator_allocate(rb_cEnumerator), obj, sym_each, 0, 0, 0, Qnil, false);
    }

    return enumerator_init(enumerator_allocate(base_class),
                           obj, meth, argc, argv, size_fn, Qnil, kw_splat);
}

VALUE
rb_enumeratorize_with_size(VALUE obj, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *size_fn)
{
    return rb_enumeratorize_with_size_kw(obj, meth, argc, argv, size_fn, rb_keyword_given_p());
}

static VALUE
enumerator_block_call(VALUE obj, rb_block_call_func *func, VALUE arg)
{
    int argc = 0;
    const VALUE *argv = 0;
    const struct enumerator *e = enumerator_ptr(obj);
    ID meth = e->meth;

    VALUE args = e->args;
    if (args) {
        argc = RARRAY_LENINT(args);
        argv = RARRAY_CONST_PTR(args);
    }

    VALUE ret = rb_block_call_kw(e->obj, meth, argc, argv, func, arg, e->kw_splat);

    RB_GC_GUARD(args);

    return ret;
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
    struct enumerator *e = enumerator_ptr(obj);

    if (argc > 0) {
        VALUE args = (e = enumerator_ptr(obj = rb_obj_dup(obj)))->args;
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
        RB_OBJ_WRITE(obj, &e->args, args);
        e->size = Qnil;
        e->size_fn = 0;
    }
    if (!rb_block_given_p()) return obj;

    if (!lazy_precheck(e->procs)) return Qnil;

    return enumerator_block_call(obj, 0, obj);
}

static VALUE
enumerator_with_index_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    struct MEMO *memo = (struct MEMO *)m;
    VALUE idx = memo->v1;
    MEMO_V1_SET(memo, rb_int_succ(idx));

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

    rb_check_arity(argc, 0, 1);
    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enumerator_enum_size);
    memo = (!argc || NIL_P(memo = argv[0])) ? INT2FIX(0) : rb_to_int(memo);
    return enumerator_block_call(obj, enumerator_with_index_i, (VALUE)MEMO_NEW(memo, 0, 0));
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
 *   # => foo: 0
 *   # => foo: 1
 *   # => foo: 2
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
    if (!UNDEF_P(e->feedvalue)) {
        feedvalue = e->feedvalue;
        e->feedvalue = Qundef;
    }
    return feedvalue;
}

static VALUE
next_i(RB_BLOCK_CALL_FUNC_ARGLIST(_, obj))
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE nil = Qnil;
    VALUE result;

    result = rb_block_call(obj, id_each, 0, 0, next_ii, obj);
    RB_OBJ_WRITE(obj, &e->stop_exc, rb_exc_new2(rb_eStopIteration, "iteration reached an end"));
    rb_ivar_set(e->stop_exc, id_result, result);
    return rb_fiber_yield(1, &nil);
}

static void
next_init(VALUE obj, struct enumerator *e)
{
    VALUE curr = rb_fiber_current();
    RB_OBJ_WRITE(obj, &e->dst, curr);
    RB_OBJ_WRITE(obj, &e->fib, rb_fiber_new(next_i, obj));
    e->lookahead = Qundef;
}

static VALUE
get_next_values(VALUE obj, struct enumerator *e)
{
    VALUE curr, vs;

    if (e->stop_exc) {
        VALUE exc = e->stop_exc;
        VALUE result = rb_attr_get(exc, id_result);
        VALUE mesg = rb_attr_get(exc, idMesg);
        if (!NIL_P(mesg)) mesg = rb_str_dup(mesg);
        VALUE stop_exc = rb_exc_new_str(rb_eStopIteration, mesg);
        rb_ivar_set(stop_exc, id_cause, exc);
        rb_ivar_set(stop_exc, id_result, result);
        rb_exc_raise(stop_exc);
    }

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
 * See class-level notes about external iterators.
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
 */

static VALUE
enumerator_next_values(VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE vs;

    rb_check_frozen(obj);

    if (!UNDEF_P(e->lookahead)) {
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
 * See class-level notes about external iterators.
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

    rb_check_frozen(obj);

    if (UNDEF_P(e->lookahead)) {
        RB_OBJ_WRITE(obj, &e->lookahead, get_next_values(obj, e));
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
 * See class-level notes about external iterators.
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
 * See class-level notes about external iterators.
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
 *   p e.peek   #raises StopIteration
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

    rb_check_frozen(obj);

    if (!UNDEF_P(e->feedvalue)) {
        rb_raise(rb_eTypeError, "feed value already set");
    }
    RB_OBJ_WRITE(obj, &e->feedvalue, v);

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

    rb_check_frozen(obj);

    rb_check_funcall(e->obj, id_rewind, 0, 0);

    e->fib = 0;
    e->dst = Qnil;
    e->lookahead = Qundef;
    e->feedvalue = Qundef;
    e->stop_exc = Qfalse;
    return obj;
}

static struct generator *generator_ptr(VALUE obj);
static VALUE append_method(VALUE obj, VALUE str, ID default_method, VALUE default_args);

static VALUE
inspect_enumerator(VALUE obj, VALUE dummy, int recur)
{
    struct enumerator *e;
    VALUE eobj, str, cname;

    TypedData_Get_Struct(obj, struct enumerator, &enumerator_data_type, e);

    cname = rb_obj_class(obj);

    if (!e || UNDEF_P(e->obj)) {
        return rb_sprintf("#<%"PRIsVALUE": uninitialized>", rb_class_path(cname));
    }

    if (recur) {
        str = rb_sprintf("#<%"PRIsVALUE": ...>", rb_class_path(cname));
        return str;
    }

    if (e->procs) {
        long i;

        eobj = generator_ptr(e->obj)->obj;
        /* In case procs chained enumerator traversing all proc entries manually */
        if (rb_obj_class(eobj) == cname) {
            str = rb_inspect(eobj);
        }
        else {
            str = rb_sprintf("#<%"PRIsVALUE": %+"PRIsVALUE">", rb_class_path(cname), eobj);
        }
        for (i = 0; i < RARRAY_LEN(e->procs); i++) {
            str = rb_sprintf("#<%"PRIsVALUE": %"PRIsVALUE, cname, str);
            append_method(RARRAY_AREF(e->procs, i), str, e->meth, e->args);
            rb_str_buf_cat2(str, ">");
        }
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

static int
key_symbol_p(VALUE key, VALUE val, VALUE arg)
{
    if (SYMBOL_P(key)) return ST_CONTINUE;
    *(int *)arg = FALSE;
    return ST_STOP;
}

static int
kwd_append(VALUE key, VALUE val, VALUE str)
{
    if (!SYMBOL_P(key)) rb_raise(rb_eRuntimeError, "non-symbol key inserted");
    rb_str_catf(str, "% "PRIsVALUE": %"PRIsVALUE", ", key, val);
    return ST_CONTINUE;
}

static VALUE
append_method(VALUE obj, VALUE str, ID default_method, VALUE default_args)
{
    VALUE method, eargs;

    method = rb_attr_get(obj, id_method);
    if (method != Qfalse) {
        if (!NIL_P(method)) {
            Check_Type(method, T_SYMBOL);
            method = rb_sym2str(method);
        }
        else {
            method = rb_id2str(default_method);
        }
        rb_str_buf_cat2(str, ":");
        rb_str_buf_append(str, method);
    }

    eargs = rb_attr_get(obj, id_arguments);
    if (NIL_P(eargs)) {
        eargs = default_args;
    }
    if (eargs != Qfalse) {
        long   argc = RARRAY_LEN(eargs);
        const VALUE *argv = RARRAY_CONST_PTR(eargs); /* WB: no new reference */

        if (argc > 0) {
            VALUE kwds = Qnil;

            rb_str_buf_cat2(str, "(");

            if (RB_TYPE_P(argv[argc-1], T_HASH) && !RHASH_EMPTY_P(argv[argc-1])) {
                int all_key = TRUE;
                rb_hash_foreach(argv[argc-1], key_symbol_p, (VALUE)&all_key);
                if (all_key) kwds = argv[--argc];
            }

            while (argc--) {
                VALUE arg = *argv++;

                rb_str_append(str, rb_inspect(arg));
                rb_str_buf_cat2(str, ", ");
            }
            if (!NIL_P(kwds)) {
                rb_hash_foreach(kwds, kwd_append, str);
            }
            rb_str_set_len(str, RSTRING_LEN(str)-2);
            rb_str_buf_cat2(str, ")");
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

    if (e->procs) {
        struct generator *g = generator_ptr(e->obj);
        VALUE receiver = rb_check_funcall(g->obj, id_size, 0, 0);
        long i = 0;

        for (i = 0; i < RARRAY_LEN(e->procs); i++) {
            VALUE proc = RARRAY_AREF(e->procs, i);
            struct proc_entry *entry = proc_entry_ptr(proc);
            lazyenum_size_func *size_fn = entry->fn->size;
            if (!size_fn) {
                return Qnil;
            }
            receiver = (*size_fn)(proc, receiver);
        }
        return receiver;
    }

    if (e->size_fn) {
        return (*e->size_fn)(e->obj, e->args, obj);
    }
    if (e->args) {
        argc = (int)RARRAY_LEN(e->args);
        argv = RARRAY_CONST_PTR(e->args);
    }
    size = rb_check_funcall_kw(e->size, id_call, argc, argv, e->kw_splat);
    if (!UNDEF_P(size)) return size;
    return e->size;
}

/*
 * Yielder
 */
static void
yielder_mark(void *p)
{
    struct yielder *ptr = p;
    rb_gc_mark_movable(ptr->proc);
}

static void
yielder_compact(void *p)
{
    struct yielder *ptr = p;
    ptr->proc = rb_gc_location(ptr->proc);
}

static const rb_data_type_t yielder_data_type = {
    "yielder",
    {
        yielder_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL,
        yielder_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static struct yielder *
yielder_ptr(VALUE obj)
{
    struct yielder *ptr;

    TypedData_Get_Struct(obj, struct yielder, &yielder_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->proc)) {
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

    RB_OBJ_WRITE(obj, &ptr->proc, proc);

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

    return rb_proc_call_kw(ptr->proc, args, RB_PASS_CALLED_KEYWORDS);
}

/* :nodoc: */
static VALUE
yielder_yield_push(VALUE obj, VALUE arg)
{
    struct yielder *ptr = yielder_ptr(obj);

    rb_proc_call_with_block(ptr->proc, 1, &arg, Qnil);

    return obj;
}

/*
 * Returns a Proc object that takes arguments and yields them.
 *
 * This method is implemented so that a Yielder object can be directly
 * passed to another method as a block argument.
 *
 *   enum = Enumerator.new { |y|
 *     Dir.glob("*.rb") { |file|
 *       File.open(file) { |f| f.each_line(&y) }
 *     }
 *   }
 */
static VALUE
yielder_to_proc(VALUE obj)
{
    VALUE method = rb_obj_method(obj, sym_yield);

    return rb_funcall(method, idTo_proc, 0);
}

static VALUE
yielder_yield_i(RB_BLOCK_CALL_FUNC_ARGLIST(obj, memo))
{
    return rb_yield_values_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);
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
    rb_gc_mark_movable(ptr->proc);
    rb_gc_mark_movable(ptr->obj);
}

static void
generator_compact(void *p)
{
    struct generator *ptr = p;
    ptr->proc = rb_gc_location(ptr->proc);
    ptr->obj = rb_gc_location(ptr->obj);
}

static const rb_data_type_t generator_data_type = {
    "generator",
    {
        generator_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL,
        generator_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static struct generator *
generator_ptr(VALUE obj)
{
    struct generator *ptr;

    TypedData_Get_Struct(obj, struct generator, &generator_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->proc)) {
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

    RB_OBJ_WRITE(obj, &ptr->proc, proc);

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
                     "wrong argument type %"PRIsVALUE" (expected Proc)",
                     rb_obj_class(proc));

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

    RB_OBJ_WRITE(obj, &ptr1->proc, ptr0->proc);

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

    return rb_proc_call_kw(ptr->proc, args, RB_PASS_CALLED_KEYWORDS);
}

/* Lazy Enumerator methods */
static VALUE
enum_size(VALUE self)
{
    VALUE r = rb_check_funcall(self, id_size, 0, 0);
    return UNDEF_P(r) ? Qnil : r;
}

static VALUE
lazyenum_size(VALUE self, VALUE args, VALUE eobj)
{
    return enum_size(self);
}

#define lazy_receiver_size lazy_map_size

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
        VALUE *nargv = ALLOCV_N(VALUE, args, len);

        nargv[0] = m;
        if (argc > 0) {
            MEMCPY(nargv + 1, argv, VALUE, argc);
        }
        result = rb_yield_values2(len, nargv);
        ALLOCV_END(args);
    }
    if (UNDEF_P(result)) rb_iter_break();
    return Qnil;
}

static VALUE
lazy_init_block_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    rb_block_call(m, id_each, argc-1, argv+1, lazy_init_iterator, val);
    return Qnil;
}

#define memo_value v2
#define memo_flags u3.state
#define LAZY_MEMO_BREAK 1
#define LAZY_MEMO_PACKED 2
#define LAZY_MEMO_BREAK_P(memo) ((memo)->memo_flags & LAZY_MEMO_BREAK)
#define LAZY_MEMO_PACKED_P(memo) ((memo)->memo_flags & LAZY_MEMO_PACKED)
#define LAZY_MEMO_SET_BREAK(memo) ((memo)->memo_flags |= LAZY_MEMO_BREAK)
#define LAZY_MEMO_RESET_BREAK(memo) ((memo)->memo_flags &= ~LAZY_MEMO_BREAK)
#define LAZY_MEMO_SET_VALUE(memo, value) MEMO_V2_SET(memo, value)
#define LAZY_MEMO_SET_PACKED(memo) ((memo)->memo_flags |= LAZY_MEMO_PACKED)
#define LAZY_MEMO_RESET_PACKED(memo) ((memo)->memo_flags &= ~LAZY_MEMO_PACKED)

static VALUE lazy_yielder_result(struct MEMO *result, VALUE yielder, VALUE procs_array, VALUE memos, long i);

static VALUE
lazy_init_yielder(RB_BLOCK_CALL_FUNC_ARGLIST(_, m))
{
    VALUE yielder = RARRAY_AREF(m, 0);
    VALUE procs_array = RARRAY_AREF(m, 1);
    VALUE memos = rb_attr_get(yielder, id_memo);
    struct MEMO *result;

    result = MEMO_NEW(m, rb_enum_values_pack(argc, argv),
                      argc > 1 ? LAZY_MEMO_PACKED : 0);
    return lazy_yielder_result(result, yielder, procs_array, memos, 0);
}

static VALUE
lazy_yielder_yield(struct MEMO *result, long memo_index, int argc, const VALUE *argv)
{
    VALUE m = result->v1;
    VALUE yielder = RARRAY_AREF(m, 0);
    VALUE procs_array = RARRAY_AREF(m, 1);
    VALUE memos = rb_attr_get(yielder, id_memo);
    LAZY_MEMO_SET_VALUE(result, rb_enum_values_pack(argc, argv));
    if (argc > 1)
        LAZY_MEMO_SET_PACKED(result);
    else
        LAZY_MEMO_RESET_PACKED(result);
    return lazy_yielder_result(result, yielder, procs_array, memos, memo_index);
}

static VALUE
lazy_yielder_result(struct MEMO *result, VALUE yielder, VALUE procs_array, VALUE memos, long i)
{
    int cont = 1;

    for (; i < RARRAY_LEN(procs_array); i++) {
        VALUE proc = RARRAY_AREF(procs_array, i);
        struct proc_entry *entry = proc_entry_ptr(proc);
        if (!(*entry->fn->proc)(proc, result, memos, i)) {
            cont = 0;
            break;
        }
    }

    if (cont) {
        rb_funcall2(yielder, idLTLT, 1, &(result->memo_value));
    }
    if (LAZY_MEMO_BREAK_P(result)) {
        rb_iter_break();
    }
    return result->memo_value;
}

static VALUE
lazy_init_block(RB_BLOCK_CALL_FUNC_ARGLIST(val, m))
{
    VALUE procs = RARRAY_AREF(m, 1);

    rb_ivar_set(val, id_memo, rb_ary_new2(RARRAY_LEN(procs)));
    rb_block_call(RARRAY_AREF(m, 0), id_each, 0, 0,
                  lazy_init_yielder, rb_ary_new3(2, val, procs));
    return Qnil;
}

static VALUE
lazy_generator_init(VALUE enumerator, VALUE procs)
{
    VALUE generator;
    VALUE obj;
    struct generator *gen_ptr;
    struct enumerator *e = enumerator_ptr(enumerator);

    if (RARRAY_LEN(procs) > 0) {
        struct generator *old_gen_ptr = generator_ptr(e->obj);
        obj = old_gen_ptr->obj;
    }
    else {
        obj = enumerator;
    }

    generator = generator_allocate(rb_cGenerator);

    rb_block_call(generator, id_initialize, 0, 0,
                  lazy_init_block, rb_ary_new3(2, obj, procs));

    gen_ptr = generator_ptr(generator);
    RB_OBJ_WRITE(generator, &gen_ptr->obj, obj);

    return generator;
}

static int
lazy_precheck(VALUE procs)
{
    if (RTEST(procs)) {
        long num_procs = RARRAY_LEN(procs), i = num_procs;
        while (i-- > 0) {
            VALUE proc = RARRAY_AREF(procs, i);
            struct proc_entry *entry = proc_entry_ptr(proc);
            lazyenum_precheck_func *precheck = entry->fn->precheck;
            if (precheck && !precheck(proc)) return FALSE;
        }
    }

    return TRUE;
}

/*
 * Document-class: Enumerator::Lazy
 *
 * Enumerator::Lazy is a special type of Enumerator, that allows constructing
 * chains of operations without evaluating them immediately, and evaluating
 * values on as-needed basis. In order to do so it redefines most of Enumerable
 * methods so that they just construct another lazy enumerator.
 *
 * Enumerator::Lazy can be constructed from any Enumerable with the
 * Enumerable#lazy method.
 *
 *    lazy = (1..Float::INFINITY).lazy.select(&:odd?).drop(10).take_while { |i| i < 30 }
 *    # => #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: #<Enumerator::Lazy: 1..Infinity>:select>:drop(10)>:take_while>
 *
 * The real enumeration is performed when any non-redefined Enumerable method
 * is called, like Enumerable#first or Enumerable#to_a (the latter is aliased
 * as #force for more semantic code):
 *
 *    lazy.first(2)
 *    #=> [21, 23]
 *
 *    lazy.force
 *    #=> [21, 23, 25, 27, 29]
 *
 * Note that most Enumerable methods that could be called with or without
 * a block, on Enumerator::Lazy will always require a block:
 *
 *    [1, 2, 3].map       #=> #<Enumerator: [1, 2, 3]:map>
 *    [1, 2, 3].lazy.map  # ArgumentError: tried to call lazy map without a block
 *
 * This class allows idiomatic calculations on long or infinite sequences, as well
 * as chaining of calculations without constructing intermediate arrays.
 *
 * Example for working with a slowly calculated sequence:
 *
 *    require 'open-uri'
 *
 *    # This will fetch all URLs before selecting
 *    # necessary data
 *    URLS.map { |u| JSON.parse(URI.open(u).read) }
 *      .select { |data| data.key?('stats') }
 *      .first(5)
 *
 *    # This will fetch URLs one-by-one, only till
 *    # there is enough data to satisfy the condition
 *    URLS.lazy.map { |u| JSON.parse(URI.open(u).read) }
 *      .select { |data| data.key?('stats') }
 *      .first(5)
 *
 * Ending a chain with ".eager" generates a non-lazy enumerator, which
 * is suitable for returning or passing to another method that expects
 * a normal enumerator.
 *
 *    def active_items
 *      groups
 *        .lazy
 *        .flat_map(&:items)
 *        .reject(&:disabled)
 *        .eager
 *    end
 *
 *    # This works lazily; if a checked item is found, it stops
 *    # iteration and does not look into remaining groups.
 *    first_checked = active_items.find(&:checked)
 *
 *    # This returns an array of items like a normal enumerator does.
 *    all_checked = active_items.select(&:checked)
 *
 */

/*
 * call-seq:
 *   Lazy.new(obj, size=nil) { |yielder, *values| block }
 *
 * Creates a new Lazy enumerator. When the enumerator is actually enumerated
 * (e.g. by calling #force), +obj+ will be enumerated and each value passed
 * to the given block. The block can yield values back using +yielder+.
 * For example, to create a "filter+map" enumerator:
 *
 *   def filter_map(sequence)
 *     Lazy.new(sequence) do |yielder, *values|
 *       result = yield *values
 *       yielder << result if result
 *     end
 *   end
 *
 *   filter_map(1..Float::INFINITY) {|i| i*i if i.even?}.first(5)
 *   #=> [4, 16, 36, 64, 100]
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
    enumerator_init(self, generator, sym_each, 0, 0, 0, size, 0);
    rb_ivar_set(self, id_receiver, obj);

    return self;
}

#if 0 /* for RDoc */
/*
 * call-seq:
 *   lazy.to_a  -> array
 *   lazy.force -> array
 *
 * Expands +lazy+ enumerator to an array.
 * See Enumerable#to_a.
 */
static VALUE
lazy_to_a(VALUE self)
{
}
#endif

static void
lazy_set_args(VALUE lazy, VALUE args)
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
}

#if 0
static VALUE
lazy_set_method(VALUE lazy, VALUE args, rb_enumerator_size_func *size_fn)
{
    struct enumerator *e = enumerator_ptr(lazy);
    lazy_set_args(lazy, args);
    e->size_fn = size_fn;
    return lazy;
}
#endif

static VALUE
lazy_add_method(VALUE obj, int argc, VALUE *argv, VALUE args, VALUE memo,
                const lazyenum_funcs *fn)
{
    struct enumerator *new_e;
    VALUE new_obj;
    VALUE new_generator;
    VALUE new_procs;
    struct enumerator *e = enumerator_ptr(obj);
    struct proc_entry *entry;
    VALUE entry_obj = TypedData_Make_Struct(rb_cObject, struct proc_entry,
                                            &proc_entry_data_type, entry);
    if (rb_block_given_p()) {
        RB_OBJ_WRITE(entry_obj, &entry->proc, rb_block_proc());
    }
    entry->fn = fn;
    RB_OBJ_WRITE(entry_obj, &entry->memo, args);

    lazy_set_args(entry_obj, memo);

    new_procs = RTEST(e->procs) ? rb_ary_dup(e->procs) : rb_ary_new();
    new_generator = lazy_generator_init(obj, new_procs);
    rb_ary_push(new_procs, entry_obj);

    new_obj = enumerator_init_copy(enumerator_allocate(rb_cLazy), obj);
    new_e = RTYPEDDATA_GET_DATA(new_obj);
    RB_OBJ_WRITE(new_obj, &new_e->obj, new_generator);
    RB_OBJ_WRITE(new_obj, &new_e->procs, new_procs);

    if (argc > 0) {
        new_e->meth = rb_to_id(*argv++);
        --argc;
    }
    else {
        new_e->meth = id_each;
    }

    RB_OBJ_WRITE(new_obj, &new_e->args, rb_ary_new4(argc, argv));

    return new_obj;
}

/*
 * call-seq:
 *   e.lazy -> lazy_enumerator
 *
 * Returns an Enumerator::Lazy, which redefines most Enumerable
 * methods to postpone enumeration and enumerate values only on an
 * as-needed basis.
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
    VALUE result = lazy_to_enum_i(obj, sym_each, 0, 0, lazyenum_size, rb_keyword_given_p());
    /* Qfalse indicates that the Enumerator::Lazy has no method name */
    rb_ivar_set(result, id_method, Qfalse);
    return result;
}

static VALUE
lazy_to_enum_i(VALUE obj, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *size_fn, int kw_splat)
{
    return enumerator_init(enumerator_allocate(rb_cLazy),
                           obj, meth, argc, argv, size_fn, Qnil, kw_splat);
}

/*
 * call-seq:
 *   lzy.to_enum(method = :each, *args)                   -> lazy_enum
 *   lzy.enum_for(method = :each, *args)                  -> lazy_enum
 *   lzy.to_enum(method = :each, *args) {|*args| block }  -> lazy_enum
 *   lzy.enum_for(method = :each, *args) {|*args| block } -> lazy_enum
 *
 * Similar to Object#to_enum, except it returns a lazy enumerator.
 * This makes it easy to define Enumerable methods that will
 * naturally remain lazy if called from a lazy enumerator.
 *
 * For example, continuing from the example in Object#to_enum:
 *
 *   # See Object#to_enum for the definition of repeat
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
    VALUE lazy, meth = sym_each, super_meth;

    if (argc > 0) {
        --argc;
        meth = *argv++;
    }
    if (RTEST((super_meth = rb_hash_aref(lazy_use_super_method, meth)))) {
        meth = super_meth;
    }
    lazy = lazy_to_enum_i(self, meth, argc, argv, 0, rb_keyword_given_p());
    if (rb_block_given_p()) {
        RB_OBJ_WRITE(lazy, &enumerator_ptr(lazy)->size, rb_block_proc());
    }
    return lazy;
}

static VALUE
lazy_eager_size(VALUE self, VALUE args, VALUE eobj)
{
    return enum_size(self);
}

/*
 * call-seq:
 *   lzy.eager -> enum
 *
 * Returns a non-lazy Enumerator converted from the lazy enumerator.
 */

static VALUE
lazy_eager(VALUE self)
{
    return enumerator_init(enumerator_allocate(rb_cEnumerator),
                           self, sym_each, 0, 0, lazy_eager_size, Qnil, 0);
}

static VALUE
lazyenum_yield(VALUE proc_entry, struct MEMO *result)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    return rb_proc_call_with_block(entry->proc, 1, &result->memo_value, Qnil);
}

static VALUE
lazyenum_yield_values(VALUE proc_entry, struct MEMO *result)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    int argc = 1;
    const VALUE *argv = &result->memo_value;
    if (LAZY_MEMO_PACKED_P(result)) {
        const VALUE args = *argv;
        argc = RARRAY_LENINT(args);
        argv = RARRAY_CONST_PTR(args);
    }
    return rb_proc_call_with_block(entry->proc, argc, argv, Qnil);
}

static struct MEMO *
lazy_map_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE value = lazyenum_yield_values(proc_entry, result);
    LAZY_MEMO_SET_VALUE(result, value);
    LAZY_MEMO_RESET_PACKED(result);
    return result;
}

static VALUE
lazy_map_size(VALUE entry, VALUE receiver)
{
    return receiver;
}

static const lazyenum_funcs lazy_map_funcs = {
    lazy_map_proc, lazy_map_size,
};

/*
 *  call-seq:
 *     lazy.collect { |obj| block } -> lazy_enumerator
 *     lazy.map     { |obj| block } -> lazy_enumerator
 *
 *  Like Enumerable#map, but chains operation to be lazy-evaluated.
 *
 *     (1..Float::INFINITY).lazy.map {|i| i**2 }
 *     #=> #<Enumerator::Lazy: #<Enumerator::Lazy: 1..Infinity>:map>
 *     (1..Float::INFINITY).lazy.map {|i| i**2 }.first(3)
 *     #=> [1, 4, 9]
 */

static VALUE
lazy_map(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy map without a block");
    }

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_map_funcs);
}

struct flat_map_i_arg {
    struct MEMO *result;
    long index;
};

static VALUE
lazy_flat_map_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, y))
{
    struct flat_map_i_arg *arg = (struct flat_map_i_arg *)y;

    return lazy_yielder_yield(arg->result, arg->index, argc, argv);
}

static struct MEMO *
lazy_flat_map_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE value = lazyenum_yield_values(proc_entry, result);
    VALUE ary = 0;
    const long proc_index = memo_index + 1;
    int break_p = LAZY_MEMO_BREAK_P(result);

    if (RB_TYPE_P(value, T_ARRAY)) {
        ary = value;
    }
    else if (rb_respond_to(value, id_force) && rb_respond_to(value, id_each)) {
        struct flat_map_i_arg arg = {.result = result, .index = proc_index};
        LAZY_MEMO_RESET_BREAK(result);
        rb_block_call(value, id_each, 0, 0, lazy_flat_map_i, (VALUE)&arg);
        if (break_p) LAZY_MEMO_SET_BREAK(result);
        return 0;
    }

    if (ary || !NIL_P(ary = rb_check_array_type(value))) {
        long i;
        LAZY_MEMO_RESET_BREAK(result);
        for (i = 0; i + 1 < RARRAY_LEN(ary); i++) {
            const VALUE argv = RARRAY_AREF(ary, i);
            lazy_yielder_yield(result, proc_index, 1, &argv);
        }
        if (break_p) LAZY_MEMO_SET_BREAK(result);
        if (i >= RARRAY_LEN(ary)) return 0;
        value = RARRAY_AREF(ary, i);
    }
    LAZY_MEMO_SET_VALUE(result, value);
    LAZY_MEMO_RESET_PACKED(result);
    return result;
}

static const lazyenum_funcs lazy_flat_map_funcs = {
    lazy_flat_map_proc, 0,
};

/*
 *  call-seq:
 *     lazy.collect_concat { |obj| block } -> a_lazy_enumerator
 *     lazy.flat_map       { |obj| block } -> a_lazy_enumerator
 *
 *  Returns a new lazy enumerator with the concatenated results of running
 *  +block+ once for every element in the lazy enumerator.
 *
 *    ["foo", "bar"].lazy.flat_map {|i| i.each_char.lazy}.force
 *    #=> ["f", "o", "o", "b", "a", "r"]
 *
 *  A value +x+ returned by +block+ is decomposed if either of
 *  the following conditions is true:
 *
 *  * +x+ responds to both each and force, which means that
 *    +x+ is a lazy enumerator.
 *  * +x+ is an array or responds to to_ary.
 *
 *  Otherwise, +x+ is contained as-is in the return value.
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

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_flat_map_funcs);
}

static struct MEMO *
lazy_select_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE chain = lazyenum_yield(proc_entry, result);
    if (!RTEST(chain)) return 0;
    return result;
}

static const lazyenum_funcs lazy_select_funcs = {
    lazy_select_proc, 0,
};

/*
 *  call-seq:
 *     lazy.find_all { |obj| block } -> lazy_enumerator
 *     lazy.select   { |obj| block } -> lazy_enumerator
 *     lazy.filter   { |obj| block } -> lazy_enumerator
 *
 *  Like Enumerable#select, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_select(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy select without a block");
    }

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_select_funcs);
}

static struct MEMO *
lazy_filter_map_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE value = lazyenum_yield_values(proc_entry, result);
    if (!RTEST(value)) return 0;
    LAZY_MEMO_SET_VALUE(result, value);
    LAZY_MEMO_RESET_PACKED(result);
    return result;
}

static const lazyenum_funcs lazy_filter_map_funcs = {
    lazy_filter_map_proc, 0,
};

/*
 *  call-seq:
 *     lazy.filter_map { |obj| block } -> lazy_enumerator
 *
 *  Like Enumerable#filter_map, but chains operation to be lazy-evaluated.
 *
 *    (1..).lazy.filter_map { |i| i * 2 if i.even? }.first(5)
 *    #=> [4, 8, 12, 16, 20]
 */

static VALUE
lazy_filter_map(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy filter_map without a block");
    }

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_filter_map_funcs);
}

static struct MEMO *
lazy_reject_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE chain = lazyenum_yield(proc_entry, result);
    if (RTEST(chain)) return 0;
    return result;
}

static const lazyenum_funcs lazy_reject_funcs = {
    lazy_reject_proc, 0,
};

/*
 *  call-seq:
 *     lazy.reject { |obj| block } -> lazy_enumerator
 *
 *  Like Enumerable#reject, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_reject(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy reject without a block");
    }

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_reject_funcs);
}

static struct MEMO *
lazy_grep_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE chain = rb_funcall(entry->memo, id_eqq, 1, result->memo_value);
    if (!RTEST(chain)) return 0;
    return result;
}

static struct MEMO *
lazy_grep_iter_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE value, chain = rb_funcall(entry->memo, id_eqq, 1, result->memo_value);

    if (!RTEST(chain)) return 0;
    value = rb_proc_call_with_block(entry->proc, 1, &(result->memo_value), Qnil);
    LAZY_MEMO_SET_VALUE(result, value);
    LAZY_MEMO_RESET_PACKED(result);

    return result;
}

static const lazyenum_funcs lazy_grep_iter_funcs = {
    lazy_grep_iter_proc, 0,
};

static const lazyenum_funcs lazy_grep_funcs = {
    lazy_grep_proc, 0,
};

/*
 *  call-seq:
 *     lazy.grep(pattern)                  -> lazy_enumerator
 *     lazy.grep(pattern) { |obj| block }  -> lazy_enumerator
 *
 *  Like Enumerable#grep, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_grep(VALUE obj, VALUE pattern)
{
    const lazyenum_funcs *const funcs = rb_block_given_p() ?
        &lazy_grep_iter_funcs : &lazy_grep_funcs;
    return lazy_add_method(obj, 0, 0, pattern, rb_ary_new3(1, pattern), funcs);
}

static struct MEMO *
lazy_grep_v_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE chain = rb_funcall(entry->memo, id_eqq, 1, result->memo_value);
    if (RTEST(chain)) return 0;
    return result;
}

static struct MEMO *
lazy_grep_v_iter_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE value, chain = rb_funcall(entry->memo, id_eqq, 1, result->memo_value);

    if (RTEST(chain)) return 0;
    value = rb_proc_call_with_block(entry->proc, 1, &(result->memo_value), Qnil);
    LAZY_MEMO_SET_VALUE(result, value);
    LAZY_MEMO_RESET_PACKED(result);

    return result;
}

static const lazyenum_funcs lazy_grep_v_iter_funcs = {
    lazy_grep_v_iter_proc, 0,
};

static const lazyenum_funcs lazy_grep_v_funcs = {
    lazy_grep_v_proc, 0,
};

/*
 *  call-seq:
 *     lazy.grep_v(pattern)                  -> lazy_enumerator
 *     lazy.grep_v(pattern) { |obj| block }  -> lazy_enumerator
 *
 *  Like Enumerable#grep_v, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_grep_v(VALUE obj, VALUE pattern)
{
    const lazyenum_funcs *const funcs = rb_block_given_p() ?
        &lazy_grep_v_iter_funcs : &lazy_grep_v_funcs;
    return lazy_add_method(obj, 0, 0, pattern, rb_ary_new3(1, pattern), funcs);
}

static VALUE
call_next(VALUE obj)
{
    return rb_funcall(obj, id_next, 0);
}

static VALUE
next_stopped(VALUE obj, VALUE _)
{
    return Qnil;
}

static struct MEMO *
lazy_zip_arrays_func(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE ary, arrays = entry->memo;
    VALUE memo = rb_ary_entry(memos, memo_index);
    long i, count = NIL_P(memo) ? 0 : NUM2LONG(memo);

    ary = rb_ary_new2(RARRAY_LEN(arrays) + 1);
    rb_ary_push(ary, result->memo_value);
    for (i = 0; i < RARRAY_LEN(arrays); i++) {
        rb_ary_push(ary, rb_ary_entry(RARRAY_AREF(arrays, i), count));
    }
    LAZY_MEMO_SET_VALUE(result, ary);
    rb_ary_store(memos, memo_index, LONG2NUM(++count));
    return result;
}

static struct MEMO *
lazy_zip_func(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE arg = rb_ary_entry(memos, memo_index);
    VALUE zip_args = entry->memo;
    VALUE ary, v;
    long i;

    if (NIL_P(arg)) {
        arg = rb_ary_new2(RARRAY_LEN(zip_args));
        for (i = 0; i < RARRAY_LEN(zip_args); i++) {
            rb_ary_push(arg, rb_funcall(RARRAY_AREF(zip_args, i), id_to_enum, 0));
        }
        rb_ary_store(memos, memo_index, arg);
    }

    ary = rb_ary_new2(RARRAY_LEN(arg) + 1);
    rb_ary_push(ary, result->memo_value);
    for (i = 0; i < RARRAY_LEN(arg); i++) {
        v = rb_rescue2(call_next, RARRAY_AREF(arg, i), next_stopped, 0,
                       rb_eStopIteration, (VALUE)0);
        rb_ary_push(ary, v);
    }
    LAZY_MEMO_SET_VALUE(result, ary);
    return result;
}

static const lazyenum_funcs lazy_zip_funcs[] = {
    {lazy_zip_func, lazy_receiver_size,},
    {lazy_zip_arrays_func, lazy_receiver_size,},
};

/*
 *  call-seq:
 *     lazy.zip(arg, ...)                  -> lazy_enumerator
 *     lazy.zip(arg, ...) { |arr| block }  -> nil
 *
 *  Like Enumerable#zip, but chains operation to be lazy-evaluated.
 *  However, if a block is given to zip, values are enumerated immediately.
 */
static VALUE
lazy_zip(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary, v;
    long i;
    const lazyenum_funcs *funcs = &lazy_zip_funcs[1];

    if (rb_block_given_p()) {
        return rb_call_super(argc, argv);
    }

    ary = rb_ary_new2(argc);
    for (i = 0; i < argc; i++) {
        v = rb_check_array_type(argv[i]);
        if (NIL_P(v)) {
            for (; i < argc; i++) {
                if (!rb_respond_to(argv[i], id_each)) {
                    rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (must respond to :each)",
                             rb_obj_class(argv[i]));
                }
            }
            ary = rb_ary_new4(argc, argv);
            funcs = &lazy_zip_funcs[0];
            break;
        }
        rb_ary_push(ary, v);
    }

    return lazy_add_method(obj, 0, 0, ary, ary, funcs);
}

static struct MEMO *
lazy_take_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    long remain;
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE memo = rb_ary_entry(memos, memo_index);

    if (NIL_P(memo)) {
        memo = entry->memo;
    }

    remain = NUM2LONG(memo);
    if (--remain == 0) LAZY_MEMO_SET_BREAK(result);
    rb_ary_store(memos, memo_index, LONG2NUM(remain));
    return result;
}

static VALUE
lazy_take_size(VALUE entry, VALUE receiver)
{
    long len = NUM2LONG(RARRAY_AREF(rb_ivar_get(entry, id_arguments), 0));
    if (NIL_P(receiver) || (FIXNUM_P(receiver) && FIX2LONG(receiver) < len))
        return receiver;
    return LONG2NUM(len);
}

static int
lazy_take_precheck(VALUE proc_entry)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    return entry->memo != INT2FIX(0);
}

static const lazyenum_funcs lazy_take_funcs = {
    lazy_take_proc, lazy_take_size, lazy_take_precheck,
};

/*
 *  call-seq:
 *     lazy.take(n)               -> lazy_enumerator
 *
 *  Like Enumerable#take, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_take(VALUE obj, VALUE n)
{
    long len = NUM2LONG(n);

    if (len < 0) {
        rb_raise(rb_eArgError, "attempt to take negative size");
    }

    n = LONG2NUM(len);          /* no more conversion */

    return lazy_add_method(obj, 0, 0, n, rb_ary_new3(1, n), &lazy_take_funcs);
}

static struct MEMO *
lazy_take_while_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE take = lazyenum_yield_values(proc_entry, result);
    if (!RTEST(take)) {
        LAZY_MEMO_SET_BREAK(result);
        return 0;
    }
    return result;
}

static const lazyenum_funcs lazy_take_while_funcs = {
    lazy_take_while_proc, 0,
};

/*
 *  call-seq:
 *     lazy.take_while { |obj| block } -> lazy_enumerator
 *
 *  Like Enumerable#take_while, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_take_while(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy take_while without a block");
    }

    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_take_while_funcs);
}

static VALUE
lazy_drop_size(VALUE proc_entry, VALUE receiver)
{
    long len = NUM2LONG(RARRAY_AREF(rb_ivar_get(proc_entry, id_arguments), 0));
    if (NIL_P(receiver))
        return receiver;
    if (FIXNUM_P(receiver)) {
        len = FIX2LONG(receiver) - len;
        return LONG2FIX(len < 0 ? 0 : len);
    }
    return rb_funcall(receiver, '-', 1, LONG2NUM(len));
}

static struct MEMO *
lazy_drop_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    long remain;
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE memo = rb_ary_entry(memos, memo_index);

    if (NIL_P(memo)) {
        memo = entry->memo;
    }
    remain = NUM2LONG(memo);
    if (remain > 0) {
        --remain;
        rb_ary_store(memos, memo_index, LONG2NUM(remain));
        return 0;
    }

    return result;
}

static const lazyenum_funcs lazy_drop_funcs = {
    lazy_drop_proc, lazy_drop_size,
};

/*
 *  call-seq:
 *     lazy.drop(n)               -> lazy_enumerator
 *
 *  Like Enumerable#drop, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_drop(VALUE obj, VALUE n)
{
    long len = NUM2LONG(n);
    VALUE argv[2];
    argv[0] = sym_each;
    argv[1] = n;

    if (len < 0) {
        rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    return lazy_add_method(obj, 2, argv, n, rb_ary_new3(1, n), &lazy_drop_funcs);
}

static struct MEMO *
lazy_drop_while_proc(VALUE proc_entry, struct MEMO* result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE memo = rb_ary_entry(memos, memo_index);

    if (NIL_P(memo)) {
        memo = entry->memo;
    }

    if (!RTEST(memo)) {
        VALUE drop = lazyenum_yield_values(proc_entry, result);
        if (RTEST(drop)) return 0;
        rb_ary_store(memos, memo_index, Qtrue);
    }
    return result;
}

static const lazyenum_funcs lazy_drop_while_funcs = {
    lazy_drop_while_proc, 0,
};

/*
 *  call-seq:
 *     lazy.drop_while { |obj| block }  -> lazy_enumerator
 *
 *  Like Enumerable#drop_while, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_drop_while(VALUE obj)
{
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "tried to call lazy drop_while without a block");
    }

    return lazy_add_method(obj, 0, 0, Qfalse, Qnil, &lazy_drop_while_funcs);
}

static int
lazy_uniq_check(VALUE chain, VALUE memos, long memo_index)
{
    VALUE hash = rb_ary_entry(memos, memo_index);

    if (NIL_P(hash)) {
        hash = rb_obj_hide(rb_hash_new());
        rb_ary_store(memos, memo_index, hash);
    }

    return rb_hash_add_new_element(hash, chain, Qfalse);
}

static struct MEMO *
lazy_uniq_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    if (lazy_uniq_check(result->memo_value, memos, memo_index)) return 0;
    return result;
}

static struct MEMO *
lazy_uniq_iter_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    VALUE chain = lazyenum_yield(proc_entry, result);

    if (lazy_uniq_check(chain, memos, memo_index)) return 0;
    return result;
}

static const lazyenum_funcs lazy_uniq_iter_funcs = {
    lazy_uniq_iter_proc, 0,
};

static const lazyenum_funcs lazy_uniq_funcs = {
    lazy_uniq_proc, 0,
};

/*
 *  call-seq:
 *     lazy.uniq                  -> lazy_enumerator
 *     lazy.uniq { |item| block } -> lazy_enumerator
 *
 *  Like Enumerable#uniq, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_uniq(VALUE obj)
{
    const lazyenum_funcs *const funcs =
        rb_block_given_p() ? &lazy_uniq_iter_funcs : &lazy_uniq_funcs;
    return lazy_add_method(obj, 0, 0, Qnil, Qnil, funcs);
}

static struct MEMO *
lazy_compact_proc(VALUE proc_entry, struct MEMO *result, VALUE memos, long memo_index)
{
    if (NIL_P(result->memo_value)) return 0;
    return result;
}

static const lazyenum_funcs lazy_compact_funcs = {
    lazy_compact_proc, 0,
};

/*
 *  call-seq:
 *     lazy.compact                  -> lazy_enumerator
 *
 *  Like Enumerable#compact, but chains operation to be lazy-evaluated.
 */

static VALUE
lazy_compact(VALUE obj)
{
    return lazy_add_method(obj, 0, 0, Qnil, Qnil, &lazy_compact_funcs);
}

static struct MEMO *
lazy_with_index_proc(VALUE proc_entry, struct MEMO* result, VALUE memos, long memo_index)
{
    struct proc_entry *entry = proc_entry_ptr(proc_entry);
    VALUE memo = rb_ary_entry(memos, memo_index);
    VALUE argv[2];

    if (NIL_P(memo)) {
        memo = entry->memo;
    }

    argv[0] = result->memo_value;
    argv[1] = memo;
    if (entry->proc) {
        rb_proc_call_with_block(entry->proc, 2, argv, Qnil);
        LAZY_MEMO_RESET_PACKED(result);
    }
    else {
        LAZY_MEMO_SET_VALUE(result, rb_ary_new_from_values(2, argv));
        LAZY_MEMO_SET_PACKED(result);
    }
    rb_ary_store(memos, memo_index, LONG2NUM(NUM2LONG(memo) + 1));
    return result;
}

static VALUE
lazy_with_index_size(VALUE proc, VALUE receiver)
{
    return receiver;
}

static const lazyenum_funcs lazy_with_index_funcs = {
    lazy_with_index_proc, lazy_with_index_size,
};

/*
 * call-seq:
 *   lazy.with_index(offset = 0) {|(*args), idx| block }
 *   lazy.with_index(offset = 0)
 *
 * If a block is given, returns a lazy enumerator that will
 * iterate over the given block for each element
 * with an index, which starts from +offset+, and returns a
 * lazy enumerator that yields the same values (without the index).
 *
 * If a block is not given, returns a new lazy enumerator that
 * includes the index, starting from +offset+.
 *
 * +offset+:: the starting index to use
 *
 * See Enumerator#with_index.
 */
static VALUE
lazy_with_index(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo;

    rb_scan_args(argc, argv, "01", &memo);
    if (NIL_P(memo))
        memo = LONG2NUM(0);

    return lazy_add_method(obj, 0, 0, memo, rb_ary_new_from_values(1, &memo), &lazy_with_index_funcs);
}

#if 0 /* for RDoc */

/*
 *  call-seq:
 *     lazy.chunk { |elt| ... }                       -> lazy_enumerator
 *
 *  Like Enumerable#chunk, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_chunk(VALUE self)
{
}

/*
 *  call-seq:
 *     lazy.chunk_while {|elt_before, elt_after| bool } -> lazy_enumerator
 *
 *  Like Enumerable#chunk_while, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_chunk_while(VALUE self)
{
}

/*
 *  call-seq:
 *     lazy.slice_after(pattern)       -> lazy_enumerator
 *     lazy.slice_after { |elt| bool } -> lazy_enumerator
 *
 *  Like Enumerable#slice_after, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_slice_after(VALUE self)
{
}

/*
 *  call-seq:
 *     lazy.slice_before(pattern)       -> lazy_enumerator
 *     lazy.slice_before { |elt| bool } -> lazy_enumerator
 *
 *  Like Enumerable#slice_before, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_slice_before(VALUE self)
{
}

/*
 *  call-seq:
 *     lazy.slice_when {|elt_before, elt_after| bool } -> lazy_enumerator
 *
 *  Like Enumerable#slice_when, but chains operation to be lazy-evaluated.
 */
static VALUE
lazy_slice_when(VALUE self)
{
}
# endif

static VALUE
lazy_super(int argc, VALUE *argv, VALUE lazy)
{
    return enumerable_lazy(rb_call_super(argc, argv));
}

/*
 *  call-seq:
 *     enum.lazy -> lazy_enumerator
 *
 *  Returns self.
 */

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

/*
 * Producer
 */

static void
producer_mark(void *p)
{
    struct producer *ptr = p;
    rb_gc_mark_movable(ptr->init);
    rb_gc_mark_movable(ptr->proc);
}

static void
producer_compact(void *p)
{
    struct producer *ptr = p;
    ptr->init = rb_gc_location(ptr->init);
    ptr->proc = rb_gc_location(ptr->proc);
}

#define producer_free RUBY_TYPED_DEFAULT_FREE

static size_t
producer_memsize(const void *p)
{
    return sizeof(struct producer);
}

static const rb_data_type_t producer_data_type = {
    "producer",
    {
        producer_mark,
        producer_free,
        producer_memsize,
        producer_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static struct producer *
producer_ptr(VALUE obj)
{
    struct producer *ptr;

    TypedData_Get_Struct(obj, struct producer, &producer_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->proc)) {
        rb_raise(rb_eArgError, "uninitialized producer");
    }
    return ptr;
}

/* :nodoc: */
static VALUE
producer_allocate(VALUE klass)
{
    struct producer *ptr;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct producer, &producer_data_type, ptr);
    ptr->init = Qundef;
    ptr->proc = Qundef;

    return obj;
}

static VALUE
producer_init(VALUE obj, VALUE init, VALUE proc)
{
    struct producer *ptr;

    TypedData_Get_Struct(obj, struct producer, &producer_data_type, ptr);

    if (!ptr) {
        rb_raise(rb_eArgError, "unallocated producer");
    }

    RB_OBJ_WRITE(obj, &ptr->init, init);
    RB_OBJ_WRITE(obj, &ptr->proc, proc);

    return obj;
}

static VALUE
producer_each_stop(VALUE dummy, VALUE exc)
{
    return rb_attr_get(exc, id_result);
}

NORETURN(static VALUE producer_each_i(VALUE obj));

static VALUE
producer_each_i(VALUE obj)
{
    struct producer *ptr;
    VALUE init, proc, curr;

    ptr = producer_ptr(obj);
    init = ptr->init;
    proc = ptr->proc;

    if (UNDEF_P(init)) {
        curr = Qnil;
    }
    else {
        rb_yield(init);
        curr = init;
    }

    for (;;) {
        curr = rb_funcall(proc, id_call, 1, curr);
        rb_yield(curr);
    }

    UNREACHABLE_RETURN(Qnil);
}

/* :nodoc: */
static VALUE
producer_each(VALUE obj)
{
    rb_need_block();

    return rb_rescue2(producer_each_i, obj, producer_each_stop, (VALUE)0, rb_eStopIteration, (VALUE)0);
}

static VALUE
producer_size(VALUE obj, VALUE args, VALUE eobj)
{
    return DBL2NUM(HUGE_VAL);
}

/*
 * call-seq:
 *    Enumerator.produce(initial = nil) { |prev| block } -> enumerator
 *
 * Creates an infinite enumerator from any block, just called over and
 * over.  The result of the previous iteration is passed to the next one.
 * If +initial+ is provided, it is passed to the first iteration, and
 * becomes the first element of the enumerator; if it is not provided,
 * the first iteration receives +nil+, and its result becomes the first
 * element of the iterator.
 *
 * Raising StopIteration from the block stops an iteration.
 *
 *   Enumerator.produce(1, &:succ)   # => enumerator of 1, 2, 3, 4, ....
 *
 *   Enumerator.produce { rand(10) } # => infinite random number sequence
 *
 *   ancestors = Enumerator.produce(node) { |prev| node = prev.parent or raise StopIteration }
 *   enclosing_section = ancestors.find { |n| n.type == :section }
 *
 * Using ::produce together with Enumerable methods like Enumerable#detect,
 * Enumerable#slice_after, Enumerable#take_while can provide Enumerator-based alternatives
 * for +while+ and +until+ cycles:
 *
 *   # Find next Tuesday
 *   require "date"
 *   Enumerator.produce(Date.today, &:succ).detect(&:tuesday?)
 *
 *   # Simple lexer:
 *   require "strscan"
 *   scanner = StringScanner.new("7+38/6")
 *   PATTERN = %r{\d+|[-/+*]}
 *   Enumerator.produce { scanner.scan(PATTERN) }.slice_after { scanner.eos? }.first
 *   # => ["7", "+", "38", "/", "6"]
 */
static VALUE
enumerator_s_produce(int argc, VALUE *argv, VALUE klass)
{
    VALUE init, producer;

    if (!rb_block_given_p()) rb_raise(rb_eArgError, "no block given");

    if (rb_scan_args(argc, argv, "01", &init) == 0) {
        init = Qundef;
    }

    producer = producer_init(producer_allocate(rb_cEnumProducer), init, rb_block_proc());

    return rb_enumeratorize_with_size_kw(producer, sym_each, 0, 0, producer_size, RB_NO_KEYWORDS);
}

/*
 * Document-class: Enumerator::Chain
 *
 * Enumerator::Chain is a subclass of Enumerator, which represents a
 * chain of enumerables that works as a single enumerator.
 *
 * This type of objects can be created by Enumerable#chain and
 * Enumerator#+.
 */

static void
enum_chain_mark(void *p)
{
    struct enum_chain *ptr = p;
    rb_gc_mark_movable(ptr->enums);
}

static void
enum_chain_compact(void *p)
{
    struct enum_chain *ptr = p;
    ptr->enums = rb_gc_location(ptr->enums);
}

#define enum_chain_free RUBY_TYPED_DEFAULT_FREE

static size_t
enum_chain_memsize(const void *p)
{
    return sizeof(struct enum_chain);
}

static const rb_data_type_t enum_chain_data_type = {
    "chain",
    {
        enum_chain_mark,
        enum_chain_free,
        enum_chain_memsize,
        enum_chain_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static struct enum_chain *
enum_chain_ptr(VALUE obj)
{
    struct enum_chain *ptr;

    TypedData_Get_Struct(obj, struct enum_chain, &enum_chain_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->enums)) {
        rb_raise(rb_eArgError, "uninitialized chain");
    }
    return ptr;
}

/* :nodoc: */
static VALUE
enum_chain_allocate(VALUE klass)
{
    struct enum_chain *ptr;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct enum_chain, &enum_chain_data_type, ptr);
    ptr->enums = Qundef;
    ptr->pos = -1;

    return obj;
}

/*
 * call-seq:
 *   Enumerator::Chain.new(*enums) -> enum
 *
 * Generates a new enumerator object that iterates over the elements
 * of given enumerable objects in sequence.
 *
 *   e = Enumerator::Chain.new(1..3, [4, 5])
 *   e.to_a #=> [1, 2, 3, 4, 5]
 *   e.size #=> 5
 */
static VALUE
enum_chain_initialize(VALUE obj, VALUE enums)
{
    struct enum_chain *ptr;

    rb_check_frozen(obj);
    TypedData_Get_Struct(obj, struct enum_chain, &enum_chain_data_type, ptr);

    if (!ptr) rb_raise(rb_eArgError, "unallocated chain");

    ptr->enums = rb_ary_freeze(enums);
    ptr->pos = -1;

    return obj;
}

static VALUE
new_enum_chain(VALUE enums)
{
    long i;
    VALUE obj = enum_chain_initialize(enum_chain_allocate(rb_cEnumChain), enums);

    for (i = 0; i < RARRAY_LEN(enums); i++) {
        if (RTEST(rb_obj_is_kind_of(RARRAY_AREF(enums, i), rb_cLazy))) {
            return enumerable_lazy(obj);
        }
    }

    return obj;
}

/* :nodoc: */
static VALUE
enum_chain_init_copy(VALUE obj, VALUE orig)
{
    struct enum_chain *ptr0, *ptr1;

    if (!OBJ_INIT_COPY(obj, orig)) return obj;
    ptr0 = enum_chain_ptr(orig);

    TypedData_Get_Struct(obj, struct enum_chain, &enum_chain_data_type, ptr1);

    if (!ptr1) rb_raise(rb_eArgError, "unallocated chain");

    ptr1->enums = ptr0->enums;
    ptr1->pos = ptr0->pos;

    return obj;
}

static VALUE
enum_chain_total_size(VALUE enums)
{
    VALUE total = INT2FIX(0);
    long i;

    for (i = 0; i < RARRAY_LEN(enums); i++) {
        VALUE size = enum_size(RARRAY_AREF(enums, i));

        if (NIL_P(size) || (RB_FLOAT_TYPE_P(size) && isinf(NUM2DBL(size)))) {
            return size;
        }
        if (!RB_INTEGER_TYPE_P(size)) {
            return Qnil;
        }

        total = rb_funcall(total, '+', 1, size);
    }

    return total;
}

/*
 * call-seq:
 *   obj.size -> int, Float::INFINITY or nil
 *
 * Returns the total size of the enumerator chain calculated by
 * summing up the size of each enumerable in the chain.  If any of the
 * enumerables reports its size as nil or Float::INFINITY, that value
 * is returned as the total size.
 */
static VALUE
enum_chain_size(VALUE obj)
{
    return enum_chain_total_size(enum_chain_ptr(obj)->enums);
}

static VALUE
enum_chain_enum_size(VALUE obj, VALUE args, VALUE eobj)
{
    return enum_chain_size(obj);
}

static VALUE
enum_chain_enum_no_size(VALUE obj, VALUE args, VALUE eobj)
{
    return Qnil;
}

/*
 * call-seq:
 *   obj.each(*args) { |...| ... } -> obj
 *   obj.each(*args) -> enumerator
 *
 * Iterates over the elements of the first enumerable by calling the
 * "each" method on it with the given arguments, then proceeds to the
 * following enumerables in sequence until all of the enumerables are
 * exhausted.
 *
 * If no block is given, returns an enumerator.
 */
static VALUE
enum_chain_each(int argc, VALUE *argv, VALUE obj)
{
    VALUE enums, block;
    struct enum_chain *objptr;
    long i;

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, argc > 0 ? enum_chain_enum_no_size : enum_chain_enum_size);

    objptr = enum_chain_ptr(obj);
    enums = objptr->enums;
    block = rb_block_proc();

    for (i = 0; i < RARRAY_LEN(enums); i++) {
        objptr->pos = i;
        rb_funcall_with_block(RARRAY_AREF(enums, i), id_each, argc, argv, block);
    }

    return obj;
}

/*
 * call-seq:
 *   obj.rewind -> obj
 *
 * Rewinds the enumerator chain by calling the "rewind" method on each
 * enumerable in reverse order.  Each call is performed only if the
 * enumerable responds to the method.
 */
static VALUE
enum_chain_rewind(VALUE obj)
{
    struct enum_chain *objptr = enum_chain_ptr(obj);
    VALUE enums = objptr->enums;
    long i;

    for (i = objptr->pos; 0 <= i && i < RARRAY_LEN(enums); objptr->pos = --i) {
        rb_check_funcall(RARRAY_AREF(enums, i), id_rewind, 0, 0);
    }

    return obj;
}

static VALUE
inspect_enum_chain(VALUE obj, VALUE dummy, int recur)
{
    VALUE klass = rb_obj_class(obj);
    struct enum_chain *ptr;

    TypedData_Get_Struct(obj, struct enum_chain, &enum_chain_data_type, ptr);

    if (!ptr || UNDEF_P(ptr->enums)) {
        return rb_sprintf("#<%"PRIsVALUE": uninitialized>", rb_class_path(klass));
    }

    if (recur) {
        return rb_sprintf("#<%"PRIsVALUE": ...>", rb_class_path(klass));
    }

    return rb_sprintf("#<%"PRIsVALUE": %+"PRIsVALUE">", rb_class_path(klass), ptr->enums);
}

/*
 * call-seq:
 *   obj.inspect -> string
 *
 * Returns a printable version of the enumerator chain.
 */
static VALUE
enum_chain_inspect(VALUE obj)
{
    return rb_exec_recursive(inspect_enum_chain, obj, 0);
}

/*
 * call-seq:
 *   e.chain(*enums) -> enumerator
 *
 * Returns an enumerator object generated from this enumerator and
 * given enumerables.
 *
 *   e = (1..3).chain([4, 5])
 *   e.to_a #=> [1, 2, 3, 4, 5]
 */
static VALUE
enum_chain(int argc, VALUE *argv, VALUE obj)
{
    VALUE enums = rb_ary_new_from_values(1, &obj);
    rb_ary_cat(enums, argv, argc);
    return new_enum_chain(enums);
}

/*
 * call-seq:
 *   e + enum -> enumerator
 *
 * Returns an enumerator object generated from this enumerator and a
 * given enumerable.
 *
 *   e = (1..3).each + [4, 5]
 *   e.to_a #=> [1, 2, 3, 4, 5]
 */
static VALUE
enumerator_plus(VALUE obj, VALUE eobj)
{
    return new_enum_chain(rb_ary_new_from_args(2, obj, eobj));
}

/*
 * Document-class: Enumerator::Product
 *
 * Enumerator::Product generates a Cartesian product of any number of
 * enumerable objects.  Iterating over the product of enumerable
 * objects is roughly equivalent to nested each_entry loops where the
 * loop for the rightmost object is put innermost.
 *
 *   innings = Enumerator::Product.new(1..9, ['top', 'bottom'])
 *
 *   innings.each do |i, h|
 *     p [i, h]
 *   end
 *   # [1, "top"]
 *   # [1, "bottom"]
 *   # [2, "top"]
 *   # [2, "bottom"]
 *   # [3, "top"]
 *   # [3, "bottom"]
 *   # ...
 *   # [9, "top"]
 *   # [9, "bottom"]
 *
 * The method used against each enumerable object is `each_entry`
 * instead of `each` so that the product of N enumerable objects
 * yields an array of exactly N elements in each iteration.
 *
 * When no enumerator is given, it calls a given block once yielding
 * an empty argument list.
 *
 * This type of objects can be created by Enumerator.product.
 */

static void
enum_product_mark(void *p)
{
    struct enum_product *ptr = p;
    rb_gc_mark_movable(ptr->enums);
}

static void
enum_product_compact(void *p)
{
    struct enum_product *ptr = p;
    ptr->enums = rb_gc_location(ptr->enums);
}

#define enum_product_free RUBY_TYPED_DEFAULT_FREE

static size_t
enum_product_memsize(const void *p)
{
    return sizeof(struct enum_product);
}

static const rb_data_type_t enum_product_data_type = {
    "product",
    {
        enum_product_mark,
        enum_product_free,
        enum_product_memsize,
        enum_product_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static struct enum_product *
enum_product_ptr(VALUE obj)
{
    struct enum_product *ptr;

    TypedData_Get_Struct(obj, struct enum_product, &enum_product_data_type, ptr);
    if (!ptr || UNDEF_P(ptr->enums)) {
        rb_raise(rb_eArgError, "uninitialized product");
    }
    return ptr;
}

/* :nodoc: */
static VALUE
enum_product_allocate(VALUE klass)
{
    struct enum_product *ptr;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct enum_product, &enum_product_data_type, ptr);
    ptr->enums = Qundef;

    return obj;
}

/*
 * call-seq:
 *   Enumerator::Product.new(*enums) -> enum
 *
 * Generates a new enumerator object that generates a Cartesian
 * product of given enumerable objects.
 *
 *   e = Enumerator::Product.new(1..3, [4, 5])
 *   e.to_a #=> [[1, 4], [1, 5], [2, 4], [2, 5], [3, 4], [3, 5]]
 *   e.size #=> 6
 */
static VALUE
enum_product_initialize(int argc, VALUE *argv, VALUE obj)
{
    struct enum_product *ptr;
    VALUE enums = Qnil, options = Qnil;

    rb_scan_args(argc, argv, "*:", &enums, &options);

    if (!NIL_P(options) && !RHASH_EMPTY_P(options)) {
        rb_exc_raise(rb_keyword_error_new("unknown", rb_hash_keys(options)));
    }

    rb_check_frozen(obj);
    TypedData_Get_Struct(obj, struct enum_product, &enum_product_data_type, ptr);

    if (!ptr) rb_raise(rb_eArgError, "unallocated product");

    ptr->enums = rb_ary_freeze(enums);

    return obj;
}

/* :nodoc: */
static VALUE
enum_product_init_copy(VALUE obj, VALUE orig)
{
    struct enum_product *ptr0, *ptr1;

    if (!OBJ_INIT_COPY(obj, orig)) return obj;
    ptr0 = enum_product_ptr(orig);

    TypedData_Get_Struct(obj, struct enum_product, &enum_product_data_type, ptr1);

    if (!ptr1) rb_raise(rb_eArgError, "unallocated product");

    ptr1->enums = ptr0->enums;

    return obj;
}

static VALUE
enum_product_total_size(VALUE enums)
{
    VALUE total = INT2FIX(1);
    VALUE sizes = rb_ary_hidden_new(RARRAY_LEN(enums));
    long i;

    for (i = 0; i < RARRAY_LEN(enums); i++) {
        VALUE size = enum_size(RARRAY_AREF(enums, i));
        if (size == INT2FIX(0)) {
            rb_ary_resize(sizes, 0);
            return size;
        }
        rb_ary_push(sizes, size);
    }
    for (i = 0; i < RARRAY_LEN(sizes); i++) {
        VALUE size = RARRAY_AREF(sizes, i);

        if (NIL_P(size) || (RB_TYPE_P(size, T_FLOAT) && isinf(NUM2DBL(size)))) {
            return size;
        }
        if (!RB_INTEGER_TYPE_P(size)) {
            return Qnil;
        }

        total = rb_funcall(total, '*', 1, size);
    }

    return total;
}

/*
 * call-seq:
 *   obj.size -> int, Float::INFINITY or nil
 *
 * Returns the total size of the enumerator product calculated by
 * multiplying the sizes of enumerables in the product.  If any of the
 * enumerables reports its size as nil or Float::INFINITY, that value
 * is returned as the size.
 */
static VALUE
enum_product_size(VALUE obj)
{
    return enum_product_total_size(enum_product_ptr(obj)->enums);
}

static VALUE
enum_product_enum_size(VALUE obj, VALUE args, VALUE eobj)
{
    return enum_product_size(obj);
}

struct product_state {
    VALUE  obj;
    VALUE  block;
    int    argc;
    VALUE *argv;
    int    index;
};

static VALUE product_each(VALUE, struct product_state *);

static VALUE
product_each_i(RB_BLOCK_CALL_FUNC_ARGLIST(value, state))
{
    struct product_state *pstate = (struct product_state *)state;
    pstate->argv[pstate->index++] = value;

    VALUE val = product_each(pstate->obj, pstate);
    pstate->index--;
    return val;
}

static VALUE
product_each(VALUE obj, struct product_state *pstate)
{
    struct enum_product *ptr = enum_product_ptr(obj);
    VALUE enums = ptr->enums;

    if (pstate->index < pstate->argc) {
        VALUE eobj = RARRAY_AREF(enums, pstate->index);

        rb_block_call(eobj, id_each_entry, 0, NULL, product_each_i, (VALUE)pstate);
    }
    else {
        rb_funcall(pstate->block, id_call, 1, rb_ary_new_from_values(pstate->argc, pstate->argv));
    }

    return obj;
}

static VALUE
enum_product_run(VALUE obj, VALUE block)
{
    struct enum_product *ptr = enum_product_ptr(obj);
    int argc = RARRAY_LENINT(ptr->enums);
    struct product_state state = {
        .obj = obj,
        .block = block,
        .index = 0,
        .argc = argc,
        .argv = ALLOCA_N(VALUE, argc),
    };

    return product_each(obj, &state);
}

/*
 * call-seq:
 *   obj.each { |...| ... } -> obj
 *   obj.each -> enumerator
 *
 * Iterates over the elements of the first enumerable by calling the
 * "each_entry" method on it with the given arguments, then proceeds
 * to the following enumerables in sequence until all of the
 * enumerables are exhausted.
 *
 * If no block is given, returns an enumerator.  Otherwise, returns self.
 */
static VALUE
enum_product_each(VALUE obj)
{
    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_product_enum_size);

    return enum_product_run(obj, rb_block_proc());
}

/*
 * call-seq:
 *   obj.rewind -> obj
 *
 * Rewinds the product enumerator by calling the "rewind" method on
 * each enumerable in reverse order.  Each call is performed only if
 * the enumerable responds to the method.
 */
static VALUE
enum_product_rewind(VALUE obj)
{
    struct enum_product *ptr = enum_product_ptr(obj);
    VALUE enums = ptr->enums;
    long i;

    for (i = 0; i < RARRAY_LEN(enums); i++) {
        rb_check_funcall(RARRAY_AREF(enums, i), id_rewind, 0, 0);
    }

    return obj;
}

static VALUE
inspect_enum_product(VALUE obj, VALUE dummy, int recur)
{
    VALUE klass = rb_obj_class(obj);
    struct enum_product *ptr;

    TypedData_Get_Struct(obj, struct enum_product, &enum_product_data_type, ptr);

    if (!ptr || UNDEF_P(ptr->enums)) {
        return rb_sprintf("#<%"PRIsVALUE": uninitialized>", rb_class_path(klass));
    }

    if (recur) {
        return rb_sprintf("#<%"PRIsVALUE": ...>", rb_class_path(klass));
    }

    return rb_sprintf("#<%"PRIsVALUE": %+"PRIsVALUE">", rb_class_path(klass), ptr->enums);
}

/*
 * call-seq:
 *   obj.inspect -> string
 *
 * Returns a printable version of the product enumerator.
 */
static VALUE
enum_product_inspect(VALUE obj)
{
    return rb_exec_recursive(inspect_enum_product, obj, 0);
}

/*
 * call-seq:
 *   Enumerator.product(*enums) -> enumerator
 *   Enumerator.product(*enums) { |elts| ... } -> enumerator
 *
 * Generates a new enumerator object that generates a Cartesian
 * product of given enumerable objects.  This is equivalent to
 * Enumerator::Product.new.
 *
 *   e = Enumerator.product(1..3, [4, 5])
 *   e.to_a #=> [[1, 4], [1, 5], [2, 4], [2, 5], [3, 4], [3, 5]]
 *   e.size #=> 6
 *
 * When a block is given, calls the block with each N-element array
 * generated and returns +nil+.
 */
static VALUE
enumerator_s_product(int argc, VALUE *argv, VALUE klass)
{
    VALUE enums = Qnil, options = Qnil, block = Qnil;

    rb_scan_args(argc, argv, "*:&", &enums, &options, &block);

    if (!NIL_P(options) && !RHASH_EMPTY_P(options)) {
        rb_exc_raise(rb_keyword_error_new("unknown", rb_hash_keys(options)));
    }

    VALUE obj = enum_product_initialize(argc, argv, enum_product_allocate(rb_cEnumProduct));

    if (!NIL_P(block)) {
        enum_product_run(obj, block);
        return Qnil;
    }

    return obj;
}

/*
 * Document-class: Enumerator::ArithmeticSequence
 *
 * Enumerator::ArithmeticSequence is a subclass of Enumerator,
 * that is a representation of sequences of numbers with common difference.
 * Instances of this class can be generated by the Range#step and Numeric#step
 * methods.
 *
 * The class can be used for slicing Array (see Array#slice) or custom
 * collections.
 */

VALUE
rb_arith_seq_new(VALUE obj, VALUE meth, int argc, VALUE const *argv,
                 rb_enumerator_size_func *size_fn,
                 VALUE beg, VALUE end, VALUE step, int excl)
{
    VALUE aseq = enumerator_init(enumerator_allocate(rb_cArithSeq),
                                 obj, meth, argc, argv, size_fn, Qnil, rb_keyword_given_p());
    rb_ivar_set(aseq, id_begin, beg);
    rb_ivar_set(aseq, id_end, end);
    rb_ivar_set(aseq, id_step, step);
    rb_ivar_set(aseq, id_exclude_end, RBOOL(excl));
    return aseq;
}

/*
 * call-seq: aseq.begin -> num or nil
 *
 * Returns the number that defines the first element of this arithmetic
 * sequence.
 */
static inline VALUE
arith_seq_begin(VALUE self)
{
    return rb_ivar_get(self, id_begin);
}

/*
 * call-seq: aseq.end -> num or nil
 *
 * Returns the number that defines the end of this arithmetic sequence.
 */
static inline VALUE
arith_seq_end(VALUE self)
{
    return rb_ivar_get(self, id_end);
}

/*
 * call-seq: aseq.step -> num
 *
 * Returns the number that defines the common difference between
 * two adjacent elements in this arithmetic sequence.
 */
static inline VALUE
arith_seq_step(VALUE self)
{
    return rb_ivar_get(self, id_step);
}

/*
 * call-seq: aseq.exclude_end? -> true or false
 *
 * Returns <code>true</code> if this arithmetic sequence excludes its end value.
 */
static inline VALUE
arith_seq_exclude_end(VALUE self)
{
    return rb_ivar_get(self, id_exclude_end);
}

static inline int
arith_seq_exclude_end_p(VALUE self)
{
    return RTEST(arith_seq_exclude_end(self));
}

int
rb_arithmetic_sequence_extract(VALUE obj, rb_arithmetic_sequence_components_t *component)
{
    if (rb_obj_is_kind_of(obj, rb_cArithSeq)) {
        component->begin = arith_seq_begin(obj);
        component->end   = arith_seq_end(obj);
        component->step  = arith_seq_step(obj);
        component->exclude_end = arith_seq_exclude_end_p(obj);
        return 1;
    }
    else if (rb_range_values(obj, &component->begin, &component->end, &component->exclude_end)) {
        component->step  = INT2FIX(1);
        return 1;
    }

    return 0;
}

VALUE
rb_arithmetic_sequence_beg_len_step(VALUE obj, long *begp, long *lenp, long *stepp, long len, int err)
{
    RBIMPL_NONNULL_ARG(begp);
    RBIMPL_NONNULL_ARG(lenp);
    RBIMPL_NONNULL_ARG(stepp);

    rb_arithmetic_sequence_components_t aseq;
    if (!rb_arithmetic_sequence_extract(obj, &aseq)) {
        return Qfalse;
    }

    long step = NIL_P(aseq.step) ? 1 : NUM2LONG(aseq.step);
    *stepp = step;

    if (step < 0) {
        if (aseq.exclude_end && !NIL_P(aseq.end)) {
            /* Handle exclusion before range reversal */
            aseq.end = LONG2NUM(NUM2LONG(aseq.end) + 1);

            /* Don't exclude the previous beginning */
            aseq.exclude_end = 0;
        }
        VALUE tmp = aseq.begin;
        aseq.begin = aseq.end;
        aseq.end = tmp;
    }

    if (err == 0 && (step < -1 || step > 1)) {
        if (rb_range_component_beg_len(aseq.begin, aseq.end, aseq.exclude_end, begp, lenp, len, 1) == Qtrue) {
            if (*begp > len)
                goto out_of_range;
            if (*lenp > len)
                goto out_of_range;
            return Qtrue;
        }
    }
    else {
        return rb_range_component_beg_len(aseq.begin, aseq.end, aseq.exclude_end, begp, lenp, len, err);
    }

  out_of_range:
    rb_raise(rb_eRangeError, "%+"PRIsVALUE" out of range", obj);
    return Qnil;
}

/*
 * call-seq:
 *   aseq.first -> num or nil
 *   aseq.first(n) -> an_array
 *
 * Returns the first number in this arithmetic sequence,
 * or an array of the first +n+ elements.
 */
static VALUE
arith_seq_first(int argc, VALUE *argv, VALUE self)
{
    VALUE b, e, s, ary;
    long n;
    int x;

    rb_check_arity(argc, 0, 1);

    b = arith_seq_begin(self);
    e = arith_seq_end(self);
    s = arith_seq_step(self);
    if (argc == 0) {
        if (NIL_P(b)) {
            return Qnil;
        }
        if (!NIL_P(e)) {
            VALUE zero = INT2FIX(0);
            int r = rb_cmpint(rb_num_coerce_cmp(s, zero, idCmp), s, zero);
            if (r > 0 && RTEST(rb_funcall(b, '>', 1, e))) {
                return Qnil;
            }
            if (r < 0 && RTEST(rb_funcall(b, '<', 1, e))) {
                return Qnil;
            }
        }
        return b;
    }

    // TODO: the following code should be extracted as arith_seq_take

    n = NUM2LONG(argv[0]);
    if (n < 0) {
        rb_raise(rb_eArgError, "attempt to take negative size");
    }
    if (n == 0) {
        return rb_ary_new_capa(0);
    }

    x = arith_seq_exclude_end_p(self);

    if (FIXNUM_P(b) && NIL_P(e) && FIXNUM_P(s)) {
        long i = FIX2LONG(b), unit = FIX2LONG(s);
        ary = rb_ary_new_capa(n);
        while (n > 0 && FIXABLE(i)) {
            rb_ary_push(ary, LONG2FIX(i));
            i += unit;  // FIXABLE + FIXABLE never overflow;
            --n;
        }
        if (n > 0) {
            b = LONG2NUM(i);
            while (n > 0) {
                rb_ary_push(ary, b);
                b = rb_big_plus(b, s);
                --n;
            }
        }
        return ary;
    }
    else if (FIXNUM_P(b) && FIXNUM_P(e) && FIXNUM_P(s)) {
        long i = FIX2LONG(b);
        long end = FIX2LONG(e);
        long unit = FIX2LONG(s);
        long len;

        if (unit >= 0) {
            if (!x) end += 1;

            len = end - i;
            if (len < 0) len = 0;
            ary = rb_ary_new_capa((n < len) ? n : len);
            while (n > 0 && i < end) {
                rb_ary_push(ary, LONG2FIX(i));
                if (i + unit < i) break;
                i += unit;
                --n;
            }
        }
        else {
            if (!x) end -= 1;

            len = i - end;
            if (len < 0) len = 0;
            ary = rb_ary_new_capa((n < len) ? n : len);
            while (n > 0 && i > end) {
                rb_ary_push(ary, LONG2FIX(i));
                if (i + unit > i) break;
                i += unit;
                --n;
            }
        }
        return ary;
    }
    else if (RB_FLOAT_TYPE_P(b) || RB_FLOAT_TYPE_P(e) || RB_FLOAT_TYPE_P(s)) {
        /* generate values like ruby_float_step */

        double unit = NUM2DBL(s);
        double beg = NUM2DBL(b);
        double end = NIL_P(e) ? (unit < 0 ? -1 : 1)*HUGE_VAL : NUM2DBL(e);
        double len = ruby_float_step_size(beg, end, unit, x);
        long i;

        if (n > len)
            n = (long)len;

        if (isinf(unit)) {
            if (len > 0) {
                ary = rb_ary_new_capa(1);
                rb_ary_push(ary, DBL2NUM(beg));
            }
            else {
                ary = rb_ary_new_capa(0);
            }
        }
        else if (unit == 0) {
            VALUE val = DBL2NUM(beg);
            ary = rb_ary_new_capa(n);
            for (i = 0; i < len; ++i) {
                rb_ary_push(ary, val);
            }
        }
        else {
            ary = rb_ary_new_capa(n);
            for (i = 0; i < n; ++i) {
                double d = i*unit+beg;
                if (unit >= 0 ? end < d : d < end) d = end;
                rb_ary_push(ary, DBL2NUM(d));
            }
        }

        return ary;
    }

    return rb_call_super(argc, argv);
}

static inline VALUE
num_plus(VALUE a, VALUE b)
{
    if (RB_INTEGER_TYPE_P(a)) {
        return rb_int_plus(a, b);
    }
    else if (RB_FLOAT_TYPE_P(a)) {
        return rb_float_plus(a, b);
    }
    else if (RB_TYPE_P(a, T_RATIONAL)) {
        return rb_rational_plus(a, b);
    }
    else {
        return rb_funcallv(a, '+', 1, &b);
    }
}

static inline VALUE
num_minus(VALUE a, VALUE b)
{
    if (RB_INTEGER_TYPE_P(a)) {
        return rb_int_minus(a, b);
    }
    else if (RB_FLOAT_TYPE_P(a)) {
        return rb_float_minus(a, b);
    }
    else if (RB_TYPE_P(a, T_RATIONAL)) {
        return rb_rational_minus(a, b);
    }
    else {
        return rb_funcallv(a, '-', 1, &b);
    }
}

static inline VALUE
num_mul(VALUE a, VALUE b)
{
    if (RB_INTEGER_TYPE_P(a)) {
        return rb_int_mul(a, b);
    }
    else if (RB_FLOAT_TYPE_P(a)) {
        return rb_float_mul(a, b);
    }
    else if (RB_TYPE_P(a, T_RATIONAL)) {
        return rb_rational_mul(a, b);
    }
    else {
        return rb_funcallv(a, '*', 1, &b);
    }
}

static inline VALUE
num_idiv(VALUE a, VALUE b)
{
    VALUE q;
    if (RB_INTEGER_TYPE_P(a)) {
        q = rb_int_idiv(a, b);
    }
    else if (RB_FLOAT_TYPE_P(a)) {
        q = rb_float_div(a, b);
    }
    else if (RB_TYPE_P(a, T_RATIONAL)) {
        q = rb_rational_div(a, b);
    }
    else {
        q = rb_funcallv(a, idDiv, 1, &b);
    }

    if (RB_INTEGER_TYPE_P(q)) {
        return q;
    }
    else if (RB_FLOAT_TYPE_P(q)) {
        return rb_float_floor(q, 0);
    }
    else if (RB_TYPE_P(q, T_RATIONAL)) {
        return rb_rational_floor(q, 0);
    }
    else {
        return rb_funcall(q, rb_intern("floor"), 0);
    }
}

/*
 * call-seq:
 *   aseq.last    -> num or nil
 *   aseq.last(n) -> an_array
 *
 * Returns the last number in this arithmetic sequence,
 * or an array of the last +n+ elements.
 */
static VALUE
arith_seq_last(int argc, VALUE *argv, VALUE self)
{
    VALUE b, e, s, len_1, len, last, nv, ary;
    int last_is_adjusted;
    long n;

    e = arith_seq_end(self);
    if (NIL_P(e)) {
        rb_raise(rb_eRangeError,
                 "cannot get the last element of endless arithmetic sequence");
    }

    b = arith_seq_begin(self);
    s = arith_seq_step(self);

    len_1 = num_idiv(num_minus(e, b), s);
    if (rb_num_negative_int_p(len_1)) {
        if (argc == 0) {
            return Qnil;
        }
        return rb_ary_new_capa(0);
    }

    last = num_plus(b, num_mul(s, len_1));
    if ((last_is_adjusted = arith_seq_exclude_end_p(self) && rb_equal(last, e))) {
        last = num_minus(last, s);
    }

    if (argc == 0) {
        return last;
    }

    if (last_is_adjusted) {
        len = len_1;
    }
    else {
        len = rb_int_plus(len_1, INT2FIX(1));
    }

    rb_scan_args(argc, argv, "1", &nv);
    if (!RB_INTEGER_TYPE_P(nv)) {
        nv = rb_to_int(nv);
    }
    if (RTEST(rb_int_gt(nv, len))) {
        nv = len;
    }
    n = NUM2LONG(nv);
    if (n < 0) {
        rb_raise(rb_eArgError, "negative array size");
    }

    ary = rb_ary_new_capa(n);
    b = rb_int_minus(last, rb_int_mul(s, nv));
    while (n) {
        b = rb_int_plus(b, s);
        rb_ary_push(ary, b);
        --n;
    }

    return ary;
}

/*
 * call-seq:
 *   aseq.inspect -> string
 *
 * Convert this arithmetic sequence to a printable form.
 */
static VALUE
arith_seq_inspect(VALUE self)
{
    struct enumerator *e;
    VALUE eobj, str, eargs;
    int range_p;

    TypedData_Get_Struct(self, struct enumerator, &enumerator_data_type, e);

    eobj = rb_attr_get(self, id_receiver);
    if (NIL_P(eobj)) {
        eobj = e->obj;
    }

    range_p = RTEST(rb_obj_is_kind_of(eobj, rb_cRange));
    str = rb_sprintf("(%s%"PRIsVALUE"%s.", range_p ? "(" : "", eobj, range_p ? ")" : "");

    rb_str_buf_append(str, rb_id2str(e->meth));

    eargs = rb_attr_get(eobj, id_arguments);
    if (NIL_P(eargs)) {
        eargs = e->args;
    }
    if (eargs != Qfalse) {
        long argc = RARRAY_LEN(eargs);
        const VALUE *argv = RARRAY_CONST_PTR(eargs); /* WB: no new reference */

        if (argc > 0) {
            VALUE kwds = Qnil;

            rb_str_buf_cat2(str, "(");

            if (RB_TYPE_P(argv[argc-1], T_HASH)) {
                int all_key = TRUE;
                rb_hash_foreach(argv[argc-1], key_symbol_p, (VALUE)&all_key);
                if (all_key) kwds = argv[--argc];
            }

            while (argc--) {
                VALUE arg = *argv++;

                rb_str_append(str, rb_inspect(arg));
                rb_str_buf_cat2(str, ", ");
            }
            if (!NIL_P(kwds)) {
                rb_hash_foreach(kwds, kwd_append, str);
            }
            rb_str_set_len(str, RSTRING_LEN(str)-2); /* drop the last ", " */
            rb_str_buf_cat2(str, ")");
        }
    }

    rb_str_buf_cat2(str, ")");

    return str;
}

/*
 * call-seq:
 *   aseq == obj  -> true or false
 *
 * Returns <code>true</code> only if +obj+ is an Enumerator::ArithmeticSequence,
 * has equivalent begin, end, step, and exclude_end? settings.
 */
static VALUE
arith_seq_eq(VALUE self, VALUE other)
{
    if (!RTEST(rb_obj_is_kind_of(other, rb_cArithSeq))) {
        return Qfalse;
    }

    if (!rb_equal(arith_seq_begin(self), arith_seq_begin(other))) {
        return Qfalse;
    }

    if (!rb_equal(arith_seq_end(self), arith_seq_end(other))) {
        return Qfalse;
    }

    if (!rb_equal(arith_seq_step(self), arith_seq_step(other))) {
        return Qfalse;
    }

    if (arith_seq_exclude_end_p(self) != arith_seq_exclude_end_p(other)) {
        return Qfalse;
    }

    return Qtrue;
}

/*
 * call-seq:
 *   aseq.hash  -> integer
 *
 * Compute a hash-value for this arithmetic sequence.
 * Two arithmetic sequences with same begin, end, step, and exclude_end?
 * values will generate the same hash-value.
 *
 * See also Object#hash.
 */
static VALUE
arith_seq_hash(VALUE self)
{
    st_index_t hash;
    VALUE v;

    hash = rb_hash_start(arith_seq_exclude_end_p(self));
    v = rb_hash(arith_seq_begin(self));
    hash = rb_hash_uint(hash, NUM2LONG(v));
    v = rb_hash(arith_seq_end(self));
    hash = rb_hash_uint(hash, NUM2LONG(v));
    v = rb_hash(arith_seq_step(self));
    hash = rb_hash_uint(hash, NUM2LONG(v));
    hash = rb_hash_end(hash);

    return ST2FIX(hash);
}

#define NUM_GE(x, y) RTEST(rb_num_coerce_relop((x), (y), idGE))

struct arith_seq_gen {
    VALUE current;
    VALUE end;
    VALUE step;
    int excl;
};

/*
 * call-seq:
 *   aseq.each {|i| block } -> aseq
 *   aseq.each              -> aseq
 */
static VALUE
arith_seq_each(VALUE self)
{
    VALUE c, e, s, len_1, last;
    int x;

    if (!rb_block_given_p()) return self;

    c = arith_seq_begin(self);
    e = arith_seq_end(self);
    s = arith_seq_step(self);
    x = arith_seq_exclude_end_p(self);

    if (!RB_TYPE_P(s, T_COMPLEX) && ruby_float_step(c, e, s, x, TRUE)) {
        return self;
    }

    if (NIL_P(e)) {
        while (1) {
            rb_yield(c);
            c = rb_int_plus(c, s);
        }

        return self;
    }

    if (rb_equal(s, INT2FIX(0))) {
        while (1) {
            rb_yield(c);
        }

        return self;
    }

    len_1 = num_idiv(num_minus(e, c), s);
    last = num_plus(c, num_mul(s, len_1));
    if (x && rb_equal(last, e)) {
        last = num_minus(last, s);
    }

    if (rb_num_negative_int_p(s)) {
        while (NUM_GE(c, last)) {
            rb_yield(c);
            c = num_plus(c, s);
        }
    }
    else {
        while (NUM_GE(last, c)) {
            rb_yield(c);
            c = num_plus(c, s);
        }
    }

    return self;
}

/*
 * call-seq:
 *   aseq.size -> num or nil
 *
 * Returns the number of elements in this arithmetic sequence if it is a finite
 * sequence.  Otherwise, returns <code>nil</code>.
 */
static VALUE
arith_seq_size(VALUE self)
{
    VALUE b, e, s, len_1, len, last;
    int x;

    b = arith_seq_begin(self);
    e = arith_seq_end(self);
    s = arith_seq_step(self);
    x = arith_seq_exclude_end_p(self);

    if (RB_FLOAT_TYPE_P(b) || RB_FLOAT_TYPE_P(e) || RB_FLOAT_TYPE_P(s)) {
        double ee, n;

        if (NIL_P(e)) {
            if (rb_num_negative_int_p(s)) {
                ee = -HUGE_VAL;
            }
            else {
                ee = HUGE_VAL;
            }
        }
        else {
            ee = NUM2DBL(e);
        }

        n = ruby_float_step_size(NUM2DBL(b), ee, NUM2DBL(s), x);
        if (isinf(n)) return DBL2NUM(n);
        if (POSFIXABLE(n)) return LONG2FIX((long)n);
        return rb_dbl2big(n);
    }

    if (NIL_P(e)) {
        return DBL2NUM(HUGE_VAL);
    }

    if (!rb_obj_is_kind_of(s, rb_cNumeric)) {
        s = rb_to_int(s);
    }

    if (rb_equal(s, INT2FIX(0))) {
        return DBL2NUM(HUGE_VAL);
    }

    len_1 = rb_int_idiv(rb_int_minus(e, b), s);
    if (rb_num_negative_int_p(len_1)) {
        return INT2FIX(0);
    }

    last = rb_int_plus(b, rb_int_mul(s, len_1));
    if (x && rb_equal(last, e)) {
        len = len_1;
    }
    else {
        len = rb_int_plus(len_1, INT2FIX(1));
    }

    return len;
}

#define sym(name) ID2SYM(rb_intern_const(name))
void
InitVM_Enumerator(void)
{
    ID id_private = rb_intern_const("private");

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
    rb_define_method(rb_cEnumerator, "+", enumerator_plus, 1);
    rb_define_method(rb_mEnumerable, "chain", enum_chain, -1);

    /* Lazy */
    rb_cLazy = rb_define_class_under(rb_cEnumerator, "Lazy", rb_cEnumerator);
    rb_define_method(rb_mEnumerable, "lazy", enumerable_lazy, 0);

    rb_define_alias(rb_cLazy, "_enumerable_map", "map");
    rb_define_alias(rb_cLazy, "_enumerable_collect", "collect");
    rb_define_alias(rb_cLazy, "_enumerable_flat_map", "flat_map");
    rb_define_alias(rb_cLazy, "_enumerable_collect_concat", "collect_concat");
    rb_define_alias(rb_cLazy, "_enumerable_select", "select");
    rb_define_alias(rb_cLazy, "_enumerable_find_all", "find_all");
    rb_define_alias(rb_cLazy, "_enumerable_filter", "filter");
    rb_define_alias(rb_cLazy, "_enumerable_filter_map", "filter_map");
    rb_define_alias(rb_cLazy, "_enumerable_reject", "reject");
    rb_define_alias(rb_cLazy, "_enumerable_grep", "grep");
    rb_define_alias(rb_cLazy, "_enumerable_grep_v", "grep_v");
    rb_define_alias(rb_cLazy, "_enumerable_zip", "zip");
    rb_define_alias(rb_cLazy, "_enumerable_take", "take");
    rb_define_alias(rb_cLazy, "_enumerable_take_while", "take_while");
    rb_define_alias(rb_cLazy, "_enumerable_drop", "drop");
    rb_define_alias(rb_cLazy, "_enumerable_drop_while", "drop_while");
    rb_define_alias(rb_cLazy, "_enumerable_uniq", "uniq");
    rb_define_private_method(rb_cLazy, "_enumerable_with_index", enumerator_with_index, -1);

    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_map"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_collect"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_flat_map"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_collect_concat"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_select"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_find_all"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_filter"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_filter_map"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_reject"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_grep"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_grep_v"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_zip"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_take"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_take_while"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_drop"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_drop_while"));
    rb_funcall(rb_cLazy, id_private, 1, sym("_enumerable_uniq"));

    rb_define_method(rb_cLazy, "initialize", lazy_initialize, -1);
    rb_define_method(rb_cLazy, "to_enum", lazy_to_enum, -1);
    rb_define_method(rb_cLazy, "enum_for", lazy_to_enum, -1);
    rb_define_method(rb_cLazy, "eager", lazy_eager, 0);
    rb_define_method(rb_cLazy, "map", lazy_map, 0);
    rb_define_method(rb_cLazy, "collect", lazy_map, 0);
    rb_define_method(rb_cLazy, "flat_map", lazy_flat_map, 0);
    rb_define_method(rb_cLazy, "collect_concat", lazy_flat_map, 0);
    rb_define_method(rb_cLazy, "select", lazy_select, 0);
    rb_define_method(rb_cLazy, "find_all", lazy_select, 0);
    rb_define_method(rb_cLazy, "filter", lazy_select, 0);
    rb_define_method(rb_cLazy, "filter_map", lazy_filter_map, 0);
    rb_define_method(rb_cLazy, "reject", lazy_reject, 0);
    rb_define_method(rb_cLazy, "grep", lazy_grep, 1);
    rb_define_method(rb_cLazy, "grep_v", lazy_grep_v, 1);
    rb_define_method(rb_cLazy, "zip", lazy_zip, -1);
    rb_define_method(rb_cLazy, "take", lazy_take, 1);
    rb_define_method(rb_cLazy, "take_while", lazy_take_while, 0);
    rb_define_method(rb_cLazy, "drop", lazy_drop, 1);
    rb_define_method(rb_cLazy, "drop_while", lazy_drop_while, 0);
    rb_define_method(rb_cLazy, "lazy", lazy_lazy, 0);
    rb_define_method(rb_cLazy, "chunk", lazy_super, -1);
    rb_define_method(rb_cLazy, "slice_before", lazy_super, -1);
    rb_define_method(rb_cLazy, "slice_after", lazy_super, -1);
    rb_define_method(rb_cLazy, "slice_when", lazy_super, -1);
    rb_define_method(rb_cLazy, "chunk_while", lazy_super, -1);
    rb_define_method(rb_cLazy, "uniq", lazy_uniq, 0);
    rb_define_method(rb_cLazy, "compact", lazy_compact, 0);
    rb_define_method(rb_cLazy, "with_index", lazy_with_index, -1);

    lazy_use_super_method = rb_hash_new_with_size(18);
    rb_hash_aset(lazy_use_super_method, sym("map"), sym("_enumerable_map"));
    rb_hash_aset(lazy_use_super_method, sym("collect"), sym("_enumerable_collect"));
    rb_hash_aset(lazy_use_super_method, sym("flat_map"), sym("_enumerable_flat_map"));
    rb_hash_aset(lazy_use_super_method, sym("collect_concat"), sym("_enumerable_collect_concat"));
    rb_hash_aset(lazy_use_super_method, sym("select"), sym("_enumerable_select"));
    rb_hash_aset(lazy_use_super_method, sym("find_all"), sym("_enumerable_find_all"));
    rb_hash_aset(lazy_use_super_method, sym("filter"), sym("_enumerable_filter"));
    rb_hash_aset(lazy_use_super_method, sym("filter_map"), sym("_enumerable_filter_map"));
    rb_hash_aset(lazy_use_super_method, sym("reject"), sym("_enumerable_reject"));
    rb_hash_aset(lazy_use_super_method, sym("grep"), sym("_enumerable_grep"));
    rb_hash_aset(lazy_use_super_method, sym("grep_v"), sym("_enumerable_grep_v"));
    rb_hash_aset(lazy_use_super_method, sym("zip"), sym("_enumerable_zip"));
    rb_hash_aset(lazy_use_super_method, sym("take"), sym("_enumerable_take"));
    rb_hash_aset(lazy_use_super_method, sym("take_while"), sym("_enumerable_take_while"));
    rb_hash_aset(lazy_use_super_method, sym("drop"), sym("_enumerable_drop"));
    rb_hash_aset(lazy_use_super_method, sym("drop_while"), sym("_enumerable_drop_while"));
    rb_hash_aset(lazy_use_super_method, sym("uniq"), sym("_enumerable_uniq"));
    rb_hash_aset(lazy_use_super_method, sym("with_index"), sym("_enumerable_with_index"));
    rb_obj_freeze(lazy_use_super_method);
    rb_vm_register_global_object(lazy_use_super_method);

#if 0 /* for RDoc */
    rb_define_method(rb_cLazy, "to_a", lazy_to_a, 0);
    rb_define_method(rb_cLazy, "chunk", lazy_chunk, 0);
    rb_define_method(rb_cLazy, "chunk_while", lazy_chunk_while, 0);
    rb_define_method(rb_cLazy, "slice_after", lazy_slice_after, 0);
    rb_define_method(rb_cLazy, "slice_before", lazy_slice_before, 0);
    rb_define_method(rb_cLazy, "slice_when", lazy_slice_when, 0);
#endif
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
    rb_define_method(rb_cYielder, "<<", yielder_yield_push, 1);
    rb_define_method(rb_cYielder, "to_proc", yielder_to_proc, 0);

    /* Producer */
    rb_cEnumProducer = rb_define_class_under(rb_cEnumerator, "Producer", rb_cObject);
    rb_define_alloc_func(rb_cEnumProducer, producer_allocate);
    rb_define_method(rb_cEnumProducer, "each", producer_each, 0);
    rb_define_singleton_method(rb_cEnumerator, "produce", enumerator_s_produce, -1);

    /* Chain */
    rb_cEnumChain = rb_define_class_under(rb_cEnumerator, "Chain", rb_cEnumerator);
    rb_define_alloc_func(rb_cEnumChain, enum_chain_allocate);
    rb_define_method(rb_cEnumChain, "initialize", enum_chain_initialize, -2);
    rb_define_method(rb_cEnumChain, "initialize_copy", enum_chain_init_copy, 1);
    rb_define_method(rb_cEnumChain, "each", enum_chain_each, -1);
    rb_define_method(rb_cEnumChain, "size", enum_chain_size, 0);
    rb_define_method(rb_cEnumChain, "rewind", enum_chain_rewind, 0);
    rb_define_method(rb_cEnumChain, "inspect", enum_chain_inspect, 0);
    rb_undef_method(rb_cEnumChain, "feed");
    rb_undef_method(rb_cEnumChain, "next");
    rb_undef_method(rb_cEnumChain, "next_values");
    rb_undef_method(rb_cEnumChain, "peek");
    rb_undef_method(rb_cEnumChain, "peek_values");

    /* Product */
    rb_cEnumProduct = rb_define_class_under(rb_cEnumerator, "Product", rb_cEnumerator);
    rb_define_alloc_func(rb_cEnumProduct, enum_product_allocate);
    rb_define_method(rb_cEnumProduct, "initialize", enum_product_initialize, -1);
    rb_define_method(rb_cEnumProduct, "initialize_copy", enum_product_init_copy, 1);
    rb_define_method(rb_cEnumProduct, "each", enum_product_each, 0);
    rb_define_method(rb_cEnumProduct, "size", enum_product_size, 0);
    rb_define_method(rb_cEnumProduct, "rewind", enum_product_rewind, 0);
    rb_define_method(rb_cEnumProduct, "inspect", enum_product_inspect, 0);
    rb_undef_method(rb_cEnumProduct, "feed");
    rb_undef_method(rb_cEnumProduct, "next");
    rb_undef_method(rb_cEnumProduct, "next_values");
    rb_undef_method(rb_cEnumProduct, "peek");
    rb_undef_method(rb_cEnumProduct, "peek_values");
    rb_define_singleton_method(rb_cEnumerator, "product", enumerator_s_product, -1);

    /* ArithmeticSequence */
    rb_cArithSeq = rb_define_class_under(rb_cEnumerator, "ArithmeticSequence", rb_cEnumerator);
    rb_undef_alloc_func(rb_cArithSeq);
    rb_undef_method(CLASS_OF(rb_cArithSeq), "new");
    rb_define_method(rb_cArithSeq, "begin", arith_seq_begin, 0);
    rb_define_method(rb_cArithSeq, "end", arith_seq_end, 0);
    rb_define_method(rb_cArithSeq, "exclude_end?", arith_seq_exclude_end, 0);
    rb_define_method(rb_cArithSeq, "step", arith_seq_step, 0);
    rb_define_method(rb_cArithSeq, "first", arith_seq_first, -1);
    rb_define_method(rb_cArithSeq, "last", arith_seq_last, -1);
    rb_define_method(rb_cArithSeq, "inspect", arith_seq_inspect, 0);
    rb_define_method(rb_cArithSeq, "==", arith_seq_eq, 1);
    rb_define_method(rb_cArithSeq, "===", arith_seq_eq, 1);
    rb_define_method(rb_cArithSeq, "eql?", arith_seq_eq, 1);
    rb_define_method(rb_cArithSeq, "hash", arith_seq_hash, 0);
    rb_define_method(rb_cArithSeq, "each", arith_seq_each, 0);
    rb_define_method(rb_cArithSeq, "size", arith_seq_size, 0);

    rb_provide("enumerator.so");	/* for backward compatibility */
}
#undef sym

void
Init_Enumerator(void)
{
    id_rewind = rb_intern_const("rewind");
    id_new = rb_intern_const("new");
    id_next = rb_intern_const("next");
    id_result = rb_intern_const("result");
    id_receiver = rb_intern_const("receiver");
    id_arguments = rb_intern_const("arguments");
    id_memo = rb_intern_const("memo");
    id_method = rb_intern_const("method");
    id_force = rb_intern_const("force");
    id_to_enum = rb_intern_const("to_enum");
    id_each_entry = rb_intern_const("each_entry");
    id_begin = rb_intern_const("begin");
    id_end = rb_intern_const("end");
    id_step = rb_intern_const("step");
    id_exclude_end = rb_intern_const("exclude_end");
    sym_each = ID2SYM(id_each);
    sym_cycle = ID2SYM(rb_intern_const("cycle"));
    sym_yield = ID2SYM(rb_intern_const("yield"));

    InitVM(Enumerator);
}
