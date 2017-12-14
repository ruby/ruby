#include <ruby/ruby.h>

static VALUE
class2name(VALUE self, VALUE klass)
{
    const char *name = rb_class2name(klass);
    return name ? rb_str_new_cstr(name) : Qnil;
}

void
Init_class2name(VALUE klass)
{
    rb_define_singleton_method(klass, "class2name", class2name, 1);
}
