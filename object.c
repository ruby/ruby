/************************************************

  object.c -

  $Author$
  $Date$
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"
#include <stdio.h>

VALUE rb_mKernel;
VALUE rb_cObject;
VALUE rb_cModule;
VALUE rb_cClass;
VALUE rb_cData;

VALUE rb_cNilClass;
VALUE rb_cTrueClass;
VALUE rb_cFalseClass;

VALUE rb_f_sprintf();
VALUE rb_obj_alloc();

static ID eq, eql;
static ID inspect;

VALUE
rb_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    VALUE result;

    result = rb_funcall(obj1, eq, 1, obj2);
    if (result == Qfalse || NIL_P(result))
	return Qfalse;
    return Qtrue;
}

int
rb_eql(obj1, obj2)
    VALUE obj1, obj2;
{
    return rb_funcall(obj1, eql, 1, obj2);
}

VALUE
rb_obj_equal(obj1, obj2)
    VALUE obj1, obj2;
{
    if (obj1 == obj2) return Qtrue;
    return Qfalse;
}

static VALUE
rb_any_to_a(obj)
    VALUE obj;
{
    return rb_ary_new3(1, obj);
}

static VALUE
rb_obj_hash(obj)
    VALUE obj;
{
    return (long)obj|FIXNUM_FLAG;
}

static VALUE
rb_obj_id(obj)
    VALUE obj;
{
    return INT2NUM((long)obj);
}

static VALUE
rb_obj_type(obj)
    VALUE obj;
{
    VALUE cl = CLASS_OF(obj);

    while (FL_TEST(cl, FL_SINGLETON) || TYPE(cl) == T_ICLASS) {
	cl = RCLASS(cl)->super;
    }
    return cl;
}

static VALUE
rb_obj_clone(obj)
    VALUE obj;
{
    VALUE clone;

    if (TYPE(obj) != T_OBJECT) {
	rb_raise(rb_eTypeError, "can't clone %s", rb_class2name(CLASS_OF(obj)));
    }
    clone = rb_obj_alloc(RBASIC(obj)->klass);
    CLONESETUP(clone,obj);
    if (ROBJECT(obj)->iv_tbl) {
	ROBJECT(clone)->iv_tbl = st_copy(ROBJECT(obj)->iv_tbl);
	RBASIC(clone)->klass = rb_singleton_class_clone(RBASIC(obj)->klass);
	RBASIC(clone)->flags = RBASIC(obj)->flags;
    }

    return clone;
}

static VALUE
rb_obj_dup(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("clone"), 0, 0);
}

VALUE
rb_any_to_s(obj)
    VALUE obj;
{
    char *s;
    char *cname = rb_class2name(CLASS_OF(obj));

    s = ALLOCA_N(char, strlen(cname)+6+16+1); /* 6:tags 16:addr 1:eos */
    sprintf(s, "#<%s:0x%x>", cname, obj);
    return rb_str_new2(s);
}

VALUE
rb_inspect(obj)
    VALUE obj;
{
    return rb_obj_as_string(rb_funcall(obj, inspect, 0, 0));
}

static int
inspect_i(id, value, str)
    ID id;
    VALUE value;
    VALUE str;
{
    VALUE str2;
    char *ivname;

    /* need not to show internal data */
    if (CLASS_OF(value) == 0) return ST_CONTINUE;
    if (RSTRING(str)->ptr[0] == '-') {
	RSTRING(str)->ptr[0] = '#';
	rb_str_cat(str, ": ", 2);
    }
    else {
	rb_str_cat(str, ", ", 2);
    }
    ivname = rb_id2name(id);
    rb_str_cat(str, ivname, strlen(ivname));
    rb_str_cat(str, "=", 1);
    if (TYPE(value) == T_OBJECT) {
	str2 = rb_any_to_s(value);
    }
    else {
	str2 = rb_inspect(value);
    }
    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
rb_obj_inspect(obj)
    VALUE obj;
{
    if (TYPE(obj) == T_OBJECT
	&& ROBJECT(obj)->iv_tbl
	&& ROBJECT(obj)->iv_tbl->num_entries > 0) {
	VALUE str;
	char *b;

	str = rb_str_new2("-<");
	b = rb_class2name(CLASS_OF(obj));
	rb_str_cat(str, b, strlen(b));
	st_foreach(ROBJECT(obj)->iv_tbl, inspect_i, str);
	rb_str_cat(str, ">", 1);

	return str;
    }
    return rb_funcall(obj, rb_intern("to_s"), 0, 0);
}

VALUE
rb_obj_is_instance_of(obj, c)
    VALUE obj, c;
{
    VALUE cl;

    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
	break;

      case T_NIL:
	if (NIL_P(obj)) return Qtrue;
	return Qfalse;

      case T_FALSE:
	if (obj) return Qfalse;
	return Qtrue;

      case T_TRUE:
	if (obj) return Qtrue;
	return Qfalse;

      default:
	rb_raise(rb_eTypeError, "class or module required");
    }

    cl = CLASS_OF(obj);
    while (FL_TEST(cl, FL_SINGLETON) || TYPE(cl) == T_ICLASS) {
	cl = RCLASS(cl)->super;
    }
    if (c == cl) return Qtrue;
    return Qfalse;
}

VALUE
rb_obj_is_kind_of(obj, c)
    VALUE obj, c;
{
    VALUE cl = CLASS_OF(obj);

    switch (TYPE(c)) {
      case T_MODULE:
      case T_CLASS:
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

static VALUE
rb_obj_dummy(obj)
    VALUE obj;
{
    return Qnil;
}

static VALUE
nil_to_i(obj)
    VALUE obj;
{
    return INT2FIX(0);
}

static VALUE
nil_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("");
}

static VALUE
nil_to_a(obj)
    VALUE obj;
{
    return rb_ary_new2(0);
}

static VALUE
nil_inspect(obj)
    VALUE obj;
{
    return rb_str_new2("nil");
}

static VALUE
nil_type(obj)
    VALUE obj;
{
    return rb_cNilClass;
}

#ifdef NIL_PLUS
static VALUE
nil_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_NIL:
      case T_FIXNUM:
      case T_FLOAT:
      case T_BIGNUM:
      case T_STRING:
      case T_ARRAY:
	return y;
      default:
	rb_raise(rb_eTypeError, "tried to add %s(%s) to nil",
		 STR2CSTR(rb_inspect(y)),
		 rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
}
#endif

static VALUE
main_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("main");
}

static VALUE
true_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("true");
}

static VALUE
true_to_i(obj)
    VALUE obj;
{
    return INT2FIX(1);
}

static VALUE
true_type(obj)
    VALUE obj;
{
    return rb_cTrueClass;
}

static VALUE
true_and(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

static VALUE
true_or(obj, obj2)
    VALUE obj, obj2;
{
    return Qtrue;
}

static VALUE
true_xor(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qfalse:Qtrue;
}

static VALUE
false_to_s(obj)
    VALUE obj;
{
    return rb_str_new2("false");
}

static VALUE
false_to_i(obj)
    VALUE obj;
{
    return INT2FIX(0);
}

static VALUE
false_type(obj)
    VALUE obj;
{
    return rb_cFalseClass;
}

static VALUE
false_and(obj, obj2)
    VALUE obj, obj2;
{
    return Qfalse;
}

static VALUE
false_or(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

static VALUE
false_xor(obj, obj2)
    VALUE obj, obj2;
{
    return RTEST(obj2)?Qtrue:Qfalse;
}

static VALUE
rb_true(obj)
    VALUE obj;
{
    return Qtrue;
}

static VALUE
rb_false(obj)
    VALUE obj;
{
    return Qfalse;
}

VALUE
rb_obj_alloc(klass)
    VALUE klass;
{
    NEWOBJ(obj, struct RObject);
    OBJSETUP(obj, klass, T_OBJECT);
    obj->iv_tbl = 0;

    return (VALUE)obj;
}

static VALUE
rb_mod_clone(module)
    VALUE module;
{
    NEWOBJ(clone, struct RClass);
    OBJSETUP(clone, CLASS_OF(module), TYPE(module));

    clone->super = RCLASS(module)->super;
    clone->iv_tbl = 0;
    clone->m_tbl = 0;		/* avoid GC crashing  */
    clone->iv_tbl = st_copy(RCLASS(module)->iv_tbl);
    clone->m_tbl = st_copy(RCLASS(module)->m_tbl);

    return (VALUE)clone;
}

static VALUE
rb_mod_to_s(klass)
    VALUE klass;
{
    return rb_str_dup(rb_class_path(klass));
}

static VALUE
rb_mod_eqq(mod, arg)
    VALUE mod, arg;
{
    return rb_obj_is_kind_of(arg, mod);
}

static VALUE
rb_mod_le(mod, arg)
    VALUE mod, arg;
{
    switch (TYPE(arg)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	rb_raise(rb_eTypeError, "compared with non class/module");
    }

    while (mod) {
	if (RCLASS(mod)->m_tbl == RCLASS(arg)->m_tbl)
	    return Qtrue;
	mod = RCLASS(mod)->super;
    }

    return Qfalse;
}

static VALUE
rb_mod_lt(mod, arg)
    VALUE mod, arg;
{
    if (mod == arg) return Qfalse;
    return rb_mod_le(mod, arg);
}

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

    return rb_mod_lt(arg, mod);
}

static VALUE
rb_mod_gt(mod, arg)
    VALUE mod, arg;
{
    if (mod == arg) return Qfalse;
    return rb_mod_ge(mod, arg);
}

static VALUE
rb_mod_cmp(mod, arg)
    VALUE mod, arg;
{
    if (mod == arg) return INT2FIX(0);

    switch (TYPE(arg)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	rb_raise(rb_eTypeError, "<=> requires Class or Module (%s given)",
		 rb_class2name(CLASS_OF(arg)));
	break;
    }

    if (rb_mod_le(mod, arg)) {
	return INT2FIX(-1);
    }
    return INT2FIX(1);
}

static VALUE
rb_module_s_new(klass)
{
    VALUE mod = rb_module_new();

    RBASIC(mod)->klass = klass;
    rb_obj_call_init(mod);
    return mod;
}

VALUE rb_class_new_instance();

static VALUE
rb_class_s_new(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE super, klass;

    if (rb_scan_args(argc, argv, "01", &super) == 0) {
	super = rb_cObject;
    }
    Check_Type(super, T_CLASS);
    if (FL_TEST(super, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't make subclass of virtual class");
    }
    klass = rb_class_new(super);
    /* make metaclass */
    RBASIC(klass)->klass = rb_singleton_class_new(RBASIC(super)->klass);
    rb_singleton_class_attached(RBASIC(klass)->klass, klass);
    rb_obj_call_init(klass);

    return klass;
}

static VALUE
rb_class_s_inherited()
{
    rb_raise(rb_eTypeError, "can't make subclass of Class");
}

VALUE rb_mod_name();
VALUE rb_mod_included_modules();
VALUE rb_mod_ancestors();
VALUE rb_class_instance_methods();
VALUE rb_class_protected_instance_methods();
VALUE rb_class_private_instance_methods();

static VALUE
rb_class_superclass(klass)
    VALUE klass;
{
    VALUE super = RCLASS(klass)->super;

    while (TYPE(super) == T_ICLASS) {
	super = RCLASS(super)->super;
    }
    if (!super) {
	return Qnil;
    }
    return super;
}

ID
rb_to_id(name)
    VALUE name;
{
    if (TYPE(name) == T_STRING) {
	return rb_intern(RSTRING(name)->ptr);
    }
    Check_Type(name, T_FIXNUM);
    return FIX2UINT(name);
}

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

VALUE rb_mod_constants();

static VALUE
rb_mod_const_get(mod, name)
    VALUE mod, name;
{
    return rb_const_get_at(mod, rb_to_id(name));
}

static VALUE
rb_mod_const_set(mod, name, value)
    VALUE mod, name, value;
{
    rb_const_set(mod, rb_to_id(name), value);
    return value;
}

static VALUE
rb_mod_const_defined(mod, name)
    VALUE mod, name;
{
    return rb_const_defined_at(mod, rb_to_id(name));
}

static VALUE
rb_obj_methods(obj)
    VALUE obj;
{
    VALUE argv[1];

    argv[0] = Qtrue;
    return rb_class_instance_methods(1, argv, CLASS_OF(obj));
}

VALUE rb_obj_singleton_methods();

static VALUE
rb_obj_protected_methods(obj)
    VALUE obj;
{
    VALUE argv[1];

    argv[0] = Qtrue;
    return rb_class_protected_instance_methods(1, argv, CLASS_OF(obj));
}

static VALUE
rb_obj_private_methods(obj)
    VALUE obj;
{
    VALUE argv[1];

    argv[0] = Qtrue;
    return rb_class_private_instance_methods(1, argv, CLASS_OF(obj));
}

static VALUE
rb_f_integer(obj, arg)
    VALUE obj, arg;
{
    long i;

    switch (TYPE(arg)) {
      case T_FLOAT:
	if (RFLOAT(arg)->value <= (double)FIXNUM_MAX
	    && RFLOAT(arg)->value >= (double)FIXNUM_MIN) {
	    i = (long)RFLOAT(arg)->value;
	    break;
	}
	return rb_dbl2big(RFLOAT(arg)->value);

      case T_BIGNUM:
	return arg;

      case T_STRING:
	return rb_str2inum(RSTRING(arg)->ptr, 0);

      case T_NIL:
	return INT2FIX(0);

      default:
	i = NUM2LONG(arg);
    }
    return INT2NUM(i);
}

VALUE
rb_Integer(val)
    VALUE val;
{
    return rb_f_integer(Qnil, val);
}

struct arg_to {
    VALUE val;
    char *s;
};

static VALUE
to_type(arg)
    struct arg_to *arg;
{
    return rb_funcall(arg->val, rb_intern(arg->s), 0);
}

static VALUE
fail_to_type(arg)
    struct arg_to *arg;
{
    rb_raise(rb_eTypeError, "failed to convert %s into %s",
	     NIL_P(arg->val) ? "nil" :
	     arg->val == Qtrue ? "true" :
	     arg->val == Qfalse ? "false" :
	     rb_class2name(CLASS_OF(arg->val)), 
	     arg->s);
}

VALUE
rb_convert_type(val, type, tname, method)
    VALUE val;
    int type;
    char *tname, *method;
{
    struct arg_to arg1, arg2;

    if (TYPE(val) == type) return val;
    arg1.val = arg2.val = val;
    arg1.s = method;
    arg2.s = tname;
    val = rb_rescue(to_type, (VALUE)&arg1, fail_to_type, (VALUE)&arg2);
    Check_Type(val, type);
    return val;
}

double rb_big2dbl _((VALUE));

static VALUE
rb_f_float(obj, arg)
    VALUE obj, arg;
{
    switch (TYPE(arg)) {
      case T_FIXNUM:
	return rb_float_new((double)FIX2LONG(arg));

      case T_FLOAT:
	return arg;

      case T_BIGNUM:
	return rb_float_new(rb_big2dbl(arg));

      default:
	return rb_convert_type(arg, T_FLOAT, "Float", "to_f");
    }
}

VALUE
rb_Float(val)
    VALUE val;
{
    return rb_f_float(Qnil, val);
}

double
rb_num2dbl(val)
    VALUE val;
{
    VALUE v = rb_Float(val);
    return RFLOAT(v)->value;
}

static VALUE
rb_f_string(obj, arg)
    VALUE obj, arg;
{
    return rb_convert_type(arg, T_STRING, "String", "to_s");
}

char*
rb_str2cstr(str, len)
    VALUE str;
    int *len;
{
    if (TYPE(str) != T_STRING) {
	str = rb_str_to_str(str);
    }
    if (len) *len = RSTRING(str)->len;
    return RSTRING(str)->ptr;
}

VALUE
rb_String(val)
    VALUE val;
{
    return rb_f_string(Qnil, val);
}

static VALUE
rb_f_array(obj, arg)
    VALUE obj, arg;
{
    if (TYPE(arg) == T_ARRAY) return arg;
    arg = rb_funcall(arg, rb_intern("to_a"), 0);
    if (TYPE(arg) != T_ARRAY) {
	rb_raise(rb_eTypeError, "`to_a' did not return Array");
    }
    return arg;
}

VALUE
rb_Array(val)
    VALUE val;
{
    return rb_f_array(Qnil, val);
}

static VALUE
boot_defclass(name, super)
    char *name;
    VALUE super;
{
    extern st_table *rb_class_tbl;
    VALUE obj = rb_class_new(super);
    ID id = rb_intern(name);

    rb_name_class(obj, id);
    st_add_direct(rb_class_tbl, id, obj);
    return obj;
}

VALUE rb_top_self;

void
Init_Object()
{
    VALUE metaclass;

    rb_cObject = boot_defclass("Object", 0);
    rb_cModule = boot_defclass("Module", rb_cObject);
    rb_cClass =  boot_defclass("Class",  rb_cModule);

    metaclass = RBASIC(rb_cObject)->klass = rb_singleton_class_new(rb_cClass);
    rb_singleton_class_attached(metaclass, rb_cObject);
    metaclass = RBASIC(rb_cModule)->klass = rb_singleton_class_new(metaclass);
    rb_singleton_class_attached(metaclass, rb_cModule);
    metaclass = RBASIC(rb_cClass)->klass = rb_singleton_class_new(metaclass);
    rb_singleton_class_attached(metaclass, rb_cClass);

    rb_mKernel = rb_define_module("Kernel");
    rb_include_module(rb_cObject, rb_mKernel);
    rb_define_private_method(rb_cClass, "inherited", rb_obj_dummy, 1);

    /*
     * Ruby's Class Hierarchy Chart
     *
     *                           +------------------+
     *                           |                  |
     *             Object---->(Object)              |
     *              ^  ^        ^  ^                |
     *              |  |        |  |                |
     *              |  |  +-----+  +---------+      |
     *              |  |  |                  |      |
     *              |  +-----------+         |      |
     *              |     |        |         |      |
     *       +------+     |     Module--->(Module)  |
     *       |            |        ^         ^      |
     *  OtherClass-->(OtherClass)  |         |      |
     *                             |         |      |
     *                           Class---->(Class)  |
     *                             ^                |
     *                             |                |
     *                             +----------------+
     *
     *   + All metaclasses are instances of the class `Class'.
     */

    rb_define_method(rb_mKernel, "nil?", rb_false, 0);
    rb_define_method(rb_mKernel, "==", rb_obj_equal, 1);
    rb_define_alias(rb_mKernel, "equal?", "==");
    rb_define_alias(rb_mKernel, "===", "==");
    rb_define_method(rb_mKernel, "=~", rb_false, 1);

    rb_define_method(rb_mKernel, "eql?", rb_obj_equal, 1);

    rb_define_method(rb_mKernel, "hash", rb_obj_hash, 0);
    rb_define_method(rb_mKernel, "id", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "__id__", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "type", rb_obj_type, 0);

    rb_define_method(rb_mKernel, "clone", rb_obj_clone, 0);
    rb_define_method(rb_mKernel, "dup", rb_obj_dup, 0);

    rb_define_method(rb_mKernel, "to_a", rb_any_to_a, 0);
    rb_define_method(rb_mKernel, "to_s", rb_any_to_s, 0);
    rb_define_method(rb_mKernel, "inspect", rb_obj_inspect, 0);
    rb_define_method(rb_mKernel, "methods", rb_obj_methods, 0);
    rb_define_method(rb_mKernel, "public_methods", rb_obj_methods, 0);
    rb_define_method(rb_mKernel, "singleton_methods", rb_obj_singleton_methods, 0);
    rb_define_method(rb_mKernel, "protected_methods", rb_obj_protected_methods, 0);
    rb_define_method(rb_mKernel, "private_methods", rb_obj_private_methods, 0);
    rb_define_method(rb_mKernel, "instance_variables", rb_obj_instance_variables, 0);
    rb_define_private_method(rb_mKernel, "remove_instance_variable",
			     rb_obj_remove_instance_variable, 0);

    rb_define_method(rb_mKernel, "instance_of?", rb_obj_is_instance_of, 1);
    rb_define_method(rb_mKernel, "kind_of?", rb_obj_is_kind_of, 1);
    rb_define_method(rb_mKernel, "is_a?", rb_obj_is_kind_of, 1);

    rb_define_global_function("sprintf", rb_f_sprintf, -1);
    rb_define_alias(rb_mKernel, "format", "sprintf");

    rb_define_global_function("Integer", rb_f_integer, 1);
    rb_define_global_function("Float", rb_f_float, 1);

    rb_define_global_function("String", rb_f_string, 1);
    rb_define_global_function("Array", rb_f_array, 1);

    rb_cNilClass = rb_define_class("NilClass", rb_cObject);
    rb_define_method(rb_cNilClass, "type", nil_type, 0);
    rb_define_method(rb_cNilClass, "to_i", nil_to_i, 0);
    rb_define_method(rb_cNilClass, "to_s", nil_to_s, 0);
    rb_define_method(rb_cNilClass, "to_a", nil_to_a, 0);
    rb_define_method(rb_cNilClass, "inspect", nil_inspect, 0);

    rb_define_method(rb_cNilClass, "nil?", rb_true, 0);
    rb_undef_method(CLASS_OF(rb_cNilClass), "new");
    rb_define_global_const("NIL", Qnil);

    /* default addition */
#ifdef NIL_PLUS
    rb_define_method(rb_cNilClass, "+", nil_plus, 1);
#endif

    rb_define_global_function("initialize", rb_obj_dummy, -1);
    rb_define_global_function("singleton_method_added", rb_obj_dummy, 1);

    rb_define_method(rb_cModule, "===", rb_mod_eqq, 1);
    rb_define_method(rb_cModule, "<=>",  rb_mod_cmp, 1);
    rb_define_method(rb_cModule, "<",  rb_mod_lt, 1);
    rb_define_method(rb_cModule, "<=", rb_mod_le, 1);
    rb_define_method(rb_cModule, ">",  rb_mod_gt, 1);
    rb_define_method(rb_cModule, ">=", rb_mod_ge, 1);
    rb_define_method(rb_cModule, "clone", rb_mod_clone, 0);
    rb_define_method(rb_cModule, "to_s", rb_mod_to_s, 0);
    rb_define_method(rb_cModule, "included_modules", rb_mod_included_modules, 0);
    rb_define_method(rb_cModule, "name", rb_mod_name, 0);
    rb_define_method(rb_cModule, "ancestors", rb_mod_ancestors, 0);

    rb_define_private_method(rb_cModule, "attr", rb_mod_attr, -1);
    rb_define_private_method(rb_cModule, "attr_reader", rb_mod_attr_reader, -1);
    rb_define_private_method(rb_cModule, "attr_writer", rb_mod_attr_writer, -1);
    rb_define_private_method(rb_cModule, "attr_accessor", rb_mod_attr_accessor, -1);

    rb_define_singleton_method(rb_cModule, "new", rb_module_s_new, 0);
    rb_define_method(rb_cModule, "instance_methods", rb_class_instance_methods, -1);
    rb_define_method(rb_cModule, "public_instance_methods", rb_class_instance_methods, -1);
    rb_define_method(rb_cModule, "protected_instance_methods", rb_class_protected_instance_methods, -1);
    rb_define_method(rb_cModule, "private_instance_methods", rb_class_private_instance_methods, -1);

    rb_define_method(rb_cModule, "constants", rb_mod_constants, 0);
    rb_define_method(rb_cModule, "const_get", rb_mod_const_get, 1);
    rb_define_method(rb_cModule, "const_set", rb_mod_const_set, 2);
    rb_define_method(rb_cModule, "const_defined?", rb_mod_const_defined, 1);
    rb_define_private_method(rb_cModule, "remove_const", rb_mod_remove_const, 1);
    rb_define_private_method(rb_cModule, "method_added", rb_obj_dummy, 1);

    rb_define_method(rb_cClass, "new", rb_class_new_instance, -1);
    rb_define_method(rb_cClass, "superclass", rb_class_superclass, 0);
    rb_define_singleton_method(rb_cClass, "new", rb_class_s_new, -1);
    rb_undef_method(rb_cClass, "extend_object");
    rb_undef_method(rb_cClass, "append_features");
    rb_define_singleton_method(rb_cClass, "inherited", rb_class_s_inherited, 1);

    rb_cData = rb_define_class("Data", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cData), "new");

    rb_top_self = rb_obj_alloc(rb_cObject);
    rb_global_variable(&rb_top_self);
    rb_define_singleton_method(rb_top_self, "to_s", main_to_s, 0);

    rb_cTrueClass = rb_define_class("TrueClass", rb_cObject);
    rb_define_method(rb_cTrueClass, "to_s", true_to_s, 0);
    rb_define_method(rb_cTrueClass, "to_i", true_to_i, 0);
    rb_define_method(rb_cTrueClass, "type", true_type, 0);
    rb_define_method(rb_cTrueClass, "&", true_and, 1);
    rb_define_method(rb_cTrueClass, "|", true_or, 1);
    rb_define_method(rb_cTrueClass, "^", true_xor, 1);
    rb_undef_method(CLASS_OF(rb_cTrueClass), "new");
    rb_define_global_const("TRUE", Qtrue);

    rb_cFalseClass = rb_define_class("FalseClass", rb_cObject);
    rb_define_method(rb_cFalseClass, "to_s", false_to_s, 0);
    rb_define_method(rb_cFalseClass, "to_i", false_to_i, 0);
    rb_define_method(rb_cFalseClass, "type", false_type, 0);
    rb_define_method(rb_cFalseClass, "&", false_and, 1);
    rb_define_method(rb_cFalseClass, "|", false_or, 1);
    rb_define_method(rb_cFalseClass, "^", false_xor, 1);
    rb_undef_method(CLASS_OF(rb_cFalseClass), "new");
    rb_define_global_const("FALSE", Qfalse);

    eq = rb_intern("==");
    eql = rb_intern("eql?");
    inspect = rb_intern("inspect");
}
