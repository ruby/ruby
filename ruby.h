/************************************************

  ruby.h -

  $Author$
  $Date$
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

*************************************************/

#ifndef RUBY_H
#define RUBY_H

#include "config.h"

#include "defines.h"

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

#ifndef __STDC__
# define volatile
# ifdef __GNUC__
#  define const __const__
# else
#  define const
# endif
# define _(args) ()
#else
# define _(args) args
#endif

#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

#ifdef _AIX
#pragma alloca
#endif

typedef unsigned short USHORT;
typedef unsigned long UINT;

#if SIZEOF_INT == SIZEOF_VOIDP
typedef int INT;
#elif SIZEOF_LONG == SIZEOF_VOIDP
typedef long INT;
#else
---->> ruby requires sizeof(void*) == sizeof(int/long) to be compiled. <<----
#endif
typedef UINT VALUE;
typedef unsigned int ID;

typedef unsigned char UCHAR;

#ifdef __STDC__
# include <limits.h>
#else
# ifndef LONG_MAX
#  ifdef HAVE_LIMITS_H
#   include <limits.h>
#  else
#   define LONG_MAX 2147483647	/* assuming 32bit(2's compliment) LONG */
#  endif
# endif
# ifndef LONG_MIN
#  if (0 != ~0)
#   define LONG_MIN (-LONG_MAX-1)
#  else
#   define LONG_MIN (-LONG_MAX)
#  endif
# endif
# ifndef CHAR_BIT
#  define CHAR_BIT 8
# endif
#endif

#define FIXNUM_MAX (LONG_MAX>>1)
#define FIXNUM_MIN RSHIFT((INT)LONG_MIN,1)

#define FIXNUM_FLAG 0x01
#define INT2FIX(i) (VALUE)(((INT)(i))<<1 | FIXNUM_FLAG)
VALUE int2inum _((INT));
#define INT2NUM(v) int2inum(v)

#if (-1==(((-1)<<1)&FIXNUM_FLAG)>>1)
# define RSHIFT(x,y) ((x)>>y)
#else
# define RSHIFT(x,y) (((x)<0) ? ~((~(x))>>y) : (x)>>y)
#endif
#define FIX2INT(x) RSHIFT((INT)x,1)

#define FIX2UINT(f) (((UINT)(f))>>1)
#define FIXNUM_P(f) (((long)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

/* special contants - i.e. non-zero and non-fixnum constants */
#undef FALSE 
#undef TRUE
#define FALSE  0
#define TRUE   2
#define NIL    4
#define Qfalse 0
#define Qtrue  2
#define Qnil   4

# define RTEST(v) rb_test_false_or_nil((VALUE)(v))
#define NIL_P(v) ((VALUE)(v) == Qnil)

extern VALUE cObject;

VALUE rb_class_of _((VALUE));
#define CLASS_OF(v) rb_class_of((VALUE)(v))

#define T_NIL    0x00
#define T_OBJECT 0x01
#define T_CLASS  0x02
#define T_ICLASS 0x03
#define T_MODULE 0x04
#define T_FLOAT  0x05
#define T_STRING 0x06
#define T_REGEXP 0x07
#define T_ARRAY  0x08
#define T_FIXNUM 0x09
#define T_HASH   0x0a
#define T_STRUCT 0x0b
#define T_BIGNUM 0x0c
#define T_FILE   0x0d

#define T_TRUE   0x20
#define T_FALSE  0x21
#define T_DATA   0x22
#define T_MATCH  0x23

#define T_VARMAP 0xfd
#define T_SCOPE  0xfe
#define T_NODE   0xff

#define T_MASK   0xff

#define BUILTIN_TYPE(x) (((struct RBasic*)(x))->flags & T_MASK)

#define TYPE(x) rb_type((VALUE)(x))

void rb_check_type _((VALUE,int));
#define Check_Type(v,t) rb_check_type((VALUE)(v),t)
void rb_check_safe_str _((VALUE));
#define Check_SafeStr(v) rb_check_safe_str((VALUE)(v))
void rb_secure _((int));

int   num2int _((VALUE));
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):num2int(x))

double num2dbl _((VALUE));
#define NUM2DBL(x) num2dbl((VALUE)(x))

char *str2cstr _((VALUE));
#define STR2CSTR(x) str2cstr((VALUE)(x))

VALUE rb_newobj _((void));
#define NEWOBJ(obj,type) type *obj = (type*)rb_newobj()
#define OBJSETUP(obj,c,t) {\
    RBASIC(obj)->klass = (c);\
    RBASIC(obj)->flags = (t);\
}
#define CLONESETUP(clone,obj) {\
    OBJSETUP(clone,singleton_class_clone(RBASIC(obj)->klass),RBASIC(obj)->flags);\
    singleton_class_attached(RBASIC(clone)->klass, (VALUE)clone);\
}

struct RBasic {
    UINT flags;
    VALUE klass;
};

struct RObject {
    struct RBasic basic;
    struct st_table *iv_tbl;
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

struct RString {
    struct RBasic basic;
    UINT len;
    UCHAR *ptr;
    VALUE orig;
};

struct RArray {
    struct RBasic basic;
    UINT len, capa;
    VALUE *ptr;
};

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    UINT len;
    UCHAR *str;
};

struct RHash {
    struct RBasic basic;
    struct st_table *tbl;
    int iter_lev;
    UINT status;
};

struct RFile {
    struct RBasic basic;
    struct OpenFile *fptr;
};

struct RData {
    struct RBasic basic;
    void (*dmark)();
    void (*dfree)();
    void *data;
};

#define DATA_PTR(dta) (RDATA(dta)->data)

VALUE data_object_alloc _((VALUE,void*,void (*)(),void (*)()));
#define Data_Make_Struct(klass,type,mark,free,sval) (\
    sval = ALLOC(type),\
    memset(sval, 0, sizeof(type)),\
    data_object_alloc(klass,sval,mark,free)\
)

#define Data_Wrap_Struct(klass,mark,free,sval) (\
    data_object_alloc(klass,sval,mark,free)\
)

#define Data_Get_Struct(obj,type,sval) {\
    Check_Type(obj, T_DATA); \
    sval = (type*)DATA_PTR(obj);\
}

struct RStruct {
    struct RBasic basic;
    UINT len;
    VALUE *ptr;
};

struct RBignum {
    struct RBasic basic;
    char sign;
    UINT len;
    USHORT *digits;
};

#define R_CAST(st) (struct st*)
#define RBASIC(obj)  (R_CAST(RBasic)(obj))
#define ROBJECT(obj) (R_CAST(RObject)(obj))
#define RCLASS(obj)  (R_CAST(RClass)(obj))
#define RFLOAT(obj)  (R_CAST(RFloat)(obj))
#define RSTRING(obj) (R_CAST(RString)(obj))
#define RREGEXP(obj) (R_CAST(RRegexp)(obj))
#define RARRAY(obj)  (R_CAST(RArray)(obj))
#define RHASH(obj)   (R_CAST(RHash)(obj))
#define RDATA(obj)   (R_CAST(RData)(obj))
#define RSTRUCT(obj) (R_CAST(RStruct)(obj))
#define RBIGNUM(obj) (R_CAST(RBignum)(obj))
#define RFILE(obj)   (R_CAST(RFile)(obj))

#define FL_SINGLETON (1<<8)
#define FL_MARK      (1<<9)
#define FL_FINALIZE  (1<<10)

#define FL_USHIFT    11

#define FL_USER0     (1<<(FL_USHIFT+0))
#define FL_USER1     (1<<(FL_USHIFT+1))
#define FL_USER2     (1<<(FL_USHIFT+2))
#define FL_USER3     (1<<(FL_USHIFT+3))
#define FL_USER4     (1<<(FL_USHIFT+4))
#define FL_USER5     (1<<(FL_USHIFT+5))
#define FL_USER6     (1<<(FL_USHIFT+6))

#define FL_UMASK  (0x7f<<FL_USHIFT)

#define FL_ABLE(x) (!(FIXNUM_P(x)||rb_special_const_p((VALUE)(x))))
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_SET(x,f) if (FL_ABLE(x)) {RBASIC(x)->flags |= (f);}
#define FL_UNSET(x,f) if(FL_ABLE(x)){RBASIC(x)->flags &= ~(f);}
#define FL_REVERSE(x,f) if(FL_ABLE(x)){RBASIC(x)->flags ^= f;}

#if defined(__GNUC__) && __GNUC__ >= 2 && !defined(RUBY_NO_INLINE)
extern __inline__ int
rb_type(VALUE obj)
{
    if (FIXNUM_P(obj)) return T_FIXNUM;
    if (obj == Qnil) return T_NIL;
    if (obj == FALSE) return T_FALSE;
    if (obj == TRUE) return T_TRUE;

    return BUILTIN_TYPE(obj);
}

extern __inline__ int
rb_special_const_p(VALUE obj)
{
    return (FIXNUM_P(obj)||obj == Qnil||obj == FALSE||obj == TRUE)?TRUE:FALSE;
}

extern __inline__ int
rb_test_false_or_nil(VALUE v)
{
    return (v != Qnil) && (v != FALSE);
}
#else
int rb_type _((VALUE));
int rb_special_const_p _((VALUE));
int rb_test_false_or_nil _((VALUE));
#endif

void *xmalloc _((unsigned long));
void *xcalloc _((unsigned long,unsigned long));
void *xrealloc _((void*,unsigned long));
#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

#define ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(n))

VALUE rb_define_class _((char*,VALUE));
VALUE rb_define_module _((char*));
VALUE rb_define_class_under _((VALUE, char *, VALUE));
VALUE rb_define_module_under _((VALUE, char *));

void rb_include_module _((VALUE,VALUE));
void rb_extend_object _((VALUE,VALUE));

void rb_define_variable _((char*,VALUE*));
void rb_define_virtual_variable _((char*,VALUE(*)(),void(*)()));
void rb_define_hooked_variable _((char*,VALUE*,VALUE(*)(),void(*)()));
void rb_define_readonly_variable _((char*,VALUE*));
void rb_define_const _((VALUE,char*,VALUE));
void rb_define_global_const _((char*,VALUE));

void rb_define_method _((VALUE,char*,VALUE(*)(),int));
void rb_define_function _((VALUE,char*,VALUE(*)(),int));
void rb_define_module_function _((VALUE,char*,VALUE(*)(),int));
void rb_define_global_function _((char *, VALUE (*)(), int));

void rb_undef_method _((VALUE,char*));
void rb_define_alias _((VALUE,char*,char*));
void rb_define_attr _((VALUE,ID,int,int));

ID rb_intern _((char*));
char *rb_id2name _((ID));
ID rb_to_id _((VALUE));

char *rb_class2name _((VALUE));

void rb_p _((VALUE));

VALUE rb_eval_string _((char*));
VALUE rb_funcall();
int rb_scan_args();

VALUE rb_iv_get _((VALUE, char *));
VALUE rb_iv_set _((VALUE, char *, VALUE));
VALUE rb_const_get _((VALUE, ID));
VALUE rb_const_get_at _((VALUE, ID));
void rb_const_set _((VALUE, ID, VALUE));

VALUE rb_equal _((VALUE,VALUE));

extern VALUE verbose, debug;

int rb_safe_level _((void));
void rb_set_safe_level _((int));

#ifdef __GNUC__
typedef void voidfn ();
volatile voidfn Raise;
volatile voidfn Fail;
volatile voidfn Fatal;
volatile voidfn Bug;
volatile voidfn WrongType;
volatile voidfn rb_sys_fail;
volatile voidfn rb_iter_break;
volatile voidfn rb_exit;
volatile voidfn rb_fatal;
volatile voidfn rb_raise;
volatile voidfn rb_notimplement;
#else
void Raise();
void Fail();
void Fatal();
void Bug();
void WrongType();
void rb_sys_fail _((char *));
void rb_iter_break _((void));
void rb_exit _((int));
void rb_raise _((VALUE));
void rb_fatal _((VALUE));
void rb_notimplement _((void));
#endif

void Error();
void Warning();

VALUE rb_each _((VALUE));
VALUE rb_yield _((VALUE));
int iterator_p _((void));
VALUE rb_iterate();
VALUE rb_rescue();
VALUE rb_ensure();

#include "intern.h"

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#endif
