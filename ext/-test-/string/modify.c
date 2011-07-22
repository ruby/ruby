#include "ruby.h"

VALUE
bug_str_modify(VALUE str)
{
    rb_str_modify(str);
    return str;
}

void
Init_modify(VALUE klass)
{
    rb_define_method(klass, "modify!", bug_str_modify, 0);
}
