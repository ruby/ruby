/**********************************************************************

  vm_trace.c -

  $Author: ko1 $
  created at: Tue Aug 14 19:37:09 2012

  Copyright (C) 1993-2012 Yukihiro Matsumoto

**********************************************************************/

/*
 * This file incldue two parts:
 *
 * (1) set_trace_func internal mechanisms
 *     and C level API
 *
 * (2) Ruby level API
 *  (2-1) set_trace_func API
 *  (2-2) TracePoint API (not yet)
 *
 */

#include "ruby/ruby.h"
#include "ruby/encoding.h"

#include "internal.h"
#include "vm_core.h"
#include "eval_intern.h"

/* (1) trace mechanisms */

typedef enum {
    RUBY_HOOK_FLAG_SAFE    = 0x01,
    RUBY_HOOK_FLAG_DELETED = 0x02,
    RUBY_HOOK_FLAG_RAW_ARG = 0x04
} rb_hook_flag_t;

typedef struct rb_event_hook_struct {
    rb_hook_flag_t hook_flags;
    rb_event_flag_t events;
    rb_event_hook_func_t func;
    VALUE data;
    struct rb_event_hook_struct *next;
} rb_event_hook_t;

typedef struct rb_trace_arg_struct {
    rb_event_flag_t event;
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    VALUE self;
    ID id;
    VALUE klass;
} rb_trace_arg_t;

typedef void (*rb_event_hook_raw_arg_func_t)(VALUE data, const rb_trace_arg_t *arg);

#define MAX_EVENT_NUM 32

static int ruby_event_flag_count[MAX_EVENT_NUM] = {0};

/* Safe API.  Callback will be called under PUSH_TAG() */
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);
int rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data);
void rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func);
int rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data);

/* advanced version */
void rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flag);
void rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flag);

/* called from vm.c */

void
vm_trace_mark_event_hooks(rb_hook_list_t *hooks)
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
	if (events & (1 << i)) {
	    ruby_event_flag_count[i]++;
	}
	ruby_vm_event_flags |= ruby_event_flag_count[i] ? (1<<i) : 0;
    }
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
alloc_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = ALLOC(rb_event_hook_t);
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
rb_threadptr_add_event_hook(rb_thread_t *th, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flags)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, hook_flags);
    connect_event_hook(&th->event_hooks, hook);
}

void
rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data, RUBY_HOOK_FLAG_SAFE);
}

void
rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, RUBY_HOOK_FLAG_SAFE);
    connect_event_hook(&GET_VM()->event_hooks, hook);
}

void
rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flags)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data, hook_flags);
}

void
rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_hook_flag_t hook_flags)
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
		hook->hook_flags |= RUBY_HOOK_FLAG_DELETED;
		ret+=1;
		list->need_clean++;
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

static int
clear_trace_func_i(st_data_t key, st_data_t val, st_data_t flag)
{
    rb_thread_t *th;
    GetThreadPtr((VALUE)key, th);
    rb_threadptr_remove_event_hook(th, 0, Qundef);
    return ST_CONTINUE;
}

void
rb_clear_trace_func(void)
{
    st_foreach(GET_VM()->living_threads, clear_trace_func_i, (st_data_t) 0);
    rb_remove_event_hook(0);
}

/* invoke hooks */

static void
clean_hooks(rb_hook_list_t *list)
{
    rb_event_hook_t *hook, **nextp = &list->hooks;

    list->events = 0;
    list->need_clean = 0;

    while ((hook = *nextp) != 0) {
	if (hook->hook_flags & RUBY_HOOK_FLAG_DELETED) {
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

static int
exec_hooks(rb_thread_t *th, rb_hook_list_t *list, const rb_trace_arg_t *trace_arg, int can_clean_hooks)
{
    int state;
    volatile int raised;

    if (UNLIKELY(list->need_clean > 0) && can_clean_hooks) {
	clean_hooks(list);
    }

    raised = rb_threadptr_reset_raised(th);

    /* TODO: Support !RUBY_HOOK_FLAG_SAFE hooks */

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	rb_event_hook_t *hook;

	for (hook = list->hooks; hook; hook = hook->next) {
	    if (LIKELY(!(hook->hook_flags & RUBY_HOOK_FLAG_DELETED)) && (trace_arg->event & hook->events)) {
		if (!(hook->hook_flags & RUBY_HOOK_FLAG_RAW_ARG)) {
		    (*hook->func)(trace_arg->event, hook->data, trace_arg->self, trace_arg->id, trace_arg->klass);
		}
		else {
		    (*((rb_event_hook_raw_arg_func_t)hook->func))(hook->data, trace_arg);
		}
	    }
	}
    }
    TH_POP_TAG();

    if (raised) {
	rb_threadptr_set_raised(th);
    }

    return state;
}

void
rb_threadptr_exec_event_hooks(rb_thread_t *th, rb_event_flag_t event, VALUE self, ID id, VALUE klass)
{
    if (th->trace_running == 0 &&
	self != rb_mRubyVMFrozenCore /* skip special methods. TODO: remove it. */) {
	const int vm_tracing = th->vm->trace_running;
	int state = 0;
	int outer_state = th->state;
	th->state = 0;

	th->vm->trace_running = 1;
	th->trace_running = 1;
	{
	    const VALUE errinfo = th->errinfo;
	    rb_hook_list_t *list;
	    rb_trace_arg_t ta;

	    ta.event = event;
	    ta.th = th;
	    ta.cfp = th->cfp;
	    ta.self = self;
	    ta.id = id;
	    ta.klass = klass;

	    /* thread local traces */
	    list = &th->event_hooks;
	    if (list->events & event) {
		state = exec_hooks(th, list, &ta, TRUE);
		if (state) goto terminate;
	    }

	    /* vm global traces */
	    list = &th->vm->event_hooks;
	    if (list->events & event) {
		state = exec_hooks(th, list, &ta, !vm_tracing);
		if (state) goto terminate;
	    }
	    th->errinfo = errinfo;
	}
      terminate:
	th->trace_running = 0;
	th->vm->trace_running = vm_tracing;

	if (state) {
	    TH_JUMP_TAG(th, state);
	}
	th->state = outer_state;
    }
}

VALUE
rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg)
{
    volatile int raised;
    volatile int outer_state;
    VALUE result = Qnil;
    rb_thread_t *th = GET_THREAD();
    int state;
    const int vm_tracing = th->vm->trace_running;
    const int tracing = th->trace_running;

    th->vm->trace_running = 1;
    th->trace_running = 1;
    raised = rb_threadptr_reset_raised(th);
    outer_state = th->state;
    th->state = 0;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	result = (*func)(arg);
    }
    POP_TAG();

    if (raised) {
	rb_threadptr_set_raised(th);
    }
    th->trace_running = tracing;
    th->vm->trace_running = vm_tracing;

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
 *  tracing if the parameter is +nil+. _proc_ takes up
 *  to six parameters: an event name, a filename, a line number, an
 *  object id, a binding, and the name of a class. _proc_ is
 *  invoked whenever an event occurs. Events are: <code>c-call</code>
 *  (call a C-language routine), <code>c-return</code> (return from a
 *  C-language routine), <code>call</code> (call a Ruby method),
 *  <code>class</code> (start a class or module definition),
 *  <code>end</code> (finish a class or module definition),
 *  <code>line</code> (execute code on a new line), <code>raise</code>
 *  (raise an exception), and <code>return</code> (return from a Ruby
 *  method). Tracing is disabled within the context of _proc_.
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

    rb_threadptr_add_event_hook(th, call_trace_func, RUBY_EVENT_ALL, trace, RUBY_HOOK_FLAG_SAFE);
}

/*
 *  call-seq:
 *     thr.add_trace_func(proc)    -> proc
 *
 *  Adds _proc_ as a handler for tracing.
 *  See <code>Thread#set_trace_func</code> and +set_trace_func+.
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
 *  See +set_trace_func+.
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
#undef C
      default:
	return 0;
    }
}

static void
call_trace_func(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
    const char *srcfile = rb_sourcefile();
    VALUE eventname = rb_str_new2(get_event_name(event));
    VALUE filename = srcfile ? rb_str_new2(srcfile) : Qnil;
    VALUE argv[6];
    int line = rb_sourceline();
    rb_thread_t *th = GET_THREAD();

    if (!klass) {
	rb_thread_method_id_and_class(th, &id, &klass);
    }

    if (klass) {
	if (RB_TYPE_P(klass, T_ICLASS)) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = rb_iv_get(klass, "__attached__");
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
    rb_thread_t *target_th;
    VALUE proc;
    rb_trace_arg_t *trace_arg;
    int tracing;
} rb_tp_t;

static void
tp_mark(void *ptr)
{
    if (ptr) {
	rb_tp_t *tp = (rb_tp_t *)ptr;
	rb_gc_mark(tp->proc);
	if (tp->target_th) rb_gc_mark(tp->target_th->self);
    }
}

static void
tp_free(void *ptr)
{
    /* do nothing */
}

static size_t
tp_memsize(const void *ptr)
{
    return sizeof(rb_tp_t);
}

static const rb_data_type_t tp_data_type = {
    "tracepoint",
    {tp_mark, tp_free, tp_memsize,},
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
    static ID id;
    VALUE sym = rb_convert_type(v, T_SYMBOL, "Symbol", "to_sym");

#define C(name, NAME) CONST_ID(id, #name); if (sym == ID2SYM(id)) return RUBY_EVENT_##NAME
    C(line, LINE);
    C(class, CLASS);
    C(end, END);
    C(call, CALL);
    C(return, RETURN);
    C(c_call, C_CALL);
    C(c_return, C_RETURN);
    C(raise, RAISE);
#undef C
    rb_raise(rb_eArgError, "unknown event: %s", rb_id2name(SYM2ID(sym)));
}

static rb_tp_t *
tpptr(VALUE tpval)
{
    rb_tp_t *tp;
    TypedData_Get_Struct(tpval, rb_tp_t, &tp_data_type, tp);
    return tp;
}

static void
tp_attr_check_active(rb_tp_t *tp)
{
    if (tp->trace_arg == 0) {
	rb_raise(rb_eRuntimeError, "access from outside");
    }
}

static VALUE
tp_attr_event_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    tp_attr_check_active(tp);
    return ID2SYM(get_event_id(tp->trace_arg->event));
}

rb_control_frame_t *rb_vm_get_ruby_level_next_cfp(rb_thread_t *th, rb_control_frame_t *cfp);
int rb_vm_control_frame_id_and_class(rb_control_frame_t *cfp, ID *idp, VALUE *klassp);
VALUE rb_binding_new_with_cfp(rb_thread_t *th, rb_control_frame_t *src_cfp);

static VALUE
tp_attr_line_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    rb_control_frame_t *cfp;
    tp_attr_check_active(tp);

    cfp = rb_vm_get_ruby_level_next_cfp(tp->trace_arg->th, tp->trace_arg->cfp);
    if (cfp) {
	return INT2FIX(rb_vm_get_sourceline(cfp));
    }
    else {
	return INT2FIX(0);
    }
}

static VALUE
tp_attr_file_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    rb_control_frame_t *cfp;
    tp_attr_check_active(tp);

    cfp = rb_vm_get_ruby_level_next_cfp(tp->trace_arg->th, tp->trace_arg->cfp);
    if (cfp) {
	return cfp->iseq->location.path;
    }
    else {
	return Qnil;
    }
}

static void
fill_id_and_klass(rb_trace_arg_t *trace_arg)
{
    if (!trace_arg->klass)
      rb_vm_control_frame_id_and_class(trace_arg->cfp, &trace_arg->id, &trace_arg->klass);

    if (trace_arg->klass) {
	if (RB_TYPE_P(trace_arg->klass, T_ICLASS)) {
	    trace_arg->klass = RBASIC(trace_arg->klass)->klass;
	}
	else if (FL_TEST(trace_arg->klass, FL_SINGLETON)) {
	    trace_arg->klass = rb_iv_get(trace_arg->klass, "__attached__");
	}
    }
}

static VALUE
tp_attr_id_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    tp_attr_check_active(tp);
    fill_id_and_klass(tp->trace_arg);
    if (tp->trace_arg->id) {
	return ID2SYM(tp->trace_arg->id);
    }
    else {
	return Qnil;
    }
}

static VALUE
tp_attr_klass_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    tp_attr_check_active(tp);
    fill_id_and_klass(tp->trace_arg);

    if (tp->trace_arg->klass) {
	return tp->trace_arg->klass;
    }
    else {
	return Qnil;
    }
}

static VALUE
tp_attr_binding_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    rb_control_frame_t *cfp;
    tp_attr_check_active(tp);

    cfp = rb_vm_get_ruby_level_next_cfp(tp->trace_arg->th, tp->trace_arg->cfp);
    if (cfp) {
	return rb_binding_new_with_cfp(tp->trace_arg->th, cfp);
    }
    else {
	return Qnil;
    }
}

static VALUE
tp_attr_self_m(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);
    tp_attr_check_active(tp);

    return tp->trace_arg->self;
}

static void
tp_call_trace(VALUE tpval, rb_trace_arg_t *trace_arg)
{
    rb_tp_t *tp = tpptr(tpval);
    rb_thread_t *th = GET_THREAD();
    int state;

    tp->trace_arg = trace_arg;

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	rb_proc_call_with_block(tp->proc, 1, &tpval, Qnil);
    }
    TH_POP_TAG();

    tp->trace_arg = 0;

    if (state) {
	TH_JUMP_TAG(th, state);
    }
}

static VALUE
tp_set_trace(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);

    if (tp->tracing) {
	/* already tracing */
	/* TODO: raise error? */
    }
    else {
	if (tp->target_th) {
	    rb_thread_add_event_hook2(tp->target_th->self, (rb_event_hook_func_t)tp_call_trace, tp->events, tpval, RUBY_HOOK_FLAG_SAFE | RUBY_HOOK_FLAG_RAW_ARG);
	}
	else {
	    rb_add_event_hook2((rb_event_hook_func_t)tp_call_trace, tp->events, tpval, RUBY_HOOK_FLAG_SAFE | RUBY_HOOK_FLAG_RAW_ARG);
	}
	tp->tracing = 1;
    }

    return tpval;
}

static VALUE
tp_unset_trace(VALUE tpval)
{
    rb_tp_t *tp = tpptr(tpval);

    if (!tp->tracing) {
	/* not tracing */
	/* TODO: raise error? */
    }
    else {
	if (tp->target_th) {
	    rb_thread_remove_event_hook_with_data(tp->target_th->self, (rb_event_hook_func_t)tp_call_trace, tpval);
	}
	else {
	    rb_remove_event_hook_with_data((rb_event_hook_func_t)tp_call_trace, tpval);
	}
	tp->tracing = 0;
    }

    return tpval;
}

static VALUE
tp_initialize(rb_thread_t *target_th, rb_event_flag_t events, VALUE proc)
{
    VALUE tpval = tp_alloc(rb_cTracePoint);
    rb_tp_t *tp;
    TypedData_Get_Struct(tpval, rb_tp_t, &tp_data_type, tp);

    tp->proc = proc;
    tp->events = events;

    tp_set_trace(tpval);

    return tpval;
}

static VALUE
tp_trace_s(int argc, VALUE *argv)
{
    rb_event_flag_t events = 0;
    int i;

    if (argc > 0) {
	for (i=0; i<argc; i++) {
	    events |= symbol2event_flag(argv[i]);
	}
    }
    else {
	events = RUBY_EVENT_ALL;
    }

    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }

    return tp_initialize(0, events, rb_block_proc());
}

/* This function is called from inits.c */
void
Init_vm_trace(void)
{
    /* trace_func */
    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_define_method(rb_cThread, "set_trace_func", thread_set_trace_func_m, 1);
    rb_define_method(rb_cThread, "add_trace_func", thread_add_trace_func_m, 1);

    /* TracePoint */
    rb_cTracePoint = rb_define_class("TracePoint", rb_cObject);
    rb_undef_alloc_func(rb_cTracePoint);
    rb_undef_method(CLASS_OF(rb_cTracePoint), "new");
    rb_define_singleton_method(rb_cTracePoint, "trace", tp_trace_s, -1);

    rb_define_method(rb_cTracePoint, "retrace", tp_set_trace, 0);
    rb_define_method(rb_cTracePoint, "untrace", tp_unset_trace, 0);

    rb_define_method(rb_cTracePoint, "event", tp_attr_event_m, 0);
    rb_define_method(rb_cTracePoint, "line", tp_attr_line_m, 0);
    rb_define_method(rb_cTracePoint, "file", tp_attr_file_m, 0);
    rb_define_method(rb_cTracePoint, "id", tp_attr_id_m, 0);
    rb_define_method(rb_cTracePoint, "klass", tp_attr_klass_m, 0);
    rb_define_method(rb_cTracePoint, "binding", tp_attr_binding_m, 0);
    rb_define_method(rb_cTracePoint, "self", tp_attr_self_m, 0);
}
