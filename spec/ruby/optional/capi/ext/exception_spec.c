#include "ruby.h"
#include "rubyspec.h"

#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

VALUE exception_spec_rb_errinfo(VALUE self) {
  return rb_errinfo();
}

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

VALUE exception_spec_rb_syserr_new(VALUE self, VALUE num, VALUE msg) {
  int n = NUM2INT(num);
  char *cstr = NULL;

  if (msg != Qnil) {
    cstr = StringValuePtr(msg);
  }

  return rb_syserr_new(n, cstr);
}

VALUE exception_spec_rb_syserr_new_str(VALUE self, VALUE num, VALUE msg) {
  int n = NUM2INT(num);
  return rb_syserr_new_str(n, msg);
}

VALUE exception_spec_rb_make_exception(VALUE self, VALUE ary) {
  int argc = RARRAY_LENINT(ary);
  VALUE *argv = RARRAY_PTR(ary);
  return rb_make_exception(argc, argv);
}

void Init_exception_spec(void) {
  VALUE cls = rb_define_class("CApiExceptionSpecs", rb_cObject);
  rb_define_method(cls, "rb_errinfo", exception_spec_rb_errinfo, 0);
  rb_define_method(cls, "rb_exc_new", exception_spec_rb_exc_new, 1);
  rb_define_method(cls, "rb_exc_new2", exception_spec_rb_exc_new2, 1);
  rb_define_method(cls, "rb_exc_new3", exception_spec_rb_exc_new3, 1);
  rb_define_method(cls, "rb_exc_raise", exception_spec_rb_exc_raise, 1);
  rb_define_method(cls, "rb_set_errinfo", exception_spec_rb_set_errinfo, 1);
  rb_define_method(cls, "rb_syserr_new", exception_spec_rb_syserr_new, 2);
  rb_define_method(cls, "rb_syserr_new_str", exception_spec_rb_syserr_new_str, 2);
  rb_define_method(cls, "rb_make_exception", exception_spec_rb_make_exception, 1);
}

#ifdef __cplusplus
}
#endif
