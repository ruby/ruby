/**********************************************************************

  thread_native.h -

  $Author: ko1 $
  created at: Wed May 14 19:37:31 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_THREAD_NATIVE_H
#define RUBY_THREAD_NATIVE_H 1

/*
 * This file contains wrapper APIs for native thread primitives
 * which Ruby interpreter uses.
 *
 * Now, we only suppors pthread and Windows threads.
 *
 * If you want to use Ruby's Mutex and so on to synchronize Ruby Threads,
 * please use Mutex directly.
 */


#if defined(_WIN32)
#include <windows.h>
typedef HANDLE rb_nativethread_id_t;

typedef union rb_thread_lock_union {
    HANDLE mutex;
    CRITICAL_SECTION crit;
} rb_nativethread_lock_t;

#elif defined(HAVE_PTHREAD_H)
#include <pthread.h>
typedef pthread_t rb_nativethread_id_t;
typedef pthread_mutex_t rb_nativethread_lock_t;

#else
#error "unsupported thread type"

#endif

RUBY_SYMBOL_EXPORT_BEGIN

rb_nativethread_id_t rb_nativethread_self();

void rb_nativethread_lock_initialize(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_destroy(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_lock(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_unlock(rb_nativethread_lock_t *lock);

RUBY_SYMBOL_EXPORT_END

#endif
