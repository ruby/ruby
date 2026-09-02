/* -*-c-*- */
/**********************************************************************

  thread_sched_mn.c - the M:N scheduler

  Included by the platform implementation (currently only thread_pthread.c)
  when USE_MN_THREADS is 1.  A platform that cannot run coroutine threads
  defines it to 0 and supplies the stubs at the bottom of this file itself
  (see thread_win32.c).

  Most of what is here is platform independent: the coroutine threads
  themselves, the native thread stack pool, the timer wheel, and the
  fd -> waiters map.  The part that is not is the readiness backend --
  arming an fd and waiting for events -- which is epoll on Linux and kqueue
  elsewhere.  Those pieces are marked "backend" below; they are the natural
  seam for a thread_sched_epoll.c / thread_sched_kqueue.c split, and for an
  IOCP backend that would let Windows run M:N threads too.

**********************************************************************/

#if USE_MN_THREADS

#if HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H
static void timer_thread_unregister_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags);
#endif

static bool
timer_thread_check_exceed(rb_hrtime_t abs, rb_hrtime_t now)
{
    return abs <= now;
}

static rb_thread_t *
thread_sched_waiting_thread(struct rb_thread_sched_waiting *w)
{
    if (w) {
        return (rb_thread_t *)((size_t)w - offsetof(rb_thread_t, sched.waiting_reason));
    }
    else {
        return NULL;
    }
}

#define FD_WAIT_IO_MASK (thread_sched_waiting_io_read | thread_sched_waiting_io_write)

// Guards the fd map entries and the flags of io waits for its fds.  Whoever
// clears an io wait's flags under its shard owns that wakeup.
// Lock order: shard -> waiting_lock -> wake_pending_lock.
static void
fd_shard_lock(int fd)
{
    rb_native_mutex_lock(&timer_th.fd_shard_locks[(unsigned int)fd % IO_WAIT_SHARDS]);
}

static void
fd_shard_unlock(int fd)
{
    rb_native_mutex_unlock(&timer_th.fd_shard_locks[(unsigned int)fd % IO_WAIT_SHARDS]);
}

#define TIMER_WHEEL_NO_EXPIRY RB_HRTIME_MAX
#ifndef TIMER_WHEEL_TICK_MS
#define TIMER_WHEEL_TICK_MS 1 // L0 slot width; coarser trades sleep accuracy for fewer drains
#endif

/* Timer wheel over the timed waiters.  Every operation runs under
 * timer_th.waiting_lock.
 *
 * Level L buckets deadlines into 64 slots of 64^L ms each; a deadline is
 * placed by its distance from the drain cursor, so its slot is always
 * strictly ahead of the cursor at that level.  The drain refines a
 * not-yet-due waiter onto a finer level instead of cascading whole slots,
 * so one waiter moves at most once per level over its lifetime.
 *
 * This is the hierarchical timing wheel of Varghese & Lauck, "Hashed and
 * Hierarchical Timing Wheels" (SOSP '87). */

static uint64_t
timer_wheel_tick(rb_hrtime_t hrt)
{
    return hrt / (RB_HRTIME_PER_MSEC * TIMER_WHEEL_TICK_MS);
}

static inline int
timer_wheel_ctz64(uint64_t v)
{
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_ctzll(v);
#else
    int n = 0;
    while (!(v & 1)) { v >>= 1; n++; }
    return n;
#endif
}

static int
timer_wheel_level(uint64_t dist_ms)
{
    if (dist_ms < ((uint64_t)1 << TIMER_WHEEL_SLOT_BITS)) return 0;
    if (dist_ms < ((uint64_t)1 << 2 * TIMER_WHEEL_SLOT_BITS)) return 1;
    if (dist_ms < ((uint64_t)1 << 3 * TIMER_WHEEL_SLOT_BITS)) return 2;
    return TIMER_WHEEL_LEVELS - 1;
}

static void
timer_wheel_insert(struct rb_thread_sched_waiting *w)
{
    uint64_t dl_tick = timer_wheel_tick(w->data.timeout);
    uint64_t cur = timer_th.wheel_cursor_tick;

    /* A deadline at or behind the cursor parks one tick ahead: its own slot
     * is already drained and would otherwise wait out a full wheel turn. */
    uint64_t target = dl_tick > cur ? dl_tick : cur + 1;
    int lvl = timer_wheel_level(target - cur);
    int shift = lvl * TIMER_WHEEL_SLOT_BITS;
    uint64_t slot_tick = target >> shift;

    if (lvl == TIMER_WHEEL_LEVELS - 1) {
        /* Beyond the wheel range: park on the farthest slot; the drain
         * re-inserts it with the then-smaller distance. */
        uint64_t far = (cur >> shift) + TIMER_WHEEL_SLOTS - 1;
        if (slot_tick > far) slot_tick = far;
    }

    int slot = (int)(slot_tick & (TIMER_WHEEL_SLOTS - 1));

    ccan_list_add_tail(&timer_th.wheel[lvl].slots[slot], &w->node);
    timer_th.wheel[lvl].occupied |= UINT64_C(1) << slot;
    w->wheel_lvl = (uint8_t)lvl;
    w->wheel_slot = (uint8_t)slot;

    if (w->data.timeout < timer_th.next_expiry) {
        timer_th.next_expiry = w->data.timeout;
    }
}

// Unlink a waiter from the wheel slot or the untimed list it is on.
static void
timer_wheel_del(struct rb_thread_sched_waiting *w)
{
    ccan_list_del_init(&w->node);

    if (w->flags & thread_sched_waiting_timeout) {
        struct timer_wheel_level *lv = &timer_th.wheel[w->wheel_lvl];
        if (ccan_list_empty(&lv->slots[w->wheel_slot])) {
            lv->occupied &= ~(UINT64_C(1) << w->wheel_slot);
        }
    }
}

/* A lower bound on the earliest deadline: the start time of the nearest
 * occupied slot per level.  Never later than any real deadline, so waking
 * by it is at worst early, which is harmless. */
static rb_hrtime_t
timer_wheel_next_expiry(void)
{
    rb_hrtime_t best = TIMER_WHEEL_NO_EXPIRY;

    for (int lvl = 0; lvl < TIMER_WHEEL_LEVELS; lvl++) {
        uint64_t occ = timer_th.wheel[lvl].occupied;
        if (!occ) continue;

        int shift = lvl * TIMER_WHEEL_SLOT_BITS;
        uint64_t cur_tick = timer_th.wheel_cursor_tick >> shift;
        unsigned base = (unsigned)((cur_tick + 1) & (TIMER_WHEEL_SLOTS - 1));
        // rotate so bit k = slot for tick cur_tick+1+k
        uint64_t rot = (occ >> base) | (base ? (occ << (TIMER_WHEEL_SLOTS - base)) : 0);
        uint64_t tick = cur_tick + 1 + timer_wheel_ctz64(rot);
        rb_hrtime_t start = (rb_hrtime_t)(tick << shift) * RB_HRTIME_PER_MSEC * TIMER_WHEEL_TICK_MS;

        if (start < best) best = start;
    }

    return best;
}

/* Drain every slot whose tick moved behind `now`, collecting due waiters
 * onto `expired` and re-bucketing not-yet-due ones onto a finer level.
 * timer_th.waiting_lock must be held. */
static void
timer_wheel_drain(rb_hrtime_t now, uint64_t now_tick, struct ccan_list_head *expired)
{
    uint64_t prev_tick = timer_th.wheel_cursor_tick;
    timer_th.wheel_cursor_tick = now_tick;  // re-inserts below map against the new cursor
    /* A deadline inside the current tick parks one tick ahead, so its slot
     * start is later than the deadline.  Keep the exact value: the recompute
     * below only knows slot starts, and next_expiry must not exceed a deadline. */
    rb_hrtime_t reinserted = TIMER_WHEEL_NO_EXPIRY;

    for (int lvl = 0; lvl < TIMER_WHEEL_LEVELS; lvl++) {
        int shift = lvl * TIMER_WHEEL_SLOT_BITS;
        uint64_t from = prev_tick >> shift;
        uint64_t to = now_tick >> shift;

        if (to == from) break; // no boundary crossed; coarser levels crossed none either

        uint64_t steps = to - from;
        if (steps > TIMER_WHEEL_SLOTS) steps = TIMER_WHEEL_SLOTS;
        struct timer_wheel_level *lv = &timer_th.wheel[lvl];

        for (uint64_t tick = to - steps + 1; tick <= to; tick++) {
            int slot = (int)(tick & (TIMER_WHEEL_SLOTS - 1));

            if (!(lv->occupied & (UINT64_C(1) << slot))) continue;
            lv->occupied &= ~(UINT64_C(1) << slot);

            /* Detach first: a far-future waiter re-clamped by the insert below
             * can land back on this very slot and must not be drained again. */
            struct ccan_list_head pending;
            ccan_list_head_init(&pending);
            ccan_list_append_list(&pending, &lv->slots[slot]);

            struct rb_thread_sched_waiting *w;
            while ((w = ccan_list_pop(&pending, struct rb_thread_sched_waiting, node)) != NULL) {
                if (timer_thread_check_exceed(w->data.timeout, now)) {
                    RUBY_DEBUG_LOG("expired th:%u", rb_th_serial(thread_sched_waiting_thread(w)));

                    /* flags stay set until the wakeup takes them under the
                     * owning lock (the fd shard for io waits, this one
                     * otherwise): a waiter whose flags are already cleared may
                     * run and re-register through this same `w`, which would
                     * relink the node we are still holding on `expired`. */
                    ccan_list_add_tail(expired, &w->node);
                }
                else {
                    /* arrived early: the distance shrank, so this lands on a
                     * finer level (or a farther slot of the coarsest one) */
                    if (w->data.timeout < reinserted) reinserted = w->data.timeout;
                    timer_wheel_insert(w);
                }
            }
        }
    }

    timer_th.next_expiry = timer_wheel_next_expiry();
    if (reinserted < timer_th.next_expiry) timer_th.next_expiry = reinserted;
}

/* Merge the wheel's next expiry into the poll timeout (ms; -1 = none).
 * Checked even when the scheduler has other work (grq_cnt > 0). */
static int
timer_wheel_timeout(int timeout)
{
    rb_native_mutex_lock(&timer_th.waiting_lock);
    {
        if (timer_th.next_expiry != TIMER_WHEEL_NO_EXPIRY) {
            rb_hrtime_t now = rb_hrtime_now();
            rb_hrtime_t hrrel = rb_hrtime_sub(timer_th.next_expiry, now);

            RUBY_DEBUG_LOG("now:%lu rel:%lu", (unsigned long)now, (unsigned long)hrrel);

            rb_hrtime_t msec = (hrrel + RB_HRTIME_PER_MSEC - 1) / RB_HRTIME_PER_MSEC;
            // A deadline further away than INT_MAX ms must clamp, not truncate:
            // a negative timeout would be an untimed epoll_wait.
            int thread_timeout = msec > INT_MAX ? INT_MAX : (int)msec; // ms

            // Use minimum of scheduler timeout and thread sleep timeout
            if (timeout < 0 || thread_timeout < timeout) {
                timeout = thread_timeout;
            }
        }
    }
    rb_native_mutex_unlock(&timer_th.waiting_lock);

    return timeout;
}

static void
timer_thread_wakeup_thread_locked(struct rb_thread_sched *sched, rb_thread_t *th, uint32_t event_serial)
{
    if (sched->running != th && th->sched.event_serial == event_serial) {
        thread_sched_to_ready_common(sched, th, true, false);
    }
}

static void
timer_thread_wakeup_thread(rb_thread_t *th, uint32_t event_serial)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));
    struct rb_thread_sched *sched = TH_SCHED(th);

    thread_sched_lock(sched, th);
    {
        timer_thread_wakeup_thread_locked(sched, th, event_serial);
    }
    thread_sched_unlock(sched, th);
}

#define TIMEOUT_WAKE_BATCH 16

// One thread the timer thread is about to wake, with the serial it was armed at.
struct timer_wake { rb_thread_t *th; uint32_t serial; };

// Count a pending wake against a thread, so a dying thread can wait them out
// (timer_thread_wake_fence).  A count, not a flag: an expiry hold and an fd
// event's wake can be pending on one thread at once.  Take it while the lock
// that pinned the thread (shard or waiting_lock) is still held.
static void
timer_wake_pending_inc(rb_thread_t *th)
{
    rb_native_mutex_lock(&timer_th.wake_pending_lock);
    th->sched.wake_pending_cnt++;
    rb_native_mutex_unlock(&timer_th.wake_pending_lock);
}

static void
timer_wake_pending_dec(rb_thread_t *th)
{
    rb_native_mutex_lock(&timer_th.wake_pending_lock);
    VM_ASSERT(th->sched.wake_pending_cnt > 0);
    th->sched.wake_pending_cnt--;
    rb_native_cond_broadcast(&timer_th.wake_pending_cond);
    rb_native_mutex_unlock(&timer_th.wake_pending_lock);
}

static void
timer_wake_pending_clear(struct timer_wake *batch, int n)
{
    for (int i = 0; i < n; i++) {
        timer_wake_pending_dec(batch[i].th);
    }
}

// Wait out pending wakes before a thread is freed: they would touch freed
// memory, or wake a reused thread whose first serial matches a stale entry.
static void
timer_thread_wake_fence(rb_thread_t *th)
{
    if (!TIMER_THREAD_CREATED_P()) return;

    rb_native_mutex_lock(&timer_th.wake_pending_lock);
    while (th->sched.wake_pending_cnt > 0) {
        rb_native_cond_wait(&timer_th.wake_pending_cond, &timer_th.wake_pending_lock);
    }
    rb_native_mutex_unlock(&timer_th.wake_pending_lock);
}

static void
timer_thread_check_timeout(rb_vm_t *vm)
{
    rb_hrtime_t now = rb_hrtime_now();
    uint64_t now_tick = timer_wheel_tick(now);
    struct ccan_list_head expired;

    ccan_list_head_init(&expired);

    struct timer_wake batch[TIMEOUT_WAKE_BATCH];
    bool more = true;

    while (more) {
        int n = 0;
        struct { rb_thread_t *th; uint32_t serial; int fd; } io_claims[TIMEOUT_WAKE_BATCH];
        int n_io = 0;

        rb_native_mutex_lock(&timer_th.waiting_lock);
        {
            // A second pass finds the cursor already at now_tick and drains nothing.
            if (now_tick > timer_th.wheel_cursor_tick) {
                timer_wheel_drain(now, now_tick, &expired);
            }

            struct rb_thread_sched_waiting *w;
            while (n + n_io < TIMEOUT_WAKE_BATCH &&
                   (w = ccan_list_pop(&expired, struct rb_thread_sched_waiting, node)) != NULL) {
                // Name the thread and its serial here, then release it: once the
                // flags are clear the thread may run and re-register through `w`,
                // and a serial read after that would match the new registration.
                // the pop leaves the node dangling; a concurrent claimer's
                // wheel del (under this lock) must find it self-linked
                ccan_list_node_init(&w->node);

                if (w->flags & FD_WAIT_IO_MASK) {
                    // The fd shard owns these flags; claim below, once this
                    // lock is dropped.  The pending count pins the thread: it
                    // was parked when we popped its node (a claimed entry
                    // leaves the wheel before its thread can wake).
                    io_claims[n_io].th = thread_sched_waiting_thread(w);
                    io_claims[n_io].serial = w->data.event_serial;
                    io_claims[n_io].fd = w->data.fd;
                    timer_wake_pending_inc(io_claims[n_io].th);
                    n_io++;
                }
                else {
                    // pin before the flags clear; see timer_thread_wake_fd_waiters
                    batch[n].th = thread_sched_waiting_thread(w);
                    batch[n].serial = w->data.event_serial;
                    timer_wake_pending_inc(batch[n].th);
                    w->flags = thread_sched_waiting_none;
                    w->data.result = 0;
                    n++;
                }
            }
            more = !ccan_list_empty(&expired);
        }
        rb_native_mutex_unlock(&timer_th.waiting_lock);

        for (int i = 0; i < n; i++) {
            timer_thread_wakeup_thread(batch[i].th, batch[i].serial);
        }
        timer_wake_pending_clear(batch, n);

        // The io entries race the fd event and the ubf for their flags.
        for (int i = 0; i < n_io; i++) {
            rb_thread_t *th = io_claims[i].th;
            int fd = io_claims[i].fd;
            bool claimed = false;

            fd_shard_lock(fd);
            {
                struct rb_thread_sched_waiting *w = &th->sched.waiting_reason;

                if (w->flags != thread_sched_waiting_none &&
                    w->data.event_serial == io_claims[i].serial) {
                    VM_ASSERT(w->data.fd == fd);
                    timer_thread_unregister_waiting(th, fd, w->flags);
                    w->flags = thread_sched_waiting_none;
                    w->data.result = 0;
                    claimed = true;
                }
            }
            fd_shard_unlock(fd);

            if (claimed) {
                timer_thread_wakeup_thread(th, io_claims[i].serial);
            }
            timer_wake_pending_dec(th);
        }
    }
}

static bool
timer_thread_cancel_waiting(rb_thread_t *th)
{
    struct rb_thread_sched_waiting *w = &th->sched.waiting_reason;

    while (1) {
        // Racy routing read; the claim is re-verified under the owning lock.
        enum thread_sched_waiting_flag flags = w->flags;

        if (flags == thread_sched_waiting_none) {
            return false;
        }
        else if (flags & FD_WAIT_IO_MASK) {
            int fd = w->data.fd;

            fd_shard_lock(fd);
            if ((w->flags & FD_WAIT_IO_MASK) && w->data.fd == fd) {
                if (w->flags & thread_sched_waiting_timeout) {
                    rb_native_mutex_lock(&timer_th.waiting_lock);
                    timer_wheel_del(w);
                    rb_native_mutex_unlock(&timer_th.waiting_lock);
                }
                timer_thread_unregister_waiting(th, fd, w->flags);
                w->flags = thread_sched_waiting_none;
                fd_shard_unlock(fd);
                return true;
            }
            fd_shard_unlock(fd);
        }
        else {
            rb_native_mutex_lock(&timer_th.waiting_lock);
            if (w->flags && !(w->flags & FD_WAIT_IO_MASK)) {
                timer_wheel_del(w);
                w->flags = thread_sched_waiting_none;
                rb_native_mutex_unlock(&timer_th.waiting_lock);
                return true;
            }
            rb_native_mutex_unlock(&timer_th.waiting_lock);
        }
        // lost the routing race; look again
    }
}

static void
ubf_event_waiting(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    struct rb_thread_sched *sched = TH_SCHED(th);

    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    VM_ASSERT(th->nt == NULL || !th_has_dedicated_nt(th));

    // only once. it is safe because th->interrupt_lock is already acquired.
    th->unblock.func = NULL;
    th->unblock.arg = NULL;

    thread_sched_lock(sched, th);
    {
        bool canceled = timer_thread_cancel_waiting(th);

        if (sched->running == th) {
            RUBY_DEBUG_LOG("not waiting yet");
        }
        else if (canceled) {
            thread_sched_to_ready_common(sched, th, true, false);
        }
        else {
            RUBY_DEBUG_LOG("already not waiting");
        }
    }
    thread_sched_unlock(sched, th);
}

// Why timer_thread_register_waiting() did or did not take over the wait.  Both
// "not registered" cases used to share one value; only the first means ready.
enum timer_thread_register_result {
    timer_thread_registered,    // the timer thread owns this wait now
    timer_thread_already_ready, // no wait needed: the fd is ready, or no timeout
    timer_thread_unavailable,   // cannot be registered; the caller must fall back
};

static enum timer_thread_register_result
timer_thread_register_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags, rb_hrtime_t *rel, uint32_t event_serial);

// Arm a timeout-only wake on the timer thread for a Ractor wait.  Returns false
// if the deadline has already passed, in which case nothing was registered.
static bool
ractor_sched_timeout_arm(rb_thread_t *th, const rb_hrtime_t *rel)
{
    rb_hrtime_t rel_copy = *rel;

    return timer_thread_register_waiting(th, -1, thread_sched_waiting_timeout, &rel_copy,
                                         ++th->sched.event_serial) == timer_thread_registered;
}

// Returns true if the timeout was still armed, i.e. it did not fire.
static bool
ractor_sched_timeout_disarm(rb_thread_t *th)
{
    return timer_thread_cancel_waiting(th);
}

// return how the wait ended; see enum thread_sched_wait_result
static enum thread_sched_wait_result
thread_sched_wait_events(struct rb_thread_sched *sched, rb_thread_t *th, int fd, enum thread_sched_waiting_flag events, rb_hrtime_t *rel)
{
    VM_ASSERT(!th_has_dedicated_nt(th));  // on SNT

    volatile bool timedout = false, need_cancel = false;
    volatile enum timer_thread_register_result reg = timer_thread_unavailable;

    uint32_t event_serial = ++th->sched.event_serial; // overflow is okay


    thread_sched_lock(sched, th);
    {
        // NOTE: there's a lock ordering inversion here with the ubf call, but it's benign.
        if (ubf_set(th, ubf_event_waiting, (void *)th, NULL)) {
            // Already interrupted: report an event so the caller retries and then
            // processes the interrupt, as it always has.
            thread_sched_unlock(sched, th);
            return thread_sched_wait_event;
        }

        reg = timer_thread_register_waiting(th, fd, events, rel, event_serial);

        if (reg == timer_thread_registered) {
            RUBY_DEBUG_LOG("wait fd:%d", fd);

            RB_VM_SAVE_MACHINE_CONTEXT(th);

            RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);

            if (th->sched.waiting_reason.flags == thread_sched_waiting_none) {
                th->sched.event_serial++;
                // timer thread has dequeued us already, but it won't try to wake us because we bumped our serial
            }
            else if (RUBY_VM_INTERRUPTED(th->ec)) {
                th->sched.event_serial++; // make sure timer thread doesn't try to wake us
                need_cancel = true;
            }
            else {
                RUBY_DEBUG_LOG("sleep");

                // A sleeper's status belongs to the caller: sleep_hrtime
                // re-sleeps while it stays THREAD_STOPPED and only a waker may
                // change it, as with native_cond_sleep on a dedicated nt.  An
                // io wait enters as THREAD_RUNNABLE and shows "sleep" while
                // parked, as a dedicated nt's blocking region does.
                enum rb_thread_status prev_status = th->status;
                if (prev_status == THREAD_RUNNABLE) th->status = THREAD_STOPPED_FOREVER;
                thread_sched_wakeup_next_thread(sched, th, true);
                thread_sched_wait_running_turn(sched, th, true, NULL);
                if (prev_status == THREAD_RUNNABLE) th->status = THREAD_RUNNABLE;

                RUBY_DEBUG_LOG("wakeup");
            }

            timedout = th->sched.waiting_reason.data.result == 0;

            if (need_cancel) {
                timer_thread_cancel_waiting(th);
            }
        }
        else {
            // Ready right now, or not registerable at all -- only the former may
            // be reported as readiness.
            RUBY_DEBUG_LOG("did not wait fd:%d reg:%d", fd, (int)reg);
        }
    }
    thread_sched_unlock(sched, th);

    // if ubf triggered between sched unlock and ubf clear, sched->running == th here
    ubf_clear(th, false);

    VM_ASSERT(sched->running == th);

    if (reg == timer_thread_unavailable) return thread_sched_wait_unavailable;
    // A ready fd never registered, so it never timed out either.
    if (reg == timer_thread_already_ready) return thread_sched_wait_event;
    return timedout ? thread_sched_wait_timeout : thread_sched_wait_event;
}

/// stack management

static int
get_sysconf_page_size(void)
{
    static long page_size = 0;

    if (UNLIKELY(page_size == 0)) {
        page_size = sysconf(_SC_PAGESIZE);
        VM_ASSERT(page_size < INT_MAX);
    }
    return (int)page_size;
}

#define MSTACK_CHUNK_SIZE (512 * 1024 * 1024) // 512MB
#define MSTACK_PAGE_SIZE get_sysconf_page_size()
#define MSTACK_CHUNK_PAGE_NUM (MSTACK_CHUNK_SIZE / MSTACK_PAGE_SIZE - 1) // 1 is start redzone

// 512MB chunk
// 131,072 pages (> 65,536)
// Head pages hold the chunk header (see start_page); stacks follow.

/*
 *            <--> machine stack + vm stack
 * ----------------------------------
 * |HD...|RZ| ... |RZ| ...   ... |RZ|
 * <------------- 512MB ------------->
 */

static struct nt_stack_chunk_header {
    struct nt_stack_chunk_header *prev_chunk;
    struct nt_stack_chunk_header *prev_free_chunk;
    // prev_free_chunk == NULL cannot double as the membership test: the free
    // list's tail also has it NULL, and re-pushing the tail self-cycles it.
    bool on_free_list;

    uint16_t start_page;
    uint16_t stack_count;
    uint16_t uninitialized_stack_count;

    uint16_t free_stack_pos;
    uint16_t free_stack[];
} *nt_stack_chunks = NULL,
  *nt_free_stack_chunks = NULL;

struct nt_machine_stack_footer {
    struct nt_stack_chunk_header *ch;
    size_t index;
};

static rb_nativethread_lock_t nt_machine_stack_lock = RB_NATIVETHREAD_LOCK_INIT;

// The holder at the fork moment does not exist in the child; start over.
static void
nt_machine_stack_atfork(void)
{
    rb_native_mutex_initialize(&nt_machine_stack_lock);
}

#include <sys/mman.h>

// Page-align the configured sizes: the layout puts a guard page and a
// MAP_FIXED machine stack behind the VM stack, and both must land on page
// boundaries whatever RUBY_THREAD_VM_STACK_SIZE and
// RUBY_THREAD_MACHINE_STACK_SIZE hold (those align only to 4KB).
static inline size_t
nt_vm_stack_area(const rb_vm_t *vm)
{
    return (size_t)roomof(vm->default_params.thread_vm_stack_size, MSTACK_PAGE_SIZE) * MSTACK_PAGE_SIZE;
}

static inline size_t
nt_machine_stack_area(const rb_vm_t *vm)
{
    return (size_t)roomof(vm->default_params.thread_machine_stack_size, MSTACK_PAGE_SIZE) * MSTACK_PAGE_SIZE;
}

// vm stack area + guard page + machine stack area
static inline size_t
nt_thread_stack_size(void)
{
    static size_t msz;
    if (LIKELY(msz > 0)) return msz;

    rb_vm_t *vm = GET_VM();
    msz = nt_vm_stack_area(vm) + MSTACK_PAGE_SIZE + nt_machine_stack_area(vm);
    return msz;
}

static struct nt_stack_chunk_header *
nt_alloc_thread_stack_chunk(void)
{
    const char *m = (void *)mmap(NULL, MSTACK_CHUNK_SIZE, PROT_NONE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    if (m == MAP_FAILED) {
        return NULL;
    }

    ruby_annotate_mmap(m, MSTACK_CHUNK_SIZE, "Ruby:nt_alloc_thread_stack_chunk");

    size_t msz = nt_thread_stack_size();
    int header_page_cnt = 1;
    int stack_count = ((MSTACK_CHUNK_PAGE_NUM - header_page_cnt) * MSTACK_PAGE_SIZE) / msz;
    int ch_size = sizeof(struct nt_stack_chunk_header) + sizeof(uint16_t) * stack_count;

    if (ch_size > MSTACK_PAGE_SIZE * header_page_cnt) {
        header_page_cnt = (ch_size + MSTACK_PAGE_SIZE - 1) / MSTACK_PAGE_SIZE;
        stack_count = ((MSTACK_CHUNK_PAGE_NUM - header_page_cnt) * MSTACK_PAGE_SIZE) / msz;
    }

    VM_ASSERT(stack_count <= UINT16_MAX);

    // Enable read/write for the header pages
    if (mprotect((void *)m, (size_t)header_page_cnt * MSTACK_PAGE_SIZE, PROT_READ | PROT_WRITE) != 0) {
        munmap((void *)m, MSTACK_CHUNK_SIZE);
        return NULL;
    }

    struct nt_stack_chunk_header *ch = (struct nt_stack_chunk_header *)m;

    ch->start_page = header_page_cnt;
    ch->prev_chunk = nt_stack_chunks;
    ch->prev_free_chunk = nt_free_stack_chunks;
    ch->on_free_list = true; // the caller makes it the free-list head
    ch->uninitialized_stack_count = ch->stack_count = (uint16_t)stack_count;
    ch->free_stack_pos = 0;

    RUBY_DEBUG_LOG("ch:%p start_page:%d stack_cnt:%d stack_size:%d", ch, (int)ch->start_page, (int)ch->stack_count, (int)msz);

    return ch;
}

static void *
nt_stack_chunk_get_stack_start(struct nt_stack_chunk_header *ch, size_t idx)
{
    const char *m = (char *)ch;
    return (void *)(m + ch->start_page * MSTACK_PAGE_SIZE + idx * nt_thread_stack_size());
}

static struct nt_machine_stack_footer *
nt_stack_chunk_get_msf(const rb_vm_t *vm, const char *mstack)
{
    // TODO: stack direction
    const size_t msz = vm->default_params.thread_machine_stack_size;
    return (struct nt_machine_stack_footer *)&mstack[msz - sizeof(struct nt_machine_stack_footer)];
}

static void
nt_stack_chunk_get_stack(const rb_vm_t *vm, struct nt_stack_chunk_header *ch, size_t idx, void **vm_stack, void **machine_stack)
{
    // TODO: only support stack going down
    // [VM ... <GUARD> machine stack ...]

    const char *vstack, *mstack;
    const char *guard_page;
    vstack = nt_stack_chunk_get_stack_start(ch, idx);
    guard_page = vstack + nt_vm_stack_area(vm);
    mstack = guard_page + MSTACK_PAGE_SIZE;

    struct nt_machine_stack_footer *msf = nt_stack_chunk_get_msf(vm, mstack);
    msf->ch = ch;
    msf->index = idx;

#if 0
    RUBY_DEBUG_LOG("msf:%p vstack:%p-%p guard_page:%p-%p mstack:%p-%p", msf,
                   vstack, (void *)(guard_page-1),
                   guard_page, (void *)(mstack-1),
                   mstack, (void *)(msf));
#endif

    *vm_stack = (void *)vstack;
    *machine_stack = (void *)mstack;
}

RBIMPL_ATTR_MAYBE_UNUSED()
static void
nt_stack_chunk_dump(void)
{
    struct nt_stack_chunk_header *ch;
    int i;

    fprintf(stderr, "** nt_stack_chunks\n");
    ch = nt_stack_chunks;
    for (i=0; ch; i++, ch = ch->prev_chunk) {
        fprintf(stderr, "%d %p free_pos:%d\n", i, (void *)ch, (int)ch->free_stack_pos);
    }

    fprintf(stderr, "** nt_free_stack_chunks\n");
    ch = nt_free_stack_chunks;
    for (i=0; ch; i++, ch = ch->prev_free_chunk) {
        fprintf(stderr, "%d %p free_pos:%d\n", i, (void *)ch, (int)ch->free_stack_pos);
    }
}

static int
nt_alloc_stack(rb_vm_t *vm, void **vm_stack, void **machine_stack)
{
    int err = 0;

    rb_native_mutex_lock(&nt_machine_stack_lock);
    {
      retry:
        if (nt_free_stack_chunks) {
            struct nt_stack_chunk_header *ch = nt_free_stack_chunks;
            if (ch->free_stack_pos > 0) {
                RUBY_DEBUG_LOG("free_stack_pos:%d", ch->free_stack_pos);
                nt_stack_chunk_get_stack(vm, ch, ch->free_stack[--ch->free_stack_pos], vm_stack, machine_stack);
            }
            else if (ch->uninitialized_stack_count > 0) {
                RUBY_DEBUG_LOG("uninitialized_stack_count:%d", ch->uninitialized_stack_count);

                size_t idx = ch->stack_count - ch->uninitialized_stack_count--;

                // The chunk was mapped PROT_NONE; enable the VM stack and
                // machine stack pages, leaving the guard page as PROT_NONE.
                char *stack_start = nt_stack_chunk_get_stack_start(ch, idx);
                size_t vm_stack_area = nt_vm_stack_area(vm);
                size_t mstack_size = nt_thread_stack_size() - vm_stack_area - MSTACK_PAGE_SIZE;
                char *mstack_start = stack_start + vm_stack_area + MSTACK_PAGE_SIZE;

                int mstack_flags = MAP_FIXED | MAP_ANONYMOUS | MAP_PRIVATE;
#if defined(MAP_STACK) && !defined(__FreeBSD__) && !defined(__FreeBSD_kernel__)
                mstack_flags |= MAP_STACK;
#endif

                if (mprotect(stack_start, vm_stack_area, PROT_READ | PROT_WRITE) != 0 ||
                    mmap(mstack_start, mstack_size, PROT_READ | PROT_WRITE, mstack_flags, -1, 0) == MAP_FAILED) {
                    err = errno;
                    ch->uninitialized_stack_count++; // the slot was not consumed
                }
                else {
                    nt_stack_chunk_get_stack(vm, ch, idx, vm_stack, machine_stack);
                }
            }
            else {
                nt_free_stack_chunks = ch->prev_free_chunk;
                ch->prev_free_chunk = NULL;
                ch->on_free_list = false;
                goto retry;
            }
        }
        else {
            struct nt_stack_chunk_header *p = nt_alloc_thread_stack_chunk();
            if (p == NULL) {
                err = errno;
            }
            else {
                nt_free_stack_chunks = nt_stack_chunks = p;
                goto retry;
            }
        }
    }
    rb_native_mutex_unlock(&nt_machine_stack_lock);

    return err;
}

static void
nt_madvise_free_or_dontneed(void *addr, size_t len)
{
    /* There is no real way to perform error handling here. Both MADV_FREE
     * and MADV_DONTNEED are both documented to pretty much only return EINVAL
     * for a huge variety of errors. It's indistinguishable if madvise fails
     * because the parameters were bad, or because the kernel we're running on
     * does not support the given advice. This kind of free-but-don't-unmap
     * is best-effort anyway, so don't sweat it.
     *
     * n.b. A very common case of "the kernel doesn't support MADV_FREE and
     * returns EINVAL" is running under the `rr` debugger; it makes all
     * MADV_FREE calls return EINVAL. */

#if defined(MADV_FREE)
    int r = madvise(addr, len, MADV_FREE);
    // Return on success, or else try MADV_DONTNEED
    if (r == 0) return;
#endif
#if defined(MADV_DONTNEED)
    madvise(addr, len, MADV_DONTNEED);
#endif
}

static void
nt_free_stack(void *mstack)
{
    if (!mstack) return;

    rb_native_mutex_lock(&nt_machine_stack_lock);
    {
        struct nt_machine_stack_footer *msf = nt_stack_chunk_get_msf(GET_VM(), mstack);
        struct nt_stack_chunk_header *ch = msf->ch;
        int idx = (int)msf->index;
        void *stack = nt_stack_chunk_get_stack_start(ch, idx);

        RUBY_DEBUG_LOG("stack:%p mstack:%p ch:%p index:%d", stack, mstack, ch, idx);

        if (!ch->on_free_list) {
            ch->on_free_list = true;
            ch->prev_free_chunk = nt_free_stack_chunks;
            nt_free_stack_chunks = ch;
        }
        ch->free_stack[ch->free_stack_pos++] = idx;

        // clear the stack pages
        nt_madvise_free_or_dontneed(stack, nt_thread_stack_size());
    }
    rb_native_mutex_unlock(&nt_machine_stack_lock);
}


static int
native_thread_check_and_create_shared(rb_vm_t *vm)
{
    bool need_to_make = false;

    ractor_sched_lock(vm, NULL); // NULL: the timer thread also calls this
    {
        unsigned int schedulable_ractor_cnt = vm->ractor.cnt;
        RUBY_ASSERT(schedulable_ractor_cnt >= 1);

        if (!vm->ractor.main_ractor->threads.sched.enable_mn_threads)
            schedulable_ractor_cnt--; // do not need snt for main ractor

        // CAS keeps a concurrent rejoin from pushing snt_cnt past the cap
        rb_atomic_t snt_cnt = RUBY_ATOMIC_LOAD(vm->ractor.sched.snt_cnt);
        while (((int)snt_cnt < MINIMUM_SNT) ||
               (snt_cnt < schedulable_ractor_cnt  &&
                snt_cnt < vm->ractor.sched.max_cpu)) {
            rb_atomic_t prev = RUBY_ATOMIC_CAS(vm->ractor.sched.snt_cnt, snt_cnt, snt_cnt + 1);
            if (prev == snt_cnt) {
                need_to_make = true;
                break;
            }
            snt_cnt = prev;
        }

        if (need_to_make) {
            RUBY_DEBUG_LOG("added snt:%u dnt:%u ractor_cnt:%u grq_cnt:%u",
                           vm->ractor.sched.snt_cnt,
                           vm->ractor.sched.dnt_cnt,
                           vm->ractor.cnt,
                           vm->ractor.sched.grq_cnt);
        }
        else {
            RUBY_DEBUG_LOG("snt:%d ractor_cnt:%d", (int)vm->ractor.sched.snt_cnt, (int)vm->ractor.cnt);
        }
    }
    ractor_sched_unlock(vm, NULL);

    if (need_to_make) {
        struct rb_native_thread *nt = native_thread_alloc();
        nt->vm = vm;
        int err = native_thread_create0(nt);
        if (err) {
            // Roll back, or this function would conclude forever that the
            // pool is wide enough and never try again.
            ractor_sched_lock(vm, NULL);
            RUBY_ATOMIC_DEC(vm->ractor.sched.snt_cnt);
            ractor_sched_unlock(vm, NULL);
            native_thread_destroy(nt);
        }
        return err;
    }
    else {
        return 0;
    }
}

// A coroutine thread's epilogue, run from thread_start_func_2 while th is
// still valid. Everything that touches th happens here; co_start then only
// makes the final transfer, touching the execution-owned tctx alone.
static void
coroutine_thread_terminated(rb_thread_t *th)
{
    struct rb_thread_context *tctx = (struct rb_thread_context *)th->sched.context;
    struct rb_thread_sched *sched = TH_SCHED(th);
    rb_ractor_t *r = th->ractor;
    bool last = (th->invoke_type == thread_invoke_type_ractor_proc);
    bool is_dnt = th_has_dedicated_nt(th);

    // VM destruct tears down the heap and then unsets ruby_current_vm_ptr;
    // this native thread still frees the dead context afterwards (the nt
    // loop's reclaim uses ruby_xfree and the stack-pool geometry via
    // GET_VM()). Make destruct wait until the reclaim finished. (Observed:
    // an assert_separately child exiting right after a Ractor finished
    // crashed at GET_VM()->default_params, offset 0x2600, on two arches.)
    rb_vm_t *const vm = th->vm; // survives th; the tail below must not read th
    RUBY_ATOMIC_INC(vm->ractor.sched.winding_cnt);

    rb_thread_t *wake_th;
    bool wake_mn = false;

    // Leave the living set here, while th is still barrier-registered and no
    // successor can run: the GC's root scan walks r->threads.set without the
    // Ractor lock, so the unlink must not race with it.  Off the set th would
    // be unreachable although the handoff below keeps using it (and the GC can
    // run: to_dead_common() deregisters th, so no barrier waits for it) --
    // dying_th keeps it marked until its last use.
    VM_ASSERT(sched->running == th); // th owns the slot through the handoff
    if (!last) {
        RUBY_ATOMIC_PTR_SET(r->threads.dying_th, th);
        rb_ractor_living_threads_remove(r, th);
    }

    thread_sched_lock(sched, th);
    {
        // designate the successor (running = next from readyq, or NULL); for
        // a dedicated nt (will_switch false) this also enqueues the Ractor.
        thread_sched_to_dead_common(sched, th);

        // Only the successor WE designated here may be enqueued by this
        // epilogue (below). If readyq was empty, running is now NULL and a
        // waker (e.g. the timer thread) that later installs a runnable
        // thread enqueues the Ractor itself -- enqueuing "whatever is
        // running" at that point would duplicate its entry.
        wake_th = is_dnt ? NULL : sched->running;
        // Read wake_th->nt under the lock: a dedicated successor was already
        // woken by to_dead_common and may die (freeing wake_th) as soon as we
        // unlock.  An M:N successor (nt == NULL) cannot run or be assigned an
        // nt before our enqueue below, so the value cannot go stale.
        wake_mn = (wake_th != NULL && wake_th->nt == NULL);

        tctx->nt = th->nt;        // stash the final transfer target for co_start
        native_thread_assign(NULL, th);
        th->sched.context = NULL; // the wrapper's dfree must not reclaim tctx

        if (!last) {
            // Still under the sched lock: a successor (even a dedicated one
            // woken by to_dead_common) starts by taking it, so it cannot
            // observe or overwrite these until we unlock.  th was last used
            // above and running_ec no longer points into it; now it may be
            // collected.
            rb_ractor_set_current_ec(r, NULL); // r alive: it has other threads
            VM_ASSERT(RUBY_ATOMIC_PTR_LOAD(r->threads.dying_th) == th);
            RUBY_ATOMIC_PTR_SET(r->threads.dying_th, NULL);
        }
    }
    if (last) {
        thread_sched_unlock(sched, th); // th is still on the living set here

        VM_ASSERT(sched->running == NULL);
        VM_ASSERT(wake_th == NULL);
        // Last access to th/r: the removal may unlink the Ractor, after
        // which the GC may collect th and r.
        rb_ractor_living_threads_remove(r, th);
        rb_current_ec_set(NULL); // TLS only; r may be collectable already
    }
    else {
        // th lost its root at the clear above; the plain unlock's debug log
        // would read th->serial.
        thread_sched_unlock_no_log(sched, th);

        if (wake_mn) {
            // enqueue the successor designated above -- exactly once per
            // "runnable but unserved" period, by its designator.
            thread_sched_lock(sched, NULL);
            ractor_sched_enq(vm, r);
            thread_sched_unlock(sched, NULL);
        }
    }
}

#ifdef __APPLE__
# define co_start ruby_coroutine_start
#else
static
#endif
COROUTINE
co_start(struct coroutine_context *from, struct coroutine_context *self)
{
#ifdef RUBY_ASAN_ENABLED
    __sanitizer_finish_switch_fiber(self->fake_stack,
                                    (const void**)&from->stack_base, &from->stack_size);
#endif

    rb_thread_t *th = (rb_thread_t *)self->argument;
    struct rb_thread_sched *sched = TH_SCHED(th);
    VM_ASSERT(th->nt != NULL);
    VM_ASSERT(th == sched->running);
    VM_ASSERT(sched->lock_owner == NULL);

    // RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    thread_sched_set_locked(sched, th);
    thread_sched_add_running_thread(TH_SCHED(th), th);
    thread_sched_unlock(sched, th);
    {
        RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_RESUMED, th);
        call_thread_start_func_2(th);
    }
    // Thread is terminated. coroutine_thread_terminated (run from
    // thread_start_func_2 while th was still valid) already left the living
    // set and stashed the transfer target, so th / its Ractor may already be
    // collected. Only tctx is touched here: mark it dead and transfer back to
    // this native thread's own context, where the nt loop reclaims tctx.
    struct rb_thread_context *tctx = (struct rb_thread_context *)self;
    tctx->dead = true;
    // Hand this context to the nt's loop, which reclaims it right after the
    // final transfer returns from switch0.
    tctx->nt->dead_co = &tctx->co;
    coroutine_transfer0(&tctx->co, tctx->nt->nt_context, true);

    rb_bug("unreachable");
}

static int
native_thread_create_shared(rb_thread_t *th)
{
    // setup coroutine
    rb_vm_t *vm = th->vm;
    void *vm_stack = NULL, *machine_stack = NULL;
    int err = nt_alloc_stack(vm, &vm_stack, &machine_stack);
    if (err) return err;

    VM_ASSERT(vm_stack < machine_stack);

    // setup vm stack
    size_t vm_stack_words = th->vm->default_params.thread_vm_stack_size/sizeof(VALUE);
    rb_ec_initialize_vm_stack(th->ec, vm_stack, vm_stack_words);

    // setup machine stack
    size_t machine_stack_size = vm->default_params.thread_machine_stack_size - sizeof(struct nt_machine_stack_footer);
    th->ec->machine.stack_start = (void *)((uintptr_t)machine_stack + machine_stack_size);
    th->ec->machine.stack_maxsize = machine_stack_size; // TODO
    th->sched.context_stack = machine_stack;
    th->sched.context_stack_size = machine_stack_size;

    struct rb_thread_context *tctx = ruby_xmalloc(sizeof(struct rb_thread_context));
    tctx->stack = machine_stack;
    tctx->dead = false;
    tctx->nt = NULL;
    th->sched.context = &tctx->co;
    coroutine_initialize(&tctx->co, co_start, machine_stack, machine_stack_size);
    tctx->co.argument = th;

    RUBY_DEBUG_LOG("th:%u vm_stack:%p machine_stack:%p", rb_th_serial(th), vm_stack, machine_stack);

    // Widen the pool before publishing th.  Once ready, a Ractor's thread that
    // runs to its end frees its own rb_thread_t (rb_ractor_postmortem_free),
    // and the caller's create-failure path assumes th never became runnable.
    int create_err = native_thread_check_and_create_shared(vm);
    if (create_err) return create_err;

    thread_sched_to_ready(TH_SCHED(th), th);
    return 0;
}

/// EPOLL/KQUEUE specific code
#if HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H

/// Per-fd waiter table (struct rb_fd_waiters).  One fd may have several waiters
/// -- a reader and a writer on one socket -- so the backend is armed with their
/// union, and an event is dispatched to every waiter it concerns.

// (FD_WAIT_IO_MASK and the fd shard helpers are defined near the top.)

#define FDMAP_CHUNK_BITS 10
#define FDMAP_CHUNK_SIZE (1u << FDMAP_CHUNK_BITS)
#define FDMAP_CHUNK_MASK (FDMAP_CHUNK_SIZE - 1)

// Callable under any fd shard lock: a chunk spans every shard, so the chunk
// table is not guarded by them; slots install by CAS and are never freed.
static struct rb_fd_waiters *
fd_waiters_lookup(int fd, bool create)
{
    if (fd < 0) return NULL;

    unsigned int ci = (unsigned int)fd >> FDMAP_CHUNK_BITS;
    if (ci >= FDMAP_MAX_CHUNKS) return NULL; // the caller falls back to a blocking wait

    struct rb_fd_waiters *chunk = RUBY_ATOMIC_PTR_LOAD(timer_th.fdmap_chunks[ci]);

    if (chunk == NULL) {
        if (!create) return NULL;

        chunk = calloc(FDMAP_CHUNK_SIZE, sizeof(*chunk));
        if (chunk == NULL) rb_bug("fd_waiters_lookup: calloc failed");

        for (unsigned int i = 0; i < FDMAP_CHUNK_SIZE; i++) {
            ccan_list_head_init(&chunk[i].waiters);
        }

        struct rb_fd_waiters *prev = RUBY_ATOMIC_PTR_CAS(timer_th.fdmap_chunks[ci], NULL, chunk);
        if (prev != NULL) {
            free(chunk); // another shard installed it first
            chunk = prev;
        }
    }

    return &chunk[(unsigned int)fd & FDMAP_CHUNK_MASK];
}

// The fd's shard lock must be held.
static uint32_t
fd_waiters_union(struct rb_fd_waiters *e)
{
    uint32_t want = 0;
    struct rb_thread_sched_waiting *w;

    ccan_list_for_each(&e->waiters, w, fd_node) {
        want |= (uint32_t)(w->flags & FD_WAIT_IO_MASK);
    }
    return want;
}

// Events name an fd and the generation it was armed with, never a thread: a
// stale event then resolves to a table lookup instead of a freed thread.
static inline uint64_t
fd_event_tag(int fd, uint32_t generation)
{
    return ((uint64_t)generation << 32) | (uint32_t)fd;
}

#define FD_EVENT_TAG_FD(tag)  ((int)((tag) & 0xffffffffu))
#define FD_EVENT_TAG_GEN(tag) ((uint32_t)((tag) >> 32))

// Make the backend match `want`.  Returns false if the fd cannot be registered
// at all (closed, or unsupported by the backend), leaving the entry untouched.
// The fd's shard lock must be held.  `consumed` says an epoll event for the
// current arming was just delivered, so EPOLLONESHOT has already disarmed it.
static bool
fd_waiters_arm(int fd, struct rb_fd_waiters *e, uint32_t want, bool consumed)
{
    // After a delivery the kernel side is disarmed even when the flags agree,
    // so a consumed call must fall through to re-arm.
    if (want == e->armed_flags && !consumed) return true;

#if HAVE_SYS_EVENT_H
    struct kevent ke[2];
    int n = 0;
    uint32_t add = want & ~e->armed_flags;
    uint32_t del = e->armed_flags & ~want;
    void *tag = (void *)(uintptr_t)fd_event_tag(fd, e->generation);

    if (del & thread_sched_waiting_io_read)  { EV_SET(&ke[n], fd, EVFILT_READ,  EV_DELETE, 0, 0, NULL); n++; }
    if (del & thread_sched_waiting_io_write) { EV_SET(&ke[n], fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL); n++; }

    if (n > 0 && kevent(timer_th.event_fd, ke, n, NULL, 0, NULL) == -1) {
        // The fd may already be gone; that is not an error for a removal.
        if (errno != ENOENT && errno != EBADF) {
            perror("kevent");
            rb_bug("fd_waiters_arm/kevent delete failed (fd:%d errno:%d)", fd, errno);
        }
    }

    n = 0;
    if (add & thread_sched_waiting_io_read)  { EV_SET(&ke[n], fd, EVFILT_READ,  EV_ADD, 0, 0, tag); n++; }
    if (add & thread_sched_waiting_io_write) { EV_SET(&ke[n], fd, EVFILT_WRITE, EV_ADD, 0, 0, tag); n++; }

    if (n > 0 && kevent(timer_th.event_fd, ke, n, NULL, 0, NULL) == -1) {
        switch (errno) {
          case EBADF:
          case EINVAL:
            return false;
          default:
            perror("kevent");
            rb_bug("fd_waiters_arm/kevent add failed (fd:%d errno:%d)", fd, errno);
        }
    }
#elif HAVE_SYS_EPOLL_H
    if (want == 0) {
        // A delivered oneshot event has already disarmed the fd; otherwise
        // disarm by MOD to no events.  Either way the registration stays, so
        // the next wait is one MOD instead of DEL + ADD.
        if (!consumed && e->registered) {
            struct epoll_event off = { .events = 0, .data = { .u64 = 0 } };
            if (epoll_ctl(timer_th.event_fd, EPOLL_CTL_MOD, fd, &off) == -1) {
                switch (errno) {
                  case EBADF:
                  case ENOENT:
                    // the fd is already closed or gone from the set
                    e->registered = false;
                    break;
                  default:
                    perror("epoll_ctl");
                    rb_bug("fd_waiters_arm/epoll_ctl disarm failed (fd:%d errno:%d)", fd, errno);
                }
            }
        }
        // Anything epoll_wait already queued for the old arming is stale now.
        e->generation++;
        e->armed_flags = 0;
        return true;
    }

    uint32_t epoll_events = EPOLLONESHOT;
    if (want & thread_sched_waiting_io_read)  epoll_events |= EPOLLIN;
    if (want & thread_sched_waiting_io_write) epoll_events |= EPOLLOUT;

    struct epoll_event event = {
        .events = epoll_events,
        .data = { .u64 = fd_event_tag(fd, e->generation) },
    };

    int op = e->registered ? EPOLL_CTL_MOD : EPOLL_CTL_ADD;

    if (epoll_ctl(timer_th.event_fd, op, fd, &event) == -1) {
        switch (errno) {
          case ENOENT:
            // Not registered after all: the fd was closed and reopened. Add it.
            if (op == EPOLL_CTL_MOD &&
                epoll_ctl(timer_th.event_fd, EPOLL_CTL_ADD, fd, &event) == 0) {
                break;
            }
            e->registered = false;
            return false;
          case EEXIST:
            // Likewise in the other direction.
            if (op == EPOLL_CTL_ADD &&
                epoll_ctl(timer_th.event_fd, EPOLL_CTL_MOD, fd, &event) == 0) {
                break;
            }
            return false;
          case EBADF:
          case EPERM:
            // closed, or the fd does not support epoll
            e->registered = false;
            return false;
          default:
            perror("epoll_ctl");
            rb_bug("fd_waiters_arm/epoll_ctl failed (fd:%d op:%d errno:%d)", fd, op, errno);
        }
    }
    e->registered = true;
#else
# error "neither kqueue nor epoll"
#endif

    e->armed_flags = want;
    return true;
}

static bool
fd_readable_nonblock(int fd)
{
    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN,
    };
    return poll(&pfd, 1, 0) != 0;
}

static bool
fd_writable_nonblock(int fd)
{
    struct pollfd pfd = {
        .fd = fd,
        .events = POLLOUT,
    };
    return poll(&pfd, 1, 0) != 0;
}

static void
verify_waiting_list(void)
{
#if VM_CHECK_MODE > 0
    struct rb_thread_sched_waiting *w;

    for (int lvl = 0; lvl < TIMER_WHEEL_LEVELS; lvl++) {
        const struct timer_wheel_level *lv = &timer_th.wheel[lvl];

        for (int slot = 0; slot < TIMER_WHEEL_SLOTS; slot++) {
            bool occupied = (lv->occupied >> slot) & 1;
            VM_ASSERT(occupied == !ccan_list_empty(&lv->slots[slot]));

            ccan_list_for_each(&lv->slots[slot], w, node) {
                // an io entry's flags belong to its fd shard: do not read them here
                if (!(w->flags & FD_WAIT_IO_MASK)) {
                    VM_ASSERT(w->flags & thread_sched_waiting_timeout);
                    VM_ASSERT(w->data.timeout != 0);
                }
                VM_ASSERT(w->wheel_lvl == lvl);
                VM_ASSERT(w->wheel_slot == slot);
            }
        }
    }
#endif
}

/* ------------------------------------------------------------------------
 * backend: the readiness notification mechanism (epoll / kqueue).
 *
 * Everything below that names epoll or kqueue is this backend; the rest of
 * the M:N scheduler only asks it to arm an fd (fd_waiters_arm) and to wait
 * for what fired (event_wait / timer_thread_polling).
 * ------------------------------------------------------------------------ */

#if HAVE_SYS_EVENT_H // kqueue helpers

static enum thread_sched_waiting_flag
kqueue_translate_filter_to_flags(int16_t filter)
{
    switch (filter) {
      case EVFILT_READ:
        return thread_sched_waiting_io_read;
      case EVFILT_WRITE:
        return thread_sched_waiting_io_write;
      case EVFILT_TIMER:
        return thread_sched_waiting_timeout;
      default:
        rb_bug("kevent filter:%d not supported", filter);
    }
}

static int
kqueue_wait(rb_vm_t *vm)
{
    struct timespec calculated_timeout;
    struct timespec *timeout = NULL;
    int timeout_ms = timer_thread_set_timeout(vm);

    if (timeout_ms > 0) {
        calculated_timeout.tv_sec = timeout_ms / 1000;
        calculated_timeout.tv_nsec = (timeout_ms % 1000) * 1000000;
        timeout = &calculated_timeout;
    }
    else if (timeout_ms == 0) {
        // Relying on the absence of other members of struct timespec is not strictly portable,
        // and kevent needs a 0-valued timespec to mean immediate timeout.
        memset(&calculated_timeout, 0, sizeof(struct timespec));
        timeout = &calculated_timeout;
    }

    return kevent(timer_th.event_fd, NULL, 0, timer_th.finished_events, KQUEUE_EVENTS_MAX, timeout);
}

static void
kqueue_create(void)
{
    if ((timer_th.event_fd = kqueue()) == -1) rb_bug("kqueue creation failed (errno:%d)", errno);
    int flags = fcntl(timer_th.event_fd, F_GETFD);
    if (flags == -1) {
        rb_bug("kqueue GETFD failed (errno:%d)", errno);
    }

    flags |= FD_CLOEXEC;
    if (fcntl(timer_th.event_fd, F_SETFD, flags) == -1) {
        rb_bug("kqueue SETFD failed (errno:%d)", errno);
    }
}

#endif // HAVE_SYS_EVENT_H

// return false if the fd is not waitable or not need to wait.
static enum timer_thread_register_result
timer_thread_register_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags, rb_hrtime_t *rel, uint32_t event_serial)
{
    RUBY_DEBUG_LOG("th:%u fd:%d flag:%d rel:%lu", rb_th_serial(th), fd, flags, rel ? (unsigned long)*rel : 0);

    VM_ASSERT(th == NULL || TH_SCHED(th)->running == th);
    VM_ASSERT(flags != 0);

    rb_hrtime_t abs = 0; // 0 means no timeout

    if (rel) {
        if (*rel > 0) {
            flags |= thread_sched_waiting_timeout;
        }
        else {
            return timer_thread_already_ready; // zero timeout: nothing to wait for
        }
    }

    if (flags & thread_sched_waiting_timeout) {
        VM_ASSERT(rel != NULL);
        abs = rb_hrtime_add(rb_hrtime_now(), *rel);
    }

    if (flags & thread_sched_waiting_io_read) {
        if (!(flags & thread_sched_waiting_io_force) && fd_readable_nonblock(fd)) {
            RUBY_DEBUG_LOG("fd_readable_nonblock");
            return timer_thread_already_ready;
        }
        VM_ASSERT(fd >= 0);
    }

    if (flags & thread_sched_waiting_io_write) {
        if (!(flags & thread_sched_waiting_io_force) && fd_writable_nonblock(fd)) {
            RUBY_DEBUG_LOG("fd_writable_nonblock");
            return timer_thread_already_ready;
        }
        VM_ASSERT(fd >= 0);
    }

    if (flags & FD_WAIT_IO_MASK) {
        fd_shard_lock(fd);
        {
            struct rb_fd_waiters *e = fd_waiters_lookup(fd, true);

            if (e == NULL) { // fd beyond the map: fall back to a blocking wait
                fd_shard_unlock(fd);
                return timer_thread_unavailable;
            }

            // Arm the union of what this fd's waiters want, so a second waiter
            // on the same fd extends the arming instead of colliding with it.
            if (!fd_waiters_arm(fd, e, fd_waiters_union(e) | (uint32_t)(flags & FD_WAIT_IO_MASK), false)) {
                fd_shard_unlock(fd);
                return timer_thread_unavailable;
            }

            if (th) {
                ccan_list_add_tail(&e->waiters, &th->sched.waiting_reason.fd_node);

                VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);
                th->sched.waiting_reason.flags = flags;
                th->sched.waiting_reason.data.timeout = abs;
                th->sched.waiting_reason.data.fd = fd;
                th->sched.waiting_reason.data.result = 0;
                th->sched.waiting_reason.data.event_serial = event_serial;

                if (abs != 0) {
                    RUBY_DEBUG_LOG("abs:%lu", (unsigned long)abs);
                    VM_ASSERT(flags & thread_sched_waiting_timeout);

                    rb_native_mutex_lock(&timer_th.waiting_lock);
                    {
                        rb_hrtime_t prev_expiry = timer_th.next_expiry;
                        timer_wheel_insert(&th->sched.waiting_reason);
                        verify_waiting_list();
                        if (timer_th.next_expiry < prev_expiry) {
                            // an earlier deadline than the timer thread is armed for
                            timer_thread_wakeup_force();
                        }
                    }
                    rb_native_mutex_unlock(&timer_th.waiting_lock);
                }
            }
            RUBY_DEBUG_LOG("armed fd:%d want:%u", fd, e->armed_flags);
        }
        fd_shard_unlock(fd);
    }
    else if (th) {
        // fd-less timed wait: the wheel lock owns it end to end
        VM_ASSERT(abs != 0 && (flags & thread_sched_waiting_timeout));

        rb_native_mutex_lock(&timer_th.waiting_lock);
        {
            VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);
            th->sched.waiting_reason.flags = flags;
            th->sched.waiting_reason.data.timeout = abs;
            th->sched.waiting_reason.data.fd = fd;
            th->sched.waiting_reason.data.result = 0;
            th->sched.waiting_reason.data.event_serial = event_serial;

            rb_hrtime_t prev_expiry = timer_th.next_expiry;
            timer_wheel_insert(&th->sched.waiting_reason);
            verify_waiting_list();
            if (timer_th.next_expiry < prev_expiry) {
                timer_thread_wakeup_force();
            }
        }
        rb_native_mutex_unlock(&timer_th.waiting_lock);
    }
    else {
        VM_ASSERT(abs == 0);
    }

    return timer_thread_registered;
}

// Drop `th` from its fd's waiter list and re-arm the backend for whoever is
// left.  The fd's shard lock must be held.
static void
timer_thread_unregister_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags)
{
    if (!(th->sched.waiting_reason.flags & FD_WAIT_IO_MASK)) {
        return;
    }

    RUBY_DEBUG_LOG("th:%u fd:%d", rb_th_serial(th), fd);

    ccan_list_del_init(&th->sched.waiting_reason.fd_node);

    struct rb_fd_waiters *e = fd_waiters_lookup(fd, false);
    if (e) {
        fd_waiters_arm(fd, e, fd_waiters_union(e), false);
    }
}

// The timer thread's own wakeup pipe has no waiter: it stays armed forever and
// is recognised by its fd when an event arrives.
static void
timer_thread_arm_comm_pipe(void)
{
    int fd = timer_th.comm_fds[0];

#if HAVE_SYS_EVENT_H
    struct kevent ke;
    EV_SET(&ke, fd, EVFILT_READ, EV_ADD, 0, 0, (void *)(uintptr_t)fd_event_tag(fd, 0));
    if (kevent(timer_th.event_fd, &ke, 1, NULL, 0, NULL) == -1) {
        rb_bug("timer_thread_arm_comm_pipe/kevent failed (errno:%d)", errno);
    }
#elif HAVE_SYS_EPOLL_H
    struct epoll_event event = {
        .events = EPOLLIN,
        .data = { .u64 = fd_event_tag(fd, 0) },
    };
    if (epoll_ctl(timer_th.event_fd, EPOLL_CTL_ADD, fd, &event) == -1) {
        rb_bug("timer_thread_arm_comm_pipe/epoll_ctl failed (errno:%d)", errno);
    }
#else
# error "neither kqueue nor epoll"
#endif
}

static void
timer_thread_setup_mn(void)
{
#if HAVE_SYS_EVENT_H
    kqueue_create();
    RUBY_DEBUG_LOG("kqueue_fd:%d", timer_th.event_fd);
#else
    if ((timer_th.event_fd = epoll_create1(EPOLL_CLOEXEC)) == -1) rb_bug("epoll_create (errno:%d)", errno);
    RUBY_DEBUG_LOG("epoll_fd:%d", timer_th.event_fd);
#endif
    RUBY_DEBUG_LOG("comm_fds:%d/%d", timer_th.comm_fds[0], timer_th.comm_fds[1]);

    timer_thread_arm_comm_pipe();
}

static int
event_wait(rb_vm_t *vm)
{
#if HAVE_SYS_EVENT_H
    int r = kqueue_wait(vm);
#else
    int r = epoll_wait(timer_th.event_fd, timer_th.finished_events, EPOLL_EVENTS_MAX, timer_thread_set_timeout(vm));
#endif
    return r;
}

// How many waiters one pass may unlink before it stops holding waiting_lock.
#define FD_WAKE_BATCH 16


// Deliver an fd event to every thread waiting for it.  Waiters are unlinked
// under waiting_lock but woken after releasing it (the scheduler lock is taken
// before it, never after); event_serial, captured under the lock, guards them.
static void
timer_thread_wake_fd_waiters(int fd, uint32_t generation, uint32_t wake_flags, int result)
{
    struct timer_wake batch[FD_WAKE_BATCH];

    if (wake_flags == 0) return;

    while (1) {
        int n = 0;
        bool more = false;

        fd_shard_lock(fd);
        {
            struct rb_fd_waiters *e = fd_waiters_lookup(fd, false);

            // A newer generation means the fd was disarmed after this event was
            // queued, and the number may name a different file by now.
            if (e != NULL && e->generation == generation) {
                struct rb_thread_sched_waiting *w, *nxt;

                ccan_list_for_each_safe(&e->waiters, w, nxt, fd_node) {
                    if (!(w->flags & wake_flags)) continue;

                    if (n == FD_WAKE_BATCH) {
                        more = true;
                        break;
                    }

                    ccan_list_del_init(&w->fd_node);

                    if (w->flags & thread_sched_waiting_timeout) {
                        // also leaves the timer wheel (or the expiry pass's
                        // batch, whose claim will then find the flags gone)
                        rb_native_mutex_lock(&timer_th.waiting_lock);
                        timer_wheel_del(w);
                        rb_native_mutex_unlock(&timer_th.waiting_lock);
                    }

                    // The pin must be visible before the flags clear: a waiter
                    // that sees the clear may skip parking, finish and die,
                    // and the fence only waits on the pending count.
                    batch[n].th = thread_sched_waiting_thread(w);
                    batch[n].serial = w->data.event_serial;
                    timer_wake_pending_inc(batch[n].th);
                    n++;

                    w->flags = thread_sched_waiting_none;
                    w->data.fd = -1;
                    w->data.result = result;
                }

                // Re-arm for whoever is still waiting on this fd (nothing, if
                // they all just woke up).
                fd_waiters_arm(fd, e, fd_waiters_union(e), true);
            }
        }
        fd_shard_unlock(fd);

        for (int i = 0; i < n; i++) {
            timer_thread_wakeup_thread(batch[i].th, batch[i].serial);
        }
        timer_wake_pending_clear(batch, n);

        if (!more) break;
    }
}

/*
 * The purpose of the timer thread:
 *
 * (1) Periodic checking
 *   (1-1) Provide time slice for active NTs
 *   (1-2) Check NT shortage
 *   (1-3) Periodic UBF (global)
 *   (1-4) Lazy GRQ deq start
 * (2) Receive notification
 *   (2-1) async I/O termination
 *   (2-2) timeout
 *     (2-2-1) sleep(n)
 *     (2-2-2) timeout(n), I/O, ...
 */
static void
timer_thread_polling(rb_vm_t *vm)
{
    int r = event_wait(vm);

    RUBY_DEBUG_LOG("r:%d errno:%d", r, errno);

    switch (r) {
      case 0: // timeout
        RUBY_DEBUG_LOG("timeout%s", "");

        ractor_sched_lock(vm, NULL);
        {
            // (1-1) timeslice
            timer_thread_check_timeslice(vm);

            // (1-4) lazy grq deq
            if (vm->ractor.sched.grq_cnt > 0) {
                RUBY_DEBUG_LOG("GRQ cnt: %u", vm->ractor.sched.grq_cnt);
                rb_native_cond_signal(&vm->ractor.sched.cond);
            }
        }
        ractor_sched_unlock(vm, NULL);

        // (1-2)
        native_thread_check_and_create_shared(vm);

        break;

      case -1:
        switch (errno) {
          case EINTR:
            // simply retry
            break;
          default:
            perror("event_wait");
            rb_bug("event_wait errno:%d", errno);
        }
        break;

      default:
        RUBY_DEBUG_LOG("%d event(s)", r);

#if HAVE_SYS_EVENT_H
        for (int i=0; i<r; i++) {
            uint64_t tag = (uint64_t)(uintptr_t)timer_th.finished_events[i].udata;
            int fd = (int)timer_th.finished_events[i].ident;
            int16_t filter = timer_th.finished_events[i].filter;

            if (fd == timer_th.comm_fds[0]) {
                RUBY_DEBUG_LOG("comm from fd:%d", timer_th.comm_fds[1]);
                consume_communication_pipe(timer_th.comm_fds[0]);
                continue;
            }

            uint32_t wake_flags = kqueue_translate_filter_to_flags(filter) & FD_WAIT_IO_MASK;
            if (timer_th.finished_events[i].flags & (EV_EOF | EV_ERROR)) {
                wake_flags = FD_WAIT_IO_MASK; // end of file or error concerns everyone
            }

            timer_thread_wake_fd_waiters(fd, FD_EVENT_TAG_GEN(tag), wake_flags, filter);
        }
#elif HAVE_SYS_EPOLL_H
        for (int i=0; i<r; i++) {
            uint64_t tag = timer_th.finished_events[i].data.u64;
            int fd = FD_EVENT_TAG_FD(tag);
            uint32_t events = timer_th.finished_events[i].events;

            if (fd == timer_th.comm_fds[0]) {
                RUBY_DEBUG_LOG("comm from fd:%d", timer_th.comm_fds[1]);
                consume_communication_pipe(timer_th.comm_fds[0]);
                continue;
            }

            RUBY_DEBUG_LOG("io event. fd:%d event:%s%s%s%s%s%s", fd,
                           (events & EPOLLIN)    ? "in/" : "",
                           (events & EPOLLOUT)   ? "out/" : "",
                           (events & EPOLLRDHUP) ? "RDHUP/" : "",
                           (events & EPOLLPRI)   ? "pri/" : "",
                           (events & EPOLLERR)   ? "err/" : "",
                           (events & EPOLLHUP)   ? "hup/" : "");

            uint32_t wake_flags = 0;
            if (events & (EPOLLIN | EPOLLPRI | EPOLLRDHUP)) wake_flags |= thread_sched_waiting_io_read;
            if (events & EPOLLOUT)                          wake_flags |= thread_sched_waiting_io_write;
            // An error or hangup ends every wait on this fd, in either direction.
            if (events & (EPOLLERR | EPOLLHUP))             wake_flags |= FD_WAIT_IO_MASK;

            timer_thread_wake_fd_waiters(fd, FD_EVENT_TAG_GEN(tag), wake_flags, (int)events);
        }
#else
# error "neither kqueue nor epoll"
#endif
    }
}

#endif // HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H

#else // USE_MN_THREADS

static void
timer_thread_setup_mn(void)
{
    // do nothing
}

static void
timer_thread_polling(rb_vm_t *vm)
{
    int timeout = timer_thread_set_timeout(vm);

    struct pollfd pfd = {
        .fd = timer_th.comm_fds[0],
        .events = POLLIN,
    };

    int r = poll(&pfd, 1, timeout);

    switch (r) {
      case 0: // timeout
        ractor_sched_lock(vm, NULL);
        {
            // (1-1) timeslice
            timer_thread_check_timeslice(vm);
        }
        ractor_sched_unlock(vm, NULL);
        break;

      case -1: // error
        switch (errno) {
          case EINTR:
            // simply retry
            break;
          default:
            perror("poll");
            rb_bug("poll errno:%d", errno);
            break;
        }

      case 1:
        consume_communication_pipe(timer_th.comm_fds[0]);
        break;

      default:
        rb_bug("unreachbale");
    }
}

static int
native_thread_create_shared(rb_thread_t *th)
{
    rb_bug("unreachable");
}

static enum thread_sched_wait_result
thread_sched_wait_events(struct rb_thread_sched *sched, rb_thread_t *th, int fd, enum thread_sched_waiting_flag events, rb_hrtime_t *rel)
{
    rb_bug("unreachable");
}

// Without the wheel every thread is dedicated, so a Ractor wait takes its
// deadline on its own condvar and never reaches these.
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

#endif // USE_MN_THREADS
