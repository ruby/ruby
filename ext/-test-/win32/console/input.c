#include <ruby.h>

static HANDLE
io_handle(VALUE io)
{
    int fd = NUM2INT(rb_funcallv(io, rb_intern("fileno"), 0, 0));
    HANDLE h = (HANDLE)rb_w32_get_osfhandle(fd);

    if (h == (HANDLE)-1) rb_raise(rb_eIOError, "invalid IO");
    return h;
}

static void
set_keyevent(INPUT_RECORD *ir, BOOL pressed, WORD vkey, WCHAR codepoint)
{
    ir->EventType = KEY_EVENT;
    ir->Event.KeyEvent.bKeyDown = pressed;
    ir->Event.KeyEvent.wRepeatCount = 1;
    ir->Event.KeyEvent.wVirtualKeyCode = vkey;
    ir->Event.KeyEvent.wVirtualScanCode = 0;
    ir->Event.KeyEvent.uChar.UnicodeChar = codepoint;
    ir->Event.KeyEvent.dwControlKeyState = 0;
}

static VALUE
write_console_input(VALUE klass, VALUE io, VALUE codepoints)
{
    HANDLE h = io_handle(io);
    INPUT_RECORD *ir;
    int i, n;
    WCHAR c;
    DWORD nwritten;

    Check_Type(codepoints, T_ARRAY);
    n = RARRAY_LEN(codepoints);
    ir = calloc(n * 2, sizeof(INPUT_RECORD));

    for (i = 0; i < n; i++) {
        c = NUM2INT(RARRAY_AREF(codepoints, i));
        if (c == '\n') c = '\r';
        set_keyevent(&ir[i*2  ], 1, 0, c);
        set_keyevent(&ir[i*2+1], 0, 0, c);
    }
    if (!WriteConsoleInputW(h, ir, n * 2, &nwritten))
        rb_syserr_fail(rb_w32_map_errno(GetLastError()), "not writable console");
    return INT2FIX(nwritten);
}

void
Init_input(VALUE m)
{
    rb_define_singleton_method(m, "write_console_input", write_console_input, 2);
}
