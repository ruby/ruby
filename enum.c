/**********************************************************************

  enum.c -

  $Author$
  $Date$
  created at: Fri Oct  1 15:15:19 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "node.h"
#include "util.h"

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
    VALUE ary = rb_ary_new();
    VALUE arg[2];

    arg[0] = pat;
    arg[1] = ary;

    rb_iterate(rb_each, obj, rb_block_given_p() ? grep_iter_i : grep_i, (VALUE)arg);
    
    return ary;
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
	VALUE result = memo->u1.value;
	rb_gc_force_recycle((VALUE)memo);
	return result;
    }
    rb_gc_force_recycle((VALUE)memo);
    if (!NIL_P(if_none)) {
	return rb_funcall(if_none, rb_intern("call"), 0, 0);
    }
    return Qnil;
}

static VALUE
find_all_i(i, ary)
    VALUE i, ary;
{
    if (RTEST(rb_yield(i))) {
	rb_ary_push(ary, i);
    }
    return Qnil;
}

static VALUE
enum_find_all(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, find_all_i, ary);

    return ary;
}

static VALUE
reject_i(i, ary)
    VALUE i, ary;
{
    if (!RTEST(rb_yield(i))) {
	rb_ary_push(ary, i);
    }
    return Qnil;
}

static VALUE
enum_reject(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, reject_i, ary);

    return ary;
}

static VALUE
collect_i(i, ary)
    VALUE i, ary;
{
    rb_ary_push(ary, rb_yield(i));
    
    return Qnil;
}

static VALUE
collect_all(i, ary)
    VALUE i, ary;
{
    rb_ary_push(ary, i);
    
    return Qnil;
}

static VALUE
enum_collect(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, rb_block_given_p() ? collect_i : collect_all, ary);

    return ary;
}

static VALUE
enum_to_a(obj)
    VALUE obj;
{
    VALUE ary = rb_ary_new();
    
    rb_iterate(rb_each, obj, collect_all, ary);

    return ary;
}

static VALUE
inject_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (memo->u2.value) {
        memo->u2.value = Qfalse;
        memo->u1.value = i;
    }
    else {
        memo->u1.value = rb_yield_values(2, memo->u1.value, i);
    }
    return Qnil;
}

static VALUE
enum_inject(argc, argv, obj)
    int argc;
    VALUE *argv, obj;
{
    NODE *memo;
    VALUE n;

    if (rb_scan_args(argc, argv, "01", &n) == 1) {
        memo = rb_node_newnode(NODE_MEMO, n, Qfalse, 0);
    }
    else {
        memo = rb_node_newnode(NODE_MEMO, Qnil, Qtrue, 0);
    }
    rb_iterate(rb_each, obj, inject_i, (VALUE)memo);
    n = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return n;
}

static VALUE
partition_i(i, ary)
    VALUE i, *ary;
{
    if (RTEST(rb_yield(i))) {
	rb_ary_push(ary[0], i);
    }
    else {
	rb_ary_push(ary[1], i);
    }
    return Qnil;
}

static VALUE
enum_partition(obj)
    VALUE obj;
{
    VALUE ary[2];

    ary[0] = rb_ary_new();
    ary[1] = rb_ary_new();
    rb_iterate(rb_each, obj, partition_i, (VALUE)ary);

    return rb_assoc_new(ary[0], ary[1]);
}

static VALUE
enum_sort(obj)
    VALUE obj;
{
    return rb_ary_sort(enum_to_a(obj));
}

static VALUE
sort_by_i(i, ary)
    VALUE i, ary;
{
    VALUE v, e;

    v = rb_yield(i);
    e = rb_assoc_new(v, i);
    rb_ary_push(ary, e);
    return Qnil;
}

static int
sort_by_cmp(a, b)
    VALUE *a, *b;
{
    VALUE retval;

    retval = rb_funcall(RARRAY(*a)->ptr[0], id_cmp, 1, RARRAY(*b)->ptr[0]);
    return rb_cmpint(retval, *a, *b);
}

static VALUE
enum_sort_by(obj)
    VALUE obj;
{
    VALUE ary;
    long i;

    if (TYPE(obj) == T_ARRAY) {
	ary  = rb_ary_new2(RARRAY(obj)->len);
    }
    else {
	ary = rb_ary_new();
    }
    rb_iterate(rb_each, obj, sort_by_i, ary);
    if (RARRAY(ary)->len > 1) {
	qsort(RARRAY(ary)->ptr, RARRAY(ary)->len, sizeof(VALUE), sort_by_cmp);
    }
    for (i=0; i<RARRAY(ary)->len; i++) {
	VALUE e = RARRAY(ary)->ptr[i];
	RARRAY(ary)->ptr[i] = RARRAY(e)->ptr[1];
    }
    return ary;
}

static VALUE
all_iter_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (!RTEST(rb_yield(i))) {
	memo->u1.value = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
all_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (!RTEST(i)) {
	memo->u1.value = Qfalse;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
enum_all(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    memo->u1.value = Qtrue;
    rb_iterate(rb_each, obj, rb_block_given_p() ? all_iter_i : all_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
any_iter_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(rb_yield(i))) {
	memo->u1.value = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
any_i(i, memo)
    VALUE i;
    NODE *memo;
{
    if (RTEST(i)) {
	memo->u1.value = Qtrue;
	rb_iter_break();
    }
    return Qnil;
}

static VALUE
enum_any(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    memo->u1.value = Qfalse;
    rb_iterate(rb_each, obj, rb_block_given_p() ? any_iter_i : any_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
min_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) < 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
min_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_yield_values(2, i, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) < 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
enum_min(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p() ? min_ii : min_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
}

static VALUE
max_i(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_funcall(i, id_cmp, 1, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) > 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
max_ii(i, memo)
    VALUE i;
    NODE *memo;
{
    VALUE cmp;

    if (NIL_P(memo->u1.value)) {
	memo->u1.value = i;
    }
    else {
	cmp = rb_yield_values(2, i, memo->u1.value);
	if (rb_cmpint(cmp, i, memo->u1.value) > 0) {
	    memo->u1.value = i;
	}
    }
    return Qnil;
}

static VALUE
enum_max(obj)
    VALUE obj;
{
    VALUE result;
    NODE *memo = rb_node_newnode(NODE_MEMO, Qnil, 0, 0);

    rb_iterate(rb_each, obj, rb_block_given_p() ? max_ii : max_i, (VALUE)memo);
    result = memo->u1.value;
    rb_gc_force_recycle((VALUE)memo);
    return result;
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
    rb_yield_values(2, val, INT2FIX(memo->u3.cnt));
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

static VALUE
zip_i(val, memo)
    VALUE val;
    NODE *memo;
{
    VALUE result = memo->u1.value;
    VALUE args = memo->u2.value;
    int idx = memo->u3.cnt++;
    VALUE tmp;
    int i;

    tmp = rb_ary_new2(RARRAY(args)->len + 1);
    rb_ary_store(tmp, 0, val);
    for (i=0; i<RARRAY(args)->len; i++) {
	rb_ary_push(tmp, rb_ary_entry(RARRAY(args)->ptr[i], idx));
    }
    if (rb_block_given_p()) {
	rb_yield(tmp);
    }
    else {
	rb_ary_push(result, tmp);
    }
    return Qnil;
}

static VALUE
enum_zip(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    int i;
    VALUE result;
    NODE *memo;

    for (i=0; i<argc; i++) {
	argv[i] = rb_convert_type(argv[i], T_ARRAY, "Array", "to_ary");
    }
    result = rb_block_given_p() ? Qnil : rb_ary_new();
    memo = rb_node_newnode(NODE_MEMO, result, rb_ary_new4(argc, argv), 0);
    rb_iterate(rb_each, obj, zip_i, (VALUE)memo);

    return result;
}

void
Init_Enumerable()
{
    rb_mEnumerable = rb_define_module("Enumerable");

    rb_define_method(rb_mEnumerable,"to_a", enum_to_a, 0);
    rb_define_method(rb_mEnumerable,"entries", enum_to_a, 0);

    rb_define_method(rb_mEnumerable,"sort", enum_sort, 0);
    rb_define_method(rb_mEnumerable,"sort_by", enum_sort_by, 0);
    rb_define_method(rb_mEnumerable,"grep", enum_grep, 1);
    rb_define_method(rb_mEnumerable,"find", enum_find, -1);
    rb_define_method(rb_mEnumerable,"detect", enum_find, -1);
    rb_define_method(rb_mEnumerable,"find_all", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"select", enum_find_all, 0);
    rb_define_method(rb_mEnumerable,"reject", enum_reject, 0);
    rb_define_method(rb_mEnumerable,"collect", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"map", enum_collect, 0);
    rb_define_method(rb_mEnumerable,"inject", enum_inject, -1);
    rb_define_method(rb_mEnumerable,"partition", enum_partition, 0);
    rb_define_method(rb_mEnumerable,"all?", enum_all, 0);
    rb_define_method(rb_mEnumerable,"any?", enum_any, 0);
    rb_define_method(rb_mEnumerable,"min", enum_min, 0);
    rb_define_method(rb_mEnumerable,"max", enum_max, 0);
    rb_define_method(rb_mEnumerable,"member?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"include?", enum_member, 1);
    rb_define_method(rb_mEnumerable,"each_with_index", enum_each_with_index, 0);
    rb_define_method(rb_mEnumerable, "zip", enum_zip, -1);

    id_eqq  = rb_intern("===");
    id_each = rb_intern("each");
    id_cmp  = rb_intern("<=>");
}

