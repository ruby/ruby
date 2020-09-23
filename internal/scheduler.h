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

VALUE rb_scheduler_get();
VALUE rb_scheduler_set(VALUE scheduler);

VALUE rb_scheduler_current();
VALUE rb_thread_scheduler_current(VALUE thread);

VALUE rb_scheduler_timeout(struct timeval *timeout);

VALUE rb_scheduler_close(VALUE scheduler);

VALUE rb_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout);
VALUE rb_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber);

VALUE rb_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout);
VALUE rb_scheduler_io_wait_readable(VALUE scheduler, VALUE io);
VALUE rb_scheduler_io_wait_writable(VALUE scheduler, VALUE io);

int rb_scheduler_supports_io_read(VALUE scheduler);
VALUE rb_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length);

int rb_scheduler_supports_io_write(VALUE scheduler);
VALUE rb_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length);

#endif /* RUBY_SCHEDULER_H */
