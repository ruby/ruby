#include "internal/bignum.h"

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
mul_normal(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_mul_normal(big(x), big(y)));
}

static VALUE
sq_fast(VALUE klass, VALUE x)
{
    return rb_big_norm(rb_big_sq_fast(big(x)));
}

static VALUE
mul_balance(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_mul_balance(big(x), big(y)));
}

static VALUE
mul_karatsuba(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_mul_karatsuba(big(x), big(y)));
}

static VALUE
mul_toom3(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_mul_toom3(big(x), big(y)));
}

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
static VALUE
mul_gmp(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_mul_gmp(big(x), big(y)));
}
#else
#define mul_gmp rb_f_notimplement
#endif

void
Init_mul(VALUE klass)
{
    rb_define_const(klass, "SIZEOF_BDIGIT", INT2NUM(SIZEOF_BDIGIT));
    rb_define_const(klass, "BITSPERDIG", INT2NUM(SIZEOF_BDIGIT * CHAR_BIT));
    rb_define_singleton_method(klass, "big_mul_normal", mul_normal, 2);
    rb_define_singleton_method(klass, "big_sq_fast", sq_fast, 1);
    rb_define_singleton_method(klass, "big_mul_balance", mul_balance, 2);
    rb_define_singleton_method(klass, "big_mul_karatsuba", mul_karatsuba, 2);
    rb_define_singleton_method(klass, "big_mul_toom3", mul_toom3, 2);
    rb_define_singleton_method(klass, "big_mul_gmp", mul_gmp, 2);
}
