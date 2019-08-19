#include "ruby.h"
#include "ruby/encoding.h"

static VALUE
bug_str_buf_new(VALUE self, VALUE len)
{
    return rb_str_buf_new(NUM2LONG(len));
}

static VALUE
bug_external_str_new(VALUE self, VALUE len, VALUE enc)
{
    return rb_external_str_new_with_enc(NULL, NUM2LONG(len), rb_to_encoding(enc));
}

void
Init_string_new(VALUE klass)
{
    rb_define_singleton_method(klass, "buf_new", bug_str_buf_new, 1);
    rb_define_singleton_method(klass, "external_new", bug_external_str_new, 2);
}
