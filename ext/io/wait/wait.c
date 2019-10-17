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
#if defined(HAVE_UNISTD_H) && (defined(__sun))
#include <unistd.h>
#endif
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
static VALUE io_wait_readable _((int argc, VALUE *argv, VALUE io));
static VALUE io_wait_writable _((int argc, VALUE *argv, VALUE io));
void Init_wait _((void));

static struct timeval *
get_timeout(int argc, VALUE *argv, struct timeval *timerec)
{
    VALUE timeout = Qnil;
    rb_check_arity(argc, 0, 1);
    if (!argc || NIL_P(timeout = argv[0])) {
	return NULL;
    }
    else {
	*timerec = rb_time_interval(timeout);
	return timerec;
    }
}

static int
wait_for_single_fd(rb_io_t *fptr, int events, struct timeval *tv)
{
    int i = rb_wait_for_single_fd(fptr->fd, events, tv);
    if (i < 0)
	rb_sys_fail(0);
    rb_io_check_closed(fptr);
    return (i & events);
}

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
    if (len > 0) return INT2FIX(len);
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return INT2FIX(0);
    if (ioctl(fptr->fd, FIONREAD, &n)) return INT2FIX(0);
    if (n > 0) return ioctl_arg2num(n);
    return INT2FIX(0);
}

/*
 * call-seq:
 *   io.ready? -> true or false
 *
 * Returns true if input available without blocking, or false.
 */

static VALUE
io_ready_p(VALUE io)
{
    rb_io_t *fptr;
    struct timeval tv = {0, 0};

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (rb_io_read_pending(fptr)) return Qtrue;
    if (wait_for_single_fd(fptr, RB_WAITFD_IN, &tv))
	return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *   io.wait_readable          -> IO, true or nil
 *   io.wait_readable(timeout) -> IO, true or nil
 *
 * Waits until IO is readable without blocking and returns +self+, or
 * +nil+ when times out.
 * Returns +true+ immediately when buffered data is available.
 */

static VALUE
io_wait_readable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    struct timeval timerec;
    struct timeval *tv;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    tv = get_timeout(argc, argv, &timerec);
    if (rb_io_read_pending(fptr)) return Qtrue;
    if (wait_for_single_fd(fptr, RB_WAITFD_IN, tv)) {
	return io;
    }
    return Qnil;
}

/*
 * call-seq:
 *   io.wait_writable          -> IO
 *   io.wait_writable(timeout) -> IO or nil
 *
 * Waits until IO is writable without blocking and returns +self+ or
 * +nil+ when times out.
 */
static VALUE
io_wait_writable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    struct timeval timerec;
    struct timeval *tv;

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    tv = get_timeout(argc, argv, &timerec);
    if (wait_for_single_fd(fptr, RB_WAITFD_OUT, tv)) {
	return io;
    }
    return Qnil;
}

static int
wait_mode_sym(VALUE mode)
{
    if (mode == ID2SYM(rb_intern("r"))) {
	return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("read"))) {
	return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("readable"))) {
	return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("w"))) {
	return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("write"))) {
	return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("writable"))) {
	return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("rw"))) {
	return RB_WAITFD_IN|RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("read_write"))) {
	return RB_WAITFD_IN|RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("readable_writable"))) {
	return RB_WAITFD_IN|RB_WAITFD_OUT;
    }
    rb_raise(rb_eArgError, "unsupported mode: %"PRIsVALUE, mode);
    return 0;
}

/*
 * call-seq:
 *   io.wait(timeout = nil, mode = :read) -> IO, true or nil
 *
 * Waits until IO is readable or writable without blocking and returns
 * +self+, or +nil+ when times out.
 * Returns +true+ immediately when buffered data is available.
 * Optional parameter +mode+ is one of +:read+, +:write+, or
 * +:read_write+.
 */

static VALUE
io_wait_readwrite(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    struct timeval timerec;
    struct timeval *tv = NULL;
    int event = 0;
    int i;

    GetOpenFile(io, fptr);
    for (i = 0; i < argc; ++i) {
	if (SYMBOL_P(argv[i])) {
	    event |= wait_mode_sym(argv[i]);
	}
	else {
	    *(tv = &timerec) = rb_time_interval(argv[i]);
	}
    }
    /* rb_time_interval() and might_mode() might convert the argument */
    rb_io_check_closed(fptr);
    if (!event) event = RB_WAITFD_IN;
    if ((event & RB_WAITFD_IN) && rb_io_read_pending(fptr))
	return Qtrue;
    if (wait_for_single_fd(fptr, event, tv))
	return io;
    return Qnil;
}

/*
 * IO wait methods
 */

void
Init_wait(void)
{
    rb_define_method(rb_cIO, "nread", io_nread, 0);
    rb_define_method(rb_cIO, "ready?", io_ready_p, 0);
    rb_define_method(rb_cIO, "wait", io_wait_readwrite, -1);
    rb_define_method(rb_cIO, "wait_readable", io_wait_readable, -1);
    rb_define_method(rb_cIO, "wait_writable", io_wait_writable, -1);
}
