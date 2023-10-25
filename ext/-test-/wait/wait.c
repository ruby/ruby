#include "ruby/ruby.h"
#include "ruby/io.h"

static VALUE
io_wait(VALUE klass, VALUE io, VALUE events, VALUE timeout)
{
    return rb_io_wait(io, events, timeout);
}

static VALUE
io_maybe_wait(VALUE klass, VALUE error, VALUE io, VALUE events, VALUE timeout)
{
    return rb_io_maybe_wait(RB_NUM2INT(error), io, events, timeout);
}

static VALUE
io_maybe_wait_readable(VALUE klass, VALUE error, VALUE io, VALUE timeout)
{
    return RB_INT2NUM(
        rb_io_maybe_wait_readable(RB_NUM2INT(error), io, timeout)
    );
}

static VALUE
io_maybe_wait_writable(VALUE klass, VALUE error, VALUE io, VALUE timeout)
{
    return RB_INT2NUM(
        rb_io_maybe_wait_writable(RB_NUM2INT(error), io, timeout)
    );
}

void
Init_wait(void)
{
    rb_define_singleton_method(rb_cIO, "io_wait", io_wait, 3);
    rb_define_singleton_method(rb_cIO, "io_maybe_wait", io_maybe_wait, 4);
    rb_define_singleton_method(rb_cIO, "io_maybe_wait_readable", io_maybe_wait_readable, 3);
    rb_define_singleton_method(rb_cIO, "io_maybe_wait_writable", io_maybe_wait_writable, 3);
}
