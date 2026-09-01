/* -*-c-*- */
/**********************************************************************

  thread_win32.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

  Windows platform primitives for the common thread/ractor scheduler.  The
  scheduler itself is in thread_sched.c, which includes this file and then
  builds on the primitives below; see thread_sched.h for the contract.

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include "internal/sanitizers.h"
#include <process.h>

#undef Sleep

#define native_thread_yield() Sleep(0)

// A CRITICAL_SECTION is recursive, so trylock cannot tell "held by me" from
// "free"; see thread_sched.c.
#define RB_NATIVE_MUTEX_TRYLOCK_DETECTS_SELF 0

// M:N threads need an event backend to park a coroutine on (epoll/kqueue on
// the POSIX side; IOCP would be the Windows counterpart).  Until there is one
// every thread here is dedicated, and this file supplies the stubs that
// thread_sched_mn.c provides elsewhere.
#define USE_MN_THREADS 0

// Interruption is delivered through a per-native-thread event object rather
// than a signal, but the bookkeeping is the same as everywhere else.
#define USE_UBF_LIST 1

#include COROUTINE_H

// Thread event hooks are not implemented on this platform.
#define RB_INTERNAL_THREAD_HOOK(event, th) ((void)0)

// No fork(), so this never advances; it only keeps TIMER_THREAD_CREATED_P()
// spelled the same way on both platforms.
static rb_serial_t current_fork_gen = 1;

// Always: native_cond_timedwait() below takes the rb_hrtime_t deadline and
// converts it to the relative timeout the Win32 wait wants itself.
#define RB_NATIVE_COND_HRTIME_DEADLINE_P() 1

static volatile DWORD ruby_native_thread_key = TLS_OUT_OF_INDEXES;

static int w32_wait_events(HANDLE *events, int count, DWORD timeout, rb_thread_t *th);
static void native_thread_destroy(struct rb_native_thread *nt);
static void timer_thread_wakeup_force(void);
static void ubf_select(void *ptr); // thread_sched.c

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

bool
rb_thread_event_hooks_registered_p(void)
{
    return false; // hooks are not implemented on this platform
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

static void
w32_close_handle(HANDLE handle)
{
    if (CloseHandle(handle) == 0) {
        w32_error("w32_close_handle");
    }
}

/* -------------------------------------------------------------------------
 * native mutex / condition variable
 * ------------------------------------------------------------------------- */

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

void
rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec)
{
    native_cond_timedwait_ms(cond, mutex, msec);
}

// The scheduler parks threads with an absolute deadline; on this platform the
// wait itself is relative, so the conversion happens here.
static rb_hrtime_t
native_cond_timeout(rb_nativethread_cond_t *cond, const rb_hrtime_t rel)
{
    if (rel > 0) {
        rb_hrtime_t now = rb_hrtime_now();
        return (rel > RB_HRTIME_MAX - now) ? RB_HRTIME_MAX : now + rel;
    }
    return rb_hrtime_now();
}

static int
native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, const rb_hrtime_t *abs)
{
    rb_hrtime_t now = rb_hrtime_now();

    if (*abs <= now) return ETIMEDOUT;

    rb_hrtime_t rel = *abs - now;
    unsigned long msec = (unsigned long)(rel / RB_HRTIME_PER_MSEC);

    // do not busy loop on a sub-millisecond deadline
    if (msec == 0) msec = 1;

    return native_cond_timedwait_ms(cond, mutex, msec);
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

/* -------------------------------------------------------------------------
 * thread local storage
 * ------------------------------------------------------------------------- */

rb_thread_t *
ruby_thread_from_native(void)
{
    return TlsGetValue(ruby_native_thread_key);
}

int
ruby_thread_set_native(rb_thread_t *th)
{
    if (th) {
        ccan_list_node_init(&th->sched.node.ubf);
    }

    if (th && th->ec) {
        rb_ractor_set_current_ec(th->ractor, th->ec);
    }
    return TlsSetValue(ruby_native_thread_key, th);
}

/* -------------------------------------------------------------------------
 * waiting on Windows objects, with interruption
 * ------------------------------------------------------------------------- */

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
                    ubf_select, ruby_thread_from_native(), FALSE);
    return ret;
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
                    ubf_select, ruby_thread_from_native(), FALSE);
    return ret;
}

/* @internal */
int
rb_w32_check_interrupt(rb_thread_t *th)
{
    return w32_wait_events(0, 0, 0, th);
}

/*
 * Pull the target thread out of a blocking w32_wait_events().  This is the
 * counterpart of the SIGVTALRM the POSIX implementation sends.
 */
static void
native_thread_interrupt(rb_thread_t *th)
{
    // the caller (ubf_wakeup_thread) logs this
    if (!SetEvent(th->nt->interrupt_event)) {
        w32_error("native_thread_interrupt");
    }
}

/* -------------------------------------------------------------------------
 * native thread
 * ------------------------------------------------------------------------- */

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

static void
native_thread_join(HANDLE th)
{
    w32_wait_events(&th, 1, INFINITE, 0);
}

#if !defined(_WIN32_WINNT_WIN8) || _WIN32_WINNT < 0x602
/* declared in processthreadsapi.h only when _WIN32_WINNT >= 0x0602,
 * but exported from kernel32.dll since Windows 8 */
WINBASEAPI VOID WINAPI GetCurrentThreadStackLimits(PULONG_PTR, PULONG_PTR);
#endif

static void
native_thread_init_stack(rb_thread_t *th, void *local_in_parent_frame)
{
    ULONG_PTR low, high;
    SIZE_T size, space;

    /* VirtualQuery against the current stack pointer may return a region
     * that does not span the whole stack when the interpreter is
     * initialized deep in the stack, which makes stack_check() misfire.
     * [Bug #11438] */
    GetCurrentThreadStackLimits(&low, &high);
    size = high - low;
    space = size / 5;
    if (space > 1024*1024) space = 1024*1024;
    th->ec->machine.stack_start = (VALUE *)high - 1;
    th->ec->machine.stack_maxsize = size - space;
}

static void
native_thread_setup(struct rb_native_thread *nt)
{
    rb_native_cond_initialize(&nt->readyq);
    rb_native_mutex_initialize(&nt->running_th_lock);

    // Created here rather than on the new thread itself: ubf can fire before
    // that thread gets a chance to run.
    nt->interrupt_event = CreateEvent(0, TRUE, FALSE, 0);
    if (nt->interrupt_event == NULL) {
        w32_error("native_thread_setup");
    }
}

static void
native_thread_setup_on_thread(struct rb_native_thread *nt)
{
    // nothing to do: there is no altstack and no thread id to cache
}

static struct rb_native_thread *
native_thread_alloc(void)
{
    struct rb_native_thread *nt = ZALLOC(struct rb_native_thread);
    native_thread_setup(nt);

#if USE_RUBY_DEBUG_LOG
    static rb_atomic_t nt_serial = 2;
    nt->serial = RUBY_ATOMIC_FETCH_ADD(nt_serial, 1);
#endif
    return nt;
}

static void
native_thread_destroy_atfork(struct rb_native_thread *nt)
{
    /* no fork() on this platform */
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
        if (intr) w32_close_handle(intr);

        rb_native_cond_destroy(&nt->readyq);
        rb_native_mutex_destroy(&nt->running_th_lock);

        ruby_xfree(nt);
    }
}

static void
native_thread_destroy_self(struct rb_native_thread *nt)
{
    native_thread_destroy(nt);
}

static unsigned long __stdcall
nt_start_trampoline(void *nt_ptr)
{
    struct rb_native_thread *nt = (struct rb_native_thread *)nt_ptr;
    HANDLE thread_id = nt->thread_id;

    nt_start(nt);

    w32_close_handle(thread_id);
    return 0;
}

static int
native_thread_create0(struct rb_native_thread *nt)
{
    const size_t stack_size = nt->vm->default_params.thread_machine_stack_size;

    nt->thread_id = w32_create_thread(stack_size, nt_start_trampoline, nt);
    if (nt->thread_id == 0) {
        return thread_errno;
    }

    w32_resume_thread(nt->thread_id);

    RUBY_DEBUG_LOG("nt:%u thid:%p stack size:%"PRIuSIZE"",
                   nt->serial, nt->thread_id, stack_size);
    return 0;
}

static int
native_thread_default_max_cpu(void)
{
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwNumberOfProcessors > 0 ? (int)si.dwNumberOfProcessors : 8;
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

int rb_w32_set_thread_description(HANDLE th, const WCHAR *name);
int rb_w32_set_thread_description_str(HANDLE th, VALUE name);
#define native_set_another_thread_name rb_w32_set_thread_description_str

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
Init_native_thread(rb_thread_t *main_th)
{
    if ((ruby_current_ec_key = TlsAlloc()) == TLS_OUT_OF_INDEXES) {
        rb_bug("TlsAlloc() for ruby_current_ec_key fails");
    }
    if ((ruby_native_thread_key = TlsAlloc()) == TLS_OUT_OF_INDEXES) {
        rb_bug("TlsAlloc() for ruby_native_thread_key fails");
    }

    // setup vm
    rb_vm_t *vm = main_th->vm;
    thread_sched_init_vm(vm);

    // setup main thread
    native_thread_setup(main_th->nt);
    DuplicateHandle(GetCurrentProcess(),
                    GetCurrentThread(),
                    GetCurrentProcess(),
                    &main_th->nt->thread_id, 0, FALSE, DUPLICATE_SAME_ACCESS);
    main_th->nt->serial = 1;
    ruby_thread_set_native(main_th);

    TH_SCHED(main_th)->running = main_th;
    main_th->has_dedicated_nt = 1;

    // setup main NT (before the record below: its kind decides where it goes)
    main_th->nt->dedicated = 1;
    main_th->nt->running_thread = main_th;
    main_th->nt->vm = vm;

    thread_sched_setup_running_threads(TH_SCHED(main_th), main_th->ractor, vm, main_th, NULL);

#if USE_RUBY_DEBUG_LOG
    vm->ractor.sched.dnt_cnt = 1;
#endif

    RUBY_DEBUG_LOG("initial thread th:%u thid:%p, event: %p",
                   rb_th_serial(main_th),
                   main_th->nt->thread_id,
                   main_th->nt->interrupt_event);
}

/* -------------------------------------------------------------------------
 * timer thread
 * ------------------------------------------------------------------------- */

static struct {
    rb_serial_t created_fork_gen;
    HANDLE thread_id;
    HANDLE wakeup_event; // manual reset; the "comm pipe" of this platform
} timer_th = {
    .created_fork_gen = 0,
};

#define TIMER_THREAD_CREATED_P() (timer_th.created_fork_gen == current_fork_gen)

static void
timer_thread_wakeup_force(void)
{
    if (timer_th.wakeup_event) {
        SetEvent(timer_th.wakeup_event);
    }
}

void
rb_thread_wakeup_timer_thread(int sig)
{
    timer_thread_wakeup_force();

    if (RUBY_ATOMIC_LOAD(system_working)) {
        rb_vm_t *vm = GET_VM();
        rb_thread_t *main_th = vm->ractor.main_thread;

        if (main_th) {
            volatile rb_execution_context_t *main_th_ec = ACCESS_ONCE(rb_execution_context_t *, main_th->ec);

            if (main_th_ec) {
                RUBY_VM_SET_TRAP_INTERRUPT(main_th_ec);

                if (vm->ubf_async_safe && main_th->unblock.func) {
                    (main_th->unblock.func)(main_th->unblock.arg);
                }
            }
        }
    }
}

// The blocking part of the timer thread loop: this is what
// timer_thread_wakeup_force() interrupts.
static void
timer_thread_polling(rb_vm_t *vm)
{
    int timeout = timer_thread_set_timeout(vm);
    DWORD msec = (timeout < 0) ? INFINITE : (DWORD)timeout;

    DWORD ret = WaitForSingleObject(timer_th.wakeup_event, msec);

    switch (ret) {
      case WAIT_TIMEOUT:
        ractor_sched_lock(vm, NULL);
        {
            timer_thread_check_timeslice(vm);
        }
        ractor_sched_unlock(vm, NULL);
        break;

      case WAIT_OBJECT_0:
        ResetEvent(timer_th.wakeup_event);
        break;

      default:
        w32_error("timer_thread_polling");
    }
}

static unsigned long __stdcall
timer_thread_trampoline(void *vm_ptr)
{
    rb_w32_set_thread_description(GetCurrentThread(), L"ruby-timer-thread");
    timer_thread_func(vm_ptr);
    return 0;
}

static void
rb_thread_create_timer_thread(void)
{
    timer_th.created_fork_gen = current_fork_gen;

    if (timer_th.wakeup_event == NULL) {
        timer_th.wakeup_event = CreateEvent(0, TRUE, FALSE, 0);
        if (timer_th.wakeup_event == NULL) {
            w32_error("rb_thread_create_timer_thread");
        }
    }

    timer_th.thread_id = w32_create_thread(1024 + (USE_RUBY_DEBUG_LOG ? BUFSIZ : 0),
                                           timer_thread_trampoline, GET_VM());
    if (timer_th.thread_id == 0) {
        rb_bug("rb_thread_create_timer_thread: failed to create the timer thread");
    }
    w32_resume_thread(timer_th.thread_id);
}

static int
native_stop_timer_thread(void)
{
    RUBY_ATOMIC_SET(system_working, 0);

    timer_thread_wakeup_force();
    native_thread_join(timer_th.thread_id);

    w32_close_handle(timer_th.wakeup_event);
    timer_th.wakeup_event = NULL;

    return 1;
}

static void
native_reset_timer_thread(void)
{
    if (timer_th.thread_id) {
        CloseHandle(timer_th.thread_id);
        timer_th.thread_id = 0;
    }
}

/* -------------------------------------------------------------------------
 * M:N scheduler stubs
 *
 * These are what thread_sched_mn.c provides on platforms that have an event
 * backend.  Every thread here is dedicated, so the scheduler never reaches
 * the ones that rb_bug().
 * ------------------------------------------------------------------------- */

static int
native_thread_create_shared(rb_thread_t *th)
{
    rb_bug("unreachable");
}

static enum thread_sched_wait_result
thread_sched_wait_events(struct rb_thread_sched *sched, rb_thread_t *th, int fd,
                         enum thread_sched_waiting_flag events, rb_hrtime_t *rel)
{
    return thread_sched_wait_unavailable;
}

static bool
ractor_sched_timeout_arm(rb_thread_t *th, const rb_hrtime_t *rel)
{
    rb_bug("unreachable");
}

static bool
ractor_sched_timeout_disarm(rb_thread_t *th)
{
    rb_bug("unreachable");
}

static int
timer_wheel_timeout(int timeout)
{
    return timeout; // no M:N threads, no timed waiters
}

static void
timer_thread_wake_fence(rb_thread_t *th)
{
    // no timer wheel, no wake batches
}

static void
timer_thread_check_timeout(rb_vm_t *vm)
{
    // no M:N threads, no timed waiters
}

/* -------------------------------------------------------------------------
 * misc
 * ------------------------------------------------------------------------- */

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

void *
rb_thread_prevent_fork(void *(*func)(void *), void *data)
{
    return func(data);
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
