/**********************************************************************

  thread.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

/*
  YARV Thread Design

  model 1: Userlevel Thread
    Same as traditional ruby thread.

  model 2: Native Thread with Global VM lock
    Using pthread (or Windows thread) and Ruby threads run concurrent.

  model 3: Native Thread with fine grain lock
    Using pthread and Ruby threads run concurrent or parallel.

------------------------------------------------------------------------

  model 2:
    A thread has mutex (GVL: Global VM Lock or Giant VM Lock) can run.
    When thread scheduling, running thread release GVL.  If running thread
    try blocking operation, this thread must release GVL and another
    thread can continue this flow.  After blocking operation, thread
    must check interrupt (RUBY_VM_CHECK_INTS).

    Every VM can run parallel.

    Ruby threads are scheduled by OS thread scheduler.

------------------------------------------------------------------------

  model 3:
    Every threads run concurrent or parallel and to access shared object
    exclusive access control is needed.  For example, to access String
    object or Array object, fine grain lock must be locked every time.
 */


/*
 * FD_SET, FD_CLR and FD_ISSET have a small sanity check when using glibc
 * 2.15 or later and set _FORTIFY_SOURCE > 0.
 * However, the implementation is wrong. Even though Linux's select(2)
 * supports large fd size (>FD_SETSIZE), it wrongly assumes fd is always
 * less than FD_SETSIZE (i.e. 1024). And then when enabling HAVE_RB_FD_INIT,
 * it doesn't work correctly and makes program abort. Therefore we need to
 * disable FORTIFY_SOURCE until glibc fixes it.
 */
#undef _FORTIFY_SOURCE
#undef __USE_FORTIFY_LEVEL
#define __USE_FORTIFY_LEVEL 0

/* for model 2 */

#include "eval_intern.h"
#include "gc.h"
#include "timev.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include "ruby/thread_native.h"
#include "internal.h"

#ifndef USE_NATIVE_THREAD_PRIORITY
#define USE_NATIVE_THREAD_PRIORITY 0
#define RUBY_THREAD_PRIORITY_MAX 3
#define RUBY_THREAD_PRIORITY_MIN -3
#endif

#ifndef THREAD_DEBUG
#define THREAD_DEBUG 0
#endif

static VALUE rb_cThreadShield;

static VALUE sym_immediate;
static VALUE sym_on_blocking;
static VALUE sym_never;
static ID id_locals;

static void sleep_timeval(rb_thread_t *th, struct timeval time, int spurious_check);
static void sleep_wait_for_interrupt(rb_thread_t *th, double sleepsec, int spurious_check);
static void sleep_forever(rb_thread_t *th, int nodeadlock, int spurious_check);
static void rb_thread_sleep_deadly_allow_spurious_wakeup(void);
static double timeofday(void);
static int rb_threadptr_dead(rb_thread_t *th);
static void rb_check_deadlock(rb_vm_t *vm);
static int rb_threadptr_pending_interrupt_empty_p(rb_thread_t *th);

#define eKillSignal INT2FIX(0)
#define eTerminateSignal INT2FIX(1)
static volatile int system_working = 1;

#define closed_stream_error GET_VM()->special_exceptions[ruby_error_closed_stream]

inline static void
st_delete_wrap(st_table *table, st_data_t key)
{
    st_delete(table, &key, 0);
}

/********************************************************************************/

#define THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

struct rb_blocking_region_buffer {
    enum rb_thread_status prev_status;
    struct rb_unblock_callback oldubf;
};

static int set_unblock_function(rb_thread_t *th, rb_unblock_function_t *func, void *arg,
				struct rb_unblock_callback *old, int fail_if_interrupted);
static void reset_unblock_function(rb_thread_t *th, const struct rb_unblock_callback *old);

static inline int blocking_region_begin(rb_thread_t *th, struct rb_blocking_region_buffer *region,
					rb_unblock_function_t *ubf, void *arg, int fail_if_interrupted);
static inline void blocking_region_end(rb_thread_t *th, struct rb_blocking_region_buffer *region);

#ifdef __ia64
#define RB_GC_SAVE_MACHINE_REGISTER_STACK(th)          \
    do{(th)->machine.register_stack_end = rb_ia64_bsp();}while(0)
#else
#define RB_GC_SAVE_MACHINE_REGISTER_STACK(th)
#endif
#define RB_GC_SAVE_MACHINE_CONTEXT(th)				\
    do {							\
	FLUSH_REGISTER_WINDOWS;					\
	RB_GC_SAVE_MACHINE_REGISTER_STACK(th);			\
	setjmp((th)->machine.regs);				\
	SET_MACHINE_STACK_END(&(th)->machine.stack_end);	\
    } while (0)

#define GVL_UNLOCK_BEGIN() do { \
  rb_thread_t *_th_stored = GET_THREAD(); \
  RB_GC_SAVE_MACHINE_CONTEXT(_th_stored); \
  gvl_release(_th_stored->vm);

#define GVL_UNLOCK_END() \
  gvl_acquire(_th_stored->vm, _th_stored); \
  rb_thread_set_current(_th_stored); \
} while(0)

#ifdef __GNUC__
#ifdef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
#define only_if_constant(expr, notconst) __builtin_choose_expr(__builtin_constant_p(expr), (expr), (notconst))
#else
#define only_if_constant(expr, notconst) (__builtin_constant_p(expr) ? (expr) : (notconst))
#endif
#else
#define only_if_constant(expr, notconst) notconst
#endif
#define BLOCKING_REGION(exec, ubf, ubfarg, fail_if_interrupted) do { \
    rb_thread_t *__th = GET_THREAD(); \
    struct rb_blocking_region_buffer __region; \
    if (blocking_region_begin(__th, &__region, (ubf), (ubfarg), fail_if_interrupted) || \
	/* always return true unless fail_if_interrupted */ \
	!only_if_constant(fail_if_interrupted, TRUE)) { \
	exec; \
	blocking_region_end(__th, &__region); \
    }; \
} while(0)

#define RUBY_VM_CHECK_INTS_BLOCKING(th) vm_check_ints_blocking(th)
static inline void
vm_check_ints_blocking(rb_thread_t *th)
{
    if (LIKELY(rb_threadptr_pending_interrupt_empty_p(th))) {
	if (LIKELY(!RUBY_VM_INTERRUPTED_ANY(th))) return;
    }
    else {
	th->pending_interrupt_queue_checked = 0;

	RUBY_VM_SET_INTERRUPT(th);
    }
    rb_threadptr_execute_interrupts(th, 1);
}

static int
vm_living_thread_num(rb_vm_t *vm)
{
    return (int)vm->living_thread_num;
}

#if THREAD_DEBUG
#ifdef HAVE_VA_ARGS_MACRO
void rb_thread_debug(const char *file, int line, const char *fmt, ...);
#define thread_debug(fmt, ...) rb_thread_debug(__FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define POSITION_FORMAT "%s:%d:"
#define POSITION_ARGS ,file, line
#else
void rb_thread_debug(const char *fmt, ...);
#define thread_debug rb_thread_debug
#define POSITION_FORMAT
#define POSITION_ARGS
#endif

# ifdef NON_SCALAR_THREAD_ID
static const char *
fill_thread_id_string(rb_nativethread_id_t thid, rb_thread_id_string_t buf)
{
    extern const char ruby_digitmap[];
    size_t i;

    buf[0] = '0';
    buf[1] = 'x';
    for (i = 0; i < sizeof(thid); i++) {
# ifdef LITTLE_ENDIAN
	size_t j = sizeof(thid) - i - 1;
# else
	size_t j = i;
# endif
	unsigned char c = (unsigned char)((char *)&thid)[j];
	buf[2 + i * 2] = ruby_digitmap[(c >> 4) & 0xf];
	buf[3 + i * 2] = ruby_digitmap[c & 0xf];
    }
    buf[sizeof(rb_thread_id_string_t)-1] = '\0';
    return buf;
}
#   define fill_thread_id_str(th) fill_thread_id_string((th)->thread_id, (th)->thread_id_string)
#   define thread_id_str(th) ((th)->thread_id_string)
#   define PRI_THREAD_ID "s"
# endif

# if THREAD_DEBUG < 0
static int rb_thread_debug_enabled;

/*
 *  call-seq:
 *     Thread.DEBUG     -> num
 *
 *  Returns the thread debug level.  Available only if compiled with
 *  THREAD_DEBUG=-1.
 */

static VALUE
rb_thread_s_debug(void)
{
    return INT2NUM(rb_thread_debug_enabled);
}

/*
 *  call-seq:
 *     Thread.DEBUG = num
 *
 *  Sets the thread debug level.  Available only if compiled with
 *  THREAD_DEBUG=-1.
 */

static VALUE
rb_thread_s_debug_set(VALUE self, VALUE val)
{
    rb_thread_debug_enabled = RTEST(val) ? NUM2INT(val) : 0;
    return val;
}
# else
# define rb_thread_debug_enabled THREAD_DEBUG
# endif
#else
#define thread_debug if(0)printf
#endif

#ifndef fill_thread_id_str
# define fill_thread_id_string(thid, buf) (thid)
# define fill_thread_id_str(th) (void)0
# define thread_id_str(th) ((void *)(th)->thread_id)
# define PRI_THREAD_ID "p"
#endif

#ifndef __ia64
#define thread_start_func_2(th, st, rst) thread_start_func_2(th, st)
#endif
NOINLINE(static int thread_start_func_2(rb_thread_t *th, VALUE *stack_start,
					VALUE *register_stack_start));
static void timer_thread_function(void *);

#if   defined(_WIN32)
#include "thread_win32.c"

#define DEBUG_OUT() \
  WaitForSingleObject(&debug_mutex, INFINITE); \
  printf(POSITION_FORMAT"%#lx - %s" POSITION_ARGS, GetCurrentThreadId(), buf); \
  fflush(stdout); \
  ReleaseMutex(&debug_mutex);

#elif defined(HAVE_PTHREAD_H)
#include "thread_pthread.c"

#define DEBUG_OUT() \
  pthread_mutex_lock(&debug_mutex); \
  printf(POSITION_FORMAT"%"PRI_THREAD_ID" - %s" POSITION_ARGS, \
	 fill_thread_id_string(pthread_self(), thread_id_string), buf);	\
  fflush(stdout); \
  pthread_mutex_unlock(&debug_mutex);

#else
#error "unsupported thread type"
#endif

#if THREAD_DEBUG
static int debug_mutex_initialized = 1;
static rb_nativethread_lock_t debug_mutex;

void
rb_thread_debug(
#ifdef HAVE_VA_ARGS_MACRO
    const char *file, int line,
#endif
    const char *fmt, ...)
{
    va_list args;
    char buf[BUFSIZ];
#ifdef NON_SCALAR_THREAD_ID
    rb_thread_id_string_t thread_id_string;
#endif

    if (!rb_thread_debug_enabled) return;

    if (debug_mutex_initialized == 1) {
	debug_mutex_initialized = 0;
	native_mutex_initialize(&debug_mutex);
    }

    va_start(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);

    DEBUG_OUT();
}
#endif

#include "thread_sync.c"

void
rb_vm_gvl_destroy(rb_vm_t *vm)
{
    gvl_release(vm);
    gvl_destroy(vm);
    native_mutex_destroy(&vm->thread_destruct_lock);
}

void
rb_nativethread_lock_initialize(rb_nativethread_lock_t *lock)
{
    native_mutex_initialize(lock);
}

void
rb_nativethread_lock_destroy(rb_nativethread_lock_t *lock)
{
    native_mutex_destroy(lock);
}

void
rb_nativethread_lock_lock(rb_nativethread_lock_t *lock)
{
    native_mutex_lock(lock);
}

void
rb_nativethread_lock_unlock(rb_nativethread_lock_t *lock)
{
    native_mutex_unlock(lock);
}

static int
set_unblock_function(rb_thread_t *th, rb_unblock_function_t *func, void *arg,
		     struct rb_unblock_callback *old, int fail_if_interrupted)
{
    do {
	if (fail_if_interrupted) {
	    if (RUBY_VM_INTERRUPTED_ANY(th)) {
		return FALSE;
	    }
	}
	else {
	    RUBY_VM_CHECK_INTS(th);
	}

	native_mutex_lock(&th->interrupt_lock);
    } while (RUBY_VM_INTERRUPTED_ANY(th) &&
	     (native_mutex_unlock(&th->interrupt_lock), TRUE));

    if (old) *old = th->unblock;
    th->unblock.func = func;
    th->unblock.arg = arg;
    native_mutex_unlock(&th->interrupt_lock);

    return TRUE;
}

static void
reset_unblock_function(rb_thread_t *th, const struct rb_unblock_callback *old)
{
    native_mutex_lock(&th->interrupt_lock);
    th->unblock = *old;
    native_mutex_unlock(&th->interrupt_lock);
}

static void
rb_threadptr_interrupt_common(rb_thread_t *th, int trap)
{
    native_mutex_lock(&th->interrupt_lock);
    if (trap)
	RUBY_VM_SET_TRAP_INTERRUPT(th);
    else
	RUBY_VM_SET_INTERRUPT(th);
    if (th->unblock.func) {
	(th->unblock.func)(th->unblock.arg);
    }
    else {
	/* none */
    }
    native_cond_signal(&th->interrupt_cond);
    native_mutex_unlock(&th->interrupt_lock);
}

void
rb_threadptr_interrupt(rb_thread_t *th)
{
    rb_threadptr_interrupt_common(th, 0);
}

void
rb_threadptr_trap_interrupt(rb_thread_t *th)
{
    rb_threadptr_interrupt_common(th, 1);
}

static void
terminate_all(rb_vm_t *vm, const rb_thread_t *main_thread)
{
    rb_thread_t *th = 0;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	if (th != main_thread) {
	    thread_debug("terminate_i: %p\n", (void *)th);
	    rb_threadptr_pending_interrupt_enque(th, eTerminateSignal);
	    rb_threadptr_interrupt(th);
	}
	else {
	    thread_debug("terminate_i: main thread (%p)\n", (void *)th);
	}
    }
}

void
rb_threadptr_unlock_all_locking_mutexes(rb_thread_t *th)
{
    const char *err;
    rb_mutex_t *mutex;
    rb_mutex_t *mutexes = th->keeping_mutexes;

    while (mutexes) {
	mutex = mutexes;
	/* rb_warn("mutex #<%p> remains to be locked by terminated thread",
		mutexes); */
	mutexes = mutex->next_mutex;
	err = rb_mutex_unlock_th(mutex, th);
	if (err) rb_bug("invalid keeping_mutexes: %s", err);
    }
}

void
rb_thread_terminate_all(void)
{
    rb_thread_t *volatile th = GET_THREAD(); /* main thread */
    rb_vm_t *volatile vm = th->vm;
    volatile int sleeping = 0;

    if (vm->main_thread != th) {
	rb_bug("rb_thread_terminate_all: called by child thread (%p, %p)",
	       (void *)vm->main_thread, (void *)th);
    }

    /* unlock all locking mutexes */
    rb_threadptr_unlock_all_locking_mutexes(th);

    TH_PUSH_TAG(th);
    if (TH_EXEC_TAG() == 0) {
      retry:
	thread_debug("rb_thread_terminate_all (main thread: %p)\n", (void *)th);
	terminate_all(vm, th);

	while (vm_living_thread_num(vm) > 1) {
	    /*
	     * Thread exiting routine in thread_start_func_2 notify
	     * me when the last sub-thread exit.
	     */
	    sleeping = 1;
	    native_sleep(th, 0);
	    RUBY_VM_CHECK_INTS_BLOCKING(th);
	    sleeping = 0;
	}
    }
    else {
	/*
	 * When caught an exception (e.g. Ctrl+C), let's broadcast
	 * kill request again to ensure killing all threads even
	 * if they are blocked on sleep, mutex, etc.
	 */
	if (sleeping) {
	    sleeping = 0;
	    goto retry;
	}
    }
    TH_POP_TAG();
}

static void
thread_cleanup_func_before_exec(void *th_ptr)
{
    rb_thread_t *th = th_ptr;
    th->status = THREAD_KILLED;
    th->machine.stack_start = th->machine.stack_end = 0;
#ifdef __ia64
    th->machine.register_stack_start = th->machine.register_stack_end = 0;
#endif
}

static void
thread_cleanup_func(void *th_ptr, int atfork)
{
    rb_thread_t *th = th_ptr;

    th->locking_mutex = Qfalse;
    thread_cleanup_func_before_exec(th_ptr);

    /*
     * Unfortunately, we can't release native threading resource at fork
     * because libc may have unstable locking state therefore touching
     * a threading resource may cause a deadlock.
     */
    if (atfork)
	return;

    native_mutex_destroy(&th->interrupt_lock);
    native_thread_destroy(th);
}

static VALUE rb_threadptr_raise(rb_thread_t *, int, VALUE *);
static VALUE rb_thread_inspect(VALUE thread);

void
ruby_thread_init_stack(rb_thread_t *th)
{
    native_thread_init_stack(th);
}

const VALUE *
rb_vm_proc_local_ep(VALUE proc)
{
    const VALUE *ep = vm_proc_ep(proc);

    if (ep) {
	return rb_vm_ep_local_ep(ep);
    }
    else {
	return NULL;
    }
}

static void
thread_do_start(rb_thread_t *th, VALUE args)
{
    native_set_thread_name(th);
    if (!th->first_func) {
	rb_proc_t *proc;
	GetProcPtr(th->first_proc, proc);
	th->errinfo = Qnil;
	th->root_lep = rb_vm_proc_local_ep(th->first_proc);
	th->root_svar = Qfalse;
	EXEC_EVENT_HOOK(th, RUBY_EVENT_THREAD_BEGIN, th->self, 0, 0, 0, Qundef);
	th->value = rb_vm_invoke_proc(th, proc,
				      (int)RARRAY_LEN(args), RARRAY_CONST_PTR(args),
				      VM_BLOCK_HANDLER_NONE);
	EXEC_EVENT_HOOK(th, RUBY_EVENT_THREAD_END, th->self, 0, 0, 0, Qundef);
    }
    else {
	th->value = (*th->first_func)((void *)args);
    }
}

static int
thread_start_func_2(rb_thread_t *th, VALUE *stack_start, VALUE *register_stack_start)
{
    int state;
    VALUE args = th->first_args;
    rb_thread_list_t *join_list;
    rb_thread_t *main_th;
    VALUE errinfo = Qnil;
# ifdef USE_SIGALTSTACK
    void rb_register_sigaltstack(rb_thread_t *th);

    rb_register_sigaltstack(th);
# endif

    if (th == th->vm->main_thread)
	rb_bug("thread_start_func_2 must not be used for main thread");

    ruby_thread_set_native(th);

    th->machine.stack_start = stack_start;
#ifdef __ia64
    th->machine.register_stack_start = register_stack_start;
#endif
    thread_debug("thread start: %p\n", (void *)th);

    gvl_acquire(th->vm, th);
    {
	thread_debug("thread start (get lock): %p\n", (void *)th);
	rb_thread_set_current(th);

	TH_PUSH_TAG(th);
	if ((state = EXEC_TAG()) == 0) {
	    SAVE_ROOT_JMPBUF(th, thread_do_start(th, args));
	}
	else {
	    errinfo = th->errinfo;
	    if (state == TAG_FATAL) {
		/* fatal error within this thread, need to stop whole script */
	    }
	    else if (rb_obj_is_kind_of(errinfo, rb_eSystemExit)) {
		/* exit on main_thread. */
	    }
	    else if (th->vm->thread_abort_on_exception ||
		     th->abort_on_exception || RTEST(ruby_debug)) {
		/* exit on main_thread */
	    }
	    else if (th->report_on_exception) {
		VALUE mesg = rb_thread_inspect(th->self);
		rb_str_cat_cstr(mesg, " terminated with exception:\n");
		rb_write_error_str(mesg);
		rb_threadptr_error_print(th, errinfo);
		errinfo = Qnil;
	    }
	    else {
		errinfo = Qnil;
	    }
	    th->value = Qnil;
	}

	th->status = THREAD_KILLED;
	thread_debug("thread end: %p\n", (void *)th);

	main_th = th->vm->main_thread;
	if (main_th == th) {
	    ruby_stop(0);
	}
	if (RB_TYPE_P(errinfo, T_OBJECT)) {
	    /* treat with normal error object */
	    rb_threadptr_raise(main_th, 1, &errinfo);
	}
	TH_POP_TAG();

	/* locking_mutex must be Qfalse */
	if (th->locking_mutex != Qfalse) {
	    rb_bug("thread_start_func_2: locking_mutex must not be set (%p:%"PRIxVALUE")",
		   (void *)th, th->locking_mutex);
	}

	/* delete self other than main thread from living_threads */
	rb_vm_living_threads_remove(th->vm, th);
	if (main_th->status == THREAD_KILLED && rb_thread_alone()) {
	    /* I'm last thread. wake up main thread from rb_thread_terminate_all */
	    rb_threadptr_interrupt(main_th);
	}

	/* wake up joining threads */
	join_list = th->join_list;
	while (join_list) {
	    rb_threadptr_interrupt(join_list->th);
	    switch (join_list->th->status) {
	      case THREAD_STOPPED: case THREAD_STOPPED_FOREVER:
		join_list->th->status = THREAD_RUNNABLE;
	      default: break;
	    }
	    join_list = join_list->next;
	}

	rb_threadptr_unlock_all_locking_mutexes(th);
	rb_check_deadlock(th->vm);

	if (!th->root_fiber) {
	    rb_thread_recycle_stack_release(th->stack);
	    th->stack = 0;
	}
    }
    native_mutex_lock(&th->vm->thread_destruct_lock);
    /* make sure vm->running_thread never point me after this point.*/
    th->vm->running_thread = NULL;
    native_mutex_unlock(&th->vm->thread_destruct_lock);
    thread_cleanup_func(th, FALSE);
    gvl_release(th->vm);

    return 0;
}

static VALUE
thread_create_core(VALUE thval, VALUE args, VALUE (*fn)(ANYARGS))
{
    rb_thread_t *th, *current_th = GET_THREAD();
    int err;

    if (OBJ_FROZEN(current_th->thgroup)) {
	rb_raise(rb_eThreadError,
		 "can't start a new thread (frozen ThreadGroup)");
    }
    GetThreadPtr(thval, th);

    /* setup thread environment */
    th->first_func = fn;
    th->first_proc = fn ? Qfalse : rb_block_proc();
    th->first_args = args; /* GC: shouldn't put before above line */

    th->priority = current_th->priority;
    th->thgroup = current_th->thgroup;

    th->pending_interrupt_queue = rb_ary_tmp_new(0);
    th->pending_interrupt_queue_checked = 0;
    th->pending_interrupt_mask_stack = rb_ary_dup(current_th->pending_interrupt_mask_stack);
    RBASIC_CLEAR_CLASS(th->pending_interrupt_mask_stack);

    th->interrupt_mask = 0;

    native_mutex_initialize(&th->interrupt_lock);
    native_cond_initialize(&th->interrupt_cond, RB_CONDATTR_CLOCK_MONOTONIC);
    th->report_on_exception = th->vm->thread_report_on_exception;

    /* kick thread */
    err = native_thread_create(th);
    if (err) {
	th->status = THREAD_KILLED;
	rb_raise(rb_eThreadError, "can't create Thread: %s", strerror(err));
    }
    rb_vm_living_threads_insert(th->vm, th);
    return thval;
}

#define threadptr_initialized(th) ((th)->first_args != 0)

/*
 * call-seq:
 *  Thread.new { ... }			-> thread
 *  Thread.new(*args, &proc)		-> thread
 *  Thread.new(*args) { |args| ... }	-> thread
 *
 *  Creates a new thread executing the given block.
 *
 *  Any +args+ given to ::new will be passed to the block:
 *
 *	arr = []
 *	a, b, c = 1, 2, 3
 *	Thread.new(a,b,c) { |d,e,f| arr << d << e << f }.join
 *	arr #=> [1, 2, 3]
 *
 *  A ThreadError exception is raised if ::new is called without a block.
 *
 *  If you're going to subclass Thread, be sure to call super in your
 *  +initialize+ method, otherwise a ThreadError will be raised.
 */
static VALUE
thread_s_new(int argc, VALUE *argv, VALUE klass)
{
    rb_thread_t *th;
    VALUE thread = rb_thread_alloc(klass);

    if (GET_VM()->main_thread->status == THREAD_KILLED)
	rb_raise(rb_eThreadError, "can't alloc thread");

    rb_obj_call_init(thread, argc, argv);
    GetThreadPtr(thread, th);
    if (!threadptr_initialized(th)) {
	rb_raise(rb_eThreadError, "uninitialized thread - check `%"PRIsVALUE"#initialize'",
		 klass);
    }
    return thread;
}

/*
 *  call-seq:
 *     Thread.start([args]*) {|args| block }   -> thread
 *     Thread.fork([args]*) {|args| block }    -> thread
 *
 *  Basically the same as ::new. However, if class Thread is subclassed, then
 *  calling +start+ in that subclass will not invoke the subclass's
 *  +initialize+ method.
 */

static VALUE
thread_start(VALUE klass, VALUE args)
{
    return thread_create_core(rb_thread_alloc(klass), args, 0);
}

/* :nodoc: */
static VALUE
thread_initialize(VALUE thread, VALUE args)
{
    rb_thread_t *th;
    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }
    GetThreadPtr(thread, th);
    if (th->first_args) {
	VALUE proc = th->first_proc, loc;
        if (!proc || !RTEST(loc = rb_proc_location(proc))) {
            rb_raise(rb_eThreadError, "already initialized thread");
        }
        rb_raise(rb_eThreadError,
		 "already initialized thread - %"PRIsVALUE":%"PRIsVALUE,
                 RARRAY_AREF(loc, 0), RARRAY_AREF(loc, 1));
    }
    return thread_create_core(thread, args, 0);
}

VALUE
rb_thread_create(VALUE (*fn)(ANYARGS), void *arg)
{
    return thread_create_core(rb_thread_alloc(rb_cThread), (VALUE)arg, fn);
}


/* +infty, for this purpose */
#define DELAY_INFTY 1E30

struct join_arg {
    rb_thread_t *target, *waiting;
    double delay;
};

static VALUE
remove_from_join_list(VALUE arg)
{
    struct join_arg *p = (struct join_arg *)arg;
    rb_thread_t *target_th = p->target, *th = p->waiting;

    if (target_th->status != THREAD_KILLED) {
	rb_thread_list_t **p = &target_th->join_list;

	while (*p) {
	    if ((*p)->th == th) {
		*p = (*p)->next;
		break;
	    }
	    p = &(*p)->next;
	}
    }

    return Qnil;
}

static VALUE
thread_join_sleep(VALUE arg)
{
    struct join_arg *p = (struct join_arg *)arg;
    rb_thread_t *target_th = p->target, *th = p->waiting;
    const int forever = p->delay == DELAY_INFTY;
    const double limit = forever ? 0 : timeofday() + p->delay;

    while (target_th->status != THREAD_KILLED) {
	if (forever) {
	    sleep_forever(th, TRUE, FALSE);
	}
	else {
	    double now = timeofday();
	    if (now > limit) {
		thread_debug("thread_join: timeout (thid: %"PRI_THREAD_ID")\n",
			     thread_id_str(target_th));
		return Qfalse;
	    }
	    sleep_wait_for_interrupt(th, limit - now, 0);
	}
	thread_debug("thread_join: interrupted (thid: %"PRI_THREAD_ID")\n",
		     thread_id_str(target_th));
    }
    return Qtrue;
}

static VALUE
thread_join(rb_thread_t *target_th, double delay)
{
    rb_thread_t *th = GET_THREAD();
    struct join_arg arg;

    if (th == target_th) {
	rb_raise(rb_eThreadError, "Target thread must not be current thread");
    }
    if (GET_VM()->main_thread == target_th) {
	rb_raise(rb_eThreadError, "Target thread must not be main thread");
    }

    arg.target = target_th;
    arg.waiting = th;
    arg.delay = delay;

    thread_debug("thread_join (thid: %"PRI_THREAD_ID")\n", thread_id_str(target_th));

    if (target_th->status != THREAD_KILLED) {
	rb_thread_list_t list;
	list.next = target_th->join_list;
	list.th = th;
	target_th->join_list = &list;
	if (!rb_ensure(thread_join_sleep, (VALUE)&arg,
		       remove_from_join_list, (VALUE)&arg)) {
	    return Qnil;
	}
    }

    thread_debug("thread_join: success (thid: %"PRI_THREAD_ID")\n",
		 thread_id_str(target_th));

    if (target_th->errinfo != Qnil) {
	VALUE err = target_th->errinfo;

	if (FIXNUM_P(err)) {
	    switch (err) {
	      case INT2FIX(TAG_FATAL):
		/* OK. killed. */
		break;
	      default:
		rb_bug("thread_join: Fixnum (%d) should not reach here.", FIX2INT(err));
	    }
	}
	else if (THROW_DATA_P(target_th->errinfo)) {
	    rb_bug("thread_join: THROW_DATA should not reach here.");
	}
	else {
	    /* normal exception */
	    rb_exc_raise(err);
	}
    }
    return target_th->self;
}

/*
 *  call-seq:
 *     thr.join          -> thr
 *     thr.join(limit)   -> thr
 *
 *  The calling thread will suspend execution and run this +thr+.
 *
 *  Does not return until +thr+ exits or until the given +limit+ seconds have
 *  passed.
 *
 *  If the time limit expires, +nil+ will be returned, otherwise +thr+ is
 *  returned.
 *
 *  Any threads not joined will be killed when the main program exits.
 *
 *  If +thr+ had previously raised an exception and the ::abort_on_exception or
 *  $DEBUG flags are not set, (so the exception has not yet been processed), it
 *  will be processed at this time.
 *
 *     a = Thread.new { print "a"; sleep(10); print "b"; print "c" }
 *     x = Thread.new { print "x"; Thread.pass; print "y"; print "z" }
 *     x.join # Let thread x finish, thread a will be killed on exit.
 *     #=> "axyz"
 *
 *  The following example illustrates the +limit+ parameter.
 *
 *     y = Thread.new { 4.times { sleep 0.1; puts 'tick... ' }}
 *     puts "Waiting" until y.join(0.15)
 *
 *  This will produce:
 *
 *     tick...
 *     Waiting
 *     tick...
 *     Waiting
 *     tick...
 *     tick...
 */

static VALUE
thread_join_m(int argc, VALUE *argv, VALUE self)
{
    rb_thread_t *target_th;
    double delay = DELAY_INFTY;
    VALUE limit;

    GetThreadPtr(self, target_th);

    rb_scan_args(argc, argv, "01", &limit);
    if (!NIL_P(limit)) {
	delay = rb_num2dbl(limit);
    }

    return thread_join(target_th, delay);
}

/*
 *  call-seq:
 *     thr.value   -> obj
 *
 *  Waits for +thr+ to complete, using #join, and returns its value or raises
 *  the exception which terminated the thread.
 *
 *     a = Thread.new { 2 + 2 }
 *     a.value   #=> 4
 *
 *     b = Thread.new { raise 'something went wrong' }
 *     b.value   #=> RuntimeError: something went wrong
 */

static VALUE
thread_value(VALUE self)
{
    rb_thread_t *th;
    GetThreadPtr(self, th);
    thread_join(th, DELAY_INFTY);
    return th->value;
}

/*
 * Thread Scheduling
 */

/*
 * The type of tv_sec in struct timeval is time_t in POSIX.
 * But several systems violate POSIX.
 *
 * OpenBSD 5.2 (amd64):
 *   time_t: int (signed 32bit integer)
 *   tv_sec: long (signed 64bit integer)
 *
 * MinGW-w64 (x64):
 *   time_t: long long (signed 64bit integer)
 *   tv_sec: long (signed 32bit integer)
 */

#if SIGNEDNESS_OF_TIME_T < 0	/* signed */
# define TIMEVAL_SEC_MAX SIGNED_INTEGER_MAX(TYPEOF_TIMEVAL_TV_SEC)
# define TIMEVAL_SEC_MIN SIGNED_INTEGER_MIN(TYPEOF_TIMEVAL_TV_SEC)
#elif SIGNEDNESS_OF_TIME_T > 0	/* unsigned */
# define TIMEVAL_SEC_MAX ((TYPEOF_TIMEVAL_TV_SEC)(~(unsigned_time_t)0))
# define TIMEVAL_SEC_MIN ((TYPEOF_TIMEVAL_TV_SEC)0)
#endif

static struct timeval
double2timeval(double d)
{
    /* assume timeval.tv_sec has same signedness as time_t */
    const double TIMEVAL_SEC_MAX_PLUS_ONE = (2*(double)(TIMEVAL_SEC_MAX/2+1));

    struct timeval time;

    if (TIMEVAL_SEC_MAX_PLUS_ONE <= d) {
        time.tv_sec = TIMEVAL_SEC_MAX;
        time.tv_usec = 999999;
    }
    else if (d <= TIMEVAL_SEC_MIN) {
        time.tv_sec = TIMEVAL_SEC_MIN;
        time.tv_usec = 0;
    }
    else {
        time.tv_sec = (TYPEOF_TIMEVAL_TV_SEC)d;
        time.tv_usec = (int)((d - (time_t)d) * 1e6);
        if (time.tv_usec < 0) {
            time.tv_usec += (int)1e6;
            time.tv_sec -= 1;
        }
    }
    return time;
}

static void
sleep_forever(rb_thread_t *th, int deadlockable, int spurious_check)
{
    enum rb_thread_status prev_status = th->status;
    enum rb_thread_status status = deadlockable ? THREAD_STOPPED_FOREVER : THREAD_STOPPED;

    th->status = status;
    RUBY_VM_CHECK_INTS_BLOCKING(th);
    while (th->status == status) {
	if (deadlockable) {
	    th->vm->sleeper++;
	    rb_check_deadlock(th->vm);
	}
	native_sleep(th, 0);
	if (deadlockable) {
	    th->vm->sleeper--;
	}
	RUBY_VM_CHECK_INTS_BLOCKING(th);
	if (!spurious_check)
	    break;
    }
    th->status = prev_status;
}

static void
getclockofday(struct timeval *tp)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
	tp->tv_sec = ts.tv_sec;
	tp->tv_usec = (int)(ts.tv_nsec / 1000);
    }
    else
#endif
    {
        gettimeofday(tp, NULL);
    }
}

static void
sleep_timeval(rb_thread_t *th, struct timeval tv, int spurious_check)
{
    struct timeval to, tvn;
    enum rb_thread_status prev_status = th->status;

    getclockofday(&to);
    if (TIMEVAL_SEC_MAX - tv.tv_sec < to.tv_sec)
        to.tv_sec = TIMEVAL_SEC_MAX;
    else
        to.tv_sec += tv.tv_sec;
    if ((to.tv_usec += tv.tv_usec) >= 1000000) {
        if (to.tv_sec == TIMEVAL_SEC_MAX)
            to.tv_usec = 999999;
        else {
            to.tv_sec++;
            to.tv_usec -= 1000000;
        }
    }

    th->status = THREAD_STOPPED;
    RUBY_VM_CHECK_INTS_BLOCKING(th);
    while (th->status == THREAD_STOPPED) {
	native_sleep(th, &tv);
	RUBY_VM_CHECK_INTS_BLOCKING(th);
	getclockofday(&tvn);
	if (to.tv_sec < tvn.tv_sec) break;
	if (to.tv_sec == tvn.tv_sec && to.tv_usec <= tvn.tv_usec) break;
	thread_debug("sleep_timeval: %"PRI_TIMET_PREFIX"d.%.6ld > %"PRI_TIMET_PREFIX"d.%.6ld\n",
		     (time_t)to.tv_sec, (long)to.tv_usec,
		     (time_t)tvn.tv_sec, (long)tvn.tv_usec);
	tv.tv_sec = to.tv_sec - tvn.tv_sec;
	if ((tv.tv_usec = to.tv_usec - tvn.tv_usec) < 0) {
	    --tv.tv_sec;
	    tv.tv_usec += 1000000;
	}
	if (!spurious_check)
	    break;
    }
    th->status = prev_status;
}

void
rb_thread_sleep_forever(void)
{
    thread_debug("rb_thread_sleep_forever\n");
    sleep_forever(GET_THREAD(), FALSE, TRUE);
}

void
rb_thread_sleep_deadly(void)
{
    thread_debug("rb_thread_sleep_deadly\n");
    sleep_forever(GET_THREAD(), TRUE, TRUE);
}

static void
rb_thread_sleep_deadly_allow_spurious_wakeup(void)
{
    thread_debug("rb_thread_sleep_deadly_allow_spurious_wakeup\n");
    sleep_forever(GET_THREAD(), TRUE, FALSE);
}

static double
timeofday(void)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
    struct timespec tp;

    if (clock_gettime(CLOCK_MONOTONIC, &tp) == 0) {
        return (double)tp.tv_sec + (double)tp.tv_nsec * 1e-9;
    }
    else
#endif
    {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (double)tv.tv_sec + (double)tv.tv_usec * 1e-6;
    }
}

static void
sleep_wait_for_interrupt(rb_thread_t *th, double sleepsec, int spurious_check)
{
    sleep_timeval(th, double2timeval(sleepsec), spurious_check);
}

void
rb_thread_wait_for(struct timeval time)
{
    rb_thread_t *th = GET_THREAD();
    sleep_timeval(th, time, 1);
}

/*
 * CAUTION: This function causes thread switching.
 *          rb_thread_check_ints() check ruby's interrupts.
 *          some interrupt needs thread switching/invoke handlers,
 *          and so on.
 */

void
rb_thread_check_ints(void)
{
    rb_thread_t *th = GET_THREAD();
    RUBY_VM_CHECK_INTS_BLOCKING(th);
}

/*
 * Hidden API for tcl/tk wrapper.
 * There is no guarantee to perpetuate it.
 */
int
rb_thread_check_trap_pending(void)
{
    return rb_signal_buff_size() != 0;
}

/* This function can be called in blocking region. */
int
rb_thread_interrupted(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    return (int)RUBY_VM_INTERRUPTED(th);
}

void
rb_thread_sleep(int sec)
{
    rb_thread_wait_for(rb_time_timeval(INT2FIX(sec)));
}

static void
rb_thread_schedule_limits(unsigned long limits_us)
{
    thread_debug("rb_thread_schedule\n");
    if (!rb_thread_alone()) {
	rb_thread_t *th = GET_THREAD();

	if (th->running_time_us >= limits_us) {
	    thread_debug("rb_thread_schedule/switch start\n");
	    RB_GC_SAVE_MACHINE_CONTEXT(th);
	    gvl_yield(th->vm, th);
	    rb_thread_set_current(th);
	    thread_debug("rb_thread_schedule/switch done\n");
	}
    }
}

void
rb_thread_schedule(void)
{
    rb_thread_t *cur_th = GET_THREAD();
    rb_thread_schedule_limits(0);

    RUBY_VM_CHECK_INTS(cur_th);
}

/* blocking region */

static inline int
blocking_region_begin(rb_thread_t *th, struct rb_blocking_region_buffer *region,
		      rb_unblock_function_t *ubf, void *arg, int fail_if_interrupted)
{
    region->prev_status = th->status;
    if (set_unblock_function(th, ubf, arg, &region->oldubf, fail_if_interrupted)) {
	th->blocking_region_buffer = region;
	th->status = THREAD_STOPPED;
	thread_debug("enter blocking region (%p)\n", (void *)th);
	RB_GC_SAVE_MACHINE_CONTEXT(th);
	gvl_release(th->vm);
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static inline void
blocking_region_end(rb_thread_t *th, struct rb_blocking_region_buffer *region)
{
    gvl_acquire(th->vm, th);
    rb_thread_set_current(th);
    thread_debug("leave blocking region (%p)\n", (void *)th);
    unregister_ubf_list(th);
    th->blocking_region_buffer = 0;
    reset_unblock_function(th, &region->oldubf);
    if (th->status == THREAD_STOPPED) {
	th->status = region->prev_status;
    }
}

static void *
call_without_gvl(void *(*func)(void *), void *data1,
		 rb_unblock_function_t *ubf, void *data2, int fail_if_interrupted)
{
    void *val = 0;

    rb_thread_t *th = GET_THREAD();
    int saved_errno = 0;

    th->waiting_fd = -1;
    if (ubf == RUBY_UBF_IO || ubf == RUBY_UBF_PROCESS) {
	ubf = ubf_select;
	data2 = th;
    }

    BLOCKING_REGION({
	val = func(data1);
	saved_errno = errno;
    }, ubf, data2, fail_if_interrupted);

    if (!fail_if_interrupted) {
	RUBY_VM_CHECK_INTS_BLOCKING(th);
    }

    errno = saved_errno;

    return val;
}

/*
 * rb_thread_call_without_gvl - permit concurrent/parallel execution.
 * rb_thread_call_without_gvl2 - permit concurrent/parallel execution
 *                               without interrupt process.
 *
 * rb_thread_call_without_gvl() does:
 *   (1) Check interrupts.
 *   (2) release GVL.
 *       Other Ruby threads may run in parallel.
 *   (3) call func with data1
 *   (4) acquire GVL.
 *       Other Ruby threads can not run in parallel any more.
 *   (5) Check interrupts.
 *
 * rb_thread_call_without_gvl2() does:
 *   (1) Check interrupt and return if interrupted.
 *   (2) release GVL.
 *   (3) call func with data1 and a pointer to the flags.
 *   (4) acquire GVL.
 *
 * If another thread interrupts this thread (Thread#kill, signal delivery,
 * VM-shutdown request, and so on), `ubf()' is called (`ubf()' means
 * "un-blocking function").  `ubf()' should interrupt `func()' execution by
 * toggling a cancellation flag, canceling the invocation of a call inside
 * `func()' or similar.  Note that `ubf()' may not be called with the GVL.
 *
 * There are built-in ubfs and you can specify these ubfs:
 *
 * * RUBY_UBF_IO: ubf for IO operation
 * * RUBY_UBF_PROCESS: ubf for process operation
 *
 * However, we can not guarantee our built-in ubfs interrupt your `func()'
 * correctly. Be careful to use rb_thread_call_without_gvl(). If you don't
 * provide proper ubf(), your program will not stop for Control+C or other
 * shutdown events.
 *
 * "Check interrupts" on above list means checking asynchronous
 * interrupt events (such as Thread#kill, signal delivery, VM-shutdown
 * request, and so on) and calling corresponding procedures
 * (such as `trap' for signals, raise an exception for Thread#raise).
 * If `func()' finished and received interrupts, you may skip interrupt
 * checking.  For example, assume the following func() it reads data from file.
 *
 *   read_func(...) {
 *                   // (a) before read
 *     read(buffer); // (b) reading
 *                   // (c) after read
 *   }
 *
 * If an interrupt occurs at (a) or (b), then `ubf()' cancels this
 * `read_func()' and interrupts are checked. However, if an interrupt occurs
 * at (c), after *read* operation is completed, checking interrupts is harmful
 * because it causes irrevocable side-effect, the read data will vanish.  To
 * avoid such problem, the `read_func()' should be used with
 * `rb_thread_call_without_gvl2()'.
 *
 * If `rb_thread_call_without_gvl2()' detects interrupt, it returns
 * immediately. This function does not show when the execution was interrupted.
 * For example, there are 4 possible timing (a), (b), (c) and before calling
 * read_func(). You need to record progress of a read_func() and check
 * the progress after `rb_thread_call_without_gvl2()'. You may need to call
 * `rb_thread_check_ints()' correctly or your program can not process proper
 * process such as `trap' and so on.
 *
 * NOTE: You can not execute most of Ruby C API and touch Ruby
 *       objects in `func()' and `ubf()', including raising an
 *       exception, because current thread doesn't acquire GVL
 *       (it causes synchronization problems).  If you need to
 *       call ruby functions either use rb_thread_call_with_gvl()
 *       or read source code of C APIs and confirm safety by
 *       yourself.
 *
 * NOTE: In short, this API is difficult to use safely.  I recommend you
 *       use other ways if you have.  We lack experiences to use this API.
 *       Please report your problem related on it.
 *
 * NOTE: Releasing GVL and re-acquiring GVL may be expensive operations
 *       for a short running `func()'. Be sure to benchmark and use this
 *       mechanism when `func()' consumes enough time.
 *
 * Safe C API:
 * * rb_thread_interrupted() - check interrupt flag
 * * ruby_xmalloc(), ruby_xrealloc(), ruby_xfree() -
 *   they will work without GVL, and may acquire GVL when GC is needed.
 */
void *
rb_thread_call_without_gvl2(void *(*func)(void *), void *data1,
			    rb_unblock_function_t *ubf, void *data2)
{
    return call_without_gvl(func, data1, ubf, data2, TRUE);
}

void *
rb_thread_call_without_gvl(void *(*func)(void *data), void *data1,
			    rb_unblock_function_t *ubf, void *data2)
{
    return call_without_gvl(func, data1, ubf, data2, FALSE);
}

VALUE
rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd)
{
    volatile VALUE val = Qundef; /* shouldn't be used */
    rb_thread_t *th = GET_THREAD();
    volatile int saved_errno = 0;
    int state;

    th->waiting_fd = fd;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	BLOCKING_REGION({
	    val = func(data1);
	    saved_errno = errno;
	}, ubf_select, th, FALSE);
    }
    TH_POP_TAG();

    /* clear waiting_fd anytime */
    th->waiting_fd = -1;

    if (state) {
	TH_JUMP_TAG(th, state);
    }
    /* TODO: check func() */
    RUBY_VM_CHECK_INTS_BLOCKING(th);

    errno = saved_errno;

    return val;
}

/*
 * rb_thread_call_with_gvl - re-enter the Ruby world after GVL release.
 *
 * After releasing GVL using
 * rb_thread_call_without_gvl() you can not access Ruby values or invoke
 * methods. If you need to access Ruby you must use this function
 * rb_thread_call_with_gvl().
 *
 * This function rb_thread_call_with_gvl() does:
 * (1) acquire GVL.
 * (2) call passed function `func'.
 * (3) release GVL.
 * (4) return a value which is returned at (2).
 *
 * NOTE: You should not return Ruby object at (2) because such Object
 *       will not be marked.
 *
 * NOTE: If an exception is raised in `func', this function DOES NOT
 *       protect (catch) the exception.  If you have any resources
 *       which should free before throwing exception, you need use
 *       rb_protect() in `func' and return a value which represents
 *       exception was raised.
 *
 * NOTE: This function should not be called by a thread which was not
 *       created as Ruby thread (created by Thread.new or so).  In other
 *       words, this function *DOES NOT* associate or convert a NON-Ruby
 *       thread to a Ruby thread.
 */
void *
rb_thread_call_with_gvl(void *(*func)(void *), void *data1)
{
    rb_thread_t *th = ruby_thread_from_native();
    struct rb_blocking_region_buffer *brb;
    struct rb_unblock_callback prev_unblock;
    void *r;

    if (th == 0) {
	/* Error has occurred, but we can't use rb_bug()
	 * because this thread is not Ruby's thread.
         * What should we do?
	 */

	fprintf(stderr, "[BUG] rb_thread_call_with_gvl() is called by non-ruby thread\n");
	exit(EXIT_FAILURE);
    }

    brb = (struct rb_blocking_region_buffer *)th->blocking_region_buffer;
    prev_unblock = th->unblock;

    if (brb == 0) {
	rb_bug("rb_thread_call_with_gvl: called by a thread which has GVL.");
    }

    blocking_region_end(th, brb);
    /* enter to Ruby world: You can access Ruby values, methods and so on. */
    r = (*func)(data1);
    /* leave from Ruby world: You can not access Ruby values, etc. */
    blocking_region_begin(th, brb, prev_unblock.func, prev_unblock.arg, FALSE);
    return r;
}

/*
 * ruby_thread_has_gvl_p - check if current native thread has GVL.
 *
 ***
 *** This API is EXPERIMENTAL!
 *** We do not guarantee that this API remains in ruby 1.9.2 or later.
 ***
 */

int
ruby_thread_has_gvl_p(void)
{
    rb_thread_t *th = ruby_thread_from_native();

    if (th && th->blocking_region_buffer == 0) {
	return 1;
    }
    else {
	return 0;
    }
}

/*
 * call-seq:
 *    Thread.pass   -> nil
 *
 * Give the thread scheduler a hint to pass execution to another thread.
 * A running thread may or may not switch, it depends on OS and processor.
 */

static VALUE
thread_s_pass(VALUE klass)
{
    rb_thread_schedule();
    return Qnil;
}

/*****************************************************/

/*
 * rb_threadptr_pending_interrupt_* - manage asynchronous error queue
 *
 * Async events such as an exception thrown by Thread#raise,
 * Thread#kill and thread termination (after main thread termination)
 * will be queued to th->pending_interrupt_queue.
 * - clear: clear the queue.
 * - enque: enqueue err object into queue.
 * - deque: dequeue err object from queue.
 * - active_p: return 1 if the queue should be checked.
 *
 * All rb_threadptr_pending_interrupt_* functions are called by
 * a GVL acquired thread, of course.
 * Note that all "rb_" prefix APIs need GVL to call.
 */

void
rb_threadptr_pending_interrupt_clear(rb_thread_t *th)
{
    rb_ary_clear(th->pending_interrupt_queue);
}

void
rb_threadptr_pending_interrupt_enque(rb_thread_t *th, VALUE v)
{
    rb_ary_push(th->pending_interrupt_queue, v);
    th->pending_interrupt_queue_checked = 0;
}

static void
threadptr_check_pending_interrupt_queue(rb_thread_t *th)
{
    if (!th->pending_interrupt_queue) {
	rb_raise(rb_eThreadError, "uninitialized thread");
    }
}

enum handle_interrupt_timing {
    INTERRUPT_NONE,
    INTERRUPT_IMMEDIATE,
    INTERRUPT_ON_BLOCKING,
    INTERRUPT_NEVER
};

static enum handle_interrupt_timing
rb_threadptr_pending_interrupt_check_mask(rb_thread_t *th, VALUE err)
{
    VALUE mask;
    long mask_stack_len = RARRAY_LEN(th->pending_interrupt_mask_stack);
    const VALUE *mask_stack = RARRAY_CONST_PTR(th->pending_interrupt_mask_stack);
    VALUE ancestors = rb_mod_ancestors(err); /* TODO: GC guard */
    long ancestors_len = RARRAY_LEN(ancestors);
    const VALUE *ancestors_ptr = RARRAY_CONST_PTR(ancestors);
    int i, j;

    for (i=0; i<mask_stack_len; i++) {
	mask = mask_stack[mask_stack_len-(i+1)];

	for (j=0; j<ancestors_len; j++) {
	    VALUE klass = ancestors_ptr[j];
	    VALUE sym;

	    /* TODO: remove rb_intern() */
	    if ((sym = rb_hash_aref(mask, klass)) != Qnil) {
		if (sym == sym_immediate) {
		    return INTERRUPT_IMMEDIATE;
		}
		else if (sym == sym_on_blocking) {
		    return INTERRUPT_ON_BLOCKING;
		}
		else if (sym == sym_never) {
		    return INTERRUPT_NEVER;
		}
		else {
		    rb_raise(rb_eThreadError, "unknown mask signature");
		}
	    }
	}
	/* try to next mask */
    }
    return INTERRUPT_NONE;
}

static int
rb_threadptr_pending_interrupt_empty_p(rb_thread_t *th)
{
    return RARRAY_LEN(th->pending_interrupt_queue) == 0;
}

static int
rb_threadptr_pending_interrupt_include_p(rb_thread_t *th, VALUE err)
{
    int i;
    for (i=0; i<RARRAY_LEN(th->pending_interrupt_queue); i++) {
	VALUE e = RARRAY_AREF(th->pending_interrupt_queue, i);
	if (rb_class_inherited_p(e, err)) {
	    return TRUE;
	}
    }
    return FALSE;
}

static VALUE
rb_threadptr_pending_interrupt_deque(rb_thread_t *th, enum handle_interrupt_timing timing)
{
#if 1 /* 1 to enable Thread#handle_interrupt, 0 to ignore it */
    int i;

    for (i=0; i<RARRAY_LEN(th->pending_interrupt_queue); i++) {
	VALUE err = RARRAY_AREF(th->pending_interrupt_queue, i);

	enum handle_interrupt_timing mask_timing = rb_threadptr_pending_interrupt_check_mask(th, CLASS_OF(err));

	switch (mask_timing) {
	  case INTERRUPT_ON_BLOCKING:
	    if (timing != INTERRUPT_ON_BLOCKING) {
		break;
	    }
	    /* fall through */
	  case INTERRUPT_NONE: /* default: IMMEDIATE */
	  case INTERRUPT_IMMEDIATE:
	    rb_ary_delete_at(th->pending_interrupt_queue, i);
	    return err;
	  case INTERRUPT_NEVER:
	    break;
	}
    }

    th->pending_interrupt_queue_checked = 1;
    return Qundef;
#else
    VALUE err = rb_ary_shift(th->pending_interrupt_queue);
    if (rb_threadptr_pending_interrupt_empty_p(th)) {
	th->pending_interrupt_queue_checked = 1;
    }
    return err;
#endif
}

int
rb_threadptr_pending_interrupt_active_p(rb_thread_t *th)
{
    /*
     * For optimization, we don't check async errinfo queue
     * if the queue and the thread interrupt mask were not changed
     * since last check.
     */
    if (th->pending_interrupt_queue_checked) {
	return 0;
    }

    if (rb_threadptr_pending_interrupt_empty_p(th)) {
	return 0;
    }

    return 1;
}

static int
handle_interrupt_arg_check_i(VALUE key, VALUE val, VALUE args)
{
    VALUE *maskp = (VALUE *)args;

    if (val != sym_immediate && val != sym_on_blocking && val != sym_never) {
	rb_raise(rb_eArgError, "unknown mask signature");
    }

    if (!*maskp) {
	*maskp = rb_ident_hash_new();
    }
    rb_hash_aset(*maskp, key, val);

    return ST_CONTINUE;
}

/*
 * call-seq:
 *   Thread.handle_interrupt(hash) { ... } -> result of the block
 *
 * Changes asynchronous interrupt timing.
 *
 * _interrupt_ means asynchronous event and corresponding procedure
 * by Thread#raise, Thread#kill, signal trap (not supported yet)
 * and main thread termination (if main thread terminates, then all
 * other thread will be killed).
 *
 * The given +hash+ has pairs like <code>ExceptionClass =>
 * :TimingSymbol</code>. Where the ExceptionClass is the interrupt handled by
 * the given block. The TimingSymbol can be one of the following symbols:
 *
 * [+:immediate+]   Invoke interrupts immediately.
 * [+:on_blocking+] Invoke interrupts while _BlockingOperation_.
 * [+:never+]       Never invoke all interrupts.
 *
 * _BlockingOperation_ means that the operation will block the calling thread,
 * such as read and write.  On CRuby implementation, _BlockingOperation_ is any
 * operation executed without GVL.
 *
 * Masked asynchronous interrupts are delayed until they are enabled.
 * This method is similar to sigprocmask(3).
 *
 * === NOTE
 *
 * Asynchronous interrupts are difficult to use.
 *
 * If you need to communicate between threads, please consider to use another way such as Queue.
 *
 * Or use them with deep understanding about this method.
 *
 * === Usage
 *
 * In this example, we can guard from Thread#raise exceptions.
 *
 * Using the +:never+ TimingSymbol the RuntimeError exception will always be
 * ignored in the first block of the main thread. In the second
 * ::handle_interrupt block we can purposefully handle RuntimeError exceptions.
 *
 *   th = Thread.new do
 *     Thread.handle_interrupt(RuntimeError => :never) {
 *       begin
 *         # You can write resource allocation code safely.
 *         Thread.handle_interrupt(RuntimeError => :immediate) {
 *	     # ...
 *         }
 *       ensure
 *         # You can write resource deallocation code safely.
 *       end
 *     }
 *   end
 *   Thread.pass
 *   # ...
 *   th.raise "stop"
 *
 * While we are ignoring the RuntimeError exception, it's safe to write our
 * resource allocation code. Then, the ensure block is where we can safely
 * deallocate your resources.
 *
 * ==== Guarding from Timeout::Error
 *
 * In the next example, we will guard from the Timeout::Error exception. This
 * will help prevent from leaking resources when Timeout::Error exceptions occur
 * during normal ensure clause. For this example we use the help of the
 * standard library Timeout, from lib/timeout.rb
 *
 *   require 'timeout'
 *   Thread.handle_interrupt(Timeout::Error => :never) {
 *     timeout(10){
 *       # Timeout::Error doesn't occur here
 *       Thread.handle_interrupt(Timeout::Error => :on_blocking) {
 *         # possible to be killed by Timeout::Error
 *         # while blocking operation
 *       }
 *       # Timeout::Error doesn't occur here
 *     }
 *   }
 *
 * In the first part of the +timeout+ block, we can rely on Timeout::Error being
 * ignored. Then in the <code>Timeout::Error => :on_blocking</code> block, any
 * operation that will block the calling thread is susceptible to a
 * Timeout::Error exception being raised.
 *
 * ==== Stack control settings
 *
 * It's possible to stack multiple levels of ::handle_interrupt blocks in order
 * to control more than one ExceptionClass and TimingSymbol at a time.
 *
 *   Thread.handle_interrupt(FooError => :never) {
 *     Thread.handle_interrupt(BarError => :never) {
 *        # FooError and BarError are prohibited.
 *     }
 *   }
 *
 * ==== Inheritance with ExceptionClass
 *
 * All exceptions inherited from the ExceptionClass parameter will be considered.
 *
 *   Thread.handle_interrupt(Exception => :never) {
 *     # all exceptions inherited from Exception are prohibited.
 *   }
 *
 */
static VALUE
rb_thread_s_handle_interrupt(VALUE self, VALUE mask_arg)
{
    VALUE mask;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE r = Qnil;
    int state;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "block is needed.");
    }

    mask = 0;
    mask_arg = rb_convert_type(mask_arg, T_HASH, "Hash", "to_hash");
    rb_hash_foreach(mask_arg, handle_interrupt_arg_check_i, (VALUE)&mask);
    if (!mask) {
	return rb_yield(Qnil);
    }
    OBJ_FREEZE_RAW(mask);
    rb_ary_push(th->pending_interrupt_mask_stack, mask);
    if (!rb_threadptr_pending_interrupt_empty_p(th)) {
	th->pending_interrupt_queue_checked = 0;
	RUBY_VM_SET_INTERRUPT(th);
    }

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	r = rb_yield(Qnil);
    }
    TH_POP_TAG();

    rb_ary_pop(th->pending_interrupt_mask_stack);
    if (!rb_threadptr_pending_interrupt_empty_p(th)) {
	th->pending_interrupt_queue_checked = 0;
	RUBY_VM_SET_INTERRUPT(th);
    }

    RUBY_VM_CHECK_INTS(th);

    if (state) {
	TH_JUMP_TAG(th, state);
    }

    return r;
}

/*
 * call-seq:
 *   target_thread.pending_interrupt?(error = nil) -> true/false
 *
 * Returns whether or not the asynchronous queue is empty for the target thread.
 *
 * If +error+ is given, then check only for +error+ type deferred events.
 *
 * See ::pending_interrupt? for more information.
 */
static VALUE
rb_thread_pending_interrupt_p(int argc, VALUE *argv, VALUE target_thread)
{
    rb_thread_t *target_th;

    GetThreadPtr(target_thread, target_th);

    if (!target_th->pending_interrupt_queue) {
	return Qfalse;
    }
    if (rb_threadptr_pending_interrupt_empty_p(target_th)) {
	return Qfalse;
    }
    else {
	if (argc == 1) {
	    VALUE err;
	    rb_scan_args(argc, argv, "01", &err);
	    if (!rb_obj_is_kind_of(err, rb_cModule)) {
		rb_raise(rb_eTypeError, "class or module required for rescue clause");
	    }
	    if (rb_threadptr_pending_interrupt_include_p(target_th, err)) {
		return Qtrue;
	    }
	    else {
		return Qfalse;
	    }
	}
	return Qtrue;
    }
}

/*
 * call-seq:
 *   Thread.pending_interrupt?(error = nil) -> true/false
 *
 * Returns whether or not the asynchronous queue is empty.
 *
 * Since Thread::handle_interrupt can be used to defer asynchronous events,
 * this method can be used to determine if there are any deferred events.
 *
 * If you find this method returns true, then you may finish +:never+ blocks.
 *
 * For example, the following method processes deferred asynchronous events
 * immediately.
 *
 *   def Thread.kick_interrupt_immediately
 *     Thread.handle_interrupt(Object => :immediate) {
 *       Thread.pass
 *     }
 *   end
 *
 * If +error+ is given, then check only for +error+ type deferred events.
 *
 * === Usage
 *
 *   th = Thread.new{
 *     Thread.handle_interrupt(RuntimeError => :on_blocking){
 *       while true
 *         ...
 *         # reach safe point to invoke interrupt
 *         if Thread.pending_interrupt?
 *           Thread.handle_interrupt(Object => :immediate){}
 *         end
 *         ...
 *       end
 *     }
 *   }
 *   ...
 *   th.raise # stop thread
 *
 * This example can also be written as the following, which you should use to
 * avoid asynchronous interrupts.
 *
 *   flag = true
 *   th = Thread.new{
 *     Thread.handle_interrupt(RuntimeError => :on_blocking){
 *       while true
 *         ...
 *         # reach safe point to invoke interrupt
 *         break if flag == false
 *         ...
 *       end
 *     }
 *   }
 *   ...
 *   flag = false # stop thread
 */

static VALUE
rb_thread_s_pending_interrupt_p(int argc, VALUE *argv, VALUE self)
{
    return rb_thread_pending_interrupt_p(argc, argv, GET_THREAD()->self);
}

static void
rb_threadptr_to_kill(rb_thread_t *th)
{
    rb_threadptr_pending_interrupt_clear(th);
    th->status = THREAD_RUNNABLE;
    th->to_kill = 1;
    th->errinfo = INT2FIX(TAG_FATAL);
    TH_JUMP_TAG(th, TAG_FATAL);
}

static inline rb_atomic_t
threadptr_get_interrupts(rb_thread_t *th)
{
    rb_atomic_t interrupt;
    rb_atomic_t old;

    do {
	interrupt = th->interrupt_flag;
	old = ATOMIC_CAS(th->interrupt_flag, interrupt, interrupt & th->interrupt_mask);
    } while (old != interrupt);
    return interrupt & (rb_atomic_t)~th->interrupt_mask;
}

void
rb_threadptr_execute_interrupts(rb_thread_t *th, int blocking_timing)
{
    rb_atomic_t interrupt;
    int postponed_job_interrupt = 0;

    if (th->raised_flag) return;

    while ((interrupt = threadptr_get_interrupts(th)) != 0) {
	int sig;
	int timer_interrupt;
	int pending_interrupt;
	int trap_interrupt;

	timer_interrupt = interrupt & TIMER_INTERRUPT_MASK;
	pending_interrupt = interrupt & PENDING_INTERRUPT_MASK;
	postponed_job_interrupt = interrupt & POSTPONED_JOB_INTERRUPT_MASK;
	trap_interrupt = interrupt & TRAP_INTERRUPT_MASK;

	if (postponed_job_interrupt) {
	    rb_postponed_job_flush(th->vm);
	}

	/* signal handling */
	if (trap_interrupt && (th == th->vm->main_thread)) {
	    enum rb_thread_status prev_status = th->status;
	    th->status = THREAD_RUNNABLE;
	    while ((sig = rb_get_next_signal()) != 0) {
		rb_signal_exec(th, sig);
	    }
	    th->status = prev_status;
	}

	/* exception from another thread */
	if (pending_interrupt && rb_threadptr_pending_interrupt_active_p(th)) {
	    VALUE err = rb_threadptr_pending_interrupt_deque(th, blocking_timing ? INTERRUPT_ON_BLOCKING : INTERRUPT_NONE);
	    thread_debug("rb_thread_execute_interrupts: %"PRIdVALUE"\n", err);

	    if (err == Qundef) {
		/* no error */
	    }
	    else if (err == eKillSignal        /* Thread#kill received */   ||
		     err == eTerminateSignal   /* Terminate thread */       ||
		     err == INT2FIX(TAG_FATAL) /* Thread.exit etc. */         ) {
		rb_threadptr_to_kill(th);
	    }
	    else {
		/* set runnable if th was slept. */
		if (th->status == THREAD_STOPPED ||
		    th->status == THREAD_STOPPED_FOREVER)
		    th->status = THREAD_RUNNABLE;
		rb_exc_raise(err);
	    }
	}

	if (timer_interrupt) {
	    unsigned long limits_us = TIME_QUANTUM_USEC;

	    if (th->priority > 0)
		limits_us <<= th->priority;
	    else
		limits_us >>= -th->priority;

	    if (th->status == THREAD_RUNNABLE)
		th->running_time_us += TIME_QUANTUM_USEC;

	    EXEC_EVENT_HOOK(th, RUBY_INTERNAL_EVENT_SWITCH, th->cfp->self, 0, 0, 0, Qundef);

	    rb_thread_schedule_limits(limits_us);
	}
    }
}

void
rb_thread_execute_interrupts(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    rb_threadptr_execute_interrupts(th, 1);
}

static void
rb_threadptr_ready(rb_thread_t *th)
{
    rb_threadptr_interrupt(th);
}

void rb_threadptr_setup_exception(rb_thread_t *th, VALUE mesg, VALUE cause);

static VALUE
rb_threadptr_raise(rb_thread_t *th, int argc, VALUE *argv)
{
    VALUE exc;

    if (rb_threadptr_dead(th)) {
	return Qnil;
    }

    if (argc == 0) {
	exc = rb_exc_new(rb_eRuntimeError, 0, 0);
    }
    else {
	exc = rb_make_exception(argc, argv);
    }

    /* making an exception object can switch thread,
       so we need to check thread deadness again */
    if (rb_threadptr_dead(th)) {
	return Qnil;
    }

    rb_threadptr_setup_exception(GET_THREAD(), exc, Qundef);
    rb_threadptr_pending_interrupt_enque(th, exc);
    rb_threadptr_interrupt(th);
    return Qnil;
}

void
rb_threadptr_signal_raise(rb_thread_t *th, int sig)
{
    VALUE argv[2];

    argv[0] = rb_eSignal;
    argv[1] = INT2FIX(sig);
    rb_threadptr_raise(th->vm->main_thread, 2, argv);
}

void
rb_threadptr_signal_exit(rb_thread_t *th)
{
    VALUE argv[2];

    argv[0] = rb_eSystemExit;
    argv[1] = rb_str_new2("exit");
    rb_threadptr_raise(th->vm->main_thread, 2, argv);
}

#if defined(POSIX_SIGNAL) && defined(SIGSEGV) && defined(HAVE_SIGALTSTACK)
#define USE_SIGALTSTACK
#endif

NORETURN(void ruby_thread_stack_overflow(rb_thread_t *th));
void
ruby_thread_stack_overflow(rb_thread_t *th)
{
    th->raised_flag = 0;
#ifdef USE_SIGALTSTACK
    if (!rb_during_gc()) {
	rb_exc_raise(sysstack_error);
    }
#endif
    th->errinfo = sysstack_error;
    TH_JUMP_TAG(th, TAG_RAISE);
}

int
rb_threadptr_set_raised(rb_thread_t *th)
{
    if (th->raised_flag & RAISED_EXCEPTION) {
	return 1;
    }
    th->raised_flag |= RAISED_EXCEPTION;
    return 0;
}

int
rb_threadptr_reset_raised(rb_thread_t *th)
{
    if (!(th->raised_flag & RAISED_EXCEPTION)) {
	return 0;
    }
    th->raised_flag &= ~RAISED_EXCEPTION;
    return 1;
}

int
rb_notify_fd_close(int fd)
{
    rb_vm_t *vm = GET_THREAD()->vm;
    rb_thread_t *th = 0;
    int busy;

    busy = 0;
    list_for_each(&vm->living_threads, th, vmlt_node) {
	if (th->waiting_fd == fd) {
	    VALUE err = th->vm->special_exceptions[ruby_error_closed_stream];
	    rb_threadptr_pending_interrupt_enque(th, err);
	    rb_threadptr_interrupt(th);
	    busy = 1;
	}
    }
    return busy;
}

void
rb_thread_fd_close(int fd)
{
    while (rb_notify_fd_close(fd));
}

/*
 *  call-seq:
 *     thr.raise
 *     thr.raise(string)
 *     thr.raise(exception [, string [, array]])
 *
 *  Raises an exception from the given thread. The caller does not have to be
 *  +thr+. See Kernel#raise for more information.
 *
 *     Thread.abort_on_exception = true
 *     a = Thread.new { sleep(200) }
 *     a.raise("Gotcha")
 *
 *  This will produce:
 *
 *     prog.rb:3: Gotcha (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 */

static VALUE
thread_raise_m(int argc, VALUE *argv, VALUE self)
{
    rb_thread_t *target_th;
    rb_thread_t *th = GET_THREAD();
    GetThreadPtr(self, target_th);
    threadptr_check_pending_interrupt_queue(target_th);
    rb_threadptr_raise(target_th, argc, argv);

    /* To perform Thread.current.raise as Kernel.raise */
    if (th == target_th) {
	RUBY_VM_CHECK_INTS(th);
    }
    return Qnil;
}


/*
 *  call-seq:
 *     thr.exit        -> thr or nil
 *     thr.kill        -> thr or nil
 *     thr.terminate   -> thr or nil
 *
 *  Terminates +thr+ and schedules another thread to be run.
 *
 *  If this thread is already marked to be killed, #exit returns the Thread.
 *
 *  If this is the main thread, or the last thread, exits the process.
 */

VALUE
rb_thread_kill(VALUE thread)
{
    rb_thread_t *th;

    GetThreadPtr(thread, th);

    if (th->to_kill || th->status == THREAD_KILLED) {
	return thread;
    }
    if (th == th->vm->main_thread) {
	rb_exit(EXIT_SUCCESS);
    }

    thread_debug("rb_thread_kill: %p (%"PRI_THREAD_ID")\n", (void *)th, thread_id_str(th));

    if (th == GET_THREAD()) {
	/* kill myself immediately */
	rb_threadptr_to_kill(th);
    }
    else {
	threadptr_check_pending_interrupt_queue(th);
	rb_threadptr_pending_interrupt_enque(th, eKillSignal);
	rb_threadptr_interrupt(th);
    }
    return thread;
}

int
rb_thread_to_be_killed(VALUE thread)
{
    rb_thread_t *th;

    GetThreadPtr(thread, th);

    if (th->to_kill || th->status == THREAD_KILLED) {
	return TRUE;
    }
    return FALSE;
}

/*
 *  call-seq:
 *     Thread.kill(thread)   -> thread
 *
 *  Causes the given +thread+ to exit, see also Thread::exit.
 *
 *     count = 0
 *     a = Thread.new { loop { count += 1 } }
 *     sleep(0.1)       #=> 0
 *     Thread.kill(a)   #=> #<Thread:0x401b3d30 dead>
 *     count            #=> 93947
 *     a.alive?         #=> false
 */

static VALUE
rb_thread_s_kill(VALUE obj, VALUE th)
{
    return rb_thread_kill(th);
}


/*
 *  call-seq:
 *     Thread.exit   -> thread
 *
 *  Terminates the currently running thread and schedules another thread to be
 *  run.
 *
 *  If this thread is already marked to be killed, ::exit returns the Thread.
 *
 *  If this is the main thread, or the last  thread, exit the process.
 */

static VALUE
rb_thread_exit(void)
{
    rb_thread_t *th = GET_THREAD();
    return rb_thread_kill(th->self);
}


/*
 *  call-seq:
 *     thr.wakeup   -> thr
 *
 *  Marks a given thread as eligible for scheduling, however it may still
 *  remain blocked on I/O.
 *
 *  *Note:* This does not invoke the scheduler, see #run for more information.
 *
 *     c = Thread.new { Thread.stop; puts "hey!" }
 *     sleep 0.1 while c.status!='sleep'
 *     c.wakeup
 *     c.join
 *     #=> "hey!"
 */

VALUE
rb_thread_wakeup(VALUE thread)
{
    if (!RTEST(rb_thread_wakeup_alive(thread))) {
	rb_raise(rb_eThreadError, "killed thread");
    }
    return thread;
}

VALUE
rb_thread_wakeup_alive(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    if (th->status == THREAD_KILLED) {
	return Qnil;
    }
    rb_threadptr_ready(th);
    if (th->status == THREAD_STOPPED || th->status == THREAD_STOPPED_FOREVER)
	th->status = THREAD_RUNNABLE;
    return thread;
}


/*
 *  call-seq:
 *     thr.run   -> thr
 *
 *  Wakes up +thr+, making it eligible for scheduling.
 *
 *     a = Thread.new { puts "a"; Thread.stop; puts "c" }
 *     sleep 0.1 while a.status!='sleep'
 *     puts "Got here"
 *     a.run
 *     a.join
 *
 *  This will produce:
 *
 *     a
 *     Got here
 *     c
 *
 *  See also the instance method #wakeup.
 */

VALUE
rb_thread_run(VALUE thread)
{
    rb_thread_wakeup(thread);
    rb_thread_schedule();
    return thread;
}


/*
 *  call-seq:
 *     Thread.stop   -> nil
 *
 *  Stops execution of the current thread, putting it into a ``sleep'' state,
 *  and schedules execution of another thread.
 *
 *     a = Thread.new { print "a"; Thread.stop; print "c" }
 *     sleep 0.1 while a.status!='sleep'
 *     print "b"
 *     a.run
 *     a.join
 *     #=> "abc"
 */

VALUE
rb_thread_stop(void)
{
    if (rb_thread_alone()) {
	rb_raise(rb_eThreadError,
		 "stopping only thread\n\tnote: use sleep to stop forever");
    }
    rb_thread_sleep_deadly();
    return Qnil;
}

/********************************************************************/

/*
 *  call-seq:
 *     Thread.list   -> array
 *
 *  Returns an array of Thread objects for all threads that are either runnable
 *  or stopped.
 *
 *     Thread.new { sleep(200) }
 *     Thread.new { 1000000.times {|i| i*i } }
 *     Thread.new { Thread.stop }
 *     Thread.list.each {|t| p t}
 *
 *  This will produce:
 *
 *     #<Thread:0x401b3e84 sleep>
 *     #<Thread:0x401b3f38 run>
 *     #<Thread:0x401b3fb0 sleep>
 *     #<Thread:0x401bdf4c run>
 */

VALUE
rb_thread_list(void)
{
    VALUE ary = rb_ary_new();
    rb_vm_t *vm = GET_THREAD()->vm;
    rb_thread_t *th = 0;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	switch (th->status) {
	  case THREAD_RUNNABLE:
	  case THREAD_STOPPED:
	  case THREAD_STOPPED_FOREVER:
	    rb_ary_push(ary, th->self);
	  default:
	    break;
	}
    }
    return ary;
}

VALUE
rb_thread_current(void)
{
    return GET_THREAD()->self;
}

/*
 *  call-seq:
 *     Thread.current   -> thread
 *
 *  Returns the currently executing thread.
 *
 *     Thread.current   #=> #<Thread:0x401bdf4c run>
 */

static VALUE
thread_s_current(VALUE klass)
{
    return rb_thread_current();
}

VALUE
rb_thread_main(void)
{
    return GET_THREAD()->vm->main_thread->self;
}

/*
 *  call-seq:
 *     Thread.main   -> thread
 *
 *  Returns the main thread.
 */

static VALUE
rb_thread_s_main(VALUE klass)
{
    return rb_thread_main();
}


/*
 *  call-seq:
 *     Thread.abort_on_exception   -> true or false
 *
 *  Returns the status of the global ``abort on exception'' condition.
 *
 *  The default is +false+.
 *
 *  When set to +true+, if any thread is aborted by an exception, the
 *  raised exception will be re-raised in the main thread.
 *
 *  Can also be specified by the global $DEBUG flag or command line option
 *  +-d+.
 *
 *  See also ::abort_on_exception=.
 *
 *  There is also an instance level method to set this for a specific thread,
 *  see #abort_on_exception.
 */

static VALUE
rb_thread_s_abort_exc(void)
{
    return GET_THREAD()->vm->thread_abort_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     Thread.abort_on_exception= boolean   -> true or false
 *
 *  When set to +true+, if any thread is aborted by an exception, the
 *  raised exception will be re-raised in the main thread.
 *  Returns the new state.
 *
 *     Thread.abort_on_exception = true
 *     t1 = Thread.new do
 *       puts  "In new thread"
 *       raise "Exception from thread"
 *     end
 *     sleep(1)
 *     puts "not reached"
 *
 *  This will produce:
 *
 *     In new thread
 *     prog.rb:4: Exception from thread (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 *
 *  See also ::abort_on_exception.
 *
 *  There is also an instance level method to set this for a specific thread,
 *  see #abort_on_exception=.
 */

static VALUE
rb_thread_s_abort_exc_set(VALUE self, VALUE val)
{
    GET_THREAD()->vm->thread_abort_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.abort_on_exception   -> true or false
 *
 *  Returns the status of the thread-local ``abort on exception'' condition for
 *  this +thr+.
 *
 *  The default is +false+.
 *
 *  See also #abort_on_exception=.
 *
 *  There is also a class level method to set this for all threads, see
 *  ::abort_on_exception.
 */

static VALUE
rb_thread_abort_exc(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    return th->abort_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     thr.abort_on_exception= boolean   -> true or false
 *
 *  When set to +true+, if this +thr+ is aborted by an exception, the
 *  raised exception will be re-raised in the main thread.
 *
 *  See also #abort_on_exception.
 *
 *  There is also a class level method to set this for all threads, see
 *  ::abort_on_exception=.
 */

static VALUE
rb_thread_abort_exc_set(VALUE thread, VALUE val)
{
    rb_thread_t *th;

    GetThreadPtr(thread, th);
    th->abort_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     Thread.report_on_exception   -> true or false
 *
 *  Returns the status of the global ``report on exception'' condition.
 *
 *  The default is +false+.
 *
 *  When set to +true+, all threads will report the exception if an
 *  exception is raised in any thread.
 *
 *  See also ::report_on_exception=.
 *
 *  There is also an instance level method to set this for a specific thread,
 *  see #report_on_exception.
 */

static VALUE
rb_thread_s_report_exc(void)
{
    return GET_THREAD()->vm->thread_report_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     Thread.report_on_exception= boolean   -> true or false
 *
 *  When set to +true+, all threads will report the exception if an
 *  exception is raised.  Returns the new state.
 *
 *     Thread.report_on_exception = true
 *     t1 = Thread.new do
 *       puts  "In new thread"
 *       raise "Exception from thread"
 *     end
 *     sleep(1)
 *     puts "In the main thread"
 *
 *  This will produce:
 *
 *     In new thread
 *     prog.rb:4: Exception from thread (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 *     In the main thread
 *
 *  See also ::report_on_exception.
 *
 *  There is also an instance level method to set this for a specific thread,
 *  see #report_on_exception=.
 */

static VALUE
rb_thread_s_report_exc_set(VALUE self, VALUE val)
{
    GET_THREAD()->vm->thread_report_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.report_on_exception   -> true or false
 *
 *  Returns the status of the thread-local ``report on exception'' condition for
 *  this +thr+.
 *
 *  The default is +false+.
 *
 *  See also #report_on_exception=.
 *
 *  There is also a class level method to set this for all threads, see
 *  ::report_on_exception.
 */

static VALUE
rb_thread_report_exc(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    return th->report_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     thr.report_on_exception= boolean   -> true or false
 *
 *  When set to +true+, all threads (including the main program) will
 *  report the exception if an exception is raised in this +thr+.
 *
 *  See also #report_on_exception.
 *
 *  There is also a class level method to set this for all threads, see
 *  ::report_on_exception=.
 */

static VALUE
rb_thread_report_exc_set(VALUE thread, VALUE val)
{
    rb_thread_t *th;

    GetThreadPtr(thread, th);
    th->report_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.group   -> thgrp or nil
 *
 *  Returns the ThreadGroup which contains the given thread, or returns +nil+
 *  if +thr+ is not a member of any group.
 *
 *     Thread.main.group   #=> #<ThreadGroup:0x4029d914>
 */

VALUE
rb_thread_group(VALUE thread)
{
    rb_thread_t *th;
    VALUE group;
    GetThreadPtr(thread, th);
    group = th->thgroup;

    if (!group) {
	group = Qnil;
    }
    return group;
}

static const char *
thread_status_name(rb_thread_t *th, int detail)
{
    switch (th->status) {
      case THREAD_RUNNABLE:
	if (th->to_kill)
	    return "aborting";
	else
	    return "run";
      case THREAD_STOPPED_FOREVER:
	if (detail) return "sleep_forever";
      case THREAD_STOPPED:
	return "sleep";
      case THREAD_KILLED:
	return "dead";
      default:
	return "unknown";
    }
}

static int
rb_threadptr_dead(rb_thread_t *th)
{
    return th->status == THREAD_KILLED;
}


/*
 *  call-seq:
 *     thr.status   -> string, false or nil
 *
 *  Returns the status of +thr+.
 *
 *  [<tt>"sleep"</tt>]
 *	Returned if this thread is sleeping or waiting on I/O
 *  [<tt>"run"</tt>]
 *	When this thread is executing
 *  [<tt>"aborting"</tt>]
 *	If this thread is aborting
 *  [+false+]
 *	When this thread is terminated normally
 *  [+nil+]
 *	If terminated with an exception.
 *
 *     a = Thread.new { raise("die now") }
 *     b = Thread.new { Thread.stop }
 *     c = Thread.new { Thread.exit }
 *     d = Thread.new { sleep }
 *     d.kill                  #=> #<Thread:0x401b3678 aborting>
 *     a.status                #=> nil
 *     b.status                #=> "sleep"
 *     c.status                #=> false
 *     d.status                #=> "aborting"
 *     Thread.current.status   #=> "run"
 *
 *  See also the instance methods #alive? and #stop?
 */

static VALUE
rb_thread_status(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_threadptr_dead(th)) {
	if (!NIL_P(th->errinfo) && !FIXNUM_P(th->errinfo)
	    /* TODO */ ) {
	    return Qnil;
	}
	return Qfalse;
    }
    return rb_str_new2(thread_status_name(th, FALSE));
}


/*
 *  call-seq:
 *     thr.alive?   -> true or false
 *
 *  Returns +true+ if +thr+ is running or sleeping.
 *
 *     thr = Thread.new { }
 *     thr.join                #=> #<Thread:0x401b3fb0 dead>
 *     Thread.current.alive?   #=> true
 *     thr.alive?              #=> false
 *
 *  See also #stop? and #status.
 */

static VALUE
rb_thread_alive_p(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_threadptr_dead(th))
	return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     thr.stop?   -> true or false
 *
 *  Returns +true+ if +thr+ is dead or sleeping.
 *
 *     a = Thread.new { Thread.stop }
 *     b = Thread.current
 *     a.stop?   #=> true
 *     b.stop?   #=> false
 *
 *  See also #alive? and #status.
 */

static VALUE
rb_thread_stop_p(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_threadptr_dead(th))
	return Qtrue;
    if (th->status == THREAD_STOPPED || th->status == THREAD_STOPPED_FOREVER)
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     thr.safe_level   -> integer
 *
 *  Returns the safe level in effect for <i>thr</i>. Setting thread-local safe
 *  levels can help when implementing sandboxes which run insecure code.
 *
 *     thr = Thread.new { $SAFE = 1; sleep }
 *     Thread.current.safe_level   #=> 0
 *     thr.safe_level              #=> 1
 */

static VALUE
rb_thread_safe_level(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    return INT2NUM(th->safe_level);
}

/*
 * call-seq:
 *   thr.name   -> string
 *
 * show the name of the thread.
 */

static VALUE
rb_thread_getname(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    return th->name;
}

/*
 * call-seq:
 *   thr.name=(name)   -> string
 *
 * set given name to the ruby thread.
 * On some platform, it may set the name to pthread and/or kernel.
 */

static VALUE
rb_thread_setname(VALUE thread, VALUE name)
{
#ifdef SET_ANOTHER_THREAD_NAME
    const char *s = "";
#endif
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    if (!NIL_P(name)) {
	rb_encoding *enc;
	StringValueCStr(name);
	enc = rb_enc_get(name);
	if (!rb_enc_asciicompat(enc)) {
	    rb_raise(rb_eArgError, "ASCII incompatible encoding (%s)",
		     rb_enc_name(enc));
	}
	name = rb_str_new_frozen(name);
#ifdef SET_ANOTHER_THREAD_NAME
	s = RSTRING_PTR(name);
#endif
    }
    th->name = name;
#if defined(SET_ANOTHER_THREAD_NAME)
    if (threadptr_initialized(th)) {
	SET_ANOTHER_THREAD_NAME(th->thread_id, s);
    }
#endif
    return name;
}

/*
 * call-seq:
 *   thr.inspect   -> string
 *
 * Dump the name, id, and status of _thr_ to a string.
 */

static VALUE
rb_thread_inspect(VALUE thread)
{
    VALUE cname = rb_class_path(rb_obj_class(thread));
    rb_thread_t *th;
    const char *status;
    VALUE str;

    GetThreadPtr(thread, th);
    status = thread_status_name(th, TRUE);
    str = rb_sprintf("#<%"PRIsVALUE":%p", cname, (void *)thread);
    if (!NIL_P(th->name)) {
	rb_str_catf(str, "@%"PRIsVALUE, th->name);
    }
    if (!th->first_func && th->first_proc) {
	VALUE loc = rb_proc_location(th->first_proc);
	if (!NIL_P(loc)) {
	    const VALUE *ptr = RARRAY_CONST_PTR(loc);
	    rb_str_catf(str, "@%"PRIsVALUE":%"PRIsVALUE, ptr[0], ptr[1]);
	    rb_gc_force_recycle(loc);
	}
    }
    rb_str_catf(str, " %s>", status);
    OBJ_INFECT(str, thread);

    return str;
}

/* variables for recursive traversals */
static ID recursive_key;

static VALUE
threadptr_local_aref(rb_thread_t *th, ID id)
{
    if (id == recursive_key) {
	return th->local_storage_recursive_hash;
    }
    else {
	st_data_t val;

	if (th->local_storage && st_lookup(th->local_storage, id, &val)) {
	    return (VALUE)val;
	}
	else {
	    return Qnil;
	}
    }
}

VALUE
rb_thread_local_aref(VALUE thread, ID id)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    return threadptr_local_aref(th, id);
}

/*
 *  call-seq:
 *      thr[sym]   -> obj or nil
 *
 *  Attribute Reference---Returns the value of a fiber-local variable (current thread's root fiber
 *  if not explicitly inside a Fiber), using either a symbol or a string name.
 *  If the specified variable does not exist, returns +nil+.
 *
 *     [
 *       Thread.new { Thread.current["name"] = "A" },
 *       Thread.new { Thread.current[:name]  = "B" },
 *       Thread.new { Thread.current["name"] = "C" }
 *     ].each do |th|
 *       th.join
 *       puts "#{th.inspect}: #{th[:name]}"
 *     end
 *
 *  This will produce:
 *
 *     #<Thread:0x00000002a54220 dead>: A
 *     #<Thread:0x00000002a541a8 dead>: B
 *     #<Thread:0x00000002a54130 dead>: C
 *
 *  Thread#[] and Thread#[]= are not thread-local but fiber-local.
 *  This confusion did not exist in Ruby 1.8 because
 *  fibers are only available since Ruby 1.9.
 *  Ruby 1.9 chooses that the methods behaves fiber-local to save
 *  following idiom for dynamic scope.
 *
 *    def meth(newvalue)
 *      begin
 *        oldvalue = Thread.current[:name]
 *        Thread.current[:name] = newvalue
 *        yield
 *      ensure
 *        Thread.current[:name] = oldvalue
 *      end
 *    end
 *
 *  The idiom may not work as dynamic scope if the methods are thread-local
 *  and a given block switches fiber.
 *
 *    f = Fiber.new {
 *      meth(1) {
 *        Fiber.yield
 *      }
 *    }
 *    meth(2) {
 *      f.resume
 *    }
 *    f.resume
 *    p Thread.current[:name]
 *    #=> nil if fiber-local
 *    #=> 2 if thread-local (The value 2 is leaked to outside of meth method.)
 *
 *  For thread-local variables, please see #thread_variable_get and
 *  #thread_variable_set.
 *
 */

static VALUE
rb_thread_aref(VALUE thread, VALUE key)
{
    ID id = rb_check_id(&key);
    if (!id) return Qnil;
    return rb_thread_local_aref(thread, id);
}

static VALUE
threadptr_local_aset(rb_thread_t *th, ID id, VALUE val)
{
    if (id == recursive_key) {
	th->local_storage_recursive_hash = val;
	return val;
    }
    else if (NIL_P(val)) {
	if (!th->local_storage) return Qnil;
	st_delete_wrap(th->local_storage, id);
	return Qnil;
    }
    else {
	if (!th->local_storage) {
	    th->local_storage = st_init_numtable();
	}
	st_insert(th->local_storage, id, val);
	return val;
    }
}

VALUE
rb_thread_local_aset(VALUE thread, ID id, VALUE val)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);

    if (OBJ_FROZEN(thread)) {
	rb_error_frozen("thread locals");
    }

    return threadptr_local_aset(th, id, val);
}

/*
 *  call-seq:
 *      thr[sym] = obj   -> obj
 *
 *  Attribute Assignment---Sets or creates the value of a fiber-local variable,
 *  using either a symbol or a string.
 *
 *  See also Thread#[].
 *
 *  For thread-local variables, please see #thread_variable_set and
 *  #thread_variable_get.
 */

static VALUE
rb_thread_aset(VALUE self, VALUE id, VALUE val)
{
    return rb_thread_local_aset(self, rb_to_id(id), val);
}

/*
 *  call-seq:
 *      thr.thread_variable_get(key)  -> obj or nil
 *
 *  Returns the value of a thread local variable that has been set.  Note that
 *  these are different than fiber local values.  For fiber local values,
 *  please see Thread#[] and Thread#[]=.
 *
 *  Thread local values are carried along with threads, and do not respect
 *  fibers.  For example:
 *
 *    Thread.new {
 *      Thread.current.thread_variable_set("foo", "bar") # set a thread local
 *      Thread.current["foo"] = "bar"                    # set a fiber local
 *
 *      Fiber.new {
 *        Fiber.yield [
 *          Thread.current.thread_variable_get("foo"), # get the thread local
 *          Thread.current["foo"],                     # get the fiber local
 *        ]
 *      }.resume
 *    }.join.value # => ['bar', nil]
 *
 *  The value "bar" is returned for the thread local, where nil is returned
 *  for the fiber local.  The fiber is executed in the same thread, so the
 *  thread local values are available.
 */

static VALUE
rb_thread_variable_get(VALUE thread, VALUE key)
{
    VALUE locals;

    locals = rb_ivar_get(thread, id_locals);
    return rb_hash_aref(locals, rb_to_symbol(key));
}

/*
 *  call-seq:
 *      thr.thread_variable_set(key, value)
 *
 *  Sets a thread local with +key+ to +value+.  Note that these are local to
 *  threads, and not to fibers.  Please see Thread#thread_variable_get and
 *  Thread#[] for more information.
 */

static VALUE
rb_thread_variable_set(VALUE thread, VALUE id, VALUE val)
{
    VALUE locals;

    if (OBJ_FROZEN(thread)) {
	rb_error_frozen("thread locals");
    }

    locals = rb_ivar_get(thread, id_locals);
    return rb_hash_aset(locals, rb_to_symbol(id), val);
}

/*
 *  call-seq:
 *     thr.key?(sym)   -> true or false
 *
 *  Returns +true+ if the given string (or symbol) exists as a fiber-local
 *  variable.
 *
 *     me = Thread.current
 *     me[:oliver] = "a"
 *     me.key?(:oliver)    #=> true
 *     me.key?(:stanley)   #=> false
 */

static VALUE
rb_thread_key_p(VALUE self, VALUE key)
{
    rb_thread_t *th;
    ID id = rb_check_id(&key);

    GetThreadPtr(self, th);

    if (!id || !th->local_storage) {
	return Qfalse;
    }
    if (st_lookup(th->local_storage, id, 0)) {
	return Qtrue;
    }
    return Qfalse;
}

static int
thread_keys_i(ID key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, ID2SYM(key));
    return ST_CONTINUE;
}

int
rb_thread_alone(void)
{
    return vm_living_thread_num(GET_VM()) == 1;
}

/*
 *  call-seq:
 *     thr.keys   -> array
 *
 *  Returns an array of the names of the fiber-local variables (as Symbols).
 *
 *     thr = Thread.new do
 *       Thread.current[:cat] = 'meow'
 *       Thread.current["dog"] = 'woof'
 *     end
 *     thr.join   #=> #<Thread:0x401b3f10 dead>
 *     thr.keys   #=> [:dog, :cat]
 */

static VALUE
rb_thread_keys(VALUE self)
{
    rb_thread_t *th;
    VALUE ary = rb_ary_new();
    GetThreadPtr(self, th);

    if (th->local_storage) {
	st_foreach(th->local_storage, thread_keys_i, ary);
    }
    return ary;
}

static int
keys_i(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     thr.thread_variables   -> array
 *
 *  Returns an array of the names of the thread-local variables (as Symbols).
 *
 *     thr = Thread.new do
 *       Thread.current.thread_variable_set(:cat, 'meow')
 *       Thread.current.thread_variable_set("dog", 'woof')
 *     end
 *     thr.join               #=> #<Thread:0x401b3f10 dead>
 *     thr.thread_variables   #=> [:dog, :cat]
 *
 *  Note that these are not fiber local variables.  Please see Thread#[] and
 *  Thread#thread_variable_get for more details.
 */

static VALUE
rb_thread_variables(VALUE thread)
{
    VALUE locals;
    VALUE ary;

    locals = rb_ivar_get(thread, id_locals);
    ary = rb_ary_new();
    rb_hash_foreach(locals, keys_i, ary);

    return ary;
}

/*
 *  call-seq:
 *     thr.thread_variable?(key)   -> true or false
 *
 *  Returns +true+ if the given string (or symbol) exists as a thread-local
 *  variable.
 *
 *     me = Thread.current
 *     me.thread_variable_set(:oliver, "a")
 *     me.thread_variable?(:oliver)    #=> true
 *     me.thread_variable?(:stanley)   #=> false
 *
 *  Note that these are not fiber local variables.  Please see Thread#[] and
 *  Thread#thread_variable_get for more details.
 */

static VALUE
rb_thread_variable_p(VALUE thread, VALUE key)
{
    VALUE locals;
    ID id = rb_check_id(&key);

    if (!id) return Qfalse;

    locals = rb_ivar_get(thread, id_locals);

    if (!RHASH(locals)->ntbl)
        return Qfalse;

    if (st_lookup(RHASH(locals)->ntbl, ID2SYM(id), 0)) {
	return Qtrue;
    }

    return Qfalse;
}

/*
 *  call-seq:
 *     thr.priority   -> integer
 *
 *  Returns the priority of <i>thr</i>. Default is inherited from the
 *  current thread which creating the new thread, or zero for the
 *  initial main thread; higher-priority thread will run more frequently
 *  than lower-priority threads (but lower-priority threads can also run).
 *
 *  This is just hint for Ruby thread scheduler.  It may be ignored on some
 *  platform.
 *
 *     Thread.current.priority   #=> 0
 */

static VALUE
rb_thread_priority(VALUE thread)
{
    rb_thread_t *th;
    GetThreadPtr(thread, th);
    return INT2NUM(th->priority);
}


/*
 *  call-seq:
 *     thr.priority= integer   -> thr
 *
 *  Sets the priority of <i>thr</i> to <i>integer</i>. Higher-priority threads
 *  will run more frequently than lower-priority threads (but lower-priority
 *  threads can also run).
 *
 *  This is just hint for Ruby thread scheduler.  It may be ignored on some
 *  platform.
 *
 *     count1 = count2 = 0
 *     a = Thread.new do
 *           loop { count1 += 1 }
 *         end
 *     a.priority = -1
 *
 *     b = Thread.new do
 *           loop { count2 += 1 }
 *         end
 *     b.priority = -2
 *     sleep 1   #=> 1
 *     count1    #=> 622504
 *     count2    #=> 5832
 */

static VALUE
rb_thread_priority_set(VALUE thread, VALUE prio)
{
    rb_thread_t *th;
    int priority;
    GetThreadPtr(thread, th);


#if USE_NATIVE_THREAD_PRIORITY
    th->priority = NUM2INT(prio);
    native_thread_apply_priority(th);
#else
    priority = NUM2INT(prio);
    if (priority > RUBY_THREAD_PRIORITY_MAX) {
	priority = RUBY_THREAD_PRIORITY_MAX;
    }
    else if (priority < RUBY_THREAD_PRIORITY_MIN) {
	priority = RUBY_THREAD_PRIORITY_MIN;
    }
    th->priority = priority;
#endif
    return INT2NUM(th->priority);
}

/* for IO */

#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)

/*
 * several Unix platforms support file descriptors bigger than FD_SETSIZE
 * in select(2) system call.
 *
 * - Linux 2.2.12 (?)
 * - NetBSD 1.2 (src/sys/kern/sys_generic.c:1.25)
 *   select(2) documents how to allocate fd_set dynamically.
 *   http://netbsd.gw.com/cgi-bin/man-cgi?select++NetBSD-4.0
 * - FreeBSD 2.2 (src/sys/kern/sys_generic.c:1.19)
 * - OpenBSD 2.0 (src/sys/kern/sys_generic.c:1.4)
 *   select(2) documents how to allocate fd_set dynamically.
 *   http://www.openbsd.org/cgi-bin/man.cgi?query=select&manpath=OpenBSD+4.4
 * - HP-UX documents how to allocate fd_set dynamically.
 *   http://docs.hp.com/en/B2355-60105/select.2.html
 * - Solaris 8 has select_large_fdset
 * - Mac OS X 10.7 (Lion)
 *   select(2) returns EINVAL if nfds is greater than FD_SET_SIZE and
 *   _DARWIN_UNLIMITED_SELECT (or _DARWIN_C_SOURCE) isn't defined.
 *   http://developer.apple.com/library/mac/#releasenotes/Darwin/SymbolVariantsRelNotes/_index.html
 *
 * When fd_set is not big enough to hold big file descriptors,
 * it should be allocated dynamically.
 * Note that this assumes fd_set is structured as bitmap.
 *
 * rb_fd_init allocates the memory.
 * rb_fd_term free the memory.
 * rb_fd_set may re-allocates bitmap.
 *
 * So rb_fd_set doesn't reject file descriptors bigger than FD_SETSIZE.
 */

void
rb_fd_init(rb_fdset_t *fds)
{
    fds->maxfd = 0;
    fds->fdset = ALLOC(fd_set);
    FD_ZERO(fds->fdset);
}

void
rb_fd_init_copy(rb_fdset_t *dst, rb_fdset_t *src)
{
    size_t size = howmany(rb_fd_max(src), NFDBITS) * sizeof(fd_mask);

    if (size < sizeof(fd_set))
	size = sizeof(fd_set);
    dst->maxfd = src->maxfd;
    dst->fdset = xmalloc(size);
    memcpy(dst->fdset, src->fdset, size);
}

void
rb_fd_term(rb_fdset_t *fds)
{
    if (fds->fdset) xfree(fds->fdset);
    fds->maxfd = 0;
    fds->fdset = 0;
}

void
rb_fd_zero(rb_fdset_t *fds)
{
    if (fds->fdset)
	MEMZERO(fds->fdset, fd_mask, howmany(fds->maxfd, NFDBITS));
}

static void
rb_fd_resize(int n, rb_fdset_t *fds)
{
    size_t m = howmany(n + 1, NFDBITS) * sizeof(fd_mask);
    size_t o = howmany(fds->maxfd, NFDBITS) * sizeof(fd_mask);

    if (m < sizeof(fd_set)) m = sizeof(fd_set);
    if (o < sizeof(fd_set)) o = sizeof(fd_set);

    if (m > o) {
	fds->fdset = xrealloc(fds->fdset, m);
	memset((char *)fds->fdset + o, 0, m - o);
    }
    if (n >= fds->maxfd) fds->maxfd = n + 1;
}

void
rb_fd_set(int n, rb_fdset_t *fds)
{
    rb_fd_resize(n, fds);
    FD_SET(n, fds->fdset);
}

void
rb_fd_clr(int n, rb_fdset_t *fds)
{
    if (n >= fds->maxfd) return;
    FD_CLR(n, fds->fdset);
}

int
rb_fd_isset(int n, const rb_fdset_t *fds)
{
    if (n >= fds->maxfd) return 0;
    return FD_ISSET(n, fds->fdset) != 0; /* "!= 0" avoids FreeBSD PR 91421 */
}

void
rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int max)
{
    size_t size = howmany(max, NFDBITS) * sizeof(fd_mask);

    if (size < sizeof(fd_set)) size = sizeof(fd_set);
    dst->maxfd = max;
    dst->fdset = xrealloc(dst->fdset, size);
    memcpy(dst->fdset, src, size);
}

void
rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src)
{
    size_t size = howmany(rb_fd_max(src), NFDBITS) * sizeof(fd_mask);

    if (size < sizeof(fd_set))
	size = sizeof(fd_set);
    dst->maxfd = src->maxfd;
    dst->fdset = xrealloc(dst->fdset, size);
    memcpy(dst->fdset, src->fdset, size);
}

#ifdef __native_client__
int select(int nfds, fd_set *readfds, fd_set *writefds,
           fd_set *exceptfds, struct timeval *timeout);
#endif

int
rb_fd_select(int n, rb_fdset_t *readfds, rb_fdset_t *writefds, rb_fdset_t *exceptfds, struct timeval *timeout)
{
    fd_set *r = NULL, *w = NULL, *e = NULL;
    if (readfds) {
        rb_fd_resize(n - 1, readfds);
        r = rb_fd_ptr(readfds);
    }
    if (writefds) {
        rb_fd_resize(n - 1, writefds);
        w = rb_fd_ptr(writefds);
    }
    if (exceptfds) {
        rb_fd_resize(n - 1, exceptfds);
        e = rb_fd_ptr(exceptfds);
    }
    return select(n, r, w, e, timeout);
}

#if defined __GNUC__ && __GNUC__ >= 6
#define rb_fd_no_init(fds) ASSUME(!(fds)->maxfd)
#endif

#undef FD_ZERO
#undef FD_SET
#undef FD_CLR
#undef FD_ISSET

#define FD_ZERO(f)	rb_fd_zero(f)
#define FD_SET(i, f)	rb_fd_set((i), (f))
#define FD_CLR(i, f)	rb_fd_clr((i), (f))
#define FD_ISSET(i, f)	rb_fd_isset((i), (f))

#elif defined(_WIN32)

void
rb_fd_init(rb_fdset_t *set)
{
    set->capa = FD_SETSIZE;
    set->fdset = ALLOC(fd_set);
    FD_ZERO(set->fdset);
}

void
rb_fd_init_copy(rb_fdset_t *dst, rb_fdset_t *src)
{
    rb_fd_init(dst);
    rb_fd_dup(dst, src);
}

void
rb_fd_term(rb_fdset_t *set)
{
    xfree(set->fdset);
    set->fdset = NULL;
    set->capa = 0;
}

void
rb_fd_set(int fd, rb_fdset_t *set)
{
    unsigned int i;
    SOCKET s = rb_w32_get_osfhandle(fd);

    for (i = 0; i < set->fdset->fd_count; i++) {
        if (set->fdset->fd_array[i] == s) {
            return;
        }
    }
    if (set->fdset->fd_count >= (unsigned)set->capa) {
	set->capa = (set->fdset->fd_count / FD_SETSIZE + 1) * FD_SETSIZE;
	set->fdset = xrealloc(set->fdset, sizeof(unsigned int) + sizeof(SOCKET) * set->capa);
    }
    set->fdset->fd_array[set->fdset->fd_count++] = s;
}

#undef FD_ZERO
#undef FD_SET
#undef FD_CLR
#undef FD_ISSET

#define FD_ZERO(f)	rb_fd_zero(f)
#define FD_SET(i, f)	rb_fd_set((i), (f))
#define FD_CLR(i, f)	rb_fd_clr((i), (f))
#define FD_ISSET(i, f)	rb_fd_isset((i), (f))

#endif

#ifndef rb_fd_no_init
#define rb_fd_no_init(fds) (void)(fds)
#endif

static inline int
retryable(int e)
{
    if (e == EINTR) return TRUE;
#ifdef ERESTART
    if (e == ERESTART) return TRUE;
#endif
    return FALSE;
}

#define restore_fdset(fds1, fds2) \
    ((fds1) ? rb_fd_dup(fds1, fds2) : (void)0)

static inline void
update_timeval(struct timeval *timeout, double limit)
{
    if (timeout) {
	double d = limit - timeofday();

	timeout->tv_sec = (time_t)d;
	timeout->tv_usec = (int)((d-(double)timeout->tv_sec)*1e6);
	if (timeout->tv_sec < 0)  timeout->tv_sec = 0;
	if (timeout->tv_usec < 0) timeout->tv_usec = 0;
    }
}

static int
do_select(int n, rb_fdset_t *readfds, rb_fdset_t *writefds,
	  rb_fdset_t *exceptfds, struct timeval *timeout)
{
    int MAYBE_UNUSED(result);
    int lerrno;
    rb_fdset_t MAYBE_UNUSED(orig_read);
    rb_fdset_t MAYBE_UNUSED(orig_write);
    rb_fdset_t MAYBE_UNUSED(orig_except);
    double limit = 0;
    struct timeval wait_rest;
    rb_thread_t *th = GET_THREAD();

#define do_select_update() \
    (restore_fdset(readfds, &orig_read), \
     restore_fdset(writefds, &orig_write), \
     restore_fdset(exceptfds, &orig_except), \
     update_timeval(timeout, limit), \
     TRUE)

    if (timeout) {
	limit = timeofday();
	limit += (double)timeout->tv_sec+(double)timeout->tv_usec*1e-6;
	wait_rest = *timeout;
	timeout = &wait_rest;
    }

#define fd_init_copy(f) \
    (f##fds) ? rb_fd_init_copy(&orig_##f, f##fds) : rb_fd_no_init(&orig_##f)
    fd_init_copy(read);
    fd_init_copy(write);
    fd_init_copy(except);
#undef fd_init_copy

    do {
	lerrno = 0;

	BLOCKING_REGION({
	    result = native_fd_select(n, readfds, writefds, exceptfds,
				      timeout, th);
	    if (result < 0) lerrno = errno;
	}, ubf_select, th, FALSE);

	RUBY_VM_CHECK_INTS_BLOCKING(th);
    } while (result < 0 && retryable(errno = lerrno) && do_select_update());

#define fd_term(f) if (f##fds) rb_fd_term(&orig_##f)
    fd_term(read);
    fd_term(write);
    fd_term(except);
#undef fd_term

    return result;
}

static void
rb_thread_wait_fd_rw(int fd, int read)
{
    int result = 0;
    int events = read ? RB_WAITFD_IN : RB_WAITFD_OUT;

    thread_debug("rb_thread_wait_fd_rw(%d, %s)\n", fd, read ? "read" : "write");

    if (fd < 0) {
	rb_raise(rb_eIOError, "closed stream");
    }

    result = rb_wait_for_single_fd(fd, events, NULL);
    if (result < 0) {
	rb_sys_fail(0);
    }

    thread_debug("rb_thread_wait_fd_rw(%d, %s): done\n", fd, read ? "read" : "write");
}

void
rb_thread_wait_fd(int fd)
{
    rb_thread_wait_fd_rw(fd, 1);
}

int
rb_thread_fd_writable(int fd)
{
    rb_thread_wait_fd_rw(fd, 0);
    return TRUE;
}

int
rb_thread_fd_select(int max, rb_fdset_t * read, rb_fdset_t * write, rb_fdset_t * except,
		    struct timeval *timeout)
{
    if (!read && !write && !except) {
	if (!timeout) {
	    rb_thread_sleep_forever();
	    return 0;
	}
	rb_thread_wait_for(*timeout);
	return 0;
    }

    if (read) {
	rb_fd_resize(max - 1, read);
    }
    if (write) {
	rb_fd_resize(max - 1, write);
    }
    if (except) {
	rb_fd_resize(max - 1, except);
    }
    return do_select(max, read, write, except, timeout);
}

/*
 * poll() is supported by many OSes, but so far Linux is the only
 * one we know of that supports using poll() in all places select()
 * would work.
 */
#if defined(HAVE_POLL) && defined(__linux__)
#  define USE_POLL
#endif

#ifdef USE_POLL

/* The same with linux kernel. TODO: make platform independent definition. */
#define POLLIN_SET (POLLRDNORM | POLLRDBAND | POLLIN | POLLHUP | POLLERR)
#define POLLOUT_SET (POLLWRBAND | POLLWRNORM | POLLOUT | POLLERR)
#define POLLEX_SET (POLLPRI)

#ifndef HAVE_PPOLL
/* TODO: don't ignore sigmask */
int
ppoll(struct pollfd *fds, nfds_t nfds,
      const struct timespec *ts, const sigset_t *sigmask)
{
    int timeout_ms;

    if (ts) {
	int tmp, tmp2;

	if (ts->tv_sec > INT_MAX/1000)
	    timeout_ms = -1;
	else {
	    tmp = (int)(ts->tv_sec * 1000);
	    tmp2 = (int)(ts->tv_nsec / (1000 * 1000));
	    if (INT_MAX - tmp < tmp2)
		timeout_ms = -1;
	    else
		timeout_ms = (int)(tmp + tmp2);
	}
    }
    else
	timeout_ms = -1;

    return poll(fds, nfds, timeout_ms);
}
#endif

static inline void
update_timespec(struct timespec *timeout, double limit)
{
    if (timeout) {
	double d = limit - timeofday();

	timeout->tv_sec = (long)d;
	timeout->tv_nsec = (long)((d-(double)timeout->tv_sec)*1e9);
	if (timeout->tv_sec < 0)  timeout->tv_sec = 0;
	if (timeout->tv_nsec < 0) timeout->tv_nsec = 0;
    }
}

/*
 * returns a mask of events
 */
int
rb_wait_for_single_fd(int fd, int events, struct timeval *tv)
{
    struct pollfd fds;
    int result = 0, lerrno;
    double limit = 0;
    struct timespec ts;
    struct timespec *timeout = NULL;
    rb_thread_t *th = GET_THREAD();

#define poll_update() \
    (update_timespec(timeout, limit), \
     TRUE)

    if (tv) {
	ts.tv_sec = tv->tv_sec;
	ts.tv_nsec = tv->tv_usec * 1000;
	limit = timeofday();
	limit += (double)tv->tv_sec + (double)tv->tv_usec * 1e-6;
	timeout = &ts;
    }

    fds.fd = fd;
    fds.events = (short)events;

    do {
	fds.revents = 0;
	lerrno = 0;
	BLOCKING_REGION({
	    result = ppoll(&fds, 1, timeout, NULL);
	    if (result < 0) lerrno = errno;
	}, ubf_select, th, FALSE);

	RUBY_VM_CHECK_INTS_BLOCKING(th);
    } while (result < 0 && retryable(errno = lerrno) && poll_update());
    if (result < 0) return -1;

    if (fds.revents & POLLNVAL) {
	errno = EBADF;
	return -1;
    }

    /*
     * POLLIN, POLLOUT have a different meanings from select(2)'s read/write bit.
     * Therefore we need to fix it up.
     */
    result = 0;
    if (fds.revents & POLLIN_SET)
	result |= RB_WAITFD_IN;
    if (fds.revents & POLLOUT_SET)
	result |= RB_WAITFD_OUT;
    if (fds.revents & POLLEX_SET)
	result |= RB_WAITFD_PRI;

    return result;
}
#else /* ! USE_POLL - implement rb_io_poll_fd() using select() */
static rb_fdset_t *
init_set_fd(int fd, rb_fdset_t *fds)
{
    rb_fd_init(fds);
    rb_fd_set(fd, fds);

    return fds;
}

struct select_args {
    union {
	int fd;
	int error;
    } as;
    rb_fdset_t *read;
    rb_fdset_t *write;
    rb_fdset_t *except;
    struct timeval *tv;
};

static VALUE
select_single(VALUE ptr)
{
    struct select_args *args = (struct select_args *)ptr;
    int r;

    r = rb_thread_fd_select(args->as.fd + 1,
                            args->read, args->write, args->except, args->tv);
    if (r == -1)
	args->as.error = errno;
    if (r > 0) {
	r = 0;
	if (args->read && rb_fd_isset(args->as.fd, args->read))
	    r |= RB_WAITFD_IN;
	if (args->write && rb_fd_isset(args->as.fd, args->write))
	    r |= RB_WAITFD_OUT;
	if (args->except && rb_fd_isset(args->as.fd, args->except))
	    r |= RB_WAITFD_PRI;
    }
    return (VALUE)r;
}

static VALUE
select_single_cleanup(VALUE ptr)
{
    struct select_args *args = (struct select_args *)ptr;

    if (args->read) rb_fd_term(args->read);
    if (args->write) rb_fd_term(args->write);
    if (args->except) rb_fd_term(args->except);

    return (VALUE)-1;
}

int
rb_wait_for_single_fd(int fd, int events, struct timeval *tv)
{
    rb_fdset_t rfds, wfds, efds;
    struct select_args args;
    int r;
    VALUE ptr = (VALUE)&args;

    args.as.fd = fd;
    args.read = (events & RB_WAITFD_IN) ? init_set_fd(fd, &rfds) : NULL;
    args.write = (events & RB_WAITFD_OUT) ? init_set_fd(fd, &wfds) : NULL;
    args.except = (events & RB_WAITFD_PRI) ? init_set_fd(fd, &efds) : NULL;
    args.tv = tv;

    r = (int)rb_ensure(select_single, ptr, select_single_cleanup, ptr);
    if (r == -1)
	errno = args.as.error;

    return r;
}
#endif /* ! USE_POLL */

/*
 * for GC
 */

#ifdef USE_CONSERVATIVE_STACK_END
void
rb_gc_set_stack_end(VALUE **stack_end_p)
{
    VALUE stack_end;
    *stack_end_p = &stack_end;
}
#endif


/*
 *
 */

void
rb_threadptr_check_signal(rb_thread_t *mth)
{
    /* mth must be main_thread */
    if (rb_signal_buff_size() > 0) {
	/* wakeup main thread */
	rb_threadptr_trap_interrupt(mth);
    }
}

static void
timer_thread_function(void *arg)
{
    rb_vm_t *vm = GET_VM(); /* TODO: fix me for Multi-VM */

    /*
     * Tricky: thread_destruct_lock doesn't close a race against
     * vm->running_thread switch. however it guarantees th->running_thread
     * point to valid pointer or NULL.
     */
    native_mutex_lock(&vm->thread_destruct_lock);
    /* for time slice */
    if (vm->running_thread)
	RUBY_VM_SET_TIMER_INTERRUPT(vm->running_thread);
    native_mutex_unlock(&vm->thread_destruct_lock);

    /* check signal */
    rb_threadptr_check_signal(vm->main_thread);

#if 0
    /* prove profiler */
    if (vm->prove_profile.enable) {
	rb_thread_t *th = vm->running_thread;

	if (vm->during_gc) {
	    /* GC prove profiling */
	}
    }
#endif
}

void
rb_thread_stop_timer_thread(void)
{
    if (TIMER_THREAD_CREATED_P() && native_stop_timer_thread()) {
	native_reset_timer_thread();
    }
}

void
rb_thread_reset_timer_thread(void)
{
    native_reset_timer_thread();
}

void
rb_thread_start_timer_thread(void)
{
    system_working = 1;
    rb_thread_create_timer_thread();
}

#if defined(HAVE_WORKING_FORK)
static int
clear_coverage_i(st_data_t key, st_data_t val, st_data_t dummy)
{
    int i;
    VALUE lines = (VALUE)val;

    for (i = 0; i < RARRAY_LEN(lines); i++) {
	if (RARRAY_AREF(lines, i) != Qnil) {
	    RARRAY_ASET(lines, i, INT2FIX(0));
	}
    }
    return ST_CONTINUE;
}

static void
clear_coverage(void)
{
    VALUE coverages = rb_get_coverages();
    if (RTEST(coverages)) {
	st_foreach(rb_hash_tbl_raw(coverages), clear_coverage_i, 0);
    }
}

static void
rb_thread_atfork_internal(rb_thread_t *th, void (*atfork)(rb_thread_t *, const rb_thread_t *))
{
    rb_thread_t *i = 0;
    rb_vm_t *vm = th->vm;
    vm->main_thread = th;

    gvl_atfork(th->vm);

    list_for_each(&vm->living_threads, i, vmlt_node) {
	atfork(i, th);
    }
    rb_vm_living_threads_init(vm);
    rb_vm_living_threads_insert(vm, th);
    vm->sleeper = 0;
    clear_coverage();
}

static void
terminate_atfork_i(rb_thread_t *th, const rb_thread_t *current_th)
{
    if (th != current_th) {
	rb_mutex_abandon_keeping_mutexes(th);
	rb_mutex_abandon_locking_mutex(th);
	thread_cleanup_func(th, TRUE);
    }
}

void
rb_thread_atfork(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_thread_atfork_internal(th, terminate_atfork_i);
    th->join_list = NULL;

    /* We don't want reproduce CVE-2003-0900. */
    rb_reset_random_seed();
}

static void
terminate_atfork_before_exec_i(rb_thread_t *th, const rb_thread_t *current_th)
{
    if (th != current_th) {
	thread_cleanup_func_before_exec(th);
    }
}

void
rb_thread_atfork_before_exec(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_thread_atfork_internal(th, terminate_atfork_before_exec_i);
}
#else
void
rb_thread_atfork(void)
{
}

void
rb_thread_atfork_before_exec(void)
{
}
#endif

struct thgroup {
    int enclosed;
    VALUE group;
};

static size_t
thgroup_memsize(const void *ptr)
{
    return sizeof(struct thgroup);
}

static const rb_data_type_t thgroup_data_type = {
    "thgroup",
    {NULL, RUBY_TYPED_DEFAULT_FREE, thgroup_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

/*
 * Document-class: ThreadGroup
 *
 *  ThreadGroup provides a means of keeping track of a number of threads as a
 *  group.
 *
 *  A given Thread object can only belong to one ThreadGroup at a time; adding
 *  a thread to a new group will remove it from any previous group.
 *
 *  Newly created threads belong to the same group as the thread from which they
 *  were created.
 */

/*
 * Document-const: Default
 *
 *  The default ThreadGroup created when Ruby starts; all Threads belong to it
 *  by default.
 */
static VALUE
thgroup_s_alloc(VALUE klass)
{
    VALUE group;
    struct thgroup *data;

    group = TypedData_Make_Struct(klass, struct thgroup, &thgroup_data_type, data);
    data->enclosed = 0;
    data->group = group;

    return group;
}

/*
 *  call-seq:
 *     thgrp.list   -> array
 *
 *  Returns an array of all existing Thread objects that belong to this group.
 *
 *     ThreadGroup::Default.list   #=> [#<Thread:0x401bdf4c run>]
 */

static VALUE
thgroup_list(VALUE group)
{
    VALUE ary = rb_ary_new();
    rb_vm_t *vm = GET_THREAD()->vm;
    rb_thread_t *th = 0;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	if (th->thgroup == group) {
	    rb_ary_push(ary, th->self);
	}
    }
    return ary;
}


/*
 *  call-seq:
 *     thgrp.enclose   -> thgrp
 *
 *  Prevents threads from being added to or removed from the receiving
 *  ThreadGroup.
 *
 *  New threads can still be started in an enclosed ThreadGroup.
 *
 *     ThreadGroup::Default.enclose        #=> #<ThreadGroup:0x4029d914>
 *     thr = Thread::new { Thread.stop }   #=> #<Thread:0x402a7210 sleep>
 *     tg = ThreadGroup::new               #=> #<ThreadGroup:0x402752d4>
 *     tg.add thr
 *     #=> ThreadError: can't move from the enclosed thread group
 */

static VALUE
thgroup_enclose(VALUE group)
{
    struct thgroup *data;

    TypedData_Get_Struct(group, struct thgroup, &thgroup_data_type, data);
    data->enclosed = 1;

    return group;
}


/*
 *  call-seq:
 *     thgrp.enclosed?   -> true or false
 *
 *  Returns +true+ if the +thgrp+ is enclosed. See also ThreadGroup#enclose.
 */

static VALUE
thgroup_enclosed_p(VALUE group)
{
    struct thgroup *data;

    TypedData_Get_Struct(group, struct thgroup, &thgroup_data_type, data);
    if (data->enclosed)
	return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     thgrp.add(thread)   -> thgrp
 *
 *  Adds the given +thread+ to this group, removing it from any other
 *  group to which it may have previously been a member.
 *
 *     puts "Initial group is #{ThreadGroup::Default.list}"
 *     tg = ThreadGroup.new
 *     t1 = Thread.new { sleep }
 *     t2 = Thread.new { sleep }
 *     puts "t1 is #{t1}"
 *     puts "t2 is #{t2}"
 *     tg.add(t1)
 *     puts "Initial group now #{ThreadGroup::Default.list}"
 *     puts "tg group now #{tg.list}"
 *
 *  This will produce:
 *
 *     Initial group is #<Thread:0x401bdf4c>
 *     t1 is #<Thread:0x401b3c90>
 *     t2 is #<Thread:0x401b3c18>
 *     Initial group now #<Thread:0x401b3c18>#<Thread:0x401bdf4c>
 *     tg group now #<Thread:0x401b3c90>
 */

static VALUE
thgroup_add(VALUE group, VALUE thread)
{
    rb_thread_t *th;
    struct thgroup *data;

    GetThreadPtr(thread, th);

    if (OBJ_FROZEN(group)) {
	rb_raise(rb_eThreadError, "can't move to the frozen thread group");
    }
    TypedData_Get_Struct(group, struct thgroup, &thgroup_data_type, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError, "can't move to the enclosed thread group");
    }

    if (!th->thgroup) {
	return Qnil;
    }

    if (OBJ_FROZEN(th->thgroup)) {
	rb_raise(rb_eThreadError, "can't move from the frozen thread group");
    }
    TypedData_Get_Struct(th->thgroup, struct thgroup, &thgroup_data_type, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError,
		 "can't move from the enclosed thread group");
    }

    th->thgroup = group;
    return group;
}

/*
 * Document-class: ThreadShield
 */
static void
thread_shield_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

static const rb_data_type_t thread_shield_data_type = {
    "thread_shield",
    {thread_shield_mark, 0, 0,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
thread_shield_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &thread_shield_data_type, (void *)mutex_alloc(0));
}

#define GetThreadShieldPtr(obj) ((VALUE)rb_check_typeddata((obj), &thread_shield_data_type))
#define THREAD_SHIELD_WAITING_MASK (FL_USER0|FL_USER1|FL_USER2|FL_USER3|FL_USER4|FL_USER5|FL_USER6|FL_USER7|FL_USER8|FL_USER9|FL_USER10|FL_USER11|FL_USER12|FL_USER13|FL_USER14|FL_USER15|FL_USER16|FL_USER17|FL_USER18|FL_USER19)
#define THREAD_SHIELD_WAITING_SHIFT (FL_USHIFT)
#define rb_thread_shield_waiting(b) (int)((RBASIC(b)->flags&THREAD_SHIELD_WAITING_MASK)>>THREAD_SHIELD_WAITING_SHIFT)

static inline void
rb_thread_shield_waiting_inc(VALUE b)
{
    unsigned int w = rb_thread_shield_waiting(b);
    w++;
    if (w > (unsigned int)(THREAD_SHIELD_WAITING_MASK>>THREAD_SHIELD_WAITING_SHIFT))
	rb_raise(rb_eRuntimeError, "waiting count overflow");
    RBASIC(b)->flags &= ~THREAD_SHIELD_WAITING_MASK;
    RBASIC(b)->flags |= ((VALUE)w << THREAD_SHIELD_WAITING_SHIFT);
}

static inline void
rb_thread_shield_waiting_dec(VALUE b)
{
    unsigned int w = rb_thread_shield_waiting(b);
    if (!w) rb_raise(rb_eRuntimeError, "waiting count underflow");
    w--;
    RBASIC(b)->flags &= ~THREAD_SHIELD_WAITING_MASK;
    RBASIC(b)->flags |= ((VALUE)w << THREAD_SHIELD_WAITING_SHIFT);
}

VALUE
rb_thread_shield_new(void)
{
    VALUE thread_shield = thread_shield_alloc(rb_cThreadShield);
    rb_mutex_lock((VALUE)DATA_PTR(thread_shield));
    return thread_shield;
}

/*
 * Wait a thread shield.
 *
 * Returns
 *  true:  acquired the thread shield
 *  false: the thread shield was destroyed and no other threads waiting
 *  nil:   the thread shield was destroyed but still in use
 */
VALUE
rb_thread_shield_wait(VALUE self)
{
    VALUE mutex = GetThreadShieldPtr(self);
    rb_mutex_t *m;

    if (!mutex) return Qfalse;
    GetMutexPtr(mutex, m);
    if (m->th == GET_THREAD()) return Qnil;
    rb_thread_shield_waiting_inc(self);
    rb_mutex_lock(mutex);
    rb_thread_shield_waiting_dec(self);
    if (DATA_PTR(self)) return Qtrue;
    rb_mutex_unlock(mutex);
    return rb_thread_shield_waiting(self) > 0 ? Qnil : Qfalse;
}

static VALUE
thread_shield_get_mutex(VALUE self)
{
    VALUE mutex = GetThreadShieldPtr(self);
    if (!mutex)
	rb_raise(rb_eThreadError, "destroyed thread shield - %p", (void *)self);
    return mutex;
}

/*
 * Release a thread shield, and return true if it has waiting threads.
 */
VALUE
rb_thread_shield_release(VALUE self)
{
    VALUE mutex = thread_shield_get_mutex(self);
    rb_mutex_unlock(mutex);
    return rb_thread_shield_waiting(self) > 0 ? Qtrue : Qfalse;
}

/*
 * Release and destroy a thread shield, and return true if it has waiting threads.
 */
VALUE
rb_thread_shield_destroy(VALUE self)
{
    VALUE mutex = thread_shield_get_mutex(self);
    DATA_PTR(self) = 0;
    rb_mutex_unlock(mutex);
    return rb_thread_shield_waiting(self) > 0 ? Qtrue : Qfalse;
}

static VALUE
threadptr_recursive_hash(rb_thread_t *th)
{
    return th->local_storage_recursive_hash;
}

static void
threadptr_recursive_hash_set(rb_thread_t *th, VALUE hash)
{
    th->local_storage_recursive_hash = hash;
}

ID rb_frame_last_func(void);

/*
 * Returns the current "recursive list" used to detect recursion.
 * This list is a hash table, unique for the current thread and for
 * the current __callee__.
 */

static VALUE
recursive_list_access(VALUE sym)
{
    rb_thread_t *th = GET_THREAD();
    VALUE hash = threadptr_recursive_hash(th);
    VALUE list;
    if (NIL_P(hash) || !RB_TYPE_P(hash, T_HASH)) {
	hash = rb_ident_hash_new();
	threadptr_recursive_hash_set(th, hash);
	list = Qnil;
    }
    else {
	list = rb_hash_aref(hash, sym);
    }
    if (NIL_P(list) || !RB_TYPE_P(list, T_HASH)) {
	list = rb_hash_new();
	rb_hash_aset(hash, sym, list);
    }
    return list;
}

/*
 * Returns Qtrue iff obj_id (or the pair <obj, paired_obj>) is already
 * in the recursion list.
 * Assumes the recursion list is valid.
 */

static VALUE
recursive_check(VALUE list, VALUE obj_id, VALUE paired_obj_id)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
  #define OBJ_ID_EQL(obj_id, other) ((obj_id) == (other))
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
  #define OBJ_ID_EQL(obj_id, other) (RB_TYPE_P((obj_id), T_BIGNUM) ? \
    rb_big_eql((obj_id), (other)) : ((obj_id) == (other)))
#endif

    VALUE pair_list = rb_hash_lookup2(list, obj_id, Qundef);
    if (pair_list == Qundef)
	return Qfalse;
    if (paired_obj_id) {
	if (!RB_TYPE_P(pair_list, T_HASH)) {
	    if (!OBJ_ID_EQL(paired_obj_id, pair_list))
		return Qfalse;
	}
	else {
	    if (NIL_P(rb_hash_lookup(pair_list, paired_obj_id)))
		return Qfalse;
	}
    }
    return Qtrue;
}

/*
 * Pushes obj_id (or the pair <obj_id, paired_obj_id>) in the recursion list.
 * For a single obj_id, it sets list[obj_id] to Qtrue.
 * For a pair, it sets list[obj_id] to paired_obj_id if possible,
 * otherwise list[obj_id] becomes a hash like:
 *   {paired_obj_id_1 => true, paired_obj_id_2 => true, ... }
 * Assumes the recursion list is valid.
 */

static void
recursive_push(VALUE list, VALUE obj, VALUE paired_obj)
{
    VALUE pair_list;

    if (!paired_obj) {
	rb_hash_aset(list, obj, Qtrue);
    }
    else if ((pair_list = rb_hash_lookup2(list, obj, Qundef)) == Qundef) {
	rb_hash_aset(list, obj, paired_obj);
    }
    else {
	if (!RB_TYPE_P(pair_list, T_HASH)){
	    VALUE other_paired_obj = pair_list;
	    pair_list = rb_hash_new();
	    rb_hash_aset(pair_list, other_paired_obj, Qtrue);
	    rb_hash_aset(list, obj, pair_list);
	}
	rb_hash_aset(pair_list, paired_obj, Qtrue);
    }
}

/*
 * Pops obj_id (or the pair <obj_id, paired_obj_id>) from the recursion list.
 * For a pair, if list[obj_id] is a hash, then paired_obj_id is
 * removed from the hash and no attempt is made to simplify
 * list[obj_id] from {only_one_paired_id => true} to only_one_paired_id
 * Assumes the recursion list is valid.
 */

static int
recursive_pop(VALUE list, VALUE obj, VALUE paired_obj)
{
    if (paired_obj) {
	VALUE pair_list = rb_hash_lookup2(list, obj, Qundef);
	if (pair_list == Qundef) {
	    return 0;
	}
	if (RB_TYPE_P(pair_list, T_HASH)) {
	    rb_hash_delete_entry(pair_list, paired_obj);
	    if (!RHASH_EMPTY_P(pair_list)) {
		return 1; /* keep hash until is empty */
	    }
	}
    }
    rb_hash_delete_entry(list, obj);
    return 1;
}

struct exec_recursive_params {
    VALUE (*func) (VALUE, VALUE, int);
    VALUE list;
    VALUE obj;
    VALUE objid;
    VALUE pairid;
    VALUE arg;
};

static VALUE
exec_recursive_i(RB_BLOCK_CALL_FUNC_ARGLIST(tag, data))
{
    struct exec_recursive_params *p = (void *)data;
    return (*p->func)(p->obj, p->arg, FALSE);
}

/*
 * Calls func(obj, arg, recursive), where recursive is non-zero if the
 * current method is called recursively on obj, or on the pair <obj, pairid>
 * If outer is 0, then the innermost func will be called with recursive set
 * to Qtrue, otherwise the outermost func will be called. In the latter case,
 * all inner func are short-circuited by throw.
 * Implementation details: the value thrown is the recursive list which is
 * proper to the current method and unlikely to be caught anywhere else.
 * list[recursive_key] is used as a flag for the outermost call.
 */

static VALUE
exec_recursive(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE pairid, VALUE arg, int outer)
{
    VALUE result = Qundef;
    const ID mid = rb_frame_last_func();
    const VALUE sym = mid ? ID2SYM(mid) : ID2SYM(idNULL);
    struct exec_recursive_params p;
    int outermost;
    p.list = recursive_list_access(sym);
    p.objid = rb_obj_id(obj);
    p.obj = obj;
    p.pairid = pairid;
    p.arg = arg;
    outermost = outer && !recursive_check(p.list, ID2SYM(recursive_key), 0);

    if (recursive_check(p.list, p.objid, pairid)) {
	if (outer && !outermost) {
	    rb_throw_obj(p.list, p.list);
	}
	return (*func)(obj, arg, TRUE);
    }
    else {
	int state;

	p.func = func;

	if (outermost) {
	    recursive_push(p.list, ID2SYM(recursive_key), 0);
	    recursive_push(p.list, p.objid, p.pairid);
	    result = rb_catch_protect(p.list, exec_recursive_i, (VALUE)&p, &state);
	    if (!recursive_pop(p.list, p.objid, p.pairid)) goto invalid;
	    if (!recursive_pop(p.list, ID2SYM(recursive_key), 0)) goto invalid;
	    if (state) JUMP_TAG(state);
	    if (result == p.list) {
		result = (*func)(obj, arg, TRUE);
	    }
	}
	else {
	    volatile VALUE ret = Qundef;
	    recursive_push(p.list, p.objid, p.pairid);
	    PUSH_TAG();
	    if ((state = EXEC_TAG()) == 0) {
		ret = (*func)(obj, arg, FALSE);
	    }
	    POP_TAG();
	    if (!recursive_pop(p.list, p.objid, p.pairid)) {
	      invalid:
		rb_raise(rb_eTypeError, "invalid inspect_tbl pair_list "
			 "for %+"PRIsVALUE" in %+"PRIsVALUE,
			 sym, rb_thread_current());
	    }
	    if (state) JUMP_TAG(state);
	    result = ret;
	}
    }
    *(volatile struct exec_recursive_params *)&p;
    return result;
}

/*
 * Calls func(obj, arg, recursive), where recursive is non-zero if the
 * current method is called recursively on obj
 */

VALUE
rb_exec_recursive(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE arg)
{
    return exec_recursive(func, obj, 0, arg, 0);
}

/*
 * Calls func(obj, arg, recursive), where recursive is non-zero if the
 * current method is called recursively on the ordered pair <obj, paired_obj>
 */

VALUE
rb_exec_recursive_paired(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE paired_obj, VALUE arg)
{
    return exec_recursive(func, obj, rb_obj_id(paired_obj), arg, 0);
}

/*
 * If recursion is detected on the current method and obj, the outermost
 * func will be called with (obj, arg, Qtrue). All inner func will be
 * short-circuited using throw.
 */

VALUE
rb_exec_recursive_outer(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE arg)
{
    return exec_recursive(func, obj, 0, arg, 1);
}

/*
 * If recursion is detected on the current method, obj and paired_obj,
 * the outermost func will be called with (obj, arg, Qtrue). All inner
 * func will be short-circuited using throw.
 */

VALUE
rb_exec_recursive_paired_outer(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE paired_obj, VALUE arg)
{
    return exec_recursive(func, obj, rb_obj_id(paired_obj), arg, 1);
}

/*
 *  call-seq:
 *     thread.backtrace    -> array
 *
 *  Returns the current backtrace of the target thread.
 *
 */

static VALUE
rb_thread_backtrace_m(int argc, VALUE *argv, VALUE thval)
{
    return rb_vm_thread_backtrace(argc, argv, thval);
}

/* call-seq:
 *  thread.backtrace_locations(*args)	-> array or nil
 *
 * Returns the execution stack for the target thread---an array containing
 * backtrace location objects.
 *
 * See Thread::Backtrace::Location for more information.
 *
 * This method behaves similarly to Kernel#caller_locations except it applies
 * to a specific thread.
 */
static VALUE
rb_thread_backtrace_locations_m(int argc, VALUE *argv, VALUE thval)
{
    return rb_vm_thread_backtrace_locations(argc, argv, thval);
}

/*
 *  Document-class: ThreadError
 *
 *  Raised when an invalid operation is attempted on a thread.
 *
 *  For example, when no other thread has been started:
 *
 *     Thread.stop
 *
 *  This will raises the following exception:
 *
 *     ThreadError: stopping only thread
 *     note: use sleep to stop forever
 */

void
Init_Thread(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    VALUE cThGroup;
    rb_thread_t *th = GET_THREAD();

    sym_never = ID2SYM(rb_intern("never"));
    sym_immediate = ID2SYM(rb_intern("immediate"));
    sym_on_blocking = ID2SYM(rb_intern("on_blocking"));
    id_locals = rb_intern("locals");

    rb_define_singleton_method(rb_cThread, "new", thread_s_new, -1);
    rb_define_singleton_method(rb_cThread, "start", thread_start, -2);
    rb_define_singleton_method(rb_cThread, "fork", thread_start, -2);
    rb_define_singleton_method(rb_cThread, "main", rb_thread_s_main, 0);
    rb_define_singleton_method(rb_cThread, "current", thread_s_current, 0);
    rb_define_singleton_method(rb_cThread, "stop", rb_thread_stop, 0);
    rb_define_singleton_method(rb_cThread, "kill", rb_thread_s_kill, 1);
    rb_define_singleton_method(rb_cThread, "exit", rb_thread_exit, 0);
    rb_define_singleton_method(rb_cThread, "pass", thread_s_pass, 0);
    rb_define_singleton_method(rb_cThread, "list", rb_thread_list, 0);
    rb_define_singleton_method(rb_cThread, "abort_on_exception", rb_thread_s_abort_exc, 0);
    rb_define_singleton_method(rb_cThread, "abort_on_exception=", rb_thread_s_abort_exc_set, 1);
    rb_define_singleton_method(rb_cThread, "report_on_exception", rb_thread_s_report_exc, 0);
    rb_define_singleton_method(rb_cThread, "report_on_exception=", rb_thread_s_report_exc_set, 1);
#if THREAD_DEBUG < 0
    rb_define_singleton_method(rb_cThread, "DEBUG", rb_thread_s_debug, 0);
    rb_define_singleton_method(rb_cThread, "DEBUG=", rb_thread_s_debug_set, 1);
#endif
    rb_define_singleton_method(rb_cThread, "handle_interrupt", rb_thread_s_handle_interrupt, 1);
    rb_define_singleton_method(rb_cThread, "pending_interrupt?", rb_thread_s_pending_interrupt_p, -1);
    rb_define_method(rb_cThread, "pending_interrupt?", rb_thread_pending_interrupt_p, -1);

    rb_define_method(rb_cThread, "initialize", thread_initialize, -2);
    rb_define_method(rb_cThread, "raise", thread_raise_m, -1);
    rb_define_method(rb_cThread, "join", thread_join_m, -1);
    rb_define_method(rb_cThread, "value", thread_value, 0);
    rb_define_method(rb_cThread, "kill", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "terminate", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "exit", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "run", rb_thread_run, 0);
    rb_define_method(rb_cThread, "wakeup", rb_thread_wakeup, 0);
    rb_define_method(rb_cThread, "[]", rb_thread_aref, 1);
    rb_define_method(rb_cThread, "[]=", rb_thread_aset, 2);
    rb_define_method(rb_cThread, "key?", rb_thread_key_p, 1);
    rb_define_method(rb_cThread, "keys", rb_thread_keys, 0);
    rb_define_method(rb_cThread, "priority", rb_thread_priority, 0);
    rb_define_method(rb_cThread, "priority=", rb_thread_priority_set, 1);
    rb_define_method(rb_cThread, "status", rb_thread_status, 0);
    rb_define_method(rb_cThread, "thread_variable_get", rb_thread_variable_get, 1);
    rb_define_method(rb_cThread, "thread_variable_set", rb_thread_variable_set, 2);
    rb_define_method(rb_cThread, "thread_variables", rb_thread_variables, 0);
    rb_define_method(rb_cThread, "thread_variable?", rb_thread_variable_p, 1);
    rb_define_method(rb_cThread, "alive?", rb_thread_alive_p, 0);
    rb_define_method(rb_cThread, "stop?", rb_thread_stop_p, 0);
    rb_define_method(rb_cThread, "abort_on_exception", rb_thread_abort_exc, 0);
    rb_define_method(rb_cThread, "abort_on_exception=", rb_thread_abort_exc_set, 1);
    rb_define_method(rb_cThread, "report_on_exception", rb_thread_report_exc, 0);
    rb_define_method(rb_cThread, "report_on_exception=", rb_thread_report_exc_set, 1);
    rb_define_method(rb_cThread, "safe_level", rb_thread_safe_level, 0);
    rb_define_method(rb_cThread, "group", rb_thread_group, 0);
    rb_define_method(rb_cThread, "backtrace", rb_thread_backtrace_m, -1);
    rb_define_method(rb_cThread, "backtrace_locations", rb_thread_backtrace_locations_m, -1);

    rb_define_method(rb_cThread, "name", rb_thread_getname, 0);
    rb_define_method(rb_cThread, "name=", rb_thread_setname, 1);
    rb_define_method(rb_cThread, "inspect", rb_thread_inspect, 0);

    rb_vm_register_special_exception(ruby_error_closed_stream, rb_eIOError, "stream closed");

    cThGroup = rb_define_class("ThreadGroup", rb_cObject);
    rb_define_alloc_func(cThGroup, thgroup_s_alloc);
    rb_define_method(cThGroup, "list", thgroup_list, 0);
    rb_define_method(cThGroup, "enclose", thgroup_enclose, 0);
    rb_define_method(cThGroup, "enclosed?", thgroup_enclosed_p, 0);
    rb_define_method(cThGroup, "add", thgroup_add, 1);

    {
	th->thgroup = th->vm->thgroup_default = rb_obj_alloc(cThGroup);
	rb_define_const(cThGroup, "Default", th->thgroup);
    }

    recursive_key = rb_intern("__recursive_key__");
    rb_eThreadError = rb_define_class("ThreadError", rb_eStandardError);

    /* init thread core */
    {
	/* main thread setting */
	{
	    /* acquire global vm lock */
	    gvl_init(th->vm);
	    gvl_acquire(th->vm, th);
	    native_mutex_initialize(&th->vm->thread_destruct_lock);
	    native_mutex_initialize(&th->interrupt_lock);
	    native_cond_initialize(&th->interrupt_cond,
				   RB_CONDATTR_CLOCK_MONOTONIC);

	    th->pending_interrupt_queue = rb_ary_tmp_new(0);
	    th->pending_interrupt_queue_checked = 0;
	    th->pending_interrupt_mask_stack = rb_ary_tmp_new(0);

	    th->interrupt_mask = 0;
	}
    }

    rb_thread_create_timer_thread();

    /* suppress warnings on cygwin, mingw and mswin.*/
    (void)native_mutex_trylock;

    Init_thread_sync();
}

int
ruby_native_thread_p(void)
{
    rb_thread_t *th = ruby_thread_from_native();

    return th != 0;
}

VALUE rb_vm_backtrace_str_ary(rb_thread_t *th, long lev, long n);
static void
debug_deadlock_check(rb_vm_t *vm, VALUE msg)
{
    rb_thread_t *th = 0;
    VALUE sep = rb_str_new_cstr("\n   ");

    rb_str_catf(msg, "\n%d threads, %d sleeps current:%p main thread:%p\n",
	    vm_living_thread_num(vm), vm->sleeper, GET_THREAD(), vm->main_thread);
    list_for_each(&vm->living_threads, th, vmlt_node) {
	rb_str_catf(msg, "* %+"PRIsVALUE"\n   rb_thread_t:%p "
		    "native:%"PRI_THREAD_ID" int:%u",
		    th->self, th, thread_id_str(th), th->interrupt_flag);
	if (th->locking_mutex) {
	    rb_mutex_t *mutex;
	    struct rb_thread_struct volatile *mth;
	    int waiting;
	    GetMutexPtr(th->locking_mutex, mutex);

	    native_mutex_lock(&mutex->lock);
	    mth = mutex->th;
	    waiting = mutex->cond_waiting;
	    native_mutex_unlock(&mutex->lock);
	    rb_str_catf(msg, " mutex:%p cond:%d", mth, waiting);
	}
	{
	    rb_thread_list_t *list = th->join_list;
	    while (list) {
		rb_str_catf(msg, "\n    depended by: tb_thread_id:%p", list->th);
		list = list->next;
	    }
	}
	rb_str_catf(msg, "\n   ");
	rb_str_concat(msg, rb_ary_join(rb_vm_backtrace_str_ary(th, 0, 0), sep));
	rb_str_catf(msg, "\n");
    }
}

static void
rb_check_deadlock(rb_vm_t *vm)
{
    int found = 0;
    rb_thread_t *th = 0;

    if (vm_living_thread_num(vm) > vm->sleeper) return;
    if (vm_living_thread_num(vm) < vm->sleeper) rb_bug("sleeper must not be more than vm_living_thread_num(vm)");
    if (patrol_thread && patrol_thread != GET_THREAD()) return;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	if (th->status != THREAD_STOPPED_FOREVER || RUBY_VM_INTERRUPTED(th)) {
	    found = 1;
	}
	else if (th->locking_mutex) {
	    rb_mutex_t *mutex;
	    GetMutexPtr(th->locking_mutex, mutex);

	    native_mutex_lock(&mutex->lock);
	    if (mutex->th == th || (!mutex->th && mutex->cond_waiting)) {
		found = 1;
	    }
	    native_mutex_unlock(&mutex->lock);
	}
	if (found)
	    break;
    }

    if (!found) {
	VALUE argv[2];
	argv[0] = rb_eFatal;
	argv[1] = rb_str_new2("No live threads left. Deadlock?");
	debug_deadlock_check(vm, argv[1]);
	vm->sleeper--;
	rb_threadptr_raise(vm->main_thread, 2, argv);
    }
}

static void
update_coverage(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
    VALUE coverage = rb_iseq_coverage(GET_THREAD()->cfp->iseq);
    if (RB_TYPE_P(coverage, T_ARRAY) && !RBASIC_CLASS(coverage)) {
	long line = rb_sourceline() - 1;
	long count;
	VALUE num;
	if (line >= RARRAY_LEN(coverage)) { /* no longer tracked */
	    return;
	}
	num = RARRAY_AREF(coverage, line);
	if (!FIXNUM_P(num)) return;
	count = FIX2LONG(num) + 1;
	if (POSFIXABLE(count)) {
	    RARRAY_ASET(coverage, line, LONG2FIX(count));
	}
    }
}

VALUE
rb_get_coverages(void)
{
    return GET_VM()->coverages;
}

void
rb_set_coverages(VALUE coverages)
{
    GET_VM()->coverages = coverages;
    rb_add_event_hook(update_coverage, RUBY_EVENT_COVERAGE, Qnil);
}

/* Make coverage arrays empty so old covered files are no longer tracked. */
static int
reset_coverage_i(st_data_t key, st_data_t val, st_data_t dummy)
{
    VALUE coverage = (VALUE)val;
    rb_ary_clear(coverage);
    return ST_CONTINUE;
}

void
rb_reset_coverages(void)
{
    VALUE coverages = rb_get_coverages();
    st_foreach(rb_hash_tbl_raw(coverages), reset_coverage_i, 0);
    GET_VM()->coverages = Qfalse;
    rb_remove_event_hook(update_coverage);
}

VALUE
rb_uninterruptible(VALUE (*b_proc)(ANYARGS), VALUE data)
{
    VALUE interrupt_mask = rb_ident_hash_new();
    rb_thread_t *cur_th = GET_THREAD();

    rb_hash_aset(interrupt_mask, rb_cObject, sym_never);
    OBJ_FREEZE_RAW(interrupt_mask);
    rb_ary_push(cur_th->pending_interrupt_mask_stack, interrupt_mask);

    return rb_ensure(b_proc, data, rb_ary_pop, cur_th->pending_interrupt_mask_stack);
}

void
ruby_kill(rb_pid_t pid, int sig)
{
    int err;
    rb_thread_t *th = GET_THREAD();

    /*
     * When target pid is self, many caller assume signal will be
     * delivered immediately and synchronously.
     */
    {
	GVL_UNLOCK_BEGIN();
	native_mutex_lock(&th->interrupt_lock);
	err = kill(pid, sig);
	native_cond_wait(&th->interrupt_cond, &th->interrupt_lock);
	native_mutex_unlock(&th->interrupt_lock);
	GVL_UNLOCK_END();
    }
    if (err < 0) {
	rb_sys_fail(0);
    }
}
