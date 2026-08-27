#ifndef RUBY_THREAD_SCHED_H
#define RUBY_THREAD_SCHED_H
/**********************************************************************

  thread_sched.h - data structures of the thread/ractor scheduler

  The scheduler itself lives in thread_sched.c and is shared by every
  platform.  This header holds the types it works on; it is included from
  the platform header (thread_pthread.h / thread_win32.h), which adds the
  platform specific members and the thread local storage plumbing.

  == platform primitive layer ==

  thread_sched.c is built on top of the following, which the platform
  implementation (THREAD_IMPL_SRC) has to provide before including it:

    * rb_native_mutex_*() / rb_native_cond_*()   (ruby/thread_native.h)
    * native_thread_create0() / native_thread_destroy() and friends
    * native_thread_interrupt()   -- poke a thread out of a blocking call
    * timer_thread_polling()      -- the timer thread's blocking wait
    * timer_thread_wakeup_force() -- wake that wait up
    * TIMER_THREAD_CREATED_P()
    * USE_MN_THREADS              -- 1 enables the M:N scheduler
      (when 0 the platform supplies the stubs listed at the bottom of
       thread_sched_mn.c)

**********************************************************************/

// How a thread_sched_wait_events() wait ended.  "unavailable" (could not be
// registered) is not "the event fired": the caller must fall back, not proceed.
enum thread_sched_wait_result {
    thread_sched_wait_event,       // an event the caller asked for fired
    thread_sched_wait_timeout,     // the timeout expired before any event
    thread_sched_wait_unavailable, // not registered; the caller must fall back
};

// this data should be protected by timer_th.waiting_lock
struct rb_thread_sched_waiting {
    enum thread_sched_waiting_flag {
        thread_sched_waiting_none     = 0x00,
        thread_sched_waiting_timeout  = 0x01,
        thread_sched_waiting_io_read  = 0x02,
        thread_sched_waiting_io_write = 0x08,
        thread_sched_waiting_io_force = 0x40, // ignore readable
    } flags;

    struct {
        // should be compat with hrtime.h
#ifdef MY_RUBY_BUILD_MAY_TIME_TRAVEL
        int128_t timeout;
#else
        uint64_t timeout;
#endif
        uint32_t event_serial;
        int fd; // -1 for timeout only
        int result;
    } data;

    // connected to a timer_th wheel slot (timed) or timer_th.waiting_untimed
    struct ccan_list_node node;

    /* which wheel slot `node` is on; meaningful only while flags has
     * thread_sched_waiting_timeout */
    uint8_t wheel_lvl;
    uint8_t wheel_slot;

    // connected to rb_fd_waiters.waiters of data.fd
    struct ccan_list_node fd_node;
};

// One entry per fd with waiters; fds stay dense, so a table indexed by fd fits.
// Entries live in fixed chunks: growing must not move a live list head.
struct rb_fd_waiters {
    struct ccan_list_head waiters; // rb_thread_sched_waiting.fd_node

    // The io flags currently armed in epoll/kqueue for this fd: the union of
    // what its waiters asked for.
    uint32_t armed_flags;

    // Bumped on full disarm.  Events carry the generation they were armed with,
    // so one queued before the fd was disarmed (and reused) is recognised.
    uint32_t generation;
};

// per-Thread scheduler helper data
struct rb_thread_sched_item {
    struct {
        struct ccan_list_node ubf;

        // connected to ractor->threads.sched.reqdyq
        // locked by ractor->threads.sched.lock
        struct ccan_list_node readyq;
        // Indicates whether thread is on the readyq.
        // There is no clear relationship between this and th->status.
        bool is_ready;

    } node;

    struct rb_thread_sched_waiting waiting_reason;
    uint32_t event_serial;

    // wakes pending on this thread (timer thread or an fd shard claim);
    // under timer_th.wake_pending_lock
    uint32_t wake_pending_cnt;

    // parked on its own condvar with a deadline; under the sched lock (see
    // ubf_waiting).  Always false for an M:N thread: its deadline lives on the
    // timer wheel, and its early wake comes from the timer thread instead.
    bool waiting_timed;

    bool malloc_stack;
    void *context_stack;
    size_t context_stack_size;
    struct coroutine_context *context;
};

struct rb_native_thread {
    rb_atomic_t serial;
    struct rb_vm_struct *vm;

    rb_nativethread_id_t thread_id;

#ifdef RB_THREAD_T_HAS_NATIVE_ID
    int tid;
#endif

#if defined(_WIN32)
    // signalled by native_thread_interrupt() to break this thread out of a
    // blocking w32_wait_events()
    HANDLE interrupt_event;
#endif

    struct rb_thread_struct *running_thread;

    // The running thread on this shared nt, for the barrier/timeslice scans.
    // While a scan holds running_th_lock the thread cannot finish parking.
    rb_nativethread_lock_t running_th_lock;
    struct rb_thread_struct *running_th;
    struct ccan_list_node snts_node; // in vm->ractor.sched.ntlist.snts
    // in vm->ractor.sched.ntlist.running_dnts while running_thread runs
    struct ccan_list_node running_dnts_node;
    // barrier_serial stamped by the barrier's counting walk; this nt's
    // deregistration during that barrier decrements the snapshot count
    uint32_t barrier_counted_serial;

    // to control native thread; use sched->lock
    rb_nativethread_cond_t readyq;

#ifdef USE_SIGALTSTACK
    void *altstack;
#endif

    struct coroutine_context *nt_context;
    int dedicated;

    // set when this thread came back from a blocking region with no room left
    // in the shared pool; it ends when it next asks for work
    bool retiring;

    // A terminating coroutine records its context here before its final
    // transfer; this nt's loop reclaims it. (Not via coroutine_transfer()'s
    // return value: its meaning differs between the amd64 asm and ucontext.)
    struct coroutine_context *dead_co;
};

// <windows.h> defines these as macros, and the field names below (and in the
// rest of the interpreter) would be rewritten by them.
#undef except
#undef try
#undef leave
#undef finally

// per-Ractor
struct rb_thread_sched {
    rb_nativethread_lock_t lock_;
#if VM_CHECK_MODE
    struct rb_thread_struct *lock_owner;
#endif
    struct rb_thread_struct *running; // running thread or NULL
    // Most recently running thread or NULL. If this thread wakes up before the newly running
    // thread completes the transfer of control, it can interrupt and resume running.
    // The new thread clears this field when it takes control.
    struct rb_thread_struct *runnable_hot_th;
    int runnable_hot_th_waiting;
    bool is_running;

    bool enable_mn_threads;

    struct ccan_list_head readyq;
    int readyq_cnt;
    // ractor scheduling
    // When not linked in vm->ractor.sched.grq, this node is kept
    // self-linked (ccan_list_node_init), so "linked?" can be read off the
    // node itself: enqueuers assert it, and direct transfers cancel an
    // outstanding entry (see ractor_sched_cancel_enq).
    struct ccan_list_node grq_node;
    struct ccan_list_node timeslice_node; // self-linked = not on timeslice.scheds
};

struct rb_thread_context;

// A coroutine (M:N) thread's teardown runs coroutine_thread_terminated
// instead of the dedicated-thread path in thread_start_func_2; see the
// comments there and in thread_sched_mn.c. th->sched.context is cleared in
// that epilogue, so this also reads as "did not tear down yet".
// (Only meaningful when USE_MN_THREADS -- gate uses accordingly; the macro
// itself is a plain pointer test and always compiles.)
#define th_has_coroutine(th) ((th)->sched.context != NULL)

struct rb_ractor_struct;

// VM wide: what schedules Ractors onto native threads.  One per VM, in
// rb_vm_struct.ractor.sched.
struct rb_ractor_sched {
    rb_nativethread_lock_t lock;
    struct rb_ractor_struct *lock_owner;
    bool locked;

    rb_nativethread_cond_t cond; // GRQ
    rb_atomic_t snt_cnt;  // count of shared NTs; lock-free (see native_thread_dedicated_inc)
    unsigned int dnt_cnt; // count of dedicated NTs; logging only (USE_RUBY_DEBUG_LOG), not atomic

    unsigned int max_cpu;
    struct ccan_list_head grq; // // Global Ready Queue
    rb_atomic_t winding_cnt; // native threads between a coroutine epilogue and its reclaim; ruby_vm_destruct waits for 0
    unsigned int grq_cnt;

    // What the barrier walk visits: threads running on dedicated
    // nts, and the shared nts (whose running_th fields hold the rest).
    struct {
        rb_nativethread_lock_t lock;
        struct ccan_list_head running_dnts;
        struct ccan_list_head snts;
    } ntlist;

    // scheds whose readyq holds waiters: the timer ticks their
    // running thread (timeslice_scan) and prunes drained entries.
    struct {
        rb_nativethread_lock_t lock;
        struct ccan_list_head scheds;
    } timeslice;

    // true if timeslice timer is not enable
    bool timeslice_wait_inf;

    // barrier
    rb_nativethread_cond_t barrier_complete_cond;
    rb_nativethread_cond_t barrier_release_cond;
    // bool; nonzero while a stop-the-world section is active.  Set
    // before the barrier walks the running records; a record moved
    // after the walk sees it (thread_sched_setup_running_threads).
    rb_atomic_t barrier_is_waiting;
    unsigned int barrier_joined_cnt; // threads joined so far; under sched.lock
    unsigned int barrier_running_cnt; // runners counted by the barrier's walk; under sched.lock
    unsigned int barrier_serial;
    struct rb_ractor_struct *barrier_ractor;
    unsigned int barrier_lock_rec;
};

void rb_ractor_sched_wait(struct rb_execution_context_struct *ec, struct rb_ractor_struct *cr, rb_unblock_function_t *ptr, void *arg);
void rb_ractor_sched_wakeup(struct rb_ractor_struct *r, struct rb_thread_struct *th);
void rb_thread_wake_fence(struct rb_thread_struct *th);

#endif /* RUBY_THREAD_SCHED_H */
