/*
 A thread interface implementation without any system thread.

 Assumption:
 * There is a only single thread in the ruby process
 * No signal happens targeting the ruby process

 Note:
 * No thread switching in the VM
 * No timer thread because thread switching won't happen
 * No mutex guard because the VM won't be racy
*/

#ifdef THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

#include <time.h>

#if defined(__wasm__) && !defined(__EMSCRIPTEN__)
# include "wasm/machine.h"
#endif

// Do nothing for GVL
static void
thread_sched_to_running(struct rb_thread_sched *sched, rb_thread_t *th)
{
}

static void
thread_sched_to_waiting(struct rb_thread_sched *sched, rb_thread_t *th)
{
}

#define thread_sched_to_dead thread_sched_to_waiting

static void
thread_sched_yield(struct rb_thread_sched *sched, rb_thread_t *th)
{
}

void
rb_thread_sched_init(struct rb_thread_sched *sched, bool atfork)
{
}

#if 0
static void
rb_thread_sched_destroy(struct rb_thread_sched *sched)
{
}
#endif

// Do nothing for mutex guard
void
rb_native_mutex_lock(rb_nativethread_lock_t *lock)
{
}

void
rb_native_mutex_unlock(rb_nativethread_lock_t *lock)
{
}

int
rb_native_mutex_trylock(rb_nativethread_lock_t *lock)
{
    return 0;
}

void
rb_native_mutex_initialize(rb_nativethread_lock_t *lock)
{
}

void
rb_native_mutex_destroy(rb_nativethread_lock_t *lock)
{
}

void
rb_native_cond_initialize(rb_nativethread_cond_t *cond)
{
}

void
rb_native_cond_destroy(rb_nativethread_cond_t *cond)
{
}

void
rb_native_cond_signal(rb_nativethread_cond_t *cond)
{
}

void
rb_native_cond_broadcast(rb_nativethread_cond_t *cond)
{
}

void
rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex)
{
}

void
rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec)
{
}

// The only one thread in process
static rb_thread_t *ruby_native_thread;

rb_thread_t *
ruby_thread_from_native(void)
{
    return ruby_native_thread;
}

int
ruby_thread_set_native(rb_thread_t *th)
{
    if (th && th->ec) {
        rb_ractor_set_current_ec(th->ractor, th->ec);
    }
    ruby_native_thread = th;
    return 1; // always succeed
}

void
Init_native_thread(rb_thread_t *main_th)
{
    // no TLS setup and no thread id setup
    ruby_thread_set_native(main_th);
}

void
ruby_mn_threads_params(void)
{
}

static int
native_thread_init_stack(rb_thread_t *th, void *local_in_parent_frame)
{
#if defined(__wasm__) && !defined(__EMSCRIPTEN__)
    th->ec->machine.stack_start = (VALUE *)rb_wasm_stack_get_base();
#endif
    return 0; // success
}

static int
native_thread_create(rb_thread_t *th)
{
    th->status = THREAD_KILLED;
    rb_ractor_living_threads_remove(th->ractor, th);
    rb_notimplement();
}

// Do nothing for handling ubf because no other thread doesn't exist and unblock anything
#define register_ubf_list(th) (void)(th)
#define unregister_ubf_list(th) (void)(th)
#define ubf_select 0

inline static void
ubf_wakeup_all_threads(void)
{
    return;
}

inline static int
ubf_threads_empty(void)
{
    return 1; // true
}

inline static void
ubf_list_atfork()
{
}

inline static void
ubf_timer_disarm(void)
{
}


// No timer thread because thread switching won't happen
#define TIMER_THREAD_CREATED_P() (1)
inline static void
rb_thread_create_timer_thread(void)
{
}

void
rb_thread_wakeup_timer_thread(int sig)
{
}

inline static int
native_stop_timer_thread(void)
{
    return 1; // success
}

inline static void
native_reset_timer_thread(void)
{
}

// Do nothing for thread naming
inline static void
native_set_thread_name(rb_thread_t *th)
{
}

inline static void
native_set_another_thread_name(rb_nativethread_id_t thread_id, VALUE name)
{
}

// Don't expose native thread id for now to keep system's thread API agnostic
#define USE_NATIVE_THREAD_NATIVE_THREAD_ID 0

// No reserved fd for piping threads
int
rb_reserved_fd_p(int fd)
{
    return 0; // not reserved
}

// Don't expose native thread info for now to keep system's thread API agnostic
rb_nativethread_id_t
rb_nativethread_self(void)
{
    return NULL;
}

// Do nothing for sigwait things because of no signal assumption
// Q(katei): is this correct description?
int
rb_sigwait_fd_get(const rb_thread_t *th)
{
    return -1;
}

NORETURN(void rb_sigwait_fd_put(rb_thread_t *, int));
void
rb_sigwait_fd_put(rb_thread_t *th, int fd)
{
    rb_bug("not implemented, should not be called rb_sigwait_fd_put");
}

NORETURN(void rb_sigwait_sleep(const rb_thread_t *, int, const rb_hrtime_t *));
void
rb_sigwait_sleep(const rb_thread_t *th, int sigwait_fd, const rb_hrtime_t *rel)
{
    rb_bug("not implemented, should not be called rb_sigwait_sleep");
}

static void
native_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    // No signal assumption allows the use of uninterruptible sleep
    struct timespec ts;
    (void)clock_nanosleep(CLOCK_REALTIME, 0, rb_hrtime2timespec(&ts, rel), NULL);
}

static int
native_fd_select(int n, rb_fdset_t *readfds, rb_fdset_t *writefds, rb_fdset_t *exceptfds, struct timeval *timeout, rb_thread_t *th)
{
    return rb_fd_select(n, readfds, writefds, exceptfds, timeout);
}

static bool
th_has_dedicated_nt(const rb_thread_t *th)
{
    return true;
}

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

void
rb_threadptr_sched_free(rb_thread_t *th)
{
    // do nothing
}

void
rb_ractor_sched_barrier_start(rb_vm_t *vm, rb_ractor_t *cr)
{
    // do nothing
}

void
rb_ractor_sched_barrier_join(rb_vm_t *vm, rb_ractor_t *cr)
{
    // do nothing
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
