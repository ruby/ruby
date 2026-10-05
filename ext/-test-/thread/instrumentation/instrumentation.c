#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby/thread.h"
#include "ruby/thread_native.h"
#include "internal/gc.h"

#ifndef RB_THREAD_LOCAL_SPECIFIER
#  define RB_THREAD_LOCAL_SPECIFIER
#endif

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
    /* Hook sees every Ractor's threads; validate membership before marking. */
    rb_atomic_t n = RUBY_ATOMIC_LOAD(timeline_cursor);
    rb_atomic_t cursor;
    for (cursor = 0; cursor < n; cursor++) {
        rb_gc_mark_maybe(event_timeline[cursor].thread);
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
    rb_atomic_t cursor = RUBY_ATOMIC_LOAD(timeline_cursor);
    while (cursor > 0) {
        cursor--;
        if (event_timeline[cursor].thread == thread) {
            return event_timeline[cursor].event;
        }
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

static void
unexpected(bool strict, const char *format, VALUE thread, rb_event_flag_t last_event)
{
     const char *last_event_name = event_name(last_event);
    if (strict) {
        rb_bug(format, thread, last_event_name);
    }
    else {
        fprintf(stderr, format, thread, last_event_name);
        fprintf(stderr, "\n");
    }
}

static void
ex_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data)
{
    rb_event_flag_t last_event = find_last_event(event_data->thread);
    bool strict = (bool)user_data;

    if (last_event != 0) {
        switch (event) {
          case RUBY_INTERNAL_THREAD_EVENT_STARTED:
            unexpected(strict, "[thread=%"PRIxVALUE"] `started` event can't be preceded by `%s`", event_data->thread, last_event);
            break;
          case RUBY_INTERNAL_THREAD_EVENT_READY:
            if (last_event != RUBY_INTERNAL_THREAD_EVENT_STARTED && last_event != RUBY_INTERNAL_THREAD_EVENT_SUSPENDED) {
                unexpected(strict, "[thread=%"PRIxVALUE"] `ready` must be preceded by `started` or `suspended`, got: `%s`", event_data->thread, last_event);
            }
            break;
          case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
            if (last_event != RUBY_INTERNAL_THREAD_EVENT_READY) {
                unexpected(strict, "[thread=%"PRIxVALUE"] `resumed` must be preceded by `ready`, got: `%s`", event_data->thread, last_event);
            }
            break;
          case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
            if (last_event != RUBY_INTERNAL_THREAD_EVENT_RESUMED) {
                unexpected(strict, "[thread=%"PRIxVALUE"] `suspended` must be preceded by `resumed`, got: `%s`", event_data->thread, last_event);
            }
            break;
          case RUBY_INTERNAL_THREAD_EVENT_EXITED:
            if (last_event != RUBY_INTERNAL_THREAD_EVENT_RESUMED && last_event != RUBY_INTERNAL_THREAD_EVENT_SUSPENDED) {
                unexpected(strict, "[thread=%"PRIxVALUE"] `exited` must be preceded by `resumed` or `suspended`, got: `%s`", event_data->thread, last_event);
            }
            break;
        }
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
thread_register_callback(VALUE thread, VALUE strict)
{
    single_hook = rb_internal_thread_add_event_hook(
        ex_callback,
        RUBY_INTERNAL_THREAD_EVENT_STARTED |
        RUBY_INTERNAL_THREAD_EVENT_READY |
        RUBY_INTERNAL_THREAD_EVENT_RESUMED |
        RUBY_INTERNAL_THREAD_EVENT_SUSPENDED |
        RUBY_INTERNAL_THREAD_EVENT_EXITED,
        (void *)RTEST(strict)
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

// NOTE: only safe when there's a single active Ractor
static VALUE
thread_unregister_callback(VALUE thread)
{
    if (single_hook) {
        rb_internal_thread_remove_event_hook(single_hook);
        single_hook = NULL;
    }

    rb_atomic_t n = RUBY_ATOMIC_LOAD(timeline_cursor);
    VALUE events = rb_ary_new_capa(n);
    rb_atomic_t cursor;
    for (cursor = 0; cursor < n; cursor++) {
        VALUE th = event_timeline[cursor].thread;
        /* Skip foreign-objspace threads: pushing them into this Array would violate containment. */
        if (rb_objspace_foreign_object_p(th)) continue;
        VALUE pair = rb_ary_new_capa(2);
        rb_ary_push(pair, th);
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

struct gvl_state {
    VALUE thread;
    rb_nativethread_id_t native_thread;
    rb_internal_thread_event_hook_t *hook;
    unsigned int ready_count, ready_with_gvl;
    unsigned int resumed_count, resumed_with_gvl;
};

static void
gvl_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data)
{
    struct gvl_state *state = user_data;
    if (event_data->thread != state->thread) return;
#ifdef HAVE_PTHREAD_H
    if (!pthread_equal(rb_nativethread_self(), state->native_thread)) return;
#else
    if (rb_nativethread_self() != state->native_thread) return;
#endif

    if (event == RUBY_INTERNAL_THREAD_EVENT_READY) {
        state->ready_count++;
        state->ready_with_gvl += ruby_thread_has_gvl_p() != 0;
    }
    else if (event == RUBY_INTERNAL_THREAD_EVENT_RESUMED) {
        state->resumed_count++;
        state->resumed_with_gvl += ruby_thread_has_gvl_p() != 0;
    }
}

static VALUE
gvl_yield(VALUE unused)
{
    return rb_yield(Qnil);
}

static VALUE
gvl_unregister(VALUE arg)
{
    struct gvl_state *state = (struct gvl_state *)arg;
    rb_internal_thread_remove_event_hook(state->hook);
    return Qnil;
}

static VALUE
thread_gvl_state(VALUE self)
{
    /* Keep callbacks for this thread on the native thread being observed. */
    rb_thread_lock_native_thread();
    struct gvl_state state = {0};
    state.thread = rb_thread_current();
    state.native_thread = rb_nativethread_self();
    state.hook = rb_internal_thread_add_event_hook(gvl_callback,
        RUBY_INTERNAL_THREAD_EVENT_READY | RUBY_INTERNAL_THREAD_EVENT_RESUMED, &state);

    rb_ensure(gvl_yield, Qnil, gvl_unregister, (VALUE)&state);
    return rb_ary_new_from_args(4,
        UINT2NUM(state.ready_count), UINT2NUM(state.ready_with_gvl),
        UINT2NUM(state.resumed_count), UINT2NUM(state.resumed_with_gvl));
}

void
Init_instrumentation(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "ThreadInstrumentation");
    rb_global_variable(&timeline_value);
    timeline_value = TypedData_Wrap_Struct(0, &event_timeline_type, (void *)1);

    rb_define_singleton_method(klass, "register_callback", thread_register_callback, 1);
    rb_define_singleton_method(klass, "unregister_callback", thread_unregister_callback, 0);
    rb_define_singleton_method(klass, "register_and_unregister_callbacks", thread_register_and_unregister_callback, 0);
    rb_define_singleton_method(klass, "gvl_state", thread_gvl_state, 0);
}
