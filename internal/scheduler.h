#pragma once

#include "ruby/ruby.h"

VALUE rb_fiber_scheduler_interrupt_target_new(VALUE fiber, VALUE exception);
VALUE rb_fiber_scheduler_interrupt_target_exception(VALUE target);
void rb_fiber_scheduler_interrupt_target_invalidate(VALUE target);
