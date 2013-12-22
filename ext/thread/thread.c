#include <ruby.h>

enum {
    CONDVAR_WAITERS = 0
};

enum {
    QUEUE_QUE       = 0,
    QUEUE_WAITERS   = 1,
    SZQUEUE_WAITERS = 2,
    SZQUEUE_MAX     = 3
};

#define GET_CONDVAR_WAITERS(cv) RSTRUCT_GET((cv), CONDVAR_WAITERS)

#define GET_QUEUE_QUE(q)        RSTRUCT_GET((q), QUEUE_QUE)
#define GET_QUEUE_WAITERS(q)    RSTRUCT_GET((q), QUEUE_WAITERS)
#define GET_SZQUEUE_WAITERS(q)  RSTRUCT_GET((q), SZQUEUE_WAITERS)
#define GET_SZQUEUE_MAX(q)      RSTRUCT_GET((q), SZQUEUE_MAX)
#define GET_SZQUEUE_ULONGMAX(q) NUM2ULONG(GET_SZQUEUE_MAX(q))

static VALUE
ary_buf_new(void)
{
    return rb_ary_tmp_new(1);
}

static void
wakeup_first_thread(VALUE list)
{
    VALUE thread;

    while (!NIL_P(thread = rb_ary_shift(list))) {
	if (RTEST(rb_thread_wakeup_alive(thread))) break;
    }
}

static void
wakeup_all_threads(VALUE list)
{
    VALUE thread;
    long i;

    for (i=0; i<RARRAY_LEN(list); i++) {
	thread = RARRAY_AREF(list, i);
	rb_thread_wakeup_alive(thread);
    }
    rb_ary_clear(list);
}

/*
 *  Document-class: ConditionVariable
 *
 *  ConditionVariable objects augment class Mutex. Using condition variables,
 *  it is possible to suspend while in the middle of a critical section until a
 *  resource becomes available.
 *
 *  Example:
 *
 *    require 'thread'
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

/*
 * Document-method: ConditionVariable::new
 *
 * Creates a new condition variable instance.
 */

static VALUE
rb_condvar_initialize(VALUE self)
{
    RSTRUCT_SET(self, CONDVAR_WAITERS, ary_buf_new());
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
    return rb_funcall2(p->mutex, id_sleep, 1, &p->timeout);
}

static VALUE
delete_current_thread(VALUE ary)
{
    return rb_ary_delete(ary, rb_thread_current());
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
    VALUE waiters = GET_CONDVAR_WAITERS(self);
    VALUE mutex, timeout;
    struct sleep_call args;

    rb_scan_args(argc, argv, "11", &mutex, &timeout);

    args.mutex   = mutex;
    args.timeout = timeout;
    rb_ary_push(waiters, rb_thread_current());
    rb_ensure(do_sleep, (VALUE)&args, delete_current_thread, waiters);

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
    wakeup_first_thread(GET_CONDVAR_WAITERS(self));
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
    wakeup_all_threads(GET_CONDVAR_WAITERS(self));
    return self;
}

/*
 *  Document-class: Queue
 *
 *  This class provides a way to synchronize communication between threads.
 *
 *  Example:
 *
 *	require 'thread'
 *    	queue = Queue.new
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
 */

/*
 * Document-method: Queue::new
 *
 * Creates a new queue instance.
 */

static VALUE
rb_queue_initialize(VALUE self)
{
    RSTRUCT_SET(self, QUEUE_QUE, ary_buf_new());
    RSTRUCT_SET(self, QUEUE_WAITERS, ary_buf_new());
    return self;
}

static VALUE
queue_do_push(VALUE self, VALUE obj)
{
    rb_ary_push(GET_QUEUE_QUE(self), obj);
    wakeup_first_thread(GET_QUEUE_WAITERS(self));
    return self;
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
    return queue_do_push(self, obj);
}

static unsigned long
queue_length(VALUE self)
{
    return RARRAY_LEN(GET_QUEUE_QUE(self));
}

static unsigned long
queue_num_waiting(VALUE self)
{
    return RARRAY_LEN(GET_QUEUE_WAITERS(self));
}

struct waiting_delete {
    VALUE waiting;
    VALUE th;
};

static VALUE
queue_delete_from_waiting(struct waiting_delete *p)
{
    rb_ary_delete(p->waiting, p->th);
    return Qnil;
}

static VALUE
queue_sleep(VALUE arg)
{
    rb_thread_sleep_deadly();
    return Qnil;
}

static VALUE
queue_do_pop(VALUE self, VALUE should_block)
{
    struct waiting_delete args;
    args.waiting = GET_QUEUE_WAITERS(self);
    args.th	 = rb_thread_current();

    while (queue_length(self) == 0) {
	if (!(int)should_block) {
	    rb_raise(rb_eThreadError, "queue empty");
	}
	rb_ary_push(args.waiting, args.th);
	rb_ensure(queue_sleep, (VALUE)0, queue_delete_from_waiting, (VALUE)&args);
    }

    return rb_ary_shift(GET_QUEUE_QUE(self));
}

static VALUE
queue_pop_should_block(int argc, VALUE *argv)
{
    VALUE should_block = Qtrue;
    switch (argc) {
      case 0:
	break;
      case 1:
	should_block = RTEST(argv[0]) ? Qfalse : Qtrue;
	break;
      default:
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
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
 * onto the queue. If +non_block+ is true, the thread isn't suspended, and an
 * exception is raised.
 */

static VALUE
rb_queue_pop(int argc, VALUE *argv, VALUE self)
{
    VALUE should_block = queue_pop_should_block(argc, argv);
    return queue_do_pop(self, should_block);
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
    return queue_length(self) == 0 ? Qtrue : Qfalse;
}

/*
 * Document-method: Queue#clear
 *
 * Removes all objects from the queue.
 */

static VALUE
rb_queue_clear(VALUE self)
{
    rb_ary_clear(GET_QUEUE_QUE(self));
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
    unsigned long len = queue_length(self);
    return ULONG2NUM(len);
}

/*
 * Document-method: Queue#num_waiting
 *
 * Returns the number of threads waiting on the queue.
 */

static VALUE
rb_queue_num_waiting(VALUE self)
{
    unsigned long len = queue_num_waiting(self);
    return ULONG2NUM(len);
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

    max = NUM2LONG(vmax);
    if (max <= 0) {
	rb_raise(rb_eArgError, "queue size must be positive");
    }

    RSTRUCT_SET(self, QUEUE_QUE, ary_buf_new());
    RSTRUCT_SET(self, QUEUE_WAITERS, ary_buf_new());
    RSTRUCT_SET(self, SZQUEUE_WAITERS, ary_buf_new());
    RSTRUCT_SET(self, SZQUEUE_MAX, vmax);

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
    return GET_SZQUEUE_MAX(self);
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
    long max = NUM2LONG(vmax), diff = 0;
    VALUE t;

    if (max <= 0) {
	rb_raise(rb_eArgError, "queue size must be positive");
    }
    if ((unsigned long)max > GET_SZQUEUE_ULONGMAX(self)) {
	diff = max - GET_SZQUEUE_ULONGMAX(self);
    }
    RSTRUCT_SET(self, SZQUEUE_MAX, vmax);
    while (diff > 0 && !NIL_P(t = rb_ary_shift(GET_QUEUE_QUE(self)))) {
	rb_thread_wakeup_alive(t);
    }
    return vmax;
}

/*
 * Document-method: SizedQueue#push
 * call-seq:
 *   push(object)
 *   enq(object)
 *   <<(object)
 *
 * Pushes +object+ to the queue.
 *
 * If there is no space left in the queue, waits until space becomes available.
 */

static VALUE
rb_szqueue_push(VALUE self, VALUE obj)
{
    struct waiting_delete args;
    args.waiting = GET_QUEUE_WAITERS(self);
    args.th      = rb_thread_current();

    while (queue_length(self) >= GET_SZQUEUE_ULONGMAX(self)) {
	rb_ary_push(args.waiting, args.th);
	rb_ensure((VALUE (*)())rb_thread_sleep_deadly, (VALUE)0, queue_delete_from_waiting, (VALUE)&args);
    }
    return queue_do_push(self, obj);
}

static VALUE
szqueue_do_pop(VALUE self, VALUE should_block)
{
    VALUE retval = queue_do_pop(self, should_block);

    if (queue_length(self) < GET_SZQUEUE_ULONGMAX(self)) {
	wakeup_first_thread(GET_SZQUEUE_WAITERS(self));
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
 * onto the queue. If +non_block+ is true, the thread isn't suspended, and an
 * exception is raised.
 */

static VALUE
rb_szqueue_pop(int argc, VALUE *argv, VALUE self)
{
    VALUE should_block = queue_pop_should_block(argc, argv);
    return szqueue_do_pop(self, should_block);
}

/*
 * Document-method: SizedQueue#num_waiting
 *
 * Returns the number of threads waiting on the queue.
 */

static VALUE
rb_szqueue_num_waiting(VALUE self)
{
    long len = queue_num_waiting(self);
    len += RARRAY_LEN(GET_SZQUEUE_WAITERS(self));
    return ULONG2NUM(len);
}

#ifndef UNDER_THREAD
#define UNDER_THREAD 1
#endif

void
Init_thread(void)
{
#if UNDER_THREAD
#define ALIAS_GLOBAL_CONST(name) do {	              \
	ID id = rb_intern_const(#name);	              \
	if (!rb_const_defined_at(rb_cObject, id)) {   \
	    rb_const_set(rb_cObject, id, rb_c##name); \
	}                                             \
    } while (0)
#define OUTER rb_cThread
#else
#define ALIAS_GLOBAL_CONST(name) do { /* nothing */ } while (0)
#define OUTER 0
#endif

    VALUE rb_cConditionVariable = rb_struct_define_without_accessor_under(
	OUTER,
	"ConditionVariable", rb_cObject, rb_struct_alloc_noinit,
	"waiters", NULL);
    VALUE rb_cQueue = rb_struct_define_without_accessor_under(
	OUTER,
	"Queue", rb_cObject, rb_struct_alloc_noinit,
	"que", "waiters", NULL);
    VALUE rb_cSizedQueue = rb_struct_define_without_accessor_under(
	OUTER,
	"SizedQueue", rb_cQueue, rb_struct_alloc_noinit,
	"que", "waiters", "queue_waiters", "size", NULL);

#if 0
    rb_cConditionVariable = rb_define_class("ConditionVariable", rb_cObject); /* teach rdoc ConditionVariable */
    rb_cQueue = rb_define_class("Queue", rb_cObject); /* teach rdoc Queue */
    rb_cSizedQueue = rb_define_class("SizedQueue", rb_cObject); /* teach rdoc SizedQueue */
#endif

    id_sleep = rb_intern("sleep");

    rb_define_method(rb_cConditionVariable, "initialize", rb_condvar_initialize, 0);
    rb_define_method(rb_cConditionVariable, "wait", rb_condvar_wait, -1);
    rb_define_method(rb_cConditionVariable, "signal", rb_condvar_signal, 0);
    rb_define_method(rb_cConditionVariable, "broadcast", rb_condvar_broadcast, 0);

    rb_define_method(rb_cQueue, "initialize", rb_queue_initialize, 0);
    rb_define_method(rb_cQueue, "push", rb_queue_push, 1);
    rb_define_method(rb_cQueue, "pop", rb_queue_pop, -1);
    rb_define_method(rb_cQueue, "empty?", rb_queue_empty_p, 0);
    rb_define_method(rb_cQueue, "clear", rb_queue_clear, 0);
    rb_define_method(rb_cQueue, "length", rb_queue_length, 0);
    rb_define_method(rb_cQueue, "num_waiting", rb_queue_num_waiting, 0);

    /* Alias for #push. */
    rb_define_alias(rb_cQueue, "enq", "push");
    /* Alias for #push. */
    rb_define_alias(rb_cQueue, "<<", "push");
    /* Alias for #pop. */
    rb_define_alias(rb_cQueue, "deq", "pop");
    /* Alias for #pop. */
    rb_define_alias(rb_cQueue, "shift", "pop");
    /* Alias for #length. */
    rb_define_alias(rb_cQueue, "size", "length");

    rb_define_method(rb_cSizedQueue, "initialize", rb_szqueue_initialize, 1);
    rb_define_method(rb_cSizedQueue, "max", rb_szqueue_max_get, 0);
    rb_define_method(rb_cSizedQueue, "max=", rb_szqueue_max_set, 1);
    rb_define_method(rb_cSizedQueue, "push", rb_szqueue_push, 1);
    rb_define_method(rb_cSizedQueue, "pop", rb_szqueue_pop, -1);
    rb_define_method(rb_cSizedQueue, "num_waiting", rb_szqueue_num_waiting, 0);

    /* Alias for #push. */
    rb_define_alias(rb_cSizedQueue, "enq", "push");
    /* Alias for #push. */
    rb_define_alias(rb_cSizedQueue, "<<", "push");
    /* Alias for #pop. */
    rb_define_alias(rb_cSizedQueue, "deq", "pop");
    /* Alias for #pop. */
    rb_define_alias(rb_cSizedQueue, "shift", "pop");

    rb_provide("thread.rb");
    ALIAS_GLOBAL_CONST(ConditionVariable);
    ALIAS_GLOBAL_CONST(Queue);
    ALIAS_GLOBAL_CONST(SizedQueue);
}
