#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE fiber_spec_rb_fiber_current(VALUE self) {
  return rb_fiber_current();
}

VALUE fiber_spec_rb_fiber_alive_p(VALUE self, VALUE fiber) {
  return rb_fiber_alive_p(fiber);
}

VALUE fiber_spec_rb_fiber_resume(VALUE self, VALUE fiber, VALUE ary) {
    long argc = RARRAY_LEN(ary);
    VALUE *argv = (VALUE*) alloca(sizeof(VALUE) * argc);
    int i;

    for (i = 0; i < argc; i++) {
      argv[i] = rb_ary_entry(ary, i);
    }

  return rb_fiber_resume(fiber, (int)argc, argv);
}

VALUE fiber_spec_rb_fiber_yield(VALUE self, VALUE ary) {
  long argc = RARRAY_LEN(ary);
  VALUE *argv = (VALUE*) alloca(sizeof(VALUE) * argc);
  int i;

  for (i = 0; i < argc; i++) {
    argv[i] = rb_ary_entry(ary, i);
  }
  return rb_fiber_yield((int)argc, argv);
}

VALUE fiber_spec_rb_fiber_new_function(RB_BLOCK_CALL_FUNC_ARGLIST(args, dummy)) {
  return rb_funcall(args, rb_intern("inspect"), 0);
}

VALUE fiber_spec_rb_fiber_new(VALUE self) {
  return rb_fiber_new(fiber_spec_rb_fiber_new_function, Qnil);
}

void Init_fiber_spec(void) {
  VALUE cls = rb_define_class("CApiFiberSpecs", rb_cObject);
  rb_define_method(cls, "rb_fiber_current", fiber_spec_rb_fiber_current, 0);
  rb_define_method(cls, "rb_fiber_alive_p", fiber_spec_rb_fiber_alive_p, 1);
  rb_define_method(cls, "rb_fiber_resume", fiber_spec_rb_fiber_resume, 2);
  rb_define_method(cls, "rb_fiber_yield", fiber_spec_rb_fiber_yield, 1);
  rb_define_method(cls, "rb_fiber_new", fiber_spec_rb_fiber_new, 0);
}

#ifdef __cplusplus
}
#endif
