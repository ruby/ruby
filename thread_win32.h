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

WINBASEAPI BOOL WINAPI
TryEnterCriticalSection(IN OUT LPCRITICAL_SECTION lpCriticalSection);

typedef struct rb_thread_cond_struct {
    struct cond_event_entry *next;
    struct cond_event_entry *prev;
} rb_nativethread_cond_t;

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

void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);
void rb_native_cond_signal(rb_nativethread_cond_t *cond);
void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);
void rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec);
void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
void rb_native_cond_destroy(rb_nativethread_cond_t *cond);

#endif /* RUBY_THREAD_WIN32_H */
