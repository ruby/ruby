/************************************************

  object.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Thu Jul 15 12:01:24 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"
#include <stdio.h>

VALUE C_Kernel;
VALUE C_Object;
VALUE C_Module;
VALUE C_Class;
VALUE C_Nil;
VALUE C_Data;
VALUE C_Method;

struct st_table *new_idhash();

VALUE Fsprintf();
VALUE Ffail();
VALUE Fexit();
VALUE Feval();
VALUE Fapply();
VALUE Fdefined();
VALUE Fcaller();

VALUE obj_responds_to();
VALUE obj_alloc();
VALUE Ffix_clone();

static ID eq, match;

static VALUE
P_true(obj)
    VALUE obj;
{
    return TRUE;
}

static VALUE
P_false(obj)
    VALUE obj;
{
    return FALSE;
}

static VALUE
Fkrn_equal(obj, other)
    VALUE obj, other;
{
    if (obj == other) return TRUE;
    return FALSE;
}

static VALUE
Fkrn_hash(obj)
    VALUE obj;
{
    return obj;
}

static VALUE
Fkrn_to_a(obj)
    VALUE obj;
{
    return ary_new3(1, obj);
}

static VALUE
Fkrn_id(obj)
    VALUE obj;
{
    return obj | FIXNUM_FLAG;
}

static VALUE
Fkrn_noteq(obj, other)
    VALUE obj, other;
{
    if (rb_funcall(obj, eq, 1, other)) {
	return FALSE;
    }
    return TRUE;
}

static VALUE
Fkrn_nmatch(obj, other)
    VALUE obj, other;
{
    if (rb_funcall(obj, match, 1, other)) {
	return FALSE;
    }
    return TRUE;
}

static VALUE
Fkrn_class(obj)
    struct RBasic *obj;
{
    return obj->class;
}

VALUE
Fkrn_to_s(obj)
    VALUE obj;
{
    char buf[256];

    sprintf(buf, "#<%s: 0x%x>", rb_class2name(CLASS_OF(obj)), obj);
    return str_new2(buf);
}

VALUE
Fkrn_inspect(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("to_s"), 0, Qnil);
}

static
obj_inspect(id, value, str)
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
    GC_LINK;
    ivname = rb_id2name(id);
    str_cat(str, ivname, strlen(ivname));
    str_cat(str, "=", 1);
    GC_PRO3(str2, rb_funcall(value, rb_intern("_inspect"), 0, Qnil));
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    GC_UNLINK;

    return ST_CONTINUE;
}

static VALUE
Fobj_inspect(obj)
    struct RBasic *obj;
{
    VALUE str;
    char buf[256];

    if (FIXNUM_P(obj) || !obj->iv_tbl) return Fkrn_to_s(obj);

    GC_LINK;
    sprintf(buf, "-<%s: ", rb_class2name(CLASS_OF(obj)));
    GC_PRO3(str, str_new2(buf));
    st_foreach(obj->iv_tbl, obj_inspect, str);
    str_cat(str, ">", 1);
    GC_UNLINK;

    return str;
}

VALUE
obj_is_member_of(obj, c)
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
Fobj_clone(obj)
    VALUE obj;
{
    VALUE clone;

    Check_Type(obj, T_OBJECT);

    clone = obj_alloc(RBASIC(obj)->class);
    GC_LINK;
    GC_PRO(clone);
    if (RBASIC(obj)->iv_tbl) {
	RBASIC(clone)->iv_tbl = st_copy(RBASIC(obj)->iv_tbl);
    }
    RBASIC(clone)->class = single_class_clone(RBASIC(obj)->class);
    GC_UNLINK;

    return clone;
}

static VALUE
Fiterator_p()
{
    if (the_env->iterator > 1 && the_env->iterator < 4) return TRUE;
    return FALSE;
}

static VALUE
Fnil_to_s(obj)
    VALUE obj;
{
    return str_new2("nil");
}

static VALUE
Fnil_class(nil)
    VALUE nil;
{
    return C_Nil;
}

static VALUE
Fnil_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
      case T_FLOAT:
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
Fmain_to_s(obj)
    VALUE obj;
{
    return str_new2("main");
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
Fcls_new(class, args)
    VALUE class, args;
{
    return obj_alloc(class);
}

static VALUE
Fcls_to_s(class)
    VALUE class;
{
    return str_new2(rb_class2name(class));
}

static VALUE
Fcls_attr(class, args)
    VALUE class, args;
{
    VALUE name, pub;

    rb_scan_args(args, "11", &name, &pub);
    Check_Type(name, T_STRING);
    rb_define_attr(class, RSTRING(name)->ptr, pub);
    return Qnil;
}

static VALUE
Fcant_clone(obj)
    VALUE obj;
{
    Fail("can't clone %s", rb_class2name(CLASS_OF(obj)));
}

static VALUE
Fdata_class(data)
    VALUE data;
{
    return C_Data;
}

static VALUE boot_defclass(name, super)
    char *name;
    VALUE super;
{
    struct RClass *obj = (struct RClass*)class_new(super);

    rb_name_class(obj, rb_intern(name));
    return (VALUE)obj;
}

VALUE TopSelf;

Init_Object()
{
    VALUE metaclass;

    C_Kernel = boot_defclass("Kernel", Qnil);
    C_Object = boot_defclass("Object", C_Kernel);
    C_Module = boot_defclass("Module", C_Object);
    C_Class =  boot_defclass("Class",  C_Module);

    metaclass = RBASIC(C_Kernel)->class = single_class_new(C_Class);
    metaclass = RBASIC(C_Object)->class = single_class_new(metaclass);
    metaclass = RBASIC(C_Module)->class = single_class_new(metaclass);
    metaclass = RBASIC(C_Class)->class = single_class_new(metaclass);

    /*
     * 	+-------nil	      +---------------------+
     *  |        ^	      |			    |
     *  |        |     	      |			    |
     *  |      Kernel----->(Kernel)		    |
     *  |       ^  ^         ^  ^		    |
     *	|       |  |         |  |		    |
     *	|   +---+  +-----+   |  +---+		    |
     *	|   |     +------|---+      |		    |
     *	|   |     |      |          |		    |
     * 	+->Nil->(Nil) Object---->(Object)	    |
     *	   	      ^  ^         ^  ^	            |
     *	   	      |  |         |  |	            |
     *                |  | +-------+  |	            |
     *                |  | |          |	    	    |
     *                |  +---------+  +------+	    |
     *	       	      |	   |       |          |	    |
     * 	     +--------+    |     Module--->(Module) |
     *	     |             |       ^          ^	    |
     *  OtherClass-->(OtherClass)  |          |	    |
     * 		                 Class---->(Class)  |
     *					      ^     |
     *					      |     |
     *					      +-----+
     *
     *   + all metaclasses are instance of class Class
     */

    rb_define_method(C_Kernel, "is_nil", P_false, 0);
    rb_define_method(C_Kernel, "!", P_false, 0);
    rb_define_method(C_Kernel, "==", Fkrn_equal, 1);
    rb_define_alias(C_Kernel, "equal", "==");
    rb_define_method(C_Kernel, "hash", Fkrn_hash, 0);
    rb_define_method(C_Kernel, "id", Fkrn_id, 0);
    rb_define_method(C_Kernel, "class", Fkrn_class, 0);
    rb_define_method(C_Kernel, "!=", Fkrn_noteq, 1);
    rb_define_alias(C_Kernel, "=~", "==");
    rb_define_method(C_Kernel, "!~", Fkrn_nmatch, 1);

    rb_define_method(C_Kernel, "to_a", Fkrn_to_a, 0);
    rb_define_method(C_Kernel, "to_s", Fkrn_to_s, 0);
    rb_define_method(C_Kernel, "_inspect", Fkrn_inspect, 0);

    rb_define_func(C_Kernel, "caller", Fcaller, -2);
    rb_define_func(C_Kernel, "fail", Ffail, -2);
    rb_define_func(C_Kernel, "exit", Fexit, -2);
    rb_define_func(C_Kernel, "eval", Feval, 1);
    rb_define_func(C_Kernel, "defined", Fdefined, 1);
    rb_define_func(C_Kernel, "sprintf", Fsprintf, -1);
    rb_define_alias(C_Kernel, "format", "sprintf");
    rb_define_func(C_Kernel, "iterator_p", Fiterator_p, 0);

    rb_define_method(C_Kernel, "apply", Fapply, -2);

    rb_define_const(C_Kernel, "%TRUE", TRUE);
    rb_define_const(C_Kernel, "%FALSE", FALSE);

    rb_define_method(C_Object, "_inspect", Fobj_inspect, 0);

    rb_define_method(C_Object, "responds_to", obj_responds_to, 1);
    rb_define_method(C_Object, "is_member_of", obj_is_member_of, 1);
    rb_define_method(C_Object, "is_kind_of", obj_is_kind_of, 1);
    rb_define_method(C_Object, "clone", Fobj_clone, 0);

    rb_define_method(C_Module, "to_s", Fcls_to_s, 0);
    rb_define_method(C_Module, "clone", Fcant_clone, 0);
    rb_define_func(C_Module, "attr", Fcls_attr, -2);

    rb_define_method(C_Class, "new", Fcls_new, -2);

    C_Nil = rb_define_class("Nil", C_Kernel);
    rb_define_method(C_Nil, "to_s", Fnil_to_s, 0);
    rb_define_method(C_Nil, "clone", Ffix_clone, 0);
    rb_define_method(C_Nil, "class", Fnil_class, 0);

    rb_define_method(C_Nil, "is_nil", P_true, 0);
    rb_define_method(C_Nil, "!", P_true, 0);

    /* for compare cascading. */
    rb_define_method(C_Nil, ">", P_false, 1);
    rb_define_alias(C_Nil, ">=", ">");
    rb_define_alias(C_Nil, "<", ">");
    rb_define_alias(C_Nil, "<=", ">");

    /* default addition */
    rb_define_method(C_Nil, "+", Fnil_plus, 1);

    C_Data = rb_define_class("Data", C_Kernel);
    rb_define_method(C_Data, "clone", Fcant_clone, 0);
    rb_define_method(C_Data, "class", Fdata_class, 0);

    C_Method = rb_define_class("Method", C_Kernel);
    rb_define_method(C_Data, "clone", Fcant_clone, 0);

    eq = rb_intern("==");
    match = rb_intern("=~");

    Qself = TopSelf = obj_alloc(C_Object);
    rb_define_single_method(TopSelf, "to_s", Fmain_to_s, 0);
}
