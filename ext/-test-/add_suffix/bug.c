#include "ruby.h"
#include "ruby/defines.h"
#ifndef HAVE_RUBY_ADD_SUFFIX
#define _WIN32 1
#include "util.c"
#endif

static VALUE
add_suffix(VALUE self, VALUE path, VALUE suffix)
{
    StringValueCStr(path);
    ruby_add_suffix(path, StringValueCStr(suffix));
    return path;
}

void
Init_bug(void)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "add_suffix", add_suffix, 2);
}
