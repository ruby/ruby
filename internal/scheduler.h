#ifndef RUBY_SCHEDULER_H                                 /*-*-C-*-vi:se ft=c:*/
#define RUBY_SCHEDULER_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Scheduler.
 */
#include "ruby/ruby.h"
#include "ruby/intern.h"

VALUE rb_scheduler_timeout(struct timeval *timeout);

VALUE rb_scheduler_kernel_sleep(VALUE scheduler, VALUE duration);
VALUE rb_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv);

VALUE rb_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout);
VALUE rb_scheduler_io_wait_readable(VALUE scheduler, VALUE io);
VALUE rb_scheduler_io_wait_writable(VALUE scheduler, VALUE io);

VALUE rb_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, VALUE offset, VALUE length);
VALUE rb_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, VALUE offset, VALUE length);

#endif /* RUBY_SCHEDULER_H */
