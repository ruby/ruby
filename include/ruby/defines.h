/************************************************

  defines.h -

  $Author$
  created at: Wed May 18 00:21:44 JST 1994

************************************************/

#ifndef RUBY_DEFINES_H
#define RUBY_DEFINES_H 1

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

/* AC_INCLUDES_DEFAULT */
#include <stdio.h>
#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif
#ifdef HAVE_SYS_STAT_H
# include <sys/stat.h>
#endif
#ifdef STDC_HEADERS
# include <stdlib.h>
# include <stddef.h>
#else
# ifdef HAVE_STDLIB_H
#  include <stdlib.h>
# endif
#endif
#ifdef HAVE_STRING_H
# if !defined STDC_HEADERS && defined HAVE_MEMORY_H
#  include <memory.h>
# endif
# include <string.h>
#endif
#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif
#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif
#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>
#endif

#if defined HAVE_SETJMPEX_H && defined HAVE__SETJMPEX
#include <setjmpex.h>
#endif

#include "ruby/missing.h"

#define RUBY

#ifdef __cplusplus
# ifndef  HAVE_PROTOTYPES
#  define HAVE_PROTOTYPES 1
# endif
# ifndef  HAVE_STDARG_PROTOTYPES
#  define HAVE_STDARG_PROTOTYPES 1
# endif
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

#ifdef __cplusplus
#define ANYARGS ...
#else
#define ANYARGS
#endif

#ifndef RUBY_SYMBOL_EXPORT_BEGIN
# define RUBY_SYMBOL_EXPORT_BEGIN /* begin */
# define RUBY_SYMBOL_EXPORT_END   /* end */
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#define xmalloc ruby_xmalloc
#define xmalloc2 ruby_xmalloc2
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xrealloc2 ruby_xrealloc2
#define xfree ruby_xfree

#if defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3))
# define RUBY_ATTR_ALLOC_SIZE(params) __attribute__ ((__alloc_size__ params))
#else
# define RUBY_ATTR_ALLOC_SIZE(params)
#endif

void *xmalloc(size_t) RUBY_ATTR_ALLOC_SIZE((1));
void *xmalloc2(size_t,size_t) RUBY_ATTR_ALLOC_SIZE((1,2));
void *xcalloc(size_t,size_t) RUBY_ATTR_ALLOC_SIZE((1,2));
void *xrealloc(void*,size_t) RUBY_ATTR_ALLOC_SIZE((2));
void *xrealloc2(void*,size_t,size_t) RUBY_ATTR_ALLOC_SIZE((2,3));
void xfree(void*);

#define STRINGIZE(expr) STRINGIZE0(expr)
#ifndef STRINGIZE0
#define STRINGIZE0(expr) #expr
#endif

#ifdef HAVE_LONG_LONG
# define HAVE_TRUE_LONG_LONG 1
#endif

#if SIZEOF_LONG_LONG > 0
# define LONG_LONG long long
#elif SIZEOF___INT64 > 0
# define HAVE_LONG_LONG 1
# define LONG_LONG __int64
# undef SIZEOF_LONG_LONG
# define SIZEOF_LONG_LONG SIZEOF___INT64
#endif

#ifdef __CYGWIN__
#undef _WIN32
#endif

#if defined(_WIN32)
/*
  DOSISH mean MS-Windows style filesystem.
  But you should use more precise macros like DOSISH_DRIVE_LETTER, PATH_SEP,
  ENV_IGNORECASE or CASEFOLD_FILESYSTEM.
 */
#define DOSISH 1
# define DOSISH_DRIVE_LETTER
#endif

#ifdef AC_APPLE_UNIVERSAL_BUILD
#undef WORDS_BIGENDIAN
#ifdef __BIG_ENDIAN__
#define WORDS_BIGENDIAN
#endif
#endif

#ifdef _WIN32
#include "ruby/win32.h"
#endif

#ifdef RUBY_EXPORT
#undef RUBY_EXTERN

#ifndef FALSE
# define FALSE 0
#elif FALSE
# error FALSE must be false
#endif
#ifndef TRUE
# define TRUE 1
#elif !TRUE
# error TRUE must be true
#endif

#endif

#ifndef RUBY_FUNC_EXPORTED
#define RUBY_FUNC_EXPORTED
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

#ifndef EXTERN
#define EXTERN RUBY_EXTERN	/* deprecated */
#endif

#ifndef RUBY_MBCHAR_MAXSIZE
#define RUBY_MBCHAR_MAXSIZE INT_MAX
        /* MB_CUR_MAX will not work well in C locale */
#endif

#if defined(__sparc)
void rb_sparc_flush_register_windows(void);
#  define FLUSH_REGISTER_WINDOWS rb_sparc_flush_register_windows()
#elif defined(__ia64)
void *rb_ia64_bsp(void);
void rb_ia64_flushrs(void);
#  define FLUSH_REGISTER_WINDOWS rb_ia64_flushrs()
#else
#  define FLUSH_REGISTER_WINDOWS ((void)0)
#endif

#if defined(DOSISH)
#define PATH_SEP ";"
#else
#define PATH_SEP ":"
#endif
#define PATH_SEP_CHAR PATH_SEP[0]

#define PATH_ENV "PATH"

#if defined(DOSISH)
#define ENV_IGNORECASE
#endif

#ifndef CASEFOLD_FILESYSTEM
# if defined DOSISH
#   define CASEFOLD_FILESYSTEM 1
# else
#   define CASEFOLD_FILESYSTEM 0
# endif
#endif

#ifndef DLEXT_MAXLEN
#define DLEXT_MAXLEN 4
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#ifndef FUNC_MINIMIZED
#define FUNC_MINIMIZED(x) x
#endif
#ifndef FUNC_UNOPTIMIZED
#define FUNC_UNOPTIMIZED(x) x
#endif
#ifndef RUBY_ALIAS_FUNCTION_TYPE
#define RUBY_ALIAS_FUNCTION_TYPE(type, prot, name, args) \
    FUNC_MINIMIZED(type prot) {return (type)name args;}
#endif
#ifndef RUBY_ALIAS_FUNCTION_VOID
#define RUBY_ALIAS_FUNCTION_VOID(prot, name, args) \
    FUNC_MINIMIZED(void prot) {name args;}
#endif
#ifndef RUBY_ALIAS_FUNCTION
#define RUBY_ALIAS_FUNCTION(prot, name, args) \
    RUBY_ALIAS_FUNCTION_TYPE(VALUE, prot, name, args)
#endif

#ifndef UNALIGNED_WORD_ACCESS
# if defined(__i386) || defined(__i386__) || defined(_M_IX86) || \
     defined(__x86_64) || defined(__x86_64__) || defined(_M_AMD64) || \
     defined(__powerpc64__) || \
     defined(__mc68020__)
#   define UNALIGNED_WORD_ACCESS 1
# else
#   define UNALIGNED_WORD_ACCESS 0
# endif
#endif
#ifndef PACKED_STRUCT
# define PACKED_STRUCT(x) x
#endif
#ifndef PACKED_STRUCT_UNALIGNED
# if UNALIGNED_WORD_ACCESS
#   define PACKED_STRUCT_UNALIGNED(x) PACKED_STRUCT(x)
# else
#   define PACKED_STRUCT_UNALIGNED(x) x
# endif
#endif

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_DEFINES_H */
