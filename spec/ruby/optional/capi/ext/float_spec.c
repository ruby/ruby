#include "ruby.h"
#include "rubyspec.h"

#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

static VALUE float_spec_new_zero(VALUE self) {
  double flt = 0;
  return rb_float_new(flt);
}

static VALUE float_spec_new_point_five(VALUE self) {
  double flt = 0.555;
  return rb_float_new(flt);
}

static VALUE float_spec_rb_Float(VALUE self, VALUE float_str) {
  return rb_Float(float_str);
}

static VALUE float_spec_RFLOAT_VALUE(VALUE self, VALUE float_h) {
  return rb_float_new(RFLOAT_VALUE(float_h));
}

void Init_float_spec(void) {
  VALUE cls = rb_define_class("CApiFloatSpecs", rb_cObject);
  rb_define_method(cls, "new_zero", float_spec_new_zero, 0);
  rb_define_method(cls, "new_point_five", float_spec_new_point_five, 0);
  rb_define_method(cls, "rb_Float", float_spec_rb_Float, 1);
  rb_define_method(cls, "RFLOAT_VALUE", float_spec_RFLOAT_VALUE, 1);
}

#ifdef __cplusplus
}
#endif
