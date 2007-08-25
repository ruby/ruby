/**********************************************************************

  class.c -

  $Author$
  $Date$
  created at: Tue Aug 10 15:05:44 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/signal.h"
#include "ruby/node.h"
#include "ruby/st.h"
#include <ctype.h>

extern st_table *rb_class_tbl;

VALUE
rb_class_boot(VALUE super)
{
    NEWOBJ(klass, struct RClass);
    OBJSETUP(klass, rb_cClass, T_CLASS);

    klass->super = super;
    klass->iv_tbl = 0;
    klass->m_tbl = 0;		/* safe GC */
    klass->m_tbl = st_init_numtable();

    OBJ_INFECT(klass, super);
    return (VALUE)klass;
}

void
rb_check_inheritable(VALUE super)
{
    if (TYPE(super) != T_CLASS) {
	rb_raise(rb_eTypeError, "superclass must be a Class (%s given)",
		 rb_obj_classname(super));
    }
    if (RBASIC(super)->flags & FL_SINGLETON) {
	rb_raise(rb_eTypeError, "can't make subclass of singleton class");
    }
}

VALUE
rb_class_new(VALUE super)
{
    Check_Type(super, T_CLASS);
    rb_check_inheritable(super);
    if (super == rb_cClass) {
	rb_raise(rb_eTypeError, "can't make subclass of Class");
    }
    return rb_class_boot(super);
}

struct clone_method_data {
    st_table *tbl;
    VALUE klass;
};

static int
clone_method(ID mid, NODE *body, struct clone_method_data *data)
{
    if (body == 0) {
	st_insert(data->tbl, mid, 0);
    }
    else {
	st_insert(data->tbl, mid,
		  (st_data_t)
		  NEW_FBODY(
		      NEW_METHOD(body->nd_body->nd_body,
				 data->klass, /* TODO */
				 body->nd_body->nd_noex),
		      0));
    }
    return ST_CONTINUE;
}

/* :nodoc: */
VALUE
rb_mod_init_copy(VALUE clone, VALUE orig)
{
    rb_obj_init_copy(clone, orig);
    if (!FL_TEST(CLASS_OF(clone), FL_SINGLETON)) {
	RBASIC(clone)->klass = rb_singleton_class_clone(orig);
    }
    RCLASS(clone)->super = RCLASS(orig)->super;
    if (RCLASS(orig)->iv_tbl) {
	ID id;

	RCLASS(clone)->iv_tbl = st_copy(RCLASS(orig)->iv_tbl);
	id = rb_intern("__classpath__");
	st_delete(RCLASS(clone)->iv_tbl, (st_data_t*)&id, 0);
	id = rb_intern("__classid__");
	st_delete(RCLASS(clone)->iv_tbl, (st_data_t*)&id, 0);
    }
    if (RCLASS(orig)->m_tbl) {
	struct clone_method_data data;
	data.tbl = RCLASS(clone)->m_tbl = st_init_numtable();
	data.klass = clone;
	st_foreach(RCLASS(orig)->m_tbl, clone_method,
	  (st_data_t)&data);
    }

    return clone;
}

/* :nodoc: */
VALUE
rb_class_init_copy(VALUE clone, VALUE orig)
{
    if (RCLASS(clone)->super != 0) {
	rb_raise(rb_eTypeError, "already initialized class");
    }
    if (FL_TEST(orig, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't copy singleton class");
    }
    return rb_mod_init_copy(clone, orig);
}

VALUE
rb_singleton_class_clone(VALUE obj)
{
    VALUE klass = RBASIC(obj)->klass;

    if (!FL_TEST(klass, FL_SINGLETON))
	return klass;
    else {
	struct clone_method_data data;
	/* copy singleton(unnamed) class */
	NEWOBJ(clone, struct RClass);
	OBJSETUP(clone, 0, RBASIC(klass)->flags);

	if (BUILTIN_TYPE(obj) == T_CLASS) {
	    RBASIC(clone)->klass = (VALUE)clone;
	}
	else {
	    RBASIC(clone)->klass = rb_singleton_class_clone(klass);
	}

	clone->super = RCLASS(klass)->super;
	clone->iv_tbl = 0;
	clone->m_tbl = 0;
	if (RCLASS(klass)->iv_tbl) {
	    clone->iv_tbl = st_copy(RCLASS(klass)->iv_tbl);
	}
	clone->m_tbl = st_init_numtable();
	data.tbl = clone->m_tbl;
	data.klass = (VALUE)clone;
	st_foreach(RCLASS(klass)->m_tbl, clone_method,
	  (st_data_t)&data);
	rb_singleton_class_attached(RBASIC(clone)->klass, (VALUE)clone);
	FL_SET(clone, FL_SINGLETON);
	return (VALUE)clone;
    }
}

void
rb_singleton_class_attached(VALUE klass, VALUE obj)
{
    if (FL_TEST(klass, FL_SINGLETON)) {
	if (!RCLASS(klass)->iv_tbl) {
	    RCLASS(klass)->iv_tbl = st_init_numtable();
	}
	st_insert(RCLASS(klass)->iv_tbl, rb_intern("__attached__"), obj);
    }
}

VALUE
rb_make_metaclass(VALUE obj, VALUE super)
{
    if (BUILTIN_TYPE(obj) == T_CLASS && FL_TEST(obj, FL_SINGLETON)) {
	return RBASIC(obj)->klass = rb_cClass;
    }
    else {
	VALUE metasuper;
	VALUE klass = rb_class_boot(super);

	FL_SET(klass, FL_SINGLETON);
	RBASIC(obj)->klass = klass;
	rb_singleton_class_attached(klass, obj);

	metasuper = RBASIC(rb_class_real(super))->klass;
	/* metaclass of a superclass may be NULL at boot time */
	if (metasuper) {
	    RBASIC(klass)->klass = metasuper;
	}
	return klass;
    }
}

VALUE
rb_define_class_id(ID id, VALUE super)
{
    VALUE klass;

    if (!super) super = rb_cObject;
    klass = rb_class_new(super);
    rb_make_metaclass(klass, RBASIC(super)->klass);

    return klass;
}

VALUE
rb_class_inherited(VALUE super, VALUE klass)
{
    if (!super) super = rb_cObject;
    return rb_funcall(super, rb_intern("inherited"), 1, klass);
}

VALUE
rb_define_class(const char *name, VALUE super)
{
    VALUE klass;
    ID id;

    id = rb_intern(name);
    if (rb_const_defined(rb_cObject, id)) {
	klass = rb_const_get(rb_cObject, id);
	if (TYPE(klass) != T_CLASS) {
	    rb_raise(rb_eTypeError, "%s is not a class", name);
	}
	if (rb_class_real(RCLASS(klass)->super) != super) {
	    rb_name_error(id, "%s is already defined", name);
	}
	return klass;
    }
    if (!super) {
	rb_warn("no super class for `%s', Object assumed", name);
    }
    klass = rb_define_class_id(id, super);
    st_add_direct(rb_class_tbl, id, klass);
    rb_name_class(klass, id);
    rb_const_set(rb_cObject, id, klass);
    rb_class_inherited(super, klass);

    return klass;
}

VALUE
rb_define_class_under(VALUE outer, const char *name, VALUE super)
{
    VALUE klass;
    ID id;

    id = rb_intern(name);
    if (rb_const_defined_at(outer, id)) {
	klass = rb_const_get_at(outer, id);
	if (TYPE(klass) != T_CLASS) {
	    rb_raise(rb_eTypeError, "%s is not a class", name);
	}
	if (rb_class_real(RCLASS(klass)->super) != super) {
	    rb_name_error(id, "%s is already defined", name);
	}
	return klass;
    }
    if (!super) {
	rb_warn("no super class for `%s::%s', Object assumed",
		rb_class2name(outer), name);
    }
    klass = rb_define_class_id(id, super);
    rb_set_class_path(klass, outer, name);
    rb_const_set(outer, id, klass);
    rb_class_inherited(super, klass);

    return klass;
}

VALUE
rb_module_new(void)
{
    NEWOBJ(mdl, struct RClass);
    OBJSETUP(mdl, rb_cModule, T_MODULE);

    mdl->super = 0;
    mdl->iv_tbl = 0;
    mdl->m_tbl = 0;
    mdl->m_tbl = st_init_numtable();

    return (VALUE)mdl;
}

VALUE
rb_define_module_id(ID id)
{
    VALUE mdl;

    mdl = rb_module_new();
    rb_name_class(mdl, id);

    return mdl;
}

VALUE
rb_define_module(const char *name)
{
    VALUE module;
    ID id;

    id = rb_intern(name);
    if (rb_const_defined(rb_cObject, id)) {
	module = rb_const_get(rb_cObject, id);
	if (TYPE(module) == T_MODULE)
	    return module;
	rb_raise(rb_eTypeError, "%s is not a module", rb_obj_classname(module));
    }
    module = rb_define_module_id(id);
    st_add_direct(rb_class_tbl, id, module);
    rb_const_set(rb_cObject, id, module);

    return module;
}

VALUE
rb_define_module_under(VALUE outer, const char *name)
{
    VALUE module;
    ID id;

    id = rb_intern(name);
    if (rb_const_defined_at(outer, id)) {
	module = rb_const_get_at(outer, id);
	if (TYPE(module) == T_MODULE)
	    return module;
	rb_raise(rb_eTypeError, "%s::%s is not a module",
		 rb_class2name(outer), rb_obj_classname(module));
    }
    module = rb_define_module_id(id);
    rb_const_set(outer, id, module);
    rb_set_class_path(module, outer, name);

    return module;
}

static VALUE
include_class_new(VALUE module, VALUE super)
{
    NEWOBJ(klass, struct RClass);
    OBJSETUP(klass, rb_cClass, T_ICLASS);

    if (BUILTIN_TYPE(module) == T_ICLASS) {
	module = RBASIC(module)->klass;
    }
    if (!RCLASS(module)->iv_tbl) {
	RCLASS(module)->iv_tbl = st_init_numtable();
    }
    klass->iv_tbl = RCLASS(module)->iv_tbl;
    klass->m_tbl = RCLASS(module)->m_tbl;
    klass->super = super;
    if (TYPE(module) == T_ICLASS) {
	RBASIC(klass)->klass = RBASIC(module)->klass;
    }
    else {
	RBASIC(klass)->klass = module;
    }
    OBJ_INFECT(klass, module);
    OBJ_INFECT(klass, super);

    return (VALUE)klass;
}

void
rb_include_module(VALUE klass, VALUE module)
{
    VALUE p, c;
    int changed = 0;

    rb_frozen_class_p(klass);
    if (!OBJ_TAINTED(klass)) {
	rb_secure(4);
    }
    
    if (TYPE(module) != T_MODULE) {
	Check_Type(module, T_MODULE);
    }

    OBJ_INFECT(klass, module);
    c = klass;
    while (module) {
       int superclass_seen = Qfalse;

	if (RCLASS(klass)->m_tbl == RCLASS(module)->m_tbl)
	    rb_raise(rb_eArgError, "cyclic include detected");
       /* ignore if the module included already in superclasses */
       for (p = RCLASS(klass)->super; p; p = RCLASS(p)->super) {
           switch (BUILTIN_TYPE(p)) {
             case T_ICLASS:
               if (RCLASS(p)->m_tbl == RCLASS(module)->m_tbl) {
                   if (!superclass_seen) {
                       c = p;  /* move insertion point */
                   }
                   goto skip;
               }
               break;
             case T_CLASS:
               superclass_seen = Qtrue;
               break;
           }
       }
       c = RCLASS(c)->super = include_class_new(module, RCLASS(c)->super);
	changed = 1;
      skip:
	module = RCLASS(module)->super;
    }
    if (changed) rb_clear_cache();
}

/*
 *  call-seq:
 *     mod.included_modules -> array
 *  
 *  Returns the list of modules included in <i>mod</i>.
 *     
 *     module Mixin
 *     end
 *     
 *     module Outer
 *       include Mixin
 *     end
 *     
 *     Mixin.included_modules   #=> []
 *     Outer.included_modules   #=> [Mixin]
 */

VALUE
rb_mod_included_modules(VALUE mod)
{
    VALUE ary = rb_ary_new();
    VALUE p;

    for (p = RCLASS(mod)->super; p; p = RCLASS(p)->super) {
	if (BUILTIN_TYPE(p) == T_ICLASS) {
	    rb_ary_push(ary, RBASIC(p)->klass);
	}
    }
    return ary;
}

/*
 *  call-seq:
 *     mod.include?(module)    => true or false
 *  
 *  Returns <code>true</code> if <i>module</i> is included in
 *  <i>mod</i> or one of <i>mod</i>'s ancestors.
 *     
 *     module A
 *     end
 *     class B
 *       include A
 *     end
 *     class C < B
 *     end
 *     B.include?(A)   #=> true
 *     C.include?(A)   #=> true
 *     A.include?(A)   #=> false
 */

VALUE
rb_mod_include_p(VALUE mod, VALUE mod2)
{
    VALUE p;

    Check_Type(mod2, T_MODULE);
    for (p = RCLASS(mod)->super; p; p = RCLASS(p)->super) {
	if (BUILTIN_TYPE(p) == T_ICLASS) {
	    if (RBASIC(p)->klass == mod2) return Qtrue;
	}
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.ancestors -> array
 *  
 *  Returns a list of modules included in <i>mod</i> (including
 *  <i>mod</i> itself).
 *     
 *     module Mod
 *       include Math
 *       include Comparable
 *     end
 *     
 *     Mod.ancestors    #=> [Mod, Comparable, Math]
 *     Math.ancestors   #=> [Math]
 */

VALUE
rb_mod_ancestors(VALUE mod)
{
    VALUE p, ary = rb_ary_new();

    for (p = mod; p; p = RCLASS(p)->super) {
	if (FL_TEST(p, FL_SINGLETON))
	    continue;
	if (BUILTIN_TYPE(p) == T_ICLASS) {
	    rb_ary_push(ary, RBASIC(p)->klass);
	}
	else {
	    rb_ary_push(ary, p);
	}
    }
    return ary;
}

#define VISI(x) ((x)&NOEX_MASK)
#define VISI_CHECK(x,f) (VISI(x) == (f))

static int
ins_methods_push(ID name, long type, VALUE ary, long visi)
{
    if (type == -1) return ST_CONTINUE;

    switch (visi) {
      case NOEX_PRIVATE:
      case NOEX_PROTECTED:
      case NOEX_PUBLIC:
      case NOEX_LOCAL:
	visi = (type == visi);
	break;
      default:
	visi = (type != NOEX_PRIVATE);
	break;
    }
    if (visi) {
	rb_ary_push(ary, ID2SYM(name));
    }
    return ST_CONTINUE;
}

static int
ins_methods_i(ID name, long type, VALUE ary)
{
    return ins_methods_push(name, type, ary, -1); /* everything but private */
}

static int
ins_methods_prot_i(ID name, long type, VALUE ary)
{
    return ins_methods_push(name, type, ary, NOEX_PROTECTED);
}

static int
ins_methods_priv_i(ID name, long type, VALUE ary)
{
    return ins_methods_push(name, type, ary, NOEX_PRIVATE);
}

static int
ins_methods_pub_i(ID name, long type, VALUE ary)
{
    return ins_methods_push(name, type, ary, NOEX_PUBLIC);
}

static int
ins_methods_local_i(ID name, long type, VALUE ary)
{
    return ins_methods_push(name, type, ary, NOEX_LOCAL);
}

static int
method_entry(ID key, NODE *body, st_table *list)
{
    long type;

    if (key == ID_ALLOCATOR) {
	return ST_CONTINUE;
    }
    
    if (!st_lookup(list, key, 0)) {
	if (body ==0 || !body->nd_body->nd_body) {
	    type = -1; /* none */
	}
	else {
	    type = VISI(body->nd_body->nd_noex);
	}
	st_add_direct(list, key, type);
    }
    return ST_CONTINUE;
}

static VALUE
class_instance_method_list(int argc, VALUE *argv, VALUE mod, int (*func) (ID, long, VALUE))
{
    VALUE ary;
    int recur;
    st_table *list;

    if (argc == 0) {
	recur = Qtrue;
    }
    else {
	VALUE r;
	rb_scan_args(argc, argv, "01", &r);
	recur = RTEST(r);
    }

    list = st_init_numtable();
    for (; mod; mod = RCLASS(mod)->super) {
	st_foreach(RCLASS(mod)->m_tbl, method_entry, (st_data_t)list);
	if (BUILTIN_TYPE(mod) == T_ICLASS) continue;
	if (FL_TEST(mod, FL_SINGLETON)) continue;
	if (!recur) break;
    }
    ary = rb_ary_new();
    st_foreach(list, func, ary);
    st_free_table(list);

    return ary;
}

/*
 *  call-seq:
 *     mod.instance_methods(include_super=true)   => array
 *  
 *  Returns an array containing the names of public instance methods in
 *  the receiver. For a module, these are the public methods; for a
 *  class, they are the instance (not singleton) methods. With no
 *  argument, or with an argument that is <code>false</code>, the
 *  instance methods in <i>mod</i> are returned, otherwise the methods
 *  in <i>mod</i> and <i>mod</i>'s superclasses are returned.
 *     
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       def method2()  end
 *     end
 *     class C < B
 *       def method3()  end
 *     end
 *     
 *     A.instance_methods                #=> ["method1"]
 *     B.instance_methods(false)         #=> ["method2"]
 *     C.instance_methods(false)         #=> ["method3"]
 *     C.instance_methods(true).length   #=> 43
 */

VALUE
rb_class_instance_methods(int argc, VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, ins_methods_i);
}

/*
 *  call-seq:
 *     mod.protected_instance_methods(include_super=true)   => array
 *  
 *  Returns a list of the protected instance methods defined in
 *  <i>mod</i>. If the optional parameter is not <code>false</code>, the
 *  methods of any ancestors are included.
 */

VALUE
rb_class_protected_instance_methods(int argc, VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, ins_methods_prot_i);
}

/*
 *  call-seq:
 *     mod.private_instance_methods(include_super=true)    => array
 *  
 *  Returns a list of the private instance methods defined in
 *  <i>mod</i>. If the optional parameter is not <code>false</code>, the
 *  methods of any ancestors are included.
 *     
 *     module Mod
 *       def method1()  end
 *       private :method1
 *       def method2()  end
 *     end
 *     Mod.instance_methods           #=> ["method2"]
 *     Mod.private_instance_methods   #=> ["method1"]
 */

VALUE
rb_class_private_instance_methods(int argc, VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, ins_methods_priv_i);
}

/*
 *  call-seq:
 *     mod.public_instance_methods(include_super=true)   => array
 *  
 *  Returns a list of the public instance methods defined in <i>mod</i>.
 *  If the optional parameter is not <code>false</code>, the methods of
 *  any ancestors are included.
 */

VALUE
rb_class_public_instance_methods(int argc, VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, ins_methods_pub_i);
}

/*
 *  call-seq:
 *     mod.local_methods   => array
 *  
 *  Returns a list of the local methods defined in <i>mod</i>.
 */

VALUE
rb_class_local_methods(VALUE mod)
{
    return class_instance_method_list(0, 0, mod, ins_methods_local_i);
}

/*
 *  call-seq:
 *     obj.singleton_methods(all=true)    => array
 *  
 *  Returns an array of the names of singleton methods for <i>obj</i>.
 *  If the optional <i>all</i> parameter is true, the list will include
 *  methods in modules included in <i>obj</i>.
 *     
 *     module Other
 *       def three() end
 *     end
 *     
 *     class Single
 *       def Single.four() end
 *     end
 *     
 *     a = Single.new
 *     
 *     def a.one()
 *     end
 *     
 *     class << a
 *       include Other
 *       def two()
 *       end
 *     end
 *     
 *     Single.singleton_methods    #=> ["four"]
 *     a.singleton_methods(false)  #=> ["two", "one"]
 *     a.singleton_methods         #=> ["two", "one", "three"]
 */

VALUE
rb_obj_singleton_methods(int argc, VALUE *argv, VALUE obj)
{
    VALUE recur, ary, klass;
    st_table *list;

    rb_scan_args(argc, argv, "01", &recur);
    if (argc == 0) {
	recur = Qtrue;
    }
    klass = CLASS_OF(obj);
    list = st_init_numtable();
    if (klass && FL_TEST(klass, FL_SINGLETON)) {
	st_foreach(RCLASS(klass)->m_tbl, method_entry, (st_data_t)list);
	klass = RCLASS(klass)->super;
    }
    if (RTEST(recur)) {
	while (klass && (FL_TEST(klass, FL_SINGLETON) || TYPE(klass) == T_ICLASS)) {
	    st_foreach(RCLASS(klass)->m_tbl, method_entry, (st_data_t)list);
	    klass = RCLASS(klass)->super;
	}
    }
    ary = rb_ary_new();
    st_foreach(list, ins_methods_i, ary);
    st_free_table(list);

    return ary;
}

void
rb_define_method_id(VALUE klass, ID name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method(klass, name, NEW_CFUNC(func,argc), NOEX_PUBLIC);
}

void
rb_define_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method(klass, rb_intern(name), NEW_CFUNC(func, argc), NOEX_PUBLIC);
}

void
rb_define_protected_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method(klass, rb_intern(name), NEW_CFUNC(func, argc), NOEX_PROTECTED);
}

void
rb_define_private_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method(klass, rb_intern(name), NEW_CFUNC(func, argc), NOEX_PRIVATE);
}

void
rb_undef_method(VALUE klass, const char *name)
{
    rb_add_method(klass, rb_intern(name), 0, NOEX_UNDEF);
}

#define SPECIAL_SINGLETON(x,c) do {\
    if (obj == (x)) {\
	return c;\
    }\
} while (0)

VALUE
rb_singleton_class(VALUE obj)
{
    VALUE klass;

    if (FIXNUM_P(obj) || SYMBOL_P(obj)) {
	rb_raise(rb_eTypeError, "can't define singleton");
    }
    if (rb_special_const_p(obj)) {
	SPECIAL_SINGLETON(Qnil, rb_cNilClass);
	SPECIAL_SINGLETON(Qfalse, rb_cFalseClass);
	SPECIAL_SINGLETON(Qtrue, rb_cTrueClass);
	rb_bug("unknown immediate %ld", obj);
    }

    DEFER_INTS;
    if (FL_TEST(RBASIC(obj)->klass, FL_SINGLETON) &&
	rb_iv_get(RBASIC(obj)->klass, "__attached__") == obj) {
	klass = RBASIC(obj)->klass;
    }
    else {
	klass = rb_make_metaclass(obj, RBASIC(obj)->klass);
    }
    if (OBJ_TAINTED(obj)) {
	OBJ_TAINT(klass);
    }
    else {
	FL_UNSET(klass, FL_TAINT);
    }
    if (OBJ_FROZEN(obj)) OBJ_FREEZE(klass);
    ALLOW_INTS;

    return klass;
}

void
rb_define_singleton_method(VALUE obj, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_method(rb_singleton_class(obj), name, func, argc);
}

void
rb_define_module_function(VALUE module, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_private_method(module, name, func, argc);
    rb_define_singleton_method(module, name, func, argc);
}

void
rb_define_global_function(const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_module_function(rb_mKernel, name, func, argc);
}

void
rb_define_alias(VALUE klass, const char *name1, const char *name2)
{
    rb_alias(klass, rb_intern(name1), rb_intern(name2));
}

void
rb_define_attr(VALUE klass, const char *name, int read, int write)
{
    rb_attr(klass, rb_intern(name), read, write, Qfalse);
}

#include <stdarg.h>

int
rb_scan_args(int argc, const VALUE *argv, const char *fmt, ...)
{
    int n, i = 0;
    const char *p = fmt;
    VALUE *var;
    va_list vargs;

    va_start(vargs, fmt);

    if (*p == '*') goto rest_arg;

    if (ISDIGIT(*p)) {
	n = *p - '0';
	if (n > argc)
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", argc, n);
	for (i=0; i<n; i++) {
	    var = va_arg(vargs, VALUE*);
	    if (var) *var = argv[i];
	}
	p++;
    }
    else {
	goto error;
    }

    if (ISDIGIT(*p)) {
	n = i + *p - '0';
	for (; i<n; i++) {
	    var = va_arg(vargs, VALUE*);
	    if (argc > i) {
		if (var) *var = argv[i];
	    }
	    else {
		if (var) *var = Qnil;
	    }
	}
	p++;
    }

    if(*p == '*') {
      rest_arg:
	var = va_arg(vargs, VALUE*);
	if (argc > i) {
	    if (var) *var = rb_ary_new4(argc-i, argv+i);
	    i = argc;
	}
	else {
	    if (var) *var = rb_ary_new();
	}
	p++;
    }

    if (*p == '&') {
	var = va_arg(vargs, VALUE*);
	if (rb_block_given_p()) {
	    *var = rb_block_proc();
	}
	else {
	    *var = Qnil;
	}
	p++;
    }
    va_end(vargs);

    if (*p != '\0') {
	goto error;
    }

    if (argc > i) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", argc, i);
    }

    return argc;

  error:
    rb_fatal("bad scan arg format: %s", fmt);
    return 0;
}
