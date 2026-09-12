#ifndef INTERNAL_SCHEDULER_H                            /*-*-C-*-vi:se ft=cpp:*/
#define INTERNAL_SCHEDULER_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This file is a part of the Ruby language project.
 * @brief      Internal interfaces for the Fiber scheduler.
 */

#include "ruby/ruby.h"

VALUE rb_fiber_scheduler_io_operation_new(VALUE fiber, VALUE exception);
VALUE rb_fiber_scheduler_io_operation_exception(VALUE operation);
void rb_fiber_scheduler_io_operation_invalidate(VALUE operation);
bool rb_fiber_scheduler_supports_blocking_operation_interrupt(VALUE scheduler);

#endif /* INTERNAL_SCHEDULER_H */
