#include "big.h"

static VALUE
divrem_normal(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_divrem_normal(big(x), big(y)));
}

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
static VALUE
divrem_gmp(VALUE klass, VALUE x, VALUE y)
{
    return rb_big_norm(rb_big_divrem_gmp(big(x), big(y)));
}
#else
#define divrem_gmp rb_f_notimplement
#endif

void
Init_div(VALUE klass)
{
    rb_define_singleton_method(klass, "big_divrem_normal", divrem_normal, 2);
    rb_define_singleton_method(klass, "big_divrem_gmp", divrem_gmp, 2);
}
