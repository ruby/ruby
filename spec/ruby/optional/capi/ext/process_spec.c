#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifdef RUBY_VERSION_IS_4_1
static VALUE process_spec_rb_process_status_for(VALUE self, VALUE pid,
    VALUE status, VALUE error) {
  return rb_process_status_for(NUM2PIDT(pid), NUM2INT(status), NUM2INT(error));
}
#endif

void Init_process_spec(void) {
  VALUE cls = rb_define_class("CApiProcessSpecs", rb_cObject);

#ifdef RUBY_VERSION_IS_4_1
  rb_define_method(cls, "rb_process_status_for",
      process_spec_rb_process_status_for, 3);
#endif
}

#ifdef __cplusplus
}
#endif
