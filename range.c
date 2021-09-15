/**********************************************************************

  range.c -

  $Author$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <assert.h>
#include <math.h>

#ifdef HAVE_FLOAT_H
#include <float.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/compar.h"
#include "internal/enum.h"
#include "internal/enumerator.h"
#include "internal/error.h"
#include "internal/numeric.h"
#include "internal/range.h"

VALUE rb_cRange;
static ID id_beg, id_end, id_excl;
#define id_cmp idCmp
#define id_succ idSucc
#define id_min idMin
#define id_max idMax

static VALUE r_cover_p(VALUE, VALUE, VALUE, VALUE);

#define RANGE_SET_BEG(r, v) (RSTRUCT_SET(r, 0, v))
#define RANGE_SET_END(r, v) (RSTRUCT_SET(r, 1, v))
#define RANGE_SET_EXCL(r, v) (RSTRUCT_SET(r, 2, v))

#define EXCL(r) RTEST(RANGE_EXCL(r))

static void
range_init(VALUE range, VALUE beg, VALUE end, VALUE exclude_end)
{
    if ((!FIXNUM_P(beg) || !FIXNUM_P(end)) && !NIL_P(beg) && !NIL_P(end)) {
	VALUE v;

	v = rb_funcall(beg, id_cmp, 1, end);
	if (NIL_P(v))
	    rb_raise(rb_eArgError, "bad value for range");
    }

    RANGE_SET_EXCL(range, exclude_end);
    RANGE_SET_BEG(range, beg);
    RANGE_SET_END(range, end);

    if (CLASS_OF(range) == rb_cRange) {
        rb_obj_freeze(range);
    }
}

VALUE
rb_range_new(VALUE beg, VALUE end, int exclude_end)
{
    VALUE range = rb_obj_alloc(rb_cRange);

    range_init(range, beg, end, RBOOL(exclude_end));
    return range;
}

static void
range_modify(VALUE range)
{
    rb_check_frozen(range);
    /* Ranges are immutable, so that they should be initialized only once. */
    if (RANGE_EXCL(range) != Qnil) {
	rb_name_err_raise("`initialize' called twice", range, ID2SYM(idInitialize));
    }
}

/*
 *  call-seq:
 *    Range.new(begin, end, exclude_end = false) -> new_range
 *
 *  Returns a new range based on the given objects +begin+ and +end+.
 *  Optional argument +exclude_end+ determines whether object +end+
 *  is included as the last object in the range:
 *
 *    Range.new(2, 5).to_a            # => [2, 3, 4, 5]
 *    Range.new(2, 5, true).to_a      # => [2, 3, 4]
 *    Range.new('a', 'd').to_a        # => ["a", "b", "c", "d"]
 *    Range.new('a', 'd', true).to_a  # => ["a", "b", "c"]
 *
 */

static VALUE
range_initialize(int argc, VALUE *argv, VALUE range)
{
    VALUE beg, end, flags;

    rb_scan_args(argc, argv, "21", &beg, &end, &flags);
    range_modify(range);
    range_init(range, beg, end, RBOOL(RTEST(flags)));
    return Qnil;
}

/* :nodoc: */
static VALUE
range_initialize_copy(VALUE range, VALUE orig)
{
    range_modify(range);
    rb_struct_init_copy(range, orig);
    return range;
}

/*
 *  call-seq:
 *     exclude_end? -> true or false
 *
 *  Returns +true+ if +self+ excludes its end value; +false+ otherwise:
 *
 *    Range.new(2, 5).exclude_end?       # => false
 *    Range.new(2, 5, true).exclude_end? # => true
 *    (2..5).exclude_end?                # => false
 *    (2...5).exclude_end?               # => true
 */

static VALUE
range_exclude_end_p(VALUE range)
{
    return RBOOL(EXCL(range));
}

static VALUE
recursive_equal(VALUE range, VALUE obj, int recur)
{
    if (recur) return Qtrue; /* Subtle! */
    if (!rb_equal(RANGE_BEG(range), RANGE_BEG(obj)))
	return Qfalse;
    if (!rb_equal(RANGE_END(range), RANGE_END(obj)))
	return Qfalse;

    return RBOOL(EXCL(range) == EXCL(obj));
}


/*
 *  call-seq:
 *    self == other -> true or false
 *
 *  Returns +true+ if and only if:
 *
 *  - +other+ is a range.
 *  - <tt>other.begin == self.begin</tt>.
 *  - <tt>other.end == self.end</tt>.
 *  - <tt>other.exclude_end? == self.include_end?</tt>.
 *
 *  Otherwise returns +false+.
 *
 *    r = (1..5)
 *    r == (1..5)                # => true
 *    r = Range.new(1, 5)
 *    r == 'foo'                 # => false
 *    r == (2..5)                # => false
 *    r == (1..4)                # => false
 *    r == (1...5)               # => false
 *    r == Range.new(1, 5, true) # => false
 *
 *  Note that even with the same argument, the return values of #== and #eql? can differ:
 *
 *    (1..2) == (1..2.0)   # => true
 *    (1..2).eql? (1..2.0) # => false
 *
 *  Related: Range#eql?.
 *
 */

static VALUE
range_eq(VALUE range, VALUE obj)
{
    if (range == obj)
	return Qtrue;
    if (!rb_obj_is_kind_of(obj, rb_cRange))
	return Qfalse;

    return rb_exec_recursive_paired(recursive_equal, range, obj, obj);
}

/* compares _a_ and _b_ and returns:
 * < 0: a < b
 * = 0: a = b
 * > 0: a > b or non-comparable
 */
static int
r_less(VALUE a, VALUE b)
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (NIL_P(r))
	return INT_MAX;
    return rb_cmpint(r, a, b);
}

static VALUE
recursive_eql(VALUE range, VALUE obj, int recur)
{
    if (recur) return Qtrue; /* Subtle! */
    if (!rb_eql(RANGE_BEG(range), RANGE_BEG(obj)))
	return Qfalse;
    if (!rb_eql(RANGE_END(range), RANGE_END(obj)))
	return Qfalse;

    return RBOOL(EXCL(range) == EXCL(obj));
}

/*
 *  call-seq:
 *    eql?(other) -> true or false
 *
 *  Returns +true+ if and only if:
 *
 *  - +other+ is a range.
 *  - <tt>other.begin eql? self.begin</tt>.
 *  - <tt>other.end eql? self.end</tt>.
 *  - <tt>other.exclude_end? == self.include_end?</tt>.
 *
 *  Otherwise returns +false+.
 *
 *    r = (1..5)
 *    r.eql?(1..5)                  # => true
 *    r = Range.new(1, 5)
 *    r.eql?('foo')                 # => false
 *    r.eql?(2..5)                  # => false
 *    r.eql?(1..4)                  # => false
 *    r.eql?(1...5)                 # => false
 *    r.eql?(Range.new(1, 5, true)) # => false
 *
 *  Note that even with the same argument, the return values of #== and #eql? can differ:
 *
 *    (1..2) == (1..2.0)   # => true
 *    (1..2).eql? (1..2.0) # => false
 *
 *  Related: Range#==.
 */

static VALUE
range_eql(VALUE range, VALUE obj)
{
    if (range == obj)
	return Qtrue;
    if (!rb_obj_is_kind_of(obj, rb_cRange))
	return Qfalse;
    return rb_exec_recursive_paired(recursive_eql, range, obj, obj);
}

/*
 * call-seq:
 *   hash -> integer
 *
 * Returns the integer hash value for +self+.
 * Two range objects +r0+ and +r1+ have the same hash value
 * if and only if <tt>r0.eql?(r1)</tt>.
 *
 * Related: Range#eql?, Object#hash.
 */

static VALUE
range_hash(VALUE range)
{
    st_index_t hash = EXCL(range);
    VALUE v;

    hash = rb_hash_start(hash);
    v = rb_hash(RANGE_BEG(range));
    hash = rb_hash_uint(hash, NUM2LONG(v));
    v = rb_hash(RANGE_END(range));
    hash = rb_hash_uint(hash, NUM2LONG(v));
    hash = rb_hash_uint(hash, EXCL(range) << 24);
    hash = rb_hash_end(hash);

    return ST2FIX(hash);
}

static void
range_each_func(VALUE range, int (*func)(VALUE, VALUE), VALUE arg)
{
    int c;
    VALUE b = RANGE_BEG(range);
    VALUE e = RANGE_END(range);
    VALUE v = b;

    if (EXCL(range)) {
	while (r_less(v, e) < 0) {
	    if ((*func)(v, arg)) break;
	    v = rb_funcallv(v, id_succ, 0, 0);
	}
    }
    else {
	while ((c = r_less(v, e)) <= 0) {
	    if ((*func)(v, arg)) break;
	    if (!c) break;
	    v = rb_funcallv(v, id_succ, 0, 0);
	}
    }
}

static int
sym_step_i(VALUE i, VALUE arg)
{
    VALUE *iter = (VALUE *)arg;

    if (FIXNUM_P(iter[0])) {
	iter[0] -= INT2FIX(1) & ~FIXNUM_FLAG;
    }
    else {
	iter[0] = rb_funcall(iter[0], '-', 1, INT2FIX(1));
    }
    if (iter[0] == INT2FIX(0)) {
	rb_yield(rb_str_intern(i));
	iter[0] = iter[1];
    }
    return 0;
}

static int
step_i(VALUE i, VALUE arg)
{
    VALUE *iter = (VALUE *)arg;

    if (FIXNUM_P(iter[0])) {
	iter[0] -= INT2FIX(1) & ~FIXNUM_FLAG;
    }
    else {
	iter[0] = rb_funcall(iter[0], '-', 1, INT2FIX(1));
    }
    if (iter[0] == INT2FIX(0)) {
	rb_yield(i);
	iter[0] = iter[1];
    }
    return 0;
}

static int
discrete_object_p(VALUE obj)
{
    if (rb_obj_is_kind_of(obj, rb_cTime)) return FALSE; /* until Time#succ removed */
    return rb_respond_to(obj, id_succ);
}

static int
linear_object_p(VALUE obj)
{
    if (FIXNUM_P(obj) || FLONUM_P(obj)) return TRUE;
    if (SPECIAL_CONST_P(obj)) return FALSE;
    switch (BUILTIN_TYPE(obj)) {
      case T_FLOAT:
      case T_BIGNUM:
	return TRUE;
      default:
        break;
    }
    if (rb_obj_is_kind_of(obj, rb_cNumeric)) return TRUE;
    if (rb_obj_is_kind_of(obj, rb_cTime)) return TRUE;
    return FALSE;
}

static VALUE
check_step_domain(VALUE step)
{
    VALUE zero = INT2FIX(0);
    int cmp;
    if (!rb_obj_is_kind_of(step, rb_cNumeric)) {
	step = rb_to_int(step);
    }
    cmp = rb_cmpint(rb_funcallv(step, idCmp, 1, &zero), step, zero);
    if (cmp < 0) {
	rb_raise(rb_eArgError, "step can't be negative");
    }
    else if (cmp == 0) {
	rb_raise(rb_eArgError, "step can't be 0");
    }
    return step;
}

static VALUE
range_step_size(VALUE range, VALUE args, VALUE eobj)
{
    VALUE b = RANGE_BEG(range), e = RANGE_END(range);
    VALUE step = INT2FIX(1);
    if (args) {
	step = check_step_domain(RARRAY_AREF(args, 0));
    }

    if (rb_obj_is_kind_of(b, rb_cNumeric) && rb_obj_is_kind_of(e, rb_cNumeric)) {
	return ruby_num_interval_step_size(b, e, step, EXCL(range));
    }
    return Qnil;
}

/*
 *  call-seq:
 *    step(n = 1) {|element| ... } -> self
 *    step(n = 1)                  -> enumerator
 *
 *  Iterates over the elements of +self+.
 *
 *  With a block given and no argument,
 *  calls the block each element of the range; returns +self+:
 *
 *    a = []
 *    (1..5).step {|element| a.push(element) } # => 1..5
 *    a # => [1, 2, 3, 4, 5]
 *    a = []
 *    ('a'..'e').step {|element| a.push(element) } # => "a".."e"
 *    a # => ["a", "b", "c", "d", "e"]
 *
 *  With a block given and a positive integer argument +n+ given,
 *  calls the block with element +0+, element +n+, element <tt>2n</tt>, and so on:
 *
 *    a = []
 *    (1..5).step(2) {|element| a.push(element) } # => 1..5
 *    a # => [1, 3, 5]
 *    a = []
 *    ('a'..'e').step(2) {|element| a.push(element) } # => "a".."e"
 *    a # => ["a", "c", "e"]
 *
 *  With no block given, returns an enumerator,
 *  which will be of class Enumerator::ArithmeticSequence if +self+ is numeric;
 *  otherwise of class Enumerator:
 *
 *    e = (1..5).step(2) # => ((1..5).step(2))
 *    e.class            # => Enumerator::ArithmeticSequence
 *    ('a'..'e').step # => #<Enumerator: ...>
 *
 */


static VALUE
range_step(int argc, VALUE *argv, VALUE range)
{
    VALUE b, e, step, tmp;

    b = RANGE_BEG(range);
    e = RANGE_END(range);
    step = (!rb_check_arity(argc, 0, 1) ? INT2FIX(1) : argv[0]);

    if (!rb_block_given_p()) {
        if (!rb_obj_is_kind_of(step, rb_cNumeric)) {
            step = rb_to_int(step);
        }
        if (rb_equal(step, INT2FIX(0))) {
            rb_raise(rb_eArgError, "step can't be 0");
        }

        const VALUE b_num_p = rb_obj_is_kind_of(b, rb_cNumeric);
        const VALUE e_num_p = rb_obj_is_kind_of(e, rb_cNumeric);
        if ((b_num_p && (NIL_P(e) || e_num_p)) || (NIL_P(b) && e_num_p)) {
            return rb_arith_seq_new(range, ID2SYM(rb_frame_this_func()), argc, argv,
                    range_step_size, b, e, step, EXCL(range));
        }

        RETURN_SIZED_ENUMERATOR(range, argc, argv, range_step_size);
    }

    step = check_step_domain(step);

    if (FIXNUM_P(b) && NIL_P(e) && FIXNUM_P(step)) {
	long i = FIX2LONG(b), unit = FIX2LONG(step);
	do {
	    rb_yield(LONG2FIX(i));
	    i += unit;          /* FIXABLE+FIXABLE never overflow */
	} while (FIXABLE(i));
	b = LONG2NUM(i);

	for (;; b = rb_big_plus(b, step))
	    rb_yield(b);
    }
    else if (FIXNUM_P(b) && FIXNUM_P(e) && FIXNUM_P(step)) { /* fixnums are special */
	long end = FIX2LONG(e);
	long i, unit = FIX2LONG(step);

	if (!EXCL(range))
	    end += 1;
	i = FIX2LONG(b);
	while (i < end) {
	    rb_yield(LONG2NUM(i));
	    if (i + unit < i) break;
	    i += unit;
	}

    }
    else if (SYMBOL_P(b) && (NIL_P(e) || SYMBOL_P(e))) { /* symbols are special */
	VALUE iter[2];
	iter[0] = INT2FIX(1);
	iter[1] = step;

	b = rb_sym2str(b);
	if (NIL_P(e)) {
	    rb_str_upto_endless_each(b, sym_step_i, (VALUE)iter);
	}
	else {
	    rb_str_upto_each(b, rb_sym2str(e), EXCL(range), sym_step_i, (VALUE)iter);
	}
    }
    else if (ruby_float_step(b, e, step, EXCL(range), TRUE)) {
	/* done */
    }
    else if (rb_obj_is_kind_of(b, rb_cNumeric) ||
	     !NIL_P(rb_check_to_integer(b, "to_int")) ||
	     !NIL_P(rb_check_to_integer(e, "to_int"))) {
	ID op = EXCL(range) ? '<' : idLE;
	VALUE v = b;
	int i = 0;

	while (NIL_P(e) || RTEST(rb_funcall(v, op, 1, e))) {
	    rb_yield(v);
	    i++;
	    v = rb_funcall(b, '+', 1, rb_funcall(INT2NUM(i), '*', 1, step));
	}
    }
    else {
	tmp = rb_check_string_type(b);

	if (!NIL_P(tmp)) {
	    VALUE iter[2];

	    b = tmp;
	    iter[0] = INT2FIX(1);
	    iter[1] = step;

	    if (NIL_P(e)) {
		rb_str_upto_endless_each(b, step_i, (VALUE)iter);
	    }
	    else {
		rb_str_upto_each(b, e, EXCL(range), step_i, (VALUE)iter);
	    }
	}
	else {
	    VALUE args[2];

	    if (!discrete_object_p(b)) {
		rb_raise(rb_eTypeError, "can't iterate from %s",
			 rb_obj_classname(b));
	    }
	    args[0] = INT2FIX(1);
	    args[1] = step;
	    range_each_func(range, step_i, (VALUE)args);
	}
    }
    return range;
}

static VALUE
range_percent_step(VALUE range, VALUE step)
{
    return range_step(1, &step, range);
}

#if SIZEOF_DOUBLE == 8 && defined(HAVE_INT64_T)
union int64_double {
    int64_t i;
    double d;
};

static VALUE
int64_as_double_to_num(int64_t i)
{
    union int64_double convert;
    if (i < 0) {
	convert.i = -i;
	return DBL2NUM(-convert.d);
    }
    else {
	convert.i = i;
	return DBL2NUM(convert.d);
    }
}

static int64_t
double_as_int64(double d)
{
    union int64_double convert;
    convert.d = fabs(d);
    return d < 0 ? -convert.i : convert.i;
}
#endif

static int
is_integer_p(VALUE v)
{
    ID id_integer_p;
    VALUE is_int;
    CONST_ID(id_integer_p, "integer?");
    is_int = rb_check_funcall(v, id_integer_p, 0, 0);
    return RTEST(is_int) && is_int != Qundef;
}

static VALUE
bsearch_integer_range(VALUE beg, VALUE end, int excl)
{
    VALUE satisfied = Qnil;
    int smaller;

#define BSEARCH_CHECK(expr) \
    do { \
	VALUE val = (expr); \
	VALUE v = rb_yield(val); \
	if (FIXNUM_P(v)) { \
	    if (v == INT2FIX(0)) return val; \
	    smaller = (SIGNED_VALUE)v < 0; \
	} \
	else if (v == Qtrue) { \
	    satisfied = val; \
	    smaller = 1; \
	} \
	else if (v == Qfalse || v == Qnil) { \
	    smaller = 0; \
	} \
	else if (rb_obj_is_kind_of(v, rb_cNumeric)) { \
	    int cmp = rb_cmpint(rb_funcall(v, id_cmp, 1, INT2FIX(0)), v, INT2FIX(0)); \
	    if (!cmp) return val; \
	    smaller = cmp < 0; \
	} \
	else { \
	    rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE \
		     " (must be numeric, true, false or nil)", \
		     rb_obj_class(v)); \
	} \
    } while (0)

    VALUE low = rb_to_int(beg);
    VALUE high = rb_to_int(end);
    VALUE mid, org_high;
    ID id_div;
    CONST_ID(id_div, "div");

    if (excl) high = rb_funcall(high, '-', 1, INT2FIX(1));
    org_high = high;

    while (rb_cmpint(rb_funcall(low, id_cmp, 1, high), low, high) < 0) {
	mid = rb_funcall(rb_funcall(high, '+', 1, low), id_div, 1, INT2FIX(2));
	BSEARCH_CHECK(mid);
	if (smaller) {
	    high = mid;
	}
	else {
	    low = rb_funcall(mid, '+', 1, INT2FIX(1));
	}
    }
    if (rb_equal(low, org_high)) {
	BSEARCH_CHECK(low);
	if (!smaller) return Qnil;
    }
    return satisfied;
}

/*
 *  call-seq:
 *     bsearch {|obj| block }  -> value
 *
 *  Returns an element from +self+ selected by a binary search.
 *
 *  See {Binary Searching}[rdoc-ref:bsearch.rdoc].
 *
 */

static VALUE
range_bsearch(VALUE range)
{
    VALUE beg, end, satisfied = Qnil;
    int smaller;

    /* Implementation notes:
     * Floats are handled by mapping them to 64 bits integers.
     * Apart from sign issues, floats and their 64 bits integer have the
     * same order, assuming they are represented as exponent followed
     * by the mantissa. This is true with or without implicit bit.
     *
     * Finding the average of two ints needs to be careful about
     * potential overflow (since float to long can use 64 bits)
     * as well as the fact that -1/2 can be 0 or -1 in C89.
     *
     * Note that -0.0 is mapped to the same int as 0.0 as we don't want
     * (-1...0.0).bsearch to yield -0.0.
     */

#define BSEARCH(conv) \
    do { \
	RETURN_ENUMERATOR(range, 0, 0); \
	if (EXCL(range)) high--; \
	org_high = high; \
	while (low < high) { \
	    mid = ((high < 0) == (low < 0)) ? low + ((high - low) / 2) \
		: (low < -high) ? -((-1 - low - high)/2 + 1) : (low + high) / 2; \
	    BSEARCH_CHECK(conv(mid)); \
	    if (smaller) { \
		high = mid; \
	    } \
	    else { \
		low = mid + 1; \
	    } \
	} \
	if (low == org_high) { \
	    BSEARCH_CHECK(conv(low)); \
	    if (!smaller) return Qnil; \
	} \
	return satisfied; \
    } while (0)


    beg = RANGE_BEG(range);
    end = RANGE_END(range);

    if (FIXNUM_P(beg) && FIXNUM_P(end)) {
	long low = FIX2LONG(beg);
	long high = FIX2LONG(end);
	long mid, org_high;
	BSEARCH(INT2FIX);
    }
#if SIZEOF_DOUBLE == 8 && defined(HAVE_INT64_T)
    else if (RB_FLOAT_TYPE_P(beg) || RB_FLOAT_TYPE_P(end)) {
	int64_t low  = double_as_int64(NIL_P(beg) ? -HUGE_VAL : RFLOAT_VALUE(rb_Float(beg)));
	int64_t high = double_as_int64(NIL_P(end) ?  HUGE_VAL : RFLOAT_VALUE(rb_Float(end)));
	int64_t mid, org_high;
	BSEARCH(int64_as_double_to_num);
    }
#endif
    else if (is_integer_p(beg) && is_integer_p(end)) {
	RETURN_ENUMERATOR(range, 0, 0);
	return bsearch_integer_range(beg, end, EXCL(range));
    }
    else if (is_integer_p(beg) && NIL_P(end)) {
	VALUE diff = LONG2FIX(1);
	RETURN_ENUMERATOR(range, 0, 0);
	while (1) {
	    VALUE mid = rb_funcall(beg, '+', 1, diff);
	    BSEARCH_CHECK(mid);
	    if (smaller) {
		return bsearch_integer_range(beg, mid, 0);
	    }
	    diff = rb_funcall(diff, '*', 1, LONG2FIX(2));
	}
    }
    else if (NIL_P(beg) && is_integer_p(end)) {
	VALUE diff = LONG2FIX(-1);
	RETURN_ENUMERATOR(range, 0, 0);
	while (1) {
	    VALUE mid = rb_funcall(end, '+', 1, diff);
	    BSEARCH_CHECK(mid);
	    if (!smaller) {
		return bsearch_integer_range(mid, end, 0);
	    }
	    diff = rb_funcall(diff, '*', 1, LONG2FIX(2));
	}
    }
    else {
	rb_raise(rb_eTypeError, "can't do binary search for %s", rb_obj_classname(beg));
    }
    return range;
}

static int
each_i(VALUE v, VALUE arg)
{
    rb_yield(v);
    return 0;
}

static int
sym_each_i(VALUE v, VALUE arg)
{
    return each_i(rb_str_intern(v), arg);
}

/*
 *  call-seq:
 *    size -> non_negative_integer or Infinity or nil
 *
 *  Returns the count of elements in +self+
 *  if both begin and end values are numeric;
 *  otherwise, returns +nil+:
 *
 *    (1..4).size      # => 4
 *    (1...4).size     # => 3
 *    (1..).size       # => Infinity
 *    ('a'..'z').size  #=> nil
 */

static VALUE
range_size(VALUE range)
{
    VALUE b = RANGE_BEG(range), e = RANGE_END(range);
    if (rb_obj_is_kind_of(b, rb_cNumeric)) {
        if (rb_obj_is_kind_of(e, rb_cNumeric)) {
	    return ruby_num_interval_step_size(b, e, INT2FIX(1), EXCL(range));
        }
        if (NIL_P(e)) {
            return DBL2NUM(HUGE_VAL);
        }
    }
    else if (NIL_P(b)) {
        return DBL2NUM(HUGE_VAL);
    }

    return Qnil;
}

/*
 *  call-seq:
 *    to_a -> array
 *
 *  Returns an array containing the elements in +self+, if a finite collection;
 *  raises an exception otherwise.
 *
 *    (1..4).to_a     # => [1, 2, 3, 4]
 *    (1...4).to_a    # => [1, 2, 3]
 *    ('a'..'d').to_a # => ["a", "b", "c", "d"]
 *
 *  Range#entries is an alias for Range#to_a.
 */

static VALUE
range_to_a(VALUE range)
{
    if (NIL_P(RANGE_END(range))) {
	rb_raise(rb_eRangeError, "cannot convert endless range to an array");
    }
    return rb_call_super(0, 0);
}

static VALUE
range_enum_size(VALUE range, VALUE args, VALUE eobj)
{
    return range_size(range);
}

RBIMPL_ATTR_NORETURN()
static void
range_each_bignum_endless(VALUE beg)
{
    for (;; beg = rb_big_plus(beg, INT2FIX(1))) {
        rb_yield(beg);
    }
    UNREACHABLE;
}

RBIMPL_ATTR_NORETURN()
static void
range_each_fixnum_endless(VALUE beg)
{
    for (long i = FIX2LONG(beg); FIXABLE(i); i++) {
        rb_yield(LONG2FIX(i));
    }

    range_each_bignum_endless(LONG2NUM(RUBY_FIXNUM_MAX + 1));
    UNREACHABLE;
}

static VALUE
range_each_fixnum_loop(VALUE beg, VALUE end, VALUE range)
{
    long lim = FIX2LONG(end) + !EXCL(range);
    for (long i = FIX2LONG(beg); i < lim; i++) {
        rb_yield(LONG2FIX(i));
    }
    return range;
}

/*
 *  call-seq:
 *    each {|element| ... } -> self
 *    each                  -> an_enumerator
 *
 *  With a block given, passes each element of +self+ to the block:
 *
 *    a = []
 *    (1..4).each {|element| a.push(element) } # => 1..4
 *    a # => [1, 2, 3, 4]
 *
 *  Raises an exception unless <tt>self.first.respond_to?(:succ)</tt>.
 *
 *  With no block given, returns an enumerator.
 *
 */

static VALUE
range_each(VALUE range)
{
    VALUE beg, end;
    long i;

    RETURN_SIZED_ENUMERATOR(range, 0, 0, range_enum_size);

    beg = RANGE_BEG(range);
    end = RANGE_END(range);

    if (FIXNUM_P(beg) && NIL_P(end)) {
        range_each_fixnum_endless(beg);
    }
    else if (FIXNUM_P(beg) && FIXNUM_P(end)) { /* fixnums are special */
        return range_each_fixnum_loop(beg, end, range);
    }
    else if (RB_INTEGER_TYPE_P(beg) && (NIL_P(end) || RB_INTEGER_TYPE_P(end))) {
	if (SPECIAL_CONST_P(end) || RBIGNUM_POSITIVE_P(end)) { /* end >= FIXNUM_MIN */
	    if (!FIXNUM_P(beg)) {
		if (RBIGNUM_NEGATIVE_P(beg)) {
		    do {
			rb_yield(beg);
		    } while (!FIXNUM_P(beg = rb_big_plus(beg, INT2FIX(1))));
                    if (NIL_P(end)) range_each_fixnum_endless(beg);
                    if (FIXNUM_P(end)) return range_each_fixnum_loop(beg, end, range);
		}
		else {
                    if (NIL_P(end)) range_each_bignum_endless(beg);
		    if (FIXNUM_P(end)) return range;
		}
	    }
	    if (FIXNUM_P(beg)) {
		i = FIX2LONG(beg);
		do {
		    rb_yield(LONG2FIX(i));
		} while (POSFIXABLE(++i));
		beg = LONG2NUM(i);
	    }
	    ASSUME(!FIXNUM_P(beg));
	    ASSUME(!SPECIAL_CONST_P(end));
	}
	if (!FIXNUM_P(beg) && RBIGNUM_SIGN(beg) == RBIGNUM_SIGN(end)) {
	    if (EXCL(range)) {
		while (rb_big_cmp(beg, end) == INT2FIX(-1)) {
		    rb_yield(beg);
		    beg = rb_big_plus(beg, INT2FIX(1));
		}
	    }
	    else {
		VALUE c;
		while ((c = rb_big_cmp(beg, end)) != INT2FIX(1)) {
		    rb_yield(beg);
		    if (c == INT2FIX(0)) break;
		    beg = rb_big_plus(beg, INT2FIX(1));
		}
	    }
	}
    }
    else if (SYMBOL_P(beg) && (NIL_P(end) || SYMBOL_P(end))) { /* symbols are special */
	beg = rb_sym2str(beg);
	if (NIL_P(end)) {
	    rb_str_upto_endless_each(beg, sym_each_i, 0);
	}
	else {
	    rb_str_upto_each(beg, rb_sym2str(end), EXCL(range), sym_each_i, 0);
	}
    }
    else {
	VALUE tmp = rb_check_string_type(beg);

	if (!NIL_P(tmp)) {
	    if (!NIL_P(end)) {
		rb_str_upto_each(tmp, end, EXCL(range), each_i, 0);
	    }
	    else {
		rb_str_upto_endless_each(tmp, each_i, 0);
	    }
	}
	else {
	    if (!discrete_object_p(beg)) {
		rb_raise(rb_eTypeError, "can't iterate from %s",
			 rb_obj_classname(beg));
	    }
	    if (!NIL_P(end))
		range_each_func(range, each_i, 0);
	    else
		for (;; beg = rb_funcallv(beg, id_succ, 0, 0))
		    rb_yield(beg);
	}
    }
    return range;
}

/*
 *  call-seq:
 *    self.begin -> object
 *
 *  Returns the object that defines the beginning of +self+.
 *
 *    (1..4).begin # => 1
 *    (..2).begin  # => nil
 *
 *  Related: Range#first, Range#end.
 */

static VALUE
range_begin(VALUE range)
{
    return RANGE_BEG(range);
}


/*
 *  call-seq:
 *    self.end -> object
 *
 *  Returns the object that defines the end of +self+.
 *
 *    (1..4).end  # => 4
 *    (1...4).end # => 4
 *    (1..).end   # => nil
 *
 *  Related: Range#begin, Range#last.
 */


static VALUE
range_end(VALUE range)
{
    return RANGE_END(range);
}


static VALUE
first_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, cbarg))
{
    VALUE *ary = (VALUE *)cbarg;
    long n = NUM2LONG(ary[0]);

    if (n <= 0) {
	rb_iter_break();
    }
    rb_ary_push(ary[1], i);
    n--;
    ary[0] = LONG2NUM(n);
    return Qnil;
}

/*
 *  call-seq:
 *    first -> object
 *    first(n) -> array
 *
 *  With no argument, returns the first element of +self+, if it exists:
 *
 *    (1..4).first     # => 1
 *    ('a'..'d').first # => "a"
 *
 *  With non-negative integer argument +n+ given,
 *  returns the first +n+ elements in an array:
 *
 *    (1..10).first(3) # => [1, 2, 3]
 *    (1..10).first(0) # => []
 *    (1..4).first(50) # => [1, 2, 3, 4]
 *
 *  Raises an exception if there is no first element:
 *
 *    (..4).first # Raises RangeError
 */

static VALUE
range_first(int argc, VALUE *argv, VALUE range)
{
    VALUE n, ary[2];

    if (NIL_P(RANGE_BEG(range))) {
        rb_raise(rb_eRangeError, "cannot get the first element of beginless range");
    }
    if (argc == 0) return RANGE_BEG(range);

    rb_scan_args(argc, argv, "1", &n);
    ary[0] = n;
    ary[1] = rb_ary_new2(NUM2LONG(n));
    rb_block_call(range, idEach, 0, 0, first_i, (VALUE)ary);

    return ary[1];
}

static VALUE
rb_int_range_last(int argc, VALUE *argv, VALUE range)
{
    static const VALUE ONE = INT2FIX(1);

    VALUE b, e, len_1, len, nv, ary;
    int x;
    long n;

    assert(argc > 0);

    b = RANGE_BEG(range);
    e = RANGE_END(range);
    assert(RB_INTEGER_TYPE_P(b) && RB_INTEGER_TYPE_P(e));

    x = EXCL(range);

    len_1 = rb_int_minus(e, b);
    if (FIXNUM_ZERO_P(len_1) || rb_num_negative_p(len_1)) {
        return rb_ary_new_capa(0);
    }

    if (x) {
        e = rb_int_minus(e, ONE);
        len = len_1;
    }
    else {
        len = rb_int_plus(len_1, ONE);
    }

    rb_scan_args(argc, argv, "1", &nv);
    n = NUM2LONG(nv);
    if (n < 0) {
        rb_raise(rb_eArgError, "negative array size");
    }

    nv = LONG2NUM(n);
    if (RTEST(rb_int_gt(nv, len))) {
        nv = len;
        n = NUM2LONG(nv);
    }

    ary = rb_ary_new_capa(n);
    b = rb_int_minus(e, nv);
    while (n) {
        b = rb_int_plus(b, ONE);
        rb_ary_push(ary, b);
        --n;
    }

    return ary;
}

/*
 *  call-seq:
 *    last -> object
 *    last(n) -> array
 *
 *  With no argument, returns the last element of +self+, if it exists:
 *
 *    (1..4).last     # => 4
 *    ('a'..'d').last # => "d"
 *
 *  Note that +last+ with no argument returns the end element of +self+
 *  even if #exclude_end? is +true+:
 *
 *    (1...4).last     # => 4
 *    ('a'...'d').last # => "d"
 *
 *  With non-negative integer argument +n+ given,
 *  returns the last +n+ elements in an array:
 *
 *    (1..10).last(3) # => [8, 9, 10]
 *    (1..10).last(0) # => []
 *    (1..4).last(50) # => [1, 2, 3, 4]
 *
 *  Note that +last+ with argument does not return the end element of +self+
 *  if #exclude_end? it +true+:
 *
 *    (1...4).last(3)     # => [1, 2, 3]
 *    ('a'...'d').last(3) # => ["a", "b", "c"]
 *
 *  Raises an exception if there is no last element:
 *
 *    (1..).last # Raises RangeError
 *
 */

static VALUE
range_last(int argc, VALUE *argv, VALUE range)
{
    VALUE b, e;

    if (NIL_P(RANGE_END(range))) {
        rb_raise(rb_eRangeError, "cannot get the last element of endless range");
    }
    if (argc == 0) return RANGE_END(range);

    b = RANGE_BEG(range);
    e = RANGE_END(range);
    if (RB_INTEGER_TYPE_P(b) && RB_INTEGER_TYPE_P(e) &&
        RB_LIKELY(rb_method_basic_definition_p(rb_cRange, idEach))) {
        return rb_int_range_last(argc, argv, range);
    }
    return rb_ary_last(argc, argv, rb_Array(range));
}


/*
 *  call-seq:
 *     rng.min                       -> obj
 *     rng.min {| a,b | block }      -> obj
 *     rng.min(n)                    -> array
 *     rng.min(n) {| a,b | block }   -> array
 *
 *  Returns the minimum value in the range. Returns +nil+ if the begin
 *  value of the range is larger than the end value. Returns +nil+ if
 *  the begin value of an exclusive range is equal to the end value.
 *
 *  Can be given an optional block to override the default comparison
 *  method <code>a <=> b</code>.
 *
 *    (10..20).min    #=> 10
 */


static VALUE
range_min(int argc, VALUE *argv, VALUE range)
{
    if (NIL_P(RANGE_BEG(range))) {
	rb_raise(rb_eRangeError, "cannot get the minimum of beginless range");
    }

    if (rb_block_given_p()) {
        if (NIL_P(RANGE_END(range))) {
            rb_raise(rb_eRangeError, "cannot get the minimum of endless range with custom comparison method");
        }
	return rb_call_super(argc, argv);
    }
    else if (argc != 0) {
	return range_first(argc, argv, range);
    }
    else {
	struct cmp_opt_data cmp_opt = { 0, 0 };
	VALUE b = RANGE_BEG(range);
	VALUE e = RANGE_END(range);
	int c = NIL_P(e) ? -1 : OPTIMIZED_CMP(b, e, cmp_opt);

	if (c > 0 || (c == 0 && EXCL(range)))
	    return Qnil;
	return b;
    }
}

/*
 *  call-seq:
 *     rng.max                       -> obj
 *     rng.max {| a,b | block }      -> obj
 *     rng.max(n)                    -> obj
 *     rng.max(n) {| a,b | block }   -> obj
 *
 *  Returns the maximum value in the range, or an array of maximum
 *  values in the range if given an \Integer argument.
 *
 *  For inclusive ranges with an end, the maximum value of the range
 *  is the same as the end of the range.
 *
 *  If an argument or block is given, or +self+ is an exclusive,
 *  non-numeric range, calls Enumerable#max (via +super+) with the
 *  argument and/or block to get the maximum values, unless +self+ is
 *  a beginless range, in which case it raises a RangeError.
 *
 *  If +self+ is an exclusive, integer range (both start and end of the
 *  range are integers), and no arguments or block are provided, returns
 *  last value in the range (1 before the end).  Otherwise, if +self+ is
 *  an exclusive, numeric range, raises a TypeError.
 *
 *  Returns +nil+ if the begin value of the range larger than the
 *  end value. Returns +nil+ if the begin value of an exclusive
 *  range is equal to the end value.  Raises a RangeError if called on
 *  an endless range.
 *
 *  Examples:
 *    (10..20).max                        #=> 20
 *    (10..20).max(2)                     #=> [20, 19]
 *    (10...20).max                       #=> 19
 *    (10...20).max(2)                    #=> [19, 18]
 *    (10...20).max{|x, y| -x <=> -y }    #=> 10
 *    (10...20).max(2){|x, y| -x <=> -y } #=> [10, 11]
 */

static VALUE
range_max(int argc, VALUE *argv, VALUE range)
{
    VALUE e = RANGE_END(range);
    int nm = FIXNUM_P(e) || rb_obj_is_kind_of(e, rb_cNumeric);

    if (NIL_P(RANGE_END(range))) {
	rb_raise(rb_eRangeError, "cannot get the maximum of endless range");
    }

    VALUE b = RANGE_BEG(range);

    if (rb_block_given_p() || (EXCL(range) && !nm) || argc) {
        if (NIL_P(b)) {
            rb_raise(rb_eRangeError, "cannot get the maximum of beginless range with custom comparison method");
        }
        return rb_call_super(argc, argv);
    }
    else {
        struct cmp_opt_data cmp_opt = { 0, 0 };
        int c = NIL_P(b) ? -1 : OPTIMIZED_CMP(b, e, cmp_opt);

        if (c > 0)
            return Qnil;
        if (EXCL(range)) {
            if (!RB_INTEGER_TYPE_P(e)) {
                rb_raise(rb_eTypeError, "cannot exclude non Integer end value");
            }
            if (c == 0) return Qnil;
            if (!RB_INTEGER_TYPE_P(b)) {
                rb_raise(rb_eTypeError, "cannot exclude end value with non Integer begin value");
            }
            if (FIXNUM_P(e)) {
                return LONG2NUM(FIX2LONG(e) - 1);
            }
            return rb_funcall(e, '-', 1, INT2FIX(1));
        }
        return e;
    }
}

/*
 *  call-seq:
 *     rng.minmax                       -> [obj, obj]
 *     rng.minmax {| a,b | block }      -> [obj, obj]
 *
 *  Returns a two element array which contains the minimum and the
 *  maximum value in the range.
 *
 *  Can be given an optional block to override the default comparison
 *  method <code>a <=> b</code>.
 */

static VALUE
range_minmax(VALUE range)
{
    if (rb_block_given_p()) {
        return rb_call_super(0, NULL);
    }
    return rb_assoc_new(
        rb_funcall(range, id_min, 0),
        rb_funcall(range, id_max, 0)
    );
}

int
rb_range_values(VALUE range, VALUE *begp, VALUE *endp, int *exclp)
{
    VALUE b, e;
    int excl;

    if (rb_obj_is_kind_of(range, rb_cRange)) {
	b = RANGE_BEG(range);
	e = RANGE_END(range);
	excl = EXCL(range);
    }
    else if (RTEST(rb_obj_is_kind_of(range, rb_cArithSeq))) {
        return (int)Qfalse;
    }
    else {
	VALUE x;
	b = rb_check_funcall(range, id_beg, 0, 0);
	if (b == Qundef) return (int)Qfalse;
	e = rb_check_funcall(range, id_end, 0, 0);
	if (e == Qundef) return (int)Qfalse;
	x = rb_check_funcall(range, rb_intern("exclude_end?"), 0, 0);
	if (x == Qundef) return (int)Qfalse;
	excl = RTEST(x);
    }
    *begp = b;
    *endp = e;
    *exclp = excl;
    return (int)Qtrue;
}

/* Extract the components of a Range.
 *
 * You can use +err+ to control the behavior of out-of-range and exception.
 *
 * When +err+ is 0 or 2, if the begin offset is greater than +len+,
 * it is out-of-range.  The +RangeError+ is raised only if +err+ is 2,
 * in this case.  If +err+ is 0, +Qnil+ will be returned.
 *
 * When +err+ is 1, the begin and end offsets won't be adjusted even if they
 * are greater than +len+.  It allows +rb_ary_aset+ extends arrays.
 *
 * If the begin component of the given range is negative and is too-large
 * abstract value, the +RangeError+ is raised only +err+ is 1 or 2.
 *
 * The case of <code>err = 0</code> is used in item accessing methods such as
 * +rb_ary_aref+, +rb_ary_slice_bang+, and +rb_str_aref+.
 *
 * The case of <code>err = 1</code> is used in Array's methods such as
 * +rb_ary_aset+ and +rb_ary_fill+.
 *
 * The case of <code>err = 2</code> is used in +rb_str_aset+.
 */
VALUE
rb_range_component_beg_len(VALUE b, VALUE e, int excl,
                           long *begp, long *lenp, long len, int err)
{
    long beg, end;

    beg = NIL_P(b) ? 0 : NUM2LONG(b);
    end = NIL_P(e) ? -1 : NUM2LONG(e);
    if (NIL_P(e)) excl = 0;
    if (beg < 0) {
        beg += len;
        if (beg < 0)
            goto out_of_range;
    }
    if (end < 0)
        end += len;
    if (!excl)
        end++;			/* include end point */
    if (err == 0 || err == 2) {
        if (beg > len)
            goto out_of_range;
        if (end > len)
            end = len;
    }
    len = end - beg;
    if (len < 0)
        len = 0;

    *begp = beg;
    *lenp = len;
    return Qtrue;

  out_of_range:
    return Qnil;
}

VALUE
rb_range_beg_len(VALUE range, long *begp, long *lenp, long len, int err)
{
    VALUE b, e;
    int excl;

    if (!rb_range_values(range, &b, &e, &excl))
        return Qfalse;

    VALUE res = rb_range_component_beg_len(b, e, excl, begp, lenp, len, err);
    if (NIL_P(res) && err) {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" out of range", range);
    }

    return res;
}

/*
 * call-seq:
 *   rng.to_s   -> string
 *
 * Convert this range object to a printable form (using #to_s to convert the
 * begin and end objects).
 */

static VALUE
range_to_s(VALUE range)
{
    VALUE str, str2;

    str = rb_obj_as_string(RANGE_BEG(range));
    str2 = rb_obj_as_string(RANGE_END(range));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range) ? 3 : 2);
    rb_str_append(str, str2);

    return str;
}

static VALUE
inspect_range(VALUE range, VALUE dummy, int recur)
{
    VALUE str, str2 = Qundef;

    if (recur) {
	return rb_str_new2(EXCL(range) ? "(... ... ...)" : "(... .. ...)");
    }
    if (!NIL_P(RANGE_BEG(range)) || NIL_P(RANGE_END(range))) {
        str = rb_str_dup(rb_inspect(RANGE_BEG(range)));
    }
    else {
        str = rb_str_new(0, 0);
    }
    rb_str_cat(str, "...", EXCL(range) ? 3 : 2);
    if (NIL_P(RANGE_BEG(range)) || !NIL_P(RANGE_END(range))) {
        str2 = rb_inspect(RANGE_END(range));
    }
    if (str2 != Qundef) rb_str_append(str, str2);

    return str;
}

/*
 * call-seq:
 *   rng.inspect  -> string
 *
 * Convert this range object to a printable form (using #inspect to
 * convert the begin and end objects).
 */


static VALUE
range_inspect(VALUE range)
{
    return rb_exec_recursive(inspect_range, range, 0);
}

static VALUE range_include_internal(VALUE range, VALUE val, int string_use_cover);

/*
 *  call-seq:
 *     rng === obj       ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is between begin and end of range,
 *  <code>false</code> otherwise (same as #cover?). Conveniently,
 *  <code>===</code> is the comparison operator used by <code>case</code>
 *  statements.
 *
 *     case 79
 *     when 1..50   then   puts "low"
 *     when 51..75  then   puts "medium"
 *     when 76..100 then   puts "high"
 *     end
 *     # Prints "high"
 *
 *     case "2.6.5"
 *     when ..."2.4" then puts "EOL"
 *     when "2.4"..."2.5" then puts "maintenance"
 *     when "2.5"..."2.7" then puts "stable"
 *     when "2.7".. then puts "upcoming"
 *     end
 *     # Prints "stable"
 *
 */

static VALUE
range_eqq(VALUE range, VALUE val)
{
    VALUE ret = range_include_internal(range, val, 1);
    if (ret != Qundef) return ret;
    return r_cover_p(range, RANGE_BEG(range), RANGE_END(range), val);
}


/*
 *  call-seq:
 *     rng.member?(obj)  ->  true or false
 *     rng.include?(obj) ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is an element of
 *  the range, <code>false</code> otherwise.
 *
 *     ("a".."z").include?("g")   #=> true
 *     ("a".."z").include?("A")   #=> false
 *     ("a".."z").include?("cc")  #=> false
 *
 *  If you need to ensure +obj+ is between +begin+ and +end+, use #cover?
 *
 *     ("a".."z").cover?("cc")  #=> true
 *
 *  If begin and end are numeric, #include? behaves like #cover?
 *
 *     (1..3).include?(1.5) # => true
 */

static VALUE
range_include(VALUE range, VALUE val)
{
    VALUE ret = range_include_internal(range, val, 0);
    if (ret != Qundef) return ret;
    return rb_call_super(1, &val);
}

static VALUE
range_include_internal(VALUE range, VALUE val, int string_use_cover)
{
    VALUE beg = RANGE_BEG(range);
    VALUE end = RANGE_END(range);
    int nv = FIXNUM_P(beg) || FIXNUM_P(end) ||
	     linear_object_p(beg) || linear_object_p(end);

    if (nv ||
	!NIL_P(rb_check_to_integer(beg, "to_int")) ||
	!NIL_P(rb_check_to_integer(end, "to_int"))) {
	return r_cover_p(range, beg, end, val);
    }
    else if (RB_TYPE_P(beg, T_STRING) || RB_TYPE_P(end, T_STRING)) {
        if (RB_TYPE_P(beg, T_STRING) && RB_TYPE_P(end, T_STRING)) {
            if (string_use_cover) {
                return r_cover_p(range, beg, end, val);
            }
            else {
                VALUE rb_str_include_range_p(VALUE beg, VALUE end, VALUE val, VALUE exclusive);
                return rb_str_include_range_p(beg, end, val, RANGE_EXCL(range));
            }
        }
        else if (NIL_P(beg)) {
	    VALUE r = rb_funcall(val, id_cmp, 1, end);
	    if (NIL_P(r)) return Qfalse;
	    if (rb_cmpint(r, val, end) <= 0) return Qtrue;
	    return Qfalse;
        }
	else if (NIL_P(end)) {
	    VALUE r = rb_funcall(beg, id_cmp, 1, val);
	    if (NIL_P(r)) return Qfalse;
	    if (rb_cmpint(r, beg, val) <= 0) return Qtrue;
	    return Qfalse;
	}
    }
    return Qundef;
}

static int r_cover_range_p(VALUE range, VALUE beg, VALUE end, VALUE val);

/*
 *  call-seq:
 *     rng.cover?(obj)   ->  true or false
 *     rng.cover?(range) ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is between the begin and end of
 *  the range.
 *
 *  This tests <code>begin <= obj <= end</code> when #exclude_end? is +false+
 *  and <code>begin <= obj < end</code> when #exclude_end? is +true+.
 *
 *  If called with a Range argument, returns <code>true</code> when the
 *  given range is covered by the receiver,
 *  by comparing the begin and end values. If the argument can be treated as
 *  a sequence, this method treats it that way. In the specific case of
 *  <code>(a..b).cover?(c...d)</code> with <code>a <= c && b < d</code>,
 *  the end of the sequence must be calculated, which may exhibit poor
 *  performance if <code>c</code> is non-numeric.
 *  Returns <code>false</code> if the begin value of the
 *  range is larger than the end value. Also returns +false+ if one of the
 *  internal calls to <code><=></code> returns +nil+ (indicating the objects
 *  are not comparable).
 *
 *     ("a".."z").cover?("c")  #=> true
 *     ("a".."z").cover?("5")  #=> false
 *     ("a".."z").cover?("cc") #=> true
 *     ("a".."z").cover?(1)    #=> false
 *     (1..5).cover?(2..3)     #=> true
 *     (1..5).cover?(0..6)     #=> false
 *     (1..5).cover?(1...6)    #=> true
 */

static VALUE
range_cover(VALUE range, VALUE val)
{
    VALUE beg, end;

    beg = RANGE_BEG(range);
    end = RANGE_END(range);

    if (rb_obj_is_kind_of(val, rb_cRange)) {
        return RBOOL(r_cover_range_p(range, beg, end, val));
    }
    return r_cover_p(range, beg, end, val);
}

static VALUE
r_call_max(VALUE r)
{
    return rb_funcallv(r, rb_intern("max"), 0, 0);
}

static int
r_cover_range_p(VALUE range, VALUE beg, VALUE end, VALUE val)
{
    VALUE val_beg, val_end, val_max;
    int cmp_end;

    val_beg = RANGE_BEG(val);
    val_end = RANGE_END(val);

    if (!NIL_P(end) && NIL_P(val_end)) return FALSE;
    if (!NIL_P(beg) && NIL_P(val_beg)) return FALSE;
    if (!NIL_P(val_beg) && !NIL_P(val_end) && r_less(val_beg, val_end) > (EXCL(val) ? -1 : 0)) return FALSE;
    if (!NIL_P(val_beg) && !r_cover_p(range, beg, end, val_beg)) return FALSE;

    cmp_end = r_less(end, val_end);

    if (EXCL(range) == EXCL(val)) {
        return cmp_end >= 0;
    }
    else if (EXCL(range)) {
        return cmp_end > 0;
    }
    else if (cmp_end >= 0) {
        return TRUE;
    }

    val_max = rb_rescue2(r_call_max, val, 0, Qnil, rb_eTypeError, (VALUE)0);
    if (val_max == Qnil) return FALSE;

    return r_less(end, val_max) >= 0;
}

static VALUE
r_cover_p(VALUE range, VALUE beg, VALUE end, VALUE val)
{
    if (NIL_P(beg) || r_less(beg, val) <= 0) {
	int excl = EXCL(range);
	if (NIL_P(end) || r_less(val, end) <= -excl)
	    return Qtrue;
    }
    return Qfalse;
}

static VALUE
range_dumper(VALUE range)
{
    VALUE v = rb_obj_alloc(rb_cObject);

    rb_ivar_set(v, id_excl, RANGE_EXCL(range));
    rb_ivar_set(v, id_beg, RANGE_BEG(range));
    rb_ivar_set(v, id_end, RANGE_END(range));
    return v;
}

static VALUE
range_loader(VALUE range, VALUE obj)
{
    VALUE beg, end, excl;

    if (!RB_TYPE_P(obj, T_OBJECT) || RBASIC(obj)->klass != rb_cObject) {
        rb_raise(rb_eTypeError, "not a dumped range object");
    }

    range_modify(range);
    beg = rb_ivar_get(obj, id_beg);
    end = rb_ivar_get(obj, id_end);
    excl = rb_ivar_get(obj, id_excl);
    if (!NIL_P(excl)) {
	range_init(range, beg, end, RBOOL(RTEST(excl)));
    }
    return range;
}

static VALUE
range_alloc(VALUE klass)
{
    /* rb_struct_alloc_noinit itself should not be used because
     * rb_marshal_define_compat uses equality of allocation function */
    return rb_struct_alloc_noinit(klass);
}

/*
 *  call-seq:
 *     range.count                 -> int
 *     range.count(item)           -> int
 *     range.count { |obj| block } -> int
 *
 *  Identical to Enumerable#count, except it returns Infinity for endless
 *  ranges.
 *
 */
static VALUE
range_count(int argc, VALUE *argv, VALUE range)
{
    if (argc != 0) {
        /* It is odd for instance (1...).count(0) to return Infinity. Just let
         * it loop. */
        return rb_call_super(argc, argv);
    }
    else if (rb_block_given_p()) {
        /* Likewise it is odd for instance (1...).count {|x| x == 0 } to return
         * Infinity. Just let it loop. */
        return rb_call_super(argc, argv);
    }
    else if (NIL_P(RANGE_END(range))) {
        /* We are confident that the answer is Infinity. */
        return DBL2NUM(HUGE_VAL);
    }
    else if (NIL_P(RANGE_BEG(range))) {
        /* We are confident that the answer is Infinity. */
        return DBL2NUM(HUGE_VAL);
    }
    else {
        return rb_call_super(argc, argv);
    }
}

/*  A Range represents an interval---a set of values with a
 *  beginning and an end. Ranges may be constructed using the
 *  <em>s</em><code>..</code><em>e</em> and
 *  <em>s</em><code>...</code><em>e</em> literals, or with
 *  Range::new. Ranges constructed using <code>..</code>
 *  run from the beginning to the end inclusively. Those created using
 *  <code>...</code> exclude the end value. When used as an iterator,
 *  ranges return each value in the sequence.
 *
 *     (-1..-5).to_a      #=> []
 *     (-5..-1).to_a      #=> [-5, -4, -3, -2, -1]
 *     ('a'..'e').to_a    #=> ["a", "b", "c", "d", "e"]
 *     ('a'...'e').to_a   #=> ["a", "b", "c", "d"]
 *
 *  == Beginless/Endless Ranges
 *
 *  A "beginless range" and "endless range" represents a semi-infinite
 *  range.  Literal notation for a beginless range is:
 *
 *     (..1)
 *     # or
 *     (...1)
 *
 *  Literal notation for an endless range is:
 *
 *     (1..)
 *     # or similarly
 *     (1...)
 *
 *  Which is equivalent to
 *
 *     (1..nil)  # or similarly (1...nil)
 *     Range.new(1, nil) # or Range.new(1, nil, true)
 *
 *  Beginless/endless ranges are useful, for example, for idiomatic
 *  slicing of arrays:
 *
 *    [1, 2, 3, 4, 5][...2]   # => [1, 2]
 *    [1, 2, 3, 4, 5][2...]   # => [3, 4, 5]
 *
 *  Some implementation details:
 *
 *  * +begin+ of beginless range and +end+ of endless range are +nil+;
 *  * +each+ of beginless range raises an exception;
 *  * +each+ of endless range enumerates infinite sequence (may be
 *    useful in combination with Enumerable#take_while or similar
 *    methods);
 *  * <code>(1..)</code> and <code>(1...)</code> are not equal,
 *    although technically representing the same sequence.
 *
 *  == Custom Objects in Ranges
 *
 *  Ranges can be constructed using any objects that can be compared
 *  using the <code><=></code> operator.
 *  Methods that treat the range as a sequence (#each and methods inherited
 *  from Enumerable) expect the begin object to implement a
 *  <code>succ</code> method to return the next object in sequence.
 *  The #step and #include? methods require the begin
 *  object to implement <code>succ</code> or to be numeric.
 *
 *  In the <code>Xs</code> class below both <code><=></code> and
 *  <code>succ</code> are implemented so <code>Xs</code> can be used
 *  to construct ranges. Note that the Comparable module is included
 *  so the <code>==</code> method is defined in terms of <code><=></code>.
 *
 *     class Xs                # represent a string of 'x's
 *       include Comparable
 *       attr :length
 *       def initialize(n)
 *         @length = n
 *       end
 *       def succ
 *         Xs.new(@length + 1)
 *       end
 *       def <=>(other)
 *         @length <=> other.length
 *       end
 *       def to_s
 *         sprintf "%2d #{inspect}", @length
 *       end
 *       def inspect
 *         'x' * @length
 *       end
 *     end
 *
 *  An example of using <code>Xs</code> to construct a range:
 *
 *     r = Xs.new(3)..Xs.new(6)   #=> xxx..xxxxxx
 *     r.to_a                     #=> [xxx, xxxx, xxxxx, xxxxxx]
 *     r.member?(Xs.new(5))       #=> true
 *
 */

void
Init_Range(void)
{
    id_beg = rb_intern_const("begin");
    id_end = rb_intern_const("end");
    id_excl = rb_intern_const("excl");

    rb_cRange = rb_struct_define_without_accessor(
        "Range", rb_cObject, range_alloc,
        "begin", "end", "excl", NULL);

    rb_include_module(rb_cRange, rb_mEnumerable);
    rb_marshal_define_compat(rb_cRange, rb_cObject, range_dumper, range_loader);
    rb_define_method(rb_cRange, "initialize", range_initialize, -1);
    rb_define_method(rb_cRange, "initialize_copy", range_initialize_copy, 1);
    rb_define_method(rb_cRange, "==", range_eq, 1);
    rb_define_method(rb_cRange, "===", range_eqq, 1);
    rb_define_method(rb_cRange, "eql?", range_eql, 1);
    rb_define_method(rb_cRange, "hash", range_hash, 0);
    rb_define_method(rb_cRange, "each", range_each, 0);
    rb_define_method(rb_cRange, "step", range_step, -1);
    rb_define_method(rb_cRange, "%", range_percent_step, 1);
    rb_define_method(rb_cRange, "bsearch", range_bsearch, 0);
    rb_define_method(rb_cRange, "begin", range_begin, 0);
    rb_define_method(rb_cRange, "end", range_end, 0);
    rb_define_method(rb_cRange, "first", range_first, -1);
    rb_define_method(rb_cRange, "last", range_last, -1);
    rb_define_method(rb_cRange, "min", range_min, -1);
    rb_define_method(rb_cRange, "max", range_max, -1);
    rb_define_method(rb_cRange, "minmax", range_minmax, 0);
    rb_define_method(rb_cRange, "size", range_size, 0);
    rb_define_method(rb_cRange, "to_a", range_to_a, 0);
    rb_define_method(rb_cRange, "entries", range_to_a, 0);
    rb_define_method(rb_cRange, "to_s", range_to_s, 0);
    rb_define_method(rb_cRange, "inspect", range_inspect, 0);

    rb_define_method(rb_cRange, "exclude_end?", range_exclude_end_p, 0);

    rb_define_method(rb_cRange, "member?", range_include, 1);
    rb_define_method(rb_cRange, "include?", range_include, 1);
    rb_define_method(rb_cRange, "cover?", range_cover, 1);
    rb_define_method(rb_cRange, "count", range_count, -1);
}
