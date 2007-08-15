/* -*- C -*-
 * $Id: dl.h,v 1.9 2003/12/01 23:02:44 ttate Exp $
 */

#ifndef RUBY_DL_H
#define RUBY_DL_H

#include <ruby.h>
#include <dlconfig.h>

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
# if defined(HAVE_WINDOWS_H)
#   include <windows.h>
#   define dlclose(ptr) FreeLibrary((HINSTANCE)ptr)
#   define dlopen(name,flag) ((void*)LoadLibrary(name))
#   define dlerror()    "unknown error"
#   define dlsym(handle,name) ((void*)GetProcAddress(handle,name))
#   define RTLD_LAZY -1
#   define RTLD_NOW  -1
#   define RTLD_GLOBAL -1
# endif
#endif

#if !defined(StringValue)
# define StringValue(v) if(TYPE(v) != T_STRING) v = rb_str_to_str(v)
#endif
#if !defined(StringValuePtr)
# define StringValuePtr(v) RSTRING((TYPE(v) == T_STRING) ? (v) : rb_str_to_str(v))->ptr
#endif

#ifdef DEBUG
#define DEBUG_CODE(b) {printf("DEBUG:%d\n",__LINE__);b;}
#define DEBUG_CODE2(b1,b2) {printf("DEBUG:%d\n",__LINE__);b1;}
#else
#define DEBUG_CODE(b)
#define DEBUG_CODE2(b1,b2) b2
#endif

#define VOID_DLTYPE   0x00
#define CHAR_DLTYPE   0x01
#define SHORT_DLTYPE  0x02
#define INT_DLTYPE    0x03
#define LONG_DLTYPE   0x04
#define FLOAT_DLTYPE  0x05
#define DOUBLE_DLTYPE 0x06
#define VOIDP_DLTYPE  0x07

#define ARG_TYPE(x,i) (((x) & (0x07 << ((i)*3))) >> ((i)*3))
#define PUSH_ARG(x,t) do{x <<= 3; x |= t;}while(0)
#define PUSH_0(x) PUSH_ARG(x,VOID_DLTYPE)

#if SIZEOF_INT == SIZEOF_LONG
# define PUSH_I(x) PUSH_ARG(x,LONG_DLTYPE)
# define ANY2I(x)  x.l
# define DLINT(x)  (long)x
#else
# define PUSH_I(x) PUSH_ARG(x,INT_DLTYPE)
# define ANY2I(x)  x.i
# define DLINT(x)  (int)x
#endif
#define PUSH_L(x) PUSH_ARG(x,LONG_DLTYPE)
#define ANY2L(x)  x.l
#define DLLONG(x) (long)x

#if defined(WITH_TYPE_FLOAT)
# if SIZEOF_FLOAT == SIZEOF_DOUBLE
#   define PUSH_F(x) PUSH_ARG(x,DOUBLE_DLTYPE)
#   define ANY2F(x)  (x.d)
#   define DLFLOAT(x) ((double)x)
# else
#   define PUSH_F(x) PUSH_ARG(x,FLOAT_DLTYPE)
#   define ANY2F(x)  (x.f)
#   define DLFLOAT(x) ((float)x)
# endif
#else
# define PUSH_F(x) PUSH_ARG(x,DOUBLE_DLTYPE)
# define ANY2F(x)  (x.d)
# define DLFLOAT(x) ((double)x)
#endif
#define PUSH_D(x) PUSH_ARG(x,DOUBLE_DLTYPE)
#define ANY2D(x)  (x.d)
#define DLDOUBLE(x) ((double)x)

#if SIZEOF_INT == SIZEOF_VOIDP && SIZEOF_INT != SIZEOF_LONG
# define PUSH_P(x) PUSH_ARG(x,INT_DLTYPE)
# define ANY2P(x)  (x.i)
# define DLVOIDP(x) ((int)x)
#elif SIZEOF_LONG == SIZEOF_VOIDP
# define PUSH_P(x) PUSH_ARG(x,LONG_DLTYPE)
# define ANY2P(x)  (x.l)
# define DLVOIDP(x) ((long)x)
#else
# define PUSH_P(x) PUSH_ARG(x,VOIDP_DLTYPE)
# define ANY2P(x)  (x.p)
# define DLVOIDP(x) ((void*)p)
#endif

#if defined(WITH_TYPE_CHAR)
# define PUSH_C(x) PUSH_ARG(x,CHAR_DLTYPE)
# define ANY2C(x)  (x.c)
# define DLCHAR(x) ((char)x)
#else
# define PUSH_C(x) PUSH_I(x)
# define ANY2C(x)  ANY2I(x)
# define DLCHAR(x) DLINT(x)
#endif

#if defined(WITH_TYPE_SHORT)
# define PUSH_H(x) PUSH_ARG(x,SHORT_DLTYPE)
# define ANY2H(x)  (x.h)
# define DLSHORT(x) ((short)x)
#else
# define PUSH_H(x) PUSH_I(x)
# define ANY2H(x)  ANY2I(x)
# define DLSHORT(x) DLINT(x)
#endif

#define PUSH_S(x) PUSH_P(x)
#define ANY2S(x) ANY2P(x)
#define DLSTR(x) DLVOIDP(x)

#define CBPUSH_0(x) PUSH_0(x)
#define CBPUSH_C(x) PUSH_C(x)
#define CBPUSH_H(x) PUSH_H(x)
#define CBPUSH_I(x) PUSH_I(x)
#define CBPUSH_L(x) PUSH_L(x)
#define CBPUSH_F(x) PUSH_F(x)
#define CBPUSH_D(x) PUSH_D(x)
#if defined(WITH_CBTYPE_VOIDP)
# define CBPUSH_P(x) PUSH_ARG(x,VOIDP_DLTYPE)
#else
# define CBPUSH_P(x) PUSH_P(x)
#endif


#if defined(USE_INLINE_ASM)
# if defined(__i386__) && defined(__GNUC__)
#   define DLSTACK
#   define DLSTACK_METHOD "asm"
#   define DLSTACK_REVERSE
#   define DLSTACK_PROTO
#   define DLSTACK_ARGS
#   define DLSTACK_START(sym)
#   define DLSTACK_END(sym)
#   define DLSTACK_PUSH_C(x) asm volatile ("pushl %0" :: "g" (x));
#   define DLSTACK_PUSH_H(x) asm volatile ("pushl %0" :: "g" (x));
#   define DLSTACK_PUSH_I(x) asm volatile ("pushl %0" :: "g" (x));
#   define DLSTACK_PUSH_L(x) asm volatile ("pushl %0" :: "g" (x));
#   define DLSTACK_PUSH_P(x) asm volatile ("pushl %0" :: "g" (x));
#   define DLSTACK_PUSH_F(x) asm volatile ("flds %0"::"g"(x));\
                             asm volatile ("subl $4,%esp");\
                             asm volatile ("fstps (%esp)");
#   define DLSTACK_PUSH_D(x) asm volatile ("fldl %0"::"g"(x));\
                             asm volatile ("subl $8,%esp");\
                             asm volatile ("fstpl (%esp)")
# else
# error --with-asm is not supported on this machine
# endif
#elif defined(USE_DLSTACK)
# define DLSTACK
# define DLSTACK_GUARD
# define DLSTACK_METHOD "dl"
# define DLSTACK_PROTO long,long,long,long,long,\
                       long,long,long,long,long,\
                       long,long,long,long,long
# define DLSTACK_ARGS  stack[0],stack[1],stack[2],stack[3],stack[4],\
                       stack[5],stack[6],stack[7],stack[8],stack[9],\
                       stack[10],stack[11],stack[12],stack[13],stack[14]
# define DLSTACK_SIZE  (sizeof(long)*15)
# define DLSTACK_START(sym)
# define DLSTACK_END(sym)
# define DLSTACK_PUSH_C(x)  {long v=(long)x; memcpy(sp,&v,sizeof(long)); sp++;}
# define DLSTACK_PUSH_H(x)  {long v=(long)x; memcpy(sp,&v,sizeof(long)); sp++;}
# define DLSTACK_PUSH_I(x)  {long v=(long)x; memcpy(sp,&v,sizeof(long)); sp++;}
# define DLSTACK_PUSH_L(x)  memcpy(sp,&x,sizeof(long)); sp++;
# define DLSTACK_PUSH_P(x)  memcpy(sp,&x,sizeof(void*)); sp++;
# define DLSTACK_PUSH_F(x)  memcpy(sp,&x,sizeof(float)); sp+=sizeof(float)/sizeof(long);
# define DLSTACK_PUSH_D(x)  memcpy(sp,&x,sizeof(double)); sp+=sizeof(double)/sizeof(long);
#else
# define DLSTACK_METHOD "none"
#endif

extern VALUE rb_mDL;
extern VALUE rb_mDLMemorySpace;
extern VALUE rb_cDLHandle;
extern VALUE rb_cDLSymbol;
extern VALUE rb_cDLPtrData;
extern VALUE rb_cDLStructData;

extern VALUE rb_eDLError;
extern VALUE rb_eDLTypeError;

#if defined(LONG2NUM) && (SIZEOF_LONG == SIZEOF_VOIDP)
# define DLLONG2NUM(x) LONG2NUM((long)x)
# define DLNUM2LONG(x) (long)(NUM2LONG(x))
#else
# define DLLONG2NUM(x) INT2NUM((long)x)
# define DLNUM2LONG(x) (long)(NUM2INT(x))
#endif

typedef struct { char c; void *x; } s_voidp;
typedef struct { char c; short x; } s_short;
typedef struct { char c; int x; } s_int;
typedef struct { char c; long x; } s_long;
typedef struct { char c; float x; } s_float;
typedef struct { char c; double x; } s_double;

#define ALIGN_VOIDP  (sizeof(s_voidp) - sizeof(void *))
#define ALIGN_SHORT  (sizeof(s_short) - sizeof(short))
#define ALIGN_INT    (sizeof(s_int) - sizeof(int))
#define ALIGN_LONG   (sizeof(s_long) - sizeof(long))
#define ALIGN_FLOAT  (sizeof(s_float) - sizeof(float))
#define ALIGN_DOUBLE (sizeof(s_double) - sizeof(double))

/* for compatibility */
#define VOIDP_ALIGN  ALIGN_VOIDP
#define SHORT_ALIGN  ALIGN_SHORT
#define INT_ALIGN    ALIGN_INT
#define LONG_ALIGN   ALIGN_LONG
#define FLOAT_ALIGN  ALIGN_FLOAT
#define DOUBLE_ALIGN ALIGN_DOUBLE

#define DLALIGN(ptr,offset,align) {\
  while( (((unsigned long)((char *)ptr + offset)) % align) != 0 ) offset++;\
}

typedef void (*freefunc_t)(void *);
#define DLFREEFUNC(func) ((freefunc_t)(func))

typedef union {
  void*  p;
  char   c;
  short  h;
  int    i;
  long   l;
  float  f;
  double d;
  char  *s;
} ANY_TYPE;

struct dl_handle {
  void *ptr;
  int  open;
  int  enable_close;
};

struct sym_data {
  void *func;
  char *name;
  char *type;
  int  len;
};

enum DLPTR_CTYPE {
  DLPTR_CTYPE_UNKNOWN,
  DLPTR_CTYPE_STRUCT,
  DLPTR_CTYPE_UNION
};

struct ptr_data {
  void *ptr;       /* a pointer to the data */
  freefunc_t free; /* free() */
  char *stype;      /* array of type specifiers */
  int  *ssize;      /* size[i] = sizeof(type[i]) > 0 */
  int  slen;   /* the number of type specifiers */
  ID   *ids;
  int  ids_num;
  int  ctype; /* DLPTR_CTYPE_UNKNOWN, DLPTR_CTYPE_STRUCT, DLPTR_CTYPE_UNION */
  long size;
};

#define RDLPTR(obj)  ((struct ptr_data *)(DATA_PTR(obj)))
#define RDLSYM(obj)  ((struct sym_data *)(DATA_PTR(obj)))

void dlfree(void*);
void *dlmalloc(size_t);
void *dlrealloc(void*,size_t);
char *dlstrdup(const char *);
size_t dlsizeof(const char *);

void *rb_ary2cary(char t, VALUE ary, long *size);

/*
void rb_dlmem_delete(void *ptr);
void rb_dlmem_aset(void *ptr, VALUE obj);
VALUE rb_dlmem_aref(void *ptr);
*/

void dlptr_free(struct ptr_data *data);
void dlptr_init(VALUE val);

VALUE rb_dlptr_new(void *ptr, long size, freefunc_t func);
VALUE rb_dlptr_new2(VALUE klass, void *ptr, long size, freefunc_t func);
VALUE rb_dlptr_malloc(long size, freefunc_t func);
void *rb_dlptr2cptr(VALUE val);

VALUE rb_dlsym_new(void (*func)(), const char *name, const char *type);
freefunc_t rb_dlsym2csym(VALUE val);


#endif /* RUBY_DL_H */
