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
typedef pthread_cond_t rb_thread_cond_t;

typedef struct native_thread_data_struct {
    void *signal_thread_list;
    pthread_cond_t sleep_cond;
} native_thread_data_t;

#endif /* RUBY_THREAD_PTHREAD_H */
