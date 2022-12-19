#ifndef RUBY_THREAD_PTHREAD_H
#define RUBY_THREAD_PTHREAD_H
/**********************************************************************

  thread_pthread.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif

#define RB_NATIVETHREAD_LOCK_INIT PTHREAD_MUTEX_INITIALIZER
#define RB_NATIVETHREAD_COND_INIT PTHREAD_COND_INITIALIZER

// per-Thead scheduler helper data
struct rb_thread_sched_item {
    union {
        struct ccan_list_node ubf;
        struct ccan_list_node readyq; // protected by sched->lock
    } node;
};

struct rb_native_thread {
    int id;

    rb_nativethread_id_t thread_id;

#ifdef RB_THREAD_T_HAS_NATIVE_ID
    int tid;
#endif

    struct rb_thread_struct *running_thread;

    // to control native thread
#if defined(__GLIBC__) || defined(__FreeBSD__)
    union
#else
    /*
     * assume the platform condvars are badly implemented and have a
     * "memory" of which mutex they're associated with
     */
    struct
#endif
      {
        rb_nativethread_cond_t intr; /* th->interrupt_lock */
        rb_nativethread_cond_t readyq; /* use sched->lock */
    } cond;

#ifdef USE_SIGALTSTACK
    void *altstack;
#endif
};

#undef except
#undef try
#undef leave
#undef finally

// per-Ractor
struct rb_thread_sched {
    /* fast path */

    const struct rb_thread_struct *running; // running thread or NULL
    rb_nativethread_lock_t lock;

    /*
     * slow path, protected by ractor->thread_sched->lock
     * - @readyq - FIFO queue of threads waiting for running
     * - @timer - it handles timeslices for @current.  It is any one thread
     *   in @waitq, there is no @timer if @waitq is empty, but always
     *   a @timer if @waitq has entries
     * - @timer_err tracks timeslice limit, the timeslice only resets
     *   when pthread_cond_timedwait returns ETIMEDOUT, so frequent
     *   switching between contended/uncontended GVL won't reset the
     *   timer.
     */
    struct ccan_list_head readyq;
    const struct rb_thread_struct *timer;
    int timer_err;

    /* yield */
    rb_nativethread_cond_t switch_cond;
    rb_nativethread_cond_t switch_wait_cond;
    int need_yield;
    int wait_yield;
};

#ifndef RB_THREAD_LOCAL_SPECIFIER_IS_UNSUPPORTED
# if __STDC_VERSION__ >= 201112
#   define RB_THREAD_LOCAL_SPECIFIER _Thread_local
# elif defined(__GNUC__)
  /* note that ICC (linux) and Clang are covered by __GNUC__ */
#   define RB_THREAD_LOCAL_SPECIFIER __thread
# endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN
#ifdef RB_THREAD_LOCAL_SPECIFIER
# ifdef __APPLE__
// on Darwin, TLS can not be accessed across .so
struct rb_execution_context_struct *rb_current_ec(void);
void rb_current_ec_set(struct rb_execution_context_struct *);
# else
RUBY_EXTERN RB_THREAD_LOCAL_SPECIFIER struct rb_execution_context_struct *ruby_current_ec;
# endif
#else
typedef pthread_key_t native_tls_key_t;

static inline void *
native_tls_get(native_tls_key_t key)
{
    // return value should be checked by caller
    return pthread_getspecific(key);
}

static inline void
native_tls_set(native_tls_key_t key, void *ptr)
{
    if (UNLIKELY(pthread_setspecific(key, ptr) != 0)) {
        rb_bug("pthread_setspecific error");
    }
}

RUBY_EXTERN native_tls_key_t ruby_current_ec_key;
#endif
RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_THREAD_PTHREAD_H */
