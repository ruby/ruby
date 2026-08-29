/* -*-c-*- */
/**********************************************************************

  thread_pthread.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include "internal/gc.h"
#include "internal/sanitizers.h"

#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
#ifdef HAVE_THR_STKSEGMENT
#include <thread.h>
#endif
#if defined(HAVE_FCNTL_H)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
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
#ifdef __linux__
#include <sys/syscall.h> /* for SYS_gettid */
#endif
#include <time.h>
#include <signal.h>

#include "probes.h"

#if defined __APPLE__
# include <AvailabilityMacros.h>
#endif

#if defined(HAVE_SYS_EVENTFD_H) && defined(HAVE_EVENTFD)
#  define USE_EVENTFD (1)
#  include <sys/eventfd.h>
#else
#  define USE_EVENTFD (0)
#endif

#if defined(HAVE_PTHREAD_CONDATTR_SETCLOCK) && \
    defined(CLOCK_REALTIME) && defined(CLOCK_MONOTONIC) && \
    defined(HAVE_CLOCK_GETTIME)
static pthread_condattr_t condattr_mono;
static pthread_condattr_t *condattr_monotonic = &condattr_mono;
#else
static const void *const condattr_monotonic = NULL;
#endif

// Whether native_cond_timedwait() takes an rb_hrtime_t deadline as is.  It
// does when the condvar counts in the same clock rb_hrtime_now() reads;
// otherwise the caller has to restate the deadline in the condvar's clock.
#define RB_NATIVE_COND_HRTIME_DEADLINE_P() (condattr_monotonic != NULL)

/* A retiring shared native thread frees its own context while the threads it
 * parked are still suspended with that context as their target. */
#define COROUTINE_TARGET_MAY_BE_FREED 1

#include COROUTINE_H

#ifndef HAVE_SYS_EVENT_H
#define HAVE_SYS_EVENT_H 0
#endif

#ifndef HAVE_SYS_EPOLL_H
#define HAVE_SYS_EPOLL_H 0
#else
// force setting for debug
// #undef HAVE_SYS_EPOLL_H
// #define HAVE_SYS_EPOLL_H 0
#endif

#ifndef USE_MN_THREADS
  #if defined(__EMSCRIPTEN__) || defined(COROUTINE_PTHREAD_CONTEXT)
    // on __EMSCRIPTEN__ provides epoll* declarations, but no implementations.
    // on COROUTINE_PTHREAD_CONTEXT, it doesn't worth to use it.
    #define USE_MN_THREADS 0
  #elif HAVE_SYS_EPOLL_H
    #include <sys/epoll.h>
    #define USE_MN_THREADS 1
  #elif HAVE_SYS_EVENT_H
    #include <sys/event.h>
    #define USE_MN_THREADS 1
  #else
    #define USE_MN_THREADS 0
  #endif
#endif

#ifdef HAVE_SCHED_YIELD
#define native_thread_yield() (void)sched_yield()
#else
#define native_thread_yield() ((void)0)
#endif

// native thread wrappers

#define NATIVE_MUTEX_LOCK_DEBUG 0
#define NATIVE_MUTEX_LOCK_DEBUG_YIELD 0

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
#if NATIVE_MUTEX_LOCK_DEBUG_YIELD
    native_thread_yield();
#endif
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

int
rb_native_mutex_trylock(pthread_mutex_t *lock)
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
native_cond_timedwait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex, const rb_hrtime_t *abs)
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
        rb_hrtime2timespec(&ts, abs);
        r = pthread_cond_timedwait(cond, mutex, &ts);
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

void
rb_native_cond_timedwait(rb_nativethread_cond_t *cond, pthread_mutex_t *mutex, unsigned long msec)
{
    rb_hrtime_t hrmsec = native_cond_timeout(cond, RB_HRTIME_PER_MSEC * msec);
    native_cond_timedwait(cond, mutex, &hrmsec);
}

// thread scheduling

static rb_internal_thread_event_hook_t *rb_internal_thread_event_hooks = NULL;
static void rb_thread_execute_hooks(rb_event_flag_t event, rb_thread_t *th);

#if 0
static const char *
event_name(rb_event_flag_t event)
{
    switch (event) {
      case RUBY_INTERNAL_THREAD_EVENT_STARTED:
        return "STARTED";
      case RUBY_INTERNAL_THREAD_EVENT_READY:
        return "READY";
      case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
        return "RESUMED";
      case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
        return "SUSPENDED";
      case RUBY_INTERNAL_THREAD_EVENT_EXITED:
        return "EXITED";
    }
    return "no-event";
}

#define RB_INTERNAL_THREAD_HOOK(event, th) \
    if (UNLIKELY(rb_internal_thread_event_hooks)) { \
        fprintf(stderr, "[thread=%"PRIxVALUE"] %s in %s (%s:%d)\n", th->self, event_name(event), __func__, __FILE__, __LINE__); \
        rb_thread_execute_hooks(event, th); \
    }
#else
#define RB_INTERNAL_THREAD_HOOK(event, th) if (UNLIKELY(rb_internal_thread_event_hooks)) { rb_thread_execute_hooks(event, th); }
#endif

static rb_serial_t current_fork_gen = 1; /* We can't use GET_VM()->fork_gen */

#if defined(SIGVTALRM) && !defined(__EMSCRIPTEN__)
#  define USE_UBF_LIST 1
#endif

#if USE_MN_THREADS
static void nt_machine_stack_atfork(void);

// A coroutine thread's execution context: the coroutine_context (first, so
// th->sched.context points at the whole block) plus what is needed to free
// it without the rb_thread_t. Owned by the execution: the dying thread marks
// it dead before its final transfer, and whichever context RESUMES from that
// transfer frees it -- the resume itself proves the transfer's register save
// into this block has completed, so no further synchronization is needed.
struct rb_thread_context {
    struct coroutine_context co; // must be first
    void *stack;                 // the coroutine machine stack (pool stack)
    struct rb_native_thread *nt; // final transfer target, stashed at termination
    bool dead;
};

static bool thread_sched_reclaim(struct coroutine_context *dead_co);
#endif


#ifdef RB_THREAD_T_HAS_NATIVE_ID
static int
get_native_thread_id(void)
{
#ifdef __linux__
    return (int)syscall(SYS_gettid);
#elif defined(__FreeBSD__)
    return pthread_getthreadid_np();
#endif
}
#endif


#ifdef RB_THREAD_LOCAL_SPECIFIER
static RB_THREAD_LOCAL_SPECIFIER rb_thread_t *ruby_native_thread;
#else
static pthread_key_t ruby_native_thread_key;
#endif

static void
null_func(int i)
{
    /* null */
    // This function can be called from signal handler
    // RUBY_DEBUG_LOG("i:%d", i);
}

rb_thread_t *
ruby_thread_from_native(void)
{
#ifdef RB_THREAD_LOCAL_SPECIFIER
    return ruby_native_thread;
#else
    return pthread_getspecific(ruby_native_thread_key);
#endif
}

int
ruby_thread_set_native(rb_thread_t *th)
{
    if (th) {
#ifdef USE_UBF_LIST
        ccan_list_node_init(&th->sched.node.ubf);
#endif
    }

    // setup TLS

    if (th && th->ec) {
        rb_ractor_set_current_ec(th->ractor, th->ec);
    }
#ifdef RB_THREAD_LOCAL_SPECIFIER
    ruby_native_thread = th;
    return 1;
#else
    return pthread_setspecific(ruby_native_thread_key, th) == 0;
#endif
}

static void native_thread_setup(struct rb_native_thread *nt);
static void native_thread_setup_on_thread(struct rb_native_thread *nt);

// Internal cache of page size:
static size_t RB_THREAD_PAGE_SIZE;

void
Init_native_thread(rb_thread_t *main_th)
{
    // Get the system page size for later use in stack allocation and stack overflow checks:
    RB_THREAD_PAGE_SIZE = sysconf(_SC_PAGESIZE);

#if defined(HAVE_PTHREAD_CONDATTR_SETCLOCK)
    if (condattr_monotonic) {
        int r = pthread_condattr_init(condattr_monotonic);
        if (r == 0) {
            r = pthread_condattr_setclock(condattr_monotonic, CLOCK_MONOTONIC);
        }
        if (r) condattr_monotonic = NULL;
    }
#endif

#ifndef RB_THREAD_LOCAL_SPECIFIER
    if (pthread_key_create(&ruby_native_thread_key, 0) == EAGAIN) {
        rb_bug("pthread_key_create failed (ruby_native_thread_key)");
    }
    if (pthread_key_create(&ruby_current_ec_key, 0) == EAGAIN) {
        rb_bug("pthread_key_create failed (ruby_current_ec_key)");
    }
#endif
    ruby_posix_signal(SIGVTALRM, null_func);

    // setup vm
    rb_vm_t *vm = main_th->vm;
    thread_sched_init_vm(vm);

    // setup main thread
    main_th->nt->thread_id = pthread_self();
    main_th->nt->serial = 1;
#ifdef RUBY_NT_SERIAL
    ruby_nt_serial = 1;
#endif
    ruby_thread_set_native(main_th);
    native_thread_setup(main_th->nt);
    native_thread_setup_on_thread(main_th->nt);

    TH_SCHED(main_th)->running = main_th;
    main_th->has_dedicated_nt = 1;

    // setup main NT (before the record below: its kind decides where it goes)
    main_th->nt->dedicated = 1;
    main_th->nt->running_thread = main_th;
    main_th->nt->vm = vm;

    thread_sched_setup_running_threads(TH_SCHED(main_th), main_th->ractor, vm, main_th, NULL);

    // setup mn
#if USE_RUBY_DEBUG_LOG
    vm->ractor.sched.dnt_cnt = 1;
#endif
}


static void
native_thread_destroy_atfork(struct rb_native_thread *nt)
{
    if (nt) {
        /* We can't call rb_native_cond_destroy here because according to the
         * specs of pthread_cond_destroy:
         *
         *   Attempting to destroy a condition variable upon which other threads
         *   are currently blocked results in undefined behavior.
         *
         * Specifically, glibc's pthread_cond_destroy waits on all the other
         * listeners. Since after forking all the threads are dead, the condition
         * variable's listeners will never wake up, so it will hang forever.
         */

        RB_ALTSTACK_FREE(nt->altstack);
        SIZED_FREE(nt->nt_context);
        SIZED_FREE(nt);
    }
}

static void
native_thread_destroy(struct rb_native_thread *nt)
{
    if (nt) {
        rb_native_cond_destroy(&nt->readyq);
        rb_native_mutex_destroy(&nt->running_th_lock);

        native_thread_destroy_atfork(nt);
    }
}

// A retiring snt frees its own rb_native_thread as it exits.  Disarm the
// altstack registration first: a signal between the free and the thread's
// end must not run on the freed block.
static void
native_thread_destroy_self(struct rb_native_thread *nt)
{
#ifdef USE_SIGALTSTACK
    stack_t disable = {0};
    disable.ss_flags = SS_DISABLE;
    sigaltstack(&disable, NULL);
#endif
    native_thread_destroy(nt);
}

#if defined HAVE_PTHREAD_GETATTR_NP || defined HAVE_PTHREAD_ATTR_GET_NP
#define STACKADDR_AVAILABLE 1
# if defined(__linux__) && !defined __GLIBC__
    /* Musl libc defines `pthread_getattr_np` but it can not get the
     * correct value of the main thread. */
#   define MAINSTACKADDR_AVAILABLE 0
# endif
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
# else
    guard = RB_THREAD_PAGE_SIZE;
# endif
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
} native_main_thread;

#ifdef STACK_END_ADDRESS
extern void *STACK_END_ADDRESS;
#endif

static void
native_thread_init_main_thread_stack(void *addr)
{
    native_main_thread.id = pthread_self();
#ifdef RUBY_ASAN_ENABLED
    addr = asan_get_real_stack_addr((void *)addr);
#endif

#if MAINSTACKADDR_AVAILABLE
    if (native_main_thread.stack_maxsize) return;
    {
        void* stackaddr;
        size_t size;
        if (get_main_stack(&stackaddr, &size) == 0) {
            native_main_thread.stack_maxsize = size;
            native_main_thread.stack_start = stackaddr;
            goto bound_check;
        }
    }
#endif
#ifdef STACK_END_ADDRESS
    native_main_thread.stack_start = STACK_END_ADDRESS;
#else
    if (!native_main_thread.stack_start ||
        STACK_UPPER((VALUE *)(void *)&addr,
                    native_main_thread.stack_start > (VALUE *)addr,
                    native_main_thread.stack_start < (VALUE *)addr)) {
        native_main_thread.stack_start = (VALUE *)addr;
    }
#endif
    {
#if defined(HAVE_GETRLIMIT)
#if defined(PTHREAD_STACK_DEFAULT)
        size_t size = PTHREAD_STACK_DEFAULT;
#else
        size_t size = RUBY_VM_THREAD_VM_STACK_SIZE;
#endif
        size_t space;
        struct rlimit rlim;
        STACK_GROW_DIR_DETECTION;
        if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
            size = (size_t)rlim.rlim_cur;
        }
        addr = native_main_thread.stack_start;
        if (IS_STACK_DIR_UPPER()) {
            space = ((size_t)((char *)addr + size) / RB_THREAD_PAGE_SIZE) * RB_THREAD_PAGE_SIZE - (size_t)addr;
        }
        else {
            space = (size_t)addr - ((size_t)((char *)addr - size) / RB_THREAD_PAGE_SIZE + 1) * RB_THREAD_PAGE_SIZE;
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
native_thread_init_stack(rb_thread_t *th, void *local_in_parent_frame)
{
    rb_nativethread_id_t curr = pthread_self();
#ifdef RUBY_ASAN_ENABLED
    local_in_parent_frame = asan_get_real_stack_addr(local_in_parent_frame);
    th->ec->machine.asan_fake_stack_handle = asan_get_thread_fake_stack_handle();
#endif

    if (!native_main_thread.id) {
        /* This thread is the first thread, must be the main thread -
         * configure the native_main_thread object */
        native_thread_init_main_thread_stack(local_in_parent_frame);
    }

    if (pthread_equal(curr, native_main_thread.id)) {
        th->ec->machine.stack_start = native_main_thread.stack_start;
        th->ec->machine.stack_maxsize = native_main_thread.stack_maxsize;
    }
    else {
#ifdef STACKADDR_AVAILABLE
        if (th_has_dedicated_nt(th)) {
            void *start;
            size_t size;

            if (get_stack(&start, &size) == 0) {
                uintptr_t diff = (uintptr_t)start - (uintptr_t)local_in_parent_frame;
                th->ec->machine.stack_start = local_in_parent_frame;
                th->ec->machine.stack_maxsize = size - diff;
            }
        }
#else
        rb_raise(rb_eNotImpError, "ruby engine can initialize only in the main thread");
#endif
    }

    return 0;
}

struct nt_param {
    rb_vm_t *vm;
    struct rb_native_thread *nt;
};


static int
native_thread_create0(struct rb_native_thread *nt)
{
    int err = 0;
    pthread_attr_t attr;

    const size_t stack_size = nt->vm->default_params.thread_machine_stack_size;

#ifdef USE_SIGALTSTACK
    nt->altstack = rb_allocate_sigaltstack();
#endif

    CHECK_ERR(pthread_attr_init(&attr));

# ifdef PTHREAD_STACK_MIN
    RUBY_DEBUG_LOG("stack size: %lu", (unsigned long)stack_size);
    CHECK_ERR(pthread_attr_setstacksize(&attr, stack_size));
# endif

# ifdef HAVE_PTHREAD_ATTR_SETINHERITSCHED
    CHECK_ERR(pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED));
# endif
    CHECK_ERR(pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED));

    err = pthread_create(&nt->thread_id, &attr, nt_start, nt);

    RUBY_DEBUG_LOG("nt:%d err:%d", (int)nt->serial, err);

    CHECK_ERR(pthread_attr_destroy(&attr));

    return err;
}

static void
native_thread_setup(struct rb_native_thread *nt)
{
    // init cond
    rb_native_cond_initialize(&nt->readyq);
    // also for the main thread's nt: a zero-filled mutex is not usable on macOS
    rb_native_mutex_initialize(&nt->running_th_lock);
}

static void
native_thread_setup_on_thread(struct rb_native_thread *nt)
{
    // init tid
#ifdef RB_THREAD_T_HAS_NATIVE_ID
    nt->tid = get_native_thread_id();
#endif

    // init signal handler
    RB_ALTSTACK_INIT(nt->altstack, nt->altstack);
}

static struct rb_native_thread *
native_thread_alloc(void)
{
    struct rb_native_thread *nt = ZALLOC(struct rb_native_thread);
    native_thread_setup(nt);

#if USE_MN_THREADS
    nt->nt_context = ruby_xmalloc(sizeof(struct coroutine_context));
#endif

#if USE_RUBY_DEBUG_LOG
    static rb_atomic_t nt_serial = 2;
    nt->serial = RUBY_ATOMIC_FETCH_ADD(nt_serial, 1);
#endif
    return nt;
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
    pthread_getschedparam(th->nt->thread_id, &policy, &sp);
    max = sched_get_priority_max(policy);
    min = sched_get_priority_min(policy);

    if (min > priority) {
        priority = min;
    }
    else if (max < priority) {
        priority = max;
    }

    sp.sched_priority = priority;
    pthread_setschedparam(th->nt->thread_id, policy, &sp);
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

/*
 * Send a signal to make the target thread return from a blocking syscall.
 * Maybe any signal is ok, but we chose SIGVTALRM (see null_func).
 */
static void
native_thread_interrupt(rb_thread_t *th)
{
    pthread_kill(th->nt->thread_id, SIGVTALRM);
}

static int
native_thread_default_max_cpu(void)
{
#if defined(HAVE_SYSCONF) && defined(_SC_NPROCESSORS_ONLN)
    long nprocessors = sysconf(_SC_NPROCESSORS_ONLN);
    return (nprocessors > 0) ? (int)nprocessors : 8;
#else
    return 8;
#endif
}


#define TT_DEBUG 0
#define WRITE_CONST(fd, str) (void)(write((fd),(str),sizeof(str)-1)<0)

void
rb_thread_wakeup_timer_thread(int sig)
{
    // This function can be called from signal handlers so that
    // pthread_mutex_lock() should not be used.

    // wakeup timer thread
    timer_thread_wakeup_force();

    // interrupt main thread if main thread is available
    if (RUBY_ATOMIC_LOAD(system_working)) {
        rb_vm_t *vm = GET_VM();
        rb_thread_t *main_th = vm->ractor.main_thread;

        if (main_th) {
            volatile rb_execution_context_t *main_th_ec = ACCESS_ONCE(rb_execution_context_t *, main_th->ec);

            if (main_th_ec) {
                RUBY_VM_SET_TRAP_INTERRUPT(main_th_ec);

                if (vm->ubf_async_safe && main_th->unblock.func) {
                    (main_th->unblock.func)(main_th->unblock.arg);
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
        fds[1] = -1; // disable write port first
        close_invalidate(&fds[0], msg);
    }
    else {
        close_invalidate(&fds[1], msg);
        close_invalidate(&fds[0], msg);
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
static void
setup_communication_pipe_internal(int pipes[2])
{
    int err;

    if (pipes[0] > 0 || pipes[1] > 0) {
        VM_ASSERT(pipes[0] > 0);
        VM_ASSERT(pipes[1] > 0);
        return;
    }

    /*
     * Don't bother with eventfd on ancient Linux 2.6.22..2.6.26 which were
     * missing EFD_* flags, they can fall back to pipe
     */
#if USE_EVENTFD && defined(EFD_NONBLOCK) && defined(EFD_CLOEXEC)
    pipes[0] = pipes[1] = eventfd(0, EFD_NONBLOCK|EFD_CLOEXEC);

    if (pipes[0] >= 0) {
        rb_update_max_fd(pipes[0]);
        return;
    }
#endif

    err = rb_cloexec_pipe(pipes);
    if (err != 0) {
        rb_bug("can not create communication pipe");
    }
    rb_update_max_fd(pipes[0]);
    rb_update_max_fd(pipes[1]);
    set_nonblock(pipes[0]);
    set_nonblock(pipes[1]);
}

#if !defined(SET_CURRENT_THREAD_NAME) && defined(__linux__) && defined(PR_SET_NAME)
# define SET_CURRENT_THREAD_NAME(name) prctl(PR_SET_NAME, name)
#endif

enum {
    THREAD_NAME_MAX =
#if defined(__linux__)
    16
#elif defined(__APPLE__)
/* Undocumented, and main thread seems unlimited */
    64
#else
    16
#endif
};

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
        char buf[THREAD_NAME_MAX];
        size_t len;
        int n;

        name = RSTRING_PTR(RARRAY_AREF(loc, 0));
        p = strrchr(name, '/'); /* show only the basename of the path. */
        if (p && p[1])
            name = p + 1;

        n = snprintf(buf, sizeof(buf), "%s:%d", name, NUM2INT(RARRAY_AREF(loc, 1)));
        RB_GC_GUARD(loc);

        len = (size_t)n;
        if (len >= sizeof(buf)) {
            buf[sizeof(buf)-2] = '*';
            buf[sizeof(buf)-1] = '\0';
        }
        SET_CURRENT_THREAD_NAME(buf);
    }
#endif
}

static void
native_set_another_thread_name(rb_nativethread_id_t thread_id, VALUE name)
{
#if defined SET_ANOTHER_THREAD_NAME || defined SET_CURRENT_THREAD_NAME
    char buf[THREAD_NAME_MAX];
    const char *s = "";
# if !defined SET_ANOTHER_THREAD_NAME
    if (!pthread_equal(pthread_self(), thread_id)) return;
# endif
    if (!NIL_P(name)) {
        long n;
        RSTRING_GETMEM(name, s, n);
        if (n >= (int)sizeof(buf)) {
            memcpy(buf, s, sizeof(buf)-1);
            buf[sizeof(buf)-1] = '\0';
            s = buf;
        }
    }
# if defined SET_ANOTHER_THREAD_NAME
    SET_ANOTHER_THREAD_NAME(thread_id, s);
# elif defined SET_CURRENT_THREAD_NAME
    SET_CURRENT_THREAD_NAME(s);
# endif
#endif
}

#if defined(RB_THREAD_T_HAS_NATIVE_ID) || defined(__APPLE__)
static VALUE
native_thread_native_thread_id(rb_thread_t *target_th)
{
    if (!target_th->nt) return Qnil;

#ifdef RB_THREAD_T_HAS_NATIVE_ID
    int tid = target_th->nt->tid;
    if (tid == 0) return Qnil;
    return INT2FIX(tid);
#elif defined(__APPLE__)
    uint64_t tid;
/* The first condition is needed because MAC_OS_X_VERSION_10_6
    is not defined on 10.5, and while __POWERPC__ takes care of ppc/ppc64,
    i386 will be broken without this. Note, 10.5 is supported with GCC upstream,
    so it has C++17 and everything needed to build modern Ruby. */
# if (!defined(MAC_OS_X_VERSION_10_6) || \
      (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_6) || \
      defined(__POWERPC__) /* never defined for PowerPC platforms */)
    const bool no_pthread_threadid_np = true;
#   define NO_PTHREAD_MACH_THREAD_NP 1
# elif MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6
    const bool no_pthread_threadid_np = false;
# else
#   if !(defined(__has_attribute) && __has_attribute(availability))
    /* __API_AVAILABLE macro does nothing on gcc */
    __attribute__((weak)) int pthread_threadid_np(pthread_t, uint64_t*);
#   endif
    /* Check weakly linked symbol */
    const bool no_pthread_threadid_np = !&pthread_threadid_np;
# endif
    if (no_pthread_threadid_np) {
        return ULL2NUM(pthread_mach_thread_np(pthread_self()));
    }
# ifndef NO_PTHREAD_MACH_THREAD_NP
    int e = pthread_threadid_np(target_th->nt->thread_id, &tid);
    if (e != 0) rb_syserr_fail(e, "pthread_threadid_np");
    return ULL2NUM((unsigned long long)tid);
# endif
#endif
}
# define USE_NATIVE_THREAD_NATIVE_THREAD_ID 1
#else
# define USE_NATIVE_THREAD_NATIVE_THREAD_ID 0
#endif

static struct {
    rb_serial_t created_fork_gen;
    pthread_t pthread_id;

    int comm_fds[2]; // r, w

#if (HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H) && USE_MN_THREADS
    int event_fd; // kernel event queue fd (epoll/kqueue)
#endif
#if HAVE_SYS_EPOLL_H && USE_MN_THREADS
#define EPOLL_EVENTS_MAX 0x10
    struct epoll_event finished_events[EPOLL_EVENTS_MAX];
#elif HAVE_SYS_EVENT_H && USE_MN_THREADS
#define KQUEUE_EVENTS_MAX 0x10
    struct kevent finished_events[KQUEUE_EVENTS_MAX];
#endif

#if USE_MN_THREADS
    /* Timed waiters, bucketed by deadline into a hierarchical timer wheel;
     * untimed (fd-only) waiters keep a plain list.  Both under waiting_lock.
     * The wheel operations all live in thread_sched_mn.c (timer_wheel_*). */
#define TIMER_WHEEL_LEVELS 4
#define TIMER_WHEEL_SLOT_BITS 6
#define TIMER_WHEEL_SLOTS (1 << TIMER_WHEEL_SLOT_BITS)
    struct timer_wheel_level {
        uint64_t occupied; // bit s: slots[s] is non-empty
        struct ccan_list_head slots[TIMER_WHEEL_SLOTS];
    } wheel[TIMER_WHEEL_LEVELS];
    uint64_t wheel_cursor_tick; // slots for ticks <= this are drained
    rb_hrtime_t next_expiry;   // never later than the earliest deadline
    pthread_mutex_t waiting_lock; // the wheel and the flags of fd-less timed waits

    /* The fd map entries and the flags of io waits are guarded per fd by a
     * shard lock, so unrelated fds register and wake in parallel.  Whoever
     * clears an io wait's flags under its shard owns the wakeup.  Lock order:
     * shard -> waiting_lock -> wake_pending_lock, never the other way. */
#define IO_WAIT_SHARDS 16
    pthread_mutex_t fd_shard_locks[IO_WAIT_SHARDS];

    // signaled when wake_pending clears on a thread; see timer_thread_wake_fence
    pthread_mutex_t wake_pending_lock;
    rb_nativethread_cond_t wake_pending_cond;
#endif

#if (HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H) && USE_MN_THREADS
    // fd -> struct rb_fd_waiters, in chunks so entries never move.  The chunk
    // table installs slots by CAS (chunks span shards); entry state is guarded
    // by the fd's shard lock.
#define FDMAP_MAX_CHUNKS 1024 // fds up to FDMAP_MAX_CHUNKS * FDMAP_CHUNK_SIZE
    struct rb_fd_waiters *fdmap_chunks[FDMAP_MAX_CHUNKS];
#endif
} timer_th = {
    .created_fork_gen = 0,
};

#define TIMER_THREAD_CREATED_P() (timer_th.created_fork_gen == current_fork_gen)

static void timer_thread_check_timeslice(rb_vm_t *vm);
static bool timeslice_scan(rb_vm_t *vm, bool interrupt);
static int timer_thread_set_timeout(rb_vm_t *vm);

#include "thread_sched_mn.c"


void
rb_assert_sig(void)
{
    sigset_t oldmask;
    pthread_sigmask(0, NULL, &oldmask);
    if (sigismember(&oldmask, SIGVTALRM)) {
        rb_bug("!!!");
    }
    else {
        RUBY_DEBUG_LOG("ok");
    }
}


/* only use signal-safe system calls here */
static void
signal_communication_pipe(int fd)
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
        // ignore wakeup
    }
}

static void
timer_thread_wakeup_force(void)
{
    // should not use RUBY_DEBUG_LOG() because it can be called within signal handlers.
    signal_communication_pipe(timer_th.comm_fds[1]);
}


static void
rb_thread_create_timer_thread(void)
{
    rb_serial_t created_fork_gen = timer_th.created_fork_gen;

    RUBY_DEBUG_LOG("fork_gen create:%d current:%d", (int)created_fork_gen, (int)current_fork_gen);

    timer_th.created_fork_gen = current_fork_gen;

    if (created_fork_gen != current_fork_gen) {
        if (created_fork_gen != 0) {
            RUBY_DEBUG_LOG("forked child process");

            CLOSE_INVALIDATE_PAIR(timer_th.comm_fds);
#if USE_MN_THREADS
            // The parent's waiters do not exist in the child, and the armings
            // belong to the closed event backend: a stale entry would satisfy
            // fd_waiters_arm's want == armed_flags check and never arm the new
            // backend (a lost wake the old dynamic map also had).
            for (unsigned int ci = 0; ci < FDMAP_MAX_CHUNKS; ci++) {
                struct rb_fd_waiters *chunk = timer_th.fdmap_chunks[ci];
                if (chunk == NULL) continue;
                for (unsigned int i = 0; i < FDMAP_CHUNK_SIZE; i++) {
                    ccan_list_head_init(&chunk[i].waiters);
                    chunk[i].armed_flags = 0;
                    chunk[i].generation++;
                }
            }
#endif
#if HAVE_SYS_EPOLL_H && USE_MN_THREADS
            close_invalidate(&timer_th.event_fd, "close event_fd");
#elif HAVE_SYS_EVENT_H && USE_MN_THREADS
            // A kqueue is not inherited across fork: the number names a closed
            // fd in the child, and closing it could hit a reused one.
            timer_th.event_fd = -1;
#endif
            // No mutex_destroy for waiting_lock: glibc returns EBUSY (and
            // rb_native_mutex_destroy rb_bugs) for a mutex another ractor's
            // M:N thread held at the fork moment.  The initialize below
            // starts over.
        }

#if USE_MN_THREADS
        for (int lvl = 0; lvl < TIMER_WHEEL_LEVELS; lvl++) {
            timer_th.wheel[lvl].occupied = 0;
            for (int slot = 0; slot < TIMER_WHEEL_SLOTS; slot++) {
                ccan_list_head_init(&timer_th.wheel[lvl].slots[slot]);
            }
        }
        timer_th.wheel_cursor_tick = timer_wheel_tick(rb_hrtime_now());
        timer_th.next_expiry = TIMER_WHEEL_NO_EXPIRY;
        rb_native_mutex_initialize(&timer_th.waiting_lock);
        for (int i = 0; i < IO_WAIT_SHARDS; i++) {
            rb_native_mutex_initialize(&timer_th.fd_shard_locks[i]);
        }
        rb_native_mutex_initialize(&timer_th.wake_pending_lock);
        rb_native_cond_initialize(&timer_th.wake_pending_cond);
#endif

        // open communication channel
        setup_communication_pipe_internal(timer_th.comm_fds);

        // open event fd
        timer_thread_setup_mn();
    }

    int err = pthread_create(&timer_th.pthread_id, NULL, timer_thread_func, GET_VM());
    if (err != 0) {
        // The timer thread delivers signals and drives the M:N scheduler;
        // running without one only defers the failure to stranger places.
        rb_bug_errno("pthread_create (timer thread)", err);
    }
}

static int
native_stop_timer_thread(void)
{
    RUBY_ATOMIC_SET(system_working, 0);

    RUBY_DEBUG_LOG("wakeup send %d", timer_th.comm_fds[1]);
    timer_thread_wakeup_force();
    RUBY_DEBUG_LOG("wakeup sent");
    pthread_join(timer_th.pthread_id, NULL);

    if (TT_DEBUG) fprintf(stderr, "stop timer thread\n");

    return 1;
}

static void
native_reset_timer_thread(void)
{
    //
}

#ifdef HAVE_SIGALTSTACK
int
ruby_stack_overflowed_p(const rb_thread_t *th, const void *addr)
{
    void *base;
    size_t size;
    const size_t water_mark = RB_THREAD_PAGE_SIZE;
    STACK_GROW_DIR_DETECTION;

    if (th) {
        size = th->ec->machine.stack_maxsize;
        base = (char *)th->ec->machine.stack_start - STACK_DIR_UPPER(0, size);
    }
#ifdef STACKADDR_AVAILABLE
    else if (get_stack(&base, &size) == 0) {
# ifdef __APPLE__
        // th is NULL in this branch; ask about the calling thread itself.
        if (pthread_equal(pthread_self(), native_main_thread.id)) {
            struct rlimit rlim;
            if (getrlimit(RLIMIT_STACK, &rlim) == 0 && rlim.rlim_cur > size) {
                size = (size_t)rlim.rlim_cur;
            }
        }
# endif
        base = (char *)base + STACK_DIR_UPPER(+size, -size);
    }
#endif
    else {
        return 0;
    }

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
    if (fd < 0) return 0;

    if (fd == timer_th.comm_fds[0] ||
        fd == timer_th.comm_fds[1]
#if (HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H) && USE_MN_THREADS
        || fd == timer_th.event_fd
#endif
        ) {
        goto check_fork_gen;
    }
    return 0;

  check_fork_gen:
    if (timer_th.created_fork_gen == current_fork_gen) {
        /* async-signal-safe */
        return 1;
    }
    else {
        return 0;
    }
}

rb_nativethread_id_t
rb_nativethread_self(void)
{
    return pthread_self();
}

#if defined(USE_POLL) && !defined(HAVE_PPOLL)
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


// fork read-write lock (only for pthread)
static pthread_rwlock_t rb_thread_fork_rw_lock = PTHREAD_RWLOCK_INITIALIZER;

void
rb_thread_release_fork_lock(void)
{
    int r;
    if ((r = pthread_rwlock_unlock(&rb_thread_fork_rw_lock))) {
        rb_bug_errno("pthread_rwlock_unlock", r);
    }
}

void
rb_thread_reset_fork_lock(void)
{
    int r;
    if ((r = pthread_rwlock_destroy(&rb_thread_fork_rw_lock))) {
        rb_bug_errno("pthread_rwlock_destroy", r);
    }

    if ((r = pthread_rwlock_init(&rb_thread_fork_rw_lock, NULL))) {
        rb_bug_errno("pthread_rwlock_init", r);
    }
}

void *
rb_thread_prevent_fork(void *(*func)(void *), void *data)
{
    int r;
    if ((r = pthread_rwlock_rdlock(&rb_thread_fork_rw_lock))) {
        rb_bug_errno("pthread_rwlock_rdlock", r);
    }
    void *result = func(data);
    rb_thread_release_fork_lock();
    return result;
}

void
rb_thread_acquire_fork_lock(void)
{
    int r;
    if ((r = pthread_rwlock_wrlock(&rb_thread_fork_rw_lock))) {
        rb_bug_errno("pthread_rwlock_wrlock", r);
    }
}

// thread internal event hooks (only for pthread)

struct rb_internal_thread_event_hook {
    rb_internal_thread_event_callback callback;
    rb_event_flag_t event;
    void *user_data;

    struct rb_internal_thread_event_hook *next;
};

static pthread_rwlock_t rb_internal_thread_event_hooks_rw_lock = PTHREAD_RWLOCK_INITIALIZER;

/* For the GC: whether any thread-event hook is registered right now.  The rwlock
 * makes the answer happen-after any completed registration; a hook registered
 * after this read gets no event from the asking thread (rb_thread_execute_hooks
 * skips a swept thread), so it never sees the objects the caller may collect. */
bool
rb_thread_event_hooks_registered_p(void)
{
    int r;
    if ((r = pthread_rwlock_rdlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_rdlock", r);
    }
    const bool registered = (rb_internal_thread_event_hooks != NULL);
    if ((r = pthread_rwlock_unlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_unlock", r);
    }
    return registered;
}

#if defined(HAVE_WORKING_FORK)
static void
rb_internal_thread_event_hooks_rw_lock_atfork(void)
{
    // After fork(), this rwlock may have been held by a now-dead thread.
    //
    // pthread_rwlock_destroy() on a held lock is undefined behavior, and
    // pthread_rwlock_init() on an already-initialized lock is also undefined
    // behavior
    //
    // Direct assignment of PTHREAD_RWLOCK_INITIALIZER is safe and portable.
    rb_internal_thread_event_hooks_rw_lock =
        (pthread_rwlock_t)PTHREAD_RWLOCK_INITIALIZER;
}
#endif

rb_internal_thread_event_hook_t *
rb_internal_thread_add_event_hook(rb_internal_thread_event_callback callback, rb_event_flag_t internal_event, void *user_data)
{
    rb_internal_thread_event_hook_t *hook = ALLOC_N(rb_internal_thread_event_hook_t, 1);
    hook->callback = callback;
    hook->user_data = user_data;
    hook->event = internal_event;

    int r;
    if ((r = pthread_rwlock_wrlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_wrlock", r);
    }

    hook->next = rb_internal_thread_event_hooks;
    ATOMIC_PTR_EXCHANGE(rb_internal_thread_event_hooks, hook);

    if ((r = pthread_rwlock_unlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_unlock", r);
    }
    return hook;
}

bool
rb_internal_thread_remove_event_hook(rb_internal_thread_event_hook_t * hook)
{
    int r;
    if ((r = pthread_rwlock_wrlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_wrlock", r);
    }

    bool success = FALSE;

    if (rb_internal_thread_event_hooks == hook) {
        ATOMIC_PTR_EXCHANGE(rb_internal_thread_event_hooks, hook->next);
        success = TRUE;
    }
    else {
        rb_internal_thread_event_hook_t *h = rb_internal_thread_event_hooks;

        do {
            if (h->next == hook) {
                h->next = hook->next;
                success = TRUE;
                break;
            }
        } while ((h = h->next));
    }

    if ((r = pthread_rwlock_unlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_unlock", r);
    }

    if (success) {
        SIZED_FREE(hook);
    }
    return success;
}

static void
rb_thread_execute_hooks(rb_event_flag_t event, rb_thread_t *th)
{
    int r;

    /* th->self == 0: the dying thread's final collection swept its Thread wrapper, so
     * no hook existed then; one registered since has no ordering claim to this event. */
    if (th->self == 0) return;
    if ((r = pthread_rwlock_rdlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_rdlock", r);
    }

    if (rb_internal_thread_event_hooks) {
        rb_internal_thread_event_hook_t *h = rb_internal_thread_event_hooks;
        do {
            if (h->event & event) {
                rb_internal_thread_event_data_t event_data = {
                    .thread = th->self,
                };
                (*h->callback)(event, &event_data, h->user_data);
            }
        } while((h = h->next));
    }
    if ((r = pthread_rwlock_unlock(&rb_internal_thread_event_hooks_rw_lock))) {
        rb_bug_errno("pthread_rwlock_unlock", r);
    }
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
