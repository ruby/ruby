#include "ruby.h"
#include "rubyspec.h"

#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

VALUE exception_spec_rb_exc_new(VALUE self, VALUE str) {
  char *cstr = StringValuePtr(str);
  return rb_exc_new(rb_eException, cstr, strlen(cstr));
}

VALUE exception_spec_rb_exc_new2(VALUE self, VALUE str) {
  char *cstr = StringValuePtr(str);
  return rb_exc_new2(rb_eException, cstr);
}

VALUE exception_spec_rb_exc_new3(VALUE self, VALUE str) {
  return rb_exc_new3(rb_eException, str);
}

VALUE exception_spec_rb_exc_raise(VALUE self, VALUE exc) {
    if (self != Qundef) rb_exc_raise(exc);
  return Qnil;
}

VALUE exception_spec_rb_set_errinfo(VALUE self, VALUE exc) {
  rb_set_errinfo(exc);
  return Qnil;
}

void Init_exception_spec(void) {
  VALUE cls = rb_define_class("CApiExceptionSpecs", rb_cObject);
  rb_define_method(cls, "rb_exc_new", exception_spec_rb_exc_new, 1);
  rb_define_method(cls, "rb_exc_new2", exception_spec_rb_exc_new2, 1);
  rb_define_method(cls, "rb_exc_new3", exception_spec_rb_exc_new3, 1);
  rb_define_method(cls, "rb_exc_raise", exception_spec_rb_exc_raise, 1);
  rb_define_method(cls, "rb_set_errinfo", exception_spec_rb_set_errinfo, 1);
}

#ifdef __cplusplus
}
#endif
