/**********************************************************************

  object.c -

  $Author$
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby/encoding.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>
#include <float.h>
#include "constant.h"
#include "internal.h"
#include "id.h"
#include "probes.h"

VALUE rb_cBasicObject;
VALUE rb_mKernel;
VALUE rb_cObject;
VALUE rb_cModule;
VALUE rb_cClass;
VALUE rb_cData;

VALUE rb_cNilClass;
VALUE rb_cTrueClass;
VALUE rb_cFalseClass;

#define id_eq               idEq
#define id_eql              idEqlP
#define id_match            idEqTilde
#define id_inspect          idInspect
#define id_init_copy        idInitialize_copy
#define id_init_clone       idInitialize_clone
#define id_init_dup         idInitialize_dup
#define id_const_missing    idConst_missing

#define CLASS_OR_MODULE_P(obj) \
    (!SPECIAL_CONST_P(obj) && \
     (BUILTIN_TYPE(obj) == T_CLASS || BUILTIN_TYPE(obj) == T_MODULE))

VALUE
rb_obj_hide(VALUE obj)
{
    if (!SPECIAL_CONST_P(obj)) {
	RBASIC_CLEAR_CLASS(obj);
    }
    return obj;
}

VALUE
rb_obj_reveal(VALUE obj, VALUE klass)
{
    if (!SPECIAL_CONST_P(obj)) {
	RBASIC_SET_CLASS(obj, klass);
    }
    return obj;
}

VALUE
rb_obj_setup(VALUE obj, VALUE klass, VALUE type)
{
    RBASIC(obj)->flags = type;
    RBASIC_SET_CLASS(obj, klass);
    if (rb_safe_level() >= 3) FL_SET((obj), FL_TAINT);
    return obj;
}

/*
 *  call-seq:
 *     obj === other   -> true or false
 *
 *  Case Equality -- For class Object, effectively the same as calling
 *  <code>#==</code>, but typically overridden by descendants to provide
 *  meaningful semantics in +case+ statements.
 */

VALUE
rb_equal(VALUE obj1, VALUE obj2)
{
    VALUE result;

    if (obj1 == obj2) return Qtrue;
    result = rb_funcall(obj1, id_eq, 1, obj2);
    if (RTEST(result)) return Qtrue;
    return Qfalse;
}

int
rb_eql(VALUE obj1, VALUE obj2)
{
    return RTEST(rb_funcall(obj1, id_eql, 1, obj2));
}

/*
 *  call-seq:
 *     obj == other        -> true or false
 *     obj.equal?(other)   -> true or false
 *     obj.eql?(other)     -> true or false
 *
 *  Equality --- At the <code>Object</code> level, <code>==</code> returns
 *  <code>true</code> only if +obj+ and +other+ are the same object.
 *  Typically, this method is overridden in descendant classes to provide
 *  class-specific meaning.
 *
 *  Unlike <code>==</code>, the <code>equal?</code> method should never be
 *  overridden by subclasses as it is used to determine object identity
 *  (that is, <code>a.equal?(b)</code> if and only if <code>a</code> is the
 *  same object as <code>b</code>):
 *
 *    obj = "a"
 *    other = obj.dup
 *
 *    obj == other      #=> true
 *    obj.equal? other  #=> false
 *    obj.equal? obj    #=> true
 *
 *  The <code>eql?</code> method returns <code>true</code> if +obj+ and
 *  +other+ refer to the same hash key.  This is used by Hash to test members
 *  for equality.  For objects of class <code>Object</code>, <code>eql?</code>
 *  is synonymous with <code>==</code>.  Subclasses normally continue this
 *  tradition by aliasing <code>eql?</code> to their overridden <code>==</code>
 *  method, but there are exceptions.  <code>Numeric</code> types, for
 *  example, perform type conversion across <code>==</code>, but not across
 *  <code>eql?</code>, so:
 *
 *     1 == 1.0     #=> true
 *     1.eql? 1.0   #=> false
 */

VALUE
rb_obj_equal(VALUE obj1, VALUE obj2)
{
    if (obj1 == obj2) return Qtrue;
    return Qfalse;
}

/*
 * Generates a Fixnum hash value for this object.  This function must have the
 * property that <code>a.eql?(b)</code> implies <code>a.hash == b.hash</code>.
 *
 * The hash value is used along with #eql? by the Hash class to determine if
 * two objects reference the same hash key.  Any hash value that exceeds the
 * capacity of a Fixnum will be truncated before being used.
 *
 * The hash value for an object may not be identical across invocations or
 * implementations of ruby.  If you need a stable identifier across ruby
 * invocations and implementations you will need to generate one with a custom
 * method.
 */
VALUE
rb_obj_hash(VALUE obj)
{
    VALUE oid = rb_obj_id(obj);
#if SIZEOF_LONG == SIZEOF_VOIDP
    st_index_t index = NUM2LONG(oid);
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
    st_index_t index = NUM2LL(oid);
#else
# error not supported
#endif
    st_index_t h = rb_hash_end(rb_hash_start(index));
    return LONG2FIX(h);
}

/*
 *  call-seq:
 *     !obj    -> true or false
 *
 *  Boolean negate.
 */

VALUE
rb_obj_not(VALUE obj)
{
    return RTEST(obj) ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     obj != other        -> true or false
 *
 *  Returns true if two objects are not-equal, otherwise false.
 */

VALUE
rb_obj_not_equal(VALUE obj1, VALUE obj2)
{
    VALUE result = rb_funcall(obj1, id_eq, 1, obj2);
    return RTEST(result) ? Qfalse : Qtrue;
}

VALUE
rb_class_real(VALUE cl)
{
    if (cl == 0)
        return 0;
    while ((RBASIC(cl)->flags & FL_SINGLETON) || BUILTIN_TYPE(cl) == T_ICLASS) {
	cl = RCLASS_SUPER(cl);
    }
    return cl;
}

/*
 *  call-seq:
 *     obj.class    -> class
 *
 *  Returns the class of <i>obj</i>. This method must always be
 *  called with an explicit receiver, as <code>class</code> is also a
 *  reserved word in Ruby.
 *
 *     1.class      #=> Fixnum
 *     self.class   #=> Object
 */

VALUE
rb_obj_class(VALUE obj)
{
    return rb_class_real(CLASS_OF(obj));
}

/*
 *  call-seq:
 *     obj.singleton_class    -> class
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
rb_obj_singleton_class(VALUE obj)
{
    return rb_singleton_class(obj);
}

static void
init_copy(VALUE dest, VALUE obj)
{
    if (OBJ_FROZEN(dest)) {
        rb_raise(rb_eTypeError, "[bug] frozen object (%s) allocated", rb_obj_classname(dest));
    }
    RBASIC(dest)->flags &= ~(T_MASK|FL_EXIVAR);
    RBASIC(dest)->flags |= RBASIC(obj)->flags & (T_MASK|FL_EXIVAR|FL_TAINT);
    rb_copy_generic_ivar(dest, obj);
    rb_gc_copy_finalizer(dest, obj);
    switch (TYPE(obj)) {
      case T_OBJECT:
        if (!(RBASIC(dest)->flags & ROBJECT_EMBED) && ROBJECT_IVPTR(dest)) {
            xfree(ROBJECT_IVPTR(dest));
            ROBJECT(dest)->as.heap.ivptr = 0;
            ROBJECT(dest)->as.heap.numiv = 0;
            ROBJECT(dest)->as.heap.iv_index_tbl = 0;
        }
        if (RBASIC(obj)->flags & ROBJECT_EMBED) {
            MEMCPY(ROBJECT(dest)->as.ary, ROBJECT(obj)->as.ary, VALUE, ROBJECT_EMBED_LEN_MAX);
            RBASIC(dest)->flags |= ROBJECT_EMBED;
        }
        else {
            long len = ROBJECT(obj)->as.heap.numiv;
            VALUE *ptr = ALLOC_N(VALUE, len);
            MEMCPY(ptr, ROBJECT(obj)->as.heap.ivptr, VALUE, len);
            ROBJECT(dest)->as.heap.ivptr = ptr;
            ROBJECT(dest)->as.heap.numiv = len;
            ROBJECT(dest)->as.heap.iv_index_tbl = ROBJECT(obj)->as.heap.iv_index_tbl;
            RBASIC(dest)->flags &= ~ROBJECT_EMBED;
        }
        break;
      case T_CLASS:
      case T_MODULE:
	if (RCLASS_IV_TBL(dest)) {
	    st_free_table(RCLASS_IV_TBL(dest));
	    RCLASS_IV_TBL(dest) = 0;
	}
	if (RCLASS_CONST_TBL(dest)) {
	    rb_free_const_table(RCLASS_CONST_TBL(dest));
	    RCLASS_CONST_TBL(dest) = 0;
	}
	if (RCLASS_IV_TBL(obj)) {
	    RCLASS_IV_TBL(dest) = rb_st_copy(dest, RCLASS_IV_TBL(obj));
	}
        break;
    }
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
rb_obj_clone(VALUE obj)
{
    VALUE clone;
    VALUE singleton;

    if (rb_special_const_p(obj)) {
        rb_raise(rb_eTypeError, "can't clone %s", rb_obj_classname(obj));
    }
    clone = rb_obj_alloc(rb_obj_class(obj));
    RBASIC(clone)->flags &= FL_TAINT;
    RBASIC(clone)->flags |= RBASIC(obj)->flags & ~(FL_PROMOTED|FL_FREEZE|FL_FINALIZE);

    singleton = rb_singleton_class_clone_and_attach(obj, clone);
    RBASIC_SET_CLASS(clone, singleton);
    if (FL_TEST(singleton, FL_SINGLETON)) {
	rb_singleton_class_attached(singleton, clone);
    }

    init_copy(clone, obj);
    rb_funcall(clone, id_init_clone, 1, obj);
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
 *  in descendant classes. While <code>clone</code> is used to duplicate
 *  an object, including its internal state, <code>dup</code> typically
 *  uses the class of the descendant object to create the new instance.
 *
 *  This method may have class-specific behavior.  If so, that
 *  behavior will be documented under the #+initialize_copy+ method of
 *  the class.
 */

VALUE
rb_obj_dup(VALUE obj)
{
    VALUE dup;

    if (rb_special_const_p(obj)) {
        rb_raise(rb_eTypeError, "can't dup %s", rb_obj_classname(obj));
    }
    dup = rb_obj_alloc(rb_obj_class(obj));
    init_copy(dup, obj);
    rb_funcall(dup, id_init_dup, 1, obj);

    return dup;
}

/* :nodoc: */
VALUE
rb_obj_init_copy(VALUE obj, VALUE orig)
{
    if (obj == orig) return obj;
    rb_check_frozen(obj);
    rb_check_trusted(obj);
    if (TYPE(obj) != TYPE(orig) || rb_obj_class(obj) != rb_obj_class(orig)) {
	rb_raise(rb_eTypeError, "initialize_copy should take same class object");
    }
    return obj;
}

/* :nodoc: */
VALUE
rb_obj_init_dup_clone(VALUE obj, VALUE orig)
{
    rb_funcall(obj, id_init_copy, 1, orig);
    return obj;
}

/*
 *  call-seq:
 *     obj.to_s    -> string
 *
 *  Returns a string representing <i>obj</i>. The default
 *  <code>to_s</code> prints the object's class and an encoding of the
 *  object id. As a special case, the top-level object that is the
 *  initial execution context of Ruby programs returns ``main.''
 */

VALUE
rb_any_to_s(VALUE obj)
{
    VALUE str;
    VALUE cname = rb_class_name(CLASS_OF(obj));

    str = rb_sprintf("#<%"PRIsVALUE":%p>", cname, (void*)obj);
    OBJ_INFECT(str, obj);

    return str;
}

/*
 * If the default external encoding is ASCII compatible, the encoding of
 * inspected result must be compatible with it.
 * If the default external encoding is ASCII incompatible,
 * the result must be ASCII only.
 */
VALUE
rb_inspect(VALUE obj)
{
    VALUE str = rb_obj_as_string(rb_funcall(obj, id_inspect, 0, 0));
    rb_encoding *ext = rb_default_external_encoding();
    if (!rb_enc_asciicompat(ext)) {
	if (!rb_enc_str_asciionly_p(str))
	    rb_raise(rb_eEncCompatError, "inspected result must be ASCII only if default external encoding is ASCII incompatible");
	return str;
    }
    if (rb_enc_get(str) != ext && !rb_enc_str_asciionly_p(str))
	rb_raise(rb_eEncCompatError, "inspected result must be ASCII only or use the default external encoding");
    return str;
}

static int
inspect_i(st_data_t k, st_data_t v, st_data_t a)
{
    ID id = (ID)k;
    VALUE value = (VALUE)v;
    VALUE str = (VALUE)a;
    VALUE str2;
    const char *ivname;

    /* need not to show internal data */
    if (CLASS_OF(value) == 0) return ST_CONTINUE;
    if (!rb_is_instance_id(id)) return ST_CONTINUE;
    if (RSTRING_PTR(str)[0] == '-') { /* first element */
	RSTRING_PTR(str)[0] = '#';
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
inspect_obj(VALUE obj, VALUE str, int recur)
{
    if (recur) {
	rb_str_cat2(str, " ...");
    }
    else {
	rb_ivar_foreach(obj, inspect_i, str);
    }
    rb_str_cat2(str, ">");
    RSTRING_PTR(str)[0] = '#';
    OBJ_INFECT(str, obj);

    return str;
}

/*
 *  call-seq:
 *     obj.inspect   -> string
 *
 * Returns a string containing a human-readable representation of <i>obj</i>.
 * By default, show the class name and the list of the instance variables and
 * their values (by calling #inspect on each of them).
 * User defined classes should override this method to make better
 * representation of <i>obj</i>.  When overriding this method, it should
 * return a string whose encoding is compatible with the default external
 * encoding.
 *
 *     [ 1, 2, 3..4, 'five' ].inspect   #=> "[1, 2, 3..4, \"five\"]"
 *     Time.new.inspect                 #=> "2008-03-08 19:43:39 +0900"
 *
 *     class Foo
 *     end
 *     Foo.new.inspect                  #=> "#<Foo:0x0300c868>"
 *
 *     class Bar
 *       def initialize
 *         @bar = 1
 *       end
 *     end
 *     Bar.new.inspect                  #=> "#<Bar:0x0300c868 @bar=1>"
 *
 *     class Baz
 *       def to_s
 *         "baz"
 *       end
 *     end
 *     Baz.new.inspect                  #=> "#<Baz:0x0300c868>"
 */

static VALUE
rb_obj_inspect(VALUE obj)
{
    if (rb_ivar_count(obj) > 0) {
	VALUE str;
	VALUE c = rb_class_name(CLASS_OF(obj));

	str = rb_sprintf("-<%"PRIsVALUE":%p", c, (void*)obj);
	return rb_exec_recursive(inspect_obj, obj, str);
    }
    else {
	return rb_any_to_s(obj);
    }
}

static VALUE
class_or_module_required(VALUE c)
{
    if (SPECIAL_CONST_P(c)) goto not_class;
    switch (BUILTIN_TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
      case T_ICLASS:
	break;

      default:
      not_class:
	rb_raise(rb_eTypeError, "class or module required");
    }
    return c;
}

/*
 *  call-seq:
 *     obj.instance_of?(class)    -> true or false
 *
 *  Returns <code>true</code> if <i>obj</i> is an instance of the given
 *  class. See also <code>Object#kind_of?</code>.
 *
 *     class A;     end
 *     class B < A; end
 *     class C < B; end
 *
 *     b = B.new
 *     b.instance_of? A   #=> false
 *     b.instance_of? B   #=> true
 *     b.instance_of? C   #=> false
 */

VALUE
rb_obj_is_instance_of(VALUE obj, VALUE c)
{
    c = class_or_module_required(c);
    if (rb_obj_class(obj) == c) return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     obj.is_a?(class)       -> true or false
 *     obj.kind_of?(class)    -> true or false
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
 *
 *     b = B.new
 *     b.is_a? A          #=> true
 *     b.is_a? B          #=> true
 *     b.is_a? C          #=> false
 *     b.is_a? M          #=> true
 *
 *     b.kind_of? A       #=> true
 *     b.kind_of? B       #=> true
 *     b.kind_of? C       #=> false
 *     b.kind_of? M       #=> true
 */

VALUE
rb_obj_is_kind_of(VALUE obj, VALUE c)
{
    VALUE cl = CLASS_OF(obj);

    c = class_or_module_required(c);
    c = RCLASS_ORIGIN(c);
    while (cl) {
	if (cl == c || RCLASS_M_TBL(cl) == RCLASS_M_TBL(c))
	    return Qtrue;
	cl = RCLASS_SUPER(cl);
    }
    return Qfalse;
}


/*
 *  call-seq:
 *     obj.tap{|x|...}    -> obj
 *
 *  Yields <code>x</code> to the block, and then returns <code>x</code>.
 *  The primary purpose of this method is to "tap into" a method chain,
 *  in order to perform operations on intermediate results within the chain.
 *
 *	(1..10)                .tap {|x| puts "original: #{x.inspect}"}
 *	  .to_a                .tap {|x| puts "array: #{x.inspect}"}
 *	  .select {|x| x%2==0} .tap {|x| puts "evens: #{x.inspect}"}
 *	  .map { |x| x*x }     .tap {|x| puts "squares: #{x.inspect}"}
 *
 */

VALUE
rb_obj_tap(VALUE obj)
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
 *      def self.inherited(subclass)
 *        puts "New subclass: #{subclass}"
 *      end
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

/* Document-method: method_added
 *
 * call-seq:
 *   method_added(method_name)
 *
 * Invoked as a callback whenever an instance method is added to the
 * receiver.
 *
 *   module Chatty
 *     def self.method_added(method_name)
 *       puts "Adding #{method_name.inspect}"
 *     end
 *     def self.some_class_method() end
 *     def some_instance_method() end
 *   end
 *
 * produces:
 *
 *   Adding :some_instance_method
 *
 */

/* Document-method: method_removed
 *
 * call-seq:
 *   method_removed(method_name)
 *
 * Invoked as a callback whenever an instance method is removed from the
 * receiver.
 *
 *   module Chatty
 *     def self.method_removed(method_name)
 *       puts "Removing #{method_name.inspect}"
 *     end
 *     def self.some_class_method() end
 *     def some_instance_method() end
 *     class << self
 *       remove_method :some_class_method
 *     end
 *     remove_method :some_instance_method
 *   end
 *
 * produces:
 *
 *   Removing :some_instance_method
 *
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
 *       class << self
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
 * Document-method: extended
 *
 * call-seq:
 *    extended(othermod)
 *
 * The equivalent of <tt>included</tt>, but for extended modules.
 *
 *        module A
 *          def self.extended(mod)
 *            puts "#{self} extended in #{mod}"
 *          end
 *        end
 *        module Enumerable
 *          extend A
 *        end
 *         # => prints "A extended in Enumerable"
 */

/*
 * Document-method: included
 *
 * call-seq:
 *    included(othermod)
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
 *         # => prints "A included in Enumerable"
 */

/*
 * Document-method: prepended
 *
 * call-seq:
 *    prepended(othermod)
 *
 * The equivalent of <tt>included</tt>, but for prepended modules.
 *
 *        module A
 *          def self.prepended(mod)
 *            puts "#{self} prepended to #{mod}"
 *          end
 *        end
 *        module Enumerable
 *          prepend A
 *        end
 *         # => prints "A prepended to Enumerable"
 */

/*
 * Document-method: initialize
 *
 * call-seq:
 *    BasicObject.new
 *
 * Returns a new BasicObject.
 */

/*
 * Not documented
 */

static VALUE
rb_obj_dummy(void)
{
    return Qnil;
}

/*
 *  call-seq:
 *     obj.tainted?    -> true or false
 *
 *  Returns true if the object is tainted.
 *
 *  See #taint for more information.
 */

VALUE
rb_obj_tainted(VALUE obj)
{
    if (OBJ_TAINTED(obj))
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj.taint -> obj
 *
 *  Mark the object as tainted.
 *
 *  Objects that are marked as tainted will be restricted from various built-in
 *  methods. This is to prevent insecure data, such as command-line arguments
 *  or strings read from Kernel#gets, from inadvertently compromising the users
 *  system.
 *
 *  To check whether an object is tainted, use #tainted?
 *
 *  You should only untaint a tainted object if your code has inspected it and
 *  determined that it is safe. To do so use #untaint
 *
 *  In $SAFE level 3, all newly created objects are tainted and you can't untaint
 *  objects.
 */

VALUE
rb_obj_taint(VALUE obj)
{
    if (!OBJ_TAINTED(obj)) {
	rb_check_frozen(obj);
	OBJ_TAINT(obj);
    }
    return obj;
}


/*
 *  call-seq:
 *     obj.untaint    -> obj
 *
 *  Removes the tainted mark from the object.
 *
 *  See #taint for more information.
 */

VALUE
rb_obj_untaint(VALUE obj)
{
    rb_secure(3);
    if (OBJ_TAINTED(obj)) {
	rb_check_frozen(obj);
	FL_UNSET(obj, FL_TAINT);
    }
    return obj;
}

/*
 *  call-seq:
 *     obj.untrusted?    -> true or false
 *
 *  Deprecated method that is equivalent to #tainted?.
 */

VALUE
rb_obj_untrusted(VALUE obj)
{
    rb_warning("untrusted? is deprecated and its behavior is same as tainted?");
    return rb_obj_tainted(obj);
}

/*
 *  call-seq:
 *     obj.untrust -> obj
 *
 *  Deprecated method that is equivalent to #taint.
 */

VALUE
rb_obj_untrust(VALUE obj)
{
    rb_warning("untrust is deprecated and its behavior is same as taint");
    return rb_obj_taint(obj);
}


/*
 *  call-seq:
 *     obj.trust    -> obj
 *
 *  Deprecated method that is equivalent to #untaint.
 */

VALUE
rb_obj_trust(VALUE obj)
{
    rb_warning("trust is deprecated and its behavior is same as untaint");
    return rb_obj_untaint(obj);
}

void
rb_obj_infect(VALUE obj1, VALUE obj2)
{
    OBJ_INFECT(obj1, obj2);
}

static st_table *immediate_frozen_tbl = 0;

/*
 *  call-seq:
 *     obj.freeze    -> obj
 *
 *  Prevents further modifications to <i>obj</i>. A
 *  <code>RuntimeError</code> will be raised if modification is attempted.
 *  There is no way to unfreeze a frozen object. See also
 *  <code>Object#frozen?</code>.
 *
 *  This method returns self.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze
 *     a << "z"
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3:in `<<': can't modify frozen array (RuntimeError)
 *     	from prog.rb:3
 */

VALUE
rb_obj_freeze(VALUE obj)
{
    if (!OBJ_FROZEN(obj)) {
	OBJ_FREEZE(obj);
	if (SPECIAL_CONST_P(obj)) {
	    if (!immediate_frozen_tbl) {
		immediate_frozen_tbl = st_init_numtable();
	    }
	    st_insert(immediate_frozen_tbl, obj, (st_data_t)Qtrue);
	}
    }
    return obj;
}

/*
 *  call-seq:
 *     obj.frozen?    -> true or false
 *
 *  Returns the freeze status of <i>obj</i>.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze    #=> ["a", "b", "c"]
 *     a.frozen?   #=> true
 */

VALUE
rb_obj_frozen_p(VALUE obj)
{
    if (OBJ_FROZEN(obj)) return Qtrue;
    if (SPECIAL_CONST_P(obj)) {
	if (!immediate_frozen_tbl) return Qfalse;
	if (st_lookup(immediate_frozen_tbl, obj, 0)) return Qtrue;
    }
    return Qfalse;
}


/*
 * Document-class: NilClass
 *
 *  The class of the singleton object <code>nil</code>.
 */

/*
 *  call-seq:
 *     nil.to_i -> 0
 *
 *  Always returns zero.
 *
 *     nil.to_i   #=> 0
 */


static VALUE
nil_to_i(VALUE obj)
{
    return INT2FIX(0);
}

/*
 *  call-seq:
 *     nil.to_f    -> 0.0
 *
 *  Always returns zero.
 *
 *     nil.to_f   #=> 0.0
 */

static VALUE
nil_to_f(VALUE obj)
{
    return DBL2NUM(0.0);
}

/*
 *  call-seq:
 *     nil.to_s    -> ""
 *
 *  Always returns the empty string.
 */

static VALUE
nil_to_s(VALUE obj)
{
    return rb_usascii_str_new(0, 0);
}

/*
 * Document-method: to_a
 *
 *  call-seq:
 *     nil.to_a    -> []
 *
 *  Always returns an empty array.
 *
 *     nil.to_a   #=> []
 */

static VALUE
nil_to_a(VALUE obj)
{
    return rb_ary_new2(0);
}

/*
 * Document-method: to_h
 *
 *  call-seq:
 *     nil.to_h    -> {}
 *
 *  Always returns an empty hash.
 *
 *     nil.to_h   #=> {}
 */

static VALUE
nil_to_h(VALUE obj)
{
    return rb_hash_new();
}

/*
 *  call-seq:
 *    nil.inspect  -> "nil"
 *
 *  Always returns the string "nil".
 */

static VALUE
nil_inspect(VALUE obj)
{
    return rb_usascii_str_new2("nil");
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
 *   true.to_s   ->  "true"
 *
 * The string representation of <code>true</code> is "true".
 */

static VALUE
true_to_s(VALUE obj)
{
    return rb_usascii_str_new2("true");
}


/*
 *  call-seq:
 *     true & obj    -> true or false
 *
 *  And---Returns <code>false</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>, <code>true</code> otherwise.
 */

static VALUE
true_and(VALUE obj, VALUE obj2)
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

/*
 *  call-seq:
 *     true | obj   -> true
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
true_or(VALUE obj, VALUE obj2)
{
    return Qtrue;
}


/*
 *  call-seq:
 *     true ^ obj   -> !obj
 *
 *  Exclusive Or---Returns <code>true</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>, <code>false</code>
 *  otherwise.
 */

static VALUE
true_xor(VALUE obj, VALUE obj2)
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
 *   false.to_s   ->  "false"
 *
 * 'nuf said...
 */

static VALUE
false_to_s(VALUE obj)
{
    return rb_usascii_str_new2("false");
}

/*
 *  call-seq:
 *     false & obj   -> false
 *     nil & obj     -> false
 *
 *  And---Returns <code>false</code>. <i>obj</i> is always
 *  evaluated as it is the argument to a method call---there is no
 *  short-circuit evaluation in this case.
 */

static VALUE
false_and(VALUE obj, VALUE obj2)
{
    return Qfalse;
}


/*
 *  call-seq:
 *     false | obj   ->   true or false
 *     nil   | obj   ->   true or false
 *
 *  Or---Returns <code>false</code> if <i>obj</i> is
 *  <code>nil</code> or <code>false</code>; <code>true</code> otherwise.
 */

static VALUE
false_or(VALUE obj, VALUE obj2)
{
    return RTEST(obj2)?Qtrue:Qfalse;
}



/*
 *  call-seq:
 *     false ^ obj    -> true or false
 *     nil   ^ obj    -> true or false
 *
 *  Exclusive Or---If <i>obj</i> is <code>nil</code> or
 *  <code>false</code>, returns <code>false</code>; otherwise, returns
 *  <code>true</code>.
 *
 */

static VALUE
false_xor(VALUE obj, VALUE obj2)
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

/*
 * call-seq:
 *   nil.nil?               -> true
 *
 * Only the object <i>nil</i> responds <code>true</code> to <code>nil?</code>.
 */

static VALUE
rb_true(VALUE obj)
{
    return Qtrue;
}

/*
 * call-seq:
 *   nil.nil?               -> true
 *   <anything_else>.nil?   -> false
 *
 * Only the object <i>nil</i> responds <code>true</code> to <code>nil?</code>.
 */


static VALUE
rb_false(VALUE obj)
{
    return Qfalse;
}


/*
 *  call-seq:
 *     obj =~ other  -> nil
 *
 *  Pattern Match---Overridden by descendants (notably
 *  <code>Regexp</code> and <code>String</code>) to provide meaningful
 *  pattern-match semantics.
 */

static VALUE
rb_obj_match(VALUE obj1, VALUE obj2)
{
    return Qnil;
}

/*
 *  call-seq:
 *     obj !~ other  -> true or false
 *
 *  Returns true if two objects do not match (using the <i>=~</i>
 *  method), otherwise false.
 */

static VALUE
rb_obj_not_match(VALUE obj1, VALUE obj2)
{
    VALUE result = rb_funcall(obj1, id_match, 1, obj2);
    return RTEST(result) ? Qfalse : Qtrue;
}


/*
 *  call-seq:
 *     obj <=> other -> 0 or nil
 *
 *  Returns 0 if +obj+ and +other+ are the same object
 *  or <code>obj == other</code>, otherwise nil.
 *
 *  The <=> is used by various methods to compare objects, for example
 *  Enumerable#sort, Enumerable#max etc.
 *
 *  Your implementation of <=> should return one of the following values: -1, 0,
 *  1 or nil. -1 means self is smaller than other. 0 means self is equal to other.
 *  1 means self is bigger than other. Nil means the two values could not be
 *  compared.
 *
 *  When you define <=>, you can include Comparable to gain the methods <=, <,
 *  ==, >=, > and between?.
 */
static VALUE
rb_obj_cmp(VALUE obj1, VALUE obj2)
{
    if (obj1 == obj2 || rb_equal(obj1, obj2))
	return INT2FIX(0);
    return Qnil;
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
 *  In the descriptions that follow, the parameter <i>sym</i> refers
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
 *     Mod.constants          #=> [:CONST, :PI, :E]
 *     Mod.instance_methods   #=> [:meth]
 *
 */

/*
 * call-seq:
 *   mod.to_s   -> string
 *
 * Return a string representing this module or class. For basic
 * classes and modules, this is the name. For singletons, we
 * show information on the thing we're attached to as well.
 */

static VALUE
rb_mod_to_s(VALUE klass)
{
    ID id_defined_at;
    VALUE refined_class, defined_at;

    if (FL_TEST(klass, FL_SINGLETON)) {
	VALUE s = rb_usascii_str_new2("#<Class:");
	VALUE v = rb_ivar_get(klass, id__attached__);

	if (CLASS_OR_MODULE_P(v)) {
	    rb_str_append(s, rb_inspect(v));
	}
	else {
	    rb_str_append(s, rb_any_to_s(v));
	}
	rb_str_cat2(s, ">");

	return s;
    }
    refined_class = rb_refinement_module_get_refined_class(klass);
    if (!NIL_P(refined_class)) {
	VALUE s = rb_usascii_str_new2("#<refinement:");

	rb_str_concat(s, rb_inspect(refined_class));
	rb_str_cat2(s, "@");
	CONST_ID(id_defined_at, "__defined_at__");
	defined_at = rb_attr_get(klass, id_defined_at);
	rb_str_concat(s, rb_inspect(defined_at));
	rb_str_cat2(s, ">");
	return s;
    }
    return rb_str_dup(rb_class_name(klass));
}

/*
 *  call-seq:
 *     mod.freeze       -> mod
 *
 *  Prevents further modifications to <i>mod</i>.
 *
 *  This method returns self.
 */

static VALUE
rb_mod_freeze(VALUE mod)
{
    rb_class_name(mod);
    return rb_obj_freeze(mod);
}

/*
 *  call-seq:
 *     mod === obj    -> true or false
 *
 *  Case Equality---Returns <code>true</code> if <i>anObject</i> is an
 *  instance of <i>mod</i> or one of <i>mod</i>'s descendants. Of
 *  limited use for modules, but can be used in <code>case</code>
 *  statements to classify objects by class.
 */

static VALUE
rb_mod_eqq(VALUE mod, VALUE arg)
{
    return rb_obj_is_kind_of(arg, mod);
}

/*
 * call-seq:
 *   mod <= other   ->  true, false, or nil
 *
 * Returns true if <i>mod</i> is a subclass of <i>other</i> or
 * is the same as <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "A<B").
 *
 */

VALUE
rb_class_inherited_p(VALUE mod, VALUE arg)
{
    VALUE start = mod;

    if (mod == arg) return Qtrue;
    if (!CLASS_OR_MODULE_P(arg) && !RB_TYPE_P(arg, T_ICLASS)) {
	rb_raise(rb_eTypeError, "compared with non class/module");
    }
    arg = RCLASS_ORIGIN(arg);
    while (mod) {
	if (RCLASS_M_TBL(mod) == RCLASS_M_TBL(arg))
	    return Qtrue;
	mod = RCLASS_SUPER(mod);
    }
    /* not mod < arg; check if mod > arg */
    while (arg) {
	if (RCLASS_M_TBL(arg) == RCLASS_M_TBL(start))
	    return Qfalse;
	arg = RCLASS_SUPER(arg);
    }
    return Qnil;
}

/*
 * call-seq:
 *   mod < other   ->  true, false, or nil
 *
 * Returns true if <i>mod</i> is a subclass of <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "A<B").
 *
 */

static VALUE
rb_mod_lt(VALUE mod, VALUE arg)
{
    if (mod == arg) return Qfalse;
    return rb_class_inherited_p(mod, arg);
}


/*
 * call-seq:
 *   mod >= other   ->  true, false, or nil
 *
 * Returns true if <i>mod</i> is an ancestor of <i>other</i>, or the
 * two modules are the same. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "B>A").
 *
 */

static VALUE
rb_mod_ge(VALUE mod, VALUE arg)
{
    if (!CLASS_OR_MODULE_P(arg)) {
	rb_raise(rb_eTypeError, "compared with non class/module");
    }

    return rb_class_inherited_p(arg, mod);
}

/*
 * call-seq:
 *   mod > other   ->  true, false, or nil
 *
 * Returns true if <i>mod</i> is an ancestor of <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A<B" implies "B>A").
 *
 */

static VALUE
rb_mod_gt(VALUE mod, VALUE arg)
{
    if (mod == arg) return Qfalse;
    return rb_mod_ge(mod, arg);
}

/*
 *  call-seq:
 *     module <=> other_module   -> -1, 0, +1, or nil
 *
 *  Comparison---Returns -1, 0, +1 or nil depending on whether +module+
 *  includes +other_module+, they are the same, or if +module+ is included by
 *  +other_module+. This is the basis for the tests in Comparable.
 *
 *  Returns +nil+ if +module+ has no relationship with +other_module+, if
 *  +other_module+ is not a module, or if the two values are incomparable.
 */

static VALUE
rb_mod_cmp(VALUE mod, VALUE arg)
{
    VALUE cmp;

    if (mod == arg) return INT2FIX(0);
    if (!CLASS_OR_MODULE_P(arg)) {
	return Qnil;
    }

    cmp = rb_class_inherited_p(mod, arg);
    if (NIL_P(cmp)) return Qnil;
    if (cmp) {
	return INT2FIX(-1);
    }
    return INT2FIX(1);
}

static VALUE
rb_module_s_alloc(VALUE klass)
{
    VALUE mod = rb_module_new();

    RBASIC_SET_CLASS(mod, klass);
    return mod;
}

static VALUE
rb_class_s_alloc(VALUE klass)
{
    return rb_class_boot(0);
}

/*
 *  call-seq:
 *    Module.new                  -> mod
 *    Module.new {|mod| block }   -> mod
 *
 *  Creates a new anonymous module. If a block is given, it is passed
 *  the module object, and the block is evaluated in the context of this
 *  module using <code>module_eval</code>.
 *
 *     fred = Module.new do
 *       def meth1
 *         "hello"
 *       end
 *       def meth2
 *         "bye"
 *       end
 *     end
 *     a = "my string"
 *     a.extend(fred)   #=> "my string"
 *     a.meth1          #=> "hello"
 *     a.meth2          #=> "bye"
 *
 *  Assign the module to a constant (name starting uppercase) if you
 *  want to treat it like a regular module.
 */

static VALUE
rb_mod_initialize(VALUE module)
{
    if (rb_block_given_p()) {
	rb_mod_module_exec(1, &module, module);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     Class.new(super_class=Object)               -> a_class
 *     Class.new(super_class=Object) { |mod| ... } -> a_class
 *
 *  Creates a new anonymous (unnamed) class with the given superclass
 *  (or <code>Object</code> if no parameter is given). You can give a
 *  class a name by assigning the class object to a constant.
 *
 *  If a block is given, it is passed the class object, and the block
 *  is evaluated in the context of this class using
 *  <code>class_eval</code>.
 *
 *     fred = Class.new do
 *       def meth1
 *         "hello"
 *       end
 *       def meth2
 *         "bye"
 *       end
 *     end
 *
 *     a = fred.new     #=> #<#<Class:0x100381890>:0x100376b98>
 *     a.meth1          #=> "hello"
 *     a.meth2          #=> "bye"
 *
 *  Assign the class to a constant (name starting uppercase) if you
 *  want to treat it like a regular class.
 */

static VALUE
rb_class_initialize(int argc, VALUE *argv, VALUE klass)
{
    VALUE super;

    if (RCLASS_SUPER(klass) != 0 || klass == rb_cBasicObject) {
	rb_raise(rb_eTypeError, "already initialized class");
    }
    if (argc == 0) {
	super = rb_cObject;
    }
    else {
	rb_scan_args(argc, argv, "01", &super);
	rb_check_inheritable(super);
	if (super != rb_cBasicObject && !RCLASS_SUPER(super)) {
	    rb_raise(rb_eTypeError, "can't inherit uninitialized class");
	}
    }
    RCLASS_SET_SUPER(klass, super);
    rb_make_metaclass(klass, RBASIC(super)->klass);
    rb_class_inherited(super, klass);
    rb_mod_initialize(klass);

    return klass;
}

/*
 *  call-seq:
 *     class.allocate()   ->   obj
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
rb_obj_alloc(VALUE klass)
{
    VALUE obj;
    rb_alloc_func_t allocator;

    if (RCLASS_SUPER(klass) == 0 && klass != rb_cBasicObject) {
	rb_raise(rb_eTypeError, "can't instantiate uninitialized class");
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't create instance of singleton class");
    }
    allocator = rb_get_alloc_func(klass);
    if (!allocator) {
	rb_raise(rb_eTypeError, "allocator undefined for %"PRIsVALUE,
		 klass);
    }

#if !defined(DTRACE_PROBES_DISABLED) || !DTRACE_PROBES_DISABLED
    if (RUBY_DTRACE_OBJECT_CREATE_ENABLED()) {
        const char * file = rb_sourcefile();
        RUBY_DTRACE_OBJECT_CREATE(rb_class2name(klass),
				  file ? file : "",
				  rb_sourceline());
    }
#endif

    obj = (*allocator)(klass);

    if (rb_obj_class(obj) != rb_class_real(klass)) {
	rb_raise(rb_eTypeError, "wrong instance allocation");
    }
    return obj;
}

static VALUE
rb_class_allocate_instance(VALUE klass)
{
    NEWOBJ_OF(obj, struct RObject, klass, T_OBJECT | (RGENGC_WB_PROTECTED_OBJECT ? FL_WB_PROTECTED : 0));
    return (VALUE)obj;
}

/*
 *  call-seq:
 *     class.new(args, ...)    ->  obj
 *
 *  Calls <code>allocate</code> to create a new object of
 *  <i>class</i>'s class, then invokes that object's
 *  <code>initialize</code> method, passing it <i>args</i>.
 *  This is the method that ends up getting called whenever
 *  an object is constructed using .new.
 *
 */

VALUE
rb_class_new_instance(int argc, VALUE *argv, VALUE klass)
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
 *     File.superclass          #=> IO
 *     IO.superclass            #=> Object
 *     Object.superclass        #=> BasicObject
 *     class Foo; end
 *     class Bar < Foo; end
 *     Bar.superclass           #=> Foo
 *
 *  returns nil when the given class hasn't a parent class:
 *
 *     BasicObject.superclass   #=> nil
 *
 */

VALUE
rb_class_superclass(VALUE klass)
{
    VALUE super = RCLASS_SUPER(klass);

    if (!super) {
	if (klass == rb_cBasicObject) return Qnil;
	rb_raise(rb_eTypeError, "uninitialized class");
    }
    while (RB_TYPE_P(super, T_ICLASS)) {
	super = RCLASS_SUPER(super);
    }
    if (!super) {
	return Qnil;
    }
    return super;
}

VALUE
rb_class_get_superclass(VALUE klass)
{
    return RCLASS_EXT(klass)->super;
}

#define id_for_setter(name, type, message) \
    check_setter_id(name, rb_is_##type##_id, rb_is_##type##_name, message)
static ID
check_setter_id(VALUE name, int (*valid_id_p)(ID), int (*valid_name_p)(VALUE),
		const char *message)
{
    ID id;
    if (SYMBOL_P(name)) {
	id = SYM2ID(name);
	if (!valid_id_p(id)) {
	    rb_name_error(id, message, QUOTE_ID(id));
	}
    }
    else {
	VALUE str = rb_check_string_type(name);
	if (NIL_P(str)) {
	    rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a symbol or string",
		     str);
	}
	if (!valid_name_p(str)) {
	    rb_name_error_str(str, message, QUOTE(str));
	}
	id = rb_to_id(str);
    }
    return id;
}

static int
rb_is_attr_id(ID id)
{
    return rb_is_local_id(id) || rb_is_const_id(id);
}

static int
rb_is_attr_name(VALUE name)
{
    return rb_is_local_name(name) || rb_is_const_name(name);
}

static const char invalid_attribute_name[] = "invalid attribute name `%"PRIsVALUE"'";

static ID
id_for_attr(VALUE name)
{
    return id_for_setter(name, attr, invalid_attribute_name);
}

ID
rb_check_attr_id(ID id)
{
    if (!rb_is_attr_id(id)) {
	rb_name_error_str(id, invalid_attribute_name, QUOTE_ID(id));
    }
    return id;
}

/*
 *  call-seq:
 *     attr_reader(symbol, ...)  -> nil
 *     attr(symbol, ...)         -> nil
 *     attr_reader(string, ...)  -> nil
 *     attr(string, ...)         -> nil
 *
 *  Creates instance variables and corresponding methods that return the
 *  value of each instance variable. Equivalent to calling
 *  ``<code>attr</code><i>:name</i>'' on each name in turn.
 *  String arguments are converted to symbols.
 */

static VALUE
rb_mod_attr_reader(int argc, VALUE *argv, VALUE klass)
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, id_for_attr(argv[i]), TRUE, FALSE, TRUE);
    }
    return Qnil;
}

VALUE
rb_mod_attr(int argc, VALUE *argv, VALUE klass)
{
    if (argc == 2 && (argv[1] == Qtrue || argv[1] == Qfalse)) {
	rb_warning("optional boolean argument is obsoleted");
	rb_attr(klass, id_for_attr(argv[0]), 1, RTEST(argv[1]), TRUE);
	return Qnil;
    }
    return rb_mod_attr_reader(argc, argv, klass);
}

/*
 *  call-seq:
 *      attr_writer(symbol, ...)    -> nil
 *      attr_writer(string, ...)    -> nil
 *
 *  Creates an accessor method to allow assignment to the attribute
 *  <i>symbol</i><code>.id2name</code>.
 *  String arguments are converted to symbols.
 */

static VALUE
rb_mod_attr_writer(int argc, VALUE *argv, VALUE klass)
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, id_for_attr(argv[i]), FALSE, TRUE, TRUE);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     attr_accessor(symbol, ...)    -> nil
 *     attr_accessor(string, ...)    -> nil
 *
 *  Defines a named attribute for this module, where the name is
 *  <i>symbol.</i><code>id2name</code>, creating an instance variable
 *  (<code>@name</code>) and a corresponding access method to read it.
 *  Also creates a method called <code>name=</code> to set the attribute.
 *  String arguments are converted to symbols.
 *
 *     module Mod
 *       attr_accessor(:one, :two)
 *     end
 *     Mod.instance_methods.sort   #=> [:one, :one=, :two, :two=]
 */

static VALUE
rb_mod_attr_accessor(int argc, VALUE *argv, VALUE klass)
{
    int i;

    for (i=0; i<argc; i++) {
	rb_attr(klass, id_for_attr(argv[i]), TRUE, TRUE, TRUE);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     mod.const_get(sym, inherit=true)    -> obj
 *     mod.const_get(str, inherit=true)    -> obj
 *
 *  Checks for a constant with the given name in <i>mod</i>
 *  If +inherit+ is set, the lookup will also search
 *  the ancestors (and +Object+ if <i>mod</i> is a +Module+.)
 *
 *  The value of the constant is returned if a definition is found,
 *  otherwise a +NameError+ is raised.
 *
 *     Math.const_get(:PI)   #=> 3.14159265358979
 *
 *  This method will recursively look up constant names if a namespaced
 *  class name is provided.  For example:
 *
 *     module Foo; class Bar; end end
 *     Object.const_get 'Foo::Bar'
 *
 *  The +inherit+ flag is respected on each lookup.  For example:
 *
 *     module Foo
 *       class Bar
 *         VAL = 10
 *       end
 *
 *       class Baz < Bar; end
 *     end
 *
 *     Object.const_get 'Foo::Baz::VAL'         # => 10
 *     Object.const_get 'Foo::Baz::VAL', false  # => NameError
 *
 *  If neither +sym+ nor +str+ is not a valid constant name a NameError will be
 *  raised with a warning "wrong constant name".
 *
 *	Object.const_get 'foobar' #=> NameError: wrong constant name foobar
 *
 */

static VALUE
rb_mod_const_get(int argc, VALUE *argv, VALUE mod)
{
    VALUE name, recur;
    rb_encoding *enc;
    const char *pbeg, *p, *path, *pend;
    ID id;
    int nestable = 1;

    if (argc == 1) {
	name = argv[0];
	recur = Qtrue;
    }
    else {
	rb_scan_args(argc, argv, "11", &name, &recur);
    }

    if (SYMBOL_P(name)) {
	name = rb_sym_to_s(name);
	nestable = 0;
    }

    name = rb_check_string_type(name);
    Check_Type(name, T_STRING);

    enc = rb_enc_get(name);
    path = RSTRING_PTR(name);

    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "invalid class path encoding (non ASCII)");
    }

    pbeg = p = path;
    pend = path + RSTRING_LEN(name);

    if (p >= pend || !*p) {
      wrong_name:
	rb_raise(rb_eNameError, "wrong constant name %"PRIsVALUE,
		 QUOTE(name));
    }

    if (p + 2 < pend && p[0] == ':' && p[1] == ':') {
	if (!nestable) goto wrong_name;
	mod = rb_cObject;
	p += 2;
	pbeg = p;
    }

    while (p < pend) {
	VALUE part;
	long len, beglen;

	while (p < pend && *p != ':') p++;

	if (pbeg == p) goto wrong_name;

	id = rb_check_id_cstr(pbeg, len = p-pbeg, enc);
	beglen = pbeg-path;

	if (p < pend && p[0] == ':') {
	    if (!nestable) goto wrong_name;
	    if (p + 2 >= pend || p[1] != ':') goto wrong_name;
	    p += 2;
	    pbeg = p;
	}

	if (!RB_TYPE_P(mod, T_MODULE) && !RB_TYPE_P(mod, T_CLASS)) {
	    rb_raise(rb_eTypeError, "%"PRIsVALUE" does not refer to class/module",
		     QUOTE(name));
	}

	if (!id) {
	    if (!ISUPPER(*pbeg) || !rb_enc_symname2_p(pbeg, len, enc)) {
		part = rb_str_subseq(name, beglen, len);
		rb_name_error_str(part, "wrong constant name %"PRIsVALUE,
				  QUOTE(part));
	    }
	    else if (!rb_method_basic_definition_p(CLASS_OF(mod), id_const_missing)) {
		id = rb_intern3(pbeg, len, enc);
	    }
	    else {
		part = rb_str_subseq(name, beglen, len);
		rb_name_error_str(part, "uninitialized constant %"PRIsVALUE"%"PRIsVALUE,
				  rb_str_subseq(name, 0, beglen),
				  QUOTE(part));
	    }
	}
	if (!rb_is_const_id(id)) {
	    rb_name_error(id, "wrong constant name %"PRIsVALUE,
			  QUOTE_ID(id));
	}
	mod = RTEST(recur) ? rb_const_get(mod, id) : rb_const_get_at(mod, id);
    }

    return mod;
}

/*
 *  call-seq:
 *     mod.const_set(sym, obj)    -> obj
 *     mod.const_set(str, obj)    -> obj
 *
 *  Sets the named constant to the given object, returning that object.
 *  Creates a new constant if no constant with the given name previously
 *  existed.
 *
 *     Math.const_set("HIGH_SCHOOL_PI", 22.0/7.0)   #=> 3.14285714285714
 *     Math::HIGH_SCHOOL_PI - Math::PI              #=> 0.00126448926734968
 *
 *  If neither +sym+ nor +str+ is not a valid constant name a NameError will be
 *  raised with a warning "wrong constant name".
 *
 *	Object.const_set('foobar', 42) #=> NameError: wrong constant name foobar
 *
 */

static VALUE
rb_mod_const_set(VALUE mod, VALUE name, VALUE value)
{
    ID id = id_for_setter(name, const, "wrong constant name %"PRIsVALUE);
    rb_const_set(mod, id, value);
    return value;
}

/*
 *  call-seq:
 *     mod.const_defined?(sym, inherit=true)   -> true or false
 *     mod.const_defined?(str, inherit=true)   -> true or false
 *
 *  Checks for a constant with the given name in <i>mod</i>
 *  If +inherit+ is set, the lookup will also search
 *  the ancestors (and +Object+ if <i>mod</i> is a +Module+.)
 *
 *  Returns whether or not a definition is found:
 *
 *     Math.const_defined? "PI"   #=> true
 *     IO.const_defined? :SYNC   #=> true
 *     IO.const_defined? :SYNC, false   #=> false
 *
 *  If neither +sym+ nor +str+ is not a valid constant name a NameError will be
 *  raised with a warning "wrong constant name".
 *
 *	Hash.const_defined? 'foobar' #=> NameError: wrong constant name foobar
 *
 */

static VALUE
rb_mod_const_defined(int argc, VALUE *argv, VALUE mod)
{
    VALUE name, recur;
    ID id;

    if (argc == 1) {
	name = argv[0];
	recur = Qtrue;
    }
    else {
	rb_scan_args(argc, argv, "11", &name, &recur);
    }
    if (!(id = rb_check_id(&name))) {
	if (rb_is_const_name(name)) {
	    return Qfalse;
	}
	else {
	    rb_name_error_str(name, "wrong constant name %"PRIsVALUE,
			      QUOTE(name));
	}
    }
    if (!rb_is_const_id(id)) {
	rb_name_error(id, "wrong constant name %"PRIsVALUE,
		      QUOTE_ID(id));
    }
    return RTEST(recur) ? rb_const_defined(mod, id) : rb_const_defined_at(mod, id);
}

/*
 *  call-seq:
 *     obj.instance_variable_get(symbol)    -> obj
 *     obj.instance_variable_get(string)    -> obj
 *
 *  Returns the value of the given instance variable, or nil if the
 *  instance variable is not set. The <code>@</code> part of the
 *  variable name should be included for regular instance
 *  variables. Throws a <code>NameError</code> exception if the
 *  supplied symbol is not valid as an instance variable name.
 *  String arguments are converted to symbols.
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
rb_obj_ivar_get(VALUE obj, VALUE iv)
{
    ID id = rb_check_id(&iv);

    if (!id) {
	if (rb_is_instance_name(iv)) {
	    return Qnil;
	}
	else {
	    rb_name_error_str(iv, "`%"PRIsVALUE"' is not allowed as an instance variable name",
			      QUOTE(iv));
	}
    }
    if (!rb_is_instance_id(id)) {
	rb_name_error(id, "`%"PRIsVALUE"' is not allowed as an instance variable name",
		      QUOTE_ID(id));
    }
    return rb_ivar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.instance_variable_set(symbol, obj)    -> obj
 *     obj.instance_variable_set(string, obj)    -> obj
 *
 *  Sets the instance variable names by <i>symbol</i> to
 *  <i>object</i>, thereby frustrating the efforts of the class's
 *  author to attempt to provide proper encapsulation. The variable
 *  did not have to exist prior to this call.
 *  If the instance variable name is passed as a string, that string
 *  is converted to a symbol.
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
rb_obj_ivar_set(VALUE obj, VALUE iv, VALUE val)
{
    ID id = id_for_setter(iv, instance, "`%"PRIsVALUE"' is not allowed as an instance variable name");
    return rb_ivar_set(obj, id, val);
}

/*
 *  call-seq:
 *     obj.instance_variable_defined?(symbol)    -> true or false
 *     obj.instance_variable_defined?(string)    -> true or false
 *
 *  Returns <code>true</code> if the given instance variable is
 *  defined in <i>obj</i>.
 *  String arguments are converted to symbols.
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
rb_obj_ivar_defined(VALUE obj, VALUE iv)
{
    ID id = rb_check_id(&iv);

    if (!id) {
	if (rb_is_instance_name(iv)) {
	    return Qfalse;
	}
	else {
	    rb_name_error_str(iv, "`%"PRIsVALUE"' is not allowed as an instance variable name",
			      QUOTE(iv));
	}
    }
    if (!rb_is_instance_id(id)) {
	rb_name_error(id, "`%"PRIsVALUE"' is not allowed as an instance variable name",
		      QUOTE_ID(id));
    }
    return rb_ivar_defined(obj, id);
}

/*
 *  call-seq:
 *     mod.class_variable_get(symbol)    -> obj
 *     mod.class_variable_get(string)    -> obj
 *
 *  Returns the value of the given class variable (or throws a
 *  <code>NameError</code> exception). The <code>@@</code> part of the
 *  variable name should be included for regular class variables
 *  String arguments are converted to symbols.
 *
 *     class Fred
 *       @@foo = 99
 *     end
 *     Fred.class_variable_get(:@@foo)     #=> 99
 */

static VALUE
rb_mod_cvar_get(VALUE obj, VALUE iv)
{
    ID id = rb_check_id(&iv);

    if (!id) {
	if (rb_is_class_name(iv)) {
	    rb_name_error_str(iv, "uninitialized class variable %"PRIsVALUE" in %"PRIsVALUE"",
			      iv, rb_class_name(obj));
	}
	else {
	    rb_name_error_str(iv, "`%"PRIsVALUE"' is not allowed as a class variable name",
			      QUOTE(iv));
	}
    }
    if (!rb_is_class_id(id)) {
	rb_name_error(id, "`%"PRIsVALUE"' is not allowed as a class variable name",
		      QUOTE_ID(id));
    }
    return rb_cvar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.class_variable_set(symbol, obj)    -> obj
 *     obj.class_variable_set(string, obj)    -> obj
 *
 *  Sets the class variable names by <i>symbol</i> to
 *  <i>object</i>.
 *  If the class variable name is passed as a string, that string
 *  is converted to a symbol.
 *
 *     class Fred
 *       @@foo = 99
 *       def foo
 *         @@foo
 *       end
 *     end
 *     Fred.class_variable_set(:@@foo, 101)     #=> 101
 *     Fred.new.foo                             #=> 101
 */

static VALUE
rb_mod_cvar_set(VALUE obj, VALUE iv, VALUE val)
{
    ID id = id_for_setter(iv, class, "`%"PRIsVALUE"' is not allowed as a class variable name");
    rb_cvar_set(obj, id, val);
    return val;
}

/*
 *  call-seq:
 *     obj.class_variable_defined?(symbol)    -> true or false
 *     obj.class_variable_defined?(string)    -> true or false
 *
 *  Returns <code>true</code> if the given class variable is defined
 *  in <i>obj</i>.
 *  String arguments are converted to symbols.
 *
 *     class Fred
 *       @@foo = 99
 *     end
 *     Fred.class_variable_defined?(:@@foo)    #=> true
 *     Fred.class_variable_defined?(:@@bar)    #=> false
 */

static VALUE
rb_mod_cvar_defined(VALUE obj, VALUE iv)
{
    ID id = rb_check_id(&iv);

    if (!id) {
	if (rb_is_class_name(iv)) {
	    return Qfalse;
	}
	else {
	    rb_name_error_str(iv, "`%"PRIsVALUE"' is not allowed as a class variable name",
			      QUOTE(iv));
	}
    }
    if (!rb_is_class_id(id)) {
	rb_name_error(id, "`%"PRIsVALUE"' is not allowed as a class variable name",
		      QUOTE_ID(id));
    }
    return rb_cvar_defined(obj, id);
}

static VALUE
rb_mod_singleton_p(VALUE klass)
{
    if (RB_TYPE_P(klass, T_CLASS) && FL_TEST(klass, FL_SINGLETON))
	return Qtrue;
    return Qfalse;
}

static struct conv_method_tbl {
    const char *method;
    ID id;
} conv_method_names[] = {
    {"to_int", 0},
    {"to_ary", 0},
    {"to_str", 0},
    {"to_sym", 0},
    {"to_hash", 0},
    {"to_proc", 0},
    {"to_io", 0},
    {"to_a", 0},
    {"to_s", 0},
    {NULL, 0}
};
#define IMPLICIT_CONVERSIONS 7

static VALUE
convert_type(VALUE val, const char *tname, const char *method, int raise)
{
    ID m = 0;
    int i;
    VALUE r;

    for (i=0; conv_method_names[i].method; i++) {
	if (conv_method_names[i].method[0] == method[0] &&
	    strcmp(conv_method_names[i].method, method) == 0) {
	    m = conv_method_names[i].id;
	    break;
	}
    }
    if (!m) m = rb_intern(method);
    r = rb_check_funcall(val, m, 0, 0);
    if (r == Qundef) {
	if (raise) {
	    rb_raise(rb_eTypeError, i < IMPLICIT_CONVERSIONS
                ? "no implicit conversion of %s into %s"
                : "can't convert %s into %s",
		     NIL_P(val) ? "nil" :
		     val == Qtrue ? "true" :
		     val == Qfalse ? "false" :
		     rb_obj_classname(val),
		     tname);
	}
	return Qnil;
    }
    return r;
}

VALUE
rb_convert_type(VALUE val, int type, const char *tname, const char *method)
{
    VALUE v;

    if (TYPE(val) == type) return val;
    v = convert_type(val, tname, method, TRUE);
    if (TYPE(v) != type) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to %s (%s#%s gives %s)",
		 cname, tname, cname, method, rb_obj_classname(v));
    }
    return v;
}

VALUE
rb_check_convert_type(VALUE val, int type, const char *tname, const char *method)
{
    VALUE v;

    /* always convert T_DATA */
    if (TYPE(val) == type && type != T_DATA) return val;
    v = convert_type(val, tname, method, FALSE);
    if (NIL_P(v)) return Qnil;
    if (TYPE(v) != type) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to %s (%s#%s gives %s)",
		 cname, tname, cname, method, rb_obj_classname(v));
    }
    return v;
}


static VALUE
rb_to_integer(VALUE val, const char *method)
{
    VALUE v;

    if (FIXNUM_P(val)) return val;
    if (RB_TYPE_P(val, T_BIGNUM)) return val;
    v = convert_type(val, "Integer", method, TRUE);
    if (!rb_obj_is_kind_of(v, rb_cInteger)) {
	const char *cname = rb_obj_classname(val);
	rb_raise(rb_eTypeError, "can't convert %s to Integer (%s#%s gives %s)",
		 cname, cname, method, rb_obj_classname(v));
    }
    return v;
}

VALUE
rb_check_to_integer(VALUE val, const char *method)
{
    VALUE v;

    if (FIXNUM_P(val)) return val;
    if (RB_TYPE_P(val, T_BIGNUM)) return val;
    v = convert_type(val, "Integer", method, FALSE);
    if (!rb_obj_is_kind_of(v, rb_cInteger)) {
	return Qnil;
    }
    return v;
}

VALUE
rb_to_int(VALUE val)
{
    return rb_to_integer(val, "to_int");
}

VALUE
rb_check_to_int(VALUE val)
{
    return rb_check_to_integer(val, "to_int");
}

static VALUE
rb_convert_to_integer(VALUE val, int base)
{
    VALUE tmp;

    switch (TYPE(val)) {
      case T_FLOAT:
	if (base != 0) goto arg_error;
	if (RFLOAT_VALUE(val) <= (double)FIXNUM_MAX
	    && RFLOAT_VALUE(val) >= (double)FIXNUM_MIN) {
	    break;
	}
	return rb_dbl2big(RFLOAT_VALUE(val));

      case T_FIXNUM:
      case T_BIGNUM:
	if (base != 0) goto arg_error;
	return val;

      case T_STRING:
      string_conv:
	return rb_str_to_inum(val, base, TRUE);

      case T_NIL:
	if (base != 0) goto arg_error;
	rb_raise(rb_eTypeError, "can't convert nil into Integer");
	break;

      default:
	break;
    }
    if (base != 0) {
	tmp = rb_check_string_type(val);
	if (!NIL_P(tmp)) goto string_conv;
      arg_error:
	rb_raise(rb_eArgError, "base specified for non string value");
    }
    tmp = convert_type(val, "Integer", "to_int", FALSE);
    if (NIL_P(tmp)) {
	return rb_to_integer(val, "to_i");
    }
    return tmp;

}

VALUE
rb_Integer(VALUE val)
{
    return rb_convert_to_integer(val, 0);
}

/*
 *  call-seq:
 *     Integer(arg,base=0)    -> integer
 *
 *  Converts <i>arg</i> to a <code>Fixnum</code> or <code>Bignum</code>.
 *  Numeric types are converted directly (with floating point numbers
 *  being truncated).    <i>base</i> (0, or between 2 and 36) is a base for
 *  integer string representation.  If <i>arg</i> is a <code>String</code>,
 *  when <i>base</i> is omitted or equals to zero, radix indicators
 *  (<code>0</code>, <code>0b</code>, and <code>0x</code>) are honored.
 *  In any case, strings should be strictly conformed to numeric
 *  representation. This behavior is different from that of
 *  <code>String#to_i</code>.  Non string values will be converted using
 *  <code>to_int</code>, and <code>to_i</code>.
 *
 *     Integer(123.999)    #=> 123
 *     Integer("0x1a")     #=> 26
 *     Integer(Time.new)   #=> 1204973019
 *     Integer("0930", 10) #=> 930
 *     Integer("111", 2)   #=> 7
 */

static VALUE
rb_f_integer(int argc, VALUE *argv, VALUE obj)
{
    VALUE arg = Qnil;
    int base = 0;

    switch (argc) {
      case 2:
	base = NUM2INT(argv[1]);
      case 1:
	arg = argv[0];
	break;
      default:
	/* should cause ArgumentError */
	rb_scan_args(argc, argv, "11", NULL, NULL);
    }
    return rb_convert_to_integer(arg, base);
}

double
rb_cstr_to_dbl(const char *p, int badcheck)
{
    const char *q;
    char *end;
    double d;
    const char *ellipsis = "";
    int w;
    enum {max_width = 20};
#define OutOfRange() ((end - p > max_width) ? \
		      (w = max_width, ellipsis = "...") : \
		      (w = (int)(end - p), ellipsis = ""))

    if (!p) return 0.0;
    q = p;
    while (ISSPACE(*p)) p++;

    if (!badcheck && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
	return 0.0;
    }

    d = strtod(p, &end);
    if (errno == ERANGE) {
	OutOfRange();
	rb_warning("Float %.*s%s out of range", w, p, ellipsis);
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
	char buf[DBL_DIG * 4 + 10];
	char *n = buf;
	char *e = buf + sizeof(buf) - 1;
	char prev = 0;

	while (p < end && n < e) prev = *n++ = *p++;
	while (*p) {
	    if (*p == '_') {
		/* remove underscores between digits */
		if (badcheck) {
		    if (n == buf || !ISDIGIT(prev)) goto bad;
		    ++p;
		    if (!ISDIGIT(*p)) goto bad;
		}
		else {
		    while (*++p == '_');
		    continue;
		}
	    }
	    prev = *p++;
	    if (n < e) *n++ = prev;
	}
	*n = '\0';
	p = buf;

	if (!badcheck && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
	    return 0.0;
	}

	d = strtod(p, &end);
	if (errno == ERANGE) {
	    OutOfRange();
	    rb_warning("Float %.*s%s out of range", w, p, ellipsis);
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
rb_str_to_dbl(VALUE str, int badcheck)
{
    char *s;
    long len;
    double ret;
    VALUE v = 0;

    StringValue(str);
    s = RSTRING_PTR(str);
    len = RSTRING_LEN(str);
    if (s) {
	if (badcheck && memchr(s, '\0', len)) {
	    rb_raise(rb_eArgError, "string for Float contains null byte");
	}
	if (s[len]) {		/* no sentinel somehow */
	    char *p =  ALLOCV(v, len);
	    MEMCPY(p, s, char, len);
	    p[len] = '\0';
	    s = p;
	}
    }
    ret = rb_cstr_to_dbl(s, badcheck);
    if (v)
	ALLOCV_END(v);
    return ret;
}

VALUE
rb_Float(VALUE val)
{
    switch (TYPE(val)) {
      case T_FIXNUM:
	return DBL2NUM((double)FIX2LONG(val));

      case T_FLOAT:
	return val;

      case T_BIGNUM:
	return DBL2NUM(rb_big2dbl(val));

      case T_STRING:
	return DBL2NUM(rb_str_to_dbl(val, TRUE));

      case T_NIL:
	rb_raise(rb_eTypeError, "can't convert nil into Float");
	break;

      default:
	return rb_convert_type(val, T_FLOAT, "Float", "to_f");
    }

    UNREACHABLE;
}

/*
 *  call-seq:
 *     Float(arg)    -> float
 *
 *  Returns <i>arg</i> converted to a float. Numeric types are converted
 *  directly, the rest are converted using <i>arg</i>.to_f. As of Ruby
 *  1.8, converting <code>nil</code> generates a <code>TypeError</code>.
 *
 *     Float(1)           #=> 1.0
 *     Float("123.456")   #=> 123.456
 */

static VALUE
rb_f_float(VALUE obj, VALUE arg)
{
    return rb_Float(arg);
}

VALUE
rb_to_float(VALUE val)
{
    if (RB_TYPE_P(val, T_FLOAT)) return val;
    if (!rb_obj_is_kind_of(val, rb_cNumeric)) {
	rb_raise(rb_eTypeError, "can't convert %s into Float",
		 NIL_P(val) ? "nil" :
		 val == Qtrue ? "true" :
		 val == Qfalse ? "false" :
		 rb_obj_classname(val));
    }
    return rb_convert_type(val, T_FLOAT, "Float", "to_f");
}

VALUE
rb_check_to_float(VALUE val)
{
    if (RB_TYPE_P(val, T_FLOAT)) return val;
    if (!rb_obj_is_kind_of(val, rb_cNumeric)) {
	return Qnil;
    }
    return rb_check_convert_type(val, T_FLOAT, "Float", "to_f");
}

double
rb_num2dbl(VALUE val)
{
    switch (TYPE(val)) {
      case T_FLOAT:
	return RFLOAT_VALUE(val);

      case T_STRING:
	rb_raise(rb_eTypeError, "no implicit conversion to float from string");
	break;

      case T_NIL:
	rb_raise(rb_eTypeError, "no implicit conversion to float from nil");
	break;

      default:
	break;
    }

    return RFLOAT_VALUE(rb_Float(val));
}

VALUE
rb_String(VALUE val)
{
    VALUE tmp = rb_check_string_type(val);
    if (NIL_P(tmp))
	tmp = rb_convert_type(val, T_STRING, "String", "to_s");
    return tmp;
}


/*
 *  call-seq:
 *     String(arg)   -> string
 *
 *  Converts <i>arg</i> to a <code>String</code> by calling its
 *  <code>to_s</code> method.
 *
 *     String(self)        #=> "main"
 *     String(self.class)  #=> "Object"
 *     String(123456)      #=> "123456"
 */

static VALUE
rb_f_string(VALUE obj, VALUE arg)
{
    return rb_String(arg);
}

VALUE
rb_Array(VALUE val)
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

/*
 *  call-seq:
 *     Array(arg)    -> array
 *
 *  Returns +arg+ as an Array.
 *
 *  First tries to call Array#to_ary on +arg+, then Array#to_a.
 *
 *     Array(1..5)   #=> [1, 2, 3, 4, 5]
 */

static VALUE
rb_f_array(VALUE obj, VALUE arg)
{
    return rb_Array(arg);
}

VALUE
rb_Hash(VALUE val)
{
    VALUE tmp;

    if (NIL_P(val)) return rb_hash_new();
    tmp = rb_check_hash_type(val);
    if (NIL_P(tmp)) {
	if (RB_TYPE_P(val, T_ARRAY) && RARRAY_LEN(val) == 0)
	    return rb_hash_new();
	rb_raise(rb_eTypeError, "can't convert %s into Hash", rb_obj_classname(val));
    }
    return tmp;
}

/*
 *  call-seq:
 *     Hash(arg)    -> hash
 *
 *  Converts <i>arg</i> to a <code>Hash</code> by calling
 *  <i>arg</i><code>.to_hash</code>. Returns an empty <code>Hash</code> when
 *  <i>arg</i> is <tt>nil</tt> or <tt>[]</tt>.
 *
 *     Hash([])          #=> {}
 *     Hash(nil)         #=> {}
 *     Hash(key: :value) #=> {:key => :value}
 *     Hash([1, 2, 3])   #=> TypeError
 */

static VALUE
rb_f_hash(VALUE obj, VALUE arg)
{
    return rb_Hash(arg);
}

/*
 *  Document-class: Class
 *
 *  Classes in Ruby are first-class objects---each is an instance of
 *  class <code>Class</code>.
 *
 *  Typically, you create a new class by using:
 *
 *    class Name
 *     # some class describing the class behavior
 *    end
 *
 *  When a new class is created, an object of type Class is initialized and
 *  assigned to a global constant (<code>Name</code> in this case).
 *
 *  When <code>Name.new</code> is called to create a new object, the
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
 *                             +---------+             +-...
 *                             |         |             |
 *             BasicObject-----|-->(BasicObject)-------|-...
 *                 ^           |         ^             |
 *                 |           |         |             |
 *              Object---------|----->(Object)---------|-...
 *                 ^           |         ^             |
 *                 |           |         |             |
 *                 +-------+   |         +--------+    |
 *                 |       |   |         |        |    |
 *                 |    Module-|---------|--->(Module)-|-...
 *                 |       ^   |         |        ^    |
 *                 |       |   |         |        |    |
 *                 |     Class-|---------|---->(Class)-|-...
 *                 |       ^   |         |        ^    |
 *                 |       +---+         |        +----+
 *                 |                     |
 *    obj--->OtherClass---------->(OtherClass)-----------...
 *
 */


/*!
 * Initializes the world of objects and classes.
 *
 * At first, the function bootstraps the class hierarchy.
 * It initializes the most fundamental classes and their metaclasses.
 * - \c BasicObject
 * - \c Object
 * - \c Module
 * - \c Class
 * After the bootstrap step, the class hierarchy becomes as the following
 * diagram.
 *
 * \image html boottime-classes.png
 *
 * Then, the function defines classes, modules and methods as usual.
 * \ingroup class
 */

/*  Document-class: BasicObject
 *
 *  BasicObject is the parent class of all classes in Ruby.  It's an explicit
 *  blank class.
 *
 *  BasicObject can be used for creating object hierarchies independent of
 *  Ruby's object hierarchy, proxy objects like the Delegator class, or other
 *  uses where namespace pollution from Ruby's methods and classes must be
 *  avoided.
 *
 *  To avoid polluting BasicObject for other users an appropriately named
 *  subclass of BasicObject should be created instead of directly modifying
 *  BasicObject:
 *
 *    class MyObjectSystem < BasicObject
 *    end
 *
 *  BasicObject does not include Kernel (for methods like +puts+) and
 *  BasicObject is outside of the namespace of the standard library so common
 *  classes will not be found without a using a full class path.
 *
 *  A variety of strategies can be used to provide useful portions of the
 *  standard library to subclasses of BasicObject.  A subclass could
 *  <code>include Kernel</code> to obtain +puts+, +exit+, etc.  A custom
 *  Kernel-like module could be created and included or delegation can be used
 *  via #method_missing:
 *
 *    class MyObjectSystem < BasicObject
 *      DELEGATE = [:puts, :p]
 *
 *      def method_missing(name, *args, &block)
 *        super unless DELEGATE.include? name
 *        ::Kernel.send(name, *args, &block)
 *      end
 *
 *      def respond_to_missing?(name, include_private = false)
 *        DELEGATE.include?(name) or super
 *      end
 *    end
 *
 *  Access to classes and modules from the Ruby standard library can be
 *  obtained in a BasicObject subclass by referencing the desired constant
 *  from the root like <code>::File</code> or <code>::Enumerator</code>.
 *  Like #method_missing, #const_missing can be used to delegate constant
 *  lookup to +Object+:
 *
 *    class MyObjectSystem < BasicObject
 *      def self.const_missing(name)
 *        ::Object.const_get(name)
 *      end
 *    end
 */

/*  Document-class: Object
 *
 *  Object is the default root of all Ruby objects.  Object inherits from
 *  BasicObject which allows creating alternate object hierarchies.  Methods
 *  on object are available to all classes unless explicitly overridden.
 *
 *  Object mixes in the Kernel module, making the built-in kernel functions
 *  globally accessible.  Although the instance methods of Object are defined
 *  by the Kernel module, we have chosen to document them here for clarity.
 *
 *  When referencing constants in classes inheriting from Object you do not
 *  need to use the full namespace.  For example, referencing +File+ inside
 *  +YourClass+ will find the top-level File class.
 *
 *  In the descriptions of Object's methods, the parameter <i>symbol</i> refers
 *  to a symbol, which is either a quoted string or a Symbol (such as
 *  <code>:name</code>).
 */

void
Init_Object(void)
{
    int i;

    Init_class_hierarchy();

#if 0
    // teach RDoc about these classes
    rb_cBasicObject = rb_define_class("BasicObject", Qnil);
    rb_cObject = rb_define_class("Object", rb_cBasicObject);
    rb_cModule = rb_define_class("Module", rb_cObject);
    rb_cClass =  rb_define_class("Class",  rb_cModule);
#endif

#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_define_private_method(rb_cBasicObject, "initialize", rb_obj_dummy, 0);
    rb_define_alloc_func(rb_cBasicObject, rb_class_allocate_instance);
    rb_define_method(rb_cBasicObject, "==", rb_obj_equal, 1);
    rb_define_method(rb_cBasicObject, "equal?", rb_obj_equal, 1);
    rb_define_method(rb_cBasicObject, "!", rb_obj_not, 0);
    rb_define_method(rb_cBasicObject, "!=", rb_obj_not_equal, 1);

    rb_define_private_method(rb_cBasicObject, "singleton_method_added", rb_obj_dummy, 1);
    rb_define_private_method(rb_cBasicObject, "singleton_method_removed", rb_obj_dummy, 1);
    rb_define_private_method(rb_cBasicObject, "singleton_method_undefined", rb_obj_dummy, 1);

    /* Document-module: Kernel
     *
     * The Kernel module is included by class Object, so its methods are
     * available in every Ruby object.
     *
     * The Kernel instance methods are documented in class Object while the
     * module methods are documented here.  These methods are called without a
     * receiver and thus can be called in functional form:
     *
     *   sprintf "%.1f", 1.234 #=> "1.2"
     *
     */
    rb_mKernel = rb_define_module("Kernel");
    rb_include_module(rb_cObject, rb_mKernel);
    rb_define_private_method(rb_cClass, "inherited", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "included", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "extended", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "prepended", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_added", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_removed", rb_obj_dummy, 1);
    rb_define_private_method(rb_cModule, "method_undefined", rb_obj_dummy, 1);

    rb_define_method(rb_mKernel, "nil?", rb_false, 0);
    rb_define_method(rb_mKernel, "===", rb_equal, 1);
    rb_define_method(rb_mKernel, "=~", rb_obj_match, 1);
    rb_define_method(rb_mKernel, "!~", rb_obj_not_match, 1);
    rb_define_method(rb_mKernel, "eql?", rb_obj_equal, 1);
    rb_define_method(rb_mKernel, "hash", rb_obj_hash, 0);
    rb_define_method(rb_mKernel, "<=>", rb_obj_cmp, 1);

    rb_define_method(rb_mKernel, "class", rb_obj_class, 0);
    rb_define_method(rb_mKernel, "singleton_class", rb_obj_singleton_class, 0);
    rb_define_method(rb_mKernel, "clone", rb_obj_clone, 0);
    rb_define_method(rb_mKernel, "dup", rb_obj_dup, 0);
    rb_define_method(rb_mKernel, "initialize_copy", rb_obj_init_copy, 1);
    rb_define_method(rb_mKernel, "initialize_dup", rb_obj_init_dup_clone, 1);
    rb_define_method(rb_mKernel, "initialize_clone", rb_obj_init_dup_clone, 1);

    rb_define_method(rb_mKernel, "taint", rb_obj_taint, 0);
    rb_define_method(rb_mKernel, "tainted?", rb_obj_tainted, 0);
    rb_define_method(rb_mKernel, "untaint", rb_obj_untaint, 0);
    rb_define_method(rb_mKernel, "untrust", rb_obj_untrust, 0);
    rb_define_method(rb_mKernel, "untrusted?", rb_obj_untrusted, 0);
    rb_define_method(rb_mKernel, "trust", rb_obj_trust, 0);
    rb_define_method(rb_mKernel, "freeze", rb_obj_freeze, 0);
    rb_define_method(rb_mKernel, "frozen?", rb_obj_frozen_p, 0);

    rb_define_method(rb_mKernel, "to_s", rb_any_to_s, 0);
    rb_define_method(rb_mKernel, "inspect", rb_obj_inspect, 0);
    rb_define_method(rb_mKernel, "methods", rb_obj_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "singleton_methods", rb_obj_singleton_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "protected_methods", rb_obj_protected_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "private_methods", rb_obj_private_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "public_methods", rb_obj_public_methods, -1); /* in class.c */
    rb_define_method(rb_mKernel, "instance_variables", rb_obj_instance_variables, 0); /* in variable.c */
    rb_define_method(rb_mKernel, "instance_variable_get", rb_obj_ivar_get, 1);
    rb_define_method(rb_mKernel, "instance_variable_set", rb_obj_ivar_set, 2);
    rb_define_method(rb_mKernel, "instance_variable_defined?", rb_obj_ivar_defined, 1);
    rb_define_method(rb_mKernel, "remove_instance_variable",
		     rb_obj_remove_instance_variable, 1); /* in variable.c */

    rb_define_method(rb_mKernel, "instance_of?", rb_obj_is_instance_of, 1);
    rb_define_method(rb_mKernel, "kind_of?", rb_obj_is_kind_of, 1);
    rb_define_method(rb_mKernel, "is_a?", rb_obj_is_kind_of, 1);
    rb_define_method(rb_mKernel, "tap", rb_obj_tap, 0);

    rb_define_global_function("sprintf", rb_f_sprintf, -1); /* in sprintf.c */
    rb_define_global_function("format", rb_f_sprintf, -1);  /* in sprintf.c */

    rb_define_global_function("Integer", rb_f_integer, -1);
    rb_define_global_function("Float", rb_f_float, 1);

    rb_define_global_function("String", rb_f_string, 1);
    rb_define_global_function("Array", rb_f_array, 1);
    rb_define_global_function("Hash", rb_f_hash, 1);

    rb_cNilClass = rb_define_class("NilClass", rb_cObject);
    rb_define_method(rb_cNilClass, "to_i", nil_to_i, 0);
    rb_define_method(rb_cNilClass, "to_f", nil_to_f, 0);
    rb_define_method(rb_cNilClass, "to_s", nil_to_s, 0);
    rb_define_method(rb_cNilClass, "to_a", nil_to_a, 0);
    rb_define_method(rb_cNilClass, "to_h", nil_to_h, 0);
    rb_define_method(rb_cNilClass, "inspect", nil_inspect, 0);
    rb_define_method(rb_cNilClass, "&", false_and, 1);
    rb_define_method(rb_cNilClass, "|", false_or, 1);
    rb_define_method(rb_cNilClass, "^", false_xor, 1);

    rb_define_method(rb_cNilClass, "nil?", rb_true, 0);
    rb_undef_alloc_func(rb_cNilClass);
    rb_undef_method(CLASS_OF(rb_cNilClass), "new");
    /*
     * An alias of +nil+
     */
    rb_define_global_const("NIL", Qnil);

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
    rb_define_alias(rb_cModule, "inspect", "to_s");
    rb_define_method(rb_cModule, "included_modules", rb_mod_included_modules, 0); /* in class.c */
    rb_define_method(rb_cModule, "include?", rb_mod_include_p, 1); /* in class.c */
    rb_define_method(rb_cModule, "name", rb_mod_name, 0);  /* in variable.c */
    rb_define_method(rb_cModule, "ancestors", rb_mod_ancestors, 0); /* in class.c */

    rb_define_private_method(rb_cModule, "attr", rb_mod_attr, -1);
    rb_define_private_method(rb_cModule, "attr_reader", rb_mod_attr_reader, -1);
    rb_define_private_method(rb_cModule, "attr_writer", rb_mod_attr_writer, -1);
    rb_define_private_method(rb_cModule, "attr_accessor", rb_mod_attr_accessor, -1);

    rb_define_alloc_func(rb_cModule, rb_module_s_alloc);
    rb_define_method(rb_cModule, "initialize", rb_mod_initialize, 0);
    rb_define_method(rb_cModule, "instance_methods", rb_class_instance_methods, -1); /* in class.c */
    rb_define_method(rb_cModule, "public_instance_methods",
		     rb_class_public_instance_methods, -1);    /* in class.c */
    rb_define_method(rb_cModule, "protected_instance_methods",
		     rb_class_protected_instance_methods, -1); /* in class.c */
    rb_define_method(rb_cModule, "private_instance_methods",
		     rb_class_private_instance_methods, -1);   /* in class.c */

    rb_define_method(rb_cModule, "constants", rb_mod_constants, -1); /* in variable.c */
    rb_define_method(rb_cModule, "const_get", rb_mod_const_get, -1);
    rb_define_method(rb_cModule, "const_set", rb_mod_const_set, 2);
    rb_define_method(rb_cModule, "const_defined?", rb_mod_const_defined, -1);
    rb_define_private_method(rb_cModule, "remove_const",
			     rb_mod_remove_const, 1); /* in variable.c */
    rb_define_method(rb_cModule, "const_missing",
		     rb_mod_const_missing, 1); /* in variable.c */
    rb_define_method(rb_cModule, "class_variables",
		     rb_mod_class_variables, -1); /* in variable.c */
    rb_define_method(rb_cModule, "remove_class_variable",
		     rb_mod_remove_cvar, 1); /* in variable.c */
    rb_define_method(rb_cModule, "class_variable_get", rb_mod_cvar_get, 1);
    rb_define_method(rb_cModule, "class_variable_set", rb_mod_cvar_set, 2);
    rb_define_method(rb_cModule, "class_variable_defined?", rb_mod_cvar_defined, 1);
    rb_define_method(rb_cModule, "public_constant", rb_mod_public_constant, -1); /* in variable.c */
    rb_define_method(rb_cModule, "private_constant", rb_mod_private_constant, -1); /* in variable.c */
    rb_define_method(rb_cModule, "singleton_class?", rb_mod_singleton_p, 0);

    rb_define_method(rb_cClass, "allocate", rb_obj_alloc, 0);
    rb_define_method(rb_cClass, "new", rb_class_new_instance, -1);
    rb_define_method(rb_cClass, "initialize", rb_class_initialize, -1);
    rb_define_method(rb_cClass, "superclass", rb_class_superclass, 0);
    rb_define_alloc_func(rb_cClass, rb_class_s_alloc);
    rb_undef_method(rb_cClass, "extend_object");
    rb_undef_method(rb_cClass, "append_features");
    rb_undef_method(rb_cClass, "prepend_features");

    /*
     * Document-class: Data
     *
     * This is a recommended base class for C extensions using Data_Make_Struct
     * or Data_Wrap_Struct, see README.EXT for details.
     */
    rb_cData = rb_define_class("Data", rb_cObject);
    rb_undef_alloc_func(rb_cData);

    rb_cTrueClass = rb_define_class("TrueClass", rb_cObject);
    rb_define_method(rb_cTrueClass, "to_s", true_to_s, 0);
    rb_define_alias(rb_cTrueClass, "inspect", "to_s");
    rb_define_method(rb_cTrueClass, "&", true_and, 1);
    rb_define_method(rb_cTrueClass, "|", true_or, 1);
    rb_define_method(rb_cTrueClass, "^", true_xor, 1);
    rb_undef_alloc_func(rb_cTrueClass);
    rb_undef_method(CLASS_OF(rb_cTrueClass), "new");
    /*
     * An alias of +true+
     */
    rb_define_global_const("TRUE", Qtrue);

    rb_cFalseClass = rb_define_class("FalseClass", rb_cObject);
    rb_define_method(rb_cFalseClass, "to_s", false_to_s, 0);
    rb_define_alias(rb_cFalseClass, "inspect", "to_s");
    rb_define_method(rb_cFalseClass, "&", false_and, 1);
    rb_define_method(rb_cFalseClass, "|", false_or, 1);
    rb_define_method(rb_cFalseClass, "^", false_xor, 1);
    rb_undef_alloc_func(rb_cFalseClass);
    rb_undef_method(CLASS_OF(rb_cFalseClass), "new");
    /*
     * An alias of +false+
     */
    rb_define_global_const("FALSE", Qfalse);

    for (i=0; conv_method_names[i].method; i++) {
	conv_method_names[i].id = rb_intern(conv_method_names[i].method);
    }
}
