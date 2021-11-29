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
 *  - <tt>other.exclude_end? == self.exclude_end?</tt>.
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
 *  - <tt>other.exclude_end? == self.exclude_end?</tt>.
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

static bool
step_i_iter(VALUE arg)
{
    VALUE *iter = (VALUE *)arg;

    if (FIXNUM_P(iter[0])) {
	iter[0] -= INT2FIX(1) & ~FIXNUM_FLAG;
    }
    else {
	iter[0] = rb_funcall(iter[0], '-', 1, INT2FIX(1));
    }
    if (iter[0] != INT2FIX(0)) return false;
    iter[0] = iter[1];
    return true;
}

static int
sym_step_i(VALUE i, VALUE arg)
{
    if (step_i_iter(arg)) {
	rb_yield(rb_str_intern(i));
    }
    return 0;
}

static int
step_i(VALUE i, VALUE arg)
{
    if (step_i_iter(arg)) {
	rb_yield(i);
    }
    return 0;
}

static int
discrete_object_p(VALUE obj)
{
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
 *  Related: Range#%.
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
    VALUE iter[2] = {INT2FIX(1), step};

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
	    b = tmp;
	    if (NIL_P(e)) {
		rb_str_upto_endless_each(b, step_i, (VALUE)iter);
	    }
	    else {
		rb_str_upto_each(b, e, EXCL(range), step_i, (VALUE)iter);
	    }
	}
	else {
	    if (!discrete_object_p(b)) {
		rb_raise(rb_eTypeError, "can't iterate from %s",
			 rb_obj_classname(b));
	    }
	    range_each_func(range, step_i, (VALUE)iter);
	}
    }
    return range;
}

/*
 *  call-seq:
 *    %(n) {|element| ... } -> self
 *    %(n)                  -> enumerator
 *
 *  Iterates over the elements of +self+.
 *
 *  With a block given, calls the block with selected elements of the range;
 *  returns +self+:
 *
 *    a = []
 *    (1..5).%(2) {|element| a.push(element) } # => 1..5
 *    a # => [1, 3, 5]
 *    a = []
 *    ('a'..'e').%(2) {|element| a.push(element) } # => "a".."e"
 *    a # => ["a", "c", "e"]
 *
 *  With no block given, returns an enumerator,
 *  which will be of class Enumerator::ArithmeticSequence if +self+ is numeric;
 *  otherwise of class Enumerator:
 *
 *    e = (1..5) % 2 # => ((1..5).%(2))
 *    e.class        # => Enumerator::ArithmeticSequence
 *    ('a'..'e') % 2 # =>  #<Enumerator: ...>
 *
 *  Related: Range#step.
 */
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
	else if (!RTEST(v)) { \
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
 *
 *  Related: Range#count.
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
 *    min -> object
 *    min(n) -> array
 *    min {|a, b| ... } -> object
 *    min(n) {|a, b| ... } -> array
 *
 *  Returns the minimum value in +self+,
 *  using method <tt><=></tt> or a given block for comparison.
 *
 *  With no argument and no block given,
 *  returns the minimum-valued element of +self+.
 *
 *    (1..4).min     # => 1
 *    ('a'..'d').min # => "a"
 *    (-4..-1).min   # => -4
 *
 *  With non-negative integer argument +n+ given, and no block given,
 *  returns the +n+ minimum-valued elements of +self+ in an array:
 *
 *    (1..4).min(2)     # => [1, 2]
 *    ('a'..'d').min(2) # => ["a", "b"]
 *    (-4..-1).min(2)   # => [-4, -3]
 *    (1..4).min(50)    # => [1, 2, 3, 4]
 *
 *  If a block is given, it is called:
 *
 *  - First, with the first two element of +self+.
 *  - Then, sequentially, with the so-far minimum value and the next element of +self+.
 *
 *  To illustrate:
 *
 *    (1..4).min {|a, b| p [a, b]; a <=> b } # => 1
 *
 *  Output:
 *
 *    [2, 1]
 *    [3, 1]
 *    [4, 1]
 *
 *  With no argument and a block given,
 *  returns the return value of the last call to the block:
 *
 *    (1..4).min {|a, b| -(a <=> b) } # => 4
 *
 *  With non-negative integer argument +n+ given, and a block given,
 *  returns the return values of the last +n+ calls to the block in an array:
 *
 *    (1..4).min(2) {|a, b| -(a <=> b) }  # => [4, 3]
 *    (1..4).min(50) {|a, b| -(a <=> b) } # => [4, 3, 2, 1]
 *
 *  Returns an empty array if +n+ is zero:
 *
 *    (1..4).min(0)                      # => []
 *    (1..4).min(0) {|a, b| -(a <=> b) } # => []
 *
 *  Returns +nil+ or an empty array if:
 *
 *  - The begin value of the range is larger than the end value:
 *
 *      (4..1).min                         # => nil
 *      (4..1).min(2)                      # => []
 *      (4..1).min {|a, b| -(a <=> b) }    # => nil
 *      (4..1).min(2) {|a, b| -(a <=> b) } # => []
 *
 *  - The begin value of an exclusive range is equal to the end value:
 *
 *      (1...1).min                          # => nil
 *      (1...1).min(2)                       # => []
 *      (1...1).min  {|a, b| -(a <=> b) }    # => nil
 *      (1...1).min(2)  {|a, b| -(a <=> b) } # => []
 *
 *  Raises an exception if either:
 *
 *  - +self+ is a beginless range: <tt>(..4)</tt>.
 *  - A block is given and +self+ is an endless range.
 *
 *  Related: Range#max, Range#minmax.
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
 *    max -> object
 *    max(n) -> array
 *    max {|a, b| ... } -> object
 *    max(n) {|a, b| ... } -> array
 *
 *  Returns the maximum value in +self+,
 *  using method <tt><=></tt> or a given block for comparison.
 *
 *  With no argument and no block given,
 *  returns the maximum-valued element of +self+.
 *
 *    (1..4).max     # => 4
 *    ('a'..'d').max # => "d"
 *    (-4..-1).max   # => -1
 *
 *  With non-negative integer argument +n+ given, and no block given,
 *  returns the +n+ maximum-valued elements of +self+ in an array:
 *
 *    (1..4).max(2)     # => [4, 3]
 *    ('a'..'d').max(2) # => ["d", "c"]
 *    (-4..-1).max(2)   # => [-1, -2]
 *    (1..4).max(50)    # => [4, 3, 2, 1]
 *
 *  If a block is given, it is called:
 *
 *  - First, with the first two element of +self+.
 *  - Then, sequentially, with the so-far maximum value and the next element of +self+.
 *
 *  To illustrate:
 *
 *    (1..4).max {|a, b| p [a, b]; a <=> b } # => 4
 *
 *  Output:
 *
 *    [2, 1]
 *    [3, 2]
 *    [4, 3]
 *
 *  With no argument and a block given,
 *  returns the return value of the last call to the block:
 *
 *    (1..4).max {|a, b| -(a <=> b) } # => 1
 *
 *  With non-negative integer argument +n+ given, and a block given,
 *  returns the return values of the last +n+ calls to the block in an array:
 *
 *    (1..4).max(2) {|a, b| -(a <=> b) }  # => [1, 2]
 *    (1..4).max(50) {|a, b| -(a <=> b) } # => [1, 2, 3, 4]
 *
 *  Returns an empty array if +n+ is zero:
 *
 *    (1..4).max(0)                      # => []
 *    (1..4).max(0) {|a, b| -(a <=> b) } # => []
 *
 *  Returns +nil+ or an empty array if:
 *
 *  - The begin value of the range is larger than the end value:
 *
 *      (4..1).max                         # => nil
 *      (4..1).max(2)                      # => []
 *      (4..1).max {|a, b| -(a <=> b) }    # => nil
 *      (4..1).max(2) {|a, b| -(a <=> b) } # => []
 *
 *  - The begin value of an exclusive range is equal to the end value:
 *
 *      (1...1).max                          # => nil
 *      (1...1).max(2)                       # => []
 *      (1...1).max  {|a, b| -(a <=> b) }    # => nil
 *      (1...1).max(2)  {|a, b| -(a <=> b) } # => []
 *
 *  Raises an exception if either:
 *
 *  - +self+ is a endless range: <tt>(1..)</tt>.
 *  - A block is given and +self+ is a beginless range.
 *
 *  Related: Range#min, Range#minmax.
 *
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
 *    minmax -> [object, object]
 *    minmax {|a, b| ... } -> [object, object]
 *
 *  Returns a 2-element array containing the minimum and maximum value in +self+,
 *  either according to comparison method <tt><=></tt> or a given block.
 *
 *  With no block given, returns the minimum and maximum values,
 *  using <tt><=></tt> for comparison:
 *
 *    (1..4).minmax     # => [1, 4]
 *    (1...4).minmax    # => [1, 3]
 *    ('a'..'d').minmax # => ["a", "d"]
 *    (-4..-1).minmax   # => [-4, -1]
 *
 *  With a block given, the block must return an integer:
 *
 *  - Negative if +a+ is smaller than +b+.
 *  - Zero if +a+ and +b+ are equal.
 *  - Positive if +a+ is larger than +b+.
 *
 *  The block is called <tt>self.size</tt> times to compare elements;
 *  returns a 2-element Array containing the minimum and maximum values from +self+,
 *  per the block:
 *
 *    (1..4).minmax {|a, b| -(a <=> b) } # => [4, 1]
 *
 *  Returns <tt>[nil, nil]</tt> if:
 *
 *  - The begin value of the range is larger than the end value:
 *
 *      (4..1).minmax                      # => [nil, nil]
 *      (4..1).minmax {|a, b| -(a <=> b) } # => [nil, nil]
 *
 *  - The begin value of an exclusive range is equal to the end value:
 *
 *      (1...1).minmax                          # => [nil, nil]
 *      (1...1).minmax  {|a, b| -(a <=> b) }    # => [nil, nil]
 *
 *  Raises an exception if +self+ is a beginless or an endless range.
 *
 *  Related: Range#min, Range#max.
 *
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
 *   to_s -> string
 *
 * Returns a string representation of +self+,
 * including <tt>begin.to_s</tt> and <tt>end.to_s</tt>:
 *
 *   (1..4).to_s  # => "1..4"
 *   (1...4).to_s # => "1...4"
 *   (1..).to_s   # => "1.."
 *   (..4).to_s   # => "..4"
 *
 * Note that returns from #to_s and #inspect may differ:
 *
 *   ('a'..'d').to_s    # => "a..d"
 *   ('a'..'d').inspect # => "\"a\"..\"d\""
 *
 * Related: Range#inspect.
 *
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
 *   inspect -> string
 *
 * Returns a string representation of +self+,
 * including <tt>begin.inspect</tt> and <tt>end.inspect</tt>:
 *
 *   (1..4).inspect  # => "1..4"
 *   (1...4).inspect # => "1...4"
 *   (1..).inspect   # => "1.."
 *   (..4).inspect   # => "..4"
 *
 * Note that returns from #to_s and #inspect may differ:
 *
 *   ('a'..'d').to_s    # => "a..d"
 *   ('a'..'d').inspect # => "\"a\"..\"d\""
 *
 * Related: Range#to_s.
 *
 */


static VALUE
range_inspect(VALUE range)
{
    return rb_exec_recursive(inspect_range, range, 0);
}

static VALUE range_include_internal(VALUE range, VALUE val, int string_use_cover);

/*
 *  call-seq:
 *     self === object ->  true or false
 *
 *  Returns +true+ if +object+ is between <tt>self.begin</tt> and <tt>self.end</tt>.
 *  +false+ otherwise:
 *
 *    (1..4) === 2       # => true
 *    (1..4) === 5       # => false
 *    (1..4) === 'a'     # => false
 *    (1..4) === 4       # => true
 *    (1...4) === 4      # => false
 *    ('a'..'d') === 'c' # => true
 *    ('a'..'d') === 'e' # => false
 *
 *  A case statement uses method <tt>===</tt>, and so:
 *
 *     case 79
 *     when (1..50)
 *       "low"
 *     when (51..75)
 *       "medium"
 *     when (76..100)
 *       "high"
 *     end # => "high"
 *
 *     case "2.6.5"
 *     when ..."2.4"
 *       "EOL"
 *     when "2.4"..."2.5"
 *       "maintenance"
 *     when "2.5"..."3.0"
 *       "stable"
 *     when "3.1"..
 *       "upcoming"
 *     end # => "stable"
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
 *    include?(object) -> true or false
 *
 *  Returns +true+ if +object+ is an element of +self+, +false+ otherwise:
 *
 *    (1..4).include?(2)        # => true
 *    (1..4).include?(5)        # => false
 *    (1..4).include?(4)        # => true
 *    (1...4).include?(4)       # => false
 *    ('a'..'d').include?('b')  # => true
 *    ('a'..'d').include?('e')  # => false
 *    ('a'..'d').include?('B')  # => false
 *    ('a'..'d').include?('d')  # => true
 *    ('a'...'d').include?('d') # => false
 *
 *  If begin and end are numeric, #include? behaves like #cover?
 *
 *    (1..3).include?(1.5) # => true
 *    (1..3).cover?(1.5) # => true
 *
 *  But when not numeric, the two methods may differ:
 *
 *    ('a'..'d').include?('cc') # => false
 *    ('a'..'d').cover?('cc')   # => true
 *
 *  Related: Range#cover?.
 *
 *  Range#member? is an alias for Range#include?.
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
            return RBOOL(rb_cmpint(r, val, end) <= 0);
        }
	else if (NIL_P(end)) {
	    VALUE r = rb_funcall(beg, id_cmp, 1, val);
	    if (NIL_P(r)) return Qfalse;
            return RBOOL(rb_cmpint(r, beg, val) <= 0);
	}
    }
    return Qundef;
}

static int r_cover_range_p(VALUE range, VALUE beg, VALUE end, VALUE val);

/*
 *  call-seq:
 *    cover?(object) -> true or false
 *    cover?(range) -> true or false
 *
 *  Returns +true+ if the given argument is within +self+, +false+ otherwise.
 *
 *  With non-range argument +object+, evaluates with <tt><=</tt> and <tt><</tt>.
 *
 *  For range +self+ with included end value (<tt>#exclude_end? == false</tt>),
 *  evaluates thus:
 *
 *    self.begin <= object <= self.end
 *
 *  Examples:
 *
 *    r = (1..4)
 *    r.cover?(1)     # => true
 *    r.cover?(4)     # => true
 *    r.cover?(0)     # => false
 *    r.cover?(5)     # => false
 *    r.cover?('foo') # => false

 *    r = ('a'..'d')
 *    r.cover?('a')     # => true
 *    r.cover?('d')     # => true
 *    r.cover?(' ')     # => false
 *    r.cover?('e')     # => false
 *    r.cover?(0)       # => false
 *
 *  For range +r+ with excluded end value (<tt>#exclude_end? == true</tt>),
 *  evaluates thus:
 *
 *    r.begin <= object < r.end
 *
 *  Examples:
 *
 *    r = (1...4)
 *    r.cover?(1)     # => true
 *    r.cover?(3)     # => true
 *    r.cover?(0)     # => false
 *    r.cover?(4)     # => false
 *    r.cover?('foo') # => false

 *    r = ('a'...'d')
 *    r.cover?('a')     # => true
 *    r.cover?('c')     # => true
 *    r.cover?(' ')     # => false
 *    r.cover?('d')     # => false
 *    r.cover?(0)       # => false
 *
 *  With range argument +range+, compares the first and last
 *  elements of +self+ and +range+:
 *
 *    r = (1..4)
 *    r.cover?(1..4)     # => true
 *    r.cover?(0..4)     # => false
 *    r.cover?(1..5)     # => false
 *    r.cover?('a'..'d') # => false

 *    r = (1...4)
 *    r.cover?(1..3)     # => true
 *    r.cover?(1..4)     # => false
 *
 *  If begin and end are numeric, #cover? behaves like #include?
 *
 *    (1..3).cover?(1.5) # => true
 *    (1..3).include?(1.5) # => true
 *
 *  But when not numeric, the two methods may differ:
 *
 *    ('a'..'d').cover?('cc')   # => true
 *    ('a'..'d').include?('cc') # => false
 *
 *  Returns +false+ if either:
 *
 *  - The begin value of +self+ is larger than its end value.
 *  - An internal call to <tt><=></tt> returns +nil+;
 *    that is, the operands are not comparable.
 *
 *  Related: Range#include?.
 *
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
    if (NIL_P(val_max)) return FALSE;

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
 *    count -> integer
 *    count(object) -> integer
 *    count {|element| ... } -> integer
 *
 *  Returns the count of elements, based on an argument or block criterion, if given.
 *
 *  With no argument and no block given, returns the number of elements:
 *
 *    (1..4).count      # => 4
 *    (1...4).count     # => 3
 *    ('a'..'d').count  # => 4
 *    ('a'...'d').count # => 3
 *    (1..).count       # => Infinity
 *    (..4).count       # => Infinity
 *
 *  With argument +object+, returns the number of +object+ found in +self+,
 *  which will usually be zero or one:
 *
 *    (1..4).count(2)   # => 1
 *    (1..4).count(5)   # => 0
 *    (1..4).count('a')  # => 0
 *
 *  With a block given, calls the block with each element;
 *  returns the number of elements for which the block returns a truthy value:
 *
 *    (1..4).count {|element| element < 3 } # => 2
 *
 *  Related: Range#size.
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

/* A \Range object represents a collection of values
 * that are between given begin and end values.
 *
 * You can create an \Range object explicitly with:
 *
 * - A {range literal}[doc/syntax/literals_rdoc.html#label-Range+Literals]:
 *
 *     # Ranges that use '..' to include the given end value.
 *     (1..4).to_a      # => [1, 2, 3, 4]
 *     ('a'..'d').to_a  # => ["a", "b", "c", "d"]
 *     # Ranges that use '...' to exclude the given end value.
 *     (1...4).to_a     # => [1, 2, 3]
 *     ('a'...'d').to_a # => ["a", "b", "c"]
 *
 * A range may be created using method Range.new:
 *
 *   # Ranges that by default include the given end value.
 *   Range.new(1, 4).to_a     # => [1, 2, 3, 4]
 *   Range.new('a', 'd').to_a # => ["a", "b", "c", "d"]
 *   # Ranges that use third argument +exclude_end+ to exclude the given end value.
 *   Range.new(1, 4, true).to_a     # => [1, 2, 3]
 *   Range.new('a', 'd', true).to_a # => ["a", "b", "c"]
 *
 * == Beginless Ranges
 *
 * A _beginless_ _range_ has a definite end value, but a +nil+ begin value.
 * Such a range includes all values up to the end value.
 *
 *   r = (..4)               # => nil..4
 *   r.begin                 # => nil
 *   r.include?(-50)         # => true
 *   r.include?(4)           # => true
 *
 *   r = (...4)              # => nil...4
 *   r.include?(4)           # => false
 *
 *   Range.new(nil, 4)       # => nil..4
 *   Range.new(nil, 4, true) # => nil...4
 *
 * A beginless range may be used to slice an array:
 *
 *  a = [1, 2, 3, 4]
 *  r = (..2) # => nil...2
 *  a[r]      # => [1, 2]
 *
 * \Method +each+ for a beginless range raises an exception.
 *
 * == Endless Ranges
 *
 * An _endless_ _range_ has a definite begin value, but a +nil+ end value.
 * Such a range includes all values from the begin value.
 *
 *   r = (1..)         # => 1..
 *   r.end             # => nil
 *   r.include?(50)    # => true
 *
 *   Range.new(1, nil) # => 1..
 *
 * The literal for  an endless range may be written with either two dots
 * or three.
 * The range has the same elements, either way.
 * But note that the two are not equal:
 *
 *   r0 = (1..)           # => 1..
 *   r1 = (1...)          # => 1...
 *   r0.begin == r1.begin # => true
 *   r0.end == r1.end     # => true
 *   r0 == r1             # => false
 *
 * An endless range may be used to slice an array:
 *
 *   a = [1, 2, 3, 4]
 *   r = (2..) # => 2..
 *   a[r]      # => [3, 4]
 *
 * \Method +each+ for an endless range calls the given block indefinitely:
 *
 *   a = []
 *   r = (1..)
 *   r.each do |i|
 *     a.push(i) if i.even?
 *     break if i > 10
 *   end
 *   a # => [2, 4, 6, 8, 10]
 *
 * == Ranges and Other Classes
 *
 * An object may be put into a range if its class implements
 * instance method <tt><=></tt>.
 * Ruby core classes that do so include Array, Complex, File::Stat,
 * Float, Integer, Kernel, Module, Numeric, Rational, String, Symbol, and Time.
 *
 * Example:
 *
 *   t0 = Time.now         # => 2021-09-19 09:22:48.4854986 -0500
 *   t1 = Time.now         # => 2021-09-19 09:22:56.0365079 -0500
 *   t2 = Time.now         # => 2021-09-19 09:23:08.5263283 -0500
 *   (t0..t2).include?(t1) # => true
 *   (t0..t1).include?(t2) # => false
 *
 * A range can be iterated over only if its elements
 * implement instance method +succ+.
 * Ruby core classes that do so include Integer, String, and Symbol
 * (but not the other classes mentioned above).
 *
 * Iterator methods include:
 *
 * - In \Range itself: #each, #step, and #%
 * - Included from module Enumerable: #each_entry, #each_with_index,
 *   #each_with_object, #each_slice, #each_cons, and #reverse_each.
 *
 * Example:
 *
 *   a = []
 *   (1..4).each {|i| a.push(i) }
 *   a # => [1, 2, 3, 4]
 *
 * == Ranges and User-Defined Classes
 *
 * A user-defined class that is to be used in a range
 * must implement instance <tt><=></tt>;
 * see {Integer#<=>}[Integer.html#label-method-i-3C-3D-3E].
 * To make iteration available, it must also implement
 * instance method +succ+; see Integer#succ.
 *
 * The class below implements both <tt><=></tt> and +succ+,
 * and so can be used both to construct ranges and to iterate over them.
 * Note that the Comparable module is included
 * so the <tt>==</tt> method is defined in terms of <tt><=></tt>.
 *
 *   # Represent a string of 'X' characters.
 *   class Xs
 *     include Comparable
 *     attr_accessor :length
 *     def initialize(n)
 *       @length = n
 *     end
 *     def succ
 *       Xs.new(@length + 1)
 *     end
 *     def <=>(other)
 *       @length <=> other.length
 *     end
 *     def to_s
 *       sprintf "%2d #{inspect}", @length
 *     end
 *     def inspect
 *       'X' * @length
 *     end
 *   end
 *
 *   r = Xs.new(3)..Xs.new(6) #=> XXX..XXXXXX
 *   r.to_a                   #=> [XXX, XXXX, XXXXX, XXXXXX]
 *   r.include?(Xs.new(5))    #=> true
 *   r.include?(Xs.new(7))    #=> false
 *
 * == What's Here
 *
 * First, what's elsewhere. \Class \Range:
 *
 * - Inherits from {class Object}[Object.html#class-Object-label-What-27s+Here].
 * - Includes {module Enumerable}[Enumerable.html#module-Enumerable-label-What-27s+Here],
 *   which provides dozens of additional methods.
 *
 * Here, class \Range provides methods that are useful for:
 *
 * - {Creating a Range}[#class-Range-label-Methods+for+Creating+a+Range]
 * - {Querying}[#class-Range-label-Methods+for+Querying]
 * - {Comparing}[#class-Range-label-Methods+for+Comparing]
 * - {Iterating}[#class-Range-label-Methods+for+Iterating]
 * - {Converting}[#class-Range-label-Methods+for+Converting]
 *
 * === Methods for Creating a \Range
 *
 * - ::new:: Returns a new range.
 *
 * === Methods for Querying
 *
 * - #begin:: Returns the begin value given for +self+.
 * - #bsearch:: Returns an element from +self+ selected by a binary search.
 * - #count:: Returns a count of elements in +self+.
 * - #end:: Returns the end value given for +self+.
 * - #exclude_end?:: Returns whether the end object is excluded.
 * - #first:: Returns the first elements of +self+.
 * - #hash:: Returns the integer hash code.
 * - #last:: Returns the last elements of +self+.
 * - #max:: Returns the maximum values in +self+.
 * - #min:: Returns the minimum values in +self+.
 * - #minmax:: Returns the minimum and maximum values in +self+.
 * - #size:: Returns the count of elements in +self+.
 *
 * === Methods for Comparing
 *
 * - {#==}[#method-i-3D-3D]:: Returns whether a given object is equal to +self+
 *                            (uses #==).
 * - #===:: Returns whether the given object is between the begin and end values.
 * - #cover?:: Returns whether a given object is within +self+.
 * - #eql?:: Returns whether a given object is equal to +self+ (uses #eql?).
 * - #include? (aliased as #member?):: Returns whether a given object
 *                                     is an element of +self+.
 *
 * === Methods for Iterating
 *
 * - #%:: Requires argument +n+; calls the block with each +n+-th element of +self+.
 * - #each:: Calls the block with each element of +self+.
 * - #step:: Takes optional argument +n+ (defaults to 1);
             calls the block with each +n+-th element of +self+.
 *
 * === Methods for Converting
 *
 * - #inspect:: Returns a string representation of +self+ (uses #inspect).
 * - #to_a (aliased as #entries):: Returns elements of +self+ in an array.
 * - #to_s:: Returns a string representation of +self+ (uses #to_s).
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
