#include <ruby.h>

static VALUE
enumerator_kw(int argc, VALUE *argv, VALUE self)
{
    VALUE opt, enum_args[4];
    enum_args[0] = Qnil;
    enum_args[1] = Qnil;
    rb_scan_args(argc, argv, "01*:", enum_args, enum_args+1, &opt);
    enum_args[3] = self;
    enum_args[2] = opt;
    RETURN_SIZED_ENUMERATOR_KW(self, 4, enum_args, 0, RB_NO_KEYWORDS);
    return rb_yield_values_kw(4, enum_args, RB_NO_KEYWORDS);
}

void
Init_enumerator_kw(void) {
    VALUE module = rb_define_module("Bug");
    module = rb_define_module_under(module, "EnumeratorKw");
    rb_define_method(module, "m", enumerator_kw, -1);
}
