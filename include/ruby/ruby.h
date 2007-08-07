/**********************************************************************

  ruby.h -

  $Author$
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifndef RUBY_H
#define RUBY_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include "ruby/config.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#define NORETURN_STYLE_NEW 1
#ifndef NORETURN
# define NORETURN(x) x
#endif
#ifndef DEPRECATED
# define DEPRECATED(x) x
#endif
#ifndef NOINLINE
# define NOINLINE(x) x
#endif

#ifdef __GNUC__
#define PRINTF_ARGS(decl, string_index, first_to_check) \
  decl __attribute__((format(printf, string_index, first_to_check)))
#else
#define PRINTF_ARGS(decl, string_index, first_to_check) decl
#endif

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

#ifdef HAVE_INTRINSICS_H
# include <intrinsics.h>
#endif

#include <stddef.h>
#include <stdio.h>

#include "defines.h"

/* need to include <ctype.h> to use these macros */
#ifndef ISPRINT
#define ISASCII(c) isascii((int)(unsigned char)(c))
#undef ISPRINT
#define ISPRINT(c) (ISASCII(c) && isprint((int)(unsigned char)(c)))
#define ISSPACE(c) (ISASCII(c) && isspace((int)(unsigned char)(c)))
#define ISUPPER(c) (ISASCII(c) && isupper((int)(unsigned char)(c)))
#define ISLOWER(c) (ISASCII(c) && islower((int)(unsigned char)(c)))
#define ISALNUM(c) (ISASCII(c) && isalnum((int)(unsigned char)(c)))
#define ISALPHA(c) (ISASCII(c) && isalpha((int)(unsigned char)(c)))
#define ISDIGIT(c) (ISASCII(c) && isdigit((int)(unsigned char)(c)))
#define ISXDIGIT(c) (ISASCII(c) && isxdigit((int)(unsigned char)(c)))
#endif

#if defined(HAVE_ALLOCA_H)
#include <alloca.h>
#else
#  ifdef _AIX
#pragma alloca
#  endif
#endif

#if defined(__VMS)
# pragma builtins
# define alloca __alloca
#endif

#if SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long VALUE;
typedef unsigned long ID;
# define SIGNED_VALUE long
# define SIZEOF_VALUE SIZEOF_LONG
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG VALUE;
typedef unsigned LONG_LONG ID;
# define SIGNED_VALUE LONG_LONG
# define LONG_LONG_VALUE 1
# define SIZEOF_VALUE SIZEOF_LONG_LONG
#else
# error ---->> ruby requires sizeof(void*) == sizeof(long) to be compiled. <<----
#endif


#ifdef __STDC__
# include <limits.h>
#else
# ifndef LONG_MAX
#  ifdef HAVE_LIMITS_H
#   include <limits.h>
#  else
    /* assuming 32bit(2's compliment) long */
#   define LONG_MAX 2147483647
#  endif
# endif
# ifndef LONG_MIN
#  define LONG_MIN (-LONG_MAX-1)
# endif
# ifndef CHAR_BIT
#  define CHAR_BIT 8
# endif
#endif

#ifdef HAVE_LONG_LONG
# ifndef LLONG_MAX
#  ifdef LONG_LONG_MAX
#   define LLONG_MAX  LONG_LONG_MAX
#  else
#   ifdef _I64_MAX
#    define LLONG_MAX _I64_MAX
#   else
    /* assuming 64bit(2's complement) long long */
#    define LLONG_MAX 9223372036854775807LL
#   endif
#  endif
# endif
# ifndef LLONG_MIN
#  ifdef LONG_LONG_MIN
#   define LLONG_MIN  LONG_LONG_MIN
#  else
#   ifdef _I64_MIN
#    define LLONG_MIN _I64_MIN
#   else
#    define LLONG_MIN (-LLONG_MAX-1)
#   endif
#  endif
# endif
#endif

#define FIXNUM_MAX (LONG_MAX>>1)
#define FIXNUM_MIN RSHIFT((long)LONG_MIN,1)

#define INT2FIX(i) ((VALUE)(((SIGNED_VALUE)(i))<<1 | FIXNUM_FLAG))
#define LONG2FIX(i) INT2FIX(i)
#define rb_fix_new(v) INT2FIX(v)
VALUE rb_int2inum(SIGNED_VALUE);
#define INT2NUM(v) rb_int2inum(v)
#define LONG2NUM(v) INT2NUM(v)
#define rb_int_new(v) rb_int2inum(v)
VALUE rb_uint2inum(VALUE);
#define UINT2NUM(v) rb_uint2inum(v)
#define ULONG2NUM(v) UINT2NUM(v)
#define rb_uint_new(v) rb_uint2inum(v)

#ifdef HAVE_LONG_LONG
VALUE rb_ll2inum(LONG_LONG);
#define LL2NUM(v) rb_ll2inum(v)
VALUE rb_ull2inum(unsigned LONG_LONG);
#define ULL2NUM(v) rb_ull2inum(v)
#endif

#if SIZEOF_OFF_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
# define OFFT2NUM(v) LL2NUM(v)
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define OFFT2NUM(v) LONG2NUM(v)
#else
# define OFFT2NUM(v) INT2NUM(v)
#endif

#ifndef PIDT2NUM
#define PIDT2NUM(v) LONG2NUM(v)
#endif
#ifndef NUM2PIDT
#define NUM2PIDT(v) NUM2LONG(v)
#endif
#ifndef UIDT2NUM
#define UIDT2NUM(v) LONG2NUM(v)
#endif
#ifndef NUM2UIDT
#define NUM2UIDT(v) NUM2LONG(v)
#endif
#ifndef GIDT2NUM
#define GIDT2NUM(v) LONG2NUM(v)
#endif
#ifndef NUM2GIDT
#define NUM2GIDT(v) NUM2LONG(v)
#endif

#define FIX2LONG(x) RSHIFT((SIGNED_VALUE)x,1)
#define FIX2ULONG(x) ((((VALUE)(x))>>1)&LONG_MAX)
#define FIXNUM_P(f) (((SIGNED_VALUE)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

#define IMMEDIATE_P(x) ((VALUE)(x) & IMMEDIATE_MASK)

#define SYMBOL_P(x) (((VALUE)(x)&~(~(VALUE)0<<RUBY_SPECIAL_SHIFT))==SYMBOL_FLAG)
#define ID2SYM(x) (((VALUE)(x)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG)
#define SYM2ID(x) RSHIFT((unsigned long)x,RUBY_SPECIAL_SHIFT)

/* special contants - i.e. non-zero and non-fixnum constants */
enum ruby_special_consts {
    RUBY_Qfalse = 0,
    RUBY_Qtrue  = 2,
    RUBY_Qnil   = 4,
    RUBY_Qundef = 6,

    RUBY_IMMEDIATE_MASK = 0x03,
    RUBY_FIXNUM_FLAG    = 0x01,
    RUBY_SYMBOL_FLAG    = 0x0e,
    RUBY_SPECIAL_SHIFT  = 8,
};

#define Qfalse ((VALUE)RUBY_Qfalse)
#define Qtrue  ((VALUE)RUBY_Qtrue)
#define Qnil   ((VALUE)RUBY_Qnil)
#define Qundef ((VALUE)RUBY_Qundef)	/* undefined value for placeholder */
#define IMMEDIATE_MASK RUBY_IMMEDIATE_MASK
#define FIXNUM_FLAG RUBY_FIXNUM_FLAG
#define SYMBOL_FLAG RUBY_SYMBOL_FLAG

#define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
#define NIL_P(v) ((VALUE)(v) == Qnil)

#define CLASS_OF(v) rb_class_of((VALUE)(v))

enum ruby_value_type {
    RUBY_T_NONE   = 0x00,
#define T_NONE   RUBY_T_NONE

    RUBY_T_NIL    = 0x01,
#define T_NIL    RUBY_T_NIL
    RUBY_T_OBJECT = 0x02,
#define T_OBJECT RUBY_T_OBJECT
    RUBY_T_CLASS  = 0x03,
#define T_CLASS  RUBY_T_CLASS
    RUBY_T_ICLASS = 0x04,
#define T_ICLASS RUBY_T_ICLASS
    RUBY_T_MODULE = 0x05,
#define T_MODULE RUBY_T_MODULE
    RUBY_T_FLOAT  = 0x06,
#define T_FLOAT  RUBY_T_FLOAT
    RUBY_T_STRING = 0x07,
#define T_STRING RUBY_T_STRING
    RUBY_T_REGEXP = 0x08,
#define T_REGEXP RUBY_T_REGEXP
    RUBY_T_ARRAY  = 0x09,
#define T_ARRAY  RUBY_T_ARRAY
    RUBY_T_FIXNUM = 0x0a,
#define T_FIXNUM RUBY_T_FIXNUM
    RUBY_T_HASH   = 0x0b,
#define T_HASH   RUBY_T_HASH
    RUBY_T_STRUCT = 0x0c,
#define T_STRUCT RUBY_T_STRUCT
    RUBY_T_BIGNUM = 0x0d,
#define T_BIGNUM RUBY_T_BIGNUM
    RUBY_T_FILE   = 0x0e,
#define T_FILE   RUBY_T_FILE

    RUBY_T_TRUE   = 0x10,
#define T_TRUE   RUBY_T_TRUE
    RUBY_T_FALSE  = 0x11,
#define T_FALSE  RUBY_T_FALSE
    RUBY_T_DATA   = 0x12,
#define T_DATA   RUBY_T_DATA
    RUBY_T_MATCH  = 0x13,
#define T_MATCH  RUBY_T_MATCH
    RUBY_T_SYMBOL = 0x14,
#define T_SYMBOL RUBY_T_SYMBOL

    RUBY_T_VALUES = 0x1a,
#define T_VALUES RUBY_T_VALUES
    RUBY_T_BLOCK  = 0x1b,
#define T_BLOCK  RUBY_T_BLOCK
    RUBY_T_UNDEF  = 0x1c,
#define T_UNDEF  RUBY_T_UNDEF
    RUBY_T_NODE   = 0x1f,
#define T_NODE   RUBY_T_NODE

    RUBY_T_MASK   = 0x1f,
#define T_MASK   RUBY_T_MASK
};

#define BUILTIN_TYPE(x) (((struct RBasic*)(x))->flags & T_MASK)

#define TYPE(x) rb_type((VALUE)(x))

#define RB_GC_GUARD(v) (*(volatile VALUE *)&(v))

void rb_check_type(VALUE,int);
#define Check_Type(v,t) rb_check_type((VALUE)(v),t)

VALUE rb_str_to_str(VALUE);
VALUE rb_string_value(volatile VALUE*);
char *rb_string_value_ptr(volatile VALUE*);
char *rb_string_value_cstr(volatile VALUE*);

#define StringValue(v) rb_string_value(&(v))
#define StringValuePtr(v) rb_string_value_ptr(&(v))
#define StringValueCStr(v) rb_string_value_cstr(&(v))

void rb_check_safe_obj(VALUE);
void rb_check_safe_str(VALUE);
#define SafeStringValue(v) do {\
    StringValue(v);\
    rb_check_safe_obj(v);\
} while (0)
/* obsolete macro - use SafeStringValue(v) */
#define Check_SafeStr(v) rb_check_safe_str((VALUE)(v))

VALUE rb_get_path(VALUE);
#define FilePathValue(v) ((v) = rb_get_path(v))

void rb_secure(int);
int rb_safe_level(void);
void rb_set_safe_level(int);
void rb_set_safe_level_force(int);
void rb_secure_update(VALUE);

VALUE rb_errinfo(void);
void rb_set_errinfo(VALUE);

SIGNED_VALUE rb_num2long(VALUE);
VALUE rb_num2ulong(VALUE);
#define NUM2LONG(x) (FIXNUM_P(x)?FIX2LONG(x):rb_num2long((VALUE)x))
#define NUM2ULONG(x) rb_num2ulong((VALUE)x)
#if SIZEOF_INT < SIZEOF_LONG
long rb_num2int(VALUE);
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):rb_num2int((VALUE)x))
long rb_fix2int(VALUE);
#define FIX2INT(x) rb_fix2int((VALUE)x)
unsigned long rb_num2uint(VALUE);
#define NUM2UINT(x) rb_num2uint(x)
unsigned long rb_fix2uint(VALUE);
#define FIX2UINT(x) rb_fix2uint(x)
#else
#define NUM2INT(x) ((int)NUM2LONG(x))
#define NUM2UINT(x) ((unsigned int)NUM2ULONG(x))
#define FIX2INT(x) ((int)FIX2LONG(x))
#define FIX2UINT(x) ((unsigned int)FIX2ULONG(x))
#endif

#ifdef HAVE_LONG_LONG
LONG_LONG rb_num2ll(VALUE);
unsigned LONG_LONG rb_num2ull(VALUE);
# define NUM2LL(x) (FIXNUM_P(x)?FIX2LONG(x):rb_num2ll((VALUE)x))
# define NUM2ULL(x) rb_num2ull((VALUE)x)
#endif

#if defined(HAVE_LONG_LONG) && SIZEOF_OFF_T > SIZEOF_LONG
# define NUM2OFFT(x) ((off_t)NUM2LL(x))
#else
# define NUM2OFFT(x) NUM2LONG(x)
#endif

double rb_num2dbl(VALUE);
#define NUM2DBL(x) rb_num2dbl((VALUE)(x))

/* obsolete API - use StringValue() */
char *rb_str2cstr(VALUE,long*);
/* obsolete API - use StringValuePtr() */
#define STR2CSTR(x) rb_str2cstr((VALUE)(x),0)

#define NUM2CHR(x) (((TYPE(x) == T_STRING)&&(RSTRING_LEN(x)>=1))?\
                     RSTRING_PTR(x)[0]:(char)(NUM2INT(x)&0xff))
#define CHR2FIX(x) INT2FIX((long)((x)&0xff))

VALUE rb_newobj(void);
#define NEWOBJ(obj,type) type *obj = (type*)rb_newobj()
#define OBJSETUP(obj,c,t) do {\
    RBASIC(obj)->flags = (t);\
    RBASIC(obj)->klass = (c);\
    if (rb_safe_level() >= 3) FL_SET(obj, FL_TAINT);\
} while (0)
#define CLONESETUP(clone,obj) do {\
    OBJSETUP(clone,rb_singleton_class_clone((VALUE)obj),RBASIC(obj)->flags);\
    rb_singleton_class_attached(RBASIC(clone)->klass, (VALUE)clone);\
    if (FL_TEST(obj, FL_EXIVAR)) rb_copy_generic_ivar((VALUE)clone,(VALUE)obj);\
} while (0)
#define DUPSETUP(dup,obj) do {\
    OBJSETUP(dup,rb_obj_class(obj),(RBASIC(obj)->flags)&(T_MASK|FL_EXIVAR|FL_TAINT));\
    if (FL_TEST(obj, FL_EXIVAR)) rb_copy_generic_ivar((VALUE)dup,(VALUE)obj);\
} while (0)

struct RBasic {
    VALUE flags;
    VALUE klass;
};

struct RObject {
    struct RBasic basic;
    struct st_table *iv_tbl;
};

struct RValues {
    struct RBasic basic;
    VALUE v1;
    VALUE v2;
    VALUE v3;
};

struct RClass {
    struct RBasic basic;
    struct st_table *iv_tbl;
    struct st_table *m_tbl;
    VALUE super;
};

struct RFloat {
    struct RBasic basic;
    double value;
};

#define ELTS_SHARED FL_USER2

#define RSTRING_EMBED_LEN_MAX ((sizeof(VALUE)*3)/sizeof(char)-1)
struct RString {
    struct RBasic basic;
    union {
	struct {
	    long len;
	    char *ptr;
	    union {
		long capa;
		VALUE shared;
	    } aux;
	} heap;
	char ary[RSTRING_EMBED_LEN_MAX];
    } as;
};
#define RSTRING_NOEMBED FL_USER1
#define RSTRING_EMBED_LEN_MASK (FL_USER2|FL_USER3|FL_USER4|FL_USER5|FL_USER6)
#define RSTRING_EMBED_LEN_SHIFT (FL_USHIFT+2)
#define RSTRING_LEN(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     (long)((RBASIC(str)->flags >> RSTRING_EMBED_LEN_SHIFT) & \
            (RSTRING_EMBED_LEN_MASK >> RSTRING_EMBED_LEN_SHIFT)) : \
     RSTRING(str)->as.heap.len)
#define RSTRING_PTR(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     RSTRING(str)->as.ary : \
     RSTRING(str)->as.heap.ptr)

struct RArray {
    struct RBasic basic;
    long len;
    union {
	long capa;
	VALUE shared;
    } aux;
    VALUE *ptr;
};
#define RARRAY_LEN(a) RARRAY(a)->len
#define RARRAY_PTR(a) RARRAY(a)->ptr

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    long len;
    char *str;
};

struct RHash {
    struct RBasic basic;
    struct st_table *tbl;
    int iter_lev;
    VALUE ifnone;
};

struct RFile {
    struct RBasic basic;
    struct rb_io_t *fptr;
};

struct RData {
    struct RBasic basic;
    void (*dmark)(void*);
    void (*dfree)(void*);
    void *data;
};

#define DATA_PTR(dta) (RDATA(dta)->data)

/*
#define RUBY_DATA_FUNC(func) ((void (*)(void*))func)
*/
typedef void (*RUBY_DATA_FUNC)(void*);

VALUE rb_data_object_alloc(VALUE,void*,RUBY_DATA_FUNC,RUBY_DATA_FUNC);

#define Data_Wrap_Struct(klass,mark,free,sval)\
    rb_data_object_alloc(klass,sval,(RUBY_DATA_FUNC)mark,(RUBY_DATA_FUNC)free)

#define Data_Make_Struct(klass,type,mark,free,sval) (\
    sval = ALLOC(type),\
    memset(sval, 0, sizeof(type)),\
    Data_Wrap_Struct(klass,mark,free,sval)\
)

#define Data_Get_Struct(obj,type,sval) do {\
    Check_Type(obj, T_DATA); \
    sval = (type*)DATA_PTR(obj);\
} while (0)

#define RSTRUCT_EMBED_LEN_MAX 3
struct RStruct {
    struct RBasic basic;
    union {
	struct {
	    long len;
	    VALUE *ptr;
	} heap;
	VALUE ary[RSTRUCT_EMBED_LEN_MAX];
    } as;
};
#define RSTRUCT_EMBED_LEN_MASK (FL_USER2|FL_USER1)
#define RSTRUCT_EMBED_LEN_SHIFT (FL_USHIFT+1)
#define RSTRUCT_LEN(st) \
    ((RBASIC(st)->flags & RSTRUCT_EMBED_LEN_MASK) ? \
     (long)((RBASIC(st)->flags >> RSTRUCT_EMBED_LEN_SHIFT) & \
            (RSTRUCT_EMBED_LEN_MASK >> RSTRUCT_EMBED_LEN_SHIFT)) : \
     RSTRUCT(st)->as.heap.len)
#define RSTRUCT_PTR(st) \
    ((RBASIC(st)->flags & RSTRUCT_EMBED_LEN_MASK) ? \
     RSTRUCT(st)->as.ary : \
     RSTRUCT(st)->as.heap.ptr)

struct RBignum {
    struct RBasic basic;
    char sign;
    long len;
    void *digits;
};

#define R_CAST(st)   (struct st*)
#define RBASIC(obj)  (R_CAST(RBasic)(obj))
#define ROBJECT(obj) (R_CAST(RObject)(obj))
#define RCLASS(obj)  (R_CAST(RClass)(obj))
#define RMODULE(obj) RCLASS(obj)
#define RFLOAT(obj)  (R_CAST(RFloat)(obj))
#define RSTRING(obj) (R_CAST(RString)(obj))
#define RREGEXP(obj) (R_CAST(RRegexp)(obj))
#define RARRAY(obj)  (R_CAST(RArray)(obj))
#define RHASH(obj)   (R_CAST(RHash)(obj))
#define RDATA(obj)   (R_CAST(RData)(obj))
#define RSTRUCT(obj) (R_CAST(RStruct)(obj))
#define RBIGNUM(obj) (R_CAST(RBignum)(obj))
#define RFILE(obj)   (R_CAST(RFile)(obj))
#define RVALUES(obj) (R_CAST(RValues)(obj))

enum ruby_value_flags {
    RUBY_FL_MARK      = (1<<5),
#define FL_MARK      RUBY_FL_MARK
    RUBY_FL_RESERVED  = (1<<6)	/* will be used in the future GC */,
#define FL_RESERVED  RUBY_FL_RESERVED
    RUBY_FL_FINALIZE  = (1<<7),
#define FL_FINALIZE  RUBY_FL_FINALIZE
    RUBY_FL_TAINT     = (1<<8),
#define FL_TAINT     RUBY_FL_TAINT
    RUBY_FL_EXIVAR    = (1<<9),
#define FL_EXIVAR    RUBY_FL_EXIVAR
    RUBY_FL_FREEZE    = (1<<10),
#define FL_FREEZE    RUBY_FL_FREEZE
    RUBY_FL_SINGLETON = (1<<11),
#define FL_SINGLETON RUBY_FL_SINGLETON

    RUBY_FL_USHIFT    = 11,
#define FL_USHIFT    RUBY_FL_USHIFT

    RUBY_FL_USER0     = (1<<(FL_USHIFT+0)),
#define FL_USER0     RUBY_FL_USER0
    RUBY_FL_USER1     = (1<<(FL_USHIFT+1)),
#define FL_USER1     RUBY_FL_USER1
    RUBY_FL_USER2     = (1<<(FL_USHIFT+2)),
#define FL_USER2     RUBY_FL_USER2
    RUBY_FL_USER3     = (1<<(FL_USHIFT+3)),
#define FL_USER3     RUBY_FL_USER3
    RUBY_FL_USER4     = (1<<(FL_USHIFT+4)),
#define FL_USER4     RUBY_FL_USER4
    RUBY_FL_USER5     = (1<<(FL_USHIFT+5)),
#define FL_USER5     RUBY_FL_USER5
    RUBY_FL_USER6     = (1<<(FL_USHIFT+6)),
#define FL_USER6     RUBY_FL_USER6
    RUBY_FL_USER7     = (1<<(FL_USHIFT+7)),
#define FL_USER7     RUBY_FL_USER7
};

#define SPECIAL_CONST_P(x) (IMMEDIATE_P(x) || !RTEST(x))

#define FL_ABLE(x) (!SPECIAL_CONST_P(x) && BUILTIN_TYPE(x) != T_NODE)
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_ANY(x,f) FL_TEST(x,f)
#define FL_ALL(x,f) (FL_TEST(x,f) == (f))
#define FL_SET(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags |= (f);} while (0)
#define FL_UNSET(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags &= ~(f);} while (0)
#define FL_REVERSE(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags ^= (f);} while (0)

#define OBJ_TAINTED(x) FL_TEST((x), FL_TAINT)
#define OBJ_TAINT(x) FL_SET((x), FL_TAINT)
#define OBJ_INFECT(x,s) do {if (FL_ABLE(x) && FL_ABLE(s)) RBASIC(x)->flags |= RBASIC(s)->flags & FL_TAINT;} while (0)

#define OBJ_FROZEN(x) FL_TEST((x), FL_FREEZE)
#define OBJ_FREEZE(x) FL_SET((x), FL_FREEZE)

#define ALLOC_N(type,n) (type*)xmalloc2((n),sizeof(type))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc2((char*)(var),(n),sizeof(type))

#define ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(n))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), sizeof(type)*(n))

void rb_obj_infect(VALUE,VALUE);

typedef int ruby_glob_func(const char*,VALUE);
void rb_glob(const char*,void(*)(const char*,VALUE),VALUE);
int ruby_glob(const char*,int,ruby_glob_func*,VALUE);
int ruby_brace_expand(const char*,int,ruby_glob_func*,VALUE);
int ruby_brace_glob(const char*,int,ruby_glob_func*,VALUE);

VALUE rb_define_class(const char*,VALUE);
VALUE rb_define_module(const char*);
VALUE rb_define_class_under(VALUE, const char*, VALUE);
VALUE rb_define_module_under(VALUE, const char*);

void rb_include_module(VALUE,VALUE);
void rb_extend_object(VALUE,VALUE);

void rb_define_variable(const char*,VALUE*);
void rb_define_virtual_variable(const char*,VALUE(*)(ANYARGS),void(*)(ANYARGS));
void rb_define_hooked_variable(const char*,VALUE*,VALUE(*)(ANYARGS),void(*)(ANYARGS));
void rb_define_readonly_variable(const char*,VALUE*);
void rb_define_const(VALUE,const char*,VALUE);
void rb_define_global_const(const char*,VALUE);

#define RUBY_METHOD_FUNC(func) ((VALUE (*)(ANYARGS))func)
void rb_define_method(VALUE,const char*,VALUE(*)(ANYARGS),int);
void rb_define_module_function(VALUE,const char*,VALUE(*)(ANYARGS),int);
void rb_define_global_function(const char*,VALUE(*)(ANYARGS),int);

void rb_undef_method(VALUE,const char*);
void rb_define_alias(VALUE,const char*,const char*);
void rb_define_attr(VALUE,const char*,int,int);

void rb_global_variable(VALUE*);
void rb_register_mark_object(VALUE);
void rb_gc_register_address(VALUE*);
void rb_gc_unregister_address(VALUE*);

ID rb_intern(const char*);
ID rb_intern2(const char*, long);
const char *rb_id2name(ID);
ID rb_to_id(VALUE);
VALUE rb_id2str(ID);

char *rb_class2name(VALUE);
char *rb_obj_classname(VALUE);

void rb_p(VALUE);

VALUE rb_eval_string(const char*);
VALUE rb_eval_string_protect(const char*, int*);
VALUE rb_eval_string_wrap(const char*, int*);
VALUE rb_funcall(VALUE, ID, int, ...);
VALUE rb_funcall2(VALUE, ID, int, const VALUE*);
VALUE rb_funcall3(VALUE, ID, int, const VALUE*);
int rb_scan_args(int, const VALUE*, const char*, ...);
VALUE rb_call_super(int, const VALUE*);

VALUE rb_gv_set(const char*, VALUE);
VALUE rb_gv_get(const char*);
VALUE rb_iv_get(VALUE, const char*);
VALUE rb_iv_set(VALUE, const char*, VALUE);

VALUE rb_equal(VALUE,VALUE);

RUBY_EXTERN VALUE ruby_verbose, ruby_debug;

PRINTF_ARGS(NORETURN(void rb_raise(VALUE, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_fatal(const char*, ...)), 1, 2);
PRINTF_ARGS(NORETURN(void rb_bug(const char*, ...)), 1, 2);
NORETURN(void rb_sys_fail(const char*));
NORETURN(void rb_iter_break(void));
NORETURN(void rb_exit(int));
NORETURN(void rb_notimplement(void));

/* reports if `-w' specified */
PRINTF_ARGS(void rb_warning(const char*, ...), 1, 2);
PRINTF_ARGS(void rb_compile_warning(const char *, int, const char*, ...), 3, 4);
PRINTF_ARGS(void rb_sys_warning(const char*, ...), 1, 2);
/* reports always */
PRINTF_ARGS(void rb_warn(const char*, ...), 1, 2);
PRINTF_ARGS(void rb_compile_warn(const char *, int, const char*, ...), 3, 4);

VALUE rb_each(VALUE);
VALUE rb_yield(VALUE);
VALUE rb_yield_values(int n, ...);
VALUE rb_yield_splat(VALUE);
int rb_block_given_p(void);
void rb_need_block(void);
VALUE rb_iterate(VALUE(*)(VALUE),VALUE,VALUE(*)(ANYARGS),VALUE);
VALUE rb_block_call(VALUE,ID,int,VALUE*,VALUE(*)(ANYARGS),VALUE);
VALUE rb_rescue(VALUE(*)(ANYARGS),VALUE,VALUE(*)(ANYARGS),VALUE);
VALUE rb_rescue2(VALUE(*)(ANYARGS),VALUE,VALUE(*)(ANYARGS),VALUE,...);
VALUE rb_ensure(VALUE(*)(ANYARGS),VALUE,VALUE(*)(ANYARGS),VALUE);
VALUE rb_catch(const char*,VALUE(*)(ANYARGS),VALUE);
NORETURN(void rb_throw(const char*,VALUE));

VALUE rb_require(const char*);

#ifdef __ia64
void ruby_init_stack(VALUE*, void*);
#define RUBY_INIT_STACK \
    VALUE variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame, rb_ia64_bsp());
#else
void ruby_init_stack(VALUE*);
#define RUBY_INIT_STACK \
    VALUE variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame);
#endif
void ruby_init(void);
void *ruby_options(int, char**);
int ruby_run_node(void *);

RUBY_EXTERN VALUE rb_mKernel;
RUBY_EXTERN VALUE rb_mComparable;
RUBY_EXTERN VALUE rb_mEnumerable;
RUBY_EXTERN VALUE rb_mPrecision;
RUBY_EXTERN VALUE rb_mErrno;
RUBY_EXTERN VALUE rb_mFileTest;
RUBY_EXTERN VALUE rb_mGC;
RUBY_EXTERN VALUE rb_mMath;
RUBY_EXTERN VALUE rb_mProcess;

RUBY_EXTERN VALUE rb_cBasicObject;
RUBY_EXTERN VALUE rb_cObject;
RUBY_EXTERN VALUE rb_cArray;
RUBY_EXTERN VALUE rb_cBignum;
RUBY_EXTERN VALUE rb_cBinding;
RUBY_EXTERN VALUE rb_cClass;
RUBY_EXTERN VALUE rb_cCont;
RUBY_EXTERN VALUE rb_cDir;
RUBY_EXTERN VALUE rb_cData;
RUBY_EXTERN VALUE rb_cFalseClass;
RUBY_EXTERN VALUE rb_cFiber;
RUBY_EXTERN VALUE rb_cFile;
RUBY_EXTERN VALUE rb_cFixnum;
RUBY_EXTERN VALUE rb_cFloat;
RUBY_EXTERN VALUE rb_cHash;
RUBY_EXTERN VALUE rb_cInteger;
RUBY_EXTERN VALUE rb_cIO;
RUBY_EXTERN VALUE rb_cMatch;
RUBY_EXTERN VALUE rb_cMethod;
RUBY_EXTERN VALUE rb_cModule;
RUBY_EXTERN VALUE rb_cNameErrorMesg;
RUBY_EXTERN VALUE rb_cNilClass;
RUBY_EXTERN VALUE rb_cNumeric;
RUBY_EXTERN VALUE rb_cProc;
RUBY_EXTERN VALUE rb_cRange;
RUBY_EXTERN VALUE rb_cRegexp;
RUBY_EXTERN VALUE rb_cStat;
RUBY_EXTERN VALUE rb_cString;
RUBY_EXTERN VALUE rb_cStruct;
RUBY_EXTERN VALUE rb_cSymbol;
RUBY_EXTERN VALUE rb_cThread;
RUBY_EXTERN VALUE rb_cTime;
RUBY_EXTERN VALUE rb_cTrueClass;
RUBY_EXTERN VALUE rb_cUnboundMethod;
RUBY_EXTERN VALUE rb_cISeq;
RUBY_EXTERN VALUE rb_cVM;
RUBY_EXTERN VALUE rb_cEnv;

RUBY_EXTERN VALUE rb_eException;
RUBY_EXTERN VALUE rb_eStandardError;
RUBY_EXTERN VALUE rb_eSystemExit;
RUBY_EXTERN VALUE rb_eInterrupt;
RUBY_EXTERN VALUE rb_eSignal;
RUBY_EXTERN VALUE rb_eFatal;
RUBY_EXTERN VALUE rb_eArgError;
RUBY_EXTERN VALUE rb_eEOFError;
RUBY_EXTERN VALUE rb_eIndexError;
RUBY_EXTERN VALUE rb_eKeyError;
RUBY_EXTERN VALUE rb_eRangeError;
RUBY_EXTERN VALUE rb_eIOError;
RUBY_EXTERN VALUE rb_eRuntimeError;
RUBY_EXTERN VALUE rb_eSecurityError;
RUBY_EXTERN VALUE rb_eSystemCallError;
RUBY_EXTERN VALUE rb_eThreadError;
RUBY_EXTERN VALUE rb_eTypeError;
RUBY_EXTERN VALUE rb_eZeroDivError;
RUBY_EXTERN VALUE rb_eNotImpError;
RUBY_EXTERN VALUE rb_eNoMemError;
RUBY_EXTERN VALUE rb_eNoMethodError;
RUBY_EXTERN VALUE rb_eFloatDomainError;
RUBY_EXTERN VALUE rb_eLocalJumpError;
RUBY_EXTERN VALUE rb_eSysStackError;
RUBY_EXTERN VALUE rb_eRegexpError;

RUBY_EXTERN VALUE rb_eScriptError;
RUBY_EXTERN VALUE rb_eNameError;
RUBY_EXTERN VALUE rb_eSyntaxError;
RUBY_EXTERN VALUE rb_eLoadError;

RUBY_EXTERN VALUE rb_stdin, rb_stdout, rb_stderr;

static inline VALUE
rb_class_of(VALUE obj)
{
    if (IMMEDIATE_P(obj)) {
	if (FIXNUM_P(obj)) return rb_cFixnum;
	if (obj == Qtrue)  return rb_cTrueClass;
	if (SYMBOL_P(obj)) return rb_cSymbol;
    }
    else if (!RTEST(obj)) {
	if (obj == Qnil)   return rb_cNilClass;
	if (obj == Qfalse) return rb_cFalseClass;
    }
    return RBASIC(obj)->klass;
}

static inline int
rb_type(VALUE obj)
{
    if (IMMEDIATE_P(obj)) {
	if (FIXNUM_P(obj)) return T_FIXNUM;
	if (obj == Qtrue) return T_TRUE;
	if (SYMBOL_P(obj)) return T_SYMBOL;
	if (obj == Qundef) return T_UNDEF;
    }
    else if (!RTEST(obj)) {
	if (obj == Qnil) return T_NIL;
	if (obj == Qfalse) return T_FALSE;
    }
    return BUILTIN_TYPE(obj);
}

static inline int
rb_special_const_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) return Qtrue;
    return Qfalse;
}

#include "ruby/missing.h"
#include "ruby/intern.h"

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *dln_libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#define RUBY_VM 1 /* YARV */
#define HAVE_NATIVETHREAD
int is_ruby_native_thread(void);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_H */
