#ifndef INTERNAL_SCHEDULER_H                            /*-*-C-*-vi:se ft=cpp:*/
#define INTERNAL_SCHEDULER_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This file is a part of the Ruby language project.
 * @brief      Internal interfaces for the Fiber scheduler.
 */

#include "ruby/ruby.h"

VALUE rb_fiber_scheduler_interrupt_target_new(VALUE fiber, VALUE exception);
VALUE rb_fiber_scheduler_interrupt_target_exception(VALUE target);
void rb_fiber_scheduler_interrupt_target_invalidate(VALUE target);

#endif /* INTERNAL_SCHEDULER_H */
