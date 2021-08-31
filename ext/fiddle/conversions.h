#ifndef FIDDLE_CONVERSIONS_H
#define FIDDLE_CONVERSIONS_H

#include <fiddle.h>

typedef union
{
    ffi_arg  fffi_arg;     /* rvalue smaller than unsigned long */
    ffi_sarg fffi_sarg;    /* rvalue smaller than signed long */
    unsigned char uchar;   /* ffi_type_uchar */
    signed char   schar;   /* ffi_type_schar */
    unsigned short ushort; /* ffi_type_sshort */
    signed short sshort;   /* ffi_type_ushort */
    unsigned int uint;     /* ffi_type_uint */
    signed int sint;       /* ffi_type_sint */
    unsigned long ulong;   /* ffi_type_ulong */
    signed long slong;     /* ffi_type_slong */
    float ffloat;          /* ffi_type_float */
    double ddouble;        /* ffi_type_double */
#if HAVE_LONG_LONG
    unsigned LONG_LONG ulong_long; /* ffi_type_ulong_long */
    signed LONG_LONG slong_long; /* ffi_type_ulong_long */
#endif
    void * pointer;        /* ffi_type_pointer */
} fiddle_generic;

VALUE rb_fiddle_type_ensure(VALUE type);
ffi_type * rb_fiddle_int_to_ffi_type(int type);
void rb_fiddle_value_to_generic(int type, VALUE *src, fiddle_generic *dst);
VALUE rb_fiddle_generic_to_value(VALUE rettype, fiddle_generic retval);

/* Deprecated. Use rb_fiddle_*() version. */
ffi_type * int_to_ffi_type(int type);
void value_to_generic(int type, VALUE src, fiddle_generic *dst);
VALUE generic_to_value(VALUE rettype, fiddle_generic retval);

#define VALUE2GENERIC(_type, _src, _dst)        \
    rb_fiddle_value_to_generic((_type), &(_src), (_dst))
#define INT2FFI_TYPE(_type)                     \
    rb_fiddle_int_to_ffi_type(_type)
#define GENERIC2VALUE(_type, _retval)           \
    rb_fiddle_generic_to_value((_type), (_retval))

#if SIZEOF_VOIDP == SIZEOF_LONG
# define PTR2NUM(x)   (LONG2NUM((long)(x)))
# define NUM2PTR(x)   ((void*)(NUM2ULONG(x)))
#else
/* # error --->> Ruby/DL2 requires sizeof(void*) == sizeof(long) to be compiled. <<--- */
# define PTR2NUM(x)   (LL2NUM((LONG_LONG)(x)))
# define NUM2PTR(x)   ((void*)(NUM2ULL(x)))
#endif

#endif
