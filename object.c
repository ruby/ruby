/************************************************

  object.c -

  $Author: matz $
  $Date: 1996/12/25 08:54:49 $
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"
#include <stdio.h>

VALUE cKernel;
VALUE cObject;
VALUE cModule;
VALUE cClass;
VALUE cFixnum;
VALUE cData;

static VALUE cNil;
static VALUE cTrue;
static VALUE cFalse;

struct st_table *new_idhash();

VALUE f_sprintf();

VALUE obj_alloc();

static ID eq, eql;
static ID inspect;

int
rb_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    VALUE result;

    result = rb_funcall(obj1, eq, 1, obj2);
    if (result == FALSE || NIL_P(result))
	return FALSE;
    return TRUE;
}

int
rb_eql(obj1, obj2)
    VALUE obj1, obj2;
{
    return rb_funcall(obj1, eql, 1, obj2);
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

char *rb_class2path();

static VALUE
krn_type(obj)
    struct RBasic *obj;
{
    return rb_class_path(obj->class);
}

static VALUE
krn_clone(obj)
    VALUE obj;
{
    VALUE clone;

    if (TYPE(obj) != T_OBJECT) {
	TypeError("can't clone %s", rb_class2name(CLASS_OF(obj)));
    }

    clone = obj_alloc(RBASIC(obj)->class);
    if (ROBJECT(obj)->iv_tbl) {
	ROBJECT(clone)->iv_tbl = st_copy(ROBJECT(obj)->iv_tbl);
    }
    RBASIC(clone)->class = singleton_class_clone(RBASIC(obj)->class);
    RBASIC(clone)->flags = RBASIC(obj)->flags;

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
rb_inspect(obj)
    VALUE obj;
{
    return rb_funcall(obj, inspect, 0, 0);
}

static VALUE
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

    /* need not to show internal data */
    if (TYPE(value) == T_DATA) return ST_CONTINUE;
    if (str->ptr[0] == '-') {
	str->ptr[0] = '#';
	str_cat(str, ": ", 2);
    }
    else {
	str_cat(str, ", ", 2);
    }
    ivname = rb_id2name(id);
    str_cat(str, ivname, strlen(ivname));
    str_cat(str, "=", 1);
    if (TYPE(value) == T_OBJECT) {
	str2 = krn_to_s(value);
    }
    else {
	str2 = rb_inspect(value);
    }
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
obj_inspect(obj)
    struct RObject *obj;
{
    if (TYPE(obj) == T_OBJECT && obj->iv_tbl) {
	VALUE str;
	char buf[256];

	sprintf(buf, "-<%s", rb_class2name(CLASS_OF(obj)));
	str = str_new2(buf);
	st_foreach(obj->iv_tbl, inspect_i, str);
	str_cat(str, ">", 1);
	if (RSTRING(str)->ptr[0] == '-') /* no instance-var */
	  return krn_inspect(obj);

	return str;
    }
    return krn_inspect(obj);
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
	TypeError("class or module required");
    }

    while (FL_TEST(class, FL_SINGLETON)) {
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
	TypeError("class or module required");
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
    return str_new2("");
}

static VALUE
nil_inspect(obj)
    VALUE obj;
{
    return str_new2("nil");
}

static VALUE
nil_type(obj)
    VALUE obj;
{
    return str_new2("Nil");
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
	TypeError("tried to add %s(%s) to nil",
		  RSTRING(obj_as_string(y))->ptr, rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
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
    return str_new2("TRUE");
}

static VALUE
true_type(obj)
    VALUE obj;
{
    return str_new2("TRUE");
}

static VALUE
false_to_s(obj)
    VALUE obj;
{
    return str_new2("FALSE");
}

static VALUE
false_type(obj)
    VALUE obj;
{
    return str_new2("FALSE");
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
mod_clone(module)
    struct RClass *module;
{
    NEWOBJ(clone, struct RClass);
    OBJSETUP(clone, CLASS_OF(module), TYPE(module));

    clone->super = module->super;
    clone->m_tbl = st_copy(module->m_tbl);

    return (VALUE)clone;
}

static VALUE
mod_to_s(class)
    VALUE class;
{
    return rb_class_path(class);
}

VALUE class_s_new();		/* moved to eval.c */

static VALUE
class_superclass(class)
    struct RClass *class;
{
    struct RClass *super = class->super;

    while (TYPE(super) == T_ICLASS)
	super = super->super;

    return (VALUE)super;
}

ID
rb_to_id(name)
    VALUE name;
{
    if (TYPE(name) == T_STRING) {
	return rb_intern(RSTRING(name)->ptr);
    }
    Check_Type(name, T_FIXNUM);
    return FIX2INT(name);
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

static VALUE
f_integer(obj, arg)
    VALUE obj, arg;
{
    int i;

    switch (TYPE(arg)) {
      case T_FLOAT:
	if (RFLOAT(arg)->value <= (double)FIXNUM_MAX
	    && RFLOAT(arg)->value >= (double)FIXNUM_MIN) {
	    i = (int)RFLOAT(arg)->value;
	    break;
	}
	return dbl2big(RFLOAT(arg)->value);

      case T_BIGNUM:
	return arg;

      case T_STRING:
	return str2inum(RSTRING(arg)->ptr, 0);

      default:
	i = NUM2INT(arg);
    }
    return INT2NUM(i);
}

static VALUE
to_flo(val)
    VALUE val;
{
    return rb_funcall(val, rb_intern("to_f"), 0);
}

static VALUE
fail_to_flo(val)
    VALUE val;
{
    TypeError("failed to convert %s into Float", rb_class2name(CLASS_OF(val)));
}

double big2dbl();

VALUE
f_float(obj, arg)
    VALUE obj, arg;
{

    switch (TYPE(arg)) {
      case T_FLOAT:
	return arg;

      case T_BIGNUM:
	return float_new(big2dbl(arg));

      default:
	return rb_rescue(to_flo, arg, fail_to_flo, arg);
    }
}

static VALUE
f_string(obj, arg)
    VALUE obj, arg;
{
    return rb_funcall(arg, rb_intern("to_s"), 0);
}

static VALUE
f_array(obj, arg)
    VALUE obj, arg;
{
    return rb_funcall(arg, rb_intern("to_a"), 0);
}

static VALUE
boot_defclass(name, super)
    char *name;
    VALUE super;
{
    extern st_table *rb_class_tbl;
    struct RClass *obj = (struct RClass*)class_new(super);
    ID id = rb_intern(name);

    rb_name_class(obj, id);
    st_add_direct(rb_class_tbl, id, obj);
    return (VALUE)obj;
}

VALUE
rb_class_of(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return cFixnum;
    if (obj == Qnil) return cNil;
    if (obj == FALSE) return cFalse;
    if (obj == TRUE) return cTrue;

    return RBASIC(obj)->class;
}

int
rb_type(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return T_FIXNUM;
    if (obj == Qnil) return T_NIL;
    if (obj == FALSE) return T_FALSE;
    if (obj == TRUE) return T_TRUE;

    return BUILTIN_TYPE(obj);
}

int
rb_special_const_p(obj)
    VALUE obj;
{
    if (FIXNUM_P(obj)) return TRUE;
    if (obj == Qnil) return TRUE;
    if (obj == FALSE) return TRUE;
    if (obj == TRUE) return TRUE;

    return FALSE;
}

VALUE TopSelf;

void
Init_Object()
{
    VALUE metaclass;

    cKernel = boot_defclass("kernel", 0);
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
     *                     +------------------------+
     *                     |                        |
     *      kernel----->(kernel)                    |
     *       ^  ^         ^  ^                      |
     *       |  |         |  |                      |
     *   +---+  +----+    |  +---+                  |
     *   |     +-----|----+      |                  |
     *   |     |     |           |                  |
     *  Nil->(Nil) Object---->(Object)              |
     *              ^  ^        ^  ^                |
     *              |  |        |  |                |
     *              |  |  +-----+  +---------+      |
     *              |  |  |                  |      |
     *              |  +-----------+         |      |
     *              |     |        |         |      |
     *       +------+     |     Module--->(Module)  |
     *       |            |        ^         ^      |
     *  OtherClass-->(OtherClass)  |         |      |
     *                           Class---->(Class)  |
     *                             ^                |
     *                             |                |
     *                             +----------------+
     *
     *   + All metaclasses are instances of the class `Class'.
     */

    rb_define_method(cKernel, "nil?", krn_nil_p, 0);
    rb_define_method(cKernel, "==", krn_equal, 1);
    rb_define_alias(cKernel, "equal?", "==");
    rb_define_alias(cKernel, "===", "==");
    rb_define_alias(cKernel, "=~", "==");

    rb_define_method(cKernel, "eql?", rb_equal, 1);

    rb_define_method(cKernel, "hash", krn_id, 0);
    rb_define_method(cKernel, "id", krn_id, 0);
    rb_define_method(cKernel, "type", krn_type, 0);

    rb_define_method(cKernel, "clone", krn_clone, 0);
    rb_define_method(cKernel, "dup", krn_dup, 0);

    rb_define_method(cKernel, "to_a", krn_to_a, 0);
    rb_define_method(cKernel, "to_s", krn_to_s, 0);
    rb_define_method(cKernel, "inspect", krn_inspect, 0);

    rb_define_method(cKernel, "instance_of?", obj_is_instance_of, 1);
    rb_define_method(cKernel, "kind_of?", obj_is_kind_of, 1);
    rb_define_method(cKernel, "is_a?", obj_is_kind_of, 1);

    rb_define_private_method(cKernel, "sprintf", f_sprintf, -1);
    rb_define_alias(cKernel, "format", "sprintf");

    rb_define_private_method(cKernel, "Integer", f_integer, 1);
    rb_define_private_method(cKernel, "Float", f_float, 1);

    rb_define_private_method(cKernel, "String", f_string, 1);
    rb_define_private_method(cKernel, "Array", f_array, 1);

    cNil = rb_define_class("nil", cKernel);
    rb_define_method(cNil, "type", nil_type, 0);
    rb_define_method(cNil, "to_s", nil_to_s, 0);
    rb_define_method(cNil, "inspect", nil_inspect, 0);

    rb_define_method(cNil, "nil?", nil_nil_p, 0);

    /* default addition */
    rb_define_method(cNil, "+", nil_plus, 1);

    rb_define_private_method(cObject, "initialize", obj_initialize, -1);
    rb_define_private_method(cObject, "singleton_method_added", obj_s_added, 1);

    rb_define_method(cObject, "inspect", obj_inspect, 0);

    rb_define_method(cModule, "to_s", mod_to_s, 0);
    rb_define_method(cModule, "clone", mod_clone, 0);
    rb_define_private_method(cModule, "attr", mod_attr, -1);
    rb_define_private_method(cModule, "public_attr", mod_public_attr, -1);
    rb_define_private_method(cModule, "private_attr", mod_private_attr, -1);
    rb_define_private_method(cModule, "object_extended", obj_s_added, 1);

    rb_define_method(cClass, "new", class_s_new, -1);
    rb_define_method(cClass, "superclass", class_superclass, -1);

    cData = rb_define_class("Data", cKernel);

    TopSelf = obj_alloc(cObject);
    rb_define_singleton_method(TopSelf, "to_s", main_to_s, 0);

    cTrue = rb_define_class("true", cKernel);
    rb_define_method(cTrue, "to_s", true_to_s, 0);
    rb_define_method(cTrue, "type", true_type, 0);
    rb_define_global_const("TRUE", TRUE);

    cFalse = rb_define_class("false", cKernel);
    rb_define_method(cFalse, "to_s", false_to_s, 0);
    rb_define_method(cFalse, "type", false_type, 0);
    rb_define_global_const("FALSE", FALSE);

    eq = rb_intern("==");
    eql = rb_intern("eql?");
    inspect = rb_intern("inspect");
}
