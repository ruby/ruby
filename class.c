/************************************************

  class.c -

  $Author: matz $
  $Date: 1994/10/14 06:19:04 $
  created at: Tue Aug 10 15:05:44 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"
#include "methods.h"

struct st_table *new_idhash();

extern VALUE C_Class;
extern VALUE C_Module;

VALUE
class_new(super)
    struct RClass *super;
{
    NEWOBJ(cls, struct RClass);
    OBJSETUP(cls, C_Class, T_CLASS);

    cls->super = super;
    cls->m_tbl = new_idhash();
    cls->c_tbl = Qnil;

    return (VALUE)cls;
}

VALUE
single_class_new(super)
    struct RClass *super;
{
    struct RClass *cls = (struct RClass*)class_new(super);

    FL_SET(cls, FL_SINGLE);

    return (VALUE)cls;
}

VALUE
single_class_clone(class)
    struct RClass *class;
{
    if (!FL_TEST(class, FL_SINGLE))
	return (VALUE)class;
    else {
	/* copy single(unnamed) class */
	NEWOBJ(cls, struct RClass);
	CLONESETUP(cls, class);

	cls->super = class->super;
	cls->m_tbl = st_copy(class->m_tbl);
	cls->c_tbl = Qnil;
	FL_SET(cls, FL_SINGLE);
	return (VALUE)cls;
    }
}

VALUE 
rb_define_class_id(id, super)
    ID id;
    struct RBasic *super;
{
    struct RClass *cls = (struct RClass*)class_new(super);

    rb_name_class(cls, id);

    /* make metaclass */
    RBASIC(cls)->class = single_class_new(super?super->class:C_Class);
    literalize(RBASIC(cls)->class);

    return (VALUE)cls;
}

VALUE 
rb_define_class(name, super)
    char *name;
    VALUE super;
{
    return rb_define_class_id(rb_intern(name), super);
}

VALUE
module_new()
{
    NEWOBJ(mdl, struct RClass);
    OBJSETUP(mdl, C_Module, T_MODULE);

    mdl->super = Qnil;
    mdl->m_tbl = new_idhash();
    mdl->c_tbl = Qnil;

    return (VALUE)mdl;
}

VALUE 
rb_define_module_id(id)
    ID id;
{
    struct RClass *mdl = (struct RClass*)module_new();

    rb_name_class(mdl, id);
    return (VALUE)mdl;
}

VALUE 
rb_define_module(name)
    char *name;
{
    return rb_define_module_id(rb_intern(name));
}

static struct RClass *
include_class_new(module, super)
    struct RClass *module, *super;
{
    struct RClass *p;

    NEWOBJ(cls, struct RClass);
    OBJSETUP(cls, C_Class, T_ICLASS);

    cls->m_tbl = module->m_tbl;
    cls->c_tbl = module->c_tbl;
    cls->super = super;
    if (TYPE(module) == T_ICLASS) {
	RBASIC(cls)->class = RBASIC(module)->class;
    }
    else {
	RBASIC(cls)->class = (VALUE)module;
    }

    return cls;
}

void
rb_include_module(class, module)
    struct RClass *class, *module;
{
    struct RClass *p;
    int added = FALSE;

    Check_Type(module, T_MODULE);

    while (module) {
	/* ignore if module included already in superclasses */
	for (p = class->super; p; p = p->super) {
	    if (BUILTIN_TYPE(p) == T_ICLASS && p->m_tbl == module->m_tbl)
		goto ignore_module;
	}

	class->super = include_class_new(module, class->super);
	added = TRUE;
	class = class->super;
      ignore_module:
	module = module->super;
    }
    if (added) {
	rb_clear_cache2(class);
    }
}

void
rb_add_method(class, mid, node, undef)
    struct RClass *class;
    ID mid;
    NODE *node;
    int undef;
{
    struct SMethod *body;

    if (class == Qnil) class = (struct RClass*)C_Object;
    if (st_lookup(class->m_tbl, mid, &body)) {
	if (verbose) {
	    Warning("redefine %s", rb_id2name(mid));
	}
	rb_clear_cache(body);
	method_free(body);
    }
    body = ALLOC(struct SMethod);
    body->node = node;
    if (BUILTIN_TYPE(class) == T_MODULE)
	body->origin = Qnil;
    else
	body->origin = class;
    body->id = mid;
    body->undef = undef;
    body->count = 1;
    st_insert(class->m_tbl, mid, body);
}

void
rb_define_method(class, name, func, argc)
    struct RClass *class;
    char *name;
    VALUE (*func)();
    int argc;
{
    NODE *temp = NEW_CFUNC(func, argc);

    rb_add_method(class, rb_intern(name), temp, FALSE);
}

void
rb_undef_method(class, name)
    struct RClass *class;
    char *name;
{
    rb_add_method(class, rb_intern(name), Qnil, TRUE);
}

VALUE
rb_single_class(obj)
    struct RBasic *obj;
{
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
      case T_STRUCT:
	break;
      default:
	Fail("can't define single method for built-in classes");
	break;
    }

    if (FL_TEST(obj->class, FL_SINGLE)) {
	return (VALUE)obj->class;
    }
    return obj->class = single_class_new(obj->class);
}

void
rb_define_single_method(obj, name, func, argc)
    VALUE obj;
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_define_method(rb_single_class(obj), name, func, argc, FALSE);
}

void
rb_define_alias(class, name1, name2)
    struct RClass *class;
    char *name1, *name2;
{
    rb_alias(class, rb_intern(name1), rb_intern(name2));
}

void
rb_define_attr(class, name, pub)
    struct RClass *class;
    char *name;
    int pub;
{
    char *buf;
    ID attr, attreq, attriv;

    attr = rb_intern(name);
    buf = (char*)alloca(strlen(name) + 2);
    sprintf(buf, "%s=", name);
    attreq = rb_intern(buf);
    sprintf(buf, "@%s", name);
    attriv = rb_intern(buf);
    if (rb_method_boundp(class, attr) == Qnil) {
	rb_add_method(class, attr, NEW_IVAR(attriv), FALSE);
    }
    if (pub && rb_method_boundp(class, attreq) == Qnil) {
	rb_add_method(class, attreq, NEW_ATTRSET(attriv), FALSE);
    }
}

void
rb_define_single_attr(obj, name, pub)
    VALUE obj;
    char *name;
    int pub;
{
    rb_define_attr(rb_single_class(obj), name, pub);
}

#include <varargs.h>
#include <ctype.h>

int
rb_scan_args(args, fmt, va_alist)
    VALUE args;
    char *fmt;
    va_dcl
{
    int n, i, len;
    char *p = fmt;
    VALUE *var;
    va_list vargs;

    if (NIL_P(args)) {
	len = 0;
	args = ary_new();
    }
    else {
	Check_Type(args, T_ARRAY);
	len = RARRAY(args)->len;
    }

    va_start(vargs);

    if (*p == '*') {
	var = va_arg(vargs, VALUE*);
	*var = args;
	return len;
    }

    if (isdigit(*p)) {
	n = *p - '0';
	if (n > len)
	    Fail("Wrong number of arguments for %s",
		 rb_id2name(the_env->last_func));
	for (i=0; i<n; i++) {
	    var = va_arg(vargs, VALUE*);
	    *var = ary_entry(args, i);
	}
	p++;
    }
    else {
	goto error;
    }

    if (isdigit(*p)) {
	n = i + *p - '0';
	for (; i<n; i++) {
	    var = va_arg(vargs, VALUE*);
	    if (len > i) {
		*var = ary_entry(args, i);
	    }
	    else {
		*var = Qnil;
	    }
	}
	p++;
    }

    if(*p == '*') {
	var = va_arg(vargs, VALUE*);
	if (len > i) {
	    *var = ary_new4(RARRAY(args)->len-i, RARRAY(args)->ptr+i);
	}
	else {
	    *var = ary_new();
	}
    }
    else if (*p == '\0') {
	if (len > i) {
	    Fail("Wrong # of arguments(%d for %d)", len, i);
	}
    }
    else {
	goto error;
    }

    va_end(vargs);
    return len;

  error:
    Fail("bad scan arg format: %s", fmt);
}
