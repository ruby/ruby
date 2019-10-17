#include <ruby.h>

static VALUE
iter_break(VALUE self)
{
    rb_iter_break();

    UNREACHABLE_RETURN(Qnil);
}

static VALUE
iter_break_value(VALUE self, VALUE val)
{
    rb_iter_break_value(val);

    UNREACHABLE_RETURN(Qnil);
}

void
Init_break(VALUE klass)
{
    VALUE breakable = rb_define_module_under(klass, "Breakable");
    rb_define_module_function(breakable, "iter_break", iter_break, 0);
    rb_define_module_function(breakable, "iter_break_value", iter_break_value, 1);
}
