#include "ruby/ruby.h"

static VALUE
asan_enabled_p(VALUE self)
{
#if defined(__has_feature)
    /* clang uses __has_feature for determining asan */
    return __has_feature(address_sanitizer) ? Qtrue : Qfalse;
#elif defined(__SANITIZE_ADDRESS__)
    /* GCC sets __SANITIZE_ADDRESS__ for determining asan */
    return Qtrue;
#else
    return Qfalse;
#endif
}

void
Init_asan(void)
{
    VALUE m = rb_define_module("Test");
    VALUE c = rb_define_class_under(m, "ASAN", rb_cObject);
    rb_define_singleton_method(c, "enabled?", asan_enabled_p, 0);
}

