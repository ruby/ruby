#include <ruby.h>

static VALUE
usr_alloc(VALUE klass)
{
    int *p;
    return Data_Make_Struct(klass, int, 0, RUBY_DEFAULT_FREE, p);
}

static VALUE
usr_init(VALUE self, VALUE val)
{
    *(int *)DATA_PTR(self) = NUM2INT(val);
    return self;
}

static VALUE
usr_value(VALUE self)
{
    int val = *(int *)DATA_PTR(self);
    return INT2NUM(val);
}

void
Init_usr(void)
{
    VALUE mMarshal = rb_define_module_under(rb_define_module("Bug"), "Marshal");
    VALUE newclass = rb_define_class_under(mMarshal, "UsrMarshal", rb_cObject);

    rb_define_alloc_func(newclass, usr_alloc);
    rb_define_method(newclass, "initialize", usr_init, 1);
    rb_define_method(newclass, "value", usr_value, 0);
    rb_define_method(newclass, "marshal_load", usr_init, 1);
    rb_define_method(newclass, "marshal_dump", usr_value, 0);
}
