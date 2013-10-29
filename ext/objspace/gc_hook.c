/**********************************************************************

  gc_hook.c - GC hook mechanism/ObjectSpace extender for MRI.

  $Author$
  created at: Tue May 28 01:34:25 2013

  NOTE: This extension library is not expected to exist except C Ruby.
  NOTE: This feature is an example usage of internal event tracing APIs.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/debug.h"

static int invoking; /* TODO: should not be global variable */

static VALUE
invoke_proc_ensure(void *dmy)
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
invoke_proc(void *data)
{
    VALUE proc = (VALUE)data;
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
	rb_postponed_job_register(0, invoke_proc, data);
    }
}

static VALUE
set_gc_hook(VALUE rb_mObjSpace, VALUE proc, rb_event_flag_t event, const char *tp_str, const char *proc_str)
{
    VALUE tpval;
    ID tp_key = rb_intern(tp_str);
    ID proc_key = rb_intern(proc_str);

    /* disable previous keys */
    if (rb_ivar_defined(rb_mObjSpace, tp_key) != 0 &&
	RTEST(tpval = rb_ivar_get(rb_mObjSpace, tp_key))) {
	rb_tracepoint_disable(tpval);
	rb_ivar_set(rb_mObjSpace, tp_key, Qnil);
	rb_ivar_set(rb_mObjSpace, proc_key, Qnil);
    }

    if (RTEST(proc)) {
	if (!rb_obj_is_proc(proc)) {
	    rb_raise(rb_eTypeError, "trace_func needs to be Proc");
	}

	tpval = rb_tracepoint_new(0, event, gc_start_end_i, (void *)proc);
	rb_ivar_set(rb_mObjSpace, tp_key, tpval);
	rb_ivar_set(rb_mObjSpace, proc_key, proc); /* GC guard */
	rb_tracepoint_enable(tpval);
    }

    return proc;
}

static VALUE
set_after_gc_start(VALUE rb_mObjSpace, VALUE proc)
{
    return set_gc_hook(rb_mObjSpace, proc, RUBY_INTERNAL_EVENT_GC_START,
		       "__set_after_gc_start_tpval__", "__set_after_gc_start_proc__");
}

static VALUE
set_after_gc_end(VALUE rb_mObjSpace, VALUE proc)
{
    return set_gc_hook(rb_mObjSpace, proc, RUBY_INTERNAL_EVENT_GC_END,
		       "__set_after_gc_end_tpval__", "__set_after_gc_end_proc__");
}

void
Init_gc_hook(VALUE rb_mObjSpace)
{
    rb_define_module_function(rb_mObjSpace, "after_gc_start_hook=", set_after_gc_start, 1);
    rb_define_module_function(rb_mObjSpace, "after_gc_end_hook=", set_after_gc_end, 1);
}
