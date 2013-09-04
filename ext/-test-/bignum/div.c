#include "ruby.h"
#include "internal.h"

static VALUE
big(VALUE x)
{
    if (FIXNUM_P(x))
        return rb_int2big(FIX2LONG(x));
    if (RB_TYPE_P(x, T_BIGNUM))
        return x;
    rb_raise(rb_eTypeError, "can't convert %s to Bignum",
            rb_obj_classname(x));
}

static VALUE
divrem_normal(VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_divrem_normal(big(x), big(y)));
}

void
Init_div(VALUE klass)
{
    rb_define_method(rb_cInteger, "big_divrem_normal", divrem_normal, 1);
}
