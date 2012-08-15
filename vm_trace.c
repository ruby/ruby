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

#define RUBY_EVENT_REMOVED 0x1000000

enum {
    EVENT_RUNNING_NOTHING,
    EVENT_RUNNING_TRACE = 1,
    EVENT_RUNNING_THREAD = 2,
    EVENT_RUNNING_VM = 4,
    EVENT_RUNNING_EVENT_MASK = EVENT_RUNNING_VM|EVENT_RUNNING_THREAD
};

static VALUE thread_suppress_tracing(rb_thread_t *th, int ev, VALUE (*func)(VALUE, int), VALUE arg, int always);

struct event_call_args {
    rb_thread_t *th;
    VALUE klass;
    VALUE self;
    VALUE proc;
    ID id;
    rb_event_flag_t event;
};

static rb_event_hook_t *
alloc_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = ALLOC(rb_event_hook_t);
    hook->func = func;
    hook->flag = events;
    hook->data = data;
    return hook;
}

static void
thread_reset_event_flags(rb_thread_t *th)
{
    rb_event_hook_t *hook = th->event_hooks;
    rb_event_flag_t flag = th->event_flags & RUBY_EVENT_VM;

    while (hook) {
	if (!(flag & RUBY_EVENT_REMOVED))
	    flag |= hook->flag;
	hook = hook->next;
    }
    th->event_flags = flag;
}

static void
rb_threadptr_add_event_hook(rb_thread_t *th,
			 rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data);
    hook->next = th->event_hooks;
    th->event_hooks = hook;
    thread_reset_event_flags(th);
}

static rb_thread_t *
thval2thread_t(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    return th;
}

void
rb_thread_add_event_hook(VALUE thval,
			 rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_threadptr_add_event_hook(thval2thread_t(thval), func, events, data);
}

static int
set_threads_event_flags_i(st_data_t key, st_data_t val, st_data_t flag)
{
    VALUE thval = key;
    rb_thread_t *th;
    GetThreadPtr(thval, th);

    if (flag) {
	th->event_flags |= RUBY_EVENT_VM;
    }
    else {
	th->event_flags &= (~RUBY_EVENT_VM);
    }
    return ST_CONTINUE;
}

static void
set_threads_event_flags(int flag)
{
    st_foreach(GET_VM()->living_threads, set_threads_event_flags_i, (st_data_t) flag);
}

static inline int
exec_event_hooks(const rb_event_hook_t *hook, rb_event_flag_t flag, VALUE self, ID id, VALUE klass)
{
    int removed = 0;
    for (; hook; hook = hook->next) {
	if (hook->flag & RUBY_EVENT_REMOVED) {
	    removed++;
	    continue;
	}
	if (flag & hook->flag) {
	    (*hook->func)(flag, hook->data, self, id, klass);
	}
    }
    return removed;
}

static int remove_defered_event_hook(rb_event_hook_t **root);

static VALUE
thread_exec_event_hooks(VALUE args, int running)
{
    struct event_call_args *argp = (struct event_call_args *)args;
    rb_thread_t *th = argp->th;
    rb_event_flag_t flag = argp->event;
    VALUE self = argp->self;
    ID id = argp->id;
    VALUE klass = argp->klass;
    const rb_event_flag_t wait_event = th->event_flags;
    int removed;

    if (self == rb_mRubyVMFrozenCore) return 0;

    if ((wait_event & flag) && !(running & EVENT_RUNNING_THREAD)) {
	th->tracing |= EVENT_RUNNING_THREAD;
	removed = exec_event_hooks(th->event_hooks, flag, self, id, klass);
	th->tracing &= ~EVENT_RUNNING_THREAD;
	if (removed) {
	    remove_defered_event_hook(&th->event_hooks);
	}
    }
    if (wait_event & RUBY_EVENT_VM) {
	if (th->vm->event_hooks == NULL) {
	    th->event_flags &= (~RUBY_EVENT_VM);
	}
	else if (!(running & EVENT_RUNNING_VM)) {
	    th->tracing |= EVENT_RUNNING_VM;
	    removed = exec_event_hooks(th->vm->event_hooks, flag, self, id, klass);
	    th->tracing &= ~EVENT_RUNNING_VM;
	    if (removed) {
		remove_defered_event_hook(&th->vm->event_hooks);
	    }
	}
    }
    return 0;
}

void
rb_threadptr_exec_event_hooks(rb_thread_t *th, rb_event_flag_t flag, VALUE self, ID id, VALUE klass)
{
    const VALUE errinfo = th->errinfo;
    struct event_call_args args;
    args.th = th;
    args.event = flag;
    args.self = self;
    args.id = id;
    args.klass = klass;
    args.proc = 0;
    thread_suppress_tracing(th, EVENT_RUNNING_EVENT_MASK, thread_exec_event_hooks, (VALUE)&args, FALSE);
    th->errinfo = errinfo;
}

void
rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data)
{
    rb_event_hook_t *hook = alloc_event_hook(func, events, data);
    rb_vm_t *vm = GET_VM();

    hook->next = vm->event_hooks;
    vm->event_hooks = hook;

    set_threads_event_flags(1);
}

static int
defer_remove_event_hook(rb_event_hook_t *hook, rb_event_hook_func_t func)
{
    while (hook) {
	if (func == 0 || hook->func == func) {
	    hook->flag |= RUBY_EVENT_REMOVED;
	}
	hook = hook->next;
    }
    return -1;
}

static int
remove_event_hook(rb_event_hook_t **root, rb_event_hook_func_t func)
{
    rb_event_hook_t *hook = *root, *next;

    while (hook) {
	next = hook->next;
	if (func == 0 || hook->func == func || (hook->flag & RUBY_EVENT_REMOVED)) {
	    *root = next;
	    xfree(hook);
	}
	else {
	    root = &hook->next;
	}
	hook = next;
    }
    return -1;
}

static int
remove_defered_event_hook(rb_event_hook_t **root)
{
    rb_event_hook_t *hook = *root, *next;

    while (hook) {
	next = hook->next;
	if (hook->flag & RUBY_EVENT_REMOVED) {
	    *root = next;
	    xfree(hook);
	}
	else {
	    root = &hook->next;
	}
	hook = next;
    }
    return -1;
}

static int
rb_threadptr_remove_event_hook(rb_thread_t *th, rb_event_hook_func_t func)
{
    int ret;
    if (th->tracing & EVENT_RUNNING_THREAD) {
	ret = defer_remove_event_hook(th->event_hooks, func);
    }
    else {
	ret = remove_event_hook(&th->event_hooks, func);
    }
    thread_reset_event_flags(th);
    return ret;
}

int
rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func)
{
    return rb_threadptr_remove_event_hook(thval2thread_t(thval), func);
}

static rb_event_hook_t *
search_live_hook(rb_event_hook_t *hook)
{
    while (hook) {
	if (!(hook->flag & RUBY_EVENT_REMOVED))
	    return hook;
	hook = hook->next;
    }
    return NULL;
}

static int
running_vm_event_hooks(st_data_t key, st_data_t val, st_data_t data)
{
    rb_thread_t *th = thval2thread_t((VALUE)key);
    if (!(th->tracing & EVENT_RUNNING_VM)) return ST_CONTINUE;
    *(rb_thread_t **)data = th;
    return ST_STOP;
}

static rb_thread_t *
vm_event_hooks_running_thread(rb_vm_t *vm)
{
    rb_thread_t *found = NULL;
    st_foreach(vm->living_threads, running_vm_event_hooks, (st_data_t)&found);
    return found;
}

int
rb_remove_event_hook(rb_event_hook_func_t func)
{
    rb_vm_t *vm = GET_VM();
    rb_event_hook_t *hook = search_live_hook(vm->event_hooks);
    int ret;

    if (vm_event_hooks_running_thread(vm)) {
	ret = defer_remove_event_hook(vm->event_hooks, func);
    }
    else {
	ret = remove_event_hook(&vm->event_hooks, func);
    }

    if (hook && !search_live_hook(vm->event_hooks)) {
	set_threads_event_flags(0);
    }

    return ret;
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
	GET_THREAD()->tracing = EVENT_RUNNING_NOTHING;
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

    rb_threadptr_add_event_hook(th, call_trace_func, RUBY_EVENT_ALL, trace);
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
	th->tracing = EVENT_RUNNING_NOTHING;
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

static VALUE
call_trace_proc(VALUE args, int tracing)
{
    struct event_call_args *p = (struct event_call_args *)args;
    const char *srcfile = rb_sourcefile();
    VALUE eventname = rb_str_new2(get_event_name(p->event));
    VALUE filename = srcfile ? rb_str_new2(srcfile) : Qnil;
    VALUE argv[6];
    int line = rb_sourceline();
    ID id = 0;
    VALUE klass = 0;

    if (p->klass != 0) {
	id = p->id;
	klass = p->klass;
    }
    else {
	rb_thread_method_id_and_class(p->th, &id, &klass);
    }
    if (id == ID_ALLOCATOR)
      return Qnil;
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
    argv[4] = (p->self && srcfile) ? rb_binding_new() : Qnil;
    argv[5] = klass ? klass : Qnil;

    return rb_proc_call_with_block(p->proc, 6, argv, Qnil);
}

static void
call_trace_func(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
    struct event_call_args args;

    args.th = GET_THREAD();
    args.event = event;
    args.proc = proc;
    args.self = self;
    args.id = id;
    args.klass = klass;
    ruby_suppress_tracing(call_trace_proc, (VALUE)&args, FALSE);
}

VALUE
ruby_suppress_tracing(VALUE (*func)(VALUE, int), VALUE arg, int always)
{
    rb_thread_t *th = GET_THREAD();
    return thread_suppress_tracing(th, EVENT_RUNNING_TRACE, func, arg, always);
}

static VALUE
thread_suppress_tracing(rb_thread_t *th, int ev, VALUE (*func)(VALUE, int), VALUE arg, int always)
{
    int state, tracing = th->tracing, running = tracing & ev;
    volatile int raised;
    volatile int outer_state;
    VALUE result = Qnil;

    if (running == ev && !always) {
	return Qnil;
    }
    else {
	th->tracing |= ev;
    }

    raised = rb_threadptr_reset_raised(th);
    outer_state = th->state;
    th->state = 0;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	result = (*func)(arg, running);
    }

    if (raised) {
	rb_threadptr_set_raised(th);
    }
    POP_TAG();

    th->tracing = tracing;
    if (state) {
	JUMP_TAG(state);
    }
    th->state = outer_state;

    return result;
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

