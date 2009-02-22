/**********************************************************************

  range.c -

  $Author$
  $Date$
  created at: Thu Aug 19 17:46:47 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_cRange;
static ID id_cmp, id_succ, id_beg, id_end, id_excl;

#define EXCL(r) RTEST(rb_ivar_get((r), id_excl))
#define SET_EXCL(r,v) rb_ivar_set((r), id_excl, (v) ? Qtrue : Qfalse)

static VALUE
range_failed()
{
    rb_raise(rb_eArgError, "bad value for range");
    return Qnil;		/* dummy */
}

static VALUE
range_check(args)
    VALUE *args;
{
    return rb_funcall(args[0], id_cmp, 1, args[1]);
}

static void
range_init(range, beg, end, exclude_end)
    VALUE range, beg, end;
    int exclude_end;
{
    VALUE args[2];

    args[0] = beg;
    args[1] = end;
    
    if (!FIXNUM_P(beg) || !FIXNUM_P(end)) {
	VALUE v;

	v = rb_rescue(range_check, (VALUE)args, range_failed, 0);
	if (NIL_P(v)) range_failed();
    }

    SET_EXCL(range, exclude_end);
    rb_ivar_set(range, id_beg, beg);
    rb_ivar_set(range, id_end, end);
}

VALUE
rb_range_new(beg, end, exclude_end)
    VALUE beg, end;
    int exclude_end;
{
    VALUE range = rb_obj_alloc(rb_cRange);

    range_init(range, beg, end, exclude_end);
    return range;
}

/*
 *  call-seq:
 *     Range.new(start, end, exclusive=false)    => range
 *  
 *  Constructs a range using the given <i>start</i> and <i>end</i>. If the third
 *  parameter is omitted or is <code>false</code>, the <i>range</i> will include
 *  the end object; otherwise, it will be excluded.
 */

static VALUE
range_initialize(argc, argv, range)
    int argc;
    VALUE *argv;
    VALUE range;
{
    VALUE beg, end, flags;
    
    rb_scan_args(argc, argv, "21", &beg, &end, &flags);
    /* Ranges are immutable, so that they should be initialized only once. */
    if (rb_ivar_defined(range, id_beg)) {
	rb_name_error(rb_intern("initialize"), "`initialize' called twice");
    }
    range_init(range, beg, end, RTEST(flags));
    return Qnil;
}


/*
 *  call-seq:
 *     rng.exclude_end?    => true or false
 *  
 *  Returns <code>true</code> if <i>rng</i> excludes its end value.
 */

static VALUE
range_exclude_end_p(range)
    VALUE range;
{
    return EXCL(range) ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     rng == obj    => true or false
 *  
 *  Returns <code>true</code> only if <i>obj</i> is a Range, has equivalent
 *  beginning and end items (by comparing them with <code>==</code>), and has
 *  the same #exclude_end? setting as <i>rng</t>.
 *     
 *    (0..2) == (0..2)            #=> true
 *    (0..2) == Range.new(0,2)    #=> true
 *    (0..2) == (0...2)           #=> false
 *     
 */

static VALUE
range_eq(range, obj)
    VALUE range, obj;
{
    if (range == obj) return Qtrue;
    if (!rb_obj_is_instance_of(obj, rb_obj_class(range)))
	return Qfalse;

    if (!rb_equal(rb_ivar_get(range, id_beg), rb_ivar_get(obj, id_beg)))
	return Qfalse;
    if (!rb_equal(rb_ivar_get(range, id_end), rb_ivar_get(obj, id_end)))
	return Qfalse;

    if (EXCL(range) != EXCL(obj)) return Qfalse;

    return Qtrue;
}

static int
r_lt(a, b)
    VALUE a, b;
{
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (NIL_P(r)) return Qfalse;
    if (rb_cmpint(r, a, b) < 0) return Qtrue;
    return Qfalse;
}

static int
r_le(a, b)
    VALUE a, b;
{
    int c;
    VALUE r = rb_funcall(a, id_cmp, 1, b);

    if (NIL_P(r)) return Qfalse;
    c = rb_cmpint(r, a, b);
    if (c == 0) return INT2FIX(0);
    if (c < 0) return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     rng.eql?(obj)    => true or false
 *  
 *  Returns <code>true</code> only if <i>obj</i> is a Range, has equivalent
 *  beginning and end items (by comparing them with #eql?), and has the same
 *  #exclude_end? setting as <i>rng</i>.
 *     
 *    (0..2) == (0..2)            #=> true
 *    (0..2) == Range.new(0,2)    #=> true
 *    (0..2) == (0...2)           #=> false
 *     
 */

static VALUE
range_eql(range, obj)
    VALUE range, obj;
{
    if (range == obj) return Qtrue;
    if (!rb_obj_is_instance_of(obj, rb_obj_class(range)))
	return Qfalse;

    if (!rb_eql(rb_ivar_get(range, id_beg), rb_ivar_get(obj, id_beg)))
	return Qfalse;
    if (!rb_eql(rb_ivar_get(range, id_end), rb_ivar_get(obj, id_end)))
	return Qfalse;

    if (EXCL(range) != EXCL(obj)) return Qfalse;

    return Qtrue;
}

/*
 * call-seq:
 *   rng.hash    => fixnum
 *
 * Generate a hash value such that two ranges with the same start and
 * end points, and the same value for the "exclude end" flag, generate
 * the same hash value.
 */

static VALUE
range_hash(range)
    VALUE range;
{
    long hash = EXCL(range);
    VALUE v;

    v = rb_hash(rb_ivar_get(range, id_beg));
    hash ^= v << 1;
    v = rb_hash(rb_ivar_get(range, id_end));
    hash ^= v << 9;
    hash ^= EXCL(range) << 24;

    return LONG2FIX(hash);
}

static VALUE
str_step(args)
    VALUE *args;
{
    return rb_str_upto(args[0], args[1], EXCL(args[2]));
}

static void
range_each_func(range, func, v, e, arg)
    VALUE range;
    void (*func) _((VALUE, void*));
    VALUE v, e;
    void *arg;
{
    int c;

    if (EXCL(range)) {
	while (r_lt(v, e)) {
	    (*func)(v, arg);
	    v = rb_funcall(v, id_succ, 0, 0);
	}
    }
    else {
	while (RTEST(c = r_le(v, e))) {
	    (*func)(v, arg);
	    if (c == INT2FIX(0)) break;
	    v = rb_funcall(v, id_succ, 0, 0);
	}
    }
}

static VALUE
step_i(i, arg)
    VALUE i;
    VALUE arg;
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

extern int ruby_float_step _((VALUE from, VALUE to, VALUE step, int excl));

/*
 *  call-seq:
 *     rng.step(n=1) {| obj | block }    => rng
 *  
 *  Iterates over <i>rng</i>, passing each <i>n</i>th element to the block. If
 *  the range contains numbers, <i>n</i> is added for each iteration.  Otherwise
 *  <code>step</code> invokes <code>succ</code> to iterate through range
 *  elements. The following code uses class <code>Xs</code>, which is defined
 *  in the class-level documentation.
 *     
 *     range = Xs.new(1)..Xs.new(10)
 *     range.step(2) {|x| puts x}
 *     range.step(3) {|x| puts x}
 *     
 *  <em>produces:</em>
 *     
 *      1 x
 *      3 xxx
 *      5 xxxxx
 *      7 xxxxxxx
 *      9 xxxxxxxxx
 *      1 x
 *      4 xxxx
 *      7 xxxxxxx
 *     10 xxxxxxxxxx
 */


static VALUE
range_step(argc, argv, range)
    int argc;
    VALUE *argv;
    VALUE range;
{
    VALUE b, e, step, tmp;

    RETURN_ENUMERATOR(range, argc, argv);

    b = rb_ivar_get(range, id_beg);
    e = rb_ivar_get(range, id_end);
    if (argc == 0) {
	step = INT2FIX(1);
    }
    else {
	rb_scan_args(argc, argv, "01", &step);
	if (!rb_obj_is_kind_of(step, rb_cNumeric)) {
	    step = rb_to_int(step);
	}
	if (rb_funcall(step, '<', 1, INT2FIX(0))) {
	    rb_raise(rb_eArgError, "step can't be negative");
	}
	else if (!rb_funcall(step, '>', 1, INT2FIX(0))) {
	    rb_raise(rb_eArgError, "step can't be 0");
	}
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
    else if (ruby_float_step(b, e, step, EXCL(range))) {
	/* done */
    }
    else if (rb_obj_is_kind_of(b, rb_cNumeric) ||
	     !NIL_P(rb_check_to_integer(b, "to_int")) ||
	     !NIL_P(rb_check_to_integer(e, "to_int"))) {
	ID op = EXCL(range) ? '<' : rb_intern("<=");

	while (RTEST(rb_funcall(b, op, 1, e))) {
	    rb_yield(b);
	    b = rb_funcall(b, '+', 1, step);
	}
    }
    else {
	tmp = rb_check_string_type(b);

	if (!NIL_P(tmp)) {
	    VALUE args[5], iter[2];

	    b = tmp;
	    args[0] = e;
	    args[1] = EXCL(range) ? Qtrue : Qfalse;
	    iter[0] = INT2FIX(1);
	    iter[1] = step;
	    rb_block_call(b, rb_intern("upto"), 2, args, step_i, (VALUE)iter);
	}
	else if (rb_obj_is_kind_of(b, rb_cNumeric) ||
		 !NIL_P(rb_check_to_integer(b, "to_int")) ||
		 !NIL_P(rb_check_to_integer(e, "to_int"))) {
	    ID c = EXCL(range) ? '<' : rb_intern("<=");

	    while (RTEST(rb_funcall(b, c, 1, e))) {
		rb_yield(b);
		b = rb_funcall(b, '+', 1, step);
	    }
	}
	else {
	    VALUE args[2];

	    if (!rb_respond_to(b, id_succ)) {
		rb_raise(rb_eTypeError, "can't iterate from %s",
			 rb_obj_classname(b));
	    }
	    args[0] = INT2FIX(1);
	    args[1] = step;
	    range_each_func(range, step_i, b, e, args);
	}
    }
    return range;
}

static void
each_i(v, arg)
    VALUE v;
    void *arg;
{
    rb_yield(v);
}

/*
 *  call-seq:
 *     rng.each {| i | block } => rng
 *  
 *  Iterates over the elements <i>rng</i>, passing each in turn to the
 *  block. You can only iterate if the start object of the range
 *  supports the +succ+ method (which means that you can't iterate over
 *  ranges of +Float+ objects).
 *     
 *     (10..15).each do |n|
 *        print n, ' '
 *     end
 *     
 *  <em>produces:</em>
 *     
 *     10 11 12 13 14 15
 */

static VALUE
range_each(range)
    VALUE range;
{
    VALUE beg, end;

    RETURN_ENUMERATOR(range, 0, 0);

    beg = rb_ivar_get(range, id_beg);
    end = rb_ivar_get(range, id_end);

    if (!rb_respond_to(beg, id_succ)) {
	rb_raise(rb_eTypeError, "can't iterate from %s",
		 rb_obj_classname(beg));
    }
    if (FIXNUM_P(beg) && FIXNUM_P(end)) { /* fixnums are special */
	long lim = FIX2LONG(end);
	long i;

	if (!EXCL(range)) lim += 1;
	for (i=FIX2LONG(beg); i<lim; i++) {
	    rb_yield(LONG2NUM(i));
	}
    }
    else if (TYPE(beg) == T_STRING) {
	VALUE args[5], iter[2];

	args[0] = beg; args[1] = end; args[2] = range;
	iter[0] = INT2FIX(1); iter[1] = INT2FIX(1);
	rb_iterate((VALUE(*)_((VALUE)))str_step, (VALUE)args, step_i,
		   (VALUE)iter);
    }
    else {
	range_each_func(range, each_i, beg, end, NULL);
    }
    return range;
}

/*
 *  call-seq:
 *     rng.first    => obj
 *     rng.begin    => obj
 *  
 *  Returns the first object in <i>rng</i>.
 */

static VALUE
range_first(range)
    VALUE range;
{
    return rb_ivar_get(range, id_beg);
}


/*
 *  call-seq:
 *     rng.end    => obj
 *     rng.last   => obj
 *  
 *  Returns the object that defines the end of <i>rng</i>.
 *     
 *     (1..10).end    #=> 10
 *     (1...10).end   #=> 10
 */


static VALUE
range_last(range)
    VALUE range;
{
    return rb_ivar_get(range, id_end);
}

VALUE
rb_range_beg_len(range, begp, lenp, len, err)
    VALUE range;
    long *begp, *lenp;
    long len;
    int err;
{
    long beg, end, b, e;

    if (!rb_obj_is_kind_of(range, rb_cRange)) return Qfalse;

    beg = b = NUM2LONG(rb_ivar_get(range, id_beg));
    end = e = NUM2LONG(rb_ivar_get(range, id_end));

    if (beg < 0) {
	beg += len;
	if (beg < 0) goto out_of_range;
    }
    if (err == 0 || err == 2) {
	if (beg > len) goto out_of_range;
	if (end > len) end = len;
    }
    if (end < 0) end += len;
    if (!EXCL(range)) end++;	/* include end point */
    len = end - beg;
    if (len < 0) len = 0;

    *begp = beg;
    *lenp = len;
    return Qtrue;

  out_of_range:
    if (err) {
	rb_raise(rb_eRangeError, "%ld..%s%ld out of range",
		 b, EXCL(range)? "." : "", e);
    }
    return Qnil;
}

/*
 * call-seq:
 *   rng.to_s   => string
 *
 * Convert this range object to a printable form.
 */

static VALUE
range_to_s(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_obj_as_string(rb_ivar_get(range, id_beg));
    str2 = rb_obj_as_string(rb_ivar_get(range, id_end));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range)?3:2);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return str;
}

/*
 * call-seq:
 *   rng.inspect  => string
 *
 * Convert this range object to a printable form (using 
 * <code>inspect</code> to convert the start and end
 * objects).
 */


static VALUE
range_inspect(range)
    VALUE range;
{
    VALUE str, str2;

    str = rb_inspect(rb_ivar_get(range, id_beg));
    str2 = rb_inspect(rb_ivar_get(range, id_end));
    str = rb_str_dup(str);
    rb_str_cat(str, "...", EXCL(range)?3:2);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return str;
}

/*
 *  call-seq:
 *     rng === obj       =>  true or false
 *     rng.member?(val)  =>  true or false
 *     rng.include?(val) =>  true or false
 *  
 *  Returns <code>true</code> if <i>obj</i> is an element of
 *  <i>rng</i>, <code>false</code> otherwise. Conveniently,
 *  <code>===</code> is the comparison operator used by
 *  <code>case</code> statements.
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
range_include(range, val)
    VALUE range, val;
{
    VALUE beg, end;

    beg = rb_ivar_get(range, id_beg);
    end = rb_ivar_get(range, id_end);
    if (r_le(beg, val)) {
	if (EXCL(range)) {
	    if (r_lt(val, end)) return Qtrue;
	}
	else {
	    if (r_le(val, end)) return Qtrue;
	}
    }
    return Qfalse;
}


/*  A <code>Range</code> represents an interval---a set of values with a
 *  start and an end. Ranges may be constructed using the
 *  <em>s</em><code>..</code><em>e</em> and
 *  <em>s</em><code>...</code><em>e</em> literals, or with
 *  <code>Range::new</code>. Ranges constructed using <code>..</code>
 *  run from the start to the end inclusively. Those created using
 *  <code>...</code> exclude the end value. When used as an iterator,
 *  ranges return each value in the sequence.
 *     
 *     (-1..-5).to_a      #=> []
 *     (-5..-1).to_a      #=> [-5, -4, -3, -2, -1]
 *     ('a'..'e').to_a    #=> ["a", "b", "c", "d", "e"]
 *     ('a'...'e').to_a   #=> ["a", "b", "c", "d"]
 *     
 *  Ranges can be constructed using objects of any type, as long as the
 *  objects can be compared using their <code><=></code> operator and
 *  they support the <code>succ</code> method to return the next object
 *  in sequence.
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
 *     r = Xs.new(3)..Xs.new(6)   #=> xxx..xxxxxx
 *     r.to_a                     #=> [xxx, xxxx, xxxxx, xxxxxx]
 *     r.member?(Xs.new(5))       #=> true
 *     
 *  In the previous code example, class <code>Xs</code> includes the
 *  <code>Comparable</code> module. This is because
 *  <code>Enumerable#member?</code> checks for equality using
 *  <code>==</code>. Including <code>Comparable</code> ensures that the
 *  <code>==</code> method is defined in terms of the <code><=></code>
 *  method implemented in <code>Xs</code>.
 *     
 */

void
Init_Range()
{
    rb_cRange = rb_define_class("Range", rb_cObject);
    rb_include_module(rb_cRange, rb_mEnumerable);
    rb_define_method(rb_cRange, "initialize", range_initialize, -1);
    rb_define_method(rb_cRange, "==", range_eq, 1);
    rb_define_method(rb_cRange, "===", range_include, 1);
    rb_define_method(rb_cRange, "eql?", range_eql, 1);
    rb_define_method(rb_cRange, "hash", range_hash, 0);
    rb_define_method(rb_cRange, "each", range_each, 0);
    rb_define_method(rb_cRange, "step", range_step, -1);
    rb_define_method(rb_cRange, "first", range_first, 0);
    rb_define_method(rb_cRange, "last", range_last, 0);
    rb_define_method(rb_cRange, "begin", range_first, 0);
    rb_define_method(rb_cRange, "end", range_last, 0);
    rb_define_method(rb_cRange, "to_s", range_to_s, 0);
    rb_define_method(rb_cRange, "inspect", range_inspect, 0);

    rb_define_method(rb_cRange, "exclude_end?", range_exclude_end_p, 0);

    rb_define_method(rb_cRange, "member?", range_include, 1);
    rb_define_method(rb_cRange, "include?", range_include, 1);

    id_cmp = rb_intern("<=>");
    id_succ = rb_intern("succ");
    id_beg = rb_intern("begin");
    id_end = rb_intern("end");
    id_excl = rb_intern("excl");
}
