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

typedef pthread_cond_t rb_nativethread_cond_t;

typedef struct native_thread_data_struct {
    union {
        struct list_node ubf;
        struct list_node gvl;
    } node;
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
        rb_nativethread_cond_t gvlq; /* vm->gvl.lock */
    } cond;
} native_thread_data_t;

void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
int  rb_native_mutex_trylock(rb_nativethread_lock_t *lock);
void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);
void rb_native_cond_signal(rb_nativethread_cond_t *cond);
void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);
void rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec);
void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
void rb_native_cond_destroy(rb_nativethread_cond_t *cond);

#undef except
#undef try
#undef leave
#undef finally

typedef struct rb_global_vm_lock_struct {
    /* fast path */
    const struct rb_thread_struct *owner;
    rb_nativethread_lock_t lock; /* AKA vm->gvl.lock */

    /*
     * slow path, protected by vm->gvl.lock
     * - @waitq - FIFO queue of threads waiting for GVL
     * - @timer - it handles timeslices for @owner.  It is any one thread
     *   in @waitq, there is no @timer if @waitq is empty, but always
     *   a @timer if @waitq has entries
     * - @timer_err tracks timeslice limit, the timeslice only resets
     *   when pthread_cond_timedwait returns ETIMEDOUT, so frequent
     *   switching between contended/uncontended GVL won't reset the
     *   timer.
     */
    struct list_head waitq; /* <=> native_thread_data_t.node.ubf */
    const struct rb_thread_struct *timer;
    int timer_err;

    /* yield */
    rb_nativethread_cond_t switch_cond;
    rb_nativethread_cond_t switch_wait_cond;
    int need_yield;
    int wait_yield;
} rb_global_vm_lock_t;

typedef pthread_key_t native_tls_key_t;

static inline void *
native_tls_get(native_tls_key_t key)
{
    void *ptr = pthread_getspecific(key);
    if (UNLIKELY(ptr == NULL)) {
        rb_bug("pthread_getspecific returns NULL");
    }
    return ptr;
}

static inline void
native_tls_set(native_tls_key_t key, void *ptr)
{
    if (UNLIKELY(pthread_setspecific(key, ptr) != 0)) {
        rb_bug("pthread_setspecific error");
    }
}

#endif /* RUBY_THREAD_PTHREAD_H */
