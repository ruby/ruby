#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE basic_object_spec_RBASIC_CLASS(VALUE self, VALUE obj) {
  return RBASIC_CLASS(obj);
}

void Init_basic_object_spec(void) {
  VALUE cls = rb_define_class("CApiBasicObjectSpecs", rb_cObject);
  rb_define_method(cls, "RBASIC_CLASS", basic_object_spec_RBASIC_CLASS, 1);
}

#ifdef __cplusplus
}
#endif
