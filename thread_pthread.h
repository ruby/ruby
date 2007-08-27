/**********************************************************************

  thread_pthread.h -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef THREAD_PTHREAD_H_INCLUDED
#define THREAD_PTHREAD_H_INCLUDED

#include <pthread.h>
typedef pthread_t rb_thread_id_t;
typedef pthread_mutex_t rb_thread_lock_t;
typedef pthread_cond_t rb_thread_cond_t;

void native_mutex_lock(pthread_mutex_t *lock);
void native_mutex_unlock(pthread_mutex_t *lock);
void native_mutex_destroy(pthread_mutex_t *lock);
int native_mutex_trylock(pthread_mutex_t *lock);
void native_mutex_initialize(pthread_mutex_t *lock);
void native_mutex_destroy(pthread_mutex_t *lock);

void native_cond_signal(pthread_cond_t *cond);
void native_cond_broadcast(pthread_cond_t *cond);
void native_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
void native_cond_initialize(pthread_cond_t *cond);
void native_cond_destroy(pthread_cond_t *cond);

typedef struct native_thread_data_struct {
    void *signal_thread_list;
    pthread_cond_t sleep_cond;
} native_thread_data_t;

#endif /* THREAD_PTHREAD_H_INCLUDED */
