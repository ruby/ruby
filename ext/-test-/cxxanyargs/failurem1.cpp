#include <ruby/ruby.h>

static VALUE
func_argm1(int argc, VALUE *argv, VALUE self)
{
    return argc > 0 ? argv[0] : Qnil;
}

extern "C" void
Init_failure(void)
{
    rb_define_method(rb_cObject, "argm1", func_argm1, 0);
}
