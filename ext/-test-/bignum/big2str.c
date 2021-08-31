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
big2str_generic(VALUE klass, VALUE x, VALUE vbase)
{
    int base = NUM2INT(vbase);
    if (base < 2 || 36 < base)
        rb_raise(rb_eArgError, "invalid radix %d", base);
    return rb_big2str_generic(big(x), base);
}

#define POW2_P(x) (((x)&((x)-1))==0)

static VALUE
big2str_poweroftwo(VALUE klass, VALUE x, VALUE vbase)
{
    int base = NUM2INT(vbase);
    if (base < 2 || 36 < base || !POW2_P(base))
        rb_raise(rb_eArgError, "invalid radix %d", base);
    return rb_big2str_poweroftwo(big(x), base);
}

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
static VALUE
big2str_gmp(VALUE klass, VALUE x, VALUE vbase)
{
    int base = NUM2INT(vbase);
    if (base < 2 || 36 < base)
        rb_raise(rb_eArgError, "invalid radix %d", base);
    return rb_big2str_gmp(big(x), base);
}
#else
#define big2str_gmp rb_f_notimplement
#endif

void
Init_big2str(VALUE klass)
{
    rb_define_singleton_method(klass, "big2str_generic", big2str_generic, 2);
    rb_define_singleton_method(klass, "big2str_poweroftwo", big2str_poweroftwo, 2);
    rb_define_singleton_method(klass, "big2str_gmp", big2str_gmp, 2);
}
