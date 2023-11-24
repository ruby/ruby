#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby/thread.h"

#ifndef RB_THREAD_LOCAL_SPECIFIER
#  define RB_THREAD_LOCAL_SPECIFIER
#endif

static VALUE last_thread = Qnil;
static VALUE timeline_value = Qnil;

struct thread_event {
    VALUE thread;
    rb_event_flag_t event;
};

#define MAX_EVENTS 1024
static struct thread_event event_timeline[MAX_EVENTS];
static rb_atomic_t timeline_cursor;

static void
event_timeline_gc_mark(void *ptr) {
    rb_atomic_t cursor;
    for (cursor = 0; cursor < timeline_cursor; cursor++) {
        rb_gc_mark(event_timeline[cursor].thread);
    }
}

static const rb_data_type_t event_timeline_type = {
    "TestThreadInstrumentation/event_timeline",
    {event_timeline_gc_mark, NULL, NULL,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static void
reset_timeline(void)
{
    timeline_cursor = 0;
    memset(event_timeline, 0, sizeof(struct thread_event) * MAX_EVENTS);
}

static rb_event_flag_t
find_last_event(VALUE thread)
{
    rb_atomic_t cursor = timeline_cursor;
    if (cursor) {
        do {
            if (event_timeline[cursor].thread == thread){
                return event_timeline[cursor].event;
            }
            cursor--;
        } while (cursor > 0);
    }
    return 0;
}

static const char *
event_name(rb_event_flag_t event)
{
    switch (event) {
      case RUBY_INTERNAL_THREAD_EVENT_STARTED:
        return "started";
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        return "ready";
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        return "resumed";
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        return "suspended";
      case RUBY_INTERNAL_THREAD_EVENT_EXITED:
        return "exited";
    }
    return "no-event";
}

NORETURN(static void unexpected(const char *format, const char *event_name, VALUE thread));

static void
unexpected(const char *format, const char *event_name, VALUE thread)
{
#if 0
    fprintf(stderr, "----------------\n");
    fprintf(stderr, format, event_name, thread);
    fprintf(stderr, "\n");
    rb_backtrace();
    fprintf(stderr, "----------------\n");
#else
    rb_bug(format, event_name, thread);
#endif
}

static void
ex_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data)
{
    rb_event_flag_t last_event = find_last_event(event_data->thread);

    switch (event) {
      case RUBY_INTERNAL_THREAD_EVENT_STARTED:
        if (last_event != 0) {
            unexpected("TestThreadInstrumentation: `started` event can't be preceded by `%s` (thread=%"PRIxVALUE")", event_name(last_event), event_data->thread);
        }
        break;
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        if (last_event != 0 && last_event != RUBY_INTERNAL_THREAD_EVENT_STARTED && last_event != RUBY_INTERNAL_THREAD_EVENT_SUSPENDED) {
            unexpected("TestThreadInstrumentation: `ready` must be preceded by `started` or `suspended`, got: `%s` (thread=%"PRIxVALUE")", event_name(last_event), event_data->thread);
        }
        break;
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        if (last_event != 0 && last_event != RUBY_INTERNAL_THREAD_EVENT_READY) {
            unexpected("TestThreadInstrumentation: `resumed` must be preceded by `ready`, got: `%s` (thread=%"PRIxVALUE")", event_name(last_event), event_data->thread);
        }
        break;
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        if (last_event != 0 && last_event != RUBY_INTERNAL_THREAD_EVENT_RESUMED) {
            unexpected("TestThreadInstrumentation: `suspended` must be preceded by `resumed`, got: `%s` (thread=%"PRIxVALUE")", event_name(last_event), event_data->thread);
        }
        break;
      case RUBY_INTERNAL_THREAD_EVENT_EXITED:
        if (last_event != 0 && last_event != RUBY_INTERNAL_THREAD_EVENT_RESUMED && last_event != RUBY_INTERNAL_THREAD_EVENT_SUSPENDED) {
            unexpected("TestThreadInstrumentation: `exited` must be preceded by `resumed` or `suspended`, got: `%s` (thread=%"PRIxVALUE")", event_name(last_event), event_data->thread);
        }
        break;
    }

    rb_atomic_t cursor = RUBY_ATOMIC_FETCH_ADD(timeline_cursor, 1);
    if (cursor >= MAX_EVENTS) {
        rb_bug("TestThreadInstrumentation: ran out of event_timeline space");
    }

    event_timeline[cursor].thread = event_data->thread;
    event_timeline[cursor].event = event;
}

static rb_internal_thread_event_hook_t * single_hook = NULL;

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
event_symbol(rb_event_flag_t event)
{
    switch (event) {
      case RUBY_INTERNAL_THREAD_EVENT_STARTED:
        return rb_id2sym(rb_intern("started"));
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        return rb_id2sym(rb_intern("ready"));
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        return rb_id2sym(rb_intern("resumed"));
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        return rb_id2sym(rb_intern("suspended"));
      case RUBY_INTERNAL_THREAD_EVENT_EXITED:
        return rb_id2sym(rb_intern("exited"));
      default:
        rb_bug("TestThreadInstrumentation: Unexpected event");
        break;
    }
}

static VALUE
thread_unregister_callback(VALUE thread)
{
    if (single_hook) {
        rb_internal_thread_remove_event_hook(single_hook);
        single_hook = NULL;
    }

    VALUE events = rb_ary_new_capa(timeline_cursor);
    rb_atomic_t cursor;
    for (cursor = 0; cursor < timeline_cursor; cursor++) {
        VALUE pair = rb_ary_new_capa(2);
        rb_ary_push(pair, event_timeline[cursor].thread);
        rb_ary_push(pair, event_symbol(event_timeline[cursor].event));
        rb_ary_push(events, pair);
    }

    reset_timeline();

    return events;
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
    rb_global_variable(&timeline_value);
    timeline_value = TypedData_Wrap_Struct(0, &event_timeline_type, 0);

    rb_global_variable(&last_thread);
    rb_define_singleton_method(klass, "register_callback", thread_register_callback, 0);
    rb_define_singleton_method(klass, "unregister_callback", thread_unregister_callback, 0);
    rb_define_singleton_method(klass, "register_and_unregister_callbacks", thread_register_and_unregister_callback, 0);
}
