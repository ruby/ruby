/************************************************

  assoc.c -

  $Author: matz $
  $Date: 1995/01/10 10:30:37 $
  created at: Fri Jan  6 10:10:36 JST 1995

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

static VALUE C_Assoc;

static ID eq;

VALUE rb_to_a();

VALUE
assoc_new(car, cdr)
    VALUE car, cdr;
{
    NEWOBJ(assoc, struct RAssoc);
    OBJSETUP(assoc, C_Assoc, T_ASSOC);

    assoc->car = car;
    assoc->cdr = cdr;

    return (VALUE)assoc;
}

static VALUE
Fassoc_car(assoc)
    struct RAssoc *assoc;
{
    return assoc->car;
}

static VALUE
Fassoc_cdr(assoc)
    struct RAssoc *assoc;
{
    return assoc->cdr;
}

static VALUE
Fassoc_set_car(assoc, val)
    struct RAssoc *assoc;
    VALUE val;
{
    return assoc->car = val;
}

static VALUE
Fassoc_set_cdr(assoc, val)
    struct RAssoc *assoc;
    VALUE val;
{
    return assoc->cdr = val;
}

static VALUE
Fassoc_equal(assoc1, assoc2)
    struct RAssoc *assoc1, *assoc2;
{
    if (TYPE(assoc2) != T_ASSOC) return FALSE;
    if (!rb_equal(assoc1->car, assoc2->car)) return FALSE;
    return rb_equal(assoc1->cdr, assoc2->cdr);
}

static VALUE
Fassoc_hash(assoc)
    struct RAssoc *assoc;
{
    static ID hash;
    int key;

    if (!hash) hash = rb_intern("hash");
    key = rb_funcall(assoc->car, hash, 0, 0);
    key ^= rb_funcall(assoc->cdr, hash, 0, 0);
    return INT2FIX(key);
}

static VALUE
Fassoc_to_s(assoc)
    struct RAssoc *assoc;
{
    VALUE str1, str2;
    static ID to_s;

    if (!to_s) to_s = rb_intern("to_s");

    str1 = rb_funcall(assoc->car, to_s, 0);
    assoc = RASSOC(assoc->cdr);
    while (assoc) {
	if (TYPE(assoc) != T_ASSOC) {
	    str2 = rb_funcall(assoc, to_s, 0);
	    str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
	    break;
	}
	str2 = rb_funcall(assoc->car, to_s, 0);
	str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
	assoc = RASSOC(assoc->cdr);
    }

    return str1;
}

static VALUE
Fassoc_inspect(assoc)
    struct RAssoc *assoc;
{
    VALUE str1, str2;
    static ID inspect;

    if (!inspect) inspect = rb_intern("_inspect");

    str1 = rb_funcall(assoc->car, inspect, 0, 0);
    str2 = rb_funcall(assoc->cdr, inspect, 0, 0);
    str_cat(str1, "::", 2);
    str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str1;
}

extern VALUE C_Kernel;

Init_Assoc()
{
    C_Assoc  = rb_define_class("Assoc", C_Object);

    rb_undef_method(CLASS_OF(C_Assoc), "new");
    rb_undef_method(C_Assoc, "clone");

    rb_define_method(C_Assoc, "car", Fassoc_car, 0);
    rb_define_method(C_Assoc, "cdr", Fassoc_cdr, 0);

    rb_define_method(C_Assoc, "car=", Fassoc_set_car, 1);
    rb_define_method(C_Assoc, "cdr=", Fassoc_set_cdr, 1);

    rb_define_method(C_Assoc, "==", Fassoc_equal, 1);
    rb_define_method(C_Assoc, "hash", Fassoc_hash, 0);

    rb_define_method(C_Assoc, "to_s", Fassoc_to_s, 0);
    rb_define_method(C_Assoc, "_inspect", Fassoc_inspect, 0);

    rb_define_method(C_Kernel, "::", assoc_new, 1);
}
