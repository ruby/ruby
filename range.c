/**********************************************************************

  range.c -

  $Author$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#include "id.h"

#ifdef HAVE_FLOAT_H
#include <float.h>
#endif
#include <math.h>

VALUE rb_cRange;
static ID id_beg, id_end, id_excl, id_integer_p, id_div;
#define id_cmp idCmp
#define id_succ idSucc

static VALUE r_cover_p(VALUE, VALUE, VALUE, VALUE);

#define RANGE_BEG(r) (RSTRUCT(r)->as.ary[0])
#define RANGE_END(r) (RSTRUCT(r)->as.ary[1])
#define RANGE_EXCL(r) (RSTRUCT(r)->as.ary[2])
#define RANGE_SET_BEG(r, v) (RSTRUCT_SET(r, 0, v))
#define RANGE_SET_END(r, v) (RSTRUCT_SET(r, 1, v))
#define RANGE_SET_EXCL(r, v) (RSTRUCT_SET(r, 2, v))
#define RBOOL(v) ((v) ? Qtrue : Qfalse)

#define EXCL(r) RTEST(RANGE_EXCL(r))

static VALUE
range_failed(void)
{
    rb_raise(rb_eArgError, "bad value for range");
    return Qnil;		/* dummy */
}

static VALUE
range_check(VALUE *args)
{
    return rb_funcall(args[0], id_cmp, 1, args[1]);
}

static void
range_init(VALUE range, VALUE beg, VALUE end, VALUE exclude_end)
{
    VALUE args[2];

    args[0] = beg;
    args[1] = end;

    if (!FIXNUM_P(beg) || !FIXNUM_P(end)) {
	VALUE v;

	v = rb_rescue(range_check, (VALUE)args, range_failed, 0);
	if (NIL_P(v))
	    range_failed();
    }

    RANGE_SET_EXCL(range, exclude_end);
    RANGE_SET_BEG(range, beg);
    RANGE_SET_END(range, end);
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
 *     Range.new(begin, end, exclude_end=false)    -> rng
 *
 *  Constructs a range using the given +begin+ and +end+. If the +exclude_end+
 *  parameter is omitted or is <code>false</code>, the +rng+ will include
 *  the end object; otherwise, it will be excluded.
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
 *     rng.exclude_end?    -> true or false
 *
 *  Returns <code>true</code> if the range excludes its end value.
 *
 *     (1..5).exclude_end?     #=> false
 *     (1...5).exclude_end?    #=> true
 */

static VALUE
range_exclude_end_p(VALUE range)
{
    return EXCL(range) ? Qtrue : Qfalse;
}

static VALUE
recursive_equal(VALUE range, VALUE obj, int recur)
{
    if (recur) return Qtrue; /* Subtle! */
    if (!rb_equal(RANGE_BEG(range), RANGE_BEG(obj)))
	return Qfalse;
    if (!rb_equal(RANGE_END(range), RANGE_END(obj)))
	return Qfalse;

    if (EXCL(range) != EXCL(obj))
	return Qfalse;
    return Qtrue;
}


/*
 *  call-seq:
 *     rng == obj    -> true or false
 *
 *  Returns <code>true</code> only if +obj+ is a Range, has equivalent
 *  begin and end items (by comparing them with <code>==</code>), and has
 *  the same #exclude_end? setting as the range.
 *
 *    (0..2) == (0..2)            #=> true
 *    (0..2) == Range.new(0,2)    #=> true
 *    (0..2) == (0...2)           #=> false
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

    if (EXCL(range) != EXCL(obj))
	return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     rng.eql?(obj)    -> true or false
 *
 *  Returns <code>true</code> only if +obj+ is a Range, has equivalent
 *  begin and end items (by comparing them with <code>eql?</code>),
 *  and has the same #exclude_end? setting as the range.
 *
 *    (0..2).eql?(0..2)            #=> true
 *    (0..2).eql?(Range.new(0,2))  #=> true
 *    (0..2).eql?(0...2)           #=> false
 *
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
 *   rng.hash    -> integer
 *
 * Compute a hash-code for this range. Two ranges with equal
 * begin and end points (using <code>eql?</code>), and the same
 * #exclude_end? value will generate the same hash-code.
 *
 * See also Object#hash.
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

    return LONG2FIX(hash);
}

static void
range_each_func(VALUE range, rb_block_call_func *func, VALUE arg)
{
    int c;
    VALUE b = RANGE_BEG(range);
    VALUE e = RANGE_END(range);
    VALUE v = b;

    if (EXCL(range)) {
	while (r_less(v, e) < 0) {
	    (*func) (v, arg, 0, 0, 0);
	    v = rb_funcallv(v, id_succ, 0, 0);
	}
    }
    else {
	while ((c = r_less(v, e)) <= 0) {
	    (*func) (v, arg, 0, 0, 0);
	    if (!c) break;
	    v = rb_funcallv(v, id_succ, 0, 0);
	}
    }
}

static VALUE
sym_step_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, arg))
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
    return Qnil;
}

static VALUE
step_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, arg))
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
    return Qnil;
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
 *     rng.step(n=1) {| obj | block }    -> rng
 *     rng.step(n=1)                     -> an_enumerator
 *
 *  Iterates over the range, passing each <code>n</code>th element to the block.
 *  If begin and end are numeric, +n+ is added for each iteration.
 *  Otherwise <code>step</code> invokes <code>succ</code> to iterate through
 *  range elements.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *    range = Xs.new(1)..Xs.new(10)
 *    range.step(2) {|x| puts x}
 *    puts
 *    range.step(3) {|x| puts x}
 *
 *  <em>produces:</em>
 *
 *     1 x
 *     3 xxx
 *     5 xxxxx
 *     7 xxxxxxx
 *     9 xxxxxxxxx
 *
 *     1 x
 *     4 xxxx
 *     7 xxxxxxx
 *    10 xxxxxxxxxx
 *
 *  See Range for the definition of class Xs.
 */


static VALUE
range_step(int argc, VALUE *argv, VALUE range)
{
    VALUE b, e, step, tmp;

    RETURN_SIZED_ENUMERATOR(range, argc, argv, range_step_size);

    b = RANGE_BEG(range);
    e = RANGE_END(range);
    if (argc == 0) {
	step = INT2FIX(1);
    }
    else {
	rb_scan_args(argc, argv, "01", &step);
	step = check_step_domain(step);
    }

    if (FIXNUM_P(b) && FIXNUM_P(e) && FIXNUM_P(step)) { /* fixnums are special */
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
    else if (SYMBOL_P(b) && SYMBOL_P(e)) { /* symbols are special */
	VALUE args[2], iter[2];

	args[0] = rb_sym2str(e);
	args[1] = EXCL(range) ? Qtrue : Qfalse;
	iter[0] = INT2FIX(1);
	iter[1] = step;
	rb_block_call(rb_sym2str(b), rb_intern("upto"), 2, args, sym_step_i, (VALUE)iter);
    }
    else if (ruby_float_step(b, e, step, EXCL(range))) {
	/* done */
    }
    else if (rb_obj_is_kind_of(b, rb_cNumeric) ||
	     !NIL_P(rb_check_to_integer(b, "to_int")) ||
	     !NIL_P(rb_check_to_integer(e, "to_int"))) {
	ID op = EXCL(range) ? '<' : idLE;
	VALUE v = b;
	int i = 0;

	while (RTEST(rb_funcall(v, op, 1, e))) {
	    rb_yield(v);
	    i++;
	    v = rb_funcall(b, '+', 1, rb_funcall(INT2NUM(i), '*', 1, step));
	}
    }
    else {
	tmp = rb_check_string_type(b);

	if (!NIL_P(tmp)) {
	    VALUE args[2], iter[2];

	    b = tmp;
	    args[0] = e;
	    args[1] = EXCL(range) ? Qtrue : Qfalse;
	    iter[0] = INT2FIX(1);
	    iter[1] = step;
	    rb_block_call(b, rb_intern("upto"), 2, args, step_i, (VALUE)iter);
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
    VALUE is_int = rb_check_funcall(v, id_integer_p, 0, 0);
    return RTEST(is_int) && is_int != Qundef;
}

/*
 *  call-seq:
 *     rng.bsearch {|obj| block }  -> value
 *
 *  By using binary search, finds a value in range which meets the given
 *  condition in O(log n) where n is the size of the range.
 *
 *  You can use this method in two use cases: a find-minimum mode and
 *  a find-any mode.  In either case, the elements of the range must be
 *  monotone (or sorted) with respect to the block.
 *
 *  In find-minimum mode (this is a good choice for typical use case),
 *  the block must return true or false, and there must be a value x
 *  so that:
 *
 *  - the block returns false for any value which is less than x, and
 *  - the block returns true for any value which is greater than or
 *    equal to x.
 *
 *  If x is within the range, this method returns the value x.
 *  Otherwise, it returns nil.
 *
 *     ary = [0, 4, 7, 10, 12]
 *     (0...ary.size).bsearch {|i| ary[i] >= 4 } #=> 1
 *     (0...ary.size).bsearch {|i| ary[i] >= 6 } #=> 2
 *     (0...ary.size).bsearch {|i| ary[i] >= 8 } #=> 3
 *     (0...ary.size).bsearch {|i| ary[i] >= 100 } #=> nil
 *
 *     (0.0...Float::INFINITY).bsearch {|x| Math.log(x) >= 0 } #=> 1.0
 *
 *  In find-any mode (this behaves like libc's bsearch(3)), the block
 *  must return a number, and there must be two values x and y (x <= y)
 *  so that:
 *
 *  - the block returns a positive number for v if v < x,
 *  - the block returns zero for v if x <= v < y, and
 *  - the block returns a negative number for v if y <= v.
 *
 *  This method returns any value which is within the intersection of
 *  the given range and x...y (if any).  If there is no value that
 *  satisfies the condition, it returns nil.
 *
 *     ary = [0, 100, 100, 100, 200]
 *     (0..4).bsearch {|i| 100 - ary[i] } #=> 1, 2 or 3
 *     (0..4).bsearch {|i| 300 - ary[i] } #=> nil
 *     (0..4).bsearch {|i|  50 - ary[i] } #=> nil
 *
 *  You must not mix the two modes at a time; the block must always
 *  return either true/false, or always return a number.  It is
 *  undefined which value is actually picked up at each iteration.
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
    else if (RB_TYPE_P(beg, T_FLOAT) || RB_TYPE_P(end, T_FLOAT)) {
	int64_t low  = double_as_int64(RFLOAT_VALUE(rb_Float(beg)));
	int64_t high = double_as_int64(RFLOAT_VALUE(rb_Float(end)));
	int64_t mid, org_high;
	BSEARCH(int64_as_double_to_num);
    }
#endif
    else if (is_integer_p(beg) && is_integer_p(end)) {
	VALUE low = rb_to_int(beg);
	VALUE high = rb_to_int(end);
	VALUE mid, org_high;
	RETURN_ENUMERATOR(range, 0, 0);
	if (EXCL(range)) high = rb_funcall(high, '-', 1, INT2FIX(1));
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
    else {
	rb_raise(rb_eTypeError, "can't do binary search for %s", rb_obj_classname(beg));
    }
    return range;
}

static VALUE
each_i(RB_BLOCK_CALL_FUNC_ARGLIST(v, arg))
{
    rb_yield(v);
    return Qnil;
}

static VALUE
sym_each_i(RB_BLOCK_CALL_FUNC_ARGLIST(v, arg))
{
    rb_yield(rb_str_intern(v));
    return Qnil;
}

/*
 *  call-seq:
 *     rng.size                   -> num
 *
 *  Returns the number of elements in the range. Both the begin and the end of
 *  the Range must be Numeric, otherwise nil is returned.
 *
 *    (10..20).size    #=> 11
 *    ('a'..'z').size  #=> nil
 *    (-Float::INFINITY..Float::INFINITY).size #=> Infinity
 */

static VALUE
range_size(VALUE range)
{
    VALUE b = RANGE_BEG(range), e = RANGE_END(range);
    if (rb_obj_is_kind_of(b, rb_cNumeric) && rb_obj_is_kind_of(e, rb_cNumeric)) {
	return ruby_num_interval_step_size(b, e, INT2FIX(1), EXCL(range));
    }
    return Qnil;
}

static VALUE
range_enum_size(VALUE range, VALUE args, VALUE eobj)
{
    return range_size(range);
}

/*
 *  call-seq:
 *     rng.each {| i | block } -> rng
 *     rng.each                -> an_enumerator
 *
 *  Iterates over the elements of range, passing each in turn to the
 *  block.
 *
 *  The +each+ method can only be used if the begin object of the range
 *  supports the +succ+ method.  A TypeError is raised if the object
 *  does not have +succ+ method defined (like Float).
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     (10..15).each {|n| print n, ' ' }
 *     # prints: 10 11 12 13 14 15
 *
 *     (2.5..5).each {|n| print n, ' ' }
 *     # raises: TypeError: can't iterate from Float
 */

static VALUE
range_each(VALUE range)
{
    VALUE beg, end;

    RETURN_SIZED_ENUMERATOR(range, 0, 0, range_enum_size);

    beg = RANGE_BEG(range);
    end = RANGE_END(range);

    if (FIXNUM_P(beg) && FIXNUM_P(end)) { /* fixnums are special */
	long lim = FIX2LONG(end);
	long i;

	if (!EXCL(range))
	    lim += 1;
	for (i = FIX2LONG(beg); i < lim; i++) {
	    rb_yield(LONG2FIX(i));
	}
    }
    else if (SYMBOL_P(beg) && SYMBOL_P(end)) { /* symbols are special */
	VALUE args[2];

	args[0] = rb_sym2str(end);
	args[1] = EXCL(range) ? Qtrue : Qfalse;
	rb_block_call(rb_sym2str(beg), rb_intern("upto"), 2, args, sym_each_i, 0);
    }
    else {
	VALUE tmp = rb_check_string_type(beg);

	if (!NIL_P(tmp)) {
	    VALUE args[2];

	    args[0] = end;
	    args[1] = EXCL(range) ? Qtrue : Qfalse;
	    rb_block_call(tmp, rb_intern("upto"), 2, args, each_i, 0);
	}
	else {
	    if (!discrete_object_p(beg)) {
		rb_raise(rb_eTypeError, "can't iterate from %s",
			 rb_obj_classname(beg));
	    }
	    range_each_func(range, each_i, 0);
	}
    }
    return range;
}

/*
 *  call-seq:
 *     rng.begin    -> obj
 *
 *  Returns the object that defines the beginning of the range.
 *
 *      (1..10).begin   #=> 1
 */

static VALUE
range_begin(VALUE range)
{
    return RANGE_BEG(range);
}


/*
 *  call-seq:
 *     rng.end    -> obj
 *
 *  Returns the object that defines the end of the range.
 *
 *     (1..10).end    #=> 10
 *     (1...10).end   #=> 10
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
    ary[0] = INT2NUM(n);
    return Qnil;
}

/*
 *  call-seq:
 *     rng.first    -> obj
 *     rng.first(n) -> an_array
 *
 *  Returns the first object in the range, or an array of the first +n+
 *  elements.
 *
 *    (10..20).first     #=> 10
 *    (10..20).first(3)  #=> [10, 11, 12]
 */

static VALUE
range_first(int argc, VALUE *argv, VALUE range)
{
    VALUE n, ary[2];

    if (argc == 0) return RANGE_BEG(range);

    rb_scan_args(argc, argv, "1", &n);
    ary[0] = n;
    ary[1] = rb_ary_new2(NUM2LONG(n));
    rb_block_call(range, idEach, 0, 0, first_i, (VALUE)ary);

    return ary[1];
}


/*
 *  call-seq:
 *     rng.last    -> obj
 *     rng.last(n) -> an_array
 *
 *  Returns the last object in the range,
 *  or an array of the last +n+ elements.
 *
 *  Note that with no arguments +last+ will return the object that defines
 *  the end of the range even if #exclude_end? is +true+.
 *
 *    (10..20).last      #=> 20
 *    (10...20).last     #=> 20
 *    (10..20).last(3)   #=> [18, 19, 20]
 *    (10...20).last(3)  #=> [17, 18, 19]
 */

static VALUE
range_last(int argc, VALUE *argv, VALUE range)
{
    if (argc == 0) return RANGE_END(range);
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
    if (rb_block_given_p()) {
	return rb_call_super(argc, argv);
    }
    else if (argc != 0) {
	return range_first(argc, argv, range);
    }
    else {
	VALUE b = RANGE_BEG(range);
	VALUE e = RANGE_END(range);
	int c = rb_cmpint(rb_funcall(b, id_cmp, 1, e), b, e);

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
 *  Returns the maximum value in the range. Returns +nil+ if the begin
 *  value of the range larger than the end value. Returns +nil+ if
 *  the begin value of an exclusive range is equal to the end value.
 *
 *  Can be given an optional block to override the default comparison
 *  method <code>a <=> b</code>.
 *
 *    (10..20).max    #=> 20
 */

static VALUE
range_max(int argc, VALUE *argv, VALUE range)
{
    VALUE e = RANGE_END(range);
    int nm = FIXNUM_P(e) || rb_obj_is_kind_of(e, rb_cNumeric);

    if (rb_block_given_p() || (EXCL(range) && !nm) || argc) {
	return rb_call_super(argc, argv);
    }
    else {
	VALUE b = RANGE_BEG(range);
	int c = rb_cmpint(rb_funcall(b, id_cmp, 1, e), b, e);

	if (c > 0)
	    return Qnil;
	if (EXCL(range)) {
	    if (!FIXNUM_P(e) && !rb_obj_is_kind_of(e, rb_cInteger)) {
		rb_raise(rb_eTypeError, "cannot exclude non Integer end value");
	    }
	    if (c == 0) return Qnil;
	    if (!FIXNUM_P(b) && !rb_obj_is_kind_of(b,rb_cInteger)) {
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
    else {
	if (!rb_respond_to(range, id_beg)) return (int)Qfalse;
	if (!rb_respond_to(range, id_end)) return (int)Qfalse;
	b = rb_funcall(range, id_beg, 0);
	e = rb_funcall(range, id_end, 0);
	excl = RTEST(rb_funcall(range, rb_intern("exclude_end?"), 0));
    }
    *begp = b;
    *endp = e;
    *exclp = excl;
    return (int)Qtrue;
}

VALUE
rb_range_beg_len(VALUE range, long *begp, long *lenp, long len, int err)
{
    long beg, end, origbeg, origend;
    VALUE b, e;
    int excl;

    if (!rb_range_values(range, &b, &e, &excl))
	return Qfalse;
    beg = NUM2LONG(b);
    end = NUM2LONG(e);
    origbeg = beg;
    origend = end;
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
    if (err) {
	rb_raise(rb_eRangeError, "%ld..%s%ld out of range",
		 origbeg, excl ? "." : "", origend);
    }
    return Qnil;
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
    OBJ_INFECT(str, range);

    return str;
}

static VALUE
inspect_range(VALUE range, VALUE dummy, int recur)
{
    VALUE str, str2;

    if (recur) {
	return rb_str_new2(EXCL(range) ? "(... ... ...)" : "(... .. ...)");
    }
    str = rb_inspect(RANGE_BEG(range));
    str2 = rb_inspect(RANGE_END(range));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range) ? 3 : 2);
    rb_str_append(str, str2);
    OBJ_INFECT(str, range);

    return str;
}

/*
 * call-seq:
 *   rng.inspect  -> string
 *
 * Convert this range object to a printable form (using
 * <code>inspect</code> to convert the begin and end
 * objects).
 */


static VALUE
range_inspect(VALUE range)
{
    return rb_exec_recursive(inspect_range, range, 0);
}

/*
 *  call-seq:
 *     rng === obj       ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is an element of the range,
 *  <code>false</code> otherwise.  Conveniently, <code>===</code> is the
 *  comparison operator used by <code>case</code> statements.
 *
 *     case 79
 *     when 1..50   then   print "low\n"
 *     when 51..75  then   print "medium\n"
 *     when 76..100 then   print "high\n"
 *     end
 *
 *  <em>produces:</em>
 *
 *     high
 */

static VALUE
range_eqq(VALUE range, VALUE val)
{
    return rb_funcall(range, rb_intern("include?"), 1, val);
}


/*
 *  call-seq:
 *     rng.member?(obj)  ->  true or false
 *     rng.include?(obj) ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is an element of
 *  the range, <code>false</code> otherwise.  If begin and end are
 *  numeric, comparison is done according to the magnitude of the values.
 *
 *     ("a".."z").include?("g")   #=> true
 *     ("a".."z").include?("A")   #=> false
 *     ("a".."z").include?("cc")  #=> false
 */

static VALUE
range_include(VALUE range, VALUE val)
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
    else if (RB_TYPE_P(beg, T_STRING) && RB_TYPE_P(end, T_STRING)) {
	VALUE rb_str_include_range_p(VALUE beg, VALUE end, VALUE val, VALUE exclusive);
	return rb_str_include_range_p(beg, end, val, RANGE_EXCL(range));
    }
    /* TODO: ruby_frame->this_func = rb_intern("include?"); */
    return rb_call_super(1, &val);
}


/*
 *  call-seq:
 *     rng.cover?(obj)  ->  true or false
 *
 *  Returns <code>true</code> if +obj+ is between the begin and end of
 *  the range.
 *
 *  This tests <code>begin <= obj <= end</code> when #exclude_end? is +false+
 *  and <code>begin <= obj < end</code> when #exclude_end? is +true+.
 *
 *     ("a".."z").cover?("c")    #=> true
 *     ("a".."z").cover?("5")    #=> false
 *     ("a".."z").cover?("cc")   #=> true
 */

static VALUE
range_cover(VALUE range, VALUE val)
{
    VALUE beg, end;

    beg = RANGE_BEG(range);
    end = RANGE_END(range);
    return r_cover_p(range, beg, end, val);
}

static VALUE
r_cover_p(VALUE range, VALUE beg, VALUE end, VALUE val)
{
    if (r_less(beg, val) <= 0) {
	int excl = EXCL(range);
	if (r_less(val, end) <= -excl)
	    return Qtrue;
    }
    return Qfalse;
}

static VALUE
range_dumper(VALUE range)
{
    VALUE v;
    NEWOBJ_OF(m, struct RObject, rb_cObject, T_OBJECT | (RGENGC_WB_PROTECTED_OBJECT ? FL_WB_PROTECTED : 1));

    v = (VALUE)m;

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

/*  A <code>Range</code> represents an interval---a set of values with a
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
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    id_beg = rb_intern("begin");
    id_end = rb_intern("end");
    id_excl = rb_intern("excl");
    id_integer_p = rb_intern("integer?");
    id_div = rb_intern("div");

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
    rb_define_method(rb_cRange, "bsearch", range_bsearch, 0);
    rb_define_method(rb_cRange, "begin", range_begin, 0);
    rb_define_method(rb_cRange, "end", range_end, 0);
    rb_define_method(rb_cRange, "first", range_first, -1);
    rb_define_method(rb_cRange, "last", range_last, -1);
    rb_define_method(rb_cRange, "min", range_min, -1);
    rb_define_method(rb_cRange, "max", range_max, -1);
    rb_define_method(rb_cRange, "size", range_size, 0);
    rb_define_method(rb_cRange, "to_s", range_to_s, 0);
    rb_define_method(rb_cRange, "inspect", range_inspect, 0);

    rb_define_method(rb_cRange, "exclude_end?", range_exclude_end_p, 0);

    rb_define_method(rb_cRange, "member?", range_include, 1);
    rb_define_method(rb_cRange, "include?", range_include, 1);
    rb_define_method(rb_cRange, "cover?", range_cover, 1);
}
