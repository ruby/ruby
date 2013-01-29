#include "ruby.h"

static VALUE
obj_method_arity(VALUE self, VALUE obj, VALUE mid)
{
    int arity = rb_obj_method_arity(obj, rb_check_id(&mid));
    return INT2FIX(arity);
}

static VALUE
mod_method_arity(VALUE self, VALUE mod, VALUE mid)
{
    int arity = rb_mod_method_arity(mod, rb_check_id(&mid));
    return INT2FIX(arity);
}

void
Init_arity(VALUE mod)
{
    rb_define_module_function(mod, "obj_method_arity", obj_method_arity, 2);
    rb_define_module_function(mod, "mod_method_arity", mod_method_arity, 2);
}
