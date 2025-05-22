/* -*-c-*- */
/**********************************************************************

  thread_win32.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include "internal/sanitizers.h"
#include <process.h>

#define TIME_QUANTUM_USEC (10 * 1000)
#define RB_CONDATTR_CLOCK_MONOTONIC 1 /* no effect */

#undef Sleep

#define native_thread_yield() Sleep(0)
#define unregister_ubf_list(th)
#define ubf_wakeup_all_threads() do {} while (0)
#define ubf_threads_empty() (1)
#define ubf_timer_disarm() do {} while (0)
#define ubf_list_atfork() do {} while (0)

static volatile DWORD ruby_native_thread_key = TLS_OUT_OF_INDEXES;

static int w32_wait_events(HANDLE *events, int count, DWORD timeout, rb_thread_t *th);

rb_internal_thread_event_hook_t *
rb_internal_thread_add_event_hook(rb_internal_thread_event_callback callback, rb_event_flag_t internal_event, void *user_data)
{
    // not implemented
    return NULL;
}

bool
rb_internal_thread_remove_event_hook(rb_internal_thread_event_hook_t * hook)
{
    // not implemented
    return false;
}

RBIMPL_ATTR_NORETURN()
static void
w32_error(const char *func)
{
    LPVOID lpMsgBuf;
    DWORD err = GetLastError();
    if (FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                      FORMAT_MESSAGE_FROM_SYSTEM |
                      FORMAT_MESSAGE_IGNORE_INSERTS,
                      NULL,
                      err,
                      MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
                      (LPTSTR) & lpMsgBuf, 0, NULL) == 0)
        FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                      FORMAT_MESSAGE_FROM_SYSTEM |
                      FORMAT_MESSAGE_IGNORE_INSERTS,
                      NULL,
                      err,
                      MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                      (LPTSTR) & lpMsgBuf, 0, NULL);
    rb_bug("%s: %s", func, (char*)lpMsgBuf);
    UNREACHABLE;
}

#define W32_EVENT_DEBUG 0

#if W32_EVENT_DEBUG
#define w32_event_debug printf
#else
#define w32_event_debug if (0) printf
#endif

static int
w32_mutex_lock(HANDLE lock, bool try)
{
    DWORD result;
    while (1) {
        // RUBY_DEBUG_LOG() is not available because RUBY_DEBUG_LOG() calls it.
        w32_event_debug("lock:%p\n", lock);

        result = w32_wait_events(&lock, 1, try ? 0 : INFINITE, 0);
        switch (result) {
          case WAIT_OBJECT_0:
            /* get mutex object */
            w32_event_debug("locked lock:%p\n", lock);
            return 0;

          case WAIT_OBJECT_0 + 1:
            /* interrupt */
            errno = EINTR;
            w32_event_debug("interrupted lock:%p\n", lock);
            return 0;

          case WAIT_TIMEOUT:
            w32_event_debug("timeout locK:%p\n", lock);
            return EBUSY;

          case WAIT_ABANDONED:
            rb_bug("win32_mutex_lock: WAIT_ABANDONED");
            break;

          default:
            rb_bug("win32_mutex_lock: unknown result (%ld)", result);
            break;
        }
    }
    return 0;
}

static HANDLE
w32_mutex_create(void)
{
    HANDLE lock = CreateMutex(NULL, FALSE, NULL);
    if (lock == NULL) {
        w32_error("rb_native_mutex_initialize");
    }
    return lock;
}

#define GVL_DEBUG 0

static void
thread_sched_to_running(struct rb_thread_sched *sched, rb_thread_t *th)
{
    w32_mutex_lock(sched->lock, false);
    if (GVL_DEBUG) fprintf(stderr, "gvl acquire (%p): acquire\n", th);
}

#define thread_sched_to_dead thread_sched_to_waiting

static void
thread_sched_to_waiting(struct rb_thread_sched *sched, rb_thread_t *th)
{
    ReleaseMutex(sched->lock);
}

static void
thread_sched_yield(struct rb_thread_sched *sched, rb_thread_t *th)
{
    thread_sched_to_waiting(sched, th);
    native_thread_yield();
    thread_sched_to_running(sched, th);
}

void
rb_thread_sched_init(struct rb_thread_sched *sched, bool atfork)
{
    if (GVL_DEBUG) fprintf(stderr, "sched init\n");
    sched->lock = w32_mutex_create();
}

#if 0
// per-ractor
void
rb_thread_sched_destroy(struct rb_thread_sched *sched)
{
    if (GVL_DEBUG) fprintf(stderr, "sched destroy\n");
    CloseHandle(sched->lock);
}
#endif

rb_thread_t *
ruby_thread_from_native(void)
{
    return TlsGetValue(ruby_native_thread_key);
}

int
ruby_thread_set_native(rb_thread_t *th)
{
    if (th && th->ec) {
        rb_ractor_set_current_ec(th->ractor, th->ec);
    }
    return TlsSetValue(ruby_native_thread_key, th);
}

void
Init_native_thread(rb_thread_t *main_th)
{
    if ((ruby_current_ec_key = TlsAlloc()) == TLS_OUT_OF_INDEXES) {
        rb_bug("TlsAlloc() for ruby_current_ec_key fails");
    }
    if ((ruby_native_thread_key = TlsAlloc()) == TLS_OUT_OF_INDEXES) {
        rb_bug("TlsAlloc() for ruby_native_thread_key fails");
    }

    // setup main thread

    ruby_thread_set_native(main_th);
    main_th->nt->interrupt_event = CreateEvent(0, TRUE, FALSE, 0);

    DuplicateHandle(GetCurrentProcess(),
                    GetCurrentThread(),
                    GetCurrentProcess(),
                    &main_th->nt->thread_id, 0, FALSE, DUPLICATE_SAME_ACCESS);

    RUBY_DEBUG_LOG("initial thread th:%u thid:%p, event: %p",
                   rb_th_serial(main_th),
                   main_th->nt->thread_id,
                   main_th->nt->interrupt_event);
}

void
ruby_mn_threads_params(void)
{
}

static int
w32_wait_events(HANDLE *events, int count, DWORD timeout, rb_thread_t *th)
{
    HANDLE *targets = events;
    HANDLE intr;
    const int initcount = count;
    DWORD ret;

    w32_event_debug("events:%p, count:%d, timeout:%ld, th:%u\n",
                    events, count, timeout, th ? rb_th_serial(th) : UINT_MAX);

    if (th && (intr = th->nt->interrupt_event)) {
        if (ResetEvent(intr) && (!RUBY_VM_INTERRUPTED(th->ec) || SetEvent(intr))) {
            targets = ALLOCA_N(HANDLE, count + 1);
            memcpy(targets, events, sizeof(HANDLE) * count);

            targets[count++] = intr;
            w32_event_debug("handle:%p (count:%d, intr)\n", intr, count);
        }
        else if (intr == th->nt->interrupt_event) {
            w32_error("w32_wait_events");
        }
    }

    w32_event_debug("WaitForMultipleObjects start count:%d\n", count);
    ret = WaitForMultipleObjects(count, targets, FALSE, timeout);
    w32_event_debug("WaitForMultipleObjects end ret:%lu\n", ret);

    if (ret == (DWORD)(WAIT_OBJECT_0 + initcount) && th) {
        errno = EINTR;
    }
    if (ret == WAIT_FAILED && W32_EVENT_DEBUG) {
        int i;
        DWORD dmy;
        for (i = 0; i < count; i++) {
            w32_event_debug("i:%d %s\n", i, GetHandleInformation(targets[i], &dmy) ? "OK" : "NG");
        }
    }
    return ret;
}

static void ubf_handle(void *ptr);
#define ubf_select ubf_handle

int
rb_w32_wait_events_blocking(HANDLE *events, int num, DWORD timeout)
{
    return w32_wait_events(events, num, timeout, ruby_thread_from_native());
}

int
rb_w32_wait_events(HANDLE *events, int num, DWORD timeout)
{
    int ret;
    rb_thread_t *th = GET_THREAD();

    BLOCKING_REGION(th, ret = rb_w32_wait_events_blocking(events, num, timeout),
                    ubf_handle, ruby_thread_from_native(), FALSE);
    return ret;
}

static void
w32_close_handle(HANDLE handle)
{
    if (CloseHandle(handle) == 0) {
        w32_error("w32_close_handle");
    }
}

static void
w32_resume_thread(HANDLE handle)
{
    if (ResumeThread(handle) == (DWORD)-1) {
        w32_error("w32_resume_thread");
    }
}

#ifdef _MSC_VER
#define HAVE__BEGINTHREADEX 1
#else
#undef HAVE__BEGINTHREADEX
#endif

#ifdef HAVE__BEGINTHREADEX
#define start_thread (HANDLE)_beginthreadex
#define thread_errno errno
typedef unsigned long (__stdcall *w32_thread_start_func)(void*);
#else
#define start_thread CreateThread
#define thread_errno rb_w32_map_errno(GetLastError())
typedef LPTHREAD_START_ROUTINE w32_thread_start_func;
#endif

static HANDLE
w32_create_thread(DWORD stack_size, w32_thread_start_func func, void *val)
{
    return start_thread(0, stack_size, func, val, CREATE_SUSPENDED | STACK_SIZE_PARAM_IS_A_RESERVATION, 0);
}

int
rb_w32_sleep(unsigned long msec)
{
    return w32_wait_events(0, 0, msec, ruby_thread_from_native());
}

int WINAPI
rb_w32_Sleep(unsigned long msec)
{
    int ret;
    rb_thread_t *th = GET_THREAD();

    BLOCKING_REGION(th, ret = rb_w32_sleep(msec),
                    ubf_handle, ruby_thread_from_native(), FALSE);
    return ret;
}

static DWORD
hrtime2msec(rb_hrtime_t hrt)
{
    return (DWORD)hrt / (DWORD)RB_HRTIME_PER_MSEC;
}

static void
native_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    const volatile DWORD msec = rel ? hrtime2msec(*rel) : INFINITE;

    THREAD_BLOCKING_BEGIN(th);
    {
        DWORD ret;

        rb_native_mutex_lock(&th->interrupt_lock);
        th->unblock.func = ubf_handle;
        th->unblock.arg = th;
        rb_native_mutex_unlock(&th->interrupt_lock);

        if (RUBY_VM_INTERRUPTED(th->ec)) {
            /* interrupted.  return immediate */
        }
        else {
            RUBY_DEBUG_LOG("start msec:%lu", msec);
            ret = w32_wait_events(0, 0, msec, th);
            RUBY_DEBUG_LOG("done ret:%lu", ret);
            (void)ret;
        }

        rb_native_mutex_lock(&th->interrupt_lock);
        th->unblock.func = 0;
        th->unblock.arg = 0;
        rb_native_mutex_unlock(&th->interrupt_lock);
    }
    THREAD_BLOCKING_END(th);
}

void
rb_native_mutex_lock(rb_nativethread_lock_t *lock)
{
#ifdef USE_WIN32_MUTEX
    w32_mutex_lock(lock->mutex, false);
#else
    EnterCriticalSection(&lock->crit);
#endif
}

int
rb_native_mutex_trylock(rb_nativethread_lock_t *lock)
{
#ifdef USE_WIN32_MUTEX
    return w32_mutex_lock(lock->mutex, true);
#else
    return TryEnterCriticalSection(&lock->crit) == 0 ? EBUSY : 0;
#endif
}

void
rb_native_mutex_unlock(rb_nativethread_lock_t *lock)
{
#ifdef USE_WIN32_MUTEX
    RUBY_DEBUG_LOG("lock:%p", lock->mutex);
    ReleaseMutex(lock->mutex);
#else
    LeaveCriticalSection(&lock->crit);
#endif
}

void
rb_native_mutex_initialize(rb_nativethread_lock_t *lock)
{
#ifdef USE_WIN32_MUTEX
    lock->mutex = w32_mutex_create();
    /* thread_debug("initialize mutex: %p\n", lock->mutex); */
#else
    InitializeCriticalSection(&lock->crit);
#endif
}

void
rb_native_mutex_destroy(rb_nativethread_lock_t *lock)
{
#ifdef USE_WIN32_MUTEX
    w32_close_handle(lock->mutex);
#else
    DeleteCriticalSection(&lock->crit);
#endif
}

struct cond_event_entry {
    struct cond_event_entry* next;
    struct cond_event_entry* prev;
    HANDLE event;
};

void
rb_native_cond_signal(rb_nativethread_cond_t *cond)
{
    /* cond is guarded by mutex */
    struct cond_event_entry *e = cond->next;
    struct cond_event_entry *head = (struct cond_event_entry*)cond;

    if (e != head) {
        struct cond_event_entry *next = e->next;
        struct cond_event_entry *prev = e->prev;

        prev->next = next;
        next->prev = prev;
        e->next = e->prev = e;

        SetEvent(e->event);
    }
}

void
rb_native_cond_broadcast(rb_nativethread_cond_t *cond)
{
    /* cond is guarded by mutex */
    struct cond_event_entry *e = cond->next;
    struct cond_event_entry *head = (struct cond_event_entry*)cond;

    while (e != head) {
        struct cond_event_entry *next = e->next;
        struct cond_event_entry *prev = e->prev;

        SetEvent(e->event);

        prev->next = next;
        next->prev = prev;
        e->next = e->prev = e;

        e = next;
    }
}

static int
native_cond_timedwait_ms(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec)
{
    DWORD r;
    struct cond_event_entry entry;
    struct cond_event_entry *head = (struct cond_event_entry*)cond;

    entry.event = CreateEvent(0, FALSE, FALSE, 0);

    /* cond is guarded by mutex */
    entry.next = head;
    entry.prev = head->prev;
    head->prev->next = &entry;
    head->prev = &entry;

    rb_native_mutex_unlock(mutex);
    {
        r = WaitForSingleObject(entry.event, msec);
        if ((r != WAIT_OBJECT_0) && (r != WAIT_TIMEOUT)) {
            rb_bug("rb_native_cond_wait: WaitForSingleObject returns %lu", r);
        }
    }
    rb_native_mutex_lock(mutex);

    entry.prev->next = entry.next;
    entry.next->prev = entry.prev;

    w32_close_handle(entry.event);
    return (r == WAIT_OBJECT_0) ? 0 : ETIMEDOUT;
}

void
rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex)
{
    native_cond_timedwait_ms(cond, mutex, INFINITE);
}

static unsigned long
abs_timespec_to_timeout_ms(const struct timespec *ts)
{
    struct timeval tv;
    struct timeval now;

    gettimeofday(&now, NULL);
    tv.tv_sec = ts->tv_sec;
    tv.tv_usec = ts->tv_nsec / 1000;

    if (!rb_w32_time_subtract(&tv, &now))
        return 0;

    return (tv.tv_sec * 1000) + (tv.tv_usec / 1000);
}

static int
native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, const struct timespec *ts)
{
    unsigned long timeout_ms;

    timeout_ms = abs_timespec_to_timeout_ms(ts);
    if (!timeout_ms)
        return ETIMEDOUT;

    return native_cond_timedwait_ms(cond, mutex, timeout_ms);
}

static struct timespec native_cond_timeout(rb_nativethread_cond_t *cond, struct timespec timeout_rel);

void
rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec)
{
    struct timespec rel = {
        .tv_sec = msec / 1000,
        .tv_nsec = (msec % 1000) * 1000 * 1000,
    };
    struct timespec ts = native_cond_timeout(cond, rel);
    native_cond_timedwait(cond, mutex, &ts);
}

static struct timespec
native_cond_timeout(rb_nativethread_cond_t *cond, struct timespec timeout_rel)
{
    int ret;
    struct timeval tv;
    struct timespec timeout;
    struct timespec now;

    ret = gettimeofday(&tv, 0);
    if (ret != 0)
        rb_sys_fail(0);
    now.tv_sec = tv.tv_sec;
    now.tv_nsec = tv.tv_usec * 1000;

    timeout.tv_sec = now.tv_sec;
    timeout.tv_nsec = now.tv_nsec;
    timeout.tv_sec += timeout_rel.tv_sec;
    timeout.tv_nsec += timeout_rel.tv_nsec;

    if (timeout.tv_nsec >= 1000*1000*1000) {
        timeout.tv_sec++;
        timeout.tv_nsec -= 1000*1000*1000;
    }

    if (timeout.tv_sec < now.tv_sec)
        timeout.tv_sec = TIMET_MAX;

    return timeout;
}

void
rb_native_cond_initialize(rb_nativethread_cond_t *cond)
{
    cond->next = (struct cond_event_entry *)cond;
    cond->prev = (struct cond_event_entry *)cond;
}

void
rb_native_cond_destroy(rb_nativethread_cond_t *cond)
{
    /* */
}


#define CHECK_ERR(expr) \
    {if (!(expr)) {rb_bug("err: %lu - %s", GetLastError(), #expr);}}

COMPILER_WARNING_PUSH
#if __has_warning("-Wmaybe-uninitialized")
COMPILER_WARNING_IGNORED(-Wmaybe-uninitialized)
#endif
static inline SIZE_T
query_memory_basic_info(PMEMORY_BASIC_INFORMATION mi, void *local_in_parent_frame)
{
    return VirtualQuery(asan_get_real_stack_addr(local_in_parent_frame), mi, sizeof(*mi));
}
COMPILER_WARNING_POP

static void
native_thread_init_stack(rb_thread_t *th, void *local_in_parent_frame)
{
    MEMORY_BASIC_INFORMATION mi;
    char *base, *end;
    DWORD size, space;

    CHECK_ERR(query_memory_basic_info(&mi, local_in_parent_frame));
    base = mi.AllocationBase;
    end = mi.BaseAddress;
    end += mi.RegionSize;
    size = end - base;
    space = size / 5;
    if (space > 1024*1024) space = 1024*1024;
    th->ec->machine.stack_start = (VALUE *)end - 1;
    th->ec->machine.stack_maxsize = size - space;
}

#ifndef InterlockedExchangePointer
#define InterlockedExchangePointer(t, v) \
    (void *)InterlockedExchange((long *)(t), (long)(v))
#endif
static void
native_thread_destroy(struct rb_native_thread *nt)
{
    if (nt) {
        HANDLE intr = InterlockedExchangePointer(&nt->interrupt_event, 0);
        RUBY_DEBUG_LOG("close handle intr:%p, thid:%p\n", intr, nt->thread_id);
        w32_close_handle(intr);
    }
}

static unsigned long __stdcall
thread_start_func_1(void *th_ptr)
{
    rb_thread_t *th = th_ptr;
    volatile HANDLE thread_id = th->nt->thread_id;

    native_thread_init_stack(th, &th);
    th->nt->interrupt_event = CreateEvent(0, TRUE, FALSE, 0);

    /* run */
    RUBY_DEBUG_LOG("thread created th:%u, thid: %p, event: %p",
                   rb_th_serial(th), th->nt->thread_id, th->nt->interrupt_event);

    thread_sched_to_running(TH_SCHED(th), th);
    ruby_thread_set_native(th);

    // kick threads
    thread_start_func_2(th, th->ec->machine.stack_start);

    w32_close_handle(thread_id);
    RUBY_DEBUG_LOG("thread deleted th:%u", rb_th_serial(th));

    return 0;
}

static int
native_thread_create(rb_thread_t *th)
{
    // setup nt
    const size_t stack_size = th->vm->default_params.thread_machine_stack_size;
    th->nt = ZALLOC(struct rb_native_thread);
    th->nt->thread_id = w32_create_thread(stack_size, thread_start_func_1, th);

    // setup vm stack
    size_t vm_stack_word_size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
    void *vm_stack = ruby_xmalloc(vm_stack_word_size * sizeof(VALUE));
    th->sched.vm_stack = vm_stack;
    rb_ec_initialize_vm_stack(th->ec, vm_stack, vm_stack_word_size);

    if ((th->nt->thread_id) == 0) {
        return thread_errno;
    }

    w32_resume_thread(th->nt->thread_id);

    if (USE_RUBY_DEBUG_LOG) {
        Sleep(0);
        RUBY_DEBUG_LOG("th:%u thid:%p intr:%p), stack size: %"PRIuSIZE"",
                       rb_th_serial(th), th->nt->thread_id,
                       th->nt->interrupt_event, stack_size);
    }
    return 0;
}

static void
native_thread_join(HANDLE th)
{
    w32_wait_events(&th, 1, INFINITE, 0);
}

#if USE_NATIVE_THREAD_PRIORITY

static void
native_thread_apply_priority(rb_thread_t *th)
{
    int priority = th->priority;
    if (th->priority > 0) {
        priority = THREAD_PRIORITY_ABOVE_NORMAL;
    }
    else if (th->priority < 0) {
        priority = THREAD_PRIORITY_BELOW_NORMAL;
    }
    else {
        priority = THREAD_PRIORITY_NORMAL;
    }

    SetThreadPriority(th->nt->thread_id, priority);
}

#endif /* USE_NATIVE_THREAD_PRIORITY */

int rb_w32_select_with_thread(int, fd_set *, fd_set *, fd_set *, struct timeval *, void *);	/* @internal */

static int
native_fd_select(int n, rb_fdset_t *readfds, rb_fdset_t *writefds, rb_fdset_t *exceptfds, struct timeval *timeout, rb_thread_t *th)
{
    fd_set *r = NULL, *w = NULL, *e = NULL;
    if (readfds) {
        rb_fd_resize(n - 1, readfds);
        r = rb_fd_ptr(readfds);
    }
    if (writefds) {
        rb_fd_resize(n - 1, writefds);
        w = rb_fd_ptr(writefds);
    }
    if (exceptfds) {
        rb_fd_resize(n - 1, exceptfds);
        e = rb_fd_ptr(exceptfds);
    }
    return rb_w32_select_with_thread(n, r, w, e, timeout, th);
}

/* @internal */
int
rb_w32_check_interrupt(rb_thread_t *th)
{
    return w32_wait_events(0, 0, 0, th);
}

static void
ubf_handle(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    RUBY_DEBUG_LOG("th:%u\n", rb_th_serial(th));

    if (!SetEvent(th->nt->interrupt_event)) {
        w32_error("ubf_handle");
    }
}

int rb_w32_set_thread_description(HANDLE th, const WCHAR *name);
int rb_w32_set_thread_description_str(HANDLE th, VALUE name);
#define native_set_another_thread_name rb_w32_set_thread_description_str

static struct {
    HANDLE id;
    HANDLE lock;
} timer_thread;
#define TIMER_THREAD_CREATED_P() (timer_thread.id != 0)

static unsigned long __stdcall
timer_thread_func(void *dummy)
{
    rb_vm_t *vm = GET_VM();
    RUBY_DEBUG_LOG("start");
    rb_w32_set_thread_description(GetCurrentThread(), L"ruby-timer-thread");
    while (WaitForSingleObject(timer_thread.lock,
                               TIME_QUANTUM_USEC/1000) == WAIT_TIMEOUT) {
        vm->clock++;
        rb_threadptr_check_signal(vm->ractor.main_thread);
    }
    RUBY_DEBUG_LOG("end");
    return 0;
}

void
rb_thread_wakeup_timer_thread(int sig)
{
    /* do nothing */
}

static void
rb_thread_create_timer_thread(void)
{
    if (timer_thread.id == 0) {
        if (!timer_thread.lock) {
            timer_thread.lock = CreateEvent(0, TRUE, FALSE, 0);
        }
        timer_thread.id = w32_create_thread(1024 + (USE_RUBY_DEBUG_LOG ? BUFSIZ : 0),
                                            timer_thread_func, 0);
        w32_resume_thread(timer_thread.id);
    }
}

static int
native_stop_timer_thread(void)
{
    RUBY_ATOMIC_SET(system_working, 0);

    SetEvent(timer_thread.lock);
    native_thread_join(timer_thread.id);
    CloseHandle(timer_thread.lock);
    timer_thread.lock = 0;

    return 1;
}

static void
native_reset_timer_thread(void)
{
    if (timer_thread.id) {
        CloseHandle(timer_thread.id);
        timer_thread.id = 0;
    }
}

int
ruby_stack_overflowed_p(const rb_thread_t *th, const void *addr)
{
    return rb_ec_raised_p(th->ec, RAISED_STACKOVERFLOW);
}

#if defined(__MINGW32__)
LONG WINAPI
rb_w32_stack_overflow_handler(struct _EXCEPTION_POINTERS *exception)
{
    if (exception->ExceptionRecord->ExceptionCode == EXCEPTION_STACK_OVERFLOW) {
        rb_ec_raised_set(GET_EC(), RAISED_STACKOVERFLOW);
        raise(SIGSEGV);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
#endif

#ifdef RUBY_ALLOCA_CHKSTK
void
ruby_alloca_chkstk(size_t len, void *sp)
{
    if (ruby_stack_length(NULL) * sizeof(VALUE) >= len) {
        rb_execution_context_t *ec = GET_EC();
        if (!rb_ec_raised_p(ec, RAISED_STACKOVERFLOW)) {
            rb_ec_raised_set(ec, RAISED_STACKOVERFLOW);
            rb_exc_raise(sysstack_error);
        }
    }
}
#endif
int
rb_reserved_fd_p(int fd)
{
    return 0;
}

rb_nativethread_id_t
rb_nativethread_self(void)
{
    return GetCurrentThread();
}

static void
native_set_thread_name(rb_thread_t *th)
{
}

static VALUE
native_thread_native_thread_id(rb_thread_t *th)
{
    DWORD tid = GetThreadId(th->nt->thread_id);
    if (tid == 0) rb_sys_fail("GetThreadId");
    return ULONG2NUM(tid);
}
#define USE_NATIVE_THREAD_NATIVE_THREAD_ID 1

void
rb_add_running_thread(rb_thread_t *th)
{
    // do nothing
}

void
rb_del_running_thread(rb_thread_t *th)
{
    // do nothing
}

static bool
th_has_dedicated_nt(const rb_thread_t *th)
{
    return true;
}

void
rb_threadptr_sched_free(rb_thread_t *th)
{
    native_thread_destroy(th->nt);
    ruby_xfree(th->nt);
    ruby_xfree(th->sched.vm_stack);
}

void
rb_threadptr_remove(rb_thread_t *th)
{
    // do nothing
}

void
rb_thread_sched_mark_zombies(rb_vm_t *vm)
{
    // do nothing
}

static bool
vm_barrier_finish_p(rb_vm_t *vm)
{
    RUBY_DEBUG_LOG("cnt:%u living:%u blocking:%u",
                   vm->ractor.blocking_cnt == vm->ractor.cnt,
                   vm->ractor.sync.barrier_cnt,
                   vm->ractor.cnt,
                   vm->ractor.blocking_cnt);

    VM_ASSERT(vm->ractor.blocking_cnt <= vm->ractor.cnt);
    return vm->ractor.blocking_cnt == vm->ractor.cnt;
}

void
rb_ractor_sched_barrier_start(rb_vm_t *vm, rb_ractor_t *cr)
{
    vm->ractor.sync.barrier_waiting = true;

    RUBY_DEBUG_LOG("barrier start. cnt:%u living:%u blocking:%u",
                   vm->ractor.sync.barrier_cnt,
                   vm->ractor.cnt,
                   vm->ractor.blocking_cnt);

    rb_vm_ractor_blocking_cnt_inc(vm, cr, __FILE__, __LINE__);

    // send signal
    rb_ractor_t *r = 0;
    ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
        if (r != cr) {
            rb_ractor_vm_barrier_interrupt_running_thread(r);
        }
    }

    // wait
    while (!vm_barrier_finish_p(vm)) {
        rb_vm_cond_wait(vm, &vm->ractor.sync.barrier_cond);
    }

    RUBY_DEBUG_LOG("cnt:%u barrier success", vm->ractor.sync.barrier_cnt);

    rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);

    vm->ractor.sync.barrier_waiting = false;
    vm->ractor.sync.barrier_cnt++;

    ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
        rb_native_cond_signal(&r->barrier_wait_cond);
    }
}

void
rb_ractor_sched_barrier_join(rb_vm_t *vm, rb_ractor_t *cr)
{
    vm->ractor.sync.lock_owner = cr;
    unsigned int barrier_cnt = vm->ractor.sync.barrier_cnt;
    rb_thread_t *th = GET_THREAD();
    bool running;

    RB_VM_SAVE_MACHINE_CONTEXT(th);

    if (rb_ractor_status_p(cr, ractor_running)) {
        rb_vm_ractor_blocking_cnt_inc(vm, cr, __FILE__, __LINE__);
        running = true;
    }
    else {
        running = false;
    }
    VM_ASSERT(rb_ractor_status_p(cr, ractor_blocking));

    if (vm_barrier_finish_p(vm)) {
        RUBY_DEBUG_LOG("wakeup barrier owner");
        rb_native_cond_signal(&vm->ractor.sync.barrier_cond);
    }
    else {
        RUBY_DEBUG_LOG("wait for barrier finish");
    }

    // wait for restart
    while (barrier_cnt == vm->ractor.sync.barrier_cnt) {
        vm->ractor.sync.lock_owner = NULL;
        rb_native_cond_wait(&cr->barrier_wait_cond, &vm->ractor.sync.lock);
        VM_ASSERT(vm->ractor.sync.lock_owner == NULL);
        vm->ractor.sync.lock_owner = cr;
    }

    RUBY_DEBUG_LOG("barrier is released. Acquire vm_lock");

    if (running) {
        rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);
    }

        vm->ractor.sync.lock_owner = NULL;
}

bool
rb_thread_lock_native_thread(void)
{
    return false;
}

void *
rb_thread_prevent_fork(void *(*func)(void *), void *data)
{
    return func(data);
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
