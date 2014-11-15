#include "internal.h"

#ifdef __APPLE__
static VALUE
normalize_ospath(VALUE str)
{
    return rb_str_normalize_ospath(RSTRING_PTR(str), RSTRING_LEN(str));
}
#else
#define normalize_ospath rb_f_notimplement
#endif

void
Init_normalize(VALUE klass)
{
    rb_define_method(klass, "normalize_ospath", normalize_ospath, 0);
}
