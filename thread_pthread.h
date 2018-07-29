/**********************************************************************

  thread_pthread.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_THREAD_PTHREAD_H
#define RUBY_THREAD_PTHREAD_H

#ifdef HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif

#define RB_NATIVETHREAD_LOCK_INIT PTHREAD_MUTEX_INITIALIZER
#define RB_NATIVETHREAD_COND_INIT PTHREAD_COND_INITIALIZER

typedef pthread_cond_t rb_nativethread_cond_t;

typedef struct native_thread_data_struct {
    struct list_node ubf_list;
    rb_nativethread_cond_t sleep_cond;
} native_thread_data_t;

#undef except
#undef try
#undef leave
#undef finally

typedef struct rb_global_vm_lock_struct {
    /* fast path */
    const struct rb_thread_struct *acquired;
    rb_nativethread_lock_t lock;

    /* slow path */
    struct list_head waitq;
    const struct rb_thread_struct *timer;

    /* yield */
    rb_nativethread_cond_t switch_cond;
    rb_nativethread_cond_t switch_wait_cond;
    int need_yield;
    int wait_yield;
} rb_global_vm_lock_t;

#endif /* RUBY_THREAD_PTHREAD_H */
