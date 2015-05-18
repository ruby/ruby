/**********************************************************************

  io/wait.c -

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

#ifdef F_GETFL
static int
io_nonblock_mode(int fd)
{
    int f = fcntl(fd, F_GETFL);
    if (f == -1) rb_sys_fail(0);
    return f;
}
#else
#define io_nonblock_mode(fd) ((void)(fd), 0)
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
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    if (io_nonblock_mode(fptr->fd) & O_NONBLOCK)
	return Qtrue;
    return Qfalse;
}
#else
#define rb_io_nonblock_p rb_f_notimplement
#endif

#ifdef F_SETFL
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
    if (fcntl(fd, F_SETFL, f) == -1)
	rb_sys_fail(0);
    return 1;
}

/*
 * call-seq:
 *   io.nonblock = boolean -> boolean
 *
 * Enables non-blocking mode on a stream when set to
 * +true+, and blocking mode when set to +false+.
 */
static VALUE
rb_io_nonblock_set(VALUE io, VALUE nb)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    if (RTEST(nb))
	rb_io_set_nonblock(fptr);
    else
	io_nonblock_set(fptr->fd, io_nonblock_mode(fptr->fd), RTEST(nb));
    return io;
}

static VALUE
io_nonblock_restore(VALUE arg)
{
    int *restore = (int *)arg;
    if (fcntl(restore[0], F_SETFL, restore[1]) == -1)
	rb_sys_fail(0);
    return Qnil;
}

/*
 * call-seq:
 *   io.nonblock {|io| } -> io
 *   io.nonblock(boolean) {|io| } -> io
 *
 * Yields +self+ in non-blocking mode.
 *
 * When +false+ is given as an argument, +self+ is yielded in blocking mode.
 * The original mode is restored after the block is executed.
 */
static VALUE
rb_io_nonblock_block(int argc, VALUE *argv, VALUE io)
{
    int nb = 1;
    rb_io_t *fptr;
    int f, restore[2];

    GetOpenFile(io, fptr);
    if (argc > 0) {
	VALUE v;
	rb_scan_args(argc, argv, "01", &v);
	nb = RTEST(v);
    }
    f = io_nonblock_mode(fptr->fd);
    restore[0] = fptr->fd;
    restore[1] = f;
    if (!io_nonblock_set(fptr->fd, f, nb))
	return rb_yield(io);
    return rb_ensure(rb_yield, io, io_nonblock_restore, (VALUE)restore);
}
#else
#define rb_io_nonblock_set rb_f_notimplement
#define rb_io_nonblock_block rb_f_notimplement
#endif

void
Init_nonblock(void)
{
    rb_define_method(rb_cIO, "nonblock?", rb_io_nonblock_p, 0);
    rb_define_method(rb_cIO, "nonblock=", rb_io_nonblock_set, 1);
    rb_define_method(rb_cIO, "nonblock", rb_io_nonblock_block, -1);
}
