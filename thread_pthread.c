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

static void
native_mutex_lock(pthread_mutex_t *lock)
{
    int r;
    if ((r = pthread_mutex_lock(lock)) != 0) {
	rb_bug("pthread_mutex_lock: %d", r);
    }
}

static void
native_mutex_unlock(pthread_mutex_t *lock)
{
    int r;
    if ((r = pthread_mutex_unlock(lock)) != 0) {
	rb_bug("native_mutex_unlock return non-zero: %d", r);
    }
}

static inline int
native_mutex_trylock(pthread_mutex_t *lock)
{
    int r;
    if ((r = pthread_mutex_trylock(lock)) != 0) {
	if (r == EBUSY) {
	    return EBUSY;
	}
	else {
	    rb_bug("native_mutex_trylock return non-zero: %d", r);
	}
    }
    return 0;
}

static void
native_mutex_initialize(pthread_mutex_t *lock)
{
    int r = pthread_mutex_init(lock, 0);
    if (r != 0) {
	rb_bug("native_mutex_initialize return non-zero: %d", r);
    }
}

static void
native_mutex_destroy(pthread_mutex_t *lock)
{
    int r = pthread_mutex_destroy(lock);
    if (r != 0) {
	rb_bug("native_mutex_destroy return non-zero: %d", r);
    }
}

static void
native_cond_initialize(pthread_cond_t *cond)
{
    int r = pthread_cond_init(cond, 0);
    if (r != 0) {
	rb_bug("native_cond_initialize return non-zero: %d", r);
    }
}

static void
native_cond_destroy(pthread_cond_t *cond)
{
    int r = pthread_cond_destroy(cond);
    if (r != 0) {
	rb_bug("native_cond_destroy return non-zero: %d", r);
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


#define native_cleanup_push pthread_cleanup_push
#define native_cleanup_pop  pthread_cleanup_pop
#ifdef __HAIKU__
#define native_thread_yield() /* not available under Haiku */
#else
#define native_thread_yield() sched_yield()
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

static void
Init_native_thread(void)
{
    rb_thread_t *th = GET_THREAD();

    pthread_key_create(&ruby_native_thread_key, NULL);
    th->thread_id = pthread_self();
    native_cond_initialize(&th->native_thread_data.sleep_cond);
    ruby_thread_set_native(th);
    native_mutex_initialize(&signal_thread_list_lock);
    posix_signal(SIGVTALRM, null_func);
}

static void
native_thread_destroy(rb_thread_t *th)
{
    pthread_mutex_destroy(&th->interrupt_lock);
    pthread_cond_destroy(&th->native_thread_data.sleep_cond);
}

#define USE_THREAD_CACHE 0

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
ruby_init_stack(VALUE *addr
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
        STACK_UPPER(&addr,
                    native_main_thread.stack_start > addr,
                    native_main_thread.stack_start < addr)) {
        native_main_thread.stack_start = addr;
    }
#endif
#ifdef __ia64
    if (!native_main_thread.register_stack_start ||
        (VALUE*)bsp < native_main_thread.register_stack_start) {
        native_main_thread.register_stack_start = (VALUE*)bsp;
    }
#endif
#ifdef HAVE_GETRLIMIT
    {
	struct rlimit rlim;

	if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
	    unsigned int space = rlim.rlim_cur/5;

	    if (space > 1024*1024) space = 1024*1024;
	    native_main_thread.stack_maxsize = rlim.rlim_cur - space;
	}
    }
#endif
}

#define CHECK_ERR(expr) \
    {int err = (expr); if (err) {rb_bug("err: %d - %s", err, #expr);}}

static int
native_thread_init_stack(rb_thread_t *th)
{
    rb_thread_id_t curr = pthread_self();

    if (pthread_equal(curr, native_main_thread.id)) {
	th->machine_stack_start = native_main_thread.stack_start;
	th->machine_stack_maxsize = native_main_thread.stack_maxsize;
    }
    else {
#ifdef HAVE_PTHREAD_GETATTR_NP
	pthread_attr_t attr;
	void *start;
	CHECK_ERR(pthread_getattr_np(curr, &attr));
# if defined HAVE_PTHREAD_ATTR_GETSTACK
	CHECK_ERR(pthread_attr_getstack(&attr, &start, &th->machine_stack_maxsize));
# elif defined HAVE_PTHREAD_ATTR_GETSTACKSIZE && defined HAVE_PTHREAD_ATTR_GETSTACKADDR
	CHECK_ERR(pthread_attr_getstackaddr(&attr, &start));
	CHECK_ERR(pthread_attr_getstacksize(&attr, &th->machine_stack_maxsize));
# endif
	th->machine_stack_start = start;
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

static int
native_thread_create(rb_thread_t *th)
{
    int err = 0;

    if (use_cached_thread(th)) {
	thread_debug("create (use cached thread): %p\n", th);
    }
    else {
	pthread_attr_t attr;
	size_t stack_size = 512 * 1024; /* 512KB */
        size_t space;

#ifdef PTHREAD_STACK_MIN
	if (stack_size < PTHREAD_STACK_MIN) {
	    stack_size = PTHREAD_STACK_MIN * 2;
	}
#endif
        space = stack_size/5;
        if (space > 1024*1024) space = 1024*1024;
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

#ifndef __HAIKU__  /* not yet available under Haiku */
	CHECK_ERR(pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED));
#endif
	CHECK_ERR(pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED));

	err = pthread_create(&th->thread_id, &attr, thread_start_func_1, th);
	thread_debug("create: %p (%d)", th, err);
	CHECK_ERR(pthread_attr_destroy(&attr));

	if (!err) {
	    pthread_cond_init(&th->native_thread_data.sleep_cond, 0);
	}
	else {
	    st_delete_wrap(th->vm->living_threads, th->self);
	    th->status = THREAD_KILLED;
	    rb_raise(rb_eThreadError, "can't create Thread (%d)", err);
	}
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

static void
ubf_pthread_cond_signal(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    thread_debug("ubf_pthread_cond_signal (%p)\n", th);
    pthread_cond_signal(&th->native_thread_data.sleep_cond);
}

#ifndef __CYGWIN__
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

static void
native_sleep(rb_thread_t *th, struct timeval *tv)
{
    struct timespec ts;
    struct timeval tvn;

    if (tv) {
	gettimeofday(&tvn, NULL);
	ts.tv_sec = tvn.tv_sec + tv->tv_sec;
	ts.tv_nsec = (tvn.tv_usec + tv->tv_usec) * 1000;
        if (ts.tv_nsec >= 1000000000){
	    ts.tv_sec += 1;
	    ts.tv_nsec -= 1000000000;
        }
    }

    thread_debug("native_sleep %ld\n", tv ? tv->tv_sec : -1);
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
                if (r) rb_bug("pthread_cond_wait: %d", r);
		thread_debug("native_sleep: pthread_cond_wait end\n");
	    }
	    else {
		int r;
		thread_debug("native_sleep: pthread_cond_timedwait start (%ld, %ld)\n",
			     (unsigned long)ts.tv_sec, ts.tv_nsec);
		r = pthread_cond_timedwait(&th->native_thread_data.sleep_cond,
					   &th->interrupt_lock, &ts);
		if (r && r != ETIMEDOUT) rb_bug("pthread_cond_timedwait: %d", r);

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

static void *
thread_timer(void *dummy)
{
    while (system_working) {
#ifdef HAVE_NANOSLEEP
	struct timespec req, rem;
	req.tv_sec = 0;
	req.tv_nsec = 10 * 1000 * 1000;	/* 10 ms */
	nanosleep(&req, &rem);
#else
	struct timeval tv;
	tv.tv_sec = 0;
	tv.tv_usec = 10000;     	/* 10 ms */
	select(0, NULL, NULL, NULL, &tv);
#endif
#ifndef __CYGWIN__
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
	err = pthread_create(&timer_thread_id, &attr, thread_timer, GET_VM());
	if (err != 0) {
	    rb_bug("rb_thread_create_timer_thread: return non-zero (%d)", err);
	}
    }
    rb_disable_interrupt(); /* only timer thread recieve signal */
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
