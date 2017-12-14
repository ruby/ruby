/* -*-c-*- */
/**********************************************************************

  thread_pthread.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include "gc.h"

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
#if defined(__native_client__) && defined(NACL_NEWLIB)
# include "nacl/select.h"
#endif
#if defined(HAVE_SYS_TIME_H)
#include <sys/time.h>
#endif

static void native_mutex_lock(rb_nativethread_lock_t *lock);
static void native_mutex_unlock(rb_nativethread_lock_t *lock);
static int native_mutex_trylock(rb_nativethread_lock_t *lock);
static void native_mutex_initialize(rb_nativethread_lock_t *lock);
static void native_mutex_destroy(rb_nativethread_lock_t *lock);
static void native_cond_signal(rb_nativethread_cond_t *cond);
static void native_cond_broadcast(rb_nativethread_cond_t *cond);
static void native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);
static void native_cond_initialize(rb_nativethread_cond_t *cond, int flags);
static void native_cond_destroy(rb_nativethread_cond_t *cond);
static void rb_thread_wakeup_timer_thread_low(void);
static struct {
    pthread_t id;
    int created;
} timer_thread;
#define TIMER_THREAD_CREATED_P() (timer_thread.created != 0)

#define RB_CONDATTR_CLOCK_MONOTONIC 1

#if defined(HAVE_PTHREAD_CONDATTR_SETCLOCK) && defined(HAVE_CLOCKID_T) && \
    defined(CLOCK_REALTIME) && defined(CLOCK_MONOTONIC) && \
    defined(HAVE_CLOCK_GETTIME) && defined(HAVE_PTHREAD_CONDATTR_INIT)
#define USE_MONOTONIC_COND 1
#else
#define USE_MONOTONIC_COND 0
#endif

#if defined(HAVE_POLL) && defined(HAVE_FCNTL) && defined(F_GETFL) && defined(F_SETFL) && defined(O_NONBLOCK) && !defined(__native_client__)
/* The timer thread sleeps while only one Ruby thread is running. */
# define USE_SLEEPY_TIMER_THREAD 1
#else
# define USE_SLEEPY_TIMER_THREAD 0
#endif

static void
gvl_acquire_common(rb_vm_t *vm)
{
    if (vm->gvl.acquired) {

	vm->gvl.waiting++;
	if (vm->gvl.waiting == 1) {
	    /*
	     * Wake up timer thread iff timer thread is slept.
	     * When timer thread is polling mode, we don't want to
	     * make confusing timer thread interval time.
	     */
	    rb_thread_wakeup_timer_thread_low();
	}

	while (vm->gvl.acquired) {
	    native_cond_wait(&vm->gvl.cond, &vm->gvl.lock);
	}

	vm->gvl.waiting--;

	if (vm->gvl.need_yield) {
	    vm->gvl.need_yield = 0;
	    native_cond_signal(&vm->gvl.switch_cond);
	}
    }

    vm->gvl.acquired = 1;
}

static void
gvl_acquire(rb_vm_t *vm, rb_thread_t *th)
{
    native_mutex_lock(&vm->gvl.lock);
    gvl_acquire_common(vm);
    native_mutex_unlock(&vm->gvl.lock);
}

static void
gvl_release_common(rb_vm_t *vm)
{
    vm->gvl.acquired = 0;
    if (vm->gvl.waiting > 0)
	native_cond_signal(&vm->gvl.cond);
}

static void
gvl_release(rb_vm_t *vm)
{
    native_mutex_lock(&vm->gvl.lock);
    gvl_release_common(vm);
    native_mutex_unlock(&vm->gvl.lock);
}

static void
gvl_yield(rb_vm_t *vm, rb_thread_t *th)
{
    native_mutex_lock(&vm->gvl.lock);

    gvl_release_common(vm);

    /* An another thread is processing GVL yield. */
    if (UNLIKELY(vm->gvl.wait_yield)) {
	while (vm->gvl.wait_yield)
	    native_cond_wait(&vm->gvl.switch_wait_cond, &vm->gvl.lock);
	goto acquire;
    }

    if (vm->gvl.waiting > 0) {
	/* Wait until another thread task take GVL. */
	vm->gvl.need_yield = 1;
	vm->gvl.wait_yield = 1;
	while (vm->gvl.need_yield)
	    native_cond_wait(&vm->gvl.switch_cond, &vm->gvl.lock);
	vm->gvl.wait_yield = 0;
    }
    else {
	native_mutex_unlock(&vm->gvl.lock);
	sched_yield();
	native_mutex_lock(&vm->gvl.lock);
    }

    native_cond_broadcast(&vm->gvl.switch_wait_cond);
  acquire:
    gvl_acquire_common(vm);
    native_mutex_unlock(&vm->gvl.lock);
}

static void
gvl_init(rb_vm_t *vm)
{
    native_mutex_initialize(&vm->gvl.lock);
    native_cond_initialize(&vm->gvl.cond, RB_CONDATTR_CLOCK_MONOTONIC);
    native_cond_initialize(&vm->gvl.switch_cond, RB_CONDATTR_CLOCK_MONOTONIC);
    native_cond_initialize(&vm->gvl.switch_wait_cond, RB_CONDATTR_CLOCK_MONOTONIC);
    vm->gvl.acquired = 0;
    vm->gvl.waiting = 0;
    vm->gvl.need_yield = 0;
    vm->gvl.wait_yield = 0;
}

static void
gvl_destroy(rb_vm_t *vm)
{
    native_cond_destroy(&vm->gvl.switch_wait_cond);
    native_cond_destroy(&vm->gvl.switch_cond);
    native_cond_destroy(&vm->gvl.cond);
    native_mutex_destroy(&vm->gvl.lock);
}

static void
gvl_atfork(rb_vm_t *vm)
{
    gvl_init(vm);
    gvl_acquire(vm, GET_THREAD());
}

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

static void
native_mutex_lock(pthread_mutex_t *lock)
{
    int r;
    mutex_debug("lock", lock);
    if ((r = pthread_mutex_lock(lock)) != 0) {
	rb_bug_errno("pthread_mutex_lock", r);
    }
}

static void
native_mutex_unlock(pthread_mutex_t *lock)
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

static void
native_mutex_initialize(pthread_mutex_t *lock)
{
    int r = pthread_mutex_init(lock, 0);
    mutex_debug("init", lock);
    if (r != 0) {
	rb_bug_errno("pthread_mutex_init", r);
    }
}

static void
native_mutex_destroy(pthread_mutex_t *lock)
{
    int r = pthread_mutex_destroy(lock);
    mutex_debug("destroy", lock);
    if (r != 0) {
	rb_bug_errno("pthread_mutex_destroy", r);
    }
}

static void
native_cond_initialize(rb_nativethread_cond_t *cond, int flags)
{
#ifdef HAVE_PTHREAD_COND_INIT
    int r;
# if USE_MONOTONIC_COND
    pthread_condattr_t attr;

    pthread_condattr_init(&attr);

    cond->clockid = CLOCK_REALTIME;
    if (flags & RB_CONDATTR_CLOCK_MONOTONIC) {
	r = pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
	if (r == 0) {
	    cond->clockid = CLOCK_MONOTONIC;
	}
    }

    r = pthread_cond_init(&cond->cond, &attr);
    pthread_condattr_destroy(&attr);
# else
    r = pthread_cond_init(&cond->cond, NULL);
# endif
    if (r != 0) {
	rb_bug_errno("pthread_cond_init", r);
    }

    return;
#endif
}

static void
native_cond_destroy(rb_nativethread_cond_t *cond)
{
#ifdef HAVE_PTHREAD_COND_INIT
    int r = pthread_cond_destroy(&cond->cond);
    if (r != 0) {
	rb_bug_errno("pthread_cond_destroy", r);
    }
#endif
}

/*
 * In OS X 10.7 (Lion), pthread_cond_signal and pthread_cond_broadcast return
 * EAGAIN after retrying 8192 times.  You can see them in the following page:
 *
 * http://www.opensource.apple.com/source/Libc/Libc-763.11/pthreads/pthread_cond.c
 *
 * The following native_cond_signal and native_cond_broadcast functions
 * need to retrying until pthread functions don't return EAGAIN.
 */

static void
native_cond_signal(rb_nativethread_cond_t *cond)
{
    int r;
    do {
	r = pthread_cond_signal(&cond->cond);
    } while (r == EAGAIN);
    if (r != 0) {
	rb_bug_errno("pthread_cond_signal", r);
    }
}

static void
native_cond_broadcast(rb_nativethread_cond_t *cond)
{
    int r;
    do {
	r = pthread_cond_broadcast(&cond->cond);
    } while (r == EAGAIN);
    if (r != 0) {
	rb_bug_errno("native_cond_broadcast", r);
    }
}

static void
native_cond_wait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex)
{
    int r = pthread_cond_wait(&cond->cond, mutex);
    if (r != 0) {
	rb_bug_errno("pthread_cond_wait", r);
    }
}

static int
native_cond_timedwait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex, const struct timespec *ts)
{
    int r;

    /*
     * An old Linux may return EINTR. Even though POSIX says
     *   "These functions shall not return an error code of [EINTR]".
     *   http://pubs.opengroup.org/onlinepubs/009695399/functions/pthread_cond_timedwait.html
     * Let's hide it from arch generic code.
     */
    do {
	r = pthread_cond_timedwait(&cond->cond, mutex, ts);
    } while (r == EINTR);

    if (r != 0 && r != ETIMEDOUT) {
	rb_bug_errno("pthread_cond_timedwait", r);
    }

    return r;
}

static struct timespec
native_cond_timeout(rb_nativethread_cond_t *cond, struct timespec timeout_rel)
{
    int ret;
    struct timeval tv;
    struct timespec timeout;
    struct timespec now;

#if USE_MONOTONIC_COND
    if (cond->clockid == CLOCK_MONOTONIC) {
	ret = clock_gettime(cond->clockid, &now);
	if (ret != 0)
	    rb_sys_fail("clock_gettime()");
	goto out;
    }

    if (cond->clockid != CLOCK_REALTIME)
	rb_bug("unsupported clockid %"PRIdVALUE, (SIGNED_VALUE)cond->clockid);
#endif

    ret = gettimeofday(&tv, 0);
    if (ret != 0)
	rb_sys_fail(0);
    now.tv_sec = tv.tv_sec;
    now.tv_nsec = tv.tv_usec * 1000;

#if USE_MONOTONIC_COND
  out:
#endif
    timeout.tv_sec = now.tv_sec;
    timeout.tv_nsec = now.tv_nsec;
    timeout.tv_sec += timeout_rel.tv_sec;
    timeout.tv_nsec += timeout_rel.tv_nsec;

    if (timeout.tv_nsec >= 1000*1000*1000) {
	timeout.tv_sec++;
	timeout.tv_nsec -= 1000*1000*1000;
    }

    if (timeout.tv_sec < now.tv_sec)
	timeout.tv_sec = TIMET_MAX;

    return timeout;
}

#define native_cleanup_push pthread_cleanup_push
#define native_cleanup_pop  pthread_cleanup_pop
#ifdef HAVE_SCHED_YIELD
#define native_thread_yield() (void)sched_yield()
#else
#define native_thread_yield() ((void)0)
#endif

#if defined(SIGVTALRM) && !defined(__CYGWIN__)
#define USE_SIGNAL_THREAD_LIST 1
#endif
#ifdef USE_SIGNAL_THREAD_LIST
static void add_signal_thread_list(rb_thread_t *th);
static void remove_signal_thread_list(rb_thread_t *th);
static rb_nativethread_lock_t signal_thread_list_lock;
#endif

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
Init_native_thread(void)
{
    rb_thread_t *th = GET_THREAD();

    pthread_key_create(&ruby_native_thread_key, NULL);
    th->thread_id = pthread_self();
    fill_thread_id_str(th);
    native_thread_init(th);
#ifdef USE_SIGNAL_THREAD_LIST
    native_mutex_initialize(&signal_thread_list_lock);
#endif
#ifndef __native_client__
    posix_signal(SIGVTALRM, null_func);
#endif
}

static void
native_thread_init(rb_thread_t *th)
{
    native_cond_initialize(&th->native_thread_data.sleep_cond, RB_CONDATTR_CLOCK_MONOTONIC);
    ruby_thread_set_native(th);
}

static void
native_thread_destroy(rb_thread_t *th)
{
    native_cond_destroy(&th->native_thread_data.sleep_cond);
}

#ifndef USE_THREAD_CACHE
#define USE_THREAD_CACHE 0
#endif

#if USE_THREAD_CACHE
static rb_thread_t *register_cached_thread_and_wait(void);
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
 * noone touches the default stacksize,
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
    CHECK_ERR(pthread_attr_getguardsize(&attr, &guard));
    *size -= guard;
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
#if MAINSTACKADDR_AVAILABLE
    if (native_main_thread.stack_maxsize) return;
    {
	void* stackaddr;
	size_t size;
	if (get_main_stack(&stackaddr, &size) == 0) {
	    native_main_thread.stack_maxsize = size;
	    native_main_thread.stack_start = stackaddr;
	    reserve_stack(stackaddr, size);
	    return;
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
#ifdef __ia64
    if (!native_main_thread.register_stack_start ||
        (VALUE*)bsp < native_main_thread.register_stack_start) {
        native_main_thread.register_stack_start = (VALUE*)bsp;
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
	th->machine.stack_start = native_main_thread.stack_start;
	th->machine.stack_maxsize = native_main_thread.stack_maxsize;
    }
    else {
#ifdef STACKADDR_AVAILABLE
	void *start;
	size_t size;

	if (get_stack(&start, &size) == 0) {
	    th->machine.stack_start = start;
	    th->machine.stack_maxsize = size;
	}
#elif defined get_stack_of
	if (!th->machine.stack_maxsize) {
	    native_mutex_lock(&th->interrupt_lock);
	    native_mutex_unlock(&th->interrupt_lock);
	}
#else
	rb_raise(rb_eNotImpError, "ruby engine can initialize only in the main thread");
#endif
    }
#ifdef __ia64
    th->machine.register_stack_start = native_main_thread.register_stack_start;
    th->machine.stack_maxsize /= 2;
    th->machine.register_stack_maxsize = th->machine.stack_maxsize;
#endif
    return 0;
}

#ifndef __CYGWIN__
#define USE_NATIVE_THREAD_INIT 1
#endif

static void *
thread_start_func_1(void *th_ptr)
{
#if USE_THREAD_CACHE
  thread_start:
#endif
    {
	rb_thread_t *th = th_ptr;
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
	thread_start_func_2(th, th->machine.stack_start, rb_ia64_bsp());
#else
	thread_start_func_2(th, &stack_start, rb_ia64_bsp());
#endif
    }
#if USE_THREAD_CACHE
    if (1) {
	/* cache thread */
	rb_thread_t *th;
	if ((th = register_cached_thread_and_wait()) != 0) {
	    th_ptr = (void *)th;
	    th->thread_id = pthread_self();
	    goto thread_start;
	}
    }
#endif
    return 0;
}

struct cached_thread_entry {
    volatile rb_thread_t **th_area;
    rb_nativethread_cond_t *cond;
    struct cached_thread_entry *next;
};


#if USE_THREAD_CACHE
static rb_nativethread_lock_t thread_cache_lock = RB_NATIVETHREAD_LOCK_INIT;
struct cached_thread_entry *cached_thread_root;

static rb_thread_t *
register_cached_thread_and_wait(void)
{
    rb_nativethread_cond_t cond = RB_NATIVETHREAD_COND_INIT;
    volatile rb_thread_t *th_area = 0;
    struct timeval tv;
    struct timespec ts;
    struct cached_thread_entry *entry =
      (struct cached_thread_entry *)malloc(sizeof(struct cached_thread_entry));

    if (entry == 0) {
	return 0; /* failed -> terminate thread immediately */
    }

    gettimeofday(&tv, 0);
    ts.tv_sec = tv.tv_sec + 60;
    ts.tv_nsec = tv.tv_usec * 1000;

    native_mutex_lock(&thread_cache_lock);
    {
	entry->th_area = &th_area;
	entry->cond = &cond;
	entry->next = cached_thread_root;
	cached_thread_root = entry;

	native_cond_timedwait(&cond, &thread_cache_lock, &ts);

	{
	    struct cached_thread_entry *e, **prev = &cached_thread_root;

	    while ((e = *prev) != 0) {
		if (e == entry) {
		    *prev = e->next;
		    break;
		}
		prev = &e->next;
	    }
	}

	free(entry); /* ok */
	native_cond_destroy(&cond);
    }
    native_mutex_unlock(&thread_cache_lock);

    return (rb_thread_t *)th_area;
}
#endif

static int
use_cached_thread(rb_thread_t *th)
{
    int result = 0;
#if USE_THREAD_CACHE
    struct cached_thread_entry *entry;

    if (cached_thread_root) {
	native_mutex_lock(&thread_cache_lock);
	entry = cached_thread_root;
	{
	    if (cached_thread_root) {
		cached_thread_root = entry->next;
		*entry->th_area = th;
		result = 1;
	    }
	}
	if (result) {
	    native_cond_signal(entry->cond);
	}
	native_mutex_unlock(&thread_cache_lock);
    }
#endif
    return result;
}

static int
native_thread_create(rb_thread_t *th)
{
    int err = 0;

    if (use_cached_thread(th)) {
	thread_debug("create (use cached thread): %p\n", (void *)th);
    }
    else {
#ifdef HAVE_PTHREAD_ATTR_INIT
	pthread_attr_t attr;
	pthread_attr_t *const attrp = &attr;
#else
	pthread_attr_t *const attrp = NULL;
#endif
	const size_t stack_size = th->vm->default_params.thread_machine_stack_size;
	const size_t space = space_size(stack_size);

        th->machine.stack_maxsize = stack_size - space;
#ifdef __ia64
        th->machine.stack_maxsize /= 2;
        th->machine.register_stack_maxsize = th->machine.stack_maxsize;
#endif

#ifdef HAVE_PTHREAD_ATTR_INIT
	CHECK_ERR(pthread_attr_init(&attr));

# ifdef PTHREAD_STACK_MIN
	thread_debug("create - stack size: %lu\n", (unsigned long)stack_size);
	CHECK_ERR(pthread_attr_setstacksize(&attr, stack_size));
# endif

# ifdef HAVE_PTHREAD_ATTR_SETINHERITSCHED
	CHECK_ERR(pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED));
# endif
	CHECK_ERR(pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED));
#endif
#ifdef get_stack_of
	native_mutex_lock(&th->interrupt_lock);
#endif
	err = pthread_create(&th->thread_id, attrp, thread_start_func_1, th);
#ifdef get_stack_of
	if (!err) {
	    get_stack_of(th->thread_id,
			 &th->machine.stack_start,
			 &th->machine.stack_maxsize);
	}
	native_mutex_unlock(&th->interrupt_lock);
#endif
	thread_debug("create: %p (%d)\n", (void *)th, err);
	/* should be done in the created thread */
	fill_thread_id_str(th);
#ifdef HAVE_PTHREAD_ATTR_INIT
	CHECK_ERR(pthread_attr_destroy(&attr));
#endif
    }
    return err;
}

static void
native_thread_join(pthread_t th)
{
    int err = pthread_join(th, 0);
    if (err) {
	rb_raise(rb_eThreadError, "native_thread_join() failed (%d)", err);
    }
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
    native_cond_signal(&th->native_thread_data.sleep_cond);
}

static void
native_sleep(rb_thread_t *th, struct timeval *timeout_tv)
{
    struct timespec timeout;
    rb_nativethread_lock_t *lock = &th->interrupt_lock;
    rb_nativethread_cond_t *cond = &th->native_thread_data.sleep_cond;

    if (timeout_tv) {
	struct timespec timeout_rel;

	timeout_rel.tv_sec = timeout_tv->tv_sec;
	timeout_rel.tv_nsec = timeout_tv->tv_usec * 1000;

	/* Solaris cond_timedwait() return EINVAL if an argument is greater than
	 * current_time + 100,000,000.  So cut up to 100,000,000.  This is
	 * considered as a kind of spurious wakeup.  The caller to native_sleep
	 * should care about spurious wakeup.
	 *
	 * See also [Bug #1341] [ruby-core:29702]
	 * http://download.oracle.com/docs/cd/E19683-01/816-0216/6m6ngupgv/index.html
	 */
	if (timeout_rel.tv_sec > 100000000) {
	    timeout_rel.tv_sec = 100000000;
	    timeout_rel.tv_nsec = 0;
	}

	timeout = native_cond_timeout(cond, timeout_rel);
    }

    GVL_UNLOCK_BEGIN();
    {
	native_mutex_lock(lock);
	th->unblock.func = ubf_pthread_cond_signal;
	th->unblock.arg = th;

	if (RUBY_VM_INTERRUPTED(th)) {
	    /* interrupted.  return immediate */
	    thread_debug("native_sleep: interrupted before sleep\n");
	}
	else {
	    if (!timeout_tv)
		native_cond_wait(cond, lock);
	    else
		native_cond_timedwait(cond, lock, &timeout);
	}
	th->unblock.func = 0;
	th->unblock.arg = 0;

	native_mutex_unlock(lock);
    }
    GVL_UNLOCK_END();

    thread_debug("native_sleep done\n");
}

#ifdef USE_SIGNAL_THREAD_LIST
struct signal_thread_list {
    rb_thread_t *th;
    struct signal_thread_list *prev;
    struct signal_thread_list *next;
};

static struct signal_thread_list signal_thread_list_anchor = {
    0, 0, 0,
};

#define FGLOCK(lock, body) do { \
    native_mutex_lock(lock); \
    { \
	body; \
    } \
    native_mutex_unlock(lock); \
} while (0)

#if 0 /* for debug */
static void
print_signal_list(char *str)
{
    struct signal_thread_list *list =
      signal_thread_list_anchor.next;
    thread_debug("list (%s)> ", str);
    while (list) {
	thread_debug("%p (%p), ", list->th, list->th->thread_id);
	list = list->next;
    }
    thread_debug("\n");
}
#endif

static void
add_signal_thread_list(rb_thread_t *th)
{
    if (!th->native_thread_data.signal_thread_list) {
	FGLOCK(&signal_thread_list_lock, {
	    struct signal_thread_list *list =
	      malloc(sizeof(struct signal_thread_list));

	    if (list == 0) {
		fprintf(stderr, "[FATAL] failed to allocate memory\n");
		exit(EXIT_FAILURE);
	    }

	    list->th = th;

	    list->prev = &signal_thread_list_anchor;
	    list->next = signal_thread_list_anchor.next;
	    if (list->next) {
		list->next->prev = list;
	    }
	    signal_thread_list_anchor.next = list;
	    th->native_thread_data.signal_thread_list = list;
	});
    }
}

static void
remove_signal_thread_list(rb_thread_t *th)
{
    if (th->native_thread_data.signal_thread_list) {
	FGLOCK(&signal_thread_list_lock, {
	    struct signal_thread_list *list =
	      (struct signal_thread_list *)
		th->native_thread_data.signal_thread_list;

	    list->prev->next = list->next;
	    if (list->next) {
		list->next->prev = list->prev;
	    }
	    th->native_thread_data.signal_thread_list = 0;
	    list->th = 0;
	    free(list); /* ok */
	});
    }
}

static void
ubf_select_each(rb_thread_t *th)
{
    thread_debug("ubf_select_each (%"PRI_THREAD_ID")\n", thread_id_str(th));
    if (th) {
	pthread_kill(th->thread_id, SIGVTALRM);
    }
}

static void
ubf_select(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    add_signal_thread_list(th);

    /*
     * ubf_select_each() doesn't guarantee to wake up the target thread.
     * Therefore, we need to activate timer thread when called from
     * Thread#kill etc.
     * In the other hands, we shouldn't call rb_thread_wakeup_timer_thread()
     * if running on timer thread because it may make endless wakeups.
     */
    if (!pthread_equal(pthread_self(), timer_thread.id))
	rb_thread_wakeup_timer_thread();
    ubf_select_each(th);
}

static void
ping_signal_thread_list(void)
{
    if (signal_thread_list_anchor.next) {
	FGLOCK(&signal_thread_list_lock, {
	    struct signal_thread_list *list;

	    list = signal_thread_list_anchor.next;
	    while (list) {
		ubf_select_each(list->th);
		list = list->next;
	    }
	});
    }
}

static int
check_signal_thread_list(void)
{
    if (signal_thread_list_anchor.next)
	return 1;
    else
	return 0;
}
#else /* USE_SIGNAL_THREAD_LIST */
#define add_signal_thread_list(th) (void)(th)
#define remove_signal_thread_list(th) (void)(th)
#define ubf_select 0
static void ping_signal_thread_list(void) { return; }
static int check_signal_thread_list(void) { return 0; }
#endif /* USE_SIGNAL_THREAD_LIST */

#define TT_DEBUG 0
#define WRITE_CONST(fd, str) (void)(write((fd),(str),sizeof(str)-1)<0)

/* 100ms.  10ms is too small for user level thread scheduling
 * on recent Linux (tested on 2.6.35)
 */
#define TIME_QUANTUM_USEC (100 * 1000)

#if USE_SLEEPY_TIMER_THREAD
static struct {
    int normal[2];
    int low[2];
    int owner_process;
} timer_thread_pipe = {
    {-1, -1},
    {-1, -1}, /* low priority */
};

/* only use signal-safe system calls here */
static void
rb_thread_wakeup_timer_thread_fd(int fd)
{
    ssize_t result;

    /* already opened */
    if (timer_thread_pipe.owner_process == getpid()) {
	const char *buff = "!";
      retry:
	if ((result = write(fd, buff, 1)) <= 0) {
	    int e = errno;
	    switch (e) {
	      case EINTR: goto retry;
	      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	      case EWOULDBLOCK:
#endif
		break;
	      default:
		rb_async_bug_errno("rb_thread_wakeup_timer_thread - write", e);
	    }
	}
	if (TT_DEBUG) WRITE_CONST(2, "rb_thread_wakeup_timer_thread: write\n");
    }
    else {
	/* ignore wakeup */
    }
}

void
rb_thread_wakeup_timer_thread(void)
{
    rb_thread_wakeup_timer_thread_fd(timer_thread_pipe.normal[1]);
}

static void
rb_thread_wakeup_timer_thread_low(void)
{
    rb_thread_wakeup_timer_thread_fd(timer_thread_pipe.low[1]);
}

/* VM-dependent API is not available for this function */
static void
consume_communication_pipe(int fd)
{
#define CCP_READ_BUFF_SIZE 1024
    /* buffer can be shared because no one refers to them. */
    static char buff[CCP_READ_BUFF_SIZE];
    ssize_t result;

    while (1) {
	result = read(fd, buff, sizeof(buff));
	if (result == 0) {
	    return;
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
		return;
	      default:
		rb_async_bug_errno("consume_communication_pipe: read\n", e);
	    }
	}
    }
}

static void
close_communication_pipe(int pipes[2])
{
    if (close(pipes[0]) < 0) {
	rb_bug_errno("native_stop_timer_thread - close(ttp[0])", errno);
    }
    if (close(pipes[1]) < 0) {
	rb_bug_errno("native_stop_timer_thread - close(ttp[1])", errno);
    }
    pipes[0] = pipes[1] = -1;
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

static void
setup_communication_pipe_internal(int pipes[2])
{
    int err;

    if (pipes[0] != -1) {
	/* close pipe of parent process */
	close_communication_pipe(pipes);
    }

    err = rb_cloexec_pipe(pipes);
    if (err != 0) {
	rb_bug_errno("setup_communication_pipe: Failed to create communication pipe for timer thread", errno);
    }
    rb_update_max_fd(pipes[0]);
    rb_update_max_fd(pipes[1]);
    set_nonblock(pipes[0]);
    set_nonblock(pipes[1]);
}

/* communication pipe with timer thread and signal handler */
static void
setup_communication_pipe(void)
{
    if (timer_thread_pipe.owner_process == getpid()) {
	/* already set up. */
	return;
    }
    setup_communication_pipe_internal(timer_thread_pipe.normal);
    setup_communication_pipe_internal(timer_thread_pipe.low);

    /* validate pipe on this process */
    timer_thread_pipe.owner_process = getpid();
}

/**
 * Let the timer thread sleep a while.
 *
 * The timer thread sleeps until woken up by rb_thread_wakeup_timer_thread() if only one Ruby thread is running.
 * @pre the calling context is in the timer thread.
 */
static inline void
timer_thread_sleep(rb_global_vm_lock_t* gvl)
{
    int result;
    int need_polling;
    struct pollfd pollfds[2];

    pollfds[0].fd = timer_thread_pipe.normal[0];
    pollfds[0].events = POLLIN;
    pollfds[1].fd = timer_thread_pipe.low[0];
    pollfds[1].events = POLLIN;

    need_polling = check_signal_thread_list();

    if (gvl->waiting > 0 || need_polling) {
	/* polling (TIME_QUANTUM_USEC usec) */
	result = poll(pollfds, 1, TIME_QUANTUM_USEC/1000);
    }
    else {
	/* wait (infinite) */
	result = poll(pollfds, numberof(pollfds), -1);
    }

    if (result == 0) {
	/* maybe timeout */
    }
    else if (result > 0) {
	consume_communication_pipe(timer_thread_pipe.normal[0]);
	consume_communication_pipe(timer_thread_pipe.low[0]);
    }
    else { /* result < 0 */
	int e = errno;
	switch (e) {
	  case EBADF:
	  case EINVAL:
	  case ENOMEM: /* from Linux man */
	  case EFAULT: /* from FreeBSD man */
	    rb_async_bug_errno("thread_timer: select", e);
	  default:
	    /* ignore */;
	}
    }
}

#else /* USE_SLEEPY_TIMER_THREAD */
# define PER_NANO 1000000000
void rb_thread_wakeup_timer_thread(void) {}
static void rb_thread_wakeup_timer_thread_low(void) {}

static rb_nativethread_lock_t timer_thread_lock;
static rb_nativethread_cond_t timer_thread_cond;

static inline void
timer_thread_sleep(rb_global_vm_lock_t* unused)
{
    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = TIME_QUANTUM_USEC * 1000;
    ts = native_cond_timeout(&timer_thread_cond, ts);

    native_cond_timedwait(&timer_thread_cond, &timer_thread_lock, &ts);
}
#endif /* USE_SLEEPY_TIMER_THREAD */

#if defined(__linux__) && defined(PR_SET_NAME)
# undef SET_THREAD_NAME
# define SET_THREAD_NAME(name) prctl(PR_SET_NAME, name)
#elif !defined(SET_THREAD_NAME)
# define SET_THREAD_NAME(name) (void)0
#endif

static VALUE rb_thread_inspect_msg(VALUE thread, int show_enclosure, int show_location, int show_status);

static void
native_set_thread_name(rb_thread_t *th)
{
#if defined(__linux__) && defined(PR_SET_NAME)
    VALUE str;
    char *name, *p;
    char buf[16];
    size_t len;

    str = rb_thread_inspect_msg(th->self, 0, 1, 0);
    name = StringValueCStr(str);
    if (*name == '@')
        name++;
    p = strrchr(name, '/'); /* show only the basename of the path. */
    if (p && p[1])
        name = p + 1;

    len = strlen(name);
    if (len < sizeof(buf)) {
        memcpy(buf, name, len);
        buf[len] = '\0';
    }
    else {
        memcpy(buf, name, sizeof(buf)-2);
        buf[sizeof(buf)-2] = '*';
        buf[sizeof(buf)-1] = '\0';
    }
    SET_THREAD_NAME(buf);
#endif
}

static void *
thread_timer(void *p)
{
    rb_global_vm_lock_t *gvl = (rb_global_vm_lock_t *)p;

    if (TT_DEBUG) WRITE_CONST(2, "start timer thread\n");

    SET_THREAD_NAME("ruby-timer-thr");

#if !USE_SLEEPY_TIMER_THREAD
    native_mutex_initialize(&timer_thread_lock);
    native_cond_initialize(&timer_thread_cond, RB_CONDATTR_CLOCK_MONOTONIC);
    native_mutex_lock(&timer_thread_lock);
#endif
    while (system_working > 0) {

	/* timer function */
	ping_signal_thread_list();
	timer_thread_function(0);

	if (TT_DEBUG) WRITE_CONST(2, "tick\n");

        /* wait */
	timer_thread_sleep(gvl);
    }
#if !USE_SLEEPY_TIMER_THREAD
    native_mutex_unlock(&timer_thread_lock);
    native_cond_destroy(&timer_thread_cond);
    native_mutex_destroy(&timer_thread_lock);
#endif

    if (TT_DEBUG) WRITE_CONST(2, "finish timer thread\n");
    return NULL;
}

static void
rb_thread_create_timer_thread(void)
{
    if (!timer_thread.created) {
	int err;
#ifdef HAVE_PTHREAD_ATTR_INIT
	pthread_attr_t attr;

	err = pthread_attr_init(&attr);
	if (err != 0) {
	    fprintf(stderr, "[FATAL] Failed to initialize pthread attr: %s\n", strerror(err));
	    exit(EXIT_FAILURE);
        }
# ifdef PTHREAD_STACK_MIN
	{
	    const size_t min_size = (4096 * 4);
	    /* Allocate the machine stack for the timer thread
	     * at least 16KB (4 pages).  FreeBSD 8.2 AMD64 causes
	     * machine stack overflow only with PTHREAD_STACK_MIN.
	     */
	    size_t stack_size = PTHREAD_STACK_MIN; /* may be dynamic, get only once */
	    if (stack_size < min_size) stack_size = min_size;
	    if (THREAD_DEBUG) stack_size += BUFSIZ;
	    pthread_attr_setstacksize(&attr, stack_size);
	}
# endif
#endif

#if USE_SLEEPY_TIMER_THREAD
	setup_communication_pipe();
#endif /* USE_SLEEPY_TIMER_THREAD */

	/* create timer thread */
	if (timer_thread.created) {
	    rb_bug("rb_thread_create_timer_thread: Timer thread was already created\n");
	}
#ifdef HAVE_PTHREAD_ATTR_INIT
	err = pthread_create(&timer_thread.id, &attr, thread_timer, &GET_VM()->gvl);
#else
	err = pthread_create(&timer_thread.id, NULL, thread_timer, &GET_VM()->gvl);
#endif
	if (err != 0) {
	    fprintf(stderr, "[FATAL] Failed to create timer thread: %s\n", strerror(err));
	    exit(EXIT_FAILURE);
	}
	timer_thread.created = 1;
#ifdef HAVE_PTHREAD_ATTR_INIT
	pthread_attr_destroy(&attr);
#endif
    }
}

static int
native_stop_timer_thread(int close_anyway)
{
    int stopped;
    stopped = --system_working <= 0;

    if (TT_DEBUG) fprintf(stderr, "stop timer thread\n");
    if (stopped) {
	/* join */
	rb_thread_wakeup_timer_thread();
	native_thread_join(timer_thread.id);
	if (TT_DEBUG) fprintf(stderr, "joined timer thread\n");
	timer_thread.created = 0;

	/* close communication pipe */
	if (close_anyway) {
	    /* TODO: Uninstall all signal handlers or mask all signals.
	     *       This pass is cleaning phase (terminate ruby process).
	     *       To avoid such race, we skip to close communication
	     *       pipe.  OS will close it at process termination.
	     *       It may not good practice, but pragmatic.
	     *       We remain it is TODO.
	     */
	    /* close_communication_pipe(); */
	}
    }
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
	size = th->machine.stack_maxsize;
	base = (char *)th->machine.stack_start - STACK_DIR_UPPER(0, size);
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
#if USE_SLEEPY_TIMER_THREAD
    if (fd == timer_thread_pipe.normal[0] ||
	fd == timer_thread_pipe.normal[1] ||
	fd == timer_thread_pipe.low[0] ||
	fd == timer_thread_pipe.low[1]) {
	return 1;
    }
    else {
	return 0;
    }
#else
    return 0;
#endif
}

rb_nativethread_id_t
rb_nativethread_self(void)
{
    return pthread_self();
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
