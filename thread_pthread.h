#ifndef RUBY_THREAD_PTHREAD_H
#define RUBY_THREAD_PTHREAD_H
/**********************************************************************

  thread_pthread.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

  This platform runs the common scheduler; see thread_sched.h for its data
  structures and thread_sched.c for the implementation.

**********************************************************************/

#ifdef HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif

#define RB_NATIVETHREAD_LOCK_INIT PTHREAD_MUTEX_INITIALIZER
#define RB_NATIVETHREAD_COND_INIT PTHREAD_COND_INITIALIZER

#include "thread_sched.h"

#ifdef RB_THREAD_LOCAL_SPECIFIER
  NOINLINE(void rb_current_ec_set(struct rb_execution_context_struct *));

  // Under M:N threads, a thread may move to another native thread in the middle of
  // a C function, so the compiler must not cache the TLS address of ruby_current_ec.
  NOINLINE(struct rb_execution_context_struct *rb_current_ec(void));

  // for RUBY_DEBUG_LOG()
  RUBY_EXTERN RB_THREAD_LOCAL_SPECIFIER rb_atomic_t ruby_nt_serial;
  #define RUBY_NT_SERIAL 1
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

#endif /* RUBY_THREAD_PTHREAD_H */
