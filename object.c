/************************************************

  object.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:49 $
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"
#include <stdio.h>

VALUE cKernel;
VALUE cObject;
VALUE cModule;
VALUE cClass;
VALUE cNil;
VALUE cData;

struct st_table *new_idhash();

VALUE f_sprintf();

VALUE obj_alloc();

static ID eq;

static ID init;

VALUE
rb_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    return rb_funcall(obj1, eq, 1, obj2);
}

static VALUE
krn_nil_p(obj)
    VALUE obj;
{
    return FALSE;
}

static VALUE
krn_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    if (obj1 == obj2) return TRUE;
    return FALSE;
}

static VALUE
krn_to_a(obj)
    VALUE obj;
{
    return ary_new3(1, obj);
}

static VALUE
krn_id(obj)
    VALUE obj;
{
    return obj | FIXNUM_FLAG;
}

static VALUE
krn_type(obj)
    struct RBasic *obj;
{
    return obj->class;
}

static VALUE
krn_clone(obj)
    VALUE obj;
{
    VALUE clone;

    if (TYPE(obj) != T_OBJECT) {
	Fail("can't clone %s", rb_class2name(CLASS_OF(obj)));
    }

    clone = obj_alloc(RBASIC(obj)->class);
    if (ROBJECT(obj)->iv_tbl) {
	ROBJECT(clone)->iv_tbl = st_copy(ROBJECT(obj)->iv_tbl);
    }
    RBASIC(clone)->class = singleton_class_clone(RBASIC(obj)->class);

    return clone;
}

static VALUE
krn_dup(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("clone"), 0, 0);
}

VALUE
krn_to_s(obj)
    VALUE obj;
{
    char buf[256];

    sprintf(buf, "#<%s:0x%x>", rb_class2name(CLASS_OF(obj)), obj);
    return str_new2(buf);
}

VALUE
krn_inspect(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("to_s"), 0, 0);
}

static int
inspect_i(id, value, str)
    ID id;
    VALUE value;
    struct RString *str;
{
    VALUE str2;
    char *ivname;

    if (str->ptr[0] == '-') {
	str->ptr[0] = '#';
    }
    else {
	str_cat(str, ", ", 2);
    }
    ivname = rb_id2name(id);
    str_cat(str, ivname, strlen(ivname));
    str_cat(str, "=", 1);
    str2 = rb_funcall(value, rb_intern("inspect"), 0, 0);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
obj_inspect(obj)
    struct RObject *obj;
{
    VALUE str;
    char buf[256];

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_MODULE:
      case T_CLASS:
	if (obj->iv_tbl) break;
	/* fall through */
      default:
	return krn_inspect(obj);
    }

    sprintf(buf, "-<%s: ", rb_class2name(CLASS_OF(obj)));
    str = str_new2(buf);
    st_foreach(obj->iv_tbl, inspect_i, str);
    str_cat(str, ">", 1);

    return str;
}

VALUE
obj_is_instance_of(obj, c)
    VALUE obj, c;
{
    struct RClass *class = (struct RClass*)CLASS_OF(obj);

    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	Fail("class or module required");
    }

    while (FL_TEST(class, FL_SINGLE)) {
	class = class->super;
    }
    if (c == (VALUE)class) return TRUE;
    return FALSE;
}

VALUE
obj_is_kind_of(obj, c)
    VALUE obj, c;
{
    struct RClass *class = (struct RClass*)CLASS_OF(obj);

    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	Fail("class or module required");
    }

    while (class) {
	if ((VALUE)class == c || RCLASS(class)->m_tbl == RCLASS(c)->m_tbl)
	    return TRUE;
	class = class->super;
    }
    return FALSE;
}

static VALUE
obj_initialize(obj)
    VALUE obj;
{
    return Qnil;
}

static VALUE
obj_s_added(obj, id)
    VALUE obj, id;
{
    return Qnil;
}

static VALUE
nil_nil_p(obj)
    VALUE obj;
{
    return TRUE;
}

static VALUE
nil_to_s(obj)
    VALUE obj;
{
    return str_new2("nil");
}

static VALUE
nil_type(nil)
    VALUE nil;
{
    return cNil;
}

static VALUE
nil_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
      case T_FLOAT:
      case T_BIGNUM:
      case T_STRING:
      case T_ARRAY:
	return y;
      default:
	Fail("tried to add %s(%s) to nil",
	     RSTRING(obj_as_string(y))->ptr, rb_class2name(CLASS_OF(y)));
    }
    return Qnil;		/* not reached */
}

static VALUE
main_to_s(obj)
    VALUE obj;
{
    return str_new2("main");
}

static VALUE
true_to_s(obj)
    VALUE obj;
{
    return str_new2("t");
}

VALUE
obj_alloc(class)
    VALUE class;
{
    NEWOBJ(obj, struct RObject);
    OBJSETUP(obj, class, T_OBJECT);

    return (VALUE)obj;
}

static VALUE
mod_new(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE obj = obj_alloc(class);

    rb_funcall2(obj, init, argc, argv);
    return obj;
}

static VALUE
mod_clone(module)
    struct RClass *module;
{
    NEWOBJ(clone, struct RClass);
    OBJSETUP(clone, CLASS_OF(module), TYPE(module));

    clone->super = module->super;
    clone->m_tbl = st_copy(module->m_tbl);

    return (VALUE)clone;
}

char *rb_class2path();

static VALUE
mod_to_s(class)
    VALUE class;
{
    return rb_class_path(class);
}

ID
rb_to_id(name)
    VALUE name;
{
    if (TYPE(name) == T_STRING) {
	return rb_intern(RSTRING(name)->ptr);
    }
    return NUM2INT(name);
}

static VALUE
mod_attr(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE name, pub;
    ID id;

    rb_scan_args(argc, argv, "11", &name, &pub);
    rb_define_attr(class, rb_to_id(name), pub);
    return Qnil;
}

static VALUE
mod_public_attr(class, name)
    VALUE class, name;
{
    rb_define_attr(class, rb_to_id(name), 1);
    return Qnil;
}

static VALUE
mod_private_attr(class, name)
    VALUE class, name;
{
    rb_define_attr(class, rb_to_id(name), 0);
    return Qnil;
}

static
VALUE boot_defclass(name, super)
    char *name;
    VALUE super;
{
    extern st_table *rb_class_tbl;
    struct RClass *obj = (struct RClass*)class_new(super);
    ID id = rb_intern(name);

    rb_name_class(obj, id);
    st_add_direct(rb_class_tbl, id, obj);
    rb_set_class_path(obj, 0, name);
    return (VALUE)obj;
}

VALUE TopSelf;
VALUE TRUE = INT2FIX(1);

void
Init_Object()
{
    VALUE metaclass;

    cKernel = boot_defclass("Kernel", Qnil);
    cObject = boot_defclass("Object", cKernel);
    cModule = boot_defclass("Module", cObject);
    cClass =  boot_defclass("Class",  cModule);

    metaclass = RBASIC(cKernel)->class = singleton_class_new(cClass);
    metaclass = RBASIC(cObject)->class = singleton_class_new(metaclass);
    metaclass = RBASIC(cModule)->class = singleton_class_new(metaclass);
    metaclass = RBASIC(cClass)->class = singleton_class_new(metaclass);

    /*
     * Ruby's Class Hierarchy Chart
     *
     * 	+-------nil	      +---------------------+
     *  |        ^	      |			    |
     *  |        |     	      |			    |
     *  |      Kernel----->(Kernel)		    |
     *  |       ^  ^         ^  ^		    |
     *	|       |  |         |  |		    |
     *	|   +---+  +----+    |  +---+		    |
     *	|   |     +-----|----+      |		    |
     *	|   |     |     |           |               |
     * 	+->Nil->(Nil) Object---->(Object)	    |
     *	   	       ^ ^         ^  ^	            |
     *	   	       | |         |  |	            |
     *                 | | +-------+  |	            |
     *                 | | |          |	    	    |
     *                 | +---------+  +------+	    |
     *	       	       |   |       |          |	    |
     * 	     +---------+   |     Module--->(Module) |
     *	     |             |       ^          ^	    |
     *  OtherClass-->(OtherClass)  |          |	    |
     * 		                 Class---->(Class)  |
     *				   ^                |
     *				   |                |
     *				   +----------------+
     *
     *   + All metaclasses are instances of the class `Class'.
     */


    rb_define_method(cKernel, "nil?", krn_nil_p, 0);
    rb_define_method(cKernel, "==", krn_equal, 1);
    rb_define_alias(cKernel, "equal?", "==");
    rb_define_alias(cKernel, "=~", "==");

    rb_define_method(cKernel, "hash", krn_id, 0);
    rb_define_method(cKernel, "id", krn_id, 0);
    rb_define_method(cKernel, "type", krn_type, 0);

    rb_define_method(cKernel, "clone", krn_clone, 0);
    rb_define_method(cKernel, "dup", krn_dup, 0);

    rb_define_method(cKernel, "to_a", krn_to_a, 0);
    rb_define_method(cKernel, "to_s", krn_to_s, 0);
    rb_define_method(cKernel, "inspect", krn_inspect, 0);

    rb_define_private_method(cKernel, "sprintf", f_sprintf, -1);
    rb_define_alias(cKernel, "format", "sprintf");

    rb_define_private_method(cObject, "initialize", obj_initialize, -1);
    rb_define_private_method(cObject, "singleton_method_added", obj_s_added, 1);

    rb_define_method(cObject, "is_instance_of?", obj_is_instance_of, 1);
    rb_define_method(cObject, "is_kind_of?", obj_is_kind_of, 1);
    rb_define_method(cObject, "inspect", obj_inspect, 0);

    rb_define_method(cModule, "to_s", mod_to_s, 0);
    rb_define_method(cModule, "clone", mod_clone, 0);
    rb_define_private_method(cModule, "attr", mod_attr, -1);
    rb_define_private_method(cModule, "public_attr", mod_public_attr, -1);
    rb_define_private_method(cModule, "private_attr", mod_private_attr, -1);

    rb_define_method(cClass, "new", mod_new, -1);

    cNil = rb_define_class("Nil", cKernel);
    rb_define_method(cNil, "to_s", nil_to_s, 0);
    rb_define_method(cNil, "type", nil_type, 0);

    rb_define_method(cNil, "nil?", nil_nil_p, 0);

    /* default addition */
    rb_define_method(cNil, "+", nil_plus, 1);

    cData = rb_define_class("Data", cKernel);

    eq = rb_intern("==");

    Qself = TopSelf = obj_alloc(cObject);
    rb_define_singleton_method(TopSelf, "to_s", main_to_s, 0);

    TRUE = obj_alloc(cObject);
    rb_define_singleton_method(TRUE, "to_s", true_to_s, 0);
    rb_define_const(cKernel, "TRUE", TRUE);
    rb_define_const(cKernel, "FALSE", FALSE);

    init = rb_intern("initialize");
}
