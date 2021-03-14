/* included by thread.c */
#include "ccan/list/list.h"
#include "coroutine/Stack.h"

static VALUE rb_cMutex, rb_cQueue, rb_cSizedQueue, rb_cConditionVariable;
static VALUE rb_eClosedQueueError;

/* Mutex */
typedef struct rb_mutex_struct {
    rb_fiber_t *fiber;
    struct rb_mutex_struct *next_mutex;
    struct list_head waitq; /* protected by GVL */
} rb_mutex_t;

/* sync_waiter is always on-stack */
struct sync_waiter {
    VALUE self;
    rb_thread_t *th;
    rb_fiber_t *fiber;
    struct list_node node;
};

#define MUTEX_ALLOW_TRAP FL_USER1

static void
sync_wakeup(struct list_head *head, long max)
{
    struct sync_waiter *cur = 0, *next;

    list_for_each_safe(head, cur, next, node) {
        list_del_init(&cur->node);

        if (cur->th->status != THREAD_KILLED) {

            if (cur->th->scheduler != Qnil) {
                rb_scheduler_unblock(cur->th->scheduler, cur->self, rb_fiberptr_self(cur->fiber));
            } else {
                rb_threadptr_interrupt(cur->th);
                cur->th->status = THREAD_RUNNABLE;
            }

            if (--max == 0) return;
        }
    }
}

static void
wakeup_one(struct list_head *head)
{
    sync_wakeup(head, 1);
}

static void
wakeup_all(struct list_head *head)
{
    sync_wakeup(head, LONG_MAX);
}

#if defined(HAVE_WORKING_FORK)
static void rb_mutex_abandon_all(rb_mutex_t *mutexes);
static void rb_mutex_abandon_keeping_mutexes(rb_thread_t *th);
static void rb_mutex_abandon_locking_mutex(rb_thread_t *th);
#endif
static const char* rb_mutex_unlock_th(rb_mutex_t *mutex, rb_thread_t *th, rb_fiber_t *fiber);

/*
 *  Document-class: Mutex
 *
 *  Mutex implements a simple semaphore that can be used to coordinate access to
 *  shared data from multiple concurrent threads.
 *
 *  Example:
 *
 *    semaphore = Mutex.new
 *
 *    a = Thread.new {
 *      semaphore.synchronize {
 *        # access shared resource
 *      }
 *    }
 *
 *    b = Thread.new {
 *      semaphore.synchronize {
 *        # access shared resource
 *      }
 *    }
 *
 */

#define mutex_mark ((void(*)(void*))0)

static size_t
rb_mutex_num_waiting(rb_mutex_t *mutex)
{
    struct sync_waiter *w = 0;
    size_t n = 0;

    list_for_each(&mutex->waitq, w, node) {
	n++;
    }

    return n;
}

rb_thread_t* rb_fiber_threadptr(const rb_fiber_t *fiber);

static void
mutex_free(void *ptr)
{
    rb_mutex_t *mutex = ptr;
    if (mutex->fiber) {
	/* rb_warn("free locked mutex"); */
	const char *err = rb_mutex_unlock_th(mutex, rb_fiber_threadptr(mutex->fiber), mutex->fiber);
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
    {mutex_mark, mutex_free, mutex_memsize,},
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
    if (rb_typeddata_is_kind_of(obj, &mutex_data_type)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static VALUE
mutex_alloc(VALUE klass)
{
    VALUE obj;
    rb_mutex_t *mutex;

    obj = TypedData_Make_Struct(klass, rb_mutex_t, &mutex_data_type, mutex);

    list_head_init(&mutex->waitq);
    return obj;
}

/*
 *  call-seq:
 *     Mutex.new   -> mutex
 *
 *  Creates a new Mutex
 */
static VALUE
mutex_initialize(VALUE self)
{
    return self;
}

VALUE
rb_mutex_new(void)
{
    return mutex_alloc(rb_cMutex);
}

/*
 * call-seq:
 *    mutex.locked?  -> true or false
 *
 * Returns +true+ if this lock is currently held by some thread.
 */
VALUE
rb_mutex_locked_p(VALUE self)
{
    rb_mutex_t *mutex = mutex_ptr(self);

    return mutex->fiber ? Qtrue : Qfalse;
}

static void
thread_mutex_insert(rb_thread_t *thread, rb_mutex_t *mutex) {
    if (thread->keeping_mutexes) {
        mutex->next_mutex = thread->keeping_mutexes;
    }

    thread->keeping_mutexes = mutex;
}

static void
thread_mutex_remove(rb_thread_t *thread, rb_mutex_t *mutex) {
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
mutex_locked(rb_thread_t *th, VALUE self)
{
    rb_mutex_t *mutex = mutex_ptr(self);

    thread_mutex_insert(th, mutex);
}

/*
 * call-seq:
 *    mutex.try_lock  -> true or false
 *
 * Attempts to obtain the lock and returns immediately. Returns +true+ if the
 * lock was granted.
 */
VALUE
rb_mutex_trylock(VALUE self)
{
    rb_mutex_t *mutex = mutex_ptr(self);

    if (mutex->fiber == 0) {
	rb_fiber_t *fiber = GET_EC()->fiber_ptr;
	rb_thread_t *th = GET_THREAD();
	mutex->fiber = fiber;

	mutex_locked(th, self);
	return Qtrue;
    }

    return Qfalse;
}

/*
 * At maximum, only one thread can use cond_timedwait and watch deadlock
 * periodically. Multiple polling thread (i.e. concurrent deadlock check)
 * introduces new race conditions. [Bug #6278] [ruby-core:44275]
 */
static const rb_thread_t *patrol_thread = NULL;

static VALUE
mutex_owned_p(rb_fiber_t *fiber, rb_mutex_t *mutex)
{
    if (mutex->fiber == fiber) {
        return Qtrue;
    }
    else {
        return Qfalse;
    }
}

static VALUE call_rb_scheduler_block(VALUE mutex) {
    return rb_scheduler_block(rb_scheduler_current(), mutex, Qnil);
}

static VALUE
delete_from_waitq(VALUE v)
{
    struct sync_waiter *w = (void *)v;
    list_del(&w->node);

    COROUTINE_STACK_FREE(w);

    return Qnil;
}

static VALUE
do_mutex_lock(VALUE self, int interruptible_p)
{
    rb_execution_context_t *ec = GET_EC();
    rb_thread_t *th = ec->thread_ptr;
    rb_fiber_t *fiber = ec->fiber_ptr;
    rb_mutex_t *mutex = mutex_ptr(self);

    /* When running trap handler */
    if (!FL_TEST_RAW(self, MUTEX_ALLOW_TRAP) &&
	th->ec->interrupt_mask & TRAP_INTERRUPT_MASK) {
	rb_raise(rb_eThreadError, "can't be called from trap context");
    }

    if (rb_mutex_trylock(self) == Qfalse) {
        if (mutex->fiber == fiber) {
            rb_raise(rb_eThreadError, "deadlock; recursive locking");
        }

        while (mutex->fiber != fiber) {
            VALUE scheduler = rb_scheduler_current();
            if (scheduler != Qnil) {
                COROUTINE_STACK_LOCAL(struct sync_waiter, w);
                w->self = self;
                w->th = th;
                w->fiber = fiber;

                list_add_tail(&mutex->waitq, &w->node);

                rb_ensure(call_rb_scheduler_block, self, delete_from_waitq, (VALUE)w);

                if (!mutex->fiber) {
                    mutex->fiber = fiber;
                }
            } else {
                enum rb_thread_status prev_status = th->status;
                rb_hrtime_t *timeout = 0;
                rb_hrtime_t rel = rb_msec2hrtime(100);

                th->status = THREAD_STOPPED_FOREVER;
                th->locking_mutex = self;
                rb_ractor_sleeper_threads_inc(th->ractor);
                /*
                 * Carefully! while some contended threads are in native_sleep(),
                 * ractor->sleeper is unstable value. we have to avoid both deadlock
                 * and busy loop.
                 */
                if ((rb_ractor_living_thread_num(th->ractor) == rb_ractor_sleeper_thread_num(th->ractor)) &&
                    !patrol_thread) {
                    timeout = &rel;
                    patrol_thread = th;
                }

                COROUTINE_STACK_LOCAL(struct sync_waiter, w);
                w->self = self;
                w->th = th;
                w->fiber = fiber;

                list_add_tail(&mutex->waitq, &w->node);

                native_sleep(th, timeout); /* release GVL */

                list_del(&w->node);

                COROUTINE_STACK_FREE(w);

                if (!mutex->fiber) {
                    mutex->fiber = fiber;
                }

                if (patrol_thread == th)
                    patrol_thread = NULL;

                th->locking_mutex = Qfalse;
                if (mutex->fiber && timeout && !RUBY_VM_INTERRUPTED(th->ec)) {
                    rb_check_deadlock(th->ractor);
                }
                if (th->status == THREAD_STOPPED_FOREVER) {
                    th->status = prev_status;
                }
                rb_ractor_sleeper_threads_dec(th->ractor);
            }

            if (interruptible_p) {
                /* release mutex before checking for interrupts...as interrupt checking
                 * code might call rb_raise() */
                if (mutex->fiber == fiber) mutex->fiber = 0;
                RUBY_VM_CHECK_INTS_BLOCKING(th->ec); /* may release mutex */
                if (!mutex->fiber) {
                    mutex->fiber = fiber;
                }
            }
        }

        if (mutex->fiber == fiber) mutex_locked(th, self);
    }

    // assertion
    if (mutex_owned_p(fiber, mutex) == Qfalse) rb_bug("do_mutex_lock: mutex is not owned.");

    return self;
}

static VALUE
mutex_lock_uninterruptible(VALUE self)
{
    return do_mutex_lock(self, 0);
}

/*
 * call-seq:
 *    mutex.lock  -> self
 *
 * Attempts to grab the lock and waits if it isn't available.
 * Raises +ThreadError+ if +mutex+ was locked by the current thread.
 */
VALUE
rb_mutex_lock(VALUE self)
{
    return do_mutex_lock(self, 1);
}

/*
 * call-seq:
 *    mutex.owned?  -> true or false
 *
 * Returns +true+ if this lock is currently held by current thread.
 */
VALUE
rb_mutex_owned_p(VALUE self)
{
    rb_fiber_t *fiber = GET_EC()->fiber_ptr;
    rb_mutex_t *mutex = mutex_ptr(self);

    return mutex_owned_p(fiber, mutex);
}

static const char *
rb_mutex_unlock_th(rb_mutex_t *mutex, rb_thread_t *th, rb_fiber_t *fiber)
{
    const char *err = NULL;

    if (mutex->fiber == 0) {
        err = "Attempt to unlock a mutex which is not locked";
    }
    else if (mutex->fiber != fiber) {
        err = "Attempt to unlock a mutex which is locked by another thread/fiber";
    }
    else {
        struct sync_waiter *cur = 0, *next;

        mutex->fiber = 0;
        list_for_each_safe(&mutex->waitq, cur, next, node) {
            list_del_init(&cur->node);

            if (cur->th->scheduler != Qnil) {
                rb_scheduler_unblock(cur->th->scheduler, cur->self, rb_fiberptr_self(cur->fiber));
                goto found;
            } else {
                switch (cur->th->status) {
                  case THREAD_RUNNABLE: /* from someone else calling Thread#run */
                  case THREAD_STOPPED_FOREVER: /* likely (rb_mutex_lock) */
                    rb_threadptr_interrupt(cur->th);
                    goto found;
                  case THREAD_STOPPED: /* probably impossible */
                    rb_bug("unexpected THREAD_STOPPED");
                  case THREAD_KILLED:
                    /* not sure about this, possible in exit GC? */
                    rb_bug("unexpected THREAD_KILLED");
                    continue;
                }
            }
        }

    found:
        thread_mutex_remove(th, mutex);
    }

    return err;
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
    const char *err;
    rb_mutex_t *mutex = mutex_ptr(self);
    rb_thread_t *th = GET_THREAD();

    err = rb_mutex_unlock_th(mutex, th, GET_EC()->fiber_ptr);
    if (err) rb_raise(rb_eThreadError, "%s", err);

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

        list_head_init(&mutex->waitq);
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
	mutex->fiber = 0;
	mutex->next_mutex = 0;
	list_head_init(&mutex->waitq);
    }
}
#endif

static VALUE
rb_mutex_sleep_forever(VALUE self)
{
    rb_thread_sleep_deadly_allow_spurious_wakeup(self);
    return Qnil;
}

static VALUE
rb_mutex_wait_for(VALUE time)
{
    rb_hrtime_t *rel = (rb_hrtime_t *)time;
    /* permit spurious check */
    sleep_hrtime(GET_THREAD(), *rel, 0);
    return Qnil;
}

VALUE
rb_mutex_sleep(VALUE self, VALUE timeout)
{
    struct timeval t;

    if (!NIL_P(timeout)) {
        t = rb_time_interval(timeout);
    }

    rb_mutex_unlock(self);
    time_t beg = time(0);

    VALUE scheduler = rb_scheduler_current();
    if (scheduler != Qnil) {
        rb_scheduler_kernel_sleep(scheduler, timeout);
        mutex_lock_uninterruptible(self);
    } else {
        if (NIL_P(timeout)) {
            rb_ensure(rb_mutex_sleep_forever, self, mutex_lock_uninterruptible, self);
        } else {
            rb_hrtime_t rel = rb_timeval2hrtime(&t);
            rb_ensure(rb_mutex_wait_for, (VALUE)&rel, mutex_lock_uninterruptible, self);
        }
    }

    RUBY_VM_CHECK_INTS_BLOCKING(GET_EC());
    time_t end = time(0) - beg;
    return TIMET2NUM(end);
}

/*
 * call-seq:
 *    mutex.sleep(timeout = nil)    -> number
 *
 * Releases the lock and sleeps +timeout+ seconds if it is given and
 * non-nil or forever.  Raises +ThreadError+ if +mutex+ wasn't locked by
 * the current thread.
 *
 * When the thread is next woken up, it will attempt to reacquire
 * the lock.
 *
 * Note that this method can wakeup without explicit Thread#wakeup call.
 * For example, receiving signal and so on.
 */
static VALUE
mutex_sleep(int argc, VALUE *argv, VALUE self)
{
    VALUE timeout;

    timeout = rb_check_arity(argc, 0, 1) ? argv[0] : Qnil;
    return rb_mutex_sleep(self, timeout);
}

/*
 * call-seq:
 *    mutex.synchronize { ... }    -> result of the block
 *
 * Obtains a lock, runs the block, and releases the lock when the block
 * completes.  See the example under +Mutex+.
 */

VALUE
rb_mutex_synchronize(VALUE mutex, VALUE (*func)(VALUE arg), VALUE arg)
{
    rb_mutex_lock(mutex);
    return rb_ensure(func, arg, rb_mutex_unlock, mutex);
}

/*
 * call-seq:
 *    mutex.synchronize { ... }    -> result of the block
 *
 * Obtains a lock, runs the block, and releases the lock when the block
 * completes.  See the example under +Mutex+.
 */
static VALUE
rb_mutex_synchronize_m(VALUE self)
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }

    return rb_mutex_synchronize(self, rb_yield, Qundef);
}

void rb_mutex_allow_trap(VALUE self, int val)
{
    Check_TypedStruct(self, &mutex_data_type);

    if (val)
	FL_SET_RAW(self, MUTEX_ALLOW_TRAP);
    else
	FL_UNSET_RAW(self, MUTEX_ALLOW_TRAP);
}

/* Queue */

#define queue_waitq(q) UNALIGNED_MEMBER_PTR(q, waitq)
PACKED_STRUCT_UNALIGNED(struct rb_queue {
    struct list_head waitq;
    rb_serial_t fork_gen;
    const VALUE que;
    int num_waiting;
});

#define szqueue_waitq(sq) UNALIGNED_MEMBER_PTR(sq, q.waitq)
#define szqueue_pushq(sq) UNALIGNED_MEMBER_PTR(sq, pushq)
PACKED_STRUCT_UNALIGNED(struct rb_szqueue {
    struct rb_queue q;
    int num_waiting_push;
    struct list_head pushq;
    long max;
});

static void
queue_mark(void *ptr)
{
    struct rb_queue *q = ptr;

    /* no need to mark threads in waitq, they are on stack */
    rb_gc_mark(q->que);
}

static size_t
queue_memsize(const void *ptr)
{
    return sizeof(struct rb_queue);
}

static const rb_data_type_t queue_data_type = {
    "queue",
    {queue_mark, RUBY_TYPED_DEFAULT_FREE, queue_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
queue_alloc(VALUE klass)
{
    VALUE obj;
    struct rb_queue *q;

    obj = TypedData_Make_Struct(klass, struct rb_queue, &queue_data_type, q);
    list_head_init(queue_waitq(q));
    return obj;
}

static int
queue_fork_check(struct rb_queue *q)
{
    rb_serial_t fork_gen = GET_VM()->fork_gen;

    if (q->fork_gen == fork_gen) {
        return 0;
    }
    /* forked children can't reach into parent thread stacks */
    q->fork_gen = fork_gen;
    list_head_init(queue_waitq(q));
    q->num_waiting = 0;
    return 1;
}

static struct rb_queue *
queue_ptr(VALUE obj)
{
    struct rb_queue *q;

    TypedData_Get_Struct(obj, struct rb_queue, &queue_data_type, q);
    queue_fork_check(q);

    return q;
}

#define QUEUE_CLOSED          FL_USER5

static void
szqueue_mark(void *ptr)
{
    struct rb_szqueue *sq = ptr;

    queue_mark(&sq->q);
}

static size_t
szqueue_memsize(const void *ptr)
{
    return sizeof(struct rb_szqueue);
}

static const rb_data_type_t szqueue_data_type = {
    "sized_queue",
    {szqueue_mark, RUBY_TYPED_DEFAULT_FREE, szqueue_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
szqueue_alloc(VALUE klass)
{
    struct rb_szqueue *sq;
    VALUE obj = TypedData_Make_Struct(klass, struct rb_szqueue,
					&szqueue_data_type, sq);
    list_head_init(szqueue_waitq(sq));
    list_head_init(szqueue_pushq(sq));
    return obj;
}

static struct rb_szqueue *
szqueue_ptr(VALUE obj)
{
    struct rb_szqueue *sq;

    TypedData_Get_Struct(obj, struct rb_szqueue, &szqueue_data_type, sq);
    if (queue_fork_check(&sq->q)) {
        list_head_init(szqueue_pushq(sq));
        sq->num_waiting_push = 0;
    }

    return sq;
}

static VALUE
ary_buf_new(void)
{
    return rb_ary_tmp_new(1);
}

static VALUE
check_array(VALUE obj, VALUE ary)
{
    if (!RB_TYPE_P(ary, T_ARRAY)) {
	rb_raise(rb_eTypeError, "%+"PRIsVALUE" not initialized", obj);
    }
    return ary;
}

static long
queue_length(VALUE self, struct rb_queue *q)
{
    return RARRAY_LEN(check_array(self, q->que));
}

static int
queue_closed_p(VALUE self)
{
    return FL_TEST_RAW(self, QUEUE_CLOSED) != 0;
}

/*
 *  Document-class: ClosedQueueError
 *
 *  The exception class which will be raised when pushing into a closed
 *  Queue.  See Queue#close and SizedQueue#close.
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
    assert(queue_length(self, q) == 0);
    return Qnil;
}

/*
 *  Document-class: Queue
 *
 *  The Queue class implements multi-producer, multi-consumer queues.
 *  It is especially useful in threaded programming when information
 *  must be exchanged safely between multiple threads. The Queue class
 *  implements all the required locking semantics.
 *
 *  The class implements FIFO type of queue. In a FIFO queue, the first
 *  tasks added are the first retrieved.
 *
 *  Example:
 *
 *	queue = Queue.new
 *
 *	producer = Thread.new do
 *	  5.times do |i|
 *	     sleep rand(i) # simulate expense
 *	     queue << i
 *	     puts "#{i} produced"
 *	  end
 *	end
 *
 *	consumer = Thread.new do
 *	  5.times do |i|
 *	     value = queue.pop
 *	     sleep rand(i/2) # simulate expense
 *	     puts "consumed #{value}"
 *	  end
 *	end
 *
 *	consumer.join
 *
 */

/*
 * Document-method: Queue::new
 *
 * Creates a new queue instance.
 */

static VALUE
rb_queue_initialize(VALUE self)
{
    struct rb_queue *q = queue_ptr(self);
    RB_OBJ_WRITE(self, &q->que, ary_buf_new());
    list_head_init(queue_waitq(q));
    return self;
}

static VALUE
queue_do_push(VALUE self, struct rb_queue *q, VALUE obj)
{
    if (queue_closed_p(self)) {
	raise_closed_queue_error(self);
    }
    rb_ary_push(check_array(self, q->que), obj);
    wakeup_one(queue_waitq(q));
    return self;
}

/*
 * Document-method: Queue#close
 * call-seq:
 *   close
 *
 * Closes the queue. A closed queue cannot be re-opened.
 *
 * After the call to close completes, the following are true:
 *
 * - +closed?+ will return true
 *
 * - +close+ will be ignored.
 *
 * - calling enq/push/<< will raise a +ClosedQueueError+.
 *
 * - when +empty?+ is false, calling deq/pop/shift will return an object
 *   from the queue as usual.
 * - when +empty?+ is true, deq(false) will not suspend the thread and will return nil.
 *   deq(true) will raise a +ThreadError+.
 *
 * ClosedQueueError is inherited from StopIteration, so that you can break loop block.
 *
 *  Example:
 *
 *    	q = Queue.new
 *      Thread.new{
 *        while e = q.deq # wait for nil to break loop
 *          # ...
 *        end
 *      }
 *      q.close
 */

static VALUE
rb_queue_close(VALUE self)
{
    struct rb_queue *q = queue_ptr(self);

    if (!queue_closed_p(self)) {
	FL_SET(self, QUEUE_CLOSED);

	wakeup_all(queue_waitq(q));
    }

    return self;
}

/*
 * Document-method: Queue#closed?
 * call-seq: closed?
 *
 * Returns +true+ if the queue is closed.
 */

static VALUE
rb_queue_closed_p(VALUE self)
{
    return queue_closed_p(self) ? Qtrue : Qfalse;
}

/*
 * Document-method: Queue#push
 * call-seq:
 *   push(object)
 *   enq(object)
 *   <<(object)
 *
 * Pushes the given +object+ to the queue.
 */

static VALUE
rb_queue_push(VALUE self, VALUE obj)
{
    return queue_do_push(self, queue_ptr(self), obj);
}

static VALUE
queue_sleep(VALUE self)
{
    rb_thread_sleep_deadly_allow_spurious_wakeup(self);
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

    list_del(&qw->w.node);
    qw->as.q->num_waiting--;

    COROUTINE_STACK_FREE(qw);

    return Qfalse;
}

static VALUE
szqueue_sleep_done(VALUE p)
{
    struct queue_waiter *qw = (struct queue_waiter *)p;

    list_del(&qw->w.node);
    qw->as.sq->num_waiting_push--;

    COROUTINE_STACK_FREE(qw);

    return Qfalse;
}

static VALUE
queue_do_pop(VALUE self, struct rb_queue *q, int should_block)
{
    check_array(self, q->que);

    while (RARRAY_LEN(q->que) == 0) {
        if (!should_block) {
            rb_raise(rb_eThreadError, "queue empty");
        }
        else if (queue_closed_p(self)) {
            return queue_closed_result(self, q);
        }
        else {
            rb_execution_context_t *ec = GET_EC();

            assert(RARRAY_LEN(q->que) == 0);
            assert(queue_closed_p(self) == 0);

            COROUTINE_STACK_LOCAL(struct queue_waiter, qw);

            qw->w.self = self;
            qw->w.th = ec->thread_ptr;
            qw->w.fiber = ec->fiber_ptr;

            qw->as.q = q;
            list_add_tail(queue_waitq(qw->as.q), &qw->w.node);
            qw->as.q->num_waiting++;

            rb_ensure(queue_sleep, self, queue_sleep_done, (VALUE)qw);
        }
    }

    return rb_ary_shift(q->que);
}

static int
queue_pop_should_block(int argc, const VALUE *argv)
{
    int should_block = 1;
    rb_check_arity(argc, 0, 1);
    if (argc > 0) {
	should_block = !RTEST(argv[0]);
    }
    return should_block;
}

/*
 * Document-method: Queue#pop
 * call-seq:
 *   pop(non_block=false)
 *   deq(non_block=false)
 *   shift(non_block=false)
 *
 * Retrieves data from the queue.
 *
 * If the queue is empty, the calling thread is suspended until data is pushed
 * onto the queue. If +non_block+ is true, the thread isn't suspended, and
 * +ThreadError+ is raised.
 */

static VALUE
rb_queue_pop(int argc, VALUE *argv, VALUE self)
{
    int should_block = queue_pop_should_block(argc, argv);
    return queue_do_pop(self, queue_ptr(self), should_block);
}

/*
 * Document-method: Queue#empty?
 * call-seq: empty?
 *
 * Returns +true+ if the queue is empty.
 */

static VALUE
rb_queue_empty_p(VALUE self)
{
    return queue_length(self, queue_ptr(self)) == 0 ? Qtrue : Qfalse;
}

/*
 * Document-method: Queue#clear
 *
 * Removes all objects from the queue.
 */

static VALUE
rb_queue_clear(VALUE self)
{
    struct rb_queue *q = queue_ptr(self);

    rb_ary_clear(check_array(self, q->que));
    return self;
}

/*
 * Document-method: Queue#length
 * call-seq:
 *   length
 *   size
 *
 * Returns the length of the queue.
 */

static VALUE
rb_queue_length(VALUE self)
{
    return LONG2NUM(queue_length(self, queue_ptr(self)));
}

/*
 * Document-method: Queue#num_waiting
 *
 * Returns the number of threads waiting on the queue.
 */

static VALUE
rb_queue_num_waiting(VALUE self)
{
    struct rb_queue *q = queue_ptr(self);

    return INT2NUM(q->num_waiting);
}

/*
 *  Document-class: SizedQueue
 *
 * This class represents queues of specified size capacity.  The push operation
 * may be blocked if the capacity is full.
 *
 * See Queue for an example of how a SizedQueue works.
 */

/*
 * Document-method: SizedQueue::new
 * call-seq: new(max)
 *
 * Creates a fixed-length queue with a maximum size of +max+.
 */

static VALUE
rb_szqueue_initialize(VALUE self, VALUE vmax)
{
    long max;
    struct rb_szqueue *sq = szqueue_ptr(self);

    max = NUM2LONG(vmax);
    if (max <= 0) {
	rb_raise(rb_eArgError, "queue size must be positive");
    }

    RB_OBJ_WRITE(self, &sq->q.que, ary_buf_new());
    list_head_init(szqueue_waitq(sq));
    list_head_init(szqueue_pushq(sq));
    sq->max = max;

    return self;
}

/*
 * Document-method: SizedQueue#close
 * call-seq:
 *   close
 *
 * Similar to Queue#close.
 *
 * The difference is behavior with waiting enqueuing threads.
 *
 * If there are waiting enqueuing threads, they are interrupted by
 * raising ClosedQueueError('queue closed').
 */
static VALUE
rb_szqueue_close(VALUE self)
{
    if (!queue_closed_p(self)) {
	struct rb_szqueue *sq = szqueue_ptr(self);

	FL_SET(self, QUEUE_CLOSED);
	wakeup_all(szqueue_waitq(sq));
	wakeup_all(szqueue_pushq(sq));
    }
    return self;
}

/*
 * Document-method: SizedQueue#max
 *
 * Returns the maximum size of the queue.
 */

static VALUE
rb_szqueue_max_get(VALUE self)
{
    return LONG2NUM(szqueue_ptr(self)->max);
}

/*
 * Document-method: SizedQueue#max=
 * call-seq: max=(number)
 *
 * Sets the maximum size of the queue to the given +number+.
 */

static VALUE
rb_szqueue_max_set(VALUE self, VALUE vmax)
{
    long max = NUM2LONG(vmax);
    long diff = 0;
    struct rb_szqueue *sq = szqueue_ptr(self);

    if (max <= 0) {
	rb_raise(rb_eArgError, "queue size must be positive");
    }
    if (max > sq->max) {
	diff = max - sq->max;
    }
    sq->max = max;
    sync_wakeup(szqueue_pushq(sq), diff);
    return vmax;
}

static int
szqueue_push_should_block(int argc, const VALUE *argv)
{
    int should_block = 1;
    rb_check_arity(argc, 1, 2);
    if (argc > 1) {
	should_block = !RTEST(argv[1]);
    }
    return should_block;
}

/*
 * Document-method: SizedQueue#push
 * call-seq:
 *   push(object, non_block=false)
 *   enq(object, non_block=false)
 *   <<(object)
 *
 * Pushes +object+ to the queue.
 *
 * If there is no space left in the queue, waits until space becomes
 * available, unless +non_block+ is true.  If +non_block+ is true, the
 * thread isn't suspended, and +ThreadError+ is raised.
 */

static VALUE
rb_szqueue_push(int argc, VALUE *argv, VALUE self)
{
    struct rb_szqueue *sq = szqueue_ptr(self);
    int should_block = szqueue_push_should_block(argc, argv);

    while (queue_length(self, &sq->q) >= sq->max) {
        if (!should_block) {
            rb_raise(rb_eThreadError, "queue full");
        }
        else if (queue_closed_p(self)) {
            break;
        }
        else {
            rb_execution_context_t *ec = GET_EC();
            COROUTINE_STACK_LOCAL(struct queue_waiter, qw);
            struct list_head *pushq = szqueue_pushq(sq);

            qw->w.self = self;
            qw->w.th = ec->thread_ptr;
            qw->w.fiber = ec->fiber_ptr;

            qw->as.sq = sq;
            list_add_tail(pushq, &qw->w.node);
            sq->num_waiting_push++;

            rb_ensure(queue_sleep, self, szqueue_sleep_done, (VALUE)qw);
        }
    }

    if (queue_closed_p(self)) {
        raise_closed_queue_error(self);
    }

    return queue_do_push(self, &sq->q, argv[0]);
}

static VALUE
szqueue_do_pop(VALUE self, int should_block)
{
    struct rb_szqueue *sq = szqueue_ptr(self);
    VALUE retval = queue_do_pop(self, &sq->q, should_block);

    if (queue_length(self, &sq->q) < sq->max) {
	wakeup_one(szqueue_pushq(sq));
    }

    return retval;
}

/*
 * Document-method: SizedQueue#pop
 * call-seq:
 *   pop(non_block=false)
 *   deq(non_block=false)
 *   shift(non_block=false)
 *
 * Retrieves data from the queue.
 *
 * If the queue is empty, the calling thread is suspended until data is pushed
 * onto the queue. If +non_block+ is true, the thread isn't suspended, and
 * +ThreadError+ is raised.
 */

static VALUE
rb_szqueue_pop(int argc, VALUE *argv, VALUE self)
{
    int should_block = queue_pop_should_block(argc, argv);
    return szqueue_do_pop(self, should_block);
}

/*
 * Document-method: SizedQueue#clear
 *
 * Removes all objects from the queue.
 */

static VALUE
rb_szqueue_clear(VALUE self)
{
    struct rb_szqueue *sq = szqueue_ptr(self);

    rb_ary_clear(check_array(self, sq->q.que));
    wakeup_all(szqueue_pushq(sq));
    return self;
}

/*
 * Document-method: SizedQueue#length
 * call-seq:
 *   length
 *   size
 *
 * Returns the length of the queue.
 */

static VALUE
rb_szqueue_length(VALUE self)
{
    struct rb_szqueue *sq = szqueue_ptr(self);

    return LONG2NUM(queue_length(self, &sq->q));
}

/*
 * Document-method: SizedQueue#num_waiting
 *
 * Returns the number of threads waiting on the queue.
 */

static VALUE
rb_szqueue_num_waiting(VALUE self)
{
    struct rb_szqueue *sq = szqueue_ptr(self);

    return INT2NUM(sq->q.num_waiting + sq->num_waiting_push);
}

/*
 * Document-method: SizedQueue#empty?
 * call-seq: empty?
 *
 * Returns +true+ if the queue is empty.
 */

static VALUE
rb_szqueue_empty_p(VALUE self)
{
    struct rb_szqueue *sq = szqueue_ptr(self);

    return queue_length(self, &sq->q) == 0 ? Qtrue : Qfalse;
}


/* ConditionalVariable */
struct rb_condvar {
    struct list_head waitq;
    rb_serial_t fork_gen;
};

/*
 *  Document-class: ConditionVariable
 *
 *  ConditionVariable objects augment class Mutex. Using condition variables,
 *  it is possible to suspend while in the middle of a critical section until a
 *  resource becomes available.
 *
 *  Example:
 *
 *    mutex = Mutex.new
 *    resource = ConditionVariable.new
 *
 *    a = Thread.new {
 *	 mutex.synchronize {
 *	   # Thread 'a' now needs the resource
 *	   resource.wait(mutex)
 *	   # 'a' can now have the resource
 *	 }
 *    }
 *
 *    b = Thread.new {
 *	 mutex.synchronize {
 *	   # Thread 'b' has finished using the resource
 *	   resource.signal
 *	 }
 *    }
 */

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
        list_head_init(&cv->waitq);
    }

    return cv;
}

static VALUE
condvar_alloc(VALUE klass)
{
    struct rb_condvar *cv;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct rb_condvar, &cv_data_type, cv);
    list_head_init(&cv->waitq);

    return obj;
}

/*
 * Document-method: ConditionVariable::new
 *
 * Creates a new condition variable instance.
 */

static VALUE
rb_condvar_initialize(VALUE self)
{
    struct rb_condvar *cv = condvar_ptr(self);
    list_head_init(&cv->waitq);
    return self;
}

struct sleep_call {
    VALUE mutex;
    VALUE timeout;
};

static ID id_sleep;

static VALUE
do_sleep(VALUE args)
{
    struct sleep_call *p = (struct sleep_call *)args;
    return rb_funcallv(p->mutex, id_sleep, 1, &p->timeout);
}

/*
 * Document-method: ConditionVariable#wait
 * call-seq: wait(mutex, timeout=nil)
 *
 * Releases the lock held in +mutex+ and waits; reacquires the lock on wakeup.
 *
 * If +timeout+ is given, this method returns after +timeout+ seconds passed,
 * even if no other thread doesn't signal.
 */

static VALUE
rb_condvar_wait(int argc, VALUE *argv, VALUE self)
{
    rb_execution_context_t *ec = GET_EC();

    struct rb_condvar *cv = condvar_ptr(self);
    struct sleep_call args;

    rb_scan_args(argc, argv, "11", &args.mutex, &args.timeout);

    COROUTINE_STACK_LOCAL(struct sync_waiter, w);
    w->self = args.mutex;
    w->th = ec->thread_ptr;
    w->fiber = ec->fiber_ptr;

    list_add_tail(&cv->waitq, &w->node);
    rb_ensure(do_sleep, (VALUE)&args, delete_from_waitq, (VALUE)w);

    return self;
}

/*
 * Document-method: ConditionVariable#signal
 *
 * Wakes up the first thread in line waiting for this lock.
 */

static VALUE
rb_condvar_signal(VALUE self)
{
    struct rb_condvar *cv = condvar_ptr(self);
    wakeup_one(&cv->waitq);
    return self;
}

/*
 * Document-method: ConditionVariable#broadcast
 *
 * Wakes up all threads waiting for this lock.
 */

static VALUE
rb_condvar_broadcast(VALUE self)
{
    struct rb_condvar *cv = condvar_ptr(self);
    wakeup_all(&cv->waitq);
    return self;
}

NORETURN(static VALUE undumpable(VALUE obj));
/* :nodoc: */
static VALUE
undumpable(VALUE obj)
{
    rb_raise(rb_eTypeError, "can't dump %"PRIsVALUE, rb_obj_class(obj));
    UNREACHABLE_RETURN(Qnil);
}

static VALUE
define_thread_class(VALUE outer, const char *name, VALUE super)
{
    VALUE klass = rb_define_class_under(outer, name, super);
    rb_define_const(rb_cObject, name, klass);
    return klass;
}

static void
Init_thread_sync(void)
{
#undef rb_intern
#if 0
    rb_cMutex = rb_define_class("Mutex", rb_cObject); /* teach rdoc Mutex */
    rb_cConditionVariable = rb_define_class("ConditionVariable", rb_cObject); /* teach rdoc ConditionVariable */
    rb_cQueue = rb_define_class("Queue", rb_cObject); /* teach rdoc Queue */
    rb_cSizedQueue = rb_define_class("SizedQueue", rb_cObject); /* teach rdoc SizedQueue */
#endif

#define DEFINE_CLASS(name, super) \
    rb_c##name = define_thread_class(rb_cThread, #name, rb_c##super)

    /* Mutex */
    DEFINE_CLASS(Mutex, Object);
    rb_define_alloc_func(rb_cMutex, mutex_alloc);
    rb_define_method(rb_cMutex, "initialize", mutex_initialize, 0);
    rb_define_method(rb_cMutex, "locked?", rb_mutex_locked_p, 0);
    rb_define_method(rb_cMutex, "try_lock", rb_mutex_trylock, 0);
    rb_define_method(rb_cMutex, "lock", rb_mutex_lock, 0);
    rb_define_method(rb_cMutex, "unlock", rb_mutex_unlock, 0);
    rb_define_method(rb_cMutex, "sleep", mutex_sleep, -1);
    rb_define_method(rb_cMutex, "synchronize", rb_mutex_synchronize_m, 0);
    rb_define_method(rb_cMutex, "owned?", rb_mutex_owned_p, 0);

    /* Queue */
    DEFINE_CLASS(Queue, Object);
    rb_define_alloc_func(rb_cQueue, queue_alloc);

    rb_eClosedQueueError = rb_define_class("ClosedQueueError", rb_eStopIteration);

    rb_define_method(rb_cQueue, "initialize", rb_queue_initialize, 0);
    rb_undef_method(rb_cQueue, "initialize_copy");
    rb_define_method(rb_cQueue, "marshal_dump", undumpable, 0);
    rb_define_method(rb_cQueue, "close", rb_queue_close, 0);
    rb_define_method(rb_cQueue, "closed?", rb_queue_closed_p, 0);
    rb_define_method(rb_cQueue, "push", rb_queue_push, 1);
    rb_define_method(rb_cQueue, "pop", rb_queue_pop, -1);
    rb_define_method(rb_cQueue, "empty?", rb_queue_empty_p, 0);
    rb_define_method(rb_cQueue, "clear", rb_queue_clear, 0);
    rb_define_method(rb_cQueue, "length", rb_queue_length, 0);
    rb_define_method(rb_cQueue, "num_waiting", rb_queue_num_waiting, 0);

    rb_define_alias(rb_cQueue, "enq", "push");
    rb_define_alias(rb_cQueue, "<<", "push");
    rb_define_alias(rb_cQueue, "deq", "pop");
    rb_define_alias(rb_cQueue, "shift", "pop");
    rb_define_alias(rb_cQueue, "size", "length");

    DEFINE_CLASS(SizedQueue, Queue);
    rb_define_alloc_func(rb_cSizedQueue, szqueue_alloc);

    rb_define_method(rb_cSizedQueue, "initialize", rb_szqueue_initialize, 1);
    rb_define_method(rb_cSizedQueue, "close", rb_szqueue_close, 0);
    rb_define_method(rb_cSizedQueue, "max", rb_szqueue_max_get, 0);
    rb_define_method(rb_cSizedQueue, "max=", rb_szqueue_max_set, 1);
    rb_define_method(rb_cSizedQueue, "push", rb_szqueue_push, -1);
    rb_define_method(rb_cSizedQueue, "pop", rb_szqueue_pop, -1);
    rb_define_method(rb_cSizedQueue, "empty?", rb_szqueue_empty_p, 0);
    rb_define_method(rb_cSizedQueue, "clear", rb_szqueue_clear, 0);
    rb_define_method(rb_cSizedQueue, "length", rb_szqueue_length, 0);
    rb_define_method(rb_cSizedQueue, "num_waiting", rb_szqueue_num_waiting, 0);

    rb_define_alias(rb_cSizedQueue, "enq", "push");
    rb_define_alias(rb_cSizedQueue, "<<", "push");
    rb_define_alias(rb_cSizedQueue, "deq", "pop");
    rb_define_alias(rb_cSizedQueue, "shift", "pop");
    rb_define_alias(rb_cSizedQueue, "size", "length");

    /* CVar */
    DEFINE_CLASS(ConditionVariable, Object);
    rb_define_alloc_func(rb_cConditionVariable, condvar_alloc);

    id_sleep = rb_intern("sleep");

    rb_define_method(rb_cConditionVariable, "initialize", rb_condvar_initialize, 0);
    rb_undef_method(rb_cConditionVariable, "initialize_copy");
    rb_define_method(rb_cConditionVariable, "marshal_dump", undumpable, 0);
    rb_define_method(rb_cConditionVariable, "wait", rb_condvar_wait, -1);
    rb_define_method(rb_cConditionVariable, "signal", rb_condvar_signal, 0);
    rb_define_method(rb_cConditionVariable, "broadcast", rb_condvar_broadcast, 0);

    rb_provide("thread.rb");
}
