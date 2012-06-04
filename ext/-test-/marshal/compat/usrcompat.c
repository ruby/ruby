#include <ruby.h>

static VALUE
usr_dumper(VALUE self)
{
    return self;
}

static VALUE
usr_loader(VALUE self, VALUE m)
{
    VALUE val = rb_ivar_get(m, rb_intern("@value"));
    *(int *)DATA_PTR(self) = NUM2INT(val);
    return self;
}

static VALUE
compat_mload(VALUE self, VALUE data)
{
    rb_ivar_set(self, rb_intern("@value"), data);
    return self;
}

void
Init_compat(void)
{
    VALUE newclass = rb_path2class("Bug::Marshal::UsrMarshal");
    VALUE oldclass = rb_define_class_under(newclass, "compat", rb_cObject);

    rb_define_method(oldclass, "marshal_load", compat_mload, 1);
    rb_marshal_define_compat(newclass, oldclass, usr_dumper, usr_loader);
}
