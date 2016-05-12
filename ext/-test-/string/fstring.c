#include "ruby.h"

VALUE rb_fstring(VALUE str);

VALUE
bug_s_fstring(VALUE self, VALUE str)
{
    return rb_fstring(str);
}

void
Init_fstring(VALUE klass)
{
    rb_define_singleton_method(klass, "fstring", bug_s_fstring, 1);
}
