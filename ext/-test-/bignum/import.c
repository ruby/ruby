#include "ruby.h"
#include "internal.h"

static VALUE
rb_int_import_m(VALUE klass, VALUE sign, VALUE buf, VALUE wordcount, VALUE wordorder, VALUE wordsize, VALUE endian, VALUE nails)
{
    StringValue(buf);

    return rb_int_import(NUM2INT(sign), RSTRING_PTR(buf),
            NUM2SIZE(wordcount), NUM2INT(wordorder), NUM2SIZE(wordsize),
            NUM2INT(endian), NUM2SIZE(nails));
}

void
Init_import(VALUE klass)
{
    rb_define_singleton_method(rb_cInteger, "test_import", rb_int_import_m, 7);
}
