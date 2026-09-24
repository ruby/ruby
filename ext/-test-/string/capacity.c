#include "ruby.h"
#include "internal/string.h"

static VALUE
bug_str_capacity(VALUE klass, VALUE str)
{
    if (!STR_EMBED_P(str) && STR_SHARED_P(str)) {
        return INT2FIX(0);
    }

    return LONG2FIX(rb_str_capacity(str));
}

static VALUE
bug_str_tmp_frozen_acquire_release(VALUE klass, VALUE str)
{
    VALUE tmp = rb_str_tmp_frozen_acquire(str);
    rb_str_tmp_frozen_release(str, tmp);
    return str;
}

void
Init_string_capacity(VALUE klass)
{
    rb_define_singleton_method(klass, "capacity", bug_str_capacity, 1);
    rb_define_singleton_method(klass, "tmp_frozen_acquire_release", bug_str_tmp_frozen_acquire_release, 1);
}
