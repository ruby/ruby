#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE mutex_spec_rb_mutex_new(VALUE self) {
  return rb_mutex_new();
}

VALUE mutex_spec_rb_mutex_locked_p(VALUE self, VALUE mutex) {
  return rb_mutex_locked_p(mutex);
}

VALUE mutex_spec_rb_mutex_trylock(VALUE self, VALUE mutex) {
  return rb_mutex_trylock(mutex);
}

VALUE mutex_spec_rb_mutex_lock(VALUE self, VALUE mutex) {
  return rb_mutex_lock(mutex);
}

VALUE mutex_spec_rb_mutex_unlock(VALUE self, VALUE mutex) {
  return rb_mutex_unlock(mutex);
}

VALUE mutex_spec_rb_mutex_sleep(VALUE self, VALUE mutex, VALUE timeout) {
  return rb_mutex_sleep(mutex, timeout);
}


VALUE mutex_spec_rb_mutex_callback(VALUE arg) {
  return rb_funcall(arg, rb_intern("call"), 0);
}

VALUE mutex_spec_rb_mutex_synchronize(VALUE self, VALUE mutex, VALUE value) {
  return rb_mutex_synchronize(mutex, mutex_spec_rb_mutex_callback, value);
}

void Init_mutex_spec(void) {
  VALUE cls = rb_define_class("CApiMutexSpecs", rb_cObject);
  rb_define_method(cls, "rb_mutex_new", mutex_spec_rb_mutex_new, 0);
  rb_define_method(cls, "rb_mutex_locked_p", mutex_spec_rb_mutex_locked_p, 1);
  rb_define_method(cls, "rb_mutex_trylock", mutex_spec_rb_mutex_trylock, 1);
  rb_define_method(cls, "rb_mutex_lock", mutex_spec_rb_mutex_lock, 1);
  rb_define_method(cls, "rb_mutex_unlock", mutex_spec_rb_mutex_unlock, 1);
  rb_define_method(cls, "rb_mutex_sleep", mutex_spec_rb_mutex_sleep, 2);
  rb_define_method(cls, "rb_mutex_synchronize", mutex_spec_rb_mutex_synchronize, 2);
}

#ifdef __cplusplus
}
#endif

