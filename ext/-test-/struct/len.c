#include "ruby.h"

static VALUE
bug_struct_len(VALUE obj)
{
    return LONG2NUM(RSTRUCT_LEN(obj));
}

void
Init_len(VALUE klass)
{
    rb_define_method(klass, "rstruct_len", bug_struct_len, 0);
}
