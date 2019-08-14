#include <ruby.h>

static size_t
usr_size(const void *ptr)
{
    return sizeof(int);
}

static const rb_data_type_t usrmarshal_type = {
    "UsrMarshal",
    {0, RUBY_DEFAULT_FREE, usr_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED,
};

static VALUE
usr_alloc(VALUE klass)
{
    int *p;
    return TypedData_Make_Struct(klass, int, &usrmarshal_type, p);
}

static VALUE
usr_init(VALUE self, VALUE val)
{
    int *ptr = Check_TypedStruct(self, &usrmarshal_type);
    *ptr = NUM2INT(val);
    return self;
}

static VALUE
usr_value(VALUE self)
{
    int *ptr = Check_TypedStruct(self, &usrmarshal_type);
    int val = *ptr;
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
