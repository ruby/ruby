#include <ruby.h>
#include <node.h>

/* copied from eval.c */
static const char *
get_event_name(rb_event_t event)
{
    switch (event) {
      case RUBY_EVENT_LINE:
	return "line";
      case RUBY_EVENT_CLASS:
	return "class";
      case RUBY_EVENT_END:
	return "end";
      case RUBY_EVENT_CALL:
	return "call";
      case RUBY_EVENT_RETURN:
	return "return";
      case RUBY_EVENT_C_CALL:
	return "c-call";
      case RUBY_EVENT_C_RETURN:
	return "c-return";
      case RUBY_EVENT_RAISE:
	return "raise";
      case RUBY_EVENT_THREAD_INIT:
	return "thread-init";
      case RUBY_EVENT_THREAD_FREE:
	return "thread-free";
      case RUBY_EVENT_THREAD_SAVE:
	return "thread-save";
      case RUBY_EVENT_THREAD_RESTORE:
	return "thread-restore";
      default:
	return "unknown";
    }
}

static VALUE event_callback;

static void
event_hook(event, node, obj, mid, klass)
    rb_event_t event;
    NODE *node;
    VALUE obj;
    ID mid;
    VALUE klass;
{
    VALUE block = rb_thread_local_aref(rb_thread_current(), event_callback);
    if (!NIL_P(block)) {
	VALUE args = rb_ary_new();
	rb_ary_push(args, rb_str_new2(get_event_name(event)));
	rb_ary_push(args, obj);
	rb_ary_push(args, ID2SYM(mid));
	rb_ary_push(args, klass);
	rb_proc_call(block, args);
    }
}

static VALUE
add_event_hook(obj)
    VALUE obj;
{
    rb_add_event_hook(event_hook, RUBY_EVENT_ALL);
    return obj;
}

#ifdef RUBY_ENABLE_MACOSX_UNOFFICIAL_THREADSWITCH
#define get_threadswitch_event_name(thevent) get_event_name((thevent) << RUBY_THREADSWITCH_SHIFT)

static void
threadswitch_event_hook(event, thread)
    rb_threadswitch_event_t event;
    VALUE thread;
{
    VALUE block = rb_thread_local_aref(rb_thread_current(), event_callback);
    if (!NIL_P(block)) {
	VALUE args = rb_ary_new();
	rb_ary_push(args, rb_str_new2(get_threadswitch_event_name(event)));
	rb_ary_push(args, thread);
	rb_proc_call(block, args);
    }
}

static VALUE rb_cThreadSwitchHook;

static VALUE
threadswitch_add_event_hook(klass)
    VALUE klass;
{
    void *handle = rb_add_threadswitch_hook(threadswitch_event_hook);
    return Data_Wrap_Struct(klass, 0, rb_remove_threadswitch_hook, handle);
}

static VALUE
threadswitch_remove_event_hook(obj)
    VALUE obj;
{
    void *handle = DATA_PTR(obj);
    DATA_PTR(obj) = 0;
    if (handle) {
	rb_remove_threadswitch_hook(handle);
    }
    return obj;
}

static VALUE
restore_hook(arg)
    VALUE arg;
{
    VALUE *save = (VALUE *)arg;
    threadswitch_remove_event_hook(save[0]);
    rb_thread_local_aset(rb_thread_current(), event_callback, save[1]);
    return Qnil;
}

static VALUE
threadswitch_hook(klass)
    VALUE klass;
{
    VALUE save[2];
    save[1] = rb_thread_local_aref(rb_thread_current(), event_callback);
    rb_thread_local_aset(rb_thread_current(), event_callback, rb_block_proc());
    save[0] = threadswitch_add_event_hook(klass);
    return rb_ensure(rb_yield, save[0], restore_hook, (VALUE)save);
}

static void
Init_threadswitch_hook(mEventHook)
    VALUE mEventHook;
{
    rb_cThreadSwitchHook = rb_define_class_under(mEventHook, "ThreadSwitch", rb_cObject);
    rb_define_singleton_method(rb_cThreadSwitchHook, "add", threadswitch_add_event_hook, 0);
    rb_define_singleton_method(rb_cThreadSwitchHook, "hook", threadswitch_hook, 0);
    rb_define_method(rb_cThreadSwitchHook, "remove", threadswitch_remove_event_hook, 0);
}
#else
#define Init_threadswitch_hook(mEventHook) (void)(mEventHook)
#endif

void
Init_event_hook()
{
    VALUE mEventHook = rb_define_module("EventHook");

    event_callback = rb_intern("rb_event_callback");
    rb_define_module_function(mEventHook, "hook", add_event_hook, 0);
    Init_threadswitch_hook(mEventHook);
}
