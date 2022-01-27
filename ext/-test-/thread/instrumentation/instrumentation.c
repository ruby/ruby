#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby/thread.h"

static rb_atomic_t acquire_enter_count = 0;
static rb_atomic_t acquire_exit_count = 0;
static rb_atomic_t release_count = 0;

void
ex_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data)
{
    switch(event) {
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        RUBY_ATOMIC_INC(acquire_enter_count);
        break;
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        RUBY_ATOMIC_INC(acquire_exit_count);
        break;
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        RUBY_ATOMIC_INC(release_count);
        break;
    }
}

static rb_internal_thread_event_hook_t * single_hook = NULL;

static VALUE
thread_counters(VALUE thread)
{
    VALUE array = rb_ary_new2(3);
    rb_ary_push(array, UINT2NUM(acquire_enter_count));
    rb_ary_push(array, UINT2NUM(acquire_exit_count));
    rb_ary_push(array, UINT2NUM(release_count));
    return array;
}

static VALUE
thread_reset_counters(VALUE thread)
{
    RUBY_ATOMIC_SET(acquire_enter_count, 0);
    RUBY_ATOMIC_SET(acquire_exit_count, 0);
    RUBY_ATOMIC_SET(release_count, 0);
    return Qtrue;
}

static VALUE
thread_register_callback(VALUE thread)
{
    single_hook = rb_internal_thread_add_event_hook(
        *ex_callback,
        RUBY_INTERNAL_THREAD_EVENT_READY | RUBY_INTERNAL_THREAD_EVENT_RESUMED | RUBY_INTERNAL_THREAD_EVENT_SUSPENDED,
        NULL
    );

    return Qnil;
}

static VALUE
thread_unregister_callback(VALUE thread)
{
    if (single_hook) {
        rb_internal_thread_remove_event_hook(single_hook);
        single_hook = NULL;
    }

    return Qnil;
}

static VALUE
thread_register_and_unregister_callback(VALUE thread)
{
    rb_internal_thread_event_hook_t * hooks[5];
    for (int i = 0; i < 5; i++) {
        hooks[i] = rb_internal_thread_add_event_hook(*ex_callback, RUBY_INTERNAL_THREAD_EVENT_READY, NULL);
    }

    if (!rb_internal_thread_remove_event_hook(hooks[4])) return Qfalse;
    if (!rb_internal_thread_remove_event_hook(hooks[0])) return Qfalse;
    if (!rb_internal_thread_remove_event_hook(hooks[3])) return Qfalse;
    if (!rb_internal_thread_remove_event_hook(hooks[2])) return Qfalse;
    if (!rb_internal_thread_remove_event_hook(hooks[1])) return Qfalse;
    return Qtrue;
}

void
Init_instrumentation(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "ThreadInstrumentation");
    rb_define_singleton_method(klass, "counters", thread_counters, 0);
    rb_define_singleton_method(klass, "reset_counters", thread_reset_counters, 0);
    rb_define_singleton_method(klass, "register_callback", thread_register_callback, 0);
    rb_define_singleton_method(klass, "unregister_callback", thread_unregister_callback, 0);
    rb_define_singleton_method(klass, "register_and_unregister_callbacks", thread_register_and_unregister_callback, 0);
}
