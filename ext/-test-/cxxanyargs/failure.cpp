#include <ruby/ruby.h>

static VALUE
func_arg1(VALUE self, VALUE arg1)
{
    return arg1;
}

extern "C" void
Init_failure(void)
{
    rb_define_method(rb_cObject, "arg1", func_arg1, 0);
}
