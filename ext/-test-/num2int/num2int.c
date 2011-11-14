#include <ruby.h>

extern VALUE rb_stdout;

static VALUE
print_num2int(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%d", NUM2INT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}

static VALUE
print_num2uint(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%u", NUM2UINT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}

static VALUE
print_num2long(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%ld", NUM2LONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}

static VALUE
print_num2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%lu", NUM2ULONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}

static VALUE
print_num2ll(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%lld", NUM2LL(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}

static VALUE
print_num2ull(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%llu", NUM2ULL(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
}


void
Init_num2int(void)
{
    VALUE cNum2int = rb_path2class("TestNum2int::Num2int");

    rb_define_singleton_method(cNum2int, "print_num2int", print_num2int, 1);
    rb_define_singleton_method(cNum2int, "print_num2uint", print_num2uint, 1);

    rb_define_singleton_method(cNum2int, "print_num2long", print_num2long, 1);
    rb_define_singleton_method(cNum2int, "print_num2ulong", print_num2ulong, 1);

    rb_define_singleton_method(cNum2int, "print_num2ll", print_num2ll, 1);
    rb_define_singleton_method(cNum2int, "print_num2ull", print_num2ull, 1);
}

