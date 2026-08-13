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

#ifdef RUBY_VERSION_IS_4_1
  VALUE cls = rb_define_class("CApiProcessSpecs", rb_cObject);

  rb_define_method(cls, "rb_process_status_for",
      process_spec_rb_process_status_for, 3);
#else
  rb_define_class("CApiProcessSpecs", rb_cObject);
#endif
}

#ifdef __cplusplus
}
#endif
