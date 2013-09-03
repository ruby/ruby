#include "ruby.h"
#include "internal.h"

static VALUE
str2big_poweroftwo(VALUE str, VALUE vbase, VALUE badcheck)
{
    return rb_str2big_poweroftwo(str, NUM2INT(vbase), RTEST(badcheck));
}

static VALUE
str2big_normal(VALUE str, VALUE vbase, VALUE badcheck)
{
    return rb_str2big_normal(str, NUM2INT(vbase), RTEST(badcheck));
}

static VALUE
str2big_karatsuba(VALUE str, VALUE vbase, VALUE badcheck)
{
    return rb_str2big_karatsuba(str, NUM2INT(vbase), RTEST(badcheck));
}

void
Init_str2big(VALUE klass)
{
    rb_define_method(rb_cString, "str2big_poweroftwo", str2big_poweroftwo, 2);
    rb_define_method(rb_cString, "str2big_normal", str2big_normal, 2);
    rb_define_method(rb_cString, "str2big_karatsuba", str2big_karatsuba, 2);
}
