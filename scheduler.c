/**********************************************************************

  scheduler.c

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#include "vm_core.h"
#include "ruby/fiber/scheduler.h"
#include "ruby/io.h"
#include "ruby/io/buffer.h"

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
static ID id_io_close;

static ID id_address_resolve;

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
    id_io_close = rb_intern_const("io_close");

    id_address_resolve = rb_intern_const("address_resolve");
}

VALUE
rb_fiber_scheduler_get(void)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    rb_thread_t *thread = GET_THREAD();
    VM_ASSERT(thread);

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

VALUE
rb_fiber_scheduler_set(VALUE scheduler)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    rb_thread_t *thread = GET_THREAD();
    VM_ASSERT(thread);

    if (scheduler != Qnil) {
        verify_interface(scheduler);
    }

    // We invoke Scheduler#close when setting it to something else, to ensure the previous scheduler runs to completion before changing the scheduler. That way, we do not need to consider interactions, e.g., of a Fiber from the previous scheduler with the new scheduler.
    if (thread->scheduler != Qnil) {
        rb_fiber_scheduler_close(thread->scheduler);
    }

    thread->scheduler = scheduler;

    return thread->scheduler;
}

static VALUE
rb_fiber_scheduler_current_for_threadptr(rb_thread_t *thread)
{
    VM_ASSERT(thread);

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

VALUE
rb_fiber_scheduler_close(VALUE scheduler)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    VALUE result;

    result = rb_check_funcall(scheduler, id_scheduler_close, 0, NULL);
    if (result != Qundef) return result;

    result = rb_check_funcall(scheduler, id_close, 0, NULL);
    if (result != Qundef) return result;

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

VALUE
rb_fiber_scheduler_process_wait(VALUE scheduler, rb_pid_t pid, int flags)
{
    VALUE arguments[] = {
        PIDT2NUM(pid), RB_INT2NUM(flags)
    };

    return rb_check_funcall(scheduler, id_process_wait, 2, arguments);
}

VALUE
rb_fiber_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout)
{
    return rb_funcall(scheduler, id_block, 2, blocker, timeout);
}

VALUE
rb_fiber_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber)
{
    VM_ASSERT(rb_obj_is_fiber(fiber));

    return rb_funcall(scheduler, id_unblock, 2, blocker, fiber);
}

VALUE
rb_fiber_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout)
{
    return rb_funcall(scheduler, id_io_wait, 3, io, events, timeout);
}

VALUE
rb_fiber_scheduler_io_wait_readable(VALUE scheduler, VALUE io)
{
    return rb_fiber_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_READABLE), Qnil);
}

VALUE
rb_fiber_scheduler_io_wait_writable(VALUE scheduler, VALUE io)
{
    return rb_fiber_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_WRITABLE), Qnil);
}

VALUE
rb_fiber_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t length)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length)
    };

    return rb_check_funcall(scheduler, id_io_read, 3, arguments);
}

VALUE
rb_fiber_scheduler_io_pread(VALUE scheduler, VALUE io, VALUE buffer, size_t length, off_t offset)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length), OFFT2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_pread, 4, arguments);
}

VALUE
rb_fiber_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t length)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length)
    };

    return rb_check_funcall(scheduler, id_io_write, 3, arguments);
}

VALUE
rb_fiber_scheduler_io_pwrite(VALUE scheduler, VALUE io, VALUE buffer, size_t length, off_t offset)
{
    VALUE arguments[] = {
        io, buffer, SIZET2NUM(length), OFFT2NUM(offset)
    };

    return rb_check_funcall(scheduler, id_io_pwrite, 4, arguments);
}

VALUE
rb_fiber_scheduler_io_read_memory(VALUE scheduler, VALUE io, void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new(base, size, RB_IO_BUFFER_LOCKED);

    VALUE result = rb_fiber_scheduler_io_read(scheduler, io, buffer, length);

    rb_io_buffer_unlock(buffer);
    rb_io_buffer_free(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_write_memory(VALUE scheduler, VALUE io, const void *base, size_t size, size_t length)
{
    VALUE buffer = rb_io_buffer_new((void*)base, size, RB_IO_BUFFER_LOCKED|RB_IO_BUFFER_READONLY);

    VALUE result = rb_fiber_scheduler_io_write(scheduler, io, buffer, length);

    rb_io_buffer_unlock(buffer);
    rb_io_buffer_free(buffer);

    return result;
}

VALUE
rb_fiber_scheduler_io_close(VALUE scheduler, VALUE io)
{
    VALUE arguments[] = {io};

    return rb_check_funcall(scheduler, id_io_close, 1, arguments);
}

VALUE
rb_fiber_scheduler_address_resolve(VALUE scheduler, VALUE hostname)
{
    VALUE arguments[] = {
        hostname
    };

    return rb_check_funcall(scheduler, id_address_resolve, 1, arguments);
}
