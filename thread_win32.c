/* -*-c-*- */
/**********************************************************************

  thread_win32.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include <process.h>

#define WIN32_WAIT_TIMEOUT 10	/* 10 ms */
#undef Sleep

#define native_thread_yield() Sleep(0)
#define remove_signal_thread_list(th)

static volatile DWORD ruby_native_thread_key = TLS_OUT_OF_INDEXES;

static int native_mutex_lock(rb_thread_lock_t *);
static int native_mutex_unlock(rb_thread_lock_t *);
static int native_mutex_trylock(rb_thread_lock_t *);
static void native_mutex_initialize(rb_thread_lock_t *);

static void native_cond_signal(rb_thread_cond_t *cond);
static void native_cond_broadcast(rb_thread_cond_t *cond);
static void native_cond_wait(rb_thread_cond_t *cond, rb_thread_lock_t *mutex);
static void native_cond_initialize(rb_thread_cond_t *cond);
static void native_cond_destroy(rb_thread_cond_t *cond);

static rb_thread_t *
ruby_thread_from_native(void)
{
    return TlsGetValue(ruby_native_thread_key);
}

static int
ruby_thread_set_native(rb_thread_t *th)
{
    return TlsSetValue(ruby_native_thread_key, th);
}

void
Init_native_thread(void)
{
    rb_thread_t *th = GET_THREAD();

    ruby_native_thread_key = TlsAlloc();
    ruby_thread_set_native(th);
    DuplicateHandle(GetCurrentProcess(),
		    GetCurrentThread(),
		    GetCurrentProcess(),
		    &th->thread_id, 0, FALSE, DUPLICATE_SAME_ACCESS);

    th->native_thread_data.interrupt_event = CreateEvent(0, TRUE, FALSE, 0);

    thread_debug("initial thread (th: %p, thid: %p, event: %p)\n",
		 th, GET_THREAD()->thread_id,
		 th->native_thread_data.interrupt_event);
}

static void
w32_error(const char *func)
{
    LPVOID lpMsgBuf;
    FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER |
		  FORMAT_MESSAGE_FROM_SYSTEM |
		  FORMAT_MESSAGE_IGNORE_INSERTS,
		  NULL,
		  GetLastError(),
		  MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		  (LPTSTR) & lpMsgBuf, 0, NULL);
    rb_bug("%s: %s", func, (char*)lpMsgBuf);
}

static void
w32_set_event(HANDLE handle)
{
    if (SetEvent(handle) == 0) {
	w32_error("w32_set_event");
    }
}

static void
w32_reset_event(HANDLE handle)
{
    if (ResetEvent(handle) == 0) {
	w32_error("w32_reset_event");
    }
}

static int
w32_wait_events(HANDLE *events, int count, DWORD timeout, rb_thread_t *th)
{
    HANDLE *targets = events;
    HANDLE intr;
    DWORD ret;

    thread_debug("  w32_wait_events events:%p, count:%d, timeout:%ld, th:%p\n",
		 events, count, timeout, th);
    if (th && (intr = th->native_thread_data.interrupt_event)) {
	native_mutex_lock(&th->vm->global_vm_lock);
	if (intr == th->native_thread_data.interrupt_event) {
	    w32_reset_event(intr);
	    if (RUBY_VM_INTERRUPTED(th)) {
		w32_set_event(intr);
	    }

	    targets = ALLOCA_N(HANDLE, count + 1);
	    memcpy(targets, events, sizeof(HANDLE) * count);

	    targets[count++] = intr;
	    thread_debug("  * handle: %p (count: %d, intr)\n", intr, count);
	}
	native_mutex_unlock(&th->vm->global_vm_lock);
    }

    thread_debug("  WaitForMultipleObjects start (count: %d)\n", count);
    ret = WaitForMultipleObjects(count, targets, FALSE, timeout);
    thread_debug("  WaitForMultipleObjects end (ret: %lu)\n", ret);

    if (ret == (DWORD)(WAIT_OBJECT_0 + count - 1) && th) {
	errno = EINTR;
    }
    if (ret == WAIT_FAILED && THREAD_DEBUG) {
	int i;
	DWORD dmy;
	for (i = 0; i < count; i++) {
	    thread_debug("  * error handle %d - %s\n", i,
			 GetHandleInformation(targets[i], &dmy) ? "OK" : "NG");
	}
    }
    return ret;
}

static void ubf_handle(void *ptr);
#define ubf_select ubf_handle

int
rb_w32_wait_events_blocking(HANDLE *events, int num, DWORD timeout)
{
    return w32_wait_events(events, num, timeout, GET_THREAD());
}

int
rb_w32_wait_events(HANDLE *events, int num, DWORD timeout)
{
    int ret;

    BLOCKING_REGION(ret = rb_w32_wait_events_blocking(events, num, timeout),
		    ubf_handle, GET_THREAD());
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
typedef unsigned long (_stdcall *w32_thread_start_func)(void*);
#else
#define start_thread CreateThread
#define thread_errno rb_w32_map_errno(GetLastError())
typedef LPTHREAD_START_ROUTINE w32_thread_start_func;
#endif

static HANDLE
w32_create_thread(DWORD stack_size, w32_thread_start_func func, void *val)
{
    return start_thread(0, stack_size, func, val, CREATE_SUSPENDED, 0);
}

int
rb_w32_sleep(unsigned long msec)
{
    return w32_wait_events(0, 0, msec, GET_THREAD());
}

int WINAPI
rb_w32_Sleep(unsigned long msec)
{
    int ret;

    BLOCKING_REGION(ret = rb_w32_sleep(msec),
		    ubf_handle, GET_THREAD());
    return ret;
}

static void
native_sleep(rb_thread_t *th, struct timeval *tv)
{
    DWORD msec;

    if (tv) {
	msec = tv->tv_sec * 1000 + tv->tv_usec / 1000;
    }
    else {
	msec = INFINITE;
    }

    GVL_UNLOCK_BEGIN();
    {
	DWORD ret;

	native_mutex_lock(&th->interrupt_lock);
	th->unblock.func = ubf_handle;
	th->unblock.arg = th;
	native_mutex_unlock(&th->interrupt_lock);

	if (RUBY_VM_INTERRUPTED(th)) {
	    /* interrupted.  return immediate */
	}
	else {
	    thread_debug("native_sleep start (%lu)\n", msec);
	    ret = w32_wait_events(0, 0, msec, th);
	    thread_debug("native_sleep done (%lu)\n", ret);
	}

	native_mutex_lock(&th->interrupt_lock);
	th->unblock.func = 0;
	th->unblock.arg = 0;
	native_mutex_unlock(&th->interrupt_lock);
    }
    GVL_UNLOCK_END();
}

static int
native_mutex_lock(rb_thread_lock_t *lock)
{
#if USE_WIN32_MUTEX
    DWORD result;
    while (1) {
	thread_debug("native_mutex_lock: %p\n", *lock);
	result = w32_wait_events(&*lock, 1, INFINITE, 0);
	switch (result) {
	  case WAIT_OBJECT_0:
	    /* get mutex object */
	    thread_debug("acquire mutex: %p\n", *lock);
	    return 0;
	  case WAIT_OBJECT_0 + 1:
	    /* interrupt */
	    errno = EINTR;
	    thread_debug("acquire mutex interrupted: %p\n", *lock);
	    return 0;
	  case WAIT_TIMEOUT:
	    thread_debug("timeout mutex: %p\n", *lock);
	    break;
	  case WAIT_ABANDONED:
	    rb_bug("win32_mutex_lock: WAIT_ABANDONED");
	    break;
	  default:
	    rb_bug("win32_mutex_lock: unknown result (%d)", result);
	    break;
	}
    }
    return 0;
#else
    EnterCriticalSection(lock);
    return 0;
#endif
}

static int
native_mutex_unlock(rb_thread_lock_t *lock)
{
#if USE_WIN32_MUTEX
    thread_debug("release mutex: %p\n", *lock);
    return ReleaseMutex(*lock);
#else
    LeaveCriticalSection(lock);
    return 0;
#endif
}

static int
native_mutex_trylock(rb_thread_lock_t *lock)
{
#if USE_WIN32_MUTEX
    int result;
    thread_debug("native_mutex_trylock: %p\n", *lock);
    result = w32_wait_events(&*lock, 1, 1, 0);
    thread_debug("native_mutex_trylock result: %d\n", result);
    switch (result) {
      case WAIT_OBJECT_0:
	return 0;
      case WAIT_TIMEOUT:
	return EBUSY;
    }
    return EINVAL;
#else
    return TryEnterCriticalSection(lock) == 0;
#endif
}

static void
native_mutex_initialize(rb_thread_lock_t *lock)
{
#if USE_WIN32_MUTEX
    *lock = CreateMutex(NULL, FALSE, NULL);
    if (*lock == NULL) {
	w32_error("native_mutex_initialize");
    }
    /* thread_debug("initialize mutex: %p\n", *lock); */
#else
    InitializeCriticalSection(lock);
#endif
}

#define native_mutex_reinitialize_atfork(lock) (void)(lock)

static void
native_mutex_destroy(rb_thread_lock_t *lock)
{
#if USE_WIN32_MUTEX
    w32_close_handle(lock);
#else
    DeleteCriticalSection(lock);
#endif
}

struct cond_event_entry {
    struct cond_event_entry* next;
    HANDLE event;
};

struct rb_thread_cond_struct {
    struct cond_event_entry *next;
    struct cond_event_entry *last;
};

static void
native_cond_signal(rb_thread_cond_t *cond)
{
    /* cond is guarded by mutex */
    struct cond_event_entry *e = cond->next;

    if (e) {
	cond->next = e->next;
	SetEvent(e->event);
    }
    else {
	rb_bug("native_cond_signal: no pending threads");
    }
}

static void
native_cond_broadcast(rb_thread_cond_t *cond)
{
    /* cond is guarded by mutex */
    struct cond_event_entry *e = cond->next;
    cond->next = 0;

    while (e) {
	SetEvent(e->event);
	e = e->next;
    }
}

static void
native_cond_wait(rb_thread_cond_t *cond, rb_thread_lock_t *mutex)
{
    DWORD r;
    struct cond_event_entry entry;

    entry.next = 0;
    entry.event = CreateEvent(0, FALSE, FALSE, 0);

    /* cond is guarded by mutex */
    if (cond->next) {
	cond->last->next = &entry;
	cond->last = &entry;
    }
    else {
	cond->next = &entry;
	cond->last = &entry;
    }

    native_mutex_unlock(mutex);
    {
	r = WaitForSingleObject(entry.event, INFINITE);
	if (r != WAIT_OBJECT_0) {
	    rb_bug("native_cond_wait: WaitForSingleObject returns %lu", r);
	}
    }
    native_mutex_lock(mutex);

    w32_close_handle(entry.event);
}

static void
native_cond_initialize(rb_thread_cond_t *cond)
{
    cond->next = 0;
    cond->last = 0;
}

static void
native_cond_destroy(rb_thread_cond_t *cond)
{
    /* */
}

void
ruby_init_stack(volatile VALUE *addr)
{
}

#define CHECK_ERR(expr) \
    {if (!(expr)) {rb_bug("err: %lu - %s", GetLastError(), #expr);}}

static void
native_thread_init_stack(rb_thread_t *th)
{
    MEMORY_BASIC_INFORMATION mi;
    char *base, *end;
    DWORD size, space;

    CHECK_ERR(VirtualQuery(&mi, &mi, sizeof(mi)));
    base = mi.AllocationBase;
    end = mi.BaseAddress;
    end += mi.RegionSize;
    size = end - base;
    space = size / 5;
    if (space > 1024*1024) space = 1024*1024;
    th->machine_stack_start = (VALUE *)end - 1;
    th->machine_stack_maxsize = size - space;
}

#ifndef InterlockedExchangePointer
#define InterlockedExchangePointer(t, v) \
    (void *)InterlockedExchange((long *)(t), (long)(v))
#endif
static void
native_thread_destroy(rb_thread_t *th)
{
    HANDLE intr = InterlockedExchangePointer(&th->native_thread_data.interrupt_event, 0);
    native_mutex_destroy(&th->interrupt_lock);
    thread_debug("close handle - intr: %p, thid: %p\n", intr, th->thread_id);
    w32_close_handle(intr);
}

static unsigned long _stdcall
thread_start_func_1(void *th_ptr)
{
    rb_thread_t *th = th_ptr;
    volatile HANDLE thread_id = th->thread_id;

    native_thread_init_stack(th);
    th->native_thread_data.interrupt_event = CreateEvent(0, TRUE, FALSE, 0);

    /* run */
    thread_debug("thread created (th: %p, thid: %p, event: %p)\n", th,
		 th->thread_id, th->native_thread_data.interrupt_event);

    thread_start_func_2(th, th->machine_stack_start, rb_ia64_bsp());

    w32_close_handle(thread_id);
    thread_debug("thread deleted (th: %p)\n", th);
    return 0;
}

static int
native_thread_create(rb_thread_t *th)
{
    size_t stack_size = 4 * 1024; /* 4KB */
    th->thread_id = w32_create_thread(stack_size, thread_start_func_1, th);

    if ((th->thread_id) == 0) {
	return thread_errno;
    }

    w32_resume_thread(th->thread_id);

    if (THREAD_DEBUG) {
	Sleep(0);
	thread_debug("create: (th: %p, thid: %p, intr: %p), stack size: %d\n",
		     th, th->thread_id,
		     th->native_thread_data.interrupt_event, stack_size);
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

    SetThreadPriority(th->thread_id, priority);
}

#endif /* USE_NATIVE_THREAD_PRIORITY */

static void
ubf_handle(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    thread_debug("ubf_handle: %p\n", th);

    w32_set_event(th->native_thread_data.interrupt_event);
}

static HANDLE timer_thread_id = 0;
static HANDLE timer_thread_lock;

static unsigned long _stdcall
timer_thread_func(void *dummy)
{
    thread_debug("timer_thread\n");
    while (WaitForSingleObject(timer_thread_lock, WIN32_WAIT_TIMEOUT) ==
	   WAIT_TIMEOUT) {
	timer_thread_function(dummy);
    }
    thread_debug("timer killed\n");
    return 0;
}

static void
rb_thread_create_timer_thread(void)
{
    if (timer_thread_id == 0) {
	if (!timer_thread_lock) {
	    timer_thread_lock = CreateEvent(0, TRUE, FALSE, 0);
	}
	timer_thread_id = w32_create_thread(1024 + (THREAD_DEBUG ? BUFSIZ : 0),
					    timer_thread_func, 0);
	w32_resume_thread(timer_thread_id);
    }
}

static int
native_stop_timer_thread(void)
{
    int stopped = --system_working <= 0;
    if (stopped) {
	SetEvent(timer_thread_lock);
	native_thread_join(timer_thread_id);
	CloseHandle(timer_thread_lock);
	timer_thread_lock = 0;
    }
    return stopped;
}

static void
native_reset_timer_thread(void)
{
    if (timer_thread_id) {
	CloseHandle(timer_thread_id);
	timer_thread_id = 0;
    }
}

#endif /* THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION */
