#include "yay2.h"

VALUE
yay_value(void)
{
    return rb_str_new_cstr("yaaay");
}

static VALUE
yay2_f_version(VALUE klass)
{
    return rb_str_new_cstr("2.0.0");
}

static VALUE
yay2_yay(VALUE klass)
{
    return yay_value();
}

void
Init_yay2(void)
{
    VALUE mod = rb_define_module("Yay");
    rb_define_const(mod, "VERSION", rb_str_new_cstr("2.0.0"));
    rb_define_singleton_method(mod, "version", yay2_f_version, 0);
    rb_define_singleton_method(mod, "yay", yay2_yay, 0);
}
