#include "ruby.h"
#include "rubyspec.h"

#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

VALUE proc_spec_rb_proc_new_function(RB_BLOCK_CALL_FUNC_ARGLIST(args, dummy)) {
  return rb_funcall(args, rb_intern("inspect"), 0);
}

VALUE proc_spec_rb_proc_new_function_arg(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  return arg;
}

VALUE proc_spec_rb_proc_new_function_argc(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  return INT2FIX(argc);
}

VALUE proc_spec_rb_proc_new_function_argv_n(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  int n = FIX2INT(arg);
  if (n < argc) {
    return argv[n];
  } else {
    rb_exc_raise(rb_exc_new2(rb_eArgError, "Arg index out of bounds."));
  }
}

VALUE proc_spec_rb_proc_new_function_callback_arg(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  return callback_arg;
}

VALUE proc_spec_rb_proc_new_function_blockarg(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  return blockarg;
}

VALUE proc_spec_rb_proc_new_function_block_given_p(VALUE arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg) {
  return rb_block_given_p() ? Qtrue : Qfalse;
}

VALUE proc_spec_rb_proc_new(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function, Qnil);
}

VALUE proc_spec_rb_proc_new_arg(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function_arg, Qnil);
}

VALUE proc_spec_rb_proc_new_argc(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function_argc, Qnil);
}

VALUE proc_spec_rb_proc_new_argv_n(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function_argv_n, Qnil);
}

VALUE proc_spec_rb_proc_new_callback_arg(VALUE self, VALUE arg) {
  return rb_proc_new(proc_spec_rb_proc_new_function_callback_arg, arg);
}

VALUE proc_spec_rb_proc_new_blockarg(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function_blockarg, Qnil);
}

VALUE proc_spec_rb_proc_new_block_given_p(VALUE self) {
  return rb_proc_new(proc_spec_rb_proc_new_function_block_given_p, Qnil);
}

VALUE proc_spec_rb_proc_arity(VALUE self, VALUE prc) {
  return INT2FIX(rb_proc_arity(prc));
}

VALUE proc_spec_rb_proc_call(VALUE self, VALUE prc, VALUE args) {
  return rb_proc_call(prc, args);
}

VALUE proc_spec_rb_obj_is_proc(VALUE self, VALUE prc) {
  return rb_obj_is_proc(prc);
}

/* This helper is not strictly necessary but reflects the code in wxRuby that
 * originally exposed issues with this Proc.new behavior.
 */
VALUE proc_spec_rb_Proc_new_helper(void) {
  return rb_funcall(rb_cProc, rb_intern("new"), 0);
}

VALUE proc_spec_rb_Proc_new(VALUE self, VALUE scenario) {
  switch(FIX2INT(scenario)) {
    case 0:
      return proc_spec_rb_Proc_new_helper();
    case 1:
      rb_funcall(self, rb_intern("call_nothing"), 0);
      return proc_spec_rb_Proc_new_helper();
    case 2:
      return rb_funcall(self, rb_intern("call_Proc_new"), 0);
    case 3:
      return rb_funcall(self, rb_intern("call_rb_Proc_new"), 0);
    case 4:
      return rb_funcall(self, rb_intern("call_rb_Proc_new_with_block"), 0);
    case 5:
      rb_funcall(self, rb_intern("call_rb_Proc_new_with_block"), 0);
      return proc_spec_rb_Proc_new_helper();
    case 6:
      return rb_funcall(self, rb_intern("call_block_given?"), 0);
    default:
      rb_raise(rb_eException, "invalid scenario");
  }

  return Qnil;
}

void Init_proc_spec(void) {
  VALUE cls = rb_define_class("CApiProcSpecs", rb_cObject);
  rb_define_method(cls, "rb_proc_new", proc_spec_rb_proc_new, 0);
  rb_define_method(cls, "rb_proc_new_arg", proc_spec_rb_proc_new_arg, 0);
  rb_define_method(cls, "rb_proc_new_argc", proc_spec_rb_proc_new_argc, 0);
  rb_define_method(cls, "rb_proc_new_argv_n", proc_spec_rb_proc_new_argv_n, 0);
  rb_define_method(cls, "rb_proc_new_callback_arg", proc_spec_rb_proc_new_callback_arg, 1);
  rb_define_method(cls, "rb_proc_new_blockarg", proc_spec_rb_proc_new_blockarg, 0);
  rb_define_method(cls, "rb_proc_new_block_given_p", proc_spec_rb_proc_new_block_given_p, 0);
  rb_define_method(cls, "rb_proc_arity", proc_spec_rb_proc_arity, 1);
  rb_define_method(cls, "rb_proc_call", proc_spec_rb_proc_call, 2);
  rb_define_method(cls, "rb_Proc_new", proc_spec_rb_Proc_new, 1);
  rb_define_method(cls, "rb_obj_is_proc", proc_spec_rb_obj_is_proc, 1);
}

#ifdef __cplusplus
}
#endif
