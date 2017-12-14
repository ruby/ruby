#include <ruby.h>

static VALUE rb_cConsoleScreenBufferInfo;

static VALUE
console_info(VALUE io)
{
    int fd = NUM2INT(rb_funcallv(io, rb_intern("fileno"), 0, 0));
    HANDLE h = (HANDLE)rb_w32_get_osfhandle(fd);
    CONSOLE_SCREEN_BUFFER_INFO csbi;

    if (h == (HANDLE)-1) rb_raise(rb_eIOError, "invalid io");
    if (!GetConsoleScreenBufferInfo(h, &csbi))
	rb_syserr_fail(rb_w32_map_errno(GetLastError()), "not console");
    return rb_struct_new(rb_cConsoleScreenBufferInfo,
			 INT2FIX(csbi.dwSize.X), INT2FIX(csbi.dwSize.Y),
			 INT2FIX(csbi.dwCursorPosition.X), INT2FIX(csbi.dwCursorPosition.Y),
			 INT2FIX(csbi.wAttributes));
}

static VALUE
console_set_attribute(VALUE io, VALUE attr)
{
    int fd = NUM2INT(rb_funcallv(io, rb_intern("fileno"), 0, 0));
    HANDLE h = (HANDLE)rb_w32_get_osfhandle(fd);

    if (h == (HANDLE)-1) rb_raise(rb_eIOError, "invalid io");
    SetConsoleTextAttribute(h, (WORD)NUM2INT(attr));
    return Qnil;
}

#define FOREGROUND_MASK (FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY)
#define BACKGROUND_MASK (BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY)

void
Init_attribute(VALUE m)
{
    rb_cConsoleScreenBufferInfo = rb_struct_define_under(m, "ConsoleScreenBufferInfo",
							 "size_x", "size_y",
							 "cur_x", "cur_y",
							 "attr", NULL);
    rb_define_method(rb_cIO, "console_info", console_info, 0);
    rb_define_method(rb_cIO, "console_attribute", console_set_attribute, 1);

    rb_define_const(m, "FOREGROUND_MASK", INT2FIX(FOREGROUND_MASK));
    rb_define_const(m, "FOREGROUND_BLUE", INT2FIX(FOREGROUND_BLUE));
    rb_define_const(m, "FOREGROUND_GREEN", INT2FIX(FOREGROUND_GREEN));
    rb_define_const(m, "FOREGROUND_RED", INT2FIX(FOREGROUND_RED));
    rb_define_const(m, "FOREGROUND_INTENSITY", INT2FIX(FOREGROUND_INTENSITY));

    rb_define_const(m, "BACKGROUND_MASK", INT2FIX(BACKGROUND_MASK));
    rb_define_const(m, "BACKGROUND_BLUE", INT2FIX(BACKGROUND_BLUE));
    rb_define_const(m, "BACKGROUND_GREEN", INT2FIX(BACKGROUND_GREEN));
    rb_define_const(m, "BACKGROUND_RED", INT2FIX(BACKGROUND_RED));
    rb_define_const(m, "BACKGROUND_INTENSITY", INT2FIX(BACKGROUND_INTENSITY));
}
