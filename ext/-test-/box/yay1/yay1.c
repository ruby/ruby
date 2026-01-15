#include "yay1.h"

VALUE
yay_value(void)
{
    return rb_str_new_cstr("yay");
}

static VALUE
yay1_f_version(VALUE klass)
{
    return rb_str_new_cstr("1.0.0");
}

static VALUE
yay1_yay(VALUE klass)
{
    return yay_value();
}

void
Init_yay1(void)
{
    VALUE mod = rb_define_module("Yay");
    rb_define_const(mod, "VERSION", rb_str_new_cstr("1.0.0"));
    rb_define_singleton_method(mod, "version", yay1_f_version, 0);
    rb_define_singleton_method(mod, "yay", yay1_yay, 0);
}
