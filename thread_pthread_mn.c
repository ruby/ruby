// included by "thread_pthread.c"

#if USE_MN_THREADS

static void timer_thread_unregister_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags);
static void timer_thread_wakeup_thread_locked(struct rb_thread_sched *sched, rb_thread_t *th, uint32_t event_serial);

static bool
timer_thread_cancel_waiting(rb_thread_t *th)
{
    bool canceled = false;

    rb_native_mutex_lock(&timer_th.waiting_lock);
    {
        if (th->sched.waiting_reason.flags) {
            canceled = true;
            ccan_list_del_init(&th->sched.waiting_reason.node);
            timer_thread_unregister_waiting(th, th->sched.waiting_reason.data.fd, th->sched.waiting_reason.flags);
            th->sched.waiting_reason.flags = thread_sched_waiting_none;
        }
    }
    rb_native_mutex_unlock(&timer_th.waiting_lock);

    return canceled;
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
                thread_sched_wait_running_turn(sched, th, true);
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
// 0th page is Redzone. Start from 1st page.

/*
 *            <--> machine stack + vm stack
 * ----------------------------------
 * |HD...|RZ| ... |RZ| ...   ... |RZ|
 * <------------- 512MB ------------->
 */

static struct nt_stack_chunk_header {
    struct nt_stack_chunk_header *prev_chunk;
    struct nt_stack_chunk_header *prev_free_chunk;

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

#include <sys/mman.h>

// vm_stack_size + machine_stack_size + 1 * (guard page size)
static inline size_t
nt_thread_stack_size(void)
{
    static size_t msz;
    if (LIKELY(msz > 0)) return msz;

    rb_vm_t *vm = GET_VM();
    int sz = (int)(vm->default_params.thread_vm_stack_size + vm->default_params.thread_machine_stack_size + MSTACK_PAGE_SIZE);
    int page_num = roomof(sz, MSTACK_PAGE_SIZE);
    msz = (size_t)page_num * MSTACK_PAGE_SIZE;
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
    guard_page = vstack + vm->default_params.thread_vm_stack_size;
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
                size_t vm_stack_size = vm->default_params.thread_vm_stack_size;
                size_t mstack_size = nt_thread_stack_size() - vm_stack_size - MSTACK_PAGE_SIZE;
                char *mstack_start = stack_start + vm_stack_size + MSTACK_PAGE_SIZE;

                int mstack_flags = MAP_FIXED | MAP_ANONYMOUS | MAP_PRIVATE;
#if defined(MAP_STACK) && !defined(__FreeBSD__) && !defined(__FreeBSD_kernel__)
                mstack_flags |= MAP_STACK;
#endif

                if (mprotect(stack_start, vm_stack_size, PROT_READ | PROT_WRITE) != 0 ||
                    mmap(mstack_start, mstack_size, PROT_READ | PROT_WRITE, mstack_flags, -1, 0) == MAP_FAILED) {
                    err = errno;
                }
                else {
                    nt_stack_chunk_get_stack(vm, ch, idx, vm_stack, machine_stack);
                }
            }
            else {
                nt_free_stack_chunks = ch->prev_free_chunk;
                ch->prev_free_chunk = NULL;
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

        if (ch->prev_free_chunk == NULL) {
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

    rb_native_mutex_lock(&vm->ractor.sched.lock);
    {
        unsigned int schedulable_ractor_cnt = vm->ractor.cnt;
        RUBY_ASSERT(schedulable_ractor_cnt >= 1);

        if (!vm->ractor.main_ractor->threads.sched.enable_mn_threads)
            schedulable_ractor_cnt--; // do not need snt for main ractor

        unsigned int snt_cnt = vm->ractor.sched.snt_cnt;
        if (((int)snt_cnt < MINIMUM_SNT) ||
            (snt_cnt < schedulable_ractor_cnt  &&
             snt_cnt < vm->ractor.sched.max_cpu)) {

            RUBY_DEBUG_LOG("added snt:%u dnt:%u ractor_cnt:%u grq_cnt:%u",
                           vm->ractor.sched.snt_cnt,
                           vm->ractor.sched.dnt_cnt,
                           vm->ractor.cnt,
                           vm->ractor.sched.grq_cnt);

            vm->ractor.sched.snt_cnt++;
            need_to_make = true;
        }
        else {
            RUBY_DEBUG_LOG("snt:%d ractor_cnt:%d", (int)vm->ractor.sched.snt_cnt, (int)vm->ractor.cnt);
        }
    }
    rb_native_mutex_unlock(&vm->ractor.sched.lock);

    if (need_to_make) {
        struct rb_native_thread *nt = native_thread_alloc();
        nt->vm = vm;
        int err = native_thread_create0(nt);
        if (err) {
            // Roll back, or this function would conclude forever that the
            // pool is wide enough and never try again.
            rb_native_mutex_lock(&vm->ractor.sched.lock);
            vm->ractor.sched.snt_cnt--;
            rb_native_mutex_unlock(&vm->ractor.sched.lock);
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
    RUBY_ATOMIC_INC(th->vm->ractor.sched.winding_cnt);

    rb_thread_t *wake_th;

    // Leave the living set BEFORE handing over the scheduler slot: the
    // removal's VM-lock work (ractor_check_blocking, a barrier join) then
    // runs as an ordinary counted running thread. Afterwards th may be
    // unreachable, but no GC can complete while th still owns the slot
    // (a barrier waits for it to join), so the handoff below may keep
    // touching th/sched.
    //
    // The Ractor's last thread is the exception and keeps the reverse
    // order (below): its removal unlinks the Ractor itself, after which
    // r/sched must not be touched. That order is safe only for it: with
    // no successor, sched->running stays NULL, so the removal's VM lock
    // never joins a barrier (vm_need_barrier requires a running thread).
    VM_ASSERT(sched->running == th); // th owns the slot through the removal
    if (!last) rb_ractor_living_threads_remove(r, th);

    thread_sched_lock(sched, th);
    {
        // designate the successor (running = next from readyq, or NULL); for
        // a dedicated nt (will_switch false) this also enqueues the Ractor.
        thread_sched_to_dead_common(sched, th);

        // Only the successor WE designated here may be enqueued by this
        // epilogue (below). If readyq was empty, running is now NULL and a
        // waker (e.g. the timer thread) that later installs a runnable
        // thread enqueues the Ractor itself -- enqueuing "whatever is
        // running" at that point would duplicate its entry. While running
        // is non-NULL, nobody else re-assigns it, so wake_th stays valid
        // until we enqueue.
        wake_th = is_dnt ? NULL : sched->running;

        tctx->nt = th->nt;        // stash the final transfer target for co_start
        native_thread_assign(NULL, th);
        th->sched.context = NULL; // the wrapper's dfree must not reclaim tctx
    }
    thread_sched_unlock(sched, th);

    if (last) {
        // The reverse order is safe only with no successor: running == NULL
        // means the removal's VM lock cannot join a barrier (vm_need_barrier).
        VM_ASSERT(sched->running == NULL);
        VM_ASSERT(wake_th == NULL);
        // Last access to th/r: the removal may unlink the Ractor, after
        // which the GC may collect th and r.
        rb_ractor_living_threads_remove(r, th);
        rb_current_ec_set(NULL); // TLS only; r may be collectable already
    }
    else {
        rb_ractor_set_current_ec(r, NULL); // r alive: it has other threads

        if (wake_th && wake_th->nt == NULL) {
            // enqueue the successor designated above -- exactly once per
            // "runnable but unserved" period, by its designator.
            thread_sched_lock(sched, NULL);
            ractor_sched_enq(wake_th->vm, r);
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

#else // USE_MN_THREADS

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

#endif // USE_MN_THREADS

/// EPOLL/KQUEUE specific code
#if (HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H) && USE_MN_THREADS

/// Per-fd waiter table (struct rb_fd_waiters).  One fd may have several waiters
/// -- a reader and a writer on one socket -- so the backend is armed with their
/// union, and an event is dispatched to every waiter it concerns.

#define FD_WAIT_IO_MASK (thread_sched_waiting_io_read | thread_sched_waiting_io_write)

#define FDMAP_CHUNK_BITS 10
#define FDMAP_CHUNK_SIZE (1u << FDMAP_CHUNK_BITS)
#define FDMAP_CHUNK_MASK (FDMAP_CHUNK_SIZE - 1)

// timer_th.waiting_lock must be held.
static struct rb_fd_waiters *
fd_waiters_lookup(int fd, bool create)
{
    if (fd < 0) return NULL;

    unsigned int ci = (unsigned int)fd >> FDMAP_CHUNK_BITS;

    if (ci >= timer_th.fdmap_nchunks) {
        if (!create) return NULL;

        unsigned int n = timer_th.fdmap_nchunks ? timer_th.fdmap_nchunks : 8;
        while (n <= ci) n *= 2;

        // Only the chunk pointers are reallocated; the entries themselves never
        // move, so the list heads inside them stay valid.
        struct rb_fd_waiters **chunks = realloc(timer_th.fdmap_chunks, sizeof(*chunks) * n);
        if (chunks == NULL) rb_bug("fd_waiters_lookup: realloc failed");

        for (unsigned int i = timer_th.fdmap_nchunks; i < n; i++) chunks[i] = NULL;
        timer_th.fdmap_chunks = chunks;
        timer_th.fdmap_nchunks = n;
    }

    if (timer_th.fdmap_chunks[ci] == NULL) {
        if (!create) return NULL;

        struct rb_fd_waiters *chunk = calloc(FDMAP_CHUNK_SIZE, sizeof(*chunk));
        if (chunk == NULL) rb_bug("fd_waiters_lookup: calloc failed");

        for (unsigned int i = 0; i < FDMAP_CHUNK_SIZE; i++) {
            ccan_list_head_init(&chunk[i].waiters);
        }
        timer_th.fdmap_chunks[ci] = chunk;
    }

    return &timer_th.fdmap_chunks[ci][(unsigned int)fd & FDMAP_CHUNK_MASK];
}

// timer_th.waiting_lock must be held.
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
// timer_th.waiting_lock must be held.
static bool
fd_waiters_arm(int fd, struct rb_fd_waiters *e, uint32_t want)
{
    if (want == e->armed_flags) return true;

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
        if (epoll_ctl(timer_th.event_fd, EPOLL_CTL_DEL, fd, NULL) == -1) {
            switch (errno) {
              case EBADF:
              case ENOENT:
                // the fd is already closed or gone from the set
                break;
              default:
                perror("epoll_ctl");
                rb_bug("fd_waiters_arm/epoll_ctl del failed (fd:%d errno:%d)", fd, errno);
            }
        }
        // Anything epoll_wait already queued for the old arming is stale now.
        e->generation++;
        e->armed_flags = 0;
        return true;
    }

    uint32_t epoll_events = 0;
    if (want & thread_sched_waiting_io_read)  epoll_events |= EPOLLIN;
    if (want & thread_sched_waiting_io_write) epoll_events |= EPOLLOUT;

    struct epoll_event event = {
        .events = epoll_events,
        .data = { .u64 = fd_event_tag(fd, e->generation) },
    };

    int op = e->armed_flags ? EPOLL_CTL_MOD : EPOLL_CTL_ADD;

    if (epoll_ctl(timer_th.event_fd, op, fd, &event) == -1) {
        switch (errno) {
          case ENOENT:
            // Not registered after all: the fd was closed and reopened. Add it.
            if (op == EPOLL_CTL_MOD &&
                epoll_ctl(timer_th.event_fd, EPOLL_CTL_ADD, fd, &event) == 0) {
                break;
            }
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
            return false;
          default:
            perror("epoll_ctl");
            rb_bug("fd_waiters_arm/epoll_ctl failed (fd:%d op:%d errno:%d)", fd, op, errno);
        }
    }
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
    struct rb_thread_sched_waiting *w, *prev_w = NULL;

    // waiting list's timeout order should be [1, 2, 3, ..., 0, 0, 0]

    ccan_list_for_each(&timer_th.waiting, w, node) {
        // fprintf(stderr, "verify_waiting_list th:%u abs:%lu\n", rb_th_serial(wth), (unsigned long)wth->sched.waiting_reason.data.timeout);
        if (prev_w) {
            rb_hrtime_t timeout = w->data.timeout;
            rb_hrtime_t prev_timeout = w->data.timeout;
            VM_ASSERT(timeout == 0 || prev_timeout <= timeout);
        }
        prev_w = w;
    }
#endif
}

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

    if (rel && *rel > 0) {
        flags |= thread_sched_waiting_timeout;
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

    rb_native_mutex_lock(&timer_th.waiting_lock);
    {
        if (flags & FD_WAIT_IO_MASK) {
            VM_ASSERT(th != NULL);

            struct rb_fd_waiters *e = fd_waiters_lookup(fd, true);

            // Arm the union of what this fd's waiters want, so a second waiter
            // on the same fd extends the arming instead of colliding with it.
            if (!fd_waiters_arm(fd, e, fd_waiters_union(e) | (uint32_t)(flags & FD_WAIT_IO_MASK))) {
                rb_native_mutex_unlock(&timer_th.waiting_lock);
                return timer_thread_unavailable;
            }

            ccan_list_add_tail(&e->waiters, &th->sched.waiting_reason.fd_node);
            RUBY_DEBUG_LOG("armed fd:%d want:%u", fd, e->armed_flags);
        }

        if (th) {
            VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);

            // setup waiting information
            {
                th->sched.waiting_reason.flags = flags;
                th->sched.waiting_reason.data.timeout = abs;
                th->sched.waiting_reason.data.fd = fd;
                th->sched.waiting_reason.data.result = 0;
                th->sched.waiting_reason.data.event_serial = event_serial;
            }

            if (abs == 0) { // no timeout
                VM_ASSERT(!(flags & thread_sched_waiting_timeout));
                ccan_list_add_tail(&timer_th.waiting, &th->sched.waiting_reason.node);
            }
            else {
                RUBY_DEBUG_LOG("abs:%lu", (unsigned long)abs);
                VM_ASSERT(flags & thread_sched_waiting_timeout);

                // insert th to sorted list (TODO: O(n))
                struct rb_thread_sched_waiting *w, *prev_w = NULL;

                ccan_list_for_each(&timer_th.waiting, w, node) {
                    if ((w->flags & thread_sched_waiting_timeout) &&
                        w->data.timeout < abs) {
                        prev_w = w;
                    }
                    else {
                        break;
                    }
                }

                if (prev_w) {
                    ccan_list_add_after(&timer_th.waiting, &prev_w->node, &th->sched.waiting_reason.node);
                }
                else {
                    ccan_list_add(&timer_th.waiting, &th->sched.waiting_reason.node);
                }

                verify_waiting_list();

                // update timeout seconds; force wake so timer thread notices short deadlines
                timer_thread_wakeup_force();
            }
        }
        else {
            VM_ASSERT(abs == 0);
        }
    }
    rb_native_mutex_unlock(&timer_th.waiting_lock);

    return timer_thread_registered;
}

// Drop `th` from its fd's waiter list and re-arm the backend for whoever is
// left.  timer_th.waiting_lock must be held.
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
        fd_waiters_arm(fd, e, fd_waiters_union(e));
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
    struct { rb_thread_t *th; uint32_t serial; } batch[FD_WAKE_BATCH];

    if (wake_flags == 0) return;

    for (;;) {
        int n = 0;
        bool more = false;

        rb_native_mutex_lock(&timer_th.waiting_lock);
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
                    ccan_list_del_init(&w->node); // also leaves the timeout list

                    w->flags = thread_sched_waiting_none;
                    w->data.fd = -1;
                    w->data.result = result;

                    batch[n].th = thread_sched_waiting_thread(w);
                    batch[n].serial = w->data.event_serial;
                    n++;
                }

                // Re-arm for whoever is still waiting on this fd (nothing, if
                // they all just woke up).
                fd_waiters_arm(fd, e, fd_waiters_union(e));
            }
        }
        rb_native_mutex_unlock(&timer_th.waiting_lock);

        for (int i = 0; i < n; i++) {
            timer_thread_wakeup_thread(batch[i].th, batch[i].serial);
        }

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

#else // HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H

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

#endif // HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H
