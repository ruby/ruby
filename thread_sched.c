/* -*-c-*- */
/**********************************************************************

  thread_sched.c - platform independent thread/ractor scheduler

  This file is #included from thread.c.  It pulls in the platform
  implementation (THREAD_IMPL_SRC: thread_pthread.c or thread_win32.c)
  first, then builds the scheduler on top of the primitives that file
  provides.  It implements:

    - the per-Ractor thread scheduler (GVL): struct rb_thread_sched
    - the Ractor scheduler: global ready queue (grq) and the VM barrier
    - the native thread (NT) main loop
    - the timer thread main loop and time slice management
    - the unblocking function (UBF) list

  See thread_sched.h for the data structures and for the primitives the
  platform layer has to supply.

**********************************************************************/

/* ------------------------------------------------------------------------
 * The scheduler <-> platform contract.
 *
 * The platform implementation is included below, ahead of the scheduler
 * body, so it can use every primitive it defines without declaring them.
 * The traffic in the other direction -- the scheduler entry points the
 * platform layer (and the M:N scheduler it includes) calls back into --
 * has to be declared here instead.
 * ------------------------------------------------------------------------ */

#define thread_sched_dump(s) thread_sched_dump_(__FILE__, __LINE__, s)
#define ractor_sched_dump(s) ractor_sched_dump_(__FILE__, __LINE__, s)

#define thread_sched_lock(a, b) thread_sched_lock_(a, b, __FILE__, __LINE__)
#define thread_sched_unlock(a, b) thread_sched_unlock_(a, b, __FILE__, __LINE__)
#define ractor_sched_lock(a, b) ractor_sched_lock_(a, b, __FILE__, __LINE__)
#define ractor_sched_unlock(a, b) ractor_sched_unlock_(a, b, __FILE__, __LINE__)

#ifndef MINIMUM_SNT
// make at least MINIMUM_SNT snts for debug.
#define MINIMUM_SNT 0
#endif

struct coroutine_context;

#include "probes.h"

// thread.c
static void threadptr_trap_interrupt(rb_thread_t *);

// thread scheduler (GVL)
static void thread_sched_to_running(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_to_waiting(struct rb_thread_sched *sched, rb_thread_t *th, bool yield_immediately);
static void thread_sched_switch(rb_thread_t *cth, rb_thread_t *next_th);
static void coroutine_transfer0(struct coroutine_context *transfer_from,
                                struct coroutine_context *transfer_to, bool to_dead);
static void thread_sched_lock_(struct rb_thread_sched *sched, rb_thread_t *th, const char *file, int line);
static void thread_sched_unlock_(struct rb_thread_sched *sched, rb_thread_t *th, const char *file, int line);
static void thread_sched_unlock_no_log(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_set_locked(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_setup_running_threads(struct rb_thread_sched *sched, rb_ractor_t *cr, rb_vm_t *vm,
                                               rb_thread_t *add_th, rb_thread_t *del_th);
static void thread_sched_add_running_thread(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_to_ready(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_to_ready_common(struct rb_thread_sched *sched, rb_thread_t *th, bool wakeup, bool will_switch);
static void thread_sched_to_dead_common(struct rb_thread_sched *sched, rb_thread_t *th);
static void thread_sched_to_waiting_until_wakeup(struct rb_thread_sched *sched, rb_thread_t *th, const rb_hrtime_t *end);
static void thread_sched_wait_running_turn(struct rb_thread_sched *sched, rb_thread_t *th, bool can_direct_transfer, const rb_hrtime_t *end);
static void thread_sched_wakeup_next_thread(struct rb_thread_sched *sched, rb_thread_t *th, bool will_switch);

// native thread <-> ractor assignment
static void native_thread_dedicated_inc(rb_vm_t *vm, rb_ractor_t *cr, struct rb_native_thread *nt);
static void native_thread_dedicated_dec(rb_vm_t *vm, rb_ractor_t *cr, struct rb_native_thread *nt);
static void native_thread_assign(struct rb_native_thread *nt, rb_thread_t *th);

// ractor scheduler
static void ractor_sched_lock_(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);
static void ractor_sched_unlock_(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);
static void ractor_sched_enq(rb_vm_t *vm, rb_ractor_t *r);
static void ractor_sched_cancel_enq(rb_vm_t *vm, struct rb_thread_sched *sched);

// VM wide scheduler state; the platform's Init_native_thread() calls this
static void thread_sched_init_vm(rb_vm_t *vm);

// implemented by the M:N scheduler (thread_sched_mn.c) or stubbed out
static bool ractor_sched_timeout_arm(rb_thread_t *th, const rb_hrtime_t *rel);
static bool ractor_sched_timeout_disarm(rb_thread_t *th);
static void timer_thread_wake_fence(struct rb_thread_struct *th);

// unblocking function (UBF)
static bool ubf_set(rb_thread_t *th, rb_unblock_function_t *func, void *arg, rb_atomic_t *event_serial);
static void ubf_clear(rb_thread_t *th, bool clear_serial);

// native thread main loops
static void call_thread_start_func_2(rb_thread_t *th);
static void *nt_start(void *ptr);

// timer thread
static void *timer_thread_func(void *ptr);
static int timer_thread_set_timeout(rb_vm_t *vm);
static void timer_thread_check_timeslice(rb_vm_t *vm);
static bool timeslice_scan(rb_vm_t *vm, bool interrupt);
static void timer_thread_wakeup(void);
static void timer_thread_wakeup_locked(rb_vm_t *vm);
static void timer_thread_wakeup_force(void);

#include THREAD_IMPL_SRC

// Defaults for what the platform above did not opt out of.

#ifndef RB_NATIVE_MUTEX_TRYLOCK_DETECTS_SELF
// Whether rb_native_mutex_trylock() reports EBUSY when the calling thread is
// itself the owner.  A recursive lock (a Windows CRITICAL_SECTION) grants it
// again instead, so it cannot back a "somebody holds this" assertion.
#define RB_NATIVE_MUTEX_TRYLOCK_DETECTS_SELF 1
#endif

/* ------------------------------------------------------------------------
 * The scheduler itself.
 * ------------------------------------------------------------------------ */

static bool
th_has_dedicated_nt(const rb_thread_t *th)
{
    // TODO: th->has_dedicated_nt
    return th->nt->dedicated > 0;
}

RBIMPL_ATTR_MAYBE_UNUSED()
static void
thread_sched_dump_(const char *file, int line, struct rb_thread_sched *sched)
{
    fprintf(stderr, "@%s:%d running:%d\n", file, line, sched->running ? (int)sched->running->serial : -1);
    rb_thread_t *th;
    int i = 0;
    ccan_list_for_each(&sched->readyq, th, sched.node.readyq) {
        i++; if (i>10) rb_bug("too many");
        fprintf(stderr, "  ready:%d (%sNT:%d)\n", th->serial,
                th->nt ? (th->nt->dedicated ? "D" : "S") : "x",
                th->nt ? (int)th->nt->serial : -1);
    }
}


RBIMPL_ATTR_MAYBE_UNUSED()
static void
ractor_sched_dump_(const char *file, int line, rb_vm_t *vm)
{
    rb_ractor_t *r;

    fprintf(stderr, "ractor_sched_dump %s:%d\n", file, line);

    int i = 0;
    ccan_list_for_each(&vm->ractor.sched.grq, r, threads.sched.grq_node) {
        i++;
        if (i>10) rb_bug("!!");
        fprintf(stderr, "  %d ready:%d\n", i, rb_ractor_id(r));
    }
}


static void
thread_sched_set_locked(struct rb_thread_sched *sched, rb_thread_t *th)
{
#if VM_CHECK_MODE > 0
    VM_ASSERT(sched->lock_owner == NULL);

    sched->lock_owner = th;
#endif
}

static void
thread_sched_set_unlocked(struct rb_thread_sched *sched, rb_thread_t *th)
{
#if VM_CHECK_MODE > 0
    VM_ASSERT(sched->lock_owner == th);

    sched->lock_owner = NULL;
#endif
}

static void
thread_sched_lock_(struct rb_thread_sched *sched, rb_thread_t *th, const char *file, int line)
{
    rb_native_mutex_lock(&sched->lock_);

#if VM_CHECK_MODE
    RUBY_DEBUG_LOG2(file, line, "r:%d th:%u", th ? (int)rb_ractor_id(th->ractor) : -1, rb_th_serial(th));
#else
    RUBY_DEBUG_LOG2(file, line, "th:%u", rb_th_serial(th));
#endif

    thread_sched_set_locked(sched, th);
}

static void
thread_sched_unlock_(struct rb_thread_sched *sched, rb_thread_t *th, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line, "th:%u", rb_th_serial(th));

    thread_sched_set_unlocked(sched, th);

    rb_native_mutex_unlock(&sched->lock_);
}

// Like thread_sched_unlock(), but never dereferences th (the debug log above
// reads th->serial).  For the MN termination epilogue, which unlocks after th
// may already be collectable.  Keep in sync with thread_sched_unlock_.
RBIMPL_ATTR_MAYBE_UNUSED()
static void
thread_sched_unlock_no_log(struct rb_thread_sched *sched, rb_thread_t *th)
{
    thread_sched_set_unlocked(sched, th); // pointer compare only

    rb_native_mutex_unlock(&sched->lock_);
}

static void
ASSERT_thread_sched_locked(struct rb_thread_sched *sched, rb_thread_t *th)
{
#if RB_NATIVE_MUTEX_TRYLOCK_DETECTS_SELF
    VM_ASSERT(rb_native_mutex_trylock(&sched->lock_) == EBUSY);
#endif

#if VM_CHECK_MODE
    if (th) {
        VM_ASSERT(sched->lock_owner == th);
    }
    else {
        VM_ASSERT(sched->lock_owner != NULL);
    }
#endif
}


RBIMPL_ATTR_MAYBE_UNUSED()
static unsigned int
rb_ractor_serial(const rb_ractor_t *r)
{
    if (r) {
        return rb_ractor_id(r);
    }
    else {
        return 0;
    }
}

static void
ractor_sched_set_locked(rb_vm_t *vm, rb_ractor_t *cr)
{
#if VM_CHECK_MODE > 0
    VM_ASSERT(vm->ractor.sched.lock_owner == NULL);
    VM_ASSERT(vm->ractor.sched.locked == false);

    vm->ractor.sched.lock_owner = cr;
    vm->ractor.sched.locked = true;
#endif
}

static void
ractor_sched_set_unlocked(rb_vm_t *vm, rb_ractor_t *cr)
{
#if VM_CHECK_MODE > 0
    VM_ASSERT(vm->ractor.sched.locked);
    VM_ASSERT(vm->ractor.sched.lock_owner == cr);

    vm->ractor.sched.locked = false;
    vm->ractor.sched.lock_owner = NULL;
#endif
}


static void
ractor_sched_lock_(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line)
{
    rb_native_mutex_lock(&vm->ractor.sched.lock);

#if VM_CHECK_MODE
    RUBY_DEBUG_LOG2(file, line, "cr:%u prev_owner:%u", rb_ractor_serial(cr), rb_ractor_serial(vm->ractor.sched.lock_owner));
#else
    RUBY_DEBUG_LOG2(file, line, "cr:%u", rb_ractor_serial(cr));
#endif

    ractor_sched_set_locked(vm, cr);
}

static void
ractor_sched_unlock_(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line, "cr:%u", rb_ractor_serial(cr));

    ractor_sched_set_unlocked(vm, cr);
    rb_native_mutex_unlock(&vm->ractor.sched.lock);
}

static void
ASSERT_ractor_sched_locked(rb_vm_t *vm, rb_ractor_t *cr)
{
#if RB_NATIVE_MUTEX_TRYLOCK_DETECTS_SELF
    VM_ASSERT(rb_native_mutex_trylock(&vm->ractor.sched.lock) == EBUSY);
#endif
    VM_ASSERT(vm->ractor.sched.locked);
    VM_ASSERT(cr == NULL || vm->ractor.sched.lock_owner == cr);
}

static void ractor_sched_barrier_join_signal_locked(rb_vm_t *vm);

/* ntlist registration: a thread that executes Ruby code is always registered,
 * in its snt's nt->running_th or on running_dnts via its dedicated nt.  The
 * only unregistered execution is scheduler glue (parking, resuming), which
 * touches no Ruby heap, and the barrier wait below. */
static void
ntlist_add_running(rb_vm_t *vm, rb_thread_t *th)
{
    struct rb_native_thread *nt = th->nt;

    // a dedicated nt is not on the snts list the scans walk: running_dnts instead
    if (nt != NULL && nt->dedicated == 0) {
        rb_native_mutex_lock(&nt->running_th_lock);
        {
            VM_ASSERT(nt->running_th == NULL);
            nt->running_th = th;
        }
        rb_native_mutex_unlock(&nt->running_th_lock);
    }
    else {
        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            // an snt gone dedicated (rb_thread_lock_native_thread) has no
            // creation-time running_thread: the registration supplies it
            nt->running_thread = th;
            ccan_list_add(&vm->ractor.sched.ntlist.running_dnts, &nt->running_dnts_node);
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);
    }
}

// Returns whether the active barrier's walk had counted this registration:
// such a deregistration owes the snapshot count a decrement.  Read and
// cleared under the registration's own lock, so it pairs with the walk.
static bool
ntlist_del_running(rb_vm_t *vm, rb_thread_t *th)
{
    struct rb_native_thread *nt = th->nt;
    uint32_t serial;
    bool counted;
    bool in_running_th;

    // The registration itself says where it is: nt->running_th holds th, or
    // th's nt hangs on running_dnts.  barrier_serial is read inside the
    // registration's lock, ordered with the walk that stamped there.
    rb_native_mutex_lock(&nt->running_th_lock);
    {
        in_running_th = (nt->running_th == th);
        if (in_running_th) {
            nt->running_th = NULL;
            serial = vm->ractor.sched.barrier_serial;
            counted = (nt->barrier_counted_serial == serial);
            nt->barrier_counted_serial = serial - 1; // only once per barrier
        }
    }
    rb_native_mutex_unlock(&nt->running_th_lock);

    if (!in_running_th) {
        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            ccan_list_del_init(&nt->running_dnts_node);
            serial = vm->ractor.sched.barrier_serial;
            counted = (nt->barrier_counted_serial == serial);
            nt->barrier_counted_serial = serial - 1;
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);
    }
    return counted;
}

// Stamp a registration into the active barrier's snapshot unless the walk
// already counted it; returns whether it stamped.  Called under sched.lock,
// so it is serialized with the walk: the stamp says exactly whether the
// registration came first.
static bool
ntlist_stamp_if_uncounted(rb_vm_t *vm, rb_thread_t *th)
{
    struct rb_native_thread *nt = th->nt;
    uint32_t serial = vm->ractor.sched.barrier_serial; // sched.lock is held
    bool stamped;
    bool in_running_th;

    rb_native_mutex_lock(&nt->running_th_lock);
    {
        in_running_th = (nt->running_th == th);
        if (in_running_th) {
            stamped = (nt->barrier_counted_serial != serial);
            nt->barrier_counted_serial = serial;
        }
    }
    rb_native_mutex_unlock(&nt->running_th_lock);

    if (!in_running_th) {
        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            stamped = (nt->barrier_counted_serial != serial);
            nt->barrier_counted_serial = serial;
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);
    }
    return stamped;
}

// Record a thread entering/leaving the running set, with no global lock and
// no count: the records themselves are what the barrier counts.  Pairing:
// the barrier sets barrier_is_waiting and then walks the records under their
// locks; we move a record and then read the flag, so one side sees the other.
// List sched for the timer's timeslice ticks.  The caller holds sched->lock_
// with the readyq non-empty, so the timer cannot prune the entry meanwhile.
static void
timeslice_sched_link(rb_vm_t *vm, struct rb_thread_sched *sched)
{
    rb_native_mutex_lock(&vm->ractor.sched.timeslice.lock);
    {
        if (sched->timeslice_node.next == &sched->timeslice_node) {
            ccan_list_add_tail(&vm->ractor.sched.timeslice.scheds, &sched->timeslice_node);
        }
    }
    rb_native_mutex_unlock(&vm->ractor.sched.timeslice.lock);
}

static void
thread_sched_setup_running_threads(struct rb_thread_sched *sched, rb_ractor_t *cr, rb_vm_t *vm,
                                   rb_thread_t *add_th, rb_thread_t *del_th)
{
    RUBY_DEBUG_LOG("+:%u -:%u", rb_th_serial(add_th), rb_th_serial(del_th));

    if (del_th) {
        bool counted = ntlist_del_running(vm, del_th);
        sched->is_running = false;

        // The first load is only a filter; the one under sched.lock decides.
        // A missed flag means this deregistration preceded the barrier's walk.
        if (UNLIKELY(RUBY_ATOMIC_LOAD(vm->ractor.sched.barrier_is_waiting))) {
            ractor_sched_lock(vm, cr);
            {
                if (RUBY_ATOMIC_LOAD(vm->ractor.sched.barrier_is_waiting)) {
                    if (counted) {
                        VM_ASSERT(vm->ractor.sched.barrier_running_cnt > 0);
                        vm->ractor.sched.barrier_running_cnt--;
                    }
                    ractor_sched_barrier_join_signal_locked(vm);
                }
            }
            ractor_sched_unlock(vm, cr);
        }
    }

    if (add_th) {
        ntlist_add_running(vm, add_th);

        if (UNLIKELY(RUBY_ATOMIC_LOAD(vm->ractor.sched.barrier_is_waiting))) {
            // A stop-the-world section.  In its waiting phase sched.lock is
            // takable: join the snapshot count and take the interrupt (this
            // thread joins at its next check, like any walked runner).  In
            // the GC phase the barrier holds sched.lock to its end, so this
            // blocks here, as the old global-lock design did.
            ractor_sched_lock(vm, cr);
            {
                if (RUBY_ATOMIC_LOAD(vm->ractor.sched.barrier_is_waiting) &&
                    ntlist_stamp_if_uncounted(vm, add_th)) {
                    // the walk ran before this registration; count it in
                    RUBY_DEBUG_LOG("barrier_is_waiting");
                    vm->ractor.sched.barrier_running_cnt++;
                    RUBY_VM_SET_VM_BARRIER_INTERRUPT(add_th->ec);
                }
            }
            ractor_sched_unlock(vm, cr);
        }

        sched->is_running = true;

        // taking a turn with waiters already queued needs the timeslice ticks
        if (!ccan_list_empty(&sched->readyq)) {
            timeslice_sched_link(vm, sched);
            ractor_sched_lock(vm, cr);
            {
                if (vm->ractor.sched.timeslice_wait_inf) {
                    timer_thread_wakeup_locked(vm);
                }
            }
            ractor_sched_unlock(vm, cr);
        }
    }
}

static void
thread_sched_add_running_thread(struct rb_thread_sched *sched, rb_thread_t *th)
{
    ASSERT_thread_sched_locked(sched, th);
    VM_ASSERT(sched->running == th);

    rb_vm_t *vm = th->vm;
    thread_sched_setup_running_threads(sched, th->ractor, vm, th, NULL);
}

static void
thread_sched_del_running_thread(struct rb_thread_sched *sched, rb_thread_t *th)
{
    ASSERT_thread_sched_locked(sched, th);

    rb_vm_t *vm = th->vm;
    thread_sched_setup_running_threads(sched, th->ractor, vm, NULL, th);
}

void
rb_add_running_thread(rb_thread_t *th)
{
    struct rb_thread_sched *sched = TH_SCHED(th);

    thread_sched_lock(sched, th);
    {
        thread_sched_add_running_thread(sched, th);
    }
    thread_sched_unlock(sched, th);
}

void
rb_del_running_thread(rb_thread_t *th)
{
    struct rb_thread_sched *sched = TH_SCHED(th);

    thread_sched_lock(sched, th);
    {
        thread_sched_del_running_thread(sched, th);
    }
    thread_sched_unlock(sched, th);
}

// setup current or next running thread
// sched->running should be set only on this function.
//
// if th is NULL, there is no running threads.
static void
thread_sched_set_running(struct rb_thread_sched *sched, rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u->th:%u", rb_th_serial(sched->running), rb_th_serial(th));
    VM_ASSERT(sched->running != th);

    if (RUBY_DTRACE_RTS_SET_RUNNING_ENABLED()) {
        RUBY_DTRACE_RTS_SET_RUNNING(sched, sched->running, th);
    }

    sched->running = th;
}

RBIMPL_ATTR_MAYBE_UNUSED()
static bool
thread_sched_readyq_contain_p(struct rb_thread_sched *sched, rb_thread_t *th)
{
    rb_thread_t *rth;
    ccan_list_for_each(&sched->readyq, rth, sched.node.readyq) {
        if (rth == th) {
            VM_ASSERT(th->sched.node.is_ready);
            return true;
        }
    }
    VM_ASSERT(!th->sched.node.is_ready);
    return false;
}

// deque thread from the ready queue.
// if the ready queue is empty, return NULL.
//
// return deque'ed running thread (or NULL).
static rb_thread_t *
thread_sched_deq(struct rb_thread_sched *sched)
{
    ASSERT_thread_sched_locked(sched, NULL);
    rb_thread_t *next_th;

    VM_ASSERT(sched->running != NULL);

    if (ccan_list_empty(&sched->readyq)) {
        next_th = NULL;
    }
    else {
        next_th = ccan_list_pop(&sched->readyq, rb_thread_t, sched.node.readyq);
        VM_ASSERT(next_th->sched.node.is_ready);
        next_th->sched.node.is_ready = false;

        VM_ASSERT(sched->readyq_cnt > 0);
        sched->readyq_cnt--;
        ccan_list_node_init(&next_th->sched.node.readyq);
    }

    RUBY_DEBUG_LOG("next_th:%u readyq_cnt:%d", rb_th_serial(next_th), sched->readyq_cnt);

    return next_th;
}

// enqueue ready thread to the ready queue.
static void
thread_sched_enq(struct rb_thread_sched *sched, rb_thread_t *ready_th)
{
    ASSERT_thread_sched_locked(sched, NULL);
    RUBY_DEBUG_LOG("ready_th:%u readyq_cnt:%d", rb_th_serial(ready_th), sched->readyq_cnt);

    VM_ASSERT(sched->running != NULL);
    VM_ASSERT(!thread_sched_readyq_contain_p(sched, ready_th));

    bool timeslice_onset = sched->is_running && ccan_list_empty(&sched->readyq);

    ccan_list_add_tail(&sched->readyq, &ready_th->sched.node.readyq);
    ready_th->sched.node.is_ready = true;
    sched->readyq_cnt++;

    if (timeslice_onset) {
        // The running thread needs the timeslice ticks now.  Linked before
        // the check under sched.lock: either the timer's scan (same lock)
        // sees the sched, or this sees timeslice_wait_inf.
        rb_vm_t *vm = ready_th->vm;
        timeslice_sched_link(vm, sched);
        ractor_sched_lock(vm, NULL);
        {
            if (vm->ractor.sched.timeslice_wait_inf) {
                timer_thread_wakeup_locked(vm);
            }
        }
        ractor_sched_unlock(vm, NULL);
    }
}

// DNT: kick condvar
// SNT: TODO
static void
thread_sched_wakeup_running_thread(struct rb_thread_sched *sched, rb_thread_t *next_th, bool will_switch)
{
    ASSERT_thread_sched_locked(sched, NULL);
    VM_ASSERT(sched->running == next_th);

    if (next_th) {
        if (next_th->nt) {
            if (th_has_dedicated_nt(next_th)) {
                RUBY_DEBUG_LOG("pinning th:%u", next_th->serial);
                rb_native_cond_signal(&next_th->nt->readyq);
            }
            else {
                // TODO
                RUBY_DEBUG_LOG("th:%u is already running.", next_th->serial);
            }
        }
        else {
            if (will_switch) {
                RUBY_DEBUG_LOG("th:%u (do nothing)", rb_th_serial(next_th));
            }
            else {
                RUBY_DEBUG_LOG("th:%u (enq)", rb_th_serial(next_th));
                ractor_sched_enq(next_th->vm, next_th->ractor);
            }
        }
    }
    else {
        RUBY_DEBUG_LOG("no waiting threads%s", "");
    }
}

// waiting -> ready (locked)
static void
thread_sched_to_ready_common(struct rb_thread_sched *sched, rb_thread_t *th, bool wakeup, bool will_switch)
{
    RUBY_DEBUG_LOG("th:%u running:%u redyq_cnt:%d", rb_th_serial(th), rb_th_serial(sched->running), sched->readyq_cnt);

    VM_ASSERT(sched->running != th);
    VM_ASSERT(!thread_sched_readyq_contain_p(sched, th));
    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_READY, th);

    if (sched->running == NULL) {
        thread_sched_set_running(sched, th);
        if (wakeup) thread_sched_wakeup_running_thread(sched, th, will_switch);
    }
    else {
        thread_sched_enq(sched, th);
    }
}

// waiting -> ready
//
// `th` had became "waiting" state by `thread_sched_to_waiting`
// and `thread_sched_to_ready` enqueue `th` to the thread ready queue.
RBIMPL_ATTR_MAYBE_UNUSED()
static void
thread_sched_to_ready(struct rb_thread_sched *sched, rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    thread_sched_lock(sched, th);
    {
        thread_sched_to_ready_common(sched, th, true, false);
    }
    thread_sched_unlock(sched, th);
}

// wait until sched->running is `th`.  `end` is an absolute deadline for a dedicated
static void
thread_sched_wait_running_turn(struct rb_thread_sched *sched, rb_thread_t *th, bool can_direct_transfer, const rb_hrtime_t *end)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    ASSERT_thread_sched_locked(sched, th);
    VM_ASSERT(th == rb_ec_thread_ptr(rb_current_ec_noinline()));

    bool timedout = false;

    if (th != sched->running) {
        // TODO: This optimization should also be made to work for MN_THREADS
        if (th->has_dedicated_nt && th == sched->runnable_hot_th && (sched->running == NULL || sched->running->has_dedicated_nt)) {
            RUBY_DEBUG_LOG("(nt) stealing: hot-th:%u.  running:%u", rb_th_serial(th), rb_th_serial(sched->running));

            // th serves itself on its own nt, displacing the enqueued
            // running thread back to the readyq: cancel the entry that was
            // posted for it (a later dequeue would find this Ractor served
            // and its next enqueue would double-list the node)
            ractor_sched_cancel_enq(th->vm, sched);

            // If there is a thread set to run, move it back to the front of the readyq
            if (sched->running != NULL) {
                rb_thread_t *running = sched->running;
                VM_ASSERT(!thread_sched_readyq_contain_p(sched, running));
                running->sched.node.is_ready = true;
                ccan_list_add(&sched->readyq, &running->sched.node.readyq);
                sched->readyq_cnt++;
            }

            // Pull off the ready queue and start running.
            if (th->sched.node.is_ready) {
                VM_ASSERT(thread_sched_readyq_contain_p(sched, th));
                ccan_list_del_init(&th->sched.node.readyq);
                th->sched.node.is_ready = false;
                sched->readyq_cnt--;
            }
            thread_sched_set_running(sched, th);
            rb_ractor_thread_switch(th->ractor, th, false);
        }
        else if (th == sched->runnable_hot_th) {
            // The hot thread cannot steal the control (e.g. the running thread
            // is an MN thread). It is going to sleep, so it is no longer spinning;
            // drop the hint so that other threads don't yield the lock to it.
            sched->runnable_hot_th = NULL;
            sched->runnable_hot_th_waiting = 0;
        }

        // already deleted from running threads


        // wait for execution right
        rb_thread_t *next_th;
        while((next_th = sched->running) != th) {
            if (th_has_dedicated_nt(th)) {
                RUBY_DEBUG_LOG("(nt) sleep th:%u running:%u", rb_th_serial(th), rb_th_serial(sched->running));

                thread_sched_set_unlocked(sched, th);
                {
                    RUBY_DEBUG_LOG("nt:%d cond:%p", th->nt->serial, &th->nt->readyq);
                    rb_nativethread_cond_t *cond = &th->nt->readyq;

                    // Once someone has queued this thread the deadline is spent: it
                    // is waiting for a turn, not for the time, and arming a kernel
                    // timer for every round of that costs more than the wait.
                    // Once someone has queued this thread the deadline is spent: it
                    // is waiting for a turn, not for the time, and arming a kernel
                    // timer for every round of that costs more than the wait.
                    if (end && !th->sched.node.is_ready) {
                        rb_hrtime_t abs = *end;

                        if (!RB_NATIVE_COND_HRTIME_DEADLINE_P()) {
                            // the condvar counts in another clock: restate it there
                            rb_hrtime_t now = rb_hrtime_now();
                            abs = native_cond_timeout(cond, *end > now ? *end - now : 0);
                        }
                        timedout = native_cond_timedwait(cond, &sched->lock_, &abs) == ETIMEDOUT;
                    }
                    else {
                        rb_native_cond_wait(cond, &sched->lock_);
                    }
                }
                thread_sched_set_locked(sched, th);

                if (timedout &&
                    sched->running != th && !th->sched.node.is_ready) {
                    // the deadline passed and nobody woke this thread: get back in
                    // line for the running turn, then wait for it without a deadline
                    thread_sched_to_ready_common(sched, th, false, false);
                    end = NULL;
                }

                if (sched->runnable_hot_th != NULL && sched->runnable_hot_th_waiting) {
                    VM_ASSERT(sched->runnable_hot_th != th);
                    // Give the hot thread a chance to preempt, if it's actively spinning.
                    // On multicore, this reduces the rate of core-switching. On single-core it
                    // should mostly be a nop, since the other thread can't be concurrently spinning.
                    thread_sched_unlock(sched, th);
                    thread_sched_lock(sched, th);
                }

                RUBY_DEBUG_LOG("(nt) wakeup %s", sched->running == th ? "success" : "failed");
                if (th == sched->running) {
                    rb_ractor_thread_switch(th->ractor, th, false);
                }
            }
            else {
                // search another ready thread
                if (can_direct_transfer &&
                    (next_th = sched->running) != NULL &&
                    !next_th->nt // next_th is running or has dedicated nt
                    ) {

                    RUBY_DEBUG_LOG("th:%u->%u (direct)", rb_th_serial(th), rb_th_serial(next_th));

                    thread_sched_set_unlocked(sched, th);
                    {
                        rb_ractor_set_current_ec(th->ractor, NULL);
                        thread_sched_switch(th, next_th);
                    }
                    thread_sched_set_locked(sched, th);
                }
                else {
                    // search another ready ractor
                    struct rb_native_thread *nt = th->nt;
                    native_thread_assign(NULL, th);

                    RUBY_DEBUG_LOG("th:%u->%u (ractor scheduling)", rb_th_serial(th), rb_th_serial(next_th));

                    thread_sched_set_unlocked(sched, th);
                    {
                        rb_ractor_set_current_ec(th->ractor, NULL);
                        coroutine_transfer0(th->sched.context, nt->nt_context, false);
                    }
                    thread_sched_set_locked(sched, th);
                }

                VM_ASSERT(rb_current_ec_noinline() == th->ec);
            }
        }

        VM_ASSERT(th->nt != NULL);
        VM_ASSERT(rb_current_ec_noinline() == th->ec);
        VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);

        // add th to running threads
        thread_sched_add_running_thread(sched, th);
    }

    // Control transfer to the current thread is now complete. The original thread
    // cannot steal control at this point.
    sched->runnable_hot_th = NULL;
    sched->runnable_hot_th_waiting = 0;


    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_RESUMED, th);
}

// waiting -> ready -> running (locked)
static void
thread_sched_to_running_common(struct rb_thread_sched *sched, rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u dedicated:%d", rb_th_serial(th), th_has_dedicated_nt(th));

    VM_ASSERT(sched->running != th);
    VM_ASSERT(th_has_dedicated_nt(th));
    VM_ASSERT(GET_THREAD() == th);

    native_thread_dedicated_dec(th->vm, th->ractor, th->nt);

    // waiting -> ready
    thread_sched_to_ready_common(sched, th, false, false);

    if (sched->running == th) {
        thread_sched_add_running_thread(sched, th);
    }

    // TODO: check SNT number
    thread_sched_wait_running_turn(sched, th, false, NULL);
}

// waiting -> ready -> running
//
// `th` had been waiting by `thread_sched_to_waiting()`
// and run a dedicated task (like waitpid and so on).
// After the dedicated task, this function is called
// to join a normal thread-scheduling.
static void
thread_sched_to_running(struct rb_thread_sched *sched, rb_thread_t *th)
{
    // We are reading and writing these sched fields without lock cover, but
    // there are no correctness issues resulting from stale cache or delayed writeback.
    // When it works, this causes the next-scheduled thread to yield the sched lock
    // briefly so that we can grab it if we're still spinning (not descheduled yet).
    if (sched->runnable_hot_th == th) {
        sched->runnable_hot_th_waiting = 1;
    }
    thread_sched_lock(sched, th);
    {
        thread_sched_to_running_common(sched, th);
    }
    thread_sched_unlock(sched, th);
}

// resume a next thread in the thread ready queue.
//
// deque next running thread from the ready thread queue and
// resume this thread if available.
//
// If the next therad has a dedicated native thraed, simply signal to resume.
// Otherwise, make the ractor ready and other nt will run the ractor and the thread.
static void
thread_sched_wakeup_next_thread(struct rb_thread_sched *sched, rb_thread_t *th, bool will_switch)
{
    ASSERT_thread_sched_locked(sched, th);

    VM_ASSERT(sched->running == th);
    VM_ASSERT(sched->running->nt != NULL);

    rb_thread_t *next_th = thread_sched_deq(sched);

    RUBY_DEBUG_LOG("next_th:%u", rb_th_serial(next_th));
    VM_ASSERT(th != next_th);

    thread_sched_set_running(sched, next_th);
    VM_ASSERT(next_th == sched->running);
    thread_sched_wakeup_running_thread(sched, next_th, will_switch);

    if (th != next_th) {
        thread_sched_del_running_thread(sched, th);
    }
}

// running -> dead (locked)
static void
thread_sched_to_dead_common(struct rb_thread_sched *sched, rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u DNT:%d", rb_th_serial(th), th->nt->dedicated);

    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);

    // A dying coroutine thread (will_switch=true here) does NOT wake the
    // next thread now: it is still winding down (co_start's epilogue), and
    // the same Ractor must not have two threads executing at once. The
    // epilogue enqueues the Ractor after its last rb_ractor_t access.
    thread_sched_wakeup_next_thread(sched, th, !th_has_dedicated_nt(th));

    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_EXITED, th);
}

// running -> dead
static void
thread_sched_to_dead(struct rb_thread_sched *sched, rb_thread_t *th)
{
    // wait out any pending wake here, while th's Ractor is still alive
    timer_thread_wake_fence(th);

    thread_sched_lock(sched, th);
    {
        thread_sched_to_dead_common(sched, th);
    }
    thread_sched_unlock(sched, th);
}

// running -> waiting (locked)
//
// This thread will run dedicated task (th->nt->dedicated++).
static void
thread_sched_to_waiting_common(struct rb_thread_sched *sched, rb_thread_t *th, bool yield_immediately)
{
    RUBY_DEBUG_LOG("th:%u DNT:%d", rb_th_serial(th), th->nt->dedicated);

    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);

    native_thread_dedicated_inc(th->vm, th->ractor, th->nt);
    if (!yield_immediately) {
        sched->runnable_hot_th = th;
        sched->runnable_hot_th_waiting = 0;
    }
    thread_sched_wakeup_next_thread(sched, th, false);
}

// running -> waiting
//
// This thread will run a dedicated task.
static void
thread_sched_to_waiting(struct rb_thread_sched *sched, rb_thread_t *th, bool yield_immediately)
{
    thread_sched_lock(sched, th);
    {
        thread_sched_to_waiting_common(sched, th, yield_immediately);
    }
    thread_sched_unlock(sched, th);
}

// mini utility func
// return true if any there are any interrupts
static bool
ubf_set(rb_thread_t *th, rb_unblock_function_t *func, void *arg, rb_atomic_t *event_serial)
{
    VM_ASSERT(func != NULL);

  retry:
    if (RUBY_VM_INTERRUPTED(th->ec)) {
        RUBY_DEBUG_LOG("interrupted:0x%x", th->ec->interrupt_flag);
        return true;
    }

    rb_native_mutex_lock(&th->interrupt_lock);
    {
        if (!th->ec->raised_flag && RUBY_VM_INTERRUPTED(th->ec)) {
            rb_native_mutex_unlock(&th->interrupt_lock);
            goto retry;
        }

        VM_ASSERT(th->unblock.func == NULL);
        th->unblock.func = func;
        th->unblock.arg  = arg;
        if (event_serial) {
            rb_atomic_t prev_serial = RUBY_ATOMIC_FETCH_ADD(th->unblock.event_serial, 1);
            *event_serial = prev_serial+1;
        }
    }
    rb_native_mutex_unlock(&th->interrupt_lock);

    return false;
}

static void
ubf_clear(rb_thread_t *th, bool clear_serial)
{
    rb_native_mutex_lock(&th->interrupt_lock);
    {
        th->unblock.func = NULL;
        th->unblock.arg  = NULL;
        if (clear_serial) {
            RUBY_ATOMIC_ADD(th->unblock.event_serial, 1);
        }
    }
    rb_native_mutex_unlock(&th->interrupt_lock);
}

static void
ubf_waiting(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    struct rb_thread_sched *sched = TH_SCHED(th);

    // only once. it is safe because th->interrupt_lock is already acquired.
    th->unblock.func = NULL;
    th->unblock.arg = NULL;

    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    thread_sched_lock(sched, th);
    {
        if (sched->running == th || th->sched.node.is_ready) {
            // not sleeping yet, or a deadline already put it back in line
        }
        else {
            thread_sched_to_ready_common(sched, th, true, false);

            // If the turn is taken, th stays parked until the running thread yields.
            // For a timed wait, wake it early anyway: it re-parks at once, but its
            // wakeup then runs on another core in parallel with the running thread,
            // off the handoff path.  An untimed wait has no post-wake bookkeeping
            // worth pipelining, so it skips the extra futex round.
            if (sched->running != th && th->sched.waiting_timed &&
                th->nt != NULL && th_has_dedicated_nt(th)) {
                rb_native_cond_signal(&th->nt->readyq);
            }
        }
    }
    thread_sched_unlock(sched, th);
}

// running -> waiting
//
// This thread will sleep until other thread wakeup the thread.  `end` is an
// absolute deadline, NULL to sleep until woken; only a dedicated native thread,
// which parks on its own condvar, can take one.
static void
thread_sched_to_waiting_until_wakeup(struct rb_thread_sched *sched, rb_thread_t *th, const rb_hrtime_t *end)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));

    VM_ASSERT(end == NULL || th_has_dedicated_nt(th));

    RB_VM_SAVE_MACHINE_CONTEXT(th);


    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);

    thread_sched_lock(sched, th);
    {
        // NOTE: there's a lock ordering inversion here with the ubf call, but it's benign.
        if (ubf_set(th, ubf_waiting, (void *)th, NULL)) {
            RUBY_DEBUG_LOG("th:%u interrupted", rb_th_serial(th));
        }
        else {
            bool can_direct_transfer = !th_has_dedicated_nt(th);
            th->sched.waiting_timed = (end != NULL); // never true here for M:N (end is NULL)
            // NOTE: th->status is set before and after this sleep outside of this function in `sleep_forever`
            thread_sched_wakeup_next_thread(sched, th, can_direct_transfer);
            thread_sched_wait_running_turn(sched, th, can_direct_transfer, end);
            th->sched.waiting_timed = false;
        }
    }
    thread_sched_unlock(sched, th);

    ubf_clear(th, false);
}

// run another thread in the ready queue.
// continue to run if there are no ready threads.
static void
thread_sched_yield(struct rb_thread_sched *sched, rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%d sched->readyq_cnt:%d", (int)th->serial, sched->readyq_cnt);

    thread_sched_lock(sched, th);
    {
        if (!ccan_list_empty(&sched->readyq)) {
            RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);
            thread_sched_wakeup_next_thread(sched, th, !th_has_dedicated_nt(th));
            bool can_direct_transfer = !th_has_dedicated_nt(th);
            thread_sched_to_ready_common(sched, th, false, can_direct_transfer);
            thread_sched_wait_running_turn(sched, th, can_direct_transfer, NULL);
            th->status = THREAD_RUNNABLE;
        }
        else {
            VM_ASSERT(sched->readyq_cnt == 0);
        }
    }
    thread_sched_unlock(sched, th);
}

void
rb_thread_sched_init(struct rb_thread_sched *sched, bool atfork)
{
    rb_native_mutex_initialize(&sched->lock_);

#if VM_CHECK_MODE
    sched->lock_owner = NULL;
#endif

    ccan_list_head_init(&sched->readyq);
    sched->readyq_cnt = 0;
    ccan_list_node_init(&sched->grq_node); // self-linked = not enqueued
    ccan_list_node_init(&sched->timeslice_node);

#if USE_MN_THREADS
    if (!atfork) sched->enable_mn_threads = true; // MN is enabled on Ractors
#endif
}

static void
coroutine_transfer0(struct coroutine_context *transfer_from, struct coroutine_context *transfer_to, bool to_dead)
{
#ifdef RUBY_ASAN_ENABLED
    void **fake_stack = to_dead ? NULL : &transfer_from->fake_stack;
    __sanitizer_start_switch_fiber(fake_stack, transfer_to->stack_base, transfer_to->stack_size);
#endif

#if defined(COROUTINE_SANITIZE_THREAD)
    /* Tell TSan we are switching to transfer_to's fiber before the stack
     * switch, so its per-thread shadow stack stays bound to the right
     * coroutine. */
    __tsan_switch_to_fiber(transfer_to->tsan_fiber, 0);
#endif

    RBIMPL_ATTR_MAYBE_UNUSED()
    struct coroutine_context *returning_from = coroutine_transfer(transfer_from, transfer_to);

    /* if to_dead was passed, the caller is promising that this coroutine is finished and it should
     * never be resumed! */
    VM_ASSERT(!to_dead);
#ifdef RUBY_ASAN_ENABLED
   __sanitizer_finish_switch_fiber(transfer_from->fake_stack,
                                   (const void**)&returning_from->stack_base, &returning_from->stack_size);
#endif
}

static void
thread_sched_switch0(struct coroutine_context *current_cont, rb_thread_t *next_th, struct rb_native_thread *nt, bool to_dead)
{
    VM_ASSERT(!nt->dedicated);
    VM_ASSERT(next_th->nt == NULL);

    RUBY_DEBUG_LOG("next_th:%u", rb_th_serial(next_th));

    // this direct transfer serves next_th without a dequeue; cancel its
    // Ractor's outstanding grq entry (no-op when nothing is enqueued)
    ractor_sched_cancel_enq(next_th->vm, TH_SCHED(next_th));

    ruby_thread_set_native(next_th);
    native_thread_assign(nt, next_th);

    coroutine_transfer0(current_cont, next_th->sched.context, to_dead);
}

static void
thread_sched_switch(rb_thread_t *cth, rb_thread_t *next_th)
{
    struct rb_native_thread *nt = cth->nt;
    native_thread_assign(NULL, cth);
    RUBY_DEBUG_LOG("th:%u->%u on nt:%d", rb_th_serial(cth), rb_th_serial(next_th), nt->serial);
    thread_sched_switch0(cth->sched.context, next_th, nt, cth->status == THREAD_KILLED);
}

#if VM_CHECK_MODE > 0
RBIMPL_ATTR_MAYBE_UNUSED()
static unsigned int
grq_size(rb_vm_t *vm, rb_ractor_t *cr)
{
    ASSERT_ractor_sched_locked(vm, cr);

    rb_ractor_t *r, *prev_r = NULL;
    unsigned int i = 0;

    ccan_list_for_each(&vm->ractor.sched.grq, r, threads.sched.grq_node) {
        i++;

        VM_ASSERT(r != prev_r);
        prev_r = r;
    }
    return i;
}
#endif

// A native thread enters/leaves an epilogue that outlives its Ractor: from
// the increment until the decrement, ruby_vm_destruct waits for it below.
// The increment must happen while the VM still counts the thread's Ractor,
// so that the two never look absent at the same time.
void
rb_thread_sched_winding_begin(rb_vm_t *vm)
{
    RUBY_ATOMIC_INC(vm->ractor.sched.winding_cnt);
}

void
rb_thread_sched_winding_end(rb_vm_t *vm)
{
    VM_ASSERT(RUBY_ATOMIC_LOAD(vm->ractor.sched.winding_cnt) > 0);
    RUBY_ATOMIC_DEC(vm->ractor.sched.winding_cnt);
}

// ruby_vm_destruct: wait until no native thread is between a coroutine
// epilogue and its reclaim -- past that point the reclaim frees through the
// (about to be destroyed) objspace and reads the (about to be unset) VM.
// Runs without the VM lock, which the epilogue needs to progress.
void
rb_thread_sched_wait_winding(rb_vm_t *vm)
{
    while (RUBY_ATOMIC_LOAD(vm->ractor.sched.winding_cnt) > 0) {
        native_thread_yield();
    }
}

// A direct service of a runnable thread (direct transfer or the hot-thread
// steal) bypasses the grq; cancel the Ractor's outstanding entry so that
// "enqueued <=> runnable and unserved" keeps holding. The caller holds the
// per-Ractor sched lock, so no concurrent enqueue can relink the node: a
// self-linked read needs no lock (the common case -- direct switches whose
// transition never enqueued). A linked read can race only with a dequeue,
// hence the recheck under the grq lock.
static void
ractor_sched_cancel_enq(rb_vm_t *vm, struct rb_thread_sched *sched)
{
    if (sched->grq_node.next != &sched->grq_node) {
        ractor_sched_lock(vm, NULL);
        {
            if (sched->grq_node.next != &sched->grq_node) {
                ccan_list_del_init(&sched->grq_node);
                VM_ASSERT(vm->ractor.sched.grq_cnt > 0);
                vm->ractor.sched.grq_cnt--;
            }
        }
        ractor_sched_unlock(vm, NULL);
    }
}

static void
ractor_sched_enq(rb_vm_t *vm, rb_ractor_t *r)
{
    struct rb_thread_sched *sched = &r->threads.sched;
    rb_ractor_t *cr = NULL; // timer thread can call this function

    VM_ASSERT(sched->running != NULL);
    VM_ASSERT(sched->running->nt == NULL);

    ractor_sched_lock(vm, cr);
    {
        // Precondition: not already enqueued (the grq_node is self-linked).
        // This holds because every service of a runnable-but-unserved thread
        // either dequeues the entry (the nt scheduling loop) or cancels it
        // (direct transfers / the hot-thread steal; see
        // ractor_sched_cancel_enq) -- re-adding a linked node would corrupt
        // the queue, so check unconditionally (a CHECK-mode-only assert
        // would miss it: the race needs timing that CHECK builds perturb).
        if (sched->grq_node.next != &sched->grq_node) {
            rb_bug("ractor_sched_enq: already enqueued");
        }
        ccan_list_add_tail(&vm->ractor.sched.grq, &sched->grq_node);
        vm->ractor.sched.grq_cnt++;
        VM_ASSERT(grq_size(vm, cr) == vm->ractor.sched.grq_cnt);

        RUBY_DEBUG_LOG("r:%u th:%u grq_cnt:%u", rb_ractor_id(r), rb_th_serial(sched->running), vm->ractor.sched.grq_cnt);

        rb_native_cond_signal(&vm->ractor.sched.cond);

        // The signal reaches a parked snt, and a running one revisits the
        // queue in ractor_sched_deq before it can wait (same lock as here).
        // With every snt dedicated or retired, only the timer thread's
        // timeout branch can serve the entry or widen the pool: wake it
        // (a no-op unless it sleeps untimed).
        if (RUBY_ATOMIC_LOAD(vm->ractor.sched.snt_cnt) == 0) {
            timer_thread_wakeup_locked(vm);
        }

        // ractor_sched_dump(vm);
    }
    ractor_sched_unlock(vm, cr);
}


#ifndef MINIMUM_SNT
// make at least MINIMUM_SNT snts for debug.
#define MINIMUM_SNT 0
#endif

/* A shared thread woken with nothing to run is one whose turn another thread
 * took first.  After this many in a row it gives itself back: the queue keeps
 * running dry, so the pool is wider than the work.  0 retires on the first one
 * and is too eager to be useful; a negative value keeps every thread. */
#ifndef SNT_IDLE_RETIRE
#define SNT_IDLE_RETIRE 3
#endif

/* Never give the last shared thread back.  With none left an enqueue has nobody
 * to signal, and the only code that makes one runs on the timer thread's
 * timeout branch, which is reached only once it has seen a backlog. */
#define SNT_KEEP_MINIMUM (MINIMUM_SNT > 1 ? MINIMUM_SNT : 1)

static rb_ractor_t *
ractor_sched_deq(rb_vm_t *vm, rb_ractor_t *cr)
{
    rb_ractor_t *r;
    int idle_streak = 0;   // consecutive pops that found the queue empty

    ractor_sched_lock(vm, cr);
    {
        RUBY_DEBUG_LOG("empty? %d", ccan_list_empty(&vm->ractor.sched.grq));
        // ractor_sched_dump(vm);

        VM_ASSERT(rb_current_execution_context(false) == NULL);
        VM_ASSERT(grq_size(vm, cr) == vm->ractor.sched.grq_cnt);

        while ((r = ccan_list_pop(&vm->ractor.sched.grq, rb_ractor_t, threads.sched.grq_node)) == NULL) {
            RUBY_DEBUG_LOG("wait grq_cnt:%d", (int)vm->ractor.sched.grq_cnt);

            if (SNT_IDLE_RETIRE >= 0 && ++idle_streak > SNT_IDLE_RETIRE &&
                (int)RUBY_ATOMIC_LOAD(vm->ractor.sched.snt_cnt) > SNT_KEEP_MINIMUM) {
                RUBY_ATOMIC_DEC(vm->ractor.sched.snt_cnt);
                RUBY_DEBUG_LOG("retire, snt_cnt:%d", (int)vm->ractor.sched.snt_cnt);
                break;   // returning NULL ends this nt; see the caller
            }

            ractor_sched_set_unlocked(vm, cr);
            rb_native_cond_wait(&vm->ractor.sched.cond, &vm->ractor.sched.lock);
            ractor_sched_set_locked(vm, cr);

            RUBY_DEBUG_LOG("wakeup grq_cnt:%d", (int)vm->ractor.sched.grq_cnt);
        }

        VM_ASSERT(rb_current_execution_context(false) == NULL);

        if (r) {
            ccan_list_node_init(&r->threads.sched.grq_node); // back to self-linked
            VM_ASSERT(vm->ractor.sched.grq_cnt > 0);
            vm->ractor.sched.grq_cnt--;
            RUBY_DEBUG_LOG("r:%d grq_cnt:%u", (int)rb_ractor_id(r), vm->ractor.sched.grq_cnt);
        }
        else {
            // the retire branch is the only way out of the loop without a ractor
            VM_ASSERT(idle_streak > SNT_IDLE_RETIRE);
        }
    }
    ractor_sched_unlock(vm, cr);

    return r;
}

void rb_ractor_lock_self(rb_ractor_t *r);
void rb_ractor_unlock_self(rb_ractor_t *r);

// The current thread for a ractor is put to "sleep" (descheduled in the STOPPED_FOREVER state) waiting for
// a ractor action to wake it up.
void
rb_ractor_sched_wait(rb_execution_context_t *ec, rb_ractor_t *cr, rb_unblock_function_t *ubf, void *ubf_arg)
{
    // ractor lock of cr is acquired

    RUBY_DEBUG_LOG("start%s", "");

    rb_thread_t * volatile th = rb_ec_thread_ptr(ec);
    struct rb_thread_sched *sched = TH_SCHED(th);
    struct ractor_waiter *waiter = (struct ractor_waiter*)ubf_arg;

    if (ubf_set(th, ubf, ubf_arg, &waiter->event_serial)) {
        // interrupted
        return;
    }

    thread_sched_lock(sched, th);
    rb_ractor_unlock_self(cr);
    {
        // A dedicated native thread takes the deadline on the very condvar a wakeup
        // signals.  An M:N thread has no condvar of its own, so its deadline goes to
        // the timer thread, which then wakes it the way rb_ractor_sched_wakeup() does.
        bool dedicated = th_has_dedicated_nt(th);
        const rb_hrtime_t *end_p = NULL;
        bool armed = false, expired = false;

        if (waiter->end) {
            if (dedicated) {
                end_p = waiter->end;
            }
            else {
                // the timer wheel takes a relative timeout
                rb_hrtime_t now = rb_hrtime_now();
                rb_hrtime_t rel = *waiter->end > now ? *waiter->end - now : 0;

                armed = ractor_sched_timeout_arm(th, &rel);
                expired = !armed;
            }
        }

        if (expired) {
            RUBY_DEBUG_LOG("expired before sleep%s", "");
        }
        else if (armed && th->sched.waiting_reason.flags == thread_sched_waiting_none) {
            // the timer thread already took this thread out of the wheel; bump the
            // serial so that it does not try to wake a thread that never slept
            th->sched.event_serial++;
        }
        else {
            // setup sleep
            bool can_direct_transfer = !dedicated;
            RB_VM_SAVE_MACHINE_CONTEXT(th);
            th->status = THREAD_STOPPED_FOREVER;
            th->sched.waiting_timed = (end_p != NULL); // never true here for M:N (end_p is NULL)
            RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);
            thread_sched_wakeup_next_thread(sched, th, can_direct_transfer);
            // sleep
            thread_sched_wait_running_turn(sched, th, can_direct_transfer, end_p);
            th->sched.waiting_timed = false;
            th->status = THREAD_RUNNABLE;

            // whoever woke this thread took the timeout back first
            VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);
        }
    }
    thread_sched_unlock(sched, th);
    rb_ractor_lock_self(cr);

    ubf_clear(th, true);

    RUBY_DEBUG_LOG("end%s", "");
}

void
rb_ractor_sched_wakeup(rb_ractor_t *r, rb_thread_t *r_th)
{
    // ractor lock of r acquired
    struct rb_thread_sched *sched = TH_SCHED(r_th);

    RUBY_DEBUG_LOG("r:%u th:%d", (unsigned int)rb_ractor_id(r), r_th->serial);

    thread_sched_lock(sched, r_th);
    {
        if (r_th->status == THREAD_STOPPED_FOREVER) {
            RUBY_ATOMIC_ADD(r_th->unblock.event_serial, 1);

            // r_th must not resume with a wheel entry left behind: take its timeout
            // back, as ubf_event_waiting() does.  Only r_th arms it, and it is
            // parked here, so reading the flags without the timer lock is safe.
            if (r_th->sched.waiting_reason.flags != thread_sched_waiting_none) {
                ractor_sched_timeout_disarm(r_th);
            }

            // a timeout that fired first may have made r_th runnable already: waking
            // it twice would put it on the readyq twice
            if (sched->running != r_th && !r_th->sched.node.is_ready) {
                r_th->sched.event_serial++; // a timeout still armed must not wake it again
                thread_sched_to_ready_common(sched, r_th, true, false);
            }
        }
    }
    thread_sched_unlock(sched, r_th);
}

static bool
ractor_sched_barrier_completed_p(rb_vm_t *vm)
{
    // The snapshot barrier_running_cnt is taken by the barrier's walk and
    // decremented by counted deregistrations; no rescan is needed here.
    RUBY_DEBUG_LOG("run:%u wait:%u", vm->ractor.sched.barrier_running_cnt, vm->ractor.sched.barrier_joined_cnt);
    VM_ASSERT(vm->ractor.sched.barrier_running_cnt - 1 >= vm->ractor.sched.barrier_joined_cnt);

    return (vm->ractor.sched.barrier_running_cnt - vm->ractor.sched.barrier_joined_cnt) == 1;
}

void
rb_ractor_sched_barrier_start(rb_vm_t *vm, rb_ractor_t *cr)
{
    VM_ASSERT(cr == GET_RACTOR());
    VM_ASSERT(vm->ractor.sync.lock_owner == cr); // VM is locked
    VM_ASSERT(!vm->ractor.sched.barrier_is_waiting);
    VM_ASSERT(vm->ractor.sched.barrier_joined_cnt == 0);
    VM_ASSERT(vm->ractor.sched.barrier_ractor == NULL);
    VM_ASSERT(vm->ractor.sched.barrier_lock_rec == 0);

    RUBY_DEBUG_LOG("start serial:%u", vm->ractor.sched.barrier_serial);

    unsigned int lock_rec;

    ractor_sched_lock(vm, cr);
    {
        RUBY_ATOMIC_SET(vm->ractor.sched.barrier_is_waiting, 1);
        vm->ractor.sched.barrier_ractor = cr;
        vm->ractor.sched.barrier_lock_rec = vm->ractor.sync.lock_rec;

        // release VM lock
        lock_rec = vm->ractor.sync.lock_rec;
        vm->ractor.sync.lock_rec = 0;
        vm->ractor.sync.lock_owner = NULL;
        rb_native_mutex_unlock(&vm->ractor.sync.lock);

        // Interrupt all running threads: running_dnts plus each snt's running_th.
        // A switch before this scan is visible to it; one after it sees
        // barrier_is_waiting (set above) and waits.
        // Interrupt and count every registered runner, stamping each nt so a
        // deregistration during this barrier knows it was counted.
        rb_thread_t *ith;
        unsigned int running_cnt = 0;
        uint32_t serial = vm->ractor.sched.barrier_serial;

        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            struct rb_native_thread *dnt;
            ccan_list_for_each(&vm->ractor.sched.ntlist.running_dnts, dnt, running_dnts_node) {
                ith = dnt->running_thread;
                dnt->barrier_counted_serial = serial;
                running_cnt++;
                if (ith->ractor != cr) {
                    RUBY_DEBUG_LOG("barrier request to th:%u", rb_th_serial(ith));
                    RUBY_VM_SET_VM_BARRIER_INTERRUPT(ith->ec);
                }
            }

            struct rb_native_thread *nt;
            ccan_list_for_each(&vm->ractor.sched.ntlist.snts, nt, snts_node) {
                rb_native_mutex_lock(&nt->running_th_lock);
                {
                    ith = nt->running_th;
                    if (ith != NULL) {
                        nt->barrier_counted_serial = serial;
                        running_cnt++;
                        if (ith->ractor != cr) {
                            RUBY_DEBUG_LOG("barrier request to th:%u", rb_th_serial(ith));
                            RUBY_VM_SET_VM_BARRIER_INTERRUPT(ith->ec);
                        }
                    }
                }
                rb_native_mutex_unlock(&nt->running_th_lock);
            }
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);

        vm->ractor.sched.barrier_running_cnt = running_cnt;

        // wait for other ractors
        while (!ractor_sched_barrier_completed_p(vm)) {
            ractor_sched_set_unlocked(vm, cr);
            rb_native_cond_wait(&vm->ractor.sched.barrier_complete_cond, &vm->ractor.sched.lock);
            ractor_sched_set_locked(vm, cr);
        }

        RUBY_DEBUG_LOG("completed seirial:%u", vm->ractor.sched.barrier_serial);

        // no other ractors are there
        vm->ractor.sched.barrier_serial++;
        vm->ractor.sched.barrier_joined_cnt = 0;
        rb_native_cond_broadcast(&vm->ractor.sched.barrier_release_cond);

        // acquire VM lock
        rb_native_mutex_lock(&vm->ractor.sync.lock);
        vm->ractor.sync.lock_rec = lock_rec;
        vm->ractor.sync.lock_owner = cr;
    }

    // do not release ractor_sched_lock and there is no newly added (resumed) thread
    // thread_sched_setup_running_threads
}

// called from vm_lock_leave if the vm_lock used for barrierred
void
rb_ractor_sched_barrier_end(rb_vm_t *vm, rb_ractor_t *cr)
{
    RUBY_DEBUG_LOG("serial:%u", (unsigned int)vm->ractor.sched.barrier_serial - 1);
    VM_ASSERT(vm->ractor.sched.barrier_is_waiting);
    VM_ASSERT(vm->ractor.sched.barrier_ractor);
    VM_ASSERT(vm->ractor.sched.barrier_lock_rec > 0);

    RUBY_ATOMIC_SET(vm->ractor.sched.barrier_is_waiting, 0);
    vm->ractor.sched.barrier_ractor = NULL;
    vm->ractor.sched.barrier_lock_rec = 0;
    ractor_sched_unlock(vm, cr);
}

static void
ractor_sched_barrier_join_signal_locked(rb_vm_t *vm)
{
    if (ractor_sched_barrier_completed_p(vm)) {
        rb_native_cond_signal(&vm->ractor.sched.barrier_complete_cond);
    }
}

static void
ractor_sched_barrier_join_wait_locked(rb_vm_t *vm, rb_thread_t *th)
{
    VM_ASSERT(vm->ractor.sched.barrier_is_waiting);

    unsigned int barrier_serial = vm->ractor.sched.barrier_serial;

    while (vm->ractor.sched.barrier_serial == barrier_serial) {
        RUBY_DEBUG_LOG("sleep serial:%u", barrier_serial);
        RB_VM_SAVE_MACHINE_CONTEXT(th);

        rb_ractor_t *cr = th->ractor;
        ractor_sched_set_unlocked(vm, cr);
        rb_native_cond_wait(&vm->ractor.sched.barrier_release_cond, &vm->ractor.sched.lock);
        ractor_sched_set_locked(vm, cr);

        RUBY_DEBUG_LOG("wakeup serial:%u", barrier_serial);
    }
}

void
rb_ractor_sched_barrier_join(rb_vm_t *vm, rb_ractor_t *cr)
{
    VM_ASSERT(cr->threads.sched.running != NULL); // running ractor
    VM_ASSERT(cr == GET_RACTOR());
    VM_ASSERT(vm->ractor.sync.lock_owner == NULL); // VM is locked, but owner == NULL
    VM_ASSERT(vm->ractor.sched.barrier_is_waiting);  // VM needs barrier sync

#if USE_RUBY_DEBUG_LOG || VM_CHECK_MODE > 0
    unsigned int barrier_serial = vm->ractor.sched.barrier_serial;
#endif

    RUBY_DEBUG_LOG("join");

    rb_native_mutex_unlock(&vm->ractor.sync.lock);
    {
        VM_ASSERT(vm->ractor.sched.barrier_is_waiting);  // VM needs barrier sync
        VM_ASSERT(vm->ractor.sched.barrier_serial == barrier_serial);

        ractor_sched_lock(vm, cr);
        {
            // running_cnt
            /* Every joiner is a member of the running set: a dying thread
             * leaves the living set before handing over its scheduler slot. */
            vm->ractor.sched.barrier_joined_cnt++;
            RUBY_DEBUG_LOG("waiting_cnt:%u serial:%u", vm->ractor.sched.barrier_joined_cnt, barrier_serial);

            ractor_sched_barrier_join_signal_locked(vm);
            ractor_sched_barrier_join_wait_locked(vm, cr->threads.sched.running);
        }
        ractor_sched_unlock(vm, cr);
    }

    rb_native_mutex_lock(&vm->ractor.sync.lock);
    // VM locked here
}

// Called when the ractor holding this sched is freed.  A drained sched can
// still be on timeslice.scheds (pruning is lazy); an unlisted node is
// self-linked (fork re-inits them all), making this del a no-op.
void
rb_thread_sched_destroy(struct rb_thread_sched *sched)
{
    rb_vm_t *vm = GET_VM();

    rb_native_mutex_lock(&vm->ractor.sched.timeslice.lock);
    {
        ccan_list_del_init(&sched->timeslice_node);
    }
    rb_native_mutex_unlock(&vm->ractor.sched.timeslice.lock);
}

#if defined(HAVE_WORKING_FORK)
static void rb_internal_thread_event_hooks_rw_lock_atfork(void);

static void
thread_sched_atfork(struct rb_thread_sched *sched)
{
    current_fork_gen++;
    rb_thread_sched_init(sched, true);
    rb_thread_t *th =  GET_THREAD();
    rb_vm_t *vm = GET_VM();

    if (th_has_dedicated_nt(th)) {
        vm->ractor.sched.snt_cnt = 0;
#if USE_RUBY_DEBUG_LOG
        vm->ractor.sched.dnt_cnt = 1;
#endif
    }
    else {
        vm->ractor.sched.snt_cnt = 1;
#if USE_RUBY_DEBUG_LOG
        vm->ractor.sched.dnt_cnt = 0;
#endif
    }

    rb_native_mutex_initialize(&vm->ractor.sched.lock);
#if VM_CHECK_MODE > 0
    vm->ractor.sched.lock_owner = NULL;
    vm->ractor.sched.locked = false;
#endif

    // rb_native_cond_destroy(&vm->ractor.sched.cond);
    rb_native_cond_initialize(&vm->ractor.sched.cond);
    rb_native_cond_initialize(&vm->ractor.sched.barrier_complete_cond);
    rb_native_cond_initialize(&vm->ractor.sched.barrier_release_cond);

    ccan_list_head_init(&vm->ractor.sched.grq);
    vm->ractor.sched.grq_cnt = 0; // the list was just emptied; reset the count with it
    // A fork during a VM barrier leaves the child with barrier state that can
    // never complete (the other ractors are gone); reset it like the rest.
    vm->ractor.sched.barrier_is_waiting = 0; // single-threaded child
    vm->ractor.sched.barrier_joined_cnt = 0;
    vm->ractor.sched.barrier_ractor = NULL;
    vm->ractor.sched.barrier_lock_rec = 0;
    // Threads that were winding down in the parent do not exist in the child;
    // without this reset the child's ruby_vm_destruct would wait for their
    // reclaim (which never comes) forever.
    vm->ractor.sched.winding_cnt = 0;
    rb_native_mutex_initialize(&vm->ractor.sched.ntlist.lock);
    ccan_list_head_init(&vm->ractor.sched.ntlist.running_dnts);
    ccan_list_head_init(&vm->ractor.sched.ntlist.snts); // those nts are gone
    rb_native_mutex_initialize(&vm->ractor.sched.timeslice.lock);
    ccan_list_head_init(&vm->ractor.sched.timeslice.scheds);
    rb_native_mutex_initialize(&th->nt->running_th_lock); // a scan could hold it at fork
    // Fork can copy nodes linked (or torn mid-link); re-init every sched's
    // node so rb_thread_sched_destroy's del_init stays a no-op for them.
    rb_ractor_t *r;
    ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
        ccan_list_node_init(&r->threads.sched.timeslice_node);
    }
    ccan_list_for_each(&vm->ractor.terminated_set, r, vmlr_node) {
        ccan_list_node_init(&r->threads.sched.timeslice_node);
    }
    // th re-records itself below; the parent's record did not survive the lists
    if (th->nt && th->nt->dedicated == 0) {
        // surviving on an snt: put that nt back on the (just emptied) snts
        // list, or the scans could not see this thread's record
        ccan_list_add(&vm->ractor.sched.ntlist.snts, &th->nt->snts_node);
    }

#if USE_MN_THREADS
    nt_machine_stack_atfork();
#endif
    rb_internal_thread_event_hooks_rw_lock_atfork();

    VM_ASSERT(sched->is_running);

    if (sched->running != th) {
        thread_sched_to_running(sched, th);
    }
    else {
        thread_sched_setup_running_threads(sched, th->ractor, vm, th, NULL);
    }

#ifdef RB_THREAD_T_HAS_NATIVE_ID
    if (th->nt) {
        th->nt->tid = get_native_thread_id();
    }
#endif
}

#endif

extern int ruby_mn_threads_enabled;

void
ruby_mn_threads_params(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ractor_t *main_ractor = GET_RACTOR();

    const char *mn_threads_cstr = getenv("RUBY_MN_THREADS");
    bool enable_mn_threads = false;

    if (USE_MN_THREADS && mn_threads_cstr && (enable_mn_threads = atoi(mn_threads_cstr) > 0)) {
        // enabled
        ruby_mn_threads_enabled = 1;
    }
    main_ractor->threads.sched.enable_mn_threads = enable_mn_threads;

    const char *max_cpu_cstr = getenv("RUBY_MAX_CPU");
    int max_cpu = native_thread_default_max_cpu();

    if (USE_MN_THREADS && max_cpu_cstr)  {
        int given_max_cpu = atoi(max_cpu_cstr);
        if (given_max_cpu > 0) {
            max_cpu = given_max_cpu;
        }
    }

    vm->ractor.sched.max_cpu = max_cpu;
}

static void
native_thread_dedicated_inc(rb_vm_t *vm, rb_ractor_t *cr, struct rb_native_thread *nt)
{
    RUBY_DEBUG_LOG("nt:%d %d->%d", nt->serial, nt->dedicated, nt->dedicated + 1);

    if (nt->dedicated == 0) {
        // Lock-free; pairs with ractor_sched_enq (enq: grq_cnt up then read
        // snt_cnt / here: snt_cnt down then read grq_cnt) against lost wakeups.
        if (RUBY_ATOMIC_FETCH_SUB(vm->ractor.sched.snt_cnt, 1) == 1) {
            // the last snt went dedicated; pending entries need the timer thread
            ractor_sched_lock(vm, cr);
            {
                if (vm->ractor.sched.grq_cnt > 0) {
                    timer_thread_wakeup_locked(vm);
                }
            }
            ractor_sched_unlock(vm, cr);
        }
#if USE_RUBY_DEBUG_LOG
        vm->ractor.sched.dnt_cnt++;
#endif
    }

    nt->dedicated++;
}

static void
native_thread_dedicated_dec(rb_vm_t *vm, rb_ractor_t *cr, struct rb_native_thread *nt)
{
    RUBY_DEBUG_LOG("nt:%d %d->%d", nt->serial, nt->dedicated, nt->dedicated - 1);
    VM_ASSERT(nt->dedicated > 0);
    nt->dedicated--;

    if (nt->dedicated == 0) {
        // Rejoin under the max_cpu cap; with no room this nt retires and
        // belongs to neither count until it ends.
        while (1) {
            rb_atomic_t snt = RUBY_ATOMIC_LOAD(vm->ractor.sched.snt_cnt);
            if (snt < vm->ractor.sched.max_cpu || (int)snt <= MINIMUM_SNT) {
                if (RUBY_ATOMIC_CAS(vm->ractor.sched.snt_cnt, snt, snt + 1) == snt) break;
            }
            else {
                nt->retiring = true;
                break;
            }
        }
#if USE_RUBY_DEBUG_LOG
        vm->ractor.sched.dnt_cnt--;
#endif
    }
}

static void
native_thread_assign(struct rb_native_thread *nt, rb_thread_t *th)
{
#if USE_RUBY_DEBUG_LOG
    if (nt) {
        if (th->nt) {
            RUBY_DEBUG_LOG("th:%d nt:%d->%d", (int)th->serial, (int)th->nt->serial, (int)nt->serial);
        }
        else {
            RUBY_DEBUG_LOG("th:%d nt:NULL->%d", (int)th->serial, (int)nt->serial);
        }
    }
    else {
        if (th->nt) {
            RUBY_DEBUG_LOG("th:%d nt:%d->NULL", (int)th->serial, (int)th->nt->serial);
        }
        else {
            RUBY_DEBUG_LOG("th:%d nt:NULL->NULL", (int)th->serial);
        }
    }
#endif

    th->nt = nt;
}

static int
native_thread_create_dedicated(rb_thread_t *th)
{
    th->nt = native_thread_alloc();
    th->nt->vm = th->vm;
    th->nt->running_thread = th;
    th->nt->dedicated = 1;

    // vm stack
    size_t vm_stack_word_size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
    void *vm_stack = ruby_xmalloc(vm_stack_word_size * sizeof(VALUE));
    th->sched.malloc_stack = true;
    rb_ec_initialize_vm_stack(th->ec, vm_stack, vm_stack_word_size);
    th->sched.context_stack = vm_stack;
    th->sched.context_stack_size = vm_stack_word_size;

    int err = native_thread_create0(th->nt);
    if (!err) {
        // setup
        thread_sched_to_ready(TH_SCHED(th), th);
    }
    return err;
}

static void
call_thread_start_func_2(rb_thread_t *th)
{
    /* Capture the address of a local in this stack frame to mark the beginning of the
       machine stack for this thread. This is required even if we can tell the real
       stack beginning from the pthread API in native_thread_init_stack, because
       glibc stores some of its own data on the stack before calling into user code
       on a new thread, and replacing that data on fiber-switch would break it (see
       bug #13887) */
    VALUE stack_start = 0;
    VALUE *stack_start_addr = asan_get_real_stack_addr(&stack_start);

    native_thread_init_stack(th, stack_start_addr);
    thread_start_func_2(th, th->ec->machine.stack_start);
}

static void *
nt_start(void *ptr)
{
    struct rb_native_thread *nt = (struct rb_native_thread *)ptr;
    rb_vm_t *vm = nt->vm;

    native_thread_setup_on_thread(nt);

    // init tid
#ifdef RB_THREAD_T_HAS_NATIVE_ID
    nt->tid = get_native_thread_id();
#endif

#if USE_RUBY_DEBUG_LOG && defined(RUBY_NT_SERIAL)
    ruby_nt_serial = nt->serial;
#endif

    RUBY_DEBUG_LOG("nt:%u", nt->serial);

    bool in_snts = false;

    if (!nt->dedicated) {
        coroutine_initialize_main(nt->nt_context);

        // join the snt list that the barrier/timeslice scans walk
        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            ccan_list_add(&vm->ractor.sched.ntlist.snts, &nt->snts_node);
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);
        in_snts = true;
    }

    bool retired = false;

    while (1) {
        if (nt->dedicated) {
            // wait running turn
            rb_thread_t *th = nt->running_thread;
            struct rb_thread_sched *sched = TH_SCHED(th);

            RUBY_DEBUG_LOG("on dedicated th:%u", rb_th_serial(th));
            ruby_thread_set_native(th);

            thread_sched_lock(sched, th);
            {
                if (sched->running == th) {
                    thread_sched_add_running_thread(sched, th);
                }
                thread_sched_wait_running_turn(sched, th, false, NULL);
            }
            thread_sched_unlock(sched, th);

            // start threads
            call_thread_start_func_2(th);
            break; // TODO: allow to change to the SNT
        }
        else {
            RUBY_DEBUG_LOG("check next");
            if (nt->retiring) {   // came back with no room in the shared pool
                retired = true;
                break;
            }

            rb_ractor_t *r = ractor_sched_deq(vm, NULL);

            if (r) {
                struct rb_thread_sched *sched = &r->threads.sched;

                bool locked = true;

                thread_sched_lock(sched, NULL);
                {
                    rb_thread_t *next_th = sched->running;

                    if (next_th && next_th->nt == NULL) {
                        RUBY_DEBUG_LOG("nt:%d next_th:%d", (int)nt->serial, (int)next_th->serial);
#if USE_MN_THREADS
                        thread_sched_switch0(nt->nt_context, next_th, nt, false);

                        // If a coroutine terminated during the transfer, co_start
                        // recorded it in nt->dead_co (switch0's return value is
                        // backend-dependent, unusable; see thread_pthread.h).
                        struct coroutine_context *dead_co = nt->dead_co;
                        nt->dead_co = NULL;
                        if (thread_sched_reclaim(dead_co)) {
                            // it already released the sched lock before its
                            // transfer (its Ractor may be gone): leave sched be.
                            locked = false;
                        }
#else
                        thread_sched_switch0(nt->nt_context, next_th, nt, false);
#endif
                    }
                    else {
                        RUBY_DEBUG_LOG("no schedulable threads -- next_th:%p", next_th);
                    }
                }
                if (locked) {
                    thread_sched_unlock(sched, NULL);
                }
            }
            else {
                // ractor_sched_deq retired this nt.
                retired = true;
                break;
            }

            if (nt->dedicated) {
                // SNT becomes DNT while running
                break;
            }
        }
    }

    if (in_snts) {
        // Leaving the shared loop: every path back here deregistered first
        // (park and death both precede the transfer), so only the snts entry
        // is left to remove.
        VM_ASSERT(nt->running_th == NULL);
        rb_native_mutex_lock(&vm->ractor.sched.ntlist.lock);
        {
            ccan_list_del_init(&nt->snts_node);
        }
        rb_native_mutex_unlock(&vm->ractor.sched.ntlist.lock);
    }

    if (retired) {
        // The counts dropped this nt already; nothing can reference it now.
        RUBY_DEBUG_LOG("retired nt:%u", nt->serial);
        native_thread_destroy_self(nt);
    }

    return NULL;
}

static int native_thread_create_shared(rb_thread_t *th);

#if USE_MN_THREADS
static void nt_free_stack(void *mstack);


// Reclaim the context a coroutine thread recorded in nt->dead_co before its
// final transfer (co_start's epilogue). Our running here proves that transfer's
// register save into the block completed. Returns true when a thread did
// terminate -- it RELEASED the sched lock before transferring; NULL/false means
// a live yield, where the loop still owns the lock.
static bool
thread_sched_reclaim(struct coroutine_context *dead_co)
{
    struct rb_thread_context *tctx = (struct rb_thread_context *)dead_co;

    if (tctx != NULL && tctx->dead) {
        nt_free_stack(tctx->stack);
        SIZED_FREE(tctx);
        // pairs with the increment at the top of coroutine_thread_terminated:
        // a waiting VM destruct may proceed once this reclaim is done
        VM_ASSERT(RUBY_ATOMIC_LOAD(GET_VM()->ractor.sched.winding_cnt) > 0);
        RUBY_ATOMIC_DEC(GET_VM()->ractor.sched.winding_cnt);
        return true;
    }
    return false;
}
#endif

void
rb_thread_wake_fence(rb_thread_t *th)
{
    timer_thread_wake_fence(th);
}

void
rb_threadptr_sched_free(rb_thread_t *th)
{
    timer_thread_wake_fence(th);
#if USE_MN_THREADS
    if (th->sched.malloc_stack) {
        // has dedicated
        SIZED_FREE_N((VALUE *)th->sched.context_stack, th->sched.context_stack_size);
        native_thread_destroy(th->nt);
    }
    else if (th->sched.context != NULL) {
        // a coroutine thread that never reached its epilogue (never started);
        // a terminated one is reclaimed by whoever resumed from its final
        // transfer (thread_sched_reclaim), and cleared this pointer.
        struct rb_thread_context *tctx = (struct rb_thread_context *)th->sched.context;
        nt_free_stack(tctx->stack);
        SIZED_FREE(tctx);
        th->sched.context = NULL;
        // TODO: how to free nt and nt->altstack?
    }
#else
    SIZED_FREE_N((VALUE *)th->sched.context_stack, th->sched.context_stack_size);
    native_thread_destroy(th->nt);
#endif

    th->nt = NULL;
}


static int
native_thread_create(rb_thread_t *th)
{
    VM_ASSERT(th->nt == 0);
    RUBY_DEBUG_LOG("th:%d has_dnt:%d", th->serial, th->has_dedicated_nt);
    RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_STARTED, th);

    if (!th->ractor->threads.sched.enable_mn_threads) {
        th->has_dedicated_nt = 1;
    }

    if (th->has_dedicated_nt) {
        return native_thread_create_dedicated(th);
    }
    else {
        return native_thread_create_shared(th);
    }
}

#ifdef USE_UBF_LIST
static CCAN_LIST_HEAD(ubf_list_head);
#ifdef RB_NATIVETHREAD_LOCK_INIT
static rb_nativethread_lock_t ubf_list_lock = RB_NATIVETHREAD_LOCK_INIT;
#else
// no static initializer on this platform; thread_sched_init_vm() does it
static rb_nativethread_lock_t ubf_list_lock;
#endif

static void
ubf_list_atfork(void)
{
    ccan_list_head_init(&ubf_list_head);
    rb_native_mutex_initialize(&ubf_list_lock);
}

RBIMPL_ATTR_MAYBE_UNUSED()
static bool
ubf_list_contain_p(rb_thread_t *th)
{
    rb_thread_t *list_th;
    ccan_list_for_each(&ubf_list_head, list_th, sched.node.ubf) {
        if (list_th == th) return true;
    }
    return false;
}

/* The thread 'th' is registered to be trying unblock. */
static void
register_ubf_list(rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));
    struct ccan_list_node *node = &th->sched.node.ubf;

    VM_ASSERT(th->unblock.func != NULL);

    rb_native_mutex_lock(&ubf_list_lock);
    {
        // check not connected yet
        if (ccan_list_empty((struct ccan_list_head*)node)) {
            VM_ASSERT(!ubf_list_contain_p(th));
            ccan_list_add(&ubf_list_head, node);
        }
    }
    rb_native_mutex_unlock(&ubf_list_lock);

    timer_thread_wakeup();
}

/* The thread 'th' is unblocked. It no longer need to be registered. */
static void
unregister_ubf_list(rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u", rb_th_serial(th));
    struct ccan_list_node *node = &th->sched.node.ubf;

    /* we can't allow re-entry into ubf_list_head */
    VM_ASSERT(th->unblock.func == NULL);

    if (!ccan_list_empty((struct ccan_list_head*)node)) {
        rb_native_mutex_lock(&ubf_list_lock);
        {
            VM_ASSERT(ubf_list_contain_p(th));
            ccan_list_del_init(node);
        }
        rb_native_mutex_unlock(&ubf_list_lock);
    }
}

/*
 * Poke the target thread so that it returns from a blocking syscall.
 * How that is done is up to the platform (native_thread_interrupt).
 */
static void
ubf_wakeup_thread(rb_thread_t *th)
{
    RUBY_DEBUG_LOG("th:%u thread_id:%p", rb_th_serial(th), (void *)th->nt->thread_id);

    native_thread_interrupt(th);
}

static void
ubf_select(void *ptr)
{
    rb_thread_t *th = (rb_thread_t *)ptr;
    RUBY_DEBUG_LOG("wakeup th:%u", rb_th_serial(th));
    ubf_wakeup_thread(th);
    register_ubf_list(th);
}

static bool
ubf_threads_empty(void)
{
    return ccan_list_empty(&ubf_list_head) != 0;
}

static void
ubf_wakeup_all_threads(void)
{
    rb_thread_t *th;
    rb_native_mutex_lock(&ubf_list_lock);
    {
        ccan_list_for_each(&ubf_list_head, th, sched.node.ubf) {
            ubf_wakeup_thread(th);
        }
    }
    rb_native_mutex_unlock(&ubf_list_lock);
}

#else /* USE_UBF_LIST */
#define register_ubf_list(th) (void)(th)
#define unregister_ubf_list(th) (void)(th)
#define ubf_select 0
static void ubf_wakeup_all_threads(void) { return; }
static bool ubf_threads_empty(void) { return true; }
#define ubf_list_atfork() do {} while (0)
#endif /* USE_UBF_LIST */

static int
timer_thread_set_timeout(rb_vm_t *vm)
{
#if 0
    return 10; // ms
#else
    int timeout = -1;

    ractor_sched_lock(vm, NULL);
    {
        if (   timeslice_scan(vm, false)                             // (1-1) Provide time slice for active NTs
            || !ubf_threads_empty()                                  // (1-3) Periodic UBF
            || vm->ractor.sched.grq_cnt > 0                          // (1-4) Lazy GRQ deq start
            ) {

            RUBY_DEBUG_LOG("ubf:%d grq:%d",
                           !ubf_threads_empty(),
                           (vm->ractor.sched.grq_cnt > 0));

            timeout = 10; // ms
            vm->ractor.sched.timeslice_wait_inf = false;
        }
        else {
            vm->ractor.sched.timeslice_wait_inf = true;
        }
    }
    ractor_sched_unlock(vm, NULL);

    timeout = timer_wheel_timeout(timeout);

    RUBY_DEBUG_LOG("timeout:%d inf:%d", timeout, (int)vm->ractor.sched.timeslice_wait_inf);

    // fprintf(stderr, "timeout:%d\n", timeout);
    return timeout;
#endif
}

static void
timer_thread_check_signal(rb_vm_t *vm)
{
    // ruby_sigchld_handler(vm); TODO

    int signum = rb_signal_buff_size();
    if (UNLIKELY(signum > 0) && vm->ractor.main_thread) {
        RUBY_DEBUG_LOG("signum:%d", signum);
        threadptr_trap_interrupt(vm->ractor.main_thread);
    }
}

// Tick (with `interrupt`) each listed sched's running thread and prune scheds
// whose readyq drained; returns whether any sched still needs ticks.
static bool
timeslice_scan(rb_vm_t *vm, bool interrupt)
{
    bool found = false;
    struct rb_thread_sched *sched, *next;

    rb_native_mutex_lock(&vm->ractor.sched.timeslice.lock);
    {
        ccan_list_for_each_safe(&vm->ractor.sched.timeslice.scheds, sched, next, timeslice_node) {
            // trylock: timeslice_sched_link nests sched.lock -> timeslice.lock,
            // this scan holds the locks the other way around
            if (rb_native_mutex_trylock(&sched->lock_) == 0) {
                if (ccan_list_empty(&sched->readyq)) {
                    ccan_list_del_init(&sched->timeslice_node); // a later enq relinks it
                }
                else if (sched->is_running) {
                    VM_ASSERT(sched->running != NULL);
                    found = true;
                    if (interrupt) {
                        RUBY_DEBUG_LOG("timeslice th:%u", rb_th_serial(sched->running));
                        RUBY_VM_SET_TIMER_INTERRUPT(sched->running->ec);
                    }
                }
                // else: waiters behind a blocked runner need no ticks; the
                // add path wakes the timer when the sched runs again
                rb_native_mutex_unlock(&sched->lock_);
            }
            else {
                found = true; // busy switching; tick it on the next round
            }
        }
    }
    rb_native_mutex_unlock(&vm->ractor.sched.timeslice.lock);

    return found;
}

static void
timer_thread_check_timeslice(rb_vm_t *vm)
{
    // TODO: check time
    timeslice_scan(vm, true);
}

static void *
timer_thread_func(void *ptr)
{
    rb_vm_t *vm = (rb_vm_t *)ptr;
#if defined(RUBY_NT_SERIAL)
    ruby_nt_serial = (rb_atomic_t)-1;
#endif

    RUBY_DEBUG_LOG("started%s", "");

    while (RUBY_ATOMIC_LOAD(system_working)) {
        timer_thread_check_signal(vm);
        timer_thread_check_timeout(vm);
        ubf_wakeup_all_threads();

        RUBY_DEBUG_LOG("system_working:%d", RUBY_ATOMIC_LOAD(system_working));
        timer_thread_polling(vm);
    }

    RUBY_DEBUG_LOG("terminated");
    return NULL;
}

static void
timer_thread_wakeup_locked(rb_vm_t *vm)
{
    // should be locked before.
    ASSERT_ractor_sched_locked(vm, NULL);

    if (TIMER_THREAD_CREATED_P()) {
        if (vm->ractor.sched.timeslice_wait_inf) {
            RUBY_DEBUG_LOG("wakeup%s", "");
            timer_thread_wakeup_force();
        }
        else {
            RUBY_DEBUG_LOG("will be wakeup...");
        }
    }
}

static void
timer_thread_wakeup(void)
{
    rb_vm_t *vm = GET_VM();

    ractor_sched_lock(vm, NULL);
    {
        timer_thread_wakeup_locked(vm);
    }
    ractor_sched_unlock(vm, NULL);
}

static void
native_sleep(rb_thread_t *th, rb_hrtime_t *rel)
{
    struct rb_thread_sched *sched = TH_SCHED(th);

    RUBY_DEBUG_LOG("rel:%d", rel ? (int)*rel : 0);

    if (rel && !th_has_dedicated_nt(th)) {
        // an M:N thread has no condvar of its own: the timer thread wakes it
        thread_sched_wait_events(sched, th, -1, thread_sched_waiting_timeout, rel);
    }
    else if (rel) {
        /* Solaris cond_timedwait() returns EINVAL if an argument is greater than
         * current_time + 100,000,000.  So cut up to 100,000,000.  This is
         * considered as a kind of spurious wakeup.  The caller to native_sleep
         * should care about spurious wakeup.
         *
         * See also [Bug #1341] [ruby-core:29702]
         * http://download.oracle.com/docs/cd/E19683-01/816-0216/6m6ngupgv/index.html
         */
        const rb_hrtime_t max = (rb_hrtime_t)100000000 * RB_HRTIME_PER_SEC;
        if (*rel > max) *rel = max;

        rb_hrtime_t end = rb_hrtime_add(rb_hrtime_now(), *rel);
        thread_sched_to_waiting_until_wakeup(sched, th, &end);
    }
    else {
        thread_sched_to_waiting_until_wakeup(sched, th, NULL);
    }

    RUBY_DEBUG_LOG("wakeup");
}


// return true if the current thread acquires DNT.
// return false if the current thread already acquires DNT.
bool
rb_thread_lock_native_thread(void)
{
    rb_thread_t *th = GET_THREAD();
    bool is_snt = th->nt->dedicated == 0;
    native_thread_dedicated_inc(th->vm, th->ractor, th->nt);

    return is_snt;
}

void
rb_thread_malloc_stack_set(rb_thread_t *th, void *stack, size_t stack_size)
{
    th->sched.malloc_stack = true;
    th->sched.context_stack = stack;
    th->sched.context_stack_size = stack_size;
}

// VM wide scheduler state, shared by every platform.  Called from
// Init_native_thread() before the main thread is recorded.
static void
thread_sched_init_vm(rb_vm_t *vm)
{
    rb_native_mutex_initialize(&vm->ractor.sched.lock);
    rb_native_cond_initialize(&vm->ractor.sched.cond);
    rb_native_cond_initialize(&vm->ractor.sched.barrier_complete_cond);
    rb_native_cond_initialize(&vm->ractor.sched.barrier_release_cond);

    ccan_list_head_init(&vm->ractor.sched.grq);
    rb_native_mutex_initialize(&vm->ractor.sched.ntlist.lock);
    ccan_list_head_init(&vm->ractor.sched.ntlist.running_dnts);
    ccan_list_head_init(&vm->ractor.sched.ntlist.snts);
    rb_native_mutex_initialize(&vm->ractor.sched.timeslice.lock);
    ccan_list_head_init(&vm->ractor.sched.timeslice.scheds);

#ifndef RB_NATIVETHREAD_LOCK_INIT
    // ubf_list_lock could not be initialized statically
    ubf_list_atfork();
#endif
}
