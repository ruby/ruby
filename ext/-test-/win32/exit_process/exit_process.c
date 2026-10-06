#include <ruby.h>

static DWORD WINAPI
exit_process(LPVOID status)
{
    ExitProcess((UINT)(UINT_PTR)status);
}

/* Calls ExitProcess on a thread Ruby does not know; see pipe_atexit in io.c. */
static VALUE
exit_process_from_foreign_thread(VALUE self, VALUE status)
{
    HANDLE th = CreateThread(NULL, 0, exit_process, (LPVOID)(UINT_PTR)NUM2UINT(status), 0, NULL);
    if (!th) rb_sys_fail("CreateThread");
    CloseHandle(th);
    return Qnil;
}

void
Init_exit_process(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "exit_process_from_foreign_thread", exit_process_from_foreign_thread, 1);
}
