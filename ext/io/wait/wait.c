/**********************************************************************

  io/wait.c -

  $Author$
  created at: Tue Aug 28 09:08:06 JST 2001

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby.h"
#include "ruby/io.h"

#include <sys/types.h>
#if defined(HAVE_SYS_IOCTL_H)
#include <sys/ioctl.h>
#endif
#if defined(FIONREAD_HEADER)
#include FIONREAD_HEADER
#endif

#ifdef HAVE_RB_W32_IOCTLSOCKET
#define ioctl ioctlsocket
#define ioctl_arg u_long
#define ioctl_arg2num(i) ULONG2NUM(i)
#else
#define ioctl_arg int
#define ioctl_arg2num(i) INT2NUM(i)
#endif

#ifdef HAVE_RB_W32_IS_SOCKET
#define FIONREAD_POSSIBLE_P(fd) rb_w32_is_socket(fd)
#else
#define FIONREAD_POSSIBLE_P(fd) ((void)(fd),Qtrue)
#endif

static VALUE io_ready_p _((VALUE io));
static VALUE io_wait _((int argc, VALUE *argv, VALUE io));
void Init_wait _((void));

/*
 * call-seq:
 *   io.nread -> int
 *
 * Returns number of bytes that can be read without blocking.
 * Returns zero if no information available.
 */

static VALUE
io_nread(VALUE io)
{
    rb_io_t *fptr;
    int len;
    ioctl_arg n;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    len = rb_io_read_pending(fptr);
    if (len > 0) return len;
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return INT2FIX(0);
    if (ioctl(fptr->fd, FIONREAD, &n)) return INT2FIX(0);
    if (n > 0) return ioctl_arg2num(n);
    return INT2FIX(0);
}

/*
 * call-seq:
 *   io.ready? -> true, false or nil
 *
 * Returns true if input available without blocking, or false.
 * Returns nil if no information available.
 */

static VALUE
io_ready_p(VALUE io)
{
    rb_io_t *fptr;
    ioctl_arg n;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (rb_io_read_pending(fptr)) return Qtrue;
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return Qnil;
    if (ioctl(fptr->fd, FIONREAD, &n)) return Qnil;
    if (n > 0) return Qtrue;
    return Qfalse;
}

struct wait_readable_arg {
    rb_fdset_t fds;
    struct timeval *timeout;
};

#ifdef HAVE_RB_FD_INIT
static VALUE
wait_readable(VALUE p)
{
    struct wait_readable_arg *arg = (struct wait_readable_arg *)p;
    rb_fdset_t *fds = &arg->fds;

    return (VALUE)rb_thread_fd_select(rb_fd_max(fds), fds, NULL, NULL, arg->timeout);
}
#endif

/*
 * call-seq:
 *   io.wait          -> IO, true, false or nil
 *   io.wait(timeout) -> IO, true, false or nil
 *
 * Waits until input is available or times out and returns self or nil when
 * EOF is reached.
 */

static VALUE
io_wait(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    struct wait_readable_arg arg;
    int fd, i;
    ioctl_arg n;
    VALUE timeout;
    struct timeval timerec;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    rb_scan_args(argc, argv, "01", &timeout);
    if (NIL_P(timeout)) {
	arg.timeout = 0;
    }
    else {
	timerec = rb_time_interval(timeout);
	arg.timeout = &timerec;
    }

    if (rb_io_read_pending(fptr)) return Qtrue;
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return Qfalse;
    fd = fptr->fd;
    rb_fd_init(&arg.fds);
    rb_fd_set(fd, &arg.fds);
#ifdef HAVE_RB_FD_INIT
    i = (int)rb_ensure(wait_readable, (VALUE)&arg,
		       (VALUE (*)_((VALUE)))rb_fd_term, (VALUE)&arg.fds);
#else
    i = rb_thread_fd_select(fd + 1, &arg.fds, NULL, NULL, arg.timeout);
#endif
    if (i < 0)
	rb_sys_fail(0);
    rb_io_check_closed(fptr);
    if (ioctl(fptr->fd, FIONREAD, &n)) rb_sys_fail(0);
    if (n > 0) return io;
    return Qnil;
}

/*
 * IO wait methods
 */

void
Init_wait()
{
    rb_define_method(rb_cIO, "nread", io_nread, 0);
    rb_define_method(rb_cIO, "ready?", io_ready_p, 0);
    rb_define_method(rb_cIO, "wait", io_wait, -1);
}
