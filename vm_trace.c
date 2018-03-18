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

#include "internal.h"
#include "ruby/debug.h"

#include "vm_core.h"
#include "eval_intern.h"

/* (1) trace mechanisms */

typedef struct rb_event_hook_struct {
    rb_event_hook_flag_t hook_flags;
    rb_event_flag_t events;
    rb_event_hook_func_t func;
    VALUE data;
    struct rb_event_hook_struct *next;
} rb_event_hook_t;

typedef void (*rb_event_hook_raw_arg_func_t)(VALUE data, const rb_trace_arg_t *arg);

#define MAX_EVENT_NUM 32

static int ruby_event_flag_count[MAX_EVENT_NUM] = {0};

/* called from vm.c */

void
rb_vm_trace_mark_event_hooks(rb_hook_list_t *hooks)
{
    rb_event_hook_t *hook = hooks->hooks;

    while (hook) {
	rb_gc_mark(hook->data);
	hook = hook->next;
    }
}

/* ruby_vm_event_flags management */

static void
recalc_add_ruby_vm_event_flags(rb_event_flag_t events)
{
    int i;
    ruby_vm_event_flags = 0;

    for (i=0; i<MAX_EVENT_NUM; i++) {
	if (events & ((rb_event_flag_t)1 << i)) {
	    ruby_event_flag_count[i]++;
	}
	ruby_vm_event_flags |= ruby_event_flag_count[i] ? (1<<i) : 0;
    }

    rb_objspace_set_event_hook(ruby_vm_event_flags);
}

static void
recalc_remove_ruby_vm_event_flags(rb_event_flag_t events)
{
    int i;
    ruby_vm_event_flags = 0;

    for (i=0; i<MAX_EVENT_NUM; i++) {
	if (events & (1 << i)) {
	    ruby_event_flag_count[i]--;
	}
	ruby_vm_event_flags |= ruby_event_flag_count[i] ? (1<<i) : 0;
    }

    rb_objspace_set_event_hook(ruby_vm_event_flags);
}

/* add/remove hooks */

static rb_thread_t *
thval2thread_t(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    return th;
}

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
    return hook;
}

static void
connect_event_hook(rb_hook_list_t *list, rb_event_hook_t *hook)
{
    hook->next = list->hooks;
    list->hooks = hook;
    recalc_add_ruby_vm_event_flags(hook->events);
    list->events |= hook->events;
}

static void
rb_threadptr_add_event_hook(rb_thread_t *th, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, hook_flags);
    connect_event_hook(&th->event_hooks, hook);
}

void
rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data, RUBY_EVENT_HOOK_FLAG_SAFE);
}

void
rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, RUBY_EVENT_HOOK_FLAG_SAFE);
    connect_event_hook(&GET_VM()->event_hooks, hook);
}

void
rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data, hook_flags);
}

void
rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, hook_flags);
    connect_event_hook(&GET_VM()->event_hooks, hook);
}

/* if func is 0, then clear all funcs */
static int
remove_event_hook(rb_hook_list_t *list, rb_event_hook_func_t func, VALUE data)
{
    int ret = 0;
    rb_event_hook_t *hook = list->hooks;

    while (hook) {
	if (func == 0 || hook->func == func) {
	    if (data == Qundef || hook->data == data) {
		hook->hook_flags |= RUBY_EVENT_HOOK_FLAG_DELETED;
		ret+=1;
		list->need_clean = TRUE;
	    }
	}
	hook = hook->next;
    }

    return ret;
}

static int
rb_threadptr_remove_event_hook(rb_thread_t *th, rb_event_hook_func_t func, VALUE data)
{
    return remove_event_hook(&th->event_hooks, func, data);
}

int
rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func)
{
    return rb_threadptr_remove_event_hook(thval2thread_t(thval), func, Qundef);
}

int
rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data)
{
    return rb_threadptr_remove_event_hook(thval2thread_t(thval), func, data);
}

int
rb_remove_event_hook(rb_event_hook_func_t func)
{
    return remove_event_hook(&GET_VM()->event_hooks, func, Qundef);
}

int
rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data)
{
    return remove_event_hook(&GET_VM()->event_hooks, func, data);
}

void
rb_clear_trace_func(void)
{
    rb_vm_t *vm = GET_VM();
    rb_thread_t *th = 0;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	rb_threadptr_remove_event_hook(th, 0, Qundef);
    }
    rb_remove_event_hook(0);
}

/* invoke hooks */

static void
clean_hooks(rb_hook_list_t *list)
{
    rb_event_hook_t *hook, **nextp = &list->hooks;

    list->events = 0;
    list->need_clean = FALSE;

    while ((hook = *nextp) != 0) {
	if (hook->hook_flags & RUBY_EVENT_HOOK_FLAG_DELETED) {
	    *nextp = hook->next;
	    recalc_remove_ruby_vm_event_flags(hook->events);
	    xfree(hook);
	}
	else {
	    list->events |= hook->events; /* update active events */
	    nextp = &hook->next;
	}
    }
}

static void
exec_hooks_body(rb_thread_t *th, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    rb_event_hook_t *hook;

    for (hook = list->hooks; hook; hook = hook->next) {
	if (!(hook->hook_flags & RUBY_EVENT_HOOK_FLAG_DELETED) && (trace_arg->event & hook->events)) {
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
exec_hooks_precheck(rb_thread_t *th, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    if (UNLIKELY(list->need_clean != FALSE)) {
	if (th->vm->trace_running <= 1) { /* only running this hooks */
	    clean_hooks(list);
	}
    }

    return (list->events & trace_arg->event) != 0;
}

static void
exec_hooks_unprotected(rb_thread_t *th, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    if (exec_hooks_precheck(th, list, trace_arg) == 0) return;
    exec_hooks_body(th, list, trace_arg);
}

static int
exec_hooks_protected(rb_thread_t *th, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg)
{
    int state;
    volatile int raised;

    if (exec_hooks_precheck(th, list, trace_arg) == 0) return 0;

    raised = rb_threadptr_reset_raised(th);

    /* TODO: Support !RUBY_EVENT_HOOK_FLAG_SAFE hooks */

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	exec_hooks_body(th, list, trace_arg);
    }
    TH_POP_TAG();

    if (raised) {
	rb_threadptr_set_raised(th);
    }

    return state;
}

static void
rb_threadptr_exec_event_hooks_orig(rb_trace_arg_t *trace_arg, int pop_p)
{
    rb_thread_t *th = trace_arg->th;

    if (trace_arg->event & RUBY_INTERNAL_EVENT_MASK) {
	if (th->trace_arg && (th->trace_arg->event & RUBY_INTERNAL_EVENT_MASK)) {
	    /* skip hooks because this thread doing INTERNAL_EVENT */
	}
	else {
	    rb_trace_arg_t *prev_trace_arg = th->trace_arg;
	    th->vm->trace_running++;
	    th->trace_arg = trace_arg;
	    exec_hooks_unprotected(th, &th->event_hooks, trace_arg);
	    exec_hooks_unprotected(th, &th->vm->event_hooks, trace_arg);
	    th->trace_arg = prev_trace_arg;
	    th->vm->trace_running--;
	}
    }
    else {
	if (th->trace_arg == 0 && /* check reentrant */
	    trace_arg->self != rb_mRubyVMFrozenCore /* skip special methods. TODO: remove it. */) {
	    const VALUE errinfo = th->errinfo;
	    const int outer_state = th->state;
	    const VALUE old_recursive = th->local_storage_recursive_hash;
	    int state = 0;

	    th->local_storage_recursive_hash = th->local_storage_recursive_hash_for_trace;
	    th->state = 0;
	    th->errinfo = Qnil;

	    th->vm->trace_running++;
	    th->trace_arg = trace_arg;
	    {
		/* thread local traces */
		state = exec_hooks_protected(th, &th->event_hooks, trace_arg);
		if (state) goto terminate;

		/* vm global traces */
		state = exec_hooks_protected(th, &th->vm->event_hooks, trace_arg);
		if (state) goto terminate;

		th->errinfo = errinfo;
	    }
	  terminate:
	    th->trace_arg = 0;
	    th->vm->trace_running--;

	    th->local_storage_recursive_hash_for_trace = th->local_storage_recursive_hash;
	    th->local_storage_recursive_hash = old_recursive;

	    if (state) {
		if (pop_p) {
		    if (VM_FRAME_TYPE_FINISH_P(th->cfp)) {
			th->tag = th->tag->prev;
		    }
		    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
		}
		TH_JUMP_TAG(th, state);
	    }
	    th->state = outer_state;
	}
    }
}

void
rb_threadptr_exec_event_hooks_and_pop_frame(rb_trace_arg_t *trace_arg)
{
    rb_threadptr_exec_event_hooks_orig(trace_arg, 1);
}

void
rb_threadptr_exec_event_hooks(rb_trace_arg_t *trace_arg)
{
    rb_threadptr_exec_event_hooks_orig(trace_arg, 0);
}

VALUE
rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg)
{
    volatile int raised;
    volatile int outer_state;
    VALUE result = Qnil;
    rb_thread_t *volatile th = GET_THREAD();
    int state;
    const int tracing = th->trace_arg ? 1 : 0;
    rb_trace_arg_t dummy_trace_arg;
    dummy_trace_arg.event = 0;

    if (!tracing) th->vm->trace_running++;
    if (!th->trace_arg) th->trace_arg = &dummy_trace_arg;

    raised = rb_threadptr_reset_raised(th);
    outer_state = th->state;
    th->state = 0;

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	result = (*func)(arg);
    }
    TH_POP_TAG();

    if (raised) {
	rb_threadptr_set_raised(th);
    }

    if (th->trace_arg == &dummy_trace_arg) th->trace_arg = 0;
    if (!tracing) th->vm->trace_running--;

    if (state) {
	JUMP_TAG(state);
    }

    th->state = outer_state;
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
 *  +class+:: start a class or module definition),
 *  +end+:: finish a class or module definition),
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
thread_add_trace_func(rb_thread_t *th, VALUE trace)
{
    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }

    rb_threadptr_add_event_hook(th, call_trace_func, RUBY_EVENT_ALL, trace, RUBY_EVENT_HOOK_FLAG_SAFE);
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
    rb_thread_t *th;

    GetThreadPtr(obj, th);
    thread_add_trace_func(th, trace);
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
thread_set_trace_func_m(VALUE obj, VALUE trace)
{
    rb_thread_t *th;

    GetThreadPtr(obj, th);
    rb_threadptr_remove_event_hook(th, call_trace_func, Qundef);

    if (NIL_P(trace)) {
	return Qnil;
    }

    thread_add_trace_func(th, trace);
    return trace;
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
	C(specified_line, SPECIFIED_LINE);
      case RUBY_EVENT_LINE | RUBY_EVENT_SPECIFIED_LINE: CONST_ID(id, "line"); return id;
#undef C
      default:
	return 0;
    }
}

static void
call_trace_func(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
    int line;
    const char *srcfile = rb_source_loc(&line);
    VALUE eventname = rb_str_new2(get_event_name(event));
    VALUE filename = srcfile ? rb_str_new2(srcfile) : Qnil;
    VALUE argv[6];
    rb_thread_t *th = GET_THREAD();

    if (!klass) {
	rb_thread_method_id_and_class(th, &id, &klass);
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
    argv[4] = (self && srcfile) ? rb_binding_new() : Qnil;
    argv[5] = klass ? klass : Qnil;

    rb_proc_call_with_block(proc, 6, argv, Qnil);
}

/* (2-2) TracePoint API */

static VALUE rb_cTracePoint;

typedef struct rb_tp_struct {
    rb_event_flag_t events;
    int tracing; /* bool */
    rb_thread_t *target_th;
    void (*func)(VALUE tpval, void *data);
    void *data;
    VALUE proc;
    VALUE self;
} rb_tp_t;

static void
tp_mark(void *ptr)
{
    rb_tp_t *tp = ptr;
    rb_gc_mark(tp->proc);
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
    VALUE sym = rb_convert_type(v, T_SYMBOL, "Symbol", "to_sym");
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
    C(specified_line, SPECIFIED_LINE);
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
    rb_trace_arg_t *trace_arg = GET_THREAD()->trace_arg;
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
	rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(trace_arg->th, trace_arg->cfp);

	if (cfp) {
	    trace_arg->path = cfp->iseq->body->location.path;
	    trace_arg->lineno = rb_vm_get_sourceline(cfp);
	}
	else {
	    trace_arg->path = Qnil;
	    trace_arg->lineno = 0;
	}
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
	    rb_vm_control_frame_id_and_class(trace_arg->cfp, &trace_arg->id, &trace_arg->klass);
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
rb_tracearg_method_id(rb_trace_arg_t *trace_arg)
{
    fill_id_and_klass(trace_arg);
    return trace_arg->id ? ID2SYM(trace_arg->id) : Qnil;
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
    cfp = rb_vm_get_binding_creatable_next_cfp(trace_arg->th, trace_arg->cfp);

    if (cfp) {
	return rb_vm_make_binding(trace_arg->th, cfp);
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
	rb_bug("tp_attr_return_value_m: unreachable");
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
	rb_bug("tp_attr_raised_exception_m: unreachable");
    }
    return trace_arg->data;
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
	rb_bug("tp_attr_raised_exception_m: unreachable");
    }
    return trace_arg->data;
}

/*
 * Type of event
 *
 * See TracePoint@Events for more information.
 */
static VALUE
tracepoint_attr_event(VALUE tpval)
{
    return rb_tracearg_event(get_trace_arg());
}

/*
 * Line number of the event
 */
static VALUE
tracepoint_attr_lineno(VALUE tpval)
{
    return rb_tracearg_lineno(get_trace_arg());
}

/*
 * Path of the file being run
 */
static VALUE
tracepoint_attr_path(VALUE tpval)
{
    return rb_tracearg_path(get_trace_arg());
}

/*
 * Return the name of the method being called
 */
static VALUE
tracepoint_attr_method_id(VALUE tpval)
{
    return rb_tracearg_method_id(get_trace_arg());
}

/*
 * Return class or module of the method being called.
 *
 *	class C; def foo; end; end
 * 	trace = TracePoint.new(:call) do |tp|
 * 	  p tp.defined_class #=> C
 * 	end.enable do
 * 	  C.new.foo
 * 	end
 *
 * If method is defined by a module, then that module is returned.
 *
 *	module M; def foo; end; end
 * 	class C; include M; end;
 * 	trace = TracePoint.new(:call) do |tp|
 * 	  p tp.defined_class #=> M
 * 	end.enable do
 * 	  C.new.foo
 * 	end
 *
 * <b>Note:</b> #defined_class returns singleton class.
 *
 * 6th block parameter of Kernel#set_trace_func passes original class
 * of attached by singleton class.
 *
 * <b>This is a difference between Kernel#set_trace_func and TracePoint.</b>
 *
 *	class C; def self.foo; end; end
 * 	trace = TracePoint.new(:call) do |tp|
 * 	  p tp.defined_class #=> #<Class:C>
 * 	end.enable do
 * 	  C.foo
 * 	end
 */
static VALUE
tracepoint_attr_defined_class(VALUE tpval)
{
    return rb_tracearg_defined_class(get_trace_arg());
}

/*
 * Return the generated binding object from event
 */
static VALUE
tracepoint_attr_binding(VALUE tpval)
{
    return rb_tracearg_binding(get_trace_arg());
}

/*
 * Return the trace object during event
 *
 * Same as TracePoint#binding:
 *	trace.binding.eval('self')
 */
static VALUE
tracepoint_attr_self(VALUE tpval)
{
    return rb_tracearg_self(get_trace_arg());
}

/*
 *  Return value from +:return+, +c_return+, and +b_return+ event
 */
static VALUE
tracepoint_attr_return_value(VALUE tpval)
{
    return rb_tracearg_return_value(get_trace_arg());
}

/*
 * Value from exception raised on the +:raise+ event
 */
static VALUE
tracepoint_attr_raised_exception(VALUE tpval)
{
    return rb_tracearg_raised_exception(get_trace_arg());
}

static void
tp_call_trace(VALUE tpval, rb_trace_arg_t *trace_arg)
{
    rb_tp_t *tp = tpptr(tpval);

    if (tp->func) {
	(*tp->func)(tpval, tp->data);
    }
    else {
	rb_proc_call_with_block((VALUE)tp->proc, 1, &tpval, Qnil);
    }
}

VALUE
rb_tracepoint_enable(VALUE tpval)
{
    rb_tp_t *tp;

    tp = tpptr(tpval);

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

VALUE
rb_tracepoint_disable(VALUE tpval)
{
    rb_tp_t *tp;

    tp = tpptr(tpval);

    if (tp->target_th) {
	rb_thread_remove_event_hook_with_data(tp->target_th->self, (rb_event_hook_func_t)tp_call_trace, tpval);
    }
    else {
	rb_remove_event_hook_with_data((rb_event_hook_func_t)tp_call_trace, tpval);
    }
    tp->tracing = 0;
    return Qundef;
}

/*
 * call-seq:
 *	trace.enable		-> true or false
 *	trace.enable { block }	-> obj
 *
 * Activates the trace
 *
 * Return true if trace was enabled.
 * Return false if trace was disabled.
 *
 *	trace.enabled?  #=> false
 *	trace.enable    #=> false (previous state)
 *                      #   trace is enabled
 *	trace.enabled?  #=> true
 *	trace.enable    #=> true (previous state)
 *                      #   trace is still enabled
 *
 * If a block is given, the trace will only be enabled within the scope of the
 * block.
 *
 *	trace.enabled?
 *	#=> false
 *
 *	trace.enable do
 *	    trace.enabled?
 *	    # only enabled for this block
 *	end
 *
 *	trace.enabled?
 *	#=> false
 *
 * Note: You cannot access event hooks within the block.
 *
 *	trace.enable { p tp.lineno }
 *	#=> RuntimeError: access from outside
 *
 */
static VALUE
tracepoint_enable_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    int previous_tracing = tp->tracing;
    rb_tracepoint_enable(tpval);

    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, Qundef,
			 previous_tracing ? rb_tracepoint_enable : rb_tracepoint_disable,
			 tpval);
    }
    else {
	return previous_tracing ? Qtrue : Qfalse;
    }
}

/*
 * call-seq:
 *	trace.disable		-> true or false
 *	trace.disable { block } -> obj
 *
 * Deactivates the trace
 *
 * Return true if trace was enabled.
 * Return false if trace was disabled.
 *
 *	trace.enabled?	#=> true
 *	trace.disable	#=> false (previous status)
 *	trace.enabled?	#=> false
 *	trace.disable	#=> false
 *
 * If a block is given, the trace will only be disable within the scope of the
 * block.
 *
 *	trace.enabled?
 *	#=> true
 *
 *	trace.disable do
 *	    trace.enabled?
 *	    # only disabled for this block
 *	end
 *
 *	trace.enabled?
 *	#=> true
 *
 * Note: You cannot access event hooks within the block.
 *
 *	trace.disable { p tp.lineno }
 *	#=> RuntimeError: access from outside
 */
static VALUE
tracepoint_disable_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    int previous_tracing = tp->tracing;
    rb_tracepoint_disable(tpval);

    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, Qundef,
			 previous_tracing ? rb_tracepoint_enable : rb_tracepoint_disable,
			 tpval);
    }
    else {
	return previous_tracing ? Qtrue : Qfalse;
    }
}

/*
 * call-seq:
 *	trace.enabled?	    -> true or false
 *
 * The current status of the trace
 */
VALUE
rb_tracepoint_enabled_p(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    return tp->tracing ? Qtrue : Qfalse;
}

static VALUE
tracepoint_new(VALUE klass, rb_thread_t *target_th, rb_event_flag_t events, void (func)(VALUE, void*), void *data, VALUE proc)
{
    VALUE tpval = tp_alloc(klass);
    rb_tp_t *tp;
    TypedData_Get_Struct(tpval, rb_tp_t, &tp_data_type, tp);

    tp->proc = proc;
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
    rb_thread_t *target_th = 0;
    if (RTEST(target_thval)) {
	GetThreadPtr(target_thval, target_th);
	/* TODO: Test it!
	 * Warning: This function is not tested.
	 */
    }
    return tracepoint_new(rb_cTracePoint, target_th, events, func, data, Qundef);
}

/*
 * call-seq:
 *	TracePoint.new(*events) { |obj| block }	    -> obj
 *
 * Returns a new TracePoint object, not enabled by default.
 *
 * Next, in order to activate the trace, you must use TracePoint.enable
 *
 *	trace = TracePoint.new(:call) do |tp|
 *	    p [tp.lineno, tp.defined_class, tp.method_id, tp.event]
 *	end
 *	#=> #<TracePoint:disabled>
 *
 *	trace.enable
 *	#=> false
 *
 *	puts "Hello, TracePoint!"
 *	# ...
 *	# [48, IRB::Notifier::AbstractNotifier, :printf, :call]
 *	# ...
 *
 * When you want to deactivate the trace, you must use TracePoint.disable
 *
 *	trace.disable
 *
 * See TracePoint@Events for possible events and more information.
 *
 * A block must be given, otherwise a ThreadError is raised.
 *
 * If the trace method isn't included in the given events filter, a
 * RuntimeError is raised.
 *
 *	TracePoint.trace(:line) do |tp|
 *	    p tp.raised_exception
 *	end
 *	#=> RuntimeError: 'raised_exception' not supported by this event
 *
 * If the trace method is called outside block, a RuntimeError is raised.
 *
 *      TracePoint.trace(:line) do |tp|
 *        $tp = tp
 *      end
 *      $tp.line #=> access from outside (RuntimeError)
 *
 * Access from other threads is also forbidden.
 *
 */
static VALUE
tracepoint_new_s(int argc, VALUE *argv, VALUE self)
{
    rb_event_flag_t events = 0;
    int i;

    if (argc > 0) {
	for (i=0; i<argc; i++) {
	    events |= symbol2event_flag(argv[i]);
	}
    }
    else {
	events = RUBY_EVENT_TRACEPOINT_ALL;
    }

    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }

    return tracepoint_new(self, 0, events, 0, 0, rb_block_proc());
}

static VALUE
tracepoint_trace_s(int argc, VALUE *argv, VALUE self)
{
    VALUE trace = tracepoint_new_s(argc, argv, self);
    rb_tracepoint_enable(trace);
    return trace;
}

/*
 *  call-seq:
 *    trace.inspect  -> string
 *
 *  Return a string containing a human-readable TracePoint
 *  status.
 */

static VALUE
tracepoint_inspect(VALUE self)
{
    rb_tp_t *tp = tpptr(self);
    rb_trace_arg_t *trace_arg = GET_THREAD()->trace_arg;

    if (trace_arg) {
	switch (trace_arg->event) {
	  case RUBY_EVENT_LINE:
	  case RUBY_EVENT_SPECIFIED_LINE:
	    {
		VALUE sym = rb_tracearg_method_id(trace_arg);
		if (NIL_P(sym))
		    goto default_inspect;
		return rb_sprintf("#<TracePoint:%"PRIsVALUE"@%"PRIsVALUE":%d in `%"PRIsVALUE"'>",
				  rb_tracearg_event(trace_arg),
				  rb_tracearg_path(trace_arg),
				  FIX2INT(rb_tracearg_lineno(trace_arg)),
				  sym);
	    }
	  case RUBY_EVENT_CALL:
	  case RUBY_EVENT_C_CALL:
	  case RUBY_EVENT_RETURN:
	  case RUBY_EVENT_C_RETURN:
	    return rb_sprintf("#<TracePoint:%"PRIsVALUE" `%"PRIsVALUE"'@%"PRIsVALUE":%d>",
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
	  default_inspect:
	    return rb_sprintf("#<TracePoint:%"PRIsVALUE"@%"PRIsVALUE":%d>",
			      rb_tracearg_event(trace_arg),
			      rb_tracearg_path(trace_arg),
			      FIX2INT(rb_tracearg_lineno(trace_arg)));
	}
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

/*
 * call-seq:
 *	TracePoint.stat -> obj
 *
 *  Returns internal information of TracePoint.
 *
 *  The contents of the returned value are implementation specific.
 *  It may be changed in future.
 *
 *  This method is only for debugging TracePoint itself.
 */

static VALUE
tracepoint_stat_s(VALUE self)
{
    rb_vm_t *vm = GET_VM();
    VALUE stat = rb_hash_new();

    tracepoint_stat_event_hooks(stat, vm->self, vm->event_hooks.hooks);
    /* TODO: thread local hooks */

    return stat;
}

static void Init_postponed_job(void);

/* This function is called from inits.c */
void
Init_vm_trace(void)
{
    /* trace_func */
    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_define_method(rb_cThread, "set_trace_func", thread_set_trace_func_m, 1);
    rb_define_method(rb_cThread, "add_trace_func", thread_add_trace_func_m, 1);

    /*
     * Document-class: TracePoint
     *
     * A class that provides the functionality of Kernel#set_trace_func in a
     * nice Object-Oriented API.
     *
     * == Example
     *
     * We can use TracePoint to gather information specifically for exceptions:
     *
     *	    trace = TracePoint.new(:raise) do |tp|
     *		p [tp.lineno, tp.event, tp.raised_exception]
     *	    end
     *	    #=> #<TracePoint:disabled>
     *
     *	    trace.enable
     *	    #=> false
     *
     *	    0 / 0
     *	    #=> [5, :raise, #<ZeroDivisionError: divided by 0>]
     *
     * == Events
     *
     * If you don't specify the type of events you want to listen for,
     * TracePoint will include all available events.
     *
     * *Note* do not depend on current event set, as this list is subject to
     * change. Instead, it is recommended you specify the type of events you
     * want to use.
     *
     * To filter what is traced, you can pass any of the following as +events+:
     *
     * +:line+:: execute code on a new line
     * +:class+:: start a class or module definition
     * +:end+:: finish a class or module definition
     * +:call+:: call a Ruby method
     * +:return+:: return from a Ruby method
     * +:c_call+:: call a C-language routine
     * +:c_return+:: return from a C-language routine
     * +:raise+:: raise an exception
     * +:b_call+:: event hook at block entry
     * +:b_return+:: event hook at block ending
     * +:thread_begin+:: event hook at thread beginning
     * +:thread_end+:: event hook at thread ending
     * +:fiber_switch+:: event hook at fiber switch
     *
     */
    rb_cTracePoint = rb_define_class("TracePoint", rb_cObject);
    rb_undef_alloc_func(rb_cTracePoint);
    rb_define_singleton_method(rb_cTracePoint, "new", tracepoint_new_s, -1);
    /*
     * Document-method: trace
     *
     * call-seq:
     *	TracePoint.trace(*events) { |obj| block }	-> obj
     *
     *  A convenience method for TracePoint.new, that activates the trace
     *  automatically.
     *
     *	    trace = TracePoint.trace(:call) { |tp| [tp.lineno, tp.event] }
     *	    #=> #<TracePoint:enabled>
     *
     *	    trace.enabled? #=> true
     */
    rb_define_singleton_method(rb_cTracePoint, "trace", tracepoint_trace_s, -1);

    rb_define_method(rb_cTracePoint, "enable", tracepoint_enable_m, 0);
    rb_define_method(rb_cTracePoint, "disable", tracepoint_disable_m, 0);
    rb_define_method(rb_cTracePoint, "enabled?", rb_tracepoint_enabled_p, 0);

    rb_define_method(rb_cTracePoint, "inspect", tracepoint_inspect, 0);

    rb_define_method(rb_cTracePoint, "event", tracepoint_attr_event, 0);
    rb_define_method(rb_cTracePoint, "lineno", tracepoint_attr_lineno, 0);
    rb_define_method(rb_cTracePoint, "path", tracepoint_attr_path, 0);
    rb_define_method(rb_cTracePoint, "method_id", tracepoint_attr_method_id, 0);
    rb_define_method(rb_cTracePoint, "defined_class", tracepoint_attr_defined_class, 0);
    rb_define_method(rb_cTracePoint, "binding", tracepoint_attr_binding, 0);
    rb_define_method(rb_cTracePoint, "self", tracepoint_attr_self, 0);
    rb_define_method(rb_cTracePoint, "return_value", tracepoint_attr_return_value, 0);
    rb_define_method(rb_cTracePoint, "raised_exception", tracepoint_attr_raised_exception, 0);

    rb_define_singleton_method(rb_cTracePoint, "stat", tracepoint_stat_s, 0);

    /* initialized for postponed job */

    Init_postponed_job();
}

typedef struct rb_postponed_job_struct {
    unsigned long flags; /* reserved */
    struct rb_thread_struct *th; /* created thread, reserved */
    rb_postponed_job_func_t func;
    void *data;
} rb_postponed_job_t;

#define MAX_POSTPONED_JOB                  1000
#define MAX_POSTPONED_JOB_SPECIAL_ADDITION   24

static void
Init_postponed_job(void)
{
    rb_vm_t *vm = GET_VM();
    vm->postponed_job_buffer = ALLOC_N(rb_postponed_job_t, MAX_POSTPONED_JOB);
    vm->postponed_job_index = 0;
}

enum postponed_job_register_result {
    PJRR_SUCESS      = 0,
    PJRR_FULL        = 1,
    PJRR_INTERRUPTED = 2
};

static enum postponed_job_register_result
postponed_job_register(rb_thread_t *th, rb_vm_t *vm,
		       unsigned int flags, rb_postponed_job_func_t func, void *data, int max, int expected_index)
{
    rb_postponed_job_t *pjob;

    if (expected_index >= max) return PJRR_FULL; /* failed */

    if (ATOMIC_CAS(vm->postponed_job_index, expected_index, expected_index+1) == expected_index) {
	pjob = &vm->postponed_job_buffer[expected_index];
    }
    else {
	return PJRR_INTERRUPTED;
    }

    pjob->flags = flags;
    pjob->th = th;
    pjob->func = func;
    pjob->data = data;

    RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(th);

    return PJRR_SUCESS;
}


/* return 0 if job buffer is full */
int
rb_postponed_job_register(unsigned int flags, rb_postponed_job_func_t func, void *data)
{
    rb_thread_t *th = GET_THREAD();
    rb_vm_t *vm = th->vm;

  begin:
    switch (postponed_job_register(th, vm, flags, func, data, MAX_POSTPONED_JOB, vm->postponed_job_index)) {
      case PJRR_SUCESS     : return 1;
      case PJRR_FULL       : return 0;
      case PJRR_INTERRUPTED: goto begin;
      default: rb_bug("unreachable\n");
    }
}

/* return 0 if job buffer is full */
int
rb_postponed_job_register_one(unsigned int flags, rb_postponed_job_func_t func, void *data)
{
    rb_thread_t *th = GET_THREAD();
    rb_vm_t *vm = th->vm;
    rb_postponed_job_t *pjob;
    int i, index;

  begin:
    index = vm->postponed_job_index;
    for (i=0; i<index; i++) {
	pjob = &vm->postponed_job_buffer[i];
	if (pjob->func == func) {
	    RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(th);
	    return 2;
	}
    }
    switch (postponed_job_register(th, vm, flags, func, data, MAX_POSTPONED_JOB + MAX_POSTPONED_JOB_SPECIAL_ADDITION, index)) {
      case PJRR_SUCESS     : return 1;
      case PJRR_FULL       : return 0;
      case PJRR_INTERRUPTED: goto begin;
      default: rb_bug("unreachable\n");
    }
}

void
rb_postponed_job_flush(rb_vm_t *vm)
{
    rb_thread_t *th = GET_THREAD();
    const unsigned long block_mask = POSTPONED_JOB_INTERRUPT_MASK|TRAP_INTERRUPT_MASK;
    unsigned long saved_mask = th->interrupt_mask & block_mask;
    VALUE saved_errno = th->errinfo;

    th->errinfo = Qnil;
    /* mask POSTPONED_JOB dispatch */
    th->interrupt_mask |= block_mask;
    {
	TH_PUSH_TAG(th);
	EXEC_TAG();
	{
	    int index;
	    while ((index = vm->postponed_job_index) > 0) {
		if (ATOMIC_CAS(vm->postponed_job_index, index, index-1) == index) {
		    rb_postponed_job_t *pjob = &vm->postponed_job_buffer[index-1];
		    (*pjob->func)(pjob->data);
		}
	    }
	}
	TH_POP_TAG();
    }
    /* restore POSTPONED_JOB mask */
    th->interrupt_mask &= ~(saved_mask ^ block_mask);
    th->errinfo = saved_errno;
}
