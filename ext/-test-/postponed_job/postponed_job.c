#include "ruby.h"
#include "ruby/debug.h"

// We're testing deprecated things, don't print the compiler warnings
#if 0

#elif defined(_MSC_VER)
#pragma warning(disable : 4996)

#elif defined(__INTEL_COMPILER)
#pragma warning(disable : 1786)

#elif defined(__clang__)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__SUNPRO_CC)
#pragma error_messages (off,symdeprecated)

#else
// :FIXME: improve here for your compiler.

#endif

static int counter;

static void
pjob_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    rb_ary_push(ary, INT2FIX(counter));
}

static VALUE
pjob_call_direct(VALUE self, VALUE obj)
{
    counter = 0;
    pjob_callback((void *)obj);
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    return self;
}

static void pjob_noop_callback(void *data) { }

static void
pjob_preregistered_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);
    rb_ary_push(ary, INT2FIX(counter));
}

static VALUE
pjob_preregister_and_call_with_sleep(VALUE self, VALUE obj)
{
    counter = 0;
    rb_postponed_job_handle_t h = rb_postponed_job_preregister(0, pjob_preregistered_callback, (void *)obj);
    counter++;
    rb_postponed_job_trigger(h);
    rb_thread_sleep(0);
    counter++;
    rb_postponed_job_trigger(h);
    rb_thread_sleep(0);
    counter++;
    rb_postponed_job_trigger(h);
    rb_thread_sleep(0);
    return self;
}

static VALUE
pjob_preregister_and_call_without_sleep(VALUE self, VALUE obj)
{
    counter = 0;
    rb_postponed_job_handle_t h = rb_postponed_job_preregister(0, pjob_preregistered_callback, (void *)obj);
    counter = 3;
    rb_postponed_job_trigger(h);
    rb_postponed_job_trigger(h);
    rb_postponed_job_trigger(h);
    return self;
}

static VALUE
pjob_preregister_multiple_times(VALUE self)
{
    int r1 = rb_postponed_job_preregister(0, pjob_noop_callback, NULL);
    int r2 = rb_postponed_job_preregister(0, pjob_noop_callback, NULL);
    int r3 = rb_postponed_job_preregister(0, pjob_noop_callback, NULL);
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, INT2FIX(r1));
    rb_ary_push(ary, INT2FIX(r2));
    rb_ary_push(ary, INT2FIX(r3));
    return ary;

}

struct pjob_append_data_args {
    VALUE ary;
    VALUE data;
};

static void
pjob_append_data_callback(void *vctx) {
    struct pjob_append_data_args *ctx = (struct pjob_append_data_args *)vctx;
    Check_Type(ctx->ary, T_ARRAY);
    rb_ary_push(ctx->ary, ctx->data);
}

static VALUE
pjob_preregister_calls_with_last_argument(VALUE self)
{
    VALUE ary = rb_ary_new();

    struct pjob_append_data_args arg1 = { .ary = ary, .data = INT2FIX(1) };
    struct pjob_append_data_args arg2 = { .ary = ary, .data = INT2FIX(2) };
    struct pjob_append_data_args arg3 = { .ary = ary, .data = INT2FIX(3) };
    struct pjob_append_data_args arg4 = { .ary = ary, .data = INT2FIX(4) };

    rb_postponed_job_handle_t h;
    h = rb_postponed_job_preregister(0, pjob_append_data_callback, &arg1);
    rb_postponed_job_preregister(0, pjob_append_data_callback, &arg2);
    rb_postponed_job_trigger(h);
    rb_postponed_job_preregister(0, pjob_append_data_callback, &arg3);
    rb_thread_sleep(0); // should execute with arg3

    rb_postponed_job_preregister(0, pjob_append_data_callback, &arg4);
    rb_postponed_job_trigger(h);
    rb_thread_sleep(0); // should execute with arg4

    return ary;
}

/* internal (vm_trace.c); exported for this test */
void rb_postponed_job_trigger_for_ractor(unsigned int h, VALUE ractor);

static rb_postponed_job_handle_t pjob_for_ractor_handle = POSTPONED_JOB_HANDLE_INVALID;

static void
pjob_for_ractor_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    /* record which Ractor executed the job */
    rb_ary_push(ary, rb_funcall(rb_path2class("Ractor"), rb_intern("current"), 0));
}

static VALUE
pjob_preregister_for_ractor(VALUE self, VALUE ary)
{
    pjob_for_ractor_handle = rb_postponed_job_preregister(0, pjob_for_ractor_callback, (void *)ary);
    if (pjob_for_ractor_handle == POSTPONED_JOB_HANDLE_INVALID) {
        rb_raise(rb_eRuntimeError, "preregister failed");
    }
    return self;
}

static VALUE
pjob_trigger_for_ractor(VALUE self, VALUE ractor)
{
    if (pjob_for_ractor_handle == POSTPONED_JOB_HANDLE_INVALID) {
        rb_raise(rb_eRuntimeError, "not preregistered");
    }
    rb_postponed_job_trigger_for_ractor(pjob_for_ractor_handle, ractor);
    return self;
}

void
Init_postponed_job(VALUE self)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "postponed_job_call_direct", pjob_call_direct, 1);
    rb_define_module_function(mBug, "postponed_job_preregister_and_call_with_sleep", pjob_preregister_and_call_with_sleep, 1);
    rb_define_module_function(mBug, "postponed_job_preregister_and_call_without_sleep", pjob_preregister_and_call_without_sleep, 1);
    rb_define_module_function(mBug, "postponed_job_preregister_multiple_times", pjob_preregister_multiple_times, 0);
    rb_define_module_function(mBug, "postponed_job_preregister_calls_with_last_argument", pjob_preregister_calls_with_last_argument, 0);
    rb_define_module_function(mBug, "postponed_job_preregister_for_ractor", pjob_preregister_for_ractor, 1);
    rb_define_module_function(mBug, "postponed_job_trigger_for_ractor", pjob_trigger_for_ractor, 1);
}

