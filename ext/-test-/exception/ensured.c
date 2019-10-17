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

static VALUE
exc_raise(VALUE exc)
{
    rb_exc_raise(exc);
    return Qnil;
}

static VALUE
ensure_raise(VALUE module, VALUE object, VALUE exc)
{
    return rb_ensure(rb_yield, object, exc_raise, exc);
}

void
Init_ensured(VALUE klass)
{
    rb_define_module_function(klass, "ensured", ensured, 1);
    rb_define_module_function(klass, "ensure_raise", ensure_raise, 2);
}
