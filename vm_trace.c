/**********************************************************************

  vm_trace.c -

  $Author: ko1 $
  created at: Tue Aug 14 19:37:09 2012

  Copyright (C) 1993-2012 Yukihiro Matsumoto

**********************************************************************/

/*
 * This file include two parts:
 *
 * (1) set_trace_func internal mechanisms
 *     and C level API
 *
 * (2) Ruby level API
 *  (2-1) set_trace_func API
 *  (2-2) TracePoint API (not yet)
 *
 */

#include "eval_intern.h"
#include "internal.h"
#include "internal/hash.h"
#include "internal/symbol.h"
#include "iseq.h"
#include "mjit.h"
#include "ruby/debug.h"
#include "vm_core.h"
#include "ruby/ractor.h"

#include "builtin.h"

/* (1) trace mechanisms */

typedef struct rb_event_hook_struct {
    rb_event_hook_flag_t hook_flags;
    rb_event_flag_t events;
    rb_event_hook_func_t func;
    VALUE data;
    struct rb_event_hook_struct *next;

    struct {
	rb_thread_t *th;
        unsigned int target_line;
    } filter;
} rb_event_hook_t;

typedef void (*rb_event_hook_raw_arg_func_t)(VALUE data, const rb_trace_arg_t *arg);

#define MAX_EVENT_NUM 32

void
rb_hook_list_mark(rb_hook_list_t *hooks)
{
    rb_event_hook_t *hook = hooks->hooks;

    while (hook) {
	rb_gc_mark(hook->data);
	hook = hook->next;
    }
}

static void clean_hooks(const rb_execution_context_t *ec, rb_hook_list_t *list);

void
rb_hook_list_free(rb_hook_list_t *hooks)
{
    hooks->need_clean = TRUE;
    clean_hooks(GET_EC(), hooks);
}

/* ruby_vm_event_flags management */

static void
update_global_event_hook(rb_event_flag_t vm_events)
{
    rb_event_flag_t new_iseq_events = vm_events & ISEQ_TRACE_EVENTS;
    rb_event_flag_t enabled_iseq_events = ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS;

    if (new_iseq_events & ~enabled_iseq_events) {
        /* Stop calling all JIT-ed code. Compiling trace insns is not supported for now. */
#if USE_MJIT
        mjit_call_p = FALSE;
#endif

	/* write all ISeqs iff new events are added */
	rb_iseq_trace_set_all(new_iseq_events | enabled_iseq_events);
    }

    ruby_vm_event_flags = vm_events;
    ruby_vm_event_enabled_global_flags |= vm_events;
    rb_objspace_set_event_hook(vm_events);
}

/* add/remove hooks */

static rb_event_hook_t *
alloc_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook;

    if ((events & RUBY_INTERNAL_EVENT_MASK) && (events & ~RUBY_INTERNAL_EVENT_MASK)) {
	rb_raise(rb_eTypeError, "Can not specify normal event and internal event simultaneously.");
    }

    hook = ALLOC(rb_event_hook_t);
    hook->hook_flags = hook_flags;
    hook->events = events;
    hook->func = func;
    hook->data = data;

    /* no filters */
    hook->filter.th = NULL;
    hook->filter.target_line = 0;

    return hook;
}

static void
hook_list_connect(VALUE list_owner, rb_hook_list_t *list, rb_event_hook_t *hook, int global_p)
{
    hook->next = list->hooks;
    list->hooks = hook;
    list->events |= hook->events;

    if (global_p) {
        /* global hooks are root objects at GC mark. */
        update_global_event_hook(list->events);
    }
    else {
        RB_OBJ_WRITTEN(list_owner, Qundef, hook->data);
    }
}

static void
connect_event_hook(const rb_execution_context_t *ec, rb_event_hook_t *hook)
{
    rb_hook_list_t *list = rb_ec_ractor_hooks(ec);
    hook_list_connect(Qundef, list, hook, TRUE);
}

static void
rb_threadptr_add_event_hook(const rb_execution_context_t *ec, rb_thread_t *th,
			    rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, hook_flags);
    hook->filter.th = th;
    connect_event_hook(ec, hook);
}

void
rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_threadptr_add_event_hook(GET_EC(), rb_thread_ptr(thval), func, events, data, RUBY_EVENT_HOOK_FLAG_SAFE);
}

void
rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, RUBY_EVENT_HOOK_FLAG_SAFE);
    connect_event_hook(GET_EC(), hook);
}

void
rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_threadptr_add_event_hook(GET_EC(), rb_thread_ptr(thval), func, events, data, hook_flags);
}

void
rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, hook_flags);
    connect_event_hook(GET_EC(), hook);
}

static void
clean_hooks(const rb_execution_context_t *ec, rb_hook_list_t *list)
{
    rb_event_hook_t *hook, **nextp = &list->hooks;
    VM_ASSERT(list->need_clean == TRUE);

    list->events = 0;
    list->need_clean = FALSE;

    while ((hook = *nextp) != 0) {
	if (hook->hook_flags & RUBY_EVENT_HOOK_FLAG_DELETED) {
	    *nextp = hook->next;
	    xfree(hook);
	}
	else {
	    list->events |= hook->events; /* update active events */
	    nextp = &hook->next;
	}
    }

    if (list == rb_ec_ractor_hooks(ec)) {
        /* global events */
        update_global_event_hook(list->events);
    }
    else {
        /* local events */
    }
}

static void
clean_hooks_check(const rb_execution_context_t *ec, rb_hook_list_t *list)
{
    if (UNLIKELY(list->need_clean != FALSE)) {
        if (list->running == 0) {
            clean_hooks(ec, list);
        }
    }
}

#define MATCH_ANY_FILTER_TH ((rb_thread_t *)1)

/* if func is 0, then clear all funcs */
static int
remove_event_hook(const rb_execution_context_t *ec, const rb_thread_t *filter_th, rb_event_hook_func_t func, VALUE data)
{
    rb_hook_list_t *list = rb_ec_ractor_hooks(ec);
    int ret = 0;
    rb_event_hook_t *hook = list->hooks;

    while (hook) {
	if (func == 0 || hook->func == func) {
	    if (hook->filter.th == filter_th || filter_th == MATCH_ANY_FILTER_TH) {
		if (data == Qundef || hook->data == data) {
		    hook->hook_flags |= RUBY_EVENT_HOOK_FLAG_DELETED;
		    ret+=1;
		    list->need_clean = TRUE;
		}
	    }
	}
	hook = hook->next;
    }

    clean_hooks_check(ec, list);
    return ret;
}

static int
rb_threadptr_remove_event_hook(const rb_execution_context_t *ec, const rb_thread_t *filter_th, rb_event_hook_func_t func, VALUE data)
{
    return remove_event_hook(ec, filter_th, func, data);
}

int
rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func)
{
    return rb_threadptr_remove_event_hook(GET_EC(), rb_thread_ptr(thval), func, Qundef);
}

int
rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data)
{
    return rb_threadptr_remove_event_hook(GET_EC(), rb_thread_ptr(thval), func, data);
}

int
rb_remove_event_hook(rb_event_hook_func_t func)
{
    return remove_event_hook(GET_EC(), NULL, func, Qundef);
}

int
rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data)
{
    return remove_event_hook(GET_EC(), NULL, func, data);
}

void
rb_ec_clear_current_thread_trace_func(const rb_execution_context_t *ec)
{
    rb_threadptr_remove_event_hook(ec, rb_ec_thread_ptr(ec), 0, Qundef);
}

void
rb_ec_clear_all_trace_func(const rb_execution_context_t *ec)
{
    rb_threadptr_remove_event_hook(ec, MATCH_ANY_FILTER_TH, 0, Qundef);
}

/* invoke hooks */

static void
exec_hooks_body(const rb_execution_context_t *ec, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    rb_event_hook_t *hook;

    for (hook = list->hooks; hook; hook = hook->next) {
	if (!(hook->hook_flags & RUBY_EVENT_HOOK_FLAG_DELETED) &&
	    (trace_arg->event & hook->events) &&
            (LIKELY(hook->filter.th == 0) || hook->filter.th == rb_ec_thread_ptr(ec)) &&
            (LIKELY(hook->filter.target_line == 0) || (hook->filter.target_line == (unsigned int)rb_vm_get_sourceline(ec->cfp)))) {
	    if (!(hook->hook_flags & RUBY_EVENT_HOOK_FLAG_RAW_ARG)) {
		(*hook->func)(trace_arg->event, hook->data, trace_arg->self, trace_arg->id, trace_arg->klass);
	    }
	    else {
		(*((rb_event_hook_raw_arg_func_t)hook->func))(hook->data, trace_arg);
	    }
	}
    }
}

static int
exec_hooks_precheck(const rb_execution_context_t *ec, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    if (list->events & trace_arg->event) {
        list->running++;
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static void
exec_hooks_postcheck(const rb_execution_context_t *ec, rb_hook_list_t *list)
{
    list->running--;
    clean_hooks_check(ec, list);
}

static void
exec_hooks_unprotected(const rb_execution_context_t *ec, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    if (exec_hooks_precheck(ec, list, trace_arg) == 0) return;
    exec_hooks_body(ec, list, trace_arg);
    exec_hooks_postcheck(ec, list);
}

static int
exec_hooks_protected(rb_execution_context_t *ec, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    enum ruby_tag_type state;
    volatile int raised;

    if (exec_hooks_precheck(ec, list, trace_arg) == 0) return 0;

    raised = rb_ec_reset_raised(ec);

    /* TODO: Support !RUBY_EVENT_HOOK_FLAG_SAFE hooks */

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	exec_hooks_body(ec, list, trace_arg);
    }
    EC_POP_TAG();

    exec_hooks_postcheck(ec, list);

    if (raised) {
	rb_ec_set_raised(ec);
    }

    return state;
}

MJIT_FUNC_EXPORTED void
rb_exec_event_hooks(rb_trace_arg_t *trace_arg, rb_hook_list_t *hooks, int pop_p)
{
    rb_execution_context_t *ec = trace_arg->ec;

    if (UNLIKELY(trace_arg->event & RUBY_INTERNAL_EVENT_MASK)) {
        if (ec->trace_arg && (ec->trace_arg->event & RUBY_INTERNAL_EVENT_MASK)) {
            /* skip hooks because this thread doing INTERNAL_EVENT */
	}
	else {
	    rb_trace_arg_t *prev_trace_arg = ec->trace_arg;

            ec->trace_arg = trace_arg;
            /* only global hooks */
            exec_hooks_unprotected(ec, rb_ec_ractor_hooks(ec), trace_arg);
            ec->trace_arg = prev_trace_arg;
	}
    }
    else {
	if (ec->trace_arg == NULL && /* check reentrant */
	    trace_arg->self != rb_mRubyVMFrozenCore /* skip special methods. TODO: remove it. */) {
	    const VALUE errinfo = ec->errinfo;
	    const VALUE old_recursive = ec->local_storage_recursive_hash;
	    int state = 0;

            /* setup */
	    ec->local_storage_recursive_hash = ec->local_storage_recursive_hash_for_trace;
	    ec->errinfo = Qnil;
	    ec->trace_arg = trace_arg;

            /* kick hooks */
            if ((state = exec_hooks_protected(ec, hooks, trace_arg)) == TAG_NONE) {
                ec->errinfo = errinfo;
            }

            /* cleanup */
            ec->trace_arg = NULL;
	    ec->local_storage_recursive_hash_for_trace = ec->local_storage_recursive_hash;
	    ec->local_storage_recursive_hash = old_recursive;

	    if (state) {
		if (pop_p) {
		    if (VM_FRAME_FINISHED_P(ec->cfp)) {
			ec->tag = ec->tag->prev;
		    }
		    rb_vm_pop_frame(ec);
		}
		EC_JUMP_TAG(ec, state);
	    }
	}
    }
}

VALUE
rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg)
{
    volatile int raised;
    volatile VALUE result = Qnil;
    rb_execution_context_t *const ec = GET_EC();
    rb_vm_t *const vm = rb_ec_vm_ptr(ec);
    enum ruby_tag_type state;
    rb_trace_arg_t dummy_trace_arg;
    dummy_trace_arg.event = 0;

    if (!ec->trace_arg) {
	ec->trace_arg = &dummy_trace_arg;
    }

    raised = rb_ec_reset_raised(ec);

    EC_PUSH_TAG(ec);
    if (LIKELY((state = EC_EXEC_TAG()) == TAG_NONE)) {
	result = (*func)(arg);
    }
    else {
	(void)*&vm; /* suppress "clobbered" warning */
    }
    EC_POP_TAG();

    if (raised) {
	rb_ec_reset_raised(ec);
    }

    if (ec->trace_arg == &dummy_trace_arg) {
	ec->trace_arg = NULL;
    }

    if (state) {
#if defined RUBY_USE_SETJMPEX && RUBY_USE_SETJMPEX
	RB_GC_GUARD(result);
#endif
	EC_JUMP_TAG(ec, state);
    }

    return result;
}

static void call_trace_func(rb_event_flag_t, VALUE data, VALUE self, ID id, VALUE klass);

/* (2-1) set_trace_func (old API) */

/*
 *  call-seq:
 *     set_trace_func(proc)    -> proc
 *     set_trace_func(nil)     -> nil
 *
 *  Establishes _proc_ as the handler for tracing, or disables
 *  tracing if the parameter is +nil+.
 *
 *  *Note:* this method is obsolete, please use TracePoint instead.
 *
 *  _proc_ takes up to six parameters:
 *
 *  *	an event name
 *  *	a filename
 *  *	a line number
 *  *	an object id
 *  *	a binding
 *  *	the name of a class
 *
 *  _proc_ is invoked whenever an event occurs.
 *
 *  Events are:
 *
 *  +c-call+:: call a C-language routine
 *  +c-return+:: return from a C-language routine
 *  +call+:: call a Ruby method
 *  +class+:: start a class or module definition
 *  +end+:: finish a class or module definition
 *  +line+:: execute code on a new line
 *  +raise+:: raise an exception
 *  +return+:: return from a Ruby method
 *
 *  Tracing is disabled within the context of _proc_.
 *
 *      class Test
 *	def test
 *	  a = 1
 *	  b = 2
 *	end
 *      end
 *
 *      set_trace_func proc { |event, file, line, id, binding, classname|
 *	   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
 *      }
 *      t = Test.new
 *      t.test
 *
 *	  line prog.rb:11               false
 *      c-call prog.rb:11        new    Class
 *      c-call prog.rb:11 initialize   Object
 *    c-return prog.rb:11 initialize   Object
 *    c-return prog.rb:11        new    Class
 *	  line prog.rb:12               false
 *  	  call prog.rb:2        test     Test
 *	  line prog.rb:3        test     Test
 *	  line prog.rb:4        test     Test
 *      return prog.rb:4        test     Test
 */

static VALUE
set_trace_func(VALUE obj, VALUE trace)
{
    rb_remove_event_hook(call_trace_func);

    if (NIL_P(trace)) {
	return Qnil;
    }

    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }

    rb_add_event_hook(call_trace_func, RUBY_EVENT_ALL, trace);
    return trace;
}

static void
thread_add_trace_func(rb_execution_context_t *ec, rb_thread_t *filter_th, VALUE trace)
{
    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }

    rb_threadptr_add_event_hook(ec, filter_th, call_trace_func, RUBY_EVENT_ALL, trace, RUBY_EVENT_HOOK_FLAG_SAFE);
}

/*
 *  call-seq:
 *     thr.add_trace_func(proc)    -> proc
 *
 *  Adds _proc_ as a handler for tracing.
 *
 *  See Thread#set_trace_func and Kernel#set_trace_func.
 */

static VALUE
thread_add_trace_func_m(VALUE obj, VALUE trace)
{
    thread_add_trace_func(GET_EC(), rb_thread_ptr(obj), trace);
    return trace;
}

/*
 *  call-seq:
 *     thr.set_trace_func(proc)    -> proc
 *     thr.set_trace_func(nil)     -> nil
 *
 *  Establishes _proc_ on _thr_ as the handler for tracing, or
 *  disables tracing if the parameter is +nil+.
 *
 *  See Kernel#set_trace_func.
 */

static VALUE
thread_set_trace_func_m(VALUE target_thread, VALUE trace)
{
    rb_execution_context_t *ec = GET_EC();
    rb_thread_t *target_th = rb_thread_ptr(target_thread);

    rb_threadptr_remove_event_hook(ec, target_th, call_trace_func, Qundef);

    if (NIL_P(trace)) {
	return Qnil;
    }
    else {
	thread_add_trace_func(ec, target_th, trace);
	return trace;
    }
}

static const char *
get_event_name(rb_event_flag_t event)
{
    switch (event) {
      case RUBY_EVENT_LINE:     return "line";
      case RUBY_EVENT_CLASS:    return "class";
      case RUBY_EVENT_END:      return "end";
      case RUBY_EVENT_CALL:     return "call";
      case RUBY_EVENT_RETURN:	return "return";
      case RUBY_EVENT_C_CALL:	return "c-call";
      case RUBY_EVENT_C_RETURN:	return "c-return";
      case RUBY_EVENT_RAISE:	return "raise";
      default:
	return "unknown";
    }
}

static ID
get_event_id(rb_event_flag_t event)
{
    ID id;

    switch (event) {
#define C(name, NAME) case RUBY_EVENT_##NAME: CONST_ID(id, #name); return id;
	C(line, LINE);
	C(class, CLASS);
	C(end, END);
	C(call, CALL);
	C(return, RETURN);
	C(c_call, C_CALL);
	C(c_return, C_RETURN);
	C(raise, RAISE);
	C(b_call, B_CALL);
	C(b_return, B_RETURN);
	C(thread_begin, THREAD_BEGIN);
	C(thread_end, THREAD_END);
	C(fiber_switch, FIBER_SWITCH);
        C(script_compiled, SCRIPT_COMPILED);
#undef C
      default:
	return 0;
    }
}

static void
get_path_and_lineno(const rb_execution_context_t *ec, const rb_control_frame_t *cfp, rb_event_flag_t event, VALUE *pathp, int *linep)
{
    cfp = rb_vm_get_ruby_level_next_cfp(ec, cfp);

    if (cfp) {
	const rb_iseq_t *iseq = cfp->iseq;
	*pathp = rb_iseq_path(iseq);

	if (event & (RUBY_EVENT_CLASS |
				RUBY_EVENT_CALL  |
				RUBY_EVENT_B_CALL)) {
	    *linep = FIX2INT(rb_iseq_first_lineno(iseq));
	}
	else {
	    *linep = rb_vm_get_sourceline(cfp);
	}
    }
    else {
	*pathp = Qnil;
	*linep = 0;
    }
}

static void
call_trace_func(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
    int line;
    VALUE filename;
    VALUE eventname = rb_str_new2(get_event_name(event));
    VALUE argv[6];
    const rb_execution_context_t *ec = GET_EC();

    get_path_and_lineno(ec, ec->cfp, event, &filename, &line);

    if (!klass) {
	rb_ec_frame_method_id_and_class(ec, &id, 0, &klass);
    }

    if (klass) {
	if (RB_TYPE_P(klass, T_ICLASS)) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = rb_ivar_get(klass, id__attached__);
	}
    }

    argv[0] = eventname;
    argv[1] = filename;
    argv[2] = INT2FIX(line);
    argv[3] = id ? ID2SYM(id) : Qnil;
    argv[4] = (self && (filename != Qnil)) ? rb_binding_new() : Qnil;
    argv[5] = klass ? klass : Qnil;

    rb_proc_call_with_block(proc, 6, argv, Qnil);
}

/* (2-2) TracePoint API */

static VALUE rb_cTracePoint;

typedef struct rb_tp_struct {
    rb_event_flag_t events;
    int tracing; /* bool */
    rb_thread_t *target_th;
    VALUE local_target_set; /* Hash: target ->
                             * Qtrue (if target is iseq) or
                             * Qfalse (if target is bmethod)
                             */
    void (*func)(VALUE tpval, void *data);
    void *data;
    VALUE proc;
    rb_ractor_t *ractor;
    VALUE self;
} rb_tp_t;

static void
tp_mark(void *ptr)
{
    rb_tp_t *tp = ptr;
    rb_gc_mark(tp->proc);
    rb_gc_mark(tp->local_target_set);
    if (tp->target_th) rb_gc_mark(tp->target_th->self);
}

static size_t
tp_memsize(const void *ptr)
{
    return sizeof(rb_tp_t);
}

static const rb_data_type_t tp_data_type = {
    "tracepoint",
    {tp_mark, RUBY_TYPED_NEVER_FREE, tp_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
tp_alloc(VALUE klass)
{
    rb_tp_t *tp;
    return TypedData_Make_Struct(klass, rb_tp_t, &tp_data_type, tp);
}

static rb_event_flag_t
symbol2event_flag(VALUE v)
{
    ID id;
    VALUE sym = rb_to_symbol_type(v);
    const rb_event_flag_t RUBY_EVENT_A_CALL =
	RUBY_EVENT_CALL | RUBY_EVENT_B_CALL | RUBY_EVENT_C_CALL;
    const rb_event_flag_t RUBY_EVENT_A_RETURN =
	RUBY_EVENT_RETURN | RUBY_EVENT_B_RETURN | RUBY_EVENT_C_RETURN;

#define C(name, NAME) CONST_ID(id, #name); if (sym == ID2SYM(id)) return RUBY_EVENT_##NAME
    C(line, LINE);
    C(class, CLASS);
    C(end, END);
    C(call, CALL);
    C(return, RETURN);
    C(c_call, C_CALL);
    C(c_return, C_RETURN);
    C(raise, RAISE);
    C(b_call, B_CALL);
    C(b_return, B_RETURN);
    C(thread_begin, THREAD_BEGIN);
    C(thread_end, THREAD_END);
    C(fiber_switch, FIBER_SWITCH);
    C(script_compiled, SCRIPT_COMPILED);

    /* joke */
    C(a_call, A_CALL);
    C(a_return, A_RETURN);
#undef C
    rb_raise(rb_eArgError, "unknown event: %"PRIsVALUE, rb_sym2str(sym));
}

static rb_tp_t *
tpptr(VALUE tpval)
{
    rb_tp_t *tp;
    TypedData_Get_Struct(tpval, rb_tp_t, &tp_data_type, tp);
    return tp;
}

static rb_trace_arg_t *
get_trace_arg(void)
{
    rb_trace_arg_t *trace_arg = GET_EC()->trace_arg;
    if (trace_arg == 0) {
	rb_raise(rb_eRuntimeError, "access from outside");
    }
    return trace_arg;
}

struct rb_trace_arg_struct *
rb_tracearg_from_tracepoint(VALUE tpval)
{
    return get_trace_arg();
}

rb_event_flag_t
rb_tracearg_event_flag(rb_trace_arg_t *trace_arg)
{
    return trace_arg->event;
}

VALUE
rb_tracearg_event(rb_trace_arg_t *trace_arg)
{
    return ID2SYM(get_event_id(trace_arg->event));
}

static void
fill_path_and_lineno(rb_trace_arg_t *trace_arg)
{
    if (trace_arg->path == Qundef) {
	get_path_and_lineno(trace_arg->ec, trace_arg->cfp, trace_arg->event, &trace_arg->path, &trace_arg->lineno);
    }
}

VALUE
rb_tracearg_lineno(rb_trace_arg_t *trace_arg)
{
    fill_path_and_lineno(trace_arg);
    return INT2FIX(trace_arg->lineno);
}
VALUE
rb_tracearg_path(rb_trace_arg_t *trace_arg)
{
    fill_path_and_lineno(trace_arg);
    return trace_arg->path;
}

static void
fill_id_and_klass(rb_trace_arg_t *trace_arg)
{
    if (!trace_arg->klass_solved) {
	if (!trace_arg->klass) {
	    rb_vm_control_frame_id_and_class(trace_arg->cfp, &trace_arg->id, &trace_arg->called_id, &trace_arg->klass);
	}

	if (trace_arg->klass) {
	    if (RB_TYPE_P(trace_arg->klass, T_ICLASS)) {
		trace_arg->klass = RBASIC(trace_arg->klass)->klass;
	    }
	}
	else {
	    trace_arg->klass = Qnil;
	}

	trace_arg->klass_solved = 1;
    }
}

VALUE
rb_tracearg_parameters(rb_trace_arg_t *trace_arg)
{
    switch(trace_arg->event) {
      case RUBY_EVENT_CALL:
      case RUBY_EVENT_RETURN:
      case RUBY_EVENT_B_CALL:
      case RUBY_EVENT_B_RETURN: {
	const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(trace_arg->ec, trace_arg->cfp);
	if (cfp) {
            int is_proc = 0;
            if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_BLOCK && !VM_FRAME_LAMBDA_P(cfp)) {
                is_proc = 1;
            }
	    return rb_iseq_parameters(cfp->iseq, is_proc);
	}
	break;
      }
      case RUBY_EVENT_C_CALL:
      case RUBY_EVENT_C_RETURN: {
	fill_id_and_klass(trace_arg);
	if (trace_arg->klass && trace_arg->id) {
	    const rb_method_entry_t *me;
	    VALUE iclass = Qnil;
	    me = rb_method_entry_without_refinements(trace_arg->klass, trace_arg->id, &iclass);
	    return rb_unnamed_parameters(rb_method_entry_arity(me));
	}
	break;
      }
      case RUBY_EVENT_RAISE:
      case RUBY_EVENT_LINE:
      case RUBY_EVENT_CLASS:
      case RUBY_EVENT_END:
      case RUBY_EVENT_SCRIPT_COMPILED:
	rb_raise(rb_eRuntimeError, "not supported by this event");
	break;
    }
    return Qnil;
}

VALUE
rb_tracearg_method_id(rb_trace_arg_t *trace_arg)
{
    fill_id_and_klass(trace_arg);
    return trace_arg->id ? ID2SYM(trace_arg->id) : Qnil;
}

VALUE
rb_tracearg_callee_id(rb_trace_arg_t *trace_arg)
{
    fill_id_and_klass(trace_arg);
    return trace_arg->called_id ? ID2SYM(trace_arg->called_id) : Qnil;
}

VALUE
rb_tracearg_defined_class(rb_trace_arg_t *trace_arg)
{
    fill_id_and_klass(trace_arg);
    return trace_arg->klass;
}

VALUE
rb_tracearg_binding(rb_trace_arg_t *trace_arg)
{
    rb_control_frame_t *cfp;
    cfp = rb_vm_get_binding_creatable_next_cfp(trace_arg->ec, trace_arg->cfp);

    if (cfp) {
	return rb_vm_make_binding(trace_arg->ec, cfp);
    }
    else {
	return Qnil;
    }
}

VALUE
rb_tracearg_self(rb_trace_arg_t *trace_arg)
{
    return trace_arg->self;
}

VALUE
rb_tracearg_return_value(rb_trace_arg_t *trace_arg)
{
    if (trace_arg->event & (RUBY_EVENT_RETURN | RUBY_EVENT_C_RETURN | RUBY_EVENT_B_RETURN)) {
	/* ok */
    }
    else {
	rb_raise(rb_eRuntimeError, "not supported by this event");
    }
    if (trace_arg->data == Qundef) {
        rb_bug("rb_tracearg_return_value: unreachable");
    }
    return trace_arg->data;
}

VALUE
rb_tracearg_raised_exception(rb_trace_arg_t *trace_arg)
{
    if (trace_arg->event & (RUBY_EVENT_RAISE)) {
	/* ok */
    }
    else {
	rb_raise(rb_eRuntimeError, "not supported by this event");
    }
    if (trace_arg->data == Qundef) {
        rb_bug("rb_tracearg_raised_exception: unreachable");
    }
    return trace_arg->data;
}

VALUE
rb_tracearg_eval_script(rb_trace_arg_t *trace_arg)
{
    VALUE data = trace_arg->data;

    if (trace_arg->event & (RUBY_EVENT_SCRIPT_COMPILED)) {
        /* ok */
    }
    else {
        rb_raise(rb_eRuntimeError, "not supported by this event");
    }
    if (data == Qundef) {
        rb_bug("rb_tracearg_raised_exception: unreachable");
    }
    if (rb_obj_is_iseq(data)) {
        return Qnil;
    }
    else {
        VM_ASSERT(RB_TYPE_P(data, T_ARRAY));
        /* [src, iseq] */
        return RARRAY_AREF(data, 0);
    }
}

VALUE
rb_tracearg_instruction_sequence(rb_trace_arg_t *trace_arg)
{
    VALUE data = trace_arg->data;

    if (trace_arg->event & (RUBY_EVENT_SCRIPT_COMPILED)) {
        /* ok */
    }
    else {
        rb_raise(rb_eRuntimeError, "not supported by this event");
    }
    if (data == Qundef) {
        rb_bug("rb_tracearg_raised_exception: unreachable");
    }

    if (rb_obj_is_iseq(data)) {
        return rb_iseqw_new((const rb_iseq_t *)data);
    }
    else {
        VM_ASSERT(RB_TYPE_P(data, T_ARRAY));
        VM_ASSERT(rb_obj_is_iseq(RARRAY_AREF(data, 1)));

        /* [src, iseq] */
        return rb_iseqw_new((const rb_iseq_t *)RARRAY_AREF(data, 1));
    }
}

VALUE
rb_tracearg_object(rb_trace_arg_t *trace_arg)
{
    if (trace_arg->event & (RUBY_INTERNAL_EVENT_NEWOBJ | RUBY_INTERNAL_EVENT_FREEOBJ)) {
	/* ok */
    }
    else {
	rb_raise(rb_eRuntimeError, "not supported by this event");
    }
    if (trace_arg->data == Qundef) {
        rb_bug("rb_tracearg_object: unreachable");
    }
    return trace_arg->data;
}

static VALUE
tracepoint_attr_event(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_event(get_trace_arg());
}

static VALUE
tracepoint_attr_lineno(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_lineno(get_trace_arg());
}
static VALUE
tracepoint_attr_path(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_path(get_trace_arg());
}

static VALUE
tracepoint_attr_parameters(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_parameters(get_trace_arg());
}

static VALUE
tracepoint_attr_method_id(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_method_id(get_trace_arg());
}

static VALUE
tracepoint_attr_callee_id(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_callee_id(get_trace_arg());
}

static VALUE
tracepoint_attr_defined_class(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_defined_class(get_trace_arg());
}

static VALUE
tracepoint_attr_binding(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_binding(get_trace_arg());
}

static VALUE
tracepoint_attr_self(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_self(get_trace_arg());
}

static VALUE
tracepoint_attr_return_value(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_return_value(get_trace_arg());
}

static VALUE
tracepoint_attr_raised_exception(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_raised_exception(get_trace_arg());
}

static VALUE
tracepoint_attr_eval_script(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_eval_script(get_trace_arg());
}

static VALUE
tracepoint_attr_instruction_sequence(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracearg_instruction_sequence(get_trace_arg());
}

static void
tp_call_trace(VALUE tpval, rb_trace_arg_t *trace_arg)
{
    rb_tp_t *tp = tpptr(tpval);

    if (tp->func) {
	(*tp->func)(tpval, tp->data);
    }
    else {
        if (tp->ractor == NULL || tp->ractor == GET_RACTOR()) {
            rb_proc_call_with_block((VALUE)tp->proc, 1, &tpval, Qnil);
        }
    }
}

VALUE
rb_tracepoint_enable(VALUE tpval)
{
    rb_tp_t *tp;
    tp = tpptr(tpval);

    if (tp->local_target_set != Qfalse) {
        rb_raise(rb_eArgError, "can't nest-enable a targeting TracePoint");
    }

    if (tp->target_th) {
	rb_thread_add_event_hook2(tp->target_th->self, (rb_event_hook_func_t)tp_call_trace, tp->events, tpval,
				  RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    }
    else {
	rb_add_event_hook2((rb_event_hook_func_t)tp_call_trace, tp->events, tpval,
			   RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    }
    tp->tracing = 1;
    return Qundef;
}

static const rb_iseq_t *
iseq_of(VALUE target)
{
    VALUE iseqv = rb_funcall(rb_cISeq, rb_intern("of"), 1, target);
    if (NIL_P(iseqv)) {
        rb_raise(rb_eArgError, "specified target is not supported");
    }
    else {
        return rb_iseqw_to_iseq(iseqv);
    }
}

const rb_method_definition_t *rb_method_def(VALUE method); /* proc.c */

static VALUE
rb_tracepoint_enable_for_target(VALUE tpval, VALUE target, VALUE target_line)
{
    rb_tp_t *tp = tpptr(tpval);
    const rb_iseq_t *iseq = iseq_of(target);
    int n;
    unsigned int line = 0;

    if (tp->tracing > 0) {
        rb_raise(rb_eArgError, "can't nest-enable a targeting TracePoint");
    }

    if (!NIL_P(target_line)) {
        if ((tp->events & RUBY_EVENT_LINE) == 0) {
            rb_raise(rb_eArgError, "target_line is specified, but line event is not specified");
        }
        else {
            line = NUM2UINT(target_line);
        }
    }

    VM_ASSERT(tp->local_target_set == Qfalse);
    tp->local_target_set = rb_obj_hide(rb_ident_hash_new());

    /* iseq */
    n = rb_iseq_add_local_tracepoint_recursively(iseq, tp->events, tpval, line);
    rb_hash_aset(tp->local_target_set, (VALUE)iseq, Qtrue);

    /* bmethod */
    if (rb_obj_is_method(target)) {
        rb_method_definition_t *def = (rb_method_definition_t *)rb_method_def(target);
        if (def->type == VM_METHOD_TYPE_BMETHOD &&
            (tp->events & (RUBY_EVENT_CALL | RUBY_EVENT_RETURN))) {
            def->body.bmethod.hooks = ZALLOC(rb_hook_list_t);
            rb_hook_list_connect_tracepoint(target, def->body.bmethod.hooks, tpval, 0);
            rb_hash_aset(tp->local_target_set, target, Qfalse);

            n++;
        }
    }

    if (n == 0) {
        rb_raise(rb_eArgError, "can not enable any hooks");
    }

    ruby_vm_event_local_num++;

    tp->tracing = 1;

    return Qnil;
}

static int
disable_local_event_iseq_i(VALUE target, VALUE iseq_p, VALUE tpval)
{
    if (iseq_p) {
        rb_iseq_remove_local_tracepoint_recursively((rb_iseq_t *)target, tpval);
    }
    else {
        /* bmethod */
        rb_method_definition_t *def = (rb_method_definition_t *)rb_method_def(target);
        rb_hook_list_t *hooks = def->body.bmethod.hooks;
        VM_ASSERT(hooks != NULL);
        rb_hook_list_remove_tracepoint(hooks, tpval);
        if (hooks->running == 0) {
            rb_hook_list_free(def->body.bmethod.hooks);
        }
        def->body.bmethod.hooks = NULL;
    }
    return ST_CONTINUE;
}

VALUE
rb_tracepoint_disable(VALUE tpval)
{
    rb_tp_t *tp;

    tp = tpptr(tpval);

    if (tp->local_target_set) {
        rb_hash_foreach(tp->local_target_set, disable_local_event_iseq_i, tpval);
        tp->local_target_set = Qfalse;
        ruby_vm_event_local_num--;
    }
    else {
        if (tp->target_th) {
            rb_thread_remove_event_hook_with_data(tp->target_th->self, (rb_event_hook_func_t)tp_call_trace, tpval);
        }
        else {
            rb_remove_event_hook_with_data((rb_event_hook_func_t)tp_call_trace, tpval);
        }
    }
    tp->tracing = 0;
    tp->target_th = NULL;
    return Qundef;
}

void
rb_hook_list_connect_tracepoint(VALUE target, rb_hook_list_t *list, VALUE tpval, unsigned int target_line)
{
    rb_tp_t *tp = tpptr(tpval);
    rb_event_hook_t *hook = alloc_event_hook((rb_event_hook_func_t)tp_call_trace, tp->events, tpval,
                                             RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    hook->filter.target_line = target_line;
    hook_list_connect(target, list, hook, FALSE);
}

void
rb_hook_list_remove_tracepoint(rb_hook_list_t *list, VALUE tpval)
{
    rb_event_hook_t *hook = list->hooks;
    rb_event_flag_t events = 0;

    while (hook) {
        if (hook->data == tpval) {
            hook->hook_flags |= RUBY_EVENT_HOOK_FLAG_DELETED;
            list->need_clean = TRUE;
        }
        else {
            events |= hook->events;
        }
        hook = hook->next;
    }

    list->events = events;
}

static VALUE
tracepoint_enable_m(rb_execution_context_t *ec, VALUE tpval, VALUE target, VALUE target_line, VALUE target_thread)
{
    rb_tp_t *tp = tpptr(tpval);
    int previous_tracing = tp->tracing;

    /* check target_thread */
    if (RTEST(target_thread)) {
        if (tp->target_th) {
            rb_raise(rb_eArgError, "can not override target_thread filter");
        }
        tp->target_th = rb_thread_ptr(target_thread);
    }
    else {
        tp->target_th = NULL;
    }

    if (NIL_P(target)) {
        if (!NIL_P(target_line)) {
            rb_raise(rb_eArgError, "only target_line is specified");
        }
        rb_tracepoint_enable(tpval);
    }
    else {
        rb_tracepoint_enable_for_target(tpval, target, target_line);
    }

    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, Qundef,
			 previous_tracing ? rb_tracepoint_enable : rb_tracepoint_disable,
			 tpval);
    }
    else {
	return previous_tracing ? Qtrue : Qfalse;
    }
}

static VALUE
tracepoint_disable_m(rb_execution_context_t *ec, VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    int previous_tracing = tp->tracing;

    if (rb_block_given_p()) {
        if (tp->local_target_set != Qfalse) {
            rb_raise(rb_eArgError, "can't disable a targeting TracePoint in a block");
        }

        rb_tracepoint_disable(tpval);
        return rb_ensure(rb_yield, Qundef,
			 previous_tracing ? rb_tracepoint_enable : rb_tracepoint_disable,
			 tpval);
    }
    else {
        rb_tracepoint_disable(tpval);
	return previous_tracing ? Qtrue : Qfalse;
    }
}

VALUE
rb_tracepoint_enabled_p(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    return tp->tracing ? Qtrue : Qfalse;
}

static VALUE
tracepoint_enabled_p(rb_execution_context_t *ec, VALUE tpval)
{
    return rb_tracepoint_enabled_p(tpval);
}

static VALUE
tracepoint_new(VALUE klass, rb_thread_t *target_th, rb_event_flag_t events, void (func)(VALUE, void*), void *data, VALUE proc)
{
    VALUE tpval = tp_alloc(klass);
    rb_tp_t *tp;
    TypedData_Get_Struct(tpval, rb_tp_t, &tp_data_type, tp);

    tp->proc = proc;
    tp->ractor = rb_ractor_shareable_p(proc) ? NULL : GET_RACTOR();
    tp->func = func;
    tp->data = data;
    tp->events = events;
    tp->self = tpval;

    return tpval;
}

/*
 * Creates a tracepoint by registering a callback function for one or more
 * tracepoint events. Once the tracepoint is created, you can use
 * rb_tracepoint_enable to enable the tracepoint.
 *
 * Parameters:
 *   1. VALUE target_thval - Meant for picking the thread in which the tracepoint
 *      is to be created. However, current implementation ignore this parameter,
 *      tracepoint is created for all threads. Simply specify Qnil.
 *   2. rb_event_flag_t events - Event(s) to listen to.
 *   3. void (*func)(VALUE, void *) - A callback function.
 *   4. void *data - Void pointer that will be passed to the callback function.
 *
 * When the callback function is called, it will be passed 2 parameters:
 *   1)VALUE tpval - the TracePoint object from which trace args can be extracted.
 *   2)void *data - A void pointer which helps to share scope with the callback function.
 *
 * It is important to note that you cannot register callbacks for normal events and internal events
 * simultaneously because they are different purpose.
 * You can use any Ruby APIs (calling methods and so on) on normal event hooks.
 * However, in internal events, you can not use any Ruby APIs (even object creations).
 * This is why we can't specify internal events by TracePoint directly.
 * Limitations are MRI version specific.
 *
 * Example:
 *   rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_NEWOBJ | RUBY_INTERNAL_EVENT_FREEOBJ, obj_event_i, data);
 *
 *   In this example, a callback function obj_event_i will be registered for
 *   internal events RUBY_INTERNAL_EVENT_NEWOBJ and RUBY_INTERNAL_EVENT_FREEOBJ.
 */
VALUE
rb_tracepoint_new(VALUE target_thval, rb_event_flag_t events, void (*func)(VALUE, void *), void *data)
{
    rb_thread_t *target_th = NULL;

    if (RTEST(target_thval)) {
	target_th = rb_thread_ptr(target_thval);
	/* TODO: Test it!
	 * Warning: This function is not tested.
	 */
    }
    return tracepoint_new(rb_cTracePoint, target_th, events, func, data, Qundef);
}

static VALUE
tracepoint_new_s(rb_execution_context_t *ec, VALUE self, VALUE args)
{
    rb_event_flag_t events = 0;
    long i;
    long argc = RARRAY_LEN(args);

    if (argc > 0) {
        for (i=0; i<argc; i++) {
	    events |= symbol2event_flag(RARRAY_AREF(args, i));
        }
    }
    else {
	events = RUBY_EVENT_TRACEPOINT_ALL;
    }

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "must be called with a block");
    }

    return tracepoint_new(self, 0, events, 0, 0, rb_block_proc());
}

static VALUE
tracepoint_trace_s(rb_execution_context_t *ec, VALUE self, VALUE args)
{
    VALUE trace = tracepoint_new_s(ec, self, args);
    rb_tracepoint_enable(trace);
    return trace;
}

static VALUE
tracepoint_inspect(rb_execution_context_t *ec, VALUE self)
{
    rb_tp_t *tp = tpptr(self);
    rb_trace_arg_t *trace_arg = GET_EC()->trace_arg;

    if (trace_arg) {
	switch (trace_arg->event) {
	  case RUBY_EVENT_LINE:
	    {
		VALUE sym = rb_tracearg_method_id(trace_arg);
		if (NIL_P(sym))
                    break;
		return rb_sprintf("#<TracePoint:%"PRIsVALUE" %"PRIsVALUE":%d in `%"PRIsVALUE"'>",
				  rb_tracearg_event(trace_arg),
				  rb_tracearg_path(trace_arg),
				  FIX2INT(rb_tracearg_lineno(trace_arg)),
				  sym);
	    }
	  case RUBY_EVENT_CALL:
	  case RUBY_EVENT_C_CALL:
	  case RUBY_EVENT_RETURN:
	  case RUBY_EVENT_C_RETURN:
	    return rb_sprintf("#<TracePoint:%"PRIsVALUE" `%"PRIsVALUE"' %"PRIsVALUE":%d>",
			      rb_tracearg_event(trace_arg),
			      rb_tracearg_method_id(trace_arg),
			      rb_tracearg_path(trace_arg),
			      FIX2INT(rb_tracearg_lineno(trace_arg)));
	  case RUBY_EVENT_THREAD_BEGIN:
	  case RUBY_EVENT_THREAD_END:
	    return rb_sprintf("#<TracePoint:%"PRIsVALUE" %"PRIsVALUE">",
			      rb_tracearg_event(trace_arg),
			      rb_tracearg_self(trace_arg));
	  default:
            break;
	}
        return rb_sprintf("#<TracePoint:%"PRIsVALUE" %"PRIsVALUE":%d>",
                          rb_tracearg_event(trace_arg),
                          rb_tracearg_path(trace_arg),
                          FIX2INT(rb_tracearg_lineno(trace_arg)));
    }
    else {
	return rb_sprintf("#<TracePoint:%s>", tp->tracing ? "enabled" : "disabled");
    }
}

static void
tracepoint_stat_event_hooks(VALUE hash, VALUE key, rb_event_hook_t *hook)
{
    int active = 0, deleted = 0;

    while (hook) {
	if (hook->hook_flags & RUBY_EVENT_HOOK_FLAG_DELETED) {
	    deleted++;
	}
	else {
	    active++;
	}
	hook = hook->next;
    }

    rb_hash_aset(hash, key, rb_ary_new3(2, INT2FIX(active), INT2FIX(deleted)));
}

static VALUE
tracepoint_stat_s(rb_execution_context_t *ec, VALUE self)
{
    rb_vm_t *vm = GET_VM();
    VALUE stat = rb_hash_new();

    tracepoint_stat_event_hooks(stat, vm->self, rb_ec_ractor_hooks(ec)->hooks);
    /* TODO: thread local hooks */

    return stat;
}

#include "trace_point.rbinc"

/* This function is called from inits.c */
void
Init_vm_trace(void)
{
    /* trace_func */
    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_define_method(rb_cThread, "set_trace_func", thread_set_trace_func_m, 1);
    rb_define_method(rb_cThread, "add_trace_func", thread_add_trace_func_m, 1);

    rb_cTracePoint = rb_define_class("TracePoint", rb_cObject);
    rb_undef_alloc_func(rb_cTracePoint);
}

typedef struct rb_postponed_job_struct {
    rb_postponed_job_func_t func;
    void *data;
} rb_postponed_job_t;

#define MAX_POSTPONED_JOB                  1000
#define MAX_POSTPONED_JOB_SPECIAL_ADDITION   24

struct rb_workqueue_job {
    struct list_node jnode; /* <=> vm->workqueue */
    rb_postponed_job_t job;
};

void
Init_vm_postponed_job(void)
{
    rb_vm_t *vm = GET_VM();
    vm->postponed_job_buffer = ALLOC_N(rb_postponed_job_t, MAX_POSTPONED_JOB);
    vm->postponed_job_index = 0;
    /* workqueue is initialized when VM locks are initialized */
}

enum postponed_job_register_result {
    PJRR_SUCCESS     = 0,
    PJRR_FULL        = 1,
    PJRR_INTERRUPTED = 2
};

/* Async-signal-safe */
static enum postponed_job_register_result
postponed_job_register(rb_execution_context_t *ec, rb_vm_t *vm,
                       unsigned int flags, rb_postponed_job_func_t func, void *data, rb_atomic_t max, rb_atomic_t expected_index)
{
    rb_postponed_job_t *pjob;

    if (expected_index >= max) return PJRR_FULL; /* failed */

    if (ATOMIC_CAS(vm->postponed_job_index, expected_index, expected_index+1) == expected_index) {
        pjob = &vm->postponed_job_buffer[expected_index];
    }
    else {
        return PJRR_INTERRUPTED;
    }

    /* unused: pjob->flags = flags; */
    pjob->func = func;
    pjob->data = data;

    RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(ec);

    return PJRR_SUCCESS;
}

/*
 * return 0 if job buffer is full
 * Async-signal-safe
 */
int
rb_postponed_job_register(unsigned int flags, rb_postponed_job_func_t func, void *data)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);

  begin:
    switch (postponed_job_register(ec, vm, flags, func, data, MAX_POSTPONED_JOB, vm->postponed_job_index)) {
      case PJRR_SUCCESS    : return 1;
      case PJRR_FULL       : return 0;
      case PJRR_INTERRUPTED: goto begin;
      default: rb_bug("unreachable\n");
    }
}

/*
 * return 0 if job buffer is full
 * Async-signal-safe
 */
int
rb_postponed_job_register_one(unsigned int flags, rb_postponed_job_func_t func, void *data)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);
    rb_postponed_job_t *pjob;
    rb_atomic_t i, index;

  begin:
    index = vm->postponed_job_index;
    for (i=0; i<index; i++) {
        pjob = &vm->postponed_job_buffer[i];
        if (pjob->func == func) {
            RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(ec);
            return 2;
        }
    }
    switch (postponed_job_register(ec, vm, flags, func, data, MAX_POSTPONED_JOB + MAX_POSTPONED_JOB_SPECIAL_ADDITION, index)) {
      case PJRR_SUCCESS    : return 1;
      case PJRR_FULL       : return 0;
      case PJRR_INTERRUPTED: goto begin;
      default: rb_bug("unreachable\n");
    }
}

/*
 * thread-safe and called from non-Ruby thread
 * returns FALSE on failure (ENOMEM), TRUE otherwise
 */
int
rb_workqueue_register(unsigned flags, rb_postponed_job_func_t func, void *data)
{
    struct rb_workqueue_job *wq_job = malloc(sizeof(*wq_job));
    rb_vm_t *vm = GET_VM();

    if (!wq_job) return FALSE;
    wq_job->job.func = func;
    wq_job->job.data = data;

    rb_nativethread_lock_lock(&vm->workqueue_lock);
    list_add_tail(&vm->workqueue, &wq_job->jnode);
    rb_nativethread_lock_unlock(&vm->workqueue_lock);

    // TODO: current implementation affects only main ractor
    RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(rb_vm_main_ractor_ec(vm));

    return TRUE;
}

void
rb_postponed_job_flush(rb_vm_t *vm)
{
    rb_execution_context_t *ec = GET_EC();
    const rb_atomic_t block_mask = POSTPONED_JOB_INTERRUPT_MASK|TRAP_INTERRUPT_MASK;
    volatile rb_atomic_t saved_mask = ec->interrupt_mask & block_mask;
    VALUE volatile saved_errno = ec->errinfo;
    struct list_head tmp;

    list_head_init(&tmp);

    rb_nativethread_lock_lock(&vm->workqueue_lock);
    list_append_list(&tmp, &vm->workqueue);
    rb_nativethread_lock_unlock(&vm->workqueue_lock);

    ec->errinfo = Qnil;
    /* mask POSTPONED_JOB dispatch */
    ec->interrupt_mask |= block_mask;
    {
	EC_PUSH_TAG(ec);
	if (EC_EXEC_TAG() == TAG_NONE) {
            rb_atomic_t index;
            struct rb_workqueue_job *wq_job;

            while ((index = vm->postponed_job_index) > 0) {
                if (ATOMIC_CAS(vm->postponed_job_index, index, index-1) == index) {
                    rb_postponed_job_t *pjob = &vm->postponed_job_buffer[index-1];
                    (*pjob->func)(pjob->data);
                }
	    }
            while ((wq_job = list_pop(&tmp, struct rb_workqueue_job, jnode))) {
                rb_postponed_job_t pjob = wq_job->job;

                free(wq_job);
                (pjob.func)(pjob.data);
            }
	}
	EC_POP_TAG();
    }
    /* restore POSTPONED_JOB mask */
    ec->interrupt_mask &= ~(saved_mask ^ block_mask);
    ec->errinfo = saved_errno;

    /* don't leak memory if a job threw an exception */
    if (!list_empty(&tmp)) {
        rb_nativethread_lock_lock(&vm->workqueue_lock);
        list_prepend_list(&vm->workqueue, &tmp);
        rb_nativethread_lock_unlock(&vm->workqueue_lock);

        RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(GET_EC());
    }
}
