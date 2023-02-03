#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby/thread.h"

static rb_atomic_t started_count = 0;
static rb_atomic_t ready_count = 0;
static rb_atomic_t resumed_count = 0;
static rb_atomic_t suspended_count = 0;
static rb_atomic_t exited_count = 0;

#if __STDC_VERSION__ >= 201112
  #define RB_THREAD_LOCAL_SPECIFIER _Thread_local
#elif defined(__GNUC__) && !defined(RB_THREAD_LOCAL_SPECIFIER_IS_UNSUPPORTED)
  /* note that ICC (linux) and Clang are covered by __GNUC__ */
  #define RB_THREAD_LOCAL_SPECIFIER __thread
#else
  #define RB_THREAD_LOCAL_SPECIFIER
#endif

static RB_THREAD_LOCAL_SPECIFIER unsigned int local_ready_count = 0;
static RB_THREAD_LOCAL_SPECIFIER unsigned int local_resumed_count = 0;
static RB_THREAD_LOCAL_SPECIFIER unsigned int local_suspended_count = 0;

static void
ex_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data)
{
    switch (event) {
      case RUBY_INTERNAL_THREAD_EVENT_STARTED:
        RUBY_ATOMIC_INC(started_count);
        break;
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        RUBY_ATOMIC_INC(ready_count);
        local_ready_count++;
        break;
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        RUBY_ATOMIC_INC(resumed_count);
        local_resumed_count++;
        break;
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        RUBY_ATOMIC_INC(suspended_count);
        local_suspended_count++;
        break;
      case RUBY_INTERNAL_THREAD_EVENT_EXITED:
        RUBY_ATOMIC_INC(exited_count);
        break;
    }
}

static rb_internal_thread_event_hook_t * single_hook = NULL;

static VALUE
thread_counters(VALUE thread)
{
    VALUE array = rb_ary_new2(5);
    rb_ary_push(array, UINT2NUM(started_count));
    rb_ary_push(array, UINT2NUM(ready_count));
    rb_ary_push(array, UINT2NUM(resumed_count));
    rb_ary_push(array, UINT2NUM(suspended_count));
    rb_ary_push(array, UINT2NUM(exited_count));
    return array;
}

static VALUE
thread_local_counters(VALUE thread)
{
    VALUE array = rb_ary_new2(3);
    rb_ary_push(array, UINT2NUM(local_ready_count));
    rb_ary_push(array, UINT2NUM(local_resumed_count));
    rb_ary_push(array, UINT2NUM(local_suspended_count));
    return array;
}

static VALUE
thread_reset_counters(VALUE thread)
{
    RUBY_ATOMIC_SET(started_count, 0);
    RUBY_ATOMIC_SET(ready_count, 0);
    RUBY_ATOMIC_SET(resumed_count, 0);
    RUBY_ATOMIC_SET(suspended_count, 0);
    RUBY_ATOMIC_SET(exited_count, 0);
    local_ready_count = 0;
    local_resumed_count = 0;
    local_suspended_count = 0;
    return Qtrue;
}

static VALUE
thread_register_callback(VALUE thread)
{
    single_hook = rb_internal_thread_add_event_hook(
        ex_callback,
        RUBY_INTERNAL_THREAD_EVENT_STARTED |
        RUBY_INTERNAL_THREAD_EVENT_READY |
        RUBY_INTERNAL_THREAD_EVENT_RESUMED |
        RUBY_INTERNAL_THREAD_EVENT_SUSPENDED |
        RUBY_INTERNAL_THREAD_EVENT_EXITED,
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
        hooks[i] = rb_internal_thread_add_event_hook(ex_callback, RUBY_INTERNAL_THREAD_EVENT_READY, NULL);
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
    rb_define_singleton_method(klass, "local_counters", thread_local_counters, 0);
    rb_define_singleton_method(klass, "reset_counters", thread_reset_counters, 0);
    rb_define_singleton_method(klass, "register_callback", thread_register_callback, 0);
    rb_define_singleton_method(klass, "unregister_callback", thread_unregister_callback, 0);
    rb_define_singleton_method(klass, "register_and_unregister_callbacks", thread_register_and_unregister_callback, 0);
}
