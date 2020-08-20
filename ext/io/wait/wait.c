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
    rb_io_t *fptr = NULL;
    ioctl_arg n;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    int len = rb_io_read_pending(fptr);
    if (len > 0) return INT2FIX(len);
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return INT2FIX(0);
    if (ioctl(fptr->fd, FIONREAD, &n)) return INT2FIX(0);
    if (n > 0) return ioctl_arg2num(n);
    return INT2FIX(0);
}

static VALUE
io_wait_event(VALUE io, int event, VALUE timeout)
{
    VALUE result = rb_io_wait(io, RB_INT2NUM(event), timeout);

    if (!RB_TEST(result)) {
        return Qnil;
    }

    int mask = RB_NUM2INT(result);

    if (mask & event) {
        return io;
    } else {
        return Qfalse;
    }
}

/*
 * call-seq:
 *   io.ready? -> true or false
 *
 * Returns +true+ if input available without blocking, or +false+.
 */

static VALUE
io_ready_p(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (rb_io_read_pending(fptr)) return Qtrue;

    return io_wait_event(io, RUBY_IO_READABLE, RB_INT2NUM(0));
}

/*
 * call-seq:
 *   io.wait_readable          -> true or false
 *   io.wait_readable(timeout) -> true or false
 *
 * Waits until IO is readable and returns +true+, or
 * +false+ when times out.
 * Returns +true+ immediately when buffered data is available.
 */

static VALUE
io_wait_readable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr = NULL;

    RB_IO_POINTER(io, fptr);
    rb_io_check_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_READABLE, timeout);
}

/*
 * call-seq:
 *   io.wait_writable          -> true or false
 *   io.wait_writable(timeout) -> true or false
 *
 * Waits until IO is writable and returns +true+ or
 * +false+ when times out.
 */
static VALUE
io_wait_writable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr = NULL;

    RB_IO_POINTER(io, fptr);
    rb_io_check_writable(fptr);

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_WRITABLE, timeout);
}

/*
 * call-seq:
 *   io.wait_priority          -> true or false
 *   io.wait_priority(timeout) -> true or false
 *
 * Waits until IO is priority and returns +true+ or
 * +false+ when times out.
 */
static VALUE
io_wait_priority(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr = NULL;

    RB_IO_POINTER(io, fptr);
    rb_io_check_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = argc == 1 ? argv[0] : Qnil;

    return io_wait_event(io, RUBY_IO_PRIORITY, timeout);
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
 *   io.wait(events, timeout) -> event mask or false.
 *   io.wait(timeout = nil, mode = :read) -> event mask or false (deprecated)
 *
 * Waits until the IO becomes ready for the specified events and returns the
 * subset of events that become ready, or +false+ when times out.
 *
 * The events can be a bit mask of +IO::READABLE+, +IO::WRITABLE+ or
 * +IO::PRIORITY+.
 *
 * Returns +true+ immediately when buffered data is available.
 *
 * Optional parameter +mode+ is one of +:read+, +:write+, or
 * +:read_write+ (deprecated).
 */

static VALUE
io_wait(int argc, VALUE *argv, VALUE io)
{
    VALUE timeout = Qnil;
    rb_io_event_t events = 0;

    if (argc < 2 || (argc >= 2 && RB_SYMBOL_P(argv[1]))) {
        if (argc > 0) {
          timeout = argv[0];
        }

        for (int i = 1; i < argc; i += 1) {
            events |= wait_mode_sym(argv[i]);
        }
    } else if (argc == 2) {
        events = RB_NUM2UINT(argv[0]);
        
        if (argv[1] != Qnil) {
          timeout = argv[1];
        }
    } else {
        // TODO error
        return Qnil;
    }

    if (events == 0) {
        events = RUBY_IO_READABLE;
    }

    if (events & RUBY_IO_READABLE) {
        rb_io_t *fptr = NULL;
        RB_IO_POINTER(io, fptr);

        if (rb_io_read_pending(fptr)) {
            return Qtrue;
        }
    }

    return io_wait_event(io, events, timeout);
}

/*
 * IO wait methods
 */

void
Init_wait(void)
{
    rb_define_method(rb_cIO, "nread", io_nread, 0);
    rb_define_method(rb_cIO, "ready?", io_ready_p, 0);

    rb_define_method(rb_cIO, "wait", io_wait, -1);

    rb_define_method(rb_cIO, "wait_readable", io_wait_readable, -1);
    rb_define_method(rb_cIO, "wait_writable", io_wait_writable, -1);
    rb_define_method(rb_cIO, "wait_priority", io_wait_priority, -1);
}
