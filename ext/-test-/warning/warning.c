#include "internal/error.h"

static VALUE
warn_to_remove(VALUE self, VALUE msg, VALUE suggest)
{
    rb_warn_to_remove_at(9.9, "%"PRIsVALUE, NIL_P(suggest) ? NULL : StringValueCStr(suggest), msg);
    return Qnil;
}

static VALUE
warn_deprecated_to_remove(VALUE self, VALUE msg, VALUE suggest)
{
    rb_warn_deprecated_to_remove_at(9.9, "%"PRIsVALUE, NIL_P(suggest) ? NULL : StringValueCStr(suggest), msg);
    return Qnil;
}

static VALUE
warn_scheduled_before(VALUE self, VALUE msg)
{
    rb_warn_scheduled_deprecation(9.8, 9.9, "%"PRIsVALUE, NULL, msg);
    return Qnil;
}

static VALUE
warn_scheduled_reached(VALUE self, VALUE msg)
{
    rb_warn_scheduled_deprecation(1.0, 9.9, "%"PRIsVALUE, NULL, msg);
    return Qnil;
}

void
Init_warning(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mod = rb_define_module_under(mBug, "Warning");
    rb_define_module_function(mod, "to_remove", warn_to_remove, 2);
    rb_define_module_function(mod, "deprecated_to_remove", warn_deprecated_to_remove, 2);
    rb_define_module_function(mod, "scheduled_before", warn_scheduled_before, 1);
    rb_define_module_function(mod, "scheduled_reached", warn_scheduled_reached, 1);
}
