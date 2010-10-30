/**********************************************************************

  object.c -

  $Author$
  $Date$
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "st.h"
#include "util.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>

VALUE rb_mKernel;
VALUE rb_cObject;
VALUE rb_cModule;
VALUE rb_cClass;
VALUE rb_cData;

VALUE rb_cNilClass;
VALUE rb_cTrueClass;
VALUE rb_cFalseClass;
VALUE rb_cSymbol;

static ID id_eq, id_eql, id_inspect, id_init_copy;

/*
 *  call-seq:
 *     obj === other   => true or false
 *
 *  Case Equality---For class <code>Object</code>, effectively the same
 *  as calling  <code>#==</code>, but typically overridden by descendents
 *  to provide meaningful semantics in <code>case</code> statements.
 */

VALUE
rb_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    VALUE result;

    if (obj1 == obj2) return Qtrue;
    result = rb_funcall(obj1, id_eq, 1, obj2);
    if (RTEST(result)) return Qtrue;
    return Qfalse;
}

int
rb_eql(obj1, obj2)
    VALUE obj1, obj2;
{
    return RTEST(rb_funcall(obj1, id_eql, 1, obj2));
}

/*
 *  call-seq:
 *     obj == other        => true or false
 *     obj.equal?(other)   => true or false
 *     obj.eql?(other)     => true or false
 *
 *  Equality---At the <code>Object</code> level, <code>==</code> returns
 *  <code>true</code> only if <i>obj</i> and <i>other</i> are the
 *  same object. Typically, this method is overridden in descendent
 *  classes to provide class-specific meaning.
 *
 *  Unlike <code>==</code>, the <code>equal?</code> method should never be
 *  overridden by subclasses: it is used to determine object identity
 *  (that is, <code>a.equal?(b)</code> iff <code>a</code> is the same
 *  object as <code>b</code>).
 *
 *  The <code>eql?</code> method returns <code>true</code> if
    <i>obj</i> and <i>anObject</i> have the
 *  same value. Used by <code>Hash</code> to test members for equality.
 *  For objects of class <code>Object</code>, <code>eql?</code> is
 *  synonymous with <code>==</code>. Subclasses normally continue this
 *  tradition, but there are exceptions. <code>Numeric</code> types, for
 *  example, perform type conversion across <code>==</code>, but not
 *  across <code>eql?</code>, so:
 *
 *     1 == 1.0     #=> true
 *     1.eql? 1.0   #=> false
 */

static VALUE
rb_obj_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    if (obj1 == obj2) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj.id    => fixnum
 *
 *  Soon-to-be deprecated version of <code>Object#object_id</code>.
 */

VALUE
rb_obj_id_obsolete(obj)
    VALUE obj;
{
    rb_warn("Object#id is deprecated; use Object#object_id");
    return rb_obj_id(obj);
}

VALUE
rb_class_real(cl)
    VALUE cl;
{
    while (FL_TEST(cl, FL_SINGLETON) || TYPE(cl) == T_ICLASS) {
	cl = RCLASS(cl)->super;
    }
    return cl;
}

/*
 *  call-seq:
 *     obj.type   => class
 *
 *  Deprecated synonym for <code>Object#class</code>.
 */

VALUE
rb_obj_type(obj)
    VALUE obj;
{
    rb_warn("Object#type is deprecated; use Object#class");
    return rb_class_real(CLASS_OF(obj));
}


/*
 *  call-seq:
 *     obj.class    => class
 *
 *  Returns the class of <i>obj</i>, now preferred over
 *  <code>Object#type</code>, as an object's type in Ruby is only
 *  loosely tied to that object's class. This method must always be
 *  called with an explicit receiver, as <code>class</code> is also a
 *  reserved word in Ruby.
 *
 *     1.class      #=> Fixnum
 *     self.class   #=> Object
 */

VALUE
rb_obj_class(obj)
    VALUE obj;
{
    return rb_class_real(CLASS_OF(obj));
}

/*
 *  call-seq:
 *     obj.singleton_class    => class
 *
 *  Returns the singleton class of <i>obj</i>.  This method creates
 *  a new singleton class if <i>obj</i> does not have it.
 *
 *  If <i>obj</i> is <code>nil</code>, <code>true</code>, or
 *  <code>false</code>, it returns NilClass, TrueClass, or FalseClass,
 *  respectively.
 *  If <i>obj</i> is a Fixnum or a Symbol, it raises a TypeError.
 *
 *     Object.new.singleton_class  #=> #<Class:#<Object:0xb7ce1e24>>
 *     String.singleton_class      #=> #<Class:String>
 *     nil.singleton_class         #=> NilClass
 */

static VALUE
rb_obj_singleton_class(obj)
    VALUE obj;
{
    return rb_singleton_class(obj);
}

static void
init_copy(dest, obj)
    VALUE dest, obj;
{
    if (OBJ_FROZEN(dest)) {
        rb_raise(rb_eTypeError, "[bug] frozen object (%s) allocated", rb_obj_classname(dest));
    }
    RBASIC(dest)->flags &= ~(T_MASK|FL_EXIVAR);
    RBASIC(dest)->flags |= RBASIC(obj)->flags & (T_MASK|FL_EXIVAR|FL_TAINT);
    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_copy_generic_ivar(dest, obj);
    }
    rb_gc_copy_finalizer(dest, obj);
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(dest)->iv_tbl) {
	    st_free_table(ROBJECT(dest)->iv_tbl);
	    ROBJECT(dest)->iv_tbl = 0;
	}
	if (ROBJECT(obj)->iv_tbl) {
	    ROBJECT(dest)->iv_tbl = st_copy(ROBJECT(obj)->iv_tbl);
	}
    }
    rb_funcall(dest, id_init_copy, 1, obj);
}

/*
 *  call-seq:
 *     obj.clone -> an_object
 *
 *  Produces a shallow copy of <i>obj</i>---the instance variables of
 *  <i>obj</i> are copied, but not the objects they reference. Copies
 *  the frozen and tainted state of <i>obj</i>. See also the discussion
 *  under <code>Object#dup</code>.
 *
 *     class Klass
 *        attr_accessor :str
 *     end
 *     s1 = Klass.new      #=> #<Klass:0x401b3a38>
 *     s1.str = "Hello"    #=> "Hello"
 *     s2 = s1.clone       #=> #<Klass:0x401b3998 @str="Hello">
 *     s2.str[1,4] = "i"   #=> "i"
 *     s1.inspect          #=> "#<Klass:0x401b3a38 @str=\"Hi\">"
 *     s2.inspect          #=> "#<Klass:0x401b3998 @str=\"Hi\">"
 *
 *  This method may have class-specific behavior.  If so, that
 *  behavior will be documented under the #+initialize_copy+ method of
 *  the class.
 */

VALUE
rb_obj_clone(obj)
    VALUE obj;
{
    VALUE clone;

    if (rb_special_const_p(obj)) {
        rb_raise(rb_eTypeError, "can't clone %s", rb_obj_classname(obj));
    }
    clone = rb_obj_alloc(rb_obj_class(obj));
    RBASIC(clone)->klass = rb_singleton_class_clone(obj);
    RBASIC(clone)->flags = (RBASIC(obj)->flags | FL_TEST(clone, FL_TAINT)) & ~(FL_FREEZE|FL_FINALIZE);
    init_copy(clone, obj);
    RBASIC(clone)->flags |= RBASIC(obj)->flags & FL_FREEZE;

    return clone;
}

/*
 *  call-seq:
 *     obj.dup -> an_object
 *
 *  Produces a shallow copy of <i>obj</i>---the instance variables of
 *  <i>obj</i> are copied, but not the objects they reference.
 *  <code>dup</code> copies the tainted state of <i>obj</i>. See also
 *  the discussion under <code>Object#clone</code>. In general,
 *  <code>clone</code> and <code>dup</code> may have different semantics
 *  in descendent classes. While <code>clone</code> is used to duplicate
 *  an object, including its internal state, <code>dup</code> typically
 *  uses the class of the descendent object to create the new instance.
 *
 *  This method may have class-specific behavior.  If so, that
 *  behavior will be documented under the #+initialize_copy+ method of
 *  the class.
 */

VALUE
rb_obj_dup(obj)
    VALUE obj;
{
    VALUE dup;

    if (rb_special_const_p(obj)) {
        rb_raise(rb_eTypeError, "can't dup %s", rb_obj_classname(obj));
    }
    dup = rb_obj_alloc(rb_obj_class(obj));
    init_copy(dup, obj);

    return dup;
}

/* :nodoc: */
VALUE
rb_obj_init_copy(obj, orig)
    VALUE obj, orig;
{
    if (obj == orig) return obj;
    rb_check_frozen(obj);
    if (TYPE(obj) != TYPE(orig) || rb_obj_class(obj) != rb_obj_class(orig)) {
	rb_raise(rb_eTypeError, "initialize_copy should take same class object");
    }
    return obj;
}

/*
 *  call-seq:
 *     obj.to_a -> anArray
 *
 *  Returns an array representation of <i>obj</i>. For objects of class
 *  <code>Object</code> and others that don't explicitly override the
 *  method, the return value is an array containing <code>self</code>.
 *  However, this latter behavior will soon be obsolete.
 *
 *     self.to_a       #=> -:1: warning: Object#to_a is deprecated
 *     "hello".to_a    #=> ["hello"]
 *     Time.new.to_a   #=> [39, 54, 8, 9, 4, 2003, 3, 99, true, "CDT"]
 */


static VALUE
rb_any_to_a(obj)
    VALUE obj;
{
    rb_warn("Object#to_a is deprecated");
    return rb_ary_new3(1, obj);
}


/*
 *  call-seq:
 *     obj.to_s    => string
 *
 *  Returns a string representing <i>obj</i>. The default
 *  <code>to_s</code> prints the object's class and an encoding of the
 *  object id. As a special case, the top-level object that is the
 *  initial execution context of Ruby programs returns ``main.''
 */

VALUE
rb_any_to_s(obj)
    VALUE obj;
{
    const char *cname = rb_obj_classname(obj);
    size_t len;
    VALUE str;

    len = strlen(cname)+6+16;
    str = rb_str_new(0, len); /* 6:tags 16:addr */
    snprintf(RSTRING(str)->ptr, len+1, "#<%s:0x%lx>", cname, obj);
    RSTRING(str)->len = strlen(RSTRING(str)->ptr);
    if (OBJ_TAINTED(obj)) OBJ_TAINT(str);

    return str;
}

VALUE
rb_inspect(obj)
    VALUE obj;
{
    return rb_obj_as_string(rb_funcall(obj, id_inspect, 0, 0));
}

static int
inspect_i(id, value, str)
    ID id;
    VALUE value;
    VALUE str;
{
    VALUE str2;
    const char *ivname;

    /* need not to show internal data */
    if (CLASS_OF(value) == 0) return ST_CONTINUE;
    if (!rb_is_instance_id(id)) return ST_CONTINUE;
    if (RSTRING(str)->ptr[0] == '-') { /* first element */
	RSTRING(str)->ptr[0] = '#';
	rb_str_cat2(str, " ");
    }
    else {
	rb_str_cat2(str, ", ");
    }
    ivname = rb_id2name(id);
    rb_str_cat2(str, ivname);
    rb_str_cat2(str, "=");
    str2 = rb_inspect(value);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return ST_CONTINUE;
}

static VALUE
inspect_obj(obj, str)
    VALUE obj, str;
{
    st_foreach_safe(ROBJECT(obj)->iv_tbl, inspect_i, str);
    rb_str_cat2(str, ">");
    RSTRING(str)->ptr[0] = '#';
    OBJ_INFECT(str, obj);

    return str;
}

/*
 *  call-seq:
 *     obj.inspect   => string
 *
 *  Returns a string containing a human-readable representation of
 *  <i>obj</i>. If not overridden, uses the <code>to_s</code> method to
 *  generate the string.
 *
 *     [ 1, 2, 3..4, 'five' ].inspect   #=> "[1, 2, 3..4, \"five\"]"
 *     Time.new.inspect                 #=> "Wed Apr 09 08:54:39 CDT 2003"
 */


static VALUE
rb_obj_inspect(obj)
    VALUE obj;
{
    if (TYPE(obj) == T_OBJECT
	&& ROBJECT(obj)->iv_tbl
	&& ROBJECT(obj)->iv_tbl->num_entries > 0) {
	VALUE str;
	size_t len;
	const char *c = rb_obj_classname(obj);

	if (rb_inspecting_p(obj)) {
	    len = strlen(c)+10+16+1;
	    str = rb_str_new(0, len); /* 10:tags 16:addr 1:nul */
	    snprintf(RSTRING(str)->ptr, len, "#<%s:0x%lx ...>", c, obj);
	    RSTRING(str)->len = strlen(RSTRING(str)->ptr);
	    return str;
	}
	len = strlen(c)+6+16+1;
	str = rb_str_new(0, len);     /* 6:tags 16:addr 1:nul */
	snprintf(RSTRING(str)->ptr, len, "-<%s:0x%lx", c, obj);
	RSTRING(str)->len = strlen(RSTRING(str)->ptr);
	return rb_protect_inspect(inspect_obj, obj, str);
    }
    return rb_funcall(obj, rb_intern("to_s"), 0, 0);
}


/*
 *  call-seq:
 *     obj.instance_of?(class)    => true or false
 *
 *  Returns <code>true</code> if <i>obj</i> is an instance of the given
 *  class. See also <code>Object#kind_of?</code>.
 */

VALUE
rb_obj_is_instance_of(obj, c)
    VALUE obj, c;
{
    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
      case T_ICLASS:
	break;
      default:
	rb_raise(rb_eTypeError, "class or module required");
    }

    if (rb_obj_class(obj) == c) return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     obj.is_a?(class)       => true or false
 *     obj.kind_of?(class)    => true or false
 *
 *  Returns <code>true</code> if <i>class</i> is the class of
 *  <i>obj</i>, or if <i>class</i> is one of the superclasses of
 *  <i>obj</i> or modules included in <i>obj</i>.
 *
 *     module M;    end
 *     class A
 *       include M
 *     end
 *     class B < A; end
 *     class C < B; end
 *     b = B.new
 *     b.instance_of? A   #=> false
 *     b.instance_of? B   #=> true
 *     b.instance_of? C   #=> false
 *     b.instance_of? M   #=> false
 *     b.kind_of? A       #=> true
 *     b.kind_of? B       #=> true
 *     b.kind_of? C       #=> false
 *     b.kind_of? M       #=> true
 */

VALUE
rb_obj_is_kind_of(obj, c)
    VALUE obj, c;
{
    VALUE cl = CLASS_OF(obj);

    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
      case T_ICLASS:
	break;

      default:
	rb_raise(rb_eTypeError, "class or module required");
    }

    while (cl) {
	if (cl == c || RCLASS(cl)->m_tbl == RCLASS(c)->m_tbl)
	    return Qtrue;
	cl = RCLASS(cl)->super;
    }
    return Qfalse;
}


/*
 *  call-seq:
 *     obj.tap{|x|...}    => obj
 *
 *  Yields <code>x</code> to the block, and then returns <code>x</code>.
 *  The primary purpose of this method is to "tap into" a method chain,
 *  in order to perform operations on intermediate results within the chain.
 *
 *	(1..10).tap {
 *	  |x| puts "original: #{x.inspect}"
 *	}.to_a.tap {
 *	  |x| puts "array: #{x.inspect}"
 *	}.select {|x| x%2==0}.tap {
 *	  |x| puts "evens: #{x.inspect}"
 *	}.map {|x| x*x}.tap {
 *	  |x| puts "squares: #{x.inspect}"
 *	}
 *
 */

VALUE
rb_obj_tap(obj)
    VALUE obj;
{
    rb_yield(obj);
    return obj;
}


/*
 * Document-method: inherited
 *
 * call-seq:
 *    inherited(subclass)
 *
 * Callback invoked whenever a subclass of the current class is created.
 *
 * Example:
 *
 *    class Foo
 *       def self.inherited(subclass)
 *          puts "New subclass: #{subclass}"
 *       end
 *    end
 *
 *    class Bar < Foo
 *    end
 *
 *    class Baz < Bar
 *    end
 *
 * produces:
 *
 *    New subclass: Bar
 *    New subclass: Baz
 */

/*
 * Document-method: singleton_method_added
 *
 *  call-seq:
 *     singleton_method_added(symbol)
 *
 *  Invoked as a callback whenever a singleton method is added to the
 *  receiver.
 *
 *     module Chatty
 *       def Chatty.singleton_method_added(id)
 *         puts "Adding #{id.id2name}"
 *       end
 *       def self.one()     end
 *       def two()          end
 *       def Chatty.three() end
 *     end
 *
 *  <em>produces:</em>
 *
 *     Adding singleton_method_added
 *     Adding one
 *     Adding three
 *
 */

/*
 * Document-method: singleton_method_removed
 *
 *  call-seq:
 *     singleton_method_removed(symbol)
 *
 *  Invoked as a callback whenever a singleton method is removed from
 *  the receiver.
 *
 *     module Chatty
 *       def Chatty.singleton_method_removed(id)
 *         puts "Removing #{id.id2name}"
 *       end
 *       def self.one()     end
 *       def two()          end
 *       def Chatty.three() end
 *       class <<self
 *         remove_method :three
 *         remove_method :one
 *       end
 *     end
 *
 *  <em>produces:</em>
 *
 *     Removing three
 *     Removing one
 */

/*
 * Document-method: singleton_method_undefined
 *
 *  call-seq:
 *     singleton_method_undefined(symbol)
 *
 *  Invoked as a callback whenever a singleton method is undefined in
 *  the receiver.
 *
 *     module Chatty
 *       def Chatty.singleton_method_undefined(id)
 *         puts "Undefining #{id.id2name}"
 *       end
 *       def Chatty.one()   end
 *       class << self
 *          undef_method(:one)
 *       end
 *     end
 *
 *  <em>produces:</em>
 *
 *     Undefining one
 */


/*
 * Document-method: included
 *
 * call-seq:
 *    included( othermod )
 *
 * Callback invoked whenever the receiver is included in another
 * module or class. This should be used in preference to
 * <tt>Module.append_features</tt> if your code wants to perform some
 * action when a module is included in another.
 *
 *        module A
 *          def A.included(mod)
 *            puts "#{self} included in #{mod}"
 *          end
 *        end
 *        module Enumerable
 *          include A
 *        end
 */

/*
 * Document-method: initialize
 *
 * call-seq:
 *    Object.new
 *
 * Returns a new Object.
 */

/*
 * Not documented
 */

static VALUE
rb_obj_dummy()
{
    return Qnil;
}

/*
 *  call-seq:
 *     obj.tainted?    => true or false
 *
 *  Returns <code>true</code> if the object is tainted.
 */

VALUE
rb_obj_tainted(obj)
    VALUE obj;
{
    if (OBJ_TAINTED(obj))
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj.taint -> obj
 *
 *  Marks <i>obj</i> as tainted---if the <code>$SAFE</code> level is
 *  set appropriately, many method calls which might alter the running
 *  programs environment will refuse to accept tainted strings.
 */

VALUE
rb_obj_taint(obj)
    VALUE obj;
{
    rb_secure(4);
    if (!OBJ_TAINTED(obj)) {
	if (OBJ_FROZEN(obj)) {
	    rb_error_frozen("object");
	}
	OBJ_TAINT(obj);
    }
    return obj;
}


/*
 *  call-seq:
 *     obj.untaint    => obj
 *
 *  Removes the taint from <i>obj</i>.
 */

VALUE
rb_obj_untaint(obj)
    VALUE obj;
{
    rb_secure(3);
    if (OBJ_TAINTED(obj)) {
	if (OBJ_FROZEN(obj)) {
	    rb_error_frozen("object");
	}
	FL_UNSET(obj, FL_TAINT);
    }
    return obj;
}

void
rb_obj_infect(obj1, obj2)
    VALUE obj1, obj2;
{
    OBJ_INFECT(obj1, obj2);
}


/*
 *  call-seq:
 *     obj.freeze    => obj
 *
 *  Prevents further modifications to <i>obj</i>. A
 *  <code>TypeError</code> will be raised if modification is attempted.
 *  There is no way to unfreeze a frozen object. See also
 *  <code>Object#frozen?</code>.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze
 *     a << "z"
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3:in `<<': can't modify frozen array (TypeError)
 *     	from prog.rb:3
 */

VALUE
rb_obj_freeze(obj)
    VALUE obj;
{
    if (!OBJ_FROZEN(obj)) {
	if (rb_safe_level() >= 4 && !OBJ_TAINTED(obj)) {
	    rb_raise(rb_eSecurityError, "Insecure: can't freeze object");
	}
	OBJ_FREEZE(obj);
    }
    return obj;
}

/*
 *  call-seq:
 *     obj.frozen?    => true or false
 *
 *  Returns the freeze status of <i>obj</i>.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze    #=> ["a", "b", "c"]
 *     a.frozen?   #=> true
 */

static VALUE
rb_obj_frozen_p(obj)
    VALUE obj;
{
    if (OBJ_FROZEN(obj)) return Qtrue;
    return Qfalse;
}


/*
 * Document-class: NilClass
 *
 *  The class of the singleton object <code>nil</code>.
 */

/*
 *  call-seq:
 *     nil.to_i => 0
 *
 *  Always returns zero.
 *
 *     nil.to_i   #=> 0
 */


static VALUE
nil_to_i(obj)
    VALUE obj;
{
    return INT2FIX(0);
}

/*
 *  call-seq:
 *     nil.to_f    => 0.0
 *
 *  Always returns zero.
 *
 *     nil.to_f   #=> 0.0
 */

static VALUE
nil_to_f(obj)
    VALUE obj;
{
    return rb_float_new(0.0);
}

/*
 *  call-seq:
 *     nil.to_s    => ""
 *
 *  Always returns the empty string.
 *
 *     nil.to_s   #=> ""
 */

static VALUE
nil_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("");
}

/*
 *  call-seq:
 *     nil.to_a    => []
 *
 *  Always returns an empty array.
 *
 *     nil.to_a   #=> []
 */

static VALUE
nil_to_a(obj)
    VALUE obj;
{
    return rb_ary_new2(0);
}

/*
 *  call-seq:
 *    nil.inspect  => "nil"
 *
 *  Always returns the string "nil".
 */

static VALUE
nil_inspect(obj)
    VALUE obj;
{
    return rb_str_new2("nil");
}

static VALUE
main_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("main");
}


/***********************************************************************
 *  Document-class: TrueClass
 *
 *  The global value <code>true</code> is the only instance of class
 *  <code>TrueClass</code> and represents a logically true value in
 *  boolean expressions. The class provides operators allowing
 *  <code>true</code> to be used in logical expressions.
 */


/*
 * call-seq:
 *   true.to_s   =>  "true"
 *
 * The string representation of <code>true</code> is "true".
 */

static VALUE
true_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("true");
}


/*
 *  call-seq:
 *     true & obj    => true or false
 *
 *  And---Returns <code>false</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>, <code>true</code> otherwise.
 */

static VALUE
true_and(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

/*
 *  call-seq:
 *     true | obj   => true
 *
 *  Or---Returns <code>true</code>. As <i>anObject</i> is an argument to
 *  a method call, it is always evaluated; there is no short-circuit
 *  evaluation in this case.
 *
 *     true |  puts("or")
 *     true || puts("logical or")
 *
 *  <em>produces:</em>
 *
 *     or
 */

static VALUE
true_or(obj, obj2)
    VALUE obj, obj2;
{
    return Qtrue;
}


/*
 *  call-seq:
 *     true ^ obj   => !obj
 *
 *  Exclusive Or---Returns <code>true</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>, <code>false</code>
 *  otherwise.
 */

static VALUE
true_xor(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qfalse:Qtrue;
}


/*
 *  Document-class: FalseClass
 *
 *  The global value <code>false</code> is the only instance of class
 *  <code>FalseClass</code> and represents a logically false value in
 *  boolean expressions. The class provides operators allowing
 *  <code>false</code> to participate correctly in logical expressions.
 *
 */

/*
 * call-seq:
 *   false.to_s   =>  "false"
 *
 * 'nuf said...
 */

static VALUE
false_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("false");
}

/*
 *  call-seq:
 *     false & obj   => false
 *     nil & obj     => false
 *
 *  And---Returns <code>false</code>. <i>obj</i> is always
 *  evaluated as it is the argument to a method call---there is no
 *  short-circuit evaluation in this case.
 */

static VALUE
false_and(obj, obj2)
    VALUE obj, obj2;
{
    return Qfalse;
}


/*
 *  call-seq:
 *     false | obj   =>   true or false
 *     nil   | obj   =>   true or false
 *
 *  Or---Returns <code>false</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>; <code>true</code> otherwise.
 */

static VALUE
false_or(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}



/*
 *  call-seq:
 *     false ^ obj    => true or false
 *     nil   ^ obj    => true or false
 *
 *  Exclusive Or---If <i>obj</i> is <code>nil</code> or
 *  <code>false</code>, returns <code>false</code>; otherwise, returns
 *  <code>true</code>.
 *
 */

static VALUE
false_xor(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

/*
 * call_seq:
 *   nil.nil?               => true
 *
 * Only the object <i>nil</i> responds <code>true</code> to <code>nil?</code>.
 */

static VALUE
rb_true(obj)
    VALUE obj;
{
    return Qtrue;
}

/*
 * call_seq:
 *   nil.nil?               => true
 *   <anything_else>.nil?   => false
 *
 * Only the object <i>nil</i> responds <code>true</code> to <code>nil?</code>.
 */


static VALUE
rb_false(obj)
    VALUE obj;
{
    return Qfalse;
}


/*
 *  call-seq:
 *     obj =~ other  => false
 *
 *  Pattern Match---Overridden by descendents (notably
 *  <code>Regexp</code> and <code>String</code>) to provide meaningful
 *  pattern-match semantics.
 */

static VALUE
rb_obj_pattern_match(obj1, obj2)
    VALUE obj1, obj2;
{
    return Qfalse;
}

/**********************************************************************
 * Document-class: Symbol
 *
 *  <code>Symbol</code> objects represent names and some strings
 *  inside the Ruby
 *  interpreter. They are generated using the <code>:name</code> and
 *  <code>:"string"</code> literals
 *  syntax, and by the various <code>to_sym</code> methods. The same
 *  <code>Symbol</code> object will be created for a given name or string
 *  for the duration of a program's execution, regardless of the context
 *  or meaning of that name. Thus if <code>Fred</code> is a constant in
 *  one context, a method in another, and a class in a third, the
 *  <code>Symbol</code> <code>:Fred</code> will be the same object in
 *  all three contexts.
 *
 *     module One
 *       class Fred
 *       end
 *       $f1 = :Fred
 *     end
 *     module Two
 *       Fred = 1
 *       $f2 = :Fred
 *     end
 *     def Fred()
 *     end
 *     $f3 = :Fred
 *     $f1.id   #=> 2514190
 *     $f2.id   #=> 2514190
 *     $f3.id   #=> 2514190
 *
 */

/*
 *  call-seq:
 *     sym.to_i      => fixnum
 *
 *  Returns an integer that is unique for each symbol within a
 *  particular execution of a program.
 *
 *     :fred.to_i           #=> 9809
 *     "fred".to_sym.to_i   #=> 9809
 */

static VALUE
sym_to_i(sym)
    VALUE sym;
{
    ID id = SYM2ID(sym);

    rb_warning("Symbol#to_i is deprecated");
    return LONG2FIX(id);
}


/* :nodoc: */

static VALUE
sym_to_int(sym)
    VALUE sym;
{
    ID id = SYM2ID(sym);

    rb_warning("treating Symbol as an integer");
    return LONG2FIX(id);
}


/*
 *  call-seq:
 *     sym.inspect    => string
 *
 *  Returns the representation of <i>sym</i> as a symbol literal.
 *
 *     :fred.inspect   #=> ":fred"
 */

static VALUE
sym_inspect(sym)
    VALUE sym;
{
    VALUE str;
    const char *name;
    ID id = SYM2ID(sym);

    name = rb_id2name(id);
    str = rb_str_new(0, strlen(name)+1);
    RSTRING(str)->ptr[0] = ':';
    strcpy(RSTRING(str)->ptr+1, name);
    if (!rb_symname_p(name)) {
	str = rb_str_dump(str);
	strncpy(RSTRING(str)->ptr, ":\"", 2);
    }
    return str;
}


/*
 *  call-seq:
 *     sym.id2name   => string
 *     sym.to_s      => string
 *
 *  Returns the name or string corresponding to <i>sym</i>.
 *
 *     :fred.id2name   #=> "fred"
 */


VALUE
rb_sym_to_s(sym)
    VALUE sym;
{
    return rb_str_new2(rb_id2name(SYM2ID(sym)));
}


/*
 * call-seq:
 *   sym.to_sym   => sym
 *
 * In general, <code>to_sym</code> returns the <code>Symbol</code> corresponding
 * to an object. As <i>sym</i> is already a symbol, <code>self</code> is returned
 * in this case.
 */

static VALUE
sym_to_sym(sym)
    VALUE sym;
{
    return sym;
}


static VALUE
sym_call(args, mid)
    VALUE args, mid;
{
    VALUE obj;

    if (RARRAY(args)->len < 1) {
	rb_raise(rb_eArgError, "no receiver given");
    }
    obj = rb_ary_shift(args);
    return rb_apply(obj, (ID)mid, args);
}

VALUE rb_proc_new _((VALUE (*)(ANYARGS/* VALUE yieldarg[, VALUE procarg] */), VALUE));

/*
 * call-seq:
 *   sym.to_proc
 *
 * Returns a _Proc_ object which respond to the given method by _sym_.
 *
 *   (1..3).collect(&:to_s)  #=> ["1", "2", "3"]
 */

static VALUE
sym_to_proc(sym)
    VALUE sym;
{
    return rb_proc_new(sym_call, (VALUE)SYM2ID(sym));
}


/***********************************************************************
 *
 * Document-class: Module
 *
 *  A <code>Module</code> is a collection of methods and constants. The
 *  methods in a module may be instance methods or module methods.
 *  Instance methods appear as methods in a class when the module is
 *  included, module methods do not. Conversely, module methods may be
 *  called without creating an encapsulating object, while instance
 *  methods may not. (See <code>Module#module_function</code>)
 *
 *  In the descriptions that follow, the parameter <i>syml</i> refers
 *  to a symbol, which is either a quoted string or a
 *  <code>Symbol</code> (such as <code>:name</code>).
 *
 *     module Mod
 *       include Math
 *       CONST = 1
 *       def meth
 *         #  ...
 *       end
 *     end
 *     Mod.class              #=> Module
 *     Mod.constants          #=> ["E", "PI", "CONST"]
 *     Mod.instance_methods   #=> ["meth"]
 *
 */

/*
 * call-seq:
 *   mod.to_s   => string
 *
 * Return a string representing this module or class. For basic
 * classes and modules, this is the name. For singletons, we
 * show information on the thing we're attached to as well.
 */

static VALUE
rb_mod_to_s(klass)
    VALUE klass;

{
    if (FL_TEST(klass, FL_SINGLETON)) {
	VALUE s = rb_str_new2("#<");
	VALUE v = rb_iv_get(klass, "__attached__");

	rb_str_cat2(s, "Class:");
	switch (TYPE(v)) {
	  case T_CLASS: case T_MODULE:
	    rb_str_append(s, rb_inspect(v));
	    break;
	  default:
	    rb_str_append(s, rb_any_to_s(v));
	    break;
	}
	rb_str_cat2(s, ">");

	return s;
    }
    return rb_str_dup(rb_class_name(klass));
}

/*
 *  call-seq:
 *     mod.freeze
 *
 *  Prevents further modifications to <i>mod</i>.
 */

static VALUE
rb_mod_freeze(mod)
    VALUE mod;
{
    rb_mod_to_s(mod);
    return rb_obj_freeze(mod);
}

/*
 *  call-seq:
 *     mod === obj    => true or false
 *
 *  Case Equality---Returns <code>true</code> if <i>anObject</i> is an
 *  instance of <i>mod</i> or one of <i>mod</i>'s descendents. Of
 *  limited use for modules, but can be used in <code>case</code>
 *  statements to classify objects by class.
 */

static VALUE
rb_mod_eqq(mod, arg)
    VALUE mod, arg;
{
    return rb_obj_is_kind_of(arg, mod);
}

/*
 * call-seq:
 *   mod <= other   =>  true, false, or nil
 *
 * Returns true if <i>mod</i> is a subclass of <i>other</i> or
 * is the same as <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "A<B").
 *
 */

VALUE
rb_class_inherited_p(mod, arg)
    VALUE mod, arg;
{
    VALUE start = mod;

    if (mod == arg) return Qtrue;
    switch (TYPE(arg)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	rb_raise(rb_eTypeError, "compared with non class/module");
    }

    if (FL_TEST(mod, FL_SINGLETON)) {
	if (RCLASS(mod)->m_tbl == RCLASS(arg)->m_tbl)
	    return Qtrue;
	mod = RBASIC(mod)->klass;
    }
    while (mod) {
	if (RCLASS(mod)->m_tbl == RCLASS(arg)->m_tbl)
	    return Qtrue;
	mod = RCLASS(mod)->super;
    }
    /* not mod < arg; check if mod > arg */
    while (arg) {
	if (RCLASS(arg)->m_tbl == RCLASS(start)->m_tbl)
	    return Qfalse;
	arg = RCLASS(arg)->super;
    }
    return Qnil;
}

/*
 * call-seq:
 *   mod < other   =>  true, false, or nil
 *
 * Returns true if <i>mod</i> is a subclass of <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "A<B").
 *
 */

static VALUE
rb_mod_lt(mod, arg)
    VALUE mod, arg;
{
    if (mod == arg) return Qfalse;
    return rb_class_inherited_p(mod, arg);
}


/*
 * call-seq:
 *   mod >= other   =>  true, false, or nil
 *
 * Returns true if <i>mod</i> is an ancestor of <i>other</i>, or the
 * two modules are the same. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "B>A").
 *
 */

static VALUE
rb_mod_ge(mod, arg)
    VALUE mod, arg;
{
    switch (TYPE(arg)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	rb_raise(rb_eTypeError, "compared with non class/module");
    }

    return rb_class_inherited_p(arg, mod);
}

/*
 * call-seq:
 *   mod > other   =>  true, false, or nil
 *
 * Returns true if <i>mod</i> is an ancestor of <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "B>A").
 *
 */

static VALUE
rb_mod_gt(mod, arg)
    VALUE mod, arg;
{
    if (mod == arg) return Qfalse;
    return rb_mod_ge(mod, arg);
}

/*
 *  call-seq:
 *     mod <=> other_mod   => -1, 0, +1, or nil
 *
 *  Comparison---Returns -1 if <i>mod</i> includes <i>other_mod</i>, 0 if
 *  <i>mod</i> is the same as <i>other_mod</i>, and +1 if <i>mod</i> is
 *  included by <i>other_mod</i> or if <i>mod</i> has no relationship with
 *  <i>other_mod</i>. Returns <code>nil</code> if <i>other_mod</i> is
 *  not a module.
 */

static VALUE
rb_mod_cmp(mod, arg)
    VALUE mod, arg;
{
    VALUE cmp;

    if (mod == arg) return INT2FIX(0);
    switch (TYPE(arg)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	return Qnil;
    }

    cmp = rb_class_inherited_p(mod, arg);
    if (NIL_P(cmp)) return Qnil;
    if (cmp) {
	return INT2FIX(-1);
    }
    return INT2FIX(1);
}

static VALUE rb_module_s_alloc _((VALUE));
static VALUE
rb_module_s_alloc(klass)
    VALUE klass;
{
    VALUE mod = rb_module_new();

    RBASIC(mod)->klass = klass;
    return mod;
}

static VALUE rb_class_s_alloc _((VALUE));
static VALUE
rb_class_s_alloc(klass)
    VALUE klass;
{
    return rb_class_boot(0);
}

/*
 *  call-seq:
 *    Module.new                  => mod
 *    Module.new {|mod| block }   => mod
 *
 *  Creates a new anonymous module. If a block is given, it is passed
 *  the module object, and the block is evaluated in the context of this
 *  module using <code>module_eval</code>.
 *
 *     Fred = Module.new do
 *       def meth1
 *         "hello"
 *       end
 *       def meth2
 *         "bye"
 *       end
 *     end
 *     a = "my string"
 *     a.extend(Fred)   #=> "my string"
 *     a.meth1          #=> "hello"
 *     a.meth2          #=> "bye"
 */

static VALUE
rb_mod_initialize(module)
    VALUE module;
{
    if (rb_block_given_p()) {
	rb_mod_module_eval(0, 0, module);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     Class.new(super_class=Object)   =>    a_class
 *
 *  Creates a new anonymous (unnamed) class with the given superclass
 *  (or <code>Object</code> if no parameter is given). You can give a
 *  class a name by assigning the class object to a constant.
 *
 */

static VALUE
rb_class_initialize(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE super;

    if (RCLASS(klass)->super != 0) {
	rb_raise(rb_eTypeError, "already initialized class");
    }
    if (rb_scan_args(argc, argv, "01", &super) == 0) {
	super = rb_cObject;
    }
    else {
	rb_check_inheritable(super);
    }
    RCLASS(klass)->super = super;
    rb_make_metaclass(klass, RBASIC(super)->klass);
    rb_class_inherited(super, klass);
    rb_mod_initialize(klass);

    return klass;
}

/*
 *  call-seq:
 *     class.allocate()   =>   obj
 *
 *  Allocates space for a new object of <i>class</i>'s class and does not
 *  call initialize on the new instance. The returned object must be an
 *  instance of <i>class</i>.
 *
 *      klass = Class.new do
 *        def initialize(*args)
 *          @initialized = true
 *        end
 *
 *        def initialized?
 *          @initialized || false
 *        end
 *      end
 *
 *      klass.allocate.initialized? #=> false
 *
 */

VALUE
rb_obj_alloc(klass)
    VALUE klass;
{
    VALUE obj;

    if (RCLASS(klass)->super == 0) {
	rb_raise(rb_eTypeError, "can't instantiate uninitialized class");
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't create instance of virtual class");
    }
    obj = rb_funcall(klass, ID_ALLOCATOR, 0, 0);
    if (rb_obj_class(obj) != rb_class_real(klass)) {
	rb_raise(rb_eTypeError, "wrong instance allocation");
    }
    return obj;
}

static VALUE rb_class_allocate_instance _((VALUE));
static VALUE
rb_class_allocate_instance(klass)
    VALUE klass;
{
    NEWOBJ(obj, struct RObject);
    OBJSETUP(obj, klass, T_OBJECT);
    return (VALUE)obj;
}

/*
 *  call-seq:
 *     class.new(args, ...)    =>  obj
 *
 *  Calls <code>allocate</code> to create a new object of
 *  <i>class</i>'s class, then invokes that object's
 *  <code>initialize</code> method, passing it <i>args</i>.
 *  This is the method that ends up getting called whenever
 *  an object is constructed using .new.
 *
 */

VALUE
rb_class_new_instance(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj;

    obj = rb_obj_alloc(klass);
    rb_obj_call_init(obj, argc, argv);

    return obj;
}

/*
 *  call-seq:
 *     class.superclass -> a_super_class or nil
 *
 *  Returns the superclass of <i>class</i>, or <code>nil</code>.
 *
 *     File.superclass         #=> IO
 *     IO.superclass           #=> Object
 *
 *     class Foo; end
 *     class Bar < Foo; end
 *     Bar.superclass          #=> Foo
 *
 *  returns nil when the given class hasn't a parent class:
 *
 *     Object.superclass       #=> nil
 *
 */

static VALUE
rb_class_superclass(klass)
    VALUE klass;
{
    VALUE super = RCLASS(klass)->super;

    if (!super) {
	rb_raise(rb_eTypeError, "uninitialized class");
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	super = RBASIC(klass)->klass;
    }
    while (TYPE(super) == T_ICLASS) {
	super = RCLASS(super)->super;
    }
    if (!super) {
	return Qnil;
    }
    return super;
}

static ID
str_to_id(str)
    VALUE str;
{
    VALUE sym = rb_str_intern(str);

    return SYM2ID(sym);
}

ID
rb_to_id(name)
    VALUE name;
{
    VALUE tmp;
    ID id;

    switch (TYPE(name)) {
      case T_STRING:
	return str_to_id(name);
      case T_FIXNUM:
	rb_warn("do not use Fixnums as Symbols");
	id = FIX2LONG(name);
	if (!rb_id2name(id)) {
	    rb_raise(rb_eArgError, "%ld is not a symbol", id);
	}
	break;
      case T_SYMBOL:
	id = SYM2ID(name);
	break;
      default:
	tmp = rb_check_string_type(name);
	if (!NIL_P(tmp)) {
	    return str_to_id(tmp);
	}
	rb_raise(rb_eTypeError, "%s is not a symbol", RSTRING(rb_inspect(name))->ptr);
    }
    return id;
}

/*
 *  call-seq:
 *     attr(symbol, writable=false)    => nil
 *
 *  Defines a named attribute for this module, where the name is
 *  <i>symbol.</i><code>id2name</code>, creating an instance variable
 *  (<code>@name</code>) and a corresponding access method to read it.
 *  If the optional <i>writable</i> argument is <code>true</code>, also
 *  creates a method called <code>name=</code> to set the attribute.
 *
 *     module Mod
 *       attr  :size, true
 *     end
 *
 *  <em>is equivalent to:</em>
 *
 *     module Mod
 *       def size
 *         @size
 *       end
 *       def size=(val)
 *         @size = val
 *       end
 *     end
 */

static VALUE
rb_mod_attr(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE name, pub;

    rb_scan_args(argc, argv, "11", &name, &pub);
    rb_attr(klass, rb_to_id(name), 1, RTEST(pub), Qtrue);
    return Qnil;
}

/*
 *  call-seq:
 *     attr_reader(symbol, ...)    => nil
 *
 *  Creates instance variables and corresponding methods that return the
 *  value of each instance variable. Equivalent to calling
 *  ``<code>attr</code><i>:name</i>'' on each name in turn.
 */

static VALUE
rb_mod_attr_reader(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, rb_to_id(argv[i]), 1, 0, Qtrue);
    }
    return Qnil;
}

/*
 *  call-seq:
 *      attr_writer(symbol, ...)    => nil
 *
 *  Creates an accessor method to allow assignment to the attribute
 *  <i>aSymbol</i><code>.id2name</code>.
 */

static VALUE
rb_mod_attr_writer(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, rb_to_id(argv[i]), 0, 1, Qtrue);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     attr_accessor(symbol, ...)    => nil
 *
 *  Equivalent to calling ``<code>attr</code><i>symbol</i><code>,
 *  true</code>'' on each <i>symbol</i> in turn.
 *
 *     module Mod
 *       attr_accessor(:one, :two)
 *     end
 *     Mod.instance_methods.sort   #=> ["one", "one=", "two", "two="]
 */

static VALUE
rb_mod_attr_accessor(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, rb_to_id(argv[i]), 1, 1, Qtrue);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     mod.const_get(sym)    => obj
 *
 *  Returns the value of the named constant in <i>mod</i>.
 *
 *     Math.const_get(:PI)   #=> 3.14159265358979
 */

static VALUE
rb_mod_const_get(mod, name)
    VALUE mod, name;
{
    ID id = rb_to_id(name);

    if (!rb_is_const_id(id)) {
	rb_name_error(id, "wrong constant name %s", rb_id2name(id));
    }
    return rb_const_get(mod, id);
}

/*
 *  call-seq:
 *     mod.const_set(sym, obj)    => obj
 *
 *  Sets the named constant to the given object, returning that object.
 *  Creates a new constant if no constant with the given name previously
 *  existed.
 *
 *     Math.const_set("HIGH_SCHOOL_PI", 22.0/7.0)   #=> 3.14285714285714
 *     Math::HIGH_SCHOOL_PI - Math::PI              #=> 0.00126448926734968
 */

static VALUE
rb_mod_const_set(mod, name, value)
    VALUE mod, name, value;
{
    ID id = rb_to_id(name);

    if (!rb_is_const_id(id)) {
	rb_name_error(id, "wrong constant name %s", rb_id2name(id));
    }
    rb_const_set(mod, id, value);
    return value;
}

/*
 *  call-seq:
 *     mod.const_defined?(sym)   => true or false
 *
 *  Returns <code>true</code> if a constant with the given name is
 *  defined by <i>mod</i>.
 *
 *     Math.const_defined? "PI"   #=> true
 */

static VALUE
rb_mod_const_defined(mod, name)
    VALUE mod, name;
{
    ID id = rb_to_id(name);

    if (!rb_is_const_id(id)) {
	rb_name_error(id, "wrong constant name %s", rb_id2name(id));
    }
    return rb_const_defined_at(mod, id);
}

/*
 *  call-seq:
 *     obj.methods    => array
 *
 *  Returns a list of the names of methods publicly accessible in
 *  <i>obj</i>. This will include all the methods accessible in
 *  <i>obj</i>'s ancestors.
 *
 *     class Klass
 *       def kMethod()
 *       end
 *     end
 *     k = Klass.new
 *     k.methods[0..9]    #=> ["kMethod", "freeze", "nil?", "is_a?",
 *                             "class", "instance_variable_set",
 *                              "methods", "extend", "__send__", "instance_eval"]
 *     k.methods.length   #=> 42
 */

static VALUE
rb_obj_methods(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
  retry:
    if (argc == 0) {
	VALUE args[1];

	args[0] = Qtrue;
	return rb_class_instance_methods(1, args, CLASS_OF(obj));
    }
    else {
	VALUE recur;

	rb_scan_args(argc, argv, "1", &recur);
	if (RTEST(recur)) {
	    argc = 0;
	    goto retry;
	}
	return rb_obj_singleton_methods(argc, argv, obj);
    }
}

/*
 *  call-seq:
 *     obj.protected_methods(all=true)   => array
 *
 *  Returns the list of protected methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

static VALUE
rb_obj_protected_methods(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    if (argc == 0) {		/* hack to stop warning */
	VALUE args[1];

	args[0] = Qtrue;
	return rb_class_protected_instance_methods(1, args, CLASS_OF(obj));
    }
    return rb_class_protected_instance_methods(argc, argv, CLASS_OF(obj));
}

/*
 *  call-seq:
 *     obj.private_methods(all=true)   => array
 *
 *  Returns the list of private methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

static VALUE
rb_obj_private_methods(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    if (argc == 0) {		/* hack to stop warning */
	VALUE args[1];

	args[0] = Qtrue;
	return rb_class_private_instance_methods(1, args, CLASS_OF(obj));
    }
    return rb_class_private_instance_methods(argc, argv, CLASS_OF(obj));
}

/*
 *  call-seq:
 *     obj.public_methods(all=true)   => array
 *
 *  Returns the list of public methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

static VALUE
rb_obj_public_methods(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    if (argc == 0) {		/* hack to stop warning */
	VALUE args[1];

	args[0] = Qtrue;
	return rb_class_public_instance_methods(1, args, CLASS_OF(obj));
    }
    return rb_class_public_instance_methods(argc, argv, CLASS_OF(obj));
}

/*
 *  call-seq:
 *     obj.instance_variable_get(symbol)    => obj
 *
 *  Returns the value of the given instance variable, or nil if the
 *  instance variable is not set. The <code>@</code> part of the
 *  variable name should be included for regular instance
 *  variables. Throws a <code>NameError</code> exception if the
 *  supplied symbol is not valid as an instance variable name.
 *
 *     class Fred
 *       def initialize(p1, p2)
 *         @a, @b = p1, p2
 *       end
 *     end
 *     fred = Fred.new('cat', 99)
 *     fred.instance_variable_get(:@a)    #=> "cat"
 *     fred.instance_variable_get("@b")   #=> 99
 */

static VALUE
rb_obj_ivar_get(obj, iv)
    VALUE obj, iv;
{
    ID id = rb_to_id(iv);

    if (!rb_is_instance_id(id)) {
	rb_name_error(id, "`%s' is not allowed as an instance variable name", rb_id2name(id));
    }
    return rb_ivar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.instance_variable_set(symbol, obj)    => obj
 *
 *  Sets the instance variable names by <i>symbol</i> to
 *  <i>object</i>, thereby frustrating the efforts of the class's
 *  author to attempt to provide proper encapsulation. The variable
 *  did not have to exist prior to this call.
 *
 *     class Fred
 *       def initialize(p1, p2)
 *         @a, @b = p1, p2
 *       end
 *     end
 *     fred = Fred.new('cat', 99)
 *     fred.instance_variable_set(:@a, 'dog')   #=> "dog"
 *     fred.instance_variable_set(:@c, 'cat')   #=> "cat"
 *     fred.inspect                             #=> "#<Fred:0x401b3da8 @a=\"dog\", @b=99, @c=\"cat\">"
 */

static VALUE
rb_obj_ivar_set(obj, iv, val)
    VALUE obj, iv, val;
{
    ID id = rb_to_id(iv);

    if (!rb_is_instance_id(id)) {
	rb_name_error(id, "`%s' is not allowed as an instance variable name", rb_id2name(id));
    }
    return rb_ivar_set(obj, id, val);
}

/*
 *  call-seq:
 *     obj.instance_variable_defined?(symbol)    => true or false
 *
 *  Returns <code>true</code> if the given instance variable is
 *  defined in <i>obj</i>.
 *
 *     class Fred
 *       def initialize(p1, p2)
 *         @a, @b = p1, p2
 *       end
 *     end
 *     fred = Fred.new('cat', 99)
 *     fred.instance_variable_defined?(:@a)    #=> true
 *     fred.instance_variable_defined?("@b")   #=> true
 *     fred.instance_variable_defined?("@c")   #=> false
 */

static VALUE
rb_obj_ivar_defined(obj, iv)
    VALUE obj, iv;
{
    ID id = rb_to_id(iv);

    if (!rb_is_instance_id(id)) {
	rb_name_error(id, "`%s' is not allowed as an instance variable name", rb_id2name(id));
    }
    return rb_ivar_defined(obj, id);
}

/*
 *  call-seq:
 *     mod.class_variable_get(symbol)    => obj
 *
 *  Returns the value of the given class variable (or throws a
 *  <code>NameError</code> exception). The <code>@@</code> part of the
 *  variable name should be included for regular class variables
 *
 *     class Fred
 *       @@foo = 99
 *     end
 *
 *     def Fred.foo
 *       class_variable_get(:@@foo)     #=> 99
 *     end
 */

static VALUE
rb_mod_cvar_get(obj, iv)
    VALUE obj, iv;
{
    ID id = rb_to_id(iv);

    if (!rb_is_class_id(id)) {
	rb_name_error(id, "`%s' is not allowed as a class variable name", rb_id2name(id));
    }
    return rb_cvar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.class_variable_set(symbol, obj)    => obj
 *
 *  Sets the class variable names by <i>symbol</i> to
 *  <i>object</i>.
 *
 *     class Fred
 *       @@foo = 99
 *       def foo
 *         @@foo
 *       end
 *     end
 *
 *     def Fred.foo
 *       class_variable_set(:@@foo, 101)      #=> 101
 *     end
 *     Fred.foo
 *     Fred.new.foo                             #=> 101
 */

static VALUE
rb_mod_cvar_set(obj, iv, val)
    VALUE obj, iv, val;
{
    ID id = rb_to_id(iv);

    if (!rb_is_class_id(id)) {
	rb_name_error(id, "`%s' is not allowed as a class variable name", rb_id2name(id));
    }
    rb_cvar_set(obj, id, val, Qfalse);
    return val;
}

/*
 *  call-seq:
 *     obj.class_variable_defined?(symbol)    => true or false
 *
 *  Returns <code>true</code> if the given class variable is defined
 *  in <i>obj</i>.
 *
 *     class Fred
 *       @@foo = 99
 *     end
 *     Fred.class_variable_defined?(:@@foo)    #=> true
 *     Fred.class_variable_defined?(:@@bar)    #=> false
 */

static VALUE
rb_mod_cvar_defined(obj, iv)
    VALUE obj, iv;
{
    ID id = rb_to_id(iv);

    if (!rb_is_class_id(id)) {
	rb_name_error(id, "`%s' is not allowed as a class variable name", rb_id2name(id));
    }
    return rb_cvar_defined(obj, id);
}

static VALUE
convert_type(val, tname, method, raise)
    VALUE val;
    const char *tname, *method;
    int raise;
{
    ID m;

    m = rb_intern(method);
    if (!rb_respond_to(val, m)) {
	if (raise) {
	    rb_raise(rb_eTypeError, "can't convert %s into %s",
		     NIL_P(val) ? "nil" :
		     val == Qtrue ? "true" :
		     val == Qfalse ? "false" :
		     rb_obj_classname(val),
		     tname);
	}
	else {
	    return Qnil;
	}
    }
    return rb_funcall(val, m, 0);
}

VALUE
rb_convert_type(val, type, tname, method)
    VALUE val;
    int type;
    const char *tname, *method;
{
    VALUE v;

    if (TYPE(val) == type) return val;
    v = convert_type(val, tname, method, Qtrue);
    if (TYPE(v) != type) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to %s (%s#%s gives %s)",
		 cname, tname, cname, method, rb_obj_classname(v));
    }
    return v;
}

VALUE
rb_check_convert_type(val, type, tname, method)
    VALUE val;
    int type;
    const char *tname, *method;
{
    VALUE v;

    /* always convert T_DATA */
    if (TYPE(val) == type && type != T_DATA) return val;
    v = convert_type(val, tname, method, Qfalse);
    if (NIL_P(v)) return Qnil;
    if (TYPE(v) != type) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to %s (%s#%s gives %s)",
		 cname, tname, cname, method, rb_obj_classname(v));
    }
    return v;
}


static VALUE
rb_to_integer(val, method)
    VALUE val;
    const char *method;
{
    VALUE v = convert_type(val, "Integer", method, Qtrue);
    if (!rb_obj_is_kind_of(v, rb_cInteger)) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to Integer (%s#%s gives %s)",
		 cname, cname, method, rb_obj_classname(v));
    }
    return v;
}

VALUE
rb_check_to_integer(val, method)
    VALUE val;
    const char *method;
{
    VALUE v;

    if (FIXNUM_P(val)) return val;
    v = convert_type(val, "Integer", method, Qfalse);
    if (!rb_obj_is_kind_of(v, rb_cInteger)) {
	return Qnil;
    }
    return v;
}

VALUE
rb_to_int(val)
    VALUE val;
{
    return rb_to_integer(val, "to_int");
}

VALUE
rb_Integer(val)
    VALUE val;
{
    VALUE tmp;

    switch (TYPE(val)) {
      case T_FLOAT:
	if (RFLOAT(val)->value <= (double)FIXNUM_MAX
	    && RFLOAT(val)->value >= (double)FIXNUM_MIN) {
	    break;
	}
	return rb_dbl2big(RFLOAT(val)->value);

      case T_FIXNUM:
      case T_BIGNUM:
	return val;

      case T_STRING:
	return rb_str_to_inum(val, 0, Qtrue);

      default:
	break;
    }
    tmp = convert_type(val, "Integer", "to_int", Qfalse);
    if (NIL_P(tmp)) {
	return rb_to_integer(val, "to_i");
    }
    return tmp;
}

/*
 *  call-seq:
 *     Integer(arg)    => integer
 *
 *  Converts <i>arg</i> to a <code>Fixnum</code> or <code>Bignum</code>.
 *  Numeric types are converted directly (with floating point numbers
 *  being truncated). If <i>arg</i> is a <code>String</code>, leading
 *  radix indicators (<code>0</code>, <code>0b</code>, and
 *  <code>0x</code>) are honored. Others are converted using
 *  <code>to_int</code> and <code>to_i</code>. This behavior is
 *  different from that of <code>String#to_i</code>.
 *
 *     Integer(123.999)    #=> 123
 *     Integer("0x1a")     #=> 26
 *     Integer(Time.new)   #=> 1049896590
 */

static VALUE
rb_f_integer(obj, arg)
    VALUE obj, arg;
{
    return rb_Integer(arg);
}

double
rb_cstr_to_dbl(p, badcheck)
    const char *p;
    int badcheck;
{
    const char *q;
    char *end;
    double d;
    const char *ellipsis = "";
    int w;
#define OutOfRange() (((w = end - p) > 20) ? (w = 20, ellipsis = "...") : (ellipsis = ""))

    if (!p) return 0.0;
    q = p;
    if (badcheck) {
	while (ISSPACE(*p)) p++;
    }
    else {
	while (ISSPACE(*p) || *p == '_') p++;
    }
    errno = 0;
    d = strtod(p, &end);
    if (errno == ERANGE) {
	OutOfRange();
	rb_warn("Float %.*s%s out of range", w, p, ellipsis);
	errno = 0;
    }
    if (p == end) {
	if (badcheck) {
	  bad:
	    rb_invalid_str(q, "Float()");
	}
	return d;
    }
    if (*end) {
	char *buf = ALLOCA_N(char, strlen(p)+1);
	char *n = buf;

	while (p < end) *n++ = *p++;
	while (*p) {
	    if (*p == '_') {
		/* remove underscores between digits */
		if (badcheck) {
		    if (n == buf || !ISDIGIT(n[-1])) goto bad;
		    ++p;
		    if (!ISDIGIT(*p)) goto bad;
		}
		else {
		    while (*++p == '_');
		    continue;
		}
	    }
	    *n++ = *p++;
	}
	*n = '\0';
	p = buf;
	d = strtod(p, &end);
	if (errno == ERANGE) {
	    OutOfRange();
	    rb_warn("Float %.*s%s out of range", w, p, ellipsis);
	    errno = 0;
	}
	if (badcheck) {
	    if (!end || p == end) goto bad;
	    while (*end && ISSPACE(*end)) end++;
	    if (*end) goto bad;
	}
    }
    if (errno == ERANGE) {
	errno = 0;
	OutOfRange();
	rb_raise(rb_eArgError, "Float %.*s%s out of range", w, q, ellipsis);
    }
    return d;
}

double
rb_str_to_dbl(str, badcheck)
    VALUE str;
    int badcheck;
{
    char *s;
    long len;

    StringValue(str);
    s = RSTRING(str)->ptr;
    len = RSTRING(str)->len;
    if (s) {
	if (s[len]) {		/* no sentinel somehow */
	    char *p = ALLOCA_N(char, len+1);

	    MEMCPY(p, s, char, len);
	    p[len] = '\0';
	    s = p;
	}
	if (badcheck && len != strlen(s)) {
	    rb_raise(rb_eArgError, "string for Float contains null byte");
	}
    }
    return rb_cstr_to_dbl(s, badcheck);
}

VALUE
rb_Float(val)
    VALUE val;
{
    switch (TYPE(val)) {
      case T_FIXNUM:
	return rb_float_new((double)FIX2LONG(val));

      case T_FLOAT:
	return val;

      case T_BIGNUM:
	return rb_float_new(rb_big2dbl(val));

      case T_STRING:
	return rb_float_new(rb_str_to_dbl(val, Qtrue));

      case T_NIL:
	rb_raise(rb_eTypeError, "can't convert nil into Float");
	break;

      default:
	return rb_convert_type(val, T_FLOAT, "Float", "to_f");

    }
}

/*
 *  call-seq:
 *     Float(arg)    => float
 *
 *  Returns <i>arg</i> converted to a float. Numeric types are converted
 *  directly, the rest are converted using <i>arg</i>.to_f. As of Ruby
 *  1.8, converting <code>nil</code> generates a <code>TypeError</code>.
 *
 *     Float(1)           #=> 1.0
 *     Float("123.456")   #=> 123.456
 */

static VALUE
rb_f_float(obj, arg)
    VALUE obj, arg;
{
    return rb_Float(arg);
}

double
rb_num2dbl(val)
    VALUE val;
{
    switch (TYPE(val)) {
      case T_FLOAT:
	return RFLOAT(val)->value;

      case T_STRING:
	rb_raise(rb_eTypeError, "no implicit conversion to float from string");
	break;

      case T_NIL:
	rb_raise(rb_eTypeError, "no implicit conversion to float from nil");
	break;

      default:
	break;
    }

    return RFLOAT(rb_Float(val))->value;
}

char*
rb_str2cstr(str, len)
    VALUE str;
    long *len;
{
    StringValue(str);
    if (len) *len = RSTRING(str)->len;
    else if (RTEST(ruby_verbose) && RSTRING(str)->len != strlen(RSTRING(str)->ptr)) {
	rb_warn("string contains \\0 character");
    }
    return RSTRING(str)->ptr;
}

VALUE
rb_String(val)
    VALUE val;
{
    return rb_convert_type(val, T_STRING, "String", "to_s");
}


/*
 *  call-seq:
 *     String(arg)   => string
 *
 *  Converts <i>arg</i> to a <code>String</code> by calling its
 *  <code>to_s</code> method.
 *
 *     String(self)        #=> "main"
 *     String(self.class   #=> "Object"
 *     String(123456)      #=> "123456"
 */

static VALUE
rb_f_string(obj, arg)
    VALUE obj, arg;
{
    return rb_String(arg);
}

#if 0
VALUE
rb_Array(val)
    VALUE val;
{
    VALUE tmp = rb_check_array_type(val);

    if (NIL_P(tmp)) {
	tmp = rb_check_convert_type(val, T_ARRAY, "Array", "to_a");
	if (NIL_P(tmp)) {
	    return rb_ary_new3(1, val);
	}
    }
    return tmp;
}
#endif

/*
 *  call-seq:
 *     Array(arg)    => array
 *
 *  Returns <i>arg</i> as an <code>Array</code>. First tries to call
 *  <i>arg</i><code>.to_ary</code>, then <i>arg</i><code>.to_a</code>.
 *  If both fail, creates a single element array containing <i>arg</i>
 *  (unless <i>arg</i> is <code>nil</code>).
 *
 *     Array(1..5)   #=> [1, 2, 3, 4, 5]
 */

static VALUE
rb_f_array(obj, arg)
    VALUE obj, arg;
{
    return rb_Array(arg);
}

static VALUE boot_defclass _((const char *name, VALUE super));

static VALUE
boot_defclass(name, super)
    const char *name;
    VALUE super;
{
    extern st_table *rb_class_tbl;
    VALUE obj = rb_class_boot(super);
    ID id = rb_intern(name);

    rb_name_class(obj, id);
    st_add_direct(rb_class_tbl, id, obj);
    rb_const_set((rb_cObject ? rb_cObject : obj), id, obj);
    return obj;
}

VALUE ruby_top_self;

/*
 *  Document-class: Class
 *
 *  Classes in Ruby are first-class objects---each is an instance of
 *  class <code>Class</code>.
 *
 *  When a new class is created (typically using <code>class Name ...
 *  end</code>), an object of type <code>Class</code> is created and
 *  assigned to a global constant (<code>Name</code> in this case). When
 *  <code>Name.new</code> is called to create a new object, the
 *  <code>new</code> method in <code>Class</code> is run by default.
 *  This can be demonstrated by overriding <code>new</code> in
 *  <code>Class</code>:
 *
 *     class Class
 *        alias oldNew  new
 *        def new(*args)
 *          print "Creating a new ", self.name, "\n"
 *          oldNew(*args)
 *        end
 *      end
 *
 *
 *      class Name
 *      end
 *
 *
 *      n = Name.new
 *
 *  <em>produces:</em>
 *
 *     Creating a new Name
 *
 *  Classes, modules, and objects are interrelated. In the diagram
 *  that follows, the vertical arrows represent inheritance, and the
 *  parentheses meta-classes. All metaclasses are instances
 *  of the class `Class'.
 *
 *                            +------------------+
 *                            |                  |
 *              Object---->(Object)              |
 *               ^  ^        ^  ^                |
 *               |  |        |  |                |
 *               |  |  +-----+  +---------+      |
 *               |  |  |                  |      |
 *               |  +-----------+         |      |
 *               |     |        |         |      |
 *        +------+     |     Module--->(Module)  |
 *        |            |        ^         ^      |
 *   OtherClass-->(OtherClass)  |         |      |
 *                              |         |      |
 *                            Class---->(Class)  |
 *                              ^                |
 *                              |                |
 *                              +----------------+
 */


/*
 *  <code>Object</code> is the parent class of all classes in Ruby. Its
 *  methods are therefore available to all objects unless explicitly
 *  overridden.
 *
 *  <code>Object</code> mixes in the <code>Kernel</code> module, making
 *  the built-in kernel functions globally accessible. Although the
 *  instance methods of <code>Object</code> are defined by the
 *  <code>Kernel</code> module, we have chosen to document them here for
 *  clarity.
 *
 *  In the descriptions of Object's methods, the parameter <i>symbol</i> refers
 *  to a symbol, which is either a quoted string or a
 *  <code>Symbol</code> (such as <code>:name</code>).
 */

void
Init_Object()
{
    VALUE metaclass;

    rb_cObject = boot_defclass("Object", 0);
    rb_cModule = boot_defclass("Module", rb_cObject);
    rb_cClass =  boot_defclass("Class",  rb_cModule);

    metaclass = rb_make_metaclass(rb_cObject, rb_cClass);
    metaclass = rb_make_metaclass(rb_cModule, metaclass);
    metaclass = rb_make_metaclass(rb_cClass, metaclass);

    rb_mKernel = rb_define_module("Kernel");
    rb_include_module(rb_cObject, rb_mKernel);
    rb_define_alloc_func(rb_cObject, rb_class_allocate_instance);
    rb_define_private_method(rb_cObject, "initialize", rb_obj_dummy, 0);
    rb_define_private_method(rb_cClass, "inherited", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "included", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "extended", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_added", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_removed", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_undefined", rb_obj_dummy, 1);


    rb_define_method(rb_mKernel, "nil?", rb_false, 0);
    rb_define_method(rb_mKernel, "==", rb_obj_equal, 1);
    rb_define_method(rb_mKernel, "equal?", rb_obj_equal, 1);
    rb_define_method(rb_mKernel, "===", rb_equal, 1);
    rb_define_method(rb_mKernel, "=~", rb_obj_pattern_match, 1);

    rb_define_method(rb_mKernel, "eql?", rb_obj_equal, 1);

    rb_define_method(rb_mKernel, "id", rb_obj_id_obsolete, 0);
    rb_define_method(rb_mKernel, "type", rb_obj_type, 0);
    rb_define_method(rb_mKernel, "class", rb_obj_class, 0);
    rb_define_method(rb_mKernel, "singleton_class", rb_obj_singleton_class, 0);

    rb_define_method(rb_mKernel, "clone", rb_obj_clone, 0);
    rb_define_method(rb_mKernel, "dup", rb_obj_dup, 0);
    rb_define_method(rb_mKernel, "initialize_copy", rb_obj_init_copy, 1);

    rb_define_method(rb_mKernel, "taint", rb_obj_taint, 0);
    rb_define_method(rb_mKernel, "tainted?", rb_obj_tainted, 0);
    rb_define_method(rb_mKernel, "untaint", rb_obj_untaint, 0);
    rb_define_method(rb_mKernel, "freeze", rb_obj_freeze, 0);
    rb_define_method(rb_mKernel, "frozen?", rb_obj_frozen_p, 0);

    rb_define_method(rb_mKernel, "to_a", rb_any_to_a, 0); /* to be removed */
    rb_define_method(rb_mKernel, "to_s", rb_any_to_s, 0);
    rb_define_method(rb_mKernel, "inspect", rb_obj_inspect, 0);
    rb_define_method(rb_mKernel, "methods", rb_obj_methods, -1);
    rb_define_method(rb_mKernel, "singleton_methods",
		     rb_obj_singleton_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "protected_methods",
		     rb_obj_protected_methods, -1);
    rb_define_method(rb_mKernel, "private_methods", rb_obj_private_methods, -1);
    rb_define_method(rb_mKernel, "public_methods", rb_obj_public_methods, -1);
    rb_define_method(rb_mKernel, "instance_variables",
		     rb_obj_instance_variables, 0); /* in variable.c */
    rb_define_method(rb_mKernel, "instance_variable_get", rb_obj_ivar_get, 1);
    rb_define_method(rb_mKernel, "instance_variable_set", rb_obj_ivar_set, 2);
    rb_define_method(rb_mKernel, "instance_variable_defined?", rb_obj_ivar_defined, 1);
    rb_define_private_method(rb_mKernel, "remove_instance_variable",
			     rb_obj_remove_instance_variable, 1); /* in variable.c */

    rb_define_method(rb_mKernel, "instance_of?", rb_obj_is_instance_of, 1);
    rb_define_method(rb_mKernel, "kind_of?", rb_obj_is_kind_of, 1);
    rb_define_method(rb_mKernel, "is_a?", rb_obj_is_kind_of, 1);
    rb_define_method(rb_mKernel, "tap", rb_obj_tap, 0);

    rb_define_private_method(rb_mKernel, "singleton_method_added", rb_obj_dummy, 1);
    rb_define_private_method(rb_mKernel, "singleton_method_removed", rb_obj_dummy, 1);
    rb_define_private_method(rb_mKernel, "singleton_method_undefined", rb_obj_dummy, 1);

    rb_define_global_function("sprintf", rb_f_sprintf, -1); /* in sprintf.c */
    rb_define_global_function("format", rb_f_sprintf, -1);  /* in sprintf.c  */

    rb_define_global_function("Integer", rb_f_integer, 1);
    rb_define_global_function("Float", rb_f_float, 1);

    rb_define_global_function("String", rb_f_string, 1);
    rb_define_global_function("Array", rb_f_array, 1);

    rb_cNilClass = rb_define_class("NilClass", rb_cObject);
    rb_define_method(rb_cNilClass, "to_i", nil_to_i, 0);
    rb_define_method(rb_cNilClass, "to_f", nil_to_f, 0);
    rb_define_method(rb_cNilClass, "to_s", nil_to_s, 0);
    rb_define_method(rb_cNilClass, "to_a", nil_to_a, 0);
    rb_define_method(rb_cNilClass, "inspect", nil_inspect, 0);
    rb_define_method(rb_cNilClass, "&", false_and, 1);
    rb_define_method(rb_cNilClass, "|", false_or, 1);
    rb_define_method(rb_cNilClass, "^", false_xor, 1);

    rb_define_method(rb_cNilClass, "nil?", rb_true, 0);
    rb_undef_alloc_func(rb_cNilClass);
    rb_undef_method(CLASS_OF(rb_cNilClass), "new");
    rb_define_global_const("NIL", Qnil);

    rb_cSymbol = rb_define_class("Symbol", rb_cObject);
    rb_define_singleton_method(rb_cSymbol, "all_symbols",
			       rb_sym_all_symbols, 0); /* in parse.y */
    rb_undef_alloc_func(rb_cSymbol);
    rb_undef_method(CLASS_OF(rb_cSymbol), "new");

    rb_define_method(rb_cSymbol, "to_i", sym_to_i, 0);
    rb_define_method(rb_cSymbol, "to_int", sym_to_int, 0);
    rb_define_method(rb_cSymbol, "inspect", sym_inspect, 0);
    rb_define_method(rb_cSymbol, "to_s", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "id2name", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "to_sym", sym_to_sym, 0);
    rb_define_method(rb_cSymbol, "to_proc", sym_to_proc, 0);
    rb_define_method(rb_cSymbol, "===", rb_obj_equal, 1);

    rb_define_method(rb_cModule, "freeze", rb_mod_freeze, 0);
    rb_define_method(rb_cModule, "===", rb_mod_eqq, 1);
    rb_define_method(rb_cModule, "==", rb_obj_equal, 1);
    rb_define_method(rb_cModule, "<=>",  rb_mod_cmp, 1);
    rb_define_method(rb_cModule, "<",  rb_mod_lt, 1);
    rb_define_method(rb_cModule, "<=", rb_class_inherited_p, 1);
    rb_define_method(rb_cModule, ">",  rb_mod_gt, 1);
    rb_define_method(rb_cModule, ">=", rb_mod_ge, 1);
    rb_define_method(rb_cModule, "initialize_copy", rb_mod_init_copy, 1); /* in class.c */
    rb_define_method(rb_cModule, "to_s", rb_mod_to_s, 0);
    rb_define_method(rb_cModule, "included_modules",
		     rb_mod_included_modules, 0); /* in class.c */
    rb_define_method(rb_cModule, "include?", rb_mod_include_p, 1); /* in class.c */
    rb_define_method(rb_cModule, "name", rb_mod_name, 0);  /* in variable.c */
    rb_define_method(rb_cModule, "ancestors", rb_mod_ancestors, 0); /* in class.c */

    rb_define_private_method(rb_cModule, "attr", rb_mod_attr, -1);
    rb_define_private_method(rb_cModule, "attr_reader", rb_mod_attr_reader, -1);
    rb_define_private_method(rb_cModule, "attr_writer", rb_mod_attr_writer, -1);
    rb_define_private_method(rb_cModule, "attr_accessor", rb_mod_attr_accessor, -1);

    rb_define_alloc_func(rb_cModule, rb_module_s_alloc);
    rb_define_method(rb_cModule, "initialize", rb_mod_initialize, 0);
    rb_define_method(rb_cModule, "instance_methods",
		     rb_class_instance_methods, -1);           /* in class.c */
    rb_define_method(rb_cModule, "public_instance_methods",
		     rb_class_public_instance_methods, -1);    /* in class.c */
    rb_define_method(rb_cModule, "protected_instance_methods",
		     rb_class_protected_instance_methods, -1); /* in class.c */
    rb_define_method(rb_cModule, "private_instance_methods",
		     rb_class_private_instance_methods, -1);   /* in class.c */

    rb_define_method(rb_cModule, "class_variable_defined?", rb_mod_cvar_defined, 1);
    rb_define_method(rb_cModule, "constants", rb_mod_constants, 0); /* in variable.c */
    rb_define_method(rb_cModule, "const_get", rb_mod_const_get, 1);
    rb_define_method(rb_cModule, "const_set", rb_mod_const_set, 2);
    rb_define_method(rb_cModule, "const_defined?", rb_mod_const_defined, 1);
    rb_define_private_method(rb_cModule, "remove_const",
			     rb_mod_remove_const, 1); /* in variable.c */
    rb_define_method(rb_cModule, "const_missing",
		     rb_mod_const_missing, 1); /* in variable.c */
    rb_define_method(rb_cModule, "class_variables",
		     rb_mod_class_variables, 0); /* in variable.c */
    rb_define_private_method(rb_cModule, "remove_class_variable",
			     rb_mod_remove_cvar, 1); /* in variable.c */
    rb_define_private_method(rb_cModule, "class_variable_get", rb_mod_cvar_get, 1);
    rb_define_private_method(rb_cModule, "class_variable_set", rb_mod_cvar_set, 2);

    rb_define_method(rb_cClass, "allocate", rb_obj_alloc, 0);
    rb_define_method(rb_cClass, "new", rb_class_new_instance, -1);
    rb_define_method(rb_cClass, "initialize", rb_class_initialize, -1);
    rb_define_method(rb_cClass, "initialize_copy", rb_class_init_copy, 1); /* in class.c */
    rb_define_method(rb_cClass, "superclass", rb_class_superclass, 0);
    rb_define_alloc_func(rb_cClass, rb_class_s_alloc);
    rb_undef_method(rb_cClass, "extend_object");
    rb_undef_method(rb_cClass, "append_features");

    rb_cData = rb_define_class("Data", rb_cObject);
    rb_undef_alloc_func(rb_cData);

    rb_global_variable(&ruby_top_self);
    ruby_top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(ruby_top_self, "to_s", main_to_s, 0);

    rb_cTrueClass = rb_define_class("TrueClass", rb_cObject);
    rb_define_method(rb_cTrueClass, "to_s", true_to_s, 0);
    rb_define_method(rb_cTrueClass, "&", true_and, 1);
    rb_define_method(rb_cTrueClass, "|", true_or, 1);
    rb_define_method(rb_cTrueClass, "^", true_xor, 1);
    rb_undef_alloc_func(rb_cTrueClass);
    rb_undef_method(CLASS_OF(rb_cTrueClass), "new");
    rb_define_global_const("TRUE", Qtrue);

    rb_cFalseClass = rb_define_class("FalseClass", rb_cObject);
    rb_define_method(rb_cFalseClass, "to_s", false_to_s, 0);
    rb_define_method(rb_cFalseClass, "&", false_and, 1);
    rb_define_method(rb_cFalseClass, "|", false_or, 1);
    rb_define_method(rb_cFalseClass, "^", false_xor, 1);
    rb_undef_alloc_func(rb_cFalseClass);
    rb_undef_method(CLASS_OF(rb_cFalseClass), "new");
    rb_define_global_const("FALSE", Qfalse);

    id_eq = rb_intern("==");
    id_eql = rb_intern("eql?");
    id_inspect = rb_intern("inspect");
    id_init_copy = rb_intern("initialize_copy");
}
