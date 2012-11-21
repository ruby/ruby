/**********************************************************************

  ruby/debug.h -

  $Author: ko1 $
  created at: Tue Nov 20 20:35:08 2012

  Copyright (C) 2012 Yukihiro Matsumoto

**********************************************************************/

#ifndef RB_DEBUG_H
#define RB_DEBUG_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility push(default)
#endif

/* Note: This file contains experimental APIs. */
/* APIs can be replaced at Ruby 2.0.1 or later */

typedef enum {
    RUBY_EVENT_HOOK_FLAG_SAFE    = 0x01,
    RUBY_EVENT_HOOK_FLAG_DELETED = 0x02,
    RUBY_EVENT_HOOK_FLAG_RAW_ARG = 0x04
} rb_event_hook_flag_t;

/* Safe API.  Callback will be called under PUSH_TAG() */
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);
int rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data);
void rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func);
int rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data);

/* advanced version */
void rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);
void rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);

/* TracePoint APIs */

VALUE rb_tracepoint_new(VALUE target_thread_not_supported_yet, rb_event_flag_t events, void (*func)(VALUE, void *), void *data);
VALUE rb_tracepoint_enable(VALUE tpval);
VALUE rb_tracepoint_disable(VALUE tpval);
VALUE rb_tracepoint_enabled_p(VALUE tpval);

VALUE rb_tracepoint_attr_event(VALUE tpval);
VALUE rb_tracepoint_attr_line(VALUE tpval);
VALUE rb_tracepoint_attr_file(VALUE tpval);
VALUE rb_tracepoint_attr_id(VALUE tpval);
VALUE rb_tracepoint_attr_klass(VALUE tpval);
VALUE rb_tracepoint_attr_binding(VALUE tpval);
VALUE rb_tracepoint_attr_self(VALUE tpval);
VALUE rb_tracepoint_attr_return_value(VALUE tpval);
VALUE rb_tracepoint_attr_raised_exception(VALUE tpval);

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility pop
#endif

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_DEBUG_H */
