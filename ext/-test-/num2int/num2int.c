#include <ruby.h>

static VALUE
test_num2short(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%d", NUM2SHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ushort(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%u", NUM2USHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2int(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%d", NUM2INT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2uint(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%u", NUM2UINT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2long(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%ld", NUM2LONG(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%lu", NUM2ULONG(num));
    return rb_str_new_cstr(buf);
}

#ifdef HAVE_LONG_LONG
static VALUE
test_num2ll(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%"PRI_LL_PREFIX"d", NUM2LL(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_num2ull(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%"PRI_LL_PREFIX"u", NUM2ULL(num));
    return rb_str_new_cstr(buf);
}
#endif

static VALUE
test_fix2short(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%d", FIX2SHORT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2int(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%d", FIX2INT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2uint(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%u", FIX2UINT(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2long(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%ld", FIX2LONG(num));
    return rb_str_new_cstr(buf);
}

static VALUE
test_fix2ulong(VALUE obj, VALUE num)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "%lu", FIX2ULONG(num));
    return rb_str_new_cstr(buf);
}

void
Init_num2int(void)
{
    VALUE mNum2int = rb_define_module("Num2int");

    rb_define_module_function(mNum2int, "NUM2SHORT", test_num2short, 1);
    rb_define_module_function(mNum2int, "NUM2USHORT", test_num2ushort, 1);

    rb_define_module_function(mNum2int, "NUM2INT", test_num2int, 1);
    rb_define_module_function(mNum2int, "NUM2UINT", test_num2uint, 1);

    rb_define_module_function(mNum2int, "NUM2LONG", test_num2long, 1);
    rb_define_module_function(mNum2int, "NUM2ULONG", test_num2ulong, 1);

#ifdef HAVE_LONG_LONG
    rb_define_module_function(mNum2int, "NUM2LL", test_num2ll, 1);
    rb_define_module_function(mNum2int, "NUM2ULL", test_num2ull, 1);
#endif

    rb_define_module_function(mNum2int, "FIX2SHORT", test_fix2short, 1);

    rb_define_module_function(mNum2int, "FIX2INT", test_fix2int, 1);
    rb_define_module_function(mNum2int, "FIX2UINT", test_fix2uint, 1);

    rb_define_module_function(mNum2int, "FIX2LONG", test_fix2long, 1);
    rb_define_module_function(mNum2int, "FIX2ULONG", test_fix2ulong, 1);
}

