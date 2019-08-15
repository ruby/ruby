/**********************************************************************

  compar.c -

  $Author$
  created at: Thu Aug 26 14:39:48 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "id.h"

VALUE rb_mComparable;

static VALUE
rb_cmp(VALUE x, VALUE y)
{
    return rb_funcallv(x, idCmp, 1, &y);
}

void
rb_cmperr(VALUE x, VALUE y)
{
    VALUE classname;

    if (SPECIAL_CONST_P(y) || BUILTIN_TYPE(y) == T_FLOAT) {
	classname = rb_inspect(y);
    }
    else {
	classname = rb_obj_class(y);
    }
    rb_raise(rb_eArgError, "comparison of %"PRIsVALUE" with %"PRIsVALUE" failed",
	     rb_obj_class(x), classname);
}

static VALUE
invcmp_recursive(VALUE x, VALUE y, int recursive)
{
    if (recursive) return Qnil;
    return rb_cmp(y, x);
}

VALUE
rb_invcmp(VALUE x, VALUE y)
{
    VALUE invcmp = rb_exec_recursive(invcmp_recursive, x, y);
    if (invcmp == Qundef || NIL_P(invcmp)) {
	return Qnil;
    }
    else {
	int result = -rb_cmpint(invcmp, x, y);
	return INT2FIX(result);
    }
}

static VALUE
cmp_eq_recursive(VALUE arg1, VALUE arg2, int recursive)
{
    if (recursive) return Qnil;
    return rb_cmp(arg1, arg2);
}

/*
 *  call-seq:
 *     obj == other    -> true or false
 *
 *  Compares two objects based on the receiver's <code><=></code>
 *  method, returning true if it returns 0. Also returns true if
 *  _obj_ and _other_ are the same object.
 */

static VALUE
cmp_equal(VALUE x, VALUE y)
{
    VALUE c;
    if (x == y) return Qtrue;

    c = rb_exec_recursive_paired_outer(cmp_eq_recursive, x, y, y);

    if (NIL_P(c)) return Qfalse;
    if (rb_cmpint(c, x, y) == 0) return Qtrue;
    return Qfalse;
}

static int
cmpint(VALUE x, VALUE y)
{
    return rb_cmpint(rb_cmp(x, y), x, y);
}

/*
 *  call-seq:
 *     obj > other    -> true or false
 *
 *  Compares two objects based on the receiver's <code><=></code>
 *  method, returning true if it returns a value greater than 0.
 */

static VALUE
cmp_gt(VALUE x, VALUE y)
{
    if (cmpint(x, y) > 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj >= other    -> true or false
 *
 *  Compares two objects based on the receiver's <code><=></code>
 *  method, returning true if it returns a value greater than or equal to 0.
 */

static VALUE
cmp_ge(VALUE x, VALUE y)
{
    if (cmpint(x, y) >= 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj < other    -> true or false
 *
 *  Compares two objects based on the receiver's <code><=></code>
 *  method, returning true if it returns a value less than 0.
 */

static VALUE
cmp_lt(VALUE x, VALUE y)
{
    if (cmpint(x, y) < 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj <= other    -> true or false
 *
 *  Compares two objects based on the receiver's <code><=></code>
 *  method, returning true if it returns a value less than or equal to 0.
 */

static VALUE
cmp_le(VALUE x, VALUE y)
{
    if (cmpint(x, y) <= 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj.between?(min, max)    -> true or false
 *
 *  Returns <code>false</code> if <i>obj</i> <code><=></code>
 *  <i>min</i> is less than zero or if <i>anObject</i> <code><=></code>
 *  <i>max</i> is greater than zero, <code>true</code> otherwise.
 *
 *     3.between?(1, 5)               #=> true
 *     6.between?(1, 5)               #=> false
 *     'cat'.between?('ant', 'dog')   #=> true
 *     'gnu'.between?('ant', 'dog')   #=> false
 *
 */

static VALUE
cmp_between(VALUE x, VALUE min, VALUE max)
{
    if (cmpint(x, min) < 0) return Qfalse;
    if (cmpint(x, max) > 0) return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     obj.clamp(min, max) ->  obj
 *
 * Returns <i>min</i> if <i>obj</i> <code><=></code> <i>min</i> is less
 * than zero, <i>max</i> if <i>obj</i> <code><=></code> <i>max</i> is
 * greater than zero and <i>obj</i> otherwise.
 *
 *     12.clamp(0, 100)         #=> 12
 *     523.clamp(0, 100)        #=> 100
 *     -3.123.clamp(0, 100)     #=> 0
 *
 *     'd'.clamp('a', 'f')      #=> 'd'
 *     'z'.clamp('a', 'f')      #=> 'f'
 */

static VALUE
cmp_clamp(VALUE x, VALUE min, VALUE max)
{
    int c;

    if (cmpint(min, max) > 0) {
	rb_raise(rb_eArgError, "min argument must be smaller than max argument");
    }

    c = cmpint(x, min);
    if (c == 0) return x;
    if (c < 0) return min;
    c = cmpint(x, max);
    if (c > 0) return max;
    return x;
}

/*
 *  The Comparable mixin is used by classes whose objects may be
 *  ordered. The class must define the <code><=></code> operator,
 *  which compares the receiver against another object, returning
 *  a value less than 0, 0, or a value greater than 0, depending on
 *  whether the receiver is less than, equal to,
 *  or greater than the other object. If the other object is not
 *  comparable then the <code><=></code> operator should return +nil+.
 *  Comparable uses <code><=></code> to implement the conventional
 *  comparison operators (<code><</code>, <code><=</code>,
 *  <code>==</code>, <code>>=</code>, and <code>></code>) and the
 *  method <code>between?</code>.
 *
 *     class SizeMatters
 *       include Comparable
 *       attr :str
 *       def <=>(other)
 *         str.size <=> other.str.size
 *       end
 *       def initialize(str)
 *         @str = str
 *       end
 *       def inspect
 *         @str
 *       end
 *     end
 *
 *     s1 = SizeMatters.new("Z")
 *     s2 = SizeMatters.new("YY")
 *     s3 = SizeMatters.new("XXX")
 *     s4 = SizeMatters.new("WWWW")
 *     s5 = SizeMatters.new("VVVVV")
 *
 *     s1 < s2                       #=> true
 *     s4.between?(s1, s3)           #=> false
 *     s4.between?(s3, s5)           #=> true
 *     [ s3, s2, s5, s4, s1 ].sort   #=> [Z, YY, XXX, WWWW, VVVVV]
 *
 */

void
Init_Comparable(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_mComparable = rb_define_module("Comparable");
    rb_define_method(rb_mComparable, "==", cmp_equal, 1);
    rb_define_method(rb_mComparable, ">", cmp_gt, 1);
    rb_define_method(rb_mComparable, ">=", cmp_ge, 1);
    rb_define_method(rb_mComparable, "<", cmp_lt, 1);
    rb_define_method(rb_mComparable, "<=", cmp_le, 1);
    rb_define_method(rb_mComparable, "between?", cmp_between, 2);
    rb_define_method(rb_mComparable, "clamp", cmp_clamp, 2);
}
