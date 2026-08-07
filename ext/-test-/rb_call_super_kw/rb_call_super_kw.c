#include <ruby.h>

static VALUE
rb_call_super_kw_m(int argc, VALUE *argv, VALUE self)
{
    return rb_call_super_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);
}

void
Init_rb_call_super_kw(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif
    VALUE module = rb_define_module("Bug");
    module = rb_define_module_under(module, "RbCallSuperKw");
    rb_define_method(module, "m", rb_call_super_kw_m, -1);
}
