#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE fixnum_spec_FIX2INT(VALUE self, VALUE value) {
  int i = FIX2INT(value);
  return INT2NUM(i);
}

static VALUE fixnum_spec_FIX2UINT(VALUE self, VALUE value) {
  unsigned int i = FIX2UINT(value);
  return UINT2NUM(i);
}

void Init_fixnum_spec(void) {
  VALUE cls = rb_define_class("CApiFixnumSpecs", rb_cObject);
  rb_define_method(cls, "FIX2INT", fixnum_spec_FIX2INT, 1);
  rb_define_method(cls, "FIX2UINT", fixnum_spec_FIX2UINT, 1);
}

#ifdef __cplusplus
}
#endif
