#include "ruby.h"

VALUE
bug_str_nofree(VALUE self)
{
    return rb_str_new_cstr("abcdef");
}

void
Init_nofree(VALUE klass)
{
    rb_define_singleton_method(klass, "nofree", bug_str_nofree, 0);
}
