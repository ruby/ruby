#include <ruby.h>

static const rb_data_type_t test_data = {
    "typed_data",
    {NULL, ruby_xfree, NULL},
    NULL, NULL,
    0/* deferred free */,
};

static VALUE
test_alloc(VALUE klass)
{
    char *p;
    return TypedData_Make_Struct(klass, char, &test_data, p);
}

static VALUE
test_check(VALUE self, VALUE obj)
{
    rb_check_typeddata(obj, &test_data);
    return obj;
}

static VALUE
test_make(VALUE klass, VALUE num)
{
    unsigned long i, n = NUM2UINT(num);

    for (i = 0; i < n; i++) {
	test_alloc(klass);
    }

    return Qnil;
}

void
Init_typeddata(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "TypedData", rb_cData);
    rb_define_alloc_func(klass, test_alloc);
    rb_define_singleton_method(klass, "check", test_check, 1);
    rb_define_singleton_method(klass, "make", test_make, 1);
}
