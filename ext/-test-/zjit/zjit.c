#include "ruby.h"

static VALUE
zjit_test_six(VALUE self, VALUE a, VALUE b, VALUE c, VALUE d, VALUE e, VALUE f)
{
    return rb_ary_new_from_args(6, a, b, c, d, e, f);
}

void
Init_zjit(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE cZJIT = rb_define_class_under(mBug, "ZJIT", rb_cObject);

    rb_define_method(cZJIT, "six", zjit_test_six, 6);
}
