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
} rb_hook_flag_t;

typedef struct rb_event_hook_struct {
    rb_hook_flag_t hook_flags;
    rb_event_flag_t events;
    rb_event_hook_func_t func;
    VALUE data;
    struct rb_event_hook_struct *next;
} rb_event_hook_t;

#define MAX_EVENT_NUM 32

static int ruby_event_flag_count[MAX_EVENT_NUM] = {0};

/* Safe API.  Callback will be called under PUSH_TAG() */
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);
void rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func);

/* Raw API.  Callback will be called without PUSH_TAG() */
void rb_add_raw_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_raw_event_hook(rb_event_hook_func_t func);
void rb_thread_add_raw_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_thread_remove_raw_event_hook(VALUE thval, rb_event_hook_func_t func);

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
rb_thread_add_raw_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data, 0);
}

void
rb_add_raw_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data, 0);
    connect_event_hook(&GET_VM()->event_hooks, hook);
}

/* if func is 0, then clear all funcs */
static int
remove_event_hook_by_func(rb_hook_list_t *list, rb_event_hook_func_t func)
{
    int ret = 0;
    rb_event_hook_t *hook = list->hooks;

    while (hook) {
	if (func == 0 || hook->func == func) {
	    hook->hook_flags |= RUBY_HOOK_FLAG_DELETED;
	    ret+=1;
	    list->need_clean++;
	}
	hook = hook->next;
    }

    return ret;
}

static int
rb_threadptr_remove_event_hook(rb_thread_t *th, rb_event_hook_func_t func)
{
    return remove_event_hook_by_func(&th->event_hooks, func);
}

int
rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func)
{
    return rb_threadptr_remove_event_hook(thval2thread_t(thval), func);
}

int
rb_remove_event_hook(rb_event_hook_func_t func)
{
    return remove_event_hook_by_func(&GET_VM()->event_hooks, func);
}

static int
clear_trace_func_i(st_data_t key, st_data_t val, st_data_t flag)
{
    rb_thread_t *th;
    GetThreadPtr((VALUE)key, th);
    rb_threadptr_remove_event_hook(th, 0);
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
    rb_event_hook_t *hook = list->hooks, *prev = 0;

    list->events = 0;
    list->need_clean = 0;

    while (hook) {
	if (hook->hook_flags & RUBY_HOOK_FLAG_DELETED) {
	    if (prev == 0) {
		/* start of list */
		list->hooks = hook->next;
	    }
	    else {
		prev->next = hook->next;
	    }

	    recalc_remove_ruby_vm_event_flags(hook->events);
	    xfree(hook);
	    goto next_iter;
	}
	else {
	    list->events |= hook->events; /* update active events */
	}
	prev = hook;
      next_iter:
	hook = hook->next;
    }
}

static inline int
exec_hooks(rb_thread_t *th, rb_hook_list_t *list, rb_event_flag_t event, VALUE self, ID id, VALUE klass)
{
    rb_event_hook_t *hook;
    int state;
    volatile int raised;

    if (UNLIKELY(list->need_clean > 0)) {
	clean_hooks(list);
    }

    raised = rb_threadptr_reset_raised(th);

    hook = list->hooks;

    /* TODO: Support !RUBY_HOOK_FLAG_SAFE hooks */

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	while (hook) {
	    if (LIKELY(!(hook->hook_flags & RUBY_HOOK_FLAG_DELETED)) && (event & hook->events)) {
		(*hook->func)(event, hook->data, self, id, klass);
	    }
	    hook = hook->next;
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
	int state;
	int outer_state = th->state;
	th->state = 0;

	th->trace_running = 1;
	{
	    const VALUE errinfo = th->errinfo;
	    rb_hook_list_t *list;

	    /* thread local traces */
	    list = &th->event_hooks;
	    if (list->events & event) {
		state = exec_hooks(th, list, event, self, id, klass);
		if (state) goto terminate;
	    }

	    /* vm global traces */
	    list = &th->vm->event_hooks;
	    if (list->events & event) {
		state = exec_hooks(th, list, event, self, id, klass);
		if (state) goto terminate;
	    }
	    th->errinfo = errinfo;
	}
      terminate:
	th->trace_running = 0;

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
    int tracing = th->trace_running;

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
    rb_threadptr_remove_event_hook(th, call_trace_func);

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
      default:
	return "unknown";
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

    if (klass != 0) {
	id = id;
	klass = klass;
    }
    else {
	rb_thread_method_id_and_class(th, &id, &klass);
    }

    if (id == ID_ALLOCATOR)
      return;

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

/* (2-2) TracePoint API (not yet) */


/* This function is called from inits.c */
void
Init_vm_trace(void)
{
    /* trace */
    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_define_method(rb_cThread, "set_trace_func", thread_set_trace_func_m, 1);
    rb_define_method(rb_cThread, "add_trace_func", thread_add_trace_func_m, 1);
}

