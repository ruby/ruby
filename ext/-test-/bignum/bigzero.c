#include "internal.h"

static VALUE
bug_big_zero(VALUE self, VALUE length)
{
    long len = NUM2ULONG(length);
    VALUE z = rb_big_new(len, 1);
    MEMZERO(BIGNUM_DIGITS(z), BDIGIT, len);
    return z;
}

static VALUE
bug_big_negzero(VALUE self, VALUE length)
{
    long len = NUM2ULONG(length);
    VALUE z = rb_big_new(len, 0);
    MEMZERO(BIGNUM_DIGITS(z), BDIGIT, len);
    return z;
}

void
Init_bigzero(VALUE klass)
{
    rb_define_singleton_method(klass, "zero", bug_big_zero, 1);
    rb_define_singleton_method(klass, "negzero", bug_big_negzero, 1);
}
