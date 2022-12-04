#include "ruby.h"
#include "rubyspec.h"
#include "ruby/io.h"
#include <errno.h>
#include <fcntl.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

static int set_non_blocking(int fd) {
#if defined(O_NONBLOCK) && defined(F_GETFL)
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags == -1)
    flags = 0;
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#elif defined(FIOBIO)
  int flags = 1;
  return ioctl(fd, FIOBIO, &flags);
#else
#define SET_NON_BLOCKING_FAILS_ALWAYS 1
  errno = ENOSYS;
  return -1;
#endif
}

static int io_spec_get_fd(VALUE io) {
  rb_io_t* fp;
  GetOpenFile(io, fp);
  return fp->fd;
}

VALUE io_spec_GetOpenFile_fd(VALUE self, VALUE io) {
  return INT2NUM(io_spec_get_fd(io));
}

VALUE io_spec_rb_io_addstr(VALUE self, VALUE io, VALUE str) {
  return rb_io_addstr(io, str);
}

VALUE io_spec_rb_io_printf(VALUE self, VALUE io, VALUE ary) {
  long argc = RARRAY_LEN(ary);
  VALUE *argv = (VALUE*) alloca(sizeof(VALUE) * argc);
  int i;

  for (i = 0; i < argc; i++) {
    argv[i] = rb_ary_entry(ary, i);
  }

  return rb_io_printf((int)argc, argv, io);
}

VALUE io_spec_rb_io_print(VALUE self, VALUE io, VALUE ary) {
  long argc = RARRAY_LEN(ary);
  VALUE *argv = (VALUE*) alloca(sizeof(VALUE) * argc);
  int i;

  for (i = 0; i < argc; i++) {
    argv[i] = rb_ary_entry(ary, i);
  }

  return rb_io_print((int)argc, argv, io);
}

VALUE io_spec_rb_io_puts(VALUE self, VALUE io, VALUE ary) {
  long argc = RARRAY_LEN(ary);
  VALUE *argv = (VALUE*) alloca(sizeof(VALUE) * argc);
  int i;

  for (i = 0; i < argc; i++) {
    argv[i] = rb_ary_entry(ary, i);
  }

  return rb_io_puts((int)argc, argv, io);
}

VALUE io_spec_rb_io_write(VALUE self, VALUE io, VALUE str) {
  return rb_io_write(io, str);
}

VALUE io_spec_rb_io_check_io(VALUE self, VALUE io) {
  return rb_io_check_io(io);
}

VALUE io_spec_rb_io_check_readable(VALUE self, VALUE io) {
  rb_io_t* fp;
  GetOpenFile(io, fp);
  rb_io_check_readable(fp);
  return Qnil;
}

VALUE io_spec_rb_io_check_writable(VALUE self, VALUE io) {
  rb_io_t* fp;
  GetOpenFile(io, fp);
  rb_io_check_writable(fp);
  return Qnil;
}

VALUE io_spec_rb_io_check_closed(VALUE self, VALUE io) {
  rb_io_t* fp;
  GetOpenFile(io, fp);
  rb_io_check_closed(fp);
  return Qnil;
}

VALUE io_spec_rb_io_taint_check(VALUE self, VALUE io) {
  /*rb_io_t* fp;
  GetOpenFile(io, fp);*/
  rb_io_taint_check(io);
  return io;
}

#define RB_IO_WAIT_READABLE_BUF 13

#ifdef SET_NON_BLOCKING_FAILS_ALWAYS
NORETURN(VALUE io_spec_rb_io_wait_readable(VALUE self, VALUE io, VALUE read_p));
#endif

VALUE io_spec_rb_io_wait_readable(VALUE self, VALUE io, VALUE read_p) {
  int fd = io_spec_get_fd(io);
#ifndef SET_NON_BLOCKING_FAILS_ALWAYS
  char buf[RB_IO_WAIT_READABLE_BUF];
  int ret, saved_errno;
#endif

  if (set_non_blocking(fd) == -1)
    rb_sys_fail("set_non_blocking failed");

#ifndef SET_NON_BLOCKING_FAILS_ALWAYS
  if(RTEST(read_p)) {
    if (read(fd, buf, RB_IO_WAIT_READABLE_BUF) != -1) {
      return Qnil;
    }
    saved_errno = errno;
    rb_ivar_set(self, rb_intern("@write_data"), Qtrue);
    errno = saved_errno;
  }

  ret = rb_io_wait_readable(fd);

  if(RTEST(read_p)) {
    ssize_t r = read(fd, buf, RB_IO_WAIT_READABLE_BUF);
    if (r != RB_IO_WAIT_READABLE_BUF) {
      perror("read");
      return SSIZET2NUM(r);
    }
    rb_ivar_set(self, rb_intern("@read_data"),
        rb_str_new(buf, RB_IO_WAIT_READABLE_BUF));
  }

  return ret ? Qtrue : Qfalse;
#else
  UNREACHABLE;
#endif
}

VALUE io_spec_rb_io_wait_writable(VALUE self, VALUE io) {
  int ret = rb_io_wait_writable(io_spec_get_fd(io));
  return ret ? Qtrue : Qfalse;
}

VALUE io_spec_rb_thread_wait_fd(VALUE self, VALUE io) {
  rb_thread_wait_fd(io_spec_get_fd(io));
  return Qnil;
}

VALUE io_spec_rb_wait_for_single_fd(VALUE self, VALUE io, VALUE events, VALUE secs, VALUE usecs) {
  int fd = io_spec_get_fd(io);
  struct timeval tv;
  if (!NIL_P(secs)) {
    tv.tv_sec = FIX2INT(secs);
    tv.tv_usec = FIX2INT(usecs);
  }
  return INT2FIX(rb_wait_for_single_fd(fd, FIX2INT(events), NIL_P(secs) ? NULL : &tv));
}

VALUE io_spec_rb_thread_fd_writable(VALUE self, VALUE io) {
  rb_thread_fd_writable(io_spec_get_fd(io));
  return Qnil;
}

VALUE io_spec_rb_io_binmode(VALUE self, VALUE io) {
  return rb_io_binmode(io);
}

VALUE io_spec_rb_fd_fix_cloexec(VALUE self, VALUE io) {
  rb_fd_fix_cloexec(io_spec_get_fd(io));
  return Qnil;
}

VALUE io_spec_rb_cloexec_open(VALUE self, VALUE path, VALUE flags, VALUE mode) {
  const char *pathname = StringValuePtr(path);
  int fd = rb_cloexec_open(pathname, FIX2INT(flags), FIX2INT(mode));
  return rb_funcall(rb_cIO, rb_intern("for_fd"), 1, INT2FIX(fd));
}

VALUE io_spec_rb_io_close(VALUE self, VALUE io) {
  return rb_io_close(io);
}

VALUE io_spec_rb_io_set_nonblock(VALUE self, VALUE io) {
  rb_io_t* fp;
#ifdef F_GETFL
  int flags;
#endif
  GetOpenFile(io, fp);
  rb_io_set_nonblock(fp);
#ifdef F_GETFL
  flags = fcntl(fp->fd, F_GETFL, 0);
  return flags & O_NONBLOCK ? Qtrue : Qfalse;
#else
  return Qfalse;
#endif
}

/*
 * this is needed to ensure rb_io_wait_*able functions behave
 * predictably because errno may be set to unexpected values
 * otherwise.
 */
static VALUE io_spec_errno_set(VALUE self, VALUE val) {
  int e = NUM2INT(val);
  errno = e;
  return val;
}

VALUE io_spec_mode_sync_flag(VALUE self, VALUE io) {
  rb_io_t *fp;
  GetOpenFile(io, fp);
  if (fp->mode & FMODE_SYNC) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

void Init_io_spec(void) {
  VALUE cls = rb_define_class("CApiIOSpecs", rb_cObject);
  rb_define_method(cls, "GetOpenFile_fd", io_spec_GetOpenFile_fd, 1);
  rb_define_method(cls, "rb_io_addstr", io_spec_rb_io_addstr, 2);
  rb_define_method(cls, "rb_io_printf", io_spec_rb_io_printf, 2);
  rb_define_method(cls, "rb_io_print", io_spec_rb_io_print, 2);
  rb_define_method(cls, "rb_io_puts", io_spec_rb_io_puts, 2);
  rb_define_method(cls, "rb_io_write", io_spec_rb_io_write, 2);
  rb_define_method(cls, "rb_io_close", io_spec_rb_io_close, 1);
  rb_define_method(cls, "rb_io_check_io", io_spec_rb_io_check_io, 1);
  rb_define_method(cls, "rb_io_check_readable", io_spec_rb_io_check_readable, 1);
  rb_define_method(cls, "rb_io_check_writable", io_spec_rb_io_check_writable, 1);
  rb_define_method(cls, "rb_io_check_closed", io_spec_rb_io_check_closed, 1);
  rb_define_method(cls, "rb_io_set_nonblock", io_spec_rb_io_set_nonblock, 1);
  rb_define_method(cls, "rb_io_taint_check", io_spec_rb_io_taint_check, 1);
  rb_define_method(cls, "rb_io_wait_readable", io_spec_rb_io_wait_readable, 2);
  rb_define_method(cls, "rb_io_wait_writable", io_spec_rb_io_wait_writable, 1);
  rb_define_method(cls, "rb_thread_wait_fd", io_spec_rb_thread_wait_fd, 1);
  rb_define_method(cls, "rb_thread_fd_writable", io_spec_rb_thread_fd_writable, 1);
  rb_define_method(cls, "rb_wait_for_single_fd", io_spec_rb_wait_for_single_fd, 4);
  rb_define_method(cls, "rb_io_binmode", io_spec_rb_io_binmode, 1);
  rb_define_method(cls, "rb_fd_fix_cloexec", io_spec_rb_fd_fix_cloexec, 1);
  rb_define_method(cls, "rb_cloexec_open", io_spec_rb_cloexec_open, 3);
  rb_define_method(cls, "errno=", io_spec_errno_set, 1);
  rb_define_method(cls, "rb_io_mode_sync_flag", io_spec_mode_sync_flag, 1);
}

#ifdef __cplusplus
}
#endif
