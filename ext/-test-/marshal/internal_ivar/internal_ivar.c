#include <ruby.h>

static ID id_normal_ivar, id_internal_ivar, id_encoding_short;

static VALUE
init(VALUE self, VALUE arg1, VALUE arg2, VALUE arg3)
{
    rb_ivar_set(self, id_normal_ivar, arg1);
    rb_ivar_set(self, id_internal_ivar, arg2);
    rb_ivar_set(self, id_encoding_short, arg3);
    return self;
}

static VALUE
get_normal(VALUE self)
{
    return rb_attr_get(self, id_normal_ivar);
}

static VALUE
get_internal(VALUE self)
{
    return rb_attr_get(self, id_internal_ivar);
}

static VALUE
get_encoding_short(VALUE self)
{
    return rb_attr_get(self, id_encoding_short);
}

void
Init_internal_ivar(void)
{
    VALUE mMarshal = rb_define_module_under(rb_define_module("Bug"), "Marshal");
    VALUE newclass = rb_define_class_under(mMarshal, "InternalIVar", rb_cObject);

    id_normal_ivar = rb_intern_const("normal");
#if 0
    /* leave id_internal_ivar being 0 */
    id_internal_ivar = rb_make_internal_id();
#endif
    id_encoding_short = rb_intern_const("E");
    rb_define_method(newclass, "initialize", init, 3);
    rb_define_method(newclass, "normal", get_normal, 0);
    rb_define_method(newclass, "internal", get_internal, 0);
    rb_define_method(newclass, "encoding_short", get_encoding_short, 0);
}
