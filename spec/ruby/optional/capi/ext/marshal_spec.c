#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE marshal_spec_rb_marshal_dump(VALUE self, VALUE obj, VALUE port) {
  return rb_marshal_dump(obj, port);
}

VALUE marshal_spec_rb_marshal_load(VALUE self, VALUE data) {
  return rb_marshal_load(data);
}

void Init_marshal_spec(void) {
  VALUE cls = rb_define_class("CApiMarshalSpecs", rb_cObject);
  rb_define_method(cls, "rb_marshal_dump", marshal_spec_rb_marshal_dump, 2);
  rb_define_method(cls, "rb_marshal_load", marshal_spec_rb_marshal_load, 1);
}

#ifdef __cplusplus
}
#endif
