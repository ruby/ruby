#include <ruby/ruby.h>

static void
dataerror_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

static void
dataerror_free(void *ptr)
{
}

static const rb_data_type_t dataerror_type = {
    "Bug #9167",
    {dataerror_mark, dataerror_free},
};

static VALUE
dataerror_alloc(VALUE klass)
{
    VALUE n = rb_str_new_cstr("[Bug #9167] error");
    return TypedData_Wrap_Struct(klass, &dataerror_type, (void *)n);
}

void
Init_dataerror(VALUE klass)
{
    VALUE rb_eDataErr = rb_define_class_under(klass, "DataError", rb_eStandardError);
    rb_define_alloc_func(rb_eDataErr, dataerror_alloc);
}
