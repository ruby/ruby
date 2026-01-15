#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/io.h"
#include "ruby/fiber/scheduler.h"

/*
 * Test extension for reproducing the gRPC interrupt handling bug.
 *
 * This reproduces the exact issue from grpc/grpc commit 69f229e (June 2025):
 * https://github.com/grpc/grpc/commit/69f229edd1d79ab7a7dfda98e3aef6fd807adcad
 *
 * The bug occurs when:
 * 1. A fiber scheduler uses Thread.handle_interrupt(::SignalException => :never)
 *    (like Async::Scheduler does)
 * 2. Native code uses rb_thread_call_without_gvl in a retry loop that checks
 *    the interrupted flag and retries (like gRPC's completion queue)
 * 3. A signal (SIGINT/SIGTERM) is sent
 * 4. The unblock_func sets interrupted=1, but Thread.handle_interrupt defers the signal
 * 5. The loop sees interrupted=1 and retries without yielding to the scheduler
 * 6. The deferred interrupt never gets processed -> infinite hang
 *
 * The fix is in vm_check_ints_blocking() in thread.c, which should yield to
 * the fiber scheduler when interrupts are pending, allowing the scheduler to
 * detect Thread.pending_interrupt? and exit its run loop.
 */

struct blocking_state {
    int notify_descriptor;
    volatile int interrupted;
};

static void
unblock_callback(void *argument)
{
    struct blocking_state *blocking_state = (struct blocking_state *)argument;
    blocking_state->interrupted = 1;
}

static void *
blocking_operation(void *argument)
{
    struct blocking_state *blocking_state = (struct blocking_state *)argument;

    ssize_t ret = write(blocking_state->notify_descriptor, "x", 1);
    (void)ret; // ignore the result for now

    while (!blocking_state->interrupted) {
        struct timeval tv = {1, 0};  // 1 second timeout.
        int result = select(0, NULL, NULL, NULL, &tv);

        if (result == -1 && errno == EINTR) {
            blocking_state->interrupted = 1;
        }

        // Otherwise, timeout -> loop again.
    }

    return NULL;
}

static VALUE
scheduler_blocking_loop(VALUE self, VALUE notify)
{
    struct blocking_state blocking_state = {
        .notify_descriptor = rb_io_descriptor(notify),
        .interrupted = 0,
    };

    while (true) {
        blocking_state.interrupted = 0;

        rb_thread_call_without_gvl(
            blocking_operation, &blocking_state,
            unblock_callback, &blocking_state
        );

        // The bug: When interrupted, loop retries without yielding to scheduler.
        // With Thread.handle_interrupt(:never), this causes an infinite hang,
        // because the deferred interrupt never gets a chance to be processed.
    } while (blocking_state.interrupted);

    return Qnil;
}

void
Init_scheduler(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mScheduler = rb_define_module_under(mBug, "Scheduler");

    rb_define_module_function(mScheduler, "blocking_loop", scheduler_blocking_loop, 1);
}
