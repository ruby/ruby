/************************************************

  enum.c -

  $Author$
  $Date$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE mEnumerable;
static ID id_each, id_eqq, id_cmp;

void
rb_each(obj)
    VALUE obj;
{
    rb_funcall(obj, id_each, 0, 0);
}

static void
grep_i(i, arg)
    VALUE i, *arg;
{
    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	ary_push(arg[1], i);
    }
}

static void
grep_iter_i(i, pat)
    VALUE i, pat;
{
    if (RTEST(rb_funcall(pat, id_eqq, 1, i))) {
	rb_yield(i);
    }
}

static VALUE
enum_grep(obj, pat)
    VALUE obj, pat;
{
    if (iterator_p()) {
	rb_iterate(rb_each, obj, grep_iter_i, pat);
	return obj;
    }
    else {
	VALUE tmp, arg[2];

	arg[0] = pat; arg[1] = tmp = ary_new();
	rb_iterate(rb_each, obj, grep_i, arg);

	return tmp;
    }
}

struct find_arg {
    int found;
    VALUE val;
};
    
static void
find_i(i, arg)
    VALUE i;
    struct find_arg *arg;
{
    if (RTEST(rb_yield(i))) {
	arg->found = TRUE;
	arg->val = i;
	rb_break();
    }
}

static VALUE
enum_find(argc, argv, obj)
    int argc;
    VALUE argv;
    VALUE obj;
{
    struct find_arg arg;
    VALUE if_none;

    rb_scan_args(argc, argv, "01", &if_none);
    arg.found = FALSE;
    rb_iterate(rb_each, obj, find_i, &arg);
    if (arg.found) {
	return arg.val;
    }
    if (!NIL_P(if_none)) {
	rb_eval_cmd(if_none, Qnil);
    }
    return Qnil;
}

static void
find_all_i(i, tmp)
    VALUE i, tmp;
{
    if (RTEST(rb_yield(i))) {
	ary_push(tmp, i);
    }
}

static VALUE
enum_find_all(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = ary_new();
    rb_iterate(rb_each, obj, find_all_i, tmp);

    return tmp;
}

static void
collect_i(i, tmp)
    VALUE i, tmp;
{
    VALUE retval;

    retval = rb_yield(i);
    if (RTEST(retval)) {
	ary_push(tmp, retval);
    }
}

static VALUE
enum_collect(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = ary_new();
    rb_iterate(rb_each, obj, collect_i, tmp);

    return tmp;
}

static void
reverse_i(i, tmp)
    VALUE i, tmp;
{
    ary_unshift(tmp, i);
}

static VALUE
enum_reverse(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = ary_new();
    rb_iterate(rb_each, obj, reverse_i, tmp);

    return tmp;
}

static void
enum_all(i, ary)
    VALUE i, ary;
{
    ary_push(ary, i);
}

static VALUE
enum_to_a(obj)
    VALUE obj;
{
    VALUE ary;

    ary = ary_new();
    rb_iterate(rb_each, obj, enum_all, ary);

    return ary;
}

static VALUE
enum_sort(obj)
    VALUE obj;
{
    return ary_sort(enum_to_a(obj));
}

static void
min_i(i, min)
    VALUE i, *min;
{
    VALUE cmp;

    if (NIL_P(*min))
	*min = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *min);
	if (FIX2INT(cmp) < 0)
	    *min = i;
    }
}

static void
min_ii(i, min)
    VALUE i, *min;
{
    VALUE cmp;

    if (NIL_P(*min))
	*min = i;
    else {
	cmp = rb_yield(assoc_new(i, *min));
	if (FIX2INT(cmp) < 0)
	    *min = i;
    }
}

static VALUE
enum_min(obj)
    VALUE obj;
{
    VALUE min = Qnil;

    rb_iterate(rb_each, obj, iterator_p()?min_ii:min_i, &min);
    return min;
}

static void
max_i(i, max)
    VALUE i, *max;
{
    VALUE cmp;

    if (NIL_P(*max))
	*max = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *max);
	if (FIX2INT(cmp) > 0)
	    *max = i;
    }
}

static void
max_ii(i, max)
    VALUE i, *max;
{
    VALUE cmp;

    if (NIL_P(*max))
	*max = i;
    else {
	cmp = rb_yield(assoc_new(i, *max));
	if (FIX2INT(cmp) > 0)
	    *max = i;
    }
}

static VALUE
enum_max(obj)
    VALUE obj;
{
    VALUE max = Qnil;

    rb_iterate(rb_each, obj, iterator_p()?max_ii:max_i, &max);
    return max;
}

struct i_v_pair {
    int i;
    VALUE v;
    int found;
};

static void
index_i(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_equal(item, iv->v)) {
	iv->found = 1;
	rb_break();
    }
    else {
	iv->i++;
    }
}

static VALUE
enum_index(obj, val)
    VALUE obj, val;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    iv.found = 0;
    rb_iterate(rb_each, obj, index_i, &iv);
    if (iv.found) return INT2FIX(iv.i);
    return Qnil;		/* not found */
}

static void
member_i(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_equal(item, iv->v)) {
	iv->i = 1;
	rb_break();
    }
}

static VALUE
enum_member(obj, val)
    VALUE obj, val;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    rb_iterate(rb_each, obj, member_i, &iv);
    if (iv.i) return TRUE;
    return FALSE;
}

static void
length_i(i, length)
    VALUE i;
    int *length;
{
    (*length)++;
}

VALUE
enum_length(obj)
    VALUE obj;
{
    int length = 0;

    rb_iterate(rb_each, obj, length_i, &length);
    return INT2FIX(length);
}

void
Init_Enumerable()
{
    mEnumerable = rb_define_module("Enumerable");

    rb_define_method(mEnumerable,"to_a", enum_to_a, 0);

    rb_define_method(mEnumerable,"sort", enum_sort, 0);
    rb_define_method(mEnumerable,"grep", enum_grep, 1);
    rb_define_method(mEnumerable,"find", enum_find, -1);
    rb_define_method(mEnumerable,"find_all", enum_find_all, 0);
    rb_define_method(mEnumerable,"collect", enum_collect, 0);
    rb_define_method(mEnumerable,"reverse", enum_reverse, 0);
    rb_define_method(mEnumerable,"min", enum_min, 0);
    rb_define_method(mEnumerable,"max", enum_max, 0);
    rb_define_method(mEnumerable,"index", enum_index, 1);
    rb_define_method(mEnumerable,"member?", enum_member, 1);
    rb_define_method(mEnumerable,"include?", enum_member, 1);
    rb_define_method(mEnumerable,"length", enum_length, 0);
    rb_define_method(mEnumerable,"size", enum_length, 0);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
}
