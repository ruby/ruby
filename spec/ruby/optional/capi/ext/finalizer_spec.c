#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE define_finalizer(VALUE self, VALUE obj, VALUE finalizer) {
  return rb_define_finalizer(obj, finalizer);
}

static VALUE undefine_finalizer(VALUE self, VALUE obj) {
// Ruby 3.4.0 and 3.4.1 have a bug where rb_undefine_finalizer is missing
// See: https://bugs.ruby-lang.org/issues/20981
#if RUBY_API_VERSION_CODE == 30400 && (RUBY_VERSION_TEENY == 0 || RUBY_VERSION_TEENY == 1)
  return Qnil;
#else
  return rb_undefine_finalizer(obj);
#endif
}

void Init_finalizer_spec(void) {
  VALUE cls = rb_define_class("CApiFinalizerSpecs", rb_cObject);

  rb_define_method(cls, "rb_define_finalizer", define_finalizer, 2);
  rb_define_method(cls, "rb_undefine_finalizer", undefine_finalizer, 1);
}

#ifdef __cplusplus
}
#endif
