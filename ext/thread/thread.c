/*
 * Optimized Ruby Mutex implementation, loosely based on thread.rb by
 * Yukihiro Matsumoto <matz@ruby-lang.org>
 *
 *  Copyright 2006-2007  MenTaLguY <mental@rydia.net>
 *
 * RDoc taken from original.
 *
 * This file is made available under the same terms as Ruby.
 */

#include <ruby.h>
#include <intern.h>
#include <rubysig.h>
#include <node.h>

enum rb_thread_status rb_thread_status _((VALUE));

static VALUE rb_cMutex;
static VALUE rb_cConditionVariable;
static VALUE rb_cQueue;
static VALUE rb_cSizedQueue;

static VALUE set_critical(VALUE value);

static VALUE
thread_exclusive(VALUE (*func)(ANYARGS), VALUE arg)
{
    VALUE critical = rb_thread_critical;

    rb_thread_critical = 1;
    return rb_ensure(func, arg, set_critical, (VALUE)critical);
}

/*
 *  call-seq:
 *     Thread.exclusive { block }   => obj
 *  
 *  Wraps a block in Thread.critical, restoring the original value
 *  upon exit from the critical section, and returns the value of the
 *  block.
 */

static VALUE
rb_thread_exclusive(void)
{
    return thread_exclusive(rb_yield, Qundef);
}

typedef struct _Entry {
    VALUE value;
    struct _Entry *next;
} Entry;

typedef struct _List {
    Entry *entries;
    Entry *last_entry;
    Entry *entry_pool;
    unsigned long size;
} List;

static void
init_list(List *list)
{
    list->entries = NULL;
    list->last_entry = NULL;
    list->entry_pool = NULL;
    list->size = 0;
}

static void
mark_list(List *list)
{
    Entry *entry;
    for (entry = list->entries; entry; entry = entry->next) {
        rb_gc_mark(entry->value);
    }
}

static void
free_entries(Entry *first)
{
    Entry *next;
    while (first) {
        next = first->next;
        xfree(first);
        first = next;
    }
}

static void
finalize_list(List *list)
{
    free_entries(list->entries);
    free_entries(list->entry_pool);
}

static void
push_list(List *list, VALUE value)
{
    Entry *entry;

    if (list->entry_pool) {
        entry = list->entry_pool;
        list->entry_pool = entry->next;
    } else {
        entry = ALLOC(Entry);
    }

    entry->value = value;
    entry->next = NULL;

    if (list->last_entry) {
        list->last_entry->next = entry;
    } else {
        list->entries = entry;
    }
    list->last_entry = entry;

    ++list->size;
}

static void
push_multiple_list(List *list, VALUE *values, unsigned count)
{
    unsigned i;
    for (i = 0; i < count; i++) {
        push_list(list, values[i]);
    }
}

static void
recycle_entries(List *list, Entry *first_entry, Entry *last_entry)
{
#ifdef USE_MEM_POOLS
    last_entry->next = list->entry_pool;
    list->entry_pool = first_entry;
#else
    last_entry->next = NULL;
    free_entries(first_entry);
#endif
}

static VALUE
shift_list(List *list)
{
    Entry *entry;
    VALUE value;

    entry = list->entries;
    if (!entry) return Qnil;

    list->entries = entry->next;
    if (entry == list->last_entry) {
        list->last_entry = NULL;
    }

    --list->size;

    value = entry->value;
    recycle_entries(list, entry, entry);

    return value;
}

static void
remove_one(List *list, VALUE value)
{
    Entry **ref;
    Entry *prev;
    Entry *entry;

    for (ref = &list->entries, prev = NULL, entry = list->entries;
              entry != NULL;
              ref = &entry->next, prev = entry, entry = entry->next) {
        if (entry->value == value) {
            *ref = entry->next;
            list->size--;
            if (!entry->next) {
                list->last_entry = prev;
            }
            recycle_entries(list, entry, entry);
            break;
        }
    }
}

static void
clear_list(List *list)
{
    if (list->last_entry) {
        recycle_entries(list, list->entries, list->last_entry);
        list->entries = NULL;
        list->last_entry = NULL;
        list->size = 0;
    }
}

static VALUE
array_from_list(List const *list)
{
    VALUE ary;
    Entry *entry;
    ary = rb_ary_new();
    for (entry = list->entries; entry; entry = entry->next) {
        rb_ary_push(ary, entry->value);
    }
    return ary;
}

static VALUE
wake_thread(VALUE thread)
{
    return rb_thread_wakeup_alive(thread);
}

static VALUE
run_thread(VALUE thread)
{
    thread = wake_thread(thread);
    if (RTEST(thread) && !rb_thread_critical)
	rb_thread_schedule();
    return thread;
}

static VALUE
wake_one(List *list)
{
    VALUE waking;

    waking = Qnil;
    while (list->entries && !RTEST(waking)) {
	waking = shift_list(list);
	if (waking == Qundef) break;
	waking = wake_thread(waking);
    }

    return waking;
}

static VALUE
wake_all(List *list)
{
    while (list->entries) {
        wake_one(list);
    }
    return Qnil;
}

static VALUE
wait_list_inner(List *list)
{
    push_list(list, rb_thread_current());
    rb_thread_stop();
    return Qnil;
}

static VALUE
wait_list_cleanup(List *list)
{
    /* cleanup in case of spurious wakeups */
    remove_one(list, rb_thread_current());
    return Qnil;
}

static void
wait_list(List *list)
{
    rb_ensure(wait_list_inner, (VALUE)list, wait_list_cleanup, (VALUE)list);
}

static void
kill_waiting_threads(List *waiting)
{
    Entry *entry;

    for (entry = waiting->entries; entry; entry = entry->next) {
	rb_thread_kill(entry->value);
    }
}

/*
 * Document-class: Mutex
 *
 * Mutex implements a simple semaphore that can be used to coordinate access to
 * shared data from multiple concurrent threads.
 *
 * Example:
 *
 *   require 'thread'
 *   semaphore = Mutex.new
 *
 *   a = Thread.new {
 *     semaphore.synchronize {
 *       # access shared resource
 *     }
 *   }
 *
 *   b = Thread.new {
 *     semaphore.synchronize {
 *       # access shared resource
 *     }
 *   }
 *
 */

typedef struct _Mutex {
    VALUE owner;
    List waiting;
} Mutex;

#define MUTEX_LOCKED_P(mutex) (RTEST((mutex)->owner) && rb_thread_alive_p((mutex)->owner))

static void
mark_mutex(Mutex *mutex)
{
    rb_gc_mark(mutex->owner);
    mark_list(&mutex->waiting);
}

static void
finalize_mutex(Mutex *mutex)
{
    finalize_list(&mutex->waiting);
}

static void
free_mutex(Mutex *mutex)
{
    kill_waiting_threads(&mutex->waiting);
    finalize_mutex(mutex);
    xfree(mutex);
}

static void
init_mutex(Mutex *mutex)
{
    mutex->owner = Qnil;
    init_list(&mutex->waiting);
}

/*
 * Document-method: new
 * call-seq: Mutex.new
 * 
 * Creates a new Mutex
 *
 */

static VALUE 
rb_mutex_alloc(VALUE klass)
{
    Mutex *mutex;
    mutex = ALLOC(Mutex);
    init_mutex(mutex);
    return Data_Wrap_Struct(klass, mark_mutex, free_mutex, mutex);
}

/*
 * Document-method: locked?
 * call-seq: locked?
 *
 * Returns +true+ if this lock is currently held by some thread.
 *
 */

static VALUE
rb_mutex_locked_p(VALUE self)
{
    Mutex *mutex;
    Data_Get_Struct(self, Mutex, mutex);
    return MUTEX_LOCKED_P(mutex) ? Qtrue : Qfalse;
}

/*
 * Document-method: try_lock
 * call-seq: try_lock
 *
 * Attempts to obtain the lock and returns immediately. Returns +true+ if the
 * lock was granted.
 *
 */

static VALUE
rb_mutex_try_lock(VALUE self)
{
    Mutex *mutex;

    Data_Get_Struct(self, Mutex, mutex);

    if (MUTEX_LOCKED_P(mutex))
        return Qfalse;

    mutex->owner = rb_thread_current();
    return Qtrue;
}

/*
 * Document-method: lock
 * call-seq: lock
 *
 * Attempts to grab the lock and waits if it isn't available.
 *
 */

static VALUE
lock_mutex(Mutex *mutex)
{
    VALUE current;
    current = rb_thread_current();

    rb_thread_critical = 1;

    if (!MUTEX_LOCKED_P(mutex)) {
	mutex->owner = current;
    }
    else {
	do {
	    wait_list(&mutex->waiting);
	    rb_thread_critical = 1;
	    if (!MUTEX_LOCKED_P(mutex)) {
		mutex->owner = current;
		break;
	    }
	} while (mutex->owner != current);
    }

    rb_thread_critical = 0;
    return Qnil;
}

static VALUE
rb_mutex_lock(VALUE self)
{
    Mutex *mutex;
    Data_Get_Struct(self, Mutex, mutex);
    lock_mutex(mutex);
    return self;
}

static VALUE
relock_mutex(Mutex *mutex)
{
    VALUE current = rb_thread_current();

    switch (rb_thread_status(current)) {
      case THREAD_RUNNABLE:
      case THREAD_STOPPED:
	lock_mutex(mutex);
	break;
      default:
	break;
    }
    return Qundef;
}

/*
 * Document-method: unlock
 *
 * Releases the lock. Returns +nil+ if ref wasn't locked.
 *
 */

static VALUE
unlock_mutex_inner(Mutex *mutex)
{
    VALUE waking;

    if (mutex->owner != rb_thread_current()) {
	rb_raise(rb_eThreadError, "not owner");
    }

    waking = wake_one(&mutex->waiting);
    mutex->owner = waking;

    return waking;
}

static VALUE
set_critical(VALUE value)
{
    rb_thread_critical = (int)value;
    return Qundef;
}

static VALUE
unlock_mutex(Mutex *mutex)
{
    VALUE waking = thread_exclusive(unlock_mutex_inner, (VALUE)mutex);

    if (!RTEST(waking)) {
        return Qfalse;
    }

    run_thread(waking);

    return Qtrue;
}

static VALUE
rb_mutex_unlock(VALUE self)
{
    Mutex *mutex;
    Data_Get_Struct(self, Mutex, mutex);

    if (RTEST(unlock_mutex(mutex))) {
        return self;
    } else {
        return Qnil;
    }
}

/*
 * Document-method: exclusive_unlock
 * call-seq: exclusive_unlock { ... }
 *
 * If the mutex is locked, unlocks the mutex, wakes one waiting thread, and
 * yields in a critical section.
 *
 */

static VALUE
rb_mutex_exclusive_unlock_inner(Mutex *mutex)
{
    VALUE waking;
    waking = unlock_mutex_inner(mutex);
    rb_yield(Qundef);
    return waking;
}

static VALUE
rb_mutex_exclusive_unlock(VALUE self)
{
    Mutex *mutex;
    VALUE waking;
    Data_Get_Struct(self, Mutex, mutex);

    waking = thread_exclusive(rb_mutex_exclusive_unlock_inner, (VALUE)mutex);

    if (!RTEST(waking)) {
        return Qnil;
    }

    run_thread(waking);

    return self;
}

/*
 * Document-method: synchronize
 * call-seq: synchronize { ... }
 *
 * Obtains a lock, runs the block, and releases the lock when the block
 * completes.  See the example under Mutex.
 *
 */

static VALUE
rb_mutex_synchronize(VALUE self)
{
    rb_mutex_lock(self);
    return rb_ensure(rb_yield, Qundef, rb_mutex_unlock, self);
}

/*
 * Document-class: ConditionVariable
 *
 * ConditionVariable objects augment class Mutex. Using condition variables,
 * it is possible to suspend while in the middle of a critical section until a
 * resource becomes available.
 *
 * Example:
 *
 *   require 'thread'
 *
 *   mutex = Mutex.new
 *   resource = ConditionVariable.new
 *
 *   a = Thread.new {
 *     mutex.synchronize {
 *       # Thread 'a' now needs the resource
 *       resource.wait(mutex)
 *       # 'a' can now have the resource
 *     }
 *   }
 *
 *   b = Thread.new {
 *     mutex.synchronize {
 *       # Thread 'b' has finished using the resource
 *       resource.signal
 *     }
 *   }
 *
 */

typedef struct _ConditionVariable {
    List waiting;
} ConditionVariable;

static void
mark_condvar(ConditionVariable *condvar)
{
    mark_list(&condvar->waiting);
}

static void
finalize_condvar(ConditionVariable *condvar)
{
    finalize_list(&condvar->waiting);
}

static void
free_condvar(ConditionVariable *condvar)
{
    kill_waiting_threads(&condvar->waiting);
    finalize_condvar(condvar);
    xfree(condvar);
}

static void
init_condvar(ConditionVariable *condvar)
{
    init_list(&condvar->waiting);
}

/*
 * Document-method: new
 * call-seq: ConditionVariable.new
 *
 * Creates a new ConditionVariable
 *
 */

static VALUE
rb_condvar_alloc(VALUE klass)
{
    ConditionVariable *condvar;

    condvar = ALLOC(ConditionVariable);
    init_condvar(condvar);

    return Data_Wrap_Struct(klass, mark_condvar, free_condvar, condvar);
}

/*
 * Document-method: wait
 * call-seq: wait
 *
 * Releases the lock held in +mutex+ and waits; reacquires the lock on wakeup.
 *
 */

static void
wait_condvar(ConditionVariable *condvar, Mutex *mutex)
{
    VALUE waking;

    rb_thread_critical = 1;
    if (rb_thread_current() != mutex->owner) {
        rb_thread_critical = 0;
        rb_raise(rb_eThreadError, "not owner of the synchronization mutex");
    }
    waking = unlock_mutex_inner(mutex);
    if (RTEST(waking)) {
	wake_thread(waking);
    }
    rb_ensure(wait_list, (VALUE)&condvar->waiting, relock_mutex, (VALUE)mutex);
}

static VALUE
legacy_exclusive_unlock(VALUE mutex)
{
    return rb_funcall(mutex, rb_intern("exclusive_unlock"), 0);
}

typedef struct {
    ConditionVariable *condvar;
    VALUE mutex;
} legacy_wait_args;

static VALUE
legacy_wait(VALUE unused, legacy_wait_args *args)
{
    wait_list(&args->condvar->waiting);
    rb_funcall(args->mutex, rb_intern("lock"), 0);
    return Qnil;
}

static VALUE
rb_condvar_wait(VALUE self, VALUE mutex_v)
{
    ConditionVariable *condvar;
    Data_Get_Struct(self, ConditionVariable, condvar);

    if (CLASS_OF(mutex_v) != rb_cMutex) {
        /* interoperate with legacy mutex */
        legacy_wait_args args;
        args.condvar = condvar;
        args.mutex = mutex_v;
        rb_iterate(legacy_exclusive_unlock, mutex_v, legacy_wait, (VALUE)&args);
    } else {
        Mutex *mutex;
        Data_Get_Struct(mutex_v, Mutex, mutex);
        wait_condvar(condvar, mutex);
    }

    return self;
}

/*
 * Document-method: broadcast
 * call-seq: broadcast
 *
 * Wakes up all threads waiting for this condition.
 *
 */

static VALUE
rb_condvar_broadcast(VALUE self)
{
    ConditionVariable *condvar;

    Data_Get_Struct(self, ConditionVariable, condvar);
  
    thread_exclusive(wake_all, (VALUE)&condvar->waiting);
    rb_thread_schedule();

    return self;
}

/*
 * Document-method: signal
 * call-seq: signal
 *
 * Wakes up the first thread in line waiting for this condition.
 *
 */

static void
signal_condvar(ConditionVariable *condvar)
{
    VALUE waking = thread_exclusive(wake_one, (VALUE)&condvar->waiting);

    if (RTEST(waking)) {
        run_thread(waking);
    }
}

static VALUE
rb_condvar_signal(VALUE self)
{
    ConditionVariable *condvar;
    Data_Get_Struct(self, ConditionVariable, condvar);
    signal_condvar(condvar);
    return self;
}

/*
 * Document-class: Queue
 *
 * This class provides a way to synchronize communication between threads.
 *
 * Example:
 *
 *   require 'thread'
 *
 *   queue = Queue.new
 *
 *   producer = Thread.new do
 *     5.times do |i|
 *       sleep rand(i) # simulate expense
 *       queue << i
 *       puts "#{i} produced"
 *     end
 *   end
 *
 *   consumer = Thread.new do
 *     5.times do |i|
 *       value = queue.pop
 *       sleep rand(i/2) # simulate expense
 *       puts "consumed #{value}"
 *     end
 *   end
 *
 *   consumer.join
 *
 */

typedef struct _Queue {
    Mutex mutex;
    ConditionVariable value_available;
    ConditionVariable space_available;
    List values;
    unsigned long capacity;
} Queue;

static void
mark_queue(Queue *queue)
{
    mark_mutex(&queue->mutex);
    mark_condvar(&queue->value_available);
    mark_condvar(&queue->space_available);
    mark_list(&queue->values);
}

static void
finalize_queue(Queue *queue)
{
    finalize_mutex(&queue->mutex);
    finalize_condvar(&queue->value_available);
    finalize_condvar(&queue->space_available);
    finalize_list(&queue->values);
}

static void
free_queue(Queue *queue)
{
    kill_waiting_threads(&queue->mutex.waiting);
    kill_waiting_threads(&queue->space_available.waiting);
    kill_waiting_threads(&queue->value_available.waiting);
    finalize_queue(queue);
    xfree(queue);
}

static void
init_queue(Queue *queue)
{
    init_mutex(&queue->mutex);
    init_condvar(&queue->value_available);
    init_condvar(&queue->space_available);
    init_list(&queue->values);
    queue->capacity = 0;
}

/*
 * Document-method: new
 * call-seq: new
 *
 * Creates a new queue.
 *
 */

static VALUE
rb_queue_alloc(VALUE klass)
{
    Queue *queue;
    queue = ALLOC(Queue);
    init_queue(queue);
    return Data_Wrap_Struct(klass, mark_queue, free_queue, queue);
}

static VALUE
rb_queue_marshal_load(VALUE self, VALUE data)
{
    Queue *queue;
    VALUE array;
    Data_Get_Struct(self, Queue, queue);

    array = rb_marshal_load(data);
    if (TYPE(array) != T_ARRAY) {
	rb_raise(rb_eTypeError, "expected Array of queue data");
    }
    if (RARRAY(array)->len < 1) {
	rb_raise(rb_eArgError, "missing capacity value");
    }
    queue->capacity = NUM2ULONG(rb_ary_shift(array));
    push_multiple_list(&queue->values, RARRAY(array)->ptr, (unsigned)RARRAY(array)->len);

    return self;
}

static VALUE
rb_queue_marshal_dump(VALUE self)
{
    Queue *queue;
    VALUE array;
    Data_Get_Struct(self, Queue, queue);

    array = array_from_list(&queue->values);
    rb_ary_unshift(array, ULONG2NUM(queue->capacity));
    return rb_marshal_dump(array, Qnil);
}

/*
 * Document-method: clear
 * call-seq: clear
 *
 * Removes all objects from the queue.
 *
 */

static VALUE
rb_queue_clear(VALUE self)
{
    Queue *queue;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    clear_list(&queue->values);
    signal_condvar(&queue->space_available);
    unlock_mutex(&queue->mutex);

    return self;
}

/*
 * Document-method: empty?
 * call-seq: empty?
 *
 * Returns +true+ if the queue is empty.
 *
 */

static VALUE
rb_queue_empty_p(VALUE self)
{
    Queue *queue;
    VALUE result;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    result = queue->values.size == 0 ? Qtrue : Qfalse;
    unlock_mutex(&queue->mutex);

    return result;
}

/*
 * Document-method: length
 * call-seq: length
 *
 * Returns the length of the queue.
 *
 */

static VALUE
rb_queue_length(VALUE self)
{
    Queue *queue;
    VALUE result;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    result = ULONG2NUM(queue->values.size);
    unlock_mutex(&queue->mutex);

    return result;
}

/*
 * Document-method: num_waiting
 * call-seq: num_waiting
 *
 * Returns the number of threads waiting on the queue.
 *
 */

static VALUE
rb_queue_num_waiting(VALUE self)
{
    Queue *queue;
    VALUE result;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    result = ULONG2NUM(queue->value_available.waiting.size +
      queue->space_available.waiting.size);
    unlock_mutex(&queue->mutex);

    return result;
}

/*
 * Document-method: pop
 * call_seq: pop(non_block=false)
 *
 * Retrieves data from the queue.  If the queue is empty, the calling thread is
 * suspended until data is pushed onto the queue.  If +non_block+ is true, the
 * thread isn't suspended, and an exception is raised.
 *
 */

static VALUE
rb_queue_pop(int argc, VALUE *argv, VALUE self)
{
    Queue *queue;
    int should_block;
    VALUE result;
    Data_Get_Struct(self, Queue, queue);

    if (argc == 0) {
        should_block = 1;
    } else if (argc == 1) {
        should_block = !RTEST(argv[0]);
    } else {
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
    }

    lock_mutex(&queue->mutex);
    if (!queue->values.entries && !should_block) {
        unlock_mutex(&queue->mutex);
        rb_raise(rb_eThreadError, "queue empty");
    }

    while (!queue->values.entries) {
        wait_condvar(&queue->value_available, &queue->mutex);
    }

    result = shift_list(&queue->values);
    if (queue->capacity && queue->values.size < queue->capacity) {
        signal_condvar(&queue->space_available);
    }
    unlock_mutex(&queue->mutex);

    return result;
}

/*
 * Document-method: push
 * call-seq: push(obj)
 *
 * Pushes +obj+ to the queue.
 *
 */

static VALUE
rb_queue_push(VALUE self, VALUE value)
{
    Queue *queue;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    while (queue->capacity && queue->values.size >= queue->capacity) {
        wait_condvar(&queue->space_available, &queue->mutex);
    }
    push_list(&queue->values, value);
    signal_condvar(&queue->value_available);
    unlock_mutex(&queue->mutex);

    return self;
}

/*
 * Document-class: SizedQueue
 *
 * This class represents queues of specified size capacity.  The push operation
 * may be blocked if the capacity is full.
 *
 * See Queue for an example of how a SizedQueue works.
 *
 */

/*
 * Document-method: new
 * call-seq: new
 *
 * Creates a fixed-length queue with a maximum size of +max+.
 *
 */

/*
 * Document-method: max
 * call-seq: max
 *
 * Returns the maximum size of the queue.
 *
 */

static VALUE
rb_sized_queue_max(VALUE self)
{
    Queue *queue;
    VALUE result;
    Data_Get_Struct(self, Queue, queue);

    lock_mutex(&queue->mutex);
    result = ULONG2NUM(queue->capacity);
    unlock_mutex(&queue->mutex);

    return result;
}

/*
 * Document-method: max=
 * call-seq: max=(size)
 *
 * Sets the maximum size of the queue.
 *
 */

static VALUE
rb_sized_queue_max_set(VALUE self, VALUE value)
{
    Queue *queue;
    unsigned long new_capacity;
    unsigned long difference;
    Data_Get_Struct(self, Queue, queue);

    new_capacity = NUM2ULONG(value);

    if (new_capacity < 1) {
        rb_raise(rb_eArgError, "value must be positive");
    }

    lock_mutex(&queue->mutex);
    if (queue->capacity && new_capacity > queue->capacity) {
        difference = new_capacity - queue->capacity;
    } else {
        difference = 0;
    }
    queue->capacity = new_capacity;
    for (; difference > 0; --difference) {
        signal_condvar(&queue->space_available);
    }
    unlock_mutex(&queue->mutex);

    return self;
}

/*
 * Document-method: push
 * call-seq: push(obj)
 *
 * Pushes +obj+ to the queue.  If there is no space left in the queue, waits
 * until space becomes available.
 *
 */

/*
 * Document-method: pop
 * call-seq: pop(non_block=false)
 *
 * Retrieves data from the queue and runs a waiting thread, if any.
 *
 */

/* for marshalling mutexes and condvars */

static VALUE
dummy_load(VALUE self, VALUE string)
{
    return Qnil;
}

static VALUE
dummy_dump(VALUE self)
{
    return rb_str_new2("");
}

void
Init_thread(void)
{
    rb_define_singleton_method(rb_cThread, "exclusive", rb_thread_exclusive, 0);

    rb_cMutex = rb_define_class("Mutex", rb_cObject);
    rb_define_alloc_func(rb_cMutex, rb_mutex_alloc);
    rb_define_method(rb_cMutex, "marshal_load", dummy_load, 1);
    rb_define_method(rb_cMutex, "marshal_dump", dummy_dump, 0);
    rb_define_method(rb_cMutex, "locked?", rb_mutex_locked_p, 0);
    rb_define_method(rb_cMutex, "try_lock", rb_mutex_try_lock, 0);
    rb_define_method(rb_cMutex, "lock", rb_mutex_lock, 0);
    rb_define_method(rb_cMutex, "unlock", rb_mutex_unlock, 0);
    rb_define_method(rb_cMutex, "exclusive_unlock", rb_mutex_exclusive_unlock, 0);
    rb_define_method(rb_cMutex, "synchronize", rb_mutex_synchronize, 0);

    rb_cConditionVariable = rb_define_class("ConditionVariable", rb_cObject);
    rb_define_alloc_func(rb_cConditionVariable, rb_condvar_alloc);
    rb_define_method(rb_cConditionVariable, "marshal_load", dummy_load, 1);
    rb_define_method(rb_cConditionVariable, "marshal_dump", dummy_dump, 0);
    rb_define_method(rb_cConditionVariable, "wait", rb_condvar_wait, 1);
    rb_define_method(rb_cConditionVariable, "broadcast", rb_condvar_broadcast, 0);
    rb_define_method(rb_cConditionVariable, "signal", rb_condvar_signal, 0);

    rb_cQueue = rb_define_class("Queue", rb_cObject);
    rb_define_alloc_func(rb_cQueue, rb_queue_alloc);
    rb_define_method(rb_cQueue, "marshal_load", rb_queue_marshal_load, 1);
    rb_define_method(rb_cQueue, "marshal_dump", rb_queue_marshal_dump, 0);
    rb_define_method(rb_cQueue, "clear", rb_queue_clear, 0);
    rb_define_method(rb_cQueue, "empty?", rb_queue_empty_p, 0);
    rb_define_method(rb_cQueue, "length", rb_queue_length, 0);
    rb_define_method(rb_cQueue, "num_waiting", rb_queue_num_waiting, 0);
    rb_define_method(rb_cQueue, "pop", rb_queue_pop, -1);
    rb_define_method(rb_cQueue, "push", rb_queue_push, 1);
    rb_alias(rb_cQueue, rb_intern("enq"), rb_intern("push"));
    rb_alias(rb_cQueue, rb_intern("<<"), rb_intern("push"));
    rb_alias(rb_cQueue, rb_intern("deq"), rb_intern("pop"));
    rb_alias(rb_cQueue, rb_intern("shift"), rb_intern("pop"));
    rb_alias(rb_cQueue, rb_intern("size"), rb_intern("length"));

    rb_cSizedQueue = rb_define_class("SizedQueue", rb_cQueue);
    rb_define_method(rb_cSizedQueue, "initialize", rb_sized_queue_max_set, 1);
    rb_define_method(rb_cSizedQueue, "num_waiting", rb_queue_num_waiting, 0);
    rb_define_method(rb_cSizedQueue, "pop", rb_queue_pop, -1);
    rb_define_method(rb_cSizedQueue, "push", rb_queue_push, 1);
    rb_define_method(rb_cSizedQueue, "max", rb_sized_queue_max, 0);
    rb_define_method(rb_cSizedQueue, "max=", rb_sized_queue_max_set, 1);
    rb_alias(rb_cSizedQueue, rb_intern("enq"), rb_intern("push"));
    rb_alias(rb_cSizedQueue, rb_intern("<<"), rb_intern("push"));
    rb_alias(rb_cSizedQueue, rb_intern("deq"), rb_intern("pop"));
    rb_alias(rb_cSizedQueue, rb_intern("shift"), rb_intern("pop"));
}

