/**********************************************************************

  thread_pthread.h -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef THREAD_PTHREAD_H_INCLUDED
#define THREAD_PTHREAD_H_INCLUDED

#include <pthread.h>
typedef pthread_t yarv_thread_id_t;
typedef pthread_mutex_t yarv_thread_lock_t;

#define native_mutex_lock   pthread_mutex_lock
#define native_mutex_unlock pthread_mutex_unlock
#define native_mutex_trylock pthread_mutex_trylock

typedef struct native_thread_data_struct {
    void *signal_thread_list;
    pthread_cond_t sleep_cond;
} native_thread_data_t;

#endif /* THREAD_PTHREAD_H_INCLUDED */
