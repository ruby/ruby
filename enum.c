/**********************************************************************

  enum.c -

  $Author$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "id.h"
#include "internal.h"
#include "internal/compar.h"
#include "internal/enum.h"
#include "internal/hash.h"
#include "internal/imemo.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/rational.h"
#include "internal/re.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "symbol.h"

VALUE rb_mEnumerable;

static ID id_next;
static ID id__alone;
static ID id__separator;
static ID id_chunk_categorize;
static ID id_chunk_enumerable;
static ID id_sliceafter_enum;
static ID id_sliceafter_pat;
static ID id_sliceafter_pred;
static ID id_slicebefore_enumerable;
static ID id_slicebefore_sep_pat;
static ID id_slicebefore_sep_pred;
static ID id_slicewhen_enum;
static ID id_slicewhen_inverted;
static ID id_slicewhen_pred;

#define id_div idDiv
#define id_each idEach
#define id_eqq  idEqq
#define id_cmp  idCmp
#define id_lshift idLTLT
#define id_call idCall
#define id_size idSize

VALUE
rb_enum_values_pack(int argc, const VALUE *argv)
{
    if (argc == 0) return Qnil;
    if (argc == 1) return argv[0];
    return rb_ary_new4(argc, argv);
}

#define ENUM_WANT_SVALUE() do { \
    i = rb_enum_values_pack(argc, argv); \
} while (0)

static VALUE
enum_yield(int argc, VALUE ary)
{
    if (argc > 1)
        return rb_yield_force_blockarg(ary);
    if (argc == 1)
        return rb_yield(ary);
    return rb_yield_values2(0, 0);
}

static VALUE
enum_yield_array(VALUE ary)
{
    long len = RARRAY_LEN(ary);

    if (len > 1)
        return rb_yield_force_blockarg(ary);
    if (len == 1)
        return rb_yield(RARRAY_AREF(ary, 0));
    return rb_yield_values2(0, 0);
}

static VALUE
grep_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    ENUM_WANT_SVALUE();

    if (RTEST(rb_funcallv(memo->v1, id_eqq, 1, &i)) == RTEST(memo->u3.value)) {
        rb_ary_push(memo->v2, i);
    }
    return Qnil;
}

static VALUE
grep_regexp_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    VALUE converted_element, match;
    ENUM_WANT_SVALUE();

    /* In case element can't be converted to a Symbol or String: not a match (don't raise) */
    converted_element = SYMBOL_P(i) ? i : rb_check_string_type(i);
    match = NIL_P(converted_element) ? Qfalse : rb_reg_match_p(memo->v1, i, 0);
    if (match == memo->u3.value) {
        rb_ary_push(memo->v2, i);
    }
    return Qnil;
}

static VALUE
grep_iter_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    ENUM_WANT_SVALUE();

    if (RTEST(rb_funcallv(memo->v1, id_eqq, 1, &i)) == RTEST(memo->u3.value)) {
        rb_ary_push(memo->v2, enum_yield(argc, i));
    }
    return Qnil;
}

static VALUE
enum_grep0(VALUE obj, VALUE pat, VALUE test)
{
    VALUE ary = rb_ary_new();
    struct MEMO *memo = MEMO_NEW(pat, ary, test);
    rb_block_call_func_t fn;
    if (rb_block_given_p()) {
        fn = grep_iter_i;
    }
    else if (RB_TYPE_P(pat, T_REGEXP) &&
      LIKELY(rb_method_basic_definition_p(CLASS_OF(pat), idEqq))) {
        fn = grep_regexp_i;
    }
    else {
        fn = grep_i;
    }
    rb_block_call(obj, id_each, 0, 0, fn, (VALUE)memo);

    return ary;
}

/*
 * call-seq:
 *   grep(pattern) -> array
 *   grep(pattern) {|element| ... } -> array
 *
 * Returns an array of objects based elements of +self+ that match the given pattern.
 *
 * With no block given, returns an array containing each element
 * for which <tt>pattern === element</tt> is +true+:
 *
 *   a = ['foo', 'bar', 'car', 'moo']
 *   a.grep(/ar/)                   # => ["bar", "car"]
 *   (1..10).grep(3..8)             # => [3, 4, 5, 6, 7, 8]
 *   ['a', 'b', 0, 1].grep(Integer) # => [0, 1]
 *
 * With a block given,
 * calls the block with each matching element and returns an array containing each
 * object returned by the block:
 *
 *   a = ['foo', 'bar', 'car', 'moo']
 *   a.grep(/ar/) {|element| element.upcase } # => ["BAR", "CAR"]
 *
 * Related: #grep_v.
 */

static VALUE
enum_grep(VALUE obj, VALUE pat)
{
    return enum_grep0(obj, pat, Qtrue);
}

/*
 * call-seq:
 *   grep_v(pattern) -> array
 *   grep_v(pattern) {|element| ... } -> array
 *
 * Returns an array of objects based on elements of +self+
 * that <em>don't</em> match the given pattern.
 *
 * With no block given, returns an array containing each element
 * for which <tt>pattern === element</tt> is +false+:
 *
 *   a = ['foo', 'bar', 'car', 'moo']
 *   a.grep_v(/ar/)                   # => ["foo", "moo"]
 *   (1..10).grep_v(3..8)             # => [1, 2, 9, 10]
 *   ['a', 'b', 0, 1].grep_v(Integer) # => ["a", "b"]
 *
 * With a block given,
 * calls the block with each non-matching element and returns an array containing each
 * object returned by the block:
 *
 *   a = ['foo', 'bar', 'car', 'moo']
 *   a.grep_v(/ar/) {|element| element.upcase } # => ["FOO", "MOO"]
 *
 * Related: #grep.
 */

static VALUE
enum_grep_v(VALUE obj, VALUE pat)
{
    return enum_grep0(obj, pat, Qfalse);
}

#define COUNT_BIGNUM IMEMO_FL_USER0
#define MEMO_V3_SET(m, v) RB_OBJ_WRITE((m), &(m)->u3.value, (v))

static void
imemo_count_up(struct MEMO *memo)
{
    if (memo->flags & COUNT_BIGNUM) {
        MEMO_V3_SET(memo, rb_int_succ(memo->u3.value));
    }
    else if (++memo->u3.cnt == 0) {
        /* overflow */
        unsigned long buf[2] = {0, 1};
        MEMO_V3_SET(memo, rb_big_unpack(buf, 2));
        memo->flags |= COUNT_BIGNUM;
    }
}

static VALUE
imemo_count_value(struct MEMO *memo)
{
    if (memo->flags & COUNT_BIGNUM) {
        return memo->u3.value;
    }
    else {
        return ULONG2NUM(memo->u3.cnt);
    }
}

static VALUE
count_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    struct MEMO *memo = MEMO_CAST(memop);

    ENUM_WANT_SVALUE();

    if (rb_equal(i, memo->v1)) {
        imemo_count_up(memo);
    }
    return Qnil;
}

static VALUE
count_iter_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    struct MEMO *memo = MEMO_CAST(memop);

    if (RTEST(rb_yield_values2(argc, argv))) {
        imemo_count_up(memo);
    }
    return Qnil;
}

static VALUE
count_all_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    struct MEMO *memo = MEMO_CAST(memop);

    imemo_count_up(memo);
    return Qnil;
}

/*
 * call-seq:
 *   count -> integer
 *   count(object) -> integer
 *   count {|element| ... } -> integer
 *
 * Returns the count of elements, based on an argument or block criterion, if given.
 *
 * With no argument and no block given, returns the number of elements:
 *
 *   [0, 1, 2].count                # => 3
 *   {foo: 0, bar: 1, baz: 2}.count # => 3
 *
 * With argument +object+ given,
 * returns the number of elements that are <tt>==</tt> to +object+:
 *
 *   [0, 1, 2, 1].count(1)           # => 2
 *
 * With a block given, calls the block with each element
 * and returns the number of elements for which the block returns a truthy value:
 *
 *   [0, 1, 2, 3].count {|element| element < 2}              # => 2
 *   {foo: 0, bar: 1, baz: 2}.count {|key, value| value < 2} # => 2
 *
 */

static VALUE
enum_count(int argc, VALUE *argv, VALUE obj)
{
    VALUE item = Qnil;
    struct MEMO *memo;
    rb_block_call_func *func;

    if (argc == 0) {
        if (rb_block_given_p()) {
            func = count_iter_i;
        }
        else {
            func = count_all_i;
        }
    }
    else {
        rb_scan_args(argc, argv, "1", &item);
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        func = count_i;
    }

    memo = MEMO_NEW(item, 0, 0);
    rb_block_call(obj, id_each, 0, 0, func, (VALUE)memo);
    return imemo_count_value(memo);
}

static VALUE
find_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    ENUM_WANT_SVALUE();

    if (RTEST(enum_yield(argc, i))) {
        struct MEMO *memo = MEMO_CAST(memop);
        MEMO_V1_SET(memo, i);
        memo->u3.cnt = 1;
        rb_iter_break();
    }
    return Qnil;
}

/*
 * call-seq:
 *   find(if_none_proc = nil) {|element| ... } -> object or nil
 *   find(if_none_proc = nil) -> enumerator
 *
 * Returns the first element for which the block returns a truthy value.
 *
 * With a block given, calls the block with successive elements of the collection;
 * returns the first element for which the block returns a truthy value:
 *
 *   (0..9).find {|element| element > 2}                # => 3
 *
 * If no such element is found, calls +if_none_proc+ and returns its return value.
 *
 *   (0..9).find(proc {false}) {|element| element > 12} # => false
 *   {foo: 0, bar: 1, baz: 2}.find {|key, value| key.start_with?('b') }            # => [:bar, 1]
 *   {foo: 0, bar: 1, baz: 2}.find(proc {[]}) {|key, value| key.start_with?('c') } # => []
 *
 * With no block given, returns an Enumerator.
 *
 */
static VALUE
enum_find(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;
    VALUE if_none;

    if_none = rb_check_arity(argc, 0, 1) ? argv[0] : Qnil;
    RETURN_ENUMERATOR(obj, argc, argv);
    memo = MEMO_NEW(Qundef, 0, 0);
    rb_block_call(obj, id_each, 0, 0, find_i, (VALUE)memo);
    if (memo->u3.cnt) {
        return memo->v1;
    }
    if (!NIL_P(if_none)) {
        return rb_funcallv(if_none, id_call, 0, 0);
    }
    return Qnil;
}

static VALUE
find_index_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    struct MEMO *memo = MEMO_CAST(memop);

    ENUM_WANT_SVALUE();

    if (rb_equal(i, memo->v2)) {
        MEMO_V1_SET(memo, imemo_count_value(memo));
        rb_iter_break();
    }
    imemo_count_up(memo);
    return Qnil;
}

static VALUE
find_index_iter_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memop))
{
    struct MEMO *memo = MEMO_CAST(memop);

    if (RTEST(rb_yield_values2(argc, argv))) {
        MEMO_V1_SET(memo, imemo_count_value(memo));
        rb_iter_break();
    }
    imemo_count_up(memo);
    return Qnil;
}

/*
 * call-seq:
 *   find_index(object) -> integer or nil
 *   find_index {|element| ... } -> integer or nil
 *   find_index -> enumerator
 *
 * Returns the index of the first element that meets a specified criterion,
 * or +nil+ if no such element is found.
 *
 * With argument +object+ given,
 * returns the index of the first element that is <tt>==</tt> +object+:
 *
 *   ['a', 'b', 'c', 'b'].find_index('b') # => 1
 *
 * With a block given, calls the block with successive elements;
 * returns the first element for which the block returns a truthy value:
 *
 *   ['a', 'b', 'c', 'b'].find_index {|element| element.start_with?('b') } # => 1
 *   {foo: 0, bar: 1, baz: 2}.find_index {|key, value| value > 1 }         # => 2
 *
 * With no argument and no block given, returns an Enumerator.
 *
 */

static VALUE
enum_find_index(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;	/* [return value, current index, ] */
    VALUE condition_value = Qnil;
    rb_block_call_func *func;

    if (argc == 0) {
        RETURN_ENUMERATOR(obj, 0, 0);
        func = find_index_iter_i;
    }
    else {
        rb_scan_args(argc, argv, "1", &condition_value);
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        func = find_index_i;
    }

    memo = MEMO_NEW(Qnil, condition_value, 0);
    rb_block_call(obj, id_each, 0, 0, func, (VALUE)memo);
    return memo->v1;
}

static VALUE
find_all_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    ENUM_WANT_SVALUE();

    if (RTEST(enum_yield(argc, i))) {
        rb_ary_push(ary, i);
    }
    return Qnil;
}

static VALUE
enum_size(VALUE self, VALUE args, VALUE eobj)
{
    return rb_check_funcall_default(self, id_size, 0, 0, Qnil);
}

static long
limit_by_enum_size(VALUE obj, long n)
{
    unsigned long limit;
    VALUE size = rb_check_funcall(obj, id_size, 0, 0);
    if (!FIXNUM_P(size)) return n;
    limit = FIX2ULONG(size);
    return ((unsigned long)n > limit) ? (long)limit : n;
}

static int
enum_size_over_p(VALUE obj, long n)
{
    VALUE size = rb_check_funcall(obj, id_size, 0, 0);
    if (!FIXNUM_P(size)) return 0;
    return ((unsigned long)n > FIX2ULONG(size));
}

/*
 * call-seq:
 *   select {|element| ... } -> array
 *   select -> enumerator
 *
 * Returns an array containing elements selected by the block.
 *
 * With a block given, calls the block with successive elements;
 * returns an array of those elements for which the block returns a truthy value:
 *
 *   (0..9).select {|element| element % 3 == 0 } # => [0, 3, 6, 9]
 *   a = {foo: 0, bar: 1, baz: 2}.select {|key, value| key.start_with?('b') }
 *   a # => {:bar=>1, :baz=>2}
 *
 * With no block given, returns an Enumerator.
 *
 * Related: #reject.
 */
static VALUE
enum_find_all(VALUE obj)
{
    VALUE ary;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, find_all_i, ary);

    return ary;
}

static VALUE
filter_map_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    i = rb_yield_values2(argc, argv);

    if (RTEST(i)) {
        rb_ary_push(ary, i);
    }

    return Qnil;
}

/*
 * call-seq:
 *   filter_map {|element| ... } -> array
 *   filter_map -> enumerator
 *
 * Returns an array containing truthy elements returned by the block.
 *
 * With a block given, calls the block with successive elements;
 * returns an array containing each truthy value returned by the block:
 *
 *   (0..9).filter_map {|i| i * 2 if i.even? }                              # => [0, 4, 8, 12, 16]
 *   {foo: 0, bar: 1, baz: 2}.filter_map {|key, value| key if value.even? } # => [:foo, :baz]
 *
 * When no block given, returns an Enumerator.
 *
 */
static VALUE
enum_filter_map(VALUE obj)
{
    VALUE ary;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, filter_map_i, ary);

    return ary;
}


static VALUE
reject_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    ENUM_WANT_SVALUE();

    if (!RTEST(enum_yield(argc, i))) {
        rb_ary_push(ary, i);
    }
    return Qnil;
}

/*
 * call-seq:
 *   reject {|element| ... } -> array
 *   reject -> enumerator
 *
 * Returns an array of objects rejected by the block.
 *
 * With a block given, calls the block with successive elements;
 * returns an array of those elements for which the block returns +nil+ or +false+:
 *
 *   (0..9).reject {|i| i * 2 if i.even? }                             # => [1, 3, 5, 7, 9]
 *   {foo: 0, bar: 1, baz: 2}.reject {|key, value| key if value.odd? } # => {:foo=>0, :baz=>2}
 *
 * When no block given, returns an Enumerator.
 *
 * Related: #select.
 */

static VALUE
enum_reject(VALUE obj)
{
    VALUE ary;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, reject_i, ary);

    return ary;
}

static VALUE
collect_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    rb_ary_push(ary, rb_yield_values2(argc, argv));

    return Qnil;
}

static VALUE
collect_all(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    rb_ary_push(ary, rb_enum_values_pack(argc, argv));

    return Qnil;
}

/*
 * call-seq:
 *   map {|element| ... } -> array
 *   map -> enumerator
 *
 * Returns an array of objects returned by the block.
 *
 * With a block given, calls the block with successive elements;
 * returns an array of the objects returned by the block:
 *
 *   (0..4).map {|i| i*i }                               # => [0, 1, 4, 9, 16]
 *   {foo: 0, bar: 1, baz: 2}.map {|key, value| value*2} # => [0, 2, 4]
 *
 * With no block given, returns an Enumerator.
 *
 */
static VALUE
enum_collect(VALUE obj)
{
    VALUE ary;
    int min_argc, max_argc;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    ary = rb_ary_new();
    min_argc = rb_block_min_max_arity(&max_argc);
    rb_lambda_call(obj, id_each, 0, 0, collect_i, min_argc, max_argc, ary);

    return ary;
}

static VALUE
flat_map_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    VALUE tmp;

    i = rb_yield_values2(argc, argv);
    tmp = rb_check_array_type(i);

    if (NIL_P(tmp)) {
        rb_ary_push(ary, i);
    }
    else {
        rb_ary_concat(ary, tmp);
    }
    return Qnil;
}

/*
 * call-seq:
 *   flat_map {|element| ... } -> array
 *   flat_map -> enumerator
 *
 * Returns an array of flattened objects returned by the block.
 *
 * With a block given, calls the block with successive elements;
 * returns a flattened array of objects returned by the block:
 *
 *   [0, 1, 2, 3].flat_map {|element| -element }                    # => [0, -1, -2, -3]
 *   [0, 1, 2, 3].flat_map {|element| [element, -element] }         # => [0, 0, 1, -1, 2, -2, 3, -3]
 *   [[0, 1], [2, 3]].flat_map {|e| e + [100] }                     # => [0, 1, 100, 2, 3, 100]
 *   {foo: 0, bar: 1, baz: 2}.flat_map {|key, value| [key, value] } # => [:foo, 0, :bar, 1, :baz, 2]
 *
 * With no block given, returns an Enumerator.
 *
 * Alias: #collect_concat.
 */
static VALUE
enum_flat_map(VALUE obj)
{
    VALUE ary;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, flat_map_i, ary);

    return ary;
}

/*
 *  call-seq:
 *    to_a(*args) -> array
 *
 *  Returns an array containing the items in +self+:
 *
 *    (0..4).to_a # => [0, 1, 2, 3, 4]
 *
 */
static VALUE
enum_to_a(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary = rb_ary_new();

    rb_block_call_kw(obj, id_each, argc, argv, collect_all, ary, RB_PASS_CALLED_KEYWORDS);

    return ary;
}

static VALUE
enum_hashify_into(VALUE obj, int argc, const VALUE *argv, rb_block_call_func *iter, VALUE hash)
{
    rb_block_call(obj, id_each, argc, argv, iter, hash);
    return hash;
}

static VALUE
enum_hashify(VALUE obj, int argc, const VALUE *argv, rb_block_call_func *iter)
{
    return enum_hashify_into(obj, argc, argv, iter, rb_hash_new());
}

static VALUE
enum_to_h_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    ENUM_WANT_SVALUE();
    return rb_hash_set_pair(hash, i);
}

static VALUE
enum_to_h_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    return rb_hash_set_pair(hash, rb_yield_values2(argc, argv));
}

/*
 *  call-seq:
 *    to_h(*args) -> hash
 *    to_h(*args) {|element| ... }  -> hash
 *
 *  When +self+ consists of 2-element arrays,
 *  returns a hash each of whose entries is the key-value pair
 *  formed from one of those arrays:
 *
 *    [[:foo, 0], [:bar, 1], [:baz, 2]].to_h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  When a block is given, the block is called with each element of +self+;
 *  the block should return a 2-element array which becomes a key-value pair
 *  in the returned hash:
 *
 *    (0..3).to_h {|i| [i, i ** 2]} # => {0=>0, 1=>1, 2=>4, 3=>9}
 *
 *  Raises an exception if an element of +self+ is not a 2-element array,
 *  and a block is not passed.
 */

static VALUE
enum_to_h(int argc, VALUE *argv, VALUE obj)
{
    rb_block_call_func *iter = rb_block_given_p() ? enum_to_h_ii : enum_to_h_i;
    return enum_hashify(obj, argc, argv, iter);
}

static VALUE
inject_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, p))
{
    struct MEMO *memo = MEMO_CAST(p);

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->v1)) {
        MEMO_V1_SET(memo, i);
    }
    else {
        MEMO_V1_SET(memo, rb_yield_values(2, memo->v1, i));
    }
    return Qnil;
}

static VALUE
inject_op_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, p))
{
    struct MEMO *memo = MEMO_CAST(p);
    VALUE name;

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->v1)) {
        MEMO_V1_SET(memo, i);
    }
    else if (SYMBOL_P(name = memo->u3.value)) {
        const ID mid = SYM2ID(name);
        MEMO_V1_SET(memo, rb_funcallv_public(memo->v1, mid, 1, &i));
    }
    else {
        VALUE args[2];
        args[0] = name;
        args[1] = i;
        MEMO_V1_SET(memo, rb_f_send(numberof(args), args, memo->v1));
    }
    return Qnil;
}

static VALUE
ary_inject_op(VALUE ary, VALUE init, VALUE op)
{
    ID id;
    VALUE v, e;
    long i, n;

    if (RARRAY_LEN(ary) == 0)
        return UNDEF_P(init) ? Qnil : init;

    if (UNDEF_P(init)) {
        v = RARRAY_AREF(ary, 0);
        i = 1;
        if (RARRAY_LEN(ary) == 1)
            return v;
    }
    else {
        v = init;
        i = 0;
    }

    id = SYM2ID(op);
    if (id == idPLUS) {
        if (RB_INTEGER_TYPE_P(v) &&
            rb_method_basic_definition_p(rb_cInteger, idPLUS) &&
            rb_obj_respond_to(v, idPLUS, FALSE)) {
            n = 0;
            for (; i < RARRAY_LEN(ary); i++) {
                e = RARRAY_AREF(ary, i);
                if (FIXNUM_P(e)) {
                    n += FIX2LONG(e); /* should not overflow long type */
                    if (!FIXABLE(n)) {
                        v = rb_big_plus(LONG2NUM(n), v);
                        n = 0;
                    }
                }
                else if (RB_BIGNUM_TYPE_P(e))
                    v = rb_big_plus(e, v);
                else
                    goto not_integer;
            }
            if (n != 0)
                v = rb_fix_plus(LONG2FIX(n), v);
            return v;

          not_integer:
            if (n != 0)
                v = rb_fix_plus(LONG2FIX(n), v);
        }
    }
    for (; i < RARRAY_LEN(ary); i++) {
        VALUE arg = RARRAY_AREF(ary, i);
        v = rb_funcallv_public(v, id, 1, &arg);
    }
    return v;
}

/*
 *  call-seq:
 *    inject(symbol) -> object
 *    inject(initial_operand, symbol) -> object
 *    inject {|memo, operand| ... } -> object
 *    inject(initial_operand) {|memo, operand| ... } -> object
 *
 *  Returns an object formed from operands via either:
 *
 *  - A method named by +symbol+.
 *  - A block to which each operand is passed.
 *
 *  With method-name argument +symbol+,
 *  combines operands using the method:
 *
 *    # Sum, without initial_operand.
 *    (1..4).inject(:+)     # => 10
 *    # Sum, with initial_operand.
 *    (1..4).inject(10, :+) # => 20
 *
 *  With a block, passes each operand to the block:
 *
 *    # Sum of squares, without initial_operand.
 *    (1..4).inject {|sum, n| sum + n*n }    # => 30
 *    # Sum of squares, with initial_operand.
 *    (1..4).inject(2) {|sum, n| sum + n*n } # => 32
 *
 *  <b>Operands</b>
 *
 *  If argument +initial_operand+ is not given,
 *  the operands for +inject+ are simply the elements of +self+.
 *  Example calls and their operands:
 *
 *  - <tt>(1..4).inject(:+)</tt>:: <tt>[1, 2, 3, 4]</tt>.
 *  - <tt>(1...4).inject(:+)</tt>:: <tt>[1, 2, 3]</tt>.
 *  - <tt>('a'..'d').inject(:+)</tt>:: <tt>['a', 'b', 'c', 'd']</tt>.
 *  - <tt>('a'...'d').inject(:+)</tt>:: <tt>['a', 'b', 'c']</tt>.
 *
 *  Examples with first operand (which is <tt>self.first</tt>) of various types:
 *
 *    # Integer.
 *    (1..4).inject(:+)                # => 10
 *    # Float.
 *    [1.0, 2, 3, 4].inject(:+)        # => 10.0
 *    # Character.
 *    ('a'..'d').inject(:+)            # => "abcd"
 *    # Complex.
 *    [Complex(1, 2), 3, 4].inject(:+) # => (8+2i)
 *
 *  If argument +initial_operand+ is given,
 *  the operands for +inject+ are that value plus the elements of +self+.
 *  Example calls their operands:
 *
 *  - <tt>(1..4).inject(10, :+)</tt>:: <tt>[10, 1, 2, 3, 4]</tt>.
 *  - <tt>(1...4).inject(10, :+)</tt>:: <tt>[10, 1, 2, 3]</tt>.
 *  - <tt>('a'..'d').inject('e', :+)</tt>:: <tt>['e', 'a', 'b', 'c', 'd']</tt>.
 *  - <tt>('a'...'d').inject('e', :+)</tt>:: <tt>['e', 'a', 'b', 'c']</tt>.
 *
 *  Examples with +initial_operand+ of various types:
 *
 *    # Integer.
 *    (1..4).inject(2, :+)               # => 12
 *    # Float.
 *    (1..4).inject(2.0, :+)             # => 12.0
 *    # String.
 *    ('a'..'d').inject('foo', :+)       # => "fooabcd"
 *    # Array.
 *    %w[a b c].inject(['x'], :push)     # => ["x", "a", "b", "c"]
 *    # Complex.
 *    (1..4).inject(Complex(2, 2), :+)   # => (12+2i)
 *
 *  <b>Combination by Given \Method</b>
 *
 *  If the method-name argument +symbol+ is given,
 *  the operands are combined by that method:
 *
 *  - The first and second operands are combined.
 *  - That result is combined with the third operand.
 *  - That result is combined with the fourth operand.
 *  - And so on.
 *
 *  The return value from +inject+ is the result of the last combination.
 *
 *  This call to +inject+ computes the sum of the operands:
 *
 *    (1..4).inject(:+) # => 10
 *
 *  Examples with various methods:
 *
 *    # Integer addition.
 *    (1..4).inject(:+)                # => 10
 *    # Integer multiplication.
 *    (1..4).inject(:*)                # => 24
 *    # Character range concatenation.
 *    ('a'..'d').inject('', :+)        # => "abcd"
 *    # String array concatenation.
 *    %w[foo bar baz].inject('', :+)   # => "foobarbaz"
 *    # Hash update.
 *    h = [{foo: 0, bar: 1}, {baz: 2}, {bat: 3}].inject(:update)
 *    h # => {:foo=>0, :bar=>1, :baz=>2, :bat=>3}
 *    # Hash conversion to nested arrays.
 *    h = {foo: 0, bar: 1}.inject([], :push)
 *    h # => [[:foo, 0], [:bar, 1]]
 *
 *  <b>Combination by Given Block</b>
 *
 *  If a block is given, the operands are passed to the block:
 *
 *  - The first call passes the first and second operands.
 *  - The second call passes the result of the first call,
 *    along with the third operand.
 *  - The third call passes the result of the second call,
 *    along with the fourth operand.
 *  - And so on.
 *
 *  The return value from +inject+ is the return value from the last block call.
 *
 *  This call to +inject+ gives a block
 *  that writes the memo and element, and also sums the elements:
 *
 *    (1..4).inject do |memo, element|
 *      p "Memo: #{memo}; element: #{element}"
 *      memo + element
 *    end # => 10
 *
 *  Output:
 *
 *    "Memo: 1; element: 2"
 *    "Memo: 3; element: 3"
 *    "Memo: 6; element: 4"
 *
 *
 */
static VALUE
enum_inject(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;
    VALUE init, op;
    rb_block_call_func *iter = inject_i;
    ID id;
    int num_args;

    if (rb_block_given_p()) {
        num_args = rb_scan_args(argc, argv, "02", &init, &op);
    }
    else {
        num_args = rb_scan_args(argc, argv, "11", &init, &op);
    }

    switch (num_args) {
      case 0:
        init = Qundef;
        break;
      case 1:
        if (rb_block_given_p()) {
            break;
        }
        id = rb_check_id(&init);
        op = id ? ID2SYM(id) : init;
        init = Qundef;
        iter = inject_op_i;
        break;
      case 2:
        if (rb_block_given_p()) {
            rb_warning("given block not used");
        }
        id = rb_check_id(&op);
        if (id) op = ID2SYM(id);
        iter = inject_op_i;
        break;
    }

    if (iter == inject_op_i &&
        SYMBOL_P(op) &&
        RB_TYPE_P(obj, T_ARRAY) &&
        rb_method_basic_definition_p(CLASS_OF(obj), id_each)) {
        return ary_inject_op(obj, init, op);
    }

    memo = MEMO_NEW(init, Qnil, op);
    rb_block_call(obj, id_each, 0, 0, iter, (VALUE)memo);
    if (UNDEF_P(memo->v1)) return Qnil;
    return memo->v1;
}

static VALUE
partition_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, arys))
{
    struct MEMO *memo = MEMO_CAST(arys);
    VALUE ary;
    ENUM_WANT_SVALUE();

    if (RTEST(enum_yield(argc, i))) {
        ary = memo->v1;
    }
    else {
        ary = memo->v2;
    }
    rb_ary_push(ary, i);
    return Qnil;
}

/*
 *  call-seq:
 *    partition {|element| ... } -> [true_array, false_array]
 *    partition -> enumerator
 *
 *  With a block given, returns an array of two arrays:
 *
 *  - The first having those elements for which the block returns a truthy value.
 *  - The other having all other elements.
 *
 *  Examples:
 *
 *    p = (1..4).partition {|i| i.even? }
 *    p # => [[2, 4], [1, 3]]
 *    p = ('a'..'d').partition {|c| c < 'c' }
 *    p # => [["a", "b"], ["c", "d"]]
 *    h = {foo: 0, bar: 1, baz: 2, bat: 3}
 *    p = h.partition {|key, value| key.start_with?('b') }
 *    p # => [[[:bar, 1], [:baz, 2], [:bat, 3]], [[:foo, 0]]]
 *    p = h.partition {|key, value| value < 2 }
 *    p # => [[[:foo, 0], [:bar, 1]], [[:baz, 2], [:bat, 3]]]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: Enumerable#group_by.
 *
 */

static VALUE
enum_partition(VALUE obj)
{
    struct MEMO *memo;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    memo = MEMO_NEW(rb_ary_new(), rb_ary_new(), 0);
    rb_block_call(obj, id_each, 0, 0, partition_i, (VALUE)memo);

    return rb_assoc_new(memo->v1, memo->v2);
}

static VALUE
group_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    VALUE group;
    VALUE values;

    ENUM_WANT_SVALUE();

    group = enum_yield(argc, i);
    values = rb_hash_aref(hash, group);
    if (!RB_TYPE_P(values, T_ARRAY)) {
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
 *    group_by {|element| ... } -> hash
 *    group_by                  -> enumerator
 *
 *  With a block given returns a hash:
 *
 *  - Each key is a return value from the block.
 *  - Each value is an array of those elements for which the block returned that key.
 *
 *  Examples:
 *
 *    g = (1..6).group_by {|i| i%3 }
 *    g # => {1=>[1, 4], 2=>[2, 5], 0=>[3, 6]}
 *    h = {foo: 0, bar: 1, baz: 0, bat: 1}
 *    g = h.group_by {|key, value| value }
 *    g # => {0=>[[:foo, 0], [:baz, 0]], 1=>[[:bar, 1], [:bat, 1]]}
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_group_by(VALUE obj)
{
    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    return enum_hashify(obj, 0, 0, group_by_i);
}

static int
tally_up(st_data_t *group, st_data_t *value, st_data_t arg, int existing)
{
    VALUE tally = (VALUE)*value;
    VALUE hash = (VALUE)arg;
    if (!existing) {
        tally = INT2FIX(1);
    }
    else if (FIXNUM_P(tally) && tally < INT2FIX(FIXNUM_MAX)) {
        tally += INT2FIX(1) & ~FIXNUM_FLAG;
    }
    else {
        Check_Type(tally, T_BIGNUM);
        tally = rb_big_plus(tally, INT2FIX(1));
        RB_OBJ_WRITTEN(hash, Qundef, tally);
    }
    *value = (st_data_t)tally;
    if (!SPECIAL_CONST_P(*group)) RB_OBJ_WRITTEN(hash, Qundef, *group);
    return ST_CONTINUE;
}

static VALUE
rb_enum_tally_up(VALUE hash, VALUE group)
{
    rb_hash_stlike_update(hash, group, tally_up, (st_data_t)hash);
    return hash;
}

static VALUE
tally_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    ENUM_WANT_SVALUE();
    rb_enum_tally_up(hash, i);
    return Qnil;
}

/*
 *  call-seq:
 *    tally -> new_hash
 *    tally(hash) -> hash
 *
 *  Returns a hash containing the counts of equal elements:
 *
 *  - Each key is an element of +self+.
 *  - Each value is the number elements equal to that key.
 *
 *  With no argument:
 *
 *    %w[a b c b c a c b].tally # => {"a"=>2, "b"=>3, "c"=>3}
 *
 *  With a hash argument, that hash is used for the tally (instead of a new hash),
 *  and is returned;
 *  this may be useful for accumulating tallies across multiple enumerables:
 *
 *    hash = {}
 *    hash = %w[a c d b c a].tally(hash)
 *    hash # => {"a"=>2, "c"=>2, "d"=>1, "b"=>1}
 *    hash = %w[b a z].tally(hash)
 *    hash # => {"a"=>3, "c"=>2, "d"=>1, "b"=>2, "z"=>1}
 *    hash = %w[b a m].tally(hash)
 *    hash # => {"a"=>4, "c"=>2, "d"=>1, "b"=>3, "z"=>1, "m"=> 1}
 *
 */

static VALUE
enum_tally(int argc, VALUE *argv, VALUE obj)
{
    VALUE hash;
    if (rb_check_arity(argc, 0, 1)) {
        hash = rb_to_hash_type(argv[0]);
        rb_check_frozen(hash);
    }
    else {
        hash = rb_hash_new();
    }

    return enum_hashify_into(obj, 0, 0, tally_i, hash);
}

NORETURN(static VALUE first_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, params)));
static VALUE
first_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, params))
{
    struct MEMO *memo = MEMO_CAST(params);
    ENUM_WANT_SVALUE();

    MEMO_V1_SET(memo, i);
    rb_iter_break();

    UNREACHABLE_RETURN(Qnil);
}

static VALUE enum_take(VALUE obj, VALUE n);

/*
 *  call-seq:
 *    first    -> element or nil
 *    first(n) -> array
 *
 *  Returns the first element or elements.
 *
 *  With no argument, returns the first element, or +nil+ if there is none:
 *
 *    (1..4).first                   # => 1
 *    %w[a b c].first                # => "a"
 *    {foo: 1, bar: 1, baz: 2}.first # => [:foo, 1]
 *    [].first                       # => nil
 *
 *  With integer argument +n+, returns an array
 *  containing the first +n+ elements that exist:
 *
 *    (1..4).first(2)                   # => [1, 2]
 *    %w[a b c d].first(3)              # => ["a", "b", "c"]
 *    %w[a b c d].first(50)             # => ["a", "b", "c", "d"]
 *    {foo: 1, bar: 1, baz: 2}.first(2) # => [[:foo, 1], [:bar, 1]]
 *    [].first(2)                       # => []
 *
 */

static VALUE
enum_first(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;
    rb_check_arity(argc, 0, 1);
    if (argc > 0) {
        return enum_take(obj, argv[0]);
    }
    else {
        memo = MEMO_NEW(Qnil, 0, 0);
        rb_block_call(obj, id_each, 0, 0, first_i, (VALUE)memo);
        return memo->v1;
    }
}

/*
 *  call-seq:
 *    sort               -> array
 *    sort {|a, b| ... } -> array
 *
 *  Returns an array containing the sorted elements of +self+.
 *  The ordering of equal elements is indeterminate and may be unstable.
 *
 *  With no block given, the sort compares
 *  using the elements' own method <tt><=></tt>:
 *
 *    %w[b c a d].sort              # => ["a", "b", "c", "d"]
 *    {foo: 0, bar: 1, baz: 2}.sort # => [[:bar, 1], [:baz, 2], [:foo, 0]]
 *
 *  With a block given, comparisons in the block determine the ordering.
 *  The block is called with two elements +a+ and +b+, and must return:
 *
 *  - A negative integer if <tt>a < b</tt>.
 *  - Zero if <tt>a == b</tt>.
 *  - A positive integer if <tt>a > b</tt>.
 *
 *  Examples:
 *
 *     a = %w[b c a d]
 *     a.sort {|a, b| b <=> a } # => ["d", "c", "b", "a"]
 *     h = {foo: 0, bar: 1, baz: 2}
 *     h.sort {|a, b| b <=> a } # => [[:foo, 0], [:baz, 2], [:bar, 1]]
 *
 *  See also #sort_by. It implements a Schwartzian transform
 *  which is useful when key computation or comparison is expensive.
 */

static VALUE
enum_sort(VALUE obj)
{
    return rb_ary_sort_bang(enum_to_a(0, 0, obj));
}

#define SORT_BY_BUFSIZE 16
#define SORT_BY_UNIFORMED(num, flo, fix) (((num&1)<<2)|((flo&1)<<1)|fix)
struct sort_by_data {
    const VALUE ary;
    const VALUE buf;
    uint8_t n;
    uint8_t primitive_uniformed;
};

static VALUE
sort_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, _data))
{
    struct sort_by_data *data = (struct sort_by_data *)&MEMO_CAST(_data)->v1;
    VALUE ary = data->ary;
    VALUE v;

    ENUM_WANT_SVALUE();

    v = enum_yield(argc, i);

    if (RBASIC(ary)->klass) {
        rb_raise(rb_eRuntimeError, "sort_by reentered");
    }
    if (RARRAY_LEN(data->buf) != SORT_BY_BUFSIZE*2) {
        rb_raise(rb_eRuntimeError, "sort_by reentered");
    }

    if (data->primitive_uniformed) {
        data->primitive_uniformed &= SORT_BY_UNIFORMED((FIXNUM_P(v)) || (RB_FLOAT_TYPE_P(v)),
                                                        RB_FLOAT_TYPE_P(v),
                                                        FIXNUM_P(v));
    }
    RARRAY_ASET(data->buf, data->n*2, v);
    RARRAY_ASET(data->buf, data->n*2+1, i);
    data->n++;
    if (data->n == SORT_BY_BUFSIZE) {
        rb_ary_concat(ary, data->buf);
        data->n = 0;
    }
    return Qnil;
}

static int
sort_by_cmp(const void *ap, const void *bp, void *data)
{
    VALUE a;
    VALUE b;
    VALUE ary = (VALUE)data;

    if (RBASIC(ary)->klass) {
        rb_raise(rb_eRuntimeError, "sort_by reentered");
    }

    a = *(VALUE *)ap;
    b = *(VALUE *)bp;

    return OPTIMIZED_CMP(a, b);
}


/*
    This is parts of uniform sort
*/

#define uless rb_uniform_is_less
#define UNIFORM_SWAP(a,b)\
    do{struct rb_uniform_sort_data tmp = a; a = b; b = tmp;}  while(0)

struct rb_uniform_sort_data {
    VALUE v;
    VALUE i;
};

static inline bool
rb_uniform_is_less(VALUE a, VALUE b)
{

    if (FIXNUM_P(a) && FIXNUM_P(b)) {
        return (SIGNED_VALUE)a < (SIGNED_VALUE)b;
    }
    else if (FIXNUM_P(a)) {
        RUBY_ASSERT(RB_FLOAT_TYPE_P(b));
        return rb_float_cmp(b, a) > 0;
    }
    else {
        RUBY_ASSERT(RB_FLOAT_TYPE_P(a));
        return rb_float_cmp(a, b) < 0;
    }
}

static inline bool
rb_uniform_is_larger(VALUE a, VALUE b)
{

    if (FIXNUM_P(a) && FIXNUM_P(b)) {
        return (SIGNED_VALUE)a > (SIGNED_VALUE)b;
    }
    else if (FIXNUM_P(a)) {
        RUBY_ASSERT(RB_FLOAT_TYPE_P(b));
        return rb_float_cmp(b, a) < 0;
    }
    else {
        RUBY_ASSERT(RB_FLOAT_TYPE_P(a));
        return rb_float_cmp(a, b) > 0;
    }
}

#define med3_val(a,b,c) (uless(a,b)?(uless(b,c)?b:uless(c,a)?a:c):(uless(c,b)?b:uless(a,c)?a:c))

static void
rb_uniform_insertionsort_2(struct rb_uniform_sort_data* ptr_begin,
                           struct rb_uniform_sort_data* ptr_end)
{
    if ((ptr_end - ptr_begin) < 2) return;
    struct rb_uniform_sort_data tmp, *j, *k,
                                *index = ptr_begin+1;
    for (; index < ptr_end; index++) {
        tmp = *index;
        j = k = index;
        if (uless(tmp.v, ptr_begin->v)) {
            while (ptr_begin < j) {
                *j = *(--k);
                j = k;
            }
        }
        else {
            while (uless(tmp.v, (--k)->v)) {
                *j = *k;
                j = k;
            }
        }
        *j = tmp;
    }
}

static inline void
rb_uniform_heap_down_2(struct rb_uniform_sort_data* ptr_begin,
                       size_t offset, size_t len)
{
    size_t c;
    struct rb_uniform_sort_data tmp = ptr_begin[offset];
    while ((c = (offset<<1)+1) <= len) {
        if (c < len && uless(ptr_begin[c].v, ptr_begin[c+1].v)) {
            c++;
        }
        if (!uless(tmp.v, ptr_begin[c].v)) break;
        ptr_begin[offset] = ptr_begin[c];
        offset = c;
    }
    ptr_begin[offset] = tmp;
}

static void
rb_uniform_heapsort_2(struct rb_uniform_sort_data* ptr_begin,
                      struct rb_uniform_sort_data* ptr_end)
{
    size_t n = ptr_end - ptr_begin;
    if (n < 2) return;

    for (size_t offset = n>>1; offset > 0;) {
        rb_uniform_heap_down_2(ptr_begin, --offset, n-1);
    }
    for (size_t offset = n-1; offset > 0;) {
        UNIFORM_SWAP(*ptr_begin, ptr_begin[offset]);
        rb_uniform_heap_down_2(ptr_begin, 0, --offset);
    }
}


static void
rb_uniform_quicksort_intro_2(struct rb_uniform_sort_data* ptr_begin,
                             struct rb_uniform_sort_data* ptr_end, size_t d)
{

    if (ptr_end - ptr_begin <= 16) {
        rb_uniform_insertionsort_2(ptr_begin, ptr_end);
        return;
    }
    if (d == 0) {
        rb_uniform_heapsort_2(ptr_begin, ptr_end);
        return;
    }

    VALUE x = med3_val(ptr_begin->v,
                       ptr_begin[(ptr_end - ptr_begin)>>1].v,
                       ptr_end[-1].v);
    struct rb_uniform_sort_data *i = ptr_begin;
    struct rb_uniform_sort_data *j = ptr_end-1;

    do {
        while (uless(i->v, x)) i++;
        while (uless(x, j->v)) j--;
        if (i <= j) {
            UNIFORM_SWAP(*i, *j);
            i++;
            j--;
        }
    } while (i <= j);
    j++;
    if (ptr_end - j > 1)   rb_uniform_quicksort_intro_2(j, ptr_end, d-1);
    if (i - ptr_begin > 1) rb_uniform_quicksort_intro_2(ptr_begin, i, d-1);
}

/**
 * Direct primitive data compare sort. Implement with intro sort.
 * @param[in]     ptr_begin  The begin address of target rb_ary's raw pointer.
 * @param[in]     ptr_end    The end address of target rb_ary's raw pointer.
**/
static void
rb_uniform_intro_sort_2(struct rb_uniform_sort_data* ptr_begin,
                        struct rb_uniform_sort_data* ptr_end)
{
    size_t n = ptr_end - ptr_begin;
    size_t d = CHAR_BIT * sizeof(n) - nlz_intptr(n) - 1;
    bool sorted_flag = true;

    for (struct rb_uniform_sort_data* ptr = ptr_begin+1; ptr < ptr_end; ptr++) {
        if (rb_uniform_is_larger((ptr-1)->v, (ptr)->v)) {
            sorted_flag = false;
            break;
        }
    }

    if (sorted_flag) {
        return;
    }
    rb_uniform_quicksort_intro_2(ptr_begin, ptr_end, d<<1);
}

#undef uless


/*
 *  call-seq:
 *    sort_by {|element| ... } -> array
 *    sort_by                  -> enumerator
 *
 *  With a block given, returns an array of elements of +self+,
 *  sorted according to the value returned by the block for each element.
 *  The ordering of equal elements is indeterminate and may be unstable.
 *
 *  Examples:
 *
 *    a = %w[xx xxx x xxxx]
 *    a.sort_by {|s| s.size }        # => ["x", "xx", "xxx", "xxxx"]
 *    a.sort_by {|s| -s.size }       # => ["xxxx", "xxx", "xx", "x"]
 *    h = {foo: 2, bar: 1, baz: 0}
 *    h.sort_by{|key, value| value } # => [[:baz, 0], [:bar, 1], [:foo, 2]]
 *    h.sort_by{|key, value| key }   # => [[:bar, 1], [:baz, 0], [:foo, 2]]
 *
 *  With no block given, returns an Enumerator.
 *
 *  The current implementation of #sort_by generates an array of
 *  tuples containing the original collection element and the mapped
 *  value. This makes #sort_by fairly expensive when the keysets are
 *  simple.
 *
 *     require 'benchmark'
 *
 *     a = (1..100000).map { rand(100000) }
 *
 *     Benchmark.bm(10) do |b|
 *       b.report("Sort")    { a.sort }
 *       b.report("Sort by") { a.sort_by { |a| a } }
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
 *  using the basic #sort method.
 *
 *     files = Dir["*"]
 *     sorted = files.sort { |a, b| File.new(a).mtime <=> File.new(b).mtime }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This sort is inefficient: it generates two new File
 *  objects during every comparison. A slightly better technique is to
 *  use the Kernel#test method to generate the modification
 *  times directly.
 *
 *     files = Dir["*"]
 *     sorted = files.sort { |a, b|
 *       test(?M, a) <=> test(?M, b)
 *     }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This still generates many unnecessary Time objects. A more
 *  efficient technique is to cache the sort keys (modification times
 *  in this case) before the sort. Perl users often call this approach
 *  a Schwartzian transform, after Randal Schwartz. We construct a
 *  temporary array, where each element is an array containing our
 *  sort key along with the filename. We sort this array, and then
 *  extract the filename from the result.
 *
 *     sorted = Dir["*"].collect { |f|
 *        [test(?M, f), f]
 *     }.sort.collect { |f| f[1] }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  This is exactly what #sort_by does internally.
 *
 *     sorted = Dir["*"].sort_by { |f| test(?M, f) }
 *     sorted   #=> ["mon", "tues", "wed", "thurs"]
 *
 *  To produce the reverse of a specific order, the following can be used:
 *
 *    ary.sort_by { ... }.reverse!
 */

static VALUE
enum_sort_by(VALUE obj)
{
    VALUE ary, buf;
    struct MEMO *memo;
    long i;
    struct sort_by_data *data;

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    if (RB_TYPE_P(obj, T_ARRAY) && RARRAY_LEN(obj) <= LONG_MAX/2) {
        ary = rb_ary_new2(RARRAY_LEN(obj)*2);
    }
    else {
        ary = rb_ary_new();
    }
    RBASIC_CLEAR_CLASS(ary);
    buf = rb_ary_hidden_new(SORT_BY_BUFSIZE*2);
    rb_ary_store(buf, SORT_BY_BUFSIZE*2-1, Qnil);
    memo = MEMO_NEW(0, 0, 0);
    data = (struct sort_by_data *)&memo->v1;
    RB_OBJ_WRITE(memo, &data->ary, ary);
    RB_OBJ_WRITE(memo, &data->buf, buf);
    data->n = 0;
    data->primitive_uniformed = SORT_BY_UNIFORMED((CMP_OPTIMIZABLE(FLOAT) && CMP_OPTIMIZABLE(INTEGER)),
                                                  CMP_OPTIMIZABLE(FLOAT),
                                                  CMP_OPTIMIZABLE(INTEGER));
    rb_block_call(obj, id_each, 0, 0, sort_by_i, (VALUE)memo);
    ary = data->ary;
    buf = data->buf;
    if (data->n) {
        rb_ary_resize(buf, data->n*2);
        rb_ary_concat(ary, buf);
    }
    if (RARRAY_LEN(ary) > 2) {
        if (data->primitive_uniformed) {
            RARRAY_PTR_USE(ary, ptr,
                           rb_uniform_intro_sort_2((struct rb_uniform_sort_data*)ptr,
                                                   (struct rb_uniform_sort_data*)(ptr + RARRAY_LEN(ary))));
        }
        else {
            RARRAY_PTR_USE(ary, ptr,
                           ruby_qsort(ptr, RARRAY_LEN(ary)/2, 2*sizeof(VALUE),
                                      sort_by_cmp, (void *)ary));
        }
    }
    if (RBASIC(ary)->klass) {
        rb_raise(rb_eRuntimeError, "sort_by reentered");
    }
    for (i=1; i<RARRAY_LEN(ary); i+=2) {
        RARRAY_ASET(ary, i/2, RARRAY_AREF(ary, i));
    }
    rb_ary_resize(ary, RARRAY_LEN(ary)/2);
    RBASIC_SET_CLASS_RAW(ary, rb_cArray);

    return ary;
}

#define ENUMFUNC(name) argc ? name##_eqq : rb_block_given_p() ? name##_iter_i : name##_i

#define MEMO_ENUM_NEW(v1) (rb_check_arity(argc, 0, 1), MEMO_NEW((v1), (argc ? *argv : 0), 0))

#define DEFINE_ENUMFUNCS(name) \
static VALUE enum_##name##_func(VALUE result, struct MEMO *memo); \
\
static VALUE \
name##_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memo)) \
{ \
    return enum_##name##_func(rb_enum_values_pack(argc, argv), MEMO_CAST(memo)); \
} \
\
static VALUE \
name##_iter_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memo)) \
{ \
    return enum_##name##_func(rb_yield_values2(argc, argv), MEMO_CAST(memo));	\
} \
\
static VALUE \
name##_eqq(RB_BLOCK_CALL_FUNC_ARGLIST(i, memo)) \
{ \
    ENUM_WANT_SVALUE(); \
    return enum_##name##_func(rb_funcallv(MEMO_CAST(memo)->v2, id_eqq, 1, &i), MEMO_CAST(memo)); \
} \
\
static VALUE \
enum_##name##_func(VALUE result, struct MEMO *memo)

#define WARN_UNUSED_BLOCK(argc) do { \
    if ((argc) > 0 && rb_block_given_p()) { \
        rb_warn("given block not used"); \
    } \
} while (0)

DEFINE_ENUMFUNCS(all)
{
    if (!RTEST(result)) {
        MEMO_V1_SET(memo, Qfalse);
        rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *    all?                  -> true or false
 *    all?(pattern)         -> true or false
 *    all? {|element| ... } -> true or false
 *
 *  Returns whether every element meets a given criterion.
 *
 *  If +self+ has no element, returns +true+ and argument or block
 *  are not used.
 *
 *  With no argument and no block,
 *  returns whether every element is truthy:
 *
 *    (1..4).all?           # => true
 *    %w[a b c d].all?      # => true
 *    [1, 2, nil].all?      # => false
 *    ['a','b', false].all? # => false
 *    [].all?               # => true
 *
 *  With argument +pattern+ and no block,
 *  returns whether for each element +element+,
 *  <tt>pattern === element</tt>:
 *
 *    (1..4).all?(Integer)                 # => true
 *    (1..4).all?(Numeric)                 # => true
 *    (1..4).all?(Float)                   # => false
 *    %w[bar baz bat bam].all?(/ba/)       # => true
 *    %w[bar baz bat bam].all?(/bar/)      # => false
 *    %w[bar baz bat bam].all?('ba')       # => false
 *    {foo: 0, bar: 1, baz: 2}.all?(Array) # => true
 *    {foo: 0, bar: 1, baz: 2}.all?(Hash)  # => false
 *    [].all?(Integer)                     # => true
 *
 *  With a block given, returns whether the block returns a truthy value
 *  for every element:
 *
 *    (1..4).all? {|element| element < 5 }                    # => true
 *    (1..4).all? {|element| element < 4 }                    # => false
 *    {foo: 0, bar: 1, baz: 2}.all? {|key, value| value < 3 } # => true
 *    {foo: 0, bar: 1, baz: 2}.all? {|key, value| value < 2 } # => false
 *
 *  Related: #any?, #none? #one?.
 *
 */

static VALUE
enum_all(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo = MEMO_ENUM_NEW(Qtrue);
    WARN_UNUSED_BLOCK(argc);
    rb_block_call(obj, id_each, 0, 0, ENUMFUNC(all), (VALUE)memo);
    return memo->v1;
}

DEFINE_ENUMFUNCS(any)
{
    if (RTEST(result)) {
        MEMO_V1_SET(memo, Qtrue);
        rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *    any?                  -> true or false
 *    any?(pattern)         -> true or false
 *    any? {|element| ... } -> true or false
 *
 *  Returns whether any element meets a given criterion.
 *
 *  If +self+ has no element, returns +false+ and argument or block
 *  are not used.
 *
 *  With no argument and no block,
 *  returns whether any element is truthy:
 *
 *    (1..4).any?          # => true
 *    %w[a b c d].any?     # => true
 *    [1, false, nil].any? # => true
 *    [].any?              # => false
 *
 *  With argument +pattern+ and no block,
 *  returns whether for any element +element+,
 *  <tt>pattern === element</tt>:
 *
 *    [nil, false, 0].any?(Integer)        # => true
 *    [nil, false, 0].any?(Numeric)        # => true
 *    [nil, false, 0].any?(Float)          # => false
 *    %w[bar baz bat bam].any?(/m/)        # => true
 *    %w[bar baz bat bam].any?(/foo/)      # => false
 *    %w[bar baz bat bam].any?('ba')       # => false
 *    {foo: 0, bar: 1, baz: 2}.any?(Array) # => true
 *    {foo: 0, bar: 1, baz: 2}.any?(Hash)  # => false
 *    [].any?(Integer)                     # => false
 *
 *  With a block given, returns whether the block returns a truthy value
 *  for any element:
 *
 *    (1..4).any? {|element| element < 2 }                    # => true
 *    (1..4).any? {|element| element < 1 }                    # => false
 *    {foo: 0, bar: 1, baz: 2}.any? {|key, value| value < 1 } # => true
 *    {foo: 0, bar: 1, baz: 2}.any? {|key, value| value < 0 } # => false
 *
 *  Related: #all?, #none?, #one?.
 */

static VALUE
enum_any(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo = MEMO_ENUM_NEW(Qfalse);
    WARN_UNUSED_BLOCK(argc);
    rb_block_call(obj, id_each, 0, 0, ENUMFUNC(any), (VALUE)memo);
    return memo->v1;
}

DEFINE_ENUMFUNCS(one)
{
    if (RTEST(result)) {
        if (UNDEF_P(memo->v1)) {
            MEMO_V1_SET(memo, Qtrue);
        }
        else if (memo->v1 == Qtrue) {
            MEMO_V1_SET(memo, Qfalse);
            rb_iter_break();
        }
    }
    return Qnil;
}

struct nmin_data {
    long n;
    long bufmax;
    long curlen;
    VALUE buf;
    VALUE limit;
    int (*cmpfunc)(const void *, const void *, void *);
    int rev: 1; /* max if 1 */
    int by: 1; /* min_by if 1 */
};

static VALUE
cmpint_reenter_check(struct nmin_data *data, VALUE val)
{
    if (RBASIC(data->buf)->klass) {
        rb_raise(rb_eRuntimeError, "%s%s reentered",
                 data->rev ? "max" : "min",
                 data->by ? "_by" : "");
    }
    return val;
}

static int
nmin_cmp(const void *ap, const void *bp, void *_data)
{
    struct nmin_data *data = (struct nmin_data *)_data;
    VALUE a = *(const VALUE *)ap, b = *(const VALUE *)bp;
#define rb_cmpint(cmp, a, b) rb_cmpint(cmpint_reenter_check(data, (cmp)), a, b)
    return OPTIMIZED_CMP(a, b);
#undef rb_cmpint
}

static int
nmin_block_cmp(const void *ap, const void *bp, void *_data)
{
    struct nmin_data *data = (struct nmin_data *)_data;
    VALUE a = *(const VALUE *)ap, b = *(const VALUE *)bp;
    VALUE cmp = rb_yield_values(2, a, b);
    cmpint_reenter_check(data, cmp);
    return rb_cmpint(cmp, a, b);
}

static void
nmin_filter(struct nmin_data *data)
{
    long n;
    VALUE *beg;
    int eltsize;
    long numelts;

    long left, right;
    long store_index;

    long i, j;

    if (data->curlen <= data->n)
        return;

    n = data->n;
    beg = RARRAY_PTR(data->buf);
    eltsize = data->by ? 2 : 1;
    numelts = data->curlen;

    left = 0;
    right = numelts-1;

#define GETPTR(i) (beg+(i)*eltsize)

#define SWAP(i, j) do { \
    VALUE tmp[2]; \
    memcpy(tmp, GETPTR(i), sizeof(VALUE)*eltsize); \
    memcpy(GETPTR(i), GETPTR(j), sizeof(VALUE)*eltsize); \
    memcpy(GETPTR(j), tmp, sizeof(VALUE)*eltsize); \
} while (0)

    while (1) {
        long pivot_index = left + (right-left)/2;
        long num_pivots = 1;

        SWAP(pivot_index, right);
        pivot_index = right;

        store_index = left;
        i = left;
        while (i <= right-num_pivots) {
            int c = data->cmpfunc(GETPTR(i), GETPTR(pivot_index), data);
            if (data->rev)
                c = -c;
            if (c == 0) {
                SWAP(i, right-num_pivots);
                num_pivots++;
                continue;
            }
            if (c < 0) {
                SWAP(i, store_index);
                store_index++;
            }
            i++;
        }
        j = store_index;
        for (i = right; right-num_pivots < i; i--) {
            if (i <= j)
                break;
            SWAP(j, i);
            j++;
        }

        if (store_index <= n && n <= store_index+num_pivots)
            break;

        if (n < store_index) {
            right = store_index-1;
        }
        else {
            left = store_index+num_pivots;
        }
    }
#undef GETPTR
#undef SWAP

    data->limit = RARRAY_AREF(data->buf, store_index*eltsize); /* the last pivot */
    data->curlen = data->n;
    rb_ary_resize(data->buf, data->n * eltsize);
}

static VALUE
nmin_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, _data))
{
    struct nmin_data *data = (struct nmin_data *)_data;
    VALUE cmpv;

    ENUM_WANT_SVALUE();

    if (data->by)
        cmpv = enum_yield(argc, i);
    else
        cmpv = i;

    if (!UNDEF_P(data->limit)) {
        int c = data->cmpfunc(&cmpv, &data->limit, data);
        if (data->rev)
            c = -c;
        if (c >= 0)
            return Qnil;
    }

    if (data->by)
        rb_ary_push(data->buf, cmpv);
    rb_ary_push(data->buf, i);

    data->curlen++;

    if (data->curlen == data->bufmax) {
        nmin_filter(data);
    }

    return Qnil;
}

VALUE
rb_nmin_run(VALUE obj, VALUE num, int by, int rev, int ary)
{
    VALUE result;
    struct nmin_data data;

    data.n = NUM2LONG(num);
    if (data.n < 0)
        rb_raise(rb_eArgError, "negative size (%ld)", data.n);
    if (data.n == 0)
        return rb_ary_new2(0);
    if (LONG_MAX/4/(by ? 2 : 1) < data.n)
        rb_raise(rb_eArgError, "too big size");
    data.bufmax = data.n * 4;
    data.curlen = 0;
    data.buf = rb_ary_hidden_new(data.bufmax * (by ? 2 : 1));
    data.limit = Qundef;
    data.cmpfunc = by ? nmin_cmp :
                   rb_block_given_p() ? nmin_block_cmp :
                   nmin_cmp;
    data.rev = rev;
    data.by = by;
    if (ary) {
        long i;
        for (i = 0; i < RARRAY_LEN(obj); i++) {
            VALUE args[1];
            args[0] = RARRAY_AREF(obj, i);
            nmin_i(obj, (VALUE)&data, 1, args, Qundef);
        }
    }
    else {
        rb_block_call(obj, id_each, 0, 0, nmin_i, (VALUE)&data);
    }
    nmin_filter(&data);
    result = data.buf;
    if (by) {
        long i;
        RARRAY_PTR_USE(result, ptr, {
            ruby_qsort(ptr,
                       RARRAY_LEN(result)/2,
                       sizeof(VALUE)*2,
                       data.cmpfunc, (void *)&data);
            for (i=1; i<RARRAY_LEN(result); i+=2) {
                ptr[i/2] = ptr[i];
            }
        });
        rb_ary_resize(result, RARRAY_LEN(result)/2);
    }
    else {
        RARRAY_PTR_USE(result, ptr, {
            ruby_qsort(ptr, RARRAY_LEN(result), sizeof(VALUE),
                       data.cmpfunc, (void *)&data);
        });
    }
    if (rev) {
        rb_ary_reverse(result);
    }
    RBASIC_SET_CLASS(result, rb_cArray);
    return result;

}

/*
 *  call-seq:
 *    one?                  -> true or false
 *    one?(pattern)         -> true or false
 *    one? {|element| ... } -> true or false
 *
 *  Returns whether exactly one element meets a given criterion.
 *
 *  With no argument and no block,
 *  returns whether exactly one element is truthy:
 *
 *    (1..1).one?           # => true
 *    [1, nil, false].one?  # => true
 *    (1..4).one?           # => false
 *    {foo: 0}.one?         # => true
 *    {foo: 0, bar: 1}.one? # => false
 *    [].one?               # => false
 *
 *  With argument +pattern+ and no block,
 *  returns whether for exactly one element +element+,
 *  <tt>pattern === element</tt>:
 *
 *    [nil, false, 0].one?(Integer)        # => true
 *    [nil, false, 0].one?(Numeric)        # => true
 *    [nil, false, 0].one?(Float)          # => false
 *    %w[bar baz bat bam].one?(/m/)        # => true
 *    %w[bar baz bat bam].one?(/foo/)      # => false
 *    %w[bar baz bat bam].one?('ba')       # => false
 *    {foo: 0, bar: 1, baz: 2}.one?(Array) # => false
 *    {foo: 0}.one?(Array)                 # => true
 *    [].one?(Integer)                     # => false
 *
 *  With a block given, returns whether the block returns a truthy value
 *  for exactly one element:
 *
 *    (1..4).one? {|element| element < 2 }                     # => true
 *    (1..4).one? {|element| element < 1 }                     # => false
 *    {foo: 0, bar: 1, baz: 2}.one? {|key, value| value < 1 }  # => true
 *    {foo: 0, bar: 1, baz: 2}.one? {|key, value| value < 2 } # => false
 *
 *  Related: #none?, #all?, #any?.
 *
 */
static VALUE
enum_one(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo = MEMO_ENUM_NEW(Qundef);
    VALUE result;

    WARN_UNUSED_BLOCK(argc);
    rb_block_call(obj, id_each, 0, 0, ENUMFUNC(one), (VALUE)memo);
    result = memo->v1;
    if (UNDEF_P(result)) return Qfalse;
    return result;
}

DEFINE_ENUMFUNCS(none)
{
    if (RTEST(result)) {
        MEMO_V1_SET(memo, Qfalse);
        rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *    none?                  -> true or false
 *    none?(pattern)         -> true or false
 *    none? {|element| ... } -> true or false
 *
 *  Returns whether no element meets a given criterion.
 *
 *  With no argument and no block,
 *  returns whether no element is truthy:
 *
 *    (1..4).none?           # => false
 *    [nil, false].none?     # => true
 *    {foo: 0}.none?         # => false
 *    {foo: 0, bar: 1}.none? # => false
 *    [].none?               # => true
 *
 *  With argument +pattern+ and no block,
 *  returns whether for no element +element+,
 *  <tt>pattern === element</tt>:
 *
 *    [nil, false, 1.1].none?(Integer)      # => true
 *    %w[bar baz bat bam].none?(/m/)        # => false
 *    %w[bar baz bat bam].none?(/foo/)      # => true
 *    %w[bar baz bat bam].none?('ba')       # => true
 *    {foo: 0, bar: 1, baz: 2}.none?(Hash)  # => true
 *    {foo: 0}.none?(Array)                 # => false
 *    [].none?(Integer)                     # => true
 *
 *  With a block given, returns whether the block returns a truthy value
 *  for no element:
 *
 *    (1..4).none? {|element| element < 1 }                     # => true
 *    (1..4).none? {|element| element < 2 }                     # => false
 *    {foo: 0, bar: 1, baz: 2}.none? {|key, value| value < 0 }  # => true
 *    {foo: 0, bar: 1, baz: 2}.none? {|key, value| value < 1 } # => false
 *
 *  Related: #one?, #all?, #any?.
 *
 */
static VALUE
enum_none(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo = MEMO_ENUM_NEW(Qtrue);

    WARN_UNUSED_BLOCK(argc);
    rb_block_call(obj, id_each, 0, 0, ENUMFUNC(none), (VALUE)memo);
    return memo->v1;
}

struct min_t {
    VALUE min;
};

static VALUE
min_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct min_t *memo = MEMO_FOR(struct min_t, args);

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->min)) {
        memo->min = i;
    }
    else {
        if (OPTIMIZED_CMP(i, memo->min) < 0) {
            memo->min = i;
        }
    }
    return Qnil;
}

static VALUE
min_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    VALUE cmp;
    struct min_t *memo = MEMO_FOR(struct min_t, args);

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->min)) {
        memo->min = i;
    }
    else {
        cmp = rb_yield_values(2, i, memo->min);
        if (rb_cmpint(cmp, i, memo->min) < 0) {
            memo->min = i;
        }
    }
    return Qnil;
}


/*
 *  call-seq:
 *    min                  -> element
 *    min(n)               -> array
 *    min {|a, b| ... }    -> element
 *    min(n) {|a, b| ... } -> array
 *
 *  Returns the element with the minimum element according to a given criterion.
 *  The ordering of equal elements is indeterminate and may be unstable.
 *
 *  With no argument and no block, returns the minimum element,
 *  using the elements' own method <tt><=></tt> for comparison:
 *
 *    (1..4).min                   # => 1
 *    (-4..-1).min                 # => -4
 *    %w[d c b a].min              # => "a"
 *    {foo: 0, bar: 1, baz: 2}.min # => [:bar, 1]
 *    [].min                       # => nil
 *
 *  With positive integer argument +n+ given, and no block,
 *  returns an array containing the first +n+ minimum elements that exist:
 *
 *    (1..4).min(2)                   # => [1, 2]
 *    (-4..-1).min(2)                 # => [-4, -3]
 *    %w[d c b a].min(2)              # => ["a", "b"]
 *    {foo: 0, bar: 1, baz: 2}.min(2) # => [[:bar, 1], [:baz, 2]]
 *    [].min(2)                       # => []
 *
 *  With a block given, the block determines the minimum elements.
 *  The block is called with two elements +a+ and +b+, and must return:
 *
 *  - A negative integer if <tt>a < b</tt>.
 *  - Zero if <tt>a == b</tt>.
 *  - A positive integer if <tt>a > b</tt>.
 *
 *  With a block given and no argument,
 *  returns the minimum element as determined by the block:
 *
 *    %w[xxx x xxxx xx].min {|a, b| a.size <=> b.size } # => "x"
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.min {|pair1, pair2| pair1[1] <=> pair2[1] } # => [:foo, 0]
 *    [].min {|a, b| a <=> b }                          # => nil
 *
 *  With a block given and positive integer argument +n+ given,
 *  returns an array containing the first +n+ minimum elements that exist,
 *  as determined by the block.
 *
 *    %w[xxx x xxxx xx].min(2) {|a, b| a.size <=> b.size } # => ["x", "xx"]
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.min(2) {|pair1, pair2| pair1[1] <=> pair2[1] }
 *    # => [[:foo, 0], [:bar, 1]]
 *    [].min(2) {|a, b| a <=> b }                          # => []
 *
 *  Related: #min_by, #minmax, #max.
 *
 */

static VALUE
enum_min(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo;
    struct min_t *m = NEW_MEMO_FOR(struct min_t, memo);
    VALUE result;
    VALUE num;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(obj, num, 0, 0, 0);

    m->min = Qundef;
    if (rb_block_given_p()) {
        rb_block_call(obj, id_each, 0, 0, min_ii, memo);
    }
    else {
        rb_block_call(obj, id_each, 0, 0, min_i, memo);
    }
    result = m->min;
    if (UNDEF_P(result)) return Qnil;
    return result;
}

struct max_t {
    VALUE max;
};

static VALUE
max_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct max_t *memo = MEMO_FOR(struct max_t, args);

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->max)) {
        memo->max = i;
    }
    else {
        if (OPTIMIZED_CMP(i, memo->max) > 0) {
            memo->max = i;
        }
    }
    return Qnil;
}

static VALUE
max_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct max_t *memo = MEMO_FOR(struct max_t, args);
    VALUE cmp;

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->max)) {
        memo->max = i;
    }
    else {
        cmp = rb_yield_values(2, i, memo->max);
        if (rb_cmpint(cmp, i, memo->max) > 0) {
            memo->max = i;
        }
    }
    return Qnil;
}

/*
 *  call-seq:
 *    max                  -> element
 *    max(n)               -> array
 *    max {|a, b| ... }    -> element
 *    max(n) {|a, b| ... } -> array
 *
 *  Returns the element with the maximum element according to a given criterion.
 *  The ordering of equal elements is indeterminate and may be unstable.
 *
 *  With no argument and no block, returns the maximum element,
 *  using the elements' own method <tt><=></tt> for comparison:
 *
 *    (1..4).max                   # => 4
 *    (-4..-1).max                 # => -1
 *    %w[d c b a].max              # => "d"
 *    {foo: 0, bar: 1, baz: 2}.max # => [:foo, 0]
 *    [].max                       # => nil
 *
 *  With positive integer argument +n+ given, and no block,
 *  returns an array containing the first +n+ maximum elements that exist:
 *
 *    (1..4).max(2)                   # => [4, 3]
 *    (-4..-1).max(2)                # => [-1, -2]
 *    %w[d c b a].max(2)              # => ["d", "c"]
 *    {foo: 0, bar: 1, baz: 2}.max(2) # => [[:foo, 0], [:baz, 2]]
 *    [].max(2)                       # => []
 *
 *  With a block given, the block determines the maximum elements.
 *  The block is called with two elements +a+ and +b+, and must return:
 *
 *  - A negative integer if <tt>a < b</tt>.
 *  - Zero if <tt>a == b</tt>.
 *  - A positive integer if <tt>a > b</tt>.
 *
 *  With a block given and no argument,
 *  returns the maximum element as determined by the block:
 *
 *    %w[xxx x xxxx xx].max {|a, b| a.size <=> b.size } # => "xxxx"
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.max {|pair1, pair2| pair1[1] <=> pair2[1] }     # => [:baz, 2]
 *    [].max {|a, b| a <=> b }                          # => nil
 *
 *  With a block given and positive integer argument +n+ given,
 *  returns an array containing the first +n+ maximum elements that exist,
 *  as determined by the block.
 *
 *    %w[xxx x xxxx xx].max(2) {|a, b| a.size <=> b.size } # => ["xxxx", "xxx"]
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.max(2) {|pair1, pair2| pair1[1] <=> pair2[1] }
 *    # => [[:baz, 2], [:bar, 1]]
 *    [].max(2) {|a, b| a <=> b }                          # => []
 *
 *  Related: #min, #minmax, #max_by.
 *
 */

static VALUE
enum_max(int argc, VALUE *argv, VALUE obj)
{
    VALUE memo;
    struct max_t *m = NEW_MEMO_FOR(struct max_t, memo);
    VALUE result;
    VALUE num;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(obj, num, 0, 1, 0);

    m->max = Qundef;
    if (rb_block_given_p()) {
        rb_block_call(obj, id_each, 0, 0, max_ii, (VALUE)memo);
    }
    else {
        rb_block_call(obj, id_each, 0, 0, max_i, (VALUE)memo);
    }
    result = m->max;
    if (UNDEF_P(result)) return Qnil;
    return result;
}

struct minmax_t {
    VALUE min;
    VALUE max;
    VALUE last;
};

static void
minmax_i_update(VALUE i, VALUE j, struct minmax_t *memo)
{
    int n;

    if (UNDEF_P(memo->min)) {
        memo->min = i;
        memo->max = j;
    }
    else {
        n = OPTIMIZED_CMP(i, memo->min);
        if (n < 0) {
            memo->min = i;
        }
        n = OPTIMIZED_CMP(j, memo->max);
        if (n > 0) {
            memo->max = j;
        }
    }
}

static VALUE
minmax_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, _memo))
{
    struct minmax_t *memo = MEMO_FOR(struct minmax_t, _memo);
    int n;
    VALUE j;

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->last)) {
        memo->last = i;
        return Qnil;
    }
    j = memo->last;
    memo->last = Qundef;

    n = OPTIMIZED_CMP(j, i);
    if (n == 0)
        i = j;
    else if (n < 0) {
        VALUE tmp;
        tmp = i;
        i = j;
        j = tmp;
    }

    minmax_i_update(i, j, memo);

    return Qnil;
}

static void
minmax_ii_update(VALUE i, VALUE j, struct minmax_t *memo)
{
    int n;

    if (UNDEF_P(memo->min)) {
        memo->min = i;
        memo->max = j;
    }
    else {
        n = rb_cmpint(rb_yield_values(2, i, memo->min), i, memo->min);
        if (n < 0) {
            memo->min = i;
        }
        n = rb_cmpint(rb_yield_values(2, j, memo->max), j, memo->max);
        if (n > 0) {
            memo->max = j;
        }
    }
}

static VALUE
minmax_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, _memo))
{
    struct minmax_t *memo = MEMO_FOR(struct minmax_t, _memo);
    int n;
    VALUE j;

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->last)) {
        memo->last = i;
        return Qnil;
    }
    j = memo->last;
    memo->last = Qundef;

    n = rb_cmpint(rb_yield_values(2, j, i), j, i);
    if (n == 0)
        i = j;
    else if (n < 0) {
        VALUE tmp;
        tmp = i;
        i = j;
        j = tmp;
    }

    minmax_ii_update(i, j, memo);

    return Qnil;
}

/*
 *  call-seq:
 *    minmax               -> [minimum, maximum]
 *    minmax {|a, b| ... } -> [minimum, maximum]
 *
 *  Returns a 2-element array containing the minimum and maximum elements
 *  according to a given criterion.
 *  The ordering of equal elements is indeterminate and may be unstable.
 *
 *  With no argument and no block, returns the minimum and maximum elements,
 *  using the elements' own method <tt><=></tt> for comparison:
 *
 *    (1..4).minmax                   # => [1, 4]
 *    (-4..-1).minmax                 # => [-4, -1]
 *    %w[d c b a].minmax              # => ["a", "d"]
 *    {foo: 0, bar: 1, baz: 2}.minmax # => [[:bar, 1], [:foo, 0]]
 *    [].minmax                       # => [nil, nil]
 *
 *  With a block given, returns the minimum and maximum elements
 *  as determined by the block:
 *
 *    %w[xxx x xxxx xx].minmax {|a, b| a.size <=> b.size } # => ["x", "xxxx"]
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.minmax {|pair1, pair2| pair1[1] <=> pair2[1] }
 *    # => [[:foo, 0], [:baz, 2]]
 *    [].minmax {|a, b| a <=> b }                          # => [nil, nil]
 *
 *  Related: #min, #max, #minmax_by.
 *
 */

static VALUE
enum_minmax(VALUE obj)
{
    VALUE memo;
    struct minmax_t *m = NEW_MEMO_FOR(struct minmax_t, memo);

    m->min = Qundef;
    m->last = Qundef;
    if (rb_block_given_p()) {
        rb_block_call(obj, id_each, 0, 0, minmax_ii, memo);
        if (!UNDEF_P(m->last))
            minmax_ii_update(m->last, m->last, m);
    }
    else {
        rb_block_call(obj, id_each, 0, 0, minmax_i, memo);
        if (!UNDEF_P(m->last))
            minmax_i_update(m->last, m->last, m);
    }
    if (!UNDEF_P(m->min)) {
        return rb_assoc_new(m->min, m->max);
    }
    return rb_assoc_new(Qnil, Qnil);
}

static VALUE
min_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    VALUE v;

    ENUM_WANT_SVALUE();

    v = enum_yield(argc, i);
    if (UNDEF_P(memo->v1)) {
        MEMO_V1_SET(memo, v);
        MEMO_V2_SET(memo, i);
    }
    else if (OPTIMIZED_CMP(v, memo->v1) < 0) {
        MEMO_V1_SET(memo, v);
        MEMO_V2_SET(memo, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    min_by {|element| ... }    -> element
 *    min_by(n) {|element| ... } -> array
 *    min_by                     -> enumerator
 *    min_by(n)                  -> enumerator
 *
 *  Returns the elements for which the block returns the minimum values.
 *
 *  With a block given and no argument,
 *  returns the element for which the block returns the minimum value:
 *
 *    (1..4).min_by {|element| -element }                    # => 4
 *    %w[a b c d].min_by {|element| -element.ord }           # => "d"
 *    {foo: 0, bar: 1, baz: 2}.min_by {|key, value| -value } # => [:baz, 2]
 *    [].min_by {|element| -element }                        # => nil
 *
 *  With a block given and positive integer argument +n+ given,
 *  returns an array containing the +n+ elements
 *  for which the block returns minimum values:
 *
 *    (1..4).min_by(2) {|element| -element }
 *    # => [4, 3]
 *    %w[a b c d].min_by(2) {|element| -element.ord }
 *    # => ["d", "c"]
 *    {foo: 0, bar: 1, baz: 2}.min_by(2) {|key, value| -value }
 *    # => [[:baz, 2], [:bar, 1]]
 *    [].min_by(2) {|element| -element }
 *    # => []
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #min, #minmax, #max_by.
 *
 */

static VALUE
enum_min_by(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;
    VALUE num;

    rb_check_arity(argc, 0, 1);

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_size);

    if (argc && !NIL_P(num = argv[0]))
        return rb_nmin_run(obj, num, 1, 0, 0);

    memo = MEMO_NEW(Qundef, Qnil, 0);
    rb_block_call(obj, id_each, 0, 0, min_by_i, (VALUE)memo);
    return memo->v2;
}

static VALUE
max_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    VALUE v;

    ENUM_WANT_SVALUE();

    v = enum_yield(argc, i);
    if (UNDEF_P(memo->v1)) {
        MEMO_V1_SET(memo, v);
        MEMO_V2_SET(memo, i);
    }
    else if (OPTIMIZED_CMP(v, memo->v1) > 0) {
        MEMO_V1_SET(memo, v);
        MEMO_V2_SET(memo, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    max_by {|element| ... }    -> element
 *    max_by(n) {|element| ... } -> array
 *    max_by                     -> enumerator
 *    max_by(n)                  -> enumerator
 *
 *  Returns the elements for which the block returns the maximum values.
 *
 *  With a block given and no argument,
 *  returns the element for which the block returns the maximum value:
 *
 *    (1..4).max_by {|element| -element }                    # => 1
 *    %w[a b c d].max_by {|element| -element.ord }           # => "a"
 *    {foo: 0, bar: 1, baz: 2}.max_by {|key, value| -value } # => [:foo, 0]
 *    [].max_by {|element| -element }                        # => nil
 *
 *  With a block given and positive integer argument +n+ given,
 *  returns an array containing the +n+ elements
 *  for which the block returns maximum values:
 *
 *    (1..4).max_by(2) {|element| -element }
 *    # => [1, 2]
 *    %w[a b c d].max_by(2) {|element| -element.ord }
 *    # => ["a", "b"]
 *    {foo: 0, bar: 1, baz: 2}.max_by(2) {|key, value| -value }
 *    # => [[:foo, 0], [:bar, 1]]
 *    [].max_by(2) {|element| -element }
 *    # => []
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #max, #minmax, #min_by.
 *
 */

static VALUE
enum_max_by(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;
    VALUE num;

    rb_check_arity(argc, 0, 1);

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_size);

    if (argc && !NIL_P(num = argv[0]))
        return rb_nmin_run(obj, num, 1, 1, 0);

    memo = MEMO_NEW(Qundef, Qnil, 0);
    rb_block_call(obj, id_each, 0, 0, max_by_i, (VALUE)memo);
    return memo->v2;
}

struct minmax_by_t {
    VALUE min_bv;
    VALUE max_bv;
    VALUE min;
    VALUE max;
    VALUE last_bv;
    VALUE last;
};

static void
minmax_by_i_update(VALUE v1, VALUE v2, VALUE i1, VALUE i2, struct minmax_by_t *memo)
{
    if (UNDEF_P(memo->min_bv)) {
        memo->min_bv = v1;
        memo->max_bv = v2;
        memo->min = i1;
        memo->max = i2;
    }
    else {
        if (OPTIMIZED_CMP(v1, memo->min_bv) < 0) {
            memo->min_bv = v1;
            memo->min = i1;
        }
        if (OPTIMIZED_CMP(v2, memo->max_bv) > 0) {
            memo->max_bv = v2;
            memo->max = i2;
        }
    }
}

static VALUE
minmax_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, _memo))
{
    struct minmax_by_t *memo = MEMO_FOR(struct minmax_by_t, _memo);
    VALUE vi, vj, j;
    int n;

    ENUM_WANT_SVALUE();

    vi = enum_yield(argc, i);

    if (UNDEF_P(memo->last_bv)) {
        memo->last_bv = vi;
        memo->last = i;
        return Qnil;
    }
    vj = memo->last_bv;
    j = memo->last;
    memo->last_bv = Qundef;

    n = OPTIMIZED_CMP(vj, vi);
    if (n == 0) {
        i = j;
        vi = vj;
    }
    else if (n < 0) {
        VALUE tmp;
        tmp = i;
        i = j;
        j = tmp;
        tmp = vi;
        vi = vj;
        vj = tmp;
    }

    minmax_by_i_update(vi, vj, i, j, memo);

    return Qnil;
}

/*
 *  call-seq:
 *    minmax_by {|element| ... } -> [minimum, maximum]
 *    minmax_by                  -> enumerator
 *
 *  Returns a 2-element array containing the elements
 *  for which the block returns minimum and maximum values:
 *
 *    (1..4).minmax_by {|element| -element }
 *    # => [4, 1]
 *    %w[a b c d].minmax_by {|element| -element.ord }
 *    # => ["d", "a"]
 *    {foo: 0, bar: 1, baz: 2}.minmax_by {|key, value| -value }
 *    # => [[:baz, 2], [:foo, 0]]
 *    [].minmax_by {|element| -element }
 *    # => [nil, nil]
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #max_by, #minmax, #min_by.
 *
 */

static VALUE
enum_minmax_by(VALUE obj)
{
    VALUE memo;
    struct minmax_by_t *m = NEW_MEMO_FOR(struct minmax_by_t, memo);

    RETURN_SIZED_ENUMERATOR(obj, 0, 0, enum_size);

    m->min_bv = Qundef;
    m->max_bv = Qundef;
    m->min = Qnil;
    m->max = Qnil;
    m->last_bv = Qundef;
    m->last = Qundef;
    rb_block_call(obj, id_each, 0, 0, minmax_by_i, memo);
    if (!UNDEF_P(m->last_bv))
        minmax_by_i_update(m->last_bv, m->last_bv, m->last, m->last, m);
    m = MEMO_FOR(struct minmax_by_t, memo);
    return rb_assoc_new(m->min, m->max);
}

static VALUE
member_i(RB_BLOCK_CALL_FUNC_ARGLIST(iter, args))
{
    struct MEMO *memo = MEMO_CAST(args);

    if (rb_equal(rb_enum_values_pack(argc, argv), memo->v1)) {
        MEMO_V2_SET(memo, Qtrue);
        rb_iter_break();
    }
    return Qnil;
}

/*
 *  call-seq:
 *    include?(object) -> true or false
 *
 *  Returns whether for any element <tt>object == element</tt>:
 *
 *    (1..4).include?(2)                       # => true
 *    (1..4).include?(5)                       # => false
 *    (1..4).include?('2')                     # => false
 *    %w[a b c d].include?('b')                # => true
 *    %w[a b c d].include?('2')                # => false
 *    {foo: 0, bar: 1, baz: 2}.include?(:foo)  # => true
 *    {foo: 0, bar: 1, baz: 2}.include?('foo') # => false
 *    {foo: 0, bar: 1, baz: 2}.include?(0)     # => false
 *
 */

static VALUE
enum_member(VALUE obj, VALUE val)
{
    struct MEMO *memo = MEMO_NEW(val, Qfalse, 0);

    rb_block_call(obj, id_each, 0, 0, member_i, (VALUE)memo);
    return memo->v2;
}

static VALUE
each_with_index_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memo))
{
    struct MEMO *m = MEMO_CAST(memo);
    VALUE n = imemo_count_value(m);

    imemo_count_up(m);
    return rb_yield_values(2, rb_enum_values_pack(argc, argv), n);
}

/*
 *  call-seq:
 *    each_with_index(*args) {|element, i| ..... } -> self
 *    each_with_index(*args)                       -> enumerator
 *
 *  With a block given, calls the block with each element and its index;
 *  returns +self+:
 *
 *    h = {}
 *    (1..4).each_with_index {|element, i| h[element] = i } # => 1..4
 *    h # => {1=>0, 2=>1, 3=>2, 4=>3}
 *
 *    h = {}
 *    %w[a b c d].each_with_index {|element, i| h[element] = i }
 *    # => ["a", "b", "c", "d"]
 *    h # => {"a"=>0, "b"=>1, "c"=>2, "d"=>3}
 *
 *    a = []
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_with_index {|element, i| a.push([i, element]) }
 *    # => {:foo=>0, :bar=>1, :baz=>2}
 *    a # => [[0, [:foo, 0]], [1, [:bar, 1]], [2, [:baz, 2]]]
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_each_with_index(int argc, VALUE *argv, VALUE obj)
{
    struct MEMO *memo;

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_size);

    memo = MEMO_NEW(0, 0, 0);
    rb_block_call(obj, id_each, argc, argv, each_with_index_i, (VALUE)memo);
    return obj;
}


/*
 *  call-seq:
 *    reverse_each(*args) {|element| ... } ->  self
 *    reverse_each(*args)                  ->  enumerator
 *
 *  With a block given, calls the block with each element,
 *  but in reverse order; returns +self+:
 *
 *    a = []
 *    (1..4).reverse_each {|element| a.push(-element) } # => 1..4
 *    a # => [-4, -3, -2, -1]
 *
 *    a = []
 *    %w[a b c d].reverse_each {|element| a.push(element) }
 *    # => ["a", "b", "c", "d"]
 *    a # => ["d", "c", "b", "a"]
 *
 *    a = []
 *    h.reverse_each {|element| a.push(element) }
 *    # => {:foo=>0, :bar=>1, :baz=>2}
 *    a # => [[:baz, 2], [:bar, 1], [:foo, 0]]
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_reverse_each(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary;
    long len;

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_size);

    ary = enum_to_a(argc, argv, obj);

    len = RARRAY_LEN(ary);
    while (len--) {
        long nlen;
        rb_yield(RARRAY_AREF(ary, len));
        nlen = RARRAY_LEN(ary);
        if (nlen < len) {
            len = nlen;
        }
    }

    return obj;
}


static VALUE
each_val_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, p))
{
    ENUM_WANT_SVALUE();
    enum_yield(argc, i);
    return Qnil;
}

/*
 *  call-seq:
 *    each_entry(*args) {|element| ... } -> self
 *    each_entry(*args)                  -> enumerator
 *
 *  Calls the given block with each element,
 *  converting multiple values from yield to an array; returns +self+:
 *
 *    a = []
 *    (1..4).each_entry {|element| a.push(element) } # => 1..4
 *    a # => [1, 2, 3, 4]
 *
 *    a = []
 *    h = {foo: 0, bar: 1, baz:2}
 *    h.each_entry {|element| a.push(element) }
 *    # => {:foo=>0, :bar=>1, :baz=>2}
 *    a # => [[:foo, 0], [:bar, 1], [:baz, 2]]
 *
 *    class Foo
 *      include Enumerable
 *      def each
 *        yield 1
 *        yield 1, 2
 *        yield
 *      end
 *    end
 *    Foo.new.each_entry {|yielded| p yielded }
 *
 *  Output:
 *
 *    1
 *    [1, 2]
 *    nil
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_each_entry(int argc, VALUE *argv, VALUE obj)
{
    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_size);
    rb_block_call(obj, id_each, argc, argv, each_val_i, 0);
    return obj;
}

static VALUE
add_int(VALUE x, long n)
{
    const VALUE y = LONG2NUM(n);
    if (RB_INTEGER_TYPE_P(x)) return rb_int_plus(x, y);
    return rb_funcallv(x, '+', 1, &y);
}

static VALUE
div_int(VALUE x, long n)
{
    const VALUE y = LONG2NUM(n);
    if (RB_INTEGER_TYPE_P(x)) return rb_int_idiv(x, y);
    return rb_funcallv(x, id_div, 1, &y);
}

#define dont_recycle_block_arg(arity) ((arity) == 1 || (arity) < 0)

static VALUE
each_slice_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, m))
{
    struct MEMO *memo = MEMO_CAST(m);
    VALUE ary = memo->v1;
    VALUE v = Qnil;
    long size = memo->u3.cnt;
    ENUM_WANT_SVALUE();

    rb_ary_push(ary, i);

    if (RARRAY_LEN(ary) == size) {
        v = rb_yield(ary);

        if (memo->v2) {
            MEMO_V1_SET(memo, rb_ary_new2(size));
        }
        else {
            rb_ary_clear(ary);
        }
    }

    return v;
}

static VALUE
enum_each_slice_size(VALUE obj, VALUE args, VALUE eobj)
{
    VALUE n, size;
    long slice_size = NUM2LONG(RARRAY_AREF(args, 0));
    ID infinite_p;
    CONST_ID(infinite_p, "infinite?");
    if (slice_size <= 0) rb_raise(rb_eArgError, "invalid slice size");

    size = enum_size(obj, 0, 0);
    if (NIL_P(size)) return Qnil;
    if (RB_FLOAT_TYPE_P(size) && RTEST(rb_funcall(size, infinite_p, 0))) {
        return size;
    }

    n = add_int(size, slice_size-1);
    return div_int(n, slice_size);
}

/*
 *  call-seq:
 *    each_slice(n) { ... }  ->  self
 *    each_slice(n)          ->  enumerator
 *
 *  Calls the block with each successive disjoint +n+-tuple of elements;
 *  returns +self+:
 *
 *    a = []
 *    (1..10).each_slice(3) {|tuple| a.push(tuple) }
 *    a # => [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
 *
 *    a = []
 *    h = {foo: 0, bar: 1, baz: 2, bat: 3, bam: 4}
 *    h.each_slice(2) {|tuple| a.push(tuple) }
 *    a # => [[[:foo, 0], [:bar, 1]], [[:baz, 2], [:bat, 3]], [[:bam, 4]]]
 *
 *  With no block given, returns an Enumerator.
 *
 */
static VALUE
enum_each_slice(VALUE obj, VALUE n)
{
    long size = NUM2LONG(n);
    VALUE ary;
    struct MEMO *memo;
    int arity;

    if (size <= 0) rb_raise(rb_eArgError, "invalid slice size");
    RETURN_SIZED_ENUMERATOR(obj, 1, &n, enum_each_slice_size);
    size = limit_by_enum_size(obj, size);
    ary = rb_ary_new2(size);
    arity = rb_block_arity();
    memo = MEMO_NEW(ary, dont_recycle_block_arg(arity), size);
    rb_block_call(obj, id_each, 0, 0, each_slice_i, (VALUE)memo);
    ary = memo->v1;
    if (RARRAY_LEN(ary) > 0) rb_yield(ary);

    return obj;
}

static VALUE
each_cons_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    VALUE ary = memo->v1;
    VALUE v = Qnil;
    long size = memo->u3.cnt;
    ENUM_WANT_SVALUE();

    if (RARRAY_LEN(ary) == size) {
        rb_ary_shift(ary);
    }
    rb_ary_push(ary, i);
    if (RARRAY_LEN(ary) == size) {
        if (memo->v2) {
            ary = rb_ary_dup(ary);
        }
        v = rb_yield(ary);
    }
    return v;
}

static VALUE
enum_each_cons_size(VALUE obj, VALUE args, VALUE eobj)
{
    const VALUE zero = LONG2FIX(0);
    VALUE n, size;
    long cons_size = NUM2LONG(RARRAY_AREF(args, 0));
    if (cons_size <= 0) rb_raise(rb_eArgError, "invalid size");

    size = enum_size(obj, 0, 0);
    if (NIL_P(size)) return Qnil;

    n = add_int(size, 1 - cons_size);
    return (OPTIMIZED_CMP(n, zero) == -1) ? zero : n;
}

/*
 *  call-seq:
 *    each_cons(n) { ... } ->  self
 *    each_cons(n)         ->  enumerator
 *
 *  Calls the block with each successive overlapped +n+-tuple of elements;
 *  returns +self+:
 *
 *    a = []
 *    (1..5).each_cons(3) {|element| a.push(element) }
 *    a # => [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
 *
 *    a = []
 *    h = {foo: 0,  bar: 1, baz: 2, bam: 3}
 *    h.each_cons(2) {|element| a.push(element) }
 *    a # => [[[:foo, 0], [:bar, 1]], [[:bar, 1], [:baz, 2]], [[:baz, 2], [:bam, 3]]]
 *
 *  With no block given, returns an Enumerator.
 *
 */
static VALUE
enum_each_cons(VALUE obj, VALUE n)
{
    long size = NUM2LONG(n);
    struct MEMO *memo;
    int arity;

    if (size <= 0) rb_raise(rb_eArgError, "invalid size");
    RETURN_SIZED_ENUMERATOR(obj, 1, &n, enum_each_cons_size);
    arity = rb_block_arity();
    if (enum_size_over_p(obj, size)) return obj;
    memo = MEMO_NEW(rb_ary_new2(size), dont_recycle_block_arg(arity), size);
    rb_block_call(obj, id_each, 0, 0, each_cons_i, (VALUE)memo);

    return obj;
}

static VALUE
each_with_object_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, memo))
{
    ENUM_WANT_SVALUE();
    return rb_yield_values(2, i, memo);
}

/*
 *  call-seq:
 *    each_with_object(object) { |(*args), memo_object| ... }  ->  object
 *    each_with_object(object)                                 ->  enumerator
 *
 *  Calls the block once for each element, passing both the element
 *  and the given object:
 *
 *    (1..4).each_with_object([]) {|i, a| a.push(i**2) }
 *    # => [1, 4, 9, 16]
 *
 *    {foo: 0, bar: 1, baz: 2}.each_with_object({}) {|(k, v), h| h[v] = k }
 *    # => {0=>:foo, 1=>:bar, 2=>:baz}
 *
 *  With no block given, returns an Enumerator.
 *
 */
static VALUE
enum_each_with_object(VALUE obj, VALUE memo)
{
    RETURN_SIZED_ENUMERATOR(obj, 1, &memo, enum_size);

    rb_block_call(obj, id_each, 0, 0, each_with_object_i, memo);

    return memo;
}

static VALUE
zip_ary(RB_BLOCK_CALL_FUNC_ARGLIST(val, memoval))
{
    struct MEMO *memo = (struct MEMO *)memoval;
    VALUE result = memo->v1;
    VALUE args = memo->v2;
    long n = memo->u3.cnt++;
    VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY_LEN(args) + 1);
    rb_ary_store(tmp, 0, rb_enum_values_pack(argc, argv));
    for (i=0; i<RARRAY_LEN(args); i++) {
        VALUE e = RARRAY_AREF(args, i);

        if (RARRAY_LEN(e) <= n) {
            rb_ary_push(tmp, Qnil);
        }
        else {
            rb_ary_push(tmp, RARRAY_AREF(e, n));
        }
    }
    if (NIL_P(result)) {
        enum_yield_array(tmp);
    }
    else {
        rb_ary_push(result, tmp);
    }

    RB_GC_GUARD(args);

    return Qnil;
}

static VALUE
call_next(VALUE w)
{
    VALUE *v = (VALUE *)w;
    return v[0] = rb_funcallv(v[1], id_next, 0, 0);
}

static VALUE
call_stop(VALUE w, VALUE _)
{
    VALUE *v = (VALUE *)w;
    return v[0] = Qundef;
}

static VALUE
zip_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, memoval))
{
    struct MEMO *memo = (struct MEMO *)memoval;
    VALUE result = memo->v1;
    VALUE args = memo->v2;
    VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY_LEN(args) + 1);
    rb_ary_store(tmp, 0, rb_enum_values_pack(argc, argv));
    for (i=0; i<RARRAY_LEN(args); i++) {
        if (NIL_P(RARRAY_AREF(args, i))) {
            rb_ary_push(tmp, Qnil);
        }
        else {
            VALUE v[2];

            v[1] = RARRAY_AREF(args, i);
            rb_rescue2(call_next, (VALUE)v, call_stop, (VALUE)v, rb_eStopIteration, (VALUE)0);
            if (UNDEF_P(v[0])) {
                RARRAY_ASET(args, i, Qnil);
                v[0] = Qnil;
            }
            rb_ary_push(tmp, v[0]);
        }
    }
    if (NIL_P(result)) {
        enum_yield_array(tmp);
    }
    else {
        rb_ary_push(result, tmp);
    }

    RB_GC_GUARD(args);

    return Qnil;
}

/*
 *  call-seq:
 *    zip(*other_enums) -> array
 *    zip(*other_enums) {|array| ... } -> nil
 *
 *  With no block given, returns a new array +new_array+ of size self.size
 *  whose elements are arrays.
 *  Each nested array <tt>new_array[n]</tt>
 *  is of size <tt>other_enums.size+1</tt>, and contains:
 *
 *  - The +n+-th element of self.
 *  - The +n+-th element of each of the +other_enums+.
 *
 *  If all +other_enums+ and self are the same size,
 *  all elements are included in the result, and there is no +nil+-filling:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *    f = {foo: 0, bar: 1, baz: 2}
 *    g = {goo: 3, gar: 4, gaz: 5}
 *    h = {hoo: 6, har: 7, haz: 8}
 *    d = f.zip(g, h)
 *    d # => [
 *      #      [[:foo, 0], [:goo, 3], [:hoo, 6]],
 *      #      [[:bar, 1], [:gar, 4], [:har, 7]],
 *      #      [[:baz, 2], [:gaz, 5], [:haz, 8]]
 *      #    ]
 *
 *  If any enumerable in other_enums is smaller than self,
 *  fills to <tt>self.size</tt> with +nil+:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2]
 *    c = [:c0, :c1]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, nil], [:a3, nil, nil]]
 *
 *  If any enumerable in other_enums is larger than self,
 *  its trailing elements are ignored:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3, :b4]
 *    c = [:c0, :c1, :c2, :c3, :c4, :c5]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *  When a block is given, calls the block with each of the sub-arrays
 *  (formed as above); returns nil:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    a.zip(b, c) {|sub_array| p sub_array} # => nil
 *
 *  Output:
 *
 *    [:a0, :b0, :c0]
 *    [:a1, :b1, :c1]
 *    [:a2, :b2, :c2]
 *    [:a3, :b3, :c3]
 *
 */

static VALUE
enum_zip(int argc, VALUE *argv, VALUE obj)
{
    int i;
    ID conv;
    struct MEMO *memo;
    VALUE result = Qnil;
    VALUE args = rb_ary_new4(argc, argv);
    int allary = TRUE;

    argv = RARRAY_PTR(args);
    for (i=0; i<argc; i++) {
        VALUE ary = rb_check_array_type(argv[i]);
        if (NIL_P(ary)) {
            allary = FALSE;
            break;
        }
        argv[i] = ary;
    }
    if (!allary) {
        static const VALUE sym_each = STATIC_ID2SYM(id_each);
        CONST_ID(conv, "to_enum");
        for (i=0; i<argc; i++) {
            if (!rb_respond_to(argv[i], id_each)) {
                rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (must respond to :each)",
                         rb_obj_class(argv[i]));
            }
            argv[i] = rb_funcallv(argv[i], conv, 1, &sym_each);
        }
    }
    if (!rb_block_given_p()) {
        result = rb_ary_new();
    }

    /* TODO: use NODE_DOT2 as memo(v, v, -) */
    memo = MEMO_NEW(result, args, 0);
    rb_block_call(obj, id_each, 0, 0, allary ? zip_ary : zip_i, (VALUE)memo);

    return result;
}

static VALUE
take_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    rb_ary_push(memo->v1, rb_enum_values_pack(argc, argv));
    if (--memo->u3.cnt == 0) rb_iter_break();
    return Qnil;
}

/*
 *  call-seq:
 *    take(n) -> array
 *
 *  For non-negative integer +n+, returns the first +n+ elements:
 *
 *    r = (1..4)
 *    r.take(2) # => [1, 2]
 *    r.take(0) # => []
 *
 *    h = {foo: 0, bar: 1, baz: 2, bat: 3}
 *    h.take(2) # => [[:foo, 0], [:bar, 1]]
 *
 */

static VALUE
enum_take(VALUE obj, VALUE n)
{
    struct MEMO *memo;
    VALUE result;
    long len = NUM2LONG(n);

    if (len < 0) {
        rb_raise(rb_eArgError, "attempt to take negative size");
    }

    if (len == 0) return rb_ary_new2(0);
    result = rb_ary_new2(len);
    memo = MEMO_NEW(result, 0, len);
    rb_block_call(obj, id_each, 0, 0, take_i, (VALUE)memo);
    return result;
}


static VALUE
take_while_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    if (!RTEST(rb_yield_values2(argc, argv))) rb_iter_break();
    rb_ary_push(ary, rb_enum_values_pack(argc, argv));
    return Qnil;
}

/*
 *  call-seq:
 *    take_while {|element| ... } -> array
 *    take_while                  -> enumerator
 *
 *  Calls the block with successive elements as long as the block
 *  returns a truthy value;
 *  returns an array of all elements up to that point:
 *
 *
 *    (1..4).take_while{|i| i < 3 } # => [1, 2]
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.take_while{|element| key, value = *element; value < 2 }
 *    # => [[:foo, 0], [:bar, 1]]
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_take_while(VALUE obj)
{
    VALUE ary;

    RETURN_ENUMERATOR(obj, 0, 0);
    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, take_while_i, ary);
    return ary;
}

static VALUE
drop_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    if (memo->u3.cnt == 0) {
        rb_ary_push(memo->v1, rb_enum_values_pack(argc, argv));
    }
    else {
        memo->u3.cnt--;
    }
    return Qnil;
}

/*
 *  call-seq:
 *    drop(n) -> array
 *
 *  For positive integer +n+, returns an array containing
 *  all but the first +n+ elements:
 *
 *    r = (1..4)
 *    r.drop(3)  # => [4]
 *    r.drop(2)  # => [3, 4]
 *    r.drop(1)  # => [2, 3, 4]
 *    r.drop(0)  # => [1, 2, 3, 4]
 *    r.drop(50) # => []
 *
 *    h = {foo: 0, bar: 1, baz: 2, bat: 3}
 *    h.drop(2) # => [[:baz, 2], [:bat, 3]]
 *
 */

static VALUE
enum_drop(VALUE obj, VALUE n)
{
    VALUE result;
    struct MEMO *memo;
    long len = NUM2LONG(n);

    if (len < 0) {
        rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    result = rb_ary_new();
    memo = MEMO_NEW(result, 0, len);
    rb_block_call(obj, id_each, 0, 0, drop_i, (VALUE)memo);
    return result;
}


static VALUE
drop_while_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    struct MEMO *memo = MEMO_CAST(args);
    ENUM_WANT_SVALUE();

    if (!memo->u3.state && !RTEST(enum_yield(argc, i))) {
        memo->u3.state = TRUE;
    }
    if (memo->u3.state) {
        rb_ary_push(memo->v1, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    drop_while {|element| ... } -> array
 *    drop_while                  -> enumerator
 *
 *  Calls the block with successive elements as long as the block
 *  returns a truthy value;
 *  returns an array of all elements after that point:
 *
 *
 *    (1..4).drop_while{|i| i < 3 } # => [3, 4]
 *    h = {foo: 0, bar: 1, baz: 2}
 *    a = h.drop_while{|element| key, value = *element; value < 2 }
 *    a # => [[:baz, 2]]
 *
 *  With no block given, returns an Enumerator.
 *
 */

static VALUE
enum_drop_while(VALUE obj)
{
    VALUE result;
    struct MEMO *memo;

    RETURN_ENUMERATOR(obj, 0, 0);
    result = rb_ary_new();
    memo = MEMO_NEW(result, 0, FALSE);
    rb_block_call(obj, id_each, 0, 0, drop_while_i, (VALUE)memo);
    return result;
}

static VALUE
cycle_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    ENUM_WANT_SVALUE();

    rb_ary_push(ary, argc > 1 ? i : rb_ary_new_from_values(argc, argv));
    enum_yield(argc, i);
    return Qnil;
}

static VALUE
enum_cycle_size(VALUE self, VALUE args, VALUE eobj)
{
    long mul = 0;
    VALUE n = Qnil;
    VALUE size;

    if (args && (RARRAY_LEN(args) > 0)) {
        n = RARRAY_AREF(args, 0);
        if (!NIL_P(n)) mul = NUM2LONG(n);
    }

    size = enum_size(self, args, 0);
    if (NIL_P(size) || FIXNUM_ZERO_P(size)) return size;

    if (NIL_P(n)) return DBL2NUM(HUGE_VAL);
    if (mul <= 0) return INT2FIX(0);
    n = LONG2FIX(mul);
    return rb_funcallv(size, '*', 1, &n);
}

/*
 *  call-seq:
 *    cycle(n = nil) {|element| ...} ->  nil
 *    cycle(n = nil)                 ->  enumerator
 *
 *  When called with positive integer argument +n+ and a block,
 *  calls the block with each element, then does so again,
 *  until it has done so +n+ times; returns +nil+:
 *
 *    a = []
 *    (1..4).cycle(3) {|element| a.push(element) } # => nil
 *    a # => [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4]
 *    a = []
 *    ('a'..'d').cycle(2) {|element| a.push(element) }
 *    a # => ["a", "b", "c", "d", "a", "b", "c", "d"]
 *    a = []
 *    {foo: 0, bar: 1, baz: 2}.cycle(2) {|element| a.push(element) }
 *    a # => [[:foo, 0], [:bar, 1], [:baz, 2], [:foo, 0], [:bar, 1], [:baz, 2]]
 *
 *  If count is zero or negative, does not call the block.
 *
 *  When called with a block and +n+ is +nil+, cycles forever.
 *
 *  When no block is given, returns an Enumerator.
 *
 */

static VALUE
enum_cycle(int argc, VALUE *argv, VALUE obj)
{
    VALUE ary;
    VALUE nv = Qnil;
    long n, i, len;

    rb_check_arity(argc, 0, 1);

    RETURN_SIZED_ENUMERATOR(obj, argc, argv, enum_cycle_size);
    if (!argc || NIL_P(nv = argv[0])) {
        n = -1;
    }
    else {
        n = NUM2LONG(nv);
        if (n <= 0) return Qnil;
    }
    ary = rb_ary_new();
    RBASIC_CLEAR_CLASS(ary);
    rb_block_call(obj, id_each, 0, 0, cycle_i, ary);
    len = RARRAY_LEN(ary);
    if (len == 0) return Qnil;
    while (n < 0 || 0 < --n) {
        for (i=0; i<len; i++) {
            enum_yield_array(RARRAY_AREF(ary, i));
        }
    }
    return Qnil;
}

struct chunk_arg {
    VALUE categorize;
    VALUE prev_value;
    VALUE prev_elts;
    VALUE yielder;
};

static VALUE
chunk_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, _argp))
{
    struct chunk_arg *argp = MEMO_FOR(struct chunk_arg, _argp);
    VALUE v, s;
    VALUE alone = ID2SYM(id__alone);
    VALUE separator = ID2SYM(id__separator);

    ENUM_WANT_SVALUE();

    v = rb_funcallv(argp->categorize, id_call, 1, &i);

    if (v == alone) {
        if (!NIL_P(argp->prev_value)) {
            s = rb_assoc_new(argp->prev_value, argp->prev_elts);
            rb_funcallv(argp->yielder, id_lshift, 1, &s);
            argp->prev_value = argp->prev_elts = Qnil;
        }
        v = rb_assoc_new(v, rb_ary_new3(1, i));
        rb_funcallv(argp->yielder, id_lshift, 1, &v);
    }
    else if (NIL_P(v) || v == separator) {
        if (!NIL_P(argp->prev_value)) {
            v = rb_assoc_new(argp->prev_value, argp->prev_elts);
            rb_funcallv(argp->yielder, id_lshift, 1, &v);
            argp->prev_value = argp->prev_elts = Qnil;
        }
    }
    else if (SYMBOL_P(v) && (s = rb_sym2str(v), RSTRING_PTR(s)[0] == '_')) {
        rb_raise(rb_eRuntimeError, "symbols beginning with an underscore are reserved");
    }
    else {
        if (NIL_P(argp->prev_value)) {
            argp->prev_value = v;
            argp->prev_elts = rb_ary_new3(1, i);
        }
        else {
            if (rb_equal(argp->prev_value, v)) {
                rb_ary_push(argp->prev_elts, i);
            }
            else {
                s = rb_assoc_new(argp->prev_value, argp->prev_elts);
                rb_funcallv(argp->yielder, id_lshift, 1, &s);
                argp->prev_value = v;
                argp->prev_elts = rb_ary_new3(1, i);
            }
        }
    }
    return Qnil;
}

static VALUE
chunk_i(RB_BLOCK_CALL_FUNC_ARGLIST(yielder, enumerator))
{
    VALUE enumerable;
    VALUE arg;
    struct chunk_arg *memo = NEW_MEMO_FOR(struct chunk_arg, arg);

    enumerable = rb_ivar_get(enumerator, id_chunk_enumerable);
    memo->categorize = rb_ivar_get(enumerator, id_chunk_categorize);
    memo->prev_value = Qnil;
    memo->prev_elts = Qnil;
    memo->yielder = yielder;

    rb_block_call(enumerable, id_each, 0, 0, chunk_ii, arg);
    memo = MEMO_FOR(struct chunk_arg, arg);
    if (!NIL_P(memo->prev_elts)) {
        arg = rb_assoc_new(memo->prev_value, memo->prev_elts);
        rb_funcallv(memo->yielder, id_lshift, 1, &arg);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    chunk {|array| ... } -> enumerator
 *
 *  Each element in the returned enumerator is a 2-element array consisting of:
 *
 *  - A value returned by the block.
 *  - An array ("chunk") containing the element for which that value was returned,
 *    and all following elements for which the block returned the same value:
 *
 *  So that:
 *
 *  - Each block return value that is different from its predecessor
 *    begins a new chunk.
 *  - Each block return value that is the same as its predecessor
 *    continues the same chunk.
 *
 *  Example:
 *
 *    e = (0..10).chunk {|i| (i / 3).floor } # => #<Enumerator: ...>
 *    # The enumerator elements.
 *    e.next # => [0, [0, 1, 2]]
 *    e.next # => [1, [3, 4, 5]]
 *    e.next # => [2, [6, 7, 8]]
 *    e.next # => [3, [9, 10]]
 *
 *  \Method +chunk+ is especially useful for an enumerable that is already sorted.
 *  This example counts words for each initial letter in a large array of words:
 *
 *    # Get sorted words from a web page.
 *    url = 'https://raw.githubusercontent.com/eneko/data-repository/master/data/words.txt'
 *    words = URI::open(url).readlines
 *    # Make chunks, one for each letter.
 *    e = words.chunk {|word| word.upcase[0] } # => #<Enumerator: ...>
 *    # Display 'A' through 'F'.
 *    e.each {|c, words| p [c, words.length]; break if c == 'F' }
 *
 *  Output:
 *
 *    ["A", 17096]
 *    ["B", 11070]
 *    ["C", 19901]
 *    ["D", 10896]
 *    ["E", 8736]
 *    ["F", 6860]
 *
 *  You can use the special symbol <tt>:_alone</tt> to force an element
 *  into its own separate chuck:
 *
 *    a = [0, 0, 1, 1]
 *    e = a.chunk{|i| i.even? ? :_alone : true }
 *    e.to_a # => [[:_alone, [0]], [:_alone, [0]], [true, [1, 1]]]
 *
 *  For example, you can put each line that contains a URL into its own chunk:
 *
 *    pattern = /http/
 *    open(filename) { |f|
 *      f.chunk { |line| line =~ pattern ? :_alone : true }.each { |key, lines|
 *        pp lines
 *      }
 *    }
 *
 *  You can use the special symbol <tt>:_separator</tt> or +nil+
 *  to force an element to be ignored (not included in any chunk):
 *
 *    a = [0, 0, -1, 1, 1]
 *    e = a.chunk{|i| i < 0 ? :_separator : true }
 *    e.to_a # => [[true, [0, 0]], [true, [1, 1]]]
 *
 *  Note that the separator does end the chunk:
 *
 *    a = [0, 0, -1, 1, -1, 1]
 *    e = a.chunk{|i| i < 0 ? :_separator : true }
 *    e.to_a # => [[true, [0, 0]], [true, [1]], [true, [1]]]
 *
 *  For example, the sequence of hyphens in svn log can be eliminated as follows:
 *
 *    sep = "-"*72 + "\n"
 *    IO.popen("svn log README") { |f|
 *      f.chunk { |line|
 *        line != sep || nil
 *      }.each { |_, lines|
 *        pp lines
 *      }
 *    }
 *    #=> ["r20018 | knu | 2008-10-29 13:20:42 +0900 (Wed, 29 Oct 2008) | 2 lines\n",
 *    #    "\n",
 *    #    "* README, README.ja: Update the portability section.\n",
 *    #    "\n"]
 *    #   ["r16725 | knu | 2008-05-31 23:34:23 +0900 (Sat, 31 May 2008) | 2 lines\n",
 *    #    "\n",
 *    #    "* README, README.ja: Add a note about default C flags.\n",
 *    #    "\n"]
 *    #   ...
 *
 *  Paragraphs separated by empty lines can be parsed as follows:
 *
 *    File.foreach("README").chunk { |line|
 *      /\A\s*\z/ !~ line || nil
 *    }.each { |_, lines|
 *      pp lines
 *    }
 *
 */
static VALUE
enum_chunk(VALUE enumerable)
{
    VALUE enumerator;

    RETURN_SIZED_ENUMERATOR(enumerable, 0, 0, enum_size);

    enumerator = rb_obj_alloc(rb_cEnumerator);
    rb_ivar_set(enumerator, id_chunk_enumerable, enumerable);
    rb_ivar_set(enumerator, id_chunk_categorize, rb_block_proc());
    rb_block_call(enumerator, idInitialize, 0, 0, chunk_i, enumerator);
    return enumerator;
}


struct slicebefore_arg {
    VALUE sep_pred;
    VALUE sep_pat;
    VALUE prev_elts;
    VALUE yielder;
};

static VALUE
slicebefore_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, _argp))
{
    struct slicebefore_arg *argp = MEMO_FOR(struct slicebefore_arg, _argp);
    VALUE header_p;

    ENUM_WANT_SVALUE();

    if (!NIL_P(argp->sep_pat))
        header_p = rb_funcallv(argp->sep_pat, id_eqq, 1, &i);
    else
        header_p = rb_funcallv(argp->sep_pred, id_call, 1, &i);
    if (RTEST(header_p)) {
        if (!NIL_P(argp->prev_elts))
            rb_funcallv(argp->yielder, id_lshift, 1, &argp->prev_elts);
        argp->prev_elts = rb_ary_new3(1, i);
    }
    else {
        if (NIL_P(argp->prev_elts))
            argp->prev_elts = rb_ary_new3(1, i);
        else
            rb_ary_push(argp->prev_elts, i);
    }

    return Qnil;
}

static VALUE
slicebefore_i(RB_BLOCK_CALL_FUNC_ARGLIST(yielder, enumerator))
{
    VALUE enumerable;
    VALUE arg;
    struct slicebefore_arg *memo = NEW_MEMO_FOR(struct slicebefore_arg, arg);

    enumerable = rb_ivar_get(enumerator, id_slicebefore_enumerable);
    memo->sep_pred = rb_attr_get(enumerator, id_slicebefore_sep_pred);
    memo->sep_pat = NIL_P(memo->sep_pred) ? rb_ivar_get(enumerator, id_slicebefore_sep_pat) : Qnil;
    memo->prev_elts = Qnil;
    memo->yielder = yielder;

    rb_block_call(enumerable, id_each, 0, 0, slicebefore_ii, arg);
    memo = MEMO_FOR(struct slicebefore_arg, arg);
    if (!NIL_P(memo->prev_elts))
        rb_funcallv(memo->yielder, id_lshift, 1, &memo->prev_elts);
    return Qnil;
}

/*
 *  call-seq:
 *    slice_before(pattern)       -> enumerator
 *    slice_before {|elt| ... } -> enumerator
 *
 *  With argument +pattern+, returns an enumerator that uses the pattern
 *  to partition elements into arrays ("slices").
 *  An element begins a new slice if <tt>element === pattern</tt>
 *  (or if it is the first element).
 *
 *    a = %w[foo bar fop for baz fob fog bam foy]
 *    e = a.slice_before(/ba/) # => #<Enumerator: ...>
 *    e.each {|array| p array }
 *
 *  Output:
 *
 *    ["foo"]
 *    ["bar", "fop", "for"]
 *    ["baz", "fob", "fog"]
 *    ["bam", "foy"]
 *
 *  With a block, returns an enumerator that uses the block
 *  to partition elements into arrays.
 *  An element begins a new slice if its block return is a truthy value
 *  (or if it is the first element):
 *
 *    e = (1..20).slice_before {|i| i % 4 == 2 } # => #<Enumerator: ...>
 *    e.each {|array| p array }
 *
 *  Output:
 *
 *    [1]
 *    [2, 3, 4, 5]
 *    [6, 7, 8, 9]
 *    [10, 11, 12, 13]
 *    [14, 15, 16, 17]
 *    [18, 19, 20]
 *
 *  Other methods of the Enumerator class and Enumerable module,
 *  such as +to_a+, +map+, etc., are also usable.
 *
 *  For example, iteration over ChangeLog entries can be implemented as
 *  follows:
 *
 *    # iterate over ChangeLog entries.
 *    open("ChangeLog") { |f|
 *      f.slice_before(/\A\S/).each { |e| pp e }
 *    }
 *
 *    # same as above.  block is used instead of pattern argument.
 *    open("ChangeLog") { |f|
 *      f.slice_before { |line| /\A\S/ === line }.each { |e| pp e }
 *    }
 *
 *  "svn proplist -R" produces multiline output for each file.
 *  They can be chunked as follows:
 *
 *    IO.popen([{"LC_ALL"=>"C"}, "svn", "proplist", "-R"]) { |f|
 *      f.lines.slice_before(/\AProp/).each { |lines| p lines }
 *    }
 *    #=> ["Properties on '.':\n", "  svn:ignore\n", "  svk:merge\n"]
 *    #   ["Properties on 'goruby.c':\n", "  svn:eol-style\n"]
 *    #   ["Properties on 'complex.c':\n", "  svn:mime-type\n", "  svn:eol-style\n"]
 *    #   ["Properties on 'regparse.c':\n", "  svn:eol-style\n"]
 *    #   ...
 *
 *  If the block needs to maintain state over multiple elements,
 *  local variables can be used.
 *  For example, three or more consecutive increasing numbers can be squashed
 *  as follows (see +chunk_while+ for a better way):
 *
 *    a = [0, 2, 3, 4, 6, 7, 9]
 *    prev = a[0]
 *    p a.slice_before { |e|
 *      prev, prev2 = e, prev
 *      prev2 + 1 != e
 *    }.map { |es|
 *      es.length <= 2 ? es.join(",") : "#{es.first}-#{es.last}"
 *    }.join(",")
 *    #=> "0,2-4,6,7,9"
 *
 *  However local variables should be used carefully
 *  if the result enumerator is enumerated twice or more.
 *  The local variables should be initialized for each enumeration.
 *  Enumerator.new can be used to do it.
 *
 *    # Word wrapping.  This assumes all characters have same width.
 *    def wordwrap(words, maxwidth)
 *      Enumerator.new {|y|
 *        # cols is initialized in Enumerator.new.
 *        cols = 0
 *        words.slice_before { |w|
 *          cols += 1 if cols != 0
 *          cols += w.length
 *          if maxwidth < cols
 *            cols = w.length
 *            true
 *          else
 *            false
 *          end
 *        }.each {|ws| y.yield ws }
 *      }
 *    end
 *    text = (1..20).to_a.join(" ")
 *    enum = wordwrap(text.split(/\s+/), 10)
 *    puts "-"*10
 *    enum.each { |ws| puts ws.join(" ") } # first enumeration.
 *    puts "-"*10
 *    enum.each { |ws| puts ws.join(" ") } # second enumeration generates same result as the first.
 *    puts "-"*10
 *    #=> ----------
 *    #   1 2 3 4 5
 *    #   6 7 8 9 10
 *    #   11 12 13
 *    #   14 15 16
 *    #   17 18 19
 *    #   20
 *    #   ----------
 *    #   1 2 3 4 5
 *    #   6 7 8 9 10
 *    #   11 12 13
 *    #   14 15 16
 *    #   17 18 19
 *    #   20
 *    #   ----------
 *
 *  mbox contains series of mails which start with Unix From line.
 *  So each mail can be extracted by slice before Unix From line.
 *
 *    # parse mbox
 *    open("mbox") { |f|
 *      f.slice_before { |line|
 *        line.start_with? "From "
 *      }.each { |mail|
 *        unix_from = mail.shift
 *        i = mail.index("\n")
 *        header = mail[0...i]
 *        body = mail[(i+1)..-1]
 *        body.pop if body.last == "\n"
 *        fields = header.slice_before { |line| !" \t".include?(line[0]) }.to_a
 *        p unix_from
 *        pp fields
 *        pp body
 *      }
 *    }
 *
 *    # split mails in mbox (slice before Unix From line after an empty line)
 *    open("mbox") { |f|
 *      emp = true
 *      f.slice_before { |line|
 *        prevemp = emp
 *        emp = line == "\n"
 *        prevemp && line.start_with?("From ")
 *      }.each { |mail|
 *        mail.pop if mail.last == "\n"
 *        pp mail
 *      }
 *    }
 *
 */
static VALUE
enum_slice_before(int argc, VALUE *argv, VALUE enumerable)
{
    VALUE enumerator;

    if (rb_block_given_p()) {
        if (argc != 0)
            rb_error_arity(argc, 0, 0);
        enumerator = rb_obj_alloc(rb_cEnumerator);
        rb_ivar_set(enumerator, id_slicebefore_sep_pred, rb_block_proc());
    }
    else {
        VALUE sep_pat;
        rb_scan_args(argc, argv, "1", &sep_pat);
        enumerator = rb_obj_alloc(rb_cEnumerator);
        rb_ivar_set(enumerator, id_slicebefore_sep_pat, sep_pat);
    }
    rb_ivar_set(enumerator, id_slicebefore_enumerable, enumerable);
    rb_block_call(enumerator, idInitialize, 0, 0, slicebefore_i, enumerator);
    return enumerator;
}


struct sliceafter_arg {
    VALUE pat;
    VALUE pred;
    VALUE prev_elts;
    VALUE yielder;
};

static VALUE
sliceafter_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, _memo))
{
#define UPDATE_MEMO ((void)(memo = MEMO_FOR(struct sliceafter_arg, _memo)))
    struct sliceafter_arg *memo;
    int split_p;
    UPDATE_MEMO;

    ENUM_WANT_SVALUE();

    if (NIL_P(memo->prev_elts)) {
        memo->prev_elts = rb_ary_new3(1, i);
    }
    else {
        rb_ary_push(memo->prev_elts, i);
    }

    if (NIL_P(memo->pred)) {
        split_p = RTEST(rb_funcallv(memo->pat, id_eqq, 1, &i));
        UPDATE_MEMO;
    }
    else {
        split_p = RTEST(rb_funcallv(memo->pred, id_call, 1, &i));
        UPDATE_MEMO;
    }

    if (split_p) {
        rb_funcallv(memo->yielder, id_lshift, 1, &memo->prev_elts);
        UPDATE_MEMO;
        memo->prev_elts = Qnil;
    }

    return Qnil;
#undef UPDATE_MEMO
}

static VALUE
sliceafter_i(RB_BLOCK_CALL_FUNC_ARGLIST(yielder, enumerator))
{
    VALUE enumerable;
    VALUE arg;
    struct sliceafter_arg *memo = NEW_MEMO_FOR(struct sliceafter_arg, arg);

    enumerable = rb_ivar_get(enumerator, id_sliceafter_enum);
    memo->pat = rb_ivar_get(enumerator, id_sliceafter_pat);
    memo->pred = rb_attr_get(enumerator, id_sliceafter_pred);
    memo->prev_elts = Qnil;
    memo->yielder = yielder;

    rb_block_call(enumerable, id_each, 0, 0, sliceafter_ii, arg);
    memo = MEMO_FOR(struct sliceafter_arg, arg);
    if (!NIL_P(memo->prev_elts))
        rb_funcallv(memo->yielder, id_lshift, 1, &memo->prev_elts);
    return Qnil;
}

/*
 *  call-seq:
 *     enum.slice_after(pattern)       -> an_enumerator
 *     enum.slice_after { |elt| bool } -> an_enumerator
 *
 *  Creates an enumerator for each chunked elements.
 *  The ends of chunks are defined by _pattern_ and the block.
 *
 *  If <code>_pattern_ === _elt_</code> returns <code>true</code> or the block
 *  returns <code>true</code> for the element, the element is end of a
 *  chunk.
 *
 *  The <code>===</code> and _block_ is called from the first element to the last
 *  element of _enum_.
 *
 *  The result enumerator yields the chunked elements as an array.
 *  So +each+ method can be called as follows:
 *
 *    enum.slice_after(pattern).each { |ary| ... }
 *    enum.slice_after { |elt| bool }.each { |ary| ... }
 *
 *  Other methods of the Enumerator class and Enumerable module,
 *  such as +map+, etc., are also usable.
 *
 *  For example, continuation lines (lines end with backslash) can be
 *  concatenated as follows:
 *
 *    lines = ["foo\n", "bar\\\n", "baz\n", "\n", "qux\n"]
 *    e = lines.slice_after(/(?<!\\)\n\z/)
 *    p e.to_a
 *    #=> [["foo\n"], ["bar\\\n", "baz\n"], ["\n"], ["qux\n"]]
 *    p e.map {|ll| ll[0...-1].map {|l| l.sub(/\\\n\z/, "") }.join + ll.last }
 *    #=>["foo\n", "barbaz\n", "\n", "qux\n"]
 *
 */

static VALUE
enum_slice_after(int argc, VALUE *argv, VALUE enumerable)
{
    VALUE enumerator;
    VALUE pat = Qnil, pred = Qnil;

    if (rb_block_given_p()) {
        if (0 < argc)
            rb_raise(rb_eArgError, "both pattern and block are given");
        pred = rb_block_proc();
    }
    else {
        rb_scan_args(argc, argv, "1", &pat);
    }

    enumerator = rb_obj_alloc(rb_cEnumerator);
    rb_ivar_set(enumerator, id_sliceafter_enum, enumerable);
    rb_ivar_set(enumerator, id_sliceafter_pat, pat);
    rb_ivar_set(enumerator, id_sliceafter_pred, pred);

    rb_block_call(enumerator, idInitialize, 0, 0, sliceafter_i, enumerator);
    return enumerator;
}

struct slicewhen_arg {
    VALUE pred;
    VALUE prev_elt;
    VALUE prev_elts;
    VALUE yielder;
    int inverted; /* 0 for slice_when and 1 for chunk_while. */
};

static VALUE
slicewhen_ii(RB_BLOCK_CALL_FUNC_ARGLIST(i, _memo))
{
#define UPDATE_MEMO ((void)(memo = MEMO_FOR(struct slicewhen_arg, _memo)))
    struct slicewhen_arg *memo;
    int split_p;
    UPDATE_MEMO;

    ENUM_WANT_SVALUE();

    if (UNDEF_P(memo->prev_elt)) {
        /* The first element */
        memo->prev_elt = i;
        memo->prev_elts = rb_ary_new3(1, i);
    }
    else {
        VALUE args[2];
        args[0] = memo->prev_elt;
        args[1] = i;
        split_p = RTEST(rb_funcallv(memo->pred, id_call, 2, args));
        UPDATE_MEMO;

        if (memo->inverted)
            split_p = !split_p;

        if (split_p) {
            rb_funcallv(memo->yielder, id_lshift, 1, &memo->prev_elts);
            UPDATE_MEMO;
            memo->prev_elts = rb_ary_new3(1, i);
        }
        else {
            rb_ary_push(memo->prev_elts, i);
        }

        memo->prev_elt = i;
    }

    return Qnil;
#undef UPDATE_MEMO
}

static VALUE
slicewhen_i(RB_BLOCK_CALL_FUNC_ARGLIST(yielder, enumerator))
{
    VALUE enumerable;
    VALUE arg;
    struct slicewhen_arg *memo =
        NEW_PARTIAL_MEMO_FOR(struct slicewhen_arg, arg, inverted);

    enumerable = rb_ivar_get(enumerator, id_slicewhen_enum);
    memo->pred = rb_attr_get(enumerator, id_slicewhen_pred);
    memo->prev_elt = Qundef;
    memo->prev_elts = Qnil;
    memo->yielder = yielder;
    memo->inverted = RTEST(rb_attr_get(enumerator, id_slicewhen_inverted));

    rb_block_call(enumerable, id_each, 0, 0, slicewhen_ii, arg);
    memo = MEMO_FOR(struct slicewhen_arg, arg);
    if (!NIL_P(memo->prev_elts))
        rb_funcallv(memo->yielder, id_lshift, 1, &memo->prev_elts);
    return Qnil;
}

/*
 *  call-seq:
 *     enum.slice_when {|elt_before, elt_after| bool } -> an_enumerator
 *
 *  Creates an enumerator for each chunked elements.
 *  The beginnings of chunks are defined by the block.
 *
 *  This method splits each chunk using adjacent elements,
 *  _elt_before_ and _elt_after_,
 *  in the receiver enumerator.
 *  This method split chunks between _elt_before_ and _elt_after_ where
 *  the block returns <code>true</code>.
 *
 *  The block is called the length of the receiver enumerator minus one.
 *
 *  The result enumerator yields the chunked elements as an array.
 *  So +each+ method can be called as follows:
 *
 *    enum.slice_when { |elt_before, elt_after| bool }.each { |ary| ... }
 *
 *  Other methods of the Enumerator class and Enumerable module,
 *  such as +to_a+, +map+, etc., are also usable.
 *
 *  For example, one-by-one increasing subsequence can be chunked as follows:
 *
 *    a = [1,2,4,9,10,11,12,15,16,19,20,21]
 *    b = a.slice_when {|i, j| i+1 != j }
 *    p b.to_a #=> [[1, 2], [4], [9, 10, 11, 12], [15, 16], [19, 20, 21]]
 *    c = b.map {|a| a.length < 3 ? a : "#{a.first}-#{a.last}" }
 *    p c #=> [[1, 2], [4], "9-12", [15, 16], "19-21"]
 *    d = c.join(",")
 *    p d #=> "1,2,4,9-12,15,16,19-21"
 *
 *  Near elements (threshold: 6) in sorted array can be chunked as follows:
 *
 *    a = [3, 11, 14, 25, 28, 29, 29, 41, 55, 57]
 *    p a.slice_when {|i, j| 6 < j - i }.to_a
 *    #=> [[3], [11, 14], [25, 28, 29, 29], [41], [55, 57]]
 *
 *  Increasing (non-decreasing) subsequence can be chunked as follows:
 *
 *    a = [0, 9, 2, 2, 3, 2, 7, 5, 9, 5]
 *    p a.slice_when {|i, j| i > j }.to_a
 *    #=> [[0, 9], [2, 2, 3], [2, 7], [5, 9], [5]]
 *
 *  Adjacent evens and odds can be chunked as follows:
 *  (Enumerable#chunk is another way to do it.)
 *
 *    a = [7, 5, 9, 2, 0, 7, 9, 4, 2, 0]
 *    p a.slice_when {|i, j| i.even? != j.even? }.to_a
 *    #=> [[7, 5, 9], [2, 0], [7, 9], [4, 2, 0]]
 *
 *  Paragraphs (non-empty lines with trailing empty lines) can be chunked as follows:
 *  (See Enumerable#chunk to ignore empty lines.)
 *
 *    lines = ["foo\n", "bar\n", "\n", "baz\n", "qux\n"]
 *    p lines.slice_when {|l1, l2| /\A\s*\z/ =~ l1 && /\S/ =~ l2 }.to_a
 *    #=> [["foo\n", "bar\n", "\n"], ["baz\n", "qux\n"]]
 *
 *  Enumerable#chunk_while does the same, except splitting when the block
 *  returns <code>false</code> instead of <code>true</code>.
 */
static VALUE
enum_slice_when(VALUE enumerable)
{
    VALUE enumerator;
    VALUE pred;

    pred = rb_block_proc();

    enumerator = rb_obj_alloc(rb_cEnumerator);
    rb_ivar_set(enumerator, id_slicewhen_enum, enumerable);
    rb_ivar_set(enumerator, id_slicewhen_pred, pred);
    rb_ivar_set(enumerator, id_slicewhen_inverted, Qfalse);

    rb_block_call(enumerator, idInitialize, 0, 0, slicewhen_i, enumerator);
    return enumerator;
}

/*
 *  call-seq:
 *     enum.chunk_while {|elt_before, elt_after| bool } -> an_enumerator
 *
 *  Creates an enumerator for each chunked elements.
 *  The beginnings of chunks are defined by the block.
 *
 *  This method splits each chunk using adjacent elements,
 *  _elt_before_ and _elt_after_,
 *  in the receiver enumerator.
 *  This method split chunks between _elt_before_ and _elt_after_ where
 *  the block returns <code>false</code>.
 *
 *  The block is called the length of the receiver enumerator minus one.
 *
 *  The result enumerator yields the chunked elements as an array.
 *  So +each+ method can be called as follows:
 *
 *    enum.chunk_while { |elt_before, elt_after| bool }.each { |ary| ... }
 *
 *  Other methods of the Enumerator class and Enumerable module,
 *  such as +to_a+, +map+, etc., are also usable.
 *
 *  For example, one-by-one increasing subsequence can be chunked as follows:
 *
 *    a = [1,2,4,9,10,11,12,15,16,19,20,21]
 *    b = a.chunk_while {|i, j| i+1 == j }
 *    p b.to_a #=> [[1, 2], [4], [9, 10, 11, 12], [15, 16], [19, 20, 21]]
 *    c = b.map {|a| a.length < 3 ? a : "#{a.first}-#{a.last}" }
 *    p c #=> [[1, 2], [4], "9-12", [15, 16], "19-21"]
 *    d = c.join(",")
 *    p d #=> "1,2,4,9-12,15,16,19-21"
 *
 *  Increasing (non-decreasing) subsequence can be chunked as follows:
 *
 *    a = [0, 9, 2, 2, 3, 2, 7, 5, 9, 5]
 *    p a.chunk_while {|i, j| i <= j }.to_a
 *    #=> [[0, 9], [2, 2, 3], [2, 7], [5, 9], [5]]
 *
 *  Adjacent evens and odds can be chunked as follows:
 *  (Enumerable#chunk is another way to do it.)
 *
 *    a = [7, 5, 9, 2, 0, 7, 9, 4, 2, 0]
 *    p a.chunk_while {|i, j| i.even? == j.even? }.to_a
 *    #=> [[7, 5, 9], [2, 0], [7, 9], [4, 2, 0]]
 *
 *  Enumerable#slice_when does the same, except splitting when the block
 *  returns <code>true</code> instead of <code>false</code>.
 */
static VALUE
enum_chunk_while(VALUE enumerable)
{
    VALUE enumerator;
    VALUE pred;

    pred = rb_block_proc();

    enumerator = rb_obj_alloc(rb_cEnumerator);
    rb_ivar_set(enumerator, id_slicewhen_enum, enumerable);
    rb_ivar_set(enumerator, id_slicewhen_pred, pred);
    rb_ivar_set(enumerator, id_slicewhen_inverted, Qtrue);

    rb_block_call(enumerator, idInitialize, 0, 0, slicewhen_i, enumerator);
    return enumerator;
}

struct enum_sum_memo {
    VALUE v, r;
    long n;
    double f, c;
    int block_given;
    int float_value;
};

static void
sum_iter_normalize_memo(struct enum_sum_memo *memo)
{
    assert(FIXABLE(memo->n));
    memo->v = rb_fix_plus(LONG2FIX(memo->n), memo->v);
    memo->n = 0;

    switch (TYPE(memo->r)) {
      case T_RATIONAL: memo->v = rb_rational_plus(memo->r, memo->v); break;
      case T_UNDEF:    break;
      default:         UNREACHABLE; /* or ...? */
    }
    memo->r = Qundef;
}

static void
sum_iter_fixnum(VALUE i, struct enum_sum_memo *memo)
{
    memo->n += FIX2LONG(i); /* should not overflow long type */
    if (! FIXABLE(memo->n)) {
        memo->v = rb_big_plus(LONG2NUM(memo->n), memo->v);
        memo->n = 0;
    }
}

static void
sum_iter_bignum(VALUE i, struct enum_sum_memo *memo)
{
    memo->v = rb_big_plus(i, memo->v);
}

static void
sum_iter_rational(VALUE i, struct enum_sum_memo *memo)
{
    if (UNDEF_P(memo->r)) {
        memo->r = i;
    }
    else {
        memo->r = rb_rational_plus(memo->r, i);
    }
}

static void
sum_iter_some_value(VALUE i, struct enum_sum_memo *memo)
{
    memo->v = rb_funcallv(memo->v, idPLUS, 1, &i);
}

static void
sum_iter_Kahan_Babuska(VALUE i, struct enum_sum_memo *memo)
{
    /*
     * Kahan-Babuska balancing compensated summation algorithm
     * See https://link.springer.com/article/10.1007/s00607-005-0139-x
     */
    double x;

    switch (TYPE(i)) {
      case T_FLOAT:    x = RFLOAT_VALUE(i); break;
      case T_FIXNUM:   x = FIX2LONG(i);     break;
      case T_BIGNUM:   x = rb_big2dbl(i);   break;
      case T_RATIONAL: x = rb_num2dbl(i);   break;
      default:
        memo->v = DBL2NUM(memo->f);
        memo->float_value = 0;
        sum_iter_some_value(i, memo);
        return;
    }

    double f = memo->f;

    if (isnan(f)) {
        return;
    }
    else if (! isfinite(x)) {
        if (isinf(x) && isinf(f) && signbit(x) != signbit(f)) {
            i = DBL2NUM(f);
            x = nan("");
        }
        memo->v = i;
        memo->f = x;
        return;
    }
    else if (isinf(f)) {
        return;
    }

    double c = memo->c;
    double t = f + x;

    if (fabs(f) >= fabs(x)) {
        c += ((f - t) + x);
    }
    else {
        c += ((x - t) + f);
    }
    f = t;

    memo->f = f;
    memo->c = c;
}

static void
sum_iter(VALUE i, struct enum_sum_memo *memo)
{
    assert(memo != NULL);
    if (memo->block_given) {
        i = rb_yield(i);
    }

    if (memo->float_value) {
        sum_iter_Kahan_Babuska(i, memo);
    }
    else switch (TYPE(memo->v)) {
      default:      sum_iter_some_value(i, memo);    return;
      case T_FLOAT: sum_iter_Kahan_Babuska(i, memo); return;
      case T_FIXNUM:
      case T_BIGNUM:
      case T_RATIONAL:
        switch (TYPE(i)) {
          case T_FIXNUM:   sum_iter_fixnum(i, memo);   return;
          case T_BIGNUM:   sum_iter_bignum(i, memo);   return;
          case T_RATIONAL: sum_iter_rational(i, memo); return;
          case T_FLOAT:
            sum_iter_normalize_memo(memo);
            memo->f = NUM2DBL(memo->v);
            memo->c = 0.0;
            memo->float_value = 1;
            sum_iter_Kahan_Babuska(i, memo);
            return;
          default:
            sum_iter_normalize_memo(memo);
            sum_iter_some_value(i, memo);
            return;
        }
    }
}

static VALUE
enum_sum_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, args))
{
    ENUM_WANT_SVALUE();
    sum_iter(i, (struct enum_sum_memo *) args);
    return Qnil;
}

static int
hash_sum_i(VALUE key, VALUE value, VALUE arg)
{
    sum_iter(rb_assoc_new(key, value), (struct enum_sum_memo *) arg);
    return ST_CONTINUE;
}

static void
hash_sum(VALUE hash, struct enum_sum_memo *memo)
{
    assert(RB_TYPE_P(hash, T_HASH));
    assert(memo != NULL);

    rb_hash_foreach(hash, hash_sum_i, (VALUE)memo);
}

static VALUE
int_range_sum(VALUE beg, VALUE end, int excl, VALUE init)
{
    if (excl) {
        if (FIXNUM_P(end))
            end = LONG2FIX(FIX2LONG(end) - 1);
        else
            end = rb_big_minus(end, LONG2FIX(1));
    }

    if (rb_int_ge(end, beg)) {
        VALUE a;
        a = rb_int_plus(rb_int_minus(end, beg), LONG2FIX(1));
        a = rb_int_mul(a, rb_int_plus(end, beg));
        a = rb_int_idiv(a, LONG2FIX(2));
        return rb_int_plus(init, a);
    }

    return init;
}

/*
 *  call-seq:
 *    sum(initial_value = 0)                  -> number
 *    sum(initial_value = 0) {|element| ... } -> object
 *
 *  With no block given,
 *  returns the sum of +initial_value+ and the elements:
 *
 *    (1..100).sum          # => 5050
 *    (1..100).sum(1)       # => 5051
 *    ('a'..'d').sum('foo') # => "fooabcd"
 *
 *  Generally, the sum is computed using methods <tt>+</tt> and +each+;
 *  for performance optimizations, those methods may not be used,
 *  and so any redefinition of those methods may not have effect here.
 *
 *  One such optimization: When possible, computes using Gauss's summation
 *  formula <em>n(n+1)/2</em>:
 *
 *    100 * (100 + 1) / 2 # => 5050
 *
 *  With a block given, calls the block with each element;
 *  returns the sum of +initial_value+ and the block return values:
 *
 *    (1..4).sum {|i| i*i }                        # => 30
 *    (1..4).sum(100) {|i| i*i }                   # => 130
 *    h = {a: 0, b: 1, c: 2, d: 3, e: 4, f: 5}
 *    h.sum {|key, value| value.odd? ? value : 0 } # => 9
 *    ('a'..'f').sum('x') {|c| c < 'd' ? c : '' }  # => "xabc"
 *
 */
static VALUE
enum_sum(int argc, VALUE* argv, VALUE obj)
{
    struct enum_sum_memo memo;
    VALUE beg, end;
    int excl;

    memo.v = (rb_check_arity(argc, 0, 1) == 0) ? LONG2FIX(0) : argv[0];
    memo.block_given = rb_block_given_p();
    memo.n = 0;
    memo.r = Qundef;

    if ((memo.float_value = RB_FLOAT_TYPE_P(memo.v))) {
        memo.f = RFLOAT_VALUE(memo.v);
        memo.c = 0.0;
    }
    else {
        memo.f = 0.0;
        memo.c = 0.0;
    }

    if (RTEST(rb_range_values(obj, &beg, &end, &excl))) {
        if (!memo.block_given && !memo.float_value &&
                (FIXNUM_P(beg) || RB_BIGNUM_TYPE_P(beg)) &&
                (FIXNUM_P(end) || RB_BIGNUM_TYPE_P(end))) {
            return int_range_sum(beg, end, excl, memo.v);
        }
    }

    if (RB_TYPE_P(obj, T_HASH) &&
            rb_method_basic_definition_p(CLASS_OF(obj), id_each))
        hash_sum(obj, &memo);
    else
        rb_block_call(obj, id_each, 0, 0, enum_sum_i, (VALUE)&memo);

    if (memo.float_value) {
        return DBL2NUM(memo.f + memo.c);
    }
    else {
        if (memo.n != 0)
            memo.v = rb_fix_plus(LONG2FIX(memo.n), memo.v);
        if (!UNDEF_P(memo.r)) {
            memo.v = rb_rational_plus(memo.r, memo.v);
        }
        return memo.v;
    }
}

static VALUE
uniq_func(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    ENUM_WANT_SVALUE();
    rb_hash_add_new_element(hash, i, i);
    return Qnil;
}

static VALUE
uniq_iter(RB_BLOCK_CALL_FUNC_ARGLIST(i, hash))
{
    ENUM_WANT_SVALUE();
    rb_hash_add_new_element(hash, rb_yield_values2(argc, argv), i);
    return Qnil;
}

/*
 *  call-seq:
 *    uniq                  -> array
 *    uniq {|element| ... } -> array
 *
 *  With no block, returns a new array containing only unique elements;
 *  the array has no two elements +e0+ and +e1+ such that <tt>e0.eql?(e1)</tt>:
 *
 *    %w[a b c c b a a b c].uniq       # => ["a", "b", "c"]
 *    [0, 1, 2, 2, 1, 0, 0, 1, 2].uniq # => [0, 1, 2]
 *
 *  With a block, returns a new array containing elements only for which the block
 *  returns a unique value:
 *
 *    a = [0, 1, 2, 3, 4, 5, 5, 4, 3, 2, 1]
 *    a.uniq {|i| i.even? ? i : 0 } # => [0, 2, 4]
 *    a = %w[a b c d e e d c b a a b c d e]
 *    a.uniq {|c| c < 'c' }         # => ["a", "c"]
 *
 */

static VALUE
enum_uniq(VALUE obj)
{
    VALUE hash, ret;
    rb_block_call_func *const func =
        rb_block_given_p() ? uniq_iter : uniq_func;

    hash = rb_obj_hide(rb_hash_new());
    rb_block_call(obj, id_each, 0, 0, func, hash);
    ret = rb_hash_values(hash);
    rb_hash_clear(hash);
    return ret;
}

static VALUE
compact_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    ENUM_WANT_SVALUE();

    if (!NIL_P(i)) {
        rb_ary_push(ary, i);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    compact -> array
 *
 *  Returns an array of all non-+nil+ elements:
 *
 *    a = [nil, 0, nil, 'a', false, nil, false, nil, 'a', nil, 0, nil]
 *    a.compact # => [0, "a", false, false, "a", 0]
 *
 */

static VALUE
enum_compact(VALUE obj)
{
    VALUE ary;

    ary = rb_ary_new();
    rb_block_call(obj, id_each, 0, 0, compact_i, ary);

    return ary;
}


/*
 * == What's Here
 *
 * \Module \Enumerable provides methods that are useful to a collection class for:
 *
 * - {Querying}[rdoc-ref:Enumerable@Methods+for+Querying]
 * - {Fetching}[rdoc-ref:Enumerable@Methods+for+Fetching]
 * - {Searching and Filtering}[rdoc-ref:Enumerable@Methods+for+Searching+and+Filtering]
 * - {Sorting}[rdoc-ref:Enumerable@Methods+for+Sorting]
 * - {Iterating}[rdoc-ref:Enumerable@Methods+for+Iterating]
 * - {And more....}[rdoc-ref:Enumerable@Other+Methods]
 *
 * === Methods for Querying
 *
 * These methods return information about the \Enumerable other than the elements themselves:
 *
 * - #include?, #member?: Returns +true+ if <tt>self == object</tt>, +false+ otherwise.
 * - #all?: Returns +true+ if all elements meet a specified criterion; +false+ otherwise.
 * - #any?: Returns +true+ if any element meets a specified criterion; +false+ otherwise.
 * - #none?: Returns +true+ if no element meets a specified criterion; +false+ otherwise.
 * - #one?: Returns +true+ if exactly one element meets a specified criterion; +false+ otherwise.
 * - #count: Returns the count of elements,
 *   based on an argument or block criterion, if given.
 * - #tally: Returns a new Hash containing the counts of occurrences of each element.
 *
 * === Methods for Fetching
 *
 * These methods return entries from the \Enumerable, without modifying it:
 *
 * <i>Leading, trailing, or all elements</i>:
 *
 * - #entries, #to_a: Returns all elements.
 * - #first: Returns the first element or leading elements.
 * - #take: Returns a specified number of leading elements.
 * - #drop: Returns a specified number of trailing elements.
 * - #take_while: Returns leading elements as specified by the given block.
 * - #drop_while: Returns trailing elements as specified by the given block.
 *
 * <i>Minimum and maximum value elements</i>:
 *
 * - #min: Returns the elements whose values are smallest among the elements,
 *   as determined by <tt><=></tt> or a given block.
 * - #max: Returns the elements whose values are largest among the elements,
 *   as determined by <tt><=></tt> or a given block.
 * - #minmax: Returns a 2-element Array containing the smallest and largest elements.
 * - #min_by: Returns the smallest element, as determined by the given block.
 * - #max_by: Returns the largest element, as determined by the given block.
 * - #minmax_by: Returns the smallest and largest elements, as determined by the given block.
 *
 * <i>Groups, slices, and partitions</i>:
 *
 * - #group_by: Returns a Hash that partitions the elements into groups.
 * - #partition: Returns elements partitioned into two new Arrays, as determined by the given block.
 * - #slice_after: Returns a new Enumerator whose entries are a partition of +self+,
 *   based either on a given +object+ or a given block.
 * - #slice_before: Returns a new Enumerator whose entries are a partition of +self+,
 *   based either on a given +object+ or a given block.
 * - #slice_when: Returns a new Enumerator whose entries are a partition of +self+
 *   based on the given block.
 * - #chunk: Returns elements organized into chunks as specified by the given block.
 * - #chunk_while: Returns elements organized into chunks as specified by the given block.
 *
 * === Methods for Searching and Filtering
 *
 * These methods return elements that meet a specified criterion:
 *
 * - #find, #detect: Returns an element selected by the block.
 * - #find_all, #filter, #select: Returns elements selected by the block.
 * - #find_index: Returns the index of an element selected by a given object or block.
 * - #reject: Returns elements not rejected by the block.
 * - #uniq: Returns elements that are not duplicates.
 *
 * === Methods for Sorting
 *
 * These methods return elements in sorted order:
 *
 * - #sort: Returns the elements, sorted by <tt><=></tt> or the given block.
 * - #sort_by: Returns the elements, sorted by the given block.
 *
 * === Methods for Iterating
 *
 * - #each_entry: Calls the block with each successive element
 *   (slightly different from #each).
 * - #each_with_index: Calls the block with each successive element and its index.
 * - #each_with_object: Calls the block with each successive element and a given object.
 * - #each_slice: Calls the block with successive non-overlapping slices.
 * - #each_cons: Calls the block with successive overlapping slices.
 *   (different from #each_slice).
 * - #reverse_each: Calls the block with each successive element, in reverse order.
 *
 * === Other Methods
 *
 * - #map, #collect: Returns objects returned by the block.
 * - #filter_map: Returns truthy objects returned by the block.
 * - #flat_map, #collect_concat: Returns flattened objects returned by the block.
 * - #grep: Returns elements selected by a given object
 *   or objects returned by a given block.
 * - #grep_v: Returns elements selected by a given object
 *   or objects returned by a given block.
 * - #reduce, #inject: Returns the object formed by combining all elements.
 * - #sum: Returns the sum of the elements, using method <tt>+</tt>.
 * - #zip: Combines each element with elements from other enumerables;
 *   returns the n-tuples or calls the block with each.
 * - #cycle: Calls the block with each element, cycling repeatedly.
 *
 * == Usage
 *
 * To use module \Enumerable in a collection class:
 *
 * - Include it:
 *
 *     include Enumerable
 *
 * - Implement method <tt>#each</tt>
 *   which must yield successive elements of the collection.
 *   The method will be called by almost any \Enumerable method.
 *
 * Example:
 *
 *   class Foo
 *     include Enumerable
 *     def each
 *       yield 1
 *       yield 1, 2
 *       yield
 *     end
 *   end
 *   Foo.new.each_entry{ |element| p element }
 *
 * Output:
 *
 *   1
 *   [1, 2]
 *   nil
 *
 * == \Enumerable in Ruby Classes
 *
 * These Ruby core classes include (or extend) \Enumerable:
 *
 * - ARGF
 * - Array
 * - Dir
 * - Enumerator
 * - ENV (extends)
 * - Hash
 * - IO
 * - Range
 * - Struct
 *
 * These Ruby standard library classes include \Enumerable:
 *
 * - CSV
 * - CSV::Table
 * - CSV::Row
 * - Set
 *
 * Virtually all methods in \Enumerable call method +#each+ in the including class:
 *
 * - <tt>Hash#each</tt> yields the next key-value pair as a 2-element Array.
 * - <tt>Struct#each</tt> yields the next name-value pair as a 2-element Array.
 * - For the other classes above, +#each+ yields the next object from the collection.
 *
 * == About the Examples
 *
 * The example code snippets for the \Enumerable methods:
 *
 * - Always show the use of one or more Array-like classes (often Array itself).
 * - Sometimes show the use of a Hash-like class.
 *   For some methods, though, the usage would not make sense,
 *   and so it is not shown.  Example: #tally would find exactly one of each Hash entry.
 *
 */

void
Init_Enumerable(void)
{
    rb_mEnumerable = rb_define_module("Enumerable");

    rb_define_method(rb_mEnumerable, "to_a", enum_to_a, -1);
    rb_define_method(rb_mEnumerable, "entries", enum_to_a, -1);
    rb_define_method(rb_mEnumerable, "to_h", enum_to_h, -1);

    rb_define_method(rb_mEnumerable, "sort", enum_sort, 0);
    rb_define_method(rb_mEnumerable, "sort_by", enum_sort_by, 0);
    rb_define_method(rb_mEnumerable, "grep", enum_grep, 1);
    rb_define_method(rb_mEnumerable, "grep_v", enum_grep_v, 1);
    rb_define_method(rb_mEnumerable, "count", enum_count, -1);
    rb_define_method(rb_mEnumerable, "find", enum_find, -1);
    rb_define_method(rb_mEnumerable, "detect", enum_find, -1);
    rb_define_method(rb_mEnumerable, "find_index", enum_find_index, -1);
    rb_define_method(rb_mEnumerable, "find_all", enum_find_all, 0);
    rb_define_method(rb_mEnumerable, "select", enum_find_all, 0);
    rb_define_method(rb_mEnumerable, "filter", enum_find_all, 0);
    rb_define_method(rb_mEnumerable, "filter_map", enum_filter_map, 0);
    rb_define_method(rb_mEnumerable, "reject", enum_reject, 0);
    rb_define_method(rb_mEnumerable, "collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable, "map", enum_collect, 0);
    rb_define_method(rb_mEnumerable, "flat_map", enum_flat_map, 0);
    rb_define_method(rb_mEnumerable, "collect_concat", enum_flat_map, 0);
    rb_define_method(rb_mEnumerable, "inject", enum_inject, -1);
    rb_define_method(rb_mEnumerable, "reduce", enum_inject, -1);
    rb_define_method(rb_mEnumerable, "partition", enum_partition, 0);
    rb_define_method(rb_mEnumerable, "group_by", enum_group_by, 0);
    rb_define_method(rb_mEnumerable, "tally", enum_tally, -1);
    rb_define_method(rb_mEnumerable, "first", enum_first, -1);
    rb_define_method(rb_mEnumerable, "all?", enum_all, -1);
    rb_define_method(rb_mEnumerable, "any?", enum_any, -1);
    rb_define_method(rb_mEnumerable, "one?", enum_one, -1);
    rb_define_method(rb_mEnumerable, "none?", enum_none, -1);
    rb_define_method(rb_mEnumerable, "min", enum_min, -1);
    rb_define_method(rb_mEnumerable, "max", enum_max, -1);
    rb_define_method(rb_mEnumerable, "minmax", enum_minmax, 0);
    rb_define_method(rb_mEnumerable, "min_by", enum_min_by, -1);
    rb_define_method(rb_mEnumerable, "max_by", enum_max_by, -1);
    rb_define_method(rb_mEnumerable, "minmax_by", enum_minmax_by, 0);
    rb_define_method(rb_mEnumerable, "member?", enum_member, 1);
    rb_define_method(rb_mEnumerable, "include?", enum_member, 1);
    rb_define_method(rb_mEnumerable, "each_with_index", enum_each_with_index, -1);
    rb_define_method(rb_mEnumerable, "reverse_each", enum_reverse_each, -1);
    rb_define_method(rb_mEnumerable, "each_entry", enum_each_entry, -1);
    rb_define_method(rb_mEnumerable, "each_slice", enum_each_slice, 1);
    rb_define_method(rb_mEnumerable, "each_cons", enum_each_cons, 1);
    rb_define_method(rb_mEnumerable, "each_with_object", enum_each_with_object, 1);
    rb_define_method(rb_mEnumerable, "zip", enum_zip, -1);
    rb_define_method(rb_mEnumerable, "take", enum_take, 1);
    rb_define_method(rb_mEnumerable, "take_while", enum_take_while, 0);
    rb_define_method(rb_mEnumerable, "drop", enum_drop, 1);
    rb_define_method(rb_mEnumerable, "drop_while", enum_drop_while, 0);
    rb_define_method(rb_mEnumerable, "cycle", enum_cycle, -1);
    rb_define_method(rb_mEnumerable, "chunk", enum_chunk, 0);
    rb_define_method(rb_mEnumerable, "slice_before", enum_slice_before, -1);
    rb_define_method(rb_mEnumerable, "slice_after", enum_slice_after, -1);
    rb_define_method(rb_mEnumerable, "slice_when", enum_slice_when, 0);
    rb_define_method(rb_mEnumerable, "chunk_while", enum_chunk_while, 0);
    rb_define_method(rb_mEnumerable, "sum", enum_sum, -1);
    rb_define_method(rb_mEnumerable, "uniq", enum_uniq, 0);
    rb_define_method(rb_mEnumerable, "compact", enum_compact, 0);

    id__alone = rb_intern_const("_alone");
    id__separator = rb_intern_const("_separator");
    id_chunk_categorize = rb_intern_const("chunk_categorize");
    id_chunk_enumerable = rb_intern_const("chunk_enumerable");
    id_next = rb_intern_const("next");
    id_sliceafter_enum = rb_intern_const("sliceafter_enum");
    id_sliceafter_pat = rb_intern_const("sliceafter_pat");
    id_sliceafter_pred = rb_intern_const("sliceafter_pred");
    id_slicebefore_enumerable = rb_intern_const("slicebefore_enumerable");
    id_slicebefore_sep_pat = rb_intern_const("slicebefore_sep_pat");
    id_slicebefore_sep_pred = rb_intern_const("slicebefore_sep_pred");
    id_slicewhen_enum = rb_intern_const("slicewhen_enum");
    id_slicewhen_inverted = rb_intern_const("slicewhen_inverted");
    id_slicewhen_pred = rb_intern_const("slicewhen_pred");
}
