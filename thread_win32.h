/**********************************************************************

  thread_win32.h -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

/* interface */
#ifndef RUBY_THREAD_WIN32_H
#define RUBY_THREAD_WIN32_H

#include <windows.h>

# ifdef __CYGWIN__
# undef _WIN32
# endif

WINBASEAPI BOOL WINAPI
TryEnterCriticalSection(IN OUT LPCRITICAL_SECTION lpCriticalSection);

typedef HANDLE rb_thread_id_t;
typedef CRITICAL_SECTION rb_thread_lock_t;

int native_mutex_lock(rb_thread_lock_t *);
int native_mutex_unlock(rb_thread_lock_t *);
int native_mutex_trylock(rb_thread_lock_t *);
void native_mutex_initialize(rb_thread_lock_t *);

typedef struct native_thread_data_struct {
    HANDLE interrupt_event;
} native_thread_data_t;

#endif /* RUBY_THREAD_WIN32_H */

