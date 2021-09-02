#include "ruby.h"

// Bar

typedef struct {
    int dummy;
} Bar;

static rb_data_type_t Bar_type = {
    "Bar",
    {NULL, RUBY_TYPED_DEFAULT_FREE, NULL },
};

static VALUE
Bar_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &Bar_type, NULL);
}

VALUE Bar_to_ary(VALUE _self) {
    VALUE ary = rb_ary_new2(2);
    VALUE foo = rb_ary_new2(0);
    rb_ary_push(ary, foo);
    rb_ary_push(ary, foo);
    rb_ary_push(ary, foo);
    return ary;
}

void Init_to_ary_concat() {
    VALUE mBug = rb_define_module("Bug");
    VALUE bar = rb_define_class_under(mBug, "Bar", rb_cObject);
    rb_define_alloc_func(bar, Bar_alloc);
    rb_define_method(bar, "to_ary", Bar_to_ary, 0);
}
