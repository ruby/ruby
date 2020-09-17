/**********************************************************************

  scheduler.c

  $Author$

  Copyright (C) 2020 Samuel Grant Dawson Williams

**********************************************************************/

#include "internal/scheduler.h"
#include "ruby/io.h"

static ID id_kernel_sleep;
static ID id_block;
static ID id_unblock;
static ID id_io_read;
static ID id_io_write;
static ID id_io_wait;

void
Init_Scheduler(void)
{
    id_kernel_sleep = rb_intern_const("kernel_sleep");
    id_block = rb_intern_const("block");
    id_unblock = rb_intern_const("unblock");
    id_io_read = rb_intern_const("io_read");
    id_io_write = rb_intern_const("io_write");
    id_io_wait = rb_intern_const("io_wait");
}

VALUE
rb_scheduler_timeout(struct timeval *timeout) {
    if (timeout) {
        return rb_float_new((double)timeout->tv_sec + (0.000001f * timeout->tv_usec));
    }

    return Qnil;
}

VALUE rb_scheduler_kernel_sleep(VALUE scheduler, VALUE timeout)
{
    return rb_funcall(scheduler, id_kernel_sleep, 1, timeout);
}

VALUE rb_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv)
{
    return rb_funcallv(scheduler, id_kernel_sleep, argc, argv);
}

VALUE rb_scheduler_block(VALUE scheduler, VALUE blocker)
{
    return rb_funcall(scheduler, id_block, 1, blocker);
}

VALUE rb_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber)
{
    return rb_funcall(scheduler, id_unblock, 2, blocker, fiber);
}

VALUE rb_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout)
{
    return rb_funcall(scheduler, id_io_wait, 3, io, events, timeout);
}

VALUE rb_scheduler_io_wait_readable(VALUE scheduler, VALUE io)
{
    return rb_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_READABLE), Qnil);
}

VALUE rb_scheduler_io_wait_writable(VALUE scheduler, VALUE io)
{
    return rb_scheduler_io_wait(scheduler, io, RB_UINT2NUM(RUBY_IO_WRITABLE), Qnil);
}

int rb_scheduler_supports_io_read(VALUE scheduler)
{
    return rb_respond_to(scheduler, id_io_read);
}

VALUE rb_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length)
{
    return rb_funcall(scheduler, id_io_read, 4, io, buffer, SIZET2NUM(offset), SIZET2NUM(length));
}

int rb_scheduler_supports_io_write(VALUE scheduler)
{
    return rb_respond_to(scheduler, id_io_write);
}

VALUE rb_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length)
{
    // We should ensure string has capacity to receive data, and then resize it afterwards.
    return rb_funcall(scheduler, id_io_write, 4, io, buffer, SIZET2NUM(offset), SIZET2NUM(length));
}
