/* -*-c-*- */
/**********************************************************************

  thread_pthread.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include "gc.h"
#include "mjit.h"

#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
#ifdef HAVE_THR_STKSEGMENT
#include <thread.h>
#endif
#if HAVE_FCNTL_H
#include <fcntl.h>
#elif HAVE_SYS_FCNTL_H
#include <sys/fcntl.h>
#endif
#ifdef HAVE_SYS_PRCTL_H
#include <sys/prctl.h>
#endif
#if defined(HAVE_SYS_TIME_H)
#include <sys/time.h>
#endif
#if defined(__HAIKU__)
#include <kernel/OS.h>
#endif
#include <time.h>
#include <signal.h>

#if defined(HAVE_SYS_EVENTFD_H) && defined(HAVE_EVENTFD)
#  define USE_EVENTFD (1)
#  include <sys/eventfd.h>
#else
#  define USE_EVENTFD (0)
#endif

#if defined(SIGVTALRM) && !defined(__CYGWIN__)
#  define USE_UBF_LIST 1
#endif

/*
 * UBF_TIMER and ubf_list both use SIGVTALRM.
 *
 * UBF_TIMER has NOTHING to do with thread timeslices (TIMER_INTERRUPT_MASK)
 *
 * UBF_TIMER is to close TOCTTOU signal race on programs where we
 * cannot rely on GVL contention (vm->gvl.timer) to perform wakeups
 * while a thread is doing blocking I/O on sockets or pipes.  With
 * rb_thread_call_without_gvl and similar functions:
 *
 * (1) Check interrupts.
 * (2) release GVL.
 * (2a) signal received
 * (3) call func with data1 (blocks for a long time without ubf_timer)
 * (4) acquire GVL.
 *     Other Ruby threads can not run in parallel any more.
 * (5) Check interrupts.
 *
 * We need UBF_TIMER to break out of (3) if (2a) happens.
 *
 * ubf_list wakeups may be triggered on gvl_yield.
 *
 * If we have vm->gvl.timer (on GVL contention), we don't need UBF_TIMER
 * as it can perform the same tasks while doing timeslices.
 */
#define UBF_TIMER_NONE 0
#define UBF_TIMER_POSIX 1
#define UBF_TIMER_PTHREAD 2

#ifndef UBF_TIMER
#  if defined(HAVE_TIMER_SETTIME) && defined(HAVE_TIMER_CREATE) && \
      defined(CLOCK_MONOTONIC) && defined(USE_UBF_LIST)
     /* preferred */
#    define UBF_TIMER UBF_TIMER_POSIX
#  elif defined(USE_UBF_LIST)
     /* safe, but inefficient */
#    define UBF_TIMER UBF_TIMER_PTHREAD
#  else
     /* we'll be racy without SIGVTALRM for ubf_list */
#    define UBF_TIMER UBF_TIMER_NONE
#  endif
#endif

enum rtimer_state {
    /* alive, after timer_create: */
    RTIMER_DISARM,
    RTIMER_ARMING,
    RTIMER_ARMED,

    RTIMER_DEAD
};

#if UBF_TIMER == UBF_TIMER_POSIX
static const struct itimerspec zero;
static struct {
    rb_atomic_t state; /* rtimer_state */
    rb_pid_t owner;
    timer_t timerid;
} timer_posix = {
    /* .state = */ RTIMER_DEAD,
};

#elif UBF_TIMER == UBF_TIMER_PTHREAD
static void *timer_pthread_fn(void *);
static struct {
    int low[2];
    rb_atomic_t armed; /* boolean */
    rb_pid_t owner;
    pthread_t thid;
} timer_pthread = {
    { -1, -1 },
};
#endif

void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
static int native_mutex_trylock(rb_nativethread_lock_t *lock);
void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);
void rb_native_cond_signal(rb_nativethread_cond_t *cond);
void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);
void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
void rb_native_cond_destroy(rb_nativethread_cond_t *cond);
static void clear_thread_cache_altstack(void);
static void ubf_wakeup_all_threads(void);
static int ubf_threads_empty(void);
static int native_cond_timedwait(rb_nativethread_cond_t *, pthread_mutex_t *,
                                 const rb_hrtime_t *abs);
static const rb_hrtime_t *sigwait_timeout(rb_thread_t *, int sigwait_fd,
                                              const rb_hrtime_t *,
                                              int *drained_p);
static void ubf_timer_disarm(void);
static void threadptr_trap_interrupt(rb_thread_t *);

#define TIMER_THREAD_CREATED_P() (signal_self_pipe.owner_process == getpid())

/* for testing, and in case we come across a platform w/o pipes: */
#define BUSY_WAIT_SIGNALS (0)

/*
 * sigwait_th is the thread which owns sigwait_fd and sleeps on it
 * (using ppoll).  MJIT worker can be sigwait_th==0, so we initialize
 * it to THREAD_INVALID at startup and fork time.  It is the ONLY thread
 * allowed to read from sigwait_fd, otherwise starvation can occur.
 */
#define THREAD_INVALID ((const rb_thread_t *)-1)
static const rb_thread_t *sigwait_th;

#ifdef HAVE_SCHED_YIELD
#define native_thread_yield() (void)sched_yield()
#else
#define native_thread_yield() ((void)0)
#endif

#if defined(HAVE_PTHREAD_CONDATTR_SETCLOCK) && \
    defined(CLOCK_REALTIME) && defined(CLOCK_MONOTONIC) && \
    defined(HAVE_CLOCK_GETTIME)
static pthread_condattr_t condattr_mono;
static pthread_condattr_t *condattr_monotonic = &condattr_mono;
#else
static const void *const condattr_monotonic = NULL;
#endif

/* 100ms.  10ms is too small for user level thread scheduling
 * on recent Linux (tested on 2.6.35)
 */
#define TIME_QUANTUM_MSEC (100)
#define TIME_QUANTUM_USEC (TIME_QUANTUM_MSEC * 1000)
#define TIME_QUANTUM_NSEC (TIME_QUANTUM_USEC * 1000)

static rb_hrtime_t native_cond_timeout(rb_nativethread_cond_t *, rb_hrtime_t);

/*
 * Designate the next gvl.timer thread, favor the last thread in
 * the waitq since it will be in waitq longest
 */
static int
designate_timer_thread(rb_vm_t *vm)
{
    native_thread_data_t *last;

    last = list_tail(&vm->gvl.waitq, native_thread_data_t, node.ubf);
    if (last) {
        rb_native_cond_signal(&last->cond.gvlq);
        return TRUE;
    }
    return FALSE;
}

/*
 * We become designated timer thread to kick vm->gvl.owner
 * periodically.  Continue on old timeout if it expired.
 */
static void
do_gvl_timer(rb_vm_t *vm, rb_thread_t *th)
{
    static rb_hrtime_t abs;
    native_thread_data_t *nd = &th->native_thread_data;

    vm->gvl.timer = th;

    /* take over wakeups from UBF_TIMER */
    ubf_timer_disarm();

    if (vm->gvl.timer_err == ETIMEDOUT) {
        abs = native_cond_timeout(&nd->cond.gvlq, TIME_QUANTUM_NSEC);
    }
    vm->gvl.timer_err = native_cond_timedwait(&nd->cond.gvlq, &vm->gvl.lock, &abs);

    ubf_wakeup_all_threads();
    ruby_sigchld_handler(vm);
    if (UNLIKELY(rb_signal_buff_size())) {
        if (th == vm->main_thread) {
            RUBY_VM_SET_TRAP_INTERRUPT(th->ec);
        }
        else {
            threadptr_trap_interrupt(vm->main_thread);
        }
    }

    /*
     * Timeslice.  Warning: the process may fork while this
     * thread is contending for GVL:
     */
    if (vm->gvl.owner) timer_thread_function();
    vm->gvl.timer = 0;
}

static void
gvl_acquire_common(rb_vm_t *vm, rb_thread_t *th)
{
    if (vm->gvl.owner) {
        native_thread_data_t *nd = &th->native_thread_data;

        VM_ASSERT(th->unblock.func == 0 &&
	          "we must not be in ubf_list and GVL waitq at the same time");

        list_add_tail(&vm->gvl.waitq, &nd->node.gvl);

        do {
            if (!vm->gvl.timer) {
                do_gvl_timer(vm, th);
            }
            else {
                rb_native_cond_wait(&nd->cond.gvlq, &vm->gvl.lock);
            }
        } while (vm->gvl.owner);

        list_del_init(&nd->node.gvl);

        if (vm->gvl.need_yield) {
            vm->gvl.need_yield = 0;
            rb_native_cond_signal(&vm->gvl.switch_cond);
        }
    }
    else { /* reset timer if uncontended */
        vm->gvl.timer_err = ETIMEDOUT;
    }
    vm->gvl.owner = th;
    if (!vm->gvl.timer) {
        if (!designate_timer_thread(vm) && !ubf_threads_empty()) {
            rb_thread_wakeup_timer_thread(-1);
        }
    }
}

static void
gvl_acquire(rb_vm_t *vm, rb_thread_t *th)
{
    rb_native_mutex_lock(&vm->gvl.lock);
    gvl_acquire_common(vm, th);
    rb_native_mutex_unlock(&vm->gvl.lock);
}

static const native_thread_data_t *
gvl_release_common(rb_vm_t *vm)
{
    native_thread_data_t *next;
    vm->gvl.owner = 0;
    next = list_top(&vm->gvl.waitq, native_thread_data_t, node.ubf);
    if (next) rb_native_cond_signal(&next->cond.gvlq);

    return next;
}

static void
gvl_release(rb_vm_t *vm)
{
    rb_native_mutex_lock(&vm->gvl.lock);
    gvl_release_common(vm);
    rb_native_mutex_unlock(&vm->gvl.lock);
}

static void
gvl_yield(rb_vm_t *vm, rb_thread_t *th)
{
    const native_thread_data_t *next;

    /*
     * Perhaps other threads are stuck in blocking region w/o GVL, too,
     * (perhaps looping in io_close_fptr) so we kick them:
     */
    ubf_wakeup_all_threads();
    rb_native_mutex_lock(&vm->gvl.lock);
    next = gvl_release_common(vm);

    /* An another thread is processing GVL yield. */
    if (UNLIKELY(vm->gvl.wait_yield)) {
        while (vm->gvl.wait_yield)
            rb_native_cond_wait(&vm->gvl.switch_wait_cond, &vm->gvl.lock);
    }
    else if (next) {
        /* Wait until another thread task takes GVL. */
        vm->gvl.need_yield = 1;
        vm->gvl.wait_yield = 1;
        while (vm->gvl.need_yield)
            rb_native_cond_wait(&vm->gvl.switch_cond, &vm->gvl.lock);
        vm->gvl.wait_yield = 0;
        rb_native_cond_broadcast(&vm->gvl.switch_wait_cond);
    }
    else {
        rb_native_mutex_unlock(&vm->gvl.lock);
        native_thread_yield();
        rb_native_mutex_lock(&vm->gvl.lock);
        rb_native_cond_broadcast(&vm->gvl.switch_wait_cond);
    }
    gvl_acquire_common(vm, th);
    rb_native_mutex_unlock(&vm->gvl.lock);
}

static void
gvl_init(rb_vm_t *vm)
{
    rb_native_mutex_initialize(&vm->gvl.lock);
    rb_native_cond_initialize(&vm->gvl.switch_cond);
    rb_native_cond_initialize(&vm->gvl.switch_wait_cond);
    list_head_init(&vm->gvl.waitq);
    vm->gvl.owner = 0;
    vm->gvl.timer = 0;
    vm->gvl.timer_err = ETIMEDOUT;
    vm->gvl.need_yield = 0;
    vm->gvl.wait_yield = 0;
}

static void
gvl_destroy(rb_vm_t *vm)
{
    /*
     * only called once at VM shutdown (not atfork), another thread
     * may still grab vm->gvl.lock when calling gvl_release at
     * the end of thread_start_func_2
     */
    if (0) {
        rb_native_cond_destroy(&vm->gvl.switch_wait_cond);
        rb_native_cond_destroy(&vm->gvl.switch_cond);
        rb_native_mutex_destroy(&vm->gvl.lock);
    }
    clear_thread_cache_altstack();
}

#if defined(HAVE_WORKING_FORK)
static void thread_cache_reset(void);
static void
gvl_atfork(rb_vm_t *vm)
{
    thread_cache_reset();
    gvl_init(vm);
    gvl_acquire(vm, GET_THREAD());
}
#endif

#define NATIVE_MUTEX_LOCK_DEBUG 0

static void
mutex_debug(const char *msg, void *lock)
{
    if (NATIVE_MUTEX_LOCK_DEBUG) {
	int r;
	static pthread_mutex_t dbglock = PTHREAD_MUTEX_INITIALIZER;

	if ((r = pthread_mutex_lock(&dbglock)) != 0) {exit(EXIT_FAILURE);}
	fprintf(stdout, "%s: %p\n", msg, lock);
	if ((r = pthread_mutex_unlock(&dbglock)) != 0) {exit(EXIT_FAILURE);}
    }
}

void
rb_native_mutex_lock(pthread_mutex_t *lock)
{
    int r;
    mutex_debug("lock", lock);
    if ((r = pthread_mutex_lock(lock)) != 0) {
	rb_bug_errno("pthread_mutex_lock", r);
    }
}

void
rb_native_mutex_unlock(pthread_mutex_t *lock)
{
    int r;
    mutex_debug("unlock", lock);
    if ((r = pthread_mutex_unlock(lock)) != 0) {
	rb_bug_errno("pthread_mutex_unlock", r);
    }
}

static inline int
native_mutex_trylock(pthread_mutex_t *lock)
{
    int r;
    mutex_debug("trylock", lock);
    if ((r = pthread_mutex_trylock(lock)) != 0) {
	if (r == EBUSY) {
	    return EBUSY;
	}
	else {
	    rb_bug_errno("pthread_mutex_trylock", r);
	}
    }
    return 0;
}

void
rb_native_mutex_initialize(pthread_mutex_t *lock)
{
    int r = pthread_mutex_init(lock, 0);
    mutex_debug("init", lock);
    if (r != 0) {
	rb_bug_errno("pthread_mutex_init", r);
    }
}

void
rb_native_mutex_destroy(pthread_mutex_t *lock)
{
    int r = pthread_mutex_destroy(lock);
    mutex_debug("destroy", lock);
    if (r != 0) {
	rb_bug_errno("pthread_mutex_destroy", r);
    }
}

void
rb_native_cond_initialize(rb_nativethread_cond_t *cond)
{
    int r = pthread_cond_init(cond, condattr_monotonic);
    if (r != 0) {
	rb_bug_errno("pthread_cond_init", r);
    }
}

void
rb_native_cond_destroy(rb_nativethread_cond_t *cond)
{
    int r = pthread_cond_destroy(cond);
    if (r != 0) {
	rb_bug_errno("pthread_cond_destroy", r);
    }
}

/*
 * In OS X 10.7 (Lion), pthread_cond_signal and pthread_cond_broadcast return
 * EAGAIN after retrying 8192 times.  You can see them in the following page:
 *
 * http://www.opensource.apple.com/source/Libc/Libc-763.11/pthreads/pthread_cond.c
 *
 * The following rb_native_cond_signal and rb_native_cond_broadcast functions
 * need to retrying until pthread functions don't return EAGAIN.
 */

void
rb_native_cond_signal(rb_nativethread_cond_t *cond)
{
    int r;
    do {
	r = pthread_cond_signal(cond);
    } while (r == EAGAIN);
    if (r != 0) {
	rb_bug_errno("pthread_cond_signal", r);
    }
}

void
rb_native_cond_broadcast(rb_nativethread_cond_t *cond)
{
    int r;
    do {
	r = pthread_cond_broadcast(cond);
    } while (r == EAGAIN);
    if (r != 0) {
        rb_bug_errno("rb_native_cond_broadcast", r);
    }
}

void
rb_native_cond_wait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex)
{
    int r = pthread_cond_wait(cond, mutex);
    if (r != 0) {
	rb_bug_errno("pthread_cond_wait", r);
    }
}

static int
native_cond_timedwait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex,
                      const rb_hrtime_t *abs)
{
    int r;
    struct timespec ts;

    /*
     * An old Linux may return EINTR. Even though POSIX says
     *   "These functions shall not return an error code of [EINTR]".
     *   http://pubs.opengroup.org/onlinepubs/009695399/functions/pthread_cond_timedwait.html
     * Let's hide it from arch generic code.
     */
    do {
	r = pthread_cond_timedwait(cond, mutex, rb_hrtime2timespec(&ts, abs));
    } while (r == EINTR);

    if (r != 0 && r != ETIMEDOUT) {
	rb_bug_errno("pthread_cond_timedwait", r);
    }

    return r;
}

static rb_hrtime_t
native_cond_timeout(rb_nativethread_cond_t *cond, const rb_hrtime_t rel)
{
    if (condattr_monotonic) {
        return rb_hrtime_add(rb_hrtime_now(), rel);
    }
    else {
        struct timespec ts;

        rb_timespec_now(&ts);
        return rb_hrtime_add(rb_timespec2hrtime(&ts), rel);
    }
}

#define native_cleanup_push pthread_cleanup_push
#define native_cleanup_pop  pthread_cleanup_pop

static pthread_key_t ruby_native_thread_key;

static void
null_func(int i)
{
    /* null */
}

static rb_thread_t *
ruby_thread_from_native(void)
{
    return pthread_getspecific(ruby_native_thread_key);
}

static int
ruby_thread_set_native(rb_thread_t *th)
{
    return pthread_setspecific(ruby_native_thread_key, th) == 0;
}

static void native_thread_init(rb_thread_t *th);

void
Init_native_thread(rb_thread_t *th)
{
#if defined(HAVE_PTHREAD_CONDATTR_SETCLOCK)
    if (condattr_monotonic) {
        int r = pthread_condattr_init(condattr_monotonic);
        if (r == 0) {
            r = pthread_condattr_setclock(condattr_monotonic, CLOCK_MONOTONIC);
        }
        if (r) condattr_monotonic = NULL;
    }
#endif
    pthread_key_create(&ruby_native_thread_key, NULL);
    th->thread_id = pthread_self();
    fill_thread_id_str(th);
    native_thread_init(th);
    posix_signal(SIGVTALRM, null_func);
}

static void
native_thread_init(rb_thread_t *th)
{
    native_thread_data_t *nd = &th->native_thread_data;

#ifdef USE_UBF_LIST
    list_node_init(&nd->node.ubf);
#endif
    rb_native_cond_initialize(&nd->cond.gvlq);
    if (&nd->cond.gvlq != &nd->cond.intr)
        rb_native_cond_initialize(&nd->cond.intr);
    ruby_thread_set_native(th);
}

#ifndef USE_THREAD_CACHE
#define USE_THREAD_CACHE 1
#endif

static void
native_thread_destroy(rb_thread_t *th)
{
    native_thread_data_t *nd = &th->native_thread_data;

    rb_native_cond_destroy(&nd->cond.gvlq);
    if (&nd->cond.gvlq != &nd->cond.intr)
        rb_native_cond_destroy(&nd->cond.intr);

    /*
     * prevent false positive from ruby_thread_has_gvl_p if that
     * gets called from an interposing function wrapper
     */
    if (USE_THREAD_CACHE)
        ruby_thread_set_native(0);
}

#if USE_THREAD_CACHE
static rb_thread_t *register_cached_thread_and_wait(void *);
#endif

#if defined HAVE_PTHREAD_GETATTR_NP || defined HAVE_PTHREAD_ATTR_GET_NP
#define STACKADDR_AVAILABLE 1
#elif defined HAVE_PTHREAD_GET_STACKADDR_NP && defined HAVE_PTHREAD_GET_STACKSIZE_NP
#define STACKADDR_AVAILABLE 1
#undef MAINSTACKADDR_AVAILABLE
#define MAINSTACKADDR_AVAILABLE 1
void *pthread_get_stackaddr_np(pthread_t);
size_t pthread_get_stacksize_np(pthread_t);
#elif defined HAVE_THR_STKSEGMENT || defined HAVE_PTHREAD_STACKSEG_NP
#define STACKADDR_AVAILABLE 1
#elif defined HAVE_PTHREAD_GETTHRDS_NP
#define STACKADDR_AVAILABLE 1
#elif defined __HAIKU__
#define STACKADDR_AVAILABLE 1
#elif defined __ia64 && defined _HPUX_SOURCE
#include <sys/dyntune.h>

#define STACKADDR_AVAILABLE 1

/*
 * Do not lower the thread's stack to PTHREAD_STACK_MIN,
 * otherwise one would receive a 'sendsig: useracc failed.'
 * and a coredump.
 */
#undef PTHREAD_STACK_MIN

#define HAVE_PTHREAD_ATTR_GET_NP 1
#undef HAVE_PTHREAD_ATTR_GETSTACK

/*
 * As the PTHREAD_STACK_MIN is undefined and
 * no one touches the default stacksize,
 * it is just fine to use the default.
 */
#define pthread_attr_get_np(thid, attr) 0

/*
 * Using value of sp is very rough... To make it more real,
 * addr would need to be aligned to vps_pagesize.
 * The vps_pagesize is 'Default user page size (kBytes)'
 * and could be retrieved by gettune().
 */
static int
hpux_attr_getstackaddr(const pthread_attr_t *attr, void **addr)
{
    static uint64_t pagesize;
    size_t size;

    if (!pagesize) {
	if (gettune("vps_pagesize", &pagesize)) {
	    pagesize = 16;
	}
	pagesize *= 1024;
    }
    pthread_attr_getstacksize(attr, &size);
    *addr = (void *)((size_t)((char *)_Asm_get_sp() - size) & ~(pagesize - 1));
    return 0;
}
#define pthread_attr_getstackaddr(attr, addr) hpux_attr_getstackaddr(attr, addr)
#endif

#ifndef MAINSTACKADDR_AVAILABLE
# ifdef STACKADDR_AVAILABLE
#   define MAINSTACKADDR_AVAILABLE 1
# else
#   define MAINSTACKADDR_AVAILABLE 0
# endif
#endif
#if MAINSTACKADDR_AVAILABLE && !defined(get_main_stack)
# define get_main_stack(addr, size) get_stack(addr, size)
#endif

#ifdef STACKADDR_AVAILABLE
/*
 * Get the initial address and size of current thread's stack
 */
static int
get_stack(void **addr, size_t *size)
{
#define CHECK_ERR(expr)				\
    {int err = (expr); if (err) return err;}
#ifdef HAVE_PTHREAD_GETATTR_NP /* Linux */
    pthread_attr_t attr;
    size_t guard = 0;
    STACK_GROW_DIR_DETECTION;
    CHECK_ERR(pthread_getattr_np(pthread_self(), &attr));
# ifdef HAVE_PTHREAD_ATTR_GETSTACK
    CHECK_ERR(pthread_attr_getstack(&attr, addr, size));
    STACK_DIR_UPPER((void)0, (void)(*addr = (char *)*addr + *size));
# else
    CHECK_ERR(pthread_attr_getstackaddr(&attr, addr));
    CHECK_ERR(pthread_attr_getstacksize(&attr, size));
# endif
# ifdef HAVE_PTHREAD_ATTR_GETGUARDSIZE
    CHECK_ERR(pthread_attr_getguardsize(&attr, &guard));
    *size -= guard;
# else
    *size -= getpagesize();
# endif
    pthread_attr_destroy(&attr);
#elif defined HAVE_PTHREAD_ATTR_GET_NP /* FreeBSD, DragonFly BSD, NetBSD */
    pthread_attr_t attr;
    CHECK_ERR(pthread_attr_init(&attr));
    CHECK_ERR(pthread_attr_get_np(pthread_self(), &attr));
# ifdef HAVE_PTHREAD_ATTR_GETSTACK
    CHECK_ERR(pthread_attr_getstack(&attr, addr, size));
# else
    CHECK_ERR(pthread_attr_getstackaddr(&attr, addr));
    CHECK_ERR(pthread_attr_getstacksize(&attr, size));
# endif
    STACK_DIR_UPPER((void)0, (void)(*addr = (char *)*addr + *size));
    pthread_attr_destroy(&attr);
#elif (defined HAVE_PTHREAD_GET_STACKADDR_NP && defined HAVE_PTHREAD_GET_STACKSIZE_NP) /* MacOS X */
    pthread_t th = pthread_self();
    *addr = pthread_get_stackaddr_np(th);
    *size = pthread_get_stacksize_np(th);
#elif defined HAVE_THR_STKSEGMENT || defined HAVE_PTHREAD_STACKSEG_NP
    stack_t stk;
# if defined HAVE_THR_STKSEGMENT /* Solaris */
    CHECK_ERR(thr_stksegment(&stk));
# else /* OpenBSD */
    CHECK_ERR(pthread_stackseg_np(pthread_self(), &stk));
# endif
    *addr = stk.ss_sp;
    *size = stk.ss_size;
#elif defined HAVE_PTHREAD_GETTHRDS_NP /* AIX */
    pthread_t th = pthread_self();
    struct __pthrdsinfo thinfo;
    char reg[256];
    int regsiz=sizeof(reg);
    CHECK_ERR(pthread_getthrds_np(&th, PTHRDSINFO_QUERY_ALL,
				   &thinfo, sizeof(thinfo),
				   &reg, &regsiz));
    *addr = thinfo.__pi_stackaddr;
    /* Must not use thinfo.__pi_stacksize for size.
       It is around 3KB smaller than the correct size
       calculated by thinfo.__pi_stackend - thinfo.__pi_stackaddr. */
    *size = thinfo.__pi_stackend - thinfo.__pi_stackaddr;
    STACK_DIR_UPPER((void)0, (void)(*addr = (char *)*addr + *size));
#elif defined __HAIKU__
    thread_info info;
    STACK_GROW_DIR_DETECTION;
    CHECK_ERR(get_thread_info(find_thread(NULL), &info));
    *addr = info.stack_base;
    *size = (uintptr_t)info.stack_end - (uintptr_t)info.stack_base;
    STACK_DIR_UPPER((void)0, (void)(*addr = (char *)*addr + *size));
#else
#error STACKADDR_AVAILABLE is defined but not implemented.
#endif
    return 0;
#undef CHECK_ERR
}
#endif

static struct {
    rb_nativethread_id_t id;
    size_t stack_maxsize;
    VALUE *stack_start;
#ifdef __ia64
    VALUE *register_stack_start;
#endif
} native_main_thread;

#ifdef STACK_END_ADDRESS
extern void *STACK_END_ADDRESS;
#endif

enum {
    RUBY_STACK_SPACE_LIMIT = 1024 * 1024, /* 1024KB */
    RUBY_STACK_SPACE_RATIO = 5
};

static size_t
space_size(size_t stack_size)
{
    size_t space_size = stack_size / RUBY_STACK_SPACE_RATIO;
    if (space_size > RUBY_STACK_SPACE_LIMIT) {
	return RUBY_STACK_SPACE_LIMIT;
    }
    else {
	return space_size;
    }
}

#ifdef __linux__
static __attribute__((noinline)) void
reserve_stack(volatile char *limit, size_t size)
{
# ifdef C_ALLOCA
#   error needs alloca()
# endif
    struct rlimit rl;
    volatile char buf[0x100];
    enum {stack_check_margin = 0x1000}; /* for -fstack-check */

    STACK_GROW_DIR_DETECTION;

    if (!getrlimit(RLIMIT_STACK, &rl) && rl.rlim_cur == RLIM_INFINITY)
	return;

    if (size < stack_check_margin) return;
    size -= stack_check_margin;

    size -= sizeof(buf); /* margin */
    if (IS_STACK_DIR_UPPER()) {
	const volatile char *end = buf + sizeof(buf);
	limit += size;
	if (limit > end) {
	    /* |<-bottom (=limit(a))                                     top->|
	     * | .. |<-buf 256B |<-end                          | stack check |
	     * |  256B  |              =size=                   | margin (4KB)|
	     * |              =size=         limit(b)->|  256B  |             |
	     * |                |       alloca(sz)     |        |             |
	     * | .. |<-buf      |<-limit(c)    [sz-1]->0>       |             |
	     */
	    size_t sz = limit - end;
	    limit = alloca(sz);
	    limit[sz-1] = 0;
	}
    }
    else {
	limit -= size;
	if (buf > limit) {
	    /* |<-top (=limit(a))                                     bottom->|
	     * | .. | 256B buf->|                               | stack check |
	     * |  256B  |              =size=                   | margin (4KB)|
	     * |              =size=         limit(b)->|  256B  |             |
	     * |                |       alloca(sz)     |        |             |
	     * | .. |      buf->|           limit(c)-><0>       |             |
	     */
	    size_t sz = buf - limit;
	    limit = alloca(sz);
	    limit[0] = 0;
	}
    }
}
#else
# define reserve_stack(limit, size) ((void)(limit), (void)(size))
#endif

#undef ruby_init_stack
/* Set stack bottom of Ruby implementation.
 *
 * You must call this function before any heap allocation by Ruby implementation.
 * Or GC will break living objects */
void
ruby_init_stack(volatile VALUE *addr
#ifdef __ia64
    , void *bsp
#endif
    )
{
    native_main_thread.id = pthread_self();
#ifdef __ia64
    if (!native_main_thread.register_stack_start ||
        (VALUE*)bsp < native_main_thread.register_stack_start) {
        native_main_thread.register_stack_start = (VALUE*)bsp;
    }
#endif
#if MAINSTACKADDR_AVAILABLE
    if (native_main_thread.stack_maxsize) return;
    {
	void* stackaddr;
	size_t size;
	if (get_main_stack(&stackaddr, &size) == 0) {
	    native_main_thread.stack_maxsize = size;
	    native_main_thread.stack_start = stackaddr;
	    reserve_stack(stackaddr, size);
	    goto bound_check;
	}
    }
#endif
#ifdef STACK_END_ADDRESS
    native_main_thread.stack_start = STACK_END_ADDRESS;
#else
    if (!native_main_thread.stack_start ||
        STACK_UPPER((VALUE *)(void *)&addr,
                    native_main_thread.stack_start > addr,
                    native_main_thread.stack_start < addr)) {
        native_main_thread.stack_start = (VALUE *)addr;
    }
#endif
    {
#if defined(HAVE_GETRLIMIT)
#if defined(PTHREAD_STACK_DEFAULT)
# if PTHREAD_STACK_DEFAULT < RUBY_STACK_SPACE*5
#  error "PTHREAD_STACK_DEFAULT is too small"
# endif
	size_t size = PTHREAD_STACK_DEFAULT;
#else
	size_t size = RUBY_VM_THREAD_VM_STACK_SIZE;
#endif
	size_t space;
	int pagesize = getpagesize();
	struct rlimit rlim;
        STACK_GROW_DIR_DETECTION;
	if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
	    size = (size_t)rlim.rlim_cur;
	}
	addr = native_main_thread.stack_start;
	if (IS_STACK_DIR_UPPER()) {
	    space = ((size_t)((char *)addr + size) / pagesize) * pagesize - (size_t)addr;
	}
	else {
	    space = (size_t)addr - ((size_t)((char *)addr - size) / pagesize + 1) * pagesize;
	}
	native_main_thread.stack_maxsize = space;
#endif
    }

#if MAINSTACKADDR_AVAILABLE
  bound_check:
#endif
    /* If addr is out of range of main-thread stack range estimation,  */
    /* it should be on co-routine (alternative stack). [Feature #2294] */
    {
	void *start, *end;
	STACK_GROW_DIR_DETECTION;

	if (IS_STACK_DIR_UPPER()) {
	    start = native_main_thread.stack_start;
	    end = (char *)native_main_thread.stack_start + native_main_thread.stack_maxsize;
	}
	else {
	    start = (char *)native_main_thread.stack_start - native_main_thread.stack_maxsize;
	    end = native_main_thread.stack_start;
	}

	if ((void *)addr < start || (void *)addr > end) {
	    /* out of range */
	    native_main_thread.stack_start = (VALUE *)addr;
	    native_main_thread.stack_maxsize = 0; /* unknown */
	}
    }
}

#define CHECK_ERR(expr) \
    {int err = (expr); if (err) {rb_bug_errno(#expr, err);}}

static int
native_thread_init_stack(rb_thread_t *th)
{
    rb_nativethread_id_t curr = pthread_self();

    if (pthread_equal(curr, native_main_thread.id)) {
	th->ec->machine.stack_start = native_main_thread.stack_start;
	th->ec->machine.stack_maxsize = native_main_thread.stack_maxsize;
    }
    else {
#ifdef STACKADDR_AVAILABLE
	void *start;
	size_t size;

	if (get_stack(&start, &size) == 0) {
	    uintptr_t diff = (uintptr_t)start - (uintptr_t)&curr;
	    th->ec->machine.stack_start = (VALUE *)&curr;
	    th->ec->machine.stack_maxsize = size - diff;
	}
#else
	rb_raise(rb_eNotImpError, "ruby engine can initialize only in the main thread");
#endif
    }
#ifdef __ia64
    th->ec->machine.register_stack_start = native_main_thread.register_stack_start;
    th->ec->machine.stack_maxsize /= 2;
    th->ec->machine.register_stack_maxsize = th->ec->machine.stack_maxsize;
#endif
    return 0;
}

#ifndef __CYGWIN__
#define USE_NATIVE_THREAD_INIT 1
#endif

static void *
thread_start_func_1(void *th_ptr)
{
    rb_thread_t *th = th_ptr;
    RB_ALTSTACK_INIT(void *altstack);
#if USE_THREAD_CACHE
  thread_start:
#endif
    {
#if !defined USE_NATIVE_THREAD_INIT
	VALUE stack_start;
#endif

	fill_thread_id_str(th);
#if defined USE_NATIVE_THREAD_INIT
	native_thread_init_stack(th);
#endif
	native_thread_init(th);
	/* run */
#if defined USE_NATIVE_THREAD_INIT
	thread_start_func_2(th, th->ec->machine.stack_start, rb_ia64_bsp());
#else
	thread_start_func_2(th, &stack_start, rb_ia64_bsp());
#endif
    }
#if USE_THREAD_CACHE
    /* cache thread */
    if ((th = register_cached_thread_and_wait(RB_ALTSTACK(altstack))) != 0) {
        goto thread_start;
    }
#else
    RB_ALTSTACK_FREE(altstack);
#endif
    return 0;
}

struct cached_thread_entry {
    rb_nativethread_cond_t cond;
    rb_nativethread_id_t thread_id;
    rb_thread_t *th;
    void *altstack;
    struct list_node node;
};

#if USE_THREAD_CACHE
static rb_nativethread_lock_t thread_cache_lock = RB_NATIVETHREAD_LOCK_INIT;
static LIST_HEAD(cached_thread_head);

#  if defined(HAVE_WORKING_FORK)
static void
thread_cache_reset(void)
{
    rb_native_mutex_initialize(&thread_cache_lock);
    list_head_init(&cached_thread_head);
}
#  endif

/*
 * number of seconds to cache for, I think 1-5s is sufficient to obviate
 * the need for thread pool in many network programs (taking into account
 * worst case network latency across the globe) without wasting memory
 */
#ifndef THREAD_CACHE_TIME
#  define THREAD_CACHE_TIME ((rb_hrtime_t)3 * RB_HRTIME_PER_SEC)
#endif

static rb_thread_t *
register_cached_thread_and_wait(void *altstack)
{
    rb_hrtime_t end = THREAD_CACHE_TIME;
    struct cached_thread_entry entry;

    rb_native_cond_initialize(&entry.cond);
    entry.altstack = altstack;
    entry.th = NULL;
    entry.thread_id = pthread_self();
    end = native_cond_timeout(&entry.cond, end);

    rb_native_mutex_lock(&thread_cache_lock);
    {
        list_add(&cached_thread_head, &entry.node);

        native_cond_timedwait(&entry.cond, &thread_cache_lock, &end);

        if (entry.th == NULL) { /* unused */
            list_del(&entry.node);
        }
    }
    rb_native_mutex_unlock(&thread_cache_lock);

    rb_native_cond_destroy(&entry.cond);
    if (!entry.th) {
        RB_ALTSTACK_FREE(entry.altstack);
    }

    return entry.th;
}
#else
#  if defined(HAVE_WORKING_FORK)
static void thread_cache_reset(void) { }
#  endif
#endif

static int
use_cached_thread(rb_thread_t *th)
{
#if USE_THREAD_CACHE
    struct cached_thread_entry *entry;

    rb_native_mutex_lock(&thread_cache_lock);
    entry = list_pop(&cached_thread_head, struct cached_thread_entry, node);
    if (entry) {
        entry->th = th;
        /* th->thread_id must be set before signal for Thread#name= */
        th->thread_id = entry->thread_id;
        fill_thread_id_str(th);
        rb_native_cond_signal(&entry->cond);
    }
    rb_native_mutex_unlock(&thread_cache_lock);
    return !!entry;
#endif
    return 0;
}

static void
clear_thread_cache_altstack(void)
{
#if USE_THREAD_CACHE
    struct cached_thread_entry *entry;

    rb_native_mutex_lock(&thread_cache_lock);
    list_for_each(&cached_thread_head, entry, node) {
        void MAYBE_UNUSED(*altstack) = entry->altstack;
        entry->altstack = 0;
        RB_ALTSTACK_FREE(altstack);
    }
    rb_native_mutex_unlock(&thread_cache_lock);
#endif
}

static int
native_thread_create(rb_thread_t *th)
{
    int err = 0;

    if (use_cached_thread(th)) {
	thread_debug("create (use cached thread): %p\n", (void *)th);
    }
    else {
	pthread_attr_t attr;
	const size_t stack_size = th->vm->default_params.thread_machine_stack_size;
	const size_t space = space_size(stack_size);

        th->ec->machine.stack_maxsize = stack_size - space;
#ifdef __ia64
        th->ec->machine.stack_maxsize /= 2;
        th->ec->machine.register_stack_maxsize = th->ec->machine.stack_maxsize;
#endif

	CHECK_ERR(pthread_attr_init(&attr));

# ifdef PTHREAD_STACK_MIN
	thread_debug("create - stack size: %lu\n", (unsigned long)stack_size);
	CHECK_ERR(pthread_attr_setstacksize(&attr, stack_size));
# endif

# ifdef HAVE_PTHREAD_ATTR_SETINHERITSCHED
	CHECK_ERR(pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED));
# endif
	CHECK_ERR(pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED));

	err = pthread_create(&th->thread_id, &attr, thread_start_func_1, th);
	thread_debug("create: %p (%d)\n", (void *)th, err);
	/* should be done in the created thread */
	fill_thread_id_str(th);
	CHECK_ERR(pthread_attr_destroy(&attr));
    }
    return err;
}

#if USE_NATIVE_THREAD_PRIORITY

static void
native_thread_apply_priority(rb_thread_t *th)
{
#if defined(_POSIX_PRIORITY_SCHEDULING) && (_POSIX_PRIORITY_SCHEDULING > 0)
    struct sched_param sp;
    int policy;
    int priority = 0 - th->priority;
    int max, min;
    pthread_getschedparam(th->thread_id, &policy, &sp);
    max = sched_get_priority_max(policy);
    min = sched_get_priority_min(policy);

    if (min > priority) {
	priority = min;
    }
    else if (max < priority) {
	priority = max;
    }

    sp.sched_priority = priority;
    pthread_setschedparam(th->thread_id, policy, &sp);
#else
    /* not touched */
#endif
}

#endif /* USE_NATIVE_THREAD_PRIORITY */

static int
native_fd_select(int n, rb_fdset_t *readfds, rb_fdset_t *writefds, rb_fdset_t *exceptfds, struct timeval *timeout, rb_thread_t *th)
{
    return rb_fd_select(n, readfds, writefds, exceptfds, timeout);
}

static void
ubf_pthread_cond_signal(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    thread_debug("ubf_pthread_cond_signal (%p)\n", (void *)th);
    rb_native_cond_signal(&th->native_thread_data.cond.intr);
}

static void
native_cond_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    rb_nativethread_lock_t *lock = &th->interrupt_lock;
    rb_nativethread_cond_t *cond = &th->native_thread_data.cond.intr;

    /* Solaris cond_timedwait() return EINVAL if an argument is greater than
     * current_time + 100,000,000.  So cut up to 100,000,000.  This is
     * considered as a kind of spurious wakeup.  The caller to native_sleep
     * should care about spurious wakeup.
     *
     * See also [Bug #1341] [ruby-core:29702]
     * http://download.oracle.com/docs/cd/E19683-01/816-0216/6m6ngupgv/index.html
     */
    const rb_hrtime_t max = (rb_hrtime_t)100000000 * RB_HRTIME_PER_SEC;

    GVL_UNLOCK_BEGIN(th);
    {
        rb_native_mutex_lock(lock);
	th->unblock.func = ubf_pthread_cond_signal;
	th->unblock.arg = th;

	if (RUBY_VM_INTERRUPTED(th->ec)) {
	    /* interrupted.  return immediate */
	    thread_debug("native_sleep: interrupted before sleep\n");
	}
	else {
	    if (!rel) {
		rb_native_cond_wait(cond, lock);
	    }
            else {
                rb_hrtime_t end;

                if (*rel > max) {
                    *rel = max;
                }

                end = native_cond_timeout(cond, *rel);
		native_cond_timedwait(cond, lock, &end);
            }
	}
	th->unblock.func = 0;

	rb_native_mutex_unlock(lock);
    }
    GVL_UNLOCK_END(th);

    thread_debug("native_sleep done\n");
}

#ifdef USE_UBF_LIST
static LIST_HEAD(ubf_list_head);
static rb_nativethread_lock_t ubf_list_lock = RB_NATIVETHREAD_LOCK_INIT;

static void
ubf_list_atfork(void)
{
    list_head_init(&ubf_list_head);
    rb_native_mutex_initialize(&ubf_list_lock);
}

/* The thread 'th' is registered to be trying unblock. */
static void
register_ubf_list(rb_thread_t *th)
{
    struct list_node *node = &th->native_thread_data.node.ubf;

    if (list_empty((struct list_head*)node)) {
        rb_native_mutex_lock(&ubf_list_lock);
	list_add(&ubf_list_head, node);
        rb_native_mutex_unlock(&ubf_list_lock);
    }
}

/* The thread 'th' is unblocked. It no longer need to be registered. */
static void
unregister_ubf_list(rb_thread_t *th)
{
    struct list_node *node = &th->native_thread_data.node.ubf;

    /* we can't allow re-entry into ubf_list_head */
    VM_ASSERT(th->unblock.func == 0);

    if (!list_empty((struct list_head*)node)) {
        rb_native_mutex_lock(&ubf_list_lock);
        list_del_init(node);
        if (list_empty(&ubf_list_head) && !rb_signal_buff_size()) {
            ubf_timer_disarm();
        }
        rb_native_mutex_unlock(&ubf_list_lock);
    }
}

/*
 * send a signal to intent that a target thread return from blocking syscall.
 * Maybe any signal is ok, but we chose SIGVTALRM.
 */
static void
ubf_wakeup_thread(rb_thread_t *th)
{
    thread_debug("thread_wait_queue_wakeup (%"PRI_THREAD_ID")\n", thread_id_str(th));
    pthread_kill(th->thread_id, SIGVTALRM);
}

static void
ubf_select(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    rb_vm_t *vm = th->vm;
    const rb_thread_t *cur = ruby_thread_from_native(); /* may be 0 */

    register_ubf_list(th);

    /*
     * ubf_wakeup_thread() doesn't guarantee to wake up a target thread.
     * Therefore, we repeatedly call ubf_wakeup_thread() until a target thread
     * exit from ubf function.  We must have a timer to perform this operation.
     * We use double-checked locking here because this function may be called
     * while vm->gvl.lock is held in do_gvl_timer.
     * There is also no need to start a timer if we're the designated
     * sigwait_th thread, otherwise we can deadlock with a thread
     * in unblock_function_clear.
     */
    if (cur != vm->gvl.timer && cur != sigwait_th) {
        /*
         * Double-checked locking above was to prevent nested locking
         * by the SAME thread.  We use trylock here to prevent deadlocks
         * between DIFFERENT threads
         */
        if (native_mutex_trylock(&vm->gvl.lock) == 0) {
            if (!vm->gvl.timer) {
                rb_thread_wakeup_timer_thread(-1);
            }
            rb_native_mutex_unlock(&vm->gvl.lock);
        }
    }

    ubf_wakeup_thread(th);
}

static int
ubf_threads_empty(void)
{
    return list_empty(&ubf_list_head);
}

static void
ubf_wakeup_all_threads(void)
{
    rb_thread_t *th;
    native_thread_data_t *dat;

    if (!ubf_threads_empty()) {
        rb_native_mutex_lock(&ubf_list_lock);
	list_for_each(&ubf_list_head, dat, node.ubf) {
	    th = container_of(dat, rb_thread_t, native_thread_data);
	    ubf_wakeup_thread(th);
	}
        rb_native_mutex_unlock(&ubf_list_lock);
    }
}

#else /* USE_UBF_LIST */
#define register_ubf_list(th) (void)(th)
#define unregister_ubf_list(th) (void)(th)
#define ubf_select 0
static void ubf_wakeup_all_threads(void) { return; }
static int ubf_threads_empty(void) { return 1; }
#define ubf_list_atfork() do {} while (0)
#endif /* USE_UBF_LIST */

#define TT_DEBUG 0
#define WRITE_CONST(fd, str) (void)(write((fd),(str),sizeof(str)-1)<0)

static struct {
    /* pipes are closed in forked children when owner_process does not match */
    int normal[2]; /* [0] == sigwait_fd */
    int ub_main[2]; /* unblock main thread from native_ppoll_sleep */

    /* volatile for signal handler use: */
    volatile rb_pid_t owner_process;
} signal_self_pipe = {
    {-1, -1},
    {-1, -1},
};

/* only use signal-safe system calls here */
static void
rb_thread_wakeup_timer_thread_fd(int fd)
{
#if USE_EVENTFD
    const uint64_t buff = 1;
#else
    const char buff = '!';
#endif
    ssize_t result;

    /* already opened */
    if (fd >= 0) {
      retry:
	if ((result = write(fd, &buff, sizeof(buff))) <= 0) {
	    int e = errno;
	    switch (e) {
	      case EINTR: goto retry;
	      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	      case EWOULDBLOCK:
#endif
		break;
	      default:
		async_bug_fd("rb_thread_wakeup_timer_thread: write", e, fd);
	    }
	}
	if (TT_DEBUG) WRITE_CONST(2, "rb_thread_wakeup_timer_thread: write\n");
    }
    else {
	/* ignore wakeup */
    }
}

/*
 * This ensures we get a SIGVTALRM in TIME_QUANTUM_MSEC if our
 * process could not react to the original signal in time.
 */
static void
ubf_timer_arm(rb_pid_t current) /* async signal safe */
{
#if UBF_TIMER == UBF_TIMER_POSIX
    if ((!current || timer_posix.owner == current) &&
            !ATOMIC_CAS(timer_posix.state, RTIMER_DISARM, RTIMER_ARMING)) {
        struct itimerspec it;

        it.it_interval.tv_sec = it.it_value.tv_sec = 0;
        it.it_interval.tv_nsec = it.it_value.tv_nsec = TIME_QUANTUM_NSEC;

        if (timer_settime(timer_posix.timerid, 0, &it, 0))
            rb_async_bug_errno("timer_settime (arm)", errno);

        switch (ATOMIC_CAS(timer_posix.state, RTIMER_ARMING, RTIMER_ARMED)) {
          case RTIMER_DISARM:
            /* somebody requested a disarm while we were arming */
            /* may race harmlessly with ubf_timer_destroy */
            (void)timer_settime(timer_posix.timerid, 0, &zero, 0);

          case RTIMER_ARMING: return; /* success */
          case RTIMER_ARMED:
            /*
             * it is possible to have another thread disarm, and
             * a third thread arm finish re-arming before we get
             * here, so we wasted a syscall with timer_settime but
             * probably unavoidable in a signal handler.
             */
            return;
          case RTIMER_DEAD:
            /* may race harmlessly with ubf_timer_destroy */
            (void)timer_settime(timer_posix.timerid, 0, &zero, 0);
            return;
          default:
            rb_async_bug_errno("UBF_TIMER_POSIX unknown state", ERANGE);
        }
    }
#elif UBF_TIMER == UBF_TIMER_PTHREAD
    if (!current || current == timer_pthread.owner) {
        if (ATOMIC_EXCHANGE(timer_pthread.armed, 1) == 0)
            rb_thread_wakeup_timer_thread_fd(timer_pthread.low[1]);
    }
#endif
}

void
rb_thread_wakeup_timer_thread(int sig)
{
    rb_pid_t current;

    /* non-sighandler path */
    if (sig <= 0) {
        rb_thread_wakeup_timer_thread_fd(signal_self_pipe.normal[1]);
        if (sig < 0) {
            ubf_timer_arm(0);
        }
        return;
    }

    /* must be safe inside sighandler, so no mutex */
    current = getpid();
    if (signal_self_pipe.owner_process == current) {
        rb_thread_wakeup_timer_thread_fd(signal_self_pipe.normal[1]);

        /*
         * system_working check is required because vm and main_thread are
         * freed during shutdown
         */
        if (system_working > 0) {
            volatile rb_execution_context_t *ec;
            rb_vm_t *vm = GET_VM();
            rb_thread_t *mth;

            /*
             * FIXME: root VM and main_thread should be static and not
             * on heap for maximum safety (and startup/shutdown speed)
             */
            if (!vm) return;
            mth = vm->main_thread;
            if (!mth || system_working <= 0) return;

            /* this relies on GC for grace period before cont_free */
            ec = ACCESS_ONCE(rb_execution_context_t *, mth->ec);

            if (ec) {
                RUBY_VM_SET_TRAP_INTERRUPT(ec);
                ubf_timer_arm(current);

                /* some ubfs can interrupt single-threaded process directly */
                if (vm->ubf_async_safe && mth->unblock.func) {
                    (mth->unblock.func)(mth->unblock.arg);
                }
            }
        }
    }
}

#define CLOSE_INVALIDATE_PAIR(expr) \
    close_invalidate_pair(expr,"close_invalidate: "#expr)
static void
close_invalidate(int *fdp, const char *msg)
{
    int fd = *fdp;

    *fdp = -1;
    if (close(fd) < 0) {
	async_bug_fd(msg, errno, fd);
    }
}

static void
close_invalidate_pair(int fds[2], const char *msg)
{
    if (USE_EVENTFD && fds[0] == fds[1]) {
        close_invalidate(&fds[0], msg);
        fds[1] = -1;
    }
    else {
        close_invalidate(&fds[0], msg);
        close_invalidate(&fds[1], msg);
    }
}

static void
set_nonblock(int fd)
{
    int oflags;
    int err;

    oflags = fcntl(fd, F_GETFL);
    if (oflags == -1)
	rb_sys_fail(0);
    oflags |= O_NONBLOCK;
    err = fcntl(fd, F_SETFL, oflags);
    if (err == -1)
	rb_sys_fail(0);
}

/* communication pipe with timer thread and signal handler */
static int
setup_communication_pipe_internal(int pipes[2])
{
    int err;

    if (pipes[0] >= 0 || pipes[1] >= 0) {
        VM_ASSERT(pipes[0] >= 0);
        VM_ASSERT(pipes[1] >= 0);
        return 0;
    }

    /*
     * Don't bother with eventfd on ancient Linux 2.6.22..2.6.26 which were
     * missing EFD_* flags, they can fall back to pipe
     */
#if USE_EVENTFD && defined(EFD_NONBLOCK) && defined(EFD_CLOEXEC)
    pipes[0] = pipes[1] = eventfd(0, EFD_NONBLOCK|EFD_CLOEXEC);
    if (pipes[0] >= 0) {
        rb_update_max_fd(pipes[0]);
        return 0;
    }
#endif

    err = rb_cloexec_pipe(pipes);
    if (err != 0) {
	rb_warn("pipe creation failed for timer: %s, scheduling broken",
	        strerror(errno));
	return -1;
    }
    rb_update_max_fd(pipes[0]);
    rb_update_max_fd(pipes[1]);
    set_nonblock(pipes[0]);
    set_nonblock(pipes[1]);
    return 0;
}

#if !defined(SET_CURRENT_THREAD_NAME) && defined(__linux__) && defined(PR_SET_NAME)
# define SET_CURRENT_THREAD_NAME(name) prctl(PR_SET_NAME, name)
#endif

static VALUE threadptr_invoke_proc_location(rb_thread_t *th);

static void
native_set_thread_name(rb_thread_t *th)
{
#ifdef SET_CURRENT_THREAD_NAME
    VALUE loc;
    if (!NIL_P(loc = th->name)) {
        SET_CURRENT_THREAD_NAME(RSTRING_PTR(loc));
    }
    else if ((loc = threadptr_invoke_proc_location(th)) != Qnil) {
        char *name, *p;
        char buf[16];
        size_t len;
        int n;

        name = RSTRING_PTR(RARRAY_AREF(loc, 0));
        p = strrchr(name, '/'); /* show only the basename of the path. */
        if (p && p[1])
          name = p + 1;

        n = snprintf(buf, sizeof(buf), "%s:%d", name, NUM2INT(RARRAY_AREF(loc, 1)));
        rb_gc_force_recycle(loc); /* acts as a GC guard, too */

        len = (size_t)n;
        if (len >= sizeof(buf)) {
            buf[sizeof(buf)-2] = '*';
            buf[sizeof(buf)-1] = '\0';
        }
        SET_CURRENT_THREAD_NAME(buf);
    }
#endif
}

static VALUE
native_set_another_thread_name(rb_nativethread_id_t thread_id, VALUE name)
{
#ifdef SET_ANOTHER_THREAD_NAME
    const char *s = "";
    if (!NIL_P(name)) s = RSTRING_PTR(name);
    SET_ANOTHER_THREAD_NAME(thread_id, s);
#endif
    return name;
}

static void
ubf_timer_invalidate(void)
{
#if UBF_TIMER == UBF_TIMER_PTHREAD
    CLOSE_INVALIDATE_PAIR(timer_pthread.low);
#endif
}

static void
ubf_timer_pthread_create(rb_pid_t current)
{
#if UBF_TIMER == UBF_TIMER_PTHREAD
    int err;
    if (timer_pthread.owner == current)
        return;

    if (setup_communication_pipe_internal(timer_pthread.low) < 0)
        return;

    err = pthread_create(&timer_pthread.thid, 0, timer_pthread_fn, GET_VM());
    if (!err)
        timer_pthread.owner = current;
    else
        rb_warn("pthread_create failed for timer: %s, signals racy",
                strerror(err));
#endif
}

static void
ubf_timer_create(rb_pid_t current)
{
#if UBF_TIMER == UBF_TIMER_POSIX
#  if defined(__sun)
#    define UBF_TIMER_CLOCK CLOCK_REALTIME
#  else /* Tested Linux and FreeBSD: */
#    define UBF_TIMER_CLOCK CLOCK_MONOTONIC
#  endif

    struct sigevent sev;

    sev.sigev_notify = SIGEV_SIGNAL;
    sev.sigev_signo = SIGVTALRM;
    sev.sigev_value.sival_ptr = &timer_posix;

    if (!timer_create(UBF_TIMER_CLOCK, &sev, &timer_posix.timerid)) {
        rb_atomic_t prev = ATOMIC_EXCHANGE(timer_posix.state, RTIMER_DISARM);

        if (prev != RTIMER_DEAD) {
            rb_bug("timer_posix was not dead: %u\n", (unsigned)prev);
        }
        timer_posix.owner = current;
    }
    else {
	rb_warn("timer_create failed: %s, signals racy", strerror(errno));
    }
#endif
    if (UBF_TIMER == UBF_TIMER_PTHREAD)
        ubf_timer_pthread_create(current);
}

static void
rb_thread_create_timer_thread(void)
{
    /* we only create the pipe, and lazy-spawn */
    rb_pid_t current = getpid();
    rb_pid_t owner = signal_self_pipe.owner_process;

    if (owner && owner != current) {
        CLOSE_INVALIDATE_PAIR(signal_self_pipe.normal);
        CLOSE_INVALIDATE_PAIR(signal_self_pipe.ub_main);
        ubf_timer_invalidate();
    }

    if (setup_communication_pipe_internal(signal_self_pipe.normal) < 0) return;
    if (setup_communication_pipe_internal(signal_self_pipe.ub_main) < 0) return;

    ubf_timer_create(current);
    if (owner != current) {
        /* validate pipe on this process */
        sigwait_th = THREAD_INVALID;
        signal_self_pipe.owner_process = current;
    }
}

static void
ubf_timer_disarm(void)
{
#if UBF_TIMER == UBF_TIMER_POSIX
    rb_atomic_t prev;

    prev = ATOMIC_CAS(timer_posix.state, RTIMER_ARMED, RTIMER_DISARM);
    switch (prev) {
      case RTIMER_DISARM: return; /* likely */
      case RTIMER_ARMING: return; /* ubf_timer_arm will disarm itself */
      case RTIMER_ARMED:
        if (timer_settime(timer_posix.timerid, 0, &zero, 0)) {
            int err = errno;

            if (err == EINVAL) {
                prev = ATOMIC_CAS(timer_posix.state, RTIMER_DISARM, RTIMER_DISARM);

                /* main thread may have killed the timer */
                if (prev == RTIMER_DEAD) return;

                rb_bug_errno("timer_settime (disarm)", err);
            }
        }
        return;
      case RTIMER_DEAD: return; /* stay dead */
      default:
        rb_bug("UBF_TIMER_POSIX bad state: %u\n", (unsigned)prev);
    }

#elif UBF_TIMER == UBF_TIMER_PTHREAD
    ATOMIC_SET(timer_pthread.armed, 0);
#endif
}

static void
ubf_timer_destroy(void)
{
#if UBF_TIMER == UBF_TIMER_POSIX
    if (timer_posix.owner == getpid()) {
        rb_atomic_t expect = RTIMER_DISARM;
        size_t i, max = 10000000;

        /* prevent signal handler from arming: */
        for (i = 0; i < max; i++) {
            switch (ATOMIC_CAS(timer_posix.state, expect, RTIMER_DEAD)) {
              case RTIMER_DISARM:
                if (expect == RTIMER_DISARM) goto done;
                expect = RTIMER_DISARM;
                break;
              case RTIMER_ARMING:
                native_thread_yield(); /* let another thread finish arming */
                expect = RTIMER_ARMED;
                break;
              case RTIMER_ARMED:
                if (expect == RTIMER_ARMED) {
                    if (timer_settime(timer_posix.timerid, 0, &zero, 0))
                        rb_bug_errno("timer_settime (destroy)", errno);
                    goto done;
                }
                expect = RTIMER_ARMED;
                break;
              case RTIMER_DEAD:
                rb_bug("RTIMER_DEAD unexpected");
            }
        }
        rb_bug("timed out waiting for timer to arm");
done:
        if (timer_delete(timer_posix.timerid) < 0)
            rb_sys_fail("timer_delete");

        VM_ASSERT(ATOMIC_EXCHANGE(timer_posix.state, RTIMER_DEAD) == RTIMER_DEAD);
    }
#elif UBF_TIMER == UBF_TIMER_PTHREAD
    int err;

    timer_pthread.owner = 0;
    ubf_timer_disarm();
    rb_thread_wakeup_timer_thread_fd(timer_pthread.low[1]);
    err = pthread_join(timer_pthread.thid, 0);
    if (err) {
        rb_raise(rb_eThreadError, "native_thread_join() failed (%d)", err);
    }
#endif
}

static int
native_stop_timer_thread(void)
{
    int stopped;
    stopped = --system_working <= 0;
    if (stopped)
        ubf_timer_destroy();

    if (TT_DEBUG) fprintf(stderr, "stop timer thread\n");
    return stopped;
}

static void
native_reset_timer_thread(void)
{
    if (TT_DEBUG)  fprintf(stderr, "reset timer thread\n");
}

#ifdef HAVE_SIGALTSTACK
int
ruby_stack_overflowed_p(const rb_thread_t *th, const void *addr)
{
    void *base;
    size_t size;
    const size_t water_mark = 1024 * 1024;
    STACK_GROW_DIR_DETECTION;

#ifdef STACKADDR_AVAILABLE
    if (get_stack(&base, &size) == 0) {
# ifdef __APPLE__
	if (pthread_equal(th->thread_id, native_main_thread.id)) {
	    struct rlimit rlim;
	    if (getrlimit(RLIMIT_STACK, &rlim) == 0 && rlim.rlim_cur > size) {
		size = (size_t)rlim.rlim_cur;
	    }
	}
# endif
	base = (char *)base + STACK_DIR_UPPER(+size, -size);
    }
    else
#endif
    if (th) {
	size = th->ec->machine.stack_maxsize;
	base = (char *)th->ec->machine.stack_start - STACK_DIR_UPPER(0, size);
    }
    else {
	return 0;
    }
    size /= RUBY_STACK_SPACE_RATIO;
    if (size > water_mark) size = water_mark;
    if (IS_STACK_DIR_UPPER()) {
	if (size > ~(size_t)base+1) size = ~(size_t)base+1;
	if (addr > base && addr <= (void *)((char *)base + size)) return 1;
    }
    else {
	if (size > (size_t)base) size = (size_t)base;
	if (addr > (void *)((char *)base - size) && addr <= base) return 1;
    }
    return 0;
}
#endif

int
rb_reserved_fd_p(int fd)
{
    /* no false-positive if out-of-FD at startup */
    if (fd < 0)
        return 0;

#if UBF_TIMER == UBF_TIMER_PTHREAD
    if (fd == timer_pthread.low[0] || fd == timer_pthread.low[1])
        goto check_pid;
#endif
    if (fd == signal_self_pipe.normal[0] || fd == signal_self_pipe.normal[1])
        goto check_pid;
    if (fd == signal_self_pipe.ub_main[0] || fd == signal_self_pipe.ub_main[1])
        goto check_pid;
    return 0;
check_pid:
    if (signal_self_pipe.owner_process == getpid()) /* async-signal-safe */
	return 1;
    return 0;
}

rb_nativethread_id_t
rb_nativethread_self(void)
{
    return pthread_self();
}

#if USE_MJIT
/* A function that wraps actual worker function, for pthread abstraction. */
static void *
mjit_worker(void *arg)
{
    void (*worker_func)(void) = (void(*)(void))arg;

#ifdef SET_CURRENT_THREAD_NAME
    SET_CURRENT_THREAD_NAME("ruby-mjitworker"); /* 16 byte including NUL */
#endif
    worker_func();
    return NULL;
}

/* Launch MJIT thread. Returns FALSE if it fails to create thread. */
int
rb_thread_create_mjit_thread(void (*worker_func)(void))
{
    pthread_attr_t attr;
    pthread_t worker_pid;
    int ret = FALSE;

    if (pthread_attr_init(&attr) != 0) return ret;

    /* jit_worker thread is not to be joined */
    if (pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED) == 0
        && pthread_create(&worker_pid, &attr, mjit_worker, (void *)worker_func) == 0) {
        ret = TRUE;
    }
    pthread_attr_destroy(&attr);
    return ret;
}
#endif

int
rb_sigwait_fd_get(const rb_thread_t *th)
{
    if (signal_self_pipe.normal[0] >= 0) {
        VM_ASSERT(signal_self_pipe.owner_process == getpid());
        /*
         * no need to keep firing the timer if any thread is sleeping
         * on the signal self-pipe
         */
        ubf_timer_disarm();

        if (ATOMIC_PTR_CAS(sigwait_th, THREAD_INVALID, th) == THREAD_INVALID) {
            return signal_self_pipe.normal[0];
        }
    }
    return -1; /* avoid thundering herd and work stealing/starvation */
}

void
rb_sigwait_fd_put(const rb_thread_t *th, int fd)
{
    const rb_thread_t *old;

    VM_ASSERT(signal_self_pipe.normal[0] == fd);
    old = ATOMIC_PTR_EXCHANGE(sigwait_th, THREAD_INVALID);
    if (old != th) assert(old == th);
}

#ifndef HAVE_PPOLL
/* TODO: don't ignore sigmask */
static int
ruby_ppoll(struct pollfd *fds, nfds_t nfds,
      const struct timespec *ts, const sigset_t *sigmask)
{
    int timeout_ms;

    if (ts) {
	int tmp, tmp2;

	if (ts->tv_sec > INT_MAX/1000)
	    timeout_ms = INT_MAX;
	else {
	    tmp = (int)(ts->tv_sec * 1000);
	    /* round up 1ns to 1ms to avoid excessive wakeups for <1ms sleep */
	    tmp2 = (int)((ts->tv_nsec + 999999L) / (1000L * 1000L));
	    if (INT_MAX - tmp < tmp2)
		timeout_ms = INT_MAX;
	    else
		timeout_ms = (int)(tmp + tmp2);
	}
    }
    else
	timeout_ms = -1;

    return poll(fds, nfds, timeout_ms);
}
#  define ppoll(fds,nfds,ts,sigmask) ruby_ppoll((fds),(nfds),(ts),(sigmask))
#endif

void
rb_sigwait_sleep(rb_thread_t *th, int sigwait_fd, const rb_hrtime_t *rel)
{
    struct pollfd pfd;
    struct timespec ts;

    pfd.fd = sigwait_fd;
    pfd.events = POLLIN;

    if (!BUSY_WAIT_SIGNALS && ubf_threads_empty()) {
        (void)ppoll(&pfd, 1, rb_hrtime2timespec(&ts, rel), 0);
        check_signals_nogvl(th, sigwait_fd);
    }
    else {
        rb_hrtime_t to = RB_HRTIME_MAX, end;
        int n = 0;

        if (rel) {
            to = *rel;
            end = rb_hrtime_add(rb_hrtime_now(), to);
        }
        /*
         * tricky: this needs to return on spurious wakeup (no auto-retry).
         * But we also need to distinguish between periodic quantum
         * wakeups, so we care about the result of consume_communication_pipe
         *
         * We want to avoid spurious wakeup for Mutex#sleep compatibility
         * [ruby-core:88102]
         */
        for (;;) {
            const rb_hrtime_t *sto = sigwait_timeout(th, sigwait_fd, &to, &n);

            if (n) return;
            n = ppoll(&pfd, 1, rb_hrtime2timespec(&ts, sto), 0);
            if (check_signals_nogvl(th, sigwait_fd))
                return;
            if (n || (th && RUBY_VM_INTERRUPTED(th->ec)))
                return;
            if (rel && hrtime_update_expire(&to, end))
                return;
        }
    }
}

/*
 * we need to guarantee wakeups from native_ppoll_sleep because
 * ubf_select may not be going through ubf_list if other threads
 * are all sleeping.
 */
static void
ubf_ppoll_sleep(void *ignore)
{
    rb_thread_wakeup_timer_thread_fd(signal_self_pipe.ub_main[1]);
}

/*
 * Single CPU setups benefit from explicit sched_yield() before ppoll(),
 * since threads may be too starved to enter the GVL waitqueue for
 * us to detect contention.  Instead, we want to kick other threads
 * so they can run and possibly prevent us from entering slow paths
 * in ppoll() or similar syscalls.
 *
 * Confirmed on FreeBSD 11.2 and Linux 4.19.
 * [ruby-core:90417] [Bug #15398]
 */
#define GVL_UNLOCK_BEGIN_YIELD(th) do { \
    const native_thread_data_t *next; \
    rb_vm_t *vm = th->vm; \
    RB_GC_SAVE_MACHINE_CONTEXT(th); \
    rb_native_mutex_lock(&vm->gvl.lock); \
    next = gvl_release_common(vm); \
    rb_native_mutex_unlock(&vm->gvl.lock); \
    if (!next && vm_living_thread_num(vm) > 1) { \
        native_thread_yield(); \
    }

/*
 * This function does not exclusively acquire sigwait_fd, so it
 * cannot safely read from it.  However, it can be woken up in
 * 4 ways:
 *
 * 1) ubf_ppoll_sleep (from another thread)
 * 2) rb_thread_wakeup_timer_thread (from signal handler)
 * 3) any unmasked signal hitting the process
 * 4) periodic ubf timer wakeups (after 3)
 */
static void
native_ppoll_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    rb_native_mutex_lock(&th->interrupt_lock);
    th->unblock.func = ubf_ppoll_sleep;
    rb_native_mutex_unlock(&th->interrupt_lock);

    GVL_UNLOCK_BEGIN_YIELD(th);

    if (!RUBY_VM_INTERRUPTED(th->ec)) {
        struct pollfd pfd[2];
        struct timespec ts;

        pfd[0].fd = signal_self_pipe.normal[0]; /* sigwait_fd */
        pfd[1].fd = signal_self_pipe.ub_main[0];
        pfd[0].events = pfd[1].events = POLLIN;
        if (ppoll(pfd, 2, rb_hrtime2timespec(&ts, rel), 0) > 0) {
            if (pfd[1].revents & POLLIN) {
                (void)consume_communication_pipe(pfd[1].fd);
            }
        }
        /*
         * do not read the sigwait_fd, here, let uplevel callers
         * or other threads that, otherwise we may steal and starve
         * other threads
         */
    }
    unblock_function_clear(th);
    GVL_UNLOCK_END(th);
}

static void
native_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    int sigwait_fd = rb_sigwait_fd_get(th);

    if (sigwait_fd >= 0) {
        rb_native_mutex_lock(&th->interrupt_lock);
        th->unblock.func = ubf_sigwait;
        rb_native_mutex_unlock(&th->interrupt_lock);

        GVL_UNLOCK_BEGIN_YIELD(th);

        if (!RUBY_VM_INTERRUPTED(th->ec)) {
            rb_sigwait_sleep(th, sigwait_fd, rel);
        }
        else {
            check_signals_nogvl(th, sigwait_fd);
        }
        unblock_function_clear(th);
        GVL_UNLOCK_END(th);
        rb_sigwait_fd_put(th, sigwait_fd);
        rb_sigwait_fd_migrate(th->vm);
    }
    else if (th == th->vm->main_thread) { /* always able to handle signals */
        native_ppoll_sleep(th, rel);
    }
    else {
        native_cond_sleep(th, rel);
    }
}

#if UBF_TIMER == UBF_TIMER_PTHREAD
static void *
timer_pthread_fn(void *p)
{
    rb_vm_t *vm = p;
    pthread_t main_thread_id = vm->main_thread->thread_id;
    struct pollfd pfd;
    int timeout = -1;
    int ccp;

    pfd.fd = timer_pthread.low[0];
    pfd.events = POLLIN;

    while (system_working > 0) {
        (void)poll(&pfd, 1, timeout);
        ccp = consume_communication_pipe(pfd.fd);

        if (system_working > 0) {
            if (ATOMIC_CAS(timer_pthread.armed, 1, 1)) {
                pthread_kill(main_thread_id, SIGVTALRM);

                if (rb_signal_buff_size() || !ubf_threads_empty()) {
                    timeout = TIME_QUANTUM_MSEC;
                }
                else {
                    ATOMIC_SET(timer_pthread.armed, 0);
                    timeout = -1;
                }
            }
            else if (ccp) {
                pthread_kill(main_thread_id, SIGVTALRM);
                ATOMIC_SET(timer_pthread.armed, 0);
                timeout = -1;
            }
        }
    }

    return 0;
}
#endif /* UBF_TIMER_PTHREAD */

static VALUE
ubf_caller(const void *ignore)
{
    rb_thread_sleep_forever();

    return Qfalse;
}

/*
 * Called if and only if one thread is running, and
 * the unblock function is NOT async-signal-safe
 * This assumes USE_THREAD_CACHE is true for performance reasons
 */
static VALUE
rb_thread_start_unblock_thread(void)
{
    return rb_thread_create(ubf_caller, 0);
}
#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
