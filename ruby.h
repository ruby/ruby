/************************************************

  ruby.h -

  $Author: matz $
  $Date: 1996/12/25 08:54:52 $
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

*************************************************/

#ifndef RUBY_H
#define RUBY_H

#ifndef NT
# include "config.h"
#endif

#include "defines.h"

#ifndef __STDC__
# define volatile
# ifdef __GNUC__
#  define const __const__
# else
#  define const
# endif
# define _(args)
#else
# define _(args) args
#endif

#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

#ifdef _AIX
#pragma alloca
#endif

typedef unsigned int UINT;
typedef UINT VALUE;
typedef UINT ID;

typedef unsigned short USHORT;

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
#define FIXNUM_MIN RSHIFT((long)LONG_MIN,1)

#define FIXNUM_FLAG 0x01
#define INT2FIX(i) (VALUE)(((int)(i))<<1 | FIXNUM_FLAG)
VALUE int2inum();
#define INT2NUM(v) int2inum(v)

#if (-1==(((-1)<<1)&FIXNUM_FLAG)>>1)
# define RSHIFT(x,y) ((x)>>y)
#else
# define RSHIFT(x,y) (((x)<0) ? ~((~(x))>>y) : (x)>>y)
#endif
#define FIX2INT(x) RSHIFT((int)x,1)

#define FIX2UINT(f) ((UINT)(f)>>1)
#define FIXNUM_P(f) (((int)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

/* special contants - i.e. non-zero and non-fixnum constants */
#define FALSE 0
#undef TRUE
#define TRUE  2
#define Qnil 4

int rb_test_false_or_nil();
# define RTEST(v) rb_test_false_or_nil(v)
#define NIL_P(v) ((VALUE)(v) == Qnil)

extern VALUE cObject;

VALUE rb_class_of();
#define CLASS_OF(v) rb_class_of(v)

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

int rb_type();
#define TYPE(x) rb_type(x)

void Check_Type();
#define Need_Fixnum(x)  {if (!FIXNUM_P(x)) (x) = num2fix(x);}
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):num2int(x))
VALUE num2fix();
int   num2int();

#define NEWOBJ(obj,type) type *obj = (type*)newobj()
#define OBJSETUP(obj,c,t) {\
    RBASIC(obj)->class = (c);\
    RBASIC(obj)->flags = (t);\
}
#define CLONESETUP(obj1,obj2) \
    OBJSETUP(obj1,RBASIC(obj2)->class,RBASIC(obj2)->flags);

struct RBasic {
    UINT flags;
    VALUE class;
};

struct RObject {
    struct RBasic basic;
    struct st_table *iv_tbl;
};

struct RClass {
    struct RBasic basic;
    struct st_table *iv_tbl;
    struct st_table *m_tbl;
    struct RClass *super;
};

struct RFloat {
    struct RBasic basic;
    double value;
};

struct RString {
    struct RBasic basic;
    UINT len;
    char *ptr;
    struct RString *orig;
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
    char *str;
};

struct RHash {
    struct RBasic basic;
    struct st_table *tbl;
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

VALUE data_object_alloc();
#define Make_Data_Struct(class,type,mark,free,sval) (\
    sval = ALLOC(type),\
    memset(sval, 0, sizeof(type)),\
    data_object_alloc(class,sval,mark,free)\
)

#define Get_Data_Struct(obj,type,sval) {\
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

#define FL_USER0     (1<<10)
#define FL_USER1     (1<<11)
#define FL_USER2     (1<<12)
#define FL_USER3     (1<<13)
#define FL_USER4     (1<<14)
#define FL_USER5     (1<<15)
#define FL_USER6     (1<<16)

#define FL_UMASK  (0x7f<<10)

int rb_special_const_p();
#define FL_ABLE(x) (!(FIXNUM_P(x)||rb_special_const_p(x)))
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_SET(x,f) if (FL_ABLE(x)) {RBASIC(x)->flags |= (f);}
#define FL_UNSET(x,f) if(FL_ABLE(x)){RBASIC(x)->flags &= ~(f);}
#define FL_REVERSE(x,f) if(FL_ABLE(x)){RBASIC(x)->flags ^= f;}

#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

#define ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(n))

void *xmalloc();
void *xcalloc();
void *xrealloc();

VALUE rb_define_class();
VALUE rb_define_module();
void rb_include_module();
void rb_extend_object();

void rb_define_variable();
void rb_define_const();
void rb_define_global_const();

void rb_define_method();
void rb_define_singleton_method();
void rb_undef_method();
void rb_define_alias();
void rb_define_attr();

ID rb_intern();
char *rb_id2name();
ID rb_to_id();

char *rb_class2name();
int rb_method_boundp();

VALUE rb_eval_string();
VALUE rb_funcall();
VALUE rb_funcall2();
int rb_scan_args();

VALUE rb_ivar_get();
VALUE rb_ivar_set();

VALUE rb_iv_get();
VALUE rb_iv_set();
void rb_const_set();

VALUE rb_yield();
int iterator_p();

int rb_equal();

extern int verbose, debug;

#ifdef __GNUC__
typedef void voidfn ();
volatile voidfn Raise;
volatile voidfn Fail;
volatile voidfn Fatal;
volatile voidfn Bug;
volatile voidfn WrongType;
volatile voidfn rb_sys_fail;
volatile voidfn rb_break;
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
void rb_sys_fail();
void rb_break();
void rb_exit();
void rb_fatal();
void rb_raise();
void rb_notimplement();
#endif

void Error();
void Warning();

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#endif
