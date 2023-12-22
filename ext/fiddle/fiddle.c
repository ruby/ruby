#include <stdbool.h>

#include <fiddle.h>

VALUE mFiddle;
VALUE rb_eFiddleDLError;
VALUE rb_eFiddleError;

void Init_fiddle_pointer(void);
void Init_fiddle_pinned(void);

#ifdef HAVE_RUBY_MEMORY_VIEW_H
void Init_fiddle_memory_view(void);
#endif

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
 * Returns the Ruby object stored at the memory address +addr+
 *
 * Example:
 *
 *    x = Object.new
 *    # => #<Object:0x0000000107c7d870>
 *    Fiddle.dlwrap(x)
 *    # => 4425504880
 *    Fiddle.dlunwrap(_)
 *    # => #<Object:0x0000000107c7d870>
 */
VALUE
rb_fiddle_ptr2value(VALUE self, VALUE addr)
{
    return (VALUE)NUM2PTR(addr);
}

/*
 * call-seq: Fiddle.dlwrap(val)
 *
 * Returns the memory address of the Ruby object stored at +val+
 *
 * Example:
 *
 *    x = Object.new
 *    # => #<Object:0x0000000107c7d870>
 *    Fiddle.dlwrap(x)
 *    # => 4425504880
 *
 * In the case +val+ is not a heap allocated object, this method will return
 * the tagged pointer value.
 *
 * Example:
 *
 *    Fiddle.dlwrap(123)
 *    # => 247
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

    VALUE mFiddleTypes = rb_define_module_under(mFiddle, "Types");

    /* Document-const: Fiddle::Types::VOID
     *
     * C type - void
     */
    rb_define_const(mFiddleTypes, "VOID",      INT2NUM(TYPE_VOID));

    /* Document-const: Fiddle::Types::VOIDP
     *
     * C type - void*
     */
    rb_define_const(mFiddleTypes, "VOIDP",     INT2NUM(TYPE_VOIDP));

    /* Document-const: Fiddle::Types::CHAR
     *
     * C type - char
     */
    rb_define_const(mFiddleTypes, "CHAR",      INT2NUM(TYPE_CHAR));

    /* Document-const: Fiddle::Types::UCHAR
     *
     * C type - unsigned char
     */
    rb_define_const(mFiddleTypes, "UCHAR",      INT2NUM(TYPE_UCHAR));

    /* Document-const: Fiddle::Types::SHORT
     *
     * C type - short
     */
    rb_define_const(mFiddleTypes, "SHORT",     INT2NUM(TYPE_SHORT));

    /* Document-const: Fiddle::Types::USHORT
     *
     * C type - unsigned short
     */
    rb_define_const(mFiddleTypes, "USHORT",     INT2NUM(TYPE_USHORT));

    /* Document-const: Fiddle::Types::INT
     *
     * C type - int
     */
    rb_define_const(mFiddleTypes, "INT",       INT2NUM(TYPE_INT));

    /* Document-const: Fiddle::Types::UINT
     *
     * C type - unsigned int
     */
    rb_define_const(mFiddleTypes, "UINT",       INT2NUM(TYPE_UINT));

    /* Document-const: Fiddle::Types::LONG
     *
     * C type - long
     */
    rb_define_const(mFiddleTypes, "LONG",      INT2NUM(TYPE_LONG));

    /* Document-const: Fiddle::Types::ULONG
     *
     * C type - long
     */
    rb_define_const(mFiddleTypes, "ULONG",      INT2NUM(TYPE_ULONG));

#if HAVE_LONG_LONG
    /* Document-const: Fiddle::Types::LONG_LONG
     *
     * C type - long long
     */
    rb_define_const(mFiddleTypes, "LONG_LONG", INT2NUM(TYPE_LONG_LONG));

    /* Document-const: Fiddle::Types::ULONG_LONG
     *
     * C type - long long
     */
    rb_define_const(mFiddleTypes, "ULONG_LONG", INT2NUM(TYPE_ULONG_LONG));
#endif

#ifdef TYPE_INT8_T
    /* Document-const: Fiddle::Types::INT8_T
     *
     * C type - int8_t
     */
    rb_define_const(mFiddleTypes, "INT8_T",    INT2NUM(TYPE_INT8_T));

    /* Document-const: Fiddle::Types::UINT8_T
     *
     * C type - uint8_t
     */
    rb_define_const(mFiddleTypes, "UINT8_T",    INT2NUM(TYPE_UINT8_T));
#endif

#ifdef TYPE_INT16_T
    /* Document-const: Fiddle::Types::INT16_T
     *
     * C type - int16_t
     */
    rb_define_const(mFiddleTypes, "INT16_T",   INT2NUM(TYPE_INT16_T));

    /* Document-const: Fiddle::Types::UINT16_T
     *
     * C type - uint16_t
     */
    rb_define_const(mFiddleTypes, "UINT16_T",   INT2NUM(TYPE_UINT16_T));
#endif

#ifdef TYPE_INT32_T
    /* Document-const: Fiddle::Types::INT32_T
     *
     * C type - int32_t
     */
    rb_define_const(mFiddleTypes, "INT32_T",   INT2NUM(TYPE_INT32_T));

    /* Document-const: Fiddle::Types::UINT32_T
     *
     * C type - uint32_t
     */
    rb_define_const(mFiddleTypes, "UINT32_T",   INT2NUM(TYPE_UINT32_T));
#endif

#ifdef TYPE_INT64_T
    /* Document-const: Fiddle::Types::INT64_T
     *
     * C type - int64_t
     */
    rb_define_const(mFiddleTypes, "INT64_T",   INT2NUM(TYPE_INT64_T));

    /* Document-const: Fiddle::Types::UINT64_T
     *
     * C type - uint64_t
     */
    rb_define_const(mFiddleTypes, "UINT64_T",   INT2NUM(TYPE_UINT64_T));
#endif

    /* Document-const: Fiddle::Types::FLOAT
     *
     * C type - float
     */
    rb_define_const(mFiddleTypes, "FLOAT",     INT2NUM(TYPE_FLOAT));

    /* Document-const: Fiddle::Types::DOUBLE
     *
     * C type - double
     */
    rb_define_const(mFiddleTypes, "DOUBLE",    INT2NUM(TYPE_DOUBLE));

#ifdef HAVE_FFI_PREP_CIF_VAR
    /* Document-const: Fiddle::Types::VARIADIC
     *
     * C type - ...
     */
    rb_define_const(mFiddleTypes, "VARIADIC",  INT2NUM(TYPE_VARIADIC));
#endif

    /* Document-const: Fiddle::Types::CONST_STRING
     *
     * C type - const char* ('\0' terminated const char*)
     */
    rb_define_const(mFiddleTypes, "CONST_STRING",  INT2NUM(TYPE_CONST_STRING));

    /* Document-const: Fiddle::Types::SIZE_T
     *
     * C type - size_t
     */
    rb_define_const(mFiddleTypes, "SIZE_T",   INT2NUM(TYPE_SIZE_T));

    /* Document-const: Fiddle::Types::SSIZE_T
     *
     * C type - ssize_t
     */
    rb_define_const(mFiddleTypes, "SSIZE_T",   INT2NUM(TYPE_SSIZE_T));

    /* Document-const: Fiddle::Types::PTRDIFF_T
     *
     * C type - ptrdiff_t
     */
    rb_define_const(mFiddleTypes, "PTRDIFF_T", INT2NUM(TYPE_PTRDIFF_T));

    /* Document-const: Fiddle::Types::INTPTR_T
     *
     * C type - intptr_t
     */
    rb_define_const(mFiddleTypes, "INTPTR_T",  INT2NUM(TYPE_INTPTR_T));

    /* Document-const: Fiddle::Types::UINTPTR_T
     *
     * C type - uintptr_t
     */
    rb_define_const(mFiddleTypes, "UINTPTR_T",  INT2NUM(TYPE_UINTPTR_T));

    /* Document-const: Fiddle::Types::BOOL
     *
     * C type - bool
     */
    rb_define_const(mFiddleTypes, "BOOL" , INT2NUM(TYPE_BOOL));

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

    /* Document-const: ALIGN_INT8_T
     *
     * The alignment size of a int8_t
     */
    rb_define_const(mFiddle, "ALIGN_INT8_T",  INT2NUM(ALIGN_INT8_T));

    /* Document-const: ALIGN_INT16_T
     *
     * The alignment size of a int16_t
     */
    rb_define_const(mFiddle, "ALIGN_INT16_T", INT2NUM(ALIGN_INT16_T));

    /* Document-const: ALIGN_INT32_T
     *
     * The alignment size of a int32_t
     */
    rb_define_const(mFiddle, "ALIGN_INT32_T", INT2NUM(ALIGN_INT32_T));

    /* Document-const: ALIGN_INT64_T
     *
     * The alignment size of a int64_t
     */
    rb_define_const(mFiddle, "ALIGN_INT64_T", INT2NUM(ALIGN_INT64_T));

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

    /* Document-const: ALIGN_BOOL
     *
     * The alignment size of a bool
     */
    rb_define_const(mFiddle, "ALIGN_BOOL", INT2NUM(ALIGN_OF(bool)));

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

    /* Document-const: SIZEOF_UCHAR
     *
     * size of a unsigned char
     */
    rb_define_const(mFiddle, "SIZEOF_UCHAR",  INT2NUM(sizeof(unsigned char)));

    /* Document-const: SIZEOF_SHORT
     *
     * size of a short
     */
    rb_define_const(mFiddle, "SIZEOF_SHORT", INT2NUM(sizeof(short)));

    /* Document-const: SIZEOF_USHORT
     *
     * size of a unsigned short
     */
    rb_define_const(mFiddle, "SIZEOF_USHORT", INT2NUM(sizeof(unsigned short)));

    /* Document-const: SIZEOF_INT
     *
     * size of an int
     */
    rb_define_const(mFiddle, "SIZEOF_INT",   INT2NUM(sizeof(int)));

    /* Document-const: SIZEOF_UINT
     *
     * size of an unsigned int
     */
    rb_define_const(mFiddle, "SIZEOF_UINT",   INT2NUM(sizeof(unsigned int)));

    /* Document-const: SIZEOF_LONG
     *
     * size of a long
     */
    rb_define_const(mFiddle, "SIZEOF_LONG",  INT2NUM(sizeof(long)));

    /* Document-const: SIZEOF_ULONG
     *
     * size of a unsigned long
     */
    rb_define_const(mFiddle, "SIZEOF_ULONG",  INT2NUM(sizeof(unsigned long)));

#if HAVE_LONG_LONG
    /* Document-const: SIZEOF_LONG_LONG
     *
     * size of a long long
     */
    rb_define_const(mFiddle, "SIZEOF_LONG_LONG",  INT2NUM(sizeof(LONG_LONG)));

    /* Document-const: SIZEOF_ULONG_LONG
     *
     * size of a unsigned long long
     */
    rb_define_const(mFiddle, "SIZEOF_ULONG_LONG",  INT2NUM(sizeof(unsigned LONG_LONG)));
#endif

    /* Document-const: SIZEOF_INT8_T
     *
     * size of a int8_t
     */
    rb_define_const(mFiddle, "SIZEOF_INT8_T",  INT2NUM(sizeof(int8_t)));

    /* Document-const: SIZEOF_UINT8_T
     *
     * size of a uint8_t
     */
    rb_define_const(mFiddle, "SIZEOF_UINT8_T",  INT2NUM(sizeof(uint8_t)));

    /* Document-const: SIZEOF_INT16_T
     *
     * size of a int16_t
     */
    rb_define_const(mFiddle, "SIZEOF_INT16_T", INT2NUM(sizeof(int16_t)));

    /* Document-const: SIZEOF_UINT16_T
     *
     * size of a uint16_t
     */
    rb_define_const(mFiddle, "SIZEOF_UINT16_T", INT2NUM(sizeof(uint16_t)));

    /* Document-const: SIZEOF_INT32_T
     *
     * size of a int32_t
     */
    rb_define_const(mFiddle, "SIZEOF_INT32_T", INT2NUM(sizeof(int32_t)));

    /* Document-const: SIZEOF_UINT32_T
     *
     * size of a uint32_t
     */
    rb_define_const(mFiddle, "SIZEOF_UINT32_T", INT2NUM(sizeof(uint32_t)));

    /* Document-const: SIZEOF_INT64_T
     *
     * size of a int64_t
     */
    rb_define_const(mFiddle, "SIZEOF_INT64_T", INT2NUM(sizeof(int64_t)));

    /* Document-const: SIZEOF_UINT64_T
     *
     * size of a uint64_t
     */
    rb_define_const(mFiddle, "SIZEOF_UINT64_T", INT2NUM(sizeof(uint64_t)));

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

    /* Document-const: SIZEOF_BOOL
     *
     * size of a bool
     */
    rb_define_const(mFiddle, "SIZEOF_BOOL", INT2NUM(sizeof(bool)));

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

    /* Document-const: Qtrue
     *
     * The value of Qtrue
     */
    rb_define_const(mFiddle, "Qtrue", INT2NUM(Qtrue));

    /* Document-const: Qfalse
     *
     * The value of Qfalse
     */
    rb_define_const(mFiddle, "Qfalse", INT2NUM(Qfalse));

    /* Document-const: Qnil
     *
     * The value of Qnil
     */
    rb_define_const(mFiddle, "Qnil", INT2NUM(Qnil));

    /* Document-const: Qundef
     *
     * The value of Qundef
     */
    rb_define_const(mFiddle, "Qundef", INT2NUM(Qundef));

    Init_fiddle_function();
    Init_fiddle_closure();
    Init_fiddle_handle();
    Init_fiddle_pointer();
    Init_fiddle_pinned();

#ifdef HAVE_RUBY_MEMORY_VIEW_H
    Init_fiddle_memory_view();
#endif
}
/* vim: set noet sws=4 sw=4: */
