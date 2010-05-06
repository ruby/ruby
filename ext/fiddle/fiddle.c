#include <fiddle.h>

VALUE mFiddle;

void Init_fiddle()
{
    mFiddle = rb_define_module("Fiddle");

    rb_define_const(mFiddle, "TYPE_VOID",      INT2NUM(TYPE_VOID));
    rb_define_const(mFiddle, "TYPE_VOIDP",     INT2NUM(TYPE_VOIDP));
    rb_define_const(mFiddle, "TYPE_CHAR",      INT2NUM(TYPE_CHAR));
    rb_define_const(mFiddle, "TYPE_SHORT",     INT2NUM(TYPE_SHORT));
    rb_define_const(mFiddle, "TYPE_INT",       INT2NUM(TYPE_INT));
    rb_define_const(mFiddle, "TYPE_LONG",      INT2NUM(TYPE_LONG));
#if HAVE_LONG_LONG
    rb_define_const(mFiddle, "TYPE_LONG_LONG", INT2NUM(TYPE_LONG_LONG));
#endif
    rb_define_const(mFiddle, "TYPE_FLOAT",     INT2NUM(TYPE_FLOAT));
    rb_define_const(mFiddle, "TYPE_DOUBLE",    INT2NUM(TYPE_DOUBLE));

#if defined(HAVE_WINDOWS_H)
    rb_define_const(mFiddle, "WINDOWS", Qtrue);
#else
    rb_define_const(mFiddle, "WINDOWS", Qfalse);
#endif

    Init_fiddle_function();
    Init_fiddle_closure();
}
/* vim: set noet sws=4 sw=4: */
