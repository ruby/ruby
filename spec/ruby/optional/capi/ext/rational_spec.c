#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE rational_spec_rb_Rational(VALUE self, VALUE num, VALUE den) {
  return rb_Rational(num, den);
}

static VALUE rational_spec_rb_Rational1(VALUE self, VALUE num) {
  return rb_Rational1(num);
}

static VALUE rational_spec_rb_Rational2(VALUE self, VALUE num, VALUE den) {
  return rb_Rational2(num, den);
}

static VALUE rational_spec_rb_rational_new(VALUE self, VALUE num, VALUE den) {
  return rb_rational_new(num, den);
}

static VALUE rational_spec_rb_rational_new1(VALUE self, VALUE num) {
  return rb_rational_new1(num);
}

static VALUE rational_spec_rb_rational_new2(VALUE self, VALUE num, VALUE den) {
  return rb_rational_new2(num, den);
}

static VALUE rational_spec_rb_rational_num(VALUE self, VALUE rational) {
  return rb_rational_num(rational);
}

static VALUE rational_spec_rb_rational_den(VALUE self, VALUE rational) {
  return rb_rational_den(rational);
}

void Init_rational_spec(void) {
  VALUE cls = rb_define_class("CApiRationalSpecs", rb_cObject);
  rb_define_method(cls, "rb_Rational", rational_spec_rb_Rational, 2);
  rb_define_method(cls, "rb_Rational1", rational_spec_rb_Rational1, 1);
  rb_define_method(cls, "rb_Rational2", rational_spec_rb_Rational2, 2);
  rb_define_method(cls, "rb_rational_new", rational_spec_rb_rational_new, 2);
  rb_define_method(cls, "rb_rational_new1", rational_spec_rb_rational_new1, 1);
  rb_define_method(cls, "rb_rational_new2", rational_spec_rb_rational_new2, 2);
  rb_define_method(cls, "rb_rational_num", rational_spec_rb_rational_num, 1);
  rb_define_method(cls, "rb_rational_den", rational_spec_rb_rational_den, 1);
}

#ifdef __cplusplus
}
#endif
