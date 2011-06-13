/**********************************************************************

  thread_pthread.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_THREAD_PTHREAD_H
#define RUBY_THREAD_PTHREAD_H

#include <pthread.h>
#ifdef HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif
typedef pthread_t rb_thread_id_t;
typedef pthread_mutex_t rb_thread_lock_t;

typedef struct rb_thread_cond_struct {
    pthread_cond_t cond;
#ifdef HAVE_CLOCKID_T
    clockid_t clockid;
#endif
} rb_thread_cond_t;

typedef struct native_thread_data_struct {
    void *signal_thread_list;
    rb_thread_cond_t sleep_cond;
    rb_thread_cond_t gvl_cond;
    struct rb_thread_struct *gvl_next;
} native_thread_data_t;

#include <semaphore.h>

typedef struct rb_global_vm_lock_struct {
    /* fast path */
    unsigned long acquired;
    pthread_mutex_t lock;

    /* slow path */
    unsigned long waiting;
    rb_thread_cond_t cond;

    /* yield */
    rb_thread_cond_t switch_cond;
    unsigned long need_yield;
} rb_global_vm_lock_t;

#endif /* RUBY_THREAD_PTHREAD_H */
