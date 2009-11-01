#include <ruby/ruby.h>
#include <ruby/io.h>
#include <ctype.h>
#include "dl.h"

VALUE rb_mDL;
VALUE rb_eDLError;
VALUE rb_eDLTypeError;

ID rbdl_id_cdecl;
ID rbdl_id_stdcall;

VALUE
rb_dl_dlopen(int argc, VALUE argv[], VALUE self)
{
    return rb_class_new_instance(argc, argv, rb_cDLHandle);
}

/*
 * call-seq: DL.malloc
 *
 * Allocate +size+ bytes of memory and return the integer memory address
 * for the allocated memory.
 */
VALUE
rb_dl_malloc(VALUE self, VALUE size)
{
    void *ptr;

    rb_secure(4);
    ptr = (void*)ruby_xmalloc(NUM2INT(size));
    return PTR2NUM(ptr);
}

/*
 * call-seq: DL.realloc(addr, size)
 *
 * Change the size of the memory allocated at the memory location +addr+ to
 * +size+ bytes.  Returns the memory address of the reallocated memory, which
 * may be different than the address passed in.
 */
VALUE
rb_dl_realloc(VALUE self, VALUE addr, VALUE size)
{
    void *ptr = NUM2PTR(addr);

    rb_secure(4);
    ptr = (void*)ruby_xrealloc(ptr, NUM2INT(size));
    return PTR2NUM(ptr);
}

/*
 * call-seq: DL.free(addr)
 *
 * Free the memory at address +addr+
 */
VALUE
rb_dl_free(VALUE self, VALUE addr)
{
    void *ptr = NUM2PTR(addr);

    rb_secure(4);
    ruby_xfree(ptr);
    return Qnil;
}

VALUE
rb_dl_ptr2value(VALUE self, VALUE addr)
{
    rb_secure(4);
    return (VALUE)NUM2PTR(addr);
}

VALUE
rb_dl_value2ptr(VALUE self, VALUE val)
{
    return PTR2NUM((void*)val);
}

static void
rb_dl_init_callbacks(VALUE dl)
{
    static const char cb[] = "dl/callback.so";

    rb_autoload(dl, rb_intern_const("CdeclCallbackAddrs"), cb);
    rb_autoload(dl, rb_intern_const("CdeclCallbackProcs"), cb);
#ifdef FUNC_STDCALL
    rb_autoload(dl, rb_intern_const("StdcallCallbackAddrs"), cb);
    rb_autoload(dl, rb_intern_const("StdcallCallbackProcs"), cb);
#endif
}

void
Init_dl(void)
{
    void Init_dlhandle(void);
    void Init_dlcfunc(void);
    void Init_dlptr(void);

    rbdl_id_cdecl = rb_intern_const("cdecl");
    rbdl_id_stdcall = rb_intern_const("stdcall");

    rb_mDL = rb_define_module("DL");
    rb_eDLError = rb_define_class_under(rb_mDL, "DLError", rb_eStandardError);
    rb_eDLTypeError = rb_define_class_under(rb_mDL, "DLTypeError", rb_eDLError);

    rb_define_const(rb_mDL, "MAX_CALLBACK", INT2NUM(MAX_CALLBACK));
    rb_define_const(rb_mDL, "DLSTACK_SIZE", INT2NUM(DLSTACK_SIZE));

    rb_dl_init_callbacks(rb_mDL);

    rb_define_const(rb_mDL, "RTLD_GLOBAL", INT2NUM(RTLD_GLOBAL));
    rb_define_const(rb_mDL, "RTLD_LAZY",   INT2NUM(RTLD_LAZY));
    rb_define_const(rb_mDL, "RTLD_NOW",    INT2NUM(RTLD_NOW));

    rb_define_const(rb_mDL, "TYPE_VOID",  INT2NUM(DLTYPE_VOID));
    rb_define_const(rb_mDL, "TYPE_VOIDP",  INT2NUM(DLTYPE_VOIDP));
    rb_define_const(rb_mDL, "TYPE_CHAR",  INT2NUM(DLTYPE_CHAR));
    rb_define_const(rb_mDL, "TYPE_SHORT",  INT2NUM(DLTYPE_SHORT));
    rb_define_const(rb_mDL, "TYPE_INT",  INT2NUM(DLTYPE_INT));
    rb_define_const(rb_mDL, "TYPE_LONG",  INT2NUM(DLTYPE_LONG));
#if HAVE_LONG_LONG
    rb_define_const(rb_mDL, "TYPE_LONG_LONG",  INT2NUM(DLTYPE_LONG_LONG));
#endif
    rb_define_const(rb_mDL, "TYPE_FLOAT",  INT2NUM(DLTYPE_FLOAT));
    rb_define_const(rb_mDL, "TYPE_DOUBLE",  INT2NUM(DLTYPE_DOUBLE));

    rb_define_const(rb_mDL, "ALIGN_VOIDP", INT2NUM(ALIGN_VOIDP));
    rb_define_const(rb_mDL, "ALIGN_CHAR",  INT2NUM(ALIGN_CHAR));
    rb_define_const(rb_mDL, "ALIGN_SHORT", INT2NUM(ALIGN_SHORT));
    rb_define_const(rb_mDL, "ALIGN_INT",   INT2NUM(ALIGN_INT));
    rb_define_const(rb_mDL, "ALIGN_LONG",  INT2NUM(ALIGN_LONG));
#if HAVE_LONG_LONG
    rb_define_const(rb_mDL, "ALIGN_LONG_LONG",  INT2NUM(ALIGN_LONG_LONG));
#endif
    rb_define_const(rb_mDL, "ALIGN_FLOAT", INT2NUM(ALIGN_FLOAT));
    rb_define_const(rb_mDL, "ALIGN_DOUBLE",INT2NUM(ALIGN_DOUBLE));

    rb_define_const(rb_mDL, "SIZEOF_VOIDP", INT2NUM(sizeof(void*)));
    rb_define_const(rb_mDL, "SIZEOF_CHAR",  INT2NUM(sizeof(char)));
    rb_define_const(rb_mDL, "SIZEOF_SHORT", INT2NUM(sizeof(short)));
    rb_define_const(rb_mDL, "SIZEOF_INT",   INT2NUM(sizeof(int)));
    rb_define_const(rb_mDL, "SIZEOF_LONG",  INT2NUM(sizeof(long)));
#if HAVE_LONG_LONG
    rb_define_const(rb_mDL, "SIZEOF_LONG_LONG",  INT2NUM(sizeof(LONG_LONG)));
#endif
    rb_define_const(rb_mDL, "SIZEOF_FLOAT", INT2NUM(sizeof(float)));
    rb_define_const(rb_mDL, "SIZEOF_DOUBLE",INT2NUM(sizeof(double)));

    rb_define_module_function(rb_mDL, "dlwrap", rb_dl_value2ptr, 1);
    rb_define_module_function(rb_mDL, "dlunwrap", rb_dl_ptr2value, 1);

    rb_define_module_function(rb_mDL, "dlopen", rb_dl_dlopen, -1);
    rb_define_module_function(rb_mDL, "malloc", rb_dl_malloc, 1);
    rb_define_module_function(rb_mDL, "realloc", rb_dl_realloc, 2);
    rb_define_module_function(rb_mDL, "free", rb_dl_free, 1);

    rb_define_const(rb_mDL, "RUBY_FREE", PTR2NUM(ruby_xfree));
    rb_define_const(rb_mDL, "BUILD_RUBY_PLATFORM", rb_str_new2(RUBY_PLATFORM));
    rb_define_const(rb_mDL, "BUILD_RUBY_VERSION",  rb_str_new2(RUBY_VERSION));

    Init_dlhandle();
    Init_dlcfunc();
    Init_dlptr();
}
