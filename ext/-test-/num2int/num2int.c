#include <ruby.h>

static VALUE
print_num2short(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%d", NUM2SHORT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2ushort(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%u", NUM2USHORT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2int(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%d", NUM2INT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2uint(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%u", NUM2UINT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2long(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%ld", NUM2LONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%lu", NUM2ULONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

#ifdef HAVE_LONG_LONG
static VALUE
print_num2ll(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%"PRI_LL_PREFIX"d", NUM2LL(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_num2ull(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%"PRI_LL_PREFIX"u", NUM2ULL(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}
#endif

static VALUE
print_fix2short(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%d", FIX2SHORT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_fix2int(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%d", FIX2INT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_fix2uint(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%u", FIX2UINT(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_fix2long(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%ld", FIX2LONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

static VALUE
print_fix2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    VALUE str;

    sprintf(buf, "%lu", FIX2ULONG(num));
    str = rb_str_new_cstr(buf);
    rb_io_write(rb_stdout, str);
    return Qnil;
}

void
Init_num2int(void)
{
    VALUE cNum2int = rb_path2class("TestNum2int::Num2int");

    rb_define_singleton_method(cNum2int, "print_num2short", print_num2short, 1);
    rb_define_singleton_method(cNum2int, "print_num2ushort", print_num2ushort, 1);

    rb_define_singleton_method(cNum2int, "print_num2int", print_num2int, 1);
    rb_define_singleton_method(cNum2int, "print_num2uint", print_num2uint, 1);

    rb_define_singleton_method(cNum2int, "print_num2long", print_num2long, 1);
    rb_define_singleton_method(cNum2int, "print_num2ulong", print_num2ulong, 1);

#ifdef HAVE_LONG_LONG
    rb_define_singleton_method(cNum2int, "print_num2ll", print_num2ll, 1);
    rb_define_singleton_method(cNum2int, "print_num2ull", print_num2ull, 1);
#endif

    rb_define_singleton_method(cNum2int, "print_fix2short", print_fix2short, 1);

    rb_define_singleton_method(cNum2int, "print_fix2int", print_fix2int, 1);
    rb_define_singleton_method(cNum2int, "print_fix2uint", print_fix2uint, 1);

    rb_define_singleton_method(cNum2int, "print_fix2long", print_fix2long, 1);
    rb_define_singleton_method(cNum2int, "print_fix2ulong", print_fix2ulong, 1);
}

