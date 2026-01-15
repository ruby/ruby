/**********************************************************************

  io/nonblock.c -

  $Author$
  created at: Tue Jul 14 21:53:18 2009

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby.h"
#include "ruby/io.h"
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <fcntl.h>

#ifndef HAVE_RB_IO_DESCRIPTOR
static int
io_descriptor_fallback(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return fptr->fd;
}
#define rb_io_descriptor io_descriptor_fallback
#endif

#ifdef F_GETFL
static int
get_fcntl_flags(int fd)
{
    int f = fcntl(fd, F_GETFL);
    if (f == -1) rb_sys_fail(0);
    return f;
}
#else
#define get_fcntl_flags(fd) ((void)(fd), 0)
#endif

#ifdef F_GETFL
/*
 * call-seq:
 *   io.nonblock? -> boolean
 *
 * Returns +true+ if an IO object is in non-blocking mode.
 */
static VALUE
rb_io_nonblock_p(VALUE io)
{
    if (get_fcntl_flags(rb_io_descriptor(io)) & O_NONBLOCK)
        return Qtrue;
    return Qfalse;
}
#else
#define rb_io_nonblock_p rb_f_notimplement
#endif

#ifdef F_SETFL
static void
set_fcntl_flags(int fd, int f)
{
    if (fcntl(fd, F_SETFL, f) == -1)
	rb_sys_fail(0);
}

#ifndef RUBY_IO_NONBLOCK_METHODS

static int
io_nonblock_set(int fd, int f, int nb)
{
    if (nb) {
	if ((f & O_NONBLOCK) != 0)
	    return 0;
	f |= O_NONBLOCK;
    }
    else {
	if ((f & O_NONBLOCK) == 0)
	    return 0;
	f &= ~O_NONBLOCK;
    }
    set_fcntl_flags(fd, f);
    return 1;
}

/*
 * call-seq:
 *   io.nonblock = boolean -> boolean
 *
 * Enables non-blocking mode on a stream when set to
 * +true+, and blocking mode when set to +false+.
 *
 * This method set or clear O_NONBLOCK flag for the file descriptor
 * in <em>ios</em>.
 *
 * The behavior of most IO methods is not affected by this flag
 * because they retry system calls to complete their task
 * after EAGAIN and partial read/write.
 * (An exception is IO#syswrite which doesn't retry.)
 *
 * This method can be used to clear non-blocking mode of standard I/O.
 * Since nonblocking methods (read_nonblock, etc.) set non-blocking mode but
 * they doesn't clear it, this method is usable as follows.
 *
 *   END { STDOUT.nonblock = false }
 *   STDOUT.write_nonblock("foo")
 *
 * Since the flag is shared across processes and
 * many non-Ruby commands doesn't expect standard I/O with non-blocking mode,
 * it would be safe to clear the flag before Ruby program exits.
 *
 * For example following Ruby program leaves STDIN/STDOUT/STDER non-blocking mode.
 * (STDIN, STDOUT and STDERR are connected to a terminal.
 * So making one of them nonblocking-mode effects other two.)
 * Thus cat command try to read from standard input and
 * it causes "Resource temporarily unavailable" error (EAGAIN).
 *
 *   % ruby -e '
 *   STDOUT.write_nonblock("foo\n")'; cat
 *   foo
 *   cat: -: Resource temporarily unavailable
 *
 * Clearing the flag makes the behavior of cat command normal.
 * (cat command waits input from standard input.)
 *
 *   % ruby -rio/nonblock -e '
 *   END { STDOUT.nonblock = false }
 *   STDOUT.write_nonblock("foo")
 *   '; cat
 *   foo
 *
 */
static VALUE
rb_io_nonblock_set(VALUE self, VALUE value)
{
    if (RTEST(value)) {
        rb_io_t *fptr;
        GetOpenFile(self, fptr);
        rb_io_set_nonblock(fptr);
    }
    else {
        int descriptor = rb_io_descriptor(self);
        io_nonblock_set(descriptor, get_fcntl_flags(descriptor), RTEST(value));
    }

    return self;
}

#endif /* RUBY_IO_NONBLOCK_METHODS */

static VALUE
io_nonblock_restore(VALUE arg)
{
    int *restore = (int *)arg;
    set_fcntl_flags(restore[0], restore[1]);
    return Qnil;
}

/*
 * call-seq:
 *   io.nonblock {|io| } -> object
 *   io.nonblock(boolean) {|io| } -> object
 *
 * Yields +self+ in non-blocking mode.
 *
 * When +false+ is given as an argument, +self+ is yielded in blocking mode.
 * The original mode is restored after the block is executed.
 */
static VALUE
rb_io_nonblock_block(int argc, VALUE *argv, VALUE self)
{
    int nb = 1;

    int descriptor = rb_io_descriptor(self);

    if (argc > 0) {
        VALUE v;
        rb_scan_args(argc, argv, "01", &v);
        nb = RTEST(v);
    }

    int current_flags = get_fcntl_flags(descriptor);
    int restore[2] = {descriptor, current_flags};

    if (!io_nonblock_set(descriptor, current_flags, nb))
        return rb_yield(self);

    return rb_ensure(rb_yield, self, io_nonblock_restore, (VALUE)restore);
}
#else
#define rb_io_nonblock_set rb_f_notimplement
#define rb_io_nonblock_block rb_f_notimplement
#endif

void
Init_nonblock(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

#ifndef RUBY_IO_NONBLOCK_METHODS
    rb_define_method(rb_cIO, "nonblock?", rb_io_nonblock_p, 0);
    rb_define_method(rb_cIO, "nonblock=", rb_io_nonblock_set, 1);
#endif

    rb_define_method(rb_cIO, "nonblock", rb_io_nonblock_block, -1);
}
