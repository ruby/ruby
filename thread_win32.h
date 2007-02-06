/**********************************************************************

  thread_win32.h -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

/* interface */
#ifndef THREAD_WIN32_H_INCLUDED
#define THREAD_WIN32_H_INCLUDED

#include <windows.h>

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

#endif /* THREAD_WIN32_H_INCLUDED */

