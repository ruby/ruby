/************************************************

  ruby.h -

  $Author: matz $
  $Date: 1995/01/12 08:54:52 $
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1995 Yukihiro Matsumoto

*************************************************/

#ifndef RUBY_H
#define RUBY_H

#include "config.h"
#include "defines.h"

#ifdef __STDC__
#else
#define volatile
#define const
#endif

#if defined(HAVE_ALLOCA_H) && !defined(__GNUC__)
#include <alloca.h>
#endif

typedef unsigned int UINT;
typedef UINT VALUE;
typedef UINT ID;

typedef unsigned short USHORT;

#ifdef __STDC__
# include <limits.h>
#else
# ifndef LONG_MAX
# if !defined(LONG_MAX) || !defined(CHAR_BIT)
#  include <limits.h>
# endif
# endif
# ifndef LONG_MIN
#  if (0 != ~0)
#   define LONG_MIN (-LONG_MAX-1)
#  else
#   define LONG_MIN (-LONG_MAX)
#  endif
# endif
#endif

#ifndef CHAR_BIT
# define CHAR_BIT 8
#endif

# define FIXNUM_MAX (LONG_MAX>>1)
# define FIXNUM_MIN RSHIFT((long)LONG_MIN,1)

#define FIXNUM_FLAG 0x01
#define INT2FIX(i) (VALUE)(((int)(i))<<1 | FIXNUM_FLAG)

#if (-1==(((-1)<<1)&FIXNUM_FLAG)>>1)
# define RSHIFT(x,y) ((x)>>y)
#else
# define RSHIFT(x,y) (((x)<0) ? ~((~(x))>>y) : (x)>>y)
#endif
#define FIX2INT(x) RSHIFT((int)x,1)

#define FIX2UINT(f) ((unsigned int)(f)>>1)
#define FIXNUM_P(f) (((int)(f))&FIXNUM_FLAG)
#define POSFIXABLE(f) ((f) <= FIXNUM_MAX)
#define NEGFIXABLE(f) ((f) >= FIXNUM_MIN)
#define FIXABLE(f) (POSFIXABLE(f) && NEGFIXABLE(f))

#define POINTER(p) (p)
#define NIL_P(p) ((p) == Qnil)

#undef TRUE
extern VALUE TRUE;
#define FALSE Qnil

extern VALUE C_Object;
extern VALUE C_Nil;
extern VALUE C_Fixnum;
extern VALUE C_Data;

#define CLASS_OF(obj) (FIXNUM_P(obj)?C_Fixnum: NIL_P(obj)?C_Nil:\
                       RBASIC(obj)->class)

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
#define T_DICT   0x0a
#define T_STRUCT 0x0b
#define T_BIGNUM 0x0c
#define T_CONS   0x0f
#define T_DATA   0x10

#define T_SCOPE  0xfe
#define T_NODE   0xff

#define T_MASK   0xff

#define BUILTIN_TYPE(x) (((struct RBasic*)(x))->flags & T_MASK)
#define TYPE(x) (FIXNUM_P(x)?T_FIXNUM:NIL_P(x)?T_NIL:BUILTIN_TYPE(x))
#define Check_Type(x,t) {if (TYPE(x)!=(t)) WrongType(x,t);}
#define Need_Fixnum(x)  {if (!FIXNUM_P(x)) (x) = num2fix(x);}
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):num2int(x))
VALUE num2fix();
int   num2int();

#define NEWOBJ(obj,type) type *obj = (type*)newobj()
#define OBJSETUP(obj,c,t) {\
    RBASIC(obj)->class = (c);\
    RBASIC(obj)->flags |= (t);\
}
#define CLONESETUP(obj1,obj2) \
    OBJSETUP(obj1,RBASIC(obj2)->class,RBASIC(obj2)->flags&T_MASK);

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
    struct Regexp *ptr;
    UINT len;
    char *str;
};

struct RDict {
    struct RBasic basic;
    struct st_table *tbl;
};

struct RData {
    struct RBasic basic;
    void (*dmark)();
    void (*dfree)();
    VALUE *data;
};

#define DATA_PTR(dta) (RDATA(dta)->data)

VALUE data_new();
VALUE rb_ivar_get_1();
VALUE rb_ivar_set_1();

#define Get_Data_Struct(obj, iv, type, sval) {\
    VALUE _data_;\
    _data_ = rb_ivar_get_1(obj, iv);\
    Check_Type(_data_, T_DATA);\
    sval = (type*)DATA_PTR(_data_);\
}

#define Make_Data_Struct(obj, iv, type, mark, free, sval) {\
    VALUE _new_;\
    sval = ALLOC(type);\
    _new_ = data_new(sval,free,mark);\
    memset(sval, 0, sizeof(type));\
    rb_ivar_set_1(obj, iv, _new_);\
}

struct RStruct {
    struct RBasic basic;
    UINT len;
    struct kv_pair {
	ID key;
	VALUE value;
    } *tbl;
    char *name;
};

struct RBignum {
    struct RBasic basic;
    char sign;
    UINT len;
    USHORT *digits;
};

struct RCons {
    struct RBasic basic;
    VALUE car, cdr;
};

#define CAR(c) (RCONS(c)->car)
#define CDR(c) (RCONS(c)->cdr)

#define R_CAST(st) (struct st*)
#define RBASIC(obj)  (R_CAST(RBasic)(obj))
#define ROBJECT(obj) (R_CAST(RObject)(obj))
#define RCLASS(obj)  (R_CAST(RClass)(obj))
#define RFLOAT(obj)  (R_CAST(RFloat)(obj))
#define RSTRING(obj) (R_CAST(RString)(obj))
#define RREGEXP(obj) (R_CAST(RRegexp)(obj))
#define RARRAY(obj)  (R_CAST(RArray)(obj))
#define RDICT(obj)   (R_CAST(RDict)(obj))
#define RDATA(obj)   (R_CAST(RData)(obj))
#define RSTRUCT(obj) (R_CAST(RStruct)(obj))
#define RBIGNUM(obj) (R_CAST(RBignum)(obj))
#define RCONS(obj)   (R_CAST(RCons)(obj))

#define FL_SINGLE  (1<<8)
#define FL_MARK    (1<<9)

#define FL_USER0   (1<<10)
#define FL_USER1   (1<<11)
#define FL_USER2   (1<<12)
#define FL_USER3   (1<<13)
#define FL_USER4   (1<<14)
#define FL_USER5   (1<<15)
#define FL_USER6   (1<<16)
#define FL_USER7   (1<<17)

#define FL_UMASK   (0xff<<10)

#define FL_ABLE(x) (!(FIXNUM_P(x)||NIL_P(x)))
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_SET(x,f) if (FL_ABLE(x)) {RBASIC(x)->flags |= (f);}
#define FL_UNSET(x,f) if(FL_ABLE(x)){RBASIC(x)->flags &= ~(f);}

extern VALUE Qself;
#define Qnil 0

#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

#define ALLOCA_N(type,n) (type*)alloca(sizeof(type)*(n))

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(n))

#ifdef SAFE_SIGHANDLE
extern int trap_immediate;
# define TRAP_BEG (trap_immediate=1)
# define TRAP_END (trap_immediate=0)
#else
# define TRAP_BEG
# define TRAP_END
#endif

VALUE rb_define_class();
VALUE rb_define_module();

void rb_define_variable();
void rb_define_const();

void rb_define_method();
void rb_define_single_method();
void rb_undef_method();
void rb_define_alias();
void rb_define_attr();

ID rb_intern();
char *rb_id2name();

VALUE rb_eval_string();
VALUE rb_funcall();
VALUE rb_funcall2();
int rb_scan_args();

VALUE rb_yield();

extern int verbose, debug;

#endif
