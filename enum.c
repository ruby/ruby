/************************************************

  enum.c -

  $Author$
  $Date$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE rb_mEnumerable;
static ID id_each, id_eqq, id_cmp;

VALUE
rb_each(obj)
    VALUE obj;
{
    return rb_funcall(obj, id_each, 0, 0);
}

static VALUE
grep_i(i, arg)
    VALUE i, *arg;
{
    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	rb_ary_push(arg[1], i);
    }
    return Qnil;
}

static VALUE
grep_iter_i(i, pat)
    VALUE i, pat;
{
    if (RTEST(rb_funcall(pat, id_eqq, 1, i))) {
	rb_yield(i);
    }
    return Qnil;
}

static VALUE
enum_grep(obj, pat)
    VALUE obj, pat;
{
    if (rb_iterator_p()) {
	rb_iterate(rb_each, obj, grep_iter_i, pat);
	return obj;
    }
    else {
	VALUE tmp, arg[2];

	arg[0] = pat; arg[1] = tmp = rb_ary_new();
	rb_iterate(rb_each, obj, grep_i, (VALUE)arg);

	if (RARRAY(tmp)->len == 0) return Qnil;
	return tmp;
    }
}

struct find_arg {
    int found;
    VALUE val;
};
    
static VALUE
find_i(i, arg)
    VALUE i;
    struct find_arg *arg;
{
    if (RTEST(rb_yield(i))) {
	arg->found = Qtrue;
	arg->val = i;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
enum_find(argc, argv, obj)
    int argc;
    VALUE* argv;
    VALUE obj;
{
    struct find_arg arg;
    VALUE if_none;

    rb_scan_args(argc, argv, "01", &if_none);
    arg.found = Qfalse;
    rb_iterate(rb_each, obj, find_i, (VALUE)&arg);
    if (arg.found) {
	return arg.val;
    }
    if (!NIL_P(if_none)) {
	rb_eval_cmd(if_none, Qnil);
    }
    return Qnil;
}

static VALUE
find_all_i(i, tmp)
    VALUE i, tmp;
{
    if (RTEST(rb_yield(i))) {
	rb_ary_push(tmp, i);
    }
    return Qnil;
}

static VALUE
enum_find_all(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = rb_ary_new();
    rb_iterate(rb_each, obj, find_all_i, tmp);

    return tmp;
}

static VALUE
collect_i(i, tmp)
    VALUE i, tmp;
{
    rb_ary_push(tmp, rb_yield(i));
    return Qnil;
}

static VALUE
enum_collect(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = rb_ary_new();
    rb_iterate(rb_each, obj, collect_i, tmp);

    return tmp;
}

static VALUE
enum_all(i, ary)
    VALUE i, ary;
{
    rb_ary_push(ary, i);
    return Qnil;
}

static VALUE
enum_to_a(obj)
    VALUE obj;
{
    VALUE ary;

    ary = rb_ary_new();
    rb_iterate(rb_each, obj, enum_all, ary);

    return ary;
}

static VALUE
enum_sort(obj)
    VALUE obj;
{
    return rb_ary_sort(enum_to_a(obj));
}

static VALUE
min_i(i, min)
    VALUE i, *min;
{
    VALUE cmp;

    if (NIL_P(*min))
	*min = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *min);
	if (FIX2LONG(cmp) < 0)
	    *min = i;
    }
    return Qnil;
}

static VALUE
min_ii(i, min)
    VALUE i, *min;
{
    VALUE cmp;

    if (NIL_P(*min))
	*min = i;
    else {
	cmp = rb_yield(rb_assoc_new(i, *min));
	if (FIX2LONG(cmp) < 0)
	    *min = i;
    }
    return Qnil;
}

static VALUE
enum_min(obj)
    VALUE obj;
{
    VALUE min = Qnil;

    rb_iterate(rb_each, obj, rb_iterator_p()?min_ii:min_i, (VALUE)&min);
    return min;
}

static VALUE
max_i(i, max)
    VALUE i, *max;
{
    VALUE cmp;

    if (NIL_P(*max))
	*max = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, *max);
	if (FIX2LONG(cmp) > 0)
	    *max = i;
    }
    return Qnil;
}

static VALUE
max_ii(i, max)
    VALUE i, *max;
{
    VALUE cmp;

    if (NIL_P(*max))
	*max = i;
    else {
	cmp = rb_yield(rb_assoc_new(i, *max));
	if (FIX2LONG(cmp) > 0)
	    *max = i;
    }
    return Qnil;
}

static VALUE
enum_max(obj)
    VALUE obj;
{
    VALUE max = Qnil;

    rb_iterate(rb_each, obj, rb_iterator_p()?max_ii:max_i, (VALUE)&max);
    return max;
}

struct i_v_pair {
    int i;
    VALUE v;
    int found;
};

static VALUE
index_i(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_equal(item, iv->v)) {
	iv->found = 1;
	rb_iter_break();
    }
    else {
	iv->i++;
    }
    return Qnil;
}

static VALUE
enum_index(obj, val)
    VALUE obj, val;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    iv.found = 0;
    rb_iterate(rb_each, obj, index_i, (VALUE)&iv);
    if (iv.found) return INT2FIX(iv.i);
    return Qnil;		/* not found */
}

static VALUE
member_i(item, iv)
    VALUE item;
    struct i_v_pair *iv;
{
    if (rb_equal(item, iv->v)) {
	iv->i = 1;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
enum_member(obj, val)
    VALUE obj, val;
{
    struct i_v_pair iv;

    iv.i = 0;
    iv.v = val;
    rb_iterate(rb_each, obj, member_i, (VALUE)&iv);
    if (iv.i) return Qtrue;
    return Qfalse;
}

static VALUE
length_i(i, length)
    VALUE i;
    int *length;
{
    (*length)++;
    return Qnil;
}

static VALUE
enum_length(obj)
    VALUE obj;
{
    int length = 0;

    rb_iterate(rb_each, obj, length_i, (VALUE)&length);
    return INT2FIX(length);
}

VALUE
rb_enum_length(obj)
    VALUE obj;
{
    return enum_length(obj);
}

static VALUE
each_with_index_i(val, indexp)
    VALUE val;
    int *indexp;
{
#if 1
    rb_yield(rb_assoc_new(val, INT2FIX(*indexp)));
#else
    rb_yield(rb_ary_concat(rb_Array(val), INT2FIX(*indexp)));
#endif
    (*indexp)++;
    return Qnil;
}

static VALUE
enum_each_with_index(obj)
    VALUE obj;
{
    int index = 0;

    rb_iterate(rb_each, obj, each_with_index_i, (VALUE)&index);
    return Qnil;
}

void
Init_Enumerable()
{
    rb_mEnumerable = rb_define_module("Enumerable");

    rb_define_method(rb_mEnumerable,"to_a", enum_to_a, 0);
    rb_define_method(rb_mEnumerable,"entries", enum_to_a, 0);

    rb_define_method(rb_mEnumerable,"sort", enum_sort, 0);
    rb_define_method(rb_mEnumerable,"grep", enum_grep, 1);
    rb_define_method(rb_mEnumerable,"find", enum_find, -1);
    rb_define_method(rb_mEnumerable,"detect", enum_find, -1);
    rb_define_method(rb_mEnumerable,"find_all", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"select", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"min", enum_min, 0);
    rb_define_method(rb_mEnumerable,"max", enum_max, 0);
    rb_define_method(rb_mEnumerable,"index", enum_index, 1);
    rb_define_method(rb_mEnumerable,"member?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"include?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"length", enum_length, 0);
    rb_define_method(rb_mEnumerable,"size", enum_length, 0);
    rb_define_method(rb_mEnumerable,"each_with_index", enum_each_with_index, 0);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
}
