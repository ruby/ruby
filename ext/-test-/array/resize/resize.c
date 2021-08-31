#include "ruby/ruby.h"

static VALUE
ary_resize(VALUE klass, VALUE ary, VALUE len)
{
    rb_ary_resize(ary, NUM2LONG(len));
    return ary;
}

void
Init_resize(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "Array", rb_cObject);
    rb_define_singleton_method(klass, "__resize__", ary_resize, 2);
}
