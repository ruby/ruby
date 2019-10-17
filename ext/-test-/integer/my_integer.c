#include "ruby.h"

static VALUE
my_integer_s_new(VALUE klass)
{
    return Data_Wrap_Struct(klass, 0, 0, 0);
}

void
Init_my_integer(VALUE klass)
{
    VALUE cMyInteger;

    cMyInteger = rb_define_class_under(klass, "MyInteger", rb_cInteger);
    rb_define_singleton_method(cMyInteger, "new", my_integer_s_new, 0);
}
