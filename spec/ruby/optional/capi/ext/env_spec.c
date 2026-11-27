#include "ruby.h"
#include "rubyspec.h"

#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _WIN32
/* Change the environment the way a native extension would, through the C
   library rather than through ENV, so that specs can check that Ruby reads the
   process environment rather than a copy of its own. */

static VALUE env_spec_setenv(VALUE self, VALUE name, VALUE value) {
  return INT2FIX(setenv(StringValueCStr(name), StringValueCStr(value), 1));
}

static VALUE env_spec_unsetenv(VALUE self, VALUE name) {
  return INT2FIX(unsetenv(StringValueCStr(name)));
}

static VALUE env_spec_getenv(VALUE self, VALUE name) {
  char *value = getenv(StringValueCStr(name));
  return value == NULL ? Qnil : rb_str_new_cstr(value);
}
#endif

void Init_env_spec(void) {
#ifndef _WIN32
  VALUE cls = rb_define_class("CApiEnvSpecs", rb_cObject);
  rb_define_method(cls, "setenv", env_spec_setenv, 2);
  rb_define_method(cls, "unsetenv", env_spec_unsetenv, 1);
  rb_define_method(cls, "getenv", env_spec_getenv, 1);
#endif
}

#ifdef __cplusplus
}
#endif
