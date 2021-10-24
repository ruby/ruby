#include "internal/rational.h"

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
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
#endif

static VALUE
gcd_normal(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_gcd_normal(rb_to_int(x), rb_to_int(y)));
}

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
static VALUE
gcd_gmp(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_gcd_gmp(big(x), big(y)));
}
#else
#define gcd_gmp rb_f_notimplement
#endif

static VALUE
s_rational_raw(VALUE klass, VALUE x, VALUE y)
{
    return rb_rational_raw(x, y);
}

void
Init_rational(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "Rational");

    rb_define_singleton_method(klass, "gcd_normal", gcd_normal, 2);
    rb_define_singleton_method(klass, "gcd_gmp", gcd_gmp, 2);

    rb_define_singleton_method(klass, "raw", s_rational_raw, 2);
}
