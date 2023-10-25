#include "ruby.h"

#define init(n) {void Init_econv_##n(VALUE klass); Init_econv_##n(klass);}

void
Init_econv(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "EConv", rb_path2class("Encoding::Converter"));
    TEST_INIT_FUNCS(init);
}
