/************************************************

  class.c -

  $Author: matz $
  $Date: 1996/12/25 08:54:44 $
  created at: Tue Aug 10 15:05:44 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "node.h"
#include "st.h"

struct st_table *new_idhash();
extern st_table *rb_class_tbl;

extern VALUE cClass;
extern VALUE cModule;

VALUE
class_new(super)
    struct RClass *super;
{
    NEWOBJ(cls, struct RClass);
    OBJSETUP(cls, cClass, T_CLASS);

    cls->super = super;
    cls->iv_tbl = 0;
    cls->m_tbl = 0;		/* safe GC */
    cls->m_tbl = new_idhash();

    return (VALUE)cls;
}

VALUE
singleton_class_new(super)
    struct RClass *super;
{
    struct RClass *cls = (struct RClass*)class_new(super);

    FL_SET(cls, FL_SINGLETON);

    return (VALUE)cls;
}

static int
clone_method(mid, body, tbl)
    ID mid;
    NODE *body;
    st_table *tbl;
{
    st_insert(tbl, mid, NEW_METHOD(body->nd_body, body->nd_noex));
    return ST_CONTINUE;
}

VALUE
singleton_class_clone(class)
    struct RClass *class;
{
    if (!FL_TEST(class, FL_SINGLETON))
	return (VALUE)class;
    else {
	/* copy singleton(unnamed) class */
	NEWOBJ(clone, struct RClass);
	CLONESETUP(clone, class);

	clone->super = class->super;
	clone->iv_tbl = 0;
	clone->m_tbl = 0;
	clone->m_tbl = new_idhash();
	st_foreach(class->m_tbl, clone_method, clone->m_tbl);
	FL_SET(clone, FL_SINGLETON);
	return (VALUE)clone;
    }
}

VALUE
rb_define_class_id(id, super)
    ID id;
    struct RBasic *super;
{
    struct RClass *cls;

    if (!super) super = (struct RBasic*)cClass;
    cls = (struct RClass*)class_new(super);
    rb_name_class(cls, id);
    /* make metaclass */
    RBASIC(cls)->class = singleton_class_new(super->class);

    return (VALUE)cls;
}

VALUE
rb_define_class(name, super)
    char *name;
    VALUE super;
{
    VALUE class;
    ID id;

    id = rb_intern(name);
    class = rb_define_class_id(id, super);
    st_add_direct(rb_class_tbl, id, class);

    return class;
}

VALUE
rb_define_class_under(under, name, super)
    VALUE under;
    char *name;
    VALUE super;
{
    VALUE class;
    ID id;

    id = rb_intern(name);
    class = rb_define_class_id(id, super);
    rb_const_set(under, id, class);
    rb_set_class_path(class, under, name);

    return class;
}

VALUE
module_new()
{
    NEWOBJ(mdl, struct RClass);
    OBJSETUP(mdl, cModule, T_MODULE);

    mdl->super = 0;
    mdl->iv_tbl = 0;
    mdl->m_tbl = 0;
    mdl->m_tbl = new_idhash();

    return (VALUE)mdl;
}

VALUE
rb_define_module_id(id)
    ID id;
{
    extern st_table *rb_class_tbl;
    struct RClass *mdl = (struct RClass*)module_new();

    rb_name_class(mdl, id);

    return (VALUE)mdl;
}

VALUE
rb_define_module(name)
    char *name;
{
    VALUE module;
    ID id;

    id = rb_intern(name);
    module = rb_define_module_id(id);
    st_add_direct(rb_class_tbl, id, module);

    return module;
}

VALUE
rb_define_module_under(under, name)
    VALUE under;
    char *name;
{
    VALUE module;
    ID id;

    id = rb_intern(name);
    module = rb_define_module_id(id);
    rb_const_set(under, id, module);
    rb_set_class_path(module, under, name);

    return module;
}

static struct RClass *
include_class_new(module, super)
    struct RClass *module, *super;
{
    NEWOBJ(cls, struct RClass);
    OBJSETUP(cls, cClass, T_ICLASS);

    cls->m_tbl = module->m_tbl;
    cls->iv_tbl = module->iv_tbl;
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
    VALUE class, module;
{
    struct RClass *p;

    if (NIL_P(module)) return;

    switch (TYPE(module)) {
      case T_MODULE:
      case T_CLASS:
	break;
      default:
	Check_Type(module, T_MODULE);
    }

    if (class == module) return;
    rb_clear_cache();
 
    while (module) {
	/* ignore if the module included already in superclasses */
	for (p = RCLASS(class)->super; p; p = p->super) {
	    if (BUILTIN_TYPE(p) == T_ICLASS && p->m_tbl == RCLASS(module)->m_tbl)
		return;
	}

	RCLASS(class)->super = include_class_new(module, RCLASS(class)->super);
	class = (VALUE)RCLASS(class)->super;
	module = (VALUE)RCLASS(module)->super;
    }
}

void
rb_define_method_id(class, name, func, argc)
    struct RClass *class;
    ID name;
    VALUE (*func)();
    int argc;
{
    rb_add_method(class, name, NEW_CFUNC(func, argc), NOEX_PUBLIC);
}

void
rb_define_method(class, name, func, argc)
    VALUE class;
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_add_method(class, rb_intern(name), NEW_CFUNC(func, argc), NOEX_PUBLIC);
}

void
rb_undef_method(class, name)
    VALUE class;
    char *name;
{
    rb_add_method(class, rb_intern(name), 0, NOEX_PUBLIC);
}

void
rb_define_private_method(class, name, func, argc)
    struct RClass *class;
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_add_method(class, rb_intern(name), NEW_CFUNC(func, argc), NOEX_PRIVATE);
}

VALUE
rb_singleton_class(obj)
    struct RBasic *obj;
{
    if (rb_special_const_p((VALUE)obj)) {
	TypeError("cannot define singleton");
    }
    if (FL_TEST(obj->class, FL_SINGLETON)) {
	return (VALUE)obj->class;
    }
    return obj->class = singleton_class_new(obj->class);
}

void
rb_define_singleton_method(obj, name, func, argc)
    VALUE obj;
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_define_method(rb_singleton_class(obj), name, func, argc);
}

void
rb_define_module_function(module, name, func, argc)
    VALUE module;
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_define_private_method(module, name, func, argc);
    rb_define_singleton_method(module, name, func, argc);
}

VALUE mKernel;

void
rb_define_global_function(name, func, argc)
    char *name;
    VALUE (*func)();
    int argc;
{
    rb_define_private_method(mKernel, name, func, argc);
}

void
rb_define_alias(class, name1, name2)
    VALUE class;
    char *name1, *name2;
{
    rb_alias(class, rb_intern(name1), rb_intern(name2));
}

void
rb_define_attr(class, id, pub)
    VALUE class;
    ID id;
    int pub;
{
    char *name;
    char *buf;
    ID attr, attreq, attriv;

    name = rb_id2name(id);
    attr = rb_intern(name);
    buf = ALLOCA_N(char,strlen(name)+2);
    sprintf(buf, "%s=", name);
    attreq = rb_intern(buf);
    sprintf(buf, "@%s", name);
    attriv = rb_intern(buf);
    if (!rb_method_boundp(class, attr, NOEX_PRIVATE)) {
	rb_add_method(class, attr, NEW_IVAR(attriv), 0);
    }
    if (pub && !rb_method_boundp(class, attreq, NOEX_PRIVATE)) {
	rb_add_method(class, attreq, NEW_ATTRSET(attriv), 0);
    }
}

#include <varargs.h>
#include <ctype.h>

int
rb_scan_args(argc, argv, fmt, va_alist)
    int argc;
    VALUE *argv;
    char *fmt;
    va_dcl
{
    int n, i;
    char *p = fmt;
    VALUE *var;
    va_list vargs;

    va_start(vargs);

    if (*p == '*') {
	var = va_arg(vargs, VALUE*);
	*var = ary_new4(argc, argv);
	return argc;
    }

    if (isdigit(*p)) {
	n = *p - '0';
	if (n > argc)
	    ArgError("Wrong # of arguments (%d for %d)", argc, n);
	for (i=0; i<n; i++) {
	    var = va_arg(vargs, VALUE*);
	    *var = argv[i];
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
	    if (argc > i) {
		*var = argv[i];
	    }
	    else {
		*var = Qnil;
	    }
	}
	p++;
    }

    if(*p == '*') {
	var = va_arg(vargs, VALUE*);
	if (argc > i) {
	    *var = ary_new4(argc-i, argv+i);
	}
	else {
	    *var = ary_new();
	}
    }
    else if (*p == '\0') {
	if (argc > i) {
	    ArgError("Wrong # of arguments(%d for %d)", argc, i);
	}
    }
    else {
	goto error;
    }

    va_end(vargs);
    return argc;

  error:
    Fatal("bad scan arg format: %s", fmt);
    return 0;
}
