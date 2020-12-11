#ifndef FIDDLE_H
#define FIDDLE_H

#include <ruby.h>
#include <errno.h>

#if defined(_WIN32)
#include <windows.h>
#endif

#ifdef HAVE_SYS_MMAN_H
#include <sys/mman.h>
#endif

#if defined(HAVE_DLFCN_H)
# include <dlfcn.h>
# /* some stranger systems may not define all of these */
#ifndef RTLD_LAZY
#define RTLD_LAZY 0
#endif
#ifndef RTLD_GLOBAL
#define RTLD_GLOBAL 0
#endif
#ifndef RTLD_NOW
#define RTLD_NOW 0
#endif
#else
# if defined(_WIN32)
#   include <windows.h>
#   define dlopen(name,flag) ((void*)LoadLibrary(name))
#   define dlerror() strerror(rb_w32_map_errno(GetLastError()))
#   define dlsym(handle,name) ((void*)GetProcAddress((handle),(name)))
#   define RTLD_LAZY -1
#   define RTLD_NOW  -1
#   define RTLD_GLOBAL -1
# endif
#endif

#ifdef USE_HEADER_HACKS
#include <ffi/ffi.h>
#else
#include <ffi.h>
#endif

#undef ffi_type_uchar
#undef ffi_type_schar
#undef ffi_type_ushort
#undef ffi_type_sshort
#undef ffi_type_uint
#undef ffi_type_sint
#undef ffi_type_ulong
#undef ffi_type_slong

#if CHAR_BIT == 8
# define ffi_type_uchar ffi_type_uint8
# define ffi_type_schar ffi_type_sint8
#else
# error "CHAR_BIT not supported"
#endif

#if SIZEOF_SHORT == 2
# define ffi_type_ushort ffi_type_uint16
# define ffi_type_sshort ffi_type_sint16
#elif SIZEOF_SHORT == 4
# define ffi_type_ushort ffi_type_uint32
# define ffi_type_sshort ffi_type_sint32
#else
# error "short size not supported"
#endif

#if SIZEOF_INT == 2
# define ffi_type_uint	ffi_type_uint16
# define ffi_type_sint	ffi_type_sint16
#elif SIZEOF_INT == 4
# define ffi_type_uint	ffi_type_uint32
# define ffi_type_sint	ffi_type_sint32
#elif SIZEOF_INT == 8
# define ffi_type_uint	ffi_type_uint64
# define ffi_type_sint	ffi_type_sint64
#else
# error "int size not supported"
#endif

#if SIZEOF_LONG == 4
# define ffi_type_ulong ffi_type_uint32
# define ffi_type_slong ffi_type_sint32
#elif SIZEOF_LONG == 8
# define ffi_type_ulong ffi_type_uint64
# define ffi_type_slong ffi_type_sint64
#else
# error "long size not supported"
#endif

#if HAVE_LONG_LONG
# if SIZEOF_LONG_LONG == 8
#   define ffi_type_slong_long ffi_type_sint64
#   define ffi_type_ulong_long ffi_type_uint64
# else
#  error "long long size not supported"
# endif
#endif

#include <closure.h>
#include <conversions.h>
#include <function.h>

#define TYPE_VOID  0
#define TYPE_VOIDP 1
#define TYPE_CHAR  2
#define TYPE_SHORT 3
#define TYPE_INT   4
#define TYPE_LONG  5
#if HAVE_LONG_LONG
#define TYPE_LONG_LONG 6
#endif
#define TYPE_FLOAT 7
#define TYPE_DOUBLE 8
#define TYPE_VARIADIC 9
#define TYPE_CONST_STRING 10

#define TYPE_INT8_T TYPE_CHAR
#if SIZEOF_SHORT == 2
# define TYPE_INT16_T TYPE_SHORT
#elif SIZEOF_INT == 2
# define TYPE_INT16_T TYPE_INT
#endif
#if SIZEOF_SHORT == 4
# define TYPE_INT32_T TYPE_SHORT
#elif SIZEOF_INT == 4
# define TYPE_INT32_T TYPE_INT
#elif SIZEOF_LONG == 4
# define TYPE_INT32_T TYPE_LONG
#endif
#if SIZEOF_INT == 8
# define TYPE_INT64_T TYPE_INT
#elif SIZEOF_LONG == 8
# define TYPE_INT64_T TYPE_LONG
#elif defined(TYPE_LONG_LONG)
# define TYPE_INT64_T TYPE_LONG_LONG
#endif

#ifndef TYPE_SSIZE_T
# if SIZEOF_SIZE_T == SIZEOF_INT
#   define TYPE_SSIZE_T TYPE_INT
# elif SIZEOF_SIZE_T == SIZEOF_LONG
#   define TYPE_SSIZE_T TYPE_LONG
# elif defined HAVE_LONG_LONG && SIZEOF_SIZE_T == SIZEOF_LONG_LONG
#   define TYPE_SSIZE_T TYPE_LONG_LONG
# endif
#endif
#define TYPE_SIZE_T (-1*SIGNEDNESS_OF_SIZE_T*TYPE_SSIZE_T)

#ifndef TYPE_PTRDIFF_T
# if SIZEOF_PTRDIFF_T == SIZEOF_INT
#   define TYPE_PTRDIFF_T TYPE_INT
# elif SIZEOF_PTRDIFF_T == SIZEOF_LONG
#   define TYPE_PTRDIFF_T TYPE_LONG
# elif defined HAVE_LONG_LONG && SIZEOF_PTRDIFF_T == SIZEOF_LONG_LONG
#   define TYPE_PTRDIFF_T TYPE_LONG_LONG
# endif
#endif

#ifndef TYPE_INTPTR_T
# if SIZEOF_INTPTR_T == SIZEOF_INT
#   define TYPE_INTPTR_T TYPE_INT
# elif SIZEOF_INTPTR_T == SIZEOF_LONG
#   define TYPE_INTPTR_T TYPE_LONG
# elif defined HAVE_LONG_LONG && SIZEOF_INTPTR_T == SIZEOF_LONG_LONG
#   define TYPE_INTPTR_T TYPE_LONG_LONG
# endif
#endif
#define TYPE_UINTPTR_T (-TYPE_INTPTR_T)

#define ALIGN_OF(type) offsetof(struct {char align_c; type align_x;}, align_x)

#define ALIGN_VOIDP  ALIGN_OF(void*)
#define ALIGN_CHAR   ALIGN_OF(char)
#define ALIGN_SHORT  ALIGN_OF(short)
#define ALIGN_INT    ALIGN_OF(int)
#define ALIGN_LONG   ALIGN_OF(long)
#if HAVE_LONG_LONG
#define ALIGN_LONG_LONG ALIGN_OF(LONG_LONG)
#endif
#define ALIGN_FLOAT  ALIGN_OF(float)
#define ALIGN_DOUBLE ALIGN_OF(double)

#define ALIGN_INT8_T  ALIGN_OF(int8_t)
#define ALIGN_INT16_T ALIGN_OF(int16_t)
#define ALIGN_INT32_T ALIGN_OF(int32_t)
#define ALIGN_INT64_T ALIGN_OF(int64_t)

#ifdef HAVE_TYPE_RB_MEMORY_VIEW_T
# define FIDDLE_MEMORY_VIEW
#endif

extern VALUE mFiddle;
extern VALUE rb_eFiddleDLError;

VALUE rb_fiddle_new_function(VALUE address, VALUE arg_types, VALUE ret_type);

#endif
/* vim: set noet sws=4 sw=4: */
