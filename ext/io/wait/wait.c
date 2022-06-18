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

#ifdef HAVE_RB_IO_WAIT
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
    }
    else {
        return Qfalse;
    }
}
#else
static VALUE io_ready_p _((VALUE io));
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
    if (!FIONREAD_POSSIBLE_P(fptr->fd)) return INT2FIX(0);
    if (ioctl(fptr->fd, FIONREAD, &n)) return INT2FIX(0);
    if (n > 0) return ioctl_arg2num(n);
    return INT2FIX(0);
}

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
    if (wait_for_single_fd(fptr, RB_WAITFD_IN, &tv))
        return Qtrue;
#else
    if (RTEST(io_wait_event(io, RUBY_IO_READABLE, RB_INT2NUM(0))))
        return Qtrue;
#endif
    return Qfalse;
}

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
}
