#include <fiddle.h>

VALUE mFiddle;
VALUE rb_eFiddleDLError;
VALUE rb_eFiddleError;

void Init_fiddle_pointer(void);
void Init_fiddle_pinned(void);

/*
 * call-seq: Fiddle.malloc(size)
 *
 * Allocate +size+ bytes of memory and return the integer memory address
 * for the allocated memory.
 */
static VALUE
rb_fiddle_malloc(VALUE self, VALUE size)
{
    void *ptr;
    ptr = (void*)ruby_xcalloc(1, NUM2SIZET(size));
    return PTR2NUM(ptr);
}

/*
 * call-seq: Fiddle.realloc(addr, size)
 *
 * Change the size of the memory allocated at the memory location +addr+ to
 * +size+ bytes.  Returns the memory address of the reallocated memory, which
 * may be different than the address passed in.
 */
static VALUE
rb_fiddle_realloc(VALUE self, VALUE addr, VALUE size)
{
    void *ptr = NUM2PTR(addr);

    ptr = (void*)ruby_xrealloc(ptr, NUM2SIZET(size));
    return PTR2NUM(ptr);
}

/*
 * call-seq: Fiddle.free(addr)
 *
 * Free the memory at address +addr+
 */
VALUE
rb_fiddle_free(VALUE self, VALUE addr)
{
    void *ptr = NUM2PTR(addr);

    ruby_xfree(ptr);
    return Qnil;
}

/*
 * call-seq: Fiddle.dlunwrap(addr)
 *
 * Returns the hexadecimal representation of a memory pointer address +addr+
 *
 * Example:
 *
 *   lib = Fiddle.dlopen('/lib64/libc-2.15.so')
 *   => #<Fiddle::Handle:0x00000001342460>
 *
 *   lib['strcpy'].to_s(16)
 *   => "7f59de6dd240"
 *
 *   Fiddle.dlunwrap(Fiddle.dlwrap(lib['strcpy'].to_s(16)))
 *   => "7f59de6dd240"
 */
VALUE
rb_fiddle_ptr2value(VALUE self, VALUE addr)
{
    return (VALUE)NUM2PTR(addr);
}

/*
 * call-seq: Fiddle.dlwrap(val)
 *
 * Returns a memory pointer of a function's hexadecimal address location +val+
 *
 * Example:
 *
 *   lib = Fiddle.dlopen('/lib64/libc-2.15.so')
 *   => #<Fiddle::Handle:0x00000001342460>
 *
 *   Fiddle.dlwrap(lib['strcpy'].to_s(16))
 *   => 25522520
 */
static VALUE
rb_fiddle_value2ptr(VALUE self, VALUE val)
{
    return PTR2NUM((void*)val);
}

void Init_fiddle_handle(void);

void
Init_fiddle(void)
{
    /*
     * Document-module: Fiddle
     *
     * A libffi wrapper for Ruby.
     *
     * == Description
     *
     * Fiddle is an extension to translate a foreign function interface (FFI)
     * with ruby.
     *
     * It wraps {libffi}[http://sourceware.org/libffi/], a popular C library
     * which provides a portable interface that allows code written in one
     * language to call code written in another language.
     *
     * == Example
     *
     * Here we will use Fiddle::Function to wrap {floor(3) from
     * libm}[http://linux.die.net/man/3/floor]
     *
     *	    require 'fiddle'
     *
     *	    libm = Fiddle.dlopen('/lib/libm.so.6')
     *
     *	    floor = Fiddle::Function.new(
     *	      libm['floor'],
     *	      [Fiddle::TYPE_DOUBLE],
     *	      Fiddle::TYPE_DOUBLE
     *	    )
     *
     *	    puts floor.call(3.14159) #=> 3.0
     *
     *
     */
    mFiddle = rb_define_module("Fiddle");

    /*
     * Document-class: Fiddle::Error
     *
     * Generic error class for Fiddle
     */
    rb_eFiddleError = rb_define_class_under(mFiddle, "Error", rb_eStandardError);

    /*
     * Ruby installed by RubyInstaller for Windows always require
     * bundled Fiddle because ruby_installer/runtime/dll_directory.rb
     * requires Fiddle. It's used by
     * rubygems/defaults/operating_system.rb. It means that the
     * bundled Fiddle is always required on initialization.
     *
     * We just remove existing Fiddle::DLError here to override
     * the bundled Fiddle.
     */
    if (rb_const_defined(mFiddle, rb_intern("DLError"))) {
        rb_const_remove(mFiddle, rb_intern("DLError"));
    }

    /*
     * Document-class: Fiddle::DLError
     *
     * standard dynamic load exception
     */
    rb_eFiddleDLError = rb_define_class_under(mFiddle, "DLError", rb_eFiddleError);

    /* Document-const: TYPE_VOID
     *
     * C type - void
     */
    rb_define_const(mFiddle, "TYPE_VOID",      INT2NUM(TYPE_VOID));

    /* Document-const: TYPE_VOIDP
     *
     * C type - void*
     */
    rb_define_const(mFiddle, "TYPE_VOIDP",     INT2NUM(TYPE_VOIDP));

    /* Document-const: TYPE_CHAR
     *
     * C type - char
     */
    rb_define_const(mFiddle, "TYPE_CHAR",      INT2NUM(TYPE_CHAR));

    /* Document-const: TYPE_SHORT
     *
     * C type - short
     */
    rb_define_const(mFiddle, "TYPE_SHORT",     INT2NUM(TYPE_SHORT));

    /* Document-const: TYPE_INT
     *
     * C type - int
     */
    rb_define_const(mFiddle, "TYPE_INT",       INT2NUM(TYPE_INT));

    /* Document-const: TYPE_LONG
     *
     * C type - long
     */
    rb_define_const(mFiddle, "TYPE_LONG",      INT2NUM(TYPE_LONG));

#if HAVE_LONG_LONG
    /* Document-const: TYPE_LONG_LONG
     *
     * C type - long long
     */
    rb_define_const(mFiddle, "TYPE_LONG_LONG", INT2NUM(TYPE_LONG_LONG));
#endif

    /* Document-const: TYPE_FLOAT
     *
     * C type - float
     */
    rb_define_const(mFiddle, "TYPE_FLOAT",     INT2NUM(TYPE_FLOAT));

    /* Document-const: TYPE_DOUBLE
     *
     * C type - double
     */
    rb_define_const(mFiddle, "TYPE_DOUBLE",    INT2NUM(TYPE_DOUBLE));

#ifdef HAVE_FFI_PREP_CIF_VAR
    /* Document-const: TYPE_VARIADIC
     *
     * C type - ...
     */
    rb_define_const(mFiddle, "TYPE_VARIADIC",  INT2NUM(TYPE_VARIADIC));
#endif

    /* Document-const: TYPE_CONST_STRING
     *
     * C type - const char* ('\0' terminated const char*)
     */
    rb_define_const(mFiddle, "TYPE_CONST_STRING",  INT2NUM(TYPE_CONST_STRING));

    /* Document-const: TYPE_SIZE_T
     *
     * C type - size_t
     */
    rb_define_const(mFiddle, "TYPE_SIZE_T",   INT2NUM(TYPE_SIZE_T));

    /* Document-const: TYPE_SSIZE_T
     *
     * C type - ssize_t
     */
    rb_define_const(mFiddle, "TYPE_SSIZE_T",   INT2NUM(TYPE_SSIZE_T));

    /* Document-const: TYPE_PTRDIFF_T
     *
     * C type - ptrdiff_t
     */
    rb_define_const(mFiddle, "TYPE_PTRDIFF_T", INT2NUM(TYPE_PTRDIFF_T));

    /* Document-const: TYPE_INTPTR_T
     *
     * C type - intptr_t
     */
    rb_define_const(mFiddle, "TYPE_INTPTR_T",  INT2NUM(TYPE_INTPTR_T));

    /* Document-const: TYPE_UINTPTR_T
     *
     * C type - uintptr_t
     */
    rb_define_const(mFiddle, "TYPE_UINTPTR_T",  INT2NUM(TYPE_UINTPTR_T));

    /* Document-const: ALIGN_VOIDP
     *
     * The alignment size of a void*
     */
    rb_define_const(mFiddle, "ALIGN_VOIDP", INT2NUM(ALIGN_VOIDP));

    /* Document-const: ALIGN_CHAR
     *
     * The alignment size of a char
     */
    rb_define_const(mFiddle, "ALIGN_CHAR",  INT2NUM(ALIGN_CHAR));

    /* Document-const: ALIGN_SHORT
     *
     * The alignment size of a short
     */
    rb_define_const(mFiddle, "ALIGN_SHORT", INT2NUM(ALIGN_SHORT));

    /* Document-const: ALIGN_INT
     *
     * The alignment size of an int
     */
    rb_define_const(mFiddle, "ALIGN_INT",   INT2NUM(ALIGN_INT));

    /* Document-const: ALIGN_LONG
     *
     * The alignment size of a long
     */
    rb_define_const(mFiddle, "ALIGN_LONG",  INT2NUM(ALIGN_LONG));

#if HAVE_LONG_LONG
    /* Document-const: ALIGN_LONG_LONG
     *
     * The alignment size of a long long
     */
    rb_define_const(mFiddle, "ALIGN_LONG_LONG",  INT2NUM(ALIGN_LONG_LONG));
#endif

    /* Document-const: ALIGN_FLOAT
     *
     * The alignment size of a float
     */
    rb_define_const(mFiddle, "ALIGN_FLOAT", INT2NUM(ALIGN_FLOAT));

    /* Document-const: ALIGN_DOUBLE
     *
     * The alignment size of a double
     */
    rb_define_const(mFiddle, "ALIGN_DOUBLE",INT2NUM(ALIGN_DOUBLE));

    /* Document-const: ALIGN_SIZE_T
     *
     * The alignment size of a size_t
     */
    rb_define_const(mFiddle, "ALIGN_SIZE_T", INT2NUM(ALIGN_OF(size_t)));

    /* Document-const: ALIGN_SSIZE_T
     *
     * The alignment size of a ssize_t
     */
    rb_define_const(mFiddle, "ALIGN_SSIZE_T", INT2NUM(ALIGN_OF(size_t))); /* same as size_t */

    /* Document-const: ALIGN_PTRDIFF_T
     *
     * The alignment size of a ptrdiff_t
     */
    rb_define_const(mFiddle, "ALIGN_PTRDIFF_T", INT2NUM(ALIGN_OF(ptrdiff_t)));

    /* Document-const: ALIGN_INTPTR_T
     *
     * The alignment size of a intptr_t
     */
    rb_define_const(mFiddle, "ALIGN_INTPTR_T", INT2NUM(ALIGN_OF(intptr_t)));

    /* Document-const: ALIGN_UINTPTR_T
     *
     * The alignment size of a uintptr_t
     */
    rb_define_const(mFiddle, "ALIGN_UINTPTR_T", INT2NUM(ALIGN_OF(uintptr_t)));

    /* Document-const: WINDOWS
     *
     * Returns a boolean regarding whether the host is WIN32
     */
#if defined(_WIN32)
    rb_define_const(mFiddle, "WINDOWS", Qtrue);
#else
    rb_define_const(mFiddle, "WINDOWS", Qfalse);
#endif

    /* Document-const: SIZEOF_VOIDP
     *
     * size of a void*
     */
    rb_define_const(mFiddle, "SIZEOF_VOIDP", INT2NUM(sizeof(void*)));

    /* Document-const: SIZEOF_CHAR
     *
     * size of a char
     */
    rb_define_const(mFiddle, "SIZEOF_CHAR",  INT2NUM(sizeof(char)));

    /* Document-const: SIZEOF_SHORT
     *
     * size of a short
     */
    rb_define_const(mFiddle, "SIZEOF_SHORT", INT2NUM(sizeof(short)));

    /* Document-const: SIZEOF_INT
     *
     * size of an int
     */
    rb_define_const(mFiddle, "SIZEOF_INT",   INT2NUM(sizeof(int)));

    /* Document-const: SIZEOF_LONG
     *
     * size of a long
     */
    rb_define_const(mFiddle, "SIZEOF_LONG",  INT2NUM(sizeof(long)));

#if HAVE_LONG_LONG
    /* Document-const: SIZEOF_LONG_LONG
     *
     * size of a long long
     */
    rb_define_const(mFiddle, "SIZEOF_LONG_LONG",  INT2NUM(sizeof(LONG_LONG)));
#endif

    /* Document-const: SIZEOF_FLOAT
     *
     * size of a float
     */
    rb_define_const(mFiddle, "SIZEOF_FLOAT", INT2NUM(sizeof(float)));

    /* Document-const: SIZEOF_DOUBLE
     *
     * size of a double
     */
    rb_define_const(mFiddle, "SIZEOF_DOUBLE",INT2NUM(sizeof(double)));

    /* Document-const: SIZEOF_SIZE_T
     *
     * size of a size_t
     */
    rb_define_const(mFiddle, "SIZEOF_SIZE_T",  INT2NUM(sizeof(size_t)));

    /* Document-const: SIZEOF_SSIZE_T
     *
     * size of a ssize_t
     */
    rb_define_const(mFiddle, "SIZEOF_SSIZE_T",  INT2NUM(sizeof(size_t))); /* same as size_t */

    /* Document-const: SIZEOF_PTRDIFF_T
     *
     * size of a ptrdiff_t
     */
    rb_define_const(mFiddle, "SIZEOF_PTRDIFF_T",  INT2NUM(sizeof(ptrdiff_t)));

    /* Document-const: SIZEOF_INTPTR_T
     *
     * size of a intptr_t
     */
    rb_define_const(mFiddle, "SIZEOF_INTPTR_T",  INT2NUM(sizeof(intptr_t)));

    /* Document-const: SIZEOF_UINTPTR_T
     *
     * size of a uintptr_t
     */
    rb_define_const(mFiddle, "SIZEOF_UINTPTR_T",  INT2NUM(sizeof(uintptr_t)));

    /* Document-const: SIZEOF_CONST_STRING
     *
     * size of a const char*
     */
    rb_define_const(mFiddle, "SIZEOF_CONST_STRING", INT2NUM(sizeof(const char*)));

    /* Document-const: RUBY_FREE
     *
     * Address of the ruby_xfree() function
     */
    rb_define_const(mFiddle, "RUBY_FREE", PTR2NUM(ruby_xfree));

    /* Document-const: BUILD_RUBY_PLATFORM
     *
     * Platform built against (i.e. "x86_64-linux", etc.)
     *
     * See also RUBY_PLATFORM
     */
    rb_define_const(mFiddle, "BUILD_RUBY_PLATFORM", rb_str_new2(RUBY_PLATFORM));

    rb_define_module_function(mFiddle, "dlwrap", rb_fiddle_value2ptr, 1);
    rb_define_module_function(mFiddle, "dlunwrap", rb_fiddle_ptr2value, 1);
    rb_define_module_function(mFiddle, "malloc", rb_fiddle_malloc, 1);
    rb_define_module_function(mFiddle, "realloc", rb_fiddle_realloc, 2);
    rb_define_module_function(mFiddle, "free", rb_fiddle_free, 1);

    Init_fiddle_function();
    Init_fiddle_closure();
    Init_fiddle_handle();
    Init_fiddle_pointer();
    Init_fiddle_pinned();
}
/* vim: set noet sws=4 sw=4: */
