#include "ruby.h"

struct require_data {
    VALUE obj;
    VALUE fname;
};

static VALUE
call_require(VALUE arg)
{
    struct require_data *data = (struct require_data *)arg;
    rb_f_require(data->obj, data->fname);
    return Qnil;
}

static VALUE
call_ensure(VALUE _)
{
    VALUE v = rb_gv_get("$ensure_called");
    int called = FIX2INT(v) + 1;
    rb_gv_set("$ensure_called", INT2FIX(called));
    return Qnil;
}

static VALUE
require_with_ensure(VALUE self, VALUE fname)
{
    struct require_data data = {
        .obj = self,
        .fname = fname
    };
    return rb_ensure(call_require, (VALUE)&data, call_ensure, Qnil);
}

void
Init_ensure_and_callcc(void)
{
    rb_define_method(rb_mKernel, "require_with_ensure", require_with_ensure, 1);
}
