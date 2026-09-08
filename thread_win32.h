#ifndef RUBY_THREAD_WIN32_H
#define RUBY_THREAD_WIN32_H
/**********************************************************************

  thread_win32.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

  This platform runs the common scheduler; see thread_sched.h for its data
  structures and thread_sched.c for the implementation.

**********************************************************************/

/* interface */

# ifdef __CYGWIN__
# undef _WIN32
# endif

WINBASEAPI BOOL WINAPI
TryEnterCriticalSection(IN OUT LPCRITICAL_SECTION lpCriticalSection);

#include "thread_sched.h"

typedef DWORD native_tls_key_t; // TLS index

static inline void *
native_tls_get(native_tls_key_t key)
{
    // return value should be checked by caller.
    return TlsGetValue(key);
}

static inline void
native_tls_set(native_tls_key_t key, void *ptr)
{
    if (UNLIKELY(TlsSetValue(key, ptr) == 0)) {
        rb_bug("TlsSetValue() error");
    }
}

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN native_tls_key_t ruby_current_ec_key;
RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_THREAD_WIN32_H */
