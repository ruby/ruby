#include "ruby/ruby.h"
#include "ruby/debug.h"

static int invoking; /* TODO: should not be global variable */
static VALUE gc_start_proc;
static VALUE gc_end_proc;
static rb_postponed_job_handle_t invoking_proc_pjob;
static bool pjob_execute_gc_start_proc_p;
static bool pjob_execute_gc_end_proc_p;

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
invoke_proc(void *unused)
{
    if (pjob_execute_gc_start_proc_p) {
        pjob_execute_gc_start_proc_p = false;
        invoking += 1;
        rb_ensure(invoke_proc_begin, gc_start_proc, invoke_proc_ensure, 0);
    }
    if (pjob_execute_gc_end_proc_p) {
        pjob_execute_gc_end_proc_p = false;
        invoking += 1;
        rb_ensure(invoke_proc_begin, gc_end_proc, invoke_proc_ensure, 0);
    }
}

static void
gc_start_end_i(VALUE tpval, void *data)
{
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    if (0) {
        fprintf(stderr, "trace: %s\n", rb_tracearg_event_flag(tparg) == RUBY_INTERNAL_EVENT_GC_START ? "gc_start" : "gc_end");
    }

    if (invoking == 0) {
        if (rb_tracearg_event_flag(tparg) == RUBY_INTERNAL_EVENT_GC_START) {
            pjob_execute_gc_start_proc_p = true;
        } else {
            pjob_execute_gc_end_proc_p = true;
        }
        rb_postponed_job_trigger(invoking_proc_pjob);
    }
}

static VALUE
set_gc_hook(VALUE module, VALUE proc, rb_event_flag_t event, const char *tp_str, const char *proc_str)
{
    VALUE tpval;
    ID tp_key = rb_intern(tp_str);

    /* disable previous keys */
    if (rb_ivar_defined(module, tp_key) != 0 &&
        RTEST(tpval = rb_ivar_get(module, tp_key))) {
        rb_tracepoint_disable(tpval);
        rb_ivar_set(module, tp_key, Qnil);
    }

    if (RTEST(proc)) {
        if (!rb_obj_is_proc(proc)) {
            rb_raise(rb_eTypeError, "trace_func needs to be Proc");
        }
        if (event == RUBY_INTERNAL_EVENT_GC_START) {
            gc_start_proc = proc;
        } else {
            gc_end_proc = proc;
        }

        tpval = rb_tracepoint_new(0, event, gc_start_end_i, 0);
        rb_ivar_set(module, tp_key, tpval);
        rb_tracepoint_enable(tpval);
    }

    return proc;
}

static VALUE
set_after_gc_start(VALUE module, VALUE proc)
{
    return set_gc_hook(module, proc, RUBY_INTERNAL_EVENT_GC_START,
                       "__set_after_gc_start_tpval__", "__set_after_gc_start_proc__");
}

static VALUE
start_after_gc_exit(VALUE module, VALUE proc)
{
    return set_gc_hook(module, proc, RUBY_INTERNAL_EVENT_GC_EXIT,
                       "__set_after_gc_exit_tpval__", "__set_after_gc_exit_proc__");
}

void
Init_gc_hook(VALUE module)
{
    rb_define_module_function(module, "after_gc_start_hook=", set_after_gc_start, 1);
    rb_define_module_function(module, "after_gc_exit_hook=", start_after_gc_exit, 1);
    rb_gc_register_address(&gc_start_proc);
    rb_gc_register_address(&gc_end_proc);
    invoking_proc_pjob = rb_postponed_job_preregister(0, invoke_proc, NULL);
    if (invoking_proc_pjob == POSTPONED_JOB_HANDLE_INVALID) {
        rb_raise(rb_eStandardError, "could not preregister invoke_proc");
    }
}
