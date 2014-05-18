#include "ruby.h"

static VALUE
system_nextafter_m(VALUE klass, VALUE vx, VALUE vy)
{
    double x, y, z;

    x = NUM2DBL(vx);
    y = NUM2DBL(vy);
    z = nextafter(x, y);

    return DBL2NUM(z);
}

#define nextafter missing_nextafter
#include "../../../missing/nextafter.c"
#undef nextafter

static VALUE
missing_nextafter_m(VALUE klass, VALUE vx, VALUE vy)
{
    double x, y, z;

    x = NUM2DBL(vx);
    y = NUM2DBL(vy);
    z = missing_nextafter(x, y);

    return DBL2NUM(z);
}

void
Init_nextafter(VALUE klass)
{
    rb_define_singleton_method(klass, "system_nextafter", system_nextafter_m, 2);
    rb_define_singleton_method(klass, "missing_nextafter", missing_nextafter_m, 2);
}
