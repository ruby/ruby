#include <ruby.h>

extern __declspec(dllimport) void dlntest_ordinal(void);

static VALUE
dln_dlntest(VALUE self)
{
    dlntest_ordinal();
    return self;
}

void
Init_dln(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "dlntest", dln_dlntest, 0);
}
