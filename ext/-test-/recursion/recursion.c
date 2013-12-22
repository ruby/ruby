#include <ruby.h>

static VALUE
recursive_i(VALUE obj, VALUE mid, int recur)
{
    if (recur) return Qnil;
    return rb_funcallv(obj, rb_to_id(mid), 0, 0);
}

static VALUE
exec_recursive(VALUE self, VALUE mid)
{
    return rb_exec_recursive(recursive_i, self, mid);
}

static VALUE
exec_recursive_outer(VALUE self, VALUE mid)
{
    return rb_exec_recursive_outer(recursive_i, self, mid);
}

void
Init_recursion(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Recursive");
    rb_define_method(m, "exec_recursive", exec_recursive, 1);
    rb_define_method(m, "exec_recursive_outer", exec_recursive_outer, 1);
}
