#include <ruby.h>

static const rb_data_type_t test_data = {
    "typed_data",
    {0, ruby_xfree, 0},
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

/*
 * Used to verify that rb_data_free does not read rb_data_type_t after dfree.
 * This intentionally frees the type descriptor from dfree so ASAN can catch
 * stale post-dfree reads.
 */
typedef struct {
    rb_data_type_t *type;
    char padding[4096];
} dynamic_type_data;

static void
dynamic_type_free(void *ptr)
{
    dynamic_type_data *data = ptr;
    xfree(data->type);
}

static VALUE
test_dynamic_type(VALUE klass)
{
    rb_data_type_t *type;
    dynamic_type_data *data;
    VALUE obj;

    type = ALLOC(rb_data_type_t);
    memset(type, 0, sizeof(rb_data_type_t));
    type->wrap_struct_name = "dynamic_typed_data";
    type->function.dfree = dynamic_type_free;
    type->flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_EMBEDDABLE;

    obj = TypedData_Make_Struct(klass, dynamic_type_data, type, data);
    data->type = type;

    return obj;
}

void
Init_typeddata(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "TypedData", rb_cObject);
    rb_define_alloc_func(klass, test_alloc);
    rb_define_singleton_method(klass, "check", test_check, 1);
    rb_define_singleton_method(klass, "make", test_make, 1);
    rb_define_singleton_method(klass, "dynamic_type", test_dynamic_type, 0);
}
