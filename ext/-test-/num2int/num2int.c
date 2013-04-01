#include <ruby.h>

static VALUE
test_num2short(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%d", NUM2SHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ushort(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%u", NUM2USHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2int(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%d", NUM2INT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2uint(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%u", NUM2UINT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2long(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%ld", NUM2LONG(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%lu", NUM2ULONG(num));
    return rb_str_new_cstr(buf);
}

#ifdef HAVE_LONG_LONG
static VALUE
test_num2ll(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%"PRI_LL_PREFIX"d", NUM2LL(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ull(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%"PRI_LL_PREFIX"u", NUM2ULL(num));
    return rb_str_new_cstr(buf);
}
#endif

static VALUE
test_fix2short(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%d", FIX2SHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2int(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%d", FIX2INT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2uint(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%u", FIX2UINT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2long(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%ld", FIX2LONG(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    sprintf(buf, "%lu", FIX2ULONG(num));
    return rb_str_new_cstr(buf);
}

void
Init_num2int(void)
{
    VALUE cNum2int = rb_path2class("TestNum2int::Num2int");

    rb_define_singleton_method(cNum2int, "rb_num2short", test_num2short, 1);
    rb_define_singleton_method(cNum2int, "rb_num2ushort", test_num2ushort, 1);

    rb_define_singleton_method(cNum2int, "rb_num2int", test_num2int, 1);
    rb_define_singleton_method(cNum2int, "rb_num2uint", test_num2uint, 1);

    rb_define_singleton_method(cNum2int, "rb_num2long", test_num2long, 1);
    rb_define_singleton_method(cNum2int, "rb_num2ulong", test_num2ulong, 1);

#ifdef HAVE_LONG_LONG
    rb_define_singleton_method(cNum2int, "rb_num2ll", test_num2ll, 1);
    rb_define_singleton_method(cNum2int, "rb_num2ull", test_num2ull, 1);
#endif

    rb_define_singleton_method(cNum2int, "rb_fix2short", test_fix2short, 1);

    rb_define_singleton_method(cNum2int, "rb_fix2int", test_fix2int, 1);
    rb_define_singleton_method(cNum2int, "rb_fix2uint", test_fix2uint, 1);

    rb_define_singleton_method(cNum2int, "rb_fix2long", test_fix2long, 1);
    rb_define_singleton_method(cNum2int, "rb_fix2ulong", test_fix2ulong, 1);
}

