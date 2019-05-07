/**********************************************************************

  object.c -

  $Author$
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/encoding.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "internal.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <math.h>
#include <float.h>
#include "constant.h"
#include "id.h"
#include "probes.h"

/*!
 * \defgroup object Core objects and their operations
 * \{
 */

VALUE rb_cBasicObject; /*!< BasicObject class */
VALUE rb_mKernel; /*!< Kernel module */
VALUE rb_cObject; /*!< Object class */
VALUE rb_cModule; /*!< Module class */
VALUE rb_cClass; /*!< Class class */
VALUE rb_cData; /*!< Data class */

VALUE rb_cNilClass; /*!< NilClass class */
VALUE rb_cTrueClass; /*!< TrueClass class */
VALUE rb_cFalseClass; /*!< FalseClass class */

/*! \cond INTERNAL_MACRO */

#define id_eq               idEq
#define id_eql              idEqlP
#define id_match            idEqTilde
#define id_inspect          idInspect
#define id_init_copy        idInitialize_copy
#define id_init_clone       idInitialize_clone
#define id_init_dup         idInitialize_dup
#define id_const_missing    idConst_missing
#define id_to_f             idTo_f

#define CLASS_OR_MODULE_P(obj) \
    (!SPECIAL_CONST_P(obj) && \
     (BUILTIN_TYPE(obj) == T_CLASS || BUILTIN_TYPE(obj) == T_MODULE))

/*! \endcond */

/*!
 * Make the object invisible from Ruby code.
 *
 * It is useful to let Ruby's GC manage your internal data structure --
 * The object keeps being managed by GC, but \c ObjectSpace.each_object
 * never yields the object.
 *
 * Note that the object also lose a way to call a method on it.
 *
 * \param[in] obj a Ruby object
 * \sa rb_obj_reveal
 */
VALUE
rb_obj_hide(VALUE obj)
{
    if (!SPECIAL_CONST_P(obj)) {
	RBASIC_CLEAR_CLASS(obj);
    }
    return obj;
}

/*!
 * Make a hidden object visible again.
 *
 * It is the caller's responsibility to pass the right \a klass
 * which \a obj originally used to belong to.
 *
 * \sa rb_obj_hide
 */
VALUE
rb_obj_reveal(VALUE obj, VALUE klass)
{
    if (!SPECIAL_CONST_P(obj)) {
	RBASIC_SET_CLASS(obj, klass);
    }
    return obj;
}

/*!
 * Fills common (\c RBasic) fields in \a obj.
 *
 * \note Prefer rb_newobj_of() to this function.
 * \param[in,out] obj a Ruby object to be set up.
 * \param[in] klass \c obj will belong to this class.
 * \param[in] type one of \c ruby_value_type
 */
VALUE
rb_obj_setup(VALUE obj, VALUE klass, VALUE type)
{
    RBASIC(obj)->flags = type;
    RBASIC_SET_CLASS(obj, klass);
    return obj;
}

/**
 *  call-seq:
 *     obj === other   -> true or false
 *
 *  Case Equality -- For class Object, effectively the same as calling
 *  <code>#==</code>, but typically overridden by descendants to provide
 *  meaningful semantics in +case+ statements.
 *--
 * Same as \c Object#===, case equality.
 *++
 */

VALUE
rb_equal(VALUE obj1, VALUE obj2)
{
    VALUE result;

    if (obj1 == obj2) return Qtrue;
    result = rb_equal_opt(obj1, obj2);
    if (result == Qundef) {
	result = rb_funcall(obj1, id_eq, 1, obj2);
    }
    if (RTEST(result)) return Qtrue;
    return Qfalse;
}

/**
 * Determines if \a obj1 and \a obj2 are equal in terms of
 * \c Object#eql?.
 *
 * \note It actually calls \c #eql? when necessary.
 *   So you cannot implement \c #eql? with this function.
 * \retval non-zero if they are eql?
 * \retval zero if they are not eql?.
 */
int
rb_eql(VALUE obj1, VALUE obj2)
{
    VALUE result;

    if (obj1 == obj2) return Qtrue;
    result = rb_eql_opt(obj1, obj2);
    if (result == Qundef) {
	result = rb_funcall(obj1, id_eql, 1, obj2);
    }
    if (RTEST(result)) return Qtrue;
    return Qfalse;
}

/**
 *  call-seq:
 *     obj == other        -> true or false
 *     obj.equal?(other)   -> true or false
 *     obj.eql?(other)     -> true or false
 *
 *  Equality --- At the Object level, #== returns <code>true</code>
 *  only if +obj+ and +other+ are the same object.  Typically, this
 *  method is overridden in descendant classes to provide
 *  class-specific meaning.
 *
 *  Unlike #==, the #equal? method should never be overridden by
 *  subclasses as it is used to determine object identity (that is,
 *  <code>a.equal?(b)</code> if and only if <code>a</code> is the same
 *  object as <code>b</code>):
 *
 *    obj = "a"
 *    other = obj.dup
 *
 *    obj == other      #=> true
 *    obj.equal? other  #=> false
 *    obj.equal? obj    #=> true
 *
 *  The #eql? method returns <code>true</code> if +obj+ and +other+
 *  refer to the same hash key.  This is used by Hash to test members
 *  for equality.  For objects of class Object, #eql?  is synonymous
 *  with #==.  Subclasses normally continue this tradition by aliasing
 *  #eql? to their overridden #== method, but there are exceptions.
 *  Numeric types, for example, perform type conversion across #==,
 *  but not across #eql?, so:
 *
 *     1 == 1.0     #=> true
 *     1.eql? 1.0   #=> false
 *--
 * \private
 *++
 */
MJIT_FUNC_EXPORTED VALUE
rb_obj_equal(VALUE obj1, VALUE obj2)
{
    if (obj1 == obj2) return Qtrue;
    return Qfalse;
}

VALUE rb_obj_hash(VALUE obj);

/**
 *  call-seq:
 *     !obj    -> true or false
 *
 *  Boolean negate.
 *--
 * \private
 *++
 */

MJIT_FUNC_EXPORTED VALUE
rb_obj_not(VALUE obj)
{
    return RTEST(obj) ? Qfalse : Qtrue;
}

/**
 *  call-seq:
 *     obj != other        -> true or false
 *
 *  Returns true if two objects are not-equal, otherwise false.
 *--
 * \private
 *++
 */

MJIT_FUNC_EXPORTED VALUE
rb_obj_not_equal(VALUE obj1, VALUE obj2)
{
    VALUE result = rb_funcall(obj1, id_eq, 1, obj2);
    return RTEST(result) ? Qfalse : Qtrue;
}

/*!
 * Looks up the nearest ancestor of \a cl, skipping singleton classes or
 * module inclusions.
 * It returns the \a cl itself if it is neither a singleton class or a module.
 *
 * \param[in] cl a Class object.
 * \return the ancestor class found, or a falsey value if nothing found.
 */
VALUE
rb_class_real(VALUE cl)
{
    while (cl &&
        ((RBASIC(cl)->flags & FL_SINGLETON) || BUILTIN_TYPE(cl) == T_ICLASS)) {
	cl = RCLASS_SUPER(cl);
    }
    return cl;
}

/**
 *  call-seq:
 *     obj.class    -> class
 *
 *  Returns the class of <i>obj</i>. This method must always be called
 *  with an explicit receiver, as #class is also a reserved word in
 *  Ruby.
 *
 *     1.class      #=> Integer
 *     self.class   #=> Object
 *--
 * Equivalent to \c Object\#class in Ruby.
 *
 * Returns the class of \c obj, skipping singleton classes or module inclusions.
 *++
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
 *  a new singleton class if <i>obj</i> does not have one.
 *
 *  If <i>obj</i> is <code>nil</code>, <code>true</code>, or
 *  <code>false</code>, it returns NilClass, TrueClass, or FalseClass,
 *  respectively.
 *  If <i>obj</i> is an Integer, a Float or a Symbol, it raises a TypeError.
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

/*! \private */
MJIT_FUNC_EXPORTED void
rb_obj_copy_ivar(VALUE dest, VALUE obj)
{
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
	uint32_t len = ROBJECT(obj)->as.heap.numiv;
	VALUE *ptr = 0;
	if (len > 0) {
	    ptr = ALLOC_N(VALUE, len);
	    MEMCPY(ptr, ROBJECT(obj)->as.heap.ivptr, VALUE, len);
	}
	ROBJECT(dest)->as.heap.ivptr = ptr;
	ROBJECT(dest)->as.heap.numiv = len;
	ROBJECT(dest)->as.heap.iv_index_tbl = ROBJECT(obj)->as.heap.iv_index_tbl;
	RBASIC(dest)->flags &= ~ROBJECT_EMBED;
    }
}

static void
init_copy(VALUE dest, VALUE obj)
{
    if (OBJ_FROZEN(dest)) {
        rb_raise(rb_eTypeError, "[bug] frozen object (%s) allocated", rb_obj_classname(dest));
    }
    RBASIC(dest)->flags &= ~(T_MASK|FL_EXIVAR);
    RBASIC(dest)->flags |= RBASIC(obj)->flags & (T_MASK|FL_EXIVAR|FL_TAINT);
    rb_copy_wb_protected_attribute(dest, obj);
    rb_copy_generic_ivar(dest, obj);
    rb_gc_copy_finalizer(dest, obj);
    if (RB_TYPE_P(obj, T_OBJECT)) {
	rb_obj_copy_ivar(dest, obj);
    }
}

static int freeze_opt(int argc, VALUE *argv);
static VALUE immutable_obj_clone(VALUE obj, int kwfreeze);
static VALUE mutable_obj_clone(VALUE obj, int kwfreeze);
PUREFUNC(static inline int special_object_p(VALUE obj)); /*!< \private */
static inline int
special_object_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) return TRUE;
    switch (BUILTIN_TYPE(obj)) {
      case T_BIGNUM:
      case T_FLOAT:
      case T_SYMBOL:
      case T_RATIONAL:
      case T_COMPLEX:
	/* not a comprehensive list */
	return TRUE;
      default:
	return FALSE;
    }
}

/*
 *  call-seq:
 *     obj.clone(freeze: true) -> an_object
 *
 *  Produces a shallow copy of <i>obj</i>---the instance variables of
 *  <i>obj</i> are copied, but not the objects they reference.
 *  #clone copies the frozen (unless +:freeze+ keyword argument is
 *  given with a false value) and tainted state of <i>obj</i>.  See
 *  also the discussion under Object#dup.
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

static VALUE
rb_obj_clone2(int argc, VALUE *argv, VALUE obj)
{
    int kwfreeze = freeze_opt(argc, argv);
    if (!special_object_p(obj))
	return mutable_obj_clone(obj, kwfreeze);
    return immutable_obj_clone(obj, kwfreeze);
}

/*! \private */
VALUE
rb_immutable_obj_clone(int argc, VALUE *argv, VALUE obj)
{
    int kwfreeze = freeze_opt(argc, argv);
    return immutable_obj_clone(obj, kwfreeze);
}

static int
freeze_opt(int argc, VALUE *argv)
{
    static ID keyword_ids[1];
    VALUE opt;
    VALUE kwfreeze;

    if (!keyword_ids[0]) {
	CONST_ID(keyword_ids[0], "freeze");
    }
    rb_scan_args(argc, argv, "0:", &opt);
    if (!NIL_P(opt)) {
	rb_get_kwargs(opt, keyword_ids, 0, 1, &kwfreeze);
	if (kwfreeze == Qfalse) return FALSE;
	if (kwfreeze != Qundef && kwfreeze != Qtrue) {
	    rb_raise(rb_eArgError, "unexpected value for freeze: %"PRIsVALUE,
		     rb_obj_class(kwfreeze));
	}
    }
    return TRUE;
}

static VALUE
immutable_obj_clone(VALUE obj, int kwfreeze)
{
    if (!kwfreeze)
	rb_raise(rb_eArgError, "can't unfreeze %"PRIsVALUE,
		 rb_obj_class(obj));
    return obj;
}

static VALUE
mutable_obj_clone(VALUE obj, int kwfreeze)
{
    VALUE clone, singleton;

    clone = rb_obj_alloc(rb_obj_class(obj));

    singleton = rb_singleton_class_clone_and_attach(obj, clone);
    RBASIC_SET_CLASS(clone, singleton);
    if (FL_TEST(singleton, FL_SINGLETON)) {
	rb_singleton_class_attached(singleton, clone);
    }

    init_copy(clone, obj);
    rb_funcall(clone, id_init_clone, 1, obj);

    if (kwfreeze) {
	RBASIC(clone)->flags |= RBASIC(obj)->flags & FL_FREEZE;
    }

    return clone;
}

/**
 * :nodoc
 *--
 * Almost same as \c Object#clone
 *++
 */
VALUE
rb_obj_clone(VALUE obj)
{
    if (special_object_p(obj)) return obj;
    return mutable_obj_clone(obj, Qtrue);
}

/**
 *  call-seq:
 *     obj.dup -> an_object
 *
 *  Produces a shallow copy of <i>obj</i>---the instance variables of
 *  <i>obj</i> are copied, but not the objects they reference.
 *  #dup copies the tainted state of <i>obj</i>.
 *
 *  This method may have class-specific behavior.  If so, that
 *  behavior will be documented under the #+initialize_copy+ method of
 *  the class.
 *
 *  === on dup vs clone
 *
 *  In general, #clone and #dup may have different semantics in
 *  descendant classes. While #clone is used to duplicate an object,
 *  including its internal state, #dup typically uses the class of the
 *  descendant object to create the new instance.
 *
 *  When using #dup, any modules that the object has been extended with will not
 *  be copied.
 *
 *	class Klass
 *	  attr_accessor :str
 *	end
 *
 *	module Foo
 *	  def foo; 'foo'; end
 *	end
 *
 *	s1 = Klass.new #=> #<Klass:0x401b3a38>
 *	s1.extend(Foo) #=> #<Klass:0x401b3a38>
 *	s1.foo #=> "foo"
 *
 *	s2 = s1.clone #=> #<Klass:0x401b3a38>
 *	s2.foo #=> "foo"
 *
 *	s3 = s1.dup #=> #<Klass:0x401b3a38>
 *	s3.foo #=> NoMethodError: undefined method `foo' for #<Klass:0x401b3a38>
 *--
 * Equivalent to \c Object\#dup in Ruby
 *++
 */
VALUE
rb_obj_dup(VALUE obj)
{
    VALUE dup;

    if (special_object_p(obj)) {
	return obj;
    }
    dup = rb_obj_alloc(rb_obj_class(obj));
    init_copy(dup, obj);
    rb_funcall(dup, id_init_dup, 1, obj);

    return dup;
}

/*
 *  call-seq:
 *     obj.itself    -> obj
 *
 *  Returns the receiver.
 *
 *     string = "my string"
 *     string.itself.object_id == string.object_id   #=> true
 *
 */

static VALUE
rb_obj_itself(VALUE obj)
{
    return obj;
}

static VALUE
rb_obj_size(VALUE self, VALUE args, VALUE obj)
{
    return LONG2FIX(1);
}

/*
 *  call-seq:
 *     obj.then {|x| block }          -> an_object
 *     obj.yield_self {|x| block }    -> an_object
 *
 *  Yields self to the block and returns the result of the block.
 *
 *     3.next.then {|x| x**x }.to_s             #=> "256"
 *     "my string".yield_self {|s| s.upcase }   #=> "MY STRING"
 *
 *  Good usage for +yield_self+ is value piping in method chains:
 *
 *     require 'open-uri'
 *     require 'json'
 *
 *     construct_url(arguments).
 *       yield_self {|url| open(url).read }.
 *       yield_self {|response| JSON.parse(response) }
 *
 *  When called without block, the method returns +Enumerator+,
 *  which can be used, for example, for conditional
 *  circuit-breaking:
 *
 *     # meets condition, no-op
 *     1.yield_self.detect(&:odd?)            # => 1
 *     # does not meet condition, drop value
 *     2.yield_self.detect(&:odd?)            # => nil
 *
 */

static VALUE
rb_obj_yield_self(VALUE obj)
{
    RETURN_SIZED_ENUMERATOR(obj, 0, 0, rb_obj_size);
    return rb_yield_values2(1, &obj);
}

/**
 * :nodoc:
 *--
 * Default implementation of \c #initialize_copy
 * \param[in,out] obj the receiver being initialized
 * \param[in] orig    the object to be copied from.
 *++
 */
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

/*!
 * :nodoc:
 *--
 * Default implementation of \c #initialize_dup and \c #initialize_clone
 *
 * \param[in,out] obj the receiver being initialized
 * \param[in] orig    the object to be dup or cloned from.
 *++
 **/
VALUE
rb_obj_init_dup_clone(VALUE obj, VALUE orig)
{
    rb_funcall(obj, id_init_copy, 1, orig);
    return obj;
}

/**
 *  call-seq:
 *     obj.to_s    -> string
 *
 *  Returns a string representing <i>obj</i>. The default #to_s prints
 *  the object's class and an encoding of the object id. As a special
 *  case, the top-level object that is the initial execution context
 *  of Ruby programs returns ``main''.
 *
 *--
 * Default implementation of \c #to_s.
 *++
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

VALUE rb_str_escape(VALUE str);
/*!
 * Convenient wrapper of \c Object#inspect.
 * Returns a human-readable string representation of \a obj,
 * similarly to \c Object#inspect.
 *
 * Unlike Ruby-level \c #inspect, it escapes characters to keep the
 * result compatible to the default internal or external encoding.
 * If the default internal or external encoding is ASCII compatible,
 * the encoding of the inspected result must be compatible with it.
 * If the default internal or external encoding is ASCII incompatible,
 * the result must be ASCII only.
 */
VALUE
rb_inspect(VALUE obj)
{
    VALUE str = rb_obj_as_string(rb_funcallv(obj, id_inspect, 0, 0));

    rb_encoding *enc = rb_default_internal_encoding();
    if (enc == NULL) enc = rb_default_external_encoding();
    if (!rb_enc_asciicompat(enc)) {
	if (!rb_enc_str_asciionly_p(str))
	    return rb_str_escape(str);
	return str;
    }
    if (rb_enc_get(str) != enc && !rb_enc_str_asciionly_p(str))
	return rb_str_escape(str);
    return str;
}

static int
inspect_i(st_data_t k, st_data_t v, st_data_t a)
{
    ID id = (ID)k;
    VALUE value = (VALUE)v;
    VALUE str = (VALUE)a;

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
    rb_str_catf(str, "%"PRIsVALUE"=%+"PRIsVALUE,
		rb_id2str(id), value);

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
 * The default #inspect shows the object's class name, an encoding of
 * the object id, and a list of the instance variables and their
 * values (by calling #inspect on each of them).  User defined classes
 * should override this method to provide a better representation of
 * <i>obj</i>.  When overriding this method, it should return a string
 * whose encoding is compatible with the default external encoding.
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

static VALUE class_search_ancestor(VALUE cl, VALUE c);

/**
 *  call-seq:
 *     obj.instance_of?(class)    -> true or false
 *
 *  Returns <code>true</code> if <i>obj</i> is an instance of the given
 *  class. See also Object#kind_of?.
 *
 *     class A;     end
 *     class B < A; end
 *     class C < B; end
 *
 *     b = B.new
 *     b.instance_of? A   #=> false
 *     b.instance_of? B   #=> true
 *     b.instance_of? C   #=> false
 *--
 * Determines if \a obj is an instance of \a c.
 *
 * Equivalent to \c Object\#is_instance_of in Ruby.
 * \param[in] obj the object to be determined.
 * \param[in] c a Class object
 *++
 */

VALUE
rb_obj_is_instance_of(VALUE obj, VALUE c)
{
    c = class_or_module_required(c);
    if (rb_obj_class(obj) == c) return Qtrue;
    return Qfalse;
}


/**
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
 *--
 * Determines if \a obj is a kind of \a c.
 *
 * Equivalent to \c Object\#kind_of? in Ruby.
 * \param[in] obj the object to be determined
 * \param[in] c a Module object.
 *++
 */

VALUE
rb_obj_is_kind_of(VALUE obj, VALUE c)
{
    VALUE cl = CLASS_OF(obj);

    c = class_or_module_required(c);
    return class_search_ancestor(cl, RCLASS_ORIGIN(c)) ? Qtrue : Qfalse;
}

static VALUE
class_search_ancestor(VALUE cl, VALUE c)
{
    while (cl) {
	if (cl == c || RCLASS_M_TBL(cl) == RCLASS_M_TBL(c))
	    return cl;
	cl = RCLASS_SUPER(cl);
    }
    return 0;
}

/*! \private */
VALUE
rb_class_search_ancestor(VALUE cl, VALUE c)
{
    cl = class_or_module_required(cl);
    c = class_or_module_required(c);
    return class_search_ancestor(cl, RCLASS_ORIGIN(c));
}

/**
 *  call-seq:
 *     obj.tap {|x| block }    -> obj
 *
 *  Yields self to the block, and then returns self.
 *  The primary purpose of this method is to "tap into" a method chain,
 *  in order to perform operations on intermediate results within the chain.
 *
 *     (1..10)                  .tap {|x| puts "original: #{x}" }
 *       .to_a                  .tap {|x| puts "array:    #{x}" }
 *       .select {|x| x.even? } .tap {|x| puts "evens:    #{x}" }
 *       .map {|x| x*x }        .tap {|x| puts "squares:  #{x}" }
 *
 *--
 * \private
 *++
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
 * <em>produces:</em>
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
 * <em>produces:</em>
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
 * <em>produces:</em>
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

/**
 *  call-seq:
 *     obj.tainted?    -> true or false
 *
 *  Returns true if the object is tainted.
 *
 *  See #taint for more information.
 *--
 * Determines if \a obj is tainted. Equivalent to \c Object\#tainted? in Ruby.
 * \param[in] obj  the object to be determined
 * \retval Qtrue if the object is tainted
 * \retval Qfalse if the object is not tainted
 * \sa rb_obj_taint
 * \sa rb_obj_untaint
 *++
 */

VALUE
rb_obj_tainted(VALUE obj)
{
    if (OBJ_TAINTED(obj))
	return Qtrue;
    return Qfalse;
}

/**
 *  call-seq:
 *     obj.taint -> obj
 *
 *  Mark the object as tainted.
 *
 *  Objects that are marked as tainted will be restricted from various built-in
 *  methods. This is to prevent insecure data, such as command-line arguments
 *  or strings read from Kernel#gets, from inadvertently compromising the user's
 *  system.
 *
 *  To check whether an object is tainted, use #tainted?.
 *
 *  You should only untaint a tainted object if your code has inspected it and
 *  determined that it is safe. To do so use #untaint.
 *--
 * Marks the object as tainted. Equivalent to \c Object\#taint in Ruby
 * \param[in] obj  the object to be tainted
 * \return the object itself
 * \sa rb_obj_untaint
 * \sa rb_obj_tainted
 *++
 */

VALUE
rb_obj_taint(VALUE obj)
{
    if (!OBJ_TAINTED(obj) && OBJ_TAINTABLE(obj)) {
	rb_check_frozen(obj);
	OBJ_TAINT(obj);
    }
    return obj;
}


/**
 *  call-seq:
 *     obj.untaint    -> obj
 *
 *  Removes the tainted mark from the object.
 *
 *  See #taint for more information.
 *--
 * Removes the tainted mark from the object.
 * Equivalent to \c Object\#untaint in Ruby.
 *
 * \param[in] obj  the object to be tainted
 * \return the object itself
 * \sa rb_obj_taint
 * \sa rb_obj_tainted
 *++
 */

VALUE
rb_obj_untaint(VALUE obj)
{
    if (OBJ_TAINTED(obj)) {
	rb_check_frozen(obj);
	FL_UNSET(obj, FL_TAINT);
    }
    return obj;
}

/**
 *  call-seq:
 *     obj.untrusted?    -> true or false
 *
 *  Deprecated method that is equivalent to #tainted?.
 *--
 * \deprecated Use rb_obj_tainted.
 *
 * Trustiness used to have independent semantics from taintedness.
 * But now trustiness of objects is obsolete and this function behaves
 * the same as rb_obj_tainted.
 *
 * \sa rb_obj_tainted
 *++
 */

VALUE
rb_obj_untrusted(VALUE obj)
{
    rb_warning("untrusted? is deprecated and its behavior is same as tainted?");
    return rb_obj_tainted(obj);
}

/**
 *  call-seq:
 *     obj.untrust -> obj
 *
 *  Deprecated method that is equivalent to #taint.
 *--
 * \deprecated Use rb_obj_taint(obj)
 *
 * Trustiness used to have independent semantics from taintedness.
 * But now trustiness of objects is obsolete and this function behaves
 * the same as rb_obj_taint.
 *
 * \sa rb_obj_taint
 *++
 */

VALUE
rb_obj_untrust(VALUE obj)
{
    rb_warning("untrust is deprecated and its behavior is same as taint");
    return rb_obj_taint(obj);
}


/**
 *  call-seq:
 *     obj.trust    -> obj
 *
 *  Deprecated method that is equivalent to #untaint.
 *--
 * \deprecated Use rb_obj_untaint(obj)
 *
 * Trustiness used to have independent semantics from taintedness.
 * But now trustiness of objects is obsolete and this function behaves
 * the same as rb_obj_untaint.
 *
 * \sa rb_obj_untaint
 *++
 */

VALUE
rb_obj_trust(VALUE obj)
{
    rb_warning("trust is deprecated and its behavior is same as untaint");
    return rb_obj_untaint(obj);
}

/**
 * Convenient function to infect \a victim with the taintedness of \a carrier.
 *
 * It just keeps the taintedness of \a victim if \a carrier is not tainted.
 * \param[in,out] victim the object being infected with the taintness of \a carrier
 * \param[in] carrier a possibly tainted object
 */

void
rb_obj_infect(VALUE victim, VALUE carrier)
{
    OBJ_INFECT(victim, carrier);
}

/**
 *  call-seq:
 *     obj.freeze    -> obj
 *
 *  Prevents further modifications to <i>obj</i>. A
 *  RuntimeError will be raised if modification is attempted.
 *  There is no way to unfreeze a frozen object. See also
 *  Object#frozen?.
 *
 *  This method returns self.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze
 *     a << "z"
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3:in `<<': can't modify frozen Array (FrozenError)
 *     	from prog.rb:3
 *
 *  Objects of the following classes are always frozen: Integer,
 *  Float, Symbol.
 *--
 * Make the object unmodifiable. Equivalent to \c Object\#freeze in Ruby.
 * \param[in,out] obj  the object to be frozen
 * \return the frozen object
 *++
 */

VALUE
rb_obj_freeze(VALUE obj)
{
    if (!OBJ_FROZEN(obj)) {
	OBJ_FREEZE(obj);
	if (SPECIAL_CONST_P(obj)) {
	    rb_bug("special consts should be frozen.");
	}
    }
    return obj;
}

/**
 *  call-seq:
 *     obj.frozen?    -> true or false
 *
 *  Returns the freeze status of <i>obj</i>.
 *
 *     a = [ "a", "b", "c" ]
 *     a.freeze    #=> ["a", "b", "c"]
 *     a.frozen?   #=> true
 *--
 * Determines if the object is frozen. Equivalent to \c Object\#frozen? in Ruby.
 * \param[in] obj  the object to be determines
 * \retval Qtrue if frozen
 * \retval Qfalse if not frozen
 *++
 */

VALUE
rb_obj_frozen_p(VALUE obj)
{
    return OBJ_FROZEN(obj) ? Qtrue : Qfalse;
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

/*
 *  call-seq:
 *     nil =~ other  -> nil
 *
 *  Dummy pattern matching -- always returns nil.
 */

static VALUE
nil_match(VALUE obj1, VALUE obj2)
{
    return Qnil;
}

/***********************************************************************
 *  Document-class: TrueClass
 *
 *  The global value <code>true</code> is the only instance of class
 *  TrueClass and represents a logically true value in
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
 *  Or---Returns <code>true</code>. As <i>obj</i> is an argument to
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
 *  FalseClass and represents a logically false value in
 *  boolean expressions. The class provides operators allowing
 *  <code>false</code> to participate correctly in logical expressions.
 *
 */

/*
 * call-seq:
 *   false.to_s   ->  "false"
 *
 * The string representation of <code>false</code> is "false".
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
 *   obj.nil?               -> true or false
 *
 * Only the object <i>nil</i> responds <code>true</code> to <code>nil?</code>.
 *
 *    Object.new.nil?   #=> false
 *    nil.nil?          #=> true
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
 * This method is deprecated.
 *
 * This is not only unuseful but also troublesome because it
 * may hide a type error.
 */

static VALUE
rb_obj_match(VALUE obj1, VALUE obj2)
{
    rb_warn("deprecated Object#=~ is called on %"PRIsVALUE
            "; it always returns nil", rb_obj_class(obj1));
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
 *  The #<=> is used by various methods to compare objects, for example
 *  Enumerable#sort, Enumerable#max etc.
 *
 *  Your implementation of #<=> should return one of the following values: -1, 0,
 *  1 or nil. -1 means self is smaller than other. 0 means self is equal to other.
 *  1 means self is bigger than other. Nil means the two values could not be
 *  compared.
 *
 *  When you define #<=>, you can include Comparable to gain the
 *  methods #<=, #<, #==, #>=, #> and #between?.
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
 *  A Module is a collection of methods and constants. The
 *  methods in a module may be instance methods or module methods.
 *  Instance methods appear as methods in a class when the module is
 *  included, module methods do not. Conversely, module methods may be
 *  called without creating an encapsulating object, while instance
 *  methods may not. (See Module#module_function.)
 *
 *  In the descriptions that follow, the parameter <i>sym</i> refers
 *  to a symbol, which is either a quoted string or a
 *  Symbol (such as <code>:name</code>).
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
 * Returns a string representing this module or class. For basic
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
 *  Case Equality---Returns <code>true</code> if <i>obj</i> is an
 *  instance of <i>mod</i> or an instance of one of <i>mod</i>'s descendants.
 *  Of limited use for modules, but can be used in <code>case</code> statements
 *  to classify objects by class.
 */

static VALUE
rb_mod_eqq(VALUE mod, VALUE arg)
{
    return rb_obj_is_kind_of(arg, mod);
}

/**
 * call-seq:
 *   mod <= other   ->  true, false, or nil
 *
 * Returns true if <i>mod</i> is a subclass of <i>other</i> or
 * is the same as <i>other</i>. Returns
 * <code>nil</code> if there's no relationship between the two.
 * (Think of the relationship in terms of the class definition:
 * "class A < B" implies "A < B".)
 *--
 * Determines if \a mod inherits \a arg. Equivalent to \c Module\#<= in Ruby
 *
 * \param[in] mod a Module object
 * \param[in] arg another Module object or an iclass of a module
 * \retval Qtrue if \a mod inherits \a arg, or \a mod equals \a arg
 * \retval Qfalse if \a arg inherits \a mod
 * \retval Qnil if otherwise
 *++
 */

VALUE
rb_class_inherited_p(VALUE mod, VALUE arg)
{
    if (mod == arg) return Qtrue;
    if (!CLASS_OR_MODULE_P(arg) && !RB_TYPE_P(arg, T_ICLASS)) {
	rb_raise(rb_eTypeError, "compared with non class/module");
    }
    if (class_search_ancestor(mod, RCLASS_ORIGIN(arg))) {
	return Qtrue;
    }
    /* not mod < arg; check if mod > arg */
    if (class_search_ancestor(arg, mod)) {
	return Qfalse;
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
 * "class A < B" implies "A < B".)
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
 * "class A < B" implies "B > A".)
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
 * "class A < B" implies "B > A".)
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
 *  +other_module+.
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
 *  module like #module_eval.
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

/* :nodoc: */
static VALUE
rb_mod_initialize_clone(VALUE clone, VALUE orig)
{
    VALUE ret;
    ret = rb_obj_init_dup_clone(clone, orig);
    if (OBJ_FROZEN(orig))
        rb_class_name(clone);
    return ret;
}

/*
 *  call-seq:
 *     Class.new(super_class=Object)               -> a_class
 *     Class.new(super_class=Object) { |mod| ... } -> a_class
 *
 *  Creates a new anonymous (unnamed) class with the given superclass
 *  (or Object if no parameter is given). You can give a
 *  class a name by assigning the class object to a constant.
 *
 *  If a block is given, it is passed the class object, and the block
 *  is evaluated in the context of this class like
 *  #class_eval.
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
    if (rb_check_arity(argc, 0, 1) == 0) {
	super = rb_cObject;
    }
    else {
        super = argv[0];
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

/*! \private */
void
rb_undefined_alloc(VALUE klass)
{
    rb_raise(rb_eTypeError, "allocator undefined for %"PRIsVALUE,
	     klass);
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

static VALUE
rb_class_alloc(VALUE klass)
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
	rb_undefined_alloc(klass);
    }

    RUBY_DTRACE_CREATE_HOOK(OBJECT, rb_class2name(klass));

    obj = (*allocator)(klass);

    if (rb_obj_class(obj) != rb_class_real(klass)) {
	rb_raise(rb_eTypeError, "wrong instance allocation");
    }
    return obj;
}

/**
 * Allocates an instance of \a klass
 *
 * \note It calls the allocator defined by {rb_define_alloc_func}.
 *   So you cannot use this function to define an allocator.
 *   Use {rb_newobj_of}, {TypedData_Make_Struct} or others, instead.
 * \note Usually prefer rb_class_new_instance to rb_obj_alloc and rb_obj_call_init
 * \param[in] klass a Class object
 * \sa rb_class_new_instance
 * \sa rb_obj_call_init
 * \sa rb_define_alloc_func
 * \sa rb_newobj_of
 * \sa TypedData_Make_Struct
 */
VALUE
rb_obj_alloc(VALUE klass)
{
    Check_Type(klass, T_CLASS);
    return rb_class_alloc(klass);
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
 *  Calls #allocate to create a new object of <i>class</i>'s class,
 *  then invokes that object's #initialize method, passing it
 *  <i>args</i>.  This is the method that ends up getting called
 *  whenever an object is constructed using <code>.new</code>.
 *
 */

static VALUE
rb_class_s_new(int argc, const VALUE *argv, VALUE klass)
{
    VALUE obj;

    obj = rb_class_alloc(klass);
    rb_obj_call_init(obj, argc, argv);

    return obj;
}

/**
 * Allocates and initializes an instance of \a klass.
 *
 * Equivalent to \c Class\#new in Ruby
 *
 * \param[in] argc  the number of arguments to \c #initialize
 * \param[in] argv  a pointer to an array of arguments to \c #initialize
 * \param[in] klass a Class object
 * \return the new instance of \a klass
 * \sa rb_obj_call_init
 * \sa rb_obj_alloc
 */
VALUE
rb_class_new_instance(int argc, const VALUE *argv, VALUE klass)
{
    Check_Type(klass, T_CLASS);
    return rb_class_s_new(argc, argv, klass);
}

/**
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
 *  Returns nil when the given class does not have a parent class:
 *
 *     BasicObject.superclass   #=> nil
 *
 *--
 * Returns the superclass of \a klass. Equivalent to \c Class\#superclass in Ruby.
 *
 * It skips modules.
 * \param[in] klass a Class object
 * \return the superclass, or \c Qnil if \a klass does not have a parent class.
 * \sa rb_class_get_superclass
 *++
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

/**
 * Returns the superclass of \a klass
 * The return value might be an iclass of a module, unlike rb_class_superclass.
 *
 * Also it returns Qfalse when \a klass does not have a parent class.
 * \sa rb_class_superclass
 */
VALUE
rb_class_get_superclass(VALUE klass)
{
    return RCLASS(klass)->super;
}

/*! \private */
#define id_for_var(obj, name, part, type) \
    id_for_setter(obj, name, type, "`%1$s' is not allowed as "#part" "#type" variable name")
/*! \private */
#define id_for_setter(obj, name, type, message) \
    check_setter_id(obj, &(name), rb_is_##type##_id, rb_is_##type##_name, message, strlen(message))
static ID
check_setter_id(VALUE obj, VALUE *pname,
		int (*valid_id_p)(ID), int (*valid_name_p)(VALUE),
		const char *message, size_t message_len)
{
    ID id = rb_check_id(pname);
    VALUE name = *pname;

    if (id ? !valid_id_p(id) : !valid_name_p(name)) {
	rb_name_err_raise_str(rb_fstring_new(message, message_len),
			      obj, name);
    }
    return id;
}

static int
rb_is_attr_name(VALUE name)
{
    return rb_is_local_name(name) || rb_is_const_name(name);
}

static int
rb_is_attr_id(ID id)
{
    return rb_is_local_id(id) || rb_is_const_id(id);
}

static const char wrong_constant_name[] = "wrong constant name %1$s";
static const char invalid_attribute_name[] = "invalid attribute name `%1$s'";

static ID
id_for_attr(VALUE obj, VALUE name)
{
    ID id = id_for_setter(obj, name, attr, invalid_attribute_name);
    if (!id) id = rb_intern_str(name);
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
	rb_attr(klass, id_for_attr(klass, argv[i]), TRUE, FALSE, TRUE);
    }
    return Qnil;
}

/**
 *  call-seq:
 *    attr(name, ...) -> nil
 *    attr(name, true) -> nil
 *    attr(name, false) -> nil
 *
 *  The first form is equivalent to #attr_reader.
 *  The second form is equivalent to <code>attr_accessor(name)</code> but deprecated.
 *  The last form is equivalent to <code>attr_reader(name)</code> but deprecated.
 *--
 * \private
 * \todo can be static?
 *++
 */
VALUE
rb_mod_attr(int argc, VALUE *argv, VALUE klass)
{
    if (argc == 2 && (argv[1] == Qtrue || argv[1] == Qfalse)) {
	rb_warning("optional boolean argument is obsoleted");
	rb_attr(klass, id_for_attr(klass, argv[0]), 1, RTEST(argv[1]), TRUE);
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
	rb_attr(klass, id_for_attr(klass, argv[i]), FALSE, TRUE, TRUE);
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
	rb_attr(klass, id_for_attr(klass, argv[i]), TRUE, TRUE, TRUE);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     mod.const_get(sym, inherit=true)    -> obj
 *     mod.const_get(str, inherit=true)    -> obj
 *
 *  Checks for a constant with the given name in <i>mod</i>.
 *  If +inherit+ is set, the lookup will also search
 *  the ancestors (and +Object+ if <i>mod</i> is a +Module+).
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
 *  If the argument is not a valid constant name a +NameError+ will be
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

    rb_check_arity(argc, 1, 2);
    name = argv[0];
    recur = (argc == 1) ? Qtrue : argv[1];

    if (SYMBOL_P(name)) {
	if (!rb_is_const_sym(name)) goto wrong_name;
	id = rb_check_id(&name);
	if (!id) return rb_const_missing(mod, name);
	return RTEST(recur) ? rb_const_get(mod, id) : rb_const_get_at(mod, id);
    }

    path = StringValuePtr(name);
    enc = rb_enc_get(name);

    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "invalid class path encoding (non ASCII)");
    }

    pbeg = p = path;
    pend = path + RSTRING_LEN(name);

    if (p >= pend || !*p) {
      wrong_name:
	rb_name_err_raise(wrong_constant_name, mod, name);
    }

    if (p + 2 < pend && p[0] == ':' && p[1] == ':') {
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
	    if (p + 2 >= pend || p[1] != ':') goto wrong_name;
	    p += 2;
	    pbeg = p;
	}

	if (!RB_TYPE_P(mod, T_MODULE) && !RB_TYPE_P(mod, T_CLASS)) {
	    rb_raise(rb_eTypeError, "%"PRIsVALUE" does not refer to class/module",
		     QUOTE(name));
	}

	if (!id) {
	    part = rb_str_subseq(name, beglen, len);
	    OBJ_FREEZE(part);
	    if (!rb_is_const_name(part)) {
		name = part;
		goto wrong_name;
	    }
	    else if (!rb_method_basic_definition_p(CLASS_OF(mod), id_const_missing)) {
		part = rb_str_intern(part);
		mod = rb_const_missing(mod, part);
		continue;
	    }
	    else {
		rb_mod_const_missing(mod, part);
	    }
	}
	if (!rb_is_const_id(id)) {
	    name = ID2SYM(id);
	    goto wrong_name;
	}
#if 0
        mod = rb_const_get_0(mod, id, beglen > 0 || !RTEST(recur), RTEST(recur), FALSE);
#else
        if (!RTEST(recur)) {
            mod = rb_const_get_at(mod, id);
        }
        else if (beglen == 0) {
            mod = rb_const_get(mod, id);
        }
        else {
            mod = rb_const_get_from(mod, id);
        }
#endif
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
 *  If +sym+ or +str+ is not a valid constant name a +NameError+ will be
 *  raised with a warning "wrong constant name".
 *
 *	Object.const_set('foobar', 42) #=> NameError: wrong constant name foobar
 *
 */

static VALUE
rb_mod_const_set(VALUE mod, VALUE name, VALUE value)
{
    ID id = id_for_setter(mod, name, const, wrong_constant_name);
    if (!id) id = rb_intern_str(name);
    rb_const_set(mod, id, value);

    return value;
}

/*
 *  call-seq:
 *     mod.const_defined?(sym, inherit=true)   -> true or false
 *     mod.const_defined?(str, inherit=true)   -> true or false
 *
 *  Says whether _mod_ or its ancestors have a constant with the given name:
 *
 *    Float.const_defined?(:EPSILON)      #=> true, found in Float itself
 *    Float.const_defined?("String")      #=> true, found in Object (ancestor)
 *    BasicObject.const_defined?(:Hash)   #=> false
 *
 *  If _mod_ is a +Module+, additionally +Object+ and its ancestors are checked:
 *
 *    Math.const_defined?(:String)   #=> true, found in Object
 *
 *  In each of the checked classes or modules, if the constant is not present
 *  but there is an autoload for it, +true+ is returned directly without
 *  autoloading:
 *
 *    module Admin
 *      autoload :User, 'admin/user'
 *    end
 *    Admin.const_defined?(:User)   #=> true
 *
 *  If the constant is not found the callback +const_missing+ is *not* called
 *  and the method returns +false+.
 *
 *  If +inherit+ is false, the lookup only checks the constants in the receiver:
 *
 *    IO.const_defined?(:SYNC)          #=> true, found in File::Constants (ancestor)
 *    IO.const_defined?(:SYNC, false)   #=> false, not found in IO itself
 *
 *  In this case, the same logic for autoloading applies.
 *
 *  If the argument is not a valid constant name a +NameError+ is raised with the
 *  message "wrong constant name _name_":
 *
 *    Hash.const_defined? 'foobar'   #=> NameError: wrong constant name foobar
 *
 */

static VALUE
rb_mod_const_defined(int argc, VALUE *argv, VALUE mod)
{
    VALUE name, recur;
    rb_encoding *enc;
    const char *pbeg, *p, *path, *pend;
    ID id;

    rb_check_arity(argc, 1, 2);
    name = argv[0];
    recur = (argc == 1) ? Qtrue : argv[1];

    if (SYMBOL_P(name)) {
	if (!rb_is_const_sym(name)) goto wrong_name;
	id = rb_check_id(&name);
	if (!id) return Qfalse;
	return RTEST(recur) ? rb_const_defined(mod, id) : rb_const_defined_at(mod, id);
    }

    path = StringValuePtr(name);
    enc = rb_enc_get(name);

    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "invalid class path encoding (non ASCII)");
    }

    pbeg = p = path;
    pend = path + RSTRING_LEN(name);

    if (p >= pend || !*p) {
      wrong_name:
	rb_name_err_raise(wrong_constant_name, mod, name);
    }

    if (p + 2 < pend && p[0] == ':' && p[1] == ':') {
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
	    if (p + 2 >= pend || p[1] != ':') goto wrong_name;
	    p += 2;
	    pbeg = p;
	}

	if (!id) {
	    part = rb_str_subseq(name, beglen, len);
	    OBJ_FREEZE(part);
	    if (!rb_is_const_name(part)) {
		name = part;
		goto wrong_name;
	    }
	    else {
		return Qfalse;
	    }
	}
	if (!rb_is_const_id(id)) {
	    name = ID2SYM(id);
	    goto wrong_name;
	}

#if 0
        mod = rb_const_search(mod, id, beglen > 0 || !RTEST(recur), RTEST(recur), FALSE);
        if (mod == Qundef) return Qfalse;
#else
        if (!RTEST(recur)) {
	    if (!rb_const_defined_at(mod, id))
		return Qfalse;
            if (p == pend) return Qtrue;
	    mod = rb_const_get_at(mod, id);
	}
        else if (beglen == 0) {
            if (!rb_const_defined(mod, id))
                return Qfalse;
            if (p == pend) return Qtrue;
            mod = rb_const_get(mod, id);
        }
        else {
            if (!rb_const_defined_from(mod, id))
                return Qfalse;
            if (p == pend) return Qtrue;
            mod = rb_const_get_from(mod, id);
        }
#endif

	if (p < pend && !RB_TYPE_P(mod, T_MODULE) && !RB_TYPE_P(mod, T_CLASS)) {
	    rb_raise(rb_eTypeError, "%"PRIsVALUE" does not refer to class/module",
		     QUOTE(name));
	}
    }

    return Qtrue;
}

/*
 *  call-seq:
 *     obj.instance_variable_get(symbol)    -> obj
 *     obj.instance_variable_get(string)    -> obj
 *
 *  Returns the value of the given instance variable, or nil if the
 *  instance variable is not set. The <code>@</code> part of the
 *  variable name should be included for regular instance
 *  variables. Throws a NameError exception if the
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
    ID id = id_for_var(obj, iv, an, instance);

    if (!id) {
	return Qnil;
    }
    return rb_ivar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.instance_variable_set(symbol, obj)    -> obj
 *     obj.instance_variable_set(string, obj)    -> obj
 *
 *  Sets the instance variable named by <i>symbol</i> to the given
 *  object, thereby frustrating the efforts of the class's
 *  author to attempt to provide proper encapsulation. The variable
 *  does not have to exist prior to this call.
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
    ID id = id_for_var(obj, iv, an, instance);
    if (!id) id = rb_intern_str(iv);
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
    ID id = id_for_var(obj, iv, an, instance);

    if (!id) {
	return Qfalse;
    }
    return rb_ivar_defined(obj, id);
}

/*
 *  call-seq:
 *     mod.class_variable_get(symbol)    -> obj
 *     mod.class_variable_get(string)    -> obj
 *
 *  Returns the value of the given class variable (or throws a
 *  NameError exception). The <code>@@</code> part of the
 *  variable name should be included for regular class variables.
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
    ID id = id_for_var(obj, iv, a, class);

    if (!id) {
	rb_name_err_raise("uninitialized class variable %1$s in %2$s",
			  obj, iv);
    }
    return rb_cvar_get(obj, id);
}

/*
 *  call-seq:
 *     obj.class_variable_set(symbol, obj)    -> obj
 *     obj.class_variable_set(string, obj)    -> obj
 *
 *  Sets the class variable named by <i>symbol</i> to the given
 *  object.
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
    ID id = id_for_var(obj, iv, a, class);
    if (!id) id = rb_intern_str(iv);
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
    ID id = id_for_var(obj, iv, a, class);

    if (!id) {
	return Qfalse;
    }
    return rb_cvar_defined(obj, id);
}

/*
 *  call-seq:
 *     mod.singleton_class?    -> true or false
 *
 *  Returns <code>true</code> if <i>mod</i> is a singleton class or
 *  <code>false</code> if it is an ordinary class or module.
 *
 *     class C
 *     end
 *     C.singleton_class?                  #=> false
 *     C.singleton_class.singleton_class?  #=> true
 */

static VALUE
rb_mod_singleton_p(VALUE klass)
{
    if (RB_TYPE_P(klass, T_CLASS) && FL_TEST(klass, FL_SINGLETON))
	return Qtrue;
    return Qfalse;
}

/*! \private */
static const struct conv_method_tbl {
    const char method[6];
    unsigned short id;
} conv_method_names[] = {
#define M(n) {#n, (unsigned short)idTo_##n}
    M(int),
    M(ary),
    M(str),
    M(sym),
    M(hash),
    M(proc),
    M(io),
    M(a),
    M(s),
    M(i),
    M(r),
#undef M
};
#define IMPLICIT_CONVERSIONS 7

static int
conv_method_index(const char *method)
{
    static const char prefix[] = "to_";

    if (strncmp(prefix, method, sizeof(prefix)-1) == 0) {
	const char *const meth = &method[sizeof(prefix)-1];
	int i;
	for (i=0; i < numberof(conv_method_names); i++) {
	    if (conv_method_names[i].method[0] == meth[0] &&
		strcmp(conv_method_names[i].method, meth) == 0) {
		return i;
	    }
	}
    }
    return numberof(conv_method_names);
}

static VALUE
convert_type_with_id(VALUE val, const char *tname, ID method, int raise, int index)
{
    VALUE r = rb_check_funcall(val, method, 0, 0);
    if (r == Qundef) {
	if (raise) {
	    const char *msg =
		((index < 0 ? conv_method_index(rb_id2name(method)) : index)
		 < IMPLICIT_CONVERSIONS) ?
		"no implicit conversion of" : "can't convert";
	    const char *cname = NIL_P(val) ? "nil" :
		val == Qtrue ? "true" :
		val == Qfalse ? "false" :
		NULL;
	    if (cname)
		rb_raise(rb_eTypeError, "%s %s into %s", msg, cname, tname);
	    rb_raise(rb_eTypeError, "%s %"PRIsVALUE" into %s", msg,
		     rb_obj_class(val),
		     tname);
	}
	return Qnil;
    }
    return r;
}

static VALUE
convert_type(VALUE val, const char *tname, const char *method, int raise)
{
    int i = conv_method_index(method);
    ID m = i < numberof(conv_method_names) ?
	conv_method_names[i].id : rb_intern(method);
    return convert_type_with_id(val, tname, m, raise, i);
}

/*! \private */
NORETURN(static void conversion_mismatch(VALUE, const char *, const char *, VALUE));
static void
conversion_mismatch(VALUE val, const char *tname, const char *method, VALUE result)
{
    VALUE cname = rb_obj_class(val);
    rb_raise(rb_eTypeError,
	     "can't convert %"PRIsVALUE" to %s (%"PRIsVALUE"#%s gives %"PRIsVALUE")",
	     cname, tname, cname, method, rb_obj_class(result));
}

/*!
 * Converts an object into another type.
 * Calls the specified conversion method if necessary.
 *
 * \param[in] val    the object to be converted
 * \param[in] type   a value of \c ruby_value_type
 * \param[in] tname  name of the target type.
 *   only used for error messages.
 * \param[in] method name of the method
 * \return an object of the specified type
 * \throw TypeError on failure
 * \sa rb_check_convert_type
 */
VALUE
rb_convert_type(VALUE val, int type, const char *tname, const char *method)
{
    VALUE v;

    if (TYPE(val) == type) return val;
    v = convert_type(val, tname, method, TRUE);
    if (TYPE(v) != type) {
	conversion_mismatch(val, tname, method, v);
    }
    return v;
}

/*! \private */
VALUE
rb_convert_type_with_id(VALUE val, int type, const char *tname, ID method)
{
    VALUE v;

    if (TYPE(val) == type) return val;
    v = convert_type_with_id(val, tname, method, TRUE, -1);
    if (TYPE(v) != type) {
	conversion_mismatch(val, tname, RSTRING_PTR(rb_id2str(method)), v);
    }
    return v;
}

/*!
 * Tries to convert an object into another type.
 * Calls the specified conversion method if necessary.
 *
 * \param[in] val    the object to be converted
 * \param[in] type   a value of \c ruby_value_type
 * \param[in] tname  name of the target type.
 *   only used for error messages.
 * \param[in] method name of the method
 * \return an object of the specified type, or Qnil if no such conversion method defined.
 * \throw TypeError if the conversion method returns an unexpected type of value.
 * \sa rb_convert_type
 * \sa rb_check_convert_type_with_id
 */
VALUE
rb_check_convert_type(VALUE val, int type, const char *tname, const char *method)
{
    VALUE v;

    /* always convert T_DATA */
    if (TYPE(val) == type && type != T_DATA) return val;
    v = convert_type(val, tname, method, FALSE);
    if (NIL_P(v)) return Qnil;
    if (TYPE(v) != type) {
	conversion_mismatch(val, tname, method, v);
    }
    return v;
}

/*! \private */
MJIT_FUNC_EXPORTED VALUE
rb_check_convert_type_with_id(VALUE val, int type, const char *tname, ID method)
{
    VALUE v;

    /* always convert T_DATA */
    if (TYPE(val) == type && type != T_DATA) return val;
    v = convert_type_with_id(val, tname, method, FALSE, -1);
    if (NIL_P(v)) return Qnil;
    if (TYPE(v) != type) {
	conversion_mismatch(val, tname, RSTRING_PTR(rb_id2str(method)), v);
    }
    return v;
}

#define try_to_int(val, mid, raise) \
    convert_type_with_id(val, "Integer", mid, raise, -1)

ALWAYS_INLINE(static VALUE rb_to_integer(VALUE val, const char *method, ID mid));
static inline VALUE
rb_to_integer(VALUE val, const char *method, ID mid)
{
    VALUE v;

    if (RB_INTEGER_TYPE_P(val)) return val;
    v = try_to_int(val, mid, TRUE);
    if (!RB_INTEGER_TYPE_P(v)) {
        conversion_mismatch(val, "Integer", method, v);
    }
    return v;
}

/**
 * Tries to convert \a val into \c Integer.
 * It calls the specified conversion method if necessary.
 *
 * \param[in] val     a Ruby object
 * \param[in] method  a name of a method
 * \return an \c Integer object on success,
 *   or \c Qnil if no such conversion method defined.
 * \exception TypeError if the conversion method returns a non-Integer object.
 */
VALUE
rb_check_to_integer(VALUE val, const char *method)
{
    VALUE v;

    if (FIXNUM_P(val)) return val;
    if (RB_TYPE_P(val, T_BIGNUM)) return val;
    v = convert_type(val, "Integer", method, FALSE);
    if (!RB_INTEGER_TYPE_P(v)) {
        return Qnil;
    }
    return v;
}

/**
 * Converts \a val into \c Integer.
 * It calls \a #to_int method if necessary.
 *
 * \param[in] val a Ruby object
 * \return an \c Integer object
 * \exception TypeError on failure
 */
VALUE
rb_to_int(VALUE val)
{
    return rb_to_integer(val, "to_int", idTo_int);
}

/**
 * Tries to convert \a val into Integer.
 * It calls \c #to_int method if necessary.
 *
 * \param[in] val a Ruby object
 * \return an Integer object on success,
 *   or \c Qnil if \c #to_int is not defined.
 * \exception TypeError if \c #to_int returns a non-Integer object.
 */
VALUE
rb_check_to_int(VALUE val)
{
    if (RB_INTEGER_TYPE_P(val)) return val;
    val = try_to_int(val, idTo_int, FALSE);
    if (RB_INTEGER_TYPE_P(val)) return val;
    return Qnil;
}

static VALUE
rb_check_to_i(VALUE val)
{
    if (RB_INTEGER_TYPE_P(val)) return val;
    val = try_to_int(val, idTo_i, FALSE);
    if (RB_INTEGER_TYPE_P(val)) return val;
    return Qnil;
}

static VALUE
rb_convert_to_integer(VALUE val, int base, int raise_exception)
{
    VALUE tmp;

    if (RB_FLOAT_TYPE_P(val)) {
        double f;
        if (base != 0) goto arg_error;
        f = RFLOAT_VALUE(val);
        if (!raise_exception && !isfinite(f)) return Qnil;
        if (FIXABLE(f)) return LONG2FIX((long)f);
        return rb_dbl2big(f);
    }
    else if (RB_INTEGER_TYPE_P(val)) {
        if (base != 0) goto arg_error;
        return val;
    }
    else if (RB_TYPE_P(val, T_STRING)) {
        return rb_str_convert_to_inum(val, base, TRUE, raise_exception);
    }
    else if (NIL_P(val)) {
        if (base != 0) goto arg_error;
        if (!raise_exception) return Qnil;
        rb_raise(rb_eTypeError, "can't convert nil into Integer");
    }
    if (base != 0) {
        tmp = rb_check_string_type(val);
        if (!NIL_P(tmp)) return rb_str_convert_to_inum(tmp, base, TRUE, raise_exception);
      arg_error:
        if (!raise_exception) return Qnil;
        rb_raise(rb_eArgError, "base specified for non string value");
    }

    tmp = rb_protect(rb_check_to_int, val, NULL);
    if (RB_INTEGER_TYPE_P(tmp)) return tmp;
    rb_set_errinfo(Qnil);

    if (!raise_exception) {
        VALUE result = rb_protect(rb_check_to_i, val, NULL);
        rb_set_errinfo(Qnil);
        return result;
    }

    return rb_to_integer(val, "to_i", idTo_i);
}

/**
 * Equivalent to \c Kernel\#Integer in Ruby.
 *
 * Converts \a val into \c Integer in a slightly more strict manner
 * than \c #to_i.
 */
VALUE
rb_Integer(VALUE val)
{
    return rb_convert_to_integer(val, 0, TRUE);
}

static int
opts_exception_p(VALUE opts)
{
    static ID kwds[1];
    VALUE exception;
    if (!kwds[0]) {
        kwds[0] = idException;
    }
    rb_get_kwargs(opts, kwds, 0, 1, &exception);
    return exception != Qfalse;
}

/*
 *  call-seq:
 *     Integer(arg, base=0, exception: true)    -> integer or nil
 *
 *  Converts <i>arg</i> to an Integer.
 *  Numeric types are converted directly (with floating point numbers
 *  being truncated).  <i>base</i> (0, or between 2 and 36) is a base for
 *  integer string representation.  If <i>arg</i> is a String,
 *  when <i>base</i> is omitted or equals zero, radix indicators
 *  (<code>0</code>, <code>0b</code>, and <code>0x</code>) are honored.
 *  In any case, strings should be strictly conformed to numeric
 *  representation. This behavior is different from that of
 *  String#to_i.  Non string values will be converted by first
 *  trying <code>to_int</code>, then <code>to_i</code>.
 *
 *  Passing <code>nil</code> raises a TypeError, while passing a String that
 *  does not conform with numeric representation raises an ArgumentError.
 *  This behavior can be altered by passing <code>exception: false</code>,
 *  in this case a not convertible value will return <code>nil</code>.
 *
 *     Integer(123.999)    #=> 123
 *     Integer("0x1a")     #=> 26
 *     Integer(Time.new)   #=> 1204973019
 *     Integer("0930", 10) #=> 930
 *     Integer("111", 2)   #=> 7
 *     Integer(nil)        #=> TypeError: can't convert nil into Integer
 *     Integer("x")        #=> ArgumentError: invalid value for Integer(): "x"
 *
 *     Integer("x", exception: false)        #=> nil
 *
 */

static VALUE
rb_f_integer(int argc, VALUE *argv, VALUE obj)
{
    VALUE arg = Qnil, opts = Qnil;
    int base = 0;

    if (argc > 1) {
        int narg = 1;
        VALUE vbase = rb_check_to_int(argv[1]);
        if (!NIL_P(vbase)) {
            base = NUM2INT(vbase);
            narg = 2;
        }
        if (argc > narg) {
            VALUE hash = rb_check_hash_type(argv[argc-1]);
            if (!NIL_P(hash)) {
                opts = rb_extract_keywords(&hash);
                if (!hash) --argc;
            }
        }
    }
    rb_check_arity(argc, 1, 2);
    arg = argv[0];

    return rb_convert_to_integer(arg, base, opts_exception_p(opts));
}

static double
rb_cstr_to_dbl_raise(const char *p, int badcheck, int raise, int *error)
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
            if (raise)
                rb_invalid_str(q, "Float()");
            else {
                if (error) *error = 1;
                return 0.0;
            }
        }
        return d;
    }
    if (*end) {
        char buf[DBL_DIG * 4 + 10];
        char *n = buf;
        char *const init_e = buf + DBL_DIG * 4;
        char *e = init_e;
        char prev = 0;
        int dot_seen = FALSE;

        switch (*p) {case '+': case '-': prev = *n++ = *p++;}
        if (*p == '0') {
            prev = *n++ = '0';
            while (*++p == '0');
        }
        while (p < end && n < e) prev = *n++ = *p++;
        while (*p) {
            if (*p == '_') {
                /* remove an underscore between digits */
                if (n == buf || !ISDIGIT(prev) || (++p, !ISDIGIT(*p))) {
                    if (badcheck) goto bad;
                    break;
                }
            }
            prev = *p++;
            if (e == init_e && (prev == 'e' || prev == 'E' || prev == 'p' || prev == 'P')) {
                e = buf + sizeof(buf) - 1;
                *n++ = prev;
                switch (*p) {case '+': case '-': prev = *n++ = *p++;}
                if (*p == '0') {
                    prev = *n++ = '0';
                    while (*++p == '0');
                }
                continue;
            }
            else if (ISSPACE(prev)) {
                while (ISSPACE(*p)) ++p;
                if (*p) {
                    if (badcheck) goto bad;
                    break;
                }
            }
            else if (prev == '.' ? dot_seen++ : !ISDIGIT(prev)) {
                if (badcheck) goto bad;
                break;
            }
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

/*!
 * Parses a string representation of a floating point number.
 *
 * \param[in] p  a string representation of a floating number
 * \param[in] badcheck raises an exception on parse error if \a badcheck is non-zero.
 * \return the floating point number in the string on success,
 *   0.0 on parse error and \a badcheck is zero.
 * \note it always fails to parse a hexadecimal representation like "0xAB.CDp+1" when
 *   \a badcheck is zero, even though it would success if \a badcheck was non-zero.
 *   This inconsistency is coming from a historical compatibility reason. [ruby-dev:40822]
 */
double
rb_cstr_to_dbl(const char *p, int badcheck)
{
    return rb_cstr_to_dbl_raise(p, badcheck, TRUE, NULL);
}

static double
rb_str_to_dbl_raise(VALUE str, int badcheck, int raise, int *error)
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
            if (raise)
                rb_raise(rb_eArgError, "string for Float contains null byte");
            else {
                if (error) *error = 1;
                return 0.0;
            }
	}
	if (s[len]) {		/* no sentinel somehow */
	    char *p = ALLOCV(v, (size_t)len + 1);
	    MEMCPY(p, s, char, len);
	    p[len] = '\0';
	    s = p;
	}
    }
    ret = rb_cstr_to_dbl_raise(s, badcheck, raise, error);
    if (v)
	ALLOCV_END(v);
    return ret;
}

FUNC_MINIMIZED(double rb_str_to_dbl(VALUE str, int badcheck));

/*!
 * Parses a string representation of a floating point number.
 *
 * \param[in] str  a \c String object representation of a floating number
 * \param[in] badcheck raises an exception on parse error if \a badcheck is non-zero.
 * \return the floating point number in the string on success,
 *   0.0 on parse error and \a badcheck is zero.
 * \note it always fails to parse a hexadecimal representation like "0xAB.CDp+1" when
 *   \a badcheck is zero, even though it would success if \a badcheck was non-zero.
 *   This inconsistency is coming from a historical compatibility reason. [ruby-dev:40822]
 */
double
rb_str_to_dbl(VALUE str, int badcheck)
{
    return rb_str_to_dbl_raise(str, badcheck, TRUE, NULL);
}

/*! \cond INTERNAL_MACRO */
#define fix2dbl_without_to_f(x) (double)FIX2LONG(x)
#define big2dbl_without_to_f(x) rb_big2dbl(x)
#define int2dbl_without_to_f(x) \
    (FIXNUM_P(x) ? fix2dbl_without_to_f(x) : big2dbl_without_to_f(x))
#define num2dbl_without_to_f(x) \
    (FIXNUM_P(x) ? fix2dbl_without_to_f(x) : \
     RB_TYPE_P(x, T_BIGNUM) ? big2dbl_without_to_f(x) : \
     (Check_Type(x, T_FLOAT), RFLOAT_VALUE(x)))
static inline double
rat2dbl_without_to_f(VALUE x)
{
    VALUE num = rb_rational_num(x);
    VALUE den = rb_rational_den(x);
    return num2dbl_without_to_f(num) / num2dbl_without_to_f(den);
}

#define special_const_to_float(val, pre, post) \
    switch (val) { \
      case Qnil: \
	rb_raise_static(rb_eTypeError, pre "nil" post); \
      case Qtrue: \
	rb_raise_static(rb_eTypeError, pre "true" post); \
      case Qfalse: \
	rb_raise_static(rb_eTypeError, pre "false" post); \
    }
/*! \endcond */

static inline void
conversion_to_float(VALUE val)
{
    special_const_to_float(val, "can't convert ", " into Float");
}

static inline void
implicit_conversion_to_float(VALUE val)
{
    special_const_to_float(val, "no implicit conversion to float from ", "");
}

static int
to_float(VALUE *valp, int raise_exception)
{
    VALUE val = *valp;
    if (SPECIAL_CONST_P(val)) {
	if (FIXNUM_P(val)) {
	    *valp = DBL2NUM(fix2dbl_without_to_f(val));
	    return T_FLOAT;
	}
	else if (FLONUM_P(val)) {
	    return T_FLOAT;
	}
	else if (raise_exception) {
	    conversion_to_float(val);
	}
    }
    else {
	int type = BUILTIN_TYPE(val);
	switch (type) {
	  case T_FLOAT:
	    return T_FLOAT;
	  case T_BIGNUM:
	    *valp = DBL2NUM(big2dbl_without_to_f(val));
	    return T_FLOAT;
	  case T_RATIONAL:
	    *valp = DBL2NUM(rat2dbl_without_to_f(val));
	    return T_FLOAT;
	  case T_STRING:
	    return T_STRING;
	}
    }
    return T_NONE;
}

static VALUE
convert_type_to_float_protected(VALUE val)
{
    return rb_convert_type_with_id(val, T_FLOAT, "Float", id_to_f);
}

static VALUE
rb_convert_to_float(VALUE val, int raise_exception)
{
    switch (to_float(&val, raise_exception)) {
      case T_FLOAT:
	return val;
      case T_STRING:
        if (!raise_exception) {
            int e = 0;
            double x = rb_str_to_dbl_raise(val, TRUE, raise_exception, &e);
            return e ? Qnil : DBL2NUM(x);
        }
        return DBL2NUM(rb_str_to_dbl(val, TRUE));
      case T_NONE:
        if (SPECIAL_CONST_P(val) && !raise_exception)
            return Qnil;
    }

    if (!raise_exception) {
        int state;
        VALUE result = rb_protect(convert_type_to_float_protected, val, &state);
        if (state) rb_set_errinfo(Qnil);
        return result;
    }

    return rb_convert_type_with_id(val, T_FLOAT, "Float", id_to_f);
}

FUNC_MINIMIZED(VALUE rb_Float(VALUE val));

/*!
 * Equivalent to \c Kernel\#Float in Ruby.
 *
 * Converts \a val into \c Float in a slightly more strict manner
 * than \c #to_f.
 */
VALUE
rb_Float(VALUE val)
{
    return rb_convert_to_float(val, TRUE);
}

/*
 *  call-seq:
 *     Float(arg, exception: true)    -> float or nil
 *
 *  Returns <i>arg</i> converted to a float. Numeric types are
 *  converted directly, and with exception to String and
 *  <code>nil</code> the rest are converted using
 *  <i>arg</i><code>.to_f</code>.  Converting a String with invalid
 *  characters will result in a ArgumentError.  Converting
 *  <code>nil</code> generates a TypeError.  Exceptions can be
 *  suppressed by passing <code>exception: false</code>.
 *
 *     Float(1)                 #=> 1.0
 *     Float("123.456")         #=> 123.456
 *     Float("123.0_badstring") #=> ArgumentError: invalid value for Float(): "123.0_badstring"
 *     Float(nil)               #=> TypeError: can't convert nil into Float
 *     Float("123.0_badstring", exception: false)  #=> nil
 */

static VALUE
rb_f_float(int argc, VALUE *argv, VALUE obj)
{
    VALUE arg = Qnil, opts = Qnil;

    rb_scan_args(argc, argv, "1:", &arg, &opts);
    return rb_convert_to_float(arg, opts_exception_p(opts));
}

static VALUE
numeric_to_float(VALUE val)
{
    if (!rb_obj_is_kind_of(val, rb_cNumeric)) {
	rb_raise(rb_eTypeError, "can't convert %"PRIsVALUE" into Float",
		 rb_obj_class(val));
    }
    return rb_convert_type_with_id(val, T_FLOAT, "Float", id_to_f);
}

/*!
 * Converts a \c Numeric object into \c Float.
 * \param[in] val a \c Numeric object
 * \exception TypeError if \a val is not a \c Numeric or other conversion failures.
 */
VALUE
rb_to_float(VALUE val)
{
    switch (to_float(&val, TRUE)) {
      case T_FLOAT:
	return val;
    }
    return numeric_to_float(val);
}

/*!
 * Tries to convert an object into \c Float.
 * It calls \c #to_f if necessary.
 *
 * It returns \c Qnil if the object is not a \c Numeric
 * or \c #to_f is not defined on the object.
 */
VALUE
rb_check_to_float(VALUE val)
{
    if (RB_TYPE_P(val, T_FLOAT)) return val;
    if (!rb_obj_is_kind_of(val, rb_cNumeric)) {
	return Qnil;
    }
    return rb_check_convert_type_with_id(val, T_FLOAT, "Float", id_to_f);
}

static inline int
basic_to_f_p(VALUE klass)
{
    return rb_method_basic_definition_p(klass, id_to_f);
}

/*! \private */
double
rb_num_to_dbl(VALUE val)
{
    if (SPECIAL_CONST_P(val)) {
	if (FIXNUM_P(val)) {
	    if (basic_to_f_p(rb_cInteger))
		return fix2dbl_without_to_f(val);
	}
	else if (FLONUM_P(val)) {
	    return rb_float_flonum_value(val);
	}
	else {
	    conversion_to_float(val);
	}
    }
    else {
	switch (BUILTIN_TYPE(val)) {
	  case T_FLOAT:
	    return rb_float_noflonum_value(val);
	  case T_BIGNUM:
	    if (basic_to_f_p(rb_cInteger))
		return big2dbl_without_to_f(val);
	    break;
	  case T_RATIONAL:
	    if (basic_to_f_p(rb_cRational))
		return rat2dbl_without_to_f(val);
	    break;
	}
    }
    val = numeric_to_float(val);
    return RFLOAT_VALUE(val);
}

/*!
 * Converts a \c Numeric object to \c double.
 * \param[in] val a \c Numeric object
 * \return the converted value
 * \exception TypeError if \a val is not a \c Numeric or
 *   it does not support conversion to a floating point number.
 */
double
rb_num2dbl(VALUE val)
{
    if (SPECIAL_CONST_P(val)) {
	if (FIXNUM_P(val)) {
	    return fix2dbl_without_to_f(val);
	}
	else if (FLONUM_P(val)) {
	    return rb_float_flonum_value(val);
	}
	else {
	    implicit_conversion_to_float(val);
	}
    }
    else {
	switch (BUILTIN_TYPE(val)) {
	  case T_FLOAT:
	    return rb_float_noflonum_value(val);
	  case T_BIGNUM:
	    return big2dbl_without_to_f(val);
	  case T_RATIONAL:
	    return rat2dbl_without_to_f(val);
	  case T_STRING:
	    rb_raise(rb_eTypeError, "no implicit conversion to float from string");
	}
    }
    val = rb_convert_type_with_id(val, T_FLOAT, "Float", id_to_f);
    return RFLOAT_VALUE(val);
}

/*!
 * Equivalent to \c Kernel\#String in Ruby.
 *
 * Converts \a val into \c String by trying \c #to_str at first and
 * then trying \c #to_s.
 */
VALUE
rb_String(VALUE val)
{
    VALUE tmp = rb_check_string_type(val);
    if (NIL_P(tmp))
	tmp = rb_convert_type_with_id(val, T_STRING, "String", idTo_s);
    return tmp;
}


/*
 *  call-seq:
 *     String(arg)   -> string
 *
 *  Returns <i>arg</i> as a String.
 *
 *  First tries to call its <code>to_str</code> method, then its <code>to_s</code> method.
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

/*!
 * Equivalent to \c Kernel\#Array in Ruby.
 */
VALUE
rb_Array(VALUE val)
{
    VALUE tmp = rb_check_array_type(val);

    if (NIL_P(tmp)) {
	tmp = rb_check_to_array(val);
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
 *  First tries to call <code>to_ary</code> on +arg+, then <code>to_a</code>.
 *  If +arg+ does not respond to <code>to_ary</code> or <code>to_a</code>,
 *  returns an Array of length 1 containing +arg+.
 *
 *  If <code>to_ary</code> or <code>to_a</code> returns something other than
 *  an Array, raises a TypeError.
 *
 *     Array(["a", "b"])  #=> ["a", "b"]
 *     Array(1..5)        #=> [1, 2, 3, 4, 5]
 *     Array(key: :value) #=> [[:key, :value]]
 *     Array(nil)         #=> []
 *     Array(1)           #=> [1]
 */

static VALUE
rb_f_array(VALUE obj, VALUE arg)
{
    return rb_Array(arg);
}

/**
 * Equivalent to \c Kernel\#Hash in Ruby
 */
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
 *  Converts <i>arg</i> to a Hash by calling
 *  <i>arg</i><code>.to_hash</code>. Returns an empty Hash when
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

/*! \private */
struct dig_method {
    VALUE klass;
    int basic;
};

static ID id_dig;

static int
dig_basic_p(VALUE obj, struct dig_method *cache)
{
    VALUE klass = RBASIC_CLASS(obj);
    if (klass != cache->klass) {
	cache->klass = klass;
	cache->basic = rb_method_basic_definition_p(klass, id_dig);
    }
    return cache->basic;
}

static void
no_dig_method(int found, VALUE recv, ID mid, int argc, const VALUE *argv, VALUE data)
{
    if (!found) {
	rb_raise(rb_eTypeError, "%"PRIsVALUE" does not have #dig method",
		 CLASS_OF(data));
    }
}

/*! \private */
VALUE
rb_obj_dig(int argc, VALUE *argv, VALUE obj, VALUE notfound)
{
    struct dig_method hash = {Qnil}, ary = {Qnil}, strt = {Qnil};

    for (; argc > 0; ++argv, --argc) {
	if (NIL_P(obj)) return notfound;
	if (!SPECIAL_CONST_P(obj)) {
	    switch (BUILTIN_TYPE(obj)) {
	      case T_HASH:
		if (dig_basic_p(obj, &hash)) {
		    obj = rb_hash_aref(obj, *argv);
		    continue;
		}
		break;
	      case T_ARRAY:
		if (dig_basic_p(obj, &ary)) {
		    obj = rb_ary_at(obj, *argv);
		    continue;
		}
		break;
	      case T_STRUCT:
		if (dig_basic_p(obj, &strt)) {
		    obj = rb_struct_lookup(obj, *argv);
		    continue;
		}
		break;
	    }
	}
	return rb_check_funcall_with_hook(obj, id_dig, argc, argv,
					  no_dig_method, obj);
    }
    return obj;
}

/*
 *  Document-class: Class
 *
 *  Classes in Ruby are first-class objects---each is an instance of
 *  class Class.
 *
 *  Typically, you create a new class by using:
 *
 *    class Name
 *     # some code describing the class behavior
 *    end
 *
 *  When a new class is created, an object of type Class is initialized and
 *  assigned to a global constant (Name in this case).
 *
 *  When <code>Name.new</code> is called to create a new object, the
 *  #new method in Class is run by default.
 *  This can be demonstrated by overriding #new in Class:
 *
 *     class Class
 *       alias old_new new
 *       def new(*args)
 *         print "Creating a new ", self.name, "\n"
 *         old_new(*args)
 *       end
 *     end
 *
 *     class Name
 *     end
 *
 *     n = Name.new
 *
 *  <em>produces:</em>
 *
 *     Creating a new Name
 *
 *  Classes, modules, and objects are interrelated. In the diagram
 *  that follows, the vertical arrows represent inheritance, and the
 *  parentheses metaclasses. All metaclasses are instances
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
 *  classes will not be found without using a full class path.
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
 *  on Object are available to all classes unless explicitly overridden.
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

/*!
 *--
 * \private
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
 *++
 */

void
InitVM_Object(void)
{
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
    rb_define_method(rb_mKernel, "clone", rb_obj_clone2, -1);
    rb_define_method(rb_mKernel, "dup", rb_obj_dup, 0);
    rb_define_method(rb_mKernel, "itself", rb_obj_itself, 0);
    rb_define_method(rb_mKernel, "yield_self", rb_obj_yield_self, 0);
    rb_define_method(rb_mKernel, "then", rb_obj_yield_self, 0);
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
    rb_define_global_function("Float", rb_f_float, -1);

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
    rb_define_method(rb_cNilClass, "=~", nil_match, 1);
    rb_define_method(rb_cNilClass, "&", false_and, 1);
    rb_define_method(rb_cNilClass, "|", false_or, 1);
    rb_define_method(rb_cNilClass, "^", false_xor, 1);
    rb_define_method(rb_cNilClass, "===", rb_equal, 1);

    rb_define_method(rb_cNilClass, "nil?", rb_true, 0);
    rb_undef_alloc_func(rb_cNilClass);
    rb_undef_method(CLASS_OF(rb_cNilClass), "new");
    /*
     * An obsolete alias of +nil+
     */
    rb_define_global_const("NIL", Qnil);
    rb_deprecate_constant(rb_cObject, "NIL");

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

    rb_define_method(rb_cModule, "attr", rb_mod_attr, -1);
    rb_define_method(rb_cModule, "attr_reader", rb_mod_attr_reader, -1);
    rb_define_method(rb_cModule, "attr_writer", rb_mod_attr_writer, -1);
    rb_define_method(rb_cModule, "attr_accessor", rb_mod_attr_accessor, -1);

    rb_define_alloc_func(rb_cModule, rb_module_s_alloc);
    rb_define_method(rb_cModule, "initialize", rb_mod_initialize, 0);
    rb_define_method(rb_cModule, "initialize_clone", rb_mod_initialize_clone, 1);
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
    rb_define_method(rb_cModule, "deprecate_constant", rb_mod_deprecate_constant, -1); /* in variable.c */
    rb_define_method(rb_cModule, "singleton_class?", rb_mod_singleton_p, 0);

    rb_define_method(rb_cClass, "allocate", rb_class_alloc, 0);
    rb_define_method(rb_cClass, "new", rb_class_s_new, -1);
    rb_define_method(rb_cClass, "initialize", rb_class_initialize, -1);
    rb_define_method(rb_cClass, "superclass", rb_class_superclass, 0);
    rb_define_alloc_func(rb_cClass, rb_class_s_alloc);
    rb_undef_method(rb_cClass, "extend_object");
    rb_undef_method(rb_cClass, "append_features");
    rb_undef_method(rb_cClass, "prepend_features");

    /*
     * Document-class: Data
     *
     * This is a deprecated class, base class for C extensions using
     * Data_Make_Struct or Data_Wrap_Struct.
     */
    rb_cData = rb_define_class("Data", rb_cObject);
    rb_undef_alloc_func(rb_cData);
    rb_deprecate_constant(rb_cObject, "Data");

    rb_cTrueClass = rb_define_class("TrueClass", rb_cObject);
    rb_define_method(rb_cTrueClass, "to_s", true_to_s, 0);
    rb_define_alias(rb_cTrueClass, "inspect", "to_s");
    rb_define_method(rb_cTrueClass, "&", true_and, 1);
    rb_define_method(rb_cTrueClass, "|", true_or, 1);
    rb_define_method(rb_cTrueClass, "^", true_xor, 1);
    rb_define_method(rb_cTrueClass, "===", rb_equal, 1);
    rb_undef_alloc_func(rb_cTrueClass);
    rb_undef_method(CLASS_OF(rb_cTrueClass), "new");
    /*
     * An obsolete alias of +true+
     */
    rb_define_global_const("TRUE", Qtrue);
    rb_deprecate_constant(rb_cObject, "TRUE");

    rb_cFalseClass = rb_define_class("FalseClass", rb_cObject);
    rb_define_method(rb_cFalseClass, "to_s", false_to_s, 0);
    rb_define_alias(rb_cFalseClass, "inspect", "to_s");
    rb_define_method(rb_cFalseClass, "&", false_and, 1);
    rb_define_method(rb_cFalseClass, "|", false_or, 1);
    rb_define_method(rb_cFalseClass, "^", false_xor, 1);
    rb_define_method(rb_cFalseClass, "===", rb_equal, 1);
    rb_undef_alloc_func(rb_cFalseClass);
    rb_undef_method(CLASS_OF(rb_cFalseClass), "new");
    /*
     * An obsolete alias of +false+
     */
    rb_define_global_const("FALSE", Qfalse);
    rb_deprecate_constant(rb_cObject, "FALSE");
}

void
Init_Object(void)
{
    id_dig = rb_intern_const("dig");
    InitVM(Object);
}

/*!
 * \}
 */
