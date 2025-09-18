/**********************************************************************

  scheduler.c

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#include "vm_core.h"
#include "eval_intern.h"
#include "ruby/fiber/scheduler.h"
#include "ruby/io.h"
#include "ruby/io/buffer.h"

#include "ruby/thread.h"

// For `ruby_thread_has_gvl_p`.
#include "internal/thread.h"

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

static ID id_fiber_schedule;

/*
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

    id_fiber_schedule = rb_intern_const("fiber");

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
    rb_define_method(rb_cFiberScheduler, "fiber", rb_fiber_scheduler, -2);
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
        return rb_float_new((double)timeout->tv_sec + (0.000001f * timeout->tv_usec));
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

    VALUE result;
    enum ruby_tag_type state;

    // `rb_fiber_scheduler_unblock` can be called from points where `errno` is expected to be preserved. Therefore, we should save and restore it. For example `io_binwrite` calls `rb_fiber_scheduler_unblock` and if `errno` is reset to 0 by user code, it will break the error handling in `io_write`.
    //
    // If we explicitly preserve `errno` in `io_binwrite` and other similar functions (e.g. by returning it), this code is no longer needed. I hope in the future we will be able to remove it.
    int saved_errno = errno;

    // We must prevent interrupts while invoking the unblock method, because otherwise fibers can be left permanently blocked if an interrupt occurs during the execution of user code.
    rb_execution_context_t *ec = GET_EC();
    int saved_interrupt_mask = ec->interrupt_mask;
    ec->interrupt_mask |= PENDING_INTERRUPT_MASK;

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        result = rb_funcall(scheduler, id_unblock, 2, blocker, fiber);
    }
    EC_POP_TAG();

    ec->interrupt_mask = saved_interrupt_mask;

    if (state) {
        EC_JUMP_TAG(ec, state);
    }

    RUBY_VM_CHECK_INTS(ec);

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
VALUE
rb_fiber_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout)
{
    return rb_funcall(scheduler, id_io_wait, 3, io, events, timeout);
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
VALUE
rb_fiber_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length), SIZET2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_read, 4, arguments);
}

/*
 *  Document-method: Fiber::Scheduler#io_read
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
VALUE
rb_fiber_scheduler_io_pread(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset)
{
    VALUE arguments[] = {
        io, buffer, OFFT2NUM(from), SIZET2NUM(length), SIZET2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_pread, 5, arguments);
}

/*
 *  Document-method: Scheduler#io_write
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
VALUE
rb_fiber_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length), SIZET2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_write, 4, arguments);
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
VALUE
rb_fiber_scheduler_io_pwrite(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset)
{
    VALUE arguments[] = {
        io, buffer, OFFT2NUM(from), SIZET2NUM(length), SIZET2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_pwrite, 5, arguments);
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

struct rb_blocking_operation_wait_arguments {
    void *(*function)(void *);
    void *data;
    rb_unblock_function_t *unblock_function;
    void *data2;
    int flags;

    struct rb_fiber_scheduler_blocking_operation_state *state;
};

static VALUE
rb_fiber_scheduler_blocking_operation_wait_proc(RB_BLOCK_CALL_FUNC_ARGLIST(value, _arguments))
{
    struct rb_blocking_operation_wait_arguments *arguments = (struct rb_blocking_operation_wait_arguments*)_arguments;

    if (arguments->state == NULL) {
        rb_raise(rb_eRuntimeError, "Blocking function was already invoked!");
    }

    arguments->state->result = rb_nogvl(arguments->function, arguments->data, arguments->unblock_function, arguments->data2, arguments->flags);
    arguments->state->saved_errno = rb_errno();

    // Make sure it's only invoked once.
    arguments->state = NULL;

    return Qnil;
}

/*
 *  Document-method: Fiber::Scheduler#blocking_operation_wait
 *  call-seq: blocking_operation_wait(work)
 *
 *  Invoked by Ruby's core methods to run a blocking operation in a non-blocking way.
 *
 *  Minimal suggested implementation is:
 *
 *     def blocking_operation_wait(work)
 *       Thread.new(&work).join
 *     end
 */
VALUE rb_fiber_scheduler_blocking_operation_wait(VALUE scheduler, void* (*function)(void *), void *data, rb_unblock_function_t *unblock_function, void *data2, int flags, struct rb_fiber_scheduler_blocking_operation_state *state)
{
    struct rb_blocking_operation_wait_arguments arguments = {
        .function = function,
        .data = data,
        .unblock_function = unblock_function,
        .data2 = data2,
        .flags = flags,
        .state = state
    };

    VALUE proc = rb_proc_new(rb_fiber_scheduler_blocking_operation_wait_proc, (VALUE)&arguments);

    return rb_check_funcall(scheduler, id_blocking_operation_wait, 1, &proc);
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
