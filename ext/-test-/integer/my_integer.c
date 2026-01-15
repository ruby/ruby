#include "ruby.h"

static const rb_data_type_t my_integer_type = {
    "MyInteger", {0}, 0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
my_integer_s_new(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &my_integer_type, 0);
}

void
Init_my_integer(VALUE klass)
{
    VALUE cMyInteger;

    cMyInteger = rb_define_class_under(klass, "MyInteger", rb_cInteger);
    rb_define_singleton_method(cMyInteger, "new", my_integer_s_new, 0);
}
