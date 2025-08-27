/**********************************************************************

  scheduler.c

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#include "vm_core.h"
#include "ruby/fiber/scheduler.h"
#include "ruby/io.h"
#include "ruby/io/buffer.h"

#include "ruby/thread.h"

// For `ruby_thread_has_gvl_p`:
#include "internal/thread.h"

// For atomic operations:
#include "ruby_atomic.h"

static ID id_close;
static ID id_scheduler_close;

static ID id_block;
static ID id_unblock;

static ID id_timeout_after;
static ID id_kernel_sleep;
static ID id_process_wait;

static ID id_io_read, id_io_pread;
static ID id_io_write, id_io_pwrite;
static ID id_io_wait;
static ID id_io_select;
static ID id_io_close;

static ID id_address_resolve;

static ID id_blocking_operation_wait;
static ID id_fiber_interrupt;

static ID id_fiber_schedule;

// Our custom blocking operation class
static VALUE rb_cFiberSchedulerBlockingOperation;

/*
 * Custom blocking operation structure for blocking operations
 * This replaces the use of Ruby procs to avoid use-after-free issues
 * and provides a cleaner C API for native work pools.
 */

typedef enum {
    RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED,    // Submitted but not started
    RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_EXECUTING, // Currently running
    RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_COMPLETED, // Finished (success/error)
    RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_CANCELLED  // Cancelled
} rb_fiber_blocking_operation_status_t;

struct rb_fiber_scheduler_blocking_operation {
    void *(*function)(void *);
    void *data;

    rb_unblock_function_t *unblock_function;
    void *data2;

    int flags;
    struct rb_fiber_scheduler_blocking_operation_state *state;

    // Execution status
    volatile rb_atomic_t status;
};

static void
blocking_operation_mark(void *ptr)
{
    // No Ruby objects to mark in our struct
}

static void
blocking_operation_free(void *ptr)
{
    rb_fiber_scheduler_blocking_operation_t *blocking_operation = (rb_fiber_scheduler_blocking_operation_t *)ptr;
    ruby_xfree(blocking_operation);
}

static size_t
blocking_operation_memsize(const void *ptr)
{
    return sizeof(rb_fiber_scheduler_blocking_operation_t);
}

static const rb_data_type_t blocking_operation_data_type = {
    "Fiber::Scheduler::BlockingOperation",
    {
        blocking_operation_mark,
        blocking_operation_free,
        blocking_operation_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

/*
 * Allocate a new blocking operation
 */
static VALUE
blocking_operation_alloc(VALUE klass)
{
    rb_fiber_scheduler_blocking_operation_t *blocking_operation;
    VALUE obj = TypedData_Make_Struct(klass, rb_fiber_scheduler_blocking_operation_t, &blocking_operation_data_type, blocking_operation);

    blocking_operation->function = NULL;
    blocking_operation->data = NULL;
    blocking_operation->unblock_function = NULL;
    blocking_operation->data2 = NULL;
    blocking_operation->flags = 0;
    blocking_operation->state = NULL;
    blocking_operation->status = RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED;

    return obj;
}

/*
 * Get the blocking operation struct from a Ruby object
 */
static rb_fiber_scheduler_blocking_operation_t *
get_blocking_operation(VALUE obj)
{
    rb_fiber_scheduler_blocking_operation_t *blocking_operation;
    TypedData_Get_Struct(obj, rb_fiber_scheduler_blocking_operation_t, &blocking_operation_data_type, blocking_operation);
    return blocking_operation;
}

/*
 * Document-method: Fiber::Scheduler::BlockingOperation#call
 *
 * Execute the blocking operation. This method releases the GVL and calls
 * the blocking function, then restores the errno value.
 *
 * Returns nil. The actual result is stored in the associated state object.
 */
static VALUE
blocking_operation_call(VALUE self)
{
    rb_fiber_scheduler_blocking_operation_t *blocking_operation = get_blocking_operation(self);

    if (blocking_operation->status != RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED) {
        rb_raise(rb_eRuntimeError, "Blocking operation has already been executed!");
    }

    if (blocking_operation->function == NULL) {
        rb_raise(rb_eRuntimeError, "Blocking operation has no function to execute!");
    }

    if (blocking_operation->state == NULL) {
        rb_raise(rb_eRuntimeError, "Blocking operation has no result object!");
    }

    // Mark as executing
    blocking_operation->status = RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_EXECUTING;

    // Execute the blocking operation without GVL
    blocking_operation->state->result = rb_nogvl(blocking_operation->function, blocking_operation->data,
                                         blocking_operation->unblock_function, blocking_operation->data2,
                                         blocking_operation->flags);
    blocking_operation->state->saved_errno = rb_errno();

    // Mark as completed
    blocking_operation->status = RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_COMPLETED;

    return Qnil;
}

/*
 * C API: Extract blocking operation struct from Ruby object (GVL required)
 *
 * This function safely extracts the opaque struct from a BlockingOperation VALUE
 * while holding the GVL. The returned pointer can be passed to worker threads
 * and used with rb_fiber_scheduler_blocking_operation_execute_opaque_nogvl.
 *
 * Returns the opaque struct pointer on success, NULL on error.
 * Must be called while holding the GVL.
 */
rb_fiber_scheduler_blocking_operation_t *
rb_fiber_scheduler_blocking_operation_extract(VALUE self)
{
    return get_blocking_operation(self);
}

/*
 * C API: Execute blocking operation from opaque struct (GVL not required)
 *
 * This function executes a blocking operation using the opaque struct pointer
 * obtained from rb_fiber_scheduler_blocking_operation_extract.
 * It can be called from native threads without holding the GVL.
 *
 * Returns 0 on success, -1 on error.
 */
int
rb_fiber_scheduler_blocking_operation_execute(rb_fiber_scheduler_blocking_operation_t *blocking_operation)
{
    if (blocking_operation == NULL) {
        return -1;
    }

    if (blocking_operation->function == NULL || blocking_operation->state == NULL) {
        return -1; // Invalid blocking operation
    }

    // Resolve sentinel values for unblock_function and data2:
    rb_thread_resolve_unblock_function(&blocking_operation->unblock_function, &blocking_operation->data2, GET_THREAD());

    // Atomically check if we can transition from QUEUED to EXECUTING
    rb_atomic_t expected = RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED;
    if (RUBY_ATOMIC_CAS(blocking_operation->status, expected, RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_EXECUTING) != expected) {
        // Already cancelled or in wrong state
        return -1;
    }

    // Now we're executing - call the function
    blocking_operation->state->result = blocking_operation->function(blocking_operation->data);
    blocking_operation->state->saved_errno = errno;

    // Atomically transition to completed (unless cancelled during execution)
    expected = RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_EXECUTING;
    if (RUBY_ATOMIC_CAS(blocking_operation->status, expected, RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_COMPLETED) == expected) {
        // Successfully completed
        return 0;
    } else {
        // Was cancelled during execution
        blocking_operation->state->saved_errno = EINTR;
        return -1;
    }
}

/*
 * C API: Create a new blocking operation
 *
 * This creates a blocking operation that can be executed by native work pools.
 * The blocking operation holds references to the function and data safely.
 */
VALUE
rb_fiber_scheduler_blocking_operation_new(void *(*function)(void *), void *data,
                                         rb_unblock_function_t *unblock_function, void *data2,
                                         int flags, struct rb_fiber_scheduler_blocking_operation_state *state)
{
    VALUE self = blocking_operation_alloc(rb_cFiberSchedulerBlockingOperation);
    rb_fiber_scheduler_blocking_operation_t *blocking_operation = get_blocking_operation(self);

    blocking_operation->function = function;
    blocking_operation->data = data;
    blocking_operation->unblock_function = unblock_function;
    blocking_operation->data2 = data2;
    blocking_operation->flags = flags;
    blocking_operation->state = state;

    return self;
}

/*
 *
 *  Document-class: Fiber::Scheduler
 *
 *  This is not an existing class, but documentation of the interface that Scheduler
 *  object should comply to in order to be used as argument to Fiber.scheduler and handle non-blocking
 *  fibers. See also the "Non-blocking fibers" section in Fiber class docs for explanations
 *  of some concepts.
 *
 *  Scheduler's behavior and usage are expected to be as follows:
 *
 *  * When the execution in the non-blocking Fiber reaches some blocking operation (like
 *    sleep, wait for a process, or a non-ready I/O), it calls some of the scheduler's
 *    hook methods, listed below.
 *  * Scheduler somehow registers what the current fiber is waiting on, and yields control
 *    to other fibers with Fiber.yield (so the fiber would be suspended while expecting its
 *    wait to end, and other fibers in the same thread can perform)
 *  * At the end of the current thread execution, the scheduler's method #scheduler_close is called
 *  * The scheduler runs into a wait loop, checking all the blocked fibers (which it has
 *    registered on hook calls) and resuming them when the awaited resource is ready
 *    (e.g. I/O ready or sleep time elapsed).
 *
 *  This way concurrent execution will be achieved transparently for every
 *  individual Fiber's code.
 *
 *  Scheduler implementations are provided by gems, like
 *  Async[https://github.com/socketry/async].
 *
 *  Hook methods are:
 *
 *  * #io_wait, #io_read, #io_write, #io_pread, #io_pwrite, and #io_select, #io_close
 *  * #process_wait
 *  * #kernel_sleep
 *  * #timeout_after
 *  * #address_resolve
 *  * #block and #unblock
 *  * #blocking_operation_wait
 *  * (the list is expanded as Ruby developers make more methods having non-blocking calls)
 *
 *  When not specified otherwise, the hook implementations are mandatory: if they are not
 *  implemented, the methods trying to call hook will fail. To provide backward compatibility,
 *  in the future hooks will be optional (if they are not implemented, due to the scheduler
 *  being created for the older Ruby version, the code which needs this hook will not fail,
 *  and will just behave in a blocking fashion).
 *
 *  It is also strongly recommended that the scheduler implements the #fiber method, which is
 *  delegated to by Fiber.schedule.
 *
 *  Sample _toy_ implementation of the scheduler can be found in Ruby's code, in
 *  <tt>test/fiber/scheduler.rb</tt>
 *
 */
void
Init_Fiber_Scheduler(void)
{
    id_close = rb_intern_const("close");
    id_scheduler_close = rb_intern_const("scheduler_close");

    id_block = rb_intern_const("block");
    id_unblock = rb_intern_const("unblock");

    id_timeout_after = rb_intern_const("timeout_after");
    id_kernel_sleep = rb_intern_const("kernel_sleep");
    id_process_wait = rb_intern_const("process_wait");

    id_io_read = rb_intern_const("io_read");
    id_io_pread = rb_intern_const("io_pread");
    id_io_write = rb_intern_const("io_write");
    id_io_pwrite = rb_intern_const("io_pwrite");

    id_io_wait = rb_intern_const("io_wait");
    id_io_select = rb_intern_const("io_select");
    id_io_close = rb_intern_const("io_close");

    id_address_resolve = rb_intern_const("address_resolve");

    id_blocking_operation_wait = rb_intern_const("blocking_operation_wait");
    id_fiber_interrupt = rb_intern_const("fiber_interrupt");

    id_fiber_schedule = rb_intern_const("fiber");

    // Define an anonymous BlockingOperation class for internal use only
    // This is completely hidden from Ruby code and cannot be instantiated directly
    rb_cFiberSchedulerBlockingOperation = rb_class_new(rb_cObject);
    rb_define_alloc_func(rb_cFiberSchedulerBlockingOperation, blocking_operation_alloc);
    rb_define_method(rb_cFiberSchedulerBlockingOperation, "call", blocking_operation_call, 0);

    // Register the anonymous class as a GC root so it doesn't get collected
    rb_gc_register_mark_object(rb_cFiberSchedulerBlockingOperation);

#if 0 /* for RDoc */
    rb_cFiberScheduler = rb_define_class_under(rb_cFiber, "Scheduler", rb_cObject);
    rb_define_method(rb_cFiberScheduler, "close", rb_fiber_scheduler_close, 0);
    rb_define_method(rb_cFiberScheduler, "process_wait", rb_fiber_scheduler_process_wait, 2);
    rb_define_method(rb_cFiberScheduler, "io_wait", rb_fiber_scheduler_io_wait, 3);
    rb_define_method(rb_cFiberScheduler, "io_read", rb_fiber_scheduler_io_read, 4);
    rb_define_method(rb_cFiberScheduler, "io_write", rb_fiber_scheduler_io_write, 4);
    rb_define_method(rb_cFiberScheduler, "io_pread", rb_fiber_scheduler_io_pread, 5);
    rb_define_method(rb_cFiberScheduler, "io_pwrite", rb_fiber_scheduler_io_pwrite, 5);
    rb_define_method(rb_cFiberScheduler, "io_select", rb_fiber_scheduler_io_select, 4);
    rb_define_method(rb_cFiberScheduler, "kernel_sleep", rb_fiber_scheduler_kernel_sleep, 1);
    rb_define_method(rb_cFiberScheduler, "address_resolve", rb_fiber_scheduler_address_resolve, 1);
    rb_define_method(rb_cFiberScheduler, "timeout_after", rb_fiber_scheduler_timeout_after, 3);
    rb_define_method(rb_cFiberScheduler, "block", rb_fiber_scheduler_block, 2);
    rb_define_method(rb_cFiberScheduler, "unblock", rb_fiber_scheduler_unblock, 2);
    rb_define_method(rb_cFiberScheduler, "fiber", rb_fiber_scheduler_fiber, -2);
    rb_define_method(rb_cFiberScheduler, "blocking_operation_wait", rb_fiber_scheduler_blocking_operation_wait, -2);
#endif
}

VALUE
rb_fiber_scheduler_get(void)
{
    RUBY_ASSERT(ruby_thread_has_gvl_p());

    rb_thread_t *thread = GET_THREAD();
    RUBY_ASSERT(thread);

    return thread->scheduler;
}

static void
verify_interface(VALUE scheduler)
{
    if (!rb_respond_to(scheduler, id_block)) {
        rb_raise(rb_eArgError, "Scheduler must implement #block");
    }

    if (!rb_respond_to(scheduler, id_unblock)) {
        rb_raise(rb_eArgError, "Scheduler must implement #unblock");
    }

    if (!rb_respond_to(scheduler, id_kernel_sleep)) {
        rb_raise(rb_eArgError, "Scheduler must implement #kernel_sleep");
    }

    if (!rb_respond_to(scheduler, id_io_wait)) {
        rb_raise(rb_eArgError, "Scheduler must implement #io_wait");
    }

    if (!rb_respond_to(scheduler, id_fiber_interrupt)) {
        rb_warn("Scheduler should implement #fiber_interrupt");
    }
}

static VALUE
fiber_scheduler_close(VALUE scheduler)
{
    return rb_fiber_scheduler_close(scheduler);
}

static VALUE
fiber_scheduler_close_ensure(VALUE _thread)
{
    rb_thread_t *thread = (rb_thread_t*)_thread;
    thread->scheduler = Qnil;

    return Qnil;
}

VALUE
rb_fiber_scheduler_set(VALUE scheduler)
{
    RUBY_ASSERT(ruby_thread_has_gvl_p());

    rb_thread_t *thread = GET_THREAD();
    RUBY_ASSERT(thread);

    if (scheduler != Qnil) {
        verify_interface(scheduler);
    }

    // We invoke Scheduler#close when setting it to something else, to ensure
    // the previous scheduler runs to completion before changing the scheduler.
    // That way, we do not need to consider interactions, e.g., of a Fiber from
    // the previous scheduler with the new scheduler.
    if (thread->scheduler != Qnil) {
        // rb_fiber_scheduler_close(thread->scheduler);
        rb_ensure(fiber_scheduler_close, thread->scheduler, fiber_scheduler_close_ensure, (VALUE)thread);
    }

    thread->scheduler = scheduler;

    return thread->scheduler;
}

static VALUE
rb_fiber_scheduler_current_for_threadptr(rb_thread_t *thread)
{
    RUBY_ASSERT(thread);

    if (thread->blocking == 0) {
        return thread->scheduler;
    }
    else {
        return Qnil;
    }
}

VALUE
rb_fiber_scheduler_current(void)
{
    return rb_fiber_scheduler_current_for_threadptr(GET_THREAD());
}

VALUE rb_fiber_scheduler_current_for_thread(VALUE thread)
{
    return rb_fiber_scheduler_current_for_threadptr(rb_thread_ptr(thread));
}

/*
 *
 *  Document-method: Fiber::Scheduler#close
 *
 *  Called when the current thread exits. The scheduler is expected to implement this
 *  method in order to allow all waiting fibers to finalize their execution.
 *
 *  The suggested pattern is to implement the main event loop in the #close method.
 *
 */
VALUE
rb_fiber_scheduler_close(VALUE scheduler)
{
    RUBY_ASSERT(ruby_thread_has_gvl_p());

    VALUE result;

    // The reason for calling `scheduler_close` before calling `close` is for
    // legacy schedulers which implement `close` and expect the user to call
    // it. Subsequently, that method would call `Fiber.set_scheduler(nil)`
    // which should call `scheduler_close`. If it were to call `close`, it
    // would create an infinite loop.

    result = rb_check_funcall(scheduler, id_scheduler_close, 0, NULL);
    if (!UNDEF_P(result)) return result;

    result = rb_check_funcall(scheduler, id_close, 0, NULL);
    if (!UNDEF_P(result)) return result;

    return Qnil;
}

VALUE
rb_fiber_scheduler_make_timeout(struct timeval *timeout)
{
    if (timeout) {
        return rb_float_new((double)timeout->tv_sec + (0.000001 * timeout->tv_usec));
    }

    return Qnil;
}

/*
 *  Document-method: Fiber::Scheduler#kernel_sleep
 *  call-seq: kernel_sleep(duration = nil)
 *
 *  Invoked by Kernel#sleep and Mutex#sleep and is expected to provide
 *  an implementation of sleeping in a non-blocking way. Implementation might
 *  register the current fiber in some list of "which fiber wait until what
 *  moment", call Fiber.yield to pass control, and then in #close resume
 *  the fibers whose wait period has elapsed.
 *
 */
VALUE
rb_fiber_scheduler_kernel_sleep(VALUE scheduler, VALUE timeout)
{
    return rb_funcall(scheduler, id_kernel_sleep, 1, timeout);
}

VALUE
rb_fiber_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv)
{
    return rb_funcallv(scheduler, id_kernel_sleep, argc, argv);
}

#if 0
/*
 *  Document-method: Fiber::Scheduler#timeout_after
 *  call-seq: timeout_after(duration, exception_class, *exception_arguments, &block) -> result of block
 *
 *  Invoked by Timeout.timeout to execute the given +block+ within the given
 *  +duration+. It can also be invoked directly by the scheduler or user code.
 *
 *  Attempt to limit the execution time of a given +block+ to the given
 *  +duration+ if possible. When a non-blocking operation causes the +block+'s
 *  execution time to exceed the specified +duration+, that non-blocking
 *  operation should be interrupted by raising the specified +exception_class+
 *  constructed with the given +exception_arguments+.
 *
 *  General execution timeouts are often considered risky. This implementation
 *  will only interrupt non-blocking operations. This is by design because it's
 *  expected that non-blocking operations can fail for a variety of
 *  unpredictable reasons, so applications should already be robust in handling
 *  these conditions and by implication timeouts.
 *
 *  However, as a result of this design, if the +block+ does not invoke any
 *  non-blocking operations, it will be impossible to interrupt it. If you
 *  desire to provide predictable points for timeouts, consider adding
 *  +sleep(0)+.
 *
 *  If the block is executed successfully, its result will be returned.
 *
 *  The exception will typically be raised using Fiber#raise.
 */
VALUE
rb_fiber_scheduler_timeout_after(VALUE scheduler, VALUE timeout, VALUE exception, VALUE message)
{
    VALUE arguments[] = {
        timeout, exception, message
    };

    return rb_check_funcall(scheduler, id_timeout_after, 3, arguments);
}

VALUE
rb_fiber_scheduler_timeout_afterv(VALUE scheduler, int argc, VALUE * argv)
{
    return rb_check_funcall(scheduler, id_timeout_after, argc, argv);
}
#endif

/*
 *  Document-method: Fiber::Scheduler#process_wait
 *  call-seq: process_wait(pid, flags)
 *
 *  Invoked by Process::Status.wait in order to wait for a specified process.
 *  See that method description for arguments description.
 *
 *  Suggested minimal implementation:
 *
 *      Thread.new do
 *        Process::Status.wait(pid, flags)
 *      end.value
 *
 *  This hook is optional: if it is not present in the current scheduler,
 *  Process::Status.wait will behave as a blocking method.
 *
 *  Expected to return a Process::Status instance.
 */
VALUE
rb_fiber_scheduler_process_wait(VALUE scheduler, rb_pid_t pid, int flags)
{
    VALUE arguments[] = {
        PIDT2NUM(pid), RB_INT2NUM(flags)
    };

    return rb_check_funcall(scheduler, id_process_wait, 2, arguments);
}

/*
 *  Document-method: Fiber::Scheduler#block
 *  call-seq: block(blocker, timeout = nil)
 *
 *  Invoked by methods like Thread.join, and by Mutex, to signify that current
 *  Fiber is blocked until further notice (e.g. #unblock) or until +timeout+ has
 *  elapsed.
 *
 *  +blocker+ is what we are waiting on, informational only (for debugging and
 *  logging). There are no guarantee about its value.
 *
 *  Expected to return boolean, specifying whether the blocking operation was
 *  successful or not.
 */
VALUE
rb_fiber_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout)
{
    return rb_funcall(scheduler, id_block, 2, blocker, timeout);
}

/*
 *  Document-method: Fiber::Scheduler#unblock
 *  call-seq: unblock(blocker, fiber)
 *
 *  Invoked to wake up Fiber previously blocked with #block (for example, Mutex#lock
 *  calls #block and Mutex#unlock calls #unblock). The scheduler should use
 *  the +fiber+ parameter to understand which fiber is unblocked.
 *
 *  +blocker+ is what was awaited for, but it is informational only (for debugging
 *  and logging), and it is not guaranteed to be the same value as the +blocker+ for
 *  #block.
 *
 */
VALUE
rb_fiber_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber)
{
    RUBY_ASSERT(rb_obj_is_fiber(fiber));

    // `rb_fiber_scheduler_unblock` can be called from points where `errno` is expected to be preserved. Therefore, we should save and restore it. For example `io_binwrite` calls `rb_fiber_scheduler_unblock` and if `errno` is reset to 0 by user code, it will break the error handling in `io_write`.
    // If we explicitly preserve `errno` in `io_binwrite` and other similar functions (e.g. by returning it), this code is no longer needed. I hope in the future we will be able to remove it.
    int saved_errno = errno;

#ifdef RUBY_DEBUG
    rb_execution_context_t *ec = GET_EC();
    if (RUBY_VM_INTERRUPTED(ec)) {
        rb_bug("rb_fiber_scheduler_unblock called with pending interrupt");
    }
#endif

    VALUE result = rb_funcall(scheduler, id_unblock, 2, blocker, fiber);

    errno = saved_errno;

    return result;
}

/*
 *  Document-method: Fiber::Scheduler#io_wait
 *  call-seq: io_wait(io, events, timeout)
 *
 *  Invoked by IO#wait, IO#wait_readable, IO#wait_writable to ask whether the
 *  specified descriptor is ready for specified events within
 *  the specified +timeout+.
 *
 *  +events+ is a bit mask of <tt>IO::READABLE</tt>, <tt>IO::WRITABLE</tt>, and
 *  <tt>IO::PRIORITY</tt>.
 *
 *  Suggested implementation should register which Fiber is waiting for which
 *  resources and immediately calling Fiber.yield to pass control to other
 *  fibers. Then, in the #close method, the scheduler might dispatch all the
 *  I/O resources to fibers waiting for it.
 *
 *  Expected to return the subset of events that are ready immediately.
 *
 */
static VALUE
fiber_scheduler_io_wait(VALUE _argument) {
    VALUE *arguments = (VALUE*)_argument;

    return rb_funcallv(arguments[0], id_io_wait, 3, arguments + 1);
}

VALUE
rb_fiber_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout)
{
    VALUE arguments[] = {
        scheduler, io, events, timeout
    };

    if (rb_respond_to(scheduler, id_fiber_interrupt)) {
        return rb_thread_io_blocking_operation(io, fiber_scheduler_io_wait, (VALUE)&arguments);
    } else {
        return fiber_scheduler_io_wait((VALUE)&arguments);
    }
}

VALUE
rb_fiber_scheduler_io_wait_readable(VALUE scheduler, VALUE io)
{
    return rb_fiber_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_READABLE), rb_io_timeout(io));
}

VALUE
rb_fiber_scheduler_io_wait_writable(VALUE scheduler, VALUE io)
{
    return rb_fiber_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_WRITABLE), rb_io_timeout(io));
}

/*
 *  Document-method: Fiber::Scheduler#io_select
 *  call-seq: io_select(readables, writables, exceptables, timeout)
 *
 *  Invoked by IO.select to ask whether the specified descriptors are ready for
 *  specified events within the specified +timeout+.
 *
 *  Expected to return the 3-tuple of Array of IOs that are ready.
 *
 */
VALUE rb_fiber_scheduler_io_select(VALUE scheduler, VALUE readables, VALUE writables, VALUE exceptables, VALUE timeout)
{
    VALUE arguments[] = {
        readables, writables, exceptables, timeout
    };

    return rb_fiber_scheduler_io_selectv(scheduler, 4, arguments);
}

VALUE rb_fiber_scheduler_io_selectv(VALUE scheduler, int argc, VALUE *argv)
{
    // I wondered about extracting argv, and checking if there is only a single
    // IO instance, and instead calling `io_wait`. However, it would require a
    // decent amount of work and it would be hard to preserve the exact
    // semantics of IO.select.

    return rb_check_funcall(scheduler, id_io_select, argc, argv);
}

/*
 *  Document-method: Fiber::Scheduler#io_read
 *  call-seq: io_read(io, buffer, length, offset) -> read length or -errno
 *
 *  Invoked by IO#read or IO#Buffer.read to read +length+ bytes from +io+ into a
 *  specified +buffer+ (see IO::Buffer) at the given +offset+.
 *
 *  The +length+ argument is the "minimum length to be read". If the IO buffer
 *  size is 8KiB, but the +length+ is +1024+ (1KiB), up to 8KiB might be read,
 *  but at least 1KiB will be. Generally, the only case where less data than
 *  +length+ will be read is if there is an error reading the data.
 *
 *  Specifying a +length+ of 0 is valid and means try reading at least once and
 *  return any available data.
 *
 *  Suggested implementation should try to read from +io+ in a non-blocking
 *  manner and call #io_wait if the +io+ is not ready (which will yield control
 *  to other fibers).
 *
 *  See IO::Buffer for an interface available to return data.
 *
 *  Expected to return number of bytes read, or, in case of an error,
 *  <tt>-errno</tt> (negated number corresponding to system's error code).
 *
 *  The method should be considered _experimental_.
 */
static VALUE
fiber_scheduler_io_read(VALUE _argument) {
    VALUE *arguments = (VALUE*)_argument;

    return rb_funcallv(arguments[0], id_io_read, 4, arguments + 1);
}

VALUE
rb_fiber_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset)
{
    if (!rb_respond_to(scheduler, id_io_read)) {
        return RUBY_Qundef;
    }

    VALUE arguments[] = {
        scheduler, io, buffer, SIZET2NUM(length), SIZET2NUM(offset)
    };

    if (rb_respond_to(scheduler, id_fiber_interrupt)) {
        return rb_thread_io_blocking_operation(io, fiber_scheduler_io_read, (VALUE)&arguments);
    } else {
        return fiber_scheduler_io_read((VALUE)&arguments);
    }
}

/*
 *  Document-method: Fiber::Scheduler#io_pread
 *  call-seq: io_pread(io, buffer, from, length, offset) -> read length or -errno
 *
 *  Invoked by IO#pread or IO::Buffer#pread to read +length+ bytes from +io+
 *  at offset +from+ into a specified +buffer+ (see IO::Buffer) at the given
 *  +offset+.
 *
 *  This method is semantically the same as #io_read, but it allows to specify
 *  the offset to read from and is often better for asynchronous IO on the same
 *  file.
 *
 *  The method should be considered _experimental_.
 */
static VALUE
fiber_scheduler_io_pread(VALUE _argument) {
    VALUE *arguments = (VALUE*)_argument;

    return rb_funcallv(arguments[0], id_io_pread, 5, arguments + 1);
}

VALUE
rb_fiber_scheduler_io_pread(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset)
{
    if (!rb_respond_to(scheduler, id_io_pread)) {
        return RUBY_Qundef;
    }

    VALUE arguments[] = {
        scheduler, io, buffer, OFFT2NUM(from), SIZET2NUM(length), SIZET2NUM(offset)
    };

    if (rb_respond_to(scheduler, id_fiber_interrupt)) {
        return rb_thread_io_blocking_operation(io, fiber_scheduler_io_pread, (VALUE)&arguments);
    } else {
        return fiber_scheduler_io_pread((VALUE)&arguments);
    }
}

/*
 *  Document-method: Fiber::Scheduler#io_write
 *  call-seq: io_write(io, buffer, length, offset) -> written length or -errno
 *
 *  Invoked by IO#write or IO::Buffer#write to write +length+ bytes to +io+ from
 *  from a specified +buffer+ (see IO::Buffer) at the given +offset+.
 *
 *  The +length+ argument is the "minimum length to be written". If the IO
 *  buffer size is 8KiB, but the +length+ specified is 1024 (1KiB), at most 8KiB
 *  will be written, but at least 1KiB will be. Generally, the only case where
 *  less data than +length+ will be written is if there is an error writing the
 *  data.
 *
 *  Specifying a +length+ of 0 is valid and means try writing at least once, as
 *  much data as possible.
 *
 *  Suggested implementation should try to write to +io+ in a non-blocking
 *  manner and call #io_wait if the +io+ is not ready (which will yield control
 *  to other fibers).
 *
 *  See IO::Buffer for an interface available to get data from buffer
 *  efficiently.
 *
 *  Expected to return number of bytes written, or, in case of an error,
 *  <tt>-errno</tt> (negated number corresponding to system's error code).
 *
 *  The method should be considered _experimental_.
 */
static VALUE
fiber_scheduler_io_write(VALUE _argument) {
    VALUE *arguments = (VALUE*)_argument;

    return rb_funcallv(arguments[0], id_io_write, 4, arguments + 1);
}

VALUE
rb_fiber_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset)
{
    if (!rb_respond_to(scheduler, id_io_write)) {
        return RUBY_Qundef;
    }

    VALUE arguments[] = {
        scheduler, io, buffer, SIZET2NUM(length), SIZET2NUM(offset)
    };

    if (rb_respond_to(scheduler, id_fiber_interrupt)) {
        return rb_thread_io_blocking_operation(io, fiber_scheduler_io_write, (VALUE)&arguments);
    } else {
        return fiber_scheduler_io_write((VALUE)&arguments);
    }
}

/*
 *  Document-method: Fiber::Scheduler#io_pwrite
 *  call-seq: io_pwrite(io, buffer, from, length, offset) -> written length or -errno
 *
 *  Invoked by IO#pwrite or IO::Buffer#pwrite to write +length+ bytes to +io+
 *  at offset +from+ into a specified +buffer+ (see IO::Buffer) at the given
 *  +offset+.
 *
 *  This method is semantically the same as #io_write, but it allows to specify
 *  the offset to write to and is often better for asynchronous IO on the same
 *  file.
 *
 *  The method should be considered _experimental_.
 *
 */
static VALUE
fiber_scheduler_io_pwrite(VALUE _argument) {
    VALUE *arguments = (VALUE*)_argument;

    return rb_funcallv(arguments[0], id_io_pwrite, 5, arguments + 1);
}

VALUE
rb_fiber_scheduler_io_pwrite(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset)
{
    if (!rb_respond_to(scheduler, id_io_pwrite)) {
        return RUBY_Qundef;
    }

    VALUE arguments[] = {
        scheduler, io, buffer, OFFT2NUM(from), SIZET2NUM(length), SIZET2NUM(offset)
    };

    if (rb_respond_to(scheduler, id_fiber_interrupt)) {
        return rb_thread_io_blocking_operation(io, fiber_scheduler_io_pwrite, (VALUE)&arguments);
    } else {
        return fiber_scheduler_io_pwrite((VALUE)&arguments);
    }
}

VALUE
rb_fiber_scheduler_io_read_memory(VALUE scheduler, VALUE io, void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new(base, size, RB_IO_BUFFER_LOCKED);

    VALUE result = rb_fiber_scheduler_io_read(scheduler, io, buffer, length, 0);

    rb_io_buffer_free_locked(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_write_memory(VALUE scheduler, VALUE io, const void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new((void*)base, size, RB_IO_BUFFER_LOCKED|RB_IO_BUFFER_READONLY);

    VALUE result = rb_fiber_scheduler_io_write(scheduler, io, buffer, length, 0);

    rb_io_buffer_free_locked(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_pread_memory(VALUE scheduler, VALUE io, rb_off_t from, void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new(base, size, RB_IO_BUFFER_LOCKED);

    VALUE result = rb_fiber_scheduler_io_pread(scheduler, io, from, buffer, length, 0);

    rb_io_buffer_free_locked(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_pwrite_memory(VALUE scheduler, VALUE io, rb_off_t from, const void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new((void*)base, size, RB_IO_BUFFER_LOCKED|RB_IO_BUFFER_READONLY);

    VALUE result = rb_fiber_scheduler_io_pwrite(scheduler, io, from, buffer, length, 0);

    rb_io_buffer_free_locked(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_close(VALUE scheduler, VALUE io)
{
    VALUE arguments[] = {io};

    return rb_check_funcall(scheduler, id_io_close, 1, arguments);
}

/*
 *  Document-method: Fiber::Scheduler#address_resolve
 *  call-seq: address_resolve(hostname) -> array_of_strings or nil
 *
 *  Invoked by any method that performs a non-reverse DNS lookup. The most
 *  notable method is Addrinfo.getaddrinfo, but there are many other.
 *
 *  The method is expected to return an array of strings corresponding to ip
 *  addresses the +hostname+ is resolved to, or +nil+ if it can not be resolved.
 *
 *  Fairly exhaustive list of all possible call-sites:
 *
 *  - Addrinfo.getaddrinfo
 *  - Addrinfo.tcp
 *  - Addrinfo.udp
 *  - Addrinfo.ip
 *  - Addrinfo.new
 *  - Addrinfo.marshal_load
 *  - SOCKSSocket.new
 *  - TCPServer.new
 *  - TCPSocket.new
 *  - IPSocket.getaddress
 *  - TCPSocket.gethostbyname
 *  - UDPSocket#connect
 *  - UDPSocket#bind
 *  - UDPSocket#send
 *  - Socket.getaddrinfo
 *  - Socket.gethostbyname
 *  - Socket.pack_sockaddr_in
 *  - Socket.sockaddr_in
 *  - Socket.unpack_sockaddr_in
 */
VALUE
rb_fiber_scheduler_address_resolve(VALUE scheduler, VALUE hostname)
{
    VALUE arguments[] = {
        hostname
    };

    return rb_check_funcall(scheduler, id_address_resolve, 1, arguments);
}

/*
 *  Document-method: Fiber::Scheduler#blocking_operation_wait
 *  call-seq: blocking_operation_wait(blocking_operation)
 *
 *  Invoked by Ruby's core methods to run a blocking operation in a non-blocking way.
 *  The blocking_operation is a Fiber::Scheduler::BlockingOperation that encapsulates the blocking operation.
 *
 *  If the scheduler doesn't implement this method, or if the scheduler doesn't execute
 *  the blocking operation, Ruby will fall back to the non-scheduler implementation.
 *
 *  Minimal suggested implementation is:
 *
 *     def blocking_operation_wait(blocking_operation)
 *       Thread.new { blocking_operation.call }.join
 *     end
 */
VALUE rb_fiber_scheduler_blocking_operation_wait(VALUE scheduler, void* (*function)(void *), void *data, rb_unblock_function_t *unblock_function, void *data2, int flags, struct rb_fiber_scheduler_blocking_operation_state *state)
{
    // Check if scheduler supports blocking_operation_wait before creating the object
    if (!rb_respond_to(scheduler, id_blocking_operation_wait)) {
        return Qundef;
    }

    // Create a new BlockingOperation with the blocking operation
    VALUE blocking_operation = rb_fiber_scheduler_blocking_operation_new(function, data, unblock_function, data2, flags, state);

    VALUE result = rb_funcall(scheduler, id_blocking_operation_wait, 1, blocking_operation);

    // Get the operation data to check if it was executed
    rb_fiber_scheduler_blocking_operation_t *operation = get_blocking_operation(blocking_operation);
    rb_atomic_t current_status = RUBY_ATOMIC_LOAD(operation->status);

    // Invalidate the operation now that we're done with it
    operation->function = NULL;
    operation->state = NULL;
    operation->data = NULL;
    operation->data2 = NULL;
    operation->unblock_function = NULL;

    // If the blocking operation was never executed, return Qundef to signal the caller to use rb_nogvl instead
    if (current_status == RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED) {
        return Qundef;
    }

    return result;
}

VALUE rb_fiber_scheduler_fiber_interrupt(VALUE scheduler, VALUE fiber, VALUE exception)
{
    VALUE arguments[] = {
        fiber, exception
    };

#ifdef RUBY_DEBUG
    rb_execution_context_t *ec = GET_EC();
    if (RUBY_VM_INTERRUPTED(ec)) {
        rb_bug("rb_fiber_scheduler_fiber_interrupt called with pending interrupt");
    }
#endif

    return rb_check_funcall(scheduler, id_fiber_interrupt, 2, arguments);
}

/*
 *  Document-method: Fiber::Scheduler#fiber
 *  call-seq: fiber(&block)
 *
 *  Implementation of the Fiber.schedule. The method is <em>expected</em> to immediately
 *  run the given block of code in a separate non-blocking fiber, and to return that Fiber.
 *
 *  Minimal suggested implementation is:
 *
 *     def fiber(&block)
 *       fiber = Fiber.new(blocking: false, &block)
 *       fiber.resume
 *       fiber
 *     end
 */
VALUE
rb_fiber_scheduler_fiber(VALUE scheduler, int argc, VALUE *argv, int kw_splat)
{
    return rb_funcall_passing_block_kw(scheduler, id_fiber_schedule, argc, argv, kw_splat);
}

/*
 * C API: Cancel a blocking operation
 *
 * This function cancels a blocking operation. If the operation is queued,
 * it just marks it as cancelled. If it's executing, it marks it as cancelled
 * and calls the unblock function to interrupt the operation.
 *
 * Returns 1 if unblock function was called, 0 if just marked cancelled, -1 on error.
 */
int
rb_fiber_scheduler_blocking_operation_cancel(rb_fiber_scheduler_blocking_operation_t *blocking_operation)
{
    if (blocking_operation == NULL) {
        return -1;
    }

    rb_atomic_t current_state = RUBY_ATOMIC_LOAD(blocking_operation->status);

    switch (current_state) {
        case RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_QUEUED:
            // Work hasn't started - just mark as cancelled:
            if (RUBY_ATOMIC_CAS(blocking_operation->status, current_state, RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_CANCELLED) == current_state) {
                // Successfully cancelled before execution:
                return 0;
            }
            // Fall through if state changed between load and CAS

        case RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_EXECUTING:
            // Work is running - mark cancelled AND call unblock function
            if (RUBY_ATOMIC_CAS(blocking_operation->status, current_state, RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_CANCELLED) != current_state) {
                // State changed between load and CAS - operation may have completed:
                return 0;
            }
            // Otherwise, we successfully marked it as cancelled, so we can call the unblock function:
            rb_unblock_function_t *unblock_function = blocking_operation->unblock_function;
            if (unblock_function) {
                RUBY_ASSERT(unblock_function != (rb_unblock_function_t *)-1 && "unblock_function is still sentinel value -1, should have been resolved earlier");
                blocking_operation->unblock_function(blocking_operation->data2);
            }
            // Cancelled during execution (unblock function called):
            return 1;

        case RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_COMPLETED:
        case RB_FIBER_SCHEDULER_BLOCKING_OPERATION_STATUS_CANCELLED:
            // Already finished or cancelled:
            return 0;
    }

    return 0;
}
