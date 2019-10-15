/**********************************************************************

  ruby/ruby.h -

  $Author$
  created at: Thu Jun 10 14:26:32 JST 1993

  Copyright (C) 1993-2008 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifndef RUBY_RUBY_H
#define RUBY_RUBY_H 1

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

#include "defines.h"
#include "ruby/assert.h"

/* For MinGW, we need __declspec(dllimport) for RUBY_EXTERN on MJIT.
   mswin's RUBY_EXTERN already has that. See also: win32/Makefile.sub */
#if defined(MJIT_HEADER) && defined(_WIN32) && defined(__GNUC__)
# undef RUBY_EXTERN
# define RUBY_EXTERN extern __declspec(dllimport)
#endif

#if defined(__cplusplus)
/* __builtin_choose_expr and __builtin_types_compatible aren't available
 * on C++.  See https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
# undef HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P
#elif GCC_VERSION_BEFORE(4,8,6) /* Bug #14221 */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
#endif

#ifndef ASSUME
# ifdef UNREACHABLE
#   define ASSUME(x) (RB_LIKELY(!!(x)) ? (void)0 : UNREACHABLE)
# else
#   define ASSUME(x) ((void)(x))
# endif
#endif
#ifndef UNREACHABLE_RETURN
# ifdef UNREACHABLE
#  define UNREACHABLE_RETURN(val) UNREACHABLE
# else
#  define UNREACHABLE_RETURN(val) return (val)
# endif
#endif
#ifndef UNREACHABLE
# define UNREACHABLE ((void)0)	/* unreachable */
#endif

#define RUBY_MACRO_SELECT(base, n) TOKEN_PASTE(base, n)

#ifdef HAVE_INTRINSICS_H
# include <intrinsics.h>
#endif

#include <stdarg.h>

RUBY_SYMBOL_EXPORT_BEGIN

/* Make alloca work the best possible way.  */
#ifdef __GNUC__
# ifndef alloca
#  define alloca __builtin_alloca
# endif
#else
# ifdef HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifdef _AIX
#pragma alloca
#  else
#   ifndef alloca		/* predefined by HP cc +Olibcalls */
void *alloca();
#   endif
#  endif /* AIX */
# endif	/* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#if defined HAVE_UINTPTR_T && 0
typedef uintptr_t VALUE;
typedef uintptr_t ID;
# define SIGNED_VALUE intptr_t
# define SIZEOF_VALUE SIZEOF_UINTPTR_T
# undef PRI_VALUE_PREFIX
#elif SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long VALUE;
typedef unsigned long ID;
# define SIGNED_VALUE long
# define SIZEOF_VALUE SIZEOF_LONG
# define PRI_VALUE_PREFIX "l"
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG VALUE;
typedef unsigned LONG_LONG ID;
# define SIGNED_VALUE LONG_LONG
# define LONG_LONG_VALUE 1
# define SIZEOF_VALUE SIZEOF_LONG_LONG
# define PRI_VALUE_PREFIX PRI_LL_PREFIX
#else
# error ---->> ruby requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif

typedef char ruby_check_sizeof_int[SIZEOF_INT == sizeof(int) ? 1 : -1];
typedef char ruby_check_sizeof_long[SIZEOF_LONG == sizeof(long) ? 1 : -1];
#ifdef HAVE_LONG_LONG
typedef char ruby_check_sizeof_long_long[SIZEOF_LONG_LONG == sizeof(LONG_LONG) ? 1 : -1];
#endif
typedef char ruby_check_sizeof_voidp[SIZEOF_VOIDP == sizeof(void*) ? 1 : -1];

#ifndef PRI_INT_PREFIX
#define PRI_INT_PREFIX ""
#endif
#ifndef PRI_LONG_PREFIX
#define PRI_LONG_PREFIX "l"
#endif
#ifndef PRI_SHORT_PREFIX
#define PRI_SHORT_PREFIX "h"
#endif

#ifndef PRI_64_PREFIX
#if SIZEOF_LONG == 8
#define PRI_64_PREFIX PRI_LONG_PREFIX
#elif SIZEOF_LONG_LONG == 8
#define PRI_64_PREFIX PRI_LL_PREFIX
#endif
#endif

#ifndef PRIdPTR
#define PRIdPTR PRI_PTR_PREFIX"d"
#define PRIiPTR PRI_PTR_PREFIX"i"
#define PRIoPTR PRI_PTR_PREFIX"o"
#define PRIuPTR PRI_PTR_PREFIX"u"
#define PRIxPTR PRI_PTR_PREFIX"x"
#define PRIXPTR PRI_PTR_PREFIX"X"
#endif

#define RUBY_PRI_VALUE_MARK "\v"
#if defined PRIdPTR && !defined PRI_VALUE_PREFIX
#define PRIdVALUE PRIdPTR
#define PRIoVALUE PRIoPTR
#define PRIuVALUE PRIuPTR
#define PRIxVALUE PRIxPTR
#define PRIXVALUE PRIXPTR
#define PRIsVALUE PRIiPTR"" RUBY_PRI_VALUE_MARK
#else
#define PRIdVALUE PRI_VALUE_PREFIX"d"
#define PRIoVALUE PRI_VALUE_PREFIX"o"
#define PRIuVALUE PRI_VALUE_PREFIX"u"
#define PRIxVALUE PRI_VALUE_PREFIX"x"
#define PRIXVALUE PRI_VALUE_PREFIX"X"
#define PRIsVALUE PRI_VALUE_PREFIX"i" RUBY_PRI_VALUE_MARK
#endif
#ifndef PRI_VALUE_PREFIX
# define PRI_VALUE_PREFIX ""
#endif

#ifndef PRI_TIMET_PREFIX
# if SIZEOF_TIME_T == SIZEOF_INT
#  define PRI_TIMET_PREFIX
# elif SIZEOF_TIME_T == SIZEOF_LONG
#  define PRI_TIMET_PREFIX "l"
# elif SIZEOF_TIME_T == SIZEOF_LONG_LONG
#  define PRI_TIMET_PREFIX PRI_LL_PREFIX
# endif
#endif

#if defined PRI_PTRDIFF_PREFIX
#elif SIZEOF_PTRDIFF_T == SIZEOF_INT
# define PRI_PTRDIFF_PREFIX ""
#elif SIZEOF_PTRDIFF_T == SIZEOF_LONG
# define PRI_PTRDIFF_PREFIX "l"
#elif SIZEOF_PTRDIFF_T == SIZEOF_LONG_LONG
# define PRI_PTRDIFF_PREFIX PRI_LL_PREFIX
#endif
#define PRIdPTRDIFF PRI_PTRDIFF_PREFIX"d"
#define PRIiPTRDIFF PRI_PTRDIFF_PREFIX"i"
#define PRIoPTRDIFF PRI_PTRDIFF_PREFIX"o"
#define PRIuPTRDIFF PRI_PTRDIFF_PREFIX"u"
#define PRIxPTRDIFF PRI_PTRDIFF_PREFIX"x"
#define PRIXPTRDIFF PRI_PTRDIFF_PREFIX"X"

#if defined PRI_SIZE_PREFIX
#elif SIZEOF_SIZE_T == SIZEOF_INT
# define PRI_SIZE_PREFIX ""
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define PRI_SIZE_PREFIX "l"
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define PRI_SIZE_PREFIX PRI_LL_PREFIX
#endif
#define PRIdSIZE PRI_SIZE_PREFIX"d"
#define PRIiSIZE PRI_SIZE_PREFIX"i"
#define PRIoSIZE PRI_SIZE_PREFIX"o"
#define PRIuSIZE PRI_SIZE_PREFIX"u"
#define PRIxSIZE PRI_SIZE_PREFIX"x"
#define PRIXSIZE PRI_SIZE_PREFIX"X"

#ifdef __STDC__
# include <limits.h>
#else
# ifndef LONG_MAX
#  ifdef HAVE_LIMITS_H
#   include <limits.h>
#  else
    /* assuming 32bit(2's complement) long */
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

#define RUBY_FIXNUM_MAX (LONG_MAX>>1)
#define RUBY_FIXNUM_MIN RSHIFT((long)LONG_MIN,1)
#define FIXNUM_MAX RUBY_FIXNUM_MAX
#define FIXNUM_MIN RUBY_FIXNUM_MIN

#define RB_INT2FIX(i) (((VALUE)(i))<<1 | RUBY_FIXNUM_FLAG)
#define INT2FIX(i) RB_INT2FIX(i)
#define RB_LONG2FIX(i) RB_INT2FIX(i)
#define LONG2FIX(i) RB_INT2FIX(i)
#define rb_fix_new(v) RB_INT2FIX(v)
VALUE rb_int2inum(intptr_t);

#define rb_int_new(v) rb_int2inum(v)
VALUE rb_uint2inum(uintptr_t);

#define rb_uint_new(v) rb_uint2inum(v)

#ifdef HAVE_LONG_LONG
VALUE rb_ll2inum(LONG_LONG);
#define LL2NUM(v) rb_ll2inum(v)
VALUE rb_ull2inum(unsigned LONG_LONG);
#define ULL2NUM(v) rb_ull2inum(v)
#endif

#ifndef OFFT2NUM
#if SIZEOF_OFF_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
# define OFFT2NUM(v) LL2NUM(v)
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define OFFT2NUM(v) LONG2NUM(v)
#else
# define OFFT2NUM(v) INT2NUM(v)
#endif
#endif

#if SIZEOF_SIZE_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
# define SIZET2NUM(v) ULL2NUM(v)
# define SSIZET2NUM(v) LL2NUM(v)
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define SIZET2NUM(v) ULONG2NUM(v)
# define SSIZET2NUM(v) LONG2NUM(v)
#else
# define SIZET2NUM(v) UINT2NUM(v)
# define SSIZET2NUM(v) INT2NUM(v)
#endif

#ifndef SIZE_MAX
# if SIZEOF_SIZE_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
#   define SIZE_MAX ULLONG_MAX
#   define SIZE_MIN ULLONG_MIN
# elif SIZEOF_SIZE_T == SIZEOF_LONG
#   define SIZE_MAX ULONG_MAX
#   define SIZE_MIN ULONG_MIN
# elif SIZEOF_SIZE_T == SIZEOF_INT
#   define SIZE_MAX UINT_MAX
#   define SIZE_MIN UINT_MIN
# else
#   define SIZE_MAX USHRT_MAX
#   define SIZE_MIN USHRT_MIN
# endif
#endif

#ifndef SSIZE_MAX
# if SIZEOF_SIZE_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
#   define SSIZE_MAX LLONG_MAX
#   define SSIZE_MIN LLONG_MIN
# elif SIZEOF_SIZE_T == SIZEOF_LONG
#   define SSIZE_MAX LONG_MAX
#   define SSIZE_MIN LONG_MIN
# elif SIZEOF_SIZE_T == SIZEOF_INT
#   define SSIZE_MAX INT_MAX
#   define SSIZE_MIN INT_MIN
# else
#   define SSIZE_MAX SHRT_MAX
#   define SSIZE_MIN SHRT_MIN
# endif
#endif

#if SIZEOF_INT < SIZEOF_VALUE
NORETURN(void rb_out_of_int(SIGNED_VALUE num));
#endif

#if SIZEOF_INT < SIZEOF_LONG
static inline int
rb_long2int_inline(long n)
{
    int i = (int)n;
    if ((long)i != n)
	rb_out_of_int(n);

    return i;
}
#define rb_long2int(n) rb_long2int_inline(n)
#else
#define rb_long2int(n) ((int)(n))
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
#ifndef NUM2MODET
#define NUM2MODET(v) NUM2INT(v)
#endif
#ifndef MODET2NUM
#define MODET2NUM(v) INT2NUM(v)
#endif

#define RB_FIX2LONG(x) ((long)RSHIFT((SIGNED_VALUE)(x),1))
static inline long
rb_fix2long(VALUE x)
{
    return RB_FIX2LONG(x);
}
#define RB_FIX2ULONG(x) ((unsigned long)RB_FIX2LONG(x))
static inline unsigned long
rb_fix2ulong(VALUE x)
{
    return RB_FIX2ULONG(x);
}
#define RB_FIXNUM_P(f) (((int)(SIGNED_VALUE)(f))&RUBY_FIXNUM_FLAG)
#define RB_POSFIXABLE(f) ((f) < RUBY_FIXNUM_MAX+1)
#define RB_NEGFIXABLE(f) ((f) >= RUBY_FIXNUM_MIN)
#define RB_FIXABLE(f) (RB_POSFIXABLE(f) && RB_NEGFIXABLE(f))
#define FIX2LONG(x) RB_FIX2LONG(x)
#define FIX2ULONG(x) RB_FIX2ULONG(x)
#define FIXNUM_P(f) RB_FIXNUM_P(f)
#define POSFIXABLE(f) RB_POSFIXABLE(f)
#define NEGFIXABLE(f) RB_NEGFIXABLE(f)
#define FIXABLE(f) RB_FIXABLE(f)

#define RB_IMMEDIATE_P(x) ((VALUE)(x) & RUBY_IMMEDIATE_MASK)
#define IMMEDIATE_P(x) RB_IMMEDIATE_P(x)

ID rb_sym2id(VALUE);
VALUE rb_id2sym(ID);
#define RB_STATIC_SYM_P(x) (((VALUE)(x)&~((~(VALUE)0)<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG)
#define RB_DYNAMIC_SYM_P(x) (!RB_SPECIAL_CONST_P(x) && RB_BUILTIN_TYPE(x) == (RUBY_T_SYMBOL))
#define RB_SYMBOL_P(x) (RB_STATIC_SYM_P(x)||RB_DYNAMIC_SYM_P(x))
#define RB_ID2SYM(x) (rb_id2sym(x))
#define RB_SYM2ID(x) (rb_sym2id(x))
#define STATIC_SYM_P(x) RB_STATIC_SYM_P(x)
#define DYNAMIC_SYM_P(x) RB_DYNAMIC_SYM_P(x)
#define SYMBOL_P(x) RB_SYMBOL_P(x)
#define ID2SYM(x) RB_ID2SYM(x)
#define SYM2ID(x) RB_SYM2ID(x)

#ifndef USE_FLONUM
#if SIZEOF_VALUE >= SIZEOF_DOUBLE
#define USE_FLONUM 1
#else
#define USE_FLONUM 0
#endif
#endif

#if USE_FLONUM
#define RB_FLONUM_P(x) ((((int)(SIGNED_VALUE)(x))&RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG)
#else
#define RB_FLONUM_P(x) 0
#endif
#define FLONUM_P(x) RB_FLONUM_P(x)

/* Module#methods, #singleton_methods and so on return Symbols */
#define USE_SYMBOL_AS_METHOD_NAME 1

/* special constants - i.e. non-zero and non-fixnum constants */
enum ruby_special_consts {
#if USE_FLONUM
    RUBY_Qfalse = 0x00,		/* ...0000 0000 */
    RUBY_Qtrue  = 0x14,		/* ...0001 0100 */
    RUBY_Qnil   = 0x08,		/* ...0000 1000 */
    RUBY_Qundef = 0x34,		/* ...0011 0100 */

    RUBY_IMMEDIATE_MASK = 0x07,
    RUBY_FIXNUM_FLAG    = 0x01,	/* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x03,
    RUBY_FLONUM_FLAG    = 0x02,	/* ...xxxx xx10 */
    RUBY_SYMBOL_FLAG    = 0x0c,	/* ...0000 1100 */
#else
    RUBY_Qfalse = 0,		/* ...0000 0000 */
    RUBY_Qtrue  = 2,		/* ...0000 0010 */
    RUBY_Qnil   = 4,		/* ...0000 0100 */
    RUBY_Qundef = 6,		/* ...0000 0110 */

    RUBY_IMMEDIATE_MASK = 0x03,
    RUBY_FIXNUM_FLAG    = 0x01,	/* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x00,	/* any values ANDed with FLONUM_MASK cannot be FLONUM_FLAG */
    RUBY_FLONUM_FLAG    = 0x02,
    RUBY_SYMBOL_FLAG    = 0x0e,	/* ...0000 1110 */
#endif
    RUBY_SPECIAL_SHIFT  = 8
};

#define RUBY_Qfalse ((VALUE)RUBY_Qfalse)
#define RUBY_Qtrue  ((VALUE)RUBY_Qtrue)
#define RUBY_Qnil   ((VALUE)RUBY_Qnil)
#define RUBY_Qundef ((VALUE)RUBY_Qundef)	/* undefined value for placeholder */
#define Qfalse RUBY_Qfalse
#define Qtrue  RUBY_Qtrue
#define Qnil   RUBY_Qnil
#define Qundef RUBY_Qundef
#define IMMEDIATE_MASK RUBY_IMMEDIATE_MASK
#define FIXNUM_FLAG RUBY_FIXNUM_FLAG
#if USE_FLONUM
#define FLONUM_MASK RUBY_FLONUM_MASK
#define FLONUM_FLAG RUBY_FLONUM_FLAG
#endif
#define SYMBOL_FLAG RUBY_SYMBOL_FLAG

#define RB_TEST(v) !(((VALUE)(v) & (VALUE)~RUBY_Qnil) == 0)
#define RB_NIL_P(v) !((VALUE)(v) != RUBY_Qnil)
#define RTEST(v) RB_TEST(v)
#define NIL_P(v) RB_NIL_P(v)

#define CLASS_OF(v) rb_class_of((VALUE)(v))

enum ruby_value_type {
    RUBY_T_NONE   = 0x00,

    RUBY_T_OBJECT = 0x01,
    RUBY_T_CLASS  = 0x02,
    RUBY_T_MODULE = 0x03,
    RUBY_T_FLOAT  = 0x04,
    RUBY_T_STRING = 0x05,
    RUBY_T_REGEXP = 0x06,
    RUBY_T_ARRAY  = 0x07,
    RUBY_T_HASH   = 0x08,
    RUBY_T_STRUCT = 0x09,
    RUBY_T_BIGNUM = 0x0a,
    RUBY_T_FILE   = 0x0b,
    RUBY_T_DATA   = 0x0c,
    RUBY_T_MATCH  = 0x0d,
    RUBY_T_COMPLEX  = 0x0e,
    RUBY_T_RATIONAL = 0x0f,

    RUBY_T_NIL    = 0x11,
    RUBY_T_TRUE   = 0x12,
    RUBY_T_FALSE  = 0x13,
    RUBY_T_SYMBOL = 0x14,
    RUBY_T_FIXNUM = 0x15,
    RUBY_T_UNDEF  = 0x16,

    RUBY_T_IMEMO  = 0x1a, /*!< @see imemo_type */
    RUBY_T_NODE   = 0x1b,
    RUBY_T_ICLASS = 0x1c,
    RUBY_T_ZOMBIE = 0x1d,
    RUBY_T_MOVED  = 0x1e,

    RUBY_T_MASK   = 0x1f
};

#define T_NONE   RUBY_T_NONE
#define T_NIL    RUBY_T_NIL
#define T_OBJECT RUBY_T_OBJECT
#define T_CLASS  RUBY_T_CLASS
#define T_ICLASS RUBY_T_ICLASS
#define T_MODULE RUBY_T_MODULE
#define T_FLOAT  RUBY_T_FLOAT
#define T_STRING RUBY_T_STRING
#define T_REGEXP RUBY_T_REGEXP
#define T_ARRAY  RUBY_T_ARRAY
#define T_HASH   RUBY_T_HASH
#define T_STRUCT RUBY_T_STRUCT
#define T_BIGNUM RUBY_T_BIGNUM
#define T_FILE   RUBY_T_FILE
#define T_FIXNUM RUBY_T_FIXNUM
#define T_TRUE   RUBY_T_TRUE
#define T_FALSE  RUBY_T_FALSE
#define T_DATA   RUBY_T_DATA
#define T_MATCH  RUBY_T_MATCH
#define T_SYMBOL RUBY_T_SYMBOL
#define T_RATIONAL RUBY_T_RATIONAL
#define T_COMPLEX RUBY_T_COMPLEX
#define T_IMEMO  RUBY_T_IMEMO
#define T_UNDEF  RUBY_T_UNDEF
#define T_NODE   RUBY_T_NODE
#define T_ZOMBIE RUBY_T_ZOMBIE
#define T_MOVED RUBY_T_MOVED
#define T_MASK   RUBY_T_MASK

#define RB_BUILTIN_TYPE(x) (int)(((struct RBasic*)(x))->flags & RUBY_T_MASK)
#define BUILTIN_TYPE(x) RB_BUILTIN_TYPE(x)

static inline int rb_type(VALUE obj);
#define TYPE(x) rb_type((VALUE)(x))

#define RB_FLOAT_TYPE_P(obj) (\
	RB_FLONUM_P(obj) || \
	(!RB_SPECIAL_CONST_P(obj) && RB_BUILTIN_TYPE(obj) == RUBY_T_FLOAT))

#define RB_TYPE_P(obj, type) ( \
	((type) == RUBY_T_FIXNUM) ? RB_FIXNUM_P(obj) : \
	((type) == RUBY_T_TRUE) ? ((obj) == RUBY_Qtrue) : \
	((type) == RUBY_T_FALSE) ? ((obj) == RUBY_Qfalse) : \
	((type) == RUBY_T_NIL) ? ((obj) == RUBY_Qnil) : \
	((type) == RUBY_T_UNDEF) ? ((obj) == RUBY_Qundef) : \
	((type) == RUBY_T_SYMBOL) ? RB_SYMBOL_P(obj) : \
	((type) == RUBY_T_FLOAT) ? RB_FLOAT_TYPE_P(obj) : \
	(!RB_SPECIAL_CONST_P(obj) && RB_BUILTIN_TYPE(obj) == (type)))

#ifdef __GNUC__
#define RB_GC_GUARD(v) \
    (*__extension__ ({ \
	volatile VALUE *rb_gc_guarded_ptr = &(v); \
	__asm__("" : : "m"(rb_gc_guarded_ptr)); \
	rb_gc_guarded_ptr; \
    }))
#elif defined _MSC_VER
#pragma optimize("", off)
static inline volatile VALUE *rb_gc_guarded_ptr(volatile VALUE *ptr) {return ptr;}
#pragma optimize("", on)
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr(&(v)))
#else
volatile VALUE *rb_gc_guarded_ptr_val(volatile VALUE *ptr, VALUE val);
#define HAVE_RB_GC_GUARDED_PTR_VAL 1
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr_val(&(v),(v)))
#endif

#ifdef __GNUC__
#define RB_UNUSED_VAR(x) x __attribute__ ((unused))
#else
#define RB_UNUSED_VAR(x) x
#endif

void rb_check_type(VALUE,int);
#define Check_Type(v,t) rb_check_type((VALUE)(v),(t))

VALUE rb_str_to_str(VALUE);
VALUE rb_string_value(volatile VALUE*);
char *rb_string_value_ptr(volatile VALUE*);
char *rb_string_value_cstr(volatile VALUE*);

#define StringValue(v) rb_string_value(&(v))
#define StringValuePtr(v) rb_string_value_ptr(&(v))
#define StringValueCStr(v) rb_string_value_cstr(&(v))

void rb_check_safe_obj(VALUE);
#define SafeStringValue(v) do {\
    StringValue(v);\
    rb_check_safe_obj(v);\
} while (0)
#if GCC_VERSION_SINCE(4,4,0)
void rb_check_safe_str(VALUE) __attribute__((error("rb_check_safe_str() and Check_SafeStr() are obsolete; use SafeStringValue() instead")));
# define Check_SafeStr(v) rb_check_safe_str((VALUE)(v))
#else
# define rb_check_safe_str(x) [<"rb_check_safe_str() is obsolete; use SafeStringValue() instead">]
# define Check_SafeStr(v) [<"Check_SafeStr() is obsolete; use SafeStringValue() instead">]
#endif

VALUE rb_str_export(VALUE);
#define ExportStringValue(v) do {\
    SafeStringValue(v);\
   (v) = rb_str_export(v);\
} while (0)
VALUE rb_str_export_locale(VALUE);

VALUE rb_get_path(VALUE);
#define FilePathValue(v) (RB_GC_GUARD(v) = rb_get_path(v))

VALUE rb_get_path_no_checksafe(VALUE);
#define FilePathStringValue(v) ((v) = rb_get_path_no_checksafe(v))

#define RUBY_SAFE_LEVEL_MAX 1
void rb_secure(int);
int rb_safe_level(void);
void rb_set_safe_level(int);
#if GCC_VERSION_SINCE(4,4,0)
int ruby_safe_level_2_error(void) __attribute__((error("$SAFE=2 to 4 are obsolete")));
int ruby_safe_level_2_warning(void) __attribute__((const,warning("$SAFE=2 to 4 are obsolete")));
# ifdef RUBY_EXPORT
#   define ruby_safe_level_2_warning() ruby_safe_level_2_error()
# endif
# if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#  define RUBY_SAFE_LEVEL_INVALID_P(level) \
    __extension__(\
	__builtin_choose_expr(\
	    __builtin_constant_p(level), \
	    ((level) < 0 || RUBY_SAFE_LEVEL_MAX < (level)), 0))
#  define RUBY_SAFE_LEVEL_CHECK(level, type) \
    __extension__(__builtin_choose_expr(RUBY_SAFE_LEVEL_INVALID_P(level), ruby_safe_level_2_##type(), (level)))
# else
/* in gcc 4.8 or earlier, __builtin_choose_expr() does not consider
 * __builtin_constant_p(variable) a constant expression.
 */
#  define RUBY_SAFE_LEVEL_INVALID_P(level) \
    __extension__(__builtin_constant_p(level) && \
		  ((level) < 0 || RUBY_SAFE_LEVEL_MAX < (level)))
#  define RUBY_SAFE_LEVEL_CHECK(level, type) \
    (RUBY_SAFE_LEVEL_INVALID_P(level) ? ruby_safe_level_2_##type() : (level))
# endif
# define rb_secure(level) rb_secure(RUBY_SAFE_LEVEL_CHECK(level, warning))
# define rb_set_safe_level(level) rb_set_safe_level(RUBY_SAFE_LEVEL_CHECK(level, error))
#endif
void rb_set_safe_level_force(int);
void rb_secure_update(VALUE);
NORETURN(void rb_insecure_operation(void));

VALUE rb_errinfo(void);
void rb_set_errinfo(VALUE);

long rb_num2long(VALUE);
unsigned long rb_num2ulong(VALUE);
static inline long
rb_num2long_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
	return RB_FIX2LONG(x);
    else
	return rb_num2long(x);
}
#define RB_NUM2LONG(x) rb_num2long_inline(x)
#define NUM2LONG(x) RB_NUM2LONG(x)
static inline unsigned long
rb_num2ulong_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
	return RB_FIX2ULONG(x);
    else
	return rb_num2ulong(x);
}
#define RB_NUM2ULONG(x) rb_num2ulong_inline(x)
#define NUM2ULONG(x) RB_NUM2ULONG(x)
#if SIZEOF_INT < SIZEOF_LONG
long rb_num2int(VALUE);
long rb_fix2int(VALUE);
#define RB_FIX2INT(x) ((int)rb_fix2int((VALUE)(x)))

static inline int
rb_num2int_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
	return (int)rb_fix2int(x);
    else
	return (int)rb_num2int(x);
}
#define RB_NUM2INT(x) rb_num2int_inline(x)

unsigned long rb_num2uint(VALUE);
#define RB_NUM2UINT(x) ((unsigned int)rb_num2uint(x))
unsigned long rb_fix2uint(VALUE);
#define RB_FIX2UINT(x) ((unsigned int)rb_fix2uint(x))
#else /* SIZEOF_INT < SIZEOF_LONG */
#define RB_NUM2INT(x) ((int)RB_NUM2LONG(x))
#define RB_NUM2UINT(x) ((unsigned int)RB_NUM2ULONG(x))
#define RB_FIX2INT(x) ((int)RB_FIX2LONG(x))
#define RB_FIX2UINT(x) ((unsigned int)RB_FIX2ULONG(x))
#endif /* SIZEOF_INT < SIZEOF_LONG */
#define NUM2INT(x)  RB_NUM2INT(x)
#define NUM2UINT(x) RB_NUM2UINT(x)
#define FIX2INT(x)  RB_FIX2INT(x)
#define FIX2UINT(x) RB_FIX2UINT(x)

short rb_num2short(VALUE);
unsigned short rb_num2ushort(VALUE);
short rb_fix2short(VALUE);
unsigned short rb_fix2ushort(VALUE);
#define RB_FIX2SHORT(x) (rb_fix2short((VALUE)(x)))
#define FIX2SHORT(x) RB_FIX2SHORT(x)
static inline short
rb_num2short_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
	return rb_fix2short(x);
    else
	return rb_num2short(x);
}

#define RB_NUM2SHORT(x) rb_num2short_inline(x)
#define RB_NUM2USHORT(x) rb_num2ushort(x)
#define NUM2SHORT(x) RB_NUM2SHORT(x)
#define NUM2USHORT(x) RB_NUM2USHORT(x)

#ifdef HAVE_LONG_LONG
LONG_LONG rb_num2ll(VALUE);
unsigned LONG_LONG rb_num2ull(VALUE);
static inline LONG_LONG
rb_num2ll_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
	return RB_FIX2LONG(x);
    else
	return rb_num2ll(x);
}
# define RB_NUM2LL(x) rb_num2ll_inline(x)
# define RB_NUM2ULL(x) rb_num2ull(x)
# define NUM2LL(x) RB_NUM2LL(x)
# define NUM2ULL(x) RB_NUM2ULL(x)
#endif

#if !defined(NUM2OFFT)
# if defined(HAVE_LONG_LONG) && SIZEOF_OFF_T > SIZEOF_LONG
#  define NUM2OFFT(x) ((off_t)NUM2LL(x))
# else
#  define NUM2OFFT(x) NUM2LONG(x)
# endif
#endif

#if defined(HAVE_LONG_LONG) && SIZEOF_SIZE_T > SIZEOF_LONG
# define NUM2SIZET(x) ((size_t)NUM2ULL(x))
# define NUM2SSIZET(x) ((ssize_t)NUM2LL(x))
#else
# define NUM2SIZET(x) NUM2ULONG(x)
# define NUM2SSIZET(x) NUM2LONG(x)
#endif

double rb_num2dbl(VALUE);
#define NUM2DBL(x) rb_num2dbl((VALUE)(x))

VALUE rb_uint2big(uintptr_t);
VALUE rb_int2big(intptr_t);

VALUE rb_newobj(void);
VALUE rb_newobj_of(VALUE, VALUE);
VALUE rb_obj_setup(VALUE obj, VALUE klass, VALUE type);
#define RB_NEWOBJ(obj,type) type *(obj) = (type*)rb_newobj()
#define RB_NEWOBJ_OF(obj,type,klass,flags) type *(obj) = (type*)rb_newobj_of(klass, flags)
#define NEWOBJ(obj,type) RB_NEWOBJ(obj,type)
#define NEWOBJ_OF(obj,type,klass,flags) RB_NEWOBJ_OF(obj,type,klass,flags) /* core has special NEWOBJ_OF() in internal.h */
#define OBJSETUP(obj,c,t) rb_obj_setup(obj, c, t) /* use NEWOBJ_OF instead of NEWOBJ()+OBJSETUP() */
#define CLONESETUP(clone,obj) rb_clone_setup(clone,obj)
#define DUPSETUP(dup,obj) rb_dup_setup(dup,obj)

#ifndef USE_RGENGC
#define USE_RGENGC 1
#ifndef USE_RINCGC
#define USE_RINCGC 1
#endif
#endif

#if USE_RGENGC == 0
#define USE_RINCGC 0
#endif

#ifndef RGENGC_WB_PROTECTED_ARRAY
#define RGENGC_WB_PROTECTED_ARRAY 1
#endif
#ifndef RGENGC_WB_PROTECTED_HASH
#define RGENGC_WB_PROTECTED_HASH 1
#endif
#ifndef RGENGC_WB_PROTECTED_STRUCT
#define RGENGC_WB_PROTECTED_STRUCT 1
#endif
#ifndef RGENGC_WB_PROTECTED_STRING
#define RGENGC_WB_PROTECTED_STRING 1
#endif
#ifndef RGENGC_WB_PROTECTED_OBJECT
#define RGENGC_WB_PROTECTED_OBJECT 1
#endif
#ifndef RGENGC_WB_PROTECTED_REGEXP
#define RGENGC_WB_PROTECTED_REGEXP 1
#endif
#ifndef RGENGC_WB_PROTECTED_CLASS
#define RGENGC_WB_PROTECTED_CLASS 1
#endif
#ifndef RGENGC_WB_PROTECTED_FLOAT
#define RGENGC_WB_PROTECTED_FLOAT 1
#endif
#ifndef RGENGC_WB_PROTECTED_COMPLEX
#define RGENGC_WB_PROTECTED_COMPLEX 1
#endif
#ifndef RGENGC_WB_PROTECTED_RATIONAL
#define RGENGC_WB_PROTECTED_RATIONAL 1
#endif
#ifndef RGENGC_WB_PROTECTED_BIGNUM
#define RGENGC_WB_PROTECTED_BIGNUM 1
#endif
#ifndef RGENGC_WB_PROTECTED_NODE_CREF
#define RGENGC_WB_PROTECTED_NODE_CREF 1
#endif

#ifdef __GNUC__
__extension__
#endif
enum ruby_fl_type {
    RUBY_FL_WB_PROTECTED = (1<<5),
    RUBY_FL_PROMOTED0 = (1<<5),
    RUBY_FL_PROMOTED1 = (1<<6),
    RUBY_FL_PROMOTED  = RUBY_FL_PROMOTED0|RUBY_FL_PROMOTED1,
    RUBY_FL_FINALIZE  = (1<<7),
    RUBY_FL_TAINT     = (1<<8),
    RUBY_FL_UNTRUSTED = RUBY_FL_TAINT,
    RUBY_FL_SEEN_OBJ_ID = (1<<9),
    RUBY_FL_EXIVAR    = (1<<10),
    RUBY_FL_FREEZE    = (1<<11),

    RUBY_FL_USHIFT    = 12,

#define RUBY_FL_USER_N(n) RUBY_FL_USER##n = (1<<(RUBY_FL_USHIFT+n))
    RUBY_FL_USER_N(0),
    RUBY_FL_USER_N(1),
    RUBY_FL_USER_N(2),
    RUBY_FL_USER_N(3),
    RUBY_FL_USER_N(4),
    RUBY_FL_USER_N(5),
    RUBY_FL_USER_N(6),
    RUBY_FL_USER_N(7),
    RUBY_FL_USER_N(8),
    RUBY_FL_USER_N(9),
    RUBY_FL_USER_N(10),
    RUBY_FL_USER_N(11),
    RUBY_FL_USER_N(12),
    RUBY_FL_USER_N(13),
    RUBY_FL_USER_N(14),
    RUBY_FL_USER_N(15),
    RUBY_FL_USER_N(16),
    RUBY_FL_USER_N(17),
    RUBY_FL_USER_N(18),
#if defined ENUM_OVER_INT || SIZEOF_INT*CHAR_BIT>12+19+1
    RUBY_FL_USER_N(19),
#else
#define RUBY_FL_USER19 (((VALUE)1)<<(RUBY_FL_USHIFT+19))
#endif

    RUBY_ELTS_SHARED = RUBY_FL_USER2,
    RUBY_FL_DUPPED = (RUBY_T_MASK|RUBY_FL_EXIVAR|RUBY_FL_TAINT),
    RUBY_FL_SINGLETON = RUBY_FL_USER0
};

struct RUBY_ALIGNAS(SIZEOF_VALUE) RBasic {
    VALUE flags;
    const VALUE klass;
};

VALUE rb_obj_hide(VALUE obj);
VALUE rb_obj_reveal(VALUE obj, VALUE klass); /* do not use this API to change klass information */

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
# define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    __extension__( \
	__builtin_choose_expr( \
	    RGENGC_WB_PROTECTED_##type, \
	    OBJ_WB_UNPROTECT((VALUE)(obj)), ((VALUE)(obj))))
#else
# define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    (RGENGC_WB_PROTECTED_##type ? \
     OBJ_WB_UNPROTECT((VALUE)(obj)) : ((VALUE)(obj)))
#endif

#define RBASIC_CLASS(obj) (RBASIC(obj)->klass)

#define RVALUE_EMBED_LEN_MAX RVALUE_EMBED_LEN_MAX
enum ruby_rvalue_flags {
    RVALUE_EMBED_LEN_MAX = 3,
};

#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED ROBJECT_EMBED
enum ruby_robject_flags {
    ROBJECT_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    ROBJECT_EMBED = RUBY_FL_USER1,

    ROBJECT_ENUM_END
};

struct RObject {
    struct RBasic basic;
    union {
	struct {
	    uint32_t numiv;
	    VALUE *ivptr;
            void *iv_index_tbl; /* shortcut for RCLASS_IV_INDEX_TBL(rb_obj_class(obj)) */
	} heap;
	VALUE ary[ROBJECT_EMBED_LEN_MAX];
    } as;
};
#define ROBJECT_NUMIV(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     ROBJECT_EMBED_LEN_MAX : \
     ROBJECT(o)->as.heap.numiv)
#define ROBJECT_IVPTR(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     ROBJECT(o)->as.ary : \
     ROBJECT(o)->as.heap.ivptr)
#define ROBJECT_IV_INDEX_TBL(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     RCLASS_IV_INDEX_TBL(rb_obj_class(o)) : \
     ROBJECT(o)->as.heap.iv_index_tbl)

#define RCLASS_SUPER(c) rb_class_get_superclass(c)
#define RMODULE_IV_TBL(m) RCLASS_IV_TBL(m)
#define RMODULE_CONST_TBL(m) RCLASS_CONST_TBL(m)
#define RMODULE_M_TBL(m) RCLASS_M_TBL(m)
#define RMODULE_SUPER(m) RCLASS_SUPER(m)
#define RMODULE_IS_OVERLAID RMODULE_IS_OVERLAID
#define RMODULE_IS_REFINEMENT RMODULE_IS_REFINEMENT
#define RMODULE_INCLUDED_INTO_REFINEMENT RMODULE_INCLUDED_INTO_REFINEMENT
enum ruby_rmodule_flags {
    RMODULE_IS_OVERLAID = RUBY_FL_USER2,
    RMODULE_IS_REFINEMENT = RUBY_FL_USER3,
    RMODULE_INCLUDED_INTO_REFINEMENT = RUBY_FL_USER4,

    RMODULE_ENUM_END
};

PUREFUNC(double rb_float_value(VALUE));
VALUE rb_float_new(double);
VALUE rb_float_new_in_heap(double);

#define RFLOAT_VALUE(v) rb_float_value(v)
#define DBL2NUM(dbl)  rb_float_new(dbl)

#define RUBY_ELTS_SHARED RUBY_ELTS_SHARED
#define ELTS_SHARED RUBY_ELTS_SHARED

#define RSTRING_NOEMBED RSTRING_NOEMBED
#define RSTRING_EMBED_LEN_MASK RSTRING_EMBED_LEN_MASK
#define RSTRING_EMBED_LEN_SHIFT RSTRING_EMBED_LEN_SHIFT
#define RSTRING_EMBED_LEN_MAX RSTRING_EMBED_LEN_MAX
#define RSTRING_FSTR RSTRING_FSTR
enum ruby_rstring_flags {
    RSTRING_NOEMBED = RUBY_FL_USER1,
    RSTRING_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER3|RUBY_FL_USER4|
			      RUBY_FL_USER5|RUBY_FL_USER6),
    RSTRING_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+2),
    RSTRING_EMBED_LEN_MAX = (int)((sizeof(VALUE)*RVALUE_EMBED_LEN_MAX)/sizeof(char)-1),
    RSTRING_FSTR = RUBY_FL_USER17,

    RSTRING_ENUM_END
};

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
	char ary[RSTRING_EMBED_LEN_MAX + 1];
    } as;
};
#define RSTRING_EMBED_LEN(str) \
     (long)((RBASIC(str)->flags >> RSTRING_EMBED_LEN_SHIFT) & \
            (RSTRING_EMBED_LEN_MASK >> RSTRING_EMBED_LEN_SHIFT))
#define RSTRING_LEN(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     RSTRING_EMBED_LEN(str) : \
     RSTRING(str)->as.heap.len)
#define RSTRING_PTR(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     RSTRING(str)->as.ary : \
     RSTRING(str)->as.heap.ptr)
#define RSTRING_END(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     (RSTRING(str)->as.ary + RSTRING_EMBED_LEN(str)) : \
     (RSTRING(str)->as.heap.ptr + RSTRING(str)->as.heap.len))
#define RSTRING_LENINT(str) rb_long2int(RSTRING_LEN(str))
#define RSTRING_GETMEM(str, ptrvar, lenvar) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     ((ptrvar) = RSTRING(str)->as.ary, (lenvar) = RSTRING_EMBED_LEN(str)) : \
     ((ptrvar) = RSTRING(str)->as.heap.ptr, (lenvar) = RSTRING(str)->as.heap.len))

#ifndef USE_TRANSIENT_HEAP
#define USE_TRANSIENT_HEAP 1
#endif

enum ruby_rarray_flags {
    RARRAY_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    RARRAY_EMBED_FLAG = RUBY_FL_USER1,
    /* RUBY_FL_USER2 is for ELTS_SHARED */
    RARRAY_EMBED_LEN_MASK = (RUBY_FL_USER4|RUBY_FL_USER3),
    RARRAY_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+3),

#if USE_TRANSIENT_HEAP
    RARRAY_TRANSIENT_FLAG = RUBY_FL_USER13,
#define RARRAY_TRANSIENT_FLAG RARRAY_TRANSIENT_FLAG
#else
#define RARRAY_TRANSIENT_FLAG 0
#endif

    RARRAY_ENUM_END
};
#define RARRAY_EMBED_FLAG (VALUE)RARRAY_EMBED_FLAG
#define RARRAY_EMBED_LEN_MASK (VALUE)RARRAY_EMBED_LEN_MASK
#define RARRAY_EMBED_LEN_MAX RARRAY_EMBED_LEN_MAX
#define RARRAY_EMBED_LEN_SHIFT RARRAY_EMBED_LEN_SHIFT

struct RArray {
    struct RBasic basic;
    union {
	struct {
	    long len;
	    union {
		long capa;
#if defined(__clang__)      /* <- clang++ is sane */ || \
    !defined(__cplusplus)   /* <- C99 is sane */     || \
    (__cplusplus > 199711L) /* <- C++11 is sane */
                const
#endif
                VALUE shared_root;
	    } aux;
	    const VALUE *ptr;
	} heap;
	const VALUE ary[RARRAY_EMBED_LEN_MAX];
    } as;
};
#define RARRAY_EMBED_LEN(a) \
    (long)((RBASIC(a)->flags >> RARRAY_EMBED_LEN_SHIFT) & \
	   (RARRAY_EMBED_LEN_MASK >> RARRAY_EMBED_LEN_SHIFT))
#define RARRAY_LEN(a) rb_array_len(a)
#define RARRAY_LENINT(ary) rb_long2int(RARRAY_LEN(ary))
#define RARRAY_CONST_PTR(a) rb_array_const_ptr(a)
#define RARRAY_CONST_PTR_TRANSIENT(a) rb_array_const_ptr_transient(a)

#if USE_TRANSIENT_HEAP
#define RARRAY_TRANSIENT_P(ary) FL_TEST_RAW((ary), RARRAY_TRANSIENT_FLAG)
#else
#define RARRAY_TRANSIENT_P(ary) 0
#endif

#define RARRAY_PTR_USE_START_TRANSIENT(a) rb_array_ptr_use_start(a, 1)
#define RARRAY_PTR_USE_END_TRANSIENT(a) rb_array_ptr_use_end(a, 1)

#define RARRAY_PTR_USE_TRANSIENT(ary, ptr_name, expr) do { \
    const VALUE _ary = (ary); \
    VALUE *ptr_name = (VALUE *)RARRAY_PTR_USE_START_TRANSIENT(_ary); \
    expr; \
    RARRAY_PTR_USE_END_TRANSIENT(_ary); \
} while (0)

#define RARRAY_PTR_USE_START(a) rb_array_ptr_use_start(a, 0)
#define RARRAY_PTR_USE_END(a) rb_array_ptr_use_end(a, 0)

#define RARRAY_PTR_USE(ary, ptr_name, expr) do { \
    const VALUE _ary = (ary); \
    VALUE *ptr_name = (VALUE *)RARRAY_PTR_USE_START(_ary); \
    expr; \
    RARRAY_PTR_USE_END(_ary); \
} while (0)

#define RARRAY_AREF(a, i) (RARRAY_CONST_PTR_TRANSIENT(a)[i])
#define RARRAY_ASET(a, i, v) do { \
    const VALUE _ary = (a); \
    const VALUE _v = (v); \
    VALUE *ptr = (VALUE *)RARRAY_PTR_USE_START_TRANSIENT(_ary); \
    RB_OBJ_WRITE(_ary, &ptr[i], _v); \
    RARRAY_PTR_USE_END_TRANSIENT(_ary); \
} while (0)

#define RARRAY_PTR(a) ((VALUE *)RARRAY_CONST_PTR(RB_OBJ_WB_UNPROTECT_FOR(ARRAY, a)))

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    const VALUE src;
    unsigned long usecnt;
};
#define RREGEXP_PTR(r) (RREGEXP(r)->ptr)
#define RREGEXP_SRC(r) (RREGEXP(r)->src)
#define RREGEXP_SRC_PTR(r) RSTRING_PTR(RREGEXP(r)->src)
#define RREGEXP_SRC_LEN(r) RSTRING_LEN(RREGEXP(r)->src)
#define RREGEXP_SRC_END(r) RSTRING_END(RREGEXP(r)->src)

/* RHash is defined at internal.h */
size_t rb_hash_size_num(VALUE hash);

#define RHASH_TBL(h) rb_hash_tbl(h, __FILE__, __LINE__)
#define RHASH_ITER_LEV(h) rb_hash_iter_lev(h)
#define RHASH_IFNONE(h) rb_hash_ifnone(h)
#define RHASH_SIZE(h) rb_hash_size_num(h)
#define RHASH_EMPTY_P(h) (RHASH_SIZE(h) == 0)
#define RHASH_SET_IFNONE(h, ifnone) rb_hash_set_ifnone((VALUE)h, ifnone)

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

typedef struct rb_data_type_struct rb_data_type_t;

struct rb_data_type_struct {
    const char *wrap_struct_name;
    struct {
	void (*dmark)(void*);
	void (*dfree)(void*);
	size_t (*dsize)(const void *);
        void (*dcompact)(void*);
        void *reserved[1]; /* For future extension.
			      This array *must* be filled with ZERO. */
    } function;
    const rb_data_type_t *parent;
    void *data;        /* This area can be used for any purpose
                          by a programmer who define the type. */
    VALUE flags;       /* RUBY_FL_WB_PROTECTED */
};

#define HAVE_TYPE_RB_DATA_TYPE_T 1
#define HAVE_RB_DATA_TYPE_T_FUNCTION 1
#define HAVE_RB_DATA_TYPE_T_PARENT 1

struct RTypedData {
    struct RBasic basic;
    const rb_data_type_t *type;
    VALUE typed_flag; /* 1 or not */
    void *data;
};

#define DATA_PTR(dta) (RDATA(dta)->data)

#define RTYPEDDATA_P(v)    (RTYPEDDATA(v)->typed_flag == 1)
#define RTYPEDDATA_TYPE(v) (RTYPEDDATA(v)->type)
#define RTYPEDDATA_DATA(v) (RTYPEDDATA(v)->data)

/*
#define RUBY_DATA_FUNC(func) ((void (*)(void*))(func))
*/
typedef void (*RUBY_DATA_FUNC)(void*);

#ifndef RUBY_UNTYPED_DATA_WARNING
# if defined RUBY_EXPORT
#   define RUBY_UNTYPED_DATA_WARNING 1
# else
#   define RUBY_UNTYPED_DATA_WARNING 0
# endif
#endif
VALUE rb_data_object_wrap(VALUE,void*,RUBY_DATA_FUNC,RUBY_DATA_FUNC);
VALUE rb_data_object_zalloc(VALUE,size_t,RUBY_DATA_FUNC,RUBY_DATA_FUNC);
VALUE rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *);
VALUE rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type);
int rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent);
int rb_typeddata_is_kind_of(VALUE, const rb_data_type_t *);
void *rb_check_typeddata(VALUE, const rb_data_type_t *);
#define Check_TypedStruct(v,t) rb_check_typeddata((VALUE)(v),(t))
#define RUBY_DEFAULT_FREE ((RUBY_DATA_FUNC)-1)
#define RUBY_NEVER_FREE   ((RUBY_DATA_FUNC)0)
#define RUBY_TYPED_DEFAULT_FREE RUBY_DEFAULT_FREE
#define RUBY_TYPED_NEVER_FREE   RUBY_NEVER_FREE

/* bits for rb_data_type_struct::flags */
#define RUBY_TYPED_FREE_IMMEDIATELY  1 /* TYPE field */
#define RUBY_TYPED_WB_PROTECTED      RUBY_FL_WB_PROTECTED /* THIS FLAG DEPENDS ON Ruby version */
#define RUBY_TYPED_PROMOTED1         RUBY_FL_PROMOTED1    /* THIS FLAG DEPENDS ON Ruby version */

#define Data_Wrap_Struct(klass,mark,free,sval)\
    rb_data_object_wrap((klass),(sval),(RUBY_DATA_FUNC)(mark),(RUBY_DATA_FUNC)(free))

#define Data_Make_Struct0(result, klass, type, size, mark, free, sval) \
    VALUE result = rb_data_object_zalloc((klass), (size), \
					 (RUBY_DATA_FUNC)(mark), \
					 (RUBY_DATA_FUNC)(free)); \
    (void)((sval) = (type *)DATA_PTR(result));

#ifdef __GNUC__
#define Data_Make_Struct(klass,type,mark,free,sval) RB_GNUC_EXTENSION_BLOCK(\
    Data_Make_Struct0(data_struct_obj, klass, type, sizeof(type), mark, free, sval); \
    data_struct_obj \
)
#else
#define Data_Make_Struct(klass,type,mark,free,sval) (\
    rb_data_object_make((klass),(RUBY_DATA_FUNC)(mark),(RUBY_DATA_FUNC)(free),(void **)&(sval),sizeof(type)) \
)
#endif

#define TypedData_Wrap_Struct(klass,data_type,sval)\
  rb_data_typed_object_wrap((klass),(sval),(data_type))

#define TypedData_Make_Struct0(result, klass, type, size, data_type, sval) \
    VALUE result = rb_data_typed_object_zalloc(klass, size, data_type); \
    (void)((sval) = (type *)DATA_PTR(result));

#ifdef __GNUC__
#define TypedData_Make_Struct(klass, type, data_type, sval) RB_GNUC_EXTENSION_BLOCK(\
    TypedData_Make_Struct0(data_struct_obj, klass, type, sizeof(type), data_type, sval); \
    data_struct_obj \
)
#else
#define TypedData_Make_Struct(klass, type, data_type, sval) (\
    rb_data_typed_object_make((klass),(data_type),(void **)&(sval),sizeof(type)) \
)
#endif

#define Data_Get_Struct(obj,type,sval) \
    ((sval) = (type*)rb_data_object_get(obj))

#define TypedData_Get_Struct(obj,type,data_type,sval) \
    ((sval) = (type*)rb_check_typeddata((obj), (data_type)))

#define RSTRUCT_LEN(st)         NUM2LONG(rb_struct_size(st))
#define RSTRUCT_PTR(st)         rb_struct_ptr(st)
#define RSTRUCT_SET(st, idx, v) rb_struct_aset(st, INT2NUM(idx), (v))
#define RSTRUCT_GET(st, idx)    rb_struct_aref(st, INT2NUM(idx))

int rb_big_sign(VALUE);
#define RBIGNUM_SIGN(b) (rb_big_sign(b))
#define RBIGNUM_POSITIVE_P(b) (RBIGNUM_SIGN(b)!=0)
#define RBIGNUM_NEGATIVE_P(b) (RBIGNUM_SIGN(b)==0)

#define R_CAST(st)   (struct st*)
#define RMOVED(obj)  (R_CAST(RMoved)(obj))
#define RBASIC(obj)  (R_CAST(RBasic)(obj))
#define ROBJECT(obj) (R_CAST(RObject)(obj))
#define RCLASS(obj)  (R_CAST(RClass)(obj))
#define RMODULE(obj) RCLASS(obj)
#define RSTRING(obj) (R_CAST(RString)(obj))
#define RREGEXP(obj) (R_CAST(RRegexp)(obj))
#define RARRAY(obj)  (R_CAST(RArray)(obj))
#define RDATA(obj)   (R_CAST(RData)(obj))
#define RTYPEDDATA(obj)   (R_CAST(RTypedData)(obj))
#define RFILE(obj)   (R_CAST(RFile)(obj))

#define FL_SINGLETON    ((VALUE)RUBY_FL_SINGLETON)
#define FL_WB_PROTECTED ((VALUE)RUBY_FL_WB_PROTECTED)
#define FL_PROMOTED0    ((VALUE)RUBY_FL_PROMOTED0)
#define FL_PROMOTED1    ((VALUE)RUBY_FL_PROMOTED1)
#define FL_FINALIZE     ((VALUE)RUBY_FL_FINALIZE)
#define FL_TAINT        ((VALUE)RUBY_FL_TAINT)
#define FL_UNTRUSTED    ((VALUE)RUBY_FL_UNTRUSTED)
#define FL_SEEN_OBJ_ID  ((VALUE)RUBY_FL_SEEN_OBJ_ID)
#define FL_EXIVAR       ((VALUE)RUBY_FL_EXIVAR)
#define FL_FREEZE       ((VALUE)RUBY_FL_FREEZE)

#define FL_USHIFT       ((VALUE)RUBY_FL_USHIFT)

#define FL_USER0  	((VALUE)RUBY_FL_USER0)
#define FL_USER1  	((VALUE)RUBY_FL_USER1)
#define FL_USER2  	((VALUE)RUBY_FL_USER2)
#define FL_USER3  	((VALUE)RUBY_FL_USER3)
#define FL_USER4  	((VALUE)RUBY_FL_USER4)
#define FL_USER5  	((VALUE)RUBY_FL_USER5)
#define FL_USER6  	((VALUE)RUBY_FL_USER6)
#define FL_USER7  	((VALUE)RUBY_FL_USER7)
#define FL_USER8  	((VALUE)RUBY_FL_USER8)
#define FL_USER9  	((VALUE)RUBY_FL_USER9)
#define FL_USER10 	((VALUE)RUBY_FL_USER10)
#define FL_USER11 	((VALUE)RUBY_FL_USER11)
#define FL_USER12 	((VALUE)RUBY_FL_USER12)
#define FL_USER13 	((VALUE)RUBY_FL_USER13)
#define FL_USER14 	((VALUE)RUBY_FL_USER14)
#define FL_USER15 	((VALUE)RUBY_FL_USER15)
#define FL_USER16 	((VALUE)RUBY_FL_USER16)
#define FL_USER17 	((VALUE)RUBY_FL_USER17)
#define FL_USER18 	((VALUE)RUBY_FL_USER18)
#define FL_USER19 	((VALUE)(unsigned int)RUBY_FL_USER19)

#define RB_SPECIAL_CONST_P(x) (RB_IMMEDIATE_P(x) || !RB_TEST(x))
#define SPECIAL_CONST_P(x) RB_SPECIAL_CONST_P(x)

#define RB_FL_ABLE(x) (!RB_SPECIAL_CONST_P(x) && RB_BUILTIN_TYPE(x) != RUBY_T_NODE)
#define RB_FL_TEST_RAW(x,f) (RBASIC(x)->flags&(f))
#define RB_FL_TEST(x,f) (RB_FL_ABLE(x)?RB_FL_TEST_RAW((x),(f)):0)
#define RB_FL_ANY_RAW(x,f) RB_FL_TEST_RAW((x),(f))
#define RB_FL_ANY(x,f) RB_FL_TEST((x),(f))
#define RB_FL_ALL_RAW(x,f) (RB_FL_TEST_RAW((x),(f)) == (f))
#define RB_FL_ALL(x,f) (RB_FL_TEST((x),(f)) == (f))
#define RB_FL_SET_RAW(x,f) (void)(RBASIC(x)->flags |= (f))
#define RB_FL_SET(x,f) (RB_FL_ABLE(x) ? RB_FL_SET_RAW(x, f) : (void)0)
#define RB_FL_UNSET_RAW(x,f) (void)(RBASIC(x)->flags &= ~(VALUE)(f))
#define RB_FL_UNSET(x,f) (RB_FL_ABLE(x) ? RB_FL_UNSET_RAW(x, f) : (void)0)
#define RB_FL_REVERSE_RAW(x,f) (void)(RBASIC(x)->flags ^= (f))
#define RB_FL_REVERSE(x,f) (RB_FL_ABLE(x) ? RB_FL_REVERSE_RAW(x, f) : (void)0)

#define RB_OBJ_TAINTABLE(x) (RB_FL_ABLE(x) && RB_BUILTIN_TYPE(x) != RUBY_T_BIGNUM && RB_BUILTIN_TYPE(x) != RUBY_T_FLOAT)
#define RB_OBJ_TAINTED_RAW(x) RB_FL_TEST_RAW(x, RUBY_FL_TAINT)
#define RB_OBJ_TAINTED(x) (!!RB_FL_TEST((x), RUBY_FL_TAINT))
#define RB_OBJ_TAINT_RAW(x) RB_FL_SET_RAW(x, RUBY_FL_TAINT)
#define RB_OBJ_TAINT(x) (RB_OBJ_TAINTABLE(x) ? RB_OBJ_TAINT_RAW(x) : (void)0)
#define RB_OBJ_UNTRUSTED(x) RB_OBJ_TAINTED(x)
#define RB_OBJ_UNTRUST(x) RB_OBJ_TAINT(x)
#define RB_OBJ_INFECT_RAW(x,s) RB_FL_SET_RAW(x, RB_OBJ_TAINTED_RAW(s))
#define RB_OBJ_INFECT(x,s) ( \
    (RB_OBJ_TAINTABLE(x) && RB_FL_ABLE(s)) ? \
    RB_OBJ_INFECT_RAW(x, s) : (void)0)

#define RB_OBJ_FROZEN_RAW(x) (RBASIC(x)->flags&RUBY_FL_FREEZE)
#define RB_OBJ_FROZEN(x) (!RB_FL_ABLE(x) || RB_OBJ_FROZEN_RAW(x))
#define RB_OBJ_FREEZE_RAW(x) (void)(RBASIC(x)->flags |= RUBY_FL_FREEZE)
#define RB_OBJ_FREEZE(x) rb_obj_freeze_inline((VALUE)x)

/*!
 * \defgroup deprecated_macros deprecated macro APIs
 * \{
 * \par These macros are deprecated. Prefer their `RB_`-prefixed versions.
 */
#define FL_ABLE(x) RB_FL_ABLE(x)
#define FL_TEST_RAW(x,f) RB_FL_TEST_RAW(x,f)
#define FL_TEST(x,f) RB_FL_TEST(x,f)
#define FL_ANY_RAW(x,f) RB_FL_ANY_RAW(x,f)
#define FL_ANY(x,f) RB_FL_ANY(x,f)
#define FL_ALL_RAW(x,f) RB_FL_ALL_RAW(x,f)
#define FL_ALL(x,f) RB_FL_ALL(x,f)
#define FL_SET_RAW(x,f) RB_FL_SET_RAW(x,f)
#define FL_SET(x,f) RB_FL_SET(x,f)
#define FL_UNSET_RAW(x,f) RB_FL_UNSET_RAW(x,f)
#define FL_UNSET(x,f) RB_FL_UNSET(x,f)
#define FL_REVERSE_RAW(x,f) RB_FL_REVERSE_RAW(x,f)
#define FL_REVERSE(x,f) RB_FL_REVERSE(x,f)

#define OBJ_TAINTABLE(x) RB_OBJ_TAINTABLE(x)
#define OBJ_TAINTED_RAW(x) RB_OBJ_TAINTED_RAW(x)
#define OBJ_TAINTED(x) RB_OBJ_TAINTED(x)
#define OBJ_TAINT_RAW(x) RB_OBJ_TAINT_RAW(x)
#define OBJ_TAINT(x) RB_OBJ_TAINT(x)
#define OBJ_UNTRUSTED(x) RB_OBJ_UNTRUSTED(x)
#define OBJ_UNTRUST(x) RB_OBJ_UNTRUST(x)
#define OBJ_INFECT_RAW(x,s) RB_OBJ_INFECT_RAW(x,s)
#define OBJ_INFECT(x,s) RB_OBJ_INFECT(x,s)
#define OBJ_FROZEN_RAW(x) RB_OBJ_FROZEN_RAW(x)
#define OBJ_FROZEN(x) RB_OBJ_FROZEN(x)
#define OBJ_FREEZE_RAW(x) RB_OBJ_FREEZE_RAW(x)
#define OBJ_FREEZE(x) RB_OBJ_FREEZE(x)

/* \} */

void rb_freeze_singleton_class(VALUE klass);

static inline void
rb_obj_freeze_inline(VALUE x)
{
    if (RB_FL_ABLE(x)) {
	RB_OBJ_FREEZE_RAW(x);
	if (RBASIC_CLASS(x) && !(RBASIC(x)->flags & RUBY_FL_SINGLETON)) {
	    rb_freeze_singleton_class(x);
	}
    }
}

#if GCC_VERSION_SINCE(4,4,0)
# define RUBY_UNTYPED_DATA_FUNC(func) func __attribute__((warning("untyped Data is unsafe; use TypedData instead")))
#else
# define RUBY_UNTYPED_DATA_FUNC(func) DEPRECATED(func)
#endif

#if defined(__GNUC__) && !defined(__NO_INLINE__)
#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
RUBY_UNTYPED_DATA_FUNC(static inline VALUE rb_data_object_wrap_warning(VALUE,void*,RUBY_DATA_FUNC,RUBY_DATA_FUNC));
#endif
RUBY_UNTYPED_DATA_FUNC(static inline void *rb_data_object_get_warning(VALUE));

static inline VALUE
rb_data_object_wrap_warning(VALUE klass, void *ptr, RUBY_DATA_FUNC mark, RUBY_DATA_FUNC free)
{
    return rb_data_object_wrap(klass, ptr, mark, free);
}

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#define rb_data_object_wrap_warning(klass, ptr, mark, free) \
    __extension__( \
	__builtin_choose_expr( \
	    __builtin_constant_p(klass) && !(klass), \
	    rb_data_object_wrap(klass, ptr, mark, free), \
	    rb_data_object_wrap_warning(klass, ptr, mark, free)))
#endif
#endif

static inline void *
rb_data_object_get(VALUE obj)
{
    Check_Type(obj, RUBY_T_DATA);
    return ((struct RData *)obj)->data;
}

#if defined(__GNUC__) && !defined(__NO_INLINE__)
static inline void *
rb_data_object_get_warning(VALUE obj)
{
    return rb_data_object_get(obj);
}
#endif

static inline VALUE
rb_data_object_make(VALUE klass, RUBY_DATA_FUNC mark_func, RUBY_DATA_FUNC free_func, void **datap, size_t size)
{
    Data_Make_Struct0(result, klass, void, size, mark_func, free_func, *datap);
    return result;
}

static inline VALUE
rb_data_typed_object_make(VALUE klass, const rb_data_type_t *type, void **datap, size_t size)
{
    TypedData_Make_Struct0(result, klass, void, size, type, *datap);
    return result;
}

#ifndef rb_data_object_alloc
DEPRECATED_BY(rb_data_object_wrap, static inline VALUE rb_data_object_alloc(VALUE,void*,RUBY_DATA_FUNC,RUBY_DATA_FUNC));
static inline VALUE
rb_data_object_alloc(VALUE klass, void *data, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    return rb_data_object_wrap(klass, data, dmark, dfree);
}
#endif

#ifndef rb_data_typed_object_alloc
DEPRECATED_BY(rb_data_typed_object_wrap, static inline VALUE rb_data_typed_object_alloc(VALUE,void*,const rb_data_type_t*));
static inline VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    return rb_data_typed_object_wrap(klass, datap, type);
}
#endif

#if defined(__GNUC__) && !defined(__NO_INLINE__)
#define rb_data_object_wrap_0 rb_data_object_wrap
#define rb_data_object_wrap_1 rb_data_object_wrap_warning
#define rb_data_object_wrap  RUBY_MACRO_SELECT(rb_data_object_wrap_, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_get_0 rb_data_object_get
#define rb_data_object_get_1 rb_data_object_get_warning
#define rb_data_object_get  RUBY_MACRO_SELECT(rb_data_object_get_, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_make_0 rb_data_object_make
#define rb_data_object_make_1 rb_data_object_make_warning
#define rb_data_object_make   RUBY_MACRO_SELECT(rb_data_object_make_, RUBY_UNTYPED_DATA_WARNING)
#endif

#if USE_RGENGC
#define RB_OBJ_PROMOTED_RAW(x)      RB_FL_ALL_RAW(x, RUBY_FL_PROMOTED)
#define RB_OBJ_PROMOTED(x)          (RB_SPECIAL_CONST_P(x) ? 0 : RB_OBJ_PROMOTED_RAW(x))
#define RB_OBJ_WB_UNPROTECT(x)      rb_obj_wb_unprotect(x, __FILE__, __LINE__)

void rb_gc_writebarrier(VALUE a, VALUE b);
void rb_gc_writebarrier_unprotect(VALUE obj);

#else /* USE_RGENGC */
#define RB_OBJ_PROMOTED(x)          0
#define RB_OBJ_WB_UNPROTECT(x)      rb_obj_wb_unprotect(x, __FILE__, __LINE__)
#endif
#define OBJ_PROMOTED_RAW(x)         RB_OBJ_PROMOTED_RAW(x)
#define OBJ_PROMOTED(x)             RB_OBJ_PROMOTED(x)
#define OBJ_WB_UNPROTECT(x)         RB_OBJ_WB_UNPROTECT(x)

/* Write barrier (WB) interfaces:
 * - RB_OBJ_WRITE(a, slot, b): WB for new reference from `a' to `b'.
 *     Write `b' into `*slot'. `slot' is a pointer in `a'.
 * - RB_OBJ_WRITTEN(a, oldv, b): WB for new reference from `a' to `b'.
 *     This doesn't write any values, but only a WB declaration.
 *     `oldv' is replaced value with `b' (not used in current Ruby).
 *
 * NOTE: The following core interfaces can be changed in the future.
 *       Please catch up if you want to insert WB into C-extensions
 *       correctly.
 */
#define RB_OBJ_WRITE(a, slot, b)       rb_obj_write((VALUE)(a), (VALUE *)(slot), (VALUE)(b), __FILE__, __LINE__)
#define RB_OBJ_WRITTEN(a, oldv, b)     rb_obj_written((VALUE)(a), (VALUE)(oldv), (VALUE)(b), __FILE__, __LINE__)

#ifndef USE_RGENGC_LOGGING_WB_UNPROTECT
#define USE_RGENGC_LOGGING_WB_UNPROTECT 0
#endif

#if USE_RGENGC_LOGGING_WB_UNPROTECT
void rb_gc_unprotect_logging(void *objptr, const char *filename, int line);
#define RGENGC_LOGGING_WB_UNPROTECT rb_gc_unprotect_logging
#endif

static inline VALUE
rb_obj_wb_unprotect(VALUE x, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_WB_UNPROTECT((void *)x, filename, line);
#endif
#if USE_RGENGC
    rb_gc_writebarrier_unprotect(x);
#endif
    return x;
}

static inline VALUE
rb_obj_written(VALUE a, RB_UNUSED_VAR(VALUE oldv), VALUE b, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_OBJ_WRITTEN
    RGENGC_LOGGING_OBJ_WRITTEN(a, oldv, b, filename, line);
#endif

#if USE_RGENGC
    if (!RB_SPECIAL_CONST_P(b)) {
	rb_gc_writebarrier(a, b);
    }
#endif

    return a;
}

static inline VALUE
rb_obj_write(VALUE a, VALUE *slot, VALUE b, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_WRITE
    RGENGC_LOGGING_WRITE(a, slot, b, filename, line);
#endif

    *slot = b;

#if USE_RGENGC
    rb_obj_written(a, RUBY_Qundef /* ignore `oldv' now */, b, filename, line);
#endif
    return a;
}

#define RUBY_INTEGER_UNIFICATION 1
#define RB_INTEGER_TYPE_P(obj) rb_integer_type_p(obj)
#if defined __GNUC__ && !GCC_VERSION_SINCE(4, 3, 0)
/* clang 3.x (4.2 compatible) can't eliminate CSE of RB_BUILTIN_TYPE
 * in inline function and caller function */
#define rb_integer_type_p(obj) \
    __extension__ ({ \
	const VALUE integer_type_obj = (obj); \
	(RB_FIXNUM_P(integer_type_obj) || \
	 (!RB_SPECIAL_CONST_P(integer_type_obj) && \
	  RB_BUILTIN_TYPE(integer_type_obj) == RUBY_T_BIGNUM)); \
    })
#else
static inline int
rb_integer_type_p(VALUE obj)
{
    return (RB_FIXNUM_P(obj) ||
	    (!RB_SPECIAL_CONST_P(obj) &&
	     RB_BUILTIN_TYPE(obj) == RUBY_T_BIGNUM));
}
#endif

#if SIZEOF_INT < SIZEOF_LONG
# define RB_INT2NUM(v) RB_INT2FIX((int)(v))
# define RB_UINT2NUM(v) RB_LONG2FIX((unsigned int)(v))
#else
static inline VALUE
rb_int2num_inline(int v)
{
    if (RB_FIXABLE(v))
	return RB_INT2FIX(v);
    else
	return rb_int2big(v);
}
#define RB_INT2NUM(x) rb_int2num_inline(x)

static inline VALUE
rb_uint2num_inline(unsigned int v)
{
    if (RB_POSFIXABLE(v))
	return RB_LONG2FIX(v);
    else
	return rb_uint2big(v);
}
#define RB_UINT2NUM(x) rb_uint2num_inline(x)
#endif
#define INT2NUM(x) RB_INT2NUM(x)
#define UINT2NUM(x) RB_UINT2NUM(x)

static inline VALUE
rb_long2num_inline(long v)
{
    if (RB_FIXABLE(v))
	return RB_LONG2FIX(v);
    else
	return rb_int2big(v);
}
#define RB_LONG2NUM(x) rb_long2num_inline(x)

static inline VALUE
rb_ulong2num_inline(unsigned long v)
{
    if (RB_POSFIXABLE(v))
	return RB_LONG2FIX(v);
    else
	return rb_uint2big(v);
}
#define RB_ULONG2NUM(x) rb_ulong2num_inline(x)

static inline char
rb_num2char_inline(VALUE x)
{
    if (RB_TYPE_P(x, RUBY_T_STRING) && (RSTRING_LEN(x)>=1))
	return RSTRING_PTR(x)[0];
    else
	return (char)(NUM2INT(x) & 0xff);
}
#define RB_NUM2CHR(x) rb_num2char_inline(x)

#define RB_CHR2FIX(x) RB_INT2FIX((long)((x)&0xff))

#define LONG2NUM(x) RB_LONG2NUM(x)
#define ULONG2NUM(x) RB_ULONG2NUM(x)
#define USHORT2NUM(x) RB_INT2FIX(x)
#define NUM2CHR(x) RB_NUM2CHR(x)
#define CHR2FIX(x) RB_CHR2FIX(x)

#if SIZEOF_LONG < SIZEOF_VALUE
#define RB_ST2FIX(h) RB_LONG2FIX((long)((h) > 0 ? (h) & (unsigned long)-1 >> 2 : (h) | ~((unsigned long)-1 >> 2)))
#else
#define RB_ST2FIX(h) RB_LONG2FIX((long)(h))
#endif
#define ST2FIX(h) RB_ST2FIX(h)

#define RB_ALLOC_N(type,n) ((type*)ruby_xmalloc2((size_t)(n),sizeof(type)))
#define RB_ALLOC(type) ((type*)ruby_xmalloc(sizeof(type)))
#define RB_ZALLOC_N(type,n) ((type*)ruby_xcalloc((size_t)(n),sizeof(type)))
#define RB_ZALLOC(type) (RB_ZALLOC_N(type,1))
#define RB_REALLOC_N(var,type,n) ((var)=(type*)ruby_xrealloc2((char*)(var),(size_t)(n),sizeof(type)))

#define ALLOC_N(type,n) RB_ALLOC_N(type,n)
#define ALLOC(type) RB_ALLOC(type)
#define ZALLOC_N(type,n) RB_ZALLOC_N(type,n)
#define ZALLOC(type) RB_ZALLOC(type)
#define REALLOC_N(var,type,n) RB_REALLOC_N(var,type,n)

#if GCC_VERSION_BEFORE(4,9,5)
/* GCC 4.9.2 reportedly has this feature and is broken.
 * The function is not officially documented below.
 * Seems we should not use it.
 * https://gcc.gnu.org/onlinedocs/gcc-4.9.4/gcc/Other-Builtins.html#Other-Builtins */
# undef HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN
#endif

#if defined(HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN) && defined(RUBY_ALIGNOF)
/* I don't know why but __builtin_alloca_with_align's second argument
   takes bits rather than bytes. */
#define ALLOCA_N(type, n) \
    (type*)__builtin_alloca_with_align((sizeof(type)*(n)), \
        RUBY_ALIGNOF(type) * CHAR_BIT)
#else
#define ALLOCA_N(type,n) ((type*)alloca(sizeof(type)*(n)))
#endif

void *rb_alloc_tmp_buffer(volatile VALUE *store, long len) RUBY_ATTR_ALLOC_SIZE((2));
void *rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t len,size_t count) RUBY_ATTR_ALLOC_SIZE((2,3));
void rb_free_tmp_buffer(volatile VALUE *store);
NORETURN(void ruby_malloc_size_overflow(size_t, size_t));
#if HAVE_LONG_LONG && SIZEOF_SIZE_T * 2 <= SIZEOF_LONG_LONG
# define DSIZE_T unsigned LONG_LONG
#elif defined(HAVE_INT128_T)
# define DSIZE_T uint128_t
#endif
static inline int
rb_mul_size_overflow(size_t a, size_t b, size_t max, size_t *c)
{
#ifdef DSIZE_T
# ifdef __GNUC__
    __extension__
# endif
    DSIZE_T c2 = (DSIZE_T)a * (DSIZE_T)b;
    if (c2 > max) return 1;
    *c = (size_t)c2;
#else
    if (b != 0 && a > max / b) return 1;
    *c = a * b;
#endif
    return 0;
}
static inline void *
rb_alloc_tmp_buffer2(volatile VALUE *store, long count, size_t elsize)
{
    size_t cnt = (size_t)count;
    if (elsize == sizeof(VALUE)) {
	if (RB_UNLIKELY(cnt > LONG_MAX / sizeof(VALUE))) {
	    ruby_malloc_size_overflow(cnt, elsize);
	}
    }
    else {
	size_t size, max = LONG_MAX - sizeof(VALUE) + 1;
	if (RB_UNLIKELY(rb_mul_size_overflow(cnt, elsize, max, &size))) {
	    ruby_malloc_size_overflow(cnt, elsize);
	}
	cnt = (size + sizeof(VALUE) - 1) / sizeof(VALUE);
    }
    return rb_alloc_tmp_buffer_with_count(store, cnt * sizeof(VALUE), cnt);
}
/* allocates _n_ bytes temporary buffer and stores VALUE including it
 * in _v_.  _n_ may be evaluated twice. */
#ifdef C_ALLOCA
# define RB_ALLOCV(v, n) rb_alloc_tmp_buffer(&(v), (n))
# define RB_ALLOCV_N(type, v, n) \
     rb_alloc_tmp_buffer2(&(v), (n), sizeof(type))
#else
# define RUBY_ALLOCV_LIMIT 1024
# define RB_ALLOCV(v, n) ((n) < RUBY_ALLOCV_LIMIT ? \
                       ((v) = 0, alloca(n)) : \
		       rb_alloc_tmp_buffer(&(v), (n)))
# define RB_ALLOCV_N(type, v, n) \
    ((type*)(((size_t)(n) < RUBY_ALLOCV_LIMIT / sizeof(type)) ? \
             ((v) = 0, alloca((size_t)(n) * sizeof(type))) : \
	     rb_alloc_tmp_buffer2(&(v), (long)(n), sizeof(type))))
#endif
#define RB_ALLOCV_END(v) rb_free_tmp_buffer(&(v))

#define ALLOCV(v, n) RB_ALLOCV(v, n)
#define ALLOCV_N(type, v, n) RB_ALLOCV_N(type, v, n)
#define ALLOCV_END(v) RB_ALLOCV_END(v)

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(size_t)(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(size_t)(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(size_t)(n))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), sizeof(type)*(size_t)(n))
#ifdef __GLIBC__
static inline void *
ruby_nonempty_memcpy(void *dest, const void *src, size_t n)
{
    /* if nothing to be copied, src may be NULL */
    return (n ? memcpy(dest, src, n) : dest);
}
#define memcpy(p1,p2,n) ruby_nonempty_memcpy(p1, p2, n)
#endif

void rb_obj_infect(VALUE victim, VALUE carrier);

typedef int ruby_glob_func(const char*,VALUE, void*);
void rb_glob(const char*,void(*)(const char*,VALUE,void*),VALUE);
int ruby_glob(const char*,int,ruby_glob_func*,VALUE);
int ruby_brace_glob(const char*,int,ruby_glob_func*,VALUE);

VALUE rb_define_class(const char*,VALUE);
VALUE rb_define_module(const char*);
VALUE rb_define_class_under(VALUE, const char*, VALUE);
VALUE rb_define_module_under(VALUE, const char*);

void rb_include_module(VALUE,VALUE);
void rb_extend_object(VALUE,VALUE);
void rb_prepend_module(VALUE,VALUE);

typedef VALUE rb_gvar_getter_t(ID id, VALUE *data);
typedef void  rb_gvar_setter_t(VALUE val, ID id, VALUE *data);
typedef void  rb_gvar_marker_t(VALUE *var);

rb_gvar_getter_t rb_gvar_undef_getter;
rb_gvar_setter_t rb_gvar_undef_setter;
rb_gvar_marker_t rb_gvar_undef_marker;

rb_gvar_getter_t rb_gvar_val_getter;
rb_gvar_setter_t rb_gvar_val_setter;
rb_gvar_marker_t rb_gvar_val_marker;

rb_gvar_getter_t rb_gvar_var_getter;
rb_gvar_setter_t rb_gvar_var_setter;
rb_gvar_marker_t rb_gvar_var_marker;

NORETURN(rb_gvar_setter_t rb_gvar_readonly_setter);

void rb_define_variable(const char*,VALUE*);
void rb_define_virtual_variable(const char*,rb_gvar_getter_t*,rb_gvar_setter_t*);
void rb_define_hooked_variable(const char*,VALUE*,rb_gvar_getter_t*,rb_gvar_setter_t*);
void rb_define_readonly_variable(const char*,const VALUE*);
void rb_define_const(VALUE,const char*,VALUE);
void rb_define_global_const(const char*,VALUE);

void rb_define_method(VALUE,const char*,VALUE(*)(ANYARGS),int);
void rb_define_module_function(VALUE,const char*,VALUE(*)(ANYARGS),int);
void rb_define_global_function(const char*,VALUE(*)(ANYARGS),int);

void rb_undef_method(VALUE,const char*);
void rb_define_alias(VALUE,const char*,const char*);
void rb_define_attr(VALUE,const char*,int,int);

void rb_global_variable(VALUE*);
void rb_gc_register_mark_object(VALUE);
void rb_gc_register_address(VALUE*);
void rb_gc_unregister_address(VALUE*);

ID rb_intern(const char*);
ID rb_intern2(const char*, long);
ID rb_intern_str(VALUE str);
const char *rb_id2name(ID);
ID rb_check_id(volatile VALUE *);
ID rb_to_id(VALUE);
VALUE rb_id2str(ID);
VALUE rb_sym2str(VALUE);
VALUE rb_to_symbol(VALUE name);
VALUE rb_check_symbol(volatile VALUE *namep);

#define RUBY_CONST_ID_CACHE(result, str)		\
    {							\
	static ID rb_intern_id_cache;			\
	if (!rb_intern_id_cache)			\
	    rb_intern_id_cache = rb_intern2((str), (long)strlen(str)); \
	result rb_intern_id_cache;			\
    }
#define RUBY_CONST_ID(var, str) \
    do RUBY_CONST_ID_CACHE((var) =, (str)) while (0)
#define CONST_ID_CACHE(result, str) RUBY_CONST_ID_CACHE(result, str)
#define CONST_ID(var, str) RUBY_CONST_ID(var, str)
#if defined(HAVE_BUILTIN___BUILTIN_CONSTANT_P) && defined(HAVE_STMT_AND_DECL_IN_EXPR)
/* __builtin_constant_p and statement expression is available
 * since gcc-2.7.2.3 at least. */
#define rb_intern(str) \
    (__builtin_constant_p(str) ? \
        __extension__ (RUBY_CONST_ID_CACHE((ID), (str))) : \
        rb_intern(str))
#define rb_intern_const(str) \
    (__builtin_constant_p(str) ? \
     __extension__ (rb_intern2((str), (long)strlen(str))) : \
     (rb_intern)(str))

# define rb_varargs_argc_check_runtime(argc, vargc) \
    (((argc) <= (vargc)) ? (argc) : \
     (rb_fatal("argc(%d) exceeds actual arguments(%d)", \
	       argc, vargc), 0))
# define rb_varargs_argc_valid_p(argc, vargc) \
    ((argc) == 0 ? (vargc) <= 1 : /* [ruby-core:85266] [Bug #14425] */ \
     (argc) == (vargc))
# if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#   if HAVE_ATTRIBUTE_ERRORFUNC
ERRORFUNC((" argument length doesn't match"), int rb_varargs_bad_length(int,int));
#   else
#     define rb_varargs_bad_length(argc, vargc) \
	((argc)/rb_varargs_argc_valid_p(argc, vargc))
#   endif
#   define rb_varargs_argc_check(argc, vargc) \
    __builtin_choose_expr(__builtin_constant_p(argc), \
	(rb_varargs_argc_valid_p(argc, vargc) ? (argc) : \
	 rb_varargs_bad_length(argc, vargc)), \
	rb_varargs_argc_check_runtime(argc, vargc))
# else
#   define rb_varargs_argc_check(argc, vargc) \
	rb_varargs_argc_check_runtime(argc, vargc)
# endif

#else
#define rb_intern_const(str) rb_intern2((str), (long)strlen(str))
#endif

const char *rb_class2name(VALUE);
const char *rb_obj_classname(VALUE);

void rb_p(VALUE);

VALUE rb_eval_string(const char*);
VALUE rb_eval_string_protect(const char*, int*);
VALUE rb_eval_string_wrap(const char*, int*);
VALUE rb_funcall(VALUE, ID, int, ...);
VALUE rb_funcallv(VALUE, ID, int, const VALUE*);
VALUE rb_funcallv_kw(VALUE, ID, int, const VALUE*, int);
VALUE rb_funcallv_public(VALUE, ID, int, const VALUE*);
VALUE rb_funcallv_public_kw(VALUE, ID, int, const VALUE*, int);
#define rb_funcall2 rb_funcallv
#define rb_funcall3 rb_funcallv_public
VALUE rb_funcall_passing_block(VALUE, ID, int, const VALUE*);
VALUE rb_funcall_passing_block_kw(VALUE, ID, int, const VALUE*, int);
VALUE rb_funcall_with_block(VALUE, ID, int, const VALUE*, VALUE);
VALUE rb_funcall_with_block_kw(VALUE, ID, int, const VALUE*, VALUE, int);
int rb_scan_args(int, const VALUE*, const char*, ...);
#define RB_SCAN_ARGS_PASS_CALLED_KEYWORDS 0
#define RB_SCAN_ARGS_KEYWORDS 1
#define RB_SCAN_ARGS_EMPTY_KEYWORDS 2 /* Will be removed in 3.0 */
#define RB_SCAN_ARGS_LAST_HASH_KEYWORDS 3
int rb_scan_args_kw(int, int, const VALUE*, const char*, ...);
VALUE rb_call_super(int, const VALUE*);
VALUE rb_call_super_kw(int, const VALUE*, int);
VALUE rb_current_receiver(void);
int rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *);
VALUE rb_extract_keywords(VALUE *orighash);

/* rb_scan_args() format allows ':' for optional hash */
#define HAVE_RB_SCAN_ARGS_OPTIONAL_HASH 1

VALUE rb_gv_set(const char*, VALUE);
VALUE rb_gv_get(const char*);
VALUE rb_iv_get(VALUE, const char*);
VALUE rb_iv_set(VALUE, const char*, VALUE);

VALUE rb_equal(VALUE,VALUE);

VALUE *rb_ruby_verbose_ptr(void);
VALUE *rb_ruby_debug_ptr(void);
#define ruby_verbose (*rb_ruby_verbose_ptr())
#define ruby_debug   (*rb_ruby_debug_ptr())

/* for rb_readwrite_sys_fail first argument */
enum rb_io_wait_readwrite {RB_IO_WAIT_READABLE, RB_IO_WAIT_WRITABLE};
#define RB_IO_WAIT_READABLE RB_IO_WAIT_READABLE
#define RB_IO_WAIT_WRITABLE RB_IO_WAIT_WRITABLE

PRINTF_ARGS(NORETURN(void rb_raise(VALUE, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_fatal(const char*, ...)), 1, 2);
COLDFUNC PRINTF_ARGS(NORETURN(void rb_bug(const char*, ...)), 1, 2);
NORETURN(void rb_bug_errno(const char*, int));
NORETURN(void rb_sys_fail(const char*));
NORETURN(void rb_sys_fail_str(VALUE));
NORETURN(void rb_mod_sys_fail(VALUE, const char*));
NORETURN(void rb_mod_sys_fail_str(VALUE, VALUE));
NORETURN(void rb_readwrite_sys_fail(enum rb_io_wait_readwrite, const char*));
NORETURN(void rb_iter_break(void));
NORETURN(void rb_iter_break_value(VALUE));
NORETURN(void rb_exit(int));
NORETURN(void rb_notimplement(void));
VALUE rb_syserr_new(int, const char *);
VALUE rb_syserr_new_str(int n, VALUE arg);
NORETURN(void rb_syserr_fail(int, const char*));
NORETURN(void rb_syserr_fail_str(int, VALUE));
NORETURN(void rb_mod_syserr_fail(VALUE, int, const char*));
NORETURN(void rb_mod_syserr_fail_str(VALUE, int, VALUE));
NORETURN(void rb_readwrite_syserr_fail(enum rb_io_wait_readwrite, int, const char*));

/* reports if `-W' specified */
PRINTF_ARGS(void rb_warning(const char*, ...), 1, 2);
PRINTF_ARGS(void rb_compile_warning(const char *, int, const char*, ...), 3, 4);
PRINTF_ARGS(void rb_sys_warning(const char*, ...), 1, 2);
/* reports always */
COLDFUNC PRINTF_ARGS(void rb_warn(const char*, ...), 1, 2);
PRINTF_ARGS(void rb_compile_warn(const char *, int, const char*, ...), 3, 4);

#define RB_BLOCK_CALL_FUNC_STRICT 1
#define RUBY_BLOCK_CALL_FUNC_TAKES_BLOCKARG 1
#define RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg) \
    VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg
typedef VALUE rb_block_call_func(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg));
typedef rb_block_call_func *rb_block_call_func_t;

VALUE rb_each(VALUE);
VALUE rb_yield(VALUE);
VALUE rb_yield_values(int n, ...);
VALUE rb_yield_values2(int n, const VALUE *argv);
VALUE rb_yield_values_kw(int n, const VALUE *argv, int kw_splat);
VALUE rb_yield_splat(VALUE);
VALUE rb_yield_splat_kw(VALUE, int);
VALUE rb_yield_block(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg)); /* rb_block_call_func */
#define RB_NO_KEYWORDS 0
#define RB_PASS_KEYWORDS 1
#define RB_PASS_EMPTY_KEYWORDS 2 /* Will be removed in 3.0 */
#define RB_PASS_CALLED_KEYWORDS 3
int rb_keyword_given_p(void);
int rb_block_given_p(void);
void rb_need_block(void);
VALUE rb_iterate(VALUE(*)(VALUE),VALUE,rb_block_call_func_t,VALUE);
VALUE rb_block_call(VALUE,ID,int,const VALUE*,rb_block_call_func_t,VALUE);
VALUE rb_block_call_kw(VALUE,ID,int,const VALUE*,rb_block_call_func_t,VALUE,int);
VALUE rb_rescue(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE);
VALUE rb_rescue2(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE,...);
VALUE rb_vrescue2(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE,va_list);
VALUE rb_ensure(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE),VALUE);
VALUE rb_catch(const char*,rb_block_call_func_t,VALUE);
VALUE rb_catch_obj(VALUE,rb_block_call_func_t,VALUE);
NORETURN(void rb_throw(const char*,VALUE));
NORETURN(void rb_throw_obj(VALUE,VALUE));

VALUE rb_require(const char*);

RUBY_EXTERN VALUE rb_mKernel;
RUBY_EXTERN VALUE rb_mComparable;
RUBY_EXTERN VALUE rb_mEnumerable;
RUBY_EXTERN VALUE rb_mErrno;
RUBY_EXTERN VALUE rb_mFileTest;
RUBY_EXTERN VALUE rb_mGC;
RUBY_EXTERN VALUE rb_mMath;
RUBY_EXTERN VALUE rb_mProcess;
RUBY_EXTERN VALUE rb_mWaitReadable;
RUBY_EXTERN VALUE rb_mWaitWritable;

RUBY_EXTERN VALUE rb_cBasicObject;
RUBY_EXTERN VALUE rb_cObject;
RUBY_EXTERN VALUE rb_cArray;
#ifndef RUBY_INTEGER_UNIFICATION
RUBY_EXTERN VALUE rb_cBignum;
#endif
RUBY_EXTERN VALUE rb_cBinding;
RUBY_EXTERN VALUE rb_cClass;
RUBY_EXTERN VALUE rb_cCont;
RUBY_EXTERN VALUE rb_cData;
RUBY_EXTERN VALUE rb_cDir;
RUBY_EXTERN VALUE rb_cEncoding;
RUBY_EXTERN VALUE rb_cEnumerator;
RUBY_EXTERN VALUE rb_cFalseClass;
RUBY_EXTERN VALUE rb_cFile;
#ifndef RUBY_INTEGER_UNIFICATION
RUBY_EXTERN VALUE rb_cFixnum;
#endif
RUBY_EXTERN VALUE rb_cComplex;
RUBY_EXTERN VALUE rb_cFloat;
RUBY_EXTERN VALUE rb_cHash;
RUBY_EXTERN VALUE rb_cIO;
RUBY_EXTERN VALUE rb_cInteger;
RUBY_EXTERN VALUE rb_cMatch;
RUBY_EXTERN VALUE rb_cMethod;
RUBY_EXTERN VALUE rb_cModule;
RUBY_EXTERN VALUE rb_cNameErrorMesg;
RUBY_EXTERN VALUE rb_cNilClass;
RUBY_EXTERN VALUE rb_cNumeric;
RUBY_EXTERN VALUE rb_cProc;
RUBY_EXTERN VALUE rb_cRandom;
RUBY_EXTERN VALUE rb_cRange;
RUBY_EXTERN VALUE rb_cRational;
RUBY_EXTERN VALUE rb_cRegexp;
RUBY_EXTERN VALUE rb_cStat;
RUBY_EXTERN VALUE rb_cString;
RUBY_EXTERN VALUE rb_cStruct;
RUBY_EXTERN VALUE rb_cSymbol;
RUBY_EXTERN VALUE rb_cThread;
RUBY_EXTERN VALUE rb_cTime;
RUBY_EXTERN VALUE rb_cTrueClass;
RUBY_EXTERN VALUE rb_cUnboundMethod;

RUBY_EXTERN VALUE rb_eException;
RUBY_EXTERN VALUE rb_eStandardError;
RUBY_EXTERN VALUE rb_eSystemExit;
RUBY_EXTERN VALUE rb_eInterrupt;
RUBY_EXTERN VALUE rb_eSignal;
RUBY_EXTERN VALUE rb_eFatal;
RUBY_EXTERN VALUE rb_eArgError;
RUBY_EXTERN VALUE rb_eEOFError;
RUBY_EXTERN VALUE rb_eIndexError;
RUBY_EXTERN VALUE rb_eStopIteration;
RUBY_EXTERN VALUE rb_eKeyError;
RUBY_EXTERN VALUE rb_eRangeError;
RUBY_EXTERN VALUE rb_eIOError;
RUBY_EXTERN VALUE rb_eRuntimeError;
RUBY_EXTERN VALUE rb_eFrozenError;
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
RUBY_EXTERN VALUE rb_eEncodingError;
RUBY_EXTERN VALUE rb_eEncCompatError;
RUBY_EXTERN VALUE rb_eNoMatchingPatternError;

RUBY_EXTERN VALUE rb_eScriptError;
RUBY_EXTERN VALUE rb_eNameError;
RUBY_EXTERN VALUE rb_eSyntaxError;
RUBY_EXTERN VALUE rb_eLoadError;

RUBY_EXTERN VALUE rb_eMathDomainError;

RUBY_EXTERN VALUE rb_stdin, rb_stdout, rb_stderr;

static inline VALUE
rb_class_of(VALUE obj)
{
    if (RB_IMMEDIATE_P(obj)) {
	if (RB_FIXNUM_P(obj)) return rb_cInteger;
	if (RB_FLONUM_P(obj)) return rb_cFloat;
	if (obj == RUBY_Qtrue)  return rb_cTrueClass;
	if (RB_STATIC_SYM_P(obj)) return rb_cSymbol;
    }
    else if (!RB_TEST(obj)) {
	if (obj == RUBY_Qnil)   return rb_cNilClass;
	if (obj == RUBY_Qfalse) return rb_cFalseClass;
    }
    return RBASIC(obj)->klass;
}

static inline int
rb_type(VALUE obj)
{
    if (RB_IMMEDIATE_P(obj)) {
	if (RB_FIXNUM_P(obj)) return RUBY_T_FIXNUM;
        if (RB_FLONUM_P(obj)) return RUBY_T_FLOAT;
        if (obj == RUBY_Qtrue)  return RUBY_T_TRUE;
	if (RB_STATIC_SYM_P(obj)) return RUBY_T_SYMBOL;
	if (obj == RUBY_Qundef) return RUBY_T_UNDEF;
    }
    else if (!RB_TEST(obj)) {
	if (obj == RUBY_Qnil)   return RUBY_T_NIL;
	if (obj == RUBY_Qfalse) return RUBY_T_FALSE;
    }
    return RB_BUILTIN_TYPE(obj);
}

#ifdef __GNUC__
#define rb_type_p(obj, type) \
    __extension__ (__builtin_constant_p(type) ? RB_TYPE_P((obj), (type)) : \
		   rb_type(obj) == (type))
#else
#define rb_type_p(obj, type) (rb_type(obj) == (type))
#endif

#ifdef __GNUC__
#define rb_special_const_p(obj) \
    __extension__ ({ \
	VALUE special_const_obj = (obj); \
	(int)(RB_SPECIAL_CONST_P(special_const_obj) ? RUBY_Qtrue : RUBY_Qfalse); \
    })
#else
static inline int
rb_special_const_p(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return (int)RUBY_Qtrue;
    return (int)RUBY_Qfalse;
}
#endif

#include "ruby/intern.h"

static inline void
rb_clone_setup(VALUE clone, VALUE obj)
{
    rb_obj_setup(clone, rb_singleton_class_clone(obj),
                 RBASIC(obj)->flags & ~(FL_PROMOTED0|FL_PROMOTED1|FL_FINALIZE));
    rb_singleton_class_attached(RBASIC_CLASS(clone), clone);
    if (RB_FL_TEST(obj, RUBY_FL_EXIVAR)) rb_copy_generic_ivar(clone, obj);
}

static inline void
rb_dup_setup(VALUE dup, VALUE obj)
{
    rb_obj_setup(dup, rb_obj_class(obj), RB_FL_TEST_RAW(obj, RUBY_FL_DUPPED));
    if (RB_FL_TEST(obj, RUBY_FL_EXIVAR)) rb_copy_generic_ivar(dup, obj);
}

static inline long
rb_array_len(VALUE a)
{
    return (RBASIC(a)->flags & RARRAY_EMBED_FLAG) ?
	RARRAY_EMBED_LEN(a) : RARRAY(a)->as.heap.len;
}

#if defined(__fcc__) || defined(__fcc_version) || \
    defined(__FCC__) || defined(__FCC_VERSION)
/* workaround for old version of Fujitsu C Compiler (fcc) */
# define FIX_CONST_VALUE_PTR(x) ((const VALUE *)(x))
#else
# define FIX_CONST_VALUE_PTR(x) (x)
#endif

/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr_transient(VALUE a)
{
    return FIX_CONST_VALUE_PTR((RBASIC(a)->flags & RARRAY_EMBED_FLAG) ?
	RARRAY(a)->as.ary : RARRAY(a)->as.heap.ptr);
}

/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr(VALUE a)
{
#if USE_TRANSIENT_HEAP
    void rb_ary_detransient(VALUE a);

    if (RARRAY_TRANSIENT_P(a)) {
        rb_ary_detransient(a);
    }
#endif
    return rb_array_const_ptr_transient(a);
}

/* internal function. do not use this function */
static inline VALUE *
rb_array_ptr_use_start(VALUE a, int allow_transient)
{
    VALUE *rb_ary_ptr_use_start(VALUE ary);

#if USE_TRANSIENT_HEAP
    if (!allow_transient) {
        if (RARRAY_TRANSIENT_P(a)) {
            void rb_ary_detransient(VALUE a);
            rb_ary_detransient(a);
        }
    }
#endif
    (void)allow_transient;

    return rb_ary_ptr_use_start(a);
}

/* internal function. do not use this function */
static inline void
rb_array_ptr_use_end(VALUE a, int allow_transient)
{
    void rb_ary_ptr_use_end(VALUE a);
    rb_ary_ptr_use_end(a);
    (void)allow_transient;
}

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *dln_libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#define RUBY_VM 1 /* YARV */
#define HAVE_NATIVETHREAD
int ruby_native_thread_p(void);

/* traditional set_trace_func events */
#define RUBY_EVENT_NONE      0x0000
#define RUBY_EVENT_LINE      0x0001
#define RUBY_EVENT_CLASS     0x0002
#define RUBY_EVENT_END       0x0004
#define RUBY_EVENT_CALL      0x0008
#define RUBY_EVENT_RETURN    0x0010
#define RUBY_EVENT_C_CALL    0x0020
#define RUBY_EVENT_C_RETURN  0x0040
#define RUBY_EVENT_RAISE     0x0080
#define RUBY_EVENT_ALL       0x00ff

/* for TracePoint extended events */
#define RUBY_EVENT_B_CALL            0x0100
#define RUBY_EVENT_B_RETURN          0x0200
#define RUBY_EVENT_THREAD_BEGIN      0x0400
#define RUBY_EVENT_THREAD_END        0x0800
#define RUBY_EVENT_FIBER_SWITCH      0x1000
#define RUBY_EVENT_SCRIPT_COMPILED   0x2000
#define RUBY_EVENT_TRACEPOINT_ALL    0xffff

/* special events */
#define RUBY_EVENT_RESERVED_FOR_INTERNAL_USE 0x030000

/* internal events */
#define RUBY_INTERNAL_EVENT_SWITCH          0x040000
#define RUBY_EVENT_SWITCH                   0x040000 /* obsolete name. this macro is for compatibility */
                                         /* 0x080000 */
#define RUBY_INTERNAL_EVENT_NEWOBJ          0x100000
#define RUBY_INTERNAL_EVENT_FREEOBJ         0x200000
#define RUBY_INTERNAL_EVENT_GC_START        0x400000
#define RUBY_INTERNAL_EVENT_GC_END_MARK     0x800000
#define RUBY_INTERNAL_EVENT_GC_END_SWEEP   0x1000000
#define RUBY_INTERNAL_EVENT_GC_ENTER       0x2000000
#define RUBY_INTERNAL_EVENT_GC_EXIT        0x4000000
#define RUBY_INTERNAL_EVENT_OBJSPACE_MASK  0x7f00000
#define RUBY_INTERNAL_EVENT_MASK          0xffff0000

typedef uint32_t rb_event_flag_t;
typedef void (*rb_event_hook_func_t)(rb_event_flag_t evflag, VALUE data, VALUE self, ID mid, VALUE klass);

#define RB_EVENT_HOOKS_HAVE_CALLBACK_DATA 1
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);

/* locale insensitive functions */

static inline int rb_isascii(int c){ return '\0' <= c && c <= '\x7f'; }
static inline int rb_isupper(int c){ return 'A' <= c && c <= 'Z'; }
static inline int rb_islower(int c){ return 'a' <= c && c <= 'z'; }
static inline int rb_isalpha(int c){ return rb_isupper(c) || rb_islower(c); }
static inline int rb_isdigit(int c){ return '0' <= c && c <= '9'; }
static inline int rb_isalnum(int c){ return rb_isalpha(c) || rb_isdigit(c); }
static inline int rb_isxdigit(int c){ return rb_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f'); }
static inline int rb_isblank(int c){ return c == ' ' || c == '\t'; }
static inline int rb_isspace(int c){ return c == ' ' || ('\t' <= c && c <= '\r'); }
static inline int rb_iscntrl(int c){ return ('\0' <= c && c < ' ') || c == '\x7f'; }
static inline int rb_isprint(int c){ return ' ' <= c && c <= '\x7e'; }
static inline int rb_ispunct(int c){ return !rb_isalnum(c); }
static inline int rb_isgraph(int c){ return '!' <= c && c <= '\x7e'; }
static inline int rb_tolower(int c) { return rb_isupper(c) ? (c|0x20) : c; }
static inline int rb_toupper(int c) { return rb_islower(c) ? (c&0x5f) : c; }

#ifndef ISPRINT
#define ISASCII(c) rb_isascii(c)
#define ISPRINT(c) rb_isprint(c)
#define ISGRAPH(c) rb_isgraph(c)
#define ISSPACE(c) rb_isspace(c)
#define ISUPPER(c) rb_isupper(c)
#define ISLOWER(c) rb_islower(c)
#define ISALNUM(c) rb_isalnum(c)
#define ISALPHA(c) rb_isalpha(c)
#define ISDIGIT(c) rb_isdigit(c)
#define ISXDIGIT(c) rb_isxdigit(c)
#define ISBLANK(c) rb_isblank(c)
#define ISCNTRL(c) rb_iscntrl(c)
#define ISPUNCT(c) rb_ispunct(c)
#endif
#define TOUPPER(c) rb_toupper(c)
#define TOLOWER(c) rb_tolower(c)

int st_locale_insensitive_strcasecmp(const char *s1, const char *s2);
int st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);
#define STRCASECMP(s1, s2) (st_locale_insensitive_strcasecmp((s1), (s2)))
#define STRNCASECMP(s1, s2, n) (st_locale_insensitive_strncasecmp((s1), (s2), (n)))

unsigned long ruby_strtoul(const char *str, char **endptr, int base);
#define STRTOUL(str, endptr, base) (ruby_strtoul((str), (endptr), (base)))

#define InitVM(ext) {void InitVM_##ext(void);InitVM_##ext();}

PRINTF_ARGS(int ruby_snprintf(char *str, size_t n, char const *fmt, ...), 3, 4);
int ruby_vsnprintf(char *str, size_t n, char const *fmt, va_list ap);

/* -- Remove In 3.0, Only public for rb_scan_args optimized version -- */
int rb_empty_keyword_given_p(void);

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P) && defined(HAVE_VA_ARGS_MACRO) && defined(__OPTIMIZE__)
# define rb_scan_args(argc,argvp,fmt,...) \
    __builtin_choose_expr(__builtin_constant_p(fmt), \
        rb_scan_args0(argc,argvp,fmt,\
		      (sizeof((VALUE*[]){__VA_ARGS__})/sizeof(VALUE*)), \
		      ((VALUE*[]){__VA_ARGS__})), \
        rb_scan_args(argc,argvp,fmt,##__VA_ARGS__))
# if HAVE_ATTRIBUTE_ERRORFUNC
ERRORFUNC(("bad scan arg format"), void rb_scan_args_bad_format(const char*));
ERRORFUNC(("variable argument length doesn't match"), void rb_scan_args_length_mismatch(const char*,int));
# else
#   define rb_scan_args_bad_format(fmt) ((void)0)
#   define rb_scan_args_length_mismatch(fmt, varc) ((void)0)
# endif

# define rb_scan_args_isdigit(c) ((unsigned char)((c)-'0')<10)

#  define rb_scan_args_count_end(fmt, ofs, vari) \
     (fmt[ofs] ? -1 : (vari))

# define rb_scan_args_count_block(fmt, ofs, vari) \
    (fmt[ofs]!='&' ? \
     rb_scan_args_count_end(fmt, ofs, vari) : \
     rb_scan_args_count_end(fmt, ofs+1, vari+1))

# define rb_scan_args_count_hash(fmt, ofs, vari) \
    (fmt[ofs]!=':' ? \
     rb_scan_args_count_block(fmt, ofs, vari) : \
     rb_scan_args_count_block(fmt, ofs+1, vari+1))

# define rb_scan_args_count_trail(fmt, ofs, vari) \
    (!rb_scan_args_isdigit(fmt[ofs]) ? \
     rb_scan_args_count_hash(fmt, ofs, vari) : \
     rb_scan_args_count_hash(fmt, ofs+1, vari+(fmt[ofs]-'0')))

# define rb_scan_args_count_var(fmt, ofs, vari) \
    (fmt[ofs]!='*' ? \
     rb_scan_args_count_trail(fmt, ofs, vari) : \
     rb_scan_args_count_trail(fmt, ofs+1, vari+1))

# define rb_scan_args_count_opt(fmt, ofs, vari) \
    (!rb_scan_args_isdigit(fmt[ofs]) ? \
     rb_scan_args_count_var(fmt, ofs, vari) : \
     rb_scan_args_count_var(fmt, ofs+1, vari+fmt[ofs]-'0'))

# define rb_scan_args_count_lead(fmt, ofs, vari) \
    (!rb_scan_args_isdigit(fmt[ofs]) ? \
      rb_scan_args_count_var(fmt, ofs, vari) : \
      rb_scan_args_count_opt(fmt, ofs+1, vari+fmt[ofs]-'0'))

# define rb_scan_args_count(fmt) rb_scan_args_count_lead(fmt, 0, 0)

# if defined(__has_attribute) && __has_attribute(diagnose_if)
#  define rb_scan_args_verify(fmt, varc) (void)0
# else
# define rb_scan_args_verify(fmt, varc) \
    (sizeof(char[1-2*(rb_scan_args_count(fmt)<0)])!=1 ? \
     rb_scan_args_bad_format(fmt) : \
     sizeof(char[1-2*(rb_scan_args_count(fmt)!=(varc))])!=1 ? \
     rb_scan_args_length_mismatch(fmt, varc) : \
     (void)0)
# endif

ALWAYS_INLINE(static int rb_scan_args_lead_p(const char *fmt));
static inline int
rb_scan_args_lead_p(const char *fmt)
{
    return rb_scan_args_isdigit(fmt[0]);
}

ALWAYS_INLINE(static int rb_scan_args_n_lead(const char *fmt));
static inline int
rb_scan_args_n_lead(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) ? fmt[0]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_opt_p(const char *fmt));
static inline int
rb_scan_args_opt_p(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) && rb_scan_args_isdigit(fmt[1]));
}

ALWAYS_INLINE(static int rb_scan_args_n_opt(const char *fmt));
static inline int
rb_scan_args_n_opt(const char *fmt)
{
    return (rb_scan_args_opt_p(fmt) ? fmt[1]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_var_idx(const char *fmt));
static inline int
rb_scan_args_var_idx(const char *fmt)
{
    return (!rb_scan_args_lead_p(fmt) ? 0 : !rb_scan_args_isdigit(fmt[1]) ? 1 : 2);
}

ALWAYS_INLINE(static int rb_scan_args_f_var(const char *fmt));
static inline int
rb_scan_args_f_var(const char *fmt)
{
    return (fmt[rb_scan_args_var_idx(fmt)]=='*');
}

ALWAYS_INLINE(static int rb_scan_args_trail_idx(const char *fmt));
static inline int
rb_scan_args_trail_idx(const char *fmt)
{
    const int idx = rb_scan_args_var_idx(fmt);
    return idx+(fmt[idx]=='*');
}

ALWAYS_INLINE(static int rb_scan_args_n_trail(const char *fmt));
static inline int
rb_scan_args_n_trail(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return (rb_scan_args_isdigit(fmt[idx]) ? fmt[idx]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_hash_idx(const char *fmt));
static inline int
rb_scan_args_hash_idx(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return idx+rb_scan_args_isdigit(fmt[idx]);
}

ALWAYS_INLINE(static int rb_scan_args_f_hash(const char *fmt));
static inline int
rb_scan_args_f_hash(const char *fmt)
{
    return (fmt[rb_scan_args_hash_idx(fmt)]==':');
}

ALWAYS_INLINE(static int rb_scan_args_block_idx(const char *fmt));
static inline int
rb_scan_args_block_idx(const char *fmt)
{
    const int idx = rb_scan_args_hash_idx(fmt);
    return idx+(fmt[idx]==':');
}

ALWAYS_INLINE(static int rb_scan_args_f_block(const char *fmt));
static inline int
rb_scan_args_f_block(const char *fmt)
{
    return (fmt[rb_scan_args_block_idx(fmt)]=='&');
}

# if 0
ALWAYS_INLINE(static int rb_scan_args_end_idx(const char *fmt));
static inline int
rb_scan_args_end_idx(const char *fmt)
{
    const int idx = rb_scan_args_block_idx(fmt);
    return idx+(fmt[idx]=='&');
}
# endif

/* NOTE: Use `char *fmt` instead of `const char *fmt` because of clang's bug*/
/* https://bugs.llvm.org/show_bug.cgi?id=38095 */
# define rb_scan_args0(argc, argv, fmt, varc, vars) \
    rb_scan_args_set(argc, argv, \
		     rb_scan_args_n_lead(fmt), \
		     rb_scan_args_n_opt(fmt), \
		     rb_scan_args_n_trail(fmt), \
		     rb_scan_args_f_var(fmt), \
		     rb_scan_args_f_hash(fmt), \
		     rb_scan_args_f_block(fmt), \
		     (rb_scan_args_verify(fmt, varc), vars), (char *)fmt, varc)
ALWAYS_INLINE(static int
rb_scan_args_set(int argc, const VALUE *argv,
		 int n_lead, int n_opt, int n_trail,
		 int f_var, int f_hash, int f_block,
		 VALUE *vars[], char *fmt, int varc));

inline int
rb_scan_args_set(int argc, const VALUE *argv,
		 int n_lead, int n_opt, int n_trail,
		 int f_var, int f_hash, int f_block,
		 VALUE *vars[], RB_UNUSED_VAR(char *fmt), RB_UNUSED_VAR(int varc))
# if defined(__has_attribute) && __has_attribute(diagnose_if)
    __attribute__((diagnose_if(rb_scan_args_count(fmt)<0,"bad scan arg format","error")))
    __attribute__((diagnose_if(rb_scan_args_count(fmt)!=varc,"variable argument length doesn't match","error")))
# endif
{
    int i, argi = 0, vari = 0, last_idx = -1;
    VALUE *var, hash = Qnil, last_hash = 0;
    const int n_mand = n_lead + n_trail;
    int keyword_given = rb_keyword_given_p();
    int empty_keyword_given = 0;
    VALUE tmp_buffer = 0;

    if (!keyword_given) {
        empty_keyword_given = rb_empty_keyword_given_p();
    }

    /* capture an option hash - phase 1: pop */
    /* Ignore final positional hash if empty keywords given */
    if (argc > 0 && !(f_hash && empty_keyword_given)) {
        VALUE last = argv[argc - 1];

        if (f_hash && n_mand < argc) {
            if (keyword_given) {
                if (!RB_TYPE_P(last, T_HASH)) {
                    rb_warn("Keyword flag set when calling rb_scan_args, but last entry is not a hash");
                }
                else {
                    hash = last;
                }
            }
            else if (NIL_P(last)) {
                /* For backwards compatibility, nil is taken as an empty
                   option hash only if it is not ambiguous; i.e. '*' is
                   not specified and arguments are given more than sufficient.
                   This will be removed in Ruby 3. */
                if (!f_var && n_mand + n_opt < argc) {
                    rb_warn("The last argument is nil, treating as empty keywords");
                    argc--;
                }
            }
            else {
                hash = rb_check_hash_type(last);
            }

            /* Ruby 3: Remove if branch, as it will not attempt to split hashes */
            if (!NIL_P(hash)) {
                VALUE opts = rb_extract_keywords(&hash);

                if (!(last_hash = hash)) {
                    if (!keyword_given) {
                        /* Warn if treating positional as keyword, as in Ruby 3,
                           this will be an error */
                        rb_warn("The last argument is used as the keyword parameter");
                    }
                    argc--;
                }
                else {
                    /* Warn if splitting either positional hash to keywords or keywords
                       to positional hash, as in Ruby 3, no splitting will be done */
                    rb_warn("The last argument is split into positional and keyword parameters");
                    last_idx = argc - 1;
                }
                hash = opts ? opts : Qnil;
            }
        }
        else if (f_hash && keyword_given && n_mand == argc) {
            /* Warn if treating keywords as positional, as in Ruby 3, this will be an error */
            rb_warn("The keyword argument is passed as the last hash parameter");
        }
    }
    if (f_hash && n_mand > 0 && n_mand == argc+1 && empty_keyword_given) {
        VALUE *ptr = (VALUE *)rb_alloc_tmp_buffer2(&tmp_buffer, argc+1, sizeof(VALUE));
        memcpy(ptr, argv, sizeof(VALUE)*argc);
        ptr[argc] = rb_hash_new();
        argc++;
        *(&argv) = ptr;
        rb_warn("The keyword argument is passed as the last hash parameter");
    }


    if (argc < n_mand) {
        goto argc_error;
    }

    /* capture leading mandatory arguments */
    for (i = n_lead; i-- > 0; ) {
	var = vars[vari++];
	if (var) *var = (argi == last_idx) ? last_hash : argv[argi];
	argi++;
    }
    /* capture optional arguments */
    for (i = n_opt; i-- > 0; ) {
	var = vars[vari++];
	if (argi < argc - n_trail) {
	    if (var) *var = (argi == last_idx) ? last_hash : argv[argi];
	    argi++;
	}
	else {
	    if (var) *var = Qnil;
	}
    }
    /* capture variable length arguments */
    if (f_var) {
	int n_var = argc - argi - n_trail;

	var = vars[vari++];
	if (0 < n_var) {
	    if (var) {
		int f_last = (last_idx + 1 == argc - n_trail);
		*var = rb_ary_new4(n_var-f_last, &argv[argi]);
		if (f_last) rb_ary_push(*var, last_hash);
	    }
	    argi += n_var;
	}
	else {
	    if (var) *var = rb_ary_new();
	}
    }
    /* capture trailing mandatory arguments */
    for (i = n_trail; i-- > 0; ) {
	var = vars[vari++];
	if (var) *var = (argi == last_idx) ? last_hash : argv[argi];
	argi++;
    }
    /* capture an option hash - phase 2: assignment */
    if (f_hash) {
	var = vars[vari++];
	if (var) *var = hash;
    }
    /* capture iterator block */
    if (f_block) {
	var = vars[vari++];
	if (rb_block_given_p()) {
	    *var = rb_block_proc();
	}
	else {
	    *var = Qnil;
	}
    }

    if (argi < argc) {
      argc_error:
        if (tmp_buffer) rb_free_tmp_buffer(&tmp_buffer);
        rb_error_arity(argc, n_mand, f_var ? UNLIMITED_ARGUMENTS : n_mand + n_opt);
    }

    if (tmp_buffer) rb_free_tmp_buffer(&tmp_buffer);
    return argc;
}
#endif

#if defined(__GNUC__) && defined(HAVE_VA_ARGS_MACRO) && defined(__OPTIMIZE__)
# define rb_yield_values(argc, ...) \
__extension__({ \
	const int rb_yield_values_argc = (argc); \
	const VALUE rb_yield_values_args[] = {__VA_ARGS__}; \
	const int rb_yield_values_nargs = \
	    (int)(sizeof(rb_yield_values_args) / sizeof(VALUE)); \
	rb_yield_values2( \
	    rb_varargs_argc_check(rb_yield_values_argc, rb_yield_values_nargs), \
	    rb_yield_values_nargs ? rb_yield_values_args : NULL); \
    })

# define rb_funcall(recv, mid, argc, ...) \
__extension__({ \
	const int rb_funcall_argc = (argc); \
	const VALUE rb_funcall_args[] = {__VA_ARGS__}; \
	const int rb_funcall_nargs = \
	    (int)(sizeof(rb_funcall_args) / sizeof(VALUE)); \
        rb_funcallv(recv, mid, \
	    rb_varargs_argc_check(rb_funcall_argc, rb_funcall_nargs), \
	    rb_funcall_nargs ? rb_funcall_args : NULL); \
    })
#endif

#ifndef RUBY_DONT_SUBST
#include "ruby/subst.h"
#endif

/**
 * @defgroup embed CRuby Embedding APIs
 * CRuby interpreter APIs. These are APIs to embed MRI interpreter into your
 * program.
 * These functions are not a part of Ruby extension library API.
 * Extension libraries of Ruby should not depend on these functions.
 * @{
 */

/** @defgroup ruby1 ruby(1) implementation
 * A part of the implementation of ruby(1) command.
 * Other programs that embed Ruby interpreter do not always need to use these
 * functions.
 * @{
 */

void ruby_sysinit(int *argc, char ***argv);
void ruby_init(void);
void* ruby_options(int argc, char** argv);
int ruby_executable_node(void *n, int *status);
int ruby_run_node(void *n);

/* version.c */
void ruby_show_version(void);
void ruby_show_copyright(void);


/*! A convenience macro to call ruby_init_stack(). Must be placed just after
 *  variable declarations */
#define RUBY_INIT_STACK \
    VALUE variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame);
/*! @} */

void ruby_init_stack(volatile VALUE*);

int ruby_setup(void);
int ruby_cleanup(volatile int);

void ruby_finalize(void);
NORETURN(void ruby_stop(int));

void ruby_set_stack_size(size_t);
int ruby_stack_check(void);
size_t ruby_stack_length(VALUE**);

int ruby_exec_node(void *n);

void ruby_script(const char* name);
void ruby_set_script_name(VALUE name);

void ruby_prog_init(void);
void ruby_set_argv(int, char**);
void *ruby_process_options(int, char**);
void ruby_init_loadpath(void);
void ruby_incpush(const char*);
void ruby_sig_finalize(void);

/*! @} */

#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
extern "C++" {
#endif

#ifdef RB_METHOD_DEFINITION_DECL

RB_METHOD_DEFINITION_DECL(rb_define_method, (2,3), (VALUE klass, const char *name), (klass, name))
#ifdef __cplusplus
#define rb_define_method(m, n, f, a) rb_define_method_tmpl<a>::define(m, n, f)
#else
#define rb_define_method_if_constexpr(x, t, f)    __builtin_choose_expr(__builtin_choose_expr(__builtin_constant_p(x),(x),0),(t),(f))
#define rb_define_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_method15,rb_define_methodm3)
#define rb_define_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_method14,rb_define_method_choose_prototype15(n))
#define rb_define_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_method13,rb_define_method_choose_prototype14(n))
#define rb_define_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_method12,rb_define_method_choose_prototype13(n))
#define rb_define_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_method11,rb_define_method_choose_prototype12(n))
#define rb_define_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_method10,rb_define_method_choose_prototype11(n))
#define rb_define_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_method9, rb_define_method_choose_prototype10(n))
#define rb_define_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_method8, rb_define_method_choose_prototype9(n))
#define rb_define_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_method7, rb_define_method_choose_prototype8(n))
#define rb_define_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_method6, rb_define_method_choose_prototype7(n))
#define rb_define_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_method5, rb_define_method_choose_prototype6(n))
#define rb_define_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_method4, rb_define_method_choose_prototype5(n))
#define rb_define_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_method3, rb_define_method_choose_prototype4(n))
#define rb_define_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_method2, rb_define_method_choose_prototype3(n))
#define rb_define_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_method1, rb_define_method_choose_prototype2(n))
#define rb_define_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_method0, rb_define_method_choose_prototype1(n))
#define rb_define_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_methodm1,rb_define_method_choose_prototype0(n))
#define rb_define_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_methodm2,rb_define_method_choose_prototypem1(n))
#define rb_define_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_methodm3,rb_define_method_choose_prototypem2(n))
#define rb_define_method(klass, mid, func, arity) rb_define_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

RB_METHOD_DEFINITION_DECL(rb_define_module_function, (2,3), (VALUE klass, const char *name), (klass, name))
#ifdef __cplusplus
#define rb_define_module_function(m, n, f, a) rb_define_module_function_tmpl<a>::define(m, n, f)
#else
#define rb_define_module_function_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_module_function15,rb_define_module_functionm3)
#define rb_define_module_function_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_module_function14,rb_define_module_function_choose_prototype15(n))
#define rb_define_module_function_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_module_function13,rb_define_module_function_choose_prototype14(n))
#define rb_define_module_function_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_module_function12,rb_define_module_function_choose_prototype13(n))
#define rb_define_module_function_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_module_function11,rb_define_module_function_choose_prototype12(n))
#define rb_define_module_function_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_module_function10,rb_define_module_function_choose_prototype11(n))
#define rb_define_module_function_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_module_function9, rb_define_module_function_choose_prototype10(n))
#define rb_define_module_function_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_module_function8, rb_define_module_function_choose_prototype9(n))
#define rb_define_module_function_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_module_function7, rb_define_module_function_choose_prototype8(n))
#define rb_define_module_function_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_module_function6, rb_define_module_function_choose_prototype7(n))
#define rb_define_module_function_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_module_function5, rb_define_module_function_choose_prototype6(n))
#define rb_define_module_function_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_module_function4, rb_define_module_function_choose_prototype5(n))
#define rb_define_module_function_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_module_function3, rb_define_module_function_choose_prototype4(n))
#define rb_define_module_function_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_module_function2, rb_define_module_function_choose_prototype3(n))
#define rb_define_module_function_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_module_function1, rb_define_module_function_choose_prototype2(n))
#define rb_define_module_function_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_module_function0, rb_define_module_function_choose_prototype1(n))
#define rb_define_module_function_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_module_functionm1,rb_define_module_function_choose_prototype0(n))
#define rb_define_module_function_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_module_functionm2,rb_define_module_function_choose_prototypem1(n))
#define rb_define_module_function_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_module_functionm3,rb_define_module_function_choose_prototypem2(n))
#define rb_define_module_function(klass, mid, func, arity) rb_define_module_function_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));
#endif

RB_METHOD_DEFINITION_DECL(rb_define_global_function, (1,2), (const char *name), (name))
#ifdef __cplusplus
#define rb_define_global_function(n, f, a) rb_define_global_function_tmpl<a>::define(n, f)
#else
#define rb_define_global_function_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_global_function15,rb_define_global_functionm3)
#define rb_define_global_function_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_global_function14,rb_define_global_function_choose_prototype15(n))
#define rb_define_global_function_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_global_function13,rb_define_global_function_choose_prototype14(n))
#define rb_define_global_function_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_global_function12,rb_define_global_function_choose_prototype13(n))
#define rb_define_global_function_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_global_function11,rb_define_global_function_choose_prototype12(n))
#define rb_define_global_function_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_global_function10,rb_define_global_function_choose_prototype11(n))
#define rb_define_global_function_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_global_function9, rb_define_global_function_choose_prototype10(n))
#define rb_define_global_function_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_global_function8, rb_define_global_function_choose_prototype9(n))
#define rb_define_global_function_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_global_function7, rb_define_global_function_choose_prototype8(n))
#define rb_define_global_function_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_global_function6, rb_define_global_function_choose_prototype7(n))
#define rb_define_global_function_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_global_function5, rb_define_global_function_choose_prototype6(n))
#define rb_define_global_function_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_global_function4, rb_define_global_function_choose_prototype5(n))
#define rb_define_global_function_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_global_function3, rb_define_global_function_choose_prototype4(n))
#define rb_define_global_function_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_global_function2, rb_define_global_function_choose_prototype3(n))
#define rb_define_global_function_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_global_function1, rb_define_global_function_choose_prototype2(n))
#define rb_define_global_function_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_global_function0, rb_define_global_function_choose_prototype1(n))
#define rb_define_global_function_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_global_functionm1,rb_define_global_function_choose_prototype0(n))
#define rb_define_global_function_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_global_functionm2,rb_define_global_function_choose_prototypem1(n))
#define rb_define_global_function_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_global_functionm3,rb_define_global_function_choose_prototypem2(n))
#define rb_define_global_function(mid, func, arity) rb_define_global_function_choose_prototypem3((arity),(func))((mid),(func),(arity));
#endif

#endif

#if !defined(__cplusplus) || defined(RB_METHOD_DEFINITION_DECL)
# define RUBY_METHOD_FUNC(func) (func)
#else
# define RUBY_METHOD_FUNC(func) ((VALUE (*)(ANYARGS))(func))
#endif

#ifdef __cplusplus
#include "backward/cxxanyargs.hpp"

#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C++" { */
#endif

#endif /* RUBY_RUBY_H */
