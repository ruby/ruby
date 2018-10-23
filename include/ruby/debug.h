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

RUBY_SYMBOL_EXPORT_BEGIN

/* Note: This file contains experimental APIs. */
/* APIs can be replaced at Ruby 2.0.1 or later */


/* profile frames APIs */
int rb_profile_frames(int start, int limit, VALUE *buff, int *lines);
VALUE rb_profile_frame_path(VALUE frame);
VALUE rb_profile_frame_absolute_path(VALUE frame);
VALUE rb_profile_frame_label(VALUE frame);
VALUE rb_profile_frame_base_label(VALUE frame);
VALUE rb_profile_frame_full_label(VALUE frame);
VALUE rb_profile_frame_first_lineno(VALUE frame);
VALUE rb_profile_frame_classpath(VALUE frame);
VALUE rb_profile_frame_singleton_method_p(VALUE frame);
VALUE rb_profile_frame_method_name(VALUE frame);
VALUE rb_profile_frame_qualified_method_name(VALUE frame);

/* debug inspector APIs */
typedef struct rb_debug_inspector_struct rb_debug_inspector_t;
typedef VALUE (*rb_debug_inspector_func_t)(const rb_debug_inspector_t *, void *);

VALUE rb_debug_inspector_open(rb_debug_inspector_func_t func, void *data);
VALUE rb_debug_inspector_frame_self_get(const rb_debug_inspector_t *dc, long index);
VALUE rb_debug_inspector_frame_class_get(const rb_debug_inspector_t *dc, long index);
VALUE rb_debug_inspector_frame_binding_get(const rb_debug_inspector_t *dc, long index);
VALUE rb_debug_inspector_frame_iseq_get(const rb_debug_inspector_t *dc, long index);
VALUE rb_debug_inspector_backtrace_locations(const rb_debug_inspector_t *dc);

/* Old style set_trace_func APIs */

/* duplicated def of include/ruby/ruby.h */
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);

int rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data);
void rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func);
int rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data);

/* TracePoint APIs */

VALUE rb_tracepoint_new(VALUE target_thread_not_supported_yet, rb_event_flag_t events, void (*func)(VALUE, void *), void *data);
VALUE rb_tracepoint_enable(VALUE tpval);
VALUE rb_tracepoint_disable(VALUE tpval);
VALUE rb_tracepoint_enabled_p(VALUE tpval);

typedef struct rb_trace_arg_struct rb_trace_arg_t;
rb_trace_arg_t *rb_tracearg_from_tracepoint(VALUE tpval);

rb_event_flag_t rb_tracearg_event_flag(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_event(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_lineno(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_path(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_method_id(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_callee_id(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_defined_class(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_binding(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_self(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_return_value(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_raised_exception(rb_trace_arg_t *trace_arg);
VALUE rb_tracearg_object(rb_trace_arg_t *trace_arg);

/*
 * Postponed Job API
 * rb_postponed_job_register and rb_postponed_job_register_one are
 * async-signal-safe and used via SIGPROF by the "stackprof" RubyGem
 */
typedef void (*rb_postponed_job_func_t)(void *arg);
int rb_postponed_job_register(unsigned int flags, rb_postponed_job_func_t func, void *data);
int rb_postponed_job_register_one(unsigned int flags, rb_postponed_job_func_t func, void *data);

/* undocumented advanced tracing APIs */

typedef enum {
    RUBY_EVENT_HOOK_FLAG_SAFE    = 0x01,
    RUBY_EVENT_HOOK_FLAG_DELETED = 0x02,
    RUBY_EVENT_HOOK_FLAG_RAW_ARG = 0x04
} rb_event_hook_flag_t;

void rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);
void rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_DEBUG_H */
