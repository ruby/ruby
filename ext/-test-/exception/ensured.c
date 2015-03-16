#include <ruby.h>

static VALUE
begin(VALUE object)
{
    return rb_funcall(object, rb_intern("try_method"), 0);
}

static VALUE
ensure(VALUE object)
{
    return rb_funcall(object, rb_intern("ensured_method"), 0);
}

static VALUE
ensured(VALUE module, VALUE object)
{
    return rb_ensure(begin, object, ensure, object);
}

void
Init_ensured(VALUE klass)
{
    rb_define_module_function(klass, "ensured", ensured, 1);
}
