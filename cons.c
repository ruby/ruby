/************************************************

  cons.c -

  $Author: matz $
  $Date: 1995/01/10 10:22:24 $
  created at: Fri Jan  6 10:10:36 JST 1995

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE C_Cons;

static ID eq;

VALUE rb_to_a();

VALUE
assoc_new(car, cdr)
    VALUE car, cdr;
{
    NEWOBJ(cons, struct RCons);
    OBJSETUP(cons, C_Cons, T_CONS);

    cons->car = car;
    cons->cdr = cdr;

    return (VALUE)cons;
}

#define cons_new assoc_new

static VALUE
Fcons_car(cons)
    struct RCons *cons;
{
    return cons->car;
}

static VALUE
Fcons_cdr(cons)
    struct RCons *cons;
{
    return cons->cdr;
}

static VALUE
Fcons_set_car(cons, val)
    struct RCons *cons;
    VALUE val;
{
    return cons->car = val;
}

static VALUE
Fcons_set_cdr(cons, val)
    struct RCons *cons;
    VALUE val;
{
    return cons->cdr = val;
}

static int
cons_length(list)
    struct RCons *list;
{
    int len = 1;

    while (TYPE(list) == T_CONS) {
	len++;
	list = RCONS(list->cdr);
    }
    return len;
}

static VALUE
Fcons_length(list)
    struct RCons *list;
{
    int len = cons_length(list);
    return INT2FIX(len);
}

static VALUE
cons_aref(list, nth)
    struct RCons *list;
    int nth;
{
    if (nth == 0) return list->car;
    list = RCONS(list->cdr);
    if (TYPE(list) != T_CONS) {
	if (nth == 1) return (VALUE)list;
	return Qnil;
    }

    return cons_aref(list, nth-1);
}

static VALUE
Fcons_aref(list, nth)
    struct RCons *list;
    VALUE nth;
{
    int n = NUM2INT(nth);

    if (n < 0) {
	n = cons_length(list)+n;
	if (n < 0) return Qnil;
    }
    return cons_aref(list, n);
}

static VALUE
cons_aset(list, nth, val)
    struct RCons *list;
    int nth;
    VALUE val;
{
    if (nth == 0) return list->car = val;
    if (TYPE(list->cdr) != T_CONS) {
	if (nth > 2) {
	    Fail("list too short");
	}
	if (nth == 1)
	    list->cdr = val;
	else
	    list->cdr = cons_new(list->cdr, val);
	return val;
    }
    return cons_aset(list->cdr, nth-1, val);
}

static VALUE
Fcons_aset(list, nth, val)
    struct RCons *list;
    VALUE nth, val;
{
    int n = NUM2INT(nth);

    if (n < 0) {
	n = cons_length(list)+n;
	if (n < 0) {
	    Fail("negative offset too big");
	}
    }
    return cons_aset(list, n, val);
}

static VALUE
Fcons_each(list)
    struct RCons *list;
{
    rb_yield(list->car);
    if (TYPE(list->cdr) != T_CONS) {
	rb_yield(list->cdr);
	return Qnil;
    }
    return Fcons_each(list->cdr);
}

static VALUE
Fcons_equal(cons1, cons2)
    struct RCons *cons1, *cons2;
{
    if (TYPE(cons2) != T_CONS) return FALSE;
    if (!rb_equal(cons1->car, cons2->car)) return FALSE;
    return rb_equal(cons1->cdr, cons2->cdr);
}

static ID hash;

static VALUE
Fcons_hash(cons)
    struct RCons *cons;
{
    int key;

    key = rb_funcall(cons->car, hash, 0, 0);
    key ^= rb_funcall(cons->cdr, hash, 0, 0);
    return INT2FIX(key);
}

static VALUE
Fcons_to_s(cons)
    struct RCons *cons;
{
    VALUE str1, str2;
    ID to_s = rb_intern("to_s");

    str1 = rb_funcall(cons->car, to_s, 0);
    cons = RCONS(cons->cdr);
    while (cons) {
	if (TYPE(cons) != T_CONS) {
	    str2 = rb_funcall(cons, to_s, 0);
	    str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
	    break;
	}
	str2 = rb_funcall(cons->car, to_s, 0);
	str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
	cons = RCONS(cons->cdr);
    }

    return str1;
}

static VALUE
Fcons_inspect(cons)
    struct RCons *cons;
{
    VALUE str1, str2;
    ID inspect = rb_intern("_inspect");

    str1 = rb_funcall(cons->car, inspect, 0, 0);
    str2 = rb_funcall(cons->cdr, inspect, 0, 0);
    str_cat(str1, "::", 2);
    str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return str1;
}

static VALUE
Fcons_copy(list)
    struct RCons *list;
{
    VALUE cdr = list->cdr;

    if (TYPE(cdr) == T_CONS)
	return cons_new(list->car, Fcons_copy(list->cdr));
    else
	return cons_new(list->car, cdr);
}

extern VALUE C_Kernel;
extern VALUE M_Enumerable;

Init_Cons()
{
    C_Cons  = rb_define_class("Cons", C_Object);

    rb_undef_method(CLASS_OF(C_Cons), "new");
    rb_undef_method(C_Cons, "clone");

    rb_include_module(C_Cons, M_Enumerable);

    rb_define_method(C_Cons, "car", Fcons_car, 0);
    rb_define_method(C_Cons, "cdr", Fcons_cdr, 0);

    rb_define_method(C_Cons, "car=", Fcons_set_car, 1);
    rb_define_method(C_Cons, "cdr=", Fcons_set_cdr, 1);

    rb_define_method(C_Cons, "==", Fcons_equal, 1);
    rb_define_method(C_Cons, "hash", Fcons_hash, 0);
    hash = rb_intern("hash");
    rb_define_method(C_Cons, "length", Fcons_length, 0);

    rb_define_method(C_Cons, "to_s", Fcons_to_s, 0);
    rb_define_method(C_Cons, "_inspect", Fcons_inspect, 0);

    /* methods to access as list */
    rb_define_method(C_Cons, "[]", Fcons_aref, 1);
    rb_define_method(C_Cons, "[]=", Fcons_aset, 2);
    rb_define_method(C_Cons, "each", Fcons_each, 0);

    rb_define_method(C_Cons, "copy", Fcons_copy, 0);

    rb_define_method(C_Kernel, "::", assoc_new, 1);
}
