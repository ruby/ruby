/************************************************

  ruby.h -

  $Author: matz $
  $Date: 1994/06/27 15:48:38 $
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#ifndef RUBY_H
#define RUBY_H

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
#  define LONG_MAX ((long)((unsigned long)~0L>>1))
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

#define TRUE  INT2FIX(1)
#define FALSE Qnil

extern VALUE C_Object;
extern VALUE C_Nil;
extern VALUE C_Fixnum;
extern VALUE C_Data;

#define CLASS_OF(obj) (FIXNUM_P(obj)?C_Fixnum: NIL_P(obj)?C_Nil:\
                       RBASIC(obj)->class)

#define FL_SINGLE  0x10
#define FL_MARK    0x20
#define FL_LITERAL 0x40

#define FL_ABLE(x) (!(FIXNUM_P(x)||NIL_P(x)))
#define FL_TEST(x,f) (FL_ABLE(x)?(RBASIC(x)->flags&(f)):0)
#define FL_SET(x,f) if (FL_ABLE(x)) {RBASIC(x)->flags |= (f);}
#define FL_UNSET(x,f) if(FL_ABLE(x)){RBASIC(x)->flags &= ~(f);}

#define T_NIL    0x0
#define T_OBJECT 0x1
#define T_CLASS  0x2
#define T_ICLASS 0x3
#define T_MODULE 0x4
#define T_FLOAT  0x5
#define T_STRING 0x6
#define T_REGEXP 0x7
#define T_ARRAY  0x8
#define T_FIXNUM 0x9
#define T_DICT   0xA
#define T_DATA   0xB
#define T_METHOD 0xC
#define T_STRUCT 0xD
#define T_BIGNUM 0xE

#define T_MASK   0xF

#define BUILTIN_TYPE(x) (((struct RBasic*)(x))->flags & T_MASK)
#define TYPE(x) (FIXNUM_P(x)?T_FIXNUM:NIL_P(x)?T_NIL:BUILTIN_TYPE(x))
#define Check_Type(x,t) {if (TYPE(x)!=(t)) WrongType(x,t);}
#define Need_Fixnum(x)  {if (!FIXNUM_P(x)) (x) = num2fix(x);}
#define NUM2INT(x) (FIXNUM_P(x)?FIX2INT(x):num2int(x))
VALUE num2fix();
int   num2int();

#define NEWOBJ(obj,type) type *obj = (type*)newobj(sizeof(type))
#define OBJSETUP(obj,c,t) {\
    RBASIC(obj)->class = (c);\
    RBASIC(obj)->flags |= (t);\
}
#define CLONESETUP(obj1,obj2) \
    OBJSETUP(obj1,RBASIC(obj2)->class,RBASIC(obj2)->flags&T_MASK);
				 
struct RBasic {
    UINT flags;
    struct RBasic *next;
    VALUE class;
    struct st_table *iv_tbl;
};

struct RObject {
    struct RBasic basic;
};

struct RClass {
    struct RBasic basic;
    struct st_table *m_tbl;
    struct st_table *c_tbl;
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
    VALUE data[1];
};

#define DATA_PTR(dta) &(RDATA(dta)->data[0])

#define Get_Data_Struct(obj, iv, type, sval) {\
    VALUE _data_;\
    _data_ = rb_iv_get(obj, iv);\
    Check_Type(_data_, T_DATA);\
    sval = (type*)DATA_PTR(_data_);\
}

#define Make_Data_Struct(obj, iv, type, mark, free, sval) {\
    struct RData *_new_;\
    _new_ = (struct RData*)newobj(sizeof(struct RData)+sizeof(type));\
    OBJSETUP(_new_, C_Data, T_DATA);\
    _new_->dmark = (void (*)())(mark);\
    _new_->dfree = (void (*)())(free);\
    sval = (type*)DATA_PTR(_new_);\
    bzero(sval, sizeof(type));\
    rb_iv_set(obj, iv, _new_);\
}

struct RMethod {
    struct RBasic basic;
    struct node *node;
    struct RClass *origin;
    ID id;
    enum mth_scope { MTH_METHOD, MTH_FUNC, MTH_UNDEF } scope;
};

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
#define RMETHOD(obj) (R_CAST(RMethod)(obj))
#define RSTRUCT(obj) (R_CAST(RStruct)(obj))
#define RBIGNUM(obj) (R_CAST(RBignum)(obj))

#define Qnil (VALUE)0

#define ALLOC_N(type,n) (type*)xmalloc(sizeof(type)*(n))
#define ALLOC(type) (type*)xmalloc(sizeof(type))
#define REALLOC_N(var,type,n) (var)=(type*)xrealloc((char*)(var),sizeof(type)*(n))

extern struct gc_list {
    int n;
    VALUE *varptr;
    struct gc_list *next;
} *GC_List;

#define GC_LINK { struct gc_list *_oldgc = GC_List;

#define GC_PRO(var) {\
    struct gc_list *_tmp = (struct gc_list*)alloca(sizeof(struct gc_list));\
    _tmp->next = GC_List;\
    _tmp->varptr = (VALUE*)&(var);\
    _tmp->n = 1;\
    GC_List = _tmp;\
}
#define GC_PRO2(var) GC_PRO3((var),Qnil)
#define GC_PRO3(var,init) {\
    (var) = (init);\
    GC_PRO(var);\
}
#define GC_PRO4(var,nelt) {\
    GC_PRO(var[0]);\
    GC_List->n = nelt;\
}

#define GC_UNLINK GC_List = _oldgc; }

VALUE rb_define_class();
VALUE rb_define_module();

void rb_define_variable();
void rb_define_const();

void rb_define_method();
void rb_define_func();
void rb_define_single_method();
void rb_define_mfunc();
void rb_undef_method();
void rb_define_alias();
void rb_define_attr();

ID rb_intern();
char *rb_id2name();

VALUE rb_funcall();
int rb_scan_args();

VALUE rb_yield();

extern int verbose, debug;

#endif
