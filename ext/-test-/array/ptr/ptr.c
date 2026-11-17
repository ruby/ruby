#include "ruby/ruby.h"

static VALUE
ary_ptr_first(VALUE klass, VALUE ary)
{
    Check_Type(ary, T_ARRAY);
    if (RARRAY_LEN(ary) == 0) return Qnil;
    return RARRAY_PTR(ary)[0];
}

void
Init_ptr(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "Array", rb_cObject);
    rb_define_singleton_method(klass, "__ptr_first__", ary_ptr_first, 1);
}
