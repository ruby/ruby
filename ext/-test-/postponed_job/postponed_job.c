#include "ruby.h"
#include "ruby/debug.h"

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

void
Init_postponed_job(VALUE self)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "postponed_job_register", pjob_register, 1);
    rb_define_module_function(mBug, "postponed_job_register_one", pjob_register_one, 1);
    rb_define_module_function(mBug, "postponed_job_call_direct", pjob_call_direct, 1);
#ifdef HAVE_PTHREAD_H
    rb_define_module_function(mBug, "postponed_job_register_in_c_thread", pjob_register_in_c_thread, 1);
#endif
}

