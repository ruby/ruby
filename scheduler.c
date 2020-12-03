/**********************************************************************

  scheduler.c

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#include "vm_core.h"
#include "internal/scheduler.h"
#include "ruby/io.h"

static ID id_close;

static ID id_block;
static ID id_unblock;

static ID id_kernel_sleep;

static ID id_io_read;
static ID id_io_write;
static ID id_io_wait;

void
Init_Scheduler(void)
{
    id_close = rb_intern_const("close");

    id_block = rb_intern_const("block");
    id_unblock = rb_intern_const("unblock");

    id_kernel_sleep = rb_intern_const("kernel_sleep");

    id_io_read = rb_intern_const("io_read");
    id_io_write = rb_intern_const("io_write");
    id_io_wait = rb_intern_const("io_wait");
}

VALUE
rb_scheduler_get()
{
    rb_thread_t *thread = GET_THREAD();
    VM_ASSERT(thread);

    return thread->scheduler;
}

VALUE
rb_scheduler_set(VALUE scheduler)
{
    rb_thread_t *thread = GET_THREAD();
    VM_ASSERT(thread);

    // We invoke Scheduler#close when setting it to something else, to ensure the previous scheduler runs to completion before changing the scheduler. That way, we do not need to consider interactions, e.g., of a Fiber from the previous scheduler with the new scheduler.
    if (thread->scheduler != Qnil) {
        rb_scheduler_close(thread->scheduler);
    }

    thread->scheduler = scheduler;

    return thread->scheduler;
}

static VALUE
rb_threadptr_scheduler_current(rb_thread_t *thread)
{
    VM_ASSERT(thread);

    if (thread->blocking == 0) {
        return thread->scheduler;
    } else {
        return Qnil;
    }
}

VALUE
rb_scheduler_current()
{
    return rb_threadptr_scheduler_current(GET_THREAD());
}

VALUE rb_thread_scheduler_current(VALUE thread)
{
    return rb_threadptr_scheduler_current(rb_thread_ptr(thread));
}

VALUE
rb_scheduler_close(VALUE scheduler)
{
    if (rb_respond_to(scheduler, id_close)) {
        return rb_funcall(scheduler, id_close, 0);
    }

    return Qnil;
}

VALUE
rb_scheduler_timeout(struct timeval *timeout)
{
    if (timeout) {
        return rb_float_new((double)timeout->tv_sec + (0.000001f * timeout->tv_usec));
    }

    return Qnil;
}

VALUE
rb_scheduler_kernel_sleep(VALUE scheduler, VALUE timeout)
{
    return rb_funcall(scheduler, id_kernel_sleep, 1, timeout);
}

VALUE
rb_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv)
{
    return rb_funcallv(scheduler, id_kernel_sleep, argc, argv);
}

VALUE
rb_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout)
{
    return rb_funcall(scheduler, id_block, 2, blocker, timeout);
}

VALUE
rb_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber)
{
    return rb_funcall(scheduler, id_unblock, 2, blocker, fiber);
}

VALUE
rb_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout)
{
    return rb_funcall(scheduler, id_io_wait, 3, io, events, timeout);
}

VALUE
rb_scheduler_io_wait_readable(VALUE scheduler, VALUE io)
{
    return rb_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_READABLE), Qnil);
}

VALUE
rb_scheduler_io_wait_writable(VALUE scheduler, VALUE io)
{
    return rb_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_WRITABLE), Qnil);
}

int
rb_scheduler_supports_io_read(VALUE scheduler)
{
    return rb_respond_to(scheduler, id_io_read);
}

VALUE
rb_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length)
{
    return rb_funcall(scheduler, id_io_read, 4, io, buffer, SIZET2NUM(offset), SIZET2NUM(length));
}

int
rb_scheduler_supports_io_write(VALUE scheduler)
{
    return rb_respond_to(scheduler, id_io_write);
}

VALUE
rb_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length)
{
    // We should ensure string has capacity to receive data, and then resize it afterwards.
    return rb_funcall(scheduler, id_io_write, 4, io, buffer, SIZET2NUM(offset), SIZET2NUM(length));
}
