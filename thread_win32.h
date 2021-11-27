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

typedef struct native_thread_data_struct {
    HANDLE interrupt_event;
} native_thread_data_t;

typedef struct rb_global_vm_lock_struct {
    HANDLE lock;
} rb_global_vm_lock_t;

typedef DWORD native_tls_key_t; // TLS index

static inline void *
native_tls_get(native_tls_key_t key)
{
    void *ptr = TlsGetValue(key);
    if (UNLIKELY(ptr == NULL)) {
        rb_bug("TlsGetValue() returns NULL");
    }
    return ptr;
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
