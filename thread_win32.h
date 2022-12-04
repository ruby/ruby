#ifndef RUBY_THREAD_WIN32_H
#define RUBY_THREAD_WIN32_H
/**********************************************************************

  thread_win32.h -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

/* interface */

# ifdef __CYGWIN__
# undef _WIN32
# endif

#define USE_VM_CLOCK 1

WINBASEAPI BOOL WINAPI
TryEnterCriticalSection(IN OUT LPCRITICAL_SECTION lpCriticalSection);

struct rb_thread_cond_struct {
    struct cond_event_entry *next;
    struct cond_event_entry *prev;
};

struct rb_native_thread {
    HANDLE thread_id;
    HANDLE interrupt_event;
};

struct rb_thread_sched_item {
    char dmy;
};

struct rb_thread_sched {
    HANDLE lock;
};

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
