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
pjob_register(VALUE self, VALUE obj)
{
    counter = 0;
    rb_postponed_job_register(0, pjob_callback, (void *)obj);
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    return self;
}

static void
pjob_one_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    rb_ary_push(ary, INT2FIX(1));
}

static VALUE
pjob_register_one(VALUE self, VALUE obj)
{
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    return self;
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

static VALUE
pjob_register_one_same(VALUE self)
{
    rb_gc_start();
    int r1 = rb_postponed_job_register_one(0, pjob_noop_callback, NULL);
    int r2 = rb_postponed_job_register_one(0, pjob_noop_callback, NULL);
    int r3 = rb_postponed_job_register_one(0, pjob_noop_callback, NULL);
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, INT2FIX(r1));
    rb_ary_push(ary, INT2FIX(r2));
    rb_ary_push(ary, INT2FIX(r3));
    return ary;
}

#ifdef HAVE_PTHREAD_H
#include <pthread.h>

static void *
pjob_register_in_c_thread_i(void *obj)
{
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    return NULL;
}

static VALUE
pjob_register_in_c_thread(VALUE self, VALUE obj)
{
    pthread_t thread;
    if (pthread_create(&thread, NULL, pjob_register_in_c_thread_i, (void *)obj)) {
        return Qfalse;
    }

    if (pthread_join(thread, NULL)) {
        return Qfalse;
    }

    return Qtrue;
}
#endif

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

void
Init_postponed_job(VALUE self)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "postponed_job_register", pjob_register, 1);
    rb_define_module_function(mBug, "postponed_job_register_one", pjob_register_one, 1);
    rb_define_module_function(mBug, "postponed_job_call_direct", pjob_call_direct, 1);
    rb_define_module_function(mBug, "postponed_job_register_one_same", pjob_register_one_same, 0);
#ifdef HAVE_PTHREAD_H
    rb_define_module_function(mBug, "postponed_job_register_in_c_thread", pjob_register_in_c_thread, 1);
#endif
    rb_define_module_function(mBug, "postponed_job_preregister_and_call_with_sleep", pjob_preregister_and_call_with_sleep, 1);
    rb_define_module_function(mBug, "postponed_job_preregister_and_call_without_sleep", pjob_preregister_and_call_without_sleep, 1);
    rb_define_module_function(mBug, "postponed_job_preregister_multiple_times", pjob_preregister_multiple_times, 0);
}

