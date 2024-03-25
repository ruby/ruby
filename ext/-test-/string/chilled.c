#include "ruby.h"

static VALUE
bug_s_rb_str_chilled_p(VALUE self, VALUE str)
{
    return rb_str_chilled_p(str) ? Qtrue : Qfalse;
}

void
Init_string_chilled(VALUE klass)
{
    rb_define_singleton_method(klass, "rb_str_chilled_p", bug_s_rb_str_chilled_p, 1);
}
