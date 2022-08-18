#include "ruby/ruby.h"
#include "ruby/encoding.h"

static VALUE
econv_append(VALUE self, VALUE src, VALUE dst)
{
    rb_econv_t *ec = DATA_PTR(self);
    return rb_econv_str_append(ec, src, dst, 0);
}

void
Init_econv_append(VALUE klass)
{
    rb_define_method(klass, "append", econv_append, 2);
}
