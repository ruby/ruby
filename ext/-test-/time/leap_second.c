#include "internal/time.h"

static VALUE
bug_time_s_reset_leap_second_info(VALUE klass)
{
    ruby_reset_leap_second_info();
    return Qnil;
}

void
Init_time_leap_second(VALUE klass)
{
    rb_define_singleton_method(klass, "reset_leap_second_info", bug_time_s_reset_leap_second_info, 0);
}
