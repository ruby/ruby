/**********************************************************************

  ruby.h -

  $Author$
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

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

#include <stddef.h>
#include <stdio.h>

/* need to include <ctype.h> to use these macros */
#undef ISPRINT
#define ISPRINT(c) isprint((unsigned char)(c))
#define ISSPACE(c) isspace((unsigned char)(c))
#define ISUPPER(c) isupper((unsigned char)(c))
#define ISLOWER(c) islower((unsigned char)(c))
#define ISALNUM(c) isalnum((unsigned char)(c))
#define ISALPHA(c) isalpha((unsigned char)(c))
#define ISDIGIT(c) isdigit((unsigned char)(c))
#define ISXDIGIT(c) isxdigit((unsigned char)(c))

#ifndef __STDC__
# define volatile
#endif

#undef _
#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif

#undef __
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

#ifdef _AIX
#pragma alloca
#endif

#if SIZEOF_LONG != SIZEOF_VOIDP
---->> ruby requires sizeof(void*) == sizeof(long) to be compiled. <<----
#endif
typedef unsigned long VALUE;
typedef unsigned long ID;

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
#define INT2FIX(i) ((VALUE)(((long)(i))<<1 | FIXNUM_FLAG))
#define rb_fix_new(v) INT2FIX(v)
VALUE rb_int2inum _((long));
#define INT2NUM(v) rb_int2inum(v)
#define rb_int_new(v) rb_int2inum(v)
VALUE rb_uint2inum _((unsigned long));
#define UINT2NUM(v) rb_uint2inum(v)
#define rb_uint_new(v) rb_uint2inum(v)

#define FIX2LONG(x) RSHIFT((long)x,1)
#define FIX2ULONG(x) (((unsigned long)(x))>>1)
#define FIXNUM_P(f) (((long)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

#define IMMEDIATE_MASK 0x03
#define IMMEDIATE_P(x) ((VALUE)(x) & IMMEDIATE_MASK)

#define SYMBOL_FLAG 0x0e
#define SYMBOL_P(x) (((VALUE)(x)&0xff)==SYMBOL_FLAG)
#define ID2SYM(x) ((VALUE)(((long)(x))<<8|SYMBOL_FLAG))
#define SYM2ID(x) RSHIFT((long)x,8)

/* special contants - i.e. non-zero and non-fixnum constants */
#define Qfalse 0
#define Qtrue  2
#define Qnil   4
#define Qundef 6		/* undefined value for placeholder */

#define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
#define NIL_P(v) ((VALUE)(v) == Qnil)

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
#define T_SYMBOL 0x24

#define T_BLKTAG 0x3b
#define T_UNDEF  0x3c
#define T_VARMAP 0x3d
#define T_SCOPE  0x3e
#define T_NODE   0x3f

#define T_MASK   0x3f

#define BUILTIN_TYPE(x) (((struct RBasic*)(x))->flags & T_MASK)

#define TYPE(x) rb_type((VALUE)(x))

void rb_check_type _((VALUE,int));
#define Check_Type(v,t) rb_check_type((VALUE)(v),t)
void rb_check_safe_str _((VALUE));
#define Check_SafeStr(v) rb_check_safe_str((VALUE)(v))
void rb_secure _((int));

EXTERN int ruby_safe_level;
#define rb_safe_level() (ruby_safe_level)
void rb_set_safe_level _((int));

long rb_num2long _((VALUE));
unsigned long rb_num2ulong _((VALUE));
#define NUM2LONG(x) (FIXNUM_P(x)?FIX2LONG(x):rb_num2long((VALUE)x))
#define NUM2ULONG(x) rb_num2ulong((VALUE)x)
#if SIZEOF_INT < SIZEOF_LONG
int rb_num2int _((VALUE));
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):rb_num2int((VALUE)x))
int rb_fix2int _((VALUE));
#define FIX2INT(x) rb_fix2int((VALUE)x)
#define NUM2UINT(x) ((unsigned int)NUM2INT(x))
#define FIX2UINT(x) ((unsigned int)FIX2INT(x))
#else
#define NUM2INT(x) NUM2LONG(x)
#define NUM2UINT(x) NUM2ULONG(x)
#define FIX2INT(x) FIX2LONG(x)
#define FIX2UINT(x) FIX2ULONG(x)
#endif

double rb_num2dbl _((VALUE));
#define NUM2DBL(x) rb_num2dbl((VALUE)(x))

char *rb_str2cstr _((VALUE,int*));
#define str2cstr(x,l) rb_str2cstr((VALUE)(x),(l))
#define STR2CSTR(x) rb_str2cstr((VALUE)(x),0)

#define NUM2CHR(x) (((TYPE(x) == T_STRING)&&(RSTRING(x)->len>=1))?\
                     RSTRING(x)->ptr[0]:(char)(NUM2INT(x)&0xff))
#define CHR2FIX(x) INT2FIX((long)((x)&0xff))

VALUE rb_newobj _((void));
#define NEWOBJ(obj,type) type *obj = (type*)rb_newobj()
#define OBJSETUP(obj,c,t) {\
    RBASIC(obj)->flags = (t);\
    RBASIC(obj)->klass = (c);\
    if (rb_safe_level() >= 3) FL_SET(obj, FL_TAINT);\
}
#define CLONESETUP(clone,obj) do {\
    OBJSETUP(clone,rb_singleton_class_clone(RBASIC(obj)->klass),RBASIC(obj)->flags);\
    rb_singleton_class_attached(RBASIC(clone)->klass, (VALUE)clone);\
    if (FL_TEST(obj, FL_EXIVAR)) rb_clone_generic_ivar((VALUE)clone,(VALUE)obj);\
} while (0)

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
    long len;
    char *ptr;
    VALUE orig;
};

struct RArray {
    struct RBasic basic;
    long len, capa;
    VALUE *ptr;
};

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
    struct OpenFile *fptr;
};

struct RData {
    struct RBasic basic;
    void (*dmark) _((void*));
    void (*dfree) _((void*));
    void *data;
};

#define DATA_PTR(dta) (RDATA(dta)->data)

/*
#define RUBY_DATA_FUNC(func) ((void (*)_((void*)))func)
*/
typedef void (*RUBY_DATA_FUNC) _((void*));

VALUE rb_data_object_alloc _((VALUE,void*,RUBY_DATA_FUNC,RUBY_DATA_FUNC));

#define Data_Wrap_Struct(klass,mark,free,sval) (\
    rb_data_object_alloc(klass,sval,(RUBY_DATA_FUNC)mark,(RUBY_DATA_FUNC)free)\
)

#define Data_Make_Struct(klass,type,mark,free,sval) (\
    sval = ALLOC(type),\
    memset(sval, 0, sizeof(type)),\
    Data_Wrap_Struct(klass,mark,free,sval)\
)

#define Data_Get_Struct(obj,type,sval) {\
    Check_Type(obj, T_DATA); \
    sval = (type*)DATA_PTR(obj);\
}

struct RStruct {
    struct RBasic basic;
    long len;
    VALUE *ptr;
};

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

#define FL_SINGLETON FL_USER0
#define FL_MARK      (1<<6)
#define FL_FINALIZE  (1<<7)
#define FL_TAINT     (1<<8)
#define FL_EXIVAR    (1<<9)
#define FL_FREEZE    (1<<10)

#define FL_USHIFT    11

#define FL_USER0     (1<<(FL_USHIFT+0))
#define FL_USER1     (1<<(FL_USHIFT+1))
#define FL_USER2     (1<<(FL_USHIFT+2))
#define FL_USER3     (1<<(FL_USHIFT+3))
#define FL_USER4     (1<<(FL_USHIFT+4))
#define FL_USER5     (1<<(FL_USHIFT+5))
#define FL_USER6     (1<<(FL_USHIFT+6))
#define FL_USER7     (1<<(FL_USHIFT+7))

#define FL_UMASK  (0xff<<FL_USHIFT)

#define SPECIAL_CONST_P(x) (IMMEDIATE_P(x) || !RTEST(x))

#define FL_ABLE(x) (!SPECIAL_CONST_P(x))
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_SET(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags |= (f);} while (0)
#define FL_UNSET(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags &= ~(f);} while (0)
#define FL_REVERSE(x,f) do {if (FL_ABLE(x)) RBASIC(x)->flags ^= (f);} while (0)

#define OBJ_TAINTED(x) FL_TEST((x), FL_TAINT)
#define OBJ_TAINT(x) FL_SET((x), FL_TAINT)
#define OBJ_INFECT(x,s) do {if (FL_ABLE(x) && FL_ABLE(s)) RBASIC(x)->flags |= RBASIC(s)->flags & FL_TAINT;} while (0)

#define OBJ_FROZEN(x) FL_TEST((x), FL_FREEZE)
#define OBJ_FREEZE(x) FL_SET((x), FL_FREEZE)

#define xmalloc ruby_xmalloc
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xfree ruby_xfree

void *xmalloc _((long));
void *xcalloc _((long,long));
void *xrealloc _((void*,long));
void xfree _((void*));

#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

#define ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(n))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), sizeof(type)*(n))

void rb_glob _((char*,void(*)(),VALUE));
void rb_iglob _((char*,void(*)(),VALUE));

VALUE rb_define_class _((const char*,VALUE));
VALUE rb_define_module _((const char*));
VALUE rb_define_class_under _((VALUE, const char*, VALUE));
VALUE rb_define_module_under _((VALUE, const char*));

void rb_include_module _((VALUE,VALUE));
void rb_extend_object _((VALUE,VALUE));

void rb_define_variable _((const char*,VALUE*));
void rb_define_virtual_variable _((const char*,VALUE(*)(),void(*)()));
void rb_define_hooked_variable _((const char*,VALUE*,VALUE(*)(),void(*)()));
void rb_define_readonly_variable _((const char*,VALUE*));
void rb_define_const _((VALUE,const char*,VALUE));
void rb_define_global_const _((const char*,VALUE));

#define RUBY_METHOD_FUNC(func) ((VALUE (*)__((...)))func)
void rb_define_method _((VALUE,const char*,VALUE(*)(),int));
void rb_define_module_function _((VALUE,const char*,VALUE(*)(),int));
void rb_define_global_function _((const char*,VALUE(*)(),int));

void rb_undef_method _((VALUE,const char*));
void rb_define_alias _((VALUE,const char*,const char*));
void rb_define_attr _((VALUE,const char*,int,int));

void rb_global_variable _((VALUE*));
void rb_gc_register_address _((VALUE*));
void rb_gc_unregister_address _((VALUE*));

ID rb_intern _((const char*));
char *rb_id2name _((ID));
ID rb_to_id _((VALUE));

char *rb_class2name _((VALUE));

void rb_p _((VALUE));

VALUE rb_eval_string _((const char*));
VALUE rb_eval_string_protect _((const char*, int*));
VALUE rb_eval_string_wrap _((const char*, int*));
VALUE rb_funcall __((VALUE, ID, int, ...));
VALUE rb_funcall2 _((VALUE, ID, int, VALUE*));
VALUE rb_funcall3 _((VALUE, ID, int, VALUE*));
int rb_scan_args __((int, VALUE*, const char*, ...));
VALUE rb_call_super _((int, VALUE*));

VALUE rb_gv_set _((const char*, VALUE));
VALUE rb_gv_get _((const char*));
VALUE rb_iv_get _((VALUE, const char*));
VALUE rb_iv_set _((VALUE, const char*, VALUE));

VALUE rb_equal _((VALUE,VALUE));

EXTERN VALUE ruby_verbose, ruby_debug;

void rb_raise __((VALUE, const char*, ...)) NORETURN;
void rb_fatal __((const char*, ...)) NORETURN;
void rb_bug __((const char*, ...)) NORETURN;
void rb_sys_fail _((const char*)) NORETURN;
void rb_iter_break _((void)) NORETURN;
void rb_exit _((int)) NORETURN;
void rb_notimplement _((void)) NORETURN;

void rb_warn __((const char*, ...));
void rb_warning __((const char*, ...));		/* reports if `-w' specified */

VALUE rb_each _((VALUE));
VALUE rb_yield _((VALUE));
int rb_block_given_p _((void));
VALUE rb_iterate _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_rescue _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_rescue2 __((VALUE(*)(),VALUE,VALUE(*)(),VALUE,...));
VALUE rb_ensure _((VALUE(*)(),VALUE,VALUE(*)(),VALUE));
VALUE rb_catch _((const char*,VALUE(*)(),VALUE));
void rb_throw _((const char*,VALUE)) NORETURN;

VALUE rb_require _((const char*));

void ruby_init _((void));
void ruby_options _((int, char**));
void ruby_run _((void));

EXTERN VALUE rb_mKernel;
EXTERN VALUE rb_mComparable;
EXTERN VALUE rb_mEnumerable;
EXTERN VALUE rb_mPrecision;
EXTERN VALUE rb_mErrno;
EXTERN VALUE rb_mFileTest;
EXTERN VALUE rb_mGC;
EXTERN VALUE rb_mMath;
EXTERN VALUE rb_mProcess;

EXTERN VALUE rb_cObject;
EXTERN VALUE rb_cArray;
EXTERN VALUE rb_cBignum;
EXTERN VALUE rb_cClass;
EXTERN VALUE rb_cDir;
EXTERN VALUE rb_cData;
EXTERN VALUE rb_cFalseClass;
EXTERN VALUE rb_cFile;
EXTERN VALUE rb_cFixnum;
EXTERN VALUE rb_cFloat;
EXTERN VALUE rb_cHash;
EXTERN VALUE rb_cInteger;
EXTERN VALUE rb_cIO;
EXTERN VALUE rb_cModule;
EXTERN VALUE rb_cNilClass;
EXTERN VALUE rb_cNumeric;
EXTERN VALUE rb_cProc;
EXTERN VALUE rb_cRange;
EXTERN VALUE rb_cRegexp;
EXTERN VALUE rb_cString;
EXTERN VALUE rb_cSymbol;
EXTERN VALUE rb_cThread;
EXTERN VALUE rb_cTime;
EXTERN VALUE rb_cTrueClass;
EXTERN VALUE rb_cStruct;

EXTERN VALUE rb_eException;
EXTERN VALUE rb_eStandardError;
EXTERN VALUE rb_eSystemExit;
EXTERN VALUE rb_eInterrupt;
EXTERN VALUE rb_eSignal;
EXTERN VALUE rb_eFatal;
EXTERN VALUE rb_eArgError;
EXTERN VALUE rb_eEOFError;
EXTERN VALUE rb_eIndexError;
EXTERN VALUE rb_eRangeError;
EXTERN VALUE rb_eIOError;
EXTERN VALUE rb_eRuntimeError;
EXTERN VALUE rb_eSecurityError;
EXTERN VALUE rb_eSystemCallError;
EXTERN VALUE rb_eTypeError;
EXTERN VALUE rb_eZeroDivError;
EXTERN VALUE rb_eNotImpError;
EXTERN VALUE rb_eNoMemError;
EXTERN VALUE rb_eFloatDomainError;

EXTERN VALUE rb_eScriptError;
EXTERN VALUE rb_eNameError;
EXTERN VALUE rb_eSyntaxError;
EXTERN VALUE rb_eLoadError;

#if defined(__GNUC__) && __GNUC__ >= 2 && !defined(RUBY_NO_INLINE)
extern __inline__ VALUE rb_class_of _((VALUE));
extern __inline__ int rb_type _((VALUE));
extern __inline__ int rb_special_const_p _((VALUE));

extern __inline__ VALUE
rb_class_of(VALUE obj)
{
    if (FIXNUM_P(obj)) return rb_cFixnum;
    if (obj == Qnil) return rb_cNilClass;
    if (obj == Qfalse) return rb_cFalseClass;
    if (obj == Qtrue) return rb_cTrueClass;
    if (SYMBOL_P(obj)) return rb_cSymbol;

    return RBASIC(obj)->klass;
}

extern __inline__ int
rb_type(VALUE obj)
{
    if (FIXNUM_P(obj)) return T_FIXNUM;
    if (obj == Qnil) return T_NIL;
    if (obj == Qfalse) return T_FALSE;
    if (obj == Qtrue) return T_TRUE;
    if (obj == Qundef) return T_UNDEF;
    if (SYMBOL_P(obj)) return T_SYMBOL;
    return BUILTIN_TYPE(obj);
}

extern __inline__ int
rb_special_const_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) return Qtrue;
    return Qfalse;
}

#else
VALUE rb_class_of _((VALUE));
int rb_type _((VALUE));
int rb_special_const_p _((VALUE));
#endif

#include "intern.h"

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *dln_libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#if defined(__cplusplus)
}  /* extern "C" { */
#endif

#endif /* ifndef RUBY_H */
