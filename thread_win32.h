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

typedef HANDLE yarv_thread_id_t;
typedef CRITICAL_SECTION yarv_thread_lock_t;

int native_mutex_lock(yarv_thread_lock_t *);
int native_mutex_unlock(yarv_thread_lock_t *);
int native_mutex_trylock(yarv_thread_lock_t *);
void native_mutex_initialize(yarv_thread_lock_t *);

typedef struct native_thread_data_struct {
    HANDLE interrupt_event;
} native_thread_data_t;

#endif /* THREAD_WIN32_H_INCLUDED */

