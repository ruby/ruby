#include <ruby.h>
#include <ruby/onigmo.h>

static VALUE
get_parse_depth_limit(VALUE self)
{
    unsigned int depth = onig_get_parse_depth_limit();
    return UINT2NUM(depth);
}

static VALUE
set_parse_depth_limit(VALUE self, VALUE depth)
{
    onig_set_parse_depth_limit(NUM2UINT(depth));
    return depth;
}

void
Init_parse_depth_limit(VALUE klass)
{
    rb_define_singleton_method(klass, "parse_depth_limit", get_parse_depth_limit, 0);
    rb_define_singleton_method(klass, "parse_depth_limit=", set_parse_depth_limit, 1);
}
