#include "ruby.h"

static VALUE
bug_str_set_len(VALUE str, VALUE len)
{
    rb_str_set_len(str, NUM2LONG(len));
    return str;
}

static VALUE
bug_str_append(VALUE str, VALUE addendum)
{
    StringValue(addendum);
    rb_str_modify_expand(str, RSTRING_LEN(addendum));
    memcpy(RSTRING_END(str), RSTRING_PTR(addendum), RSTRING_LEN(addendum));
    return str;
}

static VALUE
bug_str_resize(VALUE str, VALUE len)
{
    rb_str_resize(str, NUM2LONG(len));
    return str;
}

void
Init_string_set_len(VALUE klass)
{
    rb_define_method(klass, "set_len", bug_str_set_len, 1);
    rb_define_method(klass, "append", bug_str_append, 1);
    rb_define_method(klass, "resize", bug_str_resize, 1);
}
