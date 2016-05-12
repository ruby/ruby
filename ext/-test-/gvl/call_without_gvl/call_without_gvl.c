#include "ruby/ruby.h"
#include "ruby/thread.h"

static void*
native_sleep_callback(void *data)
{
    struct timeval *timeval = data;
    select(0, NULL, NULL, NULL, timeval);

    return NULL;
}


static VALUE
thread_runnable_sleep(VALUE thread, VALUE timeout)
{
    struct timeval timeval;

    if (NIL_P(timeout)) {
	rb_raise(rb_eArgError, "timeout must be non nil");
    }

    timeval = rb_time_interval(timeout);

    rb_thread_call_without_gvl(native_sleep_callback, &timeval, RUBY_UBF_IO, NULL);

    return thread;
}

void
Init_call_without_gvl(void)
{
    rb_define_method(rb_cThread, "__runnable_sleep__", thread_runnable_sleep, 1);
}
