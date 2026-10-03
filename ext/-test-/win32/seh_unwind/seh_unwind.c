#include <ruby.h>

static int finally_ran;

static VALUE
raise_in_try(VALUE self)
{
    finally_ran = 0;
    __try {
        rb_raise(rb_eRuntimeError, "raised in __try");
    }
    __finally {
        finally_ran = 1;
    }
    return Qnil;
}

static VALUE
finally_ran_p(VALUE self)
{
    return finally_ran ? Qtrue : Qfalse;
}

void
Init_seh_unwind(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "raise_in_try", raise_in_try, 0);
    rb_define_module_function(m, "finally_ran?", finally_ran_p, 0);
}
