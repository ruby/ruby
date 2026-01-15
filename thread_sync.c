/* included by thread.c */
#include "ccan/list/list.h"
#include "builtin.h"

static VALUE rb_cMutex, rb_eClosedQueueError;

/* Mutex */
typedef struct rb_mutex_struct {
    rb_serial_t ec_serial;
    rb_thread_t *th; // even if the fiber is collected, we might need access to the thread in mutex_free
    struct rb_mutex_struct *next_mutex;
    struct ccan_list_head waitq; /* protected by GVL */
} rb_mutex_t;

/* sync_waiter is always on-stack */
struct sync_waiter {
    VALUE self;
    rb_thread_t *th;
    rb_fiber_t *fiber;
    struct ccan_list_node node;
};

static inline rb_fiber_t*
nonblocking_fiber(rb_fiber_t *fiber)
{
    if (rb_fiberptr_blocking(fiber)) {
        return NULL;
    }

    return fiber;
}

struct queue_sleep_arg {
    VALUE self;
    VALUE timeout;
    rb_hrtime_t end;
};

#define MUTEX_ALLOW_TRAP FL_USER1

static void
sync_wakeup(struct ccan_list_head *head, long max)
{
    RUBY_DEBUG_LOG("max:%ld", max);

    struct sync_waiter *cur = 0, *next;

    ccan_list_for_each_safe(head, cur, next, node) {
        ccan_list_del_init(&cur->node);

        if (cur->th->status != THREAD_KILLED) {
            if (cur->th->scheduler != Qnil && cur->fiber) {
                rb_fiber_scheduler_unblock(cur->th->scheduler, cur->self, rb_fiberptr_self(cur->fiber));
            }
            else {
                RUBY_DEBUG_LOG("target_th:%u", rb_th_serial(cur->th));
                rb_threadptr_interrupt(cur->th);
                cur->th->status = THREAD_RUNNABLE;
            }

            if (--max == 0) return;
        }
    }
}

static void
wakeup_one(struct ccan_list_head *head)
{
    sync_wakeup(head, 1);
}

static void
wakeup_all(struct ccan_list_head *head)
{
    sync_wakeup(head, LONG_MAX);
}

#if defined(HAVE_WORKING_FORK)
static void rb_mutex_abandon_all(rb_mutex_t *mutexes);
static void rb_mutex_abandon_keeping_mutexes(rb_thread_t *th);
static void rb_mutex_abandon_locking_mutex(rb_thread_t *th);
#endif
static const char* rb_mutex_unlock_th(rb_mutex_t *mutex, rb_thread_t *th, rb_serial_t ec_serial);

static size_t
rb_mutex_num_waiting(rb_mutex_t *mutex)
{
    struct sync_waiter *w = 0;
    size_t n = 0;

    ccan_list_for_each(&mutex->waitq, w, node) {
        n++;
    }

    return n;
}

rb_thread_t* rb_fiber_threadptr(const rb_fiber_t *fiber);

static bool
mutex_locked_p(rb_mutex_t *mutex)
{
    return mutex->ec_serial != 0;
}

static void
mutex_free(void *ptr)
{
    rb_mutex_t *mutex = ptr;
    if (mutex_locked_p(mutex)) {
        const char *err = rb_mutex_unlock_th(mutex, mutex->th, 0);
        if (err) rb_bug("%s", err);
    }
    ruby_xfree(ptr);
}

static size_t
mutex_memsize(const void *ptr)
{
    return sizeof(rb_mutex_t);
}

static const rb_data_type_t mutex_data_type = {
    "mutex",
    {NULL, mutex_free, mutex_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static rb_mutex_t *
mutex_ptr(VALUE obj)
{
    rb_mutex_t *mutex;

    TypedData_Get_Struct(obj, rb_mutex_t, &mutex_data_type, mutex);

    return mutex;
}

VALUE
rb_obj_is_mutex(VALUE obj)
{
    return RBOOL(rb_typeddata_is_kind_of(obj, &mutex_data_type));
}

static VALUE
mutex_alloc(VALUE klass)
{
    VALUE obj;
    rb_mutex_t *mutex;

    obj = TypedData_Make_Struct(klass, rb_mutex_t, &mutex_data_type, mutex);

    ccan_list_head_init(&mutex->waitq);
    return obj;
}

VALUE
rb_mutex_new(void)
{
    return mutex_alloc(rb_cMutex);
}

VALUE
rb_mutex_locked_p(VALUE self)
{
    rb_mutex_t *mutex = mutex_ptr(self);

    return RBOOL(mutex_locked_p(mutex));
}

static void
thread_mutex_insert(rb_thread_t *thread, rb_mutex_t *mutex)
{
    RUBY_ASSERT(!mutex->next_mutex);
    if (thread->keeping_mutexes) {
        mutex->next_mutex = thread->keeping_mutexes;
    }

    thread->keeping_mutexes = mutex;
}

static void
thread_mutex_remove(rb_thread_t *thread, rb_mutex_t *mutex)
{
    rb_mutex_t **keeping_mutexes = &thread->keeping_mutexes;

    while (*keeping_mutexes && *keeping_mutexes != mutex) {
        // Move to the next mutex in the list:
        keeping_mutexes = &(*keeping_mutexes)->next_mutex;
    }

    if (*keeping_mutexes) {
        *keeping_mutexes = mutex->next_mutex;
        mutex->next_mutex = NULL;
    }
}

static void
mutex_set_owner(rb_mutex_t *mutex, rb_thread_t *th, rb_serial_t ec_serial)
{
    mutex->th = th;
    mutex->ec_serial = ec_serial;
}

static void
mutex_locked(rb_mutex_t *mutex, rb_thread_t *th, rb_serial_t ec_serial)
{
    mutex_set_owner(mutex, th, ec_serial);
    thread_mutex_insert(th, mutex);
}

static inline bool
do_mutex_trylock(rb_mutex_t *mutex, rb_thread_t *th, rb_serial_t ec_serial)
{
    if (mutex->ec_serial == 0) {
        RUBY_DEBUG_LOG("%p ok", mutex);

        mutex_locked(mutex, th, ec_serial);
        return true;
    }
    else {
        RUBY_DEBUG_LOG("%p ng", mutex);
        return false;
    }
}

static VALUE
rb_mut_trylock(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(do_mutex_trylock(mutex_ptr(self), ec->thread_ptr, rb_ec_serial(ec)));
}

VALUE
rb_mutex_trylock(VALUE self)
{
    return rb_mut_trylock(GET_EC(), self);
}

static VALUE
mutex_owned_p(rb_serial_t ec_serial, rb_mutex_t *mutex)
{
    return RBOOL(mutex->ec_serial == ec_serial);
}

static VALUE
call_rb_fiber_scheduler_block(VALUE mutex)
{
    return rb_fiber_scheduler_block(rb_fiber_scheduler_current(), mutex, Qnil);
}

static VALUE
delete_from_waitq(VALUE value)
{
    struct sync_waiter *sync_waiter = (void *)value;
    ccan_list_del(&sync_waiter->node);

    return Qnil;
}

static inline rb_atomic_t threadptr_get_interrupts(rb_thread_t *th);

struct mutex_args {
    VALUE self;
    rb_mutex_t *mutex;
    rb_execution_context_t *ec;
};

static inline void
mutex_args_init(struct mutex_args *args, VALUE mutex)
{
    args->self = mutex;
    args->mutex = mutex_ptr(mutex);
    args->ec = GET_EC();
}

static VALUE
do_mutex_lock(struct mutex_args *args, int interruptible_p)
{
    VALUE self = args->self;
    rb_execution_context_t *ec = args->ec;
    rb_thread_t *th = ec->thread_ptr;
    rb_fiber_t *fiber = ec->fiber_ptr;
    rb_serial_t ec_serial = rb_ec_serial(ec);
    rb_mutex_t *mutex = args->mutex;
    rb_atomic_t saved_ints = 0;

    /* When running trap handler */
    if (!FL_TEST_RAW(self, MUTEX_ALLOW_TRAP) &&
        th->ec->interrupt_mask & TRAP_INTERRUPT_MASK) {
        rb_raise(rb_eThreadError, "can't be called from trap context");
    }

    if (!do_mutex_trylock(mutex, th, ec_serial)) {
        if (mutex->ec_serial == ec_serial) {
            rb_raise(rb_eThreadError, "deadlock; recursive locking");
        }

        while (mutex->ec_serial != ec_serial) {
            VM_ASSERT(mutex->ec_serial != 0);

            VALUE scheduler = rb_fiber_scheduler_current();
            if (scheduler != Qnil) {
                struct sync_waiter sync_waiter = {
                    .self = self,
                    .th = th,
                    .fiber = nonblocking_fiber(fiber)
                };

                ccan_list_add_tail(&mutex->waitq, &sync_waiter.node);

                rb_ensure(call_rb_fiber_scheduler_block, self, delete_from_waitq, (VALUE)&sync_waiter);

                if (!mutex->ec_serial) {
                    mutex_set_owner(mutex, th, ec_serial);
                }
            }
            else {
                if (!th->vm->thread_ignore_deadlock && mutex->th == th) {
                    rb_raise(rb_eThreadError, "deadlock; lock already owned by another fiber belonging to the same thread");
                }

                struct sync_waiter sync_waiter = {
                    .self = self,
                    .th = th,
                    .fiber = nonblocking_fiber(fiber),
                };

                RUBY_DEBUG_LOG("%p wait", mutex);

                // similar code with `sleep_forever`, but
                // sleep_forever(SLEEP_DEADLOCKABLE) raises an exception.
                // Ensure clause is needed like but `rb_ensure` a bit slow.
                //
                //   begin
                //     sleep_forever(th, SLEEP_DEADLOCKABLE);
                //   ensure
                //     ccan_list_del(&sync_waiter.node);
                //   end
                enum rb_thread_status prev_status = th->status;
                th->status = THREAD_STOPPED_FOREVER;
                rb_ractor_sleeper_threads_inc(th->ractor);
                rb_check_deadlock(th->ractor);

                RUBY_ASSERT(!th->locking_mutex);
                th->locking_mutex = self;

                ccan_list_add_tail(&mutex->waitq, &sync_waiter.node);
                {
                    native_sleep(th, NULL);
                }
                ccan_list_del(&sync_waiter.node);

                // unlocked by another thread while sleeping
                if (!mutex->ec_serial) {
                    mutex_set_owner(mutex, th, ec_serial);
                }

                rb_ractor_sleeper_threads_dec(th->ractor);
                th->status = prev_status;
                th->locking_mutex = Qfalse;

                RUBY_DEBUG_LOG("%p wakeup", mutex);
            }

            if (interruptible_p) {
                /* release mutex before checking for interrupts...as interrupt checking
                 * code might call rb_raise() */
                if (mutex->ec_serial == ec_serial) {
                    mutex->th = NULL;
                    mutex->ec_serial = 0;
                }
                RUBY_VM_CHECK_INTS_BLOCKING(th->ec); /* may release mutex */
                if (!mutex->ec_serial) {
                    mutex_set_owner(mutex, th, ec_serial);
                }
            }
            else {
                // clear interrupt information
                if (RUBY_VM_INTERRUPTED(th->ec)) {
                    // reset interrupts
                    if (saved_ints == 0) {
                        saved_ints = threadptr_get_interrupts(th);
                    }
                    else {
                        // ignore additional interrupts
                        threadptr_get_interrupts(th);
                    }
                }
            }
        }

        if (saved_ints) th->ec->interrupt_flag = saved_ints;
        if (mutex->ec_serial == ec_serial) mutex_locked(mutex, th, ec_serial);
    }

    RUBY_DEBUG_LOG("%p locked", mutex);

    // assertion
    if (mutex_owned_p(ec_serial, mutex) == Qfalse) rb_bug("do_mutex_lock: mutex is not owned.");

    return self;
}

static VALUE
mutex_lock_uninterruptible(VALUE self)
{
    struct mutex_args args;
    mutex_args_init(&args, self);
    return do_mutex_lock(&args, 0);
}

static VALUE
rb_mut_lock(rb_execution_context_t *ec, VALUE self)
{
    struct mutex_args args = {
        .self = self,
        .mutex = mutex_ptr(self),
        .ec = ec,
    };
    return do_mutex_lock(&args, 1);
}

VALUE
rb_mutex_lock(VALUE self)
{
    struct mutex_args args;
    mutex_args_init(&args, self);
    return do_mutex_lock(&args, 1);
}

static VALUE
rb_mut_owned_p(rb_execution_context_t *ec, VALUE self)
{
    return mutex_owned_p(rb_ec_serial(ec), mutex_ptr(self));
}

VALUE
rb_mutex_owned_p(VALUE self)
{
    return rb_mut_owned_p(GET_EC(), self);
}

static const char *
rb_mutex_unlock_th(rb_mutex_t *mutex, rb_thread_t *th, rb_serial_t ec_serial)
{
    RUBY_DEBUG_LOG("%p", mutex);

    if (mutex->ec_serial == 0) {
        return "Attempt to unlock a mutex which is not locked";
    }
    else if (ec_serial && mutex->ec_serial != ec_serial) {
        return "Attempt to unlock a mutex which is locked by another thread/fiber";
    }

    struct sync_waiter *cur = 0, *next;

    mutex->ec_serial = 0;
    thread_mutex_remove(th, mutex);

    ccan_list_for_each_safe(&mutex->waitq, cur, next, node) {
        ccan_list_del_init(&cur->node);

        if (cur->th->scheduler != Qnil && cur->fiber) {
            rb_fiber_scheduler_unblock(cur->th->scheduler, cur->self, rb_fiberptr_self(cur->fiber));
            return NULL;
        }
        else {
            switch (cur->th->status) {
              case THREAD_RUNNABLE: /* from someone else calling Thread#run */
              case THREAD_STOPPED_FOREVER: /* likely (rb_mutex_lock) */
                RUBY_DEBUG_LOG("wakeup th:%u", rb_th_serial(cur->th));
                rb_threadptr_interrupt(cur->th);
                return NULL;
              case THREAD_STOPPED: /* probably impossible */
                rb_bug("unexpected THREAD_STOPPED");
              case THREAD_KILLED:
                /* not sure about this, possible in exit GC? */
                rb_bug("unexpected THREAD_KILLED");
                continue;
            }
        }
    }

    // We did not find any threads to wake up, so we can just return with no error:
    return NULL;
}

static void
do_mutex_unlock(struct mutex_args *args)
{
    const char *err;
    rb_mutex_t *mutex = args->mutex;
    rb_thread_t *th = rb_ec_thread_ptr(args->ec);

    err = rb_mutex_unlock_th(mutex, th, rb_ec_serial(args->ec));
    if (err) rb_raise(rb_eThreadError, "%s", err);
}

static VALUE
do_mutex_unlock_safe(VALUE args)
{
    do_mutex_unlock((struct mutex_args *)args);
    return Qnil;
}

/*
 * call-seq:
 *    mutex.unlock    -> self
 *
 * Releases the lock.
 * Raises +ThreadError+ if +mutex+ wasn't locked by the current thread.
 */
VALUE
rb_mutex_unlock(VALUE self)
{
    struct mutex_args args;
    mutex_args_init(&args, self);
    do_mutex_unlock(&args);
    return self;
}

static VALUE
rb_mut_unlock(rb_execution_context_t *ec, VALUE self)
{
    struct mutex_args args = {
        .self = self,
        .mutex = mutex_ptr(self),
        .ec = ec,
    };
    do_mutex_unlock(&args);
    return self;
}

#if defined(HAVE_WORKING_FORK)
static void
rb_mutex_abandon_keeping_mutexes(rb_thread_t *th)
{
    rb_mutex_abandon_all(th->keeping_mutexes);
    th->keeping_mutexes = NULL;
}

static void
rb_mutex_abandon_locking_mutex(rb_thread_t *th)
{
    if (th->locking_mutex) {
        rb_mutex_t *mutex = mutex_ptr(th->locking_mutex);

        ccan_list_head_init(&mutex->waitq);
        th->locking_mutex = Qfalse;
    }
}

static void
rb_mutex_abandon_all(rb_mutex_t *mutexes)
{
    rb_mutex_t *mutex;

    while (mutexes) {
        mutex = mutexes;
        mutexes = mutex->next_mutex;
        mutex->ec_serial = 0;
        mutex->next_mutex = 0;
        ccan_list_head_init(&mutex->waitq);
    }
}
#endif

struct rb_mutex_sleep_arguments {
    VALUE self;
    VALUE timeout;
};

static VALUE
mutex_sleep_begin(VALUE _arguments)
{
    struct rb_mutex_sleep_arguments *arguments = (struct rb_mutex_sleep_arguments *)_arguments;
    VALUE timeout = arguments->timeout;
    VALUE woken = Qtrue;

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        rb_fiber_scheduler_kernel_sleep(scheduler, timeout);
    }
    else {
        if (NIL_P(timeout)) {
            rb_thread_sleep_deadly_allow_spurious_wakeup(arguments->self, Qnil, 0);
        }
        else {
            struct timeval timeout_value = rb_time_interval(timeout);
            rb_hrtime_t relative_timeout = rb_timeval2hrtime(&timeout_value);
            /* permit spurious check */
            woken = RBOOL(sleep_hrtime(GET_THREAD(), relative_timeout, 0));
        }
    }

    return woken;
}

static VALUE
rb_mut_sleep(rb_execution_context_t *ec, VALUE self, VALUE timeout)
{
    if (!NIL_P(timeout)) {
        // Validate the argument:
        rb_time_interval(timeout);
    }

    rb_mut_unlock(ec, self);
    time_t beg = time(0);

    struct rb_mutex_sleep_arguments arguments = {
        .self = self,
        .timeout = timeout,
    };

    VALUE woken = rb_ec_ensure(ec, mutex_sleep_begin, (VALUE)&arguments, mutex_lock_uninterruptible, self);

    RUBY_VM_CHECK_INTS_BLOCKING(ec);
    if (!woken) return Qnil;
    time_t end = time(0) - beg;
    return TIMET2NUM(end);
}

VALUE
rb_mutex_sleep(VALUE self, VALUE timeout)
{
    return rb_mut_sleep(GET_EC(), self, timeout);
}

VALUE
rb_mutex_synchronize(VALUE self, VALUE (*func)(VALUE arg), VALUE arg)
{
    struct mutex_args args;
    mutex_args_init(&args, self);
    do_mutex_lock(&args, 1);
    return rb_ec_ensure(args.ec, func, arg, do_mutex_unlock_safe, (VALUE)&args);
}

static VALUE
do_ec_yield(VALUE _ec)
{
    return rb_ec_yield((rb_execution_context_t *)_ec, Qundef);
}

VALUE
rb_mut_synchronize(rb_execution_context_t *ec, VALUE self)
{
    struct mutex_args args = {
        .self = self,
        .mutex = mutex_ptr(self),
        .ec = ec,
    };
    do_mutex_lock(&args, 1);
    return rb_ec_ensure(args.ec, do_ec_yield, (VALUE)ec, do_mutex_unlock_safe, (VALUE)&args);
}

void
rb_mutex_allow_trap(VALUE self, int val)
{
    Check_TypedStruct(self, &mutex_data_type);

    if (val)
        FL_SET_RAW(self, MUTEX_ALLOW_TRAP);
    else
        FL_UNSET_RAW(self, MUTEX_ALLOW_TRAP);
}

/* Queue */

struct rb_queue {
    struct ccan_list_head waitq;
    rb_serial_t fork_gen;
    long capa;
    long len;
    long offset;
    VALUE *buffer;
    int num_waiting;
};

#define szqueue_waitq(sq) &sq->q.waitq
#define szqueue_pushq(sq) &sq->pushq

struct rb_szqueue {
    struct rb_queue q;
    int num_waiting_push;
    struct ccan_list_head pushq;
    long max;
};

static void
queue_mark_and_move(void *ptr)
{
    struct rb_queue *q = ptr;
    /* no need to mark threads in waitq, they are on stack */
    for (long index = 0; index < q->len; index++) {
        rb_gc_mark_and_move(&q->buffer[((q->offset + index) % q->capa)]);
    }
}

static void
queue_free(void *ptr)
{
    struct rb_queue *q = ptr;
    if (q->buffer) {
        ruby_sized_xfree(q->buffer, q->capa * sizeof(VALUE));
    }
}

static size_t
queue_memsize(const void *ptr)
{
    const struct rb_queue *q = ptr;
    return sizeof(struct rb_queue) + (q->capa * sizeof(VALUE));
}

static const rb_data_type_t queue_data_type = {
    .wrap_struct_name = "Thread::Queue",
    .function = {
        .dmark = queue_mark_and_move,
        .dfree = queue_free,
        .dsize = queue_memsize,
        .dcompact = queue_mark_and_move,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

static VALUE
queue_alloc(VALUE klass)
{
    VALUE obj;
    struct rb_queue *q;

    obj = TypedData_Make_Struct(klass, struct rb_queue, &queue_data_type, q);
    ccan_list_head_init(&q->waitq);
    return obj;
}

static inline bool
queue_fork_check(struct rb_queue *q)
{
    rb_serial_t fork_gen = GET_VM()->fork_gen;

    if (RB_LIKELY(q->fork_gen == fork_gen)) {
        return false;
    }
    /* forked children can't reach into parent thread stacks */
    q->fork_gen = fork_gen;
    ccan_list_head_init(&q->waitq);
    q->num_waiting = 0;
    return true;
}

static inline struct rb_queue *
raw_queue_ptr(VALUE obj)
{
    struct rb_queue *q;

    TypedData_Get_Struct(obj, struct rb_queue, &queue_data_type, q);
    queue_fork_check(q);

    return q;
}

static inline void
check_queue(VALUE obj, struct rb_queue *q)
{
    if (RB_UNLIKELY(q->buffer == NULL)) {
         rb_raise(rb_eTypeError, "%+"PRIsVALUE" not initialized", obj);
    }
}

static inline struct rb_queue *
queue_ptr(VALUE obj)
{
    struct rb_queue *q = raw_queue_ptr(obj);
    check_queue(obj, q);
    return q;
}

#define QUEUE_CLOSED          FL_USER5

static rb_hrtime_t
queue_timeout2hrtime(VALUE timeout)
{
    if (NIL_P(timeout)) {
        return (rb_hrtime_t)0;
    }
    rb_hrtime_t rel = 0;
    if (FIXNUM_P(timeout)) {
        rel = rb_sec2hrtime(NUM2TIMET(timeout));
    }
    else {
        double2hrtime(&rel, rb_num2dbl(timeout));
    }
    return rb_hrtime_add(rel, rb_hrtime_now());
}

static void
szqueue_mark_and_move(void *ptr)
{
    struct rb_szqueue *sq = ptr;

    queue_mark_and_move(&sq->q);
}

static void
szqueue_free(void *ptr)
{
    struct rb_szqueue *sq = ptr;
    queue_free(&sq->q);
}

static size_t
szqueue_memsize(const void *ptr)
{
    const struct rb_szqueue *sq = ptr;
    return sizeof(struct rb_szqueue) + (sq->q.capa * sizeof(VALUE));
}

static const rb_data_type_t szqueue_data_type = {
    .wrap_struct_name = "Thread::SizedQueue",
    .function = {
        .dmark = szqueue_mark_and_move,
        .dfree = szqueue_free,
        .dsize = szqueue_memsize,
        .dcompact = szqueue_mark_and_move,
    },
    .parent = &queue_data_type,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

static VALUE
szqueue_alloc(VALUE klass)
{
    struct rb_szqueue *sq;
    VALUE obj = TypedData_Make_Struct(klass, struct rb_szqueue,
                                        &szqueue_data_type, sq);
    ccan_list_head_init(szqueue_waitq(sq));
    ccan_list_head_init(szqueue_pushq(sq));
    return obj;
}

static inline struct rb_szqueue *
raw_szqueue_ptr(VALUE obj)
{
    struct rb_szqueue *sq;

    TypedData_Get_Struct(obj, struct rb_szqueue, &szqueue_data_type, sq);
    if (RB_UNLIKELY(queue_fork_check(&sq->q))) {
        ccan_list_head_init(szqueue_pushq(sq));
        sq->num_waiting_push = 0;
    }

    return sq;
}

static inline struct rb_szqueue *
szqueue_ptr(VALUE obj)
{
    struct rb_szqueue *sq = raw_szqueue_ptr(obj);
    check_queue(obj, &sq->q);
    return sq;
}

static inline bool
queue_closed_p(VALUE self)
{
    return FL_TEST_RAW(self, QUEUE_CLOSED) != 0;
}

/*
 *  Document-class: ClosedQueueError
 *
 *  The exception class which will be raised when pushing into a closed
 *  Queue.  See Thread::Queue#close and Thread::SizedQueue#close.
 */

NORETURN(static void raise_closed_queue_error(VALUE self));

static void
raise_closed_queue_error(VALUE self)
{
    rb_raise(rb_eClosedQueueError, "queue closed");
}

static VALUE
queue_closed_result(VALUE self, struct rb_queue *q)
{
    RUBY_ASSERT(q->len == 0);
    return Qnil;
}

#define QUEUE_INITIAL_CAPA 8

static inline void
ring_buffer_init(struct rb_queue *q, long initial_capa)
{
    q->buffer = ALLOC_N(VALUE, initial_capa);
    q->capa = initial_capa;
}

static inline void
ring_buffer_expand(struct rb_queue *q)
{
    RUBY_ASSERT(q->capa > 0);
    VALUE *new_buffer = ALLOC_N(VALUE, q->capa * 2);
    MEMCPY(new_buffer, q->buffer + q->offset, VALUE, q->capa - q->offset);
    MEMCPY(new_buffer + (q->capa - q->offset), q->buffer, VALUE, q->offset);
    VALUE *old_buffer = q->buffer;
    q->buffer = new_buffer;
    q->offset = 0;
    ruby_sized_xfree(old_buffer, q->capa * sizeof(VALUE));
    q->capa *= 2;
}

static void
ring_buffer_push(VALUE self, struct rb_queue *q, VALUE obj)
{
    if (RB_UNLIKELY(q->len >= q->capa)) {
        ring_buffer_expand(q);
    }
    RUBY_ASSERT(q->capa > q->len);
    long index = (q->offset + q->len) % q->capa;
    q->len++;
    RB_OBJ_WRITE(self, &q->buffer[index], obj);
}

static VALUE
ring_buffer_shift(struct rb_queue *q)
{
    if (!q->len) {
        return Qnil;
    }

    VALUE obj = q->buffer[q->offset];
    q->len--;
    if (q->len == 0) {
        q->offset = 0;
    }
    else {
        q->offset = (q->offset + 1) % q->capa;
    }
    return obj;
}

static VALUE
queue_initialize(rb_execution_context_t *ec, VALUE self, VALUE initial)
{
    struct rb_queue *q = raw_queue_ptr(self);
    ccan_list_head_init(&q->waitq);
    if (NIL_P(initial)) {
        ring_buffer_init(q, QUEUE_INITIAL_CAPA);
    }
    else {
        initial = rb_to_array(initial);
        long len = RARRAY_LEN(initial);
        long initial_capa = QUEUE_INITIAL_CAPA;
        while (initial_capa < len) {
            initial_capa *= 2;
        }
        ring_buffer_init(q, initial_capa);
        MEMCPY(q->buffer, RARRAY_CONST_PTR(initial), VALUE, len);
        q->len = len;
    }
    return self;
}

static VALUE
queue_do_push(VALUE self, struct rb_queue *q, VALUE obj)
{
    check_queue(self, q);
    if (queue_closed_p(self)) {
        raise_closed_queue_error(self);
    }
    ring_buffer_push(self, q, obj);
    wakeup_one(&q->waitq);
    return self;
}

static VALUE
queue_sleep(VALUE _args)
{
    struct queue_sleep_arg *args = (struct queue_sleep_arg *)_args;
    rb_thread_sleep_deadly_allow_spurious_wakeup(args->self, args->timeout, args->end);
    return Qnil;
}

struct queue_waiter {
    struct sync_waiter w;
    union {
        struct rb_queue *q;
        struct rb_szqueue *sq;
    } as;
};

static VALUE
queue_sleep_done(VALUE p)
{
    struct queue_waiter *qw = (struct queue_waiter *)p;

    ccan_list_del(&qw->w.node);
    qw->as.q->num_waiting--;

    return Qfalse;
}

static VALUE
szqueue_sleep_done(VALUE p)
{
    struct queue_waiter *qw = (struct queue_waiter *)p;

    ccan_list_del(&qw->w.node);
    qw->as.sq->num_waiting_push--;

    return Qfalse;
}

static inline VALUE
queue_do_pop(rb_execution_context_t *ec, VALUE self, struct rb_queue *q, VALUE non_block, VALUE timeout)
{
    if (q->len == 0) {
        if (RTEST(non_block)) {
            rb_raise(rb_eThreadError, "queue empty");
        }

        if (RTEST(rb_equal(INT2FIX(0), timeout))) {
            return Qnil;
        }
    }

    rb_hrtime_t end = queue_timeout2hrtime(timeout);
    while (q->len == 0) {
        if (queue_closed_p(self)) {
            return queue_closed_result(self, q);
        }
        else {
            RUBY_ASSERT(q->len == 0);
            RUBY_ASSERT(queue_closed_p(self) == 0);

            struct queue_waiter queue_waiter = {
                .w = {.self = self, .th = ec->thread_ptr, .fiber = nonblocking_fiber(ec->fiber_ptr)},
                .as = {.q = q}
            };

            struct ccan_list_head *waitq = &q->waitq;

            ccan_list_add_tail(waitq, &queue_waiter.w.node);
            queue_waiter.as.q->num_waiting++;

            struct queue_sleep_arg queue_sleep_arg = {
                .self = self,
                .timeout = timeout,
                .end = end
            };

            rb_ensure(queue_sleep, (VALUE)&queue_sleep_arg, queue_sleep_done, (VALUE)&queue_waiter);
            if (!NIL_P(timeout) && (rb_hrtime_now() >= end))
                break;
        }
    }

    return ring_buffer_shift(q);
}

static VALUE
rb_queue_pop(rb_execution_context_t *ec, VALUE self, VALUE non_block, VALUE timeout)
{
    return queue_do_pop(ec, self, queue_ptr(self), non_block, timeout);
}

static void
queue_clear(struct rb_queue *q)
{
    q->len = 0;
    q->offset = 0;
}

static VALUE
szqueue_initialize(rb_execution_context_t *ec, VALUE self, VALUE vmax)
{
    long max = NUM2LONG(vmax);
    struct rb_szqueue *sq = raw_szqueue_ptr(self);

    if (max <= 0) {
        rb_raise(rb_eArgError, "queue size must be positive");
    }
    ring_buffer_init(&sq->q, QUEUE_INITIAL_CAPA);
    ccan_list_head_init(szqueue_waitq(sq));
    ccan_list_head_init(szqueue_pushq(sq));
    sq->max = max;

    return self;
}

static VALUE
rb_szqueue_push(rb_execution_context_t *ec, VALUE self, VALUE object, VALUE non_block, VALUE timeout)
{
    struct rb_szqueue *sq = szqueue_ptr(self);

    if (sq->q.len >= sq->max) {
        if (RTEST(non_block)) {
            rb_raise(rb_eThreadError, "queue full");
        }

        if (RTEST(rb_equal(INT2FIX(0), timeout))) {
            return Qnil;
        }
    }

    rb_hrtime_t end = queue_timeout2hrtime(timeout);
    while (sq->q.len >= sq->max) {
        if (queue_closed_p(self)) {
            raise_closed_queue_error(self);
        }
        else {
            struct queue_waiter queue_waiter = {
                .w = {.self = self, .th = ec->thread_ptr, .fiber = nonblocking_fiber(ec->fiber_ptr)},
                .as = {.sq = sq}
            };

            struct ccan_list_head *pushq = szqueue_pushq(sq);

            ccan_list_add_tail(pushq, &queue_waiter.w.node);
            sq->num_waiting_push++;

            struct queue_sleep_arg queue_sleep_arg = {
                .self = self,
                .timeout = timeout,
                .end = end
            };
            rb_ensure(queue_sleep, (VALUE)&queue_sleep_arg, szqueue_sleep_done, (VALUE)&queue_waiter);
            if (!NIL_P(timeout) && rb_hrtime_now() >= end) {
                return Qnil;
            }
        }
    }

    return queue_do_push(self, &sq->q, object);
}

static VALUE
rb_szqueue_pop(rb_execution_context_t *ec, VALUE self, VALUE non_block, VALUE timeout)
{
    struct rb_szqueue *sq = szqueue_ptr(self);
    VALUE retval = queue_do_pop(ec, self, &sq->q, non_block, timeout);

    if (sq->q.len < sq->max) {
        wakeup_one(szqueue_pushq(sq));
    }

    return retval;
}

/* ConditionalVariable */
struct rb_condvar {
    struct ccan_list_head waitq;
    rb_serial_t fork_gen;
};

static size_t
condvar_memsize(const void *ptr)
{
    return sizeof(struct rb_condvar);
}

static const rb_data_type_t cv_data_type = {
    "condvar",
    {0, RUBY_TYPED_DEFAULT_FREE, condvar_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static struct rb_condvar *
condvar_ptr(VALUE self)
{
    struct rb_condvar *cv;
    rb_serial_t fork_gen = GET_VM()->fork_gen;

    TypedData_Get_Struct(self, struct rb_condvar, &cv_data_type, cv);

    /* forked children can't reach into parent thread stacks */
    if (cv->fork_gen != fork_gen) {
        cv->fork_gen = fork_gen;
        ccan_list_head_init(&cv->waitq);
    }

    return cv;
}

static VALUE
condvar_alloc(VALUE klass)
{
    struct rb_condvar *cv;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct rb_condvar, &cv_data_type, cv);
    ccan_list_head_init(&cv->waitq);

    return obj;
}

struct sleep_call {
    rb_execution_context_t *ec;
    VALUE mutex;
    VALUE timeout;
};

static ID id_sleep;

static VALUE
do_sleep(VALUE args)
{
    struct sleep_call *p = (struct sleep_call *)args;
    if (CLASS_OF(p->mutex) == rb_cMutex) {
        return rb_mut_sleep(p->ec, p->mutex, p->timeout);
    }
    else {
        return rb_funcallv(p->mutex, id_sleep, 1, &p->timeout);
    }
}

static VALUE
rb_condvar_wait(rb_execution_context_t *ec, VALUE self, VALUE mutex, VALUE timeout)
{
    struct rb_condvar *cv = condvar_ptr(self);
    struct sleep_call args = {
        .ec = ec,
        .mutex = mutex,
        .timeout = timeout,
    };

    struct sync_waiter sync_waiter = {
        .self = mutex,
        .th = ec->thread_ptr,
        .fiber = nonblocking_fiber(ec->fiber_ptr)
    };

    ccan_list_add_tail(&cv->waitq, &sync_waiter.node);
    return rb_ec_ensure(ec, do_sleep, (VALUE)&args, delete_from_waitq, (VALUE)&sync_waiter);
}

static VALUE
rb_condvar_signal(rb_execution_context_t *ec, VALUE self)
{
    struct rb_condvar *cv = condvar_ptr(self);
    wakeup_one(&cv->waitq);
    return self;
}

static VALUE
rb_condvar_broadcast(rb_execution_context_t *ec, VALUE self)
{
    struct rb_condvar *cv = condvar_ptr(self);
    wakeup_all(&cv->waitq);
    return self;
}

static void
Init_thread_sync(void)
{
    /* Mutex */
    rb_cMutex = rb_define_class_id_under(rb_cThread, rb_intern("Mutex"), rb_cObject);
    rb_define_alloc_func(rb_cMutex, mutex_alloc);

    /* Queue */
    VALUE rb_cQueue = rb_define_class_id_under_no_pin(rb_cThread, rb_intern("Queue"), rb_cObject);
    rb_define_alloc_func(rb_cQueue, queue_alloc);

    rb_eClosedQueueError = rb_define_class("ClosedQueueError", rb_eStopIteration);

    VALUE rb_cSizedQueue = rb_define_class_id_under_no_pin(rb_cThread, rb_intern("SizedQueue"), rb_cQueue);
    rb_define_alloc_func(rb_cSizedQueue, szqueue_alloc);

    /* CVar */
    VALUE rb_cConditionVariable = rb_define_class_id_under_no_pin(rb_cThread, rb_intern("ConditionVariable"), rb_cObject);
    rb_define_alloc_func(rb_cConditionVariable, condvar_alloc);

    id_sleep = rb_intern("sleep");

    rb_provide("thread.rb");
}

#include "thread_sync.rbinc"
