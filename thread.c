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

  model 4: M:N User:Native threads with Global VM lock
    Combination of model 1 and 2

  model 5: M:N User:Native thread with fine grain lock
    Combination of model 1 and 3

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

#include "ruby/config.h"
#include "ruby/io.h"
#include "eval_intern.h"
#include "timev.h"
#include "ruby/thread.h"
#include "ruby/thread_native.h"
#include "ruby/debug.h"
#include "gc.h"
#include "internal.h"
#include "iseq.h"
#include "vm_core.h"
#include "mjit.h"
#include "hrtime.h"

#ifdef __linux__
// Normally,  gcc(1)  translates  calls to alloca() with inlined code.  This is not done when either the -ansi, -std=c89, -std=c99, or the -std=c11 option is given and the header <alloca.h> is not included.
#include <alloca.h>
#endif

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

enum SLEEP_FLAGS {
    SLEEP_DEADLOCKABLE = 0x1,
    SLEEP_SPURIOUS_CHECK = 0x2
};

static void sleep_hrtime(rb_thread_t *, rb_hrtime_t, unsigned int fl);
static void sleep_forever(rb_thread_t *th, unsigned int fl);
static void rb_thread_sleep_deadly_allow_spurious_wakeup(void);
static int rb_threadptr_dead(rb_thread_t *th);
static void rb_check_deadlock(rb_vm_t *vm);
static int rb_threadptr_pending_interrupt_empty_p(const rb_thread_t *th);
static const char *thread_status_name(rb_thread_t *th, int detail);
static int hrtime_update_expire(rb_hrtime_t *, const rb_hrtime_t);
NORETURN(static void async_bug_fd(const char *mesg, int errno_arg, int fd));
static int consume_communication_pipe(int fd);
static int check_signals_nogvl(rb_thread_t *, int sigwait_fd);
void rb_sigwait_fd_migrate(rb_vm_t *); /* process.c */

#define eKillSignal INT2FIX(0)
#define eTerminateSignal INT2FIX(1)
static volatile int system_working = 1;

struct waiting_fd {
    struct list_node wfd_node; /* <=> vm.waiting_fds */
    rb_thread_t *th;
    int fd;
};

inline static void
st_delete_wrap(st_table *table, st_data_t key)
{
    st_delete(table, &key, 0);
}

/********************************************************************************/

#define THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

struct rb_blocking_region_buffer {
    enum rb_thread_status prev_status;
};

static int unblock_function_set(rb_thread_t *th, rb_unblock_function_t *func, void *arg, int fail_if_interrupted);
static void unblock_function_clear(rb_thread_t *th);

static inline int blocking_region_begin(rb_thread_t *th, struct rb_blocking_region_buffer *region,
					rb_unblock_function_t *ubf, void *arg, int fail_if_interrupted);
static inline void blocking_region_end(rb_thread_t *th, struct rb_blocking_region_buffer *region);

#define RB_GC_SAVE_MACHINE_CONTEXT(th)				\
    do {							\
	FLUSH_REGISTER_WINDOWS;					\
	setjmp((th)->ec->machine.regs);				\
	SET_MACHINE_STACK_END(&(th)->ec->machine.stack_end);	\
    } while (0)

#define GVL_UNLOCK_BEGIN(th) do { \
  RB_GC_SAVE_MACHINE_CONTEXT(th); \
  gvl_release(th->vm);

#define GVL_UNLOCK_END(th) \
  gvl_acquire(th->vm, th); \
  rb_thread_set_current(th); \
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
#define BLOCKING_REGION(th, exec, ubf, ubfarg, fail_if_interrupted) do { \
    struct rb_blocking_region_buffer __region; \
    if (blocking_region_begin(th, &__region, (ubf), (ubfarg), fail_if_interrupted) || \
	/* always return true unless fail_if_interrupted */ \
	!only_if_constant(fail_if_interrupted, TRUE)) { \
	exec; \
	blocking_region_end(th, &__region); \
    }; \
} while(0)

/*
 * returns true if this thread was spuriously interrupted, false otherwise
 * (e.g. hit by Thread#run or ran a Ruby-level Signal.trap handler)
 */
#define RUBY_VM_CHECK_INTS_BLOCKING(ec) vm_check_ints_blocking(ec)
static inline int
vm_check_ints_blocking(rb_execution_context_t *ec)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);

    if (LIKELY(rb_threadptr_pending_interrupt_empty_p(th))) {
	if (LIKELY(!RUBY_VM_INTERRUPTED_ANY(ec))) return FALSE;
    }
    else {
	th->pending_interrupt_queue_checked = 0;
	RUBY_VM_SET_INTERRUPT(ec);
    }
    return rb_threadptr_execute_interrupts(th, 1);
}

static int
vm_living_thread_num(const rb_vm_t *vm)
{
    return vm->living_thread_num;
}

/*
 * poll() is supported by many OSes, but so far Linux is the only
 * one we know of that supports using poll() in all places select()
 * would work.
 */
#if defined(HAVE_POLL)
#  if defined(__linux__)
#    define USE_POLL
#  endif
#  if defined(__FreeBSD_version) && __FreeBSD_version >= 1100000
#    define USE_POLL
     /* FreeBSD does not set POLLOUT when POLLHUP happens */
#    define POLLERR_SET (POLLHUP | POLLERR)
#  endif
#endif

static void
timeout_prepare(rb_hrtime_t **to, rb_hrtime_t *rel, rb_hrtime_t *end,
                const struct timeval *timeout)
{
    if (timeout) {
        *rel = rb_timeval2hrtime(timeout);
        *end = rb_hrtime_add(rb_hrtime_now(), *rel);
        *to = rel;
    }
    else {
        *to = 0;
    }
}

#if THREAD_DEBUG
#ifdef HAVE_VA_ARGS_MACRO
void rb_thread_debug(const char *file, int line, const char *fmt, ...);
#define thread_debug(...) rb_thread_debug(__FILE__, __LINE__, __VA_ARGS__)
#define POSITION_FORMAT "%s:%d:"
#define POSITION_ARGS ,file, line
#else
void rb_thread_debug(const char *fmt, ...);
#define thread_debug rb_thread_debug
#define POSITION_FORMAT
#define POSITION_ARGS
#endif

# ifdef NON_SCALAR_THREAD_ID
#define fill_thread_id_string ruby_fill_thread_id_string
const char *
ruby_fill_thread_id_string(rb_nativethread_id_t thid, rb_thread_id_string_t buf)
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
# define fill_thread_id_string(thid, buf) ((void *)(uintptr_t)(thid))
# define fill_thread_id_str(th) (void)0
# define thread_id_str(th) ((void *)(uintptr_t)(th)->thread_id)
# define PRI_THREAD_ID "p"
#endif

NOINLINE(static int thread_start_func_2(rb_thread_t *th, VALUE *stack_start));
static void timer_thread_function(void);
void ruby_sigchld_handler(rb_vm_t *); /* signal.c */

static void
ubf_sigwait(void *ignore)
{
    rb_thread_wakeup_timer_thread(0);
}

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

/*
 * TODO: somebody with win32 knowledge should be able to get rid of
 * timer-thread by busy-waiting on signals.  And it should be possible
 * to make the GVL in thread_pthread.c be platform-independent.
 */
#ifndef BUSY_WAIT_SIGNALS
#  define BUSY_WAIT_SIGNALS (0)
#endif

#ifndef USE_EVENTFD
#  define USE_EVENTFD (0)
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
        rb_native_mutex_initialize(&debug_mutex);
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
    if (0) {
        /* may be held by running threads */
        rb_native_mutex_destroy(&vm->waitpid_lock);
        rb_native_mutex_destroy(&vm->workqueue_lock);
    }
}

void
rb_nativethread_lock_initialize(rb_nativethread_lock_t *lock)
{
    rb_native_mutex_initialize(lock);
}

void
rb_nativethread_lock_destroy(rb_nativethread_lock_t *lock)
{
    rb_native_mutex_destroy(lock);
}

void
rb_nativethread_lock_lock(rb_nativethread_lock_t *lock)
{
    rb_native_mutex_lock(lock);
}

void
rb_nativethread_lock_unlock(rb_nativethread_lock_t *lock)
{
    rb_native_mutex_unlock(lock);
}

static int
unblock_function_set(rb_thread_t *th, rb_unblock_function_t *func, void *arg, int fail_if_interrupted)
{
    do {
	if (fail_if_interrupted) {
	    if (RUBY_VM_INTERRUPTED_ANY(th->ec)) {
		return FALSE;
	    }
	}
	else {
	    RUBY_VM_CHECK_INTS(th->ec);
	}

        rb_native_mutex_lock(&th->interrupt_lock);
    } while (!th->ec->raised_flag && RUBY_VM_INTERRUPTED_ANY(th->ec) &&
             (rb_native_mutex_unlock(&th->interrupt_lock), TRUE));

    VM_ASSERT(th->unblock.func == NULL);

    th->unblock.func = func;
    th->unblock.arg = arg;
    rb_native_mutex_unlock(&th->interrupt_lock);

    return TRUE;
}

static void
unblock_function_clear(rb_thread_t *th)
{
    rb_native_mutex_lock(&th->interrupt_lock);
    th->unblock.func = NULL;
    rb_native_mutex_unlock(&th->interrupt_lock);
}

static void
rb_threadptr_interrupt_common(rb_thread_t *th, int trap)
{
    rb_native_mutex_lock(&th->interrupt_lock);
    if (trap) {
	RUBY_VM_SET_TRAP_INTERRUPT(th->ec);
    }
    else {
	RUBY_VM_SET_INTERRUPT(th->ec);
    }
    if (th->unblock.func != NULL) {
	(th->unblock.func)(th->unblock.arg);
    }
    else {
	/* none */
    }
    rb_native_mutex_unlock(&th->interrupt_lock);
}

void
rb_threadptr_interrupt(rb_thread_t *th)
{
    rb_threadptr_interrupt_common(th, 0);
}

static void
threadptr_trap_interrupt(rb_thread_t *th)
{
    rb_threadptr_interrupt_common(th, 1);
}

static void
terminate_all(rb_vm_t *vm, const rb_thread_t *main_thread)
{
    rb_thread_t *th = 0;

    list_for_each(&vm->living_threads, th, vmlt_node) {
	if (th != main_thread) {
	    thread_debug("terminate_all: begin (thid: %"PRI_THREAD_ID", status: %s)\n",
			 thread_id_str(th), thread_status_name(th, TRUE));
	    rb_threadptr_pending_interrupt_enque(th, eTerminateSignal);
	    rb_threadptr_interrupt(th);
	    thread_debug("terminate_all: end (thid: %"PRI_THREAD_ID", status: %s)\n",
			 thread_id_str(th), thread_status_name(th, TRUE));
	}
	else {
	    thread_debug("terminate_all: main thread (%p)\n", (void *)th);
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
		(void *)mutexes); */
	mutexes = mutex->next_mutex;
	err = rb_mutex_unlock_th(mutex, th);
	if (err) rb_bug("invalid keeping_mutexes: %s", err);
    }
}

void
rb_thread_terminate_all(void)
{
    rb_thread_t *volatile th = GET_THREAD(); /* main thread */
    rb_execution_context_t * volatile ec = th->ec;
    rb_vm_t *volatile vm = th->vm;
    volatile int sleeping = 0;

    if (vm->main_thread != th) {
	rb_bug("rb_thread_terminate_all: called by child thread (%p, %p)",
	       (void *)vm->main_thread, (void *)th);
    }

    /* unlock all locking mutexes */
    rb_threadptr_unlock_all_locking_mutexes(th);

    EC_PUSH_TAG(ec);
    if (EC_EXEC_TAG() == TAG_NONE) {
      retry:
	thread_debug("rb_thread_terminate_all (main thread: %p)\n", (void *)th);
	terminate_all(vm, th);

	while (vm_living_thread_num(vm) > 1) {
            rb_hrtime_t rel = RB_HRTIME_PER_SEC;
	    /*
	     * Thread exiting routine in thread_start_func_2 notify
	     * me when the last sub-thread exit.
	     */
	    sleeping = 1;
	    native_sleep(th, &rel);
	    RUBY_VM_CHECK_INTS_BLOCKING(ec);
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
    EC_POP_TAG();
}

void rb_threadptr_root_fiber_terminate(rb_thread_t *th);

static void
thread_cleanup_func_before_exec(void *th_ptr)
{
    rb_thread_t *th = th_ptr;
    th->status = THREAD_KILLED;
    // The thread stack doesn't exist in the forked process:
    th->ec->machine.stack_start = th->ec->machine.stack_end = NULL;

    rb_threadptr_root_fiber_terminate(th);
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
     *
     * FIXME: Skipping native_mutex_destroy(pthread_mutex_destroy) is safe
     * with NPTL, but native_thread_destroy calls pthread_cond_destroy
     * which calls free(3), so there is a small memory leak atfork, here.
     */
    if (atfork)
	return;

    rb_native_mutex_destroy(&th->interrupt_lock);
    native_thread_destroy(th);
}

static VALUE rb_threadptr_raise(rb_thread_t *, int, VALUE *);
static VALUE rb_thread_to_s(VALUE thread);

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
thread_do_start(rb_thread_t *th)
{
    native_set_thread_name(th);

    if (th->invoke_type == thread_invoke_type_proc) {
        VALUE args = th->invoke_arg.proc.args;
        long args_len = RARRAY_LEN(args);
        const VALUE *args_ptr;
        VALUE procval = th->invoke_arg.proc.proc;
	rb_proc_t *proc;
        GetProcPtr(procval, proc);

        th->ec->errinfo = Qnil;
        th->ec->root_lep = rb_vm_proc_local_ep(procval);
	th->ec->root_svar = Qfalse;

        EXEC_EVENT_HOOK(th->ec, RUBY_EVENT_THREAD_BEGIN, th->self, 0, 0, 0, Qundef);

        if (args_len < 8) {
            /* free proc.args if the length is enough small */
            args_ptr = ALLOCA_N(VALUE, args_len);
            MEMCPY((VALUE *)args_ptr, RARRAY_CONST_PTR_TRANSIENT(args), VALUE, args_len);
            th->invoke_arg.proc.args = Qnil;
        }
        else {
            args_ptr = RARRAY_CONST_PTR(args);
        }

        th->value = rb_vm_invoke_proc(th->ec, proc,
                                      (int)args_len, args_ptr,
                                      VM_BLOCK_HANDLER_NONE);

        EXEC_EVENT_HOOK(th->ec, RUBY_EVENT_THREAD_END, th->self, 0, 0, 0, Qundef);
    }
    else {
        th->value = (*th->invoke_arg.func.func)(th->invoke_arg.func.arg);
    }
}

void rb_ec_clear_current_thread_trace_func(const rb_execution_context_t *ec);

static int
thread_start_func_2(rb_thread_t *th, VALUE *stack_start)
{
    STACK_GROW_DIR_DETECTION;
    enum ruby_tag_type state;
    rb_thread_list_t *join_list;
    rb_thread_t *main_th;
    VALUE errinfo = Qnil;
    size_t size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
    VALUE * vm_stack = NULL;

    if (th == th->vm->main_thread) {
        rb_bug("thread_start_func_2 must not be used for main thread");
    }

    thread_debug("thread start: %p\n", (void *)th);
    VM_ASSERT((size * sizeof(VALUE)) <= th->ec->machine.stack_maxsize);

    vm_stack = alloca(size * sizeof(VALUE));
    VM_ASSERT(vm_stack);

    gvl_acquire(th->vm, th);

    rb_ec_initialize_vm_stack(th->ec, vm_stack, size);
    th->ec->machine.stack_start = STACK_DIR_UPPER(vm_stack + size, vm_stack);
    th->ec->machine.stack_maxsize -= size * sizeof(VALUE);

    ruby_thread_set_native(th);

    {
	thread_debug("thread start (get lock): %p\n", (void *)th);
	rb_thread_set_current(th);

	EC_PUSH_TAG(th->ec);
	if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            SAVE_ROOT_JMPBUF(th, thread_do_start(th));
	}
	else {
	    errinfo = th->ec->errinfo;
	    if (state == TAG_FATAL) {
		/* fatal error within this thread, need to stop whole script */
	    }
	    else if (rb_obj_is_kind_of(errinfo, rb_eSystemExit)) {
		/* exit on main_thread. */
	    }
	    else {
		if (th->report_on_exception) {
		    VALUE mesg = rb_thread_to_s(th->self);
		    rb_str_cat_cstr(mesg, " terminated with exception (report_on_exception is true):\n");
		    rb_write_error_str(mesg);
		    rb_ec_error_print(th->ec, errinfo);
		}
		if (th->vm->thread_abort_on_exception ||
		    th->abort_on_exception || RTEST(ruby_debug)) {
		    /* exit on main_thread */
		}
		else {
		    errinfo = Qnil;
		}
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
	EC_POP_TAG();

	rb_ec_clear_current_thread_trace_func(th->ec);

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

        rb_fiber_close(th->ec->fiber_ptr);
    }

    thread_cleanup_func(th, FALSE);
    VM_ASSERT(th->ec->vm_stack == NULL);

    gvl_release(th->vm);

    return 0;
}

static VALUE
thread_create_core(VALUE thval, VALUE args, VALUE (*fn)(ANYARGS))
{
    rb_thread_t *th = rb_thread_ptr(thval), *current_th = GET_THREAD();
    int err;

    if (OBJ_FROZEN(current_th->thgroup)) {
	rb_raise(rb_eThreadError,
		 "can't start a new thread (frozen ThreadGroup)");
    }

    if (fn) {
        th->invoke_type = thread_invoke_type_func;
        th->invoke_arg.func.func = fn;
        th->invoke_arg.func.arg = (void *)args;
    }
    else {
        th->invoke_type = thread_invoke_type_proc;
        th->invoke_arg.proc.proc = rb_block_proc();
        th->invoke_arg.proc.args = args;
    }

    th->priority = current_th->priority;
    th->thgroup = current_th->thgroup;

    th->pending_interrupt_queue = rb_ary_tmp_new(0);
    th->pending_interrupt_queue_checked = 0;
    th->pending_interrupt_mask_stack = rb_ary_dup(current_th->pending_interrupt_mask_stack);
    RBASIC_CLEAR_CLASS(th->pending_interrupt_mask_stack);

    rb_native_mutex_initialize(&th->interrupt_lock);

    /* kick thread */
    err = native_thread_create(th);
    if (err) {
	th->status = THREAD_KILLED;
	rb_raise(rb_eThreadError, "can't create Thread: %s", strerror(err));
    }
    rb_vm_living_threads_insert(th->vm, th);
    return thval;
}

#define threadptr_initialized(th) ((th)->invoke_type != thread_invoke_type_none)

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
    th = rb_thread_ptr(thread);
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

static VALUE
threadptr_invoke_proc_location(rb_thread_t *th)
{
    if (th->invoke_type == thread_invoke_type_proc) {
        return rb_proc_location(th->invoke_arg.proc.proc);
    }
    else {
        return Qnil;
    }
}

/* :nodoc: */
static VALUE
thread_initialize(VALUE thread, VALUE args)
{
    rb_thread_t *th = rb_thread_ptr(thread);

    if (!rb_block_given_p()) {
        rb_raise(rb_eThreadError, "must be called with a block");
    }
    else if (th->invoke_type != thread_invoke_type_none) {
        VALUE loc = threadptr_invoke_proc_location(th);
        if (!NIL_P(loc)) {
            rb_raise(rb_eThreadError,
                     "already initialized thread - %"PRIsVALUE":%"PRIsVALUE,
                     RARRAY_AREF(loc, 0), RARRAY_AREF(loc, 1));
        }
        else {
            rb_raise(rb_eThreadError, "already initialized thread");
        }
    }
    else {
        return thread_create_core(thread, args, NULL);
    }
}

VALUE
rb_thread_create(VALUE (*fn)(ANYARGS), void *arg)
{
    return thread_create_core(rb_thread_alloc(rb_cThread), (VALUE)arg, fn);
}


struct join_arg {
    rb_thread_t *target, *waiting;
    rb_hrtime_t *limit;
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
    rb_hrtime_t end = 0;

    if (p->limit) {
        end = rb_hrtime_add(*p->limit, rb_hrtime_now());
    }

    while (target_th->status != THREAD_KILLED) {
	if (!p->limit) {
	    th->status = THREAD_STOPPED_FOREVER;
	    th->vm->sleeper++;
	    rb_check_deadlock(th->vm);
	    native_sleep(th, 0);
	    th->vm->sleeper--;
	}
	else {
            if (hrtime_update_expire(p->limit, end)) {
		thread_debug("thread_join: timeout (thid: %"PRI_THREAD_ID")\n",
			     thread_id_str(target_th));
		return Qfalse;
	    }
	    th->status = THREAD_STOPPED;
	    native_sleep(th, p->limit);
	}
	RUBY_VM_CHECK_INTS_BLOCKING(th->ec);
	th->status = THREAD_RUNNABLE;
	thread_debug("thread_join: interrupted (thid: %"PRI_THREAD_ID", status: %s)\n",
		     thread_id_str(target_th), thread_status_name(target_th, TRUE));
    }
    return Qtrue;
}

static VALUE
thread_join(rb_thread_t *target_th, rb_hrtime_t *rel)
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
    arg.limit = rel;

    thread_debug("thread_join (thid: %"PRI_THREAD_ID", status: %s)\n",
		 thread_id_str(target_th), thread_status_name(target_th, TRUE));

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

    thread_debug("thread_join: success (thid: %"PRI_THREAD_ID", status: %s)\n",
		 thread_id_str(target_th), thread_status_name(target_th, TRUE));

    if (target_th->ec->errinfo != Qnil) {
	VALUE err = target_th->ec->errinfo;

	if (FIXNUM_P(err)) {
	    switch (err) {
	      case INT2FIX(TAG_FATAL):
		thread_debug("thread_join: terminated (thid: %"PRI_THREAD_ID", status: %s)\n",
			     thread_id_str(target_th), thread_status_name(target_th, TRUE));

		/* OK. killed. */
		break;
	      default:
		rb_bug("thread_join: Fixnum (%d) should not reach here.", FIX2INT(err));
	    }
	}
	else if (THROW_DATA_P(target_th->ec->errinfo)) {
	    rb_bug("thread_join: THROW_DATA should not reach here.");
	}
	else {
	    /* normal exception */
	    rb_exc_raise(err);
	}
    }
    return target_th->self;
}

static rb_hrtime_t *double2hrtime(rb_hrtime_t *, double);

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
    VALUE limit;
    rb_hrtime_t rel, *to = 0;

    /*
     * This supports INFINITY and negative values, so we can't use
     * rb_time_interval right now...
     */
    if (!rb_check_arity(argc, 0, 1) || NIL_P(argv[0])) {
        /* unlimited */
    }
    else if (FIXNUM_P(limit = argv[0])) {
        rel = rb_sec2hrtime(NUM2TIMET(limit));
        to = &rel;
    }
    else {
        to = double2hrtime(&rel, rb_num2dbl(limit));
    }

    return thread_join(rb_thread_ptr(self), to);
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
    rb_thread_t *th = rb_thread_ptr(self);
    thread_join(th, 0);
    return th->value;
}

/*
 * Thread Scheduling
 */

/*
 * Back when we used "struct timeval", not all platforms implemented
 * tv_sec as time_t.  Nowadays we use "struct timespec" and tv_sec
 * seems to be implemented more consistently across platforms.
 * At least other parts of our code hasn't had to deal with non-time_t
 * tv_sec in timespec...
 */
#define TIMESPEC_SEC_MAX TIMET_MAX
#define TIMESPEC_SEC_MIN TIMET_MIN

static rb_hrtime_t *
double2hrtime(rb_hrtime_t *hrt, double d)
{
    /* assume timespec.tv_sec has same signedness as time_t */
    const double TIMESPEC_SEC_MAX_PLUS_ONE = TIMET_MAX_PLUS_ONE;

    if (TIMESPEC_SEC_MAX_PLUS_ONE <= d) {
        return NULL;
    }
    else if (d <= 0) {
        *hrt = 0;
    }
    else {
        *hrt = (rb_hrtime_t)(d * (double)RB_HRTIME_PER_SEC);
    }
    return hrt;
}

static void
getclockofday(struct timespec *ts)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
    if (clock_gettime(CLOCK_MONOTONIC, ts) == 0)
        return;
#endif
    rb_timespec_now(ts);
}

/*
 * Don't inline this, since library call is already time consuming
 * and we don't want "struct timespec" on stack too long for GC
 */
NOINLINE(rb_hrtime_t rb_hrtime_now(void));
rb_hrtime_t
rb_hrtime_now(void)
{
    struct timespec ts;

    getclockofday(&ts);
    return rb_timespec2hrtime(&ts);
}

static void
sleep_forever(rb_thread_t *th, unsigned int fl)
{
    enum rb_thread_status prev_status = th->status;
    enum rb_thread_status status;
    int woke;

    status  = fl & SLEEP_DEADLOCKABLE ? THREAD_STOPPED_FOREVER : THREAD_STOPPED;
    th->status = status;
    RUBY_VM_CHECK_INTS_BLOCKING(th->ec);
    while (th->status == status) {
	if (fl & SLEEP_DEADLOCKABLE) {
	    th->vm->sleeper++;
	    rb_check_deadlock(th->vm);
	}
	native_sleep(th, 0);
	if (fl & SLEEP_DEADLOCKABLE) {
	    th->vm->sleeper--;
	}
	woke = vm_check_ints_blocking(th->ec);
	if (woke && !(fl & SLEEP_SPURIOUS_CHECK))
	    break;
    }
    th->status = prev_status;
}

/*
 * at least gcc 7.2 and 7.3 complains about "rb_hrtime_t end"
 * being uninitialized, maybe other versions, too.
 */
COMPILER_WARNING_PUSH
#if defined(__GNUC__) && __GNUC__ == 7 && __GNUC_MINOR__ <= 3
COMPILER_WARNING_IGNORED(-Wmaybe-uninitialized)
#endif
#ifndef PRIu64
#define PRIu64 PRI_64_PREFIX "u"
#endif
/*
 * @end is the absolute time when @ts is set to expire
 * Returns true if @end has past
 * Updates @ts and returns false otherwise
 */
static int
hrtime_update_expire(rb_hrtime_t *timeout, const rb_hrtime_t end)
{
    rb_hrtime_t now = rb_hrtime_now();

    if (now > end) return 1;
    thread_debug("hrtime_update_expire: "
                 "%"PRIu64" > %"PRIu64"\n",
                 (uint64_t)end, (uint64_t)now);
    *timeout = end - now;
    return 0;
}
COMPILER_WARNING_POP

static void
sleep_hrtime(rb_thread_t *th, rb_hrtime_t rel, unsigned int fl)
{
    enum rb_thread_status prev_status = th->status;
    int woke;
    rb_hrtime_t end = rb_hrtime_add(rb_hrtime_now(), rel);

    th->status = THREAD_STOPPED;
    RUBY_VM_CHECK_INTS_BLOCKING(th->ec);
    while (th->status == THREAD_STOPPED) {
	native_sleep(th, &rel);
	woke = vm_check_ints_blocking(th->ec);
	if (woke && !(fl & SLEEP_SPURIOUS_CHECK))
	    break;
	if (hrtime_update_expire(&rel, end))
	    break;
    }
    th->status = prev_status;
}

void
rb_thread_sleep_forever(void)
{
    thread_debug("rb_thread_sleep_forever\n");
    sleep_forever(GET_THREAD(), SLEEP_SPURIOUS_CHECK);
}

void
rb_thread_sleep_deadly(void)
{
    thread_debug("rb_thread_sleep_deadly\n");
    sleep_forever(GET_THREAD(), SLEEP_DEADLOCKABLE|SLEEP_SPURIOUS_CHECK);
}

void
rb_thread_sleep_interruptible(void)
{
    rb_thread_t *th = GET_THREAD();
    enum rb_thread_status prev_status = th->status;

    th->status = THREAD_STOPPED;
    native_sleep(th, 0);
    RUBY_VM_CHECK_INTS_BLOCKING(th->ec);
    th->status = prev_status;
}

static void
rb_thread_sleep_deadly_allow_spurious_wakeup(void)
{
    thread_debug("rb_thread_sleep_deadly_allow_spurious_wakeup\n");
    sleep_forever(GET_THREAD(), SLEEP_DEADLOCKABLE);
}

void
rb_thread_wait_for(struct timeval time)
{
    rb_thread_t *th = GET_THREAD();

    sleep_hrtime(th, rb_timeval2hrtime(&time), SLEEP_SPURIOUS_CHECK);
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
    RUBY_VM_CHECK_INTS_BLOCKING(GET_EC());
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
    return (int)RUBY_VM_INTERRUPTED(rb_thread_ptr(thval)->ec);
}

void
rb_thread_sleep(int sec)
{
    rb_thread_wait_for(rb_time_timeval(INT2FIX(sec)));
}

static void
rb_thread_schedule_limits(uint32_t limits_us)
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
    rb_thread_schedule_limits(0);
    RUBY_VM_CHECK_INTS(GET_EC());
}

/* blocking region */

static inline int
blocking_region_begin(rb_thread_t *th, struct rb_blocking_region_buffer *region,
		      rb_unblock_function_t *ubf, void *arg, int fail_if_interrupted)
{
    region->prev_status = th->status;
    if (unblock_function_set(th, ubf, arg, fail_if_interrupted)) {
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
    /* entry to ubf_list still permitted at this point, make it impossible: */
    unblock_function_clear(th);
    /* entry to ubf_list impossible at this point, so unregister is safe: */
    unregister_ubf_list(th);

    gvl_acquire(th->vm, th);
    rb_thread_set_current(th);
    thread_debug("leave blocking region (%p)\n", (void *)th);
    th->blocking_region_buffer = 0;
    if (th->status == THREAD_STOPPED) {
	th->status = region->prev_status;
    }
}

void *
rb_nogvl(void *(*func)(void *), void *data1,
         rb_unblock_function_t *ubf, void *data2,
         int flags)
{
    void *val = 0;
    rb_execution_context_t *ec = GET_EC();
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    int saved_errno = 0;
    VALUE ubf_th = Qfalse;

    if (ubf == RUBY_UBF_IO || ubf == RUBY_UBF_PROCESS) {
	ubf = ubf_select;
	data2 = th;
    }
    else if (ubf && vm_living_thread_num(th->vm) == 1) {
        if (RB_NOGVL_UBF_ASYNC_SAFE) {
            th->vm->ubf_async_safe = 1;
        }
        else {
            ubf_th = rb_thread_start_unblock_thread();
        }
    }

    BLOCKING_REGION(th, {
	val = func(data1);
	saved_errno = errno;
    }, ubf, data2, flags & RB_NOGVL_INTR_FAIL);

    th->vm->ubf_async_safe = 0;

    if ((flags & RB_NOGVL_INTR_FAIL) == 0) {
	RUBY_VM_CHECK_INTS_BLOCKING(ec);
    }

    if (ubf_th != Qfalse) {
        thread_value(rb_thread_kill(ubf_th));
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
    return rb_nogvl(func, data1, ubf, data2, RB_NOGVL_INTR_FAIL);
}

void *
rb_thread_call_without_gvl(void *(*func)(void *data), void *data1,
			    rb_unblock_function_t *ubf, void *data2)
{
    return rb_nogvl(func, data1, ubf, data2, 0);
}

VALUE
rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd)
{
    volatile VALUE val = Qundef; /* shouldn't be used */
    rb_execution_context_t * volatile ec = GET_EC();
    volatile int saved_errno = 0;
    enum ruby_tag_type state;
    struct waiting_fd wfd;

    wfd.fd = fd;
    wfd.th = rb_ec_thread_ptr(ec);
    list_add(&rb_ec_vm_ptr(ec)->waiting_fds, &wfd.wfd_node);

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	BLOCKING_REGION(wfd.th, {
	    val = func(data1);
	    saved_errno = errno;
	}, ubf_select, wfd.th, FALSE);
    }
    EC_POP_TAG();

    /*
     * must be deleted before jump
     * this will delete either from waiting_fds or on-stack LIST_HEAD(busy)
     */
    list_del(&wfd.wfd_node);

    if (state) {
	EC_JUMP_TAG(ec, state);
    }
    /* TODO: check func() */
    RUBY_VM_CHECK_INTS_BLOCKING(ec);

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
    int released = blocking_region_begin(th, brb, prev_unblock.func, prev_unblock.arg, FALSE);
    RUBY_ASSERT_ALWAYS(released);
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
    VALUE mod;
    long i;

    for (i=0; i<mask_stack_len; i++) {
	mask = mask_stack[mask_stack_len-(i+1)];

	for (mod = err; mod; mod = RCLASS_SUPER(mod)) {
	    VALUE klass = mod;
	    VALUE sym;

	    if (BUILTIN_TYPE(mod) == T_ICLASS) {
		klass = RBASIC(mod)->klass;
	    }
	    else if (mod != RCLASS_ORIGIN(mod)) {
		continue;
	    }

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
rb_threadptr_pending_interrupt_empty_p(const rb_thread_t *th)
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

static int
threadptr_pending_interrupt_active_p(rb_thread_t *th)
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
    rb_execution_context_t * volatile ec = GET_EC();
    rb_thread_t * volatile th = rb_ec_thread_ptr(ec);
    volatile VALUE r = Qnil;
    enum ruby_tag_type state;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "block is needed.");
    }

    mask = 0;
    mask_arg = rb_to_hash_type(mask_arg);
    rb_hash_foreach(mask_arg, handle_interrupt_arg_check_i, (VALUE)&mask);
    if (!mask) {
	return rb_yield(Qnil);
    }
    OBJ_FREEZE_RAW(mask);
    rb_ary_push(th->pending_interrupt_mask_stack, mask);
    if (!rb_threadptr_pending_interrupt_empty_p(th)) {
	th->pending_interrupt_queue_checked = 0;
	RUBY_VM_SET_INTERRUPT(th->ec);
    }

    EC_PUSH_TAG(th->ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	r = rb_yield(Qnil);
    }
    EC_POP_TAG();

    rb_ary_pop(th->pending_interrupt_mask_stack);
    if (!rb_threadptr_pending_interrupt_empty_p(th)) {
	th->pending_interrupt_queue_checked = 0;
	RUBY_VM_SET_INTERRUPT(th->ec);
    }

    RUBY_VM_CHECK_INTS(th->ec);

    if (state) {
	EC_JUMP_TAG(th->ec, state);
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
    rb_thread_t *target_th = rb_thread_ptr(target_thread);

    if (!target_th->pending_interrupt_queue) {
	return Qfalse;
    }
    if (rb_threadptr_pending_interrupt_empty_p(target_th)) {
	return Qfalse;
    }
    if (rb_check_arity(argc, 0, 1)) {
        VALUE err = argv[0];
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
    else {
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

NORETURN(static void rb_threadptr_to_kill(rb_thread_t *th));

static void
rb_threadptr_to_kill(rb_thread_t *th)
{
    rb_threadptr_pending_interrupt_clear(th);
    th->status = THREAD_RUNNABLE;
    th->to_kill = 1;
    th->ec->errinfo = INT2FIX(TAG_FATAL);
    EC_JUMP_TAG(th->ec, TAG_FATAL);
}

static inline rb_atomic_t
threadptr_get_interrupts(rb_thread_t *th)
{
    rb_execution_context_t *ec = th->ec;
    rb_atomic_t interrupt;
    rb_atomic_t old;

    do {
	interrupt = ec->interrupt_flag;
	old = ATOMIC_CAS(ec->interrupt_flag, interrupt, interrupt & ec->interrupt_mask);
    } while (old != interrupt);
    return interrupt & (rb_atomic_t)~ec->interrupt_mask;
}

MJIT_FUNC_EXPORTED int
rb_threadptr_execute_interrupts(rb_thread_t *th, int blocking_timing)
{
    rb_atomic_t interrupt;
    int postponed_job_interrupt = 0;
    int ret = FALSE;

    if (th->ec->raised_flag) return ret;

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
	    int sigwait_fd = rb_sigwait_fd_get(th);

	    if (sigwait_fd >= 0) {
		(void)consume_communication_pipe(sigwait_fd);
		ruby_sigchld_handler(th->vm);
		rb_sigwait_fd_put(th, sigwait_fd);
		rb_sigwait_fd_migrate(th->vm);
	    }
	    th->status = THREAD_RUNNABLE;
	    while ((sig = rb_get_next_signal()) != 0) {
		ret |= rb_signal_exec(th, sig);
	    }
	    th->status = prev_status;
	}

	/* exception from another thread */
	if (pending_interrupt && threadptr_pending_interrupt_active_p(th)) {
	    VALUE err = rb_threadptr_pending_interrupt_deque(th, blocking_timing ? INTERRUPT_ON_BLOCKING : INTERRUPT_NONE);
	    thread_debug("rb_thread_execute_interrupts: %"PRIdVALUE"\n", err);
            ret = TRUE;

	    if (err == Qundef) {
		/* no error */
	    }
	    else if (err == eKillSignal        /* Thread#kill received */   ||
		     err == eTerminateSignal   /* Terminate thread */       ||
		     err == INT2FIX(TAG_FATAL) /* Thread.exit etc. */         ) {
		rb_threadptr_to_kill(th);
	    }
	    else {
		if (err == th->vm->special_exceptions[ruby_error_stream_closed]) {
		    /* the only special exception to be queued across thread */
		    err = ruby_vm_special_exception_copy(err);
		}
		/* set runnable if th was slept. */
		if (th->status == THREAD_STOPPED ||
		    th->status == THREAD_STOPPED_FOREVER)
		    th->status = THREAD_RUNNABLE;
		rb_exc_raise(err);
	    }
	}

	if (timer_interrupt) {
	    uint32_t limits_us = TIME_QUANTUM_USEC;

	    if (th->priority > 0)
		limits_us <<= th->priority;
	    else
		limits_us >>= -th->priority;

	    if (th->status == THREAD_RUNNABLE)
		th->running_time_us += TIME_QUANTUM_USEC;

            VM_ASSERT(th->ec->cfp);
	    EXEC_EVENT_HOOK(th->ec, RUBY_INTERNAL_EVENT_SWITCH, th->ec->cfp->self,
			    0, 0, 0, Qundef);

	    rb_thread_schedule_limits(limits_us);
	}
    }
    return ret;
}

void
rb_thread_execute_interrupts(VALUE thval)
{
    rb_threadptr_execute_interrupts(rb_thread_ptr(thval), 1);
}

static void
rb_threadptr_ready(rb_thread_t *th)
{
    rb_threadptr_interrupt(th);
}

static VALUE
rb_threadptr_raise(rb_thread_t *target_th, int argc, VALUE *argv)
{
    VALUE exc;

    if (rb_threadptr_dead(target_th)) {
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
    if (rb_threadptr_dead(target_th)) {
	return Qnil;
    }

    rb_ec_setup_exception(GET_EC(), exc, Qundef);
    rb_threadptr_pending_interrupt_enque(target_th, exc);
    rb_threadptr_interrupt(target_th);
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

int
rb_ec_set_raised(rb_execution_context_t *ec)
{
    if (ec->raised_flag & RAISED_EXCEPTION) {
	return 1;
    }
    ec->raised_flag |= RAISED_EXCEPTION;
    return 0;
}

int
rb_ec_reset_raised(rb_execution_context_t *ec)
{
    if (!(ec->raised_flag & RAISED_EXCEPTION)) {
	return 0;
    }
    ec->raised_flag &= ~RAISED_EXCEPTION;
    return 1;
}

int
rb_notify_fd_close(int fd, struct list_head *busy)
{
    rb_vm_t *vm = GET_THREAD()->vm;
    struct waiting_fd *wfd = 0, *next;

    list_for_each_safe(&vm->waiting_fds, wfd, next, wfd_node) {
	if (wfd->fd == fd) {
	    rb_thread_t *th = wfd->th;
	    VALUE err;

	    list_del(&wfd->wfd_node);
	    list_add(busy, &wfd->wfd_node);

	    err = th->vm->special_exceptions[ruby_error_stream_closed];
	    rb_threadptr_pending_interrupt_enque(th, err);
	    rb_threadptr_interrupt(th);
	}
    }
    return !list_empty(busy);
}

void
rb_thread_fd_close(int fd)
{
    struct list_head busy;

    list_head_init(&busy);
    if (rb_notify_fd_close(fd, &busy)) {
	do rb_thread_schedule(); while (!list_empty(&busy));
    }
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
    rb_thread_t *target_th = rb_thread_ptr(self);
    const rb_thread_t *current_th = GET_THREAD();

    threadptr_check_pending_interrupt_queue(target_th);
    rb_threadptr_raise(target_th, argc, argv);

    /* To perform Thread.current.raise as Kernel.raise */
    if (current_th == target_th) {
	RUBY_VM_CHECK_INTS(target_th->ec);
    }
    return Qnil;
}


/*
 *  call-seq:
 *     thr.exit        -> thr
 *     thr.kill        -> thr
 *     thr.terminate   -> thr
 *
 *  Terminates +thr+ and schedules another thread to be run, returning
 *  the terminated Thread.  If this is the main thread, or the last
 *  thread, exits the process.
 */

VALUE
rb_thread_kill(VALUE thread)
{
    rb_thread_t *th = rb_thread_ptr(thread);

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
    rb_thread_t *th = rb_thread_ptr(thread);

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
    rb_thread_t *target_th = rb_thread_ptr(thread);
    if (target_th->status == THREAD_KILLED) return Qnil;

    rb_threadptr_ready(target_th);

    if (target_th->status == THREAD_STOPPED ||
	target_th->status == THREAD_STOPPED_FOREVER) {
	target_th->status = THREAD_RUNNABLE;
    }

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
    return rb_thread_ptr(thread)->abort_on_exception ? Qtrue : Qfalse;
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
    rb_thread_ptr(thread)->abort_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     Thread.report_on_exception   -> true or false
 *
 *  Returns the status of the global ``report on exception'' condition.
 *
 *  The default is +true+ since Ruby 2.5.
 *
 *  All threads created when this flag is true will report
 *  a message on $stderr if an exception kills the thread.
 *
 *     Thread.new { 1.times { raise } }
 *
 *  will produce this output on $stderr:
 *
 *     #<Thread:...> terminated with exception (report_on_exception is true):
 *     Traceback (most recent call last):
 *             2: from -e:1:in `block in <main>'
 *             1: from -e:1:in `times'
 *
 *  This is done to catch errors in threads early.
 *  In some cases, you might not want this output.
 *  There are multiple ways to avoid the extra output:
 *
 *  * If the exception is not intended, the best is to fix the cause of
 *    the exception so it does not happen anymore.
 *  * If the exception is intended, it might be better to rescue it closer to
 *    where it is raised rather then let it kill the Thread.
 *  * If it is guaranteed the Thread will be joined with Thread#join or
 *    Thread#value, then it is safe to disable this report with
 *    <code>Thread.current.report_on_exception = false</code>
 *    when starting the Thread.
 *    However, this might handle the exception much later, or not at all
 *    if the Thread is never joined due to the parent thread being blocked, etc.
 *
 *  See also ::report_on_exception=.
 *
 *  There is also an instance level method to set this for a specific thread,
 *  see #report_on_exception=.
  *
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
 *  Returns the new state.
 *  When set to +true+, all threads created afterwards will inherit the
 *  condition and report a message on $stderr if an exception kills a thread:
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
 *     #<Thread:...prog.rb:2> terminated with exception (report_on_exception is true):
 *     Traceback (most recent call last):
 *     prog.rb:4:in `block in <main>': Exception from thread (RuntimeError)
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
 *  The default value when creating a Thread is the value of
 *  the global flag Thread.report_on_exception.
 *
 *  See also #report_on_exception=.
 *
 *  There is also a class level method to set this for all new threads, see
 *  ::report_on_exception=.
 */

static VALUE
rb_thread_report_exc(VALUE thread)
{
    return rb_thread_ptr(thread)->report_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     thr.report_on_exception= boolean   -> true or false
 *
 *  When set to +true+, a message is printed on $stderr if an exception
 *  kills this +thr+.  See ::report_on_exception for details.
 *
 *  See also #report_on_exception.
 *
 *  There is also a class level method to set this for all new threads, see
 *  ::report_on_exception=.
 */

static VALUE
rb_thread_report_exc_set(VALUE thread, VALUE val)
{
    rb_thread_ptr(thread)->report_on_exception = RTEST(val);
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
    VALUE group = rb_thread_ptr(thread)->thgroup;
    return group == 0 ? Qnil : group;
}

static const char *
thread_status_name(rb_thread_t *th, int detail)
{
    switch (th->status) {
      case THREAD_RUNNABLE:
	return th->to_kill ? "aborting" : "run";
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
    rb_thread_t *target_th = rb_thread_ptr(thread);

    if (rb_threadptr_dead(target_th)) {
	if (!NIL_P(target_th->ec->errinfo) &&
	    !FIXNUM_P(target_th->ec->errinfo)) {
	    return Qnil;
	}
	else {
	    return Qfalse;
	}
    }
    else {
	return rb_str_new2(thread_status_name(target_th, FALSE));
    }
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
    if (rb_threadptr_dead(rb_thread_ptr(thread))) {
	return Qfalse;
    }
    else {
	return Qtrue;
    }
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
    rb_thread_t *th = rb_thread_ptr(thread);

    if (rb_threadptr_dead(th)) {
	return Qtrue;
    }
    else if (th->status == THREAD_STOPPED ||
	     th->status == THREAD_STOPPED_FOREVER) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

/*
 *  call-seq:
 *     thr.safe_level   -> integer
 *
 *  Returns the safe level.
 *
 *  This method is obsolete because $SAFE is a process global state.
 *  Simply check $SAFE.
 */

static VALUE
rb_thread_safe_level(VALUE thread)
{
    return UINT2NUM(rb_safe_level());
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
    return rb_thread_ptr(thread)->name;
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
    rb_thread_t *target_th = rb_thread_ptr(thread);

    if (!NIL_P(name)) {
	rb_encoding *enc;
	StringValueCStr(name);
	enc = rb_enc_get(name);
	if (!rb_enc_asciicompat(enc)) {
	    rb_raise(rb_eArgError, "ASCII incompatible encoding (%s)",
		     rb_enc_name(enc));
	}
	name = rb_str_new_frozen(name);
    }
    target_th->name = name;
    if (threadptr_initialized(target_th)) {
	native_set_another_thread_name(target_th->thread_id, name);
    }
    return name;
}

/*
 * call-seq:
 *   thr.to_s -> string
 *
 * Dump the name, id, and status of _thr_ to a string.
 */

static VALUE
rb_thread_to_s(VALUE thread)
{
    VALUE cname = rb_class_path(rb_obj_class(thread));
    rb_thread_t *target_th = rb_thread_ptr(thread);
    const char *status;
    VALUE str, loc;

    status = thread_status_name(target_th, TRUE);
    str = rb_sprintf("#<%"PRIsVALUE":%p", cname, (void *)thread);
    if (!NIL_P(target_th->name)) {
        rb_str_catf(str, "@%"PRIsVALUE, target_th->name);
    }
    if ((loc = threadptr_invoke_proc_location(target_th)) != Qnil) {
        rb_str_catf(str, "@%"PRIsVALUE":%"PRIsVALUE,
                    RARRAY_AREF(loc, 0), RARRAY_AREF(loc, 1));
        rb_gc_force_recycle(loc);
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
	return th->ec->local_storage_recursive_hash;
    }
    else {
	st_data_t val;
	st_table *local_storage = th->ec->local_storage;

	if (local_storage != NULL && st_lookup(local_storage, id, &val)) {
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
    return threadptr_local_aref(rb_thread_ptr(thread), id);
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

/*
 *  call-seq:
 *      thr.fetch(sym)           -> obj
 *      thr.fetch(sym) { }       -> obj
 *      thr.fetch(sym, default)  -> obj
 *
 *  Returns a fiber-local for the given key. If the key can't be
 *  found, there are several options: With no other arguments, it will
 *  raise a KeyError exception; if <i>default</i> is given, then that
 *  will be returned; if the optional code block is specified, then
 *  that will be run and its result returned.  See Thread#[] and
 *  Hash#fetch.
 */
static VALUE
rb_thread_fetch(int argc, VALUE *argv, VALUE self)
{
    VALUE key, val;
    ID id;
    rb_thread_t *target_th = rb_thread_ptr(self);
    int block_given;

    rb_check_arity(argc, 1, 2);
    key = argv[0];

    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
	rb_warn("block supersedes default value argument");
    }

    id = rb_check_id(&key);

    if (id == recursive_key) {
	return target_th->ec->local_storage_recursive_hash;
    }
    else if (id && target_th->ec->local_storage &&
	     st_lookup(target_th->ec->local_storage, id, &val)) {
	return val;
    }
    else if (block_given) {
	return rb_yield(key);
    }
    else if (argc == 1) {
	rb_key_err_raise(rb_sprintf("key not found: %+"PRIsVALUE, key), self, key);
    }
    else {
	return argv[1];
    }
}

static VALUE
threadptr_local_aset(rb_thread_t *th, ID id, VALUE val)
{
    if (id == recursive_key) {
	th->ec->local_storage_recursive_hash = val;
	return val;
    }
    else {
	st_table *local_storage = th->ec->local_storage;

	if (NIL_P(val)) {
	    if (!local_storage) return Qnil;
	    st_delete_wrap(local_storage, id);
	    return Qnil;
	}
	else {
	    if (local_storage == NULL) {
		th->ec->local_storage = local_storage = st_init_numtable();
	    }
	    st_insert(local_storage, id, val);
	    return val;
	}
    }
}

VALUE
rb_thread_local_aset(VALUE thread, ID id, VALUE val)
{
    if (OBJ_FROZEN(thread)) {
        rb_frozen_error_raise(thread, "can't modify frozen thread locals");
    }

    return threadptr_local_aset(rb_thread_ptr(thread), id, val);
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
        rb_frozen_error_raise(thread, "can't modify frozen thread locals");
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
    ID id = rb_check_id(&key);
    st_table *local_storage = rb_thread_ptr(self)->ec->local_storage;

    if (!id || local_storage == NULL) {
	return Qfalse;
    }
    else if (st_lookup(local_storage, id, 0)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
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
    st_table *local_storage = rb_thread_ptr(self)->ec->local_storage;
    VALUE ary = rb_ary_new();

    if (local_storage) {
	st_foreach(local_storage, thread_keys_i, ary);
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

    if (rb_hash_lookup(locals, ID2SYM(id)) != Qnil) {
        return Qtrue;
    }
    else {
        return Qfalse;
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
    return INT2NUM(rb_thread_ptr(thread)->priority);
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
    rb_thread_t *target_th = rb_thread_ptr(thread);
    int priority;

#if USE_NATIVE_THREAD_PRIORITY
    target_th->priority = NUM2INT(prio);
    native_thread_apply_priority(th);
#else
    priority = NUM2INT(prio);
    if (priority > RUBY_THREAD_PRIORITY_MAX) {
	priority = RUBY_THREAD_PRIORITY_MAX;
    }
    else if (priority < RUBY_THREAD_PRIORITY_MIN) {
	priority = RUBY_THREAD_PRIORITY_MIN;
    }
    target_th->priority = (int8_t)priority;
#endif
    return INT2NUM(target_th->priority);
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

#define rb_fd_no_init(fds) ((void)((fds)->fdset = 0), (void)((fds)->maxfd = 0))

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

#define rb_fd_no_init(fds) (void)((fds)->fdset = 0)

#endif

#ifndef rb_fd_no_init
#define rb_fd_no_init(fds) (void)(fds)
#endif

static int
wait_retryable(int *result, int errnum, rb_hrtime_t *rel, rb_hrtime_t end)
{
    if (*result < 0) {
        switch (errnum) {
          case EINTR:
#ifdef ERESTART
          case ERESTART:
#endif
            *result = 0;
            if (rel && hrtime_update_expire(rel, end)) {
                *rel = 0;
            }
            return TRUE;
        }
        return FALSE;
    }
    else if (*result == 0) {
	/* check for spurious wakeup */
        if (rel) {
            return !hrtime_update_expire(rel, end);
        }
        return TRUE;
    }
    return FALSE;
}

struct select_set {
    int max;
    int sigwait_fd;
    rb_thread_t *th;
    rb_fdset_t *rset;
    rb_fdset_t *wset;
    rb_fdset_t *eset;
    rb_fdset_t orig_rset;
    rb_fdset_t orig_wset;
    rb_fdset_t orig_eset;
    struct timeval *timeout;
};

static VALUE
select_set_free(VALUE p)
{
    struct select_set *set = (struct select_set *)p;

    if (set->sigwait_fd >= 0) {
        rb_sigwait_fd_put(set->th, set->sigwait_fd);
        rb_sigwait_fd_migrate(set->th->vm);
    }

    rb_fd_term(&set->orig_rset);
    rb_fd_term(&set->orig_wset);
    rb_fd_term(&set->orig_eset);

    return Qfalse;
}

static const rb_hrtime_t *
sigwait_timeout(rb_thread_t *th, int sigwait_fd, const rb_hrtime_t *orig,
                int *drained_p)
{
    static const rb_hrtime_t quantum = TIME_QUANTUM_USEC * 1000;

    if (sigwait_fd >= 0 && (!ubf_threads_empty() || BUSY_WAIT_SIGNALS)) {
        *drained_p = check_signals_nogvl(th, sigwait_fd);
        if (!orig || *orig > quantum)
            return &quantum;
    }

    return orig;
}

static VALUE
do_select(VALUE p)
{
    struct select_set *set = (struct select_set *)p;
    int result = 0;
    int lerrno;
    rb_hrtime_t *to, rel, end = 0;

    timeout_prepare(&to, &rel, &end, set->timeout);
#define restore_fdset(dst, src) \
    ((dst) ? rb_fd_dup(dst, src) : (void)0)
#define do_select_update() \
    (restore_fdset(set->rset, &set->orig_rset), \
     restore_fdset(set->wset, &set->orig_wset), \
     restore_fdset(set->eset, &set->orig_eset), \
     TRUE)

    do {
	int drained;
	lerrno = 0;

	BLOCKING_REGION(set->th, {
            const rb_hrtime_t *sto;
            struct timeval tv;

            sto = sigwait_timeout(set->th, set->sigwait_fd, to, &drained);
            if (!RUBY_VM_INTERRUPTED(set->th->ec)) {
                result = native_fd_select(set->max, set->rset, set->wset,
                                          set->eset,
                                          rb_hrtime2timeval(&tv, sto), set->th);
                if (result < 0) lerrno = errno;
            }
	}, set->sigwait_fd >= 0 ? ubf_sigwait : ubf_select, set->th, TRUE);

        if (set->sigwait_fd >= 0) {
            if (result > 0 && rb_fd_isset(set->sigwait_fd, set->rset))
                result--;
            (void)check_signals_nogvl(set->th, set->sigwait_fd);
        }

        RUBY_VM_CHECK_INTS_BLOCKING(set->th->ec); /* may raise */
    } while (wait_retryable(&result, lerrno, to, end) && do_select_update());

    if (result < 0) {
	errno = lerrno;
    }

    return (VALUE)result;
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

static rb_fdset_t *
init_set_fd(int fd, rb_fdset_t *fds)
{
    if (fd < 0) {
	return 0;
    }
    rb_fd_init(fds);
    rb_fd_set(fd, fds);

    return fds;
}

int
rb_thread_fd_select(int max, rb_fdset_t * read, rb_fdset_t * write, rb_fdset_t * except,
		    struct timeval *timeout)
{
    struct select_set set;

    set.th = GET_THREAD();
    RUBY_VM_CHECK_INTS_BLOCKING(set.th->ec);
    set.max = max;
    set.rset = read;
    set.wset = write;
    set.eset = except;
    set.timeout = timeout;

    if (!set.rset && !set.wset && !set.eset) {
        if (!timeout) {
            rb_thread_sleep_forever();
            return 0;
        }
        rb_thread_wait_for(*timeout);
        return 0;
    }

    set.sigwait_fd = rb_sigwait_fd_get(set.th);
    if (set.sigwait_fd >= 0) {
        if (set.rset)
            rb_fd_set(set.sigwait_fd, set.rset);
        else
            set.rset = init_set_fd(set.sigwait_fd, &set.orig_rset);
        if (set.sigwait_fd >= set.max) {
            set.max = set.sigwait_fd + 1;
        }
    }
#define fd_init_copy(f) do { \
        if (set.f) { \
            rb_fd_resize(set.max - 1, set.f); \
            if (&set.orig_##f != set.f) { /* sigwait_fd */ \
                rb_fd_init_copy(&set.orig_##f, set.f); \
            } \
        } \
        else { \
            rb_fd_no_init(&set.orig_##f); \
        } \
    } while (0)
    fd_init_copy(rset);
    fd_init_copy(wset);
    fd_init_copy(eset);
#undef fd_init_copy

    return (int)rb_ensure(do_select, (VALUE)&set, select_set_free, (VALUE)&set);
}

#ifdef USE_POLL

/* The same with linux kernel. TODO: make platform independent definition. */
#define POLLIN_SET (POLLRDNORM | POLLRDBAND | POLLIN | POLLHUP | POLLERR)
#define POLLOUT_SET (POLLWRBAND | POLLWRNORM | POLLOUT | POLLERR)
#define POLLEX_SET (POLLPRI)

#ifndef POLLERR_SET /* defined for FreeBSD for now */
#  define POLLERR_SET (0)
#endif

/*
 * returns a mask of events
 */
int
rb_wait_for_single_fd(int fd, int events, struct timeval *timeout)
{
    struct pollfd fds[2];
    int result = 0, lerrno;
    rb_hrtime_t *to, rel, end = 0;
    int drained;
    nfds_t nfds;
    rb_unblock_function_t *ubf;
    struct waiting_fd wfd;
    int state;

    wfd.th = GET_THREAD();
    wfd.fd = fd;
    list_add(&wfd.th->vm->waiting_fds, &wfd.wfd_node);
    EC_PUSH_TAG(wfd.th->ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        RUBY_VM_CHECK_INTS_BLOCKING(wfd.th->ec);
        timeout_prepare(&to, &rel, &end, timeout);
        fds[0].fd = fd;
        fds[0].events = (short)events;
        fds[0].revents = 0;
        do {
            fds[1].fd = rb_sigwait_fd_get(wfd.th);

            if (fds[1].fd >= 0) {
                fds[1].events = POLLIN;
                fds[1].revents = 0;
                nfds = 2;
                ubf = ubf_sigwait;
            }
            else {
                nfds = 1;
                ubf = ubf_select;
            }

            lerrno = 0;
            BLOCKING_REGION(wfd.th, {
                const rb_hrtime_t *sto;
                struct timespec ts;

                sto = sigwait_timeout(wfd.th, fds[1].fd, to, &drained);
                if (!RUBY_VM_INTERRUPTED(wfd.th->ec)) {
                    result = ppoll(fds, nfds, rb_hrtime2timespec(&ts, sto), 0);
                    if (result < 0) lerrno = errno;
                }
            }, ubf, wfd.th, TRUE);

            if (fds[1].fd >= 0) {
                if (result > 0 && fds[1].revents) {
                    result--;
                }
                (void)check_signals_nogvl(wfd.th, fds[1].fd);
                rb_sigwait_fd_put(wfd.th, fds[1].fd);
                rb_sigwait_fd_migrate(wfd.th->vm);
            }
            RUBY_VM_CHECK_INTS_BLOCKING(wfd.th->ec);
        } while (wait_retryable(&result, lerrno, to, end));
    }
    EC_POP_TAG();
    list_del(&wfd.wfd_node);
    if (state) {
        EC_JUMP_TAG(wfd.th->ec, state);
    }

    if (result < 0) {
	errno = lerrno;
	return -1;
    }

    if (fds[0].revents & POLLNVAL) {
	errno = EBADF;
	return -1;
    }

    /*
     * POLLIN, POLLOUT have a different meanings from select(2)'s read/write bit.
     * Therefore we need to fix it up.
     */
    result = 0;
    if (fds[0].revents & POLLIN_SET)
	result |= RB_WAITFD_IN;
    if (fds[0].revents & POLLOUT_SET)
	result |= RB_WAITFD_OUT;
    if (fds[0].revents & POLLEX_SET)
	result |= RB_WAITFD_PRI;

    /* all requested events are ready if there is an error */
    if (fds[0].revents & POLLERR_SET)
	result |= events;

    return result;
}
#else /* ! USE_POLL - implement rb_io_poll_fd() using select() */
struct select_args {
    union {
	int fd;
	int error;
    } as;
    rb_fdset_t *read;
    rb_fdset_t *write;
    rb_fdset_t *except;
    struct waiting_fd wfd;
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

    list_del(&args->wfd.wfd_node);
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
    args.wfd.fd = fd;
    args.wfd.th = GET_THREAD();

    list_add(&args.wfd.th->vm->waiting_fds, &args.wfd.wfd_node);
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
	threadptr_trap_interrupt(mth);
    }
}

static void
timer_thread_function(void)
{
    volatile rb_execution_context_t *ec;

    /* for time slice */
    ec = ACCESS_ONCE(rb_execution_context_t *,
                     ruby_current_execution_context_ptr);
    if (ec) RUBY_VM_SET_TIMER_INTERRUPT(ec);
}

static void
async_bug_fd(const char *mesg, int errno_arg, int fd)
{
    char buff[64];
    size_t n = strlcpy(buff, mesg, sizeof(buff));
    if (n < sizeof(buff)-3) {
	ruby_snprintf(buff+n, sizeof(buff)-n, "(%d)", fd);
    }
    rb_async_bug_errno(buff, errno_arg);
}

/* VM-dependent API is not available for this function */
static int
consume_communication_pipe(int fd)
{
#if USE_EVENTFD
    uint64_t buff[1];
#else
    /* buffer can be shared because no one refers to them. */
    static char buff[1024];
#endif
    ssize_t result;
    int ret = FALSE; /* for rb_sigwait_sleep */

    /*
     * disarm UBF_TIMER before we read, because it can become
     * re-armed at any time via sighandler and the pipe will refill
     * We can disarm it because this thread is now processing signals
     * and we do not want unnecessary SIGVTALRM
     */
    ubf_timer_disarm();

    while (1) {
	result = read(fd, buff, sizeof(buff));
	if (result > 0) {
	    ret = TRUE;
	    if (USE_EVENTFD || result < (ssize_t)sizeof(buff)) {
		return ret;
	    }
	}
	else if (result == 0) {
	    return ret;
	}
	else if (result < 0) {
	    int e = errno;
	    switch (e) {
	      case EINTR:
		continue; /* retry */
	      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	      case EWOULDBLOCK:
#endif
		return ret;
	      default:
		async_bug_fd("consume_communication_pipe: read", e, fd);
	    }
	}
    }
}

static int
check_signals_nogvl(rb_thread_t *th, int sigwait_fd)
{
    rb_vm_t *vm = GET_VM(); /* th may be 0 */
    int ret = consume_communication_pipe(sigwait_fd);
    ubf_wakeup_all_threads();
    ruby_sigchld_handler(vm);
    if (rb_signal_buff_size()) {
        if (th == vm->main_thread)
            /* no need to lock + wakeup if already in main thread */
            RUBY_VM_SET_TRAP_INTERRUPT(th->ec);
        else
            threadptr_trap_interrupt(vm->main_thread);
        ret = TRUE; /* for SIGCHLD_LOSSY && rb_sigwait_sleep */
    }
    return ret;
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

static int
clear_coverage_i(st_data_t key, st_data_t val, st_data_t dummy)
{
    int i;
    VALUE coverage = (VALUE)val;
    VALUE lines = RARRAY_AREF(coverage, COVERAGE_INDEX_LINES);
    VALUE branches = RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES);

    if (lines) {
        if (GET_VM()->coverage_mode & COVERAGE_TARGET_ONESHOT_LINES) {
            rb_ary_clear(lines);
        }
        else {
            int i;
            for (i = 0; i < RARRAY_LEN(lines); i++) {
                if (RARRAY_AREF(lines, i) != Qnil)
                    RARRAY_ASET(lines, i, INT2FIX(0));
            }
        }
    }
    if (branches) {
	VALUE counters = RARRAY_AREF(branches, 1);
	for (i = 0; i < RARRAY_LEN(counters); i++) {
	    RARRAY_ASET(counters, i, INT2FIX(0));
	}
    }

    return ST_CONTINUE;
}

void
rb_clear_coverages(void)
{
    VALUE coverages = rb_get_coverages();
    if (RTEST(coverages)) {
        rb_hash_foreach(coverages, clear_coverage_i, 0);
    }
}

#if defined(HAVE_WORKING_FORK)
static void
rb_thread_atfork_internal(rb_thread_t *th, void (*atfork)(rb_thread_t *, const rb_thread_t *))
{
    rb_thread_t *i = 0;
    rb_vm_t *vm = th->vm;
    vm->main_thread = th;

    gvl_atfork(th->vm);
    ubf_list_atfork();

    list_for_each(&vm->living_threads, i, vmlt_node) {
	atfork(i, th);
    }
    rb_vm_living_threads_init(vm);
    rb_vm_living_threads_insert(vm, th);

    /* may be held by MJIT threads in parent */
    rb_native_mutex_initialize(&vm->waitpid_lock);
    rb_native_mutex_initialize(&vm->workqueue_lock);

    /* may be held by any thread in parent */
    rb_native_mutex_initialize(&th->interrupt_lock);

    vm->fork_gen++;

    vm->sleeper = 0;
    rb_clear_coverages();
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

void rb_fiber_atfork(rb_thread_t *);
void
rb_thread_atfork(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_thread_atfork_internal(th, terminate_atfork_i);
    th->join_list = NULL;
    rb_fiber_atfork(th);

    /* We don't want reproduce CVE-2003-0900. */
    rb_reset_random_seed();

    /* For child, starting MJIT worker thread in this place which is safer than immediately after `after_fork_ruby`. */
    mjit_child_after_fork();
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
 *     thr = Thread.new { Thread.stop }    #=> #<Thread:0x402a7210 sleep>
 *     tg = ThreadGroup.new                #=> #<ThreadGroup:0x402752d4>
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
    rb_thread_t *target_th = rb_thread_ptr(thread);
    struct thgroup *data;

    if (OBJ_FROZEN(group)) {
	rb_raise(rb_eThreadError, "can't move to the frozen thread group");
    }
    TypedData_Get_Struct(group, struct thgroup, &thgroup_data_type, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError, "can't move to the enclosed thread group");
    }

    if (!target_th->thgroup) {
	return Qnil;
    }

    if (OBJ_FROZEN(target_th->thgroup)) {
	rb_raise(rb_eThreadError, "can't move from the frozen thread group");
    }
    TypedData_Get_Struct(target_th->thgroup, struct thgroup, &thgroup_data_type, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError,
		 "can't move from the enclosed thread group");
    }

    target_th->thgroup = group;
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
#define rb_thread_shield_waiting(b) ((RBASIC(b)->flags&THREAD_SHIELD_WAITING_MASK)>>THREAD_SHIELD_WAITING_SHIFT)

static inline void
rb_thread_shield_waiting_inc(VALUE b)
{
    unsigned long w = rb_thread_shield_waiting(b);
    w++;
    if (w > (THREAD_SHIELD_WAITING_MASK>>THREAD_SHIELD_WAITING_SHIFT))
	rb_raise(rb_eRuntimeError, "waiting count overflow");
    RBASIC(b)->flags &= ~THREAD_SHIELD_WAITING_MASK;
    RBASIC(b)->flags |= ((VALUE)w << THREAD_SHIELD_WAITING_SHIFT);
}

static inline void
rb_thread_shield_waiting_dec(VALUE b)
{
    unsigned long w = rb_thread_shield_waiting(b);
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
    m = mutex_ptr(mutex);
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
    return th->ec->local_storage_recursive_hash;
}

static void
threadptr_recursive_hash_set(rb_thread_t *th, VALUE hash)
{
    th->ec->local_storage_recursive_hash = hash;
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
    p.objid = rb_memory_id(obj);
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
	enum ruby_tag_type state;

	p.func = func;

	if (outermost) {
	    recursive_push(p.list, ID2SYM(recursive_key), 0);
	    recursive_push(p.list, p.objid, p.pairid);
	    result = rb_catch_protect(p.list, exec_recursive_i, (VALUE)&p, &state);
	    if (!recursive_pop(p.list, p.objid, p.pairid)) goto invalid;
	    if (!recursive_pop(p.list, ID2SYM(recursive_key), 0)) goto invalid;
	    if (state != TAG_NONE) EC_JUMP_TAG(GET_EC(), state);
	    if (result == p.list) {
		result = (*func)(obj, arg, TRUE);
	    }
	}
	else {
	    volatile VALUE ret = Qundef;
	    recursive_push(p.list, p.objid, p.pairid);
	    EC_PUSH_TAG(GET_EC());
	    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
		ret = (*func)(obj, arg, FALSE);
	    }
	    EC_POP_TAG();
	    if (!recursive_pop(p.list, p.objid, p.pairid)) {
	      invalid:
		rb_raise(rb_eTypeError, "invalid inspect_tbl pair_list "
			 "for %+"PRIsVALUE" in %+"PRIsVALUE,
			 sym, rb_thread_current());
	    }
	    if (state != TAG_NONE) EC_JUMP_TAG(GET_EC(), state);
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
    return exec_recursive(func, obj, rb_memory_id(paired_obj), arg, 0);
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
    return exec_recursive(func, obj, rb_memory_id(paired_obj), arg, 1);
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
    rb_define_method(rb_cThread, "fetch", rb_thread_fetch, -1);
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
    rb_define_method(rb_cThread, "to_s", rb_thread_to_s, 0);
    rb_define_alias(rb_cThread, "inspect", "to_s");

    rb_vm_register_special_exception(ruby_error_stream_closed, rb_eIOError,
				     "stream closed in another thread");

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
            rb_native_mutex_initialize(&th->vm->waitpid_lock);
            rb_native_mutex_initialize(&th->vm->workqueue_lock);
            rb_native_mutex_initialize(&th->interrupt_lock);

	    th->pending_interrupt_queue = rb_ary_tmp_new(0);
	    th->pending_interrupt_queue_checked = 0;
	    th->pending_interrupt_mask_stack = rb_ary_tmp_new(0);
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

static void
debug_deadlock_check(rb_vm_t *vm, VALUE msg)
{
    rb_thread_t *th = 0;
    VALUE sep = rb_str_new_cstr("\n   ");

    rb_str_catf(msg, "\n%d threads, %d sleeps current:%p main thread:%p\n",
		vm_living_thread_num(vm), vm->sleeper, (void *)GET_THREAD(), (void *)vm->main_thread);
    list_for_each(&vm->living_threads, th, vmlt_node) {
	rb_str_catf(msg, "* %+"PRIsVALUE"\n   rb_thread_t:%p "
		    "native:%"PRI_THREAD_ID" int:%u",
		    th->self, (void *)th, thread_id_str(th), th->ec->interrupt_flag);
	if (th->locking_mutex) {
	    rb_mutex_t *mutex = mutex_ptr(th->locking_mutex);
	    rb_str_catf(msg, " mutex:%p cond:%"PRIuSIZE,
			(void *)mutex->th, rb_mutex_num_waiting(mutex));
	}
	{
	    rb_thread_list_t *list = th->join_list;
	    while (list) {
		rb_str_catf(msg, "\n    depended by: tb_thread_id:%p", (void *)list->th);
		list = list->next;
	    }
	}
	rb_str_catf(msg, "\n   ");
	rb_str_concat(msg, rb_ary_join(rb_ec_backtrace_str_ary(th->ec, 0, 0), sep));
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
	if (th->status != THREAD_STOPPED_FOREVER || RUBY_VM_INTERRUPTED(th->ec)) {
	    found = 1;
	}
	else if (th->locking_mutex) {
	    rb_mutex_t *mutex = mutex_ptr(th->locking_mutex);

	    if (mutex->th == th || (!mutex->th && !list_empty(&mutex->waitq))) {
		found = 1;
	    }
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
update_line_coverage(VALUE data, const rb_trace_arg_t *trace_arg)
{
    const rb_control_frame_t *cfp = GET_EC()->cfp;
    VALUE coverage = rb_iseq_coverage(cfp->iseq);
    if (RB_TYPE_P(coverage, T_ARRAY) && !RBASIC_CLASS(coverage)) {
	VALUE lines = RARRAY_AREF(coverage, COVERAGE_INDEX_LINES);
	if (lines) {
	    long line = rb_sourceline() - 1;
	    long count;
	    VALUE num;
            void rb_iseq_clear_event_flags(const rb_iseq_t *iseq, size_t pos, rb_event_flag_t reset);
            if (GET_VM()->coverage_mode & COVERAGE_TARGET_ONESHOT_LINES) {
                rb_iseq_clear_event_flags(cfp->iseq, cfp->pc - cfp->iseq->body->iseq_encoded - 1, RUBY_EVENT_COVERAGE_LINE);
                rb_ary_push(lines, LONG2FIX(line + 1));
                return;
            }
	    if (line >= RARRAY_LEN(lines)) { /* no longer tracked */
		return;
	    }
	    num = RARRAY_AREF(lines, line);
	    if (!FIXNUM_P(num)) return;
	    count = FIX2LONG(num) + 1;
	    if (POSFIXABLE(count)) {
		RARRAY_ASET(lines, line, LONG2FIX(count));
	    }
	}
    }
}

static void
update_branch_coverage(VALUE data, const rb_trace_arg_t *trace_arg)
{
    const rb_control_frame_t *cfp = GET_EC()->cfp;
    VALUE coverage = rb_iseq_coverage(cfp->iseq);
    if (RB_TYPE_P(coverage, T_ARRAY) && !RBASIC_CLASS(coverage)) {
	VALUE branches = RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES);
	if (branches) {
            long pc = cfp->pc - cfp->iseq->body->iseq_encoded - 1;
            long idx = FIX2INT(RARRAY_AREF(ISEQ_PC2BRANCHINDEX(cfp->iseq), pc)), count;
	    VALUE counters = RARRAY_AREF(branches, 1);
	    VALUE num = RARRAY_AREF(counters, idx);
	    count = FIX2LONG(num) + 1;
	    if (POSFIXABLE(count)) {
		RARRAY_ASET(counters, idx, LONG2FIX(count));
	    }
	}
    }
}

const rb_method_entry_t *
rb_resolve_me_location(const rb_method_entry_t *me, VALUE resolved_location[5])
{
    VALUE path, beg_pos_lineno, beg_pos_column, end_pos_lineno, end_pos_column;

  retry:
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ: {
	const rb_iseq_t *iseq = me->def->body.iseq.iseqptr;
	rb_iseq_location_t *loc = &iseq->body->location;
	path = rb_iseq_path(iseq);
	beg_pos_lineno = INT2FIX(loc->code_location.beg_pos.lineno);
	beg_pos_column = INT2FIX(loc->code_location.beg_pos.column);
	end_pos_lineno = INT2FIX(loc->code_location.end_pos.lineno);
	end_pos_column = INT2FIX(loc->code_location.end_pos.column);
	break;
      }
      case VM_METHOD_TYPE_BMETHOD: {
        const rb_iseq_t *iseq = rb_proc_get_iseq(me->def->body.bmethod.proc, 0);
	if (iseq) {
	    rb_iseq_location_t *loc;
	    rb_iseq_check(iseq);
	    path = rb_iseq_path(iseq);
	    loc = &iseq->body->location;
	    beg_pos_lineno = INT2FIX(loc->code_location.beg_pos.lineno);
	    beg_pos_column = INT2FIX(loc->code_location.beg_pos.column);
	    end_pos_lineno = INT2FIX(loc->code_location.end_pos.lineno);
	    end_pos_column = INT2FIX(loc->code_location.end_pos.column);
	    break;
	}
	return NULL;
      }
      case VM_METHOD_TYPE_ALIAS:
	me = me->def->body.alias.original_me;
	goto retry;
      case VM_METHOD_TYPE_REFINED:
	me = me->def->body.refined.orig_me;
	if (!me) return NULL;
	goto retry;
      default:
	return NULL;
    }

    /* found */
    if (RB_TYPE_P(path, T_ARRAY)) {
	path = rb_ary_entry(path, 1);
	if (!RB_TYPE_P(path, T_STRING)) return NULL; /* just for the case... */
    }
    if (resolved_location) {
	resolved_location[0] = path;
	resolved_location[1] = beg_pos_lineno;
	resolved_location[2] = beg_pos_column;
	resolved_location[3] = end_pos_lineno;
	resolved_location[4] = end_pos_column;
    }
    return me;
}

static void
update_method_coverage(VALUE me2counter, rb_trace_arg_t *trace_arg)
{
    const rb_control_frame_t *cfp = GET_EC()->cfp;
    const rb_callable_method_entry_t *cme = rb_vm_frame_method_entry(cfp);
    const rb_method_entry_t *me = (const rb_method_entry_t *)cme;
    VALUE rcount;
    long count;

    me = rb_resolve_me_location(me, 0);
    if (!me) return;

    rcount = rb_hash_aref(me2counter, (VALUE) me);
    count = FIXNUM_P(rcount) ? FIX2LONG(rcount) + 1 : 1;
    if (POSFIXABLE(count)) {
	rb_hash_aset(me2counter, (VALUE) me, LONG2FIX(count));
    }
}

VALUE
rb_get_coverages(void)
{
    return GET_VM()->coverages;
}

int
rb_get_coverage_mode(void)
{
    return GET_VM()->coverage_mode;
}

void
rb_set_coverages(VALUE coverages, int mode, VALUE me2counter)
{
    GET_VM()->coverages = coverages;
    GET_VM()->coverage_mode = mode;
    rb_add_event_hook2((rb_event_hook_func_t) update_line_coverage, RUBY_EVENT_COVERAGE_LINE, Qnil, RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    if (mode & COVERAGE_TARGET_BRANCHES) {
	rb_add_event_hook2((rb_event_hook_func_t) update_branch_coverage, RUBY_EVENT_COVERAGE_BRANCH, Qnil, RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    }
    if (mode & COVERAGE_TARGET_METHODS) {
	rb_add_event_hook2((rb_event_hook_func_t) update_method_coverage, RUBY_EVENT_CALL, me2counter, RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
    }
}

/* Make coverage arrays empty so old covered files are no longer tracked. */
void
rb_reset_coverages(void)
{
    rb_clear_coverages();
    rb_iseq_remove_coverage_all();
    GET_VM()->coverages = Qfalse;
    rb_remove_event_hook((rb_event_hook_func_t) update_line_coverage);
    if (GET_VM()->coverage_mode & COVERAGE_TARGET_BRANCHES) {
	rb_remove_event_hook((rb_event_hook_func_t) update_branch_coverage);
    }
    if (GET_VM()->coverage_mode & COVERAGE_TARGET_METHODS) {
	rb_remove_event_hook((rb_event_hook_func_t) update_method_coverage);
    }
}

VALUE
rb_default_coverage(int n)
{
    VALUE coverage = rb_ary_tmp_new_fill(3);
    VALUE lines = Qfalse, branches = Qfalse;
    int mode = GET_VM()->coverage_mode;

    if (mode & COVERAGE_TARGET_LINES) {
	lines = n > 0 ? rb_ary_tmp_new_fill(n) : rb_ary_tmp_new(0);
    }
    RARRAY_ASET(coverage, COVERAGE_INDEX_LINES, lines);

    if (mode & COVERAGE_TARGET_BRANCHES) {
	branches = rb_ary_tmp_new_fill(2);
	/* internal data structures for branch coverage:
	 *
	 * [[base_type, base_first_lineno, base_first_column, base_last_lineno, base_last_column,
	 *   target_type_1, target_first_lineno_1, target_first_column_1, target_last_lineno_1, target_last_column_1, target_counter_index_1,
	 *   target_type_2, target_first_lineno_2, target_first_column_2, target_last_lineno_2, target_last_column_2, target_counter_index_2, ...],
	 *  ...]
	 *
	 * Example: [[:case, 1, 0, 4, 3,
	 *            :when, 2, 8, 2, 9, 0,
	 *            :when, 3, 8, 3, 9, 1, ...],
	 *           ...]
	 */
	RARRAY_ASET(branches, 0, rb_ary_tmp_new(0));
	/* branch execution counters */
	RARRAY_ASET(branches, 1, rb_ary_tmp_new(0));
    }
    RARRAY_ASET(coverage, COVERAGE_INDEX_BRANCHES, branches);

    return coverage;
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
