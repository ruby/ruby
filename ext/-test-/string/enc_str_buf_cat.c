#include "ruby/ruby.h"
#include "ruby/encoding.h"

static VALUE
enc_str_buf_cat(VALUE str, VALUE str2)
{
    return rb_enc_str_buf_cat(str, RSTRING_PTR(str2), RSTRING_LEN(str2), rb_enc_get(str2));
}

void
Init_enc_str_buf_cat(VALUE klass)
{
    rb_define_method(klass, "enc_str_buf_cat", enc_str_buf_cat, 1);
}
