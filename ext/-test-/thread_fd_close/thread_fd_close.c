#include "ruby/ruby.h"

static VALUE
thread_fd_close(VALUE ign, VALUE fd)
{
    rb_thread_fd_close(NUM2INT(fd));
    return Qnil;
}

void
Init_thread_fd_close(void)
{
    rb_define_singleton_method(rb_cIO, "thread_fd_close", thread_fd_close, 1);
}
