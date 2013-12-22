#include "ruby/ruby.h"
#include "ruby/io.h"

static VALUE
stat_for_fd(VALUE self, VALUE fileno)
{
    struct stat st;
    if (fstat(NUM2INT(fileno), &st)) rb_sys_fail(0);
    return rb_stat_new(&st);
}

static VALUE
stat_for_path(VALUE self, VALUE path)
{
    struct stat st;
    FilePathValue(path);
    if (stat(RSTRING_PTR(path), &st)) rb_sys_fail(0);
    return rb_stat_new(&st);
}

void
Init_stat(VALUE module)
{
    VALUE st = rb_define_module_under(module, "Stat");
    rb_define_module_function(st, "for_fd", stat_for_fd, 1);
    rb_define_module_function(st, "for_path", stat_for_path, 1);
}
