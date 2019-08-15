#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE numeric_spec_size_of_VALUE(VALUE self) {
  return INT2FIX(sizeof(VALUE));
}

static VALUE numeric_spec_size_of_long_long(VALUE self) {
  return INT2FIX(sizeof(LONG_LONG));
}

static VALUE numeric_spec_NUM2CHR(VALUE self, VALUE value) {
  return INT2FIX(NUM2CHR(value));
}

static VALUE numeric_spec_rb_int2inum_14(VALUE self) {
  return rb_int2inum(14);
}

static VALUE numeric_spec_rb_uint2inum_14(VALUE self) {
  return rb_uint2inum(14);
}

static VALUE numeric_spec_rb_uint2inum_n14(VALUE self) {
  return rb_uint2inum(-14);
}

static VALUE numeric_spec_rb_Integer(VALUE self, VALUE str) {
  return rb_Integer(str);
}

static VALUE numeric_spec_rb_ll2inum_14(VALUE self) {
  return rb_ll2inum(14);
}

static VALUE numeric_spec_rb_ull2inum_14(VALUE self) {
  return rb_ull2inum(14);
}

static VALUE numeric_spec_rb_ull2inum_n14(VALUE self) {
  return rb_ull2inum(-14);
}

static VALUE numeric_spec_NUM2DBL(VALUE self, VALUE num) {
  return rb_float_new(NUM2DBL(num));
}

static VALUE numeric_spec_NUM2INT(VALUE self, VALUE num) {
  return LONG2NUM(NUM2INT(num));
}

static VALUE numeric_spec_INT2NUM(VALUE self, VALUE num) {
  return INT2NUM(NUM2LONG(num));
}

static VALUE numeric_spec_NUM2LONG(VALUE self, VALUE num) {
  return LONG2NUM(NUM2LONG(num));
}

static VALUE numeric_spec_NUM2UINT(VALUE self, VALUE num) {
  return ULONG2NUM(NUM2UINT(num));
}

static VALUE numeric_spec_NUM2ULONG(VALUE self, VALUE num) {
  return ULONG2NUM(NUM2ULONG(num));
}

static VALUE numeric_spec_rb_num_zerodiv(VALUE self) {
  rb_num_zerodiv();
  return Qnil;
}

static VALUE numeric_spec_rb_cmpint(VALUE self, VALUE val, VALUE b) {
  return INT2FIX(rb_cmpint(val, val, b));
}

static VALUE numeric_spec_rb_num_coerce_bin(VALUE self, VALUE x, VALUE y, VALUE op) {
  return rb_num_coerce_bin(x, y, SYM2ID(op));
}

static VALUE numeric_spec_rb_num_coerce_cmp(VALUE self, VALUE x, VALUE y, VALUE op) {
  return rb_num_coerce_cmp(x, y, SYM2ID(op));
}

static VALUE numeric_spec_rb_num_coerce_relop(VALUE self, VALUE x, VALUE y, VALUE op) {
  return rb_num_coerce_relop(x, y, SYM2ID(op));
}

static VALUE numeric_spec_rb_absint_singlebit_p(VALUE self, VALUE num) {
  return INT2FIX(rb_absint_singlebit_p(num));
}

void Init_numeric_spec(void) {
  VALUE cls = rb_define_class("CApiNumericSpecs", rb_cObject);
  rb_define_method(cls, "size_of_VALUE", numeric_spec_size_of_VALUE, 0);
  rb_define_method(cls, "size_of_long_long", numeric_spec_size_of_long_long, 0);
  rb_define_method(cls, "NUM2CHR", numeric_spec_NUM2CHR, 1);
  rb_define_method(cls, "rb_int2inum_14", numeric_spec_rb_int2inum_14, 0);
  rb_define_method(cls, "rb_uint2inum_14", numeric_spec_rb_uint2inum_14, 0);
  rb_define_method(cls, "rb_uint2inum_n14", numeric_spec_rb_uint2inum_n14, 0);
  rb_define_method(cls, "rb_Integer", numeric_spec_rb_Integer, 1);
  rb_define_method(cls, "rb_ll2inum_14", numeric_spec_rb_ll2inum_14, 0);
  rb_define_method(cls, "rb_ull2inum_14", numeric_spec_rb_ull2inum_14, 0);
  rb_define_method(cls, "rb_ull2inum_n14", numeric_spec_rb_ull2inum_n14, 0);
  rb_define_method(cls, "NUM2DBL", numeric_spec_NUM2DBL, 1);
  rb_define_method(cls, "NUM2INT", numeric_spec_NUM2INT, 1);
  rb_define_method(cls, "NUM2LONG", numeric_spec_NUM2LONG, 1);
  rb_define_method(cls, "INT2NUM", numeric_spec_INT2NUM, 1);
  rb_define_method(cls, "NUM2UINT", numeric_spec_NUM2UINT, 1);
  rb_define_method(cls, "NUM2ULONG", numeric_spec_NUM2ULONG, 1);
  rb_define_method(cls, "rb_num_zerodiv", numeric_spec_rb_num_zerodiv, 0);
  rb_define_method(cls, "rb_cmpint", numeric_spec_rb_cmpint, 2);
  rb_define_method(cls, "rb_num_coerce_bin", numeric_spec_rb_num_coerce_bin, 3);
  rb_define_method(cls, "rb_num_coerce_cmp", numeric_spec_rb_num_coerce_cmp, 3);
  rb_define_method(cls, "rb_num_coerce_relop", numeric_spec_rb_num_coerce_relop, 3);
rb_define_method(cls, "rb_absint_singlebit_p", numeric_spec_rb_absint_singlebit_p, 1);
}

#ifdef __cplusplus
}
#endif
