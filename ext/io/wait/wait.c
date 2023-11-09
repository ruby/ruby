/* -*- c-file-style: "ruby"; indent-tabs-mode: t -*- */
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

#ifndef HAVE_RB_IO_WAIT
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
#endif

/*
 * call-seq:
 *   io.nread -> int
 *
 * Returns number of bytes that can be read without blocking.
 * Returns zero if no information available.
 *
 * You must require 'io/wait' to use this method.
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

#ifdef HAVE_RB_IO_DESCRIPTOR
    int fd = rb_io_descriptor(io);
#else
    int fd = fptr->fd;
#endif

    if (!FIONREAD_POSSIBLE_P(fd)) return INT2FIX(0);
    if (ioctl(fd, FIONREAD, &n)) return INT2FIX(0);
    if (n > 0) return ioctl_arg2num(n);
    return INT2FIX(0);
}

#ifdef HAVE_RB_IO_WAIT
static VALUE
io_wait_event(VALUE io, int event, VALUE timeout, int return_io)
{
    VALUE result = rb_io_wait(io, RB_INT2NUM(event), timeout);

    if (!RB_TEST(result)) {
        return Qnil;
    }

    int mask = RB_NUM2INT(result);

    if (mask & event) {
        if (return_io)
            return io;
        else
            return result;
    }
    else {
        return Qfalse;
    }
}
#endif

/*
 * call-seq:
 *   io.ready? -> truthy or falsy
 *
 * Returns a truthy value if input available without blocking, or a
 * falsy value.
 *
 * You must require 'io/wait' to use this method.
 */

static VALUE
io_ready_p(VALUE io)
{
    rb_io_t *fptr;
#ifndef HAVE_RB_IO_WAIT
    struct timeval tv = {0, 0};
#endif

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (rb_io_read_pending(fptr)) return Qtrue;

#ifndef HAVE_RB_IO_WAIT
    return wait_for_single_fd(fptr, RB_WAITFD_IN, &tv) ? Qtrue : Qfalse;
#else
    return io_wait_event(io, RUBY_IO_READABLE, RB_INT2NUM(0), 1);
#endif
}

/* Ruby 3.2+ can define these methods. This macro indicates that case. */
#ifndef RUBY_IO_WAIT_METHODS

/*
 * call-seq:
 *   io.wait_readable          -> truthy or falsy
 *   io.wait_readable(timeout) -> truthy or falsy
 *
 * Waits until IO is readable and returns a truthy value, or a falsy
 * value when times out.  Returns a truthy value immediately when
 * buffered data is available.
 *
 * You must require 'io/wait' to use this method.
 */

static VALUE
io_wait_readable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
#ifndef HAVE_RB_IO_WAIT
    struct timeval timerec;
    struct timeval *tv;
#endif

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

#ifndef HAVE_RB_IO_WAIT
    tv = get_timeout(argc, argv, &timerec);
#endif
    if (rb_io_read_pending(fptr)) return Qtrue;

#ifndef HAVE_RB_IO_WAIT
    if (wait_for_single_fd(fptr, RB_WAITFD_IN, tv)) {
        return io;
    }
    return Qnil;
#else
    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_READABLE, timeout, 1);
#endif
}

/*
 * call-seq:
 *   io.wait_writable          -> truthy or falsy
 *   io.wait_writable(timeout) -> truthy or falsy
 *
 * Waits until IO is writable and returns a truthy value or a falsy
 * value when times out.
 *
 * You must require 'io/wait' to use this method.
 */
static VALUE
io_wait_writable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
#ifndef HAVE_RB_IO_WAIT
    struct timeval timerec;
    struct timeval *tv;
#endif

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

#ifndef HAVE_RB_IO_WAIT
    tv = get_timeout(argc, argv, &timerec);
    if (wait_for_single_fd(fptr, RB_WAITFD_OUT, tv)) {
        return io;
    }
    return Qnil;
#else
    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_WRITABLE, timeout, 1);
#endif
}

#ifdef HAVE_RB_IO_WAIT
/*
 * call-seq:
 *   io.wait_priority          -> truthy or falsy
 *   io.wait_priority(timeout) -> truthy or falsy
 *
 * Waits until IO is priority and returns a truthy value or a falsy
 * value when times out. Priority data is sent and received using
 * the Socket::MSG_OOB flag and is typically limited to streams.
 *
 * You must require 'io/wait' to use this method.
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

    return io_wait_event(io, RUBY_IO_PRIORITY, timeout, 1);
}
#endif

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

#ifdef HAVE_RB_IO_WAIT
static inline rb_io_event_t
io_event_from_value(VALUE value)
{
    int events = RB_NUM2INT(value);

    if (events <= 0) rb_raise(rb_eArgError, "Events must be positive integer!");

    return events;
}
#endif

/*
 * call-seq:
 *   io.wait(events, timeout) -> event mask, false or nil
 *   io.wait(timeout = nil, mode = :read) -> self, true, or false
 *
 * Waits until the IO becomes ready for the specified events and returns the
 * subset of events that become ready, or a falsy value when times out.
 *
 * The events can be a bit mask of +IO::READABLE+, +IO::WRITABLE+ or
 * +IO::PRIORITY+.
 *
 * Returns a truthy value immediately when buffered data is available.
 *
 * Optional parameter +mode+ is one of +:read+, +:write+, or
 * +:read_write+.
 *
 * You must require 'io/wait' to use this method.
 */

static VALUE
io_wait(int argc, VALUE *argv, VALUE io)
{
#ifndef HAVE_RB_IO_WAIT
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
#else
    VALUE timeout = Qundef;
    rb_io_event_t events = 0;
    int i, return_io = 0;

    /* The documented signature for this method is actually incorrect.
     * A single timeout is allowed in any position, and multiple symbols can be given.
     * Whether this is intentional or not, I don't know, and as such I consider this to
     * be a legacy/slow path. */
    if (argc != 2 || (RB_SYMBOL_P(argv[0]) || RB_SYMBOL_P(argv[1]))) {
        /* We'd prefer to return the actual mask, but this form would return the io itself: */
        return_io = 1;

        /* Slow/messy path: */
        for (i = 0; i < argc; i += 1) {
            if (RB_SYMBOL_P(argv[i])) {
                events |= wait_mode_sym(argv[i]);
            }
            else if (timeout == Qundef) {
                rb_time_interval(timeout = argv[i]);
            }
            else {
                rb_raise(rb_eArgError, "timeout given more than once");
            }
        }

        if (timeout == Qundef) timeout = Qnil;

        if (events == 0) {
            events = RUBY_IO_READABLE;
        }
    }
    else /* argc == 2 and neither are symbols */ {
        /* This is the fast path: */
        events = io_event_from_value(argv[0]);
        timeout = argv[1];
    }

    if (events & RUBY_IO_READABLE) {
        rb_io_t *fptr = NULL;
        RB_IO_POINTER(io, fptr);

        if (rb_io_read_pending(fptr)) {
            /* This was the original behaviour: */
            if (return_io) return Qtrue;
            /* New behaviour always returns an event mask: */
            else return RB_INT2NUM(RUBY_IO_READABLE);
        }
    }

    return io_wait_event(io, events, timeout, return_io);
#endif
}

#endif /* RUBY_IO_WAIT_METHODS */

/*
 * IO wait methods
 */

void
Init_wait(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    RB_EXT_RACTOR_SAFE(true);
#endif

    rb_define_method(rb_cIO, "nread", io_nread, 0);
    rb_define_method(rb_cIO, "ready?", io_ready_p, 0);

#ifndef RUBY_IO_WAIT_METHODS
    rb_define_method(rb_cIO, "wait", io_wait, -1);

    rb_define_method(rb_cIO, "wait_readable", io_wait_readable, -1);
    rb_define_method(rb_cIO, "wait_writable", io_wait_writable, -1);
#ifdef HAVE_RB_IO_WAIT
    rb_define_method(rb_cIO, "wait_priority", io_wait_priority, -1);
#endif
#endif
}
