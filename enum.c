/************************************************

  enum.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE M_Enumerable;
static ID id_each, id_match, id_equal, id_cmp;

void
rb_each(obj)
    VALUE obj;
{
    rb_funcall(obj, id_each, 0, Qnil);
}

static void
enum_grep(i, arg)
    VALUE i, *arg;
{
    if (rb_funcall(arg[0], id_match, 1, i)) {
	Fary_push(arg[1], i);
    }
}

static void
enum_grep2(i, pat)
    VALUE i, pat;
{
    if (rb_funcall(pat, id_match, 1, i)) {
	rb_yield(i);
    }
}

static VALUE
Fenum_grep(obj, pat)
    VALUE obj;
{
    if (iterator_p()) {
	rb_iterate(rb_each, obj, enum_grep2, pat);
	return obj;
    }
    else {
	VALUE tmp, arg[2];

	arg[0] = pat; arg[1] = tmp = ary_new();
	GC_LINK;
	GC_PRO(tmp);

	rb_iterate(rb_each, obj, enum_grep, arg);

	GC_UNLINK;
	return tmp;
    }
}

static void
enum_find(i, foundp)
    VALUE i;
    int *foundp;
{
    if (rb_yield(i)) {
	*foundp = TRUE;
	rb_break();
    }
}

static VALUE
Fenum_find(obj)
    VALUE obj;
{
    int enum_found;

    enum_found = FALSE;
    rb_iterate(rb_each, obj, enum_find, &enum_found);
    return enum_found;
}

static void
enum_find_all(i, tmp)
    VALUE i;
{
    if (rb_yield(i)) {
	Fary_push(tmp, i);
    }
}

static VALUE
Fenum_find_all(obj)
    VALUE obj;
{
    VALUE tmp;

    GC_LINK;
    GC_PRO3(tmp, ary_new());

    rb_iterate(rb_each, obj, enum_find_all, Qnil);

    GC_UNLINK;
    return tmp;
}

static void
enum_collect(i, tmp)
    VALUE i;
{
    VALUE retval;

    GC_LINK;
    GC_PRO3(retval, rb_yield(i));

    if (retval) {
	Fary_push(tmp, retval);
    }

    GC_UNLINK;
}

static VALUE
Fenum_collect(obj)
    VALUE obj;
{
    VALUE tmp;

    GC_LINK;
    GC_PRO3(tmp, ary_new());

    rb_iterate(rb_each, obj, enum_collect, tmp);

    GC_UNLINK;
    return tmp;
}

static void
enum_reverse(i, tmp)
    VALUE i, tmp;
{
    Fary_unshift(tmp, i);
}

static VALUE
Fenum_reverse(obj)
    VALUE obj;
{
    VALUE tmp;

    GC_LINK;
    GC_PRO3(tmp, ary_new());

    rb_iterate(rb_each, obj, enum_reverse, tmp);

    GC_UNLINK;
    return tmp;
}

static void
enum_all(i, ary)
    VALUE i, ary;
{
    Fary_push(ary, i);
}
    
static VALUE
Fenum_to_a(obj)
    VALUE obj;
{
    VALUE ary;

    GC_LINK;
    GC_PRO3(ary, ary_new());
    rb_iterate(rb_each, obj, enum_all, ary);
    GC_UNLINK;

    return ary;
}

static VALUE
Fenum_sort(obj)
    VALUE obj;
{
    VALUE ary;

    GC_LINK;
    GC_PRO3(ary, Fenum_to_a(obj));
    Fary_sort(ary);
    GC_UNLINK;
    return ary;
}

static void
enum_min(i, min)
    VALUE i, *min;
{
    VALUE cmp;

    if (*min == Qnil)
	*min = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *min);
	if (FIX2INT(cmp) < 0)
	    *min = i;
    }
}

static VALUE
Fenum_min(obj)
    VALUE obj;
{
    VALUE min;

    GC_LINK;
    GC_PRO2(min);
    rb_iterate(rb_each, obj, enum_min, &min);
    GC_UNLINK;
    return min;
}

static void
enum_max(i, max)
    VALUE i, *max;
{
    VALUE cmp;

    if (*max == Qnil)
	*max = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *max);
	if (FIX2INT(cmp) > 0)
	    *max = i;
    }
}

static VALUE
Fenum_max(obj)
    VALUE obj;
{
    VALUE max;

    GC_LINK;
    GC_PRO2(max);
    rb_iterate(rb_each, obj, enum_max, &max);
    GC_UNLINK;
    return max;
}

struct i_v_pair {
    int i;
    VALUE v;
    int found;
};

static void
enum_index(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_funcall(item, id_equal, 1, iv->v)) {
	iv->found = 1;
	rb_break();
    }
    else {
	iv->i++;
    }
}

static VALUE
Fenum_index(obj, val)
    VALUE obj;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    iv.found = 0;
    rb_iterate(rb_each, obj, enum_index, &iv);
    if (iv.found) return INT2FIX(iv.i);
    return Qnil;		/* not found */
}

static void
enum_includes(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_funcall(item, id_equal, 1, iv->v)) {
	iv->i = 1;
	rb_break();
    }
}

static VALUE
Fenum_includes(obj, val)
    VALUE obj;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    rb_iterate(rb_each, obj, enum_includes, &iv);
    if (iv.i) return TRUE;
    return FALSE;
}

Init_Enumerable()
{
    M_Enumerable = rb_define_module("Enumerable");

    rb_define_method(M_Enumerable,"to_a", Fenum_to_a, 0);

    rb_define_method(M_Enumerable,"grep", Fenum_grep, 1);
    rb_define_method(M_Enumerable,"find", Fenum_find, 0);
    rb_define_method(M_Enumerable,"find_all", Fenum_find_all, 0);
    rb_define_method(M_Enumerable,"collect", Fenum_collect, 0);
    rb_define_method(M_Enumerable,"reverse", Fenum_reverse, 0);
    rb_define_method(M_Enumerable,"min", Fenum_min, 0);
    rb_define_method(M_Enumerable,"max", Fenum_max, 0);
    rb_define_method(M_Enumerable,"index", Fenum_index, 1);
    rb_define_method(M_Enumerable,"includes", Fenum_includes, 1);

    id_each = rb_intern("each");
    id_match = rb_intern("=~");
    id_equal = rb_intern("==");
    id_cmp   = rb_intern("<=>");
}
