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

#ifndef RUBY_IO_WAIT_METHODS
/* Ruby 3.2+ can define these methods. This macro indicates that case. */

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

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_READABLE, timeout, 1);
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

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_WRITABLE, timeout, 1);
}

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
    rb_io_check_char_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = argc == 1 ? argv[0] : Qnil;

    return io_wait_event(io, RUBY_IO_PRIORITY, timeout, 1);
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

static inline rb_io_event_t
io_event_from_value(VALUE value)
{
    int events = RB_NUM2INT(value);

    if (events <= 0) rb_raise(rb_eArgError, "Events must be positive integer!");

    return events;
}

/*
 * call-seq:
 *   io.wait(events, timeout) -> event mask, false or nil
 *   io.wait(*event_symbols[, timeout]) -> self, true, or false
 *
 * Waits until the IO becomes ready for the specified events and returns the
 * subset of events that become ready, or a falsy value when times out.
 *
 * The events can be a bit mask of +IO::READABLE+, +IO::WRITABLE+ or
 * +IO::PRIORITY+.
 *
 * Returns an event mask (truthy value) immediately when buffered data is
 * available.
 *
 * The second form: if one or more event symbols (+:read+, +:write+, or
 * +:read_write+) are passed, the event mask is the bit OR of the bitmask
 * corresponding to those symbols.  In this form, +timeout+ is optional, the
 * order of the arguments is arbitrary, and returns +io+ if any of the
 * events is ready.
 *
 * You must require 'io/wait' to use this method.
 */

static VALUE
io_wait(int argc, VALUE *argv, VALUE io)
{
    VALUE timeout = Qundef;
    rb_io_event_t events = 0;
    int i, return_io = 0;

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

#ifndef RUBY_IO_WAIT_METHODS
    rb_define_method(rb_cIO, "wait", io_wait, -1);

    rb_define_method(rb_cIO, "wait_readable", io_wait_readable, -1);
    rb_define_method(rb_cIO, "wait_writable", io_wait_writable, -1);
    rb_define_method(rb_cIO, "wait_priority", io_wait_priority, -1);
#endif
}
