// included by "thread_pthread.c"

#if USE_MN_THREADS

static void timer_thread_unregister_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags);

static bool
timer_thread_cancel_waiting(rb_thread_t *th)
{
    bool canceled = false;

    if (th->sched.waiting_reason.flags) {
        rb_native_mutex_lock(&timer_th.waiting_lock);
        {
            if (th->sched.waiting_reason.flags) {
                canceled = true;
                ccan_list_del_init(&th->sched.waiting_reason.node);
                if (th->sched.waiting_reason.flags & (thread_sched_waiting_io_read | thread_sched_waiting_io_write)) {
                    timer_thread_unregister_waiting(th, th->sched.waiting_reason.data.fd, th->sched.waiting_reason.flags);
                }
                th->sched.waiting_reason.flags = thread_sched_waiting_none;
            }
        }
        rb_native_mutex_unlock(&timer_th.waiting_lock);
    }

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

    bool canceled = timer_thread_cancel_waiting(th);

    thread_sched_lock(sched, th);
    {
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

static bool timer_thread_register_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags, rb_hrtime_t *rel);

// return true if timed out
static bool
thread_sched_wait_events(struct rb_thread_sched *sched, rb_thread_t *th, int fd, enum thread_sched_waiting_flag events, rb_hrtime_t *rel)
{
    VM_ASSERT(!th_has_dedicated_nt(th));  // on SNT

    volatile bool timedout = false, need_cancel = false;

    if (timer_thread_register_waiting(th, fd, events, rel)) {
        RUBY_DEBUG_LOG("wait fd:%d", fd);

        RB_VM_SAVE_MACHINE_CONTEXT(th);
        setup_ubf(th, ubf_event_waiting, (void *)th);

        RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, th);

        thread_sched_lock(sched, th);
        {
            if (th->sched.waiting_reason.flags == thread_sched_waiting_none) {
                // already awaken
            }
            else if (RUBY_VM_INTERRUPTED(th->ec)) {
                need_cancel = true;
            }
            else {
                RUBY_DEBUG_LOG("sleep");

                th->status = THREAD_STOPPED_FOREVER;
                thread_sched_wakeup_next_thread(sched, th, true);
                thread_sched_wait_running_turn(sched, th, true);

                RUBY_DEBUG_LOG("wakeup");
            }

            timedout = th->sched.waiting_reason.data.result == 0;
        }
        thread_sched_unlock(sched, th);

        if (need_cancel) {
            timer_thread_cancel_waiting(th);
        }

        setup_ubf(th, NULL, NULL); // TODO: maybe it is already NULL?

        th->status = THREAD_RUNNABLE;
    }
    else {
        RUBY_DEBUG_LOG("can not wait fd:%d", fd);
        return false;
    }

    VM_ASSERT(sched->running == th);

    return timedout;
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
    int mmap_flags = MAP_ANONYMOUS | MAP_PRIVATE;
#if defined(MAP_STACK) && !defined(__FreeBSD__) && !defined(__FreeBSD_kernel__)
    mmap_flags |= MAP_STACK;
#endif

    const char *m = (void *)mmap(NULL, MSTACK_CHUNK_SIZE, PROT_READ | PROT_WRITE, mmap_flags, -1, 0);
    if (m == MAP_FAILED) {
        return NULL;
    }

    size_t msz = nt_thread_stack_size();
    int header_page_cnt = 1;
    int stack_count = ((MSTACK_CHUNK_PAGE_NUM - header_page_cnt) * MSTACK_PAGE_SIZE) / msz;
    int ch_size = sizeof(struct nt_stack_chunk_header) + sizeof(uint16_t) * stack_count;

    if (ch_size > MSTACK_PAGE_SIZE * header_page_cnt) {
        header_page_cnt = (ch_size + MSTACK_PAGE_SIZE - 1) / MSTACK_PAGE_SIZE;
        stack_count = ((MSTACK_CHUNK_PAGE_NUM - header_page_cnt) * MSTACK_PAGE_SIZE) / msz;
    }

    VM_ASSERT(stack_count <= UINT16_MAX);

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

static void *
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

    return (void *)guard_page;
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
nt_guard_page(const char *p, size_t len)
{
    if (mprotect((void *)p, len, PROT_NONE) != -1) {
        return 0;
    }
    else {
        return errno;
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
                void *guard_page = nt_stack_chunk_get_stack(vm, ch, idx, vm_stack, machine_stack);
                err = nt_guard_page(guard_page, MSTACK_PAGE_SIZE);
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
#if defined(MADV_FREE)
        int r = madvise(stack, nt_thread_stack_size(), MADV_FREE);
#elif defined(MADV_DONTNEED)
        int r = madvise(stack, nt_thread_stack_size(), MADV_DONTNEED);
#else
        int r = 0;
#endif

        if (r != 0) rb_bug("madvise errno:%d", errno);
    }
    rb_native_mutex_unlock(&nt_machine_stack_lock);
}

static int
native_thread_check_and_create_shared(rb_vm_t *vm)
{
    bool need_to_make = false;

    rb_native_mutex_lock(&vm->ractor.sched.lock);
    {
        unsigned int snt_cnt = vm->ractor.sched.snt_cnt;
        if (!vm->ractor.main_ractor->threads.sched.enable_mn_threads) snt_cnt++; // do not need snt for main ractor

        if (((int)snt_cnt < MINIMUM_SNT) ||
            (snt_cnt < vm->ractor.cnt  &&
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
        return native_thread_create0(nt);
    }
    else {
        return 0;
    }
}

static COROUTINE
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

    thread_sched_set_lock_owner(sched, th);
    thread_sched_add_running_thread(TH_SCHED(th), th);
    thread_sched_unlock(sched, th);
    {
        RB_INTERNAL_THREAD_HOOK(RUBY_INTERNAL_THREAD_EVENT_RESUMED, th);
        call_thread_start_func_2(th);
    }
    thread_sched_lock(sched, NULL);

    RUBY_DEBUG_LOG("terminated th:%d", (int)th->serial);

    // Thread is terminated

    struct rb_native_thread *nt = th->nt;
    bool is_dnt = th_has_dedicated_nt(th);
    native_thread_assign(NULL, th);
    rb_ractor_set_current_ec(th->ractor, NULL);

    if (is_dnt) {
        // SNT became DNT while running. Just return to the nt_context

        th->sched.finished = true;
        coroutine_transfer0(self, nt->nt_context, true);
    }
    else {
        rb_vm_t *vm = th->vm;
        bool has_ready_ractor = vm->ractor.sched.grq_cnt > 0; // at least this ractor is not queued
        rb_thread_t *next_th = sched->running;

        if (!has_ready_ractor && next_th && !next_th->nt) {
            // switch to the next thread
            thread_sched_set_lock_owner(sched, NULL);
            thread_sched_switch0(th->sched.context, next_th, nt, true);
            th->sched.finished = true;
        }
        else {
            // switch to the next Ractor
            th->sched.finished = true;
            coroutine_transfer0(self, nt->nt_context, true);
        }
    }

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

    th->sched.context = ruby_xmalloc(sizeof(struct coroutine_context));
    coroutine_initialize(th->sched.context, co_start, machine_stack, machine_stack_size);
    th->sched.context->argument = th;

    RUBY_DEBUG_LOG("th:%u vm_stack:%p machine_stack:%p", rb_th_serial(th), vm_stack, machine_stack);
    thread_sched_to_ready(TH_SCHED(th), th);

    // setup nt
    return native_thread_check_and_create_shared(th->vm);
}

#else // USE_MN_THREADS

static int
native_thread_create_shared(rb_thread_t *th)
{
    rb_bug("unreachable");
}

static bool
thread_sched_wait_events(struct rb_thread_sched *sched, rb_thread_t *th, int fd, enum thread_sched_waiting_flag events, rb_hrtime_t *rel)
{
    rb_bug("unreachable");
}

#endif // USE_MN_THREADS

/// EPOLL/KQUEUE specific code
#if (HAVE_SYS_EPOLL_H || HAVE_SYS_EVENT_H) && USE_MN_THREADS

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

    if (timeout_ms >= 0) {
        calculated_timeout.tv_sec = timeout_ms / 1000;
        calculated_timeout.tv_nsec = (timeout_ms % 1000) * 1000000;
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

static void
kqueue_unregister_waiting(int fd, enum thread_sched_waiting_flag flags)
{
    if (flags) {
        struct kevent ke[2];
        int num_events = 0;

        if (flags & thread_sched_waiting_io_read) {
            EV_SET(&ke[num_events], fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
            num_events++;
        }
        if (flags & thread_sched_waiting_io_write) {
            EV_SET(&ke[num_events], fd, EVFILT_WRITE, EV_DELETE, 0, 0, NULL);
            num_events++;
        }
        if (kevent(timer_th.event_fd, ke, num_events, NULL, 0, NULL) == -1) {
            perror("kevent");
            rb_bug("unregister/kevent fails. errno:%d", errno);
        }
    }
}

static bool
kqueue_already_registered(int fd)
{
    struct rb_thread_sched_waiting *w, *found_w = NULL;

    ccan_list_for_each(&timer_th.waiting, w, node) {
        // Similar to EEXIST in epoll_ctl, but more strict because it checks fd rather than flags
        //   for simplicity
        if (w->flags && w->data.fd == fd) {
            found_w = w;
            break;
        }
    }
    return found_w != NULL;
}

#endif // HAVE_SYS_EVENT_H

// return false if the fd is not waitable or not need to wait.
static bool
timer_thread_register_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags, rb_hrtime_t *rel)
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
            return false;
        }
    }

    if (rel && *rel > 0) {
        flags |= thread_sched_waiting_timeout;
    }

#if HAVE_SYS_EVENT_H
    struct kevent ke[2];
    int num_events = 0;
#else
    uint32_t epoll_events = 0;
#endif
    if (flags & thread_sched_waiting_timeout) {
        VM_ASSERT(rel != NULL);
        abs = rb_hrtime_add(rb_hrtime_now(), *rel);
    }

    if (flags & thread_sched_waiting_io_read) {
        if (!(flags & thread_sched_waiting_io_force) && fd_readable_nonblock(fd)) {
            RUBY_DEBUG_LOG("fd_readable_nonblock");
            return false;
        }
        else {
            VM_ASSERT(fd >= 0);
#if HAVE_SYS_EVENT_H
            EV_SET(&ke[num_events], fd, EVFILT_READ, EV_ADD, 0, 0, (void *)th);
            num_events++;
#else
            epoll_events |= EPOLLIN;
#endif
        }
    }

    if (flags & thread_sched_waiting_io_write) {
        if (!(flags & thread_sched_waiting_io_force) && fd_writable_nonblock(fd)) {
            RUBY_DEBUG_LOG("fd_writable_nonblock");
            return false;
        }
        else {
            VM_ASSERT(fd >= 0);
#if HAVE_SYS_EVENT_H
            EV_SET(&ke[num_events], fd, EVFILT_WRITE, EV_ADD, 0, 0, (void *)th);
            num_events++;
#else
            epoll_events |= EPOLLOUT;
#endif
        }
    }

    rb_native_mutex_lock(&timer_th.waiting_lock);
    {
#if HAVE_SYS_EVENT_H
        if (num_events > 0) {
            if (kqueue_already_registered(fd)) {
                rb_native_mutex_unlock(&timer_th.waiting_lock);
                return false;
            }

            if (kevent(timer_th.event_fd, ke, num_events, NULL, 0, NULL) == -1) {
                RUBY_DEBUG_LOG("failed (%d)", errno);

                switch (errno) {
                  case EBADF:
                    // the fd is closed?
                  case EINTR:
                    // signal received? is there a sensible way to handle this?
                  default:
                    perror("kevent");
                    rb_bug("register/kevent failed(fd:%d, errno:%d)", fd, errno);
                }
            }
            RUBY_DEBUG_LOG("kevent(add, fd:%d) success", fd);
        }
#else
        if (epoll_events) {
            struct epoll_event event = {
                .events = epoll_events,
                .data = {
                    .ptr = (void *)th,
                },
            };
            if (epoll_ctl(timer_th.event_fd, EPOLL_CTL_ADD, fd, &event) == -1) {
                RUBY_DEBUG_LOG("failed (%d)", errno);

                switch (errno) {
                  case EBADF:
                    // the fd is closed?
                  case EPERM:
                    // the fd doesn't support epoll
                  case EEXIST:
                    // the fd is already registered by another thread
                    rb_native_mutex_unlock(&timer_th.waiting_lock);
                    return false;
                  default:
                    perror("epoll_ctl");
                    rb_bug("register/epoll_ctl failed(fd:%d, errno:%d)", fd, errno);
                }
            }
            RUBY_DEBUG_LOG("epoll_ctl(add, fd:%d, events:%d) success", fd, epoll_events);
        }
#endif

        if (th) {
            VM_ASSERT(th->sched.waiting_reason.flags == thread_sched_waiting_none);

            // setup waiting information
            {
                th->sched.waiting_reason.flags = flags;
                th->sched.waiting_reason.data.timeout = abs;
                th->sched.waiting_reason.data.fd = fd;
                th->sched.waiting_reason.data.result = 0;
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

                // update timeout seconds
                timer_thread_wakeup();
            }
        }
        else {
            VM_ASSERT(abs == 0);
        }
    }
    rb_native_mutex_unlock(&timer_th.waiting_lock);

    return true;
}

static void
timer_thread_unregister_waiting(rb_thread_t *th, int fd, enum thread_sched_waiting_flag flags)
{
    RUBY_DEBUG_LOG("th:%u fd:%d", rb_th_serial(th), fd);
#if HAVE_SYS_EVENT_H
    kqueue_unregister_waiting(fd, flags);
#else
    // Linux 2.6.9 or later is needed to pass NULL as data.
    if (epoll_ctl(timer_th.event_fd, EPOLL_CTL_DEL, fd, NULL) == -1) {
        switch (errno) {
          case EBADF:
            // just ignore. maybe fd is closed.
            break;
          default:
            perror("epoll_ctl");
            rb_bug("unregister/epoll_ctl fails. errno:%d", errno);
        }
    }
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

    timer_thread_register_waiting(NULL, timer_th.comm_fds[0], thread_sched_waiting_io_read | thread_sched_waiting_io_force, NULL);
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
            rb_thread_t *th = (rb_thread_t *)timer_th.finished_events[i].udata;
            int fd = (int)timer_th.finished_events[i].ident;
            int16_t filter = timer_th.finished_events[i].filter;

            if (th == NULL) {
                // wakeup timerthread
                RUBY_DEBUG_LOG("comm from fd:%d", timer_th.comm_fds[1]);
                consume_communication_pipe(timer_th.comm_fds[0]);
            }
            else {
                // wakeup specific thread by IO
                RUBY_DEBUG_LOG("io event. wakeup_th:%u event:%s%s",
                                rb_th_serial(th),
                                (filter == EVFILT_READ) ? "read/" : "",
                                (filter == EVFILT_WRITE) ? "write/" : "");

                rb_native_mutex_lock(&timer_th.waiting_lock);
                {
                    if (th->sched.waiting_reason.flags) {
                        // delete from chain
                        ccan_list_del_init(&th->sched.waiting_reason.node);
                        timer_thread_unregister_waiting(th, fd, kqueue_translate_filter_to_flags(filter));

                        th->sched.waiting_reason.flags = thread_sched_waiting_none;
                        th->sched.waiting_reason.data.fd = -1;
                        th->sched.waiting_reason.data.result = filter;

                        timer_thread_wakeup_thread(th);
                    }
                    else {
                        // already released
                    }
                }
                rb_native_mutex_unlock(&timer_th.waiting_lock);
            }
        }
#else
        for (int i=0; i<r; i++) {
            rb_thread_t *th = (rb_thread_t *)timer_th.finished_events[i].data.ptr;

            if (th == NULL) {
                // wakeup timerthread
                RUBY_DEBUG_LOG("comm from fd:%d", timer_th.comm_fds[1]);
                consume_communication_pipe(timer_th.comm_fds[0]);
            }
            else {
                // wakeup specific thread by IO
                uint32_t events = timer_th.finished_events[i].events;

                RUBY_DEBUG_LOG("io event. wakeup_th:%u event:%s%s%s%s%s%s",
                               rb_th_serial(th),
                               (events & EPOLLIN)    ? "in/" : "",
                               (events & EPOLLOUT)   ? "out/" : "",
                               (events & EPOLLRDHUP) ? "RDHUP/" : "",
                               (events & EPOLLPRI)   ? "pri/" : "",
                               (events & EPOLLERR)   ? "err/" : "",
                               (events & EPOLLHUP)   ? "hup/" : "");

                rb_native_mutex_lock(&timer_th.waiting_lock);
                {
                    if (th->sched.waiting_reason.flags) {
                        // delete from chain
                        ccan_list_del_init(&th->sched.waiting_reason.node);
                        timer_thread_unregister_waiting(th, th->sched.waiting_reason.data.fd, th->sched.waiting_reason.flags);

                        th->sched.waiting_reason.flags = thread_sched_waiting_none;
                        th->sched.waiting_reason.data.fd = -1;
                        th->sched.waiting_reason.data.result = (int)events;

                        timer_thread_wakeup_thread(th);
                    }
                    else {
                        // already released
                    }
                }
                rb_native_mutex_unlock(&timer_th.waiting_lock);
            }
        }
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
        rb_native_mutex_lock(&vm->ractor.sched.lock);
        {
            // (1-1) timeslice
            timer_thread_check_timeslice(vm);
        }
        rb_native_mutex_unlock(&vm->ractor.sched.lock);
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
