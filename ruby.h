/************************************************

  ruby.h -

  $Author$
  $Date$
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

*************************************************/

#ifndef RUBY_H
#define RUBY_H

#if defined(__cplusplus)
extern "C" {
#endif

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

#include <stdio.h>

/* need to include <ctype.h> to use these macros */
#define ISSPACE(c) isspace((unsigned char)(c))
#define ISUPPER(c) isupper((unsigned char)(c))
#define ISLOWER(c) islower((unsigned char)(c))
#define ISPRINT(c) isprint((unsigned char)(c))
#define ISALNUM(c) isalnum((unsigned char)(c))
#define ISALPHA(c) isalpha((unsigned char)(c))
#define ISDIGIT(c) isdigit((unsigned char)(c))
#define ISXDIGIT(c) isxdigit((unsigned char)(c))

#ifndef __STDC__
# define volatile
# ifdef __GNUC__
#  define const __const__
# else
#  define const
# endif
#endif

#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif

#ifdef HAVE_STDARG_PROTOTYPES
# define __(args) args
#else
# define __(args) ()
#endif

#ifdef HAVE_ATTR_NORETURN
# define NORETURN __attribute__ ((noreturn))
#else
# define NORETURN
#endif

#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

#if defined(__CYGWIN32__)
#if defined(DLLIMPORT)
#include "import.h"
#else
#define environ (*__imp___cygwin_environ)
#endif
#endif

#ifdef _AIX
#pragma alloca
#endif

#if SIZEOF_LONG != SIZEOF_VOIDP
---->> ruby requires sizeof(void*) == sizeof(long) to be compiled. <<----
# endif
/* INT, UINT, UCHAR are obsolete macro, do not use them. */
typedef long INT;
typedef unsigned long UINT;
typedef unsigned char UCHAR;

typedef unsigned long VALUE;
typedef unsigned int ID;

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

#define FIXNUM_MAX (LONG_MAX>>1)
#define FIXNUM_MIN RSHIFT((long)LONG_MIN,1)

#define FIXNUM_FLAG 0x01
#define INT2FIX(i) (VALUE)(((long)(i))<<1 | FIXNUM_FLAG)
VALUE int2inum _((long));
#define INT2NUM(v) int2inum(v)

#define FIX2LONG(x) RSHIFT((long)x,1)
#define FIX2ULONG(x) (((unsigned long)(x))>>1)
#define FIXNUM_P(f) (((long)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

/* special contants - i.e. non-zero and non-fixnum constants */
#ifndef MACRUBY_PUBLIC_INTERFACE
# undef FALSE 
# undef TRUE
# define FALSE  0
# define TRUE   2
# define NIL    4
#endif
#define Qfalse 0
#define Qtrue  2
#define Qnil   4

# define RTEST(v) rb_test_false_or_nil((VALUE)(v))
#define NIL_P(v) ((VALUE)(v) == Qnil)

VALUE rb_class_of _((VALUE));
#define CLASS_OF(v) rb_class_of((VALUE)(v))

#define T_NONE   0x00

#define T_NIL    0x01
#define T_OBJECT 0x02
#define T_CLASS  0x03
#define T_ICLASS 0x04
#define T_MODULE 0x05
#define T_FLOAT  0x06
#define T_STRING 0x07
#define T_REGEXP 0x08
#define T_ARRAY  0x09
#define T_FIXNUM 0x0a
#define T_HASH   0x0b
#define T_STRUCT 0x0c
#define T_BIGNUM 0x0d
#define T_FILE   0x0e

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

long num2long _((VALUE));
unsigned long num2ulong _((VALUE));
#define NUM2LONG(x) (FIXNUM_P(x)?FIX2INT(x):num2long((VALUE)x))
#define NUM2ULONG(x) num2ulong((VALUE)x)
#if SIZEOF_INT < SIZEOF_LONG
int num2int _((VALUE));
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):num2int((VALUE)x))
int fix2int _((VALUE));
#define FIX2INT(x) fix2int((VALUE)x)
#define NUM2UINT(x) ((unsigned int)NUM2ULONG(x))
#define FIX2UINT(x) ((unsigned int)FIX2ULONG(x))
#else
#define NUM2INT(x) NUM2LONG(x)
#define NUM2UINT(x) NUM2ULONG(x)
#define FIX2INT(x) FIX2LONG(x)
#define FIX2UINT(x) FIX2ULONG(x)
#endif

double num2dbl _((VALUE));
#define NUM2DBL(x) num2dbl((VALUE)(x))

char *str2cstr _((VALUE,int*));
#define STR2CSTR(x) str2cstr((VALUE)(x),0)

#define NUM2CHR(x) (((TYPE(x) == T_STRING)&&(RSTRING(x)->len>=1))?\
                     RSTRING(x)->ptr[0]:(char)NUM2INT(x))
#define CHR2FIX(x) INT2FIX((int)x)

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
    unsigned long flags;
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
    int len;
    char *ptr;
    VALUE orig;
};

struct RArray {
    struct RBasic basic;
    int len, capa;
    VALUE *ptr;
};

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    int len;
    char *str;
};

struct RHash {
    struct RBasic basic;
    struct st_table *tbl;
    int iter_lev;
    long status;
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

extern VALUE cData;

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
    int len;
    VALUE *ptr;
};

struct RBignum {
    struct RBasic basic;
    char sign;
    int len;
    unsigned short *digits;
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

#define FL_SINGLETON FL_USER0
#define FL_MARK      (1<<8)
#define FL_FINALIZE  (1<<9)

#define FL_USHIFT    10

#define FL_USER0     (1<<(FL_USHIFT+0))
#define FL_USER1     (1<<(FL_USHIFT+1))
#define FL_USER2     (1<<(FL_USHIFT+2))
#define FL_USER3     (1<<(FL_USHIFT+3))
#define FL_USER4     (1<<(FL_USHIFT+4))
#define FL_USER5     (1<<(FL_USHIFT+5))
#define FL_USER6     (1<<(FL_USHIFT+6))
#define FL_USER7     (1<<(FL_USHIFT+7))

#define FL_UMASK  (0xff<<FL_USHIFT)

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
#ifdef MACRUBY_PUBLIC_INTERFACE
    if (obj == RubyFALSE) return T_FALSE;
    if (obj == RubyTRUE) return T_TRUE;
#else
    if (obj == FALSE) return T_FALSE;
    if (obj == TRUE) return T_TRUE;
#endif
    return BUILTIN_TYPE(obj);
}

extern __inline__ int
rb_special_const_p(VALUE obj)
{
#ifdef MACRUBY_PUBLIC_INTERFACE
    return (FIXNUM_P(obj)||obj == Qnil||obj == RubyFALSE||obj == RubyTRUE)?RubyTRUE:RubyFALSE;
#else
    return (FIXNUM_P(obj)||obj == Qnil||obj == FALSE||obj == TRUE)?TRUE:FALSE;
#endif
}

extern __inline__ int
rb_test_false_or_nil(VALUE v)
{
#ifdef MACRUBY_PUBLIC_INTERFACE
    return (v != Qnil) && (v != RubyFALSE);
    return (v != Qnil) && (v != RubyFALSE);
#else
    return (v != Qnil) && (v != FALSE);
    return (v != Qnil) && (v != FALSE);
#endif
}
#else
int rb_type _((VALUE));
int rb_special_const_p _((VALUE));
int rb_test_false_or_nil _((VALUE));
#endif

void *xmalloc _((int));
void *xcalloc _((int,int));
void *xrealloc _((void*,int));
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
void rb_define_attr _((VALUE,char*,int,int));

ID rb_intern _((char*));
char *rb_id2name _((ID));
ID rb_to_id _((VALUE));

char *rb_class2name _((VALUE));

void rb_p _((VALUE));

VALUE rb_eval_string _((char*));
VALUE rb_funcall __((VALUE, ID, int, ...));
int rb_scan_args __((int, VALUE*, char*, ...));

VALUE rb_iv_get _((VALUE, char *));
VALUE rb_iv_set _((VALUE, char *, VALUE));
VALUE rb_const_get _((VALUE, ID));
VALUE rb_const_get_at _((VALUE, ID));
void rb_const_set _((VALUE, ID, VALUE));

VALUE rb_equal _((VALUE,VALUE));

extern VALUE verbose, debug;

int rb_safe_level _((void));
void rb_set_safe_level _((int));

void Raise __((VALUE, char*, ...)) NORETURN;
void Fail __((char*, ...)) NORETURN;
void Fatal __((char*, ...)) NORETURN;
void Bug __((char*, ...)) NORETURN;
void rb_sys_fail _((char*)) NORETURN;
void rb_iter_break _((void)) NORETURN;
void rb_exit _((int)) NORETURN;
void rb_raise _((VALUE)) NORETURN;
void rb_fatal _((VALUE)) NORETURN;
void rb_notimplement _((void)) NORETURN;

void Error __((char*, ...));
void Warn __((char*, ...));
void Warning __((char*, ...));		/* reports if `-w' specified */

VALUE rb_each _((VALUE));
VALUE rb_yield _((VALUE));
int iterator_p _((void));
VALUE rb_iterate _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_rescue _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_ensure _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_catch _((char*,VALUE(*)(),VALUE));
void rb_throw _((char*,VALUE)) NORETURN;

extern VALUE mKernel;
extern VALUE mComparable;
extern VALUE mEnumerable;
extern VALUE mErrno;
extern VALUE mFileTest;
extern VALUE mGC;
extern VALUE mMath;
extern VALUE mProcess;

#ifdef __MACOS__ /* name conflict, AERegistory.h */
extern VALUE cRubyObject;
#else
extern VALUE cObject;
#endif
extern VALUE cArray;
extern VALUE cBignum;
extern VALUE cClass;
extern VALUE cData;
extern VALUE cFile;
extern VALUE cFixnum;
extern VALUE cFloat;
extern VALUE cHash;
extern VALUE cInteger;
extern VALUE cIO;
extern VALUE cModule;
extern VALUE cNumeric;
extern VALUE cProc;
extern VALUE cRegexp;
extern VALUE cString;
extern VALUE cThread;
extern VALUE cStruct;

extern VALUE eException;
extern VALUE eStandardError;
extern VALUE eSystemExit, eInterrupt, eFatal;
extern VALUE eArgError;
extern VALUE eEOFError;
extern VALUE eIndexError;
extern VALUE eIOError;
extern VALUE eLoadError;
extern VALUE eNameError;
extern VALUE eRuntimeError;
extern VALUE eSecurityError;
extern VALUE eSyntaxError;
extern VALUE eSystemCallError;
extern VALUE eTypeError;
extern VALUE eZeroDiv;
extern VALUE eNotImpError;

#include "intern.h"

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#if defined(__cplusplus)
}  /* extern "C" { */
#endif

#endif /* ifndef RUBY_H */
