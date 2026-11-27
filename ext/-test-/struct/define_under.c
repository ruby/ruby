#include "ruby.h"

static VALUE
bug_struct_define_under(VALUE obj, VALUE name, VALUE mem)
{
    return rb_struct_define_under(obj, StringValueCStr(name), StringValueCStr(mem), NULL);
}

void
Init_define_under(VALUE klass)
{
    rb_define_singleton_method(klass, "define_under", bug_struct_define_under, 2);
}
