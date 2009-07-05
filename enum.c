/**********************************************************************

  enum.c -

  $Author$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/util.h"
#include "node.h"

VALUE rb_mEnumerable;
static ID id_each, id_eqq, id_cmp, id_next, id_size;

static VALUE
enum_values_pack(int argc, VALUE *argv)
{
    if (argc == 0) return Qnil;
    if (argc == 1) return argv[0];
    return rb_ary_new4(argc, argv);
}

#define ENUM_WANT_SVALUE() do { \
    i = enum_values_pack(argc, argv); \
} while (0)

#define enum_yield rb_yield_values2

static VALUE
grep_i(VALUE i, VALUE args, int argc, VALUE *argv)
{
    VALUE *arg = (VALUE *)args;
    ENUM_WANT_SVALUE();

    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	rb_ary_push(arg[1], i);
    }
    return Qnil;
}

static VALUE
grep_iter_i(VALUE i, VALUE args, int argc, VALUE *argv)
{
    VALUE *arg = (VALUE *)args;
    ENUM_WANT_SVALUE();

    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	rb_ary_push(arg[1], rb_yield(i));
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.grep(pattern)                   => array
 *     enum.grep(pattern) {| obj | block }  => array
 *
 *  Returns an array of every element in <i>enum</i> for which
 *  <code>Pattern === element</code>. If the optional <em>block</em> is
 *  supplied, each matching element is passed to it, and the block's
 *  result is stored in the output array.
 *
 *     (1..100).grep 38..44   #=> [38, 39, 40, 41, 42, 43, 44]
 *     c = IO.constants
 *     c.grep(/SEEK/)         #=> [:SEEK_SET, :SEEK_CUR, :SEEK_END]
 *     res = c.grep(/SEEK/) {|v| IO.const_get(v) }
 *     res                    #=> [0, 1, 2]
 *
 */

static VALUE
enum_grep(VALUE obj, VALUE pat)
{
    VALUE ary = rb_ary_new();
    VALUE arg[2];

    arg[0] = pat;
    arg[1] = ary;

    rb_block_call(obj, id_each, 0, 0, rb_block_given_p() ? grep_iter_i : grep_i, (VALUE)arg);

    return ary;
}

static VALUE
count_i(VALUE i, VALUE memop, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE*)memop;

    ENUM_WANT_SVALUE();

    if (rb_equal(i, memo[1])) {
	memo[0]++;
    }
    return Qnil;
}

static VALUE
count_iter_i(VALUE i, VALUE memop, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE*)memop;

    if (RTEST(enum_yield(argc, argv))) {
	memo[0]++;
    }
    return Qnil;
}

static VALUE
count_all_i(VALUE i, VALUE memop, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE*)memop;

    memo[0]++;
    return Qnil;
}

/*
 *  call-seq:
 *     enum.count                   => int
 *     enum.count(item)             => int
 *     enum.count {| obj | block }  => int
 *
 *  Returns the number of items in <i>enum</i>, where #size is called
 *  if it responds to it, otherwise the items are counted through
 *  enumeration.  If an argument is given, counts the number of items
 *  in <i>enum</i>, for which equals to <i>item</i>.  If a block is
 *  given, counts the number of elements yielding a true value.
 *
 *     ary = [1, 2, 4, 2]
 *     ary.count             # => 4
 *     ary.count(2)          # => 2
 *     ary.count{|x|x%2==0}  # => 3
 *
 */

static VALUE
enum_count(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo[2];	/* [count, condition value] */
    rb_block_call_func *func;

    if (argc == 0) {
	if (rb_block_given_p()) {
	    func = count_iter_i;
	}
	else {
	    if (rb_respond_to(obj, id_size)) {
		return rb_funcall(obj, id_size, 0, 0);
	    }
	    func = count_all_i;
	}
    }
    else {
	rb_scan_args(argc, argv, "1", &memo[1]);
	if (rb_block_given_p()) {
	    rb_warn("given block not used");
	}
        func = count_i;
    }

    memo[0] = 0;
    rb_block_call(obj, id_each, 0, 0, func, (VALUE)&memo);
    return INT2NUM(memo[0]);
}

static VALUE
find_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (RTEST(rb_yield(i))) {
	*memo = i;
	rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.detect(ifnone = nil) {| obj | block }  => obj or nil
 *     enum.find(ifnone = nil)   {| obj | block }  => obj or nil
 *
 *  Passes each entry in <i>enum</i> to <em>block</em>. Returns the
 *  first for which <em>block</em> is not <code>false</code>.  If no
 *  object matches, calls <i>ifnone</i> and returns its result when it
 *  is specified, or returns <code>nil</code>
 *
 *     (1..10).detect  {|i| i % 5 == 0 and i % 7 == 0 }   #=> nil
 *     (1..100).detect {|i| i % 5 == 0 and i % 7 == 0 }   #=> 35
 *
 */

static VALUE
enum_find(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo = Qundef;
    VALUE if_none;

    rb_scan_args(argc, argv, "01", &if_none);
    RETURN_ENUMERATOR(obj, argc, argv);
    rb_block_call(obj, id_each, 0, 0, find_i, (VALUE)&memo);
    if (memo != Qundef) {
	return memo;
    }
    if (!NIL_P(if_none)) {
	return rb_funcall(if_none, rb_intern("call"), 0, 0);
    }
    return Qnil;
}

static VALUE
find_index_i(VALUE i, VALUE memop, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE*)memop;

    ENUM_WANT_SVALUE();

    if (rb_equal(i, memo[2])) {
	memo[0] = UINT2NUM(memo[1]);
	rb_iter_break();
    }
    memo[1]++;
    return Qnil;
}

static VALUE
find_index_iter_i(VALUE i, VALUE memop, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE*)memop;

    if (RTEST(enum_yield(argc, argv))) {
	memo[0] = UINT2NUM(memo[1]);
	rb_iter_break();
    }
    memo[1]++;
    return Qnil;
}

/*
 *  call-seq:
 *     enum.find_index(value)            => int or nil
 *     enum.find_index {| obj | block }  => int or nil
 *
 *  Compares each entry in <i>enum</i> with <em>value</em> or passes
 *  to <em>block</em>.  Returns the index for the first for which the
 *  evaluated value is non-false.  If no object matches, returns
 *  <code>nil</code>
 *
 *     (1..10).find_index  {|i| i % 5 == 0 and i % 7 == 0 }   #=> nil
 *     (1..100).find_index {|i| i % 5 == 0 and i % 7 == 0 }   #=> 34
 *     (1..100).find_index(50)                                #=> 49
 *
 */

static VALUE
enum_find_index(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo[3];	/* [return value, current index, condition value] */
    rb_block_call_func *func;

    if (argc == 0) {
        RETURN_ENUMERATOR(obj, 0, 0);
        func = find_index_iter_i;
    }
    else {
	rb_scan_args(argc, argv, "1", &memo[2]);
	if (rb_block_given_p()) {
	    rb_warn("given block not used");
	}
        func = find_index_i;
    }

    memo[0] = Qnil;
    memo[1] = 0;
    rb_block_call(obj, id_each, 0, 0, func, (VALUE)memo);
    return memo[0];
}

static VALUE
find_all_i(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (RTEST(rb_yield(i))) {
	rb_ary_push(ary, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.find_all {| obj | block }  => array
 *     enum.select   {| obj | block }  => array
 *
 *  Returns an array containing all elements of <i>enum</i> for which
 *  <em>block</em> is not <code>false</code> (see also
 *  <code>Enumerable#reject</code>).
 *
 *     (1..10).find_all {|i|  i % 3 == 0 }   #=> [3, 6, 9]
 *
 */

static VALUE
enum_find_all(VALUE obj)
{
    VALUE ary;

    RETURN_ENUMERATOR(obj, 0, 0);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, find_all_i, ary);

    return ary;
}

static VALUE
reject_i(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (!RTEST(rb_yield(i))) {
	rb_ary_push(ary, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.reject {| obj | block }  => array
 *
 *  Returns an array for all elements of <i>enum</i> for which
 *  <em>block</em> is false (see also <code>Enumerable#find_all</code>).
 *
 *     (1..10).reject {|i|  i % 3 == 0 }   #=> [1, 2, 4, 5, 7, 8, 10]
 *
 */

static VALUE
enum_reject(VALUE obj)
{
    VALUE ary;

    RETURN_ENUMERATOR(obj, 0, 0);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, reject_i, ary);

    return ary;
}

static VALUE
collect_i(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    rb_ary_push(ary, enum_yield(argc, argv));

    return Qnil;
}

static VALUE
collect_all(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    rb_thread_check_ints();
    rb_ary_push(ary, enum_values_pack(argc, argv));

    return Qnil;
}

/*
 *  call-seq:
 *     enum.collect {| obj | block }  => array
 *     enum.map     {| obj | block }  => array
 *
 *  Returns a new array with the results of running <em>block</em> once
 *  for every element in <i>enum</i>.
 *
 *     (1..4).collect {|i| i*i }   #=> [1, 4, 9, 16]
 *     (1..4).collect { "cat"  }   #=> ["cat", "cat", "cat", "cat"]
 *
 */

static VALUE
enum_collect(VALUE obj)
{
    VALUE ary;

    RETURN_ENUMERATOR(obj, 0, 0);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, collect_i, ary);

    return ary;
}

/*
 *  call-seq:
 *     enum.to_a      =>    array
 *     enum.entries   =>    array
 *
 *  Returns an array containing the items in <i>enum</i>.
 *
 *     (1..7).to_a                       #=> [1, 2, 3, 4, 5, 6, 7]
 *     { 'a'=>1, 'b'=>2, 'c'=>3 }.to_a   #=> [["a", 1], ["b", 2], ["c", 3]]
 */
static VALUE
enum_to_a(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary = rb_ary_new();

    rb_block_call(obj, id_each, argc, argv, collect_all, ary);

    return ary;
}

static VALUE
inject_i(VALUE i, VALUE p, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE *)p;

    ENUM_WANT_SVALUE();

    if (memo[0] == Qundef) {
	memo[0] = i;
    }
    else {
	memo[0] = rb_yield_values(2, memo[0], i);
    }
    return Qnil;
}

static VALUE
inject_op_i(VALUE i, VALUE p, int argc, VALUE *argv)
{
    VALUE *memo = (VALUE *)p;

    ENUM_WANT_SVALUE();

    if (memo[0] == Qundef) {
	memo[0] = i;
    }
    else {
	memo[0] = rb_funcall(memo[0], (ID)memo[1], 1, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.inject(initial, sym) => obj
 *     enum.inject(sym)          => obj
 *     enum.inject(initial) {| memo, obj | block }  => obj
 *     enum.inject          {| memo, obj | block }  => obj
 *
 *     enum.reduce(initial, sym) => obj
 *     enum.reduce(sym)          => obj
 *     enum.reduce(initial) {| memo, obj | block }  => obj
 *     enum.reduce          {| memo, obj | block }  => obj
 *
 *  Combines all elements of <i>enum</i> by applying a binary
 *  operation, specified by a block or a symbol that names a
 *  method or operator.
 *
 *  If you specify a block, then for each element in <i>enum<i>
 *  the block is passed an accumulator value (<i>memo</i>) and the element.
 *  If you specify a symbol instead, then each element in the collection
 *  will be passed to the named method of <i>memo</i>.
 *  In either case, the result becomes the new value for <i>memo</i>.
 *  At the end of the iteration, the final value of <i>memo</i> is the
 *  return value fo the method.
 *
 *  If you do not explicitly specify an <i>initial</i> value for <i>memo</i>,
 *  then uses the first element of collection is used as the initial value
 *  of <i>memo</i>.
 *
 *  Examples:
 *
 *     # Sum some numbers
 *     (5..10).reduce(:+)                            #=> 45
 *     # Same using a block and inject
 *     (5..10).inject {|sum, n| sum + n }            #=> 45
 *     # Multiply some numbers
 *     (5..10).reduce(1, :*)                         #=> 151200
 *     # Same using a block
 *     (5..10).inject(1) {|product, n| product * n } #=> 151200
 *     # find the longest word
 *     longest = %w{ cat sheep bear }.inject do |memo,word|
 *        memo.length > word.length ? memo : word
 *     end
 *     longest                                       #=> "sheep"
 *
 */
static VALUE
enum_inject(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo[2];
    VALUE (*iter)(VALUE, VALUE, int, VALUE*) = inject_i;

    switch (rb_scan_args(argc, argv, "02", &memo[0], &memo[1])) {
      case 0:
	memo[0] = Qundef;
	break;
      case 1:
	if (rb_block_given_p()) {
	    break;
	}
	memo[1] = (VALUE)rb_to_id(memo[0]);
	memo[0] = Qundef;
	iter = inject_op_i;
	break;
      case 2:
	if (rb_block_given_p()) {
	    rb_warning("given block not used");
	}
	memo[1] = (VALUE)rb_to_id(memo[1]);
	iter = inject_op_i;
	break;
    }
    rb_block_call(obj, id_each, 0, 0, iter, (VALUE)memo);
    if (memo[0] == Qundef) return Qnil;
    return memo[0];
}

static VALUE
partition_i(VALUE i, VALUE *ary, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (RTEST(rb_yield(i))) {
	rb_ary_push(ary[0], i);
    }
    else {
	rb_ary_push(ary[1], i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.partition {| obj | block }  => [ true_array, false_array ]
 *
 *  Returns two arrays, the first containing the elements of
 *  <i>enum</i> for which the block evaluates to true, the second
 *  containing the rest.
 *
 *     (1..6).partition {|i| (i&1).zero?}   #=> [[2, 4, 6], [1, 3, 5]]
 *
 */

static VALUE
enum_partition(VALUE obj)
{
    VALUE ary[2];

    RETURN_ENUMERATOR(obj, 0, 0);

    ary[0] = rb_ary_new();
    ary[1] = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, partition_i, (VALUE)ary);

    return rb_assoc_new(ary[0], ary[1]);
}

static VALUE
group_by_i(VALUE i, VALUE hash, int argc, VALUE *argv)
{
    VALUE group;
    VALUE values;

    ENUM_WANT_SVALUE();

    group = rb_yield(i);
    values = rb_hash_aref(hash, group);
    if (NIL_P(values)) {
	values = rb_ary_new3(1, i);
	rb_hash_aset(hash, group, values);
    }
    else {
	rb_ary_push(values, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.group_by {| obj | block }  => a_hash
 *
 *  Returns a hash, which keys are evaluated result from the
 *  block, and values are arrays of elements in <i>enum</i>
 *  corresponding to the key.
 *
 *     (1..6).group_by {|i| i%3}   #=> {0=>[3, 6], 1=>[1, 4], 2=>[2, 5]}
 *
 */

static VALUE
enum_group_by(VALUE obj)
{
    VALUE hash;

    RETURN_ENUMERATOR(obj, 0, 0);

    hash = rb_hash_new();
    rb_block_call(obj, id_each, 0, 0, group_by_i, hash);

    return hash;
}

static VALUE
first_i(VALUE i, VALUE *params, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (NIL_P(params[1])) {
	params[1] = i;
	rb_iter_break();
    }
    else {
	long n = params[0];

	rb_ary_push(params[1], i);
	n--;
	if (n <= 0) {
	    rb_iter_break();
	}
	params[0] = n;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.first      -> obj or nil
 *     enum.first(n)   -> an_array
 *
 *  Returns the first element, or the first +n+ elements, of the enumerable.
 *  If the enumerable is empty, the first form returns <code>nil</code>, and the
 *  second form returns an empty array.
 *
 */

static VALUE
enum_first(int argc, VALUE *argv, VALUE obj)
{
    VALUE n, params[2];

    if (argc == 0) {
	params[0] = params[1] = Qnil;
    }
    else {
	long len;

	rb_scan_args(argc, argv, "01", &n);
	len = NUM2LONG(n);
	if (len == 0) return rb_ary_new2(0);
	if (len < 0) {
	    rb_raise(rb_eArgError, "negative length");
	}
	params[0] = len;
	params[1] = rb_ary_new2(len);
    }
    rb_block_call(obj, id_each, 0, 0, first_i, (VALUE)params);

    return params[1];
}


/*
 *  call-seq:
 *     enum.sort                     => array
 *     enum.sort {| a, b | block }   => array
 *
 *  Returns an array containing the items in <i>enum</i> sorted,
 *  either according to their own <code><=></code> method, or by using
 *  the results of the supplied block. The block should return -1, 0, or
 *  +1 depending on the comparison between <i>a</i> and <i>b</i>. As of
 *  Ruby 1.8, the method <code>Enumerable#sort_by</code> implements a
 *  built-in Schwartzian Transform, useful when key computation or
 *  comparison is expensive..
 *
 *     %w(rhea kea flea).sort         #=> ["flea", "kea", "rhea"]
 *     (1..10).sort {|a,b| b <=> a}   #=> [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
 */

static VALUE
enum_sort(VALUE obj)
{
    return rb_ary_sort(enum_to_a(0, 0, obj));
}

static VALUE
sort_by_i(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    NODE *memo;

    ENUM_WANT_SVALUE();

    if (RBASIC(ary)->klass) {
	rb_raise(rb_eRuntimeError, "sort_by reentered");
    }
    /* use NODE_DOT2 as memo(v, v, -) */
    memo = rb_node_newnode(NODE_DOT2, rb_yield(i), i, 0);
    rb_ary_push(ary, (VALUE)memo);
    return Qnil;
}

static int
sort_by_cmp(const void *ap, const void *bp, void *data)
{
    VALUE a = (*(NODE *const *)ap)->u1.value;
    VALUE b = (*(NODE *const *)bp)->u1.value;
    VALUE ary = (VALUE)data;

    if (RBASIC(ary)->klass) {
	rb_raise(rb_eRuntimeError, "sort_by reentered");
    }
    return rb_cmpint(rb_funcall(a, id_cmp, 1, b), a, b);
}

/*
 *  call-seq:
 *     enum.sort_by {| obj | block }    => array
 *
 *  Sorts <i>enum</i> using a set of keys generated by mapping the
 *  values in <i>enum</i> through the given block.
 *
 *     %w{ apple pear fig }.sort_by {|word| word.length}
 *                   #=> ["fig", "pear", "apple"]
 *
 *  The current implementation of <code>sort_by</code> generates an
 *  array of tuples containing the original collection element and the
 *  mapped value. This makes <code>sort_by</code> fairly expensive when
 *  the keysets are simple
 *
 *     require 'benchmark'
 *     include Benchmark
 *
 *     a = (1..100000).map {rand(100000)}
 *
 *     bm(10) do |b|
 *       b.report("Sort")    { a.sort }
 *       b.report("Sort by") { a.sort_by {|a| a} }
 *     end
 *
 *  <em>produces:</em>
 *
 *     user     system      total        real
 *     Sort        0.180000   0.000000   0.180000 (  0.175469)
 *     Sort by     1.980000   0.040000   2.020000 (  2.013586)
 *
 *  However, consider the case where comparing the keys is a non-trivial
 *  operation. The following code sorts some files on modification time
 *  using the basic <code>sort</code> method.
 *
 *     files = Dir["*"]
 *     sorted = files.sort {|a,b| File.new(a).mtime <=> File.new(b).mtime}
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This sort is inefficient: it generates two new <code>File</code>
 *  objects during every comparison. A slightly better technique is to
 *  use the <code>Kernel#test</code> method to generate the modification
 *  times directly.
 *
 *     files = Dir["*"]
 *     sorted = files.sort { |a,b|
 *       test(?M, a) <=> test(?M, b)
 *     }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This still generates many unnecessary <code>Time</code> objects. A
 *  more efficient technique is to cache the sort keys (modification
 *  times in this case) before the sort. Perl users often call this
 *  approach a Schwartzian Transform, after Randal Schwartz. We
 *  construct a temporary array, where each element is an array
 *  containing our sort key along with the filename. We sort this array,
 *  and then extract the filename from the result.
 *
 *     sorted = Dir["*"].collect { |f|
 *        [test(?M, f), f]
 *     }.sort.collect { |f| f[1] }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This is exactly what <code>sort_by</code> does internally.
 *
 *     sorted = Dir["*"].sort_by {|f| test(?M, f)}
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 */

static VALUE
enum_sort_by(VALUE obj)
{
    VALUE ary;
    long i;

    RETURN_ENUMERATOR(obj, 0, 0);

    if (TYPE(obj) == T_ARRAY) {
	ary  = rb_ary_new2(RARRAY_LEN(obj));
    }
    else {
	ary = rb_ary_new();
    }
    RBASIC(ary)->klass = 0;
    rb_block_call(obj, id_each, 0, 0, sort_by_i, ary);
    if (RARRAY_LEN(ary) > 1) {
	ruby_qsort(RARRAY_PTR(ary), RARRAY_LEN(ary), sizeof(VALUE),
		   sort_by_cmp, (void *)ary);
    }
    if (RBASIC(ary)->klass) {
	rb_raise(rb_eRuntimeError, "sort_by reentered");
    }
    for (i=0; i<RARRAY_LEN(ary); i++) {
	RARRAY_PTR(ary)[i] = RNODE(RARRAY_PTR(ary)[i])->u2.value;
    }
    RBASIC(ary)->klass = rb_cArray;
    return ary;
}

#define DEFINE_ENUMFUNCS(name) \
static VALUE \
name##_i(VALUE i, VALUE *memo, int argc, VALUE *argv) \
{ \
    return enum_##name##_func(enum_values_pack(argc, argv), memo); \
} \
\
static VALUE \
name##_iter_i(VALUE i, VALUE *memo, int argc, VALUE *argv) \
{ \
    return enum_##name##_func(enum_yield(argc, argv), memo); \
}

static VALUE
enum_all_func(VALUE result, VALUE *memo)
{
    if (!RTEST(result)) {
	*memo = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

DEFINE_ENUMFUNCS(all)

/*
 *  call-seq:
 *     enum.all? [{|obj| block } ]   => true or false
 *
 *  Passes each element of the collection to the given block. The method
 *  returns <code>true</code> if the block never returns
 *  <code>false</code> or <code>nil</code>. If the block is not given,
 *  Ruby adds an implicit block of <code>{|obj| obj}</code> (that is
 *  <code>all?</code> will return <code>true</code> only if none of the
 *  collection members are <code>false</code> or <code>nil</code>.)
 *
 *     %w{ant bear cat}.all? {|word| word.length >= 3}   #=> true
 *     %w{ant bear cat}.all? {|word| word.length >= 4}   #=> false
 *     [ nil, true, 99 ].all?                            #=> false
 *
 */

static VALUE
enum_all(VALUE obj)
{
    VALUE result = Qtrue;

    rb_block_call(obj, id_each, 0, 0, rb_block_given_p() ? all_iter_i : all_i, (VALUE)&result);
    return result;
}

static VALUE
enum_any_func(VALUE result, VALUE *memo)
{
    if (RTEST(result)) {
	*memo = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

DEFINE_ENUMFUNCS(any)

/*
 *  call-seq:
 *     enum.any? [{|obj| block } ]   => true or false
 *
 *  Passes each element of the collection to the given block. The method
 *  returns <code>true</code> if the block ever returns a value other
 *  than <code>false</code> or <code>nil</code>. If the block is not
 *  given, Ruby adds an implicit block of <code>{|obj| obj}</code> (that
 *  is <code>any?</code> will return <code>true</code> if at least one
 *  of the collection members is not <code>false</code> or
 *  <code>nil</code>.
 *
 *     %w{ant bear cat}.any? {|word| word.length >= 3}   #=> true
 *     %w{ant bear cat}.any? {|word| word.length >= 4}   #=> true
 *     [ nil, true, 99 ].any?                            #=> true
 *
 */

static VALUE
enum_any(VALUE obj)
{
    VALUE result = Qfalse;

    rb_block_call(obj, id_each, 0, 0, rb_block_given_p() ? any_iter_i : any_i, (VALUE)&result);
    return result;
}

static VALUE
enum_one_func(VALUE result, VALUE *memo)
{
    if (RTEST(result)) {
	if (*memo == Qundef) {
	    *memo = Qtrue;
	}
	else if (*memo == Qtrue) {
	    *memo = Qfalse;
	    rb_iter_break();
	}
    }
    return Qnil;
}

DEFINE_ENUMFUNCS(one)

/*
 *  call-seq:
 *     enum.one? [{|obj| block }]   => true or false
 *
 *  Passes each element of the collection to the given block. The method
 *  returns <code>true</code> if the block returns <code>true</code>
 *  exactly once. If the block is not given, <code>one?</code> will return
 *  <code>true</code> only if exactly one of the collection members is
 *  true.
 *
 *     %w{ant bear cat}.one? {|word| word.length == 4}   #=> true
 *     %w{ant bear cat}.one? {|word| word.length > 4}    #=> false
 *     %w{ant bear cat}.one? {|word| word.length < 4}    #=> false
 *     [ nil, true, 99 ].one?                            #=> false
 *     [ nil, true, false ].one?                         #=> true
 *
 */

static VALUE
enum_one(VALUE obj)
{
    VALUE result = Qundef;

    rb_block_call(obj, id_each, 0, 0, rb_block_given_p() ? one_iter_i : one_i, (VALUE)&result);
    if (result == Qundef) return Qfalse;
    return result;
}

static VALUE
enum_none_func(VALUE result, VALUE *memo)
{
    if (RTEST(result)) {
	*memo = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

DEFINE_ENUMFUNCS(none)

/*
 *  call-seq:
 *     enum.none? [{|obj| block }]   => true or false
 *
 *  Passes each element of the collection to the given block. The method
 *  returns <code>true</code> if the block never returns <code>true</code>
 *  for all elements. If the block is not given, <code>none?</code> will return
 *  <code>true</code> only if none of the collection members is true.
 *
 *     %w{ant bear cat}.none? {|word| word.length == 5}  #=> true
 *     %w{ant bear cat}.none? {|word| word.length >= 4}  #=> false
 *     [].none?                                          #=> true
 *     [nil].none?                                       #=> true
 *     [nil,false].none?                                 #=> true
 */
static VALUE
enum_none(VALUE obj)
{
    VALUE result = Qtrue;

    rb_block_call(obj, id_each, 0, 0, rb_block_given_p() ? none_iter_i : none_i, (VALUE)&result);
    return result;
}

static VALUE
min_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE cmp;

    ENUM_WANT_SVALUE();

    if (*memo == Qundef) {
	*memo = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, *memo);
	if (rb_cmpint(cmp, i, *memo) < 0) {
	    *memo = i;
	}
    }
    return Qnil;
}

static VALUE
min_ii(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE cmp;

    ENUM_WANT_SVALUE();

    if (*memo == Qundef) {
	*memo = i;
    }
    else {
	VALUE ary = memo[1];
	RARRAY_PTR(ary)[0] = i;
	RARRAY_PTR(ary)[1] = *memo;
	cmp = rb_yield(ary);
	if (rb_cmpint(cmp, i, *memo) < 0) {
	    *memo = i;
	}
    }
    return Qnil;
}


/*
 *  call-seq:
 *     enum.min                    => obj
 *     enum.min {| a,b | block }   => obj
 *
 *  Returns the object in <i>enum</i> with the minimum value. The
 *  first form assumes all objects implement <code>Comparable</code>;
 *  the second uses the block to return <em>a <=> b</em>.
 *
 *     a = %w(albatross dog horse)
 *     a.min                                  #=> "albatross"
 *     a.min {|a,b| a.length <=> b.length }   #=> "dog"
 */

static VALUE
enum_min(VALUE obj)
{
    VALUE result[2];

    result[0] = Qundef;
    if (rb_block_given_p()) {
	result[1] = rb_ary_new3(2, Qnil, Qnil);
	rb_block_call(obj, id_each, 0, 0, min_ii, (VALUE)result);
    }
    else {
	rb_block_call(obj, id_each, 0, 0, min_i, (VALUE)result);
    }
    if (result[0] == Qundef) return Qnil;
    return result[0];
}

static VALUE
max_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE cmp;

    ENUM_WANT_SVALUE();

    if (*memo == Qundef) {
	*memo = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, *memo);
	if (rb_cmpint(cmp, i, *memo) > 0) {
	    *memo = i;
	}
    }
    return Qnil;
}

static VALUE
max_ii(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE cmp;

    ENUM_WANT_SVALUE();

    if (*memo == Qundef) {
	*memo = i;
    }
    else {
	VALUE ary = memo[1];
	RARRAY_PTR(ary)[0] = i;
	RARRAY_PTR(ary)[1] = *memo;
	cmp = rb_yield(ary);
	if (rb_cmpint(cmp, i, *memo) > 0) {
	    *memo = i;
	}
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.max                   => obj
 *     enum.max {|a,b| block }    => obj
 *
 *  Returns the object in _enum_ with the maximum value. The
 *  first form assumes all objects implement <code>Comparable</code>;
 *  the second uses the block to return <em>a <=> b</em>.
 *
 *     a = %w(albatross dog horse)
 *     a.max                                  #=> "horse"
 *     a.max {|a,b| a.length <=> b.length }   #=> "albatross"
 */

static VALUE
enum_max(VALUE obj)
{
    VALUE result[2];

    result[0] = Qundef;
    if (rb_block_given_p()) {
	result[1] = rb_ary_new3(2, Qnil, Qnil);
	rb_block_call(obj, id_each, 0, 0, max_ii, (VALUE)result);
    }
    else {
	rb_block_call(obj, id_each, 0, 0, max_i, (VALUE)result);
    }
    if (result[0] == Qundef) return Qnil;
    return result[0];
}

static VALUE
minmax_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    int n;

    ENUM_WANT_SVALUE();

    if (memo[0] == Qundef) {
	memo[0] = i;
	memo[1] = i;
    }
    else {
	n = rb_cmpint(rb_funcall(i, id_cmp, 1, memo[0]), i, memo[0]);
	if (n < 0) {
	    memo[0] = i;
	}
	n = rb_cmpint(rb_funcall(i, id_cmp, 1, memo[1]), i, memo[1]);
	if (n > 0) {
	    memo[1] = i;
	}
    }
    return Qnil;
}

static VALUE
minmax_ii(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    int n;

    ENUM_WANT_SVALUE();

    if (memo[0] == Qundef) {
	memo[0] = i;
	memo[1] = i;
    }
    else {
	VALUE ary = memo[2];

	RARRAY_PTR(ary)[0] = i;
	RARRAY_PTR(ary)[1] = memo[0];
	n = rb_cmpint(rb_yield(ary), i, memo[0]);
	if (n < 0) {
	    memo[0] = i;
	}
	RARRAY_PTR(ary)[0] = i;
	RARRAY_PTR(ary)[1] = memo[1];
	n = rb_cmpint(rb_yield(ary), i, memo[1]);
	if (n > 0) {
	    memo[1] = i;
	}
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.minmax                   => [min,max]
 *     enum.minmax {|a,b| block }    => [min,max]
 *
 *  Returns two elements array which contains the minimum and the
 *  maximum value in the enumerable.  The first form assumes all
 *  objects implement <code>Comparable</code>; the second uses the
 *  block to return <em>a <=> b</em>.
 *
 *     a = %w(albatross dog horse)
 *     a.minmax                                  #=> ["albatross", "horse"]
 *     a.minmax {|a,b| a.length <=> b.length }   #=> ["dog", "albatross"]
 */

static VALUE
enum_minmax(VALUE obj)
{
    VALUE result[3];
    VALUE ary = rb_ary_new3(2, Qnil, Qnil);

    result[0] = Qundef;
    if (rb_block_given_p()) {
	result[2] = ary;
	rb_block_call(obj, id_each, 0, 0, minmax_ii, (VALUE)result);
    }
    else {
	rb_block_call(obj, id_each, 0, 0, minmax_i, (VALUE)result);
    }
    if (result[0] != Qundef) {
        RARRAY_PTR(ary)[0] = result[0];
        RARRAY_PTR(ary)[1] = result[1];
    }
    return ary;
}

static VALUE
min_by_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE v;

    ENUM_WANT_SVALUE();

    v = rb_yield(i);
    if (memo[0] == Qundef) {
	memo[0] = v;
	memo[1] = i;
    }
    else if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo[0]), v, memo[0]) < 0) {
	memo[0] = v;
	memo[1] = i;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.min_by {| obj| block }   => obj
 *
 *  Returns the object in <i>enum</i> that gives the minimum
 *  value from the given block.
 *
 *     a = %w(albatross dog horse)
 *     a.min_by {|x| x.length }   #=> "dog"
 */

static VALUE
enum_min_by(VALUE obj)
{
    VALUE memo[2];

    RETURN_ENUMERATOR(obj, 0, 0);

    memo[0] = Qundef;
    memo[1] = Qnil;
    rb_block_call(obj, id_each, 0, 0, min_by_i, (VALUE)memo);
    return memo[1];
}

static VALUE
max_by_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE v;

    ENUM_WANT_SVALUE();

    v = rb_yield(i);
    if (memo[0] == Qundef) {
	memo[0] = v;
	memo[1] = i;
    }
    else if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo[0]), v, memo[0]) > 0) {
	memo[0] = v;
	memo[1] = i;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.max_by {| obj| block }   => obj
 *
 *  Returns the object in <i>enum</i> that gives the maximum
 *  value from the given block.
 *
 *     a = %w(albatross dog horse)
 *     a.max_by {|x| x.length }   #=> "albatross"
 */

static VALUE
enum_max_by(VALUE obj)
{
    VALUE memo[2];

    RETURN_ENUMERATOR(obj, 0, 0);

    memo[0] = Qundef;
    memo[1] = Qnil;
    rb_block_call(obj, id_each, 0, 0, max_by_i, (VALUE)memo);
    return memo[1];
}

static VALUE
minmax_by_i(VALUE i, VALUE *memo, int argc, VALUE *argv)
{
    VALUE v;

    ENUM_WANT_SVALUE();

    v = rb_yield(i);
    if (memo[0] == Qundef) {
	memo[0] = v;
	memo[1] = v;
	memo[2] = i;
	memo[3] = i;
    }
    else {
	if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo[0]), v, memo[0]) < 0) {
	    memo[0] = v;
	    memo[2] = i;
	}
	if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo[1]), v, memo[1]) > 0) {
	    memo[1] = v;
	    memo[3] = i;
	}
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.minmax_by {| obj| block }   => [min, max]
 *
 *  Returns two elements array array containing the objects in
 *  <i>enum</i> that gives the minimum and maximum values respectively
 *  from the given block.
 *
 *     a = %w(albatross dog horse)
 *     a.minmax_by {|x| x.length }   #=> ["dog", "albatross"]
 */

static VALUE
enum_minmax_by(VALUE obj)
{
    VALUE memo[4];

    RETURN_ENUMERATOR(obj, 0, 0);

    memo[0] = Qundef;
    memo[1] = Qundef;
    memo[2] = Qnil;
    memo[3] = Qnil;
    rb_block_call(obj, id_each, 0, 0, minmax_by_i, (VALUE)memo);
    return rb_assoc_new(memo[2], memo[3]);
}

static VALUE
member_i(VALUE iter, VALUE *memo, int argc, VALUE *argv)
{
    if (rb_equal(enum_values_pack(argc, argv), memo[0])) {
	memo[1] = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.include?(obj)     => true or false
 *     enum.member?(obj)      => true or false
 *
 *  Returns <code>true</code> if any member of <i>enum</i> equals
 *  <i>obj</i>. Equality is tested using <code>==</code>.
 *
 *     IO.constants.include? :SEEK_SET          #=> true
 *     IO.constants.include? :SEEK_NO_FURTHER   #=> false
 *
 */

static VALUE
enum_member(VALUE obj, VALUE val)
{
    VALUE memo[2];

    memo[0] = val;
    memo[1] = Qfalse;
    rb_block_call(obj, id_each, 0, 0, member_i, (VALUE)memo);
    return memo[1];
}

static VALUE
each_with_index_i(VALUE i, VALUE memo, int argc, VALUE *argv)
{
    long n = (*(VALUE *)memo)++;

    return rb_yield_values(2, enum_values_pack(argc, argv), INT2NUM(n));
}

/*
 *  call-seq:
 *     enum.each_with_index {|obj, i| block }  -> enum
 *
 *  Calls <em>block</em> with two arguments, the item and its index,
 *  for each item in <i>enum</i>.  Given arguments are passed through
 *  to #each().
 *
 *     hash = Hash.new
 *     %w(cat dog wombat).each_with_index {|item, index|
 *       hash[item] = index
 *     }
 *     hash   #=> {"cat"=>0, "dog"=>1, "wombat"=>2}
 *
 */

static VALUE
enum_each_with_index(int argc, VALUE *argv, VALUE obj)
{
    long memo;

    RETURN_ENUMERATOR(obj, argc, argv);

    memo = 0;
    rb_block_call(obj, id_each, argc, argv, each_with_index_i, (VALUE)&memo);
    return obj;
}


/*
 *  call-seq:
 *     enum.reverse_each {|item| block }
 *
 *  Traverses <i>enum</i> in reverse order.
 */

static VALUE
enum_reverse_each(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary;
    long i;

    RETURN_ENUMERATOR(obj, argc, argv);

    ary = enum_to_a(argc, argv, obj);

    for (i = RARRAY_LEN(ary); --i >= 0; ) {
	rb_yield(RARRAY_PTR(ary)[i]);
    }

    return obj;
}


static VALUE
zip_ary(VALUE val, NODE *memo, int argc, VALUE *argv)
{
    volatile VALUE result = memo->u1.value;
    volatile VALUE args = memo->u2.value;
    long n = memo->u3.cnt++;
    volatile VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY_LEN(args) + 1);
    rb_ary_store(tmp, 0, enum_values_pack(argc, argv));
    for (i=0; i<RARRAY_LEN(args); i++) {
	VALUE e = RARRAY_PTR(args)[i];

	if (RARRAY_LEN(e) <= n) {
	    rb_ary_push(tmp, Qnil);
	}
	else {
	    rb_ary_push(tmp, RARRAY_PTR(e)[n]);
	}
    }
    if (NIL_P(result)) {
	rb_yield(tmp);
    }
    else {
	rb_ary_push(result, tmp);
    }
    return Qnil;
}

static VALUE
call_next(VALUE *v)
{
    return v[0] = rb_funcall(v[1], id_next, 0, 0);
}

static VALUE
call_stop(VALUE *v)
{
    return v[0] = Qundef;
}

static VALUE
zip_i(VALUE val, NODE *memo, int argc, VALUE *argv)
{
    volatile VALUE result = memo->u1.value;
    volatile VALUE args = memo->u2.value;
    volatile VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY_LEN(args) + 1);
    rb_ary_store(tmp, 0, enum_values_pack(argc, argv));
    for (i=0; i<RARRAY_LEN(args); i++) {
	if (NIL_P(RARRAY_PTR(args)[i])) {
	    rb_ary_push(tmp, Qnil);
	}
	else {
	    VALUE v[2];

	    v[1] = RARRAY_PTR(args)[i];
	    rb_rescue2(call_next, (VALUE)v, call_stop, (VALUE)v, rb_eStopIteration, 0);
	    if (v[0] == Qundef) {
		RARRAY_PTR(args)[i] = Qnil;
		v[0] = Qnil;
	    }
	    rb_ary_push(tmp, v[0]);
	}
    }
    if (NIL_P(result)) {
	rb_yield(tmp);
    }
    else {
	rb_ary_push(result, tmp);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.zip(arg, ...)                   => enumerator
 *     enum.zip(arg, ...) {|arr| block }    => nil
 *
 *  Takes one element from <i>enum</i> and merges corresponding
 *  elements from each <i>args</i>.  This generates a sequence of
 *  <em>n</em>-element arrays, where <em>n</em> is one more than the
 *  count of arguments.  The length of the resulting sequence will be
 *  <code>enum#size</code.  If the size of any argument is less than
 *  <code>enum#size</code>, <code>nil</code> values are supplied. If
 *  a block is given, it is invoked for each output array, otherwise
 *  an array of arrays is returned.
 *
 *     a = [ 4, 5, 6 ]
 *     b = [ 7, 8, 9 ]
 *
 *     [1,2,3].zip(a, b)      #=> [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
 *     [1,2].zip(a,b)         #=> [[1, 4, 7], [2, 5, 8]]
 *     a.zip([1,2],[8])       #=> [[4, 1, 8], [5, 2, nil], [6, nil, nil]]
 *
 */

static VALUE
enum_zip(int argc, VALUE *argv, VALUE obj)
{
    int i;
    ID conv;
    NODE *memo;
    VALUE result = Qnil;
    VALUE args = rb_ary_new4(argc, argv);
    int allary = Qtrue;

    argv = RARRAY_PTR(args);
    for (i=0; i<argc; i++) {
	VALUE ary = rb_check_array_type(argv[i]);
	if (NIL_P(ary)) {
	    allary = Qfalse;
	    break;
	}
	argv[i] = ary;
    }
    if (!allary) {
	CONST_ID(conv, "to_enum");
	for (i=0; i<argc; i++) {
	    argv[i] = rb_funcall(argv[i], conv, 1, ID2SYM(id_each));
	}
    }
    if (!rb_block_given_p()) {
	result = rb_ary_new();
    }
    /* use NODE_DOT2 as memo(v, v, -) */
    memo = rb_node_newnode(NODE_DOT2, result, args, 0);
    rb_block_call(obj, id_each, 0, 0, allary ? zip_ary : zip_i, (VALUE)memo);

    return result;
}

static VALUE
take_i(VALUE i, VALUE *arg, int argc, VALUE *argv)
{
    rb_ary_push(arg[0], enum_values_pack(argc, argv));
    if (--arg[1] == 0) rb_iter_break();
    return Qnil;
}

/*
 *  call-seq:
 *     enum.take(n)               => array
 *
 *  Returns first n elements from <i>enum</i>.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take(3)             # => [1, 2, 3]
 *
 */

static VALUE
enum_take(VALUE obj, VALUE n)
{
    VALUE args[2];
    long len = NUM2LONG(n);

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to take negative size");
    }

    if (len == 0) return rb_ary_new2(0);
    args[0] = rb_ary_new();
    args[1] = len;
    rb_block_call(obj, id_each, 0, 0, take_i, (VALUE)args);
    return args[0];
}


static VALUE
take_while_i(VALUE i, VALUE *ary, int argc, VALUE *argv)
{
    if (!RTEST(enum_yield(argc, argv))) rb_iter_break();
    rb_ary_push(*ary, enum_values_pack(argc, argv));
    return Qnil;
}

/*
 *  call-seq:
 *     enum.take_while {|arr| block }   => array
 *
 *  Passes elements to the block until the block returns nil or false,
 *  then stops iterating and returns an array of all prior elements.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take_while {|i| i < 3 }   # => [1, 2]
 *
 */

static VALUE
enum_take_while(VALUE obj)
{
    VALUE ary;

    RETURN_ENUMERATOR(obj, 0, 0);
    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, take_while_i, (VALUE)&ary);
    return ary;
}

static VALUE
drop_i(VALUE i, VALUE *arg, int argc, VALUE *argv)
{
    if (arg[1] == 0) {
	rb_ary_push(arg[0], enum_values_pack(argc, argv));
    }
    else {
	arg[1]--;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.drop(n)               => array
 *
 *  Drops first n elements from <i>enum</i>, and returns rest elements
 *  in an array.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop(3)             # => [4, 5, 0]
 *
 */

static VALUE
enum_drop(VALUE obj, VALUE n)
{
    VALUE args[2];
    long len = NUM2LONG(n);

    if (len < 0) {
	rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    args[1] = len;
    args[0] = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, drop_i, (VALUE)args);
    return args[0];
}


static VALUE
drop_while_i(VALUE i, VALUE *args, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    if (!args[1] && !RTEST(rb_yield(i))) {
	args[1] = Qtrue;
    }
    if (args[1]) {
	rb_ary_push(args[0], i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.drop_while {|arr| block }   => array
 *
 *  Drops elements up to, but not including, the first element for
 *  which the block returns nil or false and returns an array
 *  containing the remaining elements.
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop_while {|i| i < 3 }   # => [3, 4, 5, 0]
 *
 */

static VALUE
enum_drop_while(VALUE obj)
{
    VALUE args[2];

    RETURN_ENUMERATOR(obj, 0, 0);
    args[0] = rb_ary_new();
    args[1] = Qfalse;
    rb_block_call(obj, id_each, 0, 0, drop_while_i, (VALUE)args);
    return args[0];
}

static VALUE
cycle_i(VALUE i, VALUE ary, int argc, VALUE *argv)
{
    ENUM_WANT_SVALUE();

    rb_ary_push(ary, i);
    rb_yield(i);
    return Qnil;
}

/*
 *  call-seq:
 *     enum.cycle {|obj| block }
 *     enum.cycle(n) {|obj| block }
 *
 *  Calls <i>block</i> for each element of <i>enum</i> repeatedly _n_
 *  times or forever if none or nil is given.  If a non-positive
 *  number is given or the collection is empty, does nothing.  Returns
 *  nil if the loop has finished without getting interrupted.
 *
 *  Enumerable#cycle saves elements in an internal array so changes
 *  to <i>enum</i> after the first pass have no effect.
 *
 *     a = ["a", "b", "c"]
 *     a.cycle {|x| puts x }  # print, a, b, c, a, b, c,.. forever.
 *     a.cycle(2) {|x| puts x }  # print, a, b, c, a, b, c.
 *
 */

static VALUE
enum_cycle(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary;
    VALUE nv = Qnil;
    long n, i, len;

    rb_scan_args(argc, argv, "01", &nv);

    RETURN_ENUMERATOR(obj, argc, argv);
    if (NIL_P(nv)) {
        n = -1;
    }
    else {
        n = NUM2LONG(nv);
        if (n <= 0) return Qnil;
    }
    ary = rb_ary_new();
    RBASIC(ary)->klass = 0;
    rb_block_call(obj, id_each, 0, 0, cycle_i, ary);
    len = RARRAY_LEN(ary);
    if (len == 0) return Qnil;
    while (n < 0 || 0 < --n) {
        for (i=0; i<len; i++) {
            rb_yield(RARRAY_PTR(ary)[i]);
        }
    }
    return Qnil;		/* not reached */
}

/*
 *  call-seq:
 *     enum.join(sep=$,)    -> str
 *
 *  Returns a string created by converting each element of the
 *  <i>enum</i> to a string, separated by <i>sep</i>.
 */

static VALUE
enum_join(int argc, VALUE *argv, VALUE obj)
{
    VALUE sep;

    rb_scan_args(argc, argv, "01", &sep);
    if (NIL_P(sep)) sep = rb_output_fs;

    return rb_ary_join(enum_to_a(0, 0, obj), sep);
}

/*
 *  The <code>Enumerable</code> mixin provides collection classes with
 *  several traversal and searching methods, and with the ability to
 *  sort. The class must provide a method <code>each</code>, which
 *  yields successive members of the collection. If
 *  <code>Enumerable#max</code>, <code>#min</code>, or
 *  <code>#sort</code> is used, the objects in the collection must also
 *  implement a meaningful <code><=></code> operator, as these methods
 *  rely on an ordering between members of the collection.
 */

void
Init_Enumerable(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_mEnumerable = rb_define_module("Enumerable");

    rb_define_method(rb_mEnumerable, "to_a", enum_to_a, -1);
    rb_define_method(rb_mEnumerable, "entries", enum_to_a, -1);

    rb_define_method(rb_mEnumerable, "sort", enum_sort, 0);
    rb_define_method(rb_mEnumerable, "sort_by", enum_sort_by, 0);
    rb_define_method(rb_mEnumerable, "grep", enum_grep, 1);
    rb_define_method(rb_mEnumerable, "count", enum_count, -1);
    rb_define_method(rb_mEnumerable, "find", enum_find, -1);
    rb_define_method(rb_mEnumerable, "detect", enum_find, -1);
    rb_define_method(rb_mEnumerable, "find_index", enum_find_index, -1);
    rb_define_method(rb_mEnumerable, "find_all", enum_find_all, 0);
    rb_define_method(rb_mEnumerable, "select", enum_find_all, 0);
    rb_define_method(rb_mEnumerable, "reject", enum_reject, 0);
    rb_define_method(rb_mEnumerable, "collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable, "map", enum_collect, 0);
    rb_define_method(rb_mEnumerable, "inject", enum_inject, -1);
    rb_define_method(rb_mEnumerable, "reduce", enum_inject, -1);
    rb_define_method(rb_mEnumerable, "partition", enum_partition, 0);
    rb_define_method(rb_mEnumerable, "group_by", enum_group_by, 0);
    rb_define_method(rb_mEnumerable, "first", enum_first, -1);
    rb_define_method(rb_mEnumerable, "all?", enum_all, 0);
    rb_define_method(rb_mEnumerable, "any?", enum_any, 0);
    rb_define_method(rb_mEnumerable, "one?", enum_one, 0);
    rb_define_method(rb_mEnumerable, "none?", enum_none, 0);
    rb_define_method(rb_mEnumerable, "min", enum_min, 0);
    rb_define_method(rb_mEnumerable, "max", enum_max, 0);
    rb_define_method(rb_mEnumerable, "minmax", enum_minmax, 0);
    rb_define_method(rb_mEnumerable, "min_by", enum_min_by, 0);
    rb_define_method(rb_mEnumerable, "max_by", enum_max_by, 0);
    rb_define_method(rb_mEnumerable, "minmax_by", enum_minmax_by, 0);
    rb_define_method(rb_mEnumerable, "member?", enum_member, 1);
    rb_define_method(rb_mEnumerable, "include?", enum_member, 1);
    rb_define_method(rb_mEnumerable, "each_with_index", enum_each_with_index, -1);
    rb_define_method(rb_mEnumerable, "reverse_each", enum_reverse_each, -1);
    rb_define_method(rb_mEnumerable, "zip", enum_zip, -1);
    rb_define_method(rb_mEnumerable, "take", enum_take, 1);
    rb_define_method(rb_mEnumerable, "take_while", enum_take_while, 0);
    rb_define_method(rb_mEnumerable, "drop", enum_drop, 1);
    rb_define_method(rb_mEnumerable, "drop_while", enum_drop_while, 0);
    rb_define_method(rb_mEnumerable, "cycle", enum_cycle, -1);
    rb_define_method(rb_mEnumerable, "join", enum_join, -1);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
    id_next = rb_intern("next");
    id_size = rb_intern("size");
}

