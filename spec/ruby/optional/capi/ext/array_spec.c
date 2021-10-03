#include "ruby.h"
#include "rubyspec.h"

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

static VALUE array_spec_rb_Array(VALUE self, VALUE object) {
  return rb_Array(object);
}

static VALUE array_spec_RARRAY_PTR_iterate(VALUE self, VALUE array) {
  int i;
  VALUE* ptr;

  ptr = RARRAY_PTR(array);
  for(i = 0; i < RARRAY_LEN(array); i++) {
    rb_yield(ptr[i]);
  }
  return Qnil;
}

static VALUE array_spec_RARRAY_PTR_assign(VALUE self, VALUE array, VALUE value) {
  int i;
  VALUE* ptr;

  ptr = RARRAY_PTR(array);
  for(i = 0; i < RARRAY_LEN(array); i++) {
    ptr[i] = value;
  }
  return Qnil;
}


static VALUE array_spec_RARRAY_PTR_memcpy(VALUE self, VALUE array1, VALUE array2) {
  VALUE *ptr1, *ptr2;
  long size;
  size = RARRAY_LEN(array1);
  ptr1 = RARRAY_PTR(array1);
  ptr2 = RARRAY_PTR(array2);
  if (ptr1 != NULL && ptr2 != NULL) {
    memcpy(ptr2, ptr1, size * sizeof(VALUE));
  }
  return Qnil;
}

static VALUE array_spec_RARRAY_LEN(VALUE self, VALUE array) {
  return INT2FIX(RARRAY_LEN(array));
}

static VALUE array_spec_RARRAY_AREF(VALUE self, VALUE array, VALUE index) {
  return RARRAY_AREF(array, FIX2INT(index));
}

static VALUE array_spec_RARRAY_ASET(VALUE self, VALUE array, VALUE index, VALUE value) {
  RARRAY_ASET(array, FIX2INT(index), value);
  return value;
}

static VALUE array_spec_rb_ary_aref(int argc, VALUE *argv, VALUE self) {
  VALUE ary, args;
  rb_scan_args(argc, argv, "1*", &ary, &args);
  return rb_ary_aref((int)RARRAY_LEN(args), RARRAY_PTR(args), ary);
}

static VALUE array_spec_rb_ary_clear(VALUE self, VALUE array) {
  return rb_ary_clear(array);
}

static VALUE array_spec_rb_ary_delete(VALUE self, VALUE array, VALUE item) {
  return rb_ary_delete(array, item);
}

static VALUE array_spec_rb_ary_delete_at(VALUE self, VALUE array, VALUE index) {
  return rb_ary_delete_at(array, NUM2LONG(index));
}

static VALUE array_spec_rb_ary_dup(VALUE self, VALUE array) {
  return rb_ary_dup(array);
}

static VALUE array_spec_rb_ary_entry(VALUE self, VALUE array, VALUE offset) {
  return rb_ary_entry(array, FIX2INT(offset));
}

static VALUE array_spec_rb_ary_includes(VALUE self, VALUE ary, VALUE item) {
  return rb_ary_includes(ary, item);
}

static VALUE array_spec_rb_ary_join(VALUE self, VALUE array1, VALUE array2) {
  return rb_ary_join(array1, array2);
}

static VALUE array_spec_rb_ary_to_s(VALUE self, VALUE array) {
  return rb_ary_to_s(array);
}

static VALUE array_spec_rb_ary_new(VALUE self) {
  VALUE ret;
  ret = rb_ary_new();
  return ret;
}

static VALUE array_spec_rb_ary_new2(VALUE self, VALUE length) {
  return rb_ary_new2(NUM2LONG(length));
}

static VALUE array_spec_rb_ary_new_capa(VALUE self, VALUE length) {
  return rb_ary_new_capa(NUM2LONG(length));
}

static VALUE array_spec_rb_ary_new3(VALUE self, VALUE first, VALUE second, VALUE third) {
  return rb_ary_new3(3, first, second, third);
}

static VALUE array_spec_rb_ary_new_from_args(VALUE self, VALUE first, VALUE second, VALUE third) {
  return rb_ary_new_from_args(3, first, second, third);
}

static VALUE array_spec_rb_ary_new4(VALUE self, VALUE first, VALUE second, VALUE third) {
  VALUE values[3];
  values[0] = first;
  values[1] = second;
  values[2] = third;
  return rb_ary_new4(3, values);
}

static VALUE array_spec_rb_ary_new_from_values(VALUE self, VALUE first, VALUE second, VALUE third) {
  VALUE values[3];
  values[0] = first;
  values[1] = second;
  values[2] = third;
  return rb_ary_new_from_values(3, values);
}

static VALUE array_spec_rb_ary_pop(VALUE self, VALUE array) {
  return rb_ary_pop(array);
}

static VALUE array_spec_rb_ary_push(VALUE self, VALUE array, VALUE item) {
  rb_ary_push(array, item);
  return array;
}

static VALUE array_spec_rb_ary_cat(int argc, VALUE *argv, VALUE self) {
  VALUE ary, args;
  rb_scan_args(argc, argv, "1*", &ary, &args);
  return rb_ary_cat(ary, RARRAY_PTR(args), RARRAY_LEN(args));
}

static VALUE array_spec_rb_ary_reverse(VALUE self, VALUE array) {
  return rb_ary_reverse(array);
}

static VALUE array_spec_rb_ary_rotate(VALUE self, VALUE array, VALUE count) {
  return rb_ary_rotate(array, NUM2LONG(count));
}

static VALUE array_spec_rb_ary_shift(VALUE self, VALUE array) {
  return rb_ary_shift(array);
}

static VALUE array_spec_rb_ary_sort(VALUE self, VALUE array) {
  return rb_ary_sort(array);
}

static VALUE array_spec_rb_ary_sort_bang(VALUE self, VALUE array) {
  return rb_ary_sort_bang(array);
}

static VALUE array_spec_rb_ary_store(VALUE self, VALUE array, VALUE offset, VALUE value) {
  rb_ary_store(array, FIX2INT(offset), value);

  return Qnil;
}

static VALUE array_spec_rb_ary_concat(VALUE self, VALUE array1, VALUE array2) {
  return rb_ary_concat(array1, array2);
}

static VALUE array_spec_rb_ary_plus(VALUE self, VALUE array1, VALUE array2) {
  return rb_ary_plus(array1, array2);
}

static VALUE array_spec_rb_ary_unshift(VALUE self, VALUE array, VALUE val) {
  return rb_ary_unshift(array, val);
}

static VALUE array_spec_rb_assoc_new(VALUE self, VALUE first, VALUE second) {
  return rb_assoc_new(first, second);
}

static VALUE copy_ary(RB_BLOCK_CALL_FUNC_ARGLIST(el, new_ary)) {
  return rb_ary_push(new_ary, el);
}

static VALUE array_spec_rb_block_call(VALUE self, VALUE ary) {
  VALUE new_ary = rb_ary_new();

  rb_block_call(ary, rb_intern("each"), 0, 0, copy_ary, new_ary);

  return new_ary;
}

static VALUE sub_pair(RB_BLOCK_CALL_FUNC_ARGLIST(el, holder)) {
  return rb_ary_push(holder, rb_ary_entry(el, 1));
}

static VALUE array_spec_rb_block_call_each_pair(VALUE self, VALUE obj) {
  VALUE new_ary = rb_ary_new();

  rb_block_call(obj, rb_intern("each_pair"), 0, 0, sub_pair, new_ary);

  return new_ary;
}

static VALUE iter_yield(RB_BLOCK_CALL_FUNC_ARGLIST(el, ary)) {
  rb_yield(el);
  return Qnil;
}

static VALUE array_spec_rb_block_call_then_yield(VALUE self, VALUE obj) {
  rb_block_call(obj, rb_intern("each"), 0, 0, iter_yield, obj);
  return Qnil;
}

static VALUE array_spec_rb_mem_clear(VALUE self, VALUE obj) {
  VALUE ary[1];
  ary[0] = obj;
  rb_mem_clear(ary, 1);
  return ary[0];
}

static VALUE array_spec_rb_ary_freeze(VALUE self, VALUE ary) {
  return rb_ary_freeze(ary);
}

static VALUE array_spec_rb_ary_to_ary(VALUE self, VALUE ary) {
  return rb_ary_to_ary(ary);
}

static VALUE array_spec_rb_ary_subseq(VALUE self, VALUE ary, VALUE begin, VALUE len) {
  return rb_ary_subseq(ary, FIX2LONG(begin), FIX2LONG(len));
}

void Init_array_spec(void) {
  VALUE cls = rb_define_class("CApiArraySpecs", rb_cObject);
  rb_define_method(cls, "rb_Array", array_spec_rb_Array, 1);
  rb_define_method(cls, "RARRAY_LEN", array_spec_RARRAY_LEN, 1);
  rb_define_method(cls, "RARRAY_PTR_iterate", array_spec_RARRAY_PTR_iterate, 1);
  rb_define_method(cls, "RARRAY_PTR_assign", array_spec_RARRAY_PTR_assign, 2);
  rb_define_method(cls, "RARRAY_PTR_memcpy", array_spec_RARRAY_PTR_memcpy, 2);
  rb_define_method(cls, "RARRAY_AREF", array_spec_RARRAY_AREF, 2);
  rb_define_method(cls, "RARRAY_ASET", array_spec_RARRAY_ASET, 3);
  rb_define_method(cls, "rb_ary_aref", array_spec_rb_ary_aref, -1);
  rb_define_method(cls, "rb_ary_clear", array_spec_rb_ary_clear, 1);
  rb_define_method(cls, "rb_ary_delete", array_spec_rb_ary_delete, 2);
  rb_define_method(cls, "rb_ary_delete_at", array_spec_rb_ary_delete_at, 2);
  rb_define_method(cls, "rb_ary_dup", array_spec_rb_ary_dup, 1);
  rb_define_method(cls, "rb_ary_entry", array_spec_rb_ary_entry, 2);
  rb_define_method(cls, "rb_ary_includes", array_spec_rb_ary_includes, 2);
  rb_define_method(cls, "rb_ary_join", array_spec_rb_ary_join, 2);
  rb_define_method(cls, "rb_ary_to_s", array_spec_rb_ary_to_s, 1);
  rb_define_method(cls, "rb_ary_new", array_spec_rb_ary_new, 0);
  rb_define_method(cls, "rb_ary_new2", array_spec_rb_ary_new2, 1);
  rb_define_method(cls, "rb_ary_new_capa", array_spec_rb_ary_new_capa, 1);
  rb_define_method(cls, "rb_ary_new3", array_spec_rb_ary_new3, 3);
  rb_define_method(cls, "rb_ary_new_from_args", array_spec_rb_ary_new_from_args, 3);
  rb_define_method(cls, "rb_ary_new4", array_spec_rb_ary_new4, 3);
  rb_define_method(cls, "rb_ary_new_from_values", array_spec_rb_ary_new_from_values, 3);
  rb_define_method(cls, "rb_ary_pop", array_spec_rb_ary_pop, 1);
  rb_define_method(cls, "rb_ary_push", array_spec_rb_ary_push, 2);
  rb_define_method(cls, "rb_ary_cat", array_spec_rb_ary_cat, -1);
  rb_define_method(cls, "rb_ary_reverse", array_spec_rb_ary_reverse, 1);
  rb_define_method(cls, "rb_ary_rotate", array_spec_rb_ary_rotate, 2);
  rb_define_method(cls, "rb_ary_shift", array_spec_rb_ary_shift, 1);
  rb_define_method(cls, "rb_ary_sort", array_spec_rb_ary_sort, 1);
  rb_define_method(cls, "rb_ary_sort_bang", array_spec_rb_ary_sort_bang, 1);
  rb_define_method(cls, "rb_ary_store", array_spec_rb_ary_store, 3);
  rb_define_method(cls, "rb_ary_concat", array_spec_rb_ary_concat, 2);
  rb_define_method(cls, "rb_ary_plus", array_spec_rb_ary_plus, 2);
  rb_define_method(cls, "rb_ary_unshift", array_spec_rb_ary_unshift, 2);
  rb_define_method(cls, "rb_assoc_new", array_spec_rb_assoc_new, 2);
  rb_define_method(cls, "rb_block_call", array_spec_rb_block_call, 1);
  rb_define_method(cls, "rb_block_call_each_pair", array_spec_rb_block_call_each_pair, 1);
  rb_define_method(cls, "rb_block_call_then_yield", array_spec_rb_block_call_then_yield, 1);
  rb_define_method(cls, "rb_mem_clear", array_spec_rb_mem_clear, 1);
  rb_define_method(cls, "rb_ary_freeze", array_spec_rb_ary_freeze, 1);
  rb_define_method(cls, "rb_ary_to_ary", array_spec_rb_ary_to_ary, 1);
  rb_define_method(cls, "rb_ary_subseq", array_spec_rb_ary_subseq, 3);
}

#ifdef __cplusplus
}
#endif
