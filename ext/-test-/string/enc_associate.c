#include "ruby.h"
#include "ruby/encoding.h"

VALUE
bug_str_enc_associate(VALUE str, VALUE enc)
{
    return rb_enc_associate(str, rb_to_encoding(enc));
}

VALUE
bug_str_encoding_index(VALUE self, VALUE str)
{
    int idx = rb_enc_get_index(str);
    return INT2NUM(idx);
}

void
Init_string_enc_associate(VALUE klass)
{
    rb_define_method(klass, "associate_encoding!", bug_str_enc_associate, 1);
    rb_define_singleton_method(klass, "encoding_index", bug_str_encoding_index, 1);
}
