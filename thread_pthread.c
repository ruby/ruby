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

static void native_mutex_lock(pthread_mutex_t *lock);
static void native_mutex_unlock(pthread_mutex_t *lock);
static int native_mutex_trylock(pthread_mutex_t *lock);
static void native_mutex_initialize(pthread_mutex_t *lock);
static void native_mutex_destroy(pthread_mutex_t *lock);

static void native_cond_signal(pthread_cond_t *cond);
static void native_cond_broadcast(pthread_cond_t *cond);
static void native_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
static void native_cond_initialize(pthread_cond_t *cond);
static void native_cond_destroy(pthread_cond_t *cond);

static void native_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void));

#define native_mutex_reinitialize_atfork(lock) (\
	native_mutex_unlock(lock), \
	native_mutex_initialize(lock), \
	native_mutex_lock(lock))

#define GVL_SIMPLE_LOCK 0
#define GVL_DEBUG 0

static void
gvl_show_waiting_threads(rb_vm_t *vm)
{
    rb_thread_t *th = vm->gvl.waiting_threads;
    int i = 0;
    while (th) {
	fprintf(stderr, "waiting (%d): %p\n", i++, th);
	th = th->native_thread_data.gvl_next;
    }
}

#if !GVL_SIMPLE_LOCK
static void
gvl_waiting_push(rb_vm_t *vm, rb_thread_t *th)
{
    th->native_thread_data.gvl_next = 0;

    if (vm->gvl.waiting_threads) {
	vm->gvl.waiting_last_thread->native_thread_data.gvl_next = th;
	vm->gvl.waiting_last_thread = th;
    }
    else {
	vm->gvl.waiting_threads = th;
	vm->gvl.waiting_last_thread = th;
    }
    th = vm->gvl.waiting_threads;
    vm->gvl.waiting++;
}

static void
gvl_waiting_shift(rb_vm_t *vm, rb_thread_t *th)
{
    vm->gvl.waiting_threads = vm->gvl.waiting_threads->native_thread_data.gvl_next;
    vm->gvl.waiting--;
}
#endif

static void
gvl_acquire(rb_vm_t *vm, rb_thread_t *th)
{
#if GVL_SIMPLE_LOCK
    native_mutex_lock(&vm->gvl.lock);
#else
    native_mutex_lock(&vm->gvl.lock);
    if (vm->gvl.waiting > 0 || vm->gvl.acquired != 0) {
	if (GVL_DEBUG) fprintf(stderr, "gvl acquire (%p): sleep\n", th);
	gvl_waiting_push(vm, th);
        if (GVL_DEBUG) gvl_show_waiting_threads(vm);

	while (vm->gvl.acquired != 0 || vm->gvl.waiting_threads != th) {
	    native_cond_wait(&th->native_thread_data.gvl_cond, &vm->gvl.lock);
	}
	gvl_waiting_shift(vm, th);
    }
    else {
	/* do nothing */
    }
    vm->gvl.acquired = 1;
    native_mutex_unlock(&vm->gvl.lock);
#endif
    if (GVL_DEBUG) gvl_show_waiting_threads(vm);
    if (GVL_DEBUG) fprintf(stderr, "gvl acquire (%p): acquire\n", th);
}

static void
gvl_release(rb_vm_t *vm)
{
#if GVL_SIMPLE_LOCK
    native_mutex_unlock(&vm->gvl.lock);
#else
    native_mutex_lock(&vm->gvl.lock);
    if (vm->gvl.waiting > 0) {
	rb_thread_t *th = vm->gvl.waiting_threads;
	if (GVL_DEBUG) fprintf(stderr, "gvl release (%p): wakeup: %p\n", GET_THREAD(), th);
	native_cond_signal(&th->native_thread_data.gvl_cond);
    }
    else {
	if (GVL_DEBUG) fprintf(stderr, "gvl release (%p): wakeup: %p\n", GET_THREAD(), NULL);
	/* do nothing */
    }
    vm->gvl.acquired = 0;
    native_mutex_unlock(&vm->gvl.lock);
#endif
}

static void
gvl_atfork(rb_vm_t *vm)
{
#if GVL_SIMPLE_LOCK
    native_mutex_reinitialize_atfork(&vm->gvl.lock);
#else
    /* do nothing */
#endif
}

static void gvl_reinit(rb_vm_t *vm);

static void
gvl_atfork_child(void)
{
    gvl_reinit(GET_VM());
}

static void
gvl_init(rb_vm_t *vm)
{
    if (GVL_DEBUG) fprintf(stderr, "gvl init\n");
    native_atfork(0, 0, gvl_atfork_child);
    gvl_reinit(vm);
}

static void
gvl_reinit(rb_vm_t *vm)
{
    native_mutex_initialize(&vm->gvl.lock);
    vm->gvl.waiting_threads = 0;
    vm->gvl.waiting_last_thread = 0;
    vm->gvl.waiting = 0;
    vm->gvl.acquired = 0;
}

static void
gvl_destroy(rb_vm_t *vm)
{
    if (GVL_DEBUG) fprintf(stderr, "gvl destroy\n");
    native_mutex_destroy(&vm->gvl.lock);
}

static void
mutex_debug(const char *msg, pthread_mutex_t *lock)
{
    if (0) {
	int r;
	static pthread_mutex_t dbglock = PTHREAD_MUTEX_INITIALIZER;

	if ((r = pthread_mutex_lock(&dbglock)) != 0) {exit(1);}
	fprintf(stdout, "%s: %p\n", msg, lock);
	if ((r = pthread_mutex_unlock(&dbglock)) != 0) {exit(1);}
    }
}

#define NATIVE_MUTEX_LOCK_DEBUG 1

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
native_cond_initialize(pthread_cond_t *cond)
{
    int r = pthread_cond_init(cond, 0);
    if (r != 0) {
	rb_bug_errno("pthread_cond_init", r);
    }
}

static void
native_cond_destroy(pthread_cond_t *cond)
{
    int r = pthread_cond_destroy(cond);
    if (r != 0) {
	rb_bug_errno("pthread_cond_destroy", r);
    }
}

static void
native_cond_signal(pthread_cond_t *cond)
{
    pthread_cond_signal(cond);
}

static void
native_cond_broadcast(pthread_cond_t *cond)
{
    pthread_cond_broadcast(cond);
}

static void
native_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex)
{
    pthread_cond_wait(cond, mutex);
}

static int
native_cond_timedwait(pthread_cond_t *cond, pthread_mutex_t *mutex, struct timespec *ts)
{
    return pthread_cond_timedwait(cond, mutex, ts);
}

static void
native_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void))
{
    int r = pthread_atfork(prepare, parent, child);
    if (r != 0) {
	rb_bug_errno("native_atfork", r);
    }
}

#define native_cleanup_push pthread_cleanup_push
#define native_cleanup_pop  pthread_cleanup_pop
#ifdef HAVE_SCHED_YIELD
#define native_thread_yield() (void)sched_yield()
#else
#define native_thread_yield() ((void)0)
#endif

#ifndef __CYGWIN__
static void add_signal_thread_list(rb_thread_t *th);
#endif
static void remove_signal_thread_list(rb_thread_t *th);

static rb_thread_lock_t signal_thread_list_lock;

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
    native_thread_init(th);
    native_mutex_initialize(&signal_thread_list_lock);
    posix_signal(SIGVTALRM, null_func);
}

static void
native_thread_init(rb_thread_t *th)
{
    native_cond_initialize(&th->native_thread_data.sleep_cond);
    native_cond_initialize(&th->native_thread_data.gvl_cond);
    ruby_thread_set_native(th);
}

static void
native_thread_destroy(rb_thread_t *th)
{
    pthread_mutex_destroy(&th->interrupt_lock);
    pthread_cond_destroy(&th->native_thread_data.sleep_cond);
}

#define USE_THREAD_CACHE 0

#if defined HAVE_PTHREAD_GETATTR_NP || defined HAVE_PTHREAD_ATTR_GET_NP
#define STACKADDR_AVAILABLE 1
#elif defined HAVE_PTHREAD_GET_STACKADDR_NP && defined HAVE_PTHREAD_GET_STACKSIZE_NP
#define STACKADDR_AVAILABLE 1
#elif defined HAVE_THR_STKSEGMENT || defined HAVE_PTHREAD_STACKSEG_NP
#define STACKADDR_AVAILABLE 1
#elif defined HAVE_PTHREAD_GETTHRDS_NP
#define STACKADDR_AVAILABLE 1
#endif

#ifdef STACKADDR_AVAILABLE
static int
get_stack(void **addr, size_t *size)
{
#define CHECK_ERR(expr)				\
    {int err = (expr); if (err) return err;}
#if defined HAVE_PTHREAD_GETATTR_NP || defined HAVE_PTHREAD_ATTR_GET_NP
    pthread_attr_t attr;
    size_t guard = 0;

# ifdef HAVE_PTHREAD_GETATTR_NP
    CHECK_ERR(pthread_getattr_np(pthread_self(), &attr));
#   ifdef HAVE_PTHREAD_ATTR_GETSTACK
    CHECK_ERR(pthread_attr_getstack(&attr, addr, size));
#   else
    CHECK_ERR(pthread_attr_getstackaddr(&attr, addr));
    CHECK_ERR(pthread_attr_getstacksize(&attr, size));
#   endif
    if (pthread_attr_getguardsize(&attr, &guard) == 0) {
	STACK_GROW_DIR_DETECTION;
	STACK_DIR_UPPER((void)0, (void)(*addr = (char *)*addr + guard));
	*size -= guard;
    }
# else
    CHECK_ERR(pthread_attr_init(&attr));
    CHECK_ERR(pthread_attr_get_np(pthread_self(), &attr));
    CHECK_ERR(pthread_attr_getstackaddr(&attr, addr));
    CHECK_ERR(pthread_attr_getstacksize(&attr, size));
# endif
    CHECK_ERR(pthread_attr_getguardsize(&attr, &guard));
    *size -= guard;
    pthread_attr_destroy(&attr);
#elif defined HAVE_PTHREAD_GET_STACKADDR_NP && defined HAVE_PTHREAD_GET_STACKSIZE_NP
    pthread_t th = pthread_self();
    *addr = pthread_get_stackaddr_np(th);
    *size = pthread_get_stacksize_np(th);
#elif defined HAVE_THR_STKSEGMENT || defined HAVE_PTHREAD_STACKSEG_NP
    stack_t stk;
# if defined HAVE_THR_STKSEGMENT
    CHECK_ERR(thr_stksegment(&stk));
# else
    CHECK_ERR(pthread_stackseg_np(pthread_self(), &stk));
# endif
    *addr = stk.ss_sp;
    *size = stk.ss_size;
#elif defined HAVE_PTHREAD_GETTHRDS_NP
    pthread_t th = pthread_self();
    struct __pthrdsinfo thinfo;
    char reg[256];
    int regsiz=sizeof(reg);
    CHECK_ERR(pthread_getthrds_np(&th, PTHRDSINFO_QUERY_ALL,
				   &thinfo, sizeof(thinfo),
				   &reg, &regsiz));
    *addr = thinfo.__pi_stackaddr;
    *size = thinfo.__pi_stacksize;
#endif
    return 0;
#undef CHECK_ERR
}
#endif

static struct {
    rb_thread_id_t id;
    size_t stack_maxsize;
    VALUE *stack_start;
#ifdef __ia64
    VALUE *register_stack_start;
#endif
} native_main_thread;

#ifdef STACK_END_ADDRESS
extern void *STACK_END_ADDRESS;
#endif

#undef ruby_init_stack
void
ruby_init_stack(volatile VALUE *addr
#ifdef __ia64
    , void *bsp
#endif
    )
{
    native_main_thread.id = pthread_self();
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
	size_t size = 0;
	size_t space = 0;
#if defined(HAVE_PTHREAD_ATTR_GET_NP)
	void* addr;
	get_stack(&addr, &size);
#elif defined(HAVE_GETRLIMIT)
	struct rlimit rlim;
	if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
	    size = (size_t)rlim.rlim_cur;
	}
#endif
	space = size > 5 * 1024 * 1024 ? 1024 * 1024 : size / 5;
	native_main_thread.stack_maxsize = size - space;
    }
}

#define CHECK_ERR(expr) \
    {int err = (expr); if (err) {rb_bug_errno(#expr, err);}}

static int
native_thread_init_stack(rb_thread_t *th)
{
    rb_thread_id_t curr = pthread_self();

    if (pthread_equal(curr, native_main_thread.id)) {
	th->machine_stack_start = native_main_thread.stack_start;
	th->machine_stack_maxsize = native_main_thread.stack_maxsize;
    }
    else {
#ifdef STACKADDR_AVAILABLE
	void *start;
	size_t size;

	if (get_stack(&start, &size) == 0) {
	    th->machine_stack_start = start;
	    th->machine_stack_maxsize = size;
	}
#else
	rb_raise(rb_eNotImpError, "ruby engine can initialize only in the main thread");
#endif
    }
#ifdef __ia64
    th->machine_register_stack_start = native_main_thread.register_stack_start;
    th->machine_stack_maxsize /= 2;
    th->machine_register_stack_maxsize = th->machine_stack_maxsize;
#endif
    return 0;
}

static void *
thread_start_func_1(void *th_ptr)
{
#if USE_THREAD_CACHE
  thread_start:
#endif
    {
	rb_thread_t *th = th_ptr;
	VALUE stack_start;

#ifndef __CYGWIN__
	native_thread_init_stack(th);
#endif
	native_thread_init(th);
	/* run */
	thread_start_func_2(th, &stack_start, rb_ia64_bsp());
    }
#if USE_THREAD_CACHE
    if (1) {
	/* cache thread */
	rb_thread_t *th;
	static rb_thread_t *register_cached_thread_and_wait(void);
	if ((th = register_cached_thread_and_wait()) != 0) {
	    th_ptr = (void *)th;
	    th->thread_id = pthread_self();
	    goto thread_start;
	}
    }
#endif
    return 0;
}

void rb_thread_create_control_thread(void);

struct cached_thread_entry {
    volatile rb_thread_t **th_area;
    pthread_cond_t *cond;
    struct cached_thread_entry *next;
};


#if USE_THREAD_CACHE
static pthread_mutex_t thread_cache_lock = PTHREAD_MUTEX_INITIALIZER;
struct cached_thread_entry *cached_thread_root;

static rb_thread_t *
register_cached_thread_and_wait(void)
{
    pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
    volatile rb_thread_t *th_area = 0;
    struct cached_thread_entry *entry =
      (struct cached_thread_entry *)malloc(sizeof(struct cached_thread_entry));

    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, 0);
    ts.tv_sec = tv.tv_sec + 60;
    ts.tv_nsec = tv.tv_usec * 1000;

    pthread_mutex_lock(&thread_cache_lock);
    {
	entry->th_area = &th_area;
	entry->cond = &cond;
	entry->next = cached_thread_root;
	cached_thread_root = entry;

	pthread_cond_timedwait(&cond, &thread_cache_lock, &ts);

	{
	    struct cached_thread_entry *e = cached_thread_root;
	    struct cached_thread_entry *prev = cached_thread_root;

	    while (e) {
		if (e == entry) {
		    if (prev == cached_thread_root) {
			cached_thread_root = e->next;
		    }
		    else {
			prev->next = e->next;
		    }
		    break;
		}
		prev = e;
		e = e->next;
	    }
	}

	free(entry); /* ok */
	pthread_cond_destroy(&cond);
    }
    pthread_mutex_unlock(&thread_cache_lock);

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
	pthread_mutex_lock(&thread_cache_lock);
	entry = cached_thread_root;
	{
	    if (cached_thread_root) {
		cached_thread_root = entry->next;
		*entry->th_area = th;
		result = 1;
	    }
	}
	if (result) {
	    pthread_cond_signal(entry->cond);
	}
	pthread_mutex_unlock(&thread_cache_lock);
    }
#endif
    return result;
}

enum {
#ifdef __SYMBIAN32__
    RUBY_STACK_MIN_LIMIT = 64 * 1024,  /* 64KB: Let's be slightly more frugal on mobile platform */
#else
    RUBY_STACK_MIN_LIMIT = 512 * 1024, /* 512KB */
#endif
    RUBY_STACK_SPACE_LIMIT = 1024 * 1024
};

#ifdef PTHREAD_STACK_MIN
#define RUBY_STACK_MIN ((RUBY_STACK_MIN_LIMIT < PTHREAD_STACK_MIN) ? \
			PTHREAD_STACK_MIN * 2 : RUBY_STACK_MIN_LIMIT)
#else
#define RUBY_STACK_MIN (RUBY_STACK_MIN_LIMIT)
#endif
#define RUBY_STACK_SPACE (RUBY_STACK_MIN/5 > RUBY_STACK_SPACE_LIMIT ? \
			  RUBY_STACK_SPACE_LIMIT : RUBY_STACK_MIN/5)

static int
native_thread_create(rb_thread_t *th)
{
    int err = 0;

    if (use_cached_thread(th)) {
	thread_debug("create (use cached thread): %p\n", (void *)th);
    }
    else {
	pthread_attr_t attr;
	const size_t stack_size = RUBY_STACK_MIN;
	const size_t space = RUBY_STACK_SPACE;

        th->machine_stack_maxsize = stack_size - space;
#ifdef __ia64
        th->machine_stack_maxsize /= 2;
        th->machine_register_stack_maxsize = th->machine_stack_maxsize;
#endif

	CHECK_ERR(pthread_attr_init(&attr));

#ifdef PTHREAD_STACK_MIN
	thread_debug("create - stack size: %lu\n", (unsigned long)stack_size);
	CHECK_ERR(pthread_attr_setstacksize(&attr, stack_size));
#endif

#ifdef HAVE_PTHREAD_ATTR_SETINHERITSCHED
	CHECK_ERR(pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED));
#endif
	CHECK_ERR(pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED));

	err = pthread_create(&th->thread_id, &attr, thread_start_func_1, th);
	thread_debug("create: %p (%d)", (void *)th, err);
	CHECK_ERR(pthread_attr_destroy(&attr));
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

static void
ubf_pthread_cond_signal(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    thread_debug("ubf_pthread_cond_signal (%p)\n", (void *)th);
    pthread_cond_signal(&th->native_thread_data.sleep_cond);
}

#if !defined(__CYGWIN__) && !defined(__SYMBIAN32__)
static void
ubf_select_each(rb_thread_t *th)
{
    thread_debug("ubf_select_each (%p)\n", (void *)th->thread_id);
    if (th) {
	pthread_kill(th->thread_id, SIGVTALRM);
    }
}

static void
ubf_select(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    add_signal_thread_list(th);
    ubf_select_each(th);
}
#else
#define ubf_select 0
#endif

#define PER_NANO 1000000000

static void
native_sleep(rb_thread_t *th, struct timeval *tv)
{
    struct timespec ts;
    struct timeval tvn;

    if (tv) {
	gettimeofday(&tvn, NULL);
	ts.tv_sec = tvn.tv_sec + tv->tv_sec;
	ts.tv_nsec = (tvn.tv_usec + tv->tv_usec) * 1000;
	if (ts.tv_nsec >= PER_NANO){
	    ts.tv_sec += 1;
	    ts.tv_nsec -= PER_NANO;
	}
    }

    thread_debug("native_sleep %ld\n", (long)(tv ? tv->tv_sec : -1));
    GVL_UNLOCK_BEGIN();
    {
	pthread_mutex_lock(&th->interrupt_lock);
	th->unblock.func = ubf_pthread_cond_signal;
	th->unblock.arg = th;

	if (RUBY_VM_INTERRUPTED(th)) {
	    /* interrupted.  return immediate */
	    thread_debug("native_sleep: interrupted before sleep\n");
	}
	else {
	    if (tv == 0 || ts.tv_sec < tvn.tv_sec /* overflow */ ) {
		int r;
		thread_debug("native_sleep: pthread_cond_wait start\n");
		r = pthread_cond_wait(&th->native_thread_data.sleep_cond,
				      &th->interrupt_lock);
                if (r) rb_bug_errno("pthread_cond_wait", r);
		thread_debug("native_sleep: pthread_cond_wait end\n");
	    }
	    else {
		int r;
		thread_debug("native_sleep: pthread_cond_timedwait start (%ld, %ld)\n",
			     (unsigned long)ts.tv_sec, ts.tv_nsec);
		r = pthread_cond_timedwait(&th->native_thread_data.sleep_cond,
					   &th->interrupt_lock, &ts);
		if (r && r != ETIMEDOUT) rb_bug_errno("pthread_cond_timedwait", r);

		thread_debug("native_sleep: pthread_cond_timedwait end (%d)\n", r);
	    }
	}
	th->unblock.func = 0;
	th->unblock.arg = 0;

	pthread_mutex_unlock(&th->interrupt_lock);
    }
    GVL_UNLOCK_END();

    thread_debug("native_sleep done\n");
}

struct signal_thread_list {
    rb_thread_t *th;
    struct signal_thread_list *prev;
    struct signal_thread_list *next;
};

#ifndef __CYGWIN__
static struct signal_thread_list signal_thread_list_anchor = {
    0, 0, 0,
};
#endif

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
    while(list){
	thread_debug("%p (%p), ", list->th, list->th->thread_id);
	list = list->next;
    }
    thread_debug("\n");
}
#endif

#ifndef __CYGWIN__
static void
add_signal_thread_list(rb_thread_t *th)
{
    if (!th->native_thread_data.signal_thread_list) {
	FGLOCK(&signal_thread_list_lock, {
	    struct signal_thread_list *list =
	      malloc(sizeof(struct signal_thread_list));

	    if (list == 0) {
		fprintf(stderr, "[FATAL] failed to allocate memory\n");
		exit(1);
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
#endif

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
    else {
	/* */
    }
}

static pthread_t timer_thread_id;
static pthread_cond_t timer_thread_cond = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t timer_thread_lock = PTHREAD_MUTEX_INITIALIZER;

static struct timespec *
get_ts(struct timespec *ts, unsigned long nsec)
{
    struct timeval tv;
    gettimeofday(&tv, 0);
    ts->tv_sec = tv.tv_sec;
    ts->tv_nsec = tv.tv_usec * 1000 + nsec;
    if (ts->tv_nsec >= PER_NANO) {
	ts->tv_sec++;
	ts->tv_nsec -= PER_NANO;
    }
    return ts;
}

static void *
thread_timer(void *dummy)
{
    struct timespec ts;

    native_mutex_lock(&timer_thread_lock);
    native_cond_broadcast(&timer_thread_cond);
#define WAIT_FOR_10MS() native_cond_timedwait(&timer_thread_cond, &timer_thread_lock, get_ts(&ts, PER_NANO/100))
    while (system_working > 0) {
	int err = WAIT_FOR_10MS();
	if (err == ETIMEDOUT);
	else if (err == 0 || err == EINTR) {
	    if (rb_signal_buff_size() == 0) break;
	}
	else rb_bug_errno("thread_timer/timedwait", err);

#if !defined(__CYGWIN__) && !defined(__SYMBIAN32__)
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
#endif
	timer_thread_function(dummy);
    }
    native_mutex_unlock(&timer_thread_lock);
    return NULL;
}

static void
rb_thread_create_timer_thread(void)
{
    rb_enable_interrupt();

    if (!timer_thread_id) {
	pthread_attr_t attr;
	int err;

	pthread_attr_init(&attr);
#ifdef PTHREAD_STACK_MIN
	pthread_attr_setstacksize(&attr,
				  PTHREAD_STACK_MIN + (THREAD_DEBUG ? BUFSIZ : 0));
#endif
	native_mutex_lock(&timer_thread_lock);
	err = pthread_create(&timer_thread_id, &attr, thread_timer, 0);
	if (err != 0) {
	    native_mutex_unlock(&timer_thread_lock);
	    fprintf(stderr, "[FATAL] Failed to create timer thread (errno: %d)\n", err);
	    exit(EXIT_FAILURE);
	}
	native_cond_wait(&timer_thread_cond, &timer_thread_lock);
	native_mutex_unlock(&timer_thread_lock);
    }
    rb_disable_interrupt(); /* only timer thread recieve signal */
}

static int
native_stop_timer_thread(void)
{
    int stopped;
    native_mutex_lock(&timer_thread_lock);
    stopped = --system_working <= 0;
    if (stopped) {
	native_cond_signal(&timer_thread_cond);
    }
    native_mutex_unlock(&timer_thread_lock);
    if (stopped) {
	native_thread_join(timer_thread_id);
    }
    return stopped;
}

static void
native_reset_timer_thread(void)
{
    timer_thread_id = 0;
}

#ifdef HAVE_SIGALTSTACK
int
ruby_stack_overflowed_p(const rb_thread_t *th, const void *addr)
{
    void *base;
    size_t size;
    const size_t water_mark = 1024 * 1024;
    STACK_GROW_DIR_DETECTION;

    if (th) {
	size = th->machine_stack_maxsize;
	base = (char *)th->machine_stack_start - STACK_DIR_UPPER(0, size);
    }
#ifdef STACKADDR_AVAILABLE
    else if (get_stack(&base, &size) == 0) {
	STACK_DIR_UPPER((void)(base = (char *)base + size), (void)0);
    }
#endif
    else {
	return 0;
    }
    size /= 5;
    if (size > water_mark) size = water_mark;
    if (STACK_DIR_UPPER(1, 0)) {
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

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
