#include <ruby.h>

static VALUE
handle_count(VALUE self)
{
    DWORD count;
    if (!GetProcessHandleCount(GetCurrentProcess(), &count)) rb_sys_fail("GetProcessHandleCount");
    return ULONG2NUM(count);
}

void
Init_handle_count(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "handle_count", handle_count, 0);
}
