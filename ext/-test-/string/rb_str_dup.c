#include "ruby.h"

VALUE rb_str_dup(VALUE str);

static VALUE
bug_rb_str_dup(VALUE self, VALUE str)
{
    rb_check_type(str, T_STRING);
    return rb_str_dup(str);
}

static VALUE
bug_shared_string_p(VALUE self, VALUE str)
{
    rb_check_type(str, T_STRING);
    return RB_FL_TEST(str, RUBY_ELTS_SHARED) && RB_FL_TEST(str, RSTRING_NOEMBED) ? Qtrue : Qfalse;
}

static VALUE
bug_sharing_with_shared_p(VALUE self, VALUE str)
{
    rb_check_type(str, T_STRING);
    if (bug_shared_string_p(self, str)) {
        return bug_shared_string_p(self, RSTRING(str)->as.heap.aux.shared);
    }
    return Qfalse;
}

void
Init_string_rb_str_dup(VALUE klass)
{
    rb_define_singleton_method(klass, "rb_str_dup", bug_rb_str_dup, 1);
    rb_define_singleton_method(klass, "shared_string?", bug_shared_string_p, 1);
    rb_define_singleton_method(klass, "sharing_with_shared?", bug_sharing_with_shared_p, 1);
}
