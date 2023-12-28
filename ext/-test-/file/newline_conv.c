#include "ruby/ruby.h"
#include "ruby/io.h"
#include <fcntl.h>

static VALUE
open_with_rb_file_open(VALUE self, VALUE filename, VALUE read_or_write, VALUE binary_or_text)
{
    char fmode[3] = { 0 };
    if (rb_sym2id(read_or_write) == rb_intern("read")) {
        fmode[0] = 'r';
    }
    else if (rb_sym2id(read_or_write) == rb_intern("write")) {
        fmode[0] = 'w';
    }
    else {
        rb_raise(rb_eArgError, "read_or_write param must be :read or :write");
    }

    if (rb_sym2id(binary_or_text) == rb_intern("binary")) {
        fmode[1] = 'b';
    }
    else if (rb_sym2id(binary_or_text) == rb_intern("text")) {

    }
    else {
        rb_raise(rb_eArgError, "binary_or_text param must be :binary or :text");
    }

    return rb_file_open(StringValueCStr(filename), fmode);
}

static VALUE
open_with_rb_io_fdopen(VALUE self, VALUE filename, VALUE read_or_write, VALUE binary_or_text)
{
    int omode = 0;
    if (rb_sym2id(read_or_write) == rb_intern("read")) {
        omode |= O_RDONLY;
    }
    else if (rb_sym2id(read_or_write) == rb_intern("write")) {
        omode |= O_WRONLY;
    }
    else {
        rb_raise(rb_eArgError, "read_or_write param must be :read or :write");
    }

    if (rb_sym2id(binary_or_text) == rb_intern("binary")) {
#ifdef O_BINARY
        omode |= O_BINARY;
#endif
    }
    else if (rb_sym2id(binary_or_text) == rb_intern("text")) {

    }
    else {
        rb_raise(rb_eArgError, "binary_or_text param must be :binary or :text");
    }

    int fd = rb_cloexec_open(StringValueCStr(filename), omode, 0);
    if (fd < 0) {
        rb_raise(rb_eIOError, "failed to open the file");
    }

    rb_update_max_fd(fd);
    return rb_io_fdopen(fd, omode, StringValueCStr(filename));
}

void
Init_newline_conv(VALUE module)
{
    VALUE newline_conv = rb_define_module_under(module, "NewlineConv");
    rb_define_module_function(newline_conv, "rb_file_open", open_with_rb_file_open, 3);
    rb_define_module_function(newline_conv, "rb_io_fdopen", open_with_rb_io_fdopen, 3);
}
