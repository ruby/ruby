#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE binding_spec_get_binding(VALUE self) {
  return rb_funcall(self, rb_intern("binding"), 0);
}

void Init_binding_spec(void) {
  VALUE cls = rb_define_class("CApiBindingSpecs", rb_cObject);
  rb_define_method(cls, "get_binding", binding_spec_get_binding, 0);
}

#ifdef __cplusplus
}
#endif
