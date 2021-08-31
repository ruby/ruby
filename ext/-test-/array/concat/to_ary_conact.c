#include "ruby.h"

VALUE cFoo;

// Foo

typedef struct {
    int dummy;
} Foo;

static void Foo_free(void* _self) {
    xfree(_self);
}

static rb_data_type_t Foo_type = {
    "Foo",
    {NULL, Foo_free, NULL },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Foo_alloc(VALUE klass) {
    Foo* _self = ALLOC(Foo);
    return TypedData_Wrap_Struct(klass, &Foo_type, _self);
}

// Bar

typedef struct {
    int dummy;
} Bar;

static void Bar_free(void* _self) {
    xfree(_self);
}

static rb_data_type_t Bar_type = {
    "Bar",
    {NULL, Bar_free, NULL },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Bar_alloc(VALUE klass) {
    Bar* bar = ALLOC(Bar);
    return TypedData_Wrap_Struct(klass, &Bar_type, bar);
}

VALUE Bar_to_ary(VALUE _self) {
    VALUE ary = rb_ary_new2(2);
    rb_ary_push(ary, Foo_alloc(cFoo));
    rb_ary_push(ary, Foo_alloc(cFoo));
    rb_ary_push(ary, Foo_alloc(cFoo));
    return ary;
}

void Init_to_ary_concat() {
    VALUE mBug = rb_define_module("Bug");
    cFoo = rb_define_class_under(mBug, "Foo", rb_cObject);
    rb_gc_register_address(&cFoo);
    rb_define_alloc_func(cFoo, Foo_alloc);

    VALUE bar = rb_define_class_under(mBug, "Bar", rb_cObject);
    rb_define_alloc_func(bar, Bar_alloc);
    rb_define_method(bar, "to_ary", Bar_to_ary, 0);
}
