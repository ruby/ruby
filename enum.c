/**********************************************************************

  enum.c -

  $Author$
  $Date$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "node.h"
#include "util.h"

VALUE rb_mEnumerable;
static ID id_each, id_eqq, id_cmp;

VALUE
rb_each(obj)
    VALUE obj;
{
    return rb_funcall(obj, id_each, 0, 0);
}

static VALUE
grep_i(i, arg)
    VALUE i, *arg;
{
    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	rb_ary_push(arg[1], i);
    }
    return Qnil;
}

static VALUE
grep_iter_i(i, arg)
    VALUE i, *arg;
{
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
 *     c.grep(/SEEK/)         #=> ["SEEK_END", "SEEK_SET", "SEEK_CUR"]
 *     res = c.grep(/SEEK/) {|v| IO.const_get(v) }
 *     res                    #=> [2, 0, 1]
 *     
 */

static VALUE
enum_grep(obj, pat)
    VALUE obj, pat;
{
    VALUE ary = rb_ary_new();
    VALUE arg[2];

    arg[0] = pat;
    arg[1] = ary;

    rb_iterate(rb_each, obj, rb_block_given_p() ? grep_iter_i : grep_i, (VALUE)arg);
    
    return ary;
}

static VALUE
find_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(rb_yield(i))) {
	memo->u2.value = Qtrue;
	memo->u1.value = i;
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
enum_find(argc, argv, obj)
    int argc;
    VALUE* argv;
    VALUE obj;
{
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, Qfalse, 0);
    VALUE if_none;

    rb_scan_args(argc, argv, "01", &if_none);
    rb_iterate(rb_each, obj, find_i, (VALUE)memo);
    if (memo->u2.value) {
	VALUE result = memo->u1.value;
	rb_gc_force_recycle((VALUE)memo);
	return result;
    }
    rb_gc_force_recycle((VALUE)memo);
    if (!NIL_P(if_none)) {
	return rb_funcall(if_none, rb_intern("call"), 0, 0);
    }
    return Qnil;
}

static VALUE
find_all_i(i, ary)
    VALUE i, ary;
{
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
enum_find_all(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, find_all_i, ary);

    return ary;
}

static VALUE
reject_i(i, ary)
    VALUE i, ary;
{
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
enum_reject(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, reject_i, ary);

    return ary;
}

static VALUE
collect_i(i, ary)
    VALUE i, ary;
{
    rb_ary_push(ary, rb_yield(i));

    return Qnil;
}

static VALUE
collect_all(i, ary)
    VALUE i, ary;
{
    rb_ary_push(ary, i);

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
enum_collect(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();

    rb_iterate(rb_each, obj, rb_block_given_p() ? collect_i : collect_all, ary);

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
enum_to_a(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();

    rb_iterate(rb_each, obj, collect_all, ary);

    return ary;
}

static VALUE
inject_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (memo->u2.value) {
        memo->u2.value = Qfalse;
        memo->u1.value = i;
    }
    else {
        memo->u1.value = rb_yield_values(2, memo->u1.value, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.inject(initial) {| memo, obj | block }  => obj
 *     enum.inject          {| memo, obj | block }  => obj
 *  
 *  Combines the elements of <i>enum</i> by applying the block to an
 *  accumulator value (<i>memo</i>) and each element in turn. At each
 *  step, <i>memo</i> is set to the value returned by the block. The
 *  first form lets you supply an initial value for <i>memo</i>. The
 *  second form uses the first element of the collection as a the
 *  initial value (and skips that element while iterating).
 *     
 *     # Sum some numbers
 *     (5..10).inject {|sum, n| sum + n }              #=> 45
 *     # Multiply some numbers
 *     (5..10).inject(1) {|product, n| product * n }   #=> 151200
 *     
 *     # find the longest word
 *     longest = %w{ cat sheep bear }.inject do |memo,word|
 *        memo.length > word.length ? memo : word
 *     end
 *     longest                                         #=> "sheep"
 *     
 *     # find the length of the longest word
 *     longest = %w{ cat sheep bear }.inject(0) do |memo,word|
 *        memo >= word.length ? memo : word.length
 *     end
 *     longest                                         #=> 5
 *     
 */

static VALUE
enum_inject(argc, argv, obj)
    int argc;
    VALUE *argv, obj;
{
    NODE *memo;
    VALUE n;

    if (rb_scan_args(argc, argv, "01", &n) == 1) {
        memo = rb_node_newnode(NODE_MEMO, n, Qfalse, 0);
    }
    else {
        memo = rb_node_newnode(NODE_MEMO, Qnil, Qtrue, 0);
    }
    rb_iterate(rb_each, obj, inject_i, (VALUE)memo);
    n = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return n;
}

static VALUE
partition_i(i, ary)
    VALUE i, *ary;
{
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
enum_partition(obj)
    VALUE obj;
{
    VALUE ary[2];

    ary[0] = rb_ary_new();
    ary[1] = rb_ary_new();
    rb_iterate(rb_each, obj, partition_i, (VALUE)ary);

    return rb_assoc_new(ary[0], ary[1]);
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
enum_sort(obj)
    VALUE obj;
{
    return rb_ary_sort(enum_to_a(obj));
}

static VALUE
sort_by_i(i, ary)
    VALUE i, ary;
{
    VALUE v;
    NODE *memo;

    v = rb_yield(i);
    memo = rb_node_newnode(NODE_MEMO, v, i, 0);
    rb_ary_push(ary, (VALUE)memo);
    return Qnil;
}

static VALUE
sort_by_cmp(values, ary)
    VALUE values, ary;
{
    NODE *a = (NODE*)RARRAY(values)->ptr[0];
    NODE *b = (NODE*)RARRAY(values)->ptr[1];

    /* pedantic check; they must be memo nodes */
    Check_Type(a, T_NODE);
    Check_Type(b, T_NODE);
    return rb_funcall(a->u1.value, id_cmp, 1, b->u1.value);
}

/*
 *  call-seq:
 *     enum.sort_by {| obj | block }    => array
 *  
 *  Sorts <i>enum</i> using a set of keys generated by mapping the
 *  values in <i>enum</i> through the given block.
 *     
 *     %w{ apple pear fig }.sort_by {|word| word.length}
                    #=> ["fig", "pear", "apple"]
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
enum_sort_by(obj)
    VALUE obj;
{
    VALUE ary;
    long i;

    if (TYPE(obj) == T_ARRAY) {
	ary  = rb_ary_new2(RARRAY(obj)->len);
    }
    else {
	ary = rb_ary_new();
    }
    RBASIC(ary)->klass = 0;
    rb_iterate(rb_each, obj, sort_by_i, ary);
    if (RARRAY(ary)->len > 1) {
	rb_iterate(rb_ary_sort_bang, ary, sort_by_cmp, ary);
    }
    for (i=0; i<RARRAY(ary)->len; i++) {
	RARRAY(ary)->ptr[i] = RNODE(RARRAY(ary)->ptr[i])->u2.value;
    }
    RBASIC(ary)->klass = rb_cArray;
    return ary;
}

static VALUE
all_iter_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (!RTEST(rb_yield(i))) {
	memo->u1.value = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
all_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (!RTEST(i)) {
	memo->u1.value = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

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
 *     %w{ ant bear cat}.all? {|word| word.length >= 3}   #=> true
 *     %w{ ant bear cat}.all? {|word| word.length >= 4}   #=> false
 *     [ nil, true, 99 ].all?                             #=> false
 *     
 */

static VALUE
enum_all(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    memo->u1.value = Qtrue;
    rb_iterate(rb_each, obj, rb_block_given_p() ? all_iter_i : all_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
any_iter_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(rb_yield(i))) {
	memo->u1.value = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
any_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(i)) {
	memo->u1.value = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.any? [{|obj| block } ]   => true or false
 *  
 *  Passes each element of the collection to the given block. The method
 *  returns <code>true</code> if the block ever returns a value other
 *  that <code>false</code> or <code>nil</code>. If the block is not
 *  given, Ruby adds an implicit block of <code>{|obj| obj}</code> (that
 *  is <code>any?</code> will return <code>true</code> if at least one
 *  of the collection members is not <code>false</code> or
 *  <code>nil</code>.
 *     
 *     %w{ ant bear cat}.any? {|word| word.length >= 3}   #=> true
 *     %w{ ant bear cat}.any? {|word| word.length >= 4}   #=> true
 *     [ nil, true, 99 ].any?                             #=> true
 *     
 */

static VALUE
enum_any(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    memo->u1.value = Qfalse;
    rb_iterate(rb_each, obj, rb_block_given_p() ? any_iter_i : any_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
min_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) < 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
min_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_yield_values(2, i, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) < 0) {
	    memo->u1.value = i;
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
enum_min(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p() ? min_ii : min_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
max_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) > 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
max_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_yield_values(2, i, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) > 0) {
	    memo->u1.value = i;
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
enum_max(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p() ? max_ii : max_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
min_by_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE v;

    v = rb_yield(i);
    if (NIL_P(memo->u1.value)) {
	memo->u1.value = v;
	memo->u2.value = i;
    }
    else if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo->u1.value), v, memo->u1.value) < 0) {
	memo->u1.value = v;
	memo->u2.value = i;
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
enum_min_by(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, min_by_i, (VALUE)memo);
    result = memo->u2.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
max_by_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE v;

    v = rb_yield(i);
    if (NIL_P(memo->u1.value)) {
	memo->u1.value = v;
	memo->u2.value = i;
    }
    else if (rb_cmpint(rb_funcall(v, id_cmp, 1, memo->u1.value), v, memo->u1.value) > 0) {
	memo->u1.value = v;
	memo->u2.value = i;
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
enum_max_by(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, max_by_i, (VALUE)memo);
    result = memo->u2.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
member_i(item, memo)
    VALUE item;
    NODE *memo;
{
    if (rb_equal(item, memo->u1.value)) {
	memo->u2.value = Qtrue;
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
 *     IO.constants.include? "SEEK_SET"          #=> true
 *     IO.constants.include? "SEEK_NO_FURTHER"   #=> false
 *     
 */

static VALUE
enum_member(obj, val)
    VALUE obj, val;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, val, Qfalse, 0);

    rb_iterate(rb_each, obj, member_i, (VALUE)memo);
    result = memo->u2.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
each_with_index_i(val, memo)
    VALUE val;
    NODE *memo;
{
    rb_yield_values(2, val, INT2FIX(memo->u3.cnt));
    memo->u3.cnt++;
    return Qnil;
}

/*
 *  call-seq:
 *     enum.each_with_index {|obj, i| block }  -> enum
 *  
 *  Calls <em>block</em> with two arguments, the item and its index, for
 *  each item in <i>enum</i>.
 *     
 *     hash = Hash.new
 *     %w(cat dog wombat).each_with_index {|item, index|
 *       hash[item] = index
 *     }
 *     hash   #=> {"cat"=>0, "wombat"=>2, "dog"=>1}
 *     
 */

static VALUE
enum_each_with_index(obj)
    VALUE obj;
{
    NODE *memo = rb_node_newnode(NODE_MEMO, 0, 0, 0);

    rb_iterate(rb_each, obj, each_with_index_i, (VALUE)memo);
    rb_gc_force_recycle((VALUE)memo);
    return obj;
}

static VALUE
zip_i(val, memo)
    VALUE val;
    NODE *memo;
{
    VALUE result = memo->u1.value;
    VALUE args = memo->u2.value;
    int idx = memo->u3.cnt++;
    VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY(args)->len + 1);
    rb_ary_store(tmp, 0, val);
    for (i=0; i<RARRAY(args)->len; i++) {
	rb_ary_push(tmp, rb_ary_entry(RARRAY(args)->ptr[i], idx));
    }
    if (rb_block_given_p()) {
	rb_yield(tmp);
    }
    else {
	rb_ary_push(result, tmp);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     enum.zip(arg, ...)                   => array
 *     enum.zip(arg, ...) {|arr| block }    => nil
 *  
 *  Converts any arguments to arrays, then merges elements of
 *  <i>enum</i> with corresponding elements from each argument. This
 *  generates a sequence of <code>enum#size</code> <em>n</em>-element
 *  arrays, where <em>n</em> is one more that the count of arguments. If
 *  the size of any argument is less than <code>enum#size</code>,
 *  <code>nil</code> values are supplied. If a block given, it is
 *  invoked for each output array, otherwise an array of arrays is
 *  returned.
 *     
 *     a = [ 4, 5, 6 ]
 *     b = [ 7, 8, 9 ]
 *     
 *     (1..3).zip(a, b)      #=> [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
 *     "cat\ndog".zip([1])   #=> [["cat\n", 1], ["dog", nil]]
 *     (1..3).zip            #=> [[1], [2], [3]]
 *     
 */

static VALUE
enum_zip(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    int i;
    VALUE result;
    NODE *memo;

    for (i=0; i<argc; i++) {
	argv[i] = rb_convert_type(argv[i], T_ARRAY, "Array", "to_a");
    }
    result = rb_block_given_p() ? Qnil : rb_ary_new();
    memo = rb_node_newnode(NODE_MEMO, result, rb_ary_new4(argc, argv), 0);
    rb_iterate(rb_each, obj, zip_i, (VALUE)memo);

    return result;
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
Init_Enumerable()
{
    rb_mEnumerable = rb_define_module("Enumerable");

    rb_define_method(rb_mEnumerable,"to_a", enum_to_a, 0);
    rb_define_method(rb_mEnumerable,"entries", enum_to_a, 0);

    rb_define_method(rb_mEnumerable,"sort", enum_sort, 0);
    rb_define_method(rb_mEnumerable,"sort_by", enum_sort_by, 0);
    rb_define_method(rb_mEnumerable,"grep", enum_grep, 1);
    rb_define_method(rb_mEnumerable,"find", enum_find, -1);
    rb_define_method(rb_mEnumerable,"detect", enum_find, -1);
    rb_define_method(rb_mEnumerable,"find_all", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"select", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"reject", enum_reject, 0);
    rb_define_method(rb_mEnumerable,"collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"map", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"inject", enum_inject, -1);
    rb_define_method(rb_mEnumerable,"partition", enum_partition, 0);
    rb_define_method(rb_mEnumerable,"all?", enum_all, 0);
    rb_define_method(rb_mEnumerable,"any?", enum_any, 0);
    rb_define_method(rb_mEnumerable,"min", enum_min, 0);
    rb_define_method(rb_mEnumerable,"max", enum_max, 0);
    rb_define_method(rb_mEnumerable,"min_by", enum_min_by, 0);
    rb_define_method(rb_mEnumerable,"max_by", enum_max_by, 0);
    rb_define_method(rb_mEnumerable,"member?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"include?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"each_with_index", enum_each_with_index, 0);
    rb_define_method(rb_mEnumerable, "zip", enum_zip, -1);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
}

