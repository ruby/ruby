/**********************************************************************

  enum.c -

  $Author$
  $Date$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "node.h"

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
grep_iter_i(i, arg)
    VALUE i, *arg;
{
    if (RTEST(rb_funcall(arg[0], id_eqq, 1, i))) {
	rb_ary_push(arg[1], rb_yield(i));
    }
    return Qnil;
}

static VALUE
enum_grep(obj, pat)
    VALUE obj, pat;
{
    VALUE tmp, arg[2];

    arg[0] = pat; arg[1] = tmp = rb_ary_new();
    if (rb_block_given_p()) {
	rb_iterate(rb_each, obj, grep_iter_i, (VALUE)arg);
    }
    else {
	rb_iterate(rb_each, obj, grep_i, (VALUE)arg);
    }
    return tmp;
}

static VALUE
find_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(rb_yield(i))) {
	memo->u2.value = Qtrue;
	memo->u1.value = i;
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
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, Qfalse, 0);
    VALUE if_none;

    rb_scan_args(argc, argv, "01", &if_none);
    rb_iterate(rb_each, obj, find_i, (VALUE)memo);
    if (memo->u2.value) {
	rb_gc_force_recycle((VALUE)memo);
	return memo->u1.value;
    }
    if (!NIL_P(if_none)) {
	rb_eval_cmd(if_none, rb_ary_new2(0));
    }
    rb_gc_force_recycle((VALUE)memo);
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
reject_i(i, tmp)
    VALUE i, tmp;
{
    if (!RTEST(rb_yield(i))) {
	rb_ary_push(tmp, i);
    }
    return Qnil;
}

static VALUE
enum_reject(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = rb_ary_new();
    rb_iterate(rb_each, obj, reject_i, tmp);

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
enum_collect(obj)
    VALUE obj;
{
    VALUE tmp;

    tmp = rb_ary_new();
    rb_iterate(rb_each, obj, rb_block_given_p() ? collect_i : enum_all, tmp);

    return tmp;
}

static VALUE
enum_sort(obj)
    VALUE obj;
{
    return rb_ary_sort(enum_to_a(obj));
}

static VALUE
min_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value))
	memo->u1.value = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp) < 0)
	    memo->u1.value = i;
    }
    return Qnil;
}

static VALUE
min_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value))
	memo->u1.value = i;
    else {
	cmp = rb_yield(rb_assoc_new(i, memo->u1.value));
	if (rb_cmpint(cmp) < 0)
	    memo->u1.value = i;
    }
    return Qnil;
}

static VALUE
enum_min(obj)
    VALUE obj;
{
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p()?min_ii:min_i, (VALUE)memo);
    rb_gc_force_recycle((VALUE)memo);
    return memo->u1.value;
}

static VALUE
max_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value))
	memo->u1.value = i;
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp) > 0)
	    memo->u1.value = i;
    }
    return Qnil;
}

static VALUE
max_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value))
	memo->u1.value = i;
    else {
	cmp = rb_yield(rb_assoc_new(i, memo->u1.value));
	if (rb_cmpint(cmp) > 0)
	    memo->u1.value = i;
    }
    return Qnil;
}

static VALUE
enum_max(obj)
    VALUE obj;
{
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p()?max_ii:max_i, (VALUE)memo);
    rb_gc_force_recycle((VALUE)memo);
    return memo->u1.value;
}

static VALUE
member_i(item, memo)
    VALUE item;
    NODE *memo;
{
    if (rb_equal(item, memo->u1.value)) {
	memo->u2.value = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
enum_member(obj, val)
    VALUE obj, val;
{
    VALUE result;

    NODE *memo = rb_node_newnode(NODE_MEMO, val, Qfalse, 0);

    rb_iterate(rb_each, obj, member_i, (VALUE)memo);
    result = memo->u2.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
each_with_index_i(val, memo)
    VALUE val;
    NODE *memo;
{
    rb_yield(rb_assoc_new(val, INT2FIX(memo->u3.cnt)));
    memo->u3.cnt++;
    return Qnil;
}

static VALUE
enum_each_with_index(obj)
    VALUE obj;
{
    NODE *memo = rb_node_newnode(NODE_MEMO, 0, 0, 0);

    rb_iterate(rb_each, obj, each_with_index_i, (VALUE)memo);
    rb_gc_force_recycle((VALUE)memo);
    return obj;
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
    rb_define_method(rb_mEnumerable,"reject", enum_reject, 0);
    rb_define_method(rb_mEnumerable,"collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"map", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"min", enum_min, 0);
    rb_define_method(rb_mEnumerable,"max", enum_max, 0);
    rb_define_method(rb_mEnumerable,"member?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"include?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"each_with_index", enum_each_with_index, 0);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
}
