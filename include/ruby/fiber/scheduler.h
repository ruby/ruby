#ifndef RUBY_FIBER_SCHEDULER_H                                 /*-*-C-*-vi:se ft=c:*/
#define RUBY_FIBER_SCHEDULER_H
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

RBIMPL_SYMBOL_EXPORT_BEGIN()

VALUE rb_fiber_scheduler_get(void);
VALUE rb_fiber_scheduler_set(VALUE scheduler);

VALUE rb_fiber_scheduler_current(void);
VALUE rb_fiber_scheduler_current_for_thread(VALUE thread);

VALUE rb_fiber_scheduler_make_timeout(struct timeval *timeout);

VALUE rb_fiber_scheduler_close(VALUE scheduler);

VALUE rb_fiber_scheduler_kernel_sleep(VALUE scheduler, VALUE duration);
VALUE rb_fiber_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv);

#if 0
VALUE rb_fiber_scheduler_timeout_after(VALUE scheduler, VALUE timeout, VALUE exception, VALUE message);
VALUE rb_fiber_scheduler_timeout_afterv(VALUE scheduler, int argc, VALUE * argv);
#endif

int rb_fiber_scheduler_supports_process_wait(VALUE scheduler);
VALUE rb_fiber_scheduler_process_wait(VALUE scheduler, rb_pid_t pid, int flags);

VALUE rb_fiber_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout);
VALUE rb_fiber_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber);

VALUE rb_fiber_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout);
VALUE rb_fiber_scheduler_io_wait_readable(VALUE scheduler, VALUE io);
VALUE rb_fiber_scheduler_io_wait_writable(VALUE scheduler, VALUE io);
VALUE rb_fiber_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length);
VALUE rb_fiber_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t offset, size_t length);

VALUE rb_fiber_scheduler_address_resolve(VALUE scheduler, VALUE hostname);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_FIBER_SCHEDULER_H */
