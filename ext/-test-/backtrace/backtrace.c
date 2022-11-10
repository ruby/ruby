#include <ruby/ruby.h>
#include <ruby/debug.h>

static VALUE proc_alloc_newobj_tracepoint;

static void
proc_alloc_newobj_tp_hook(VALUE tpval, void *data)
{
  rb_trace_arg_t *tracearg = rb_tracearg_from_tracepoint(tpval);
  VALUE newobj = rb_tracearg_object(tracearg);
  if (RBASIC(newobj)->klass == rb_cProc) {
    VALUE th = rb_thread_current();
    VALUE caller_locs = rb_funcall(th, rb_intern("backtrace_locations"), 1, INT2NUM(0));
    rb_gv_set("$captured_locs", caller_locs);
  }
}

static VALUE
proc_alloc_newobj_tp_setup(VALUE self)
{
  proc_alloc_newobj_tracepoint = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ,
                                                   proc_alloc_newobj_tp_hook, NULL);
  rb_tracepoint_enable(proc_alloc_newobj_tracepoint);
  return Qnil;
}

void
Init_backtrace(void)
{
  VALUE q = rb_define_module("Bug");
  rb_define_module_function(q, "proc_alloc_newobj_tp_setup", proc_alloc_newobj_tp_setup, 0);

  rb_global_variable(&proc_alloc_newobj_tracepoint);
}

