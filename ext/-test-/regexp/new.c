#include <ruby.h>

static VALUE
reg_new_binary(VALUE self, VALUE src)
{
    StringValue(src);
    return rb_reg_new(RSTRING_PTR(src), RSTRING_LEN(src), 0);
}

void
Init_new(VALUE klass)
{
    rb_define_singleton_method(klass, "new_binary", reg_new_binary, 1);
}
