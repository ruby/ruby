#include "internal.h"

static VALUE
int_bignum_p(VALUE self)
{
    return RB_TYPE_P(self, T_BIGNUM) ? Qtrue : Qfalse;
}

static VALUE
int_fixnum_p(VALUE self)
{
    return FIXNUM_P(self) ? Qtrue : Qfalse;
}

static VALUE
rb_int_to_bignum(VALUE x)
{
    if (FIXNUM_P(x))
        x = rb_int2big(FIX2LONG(x));
    return x;
}

static VALUE
positive_pow(VALUE x, VALUE y)
{
    return rb_int_positive_pow(NUM2LONG(x), NUM2ULONG(y));
}

void
Init_core_ext(VALUE klass)
{
    rb_define_method(rb_cInteger, "bignum?", int_bignum_p, 0);
    rb_define_method(rb_cInteger, "fixnum?", int_fixnum_p, 0);
    rb_define_method(rb_cInteger, "to_bignum", rb_int_to_bignum, 0);
    rb_define_method(rb_cInteger, "positive_pow", positive_pow, 1);
}
