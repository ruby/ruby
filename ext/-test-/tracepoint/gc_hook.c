#include "ruby/ruby.h"
#include "ruby/debug.h"

static int invoking; /* TODO: should not be global variable */
extern VALUE tp_mBug;

static VALUE
invoke_proc_ensure(VALUE _)
{
    invoking = 0;
    return Qnil;
}

static VALUE
invoke_proc_begin(VALUE proc)
{
    return rb_proc_call(proc, rb_ary_new());
}

static void
invoke_proc(void *ivar_name)
{
    VALUE proc = rb_ivar_get(tp_mBug, rb_intern(ivar_name));
    invoking += 1;
    rb_ensure(invoke_proc_begin, proc, invoke_proc_ensure, 0);
}

static void
gc_start_end_i(VALUE tpval, void *data)
{
    if (0) {
        rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
        fprintf(stderr, "trace: %s\n", rb_tracearg_event_flag(tparg) == RUBY_INTERNAL_EVENT_GC_START ? "gc_start" : "gc_end");
    }

    if (invoking == 0) {
        /* will overwrite the existing handle with new data on the second and subsequent call */
        rb_postponed_job_handle_t h = rb_postponed_job_preregister(0, invoke_proc, data);
        rb_postponed_job_trigger(h);
    }
}

static VALUE
set_gc_hook(VALUE proc, rb_event_flag_t event, const char *tp_str, const char *proc_str)
{
    VALUE tpval;
    ID tp_key = rb_intern(tp_str);

    /* disable previous keys */
    if (rb_ivar_defined(tp_mBug, tp_key) != 0 &&
        RTEST(tpval = rb_ivar_get(tp_mBug, tp_key))) {
        rb_tracepoint_disable(tpval);
        rb_ivar_set(tp_mBug, tp_key, Qnil);
    }

    if (RTEST(proc)) {
        if (!rb_obj_is_proc(proc)) {
            rb_raise(rb_eTypeError, "trace_func needs to be Proc");
        }

        rb_ivar_set(tp_mBug, rb_intern(proc_str), proc);
        tpval = rb_tracepoint_new(0, event, gc_start_end_i, (void *)proc_str);
        rb_ivar_set(tp_mBug, tp_key, tpval);
        rb_tracepoint_enable(tpval);
    }

    return proc;
}

static VALUE
set_after_gc_start(VALUE _self, VALUE proc)
{
    return set_gc_hook(proc, RUBY_INTERNAL_EVENT_GC_START,
                       "__set_after_gc_start_tpval__", "__set_after_gc_start_proc__");
}

static VALUE
start_after_gc_exit(VALUE _self, VALUE proc)
{
    return set_gc_hook(proc, RUBY_INTERNAL_EVENT_GC_EXIT,
                       "__set_after_gc_exit_tpval__", "__set_after_gc_exit_proc__");
}

void
Init_gc_hook(VALUE module)
{
    rb_define_module_function(module, "after_gc_start_hook=", set_after_gc_start, 1);
    rb_define_module_function(module, "after_gc_exit_hook=", start_after_gc_exit, 1);
}
