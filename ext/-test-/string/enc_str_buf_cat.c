#include "ruby/ruby.h"
#include "ruby/encoding.h"

static VALUE
enc_str_buf_cat(VALUE str, VALUE str2)
{
    return rb_enc_str_buf_cat(str, RSTRING_PTR(str2), RSTRING_LEN(str2), rb_enc_get(str2));
}

static VALUE
str_conv_enc_opts(VALUE str, VALUE from, VALUE to, VALUE ecflags, VALUE ecopts)
{
    rb_encoding *from_enc = NIL_P(from) ? NULL : rb_to_encoding(from);
    rb_encoding *to_enc = NIL_P(to) ? NULL : rb_to_encoding(to);
    int flags = NUM2INT(ecflags);
    if (!NIL_P(ecopts)) {
        Check_Type(ecopts, T_HASH);
        OBJ_FREEZE(ecopts);
    }
    return rb_str_conv_enc_opts(str, from_enc, to_enc, flags, ecopts);
}

void
Init_string_enc_str_buf_cat(VALUE klass)
{
    rb_define_method(klass, "enc_str_buf_cat", enc_str_buf_cat, 1);
    rb_define_method(klass, "str_conv_enc_opts", str_conv_enc_opts, 4);
}
