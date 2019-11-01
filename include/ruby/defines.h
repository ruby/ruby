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

/* function attributes */
#ifndef CONSTFUNC
# define CONSTFUNC(x) x
#endif
#ifndef PUREFUNC
# define PUREFUNC(x) x
#endif
#ifndef DEPRECATED
# define DEPRECATED(x) x
#endif
#ifndef DEPRECATED_BY
# define DEPRECATED_BY(n,x) DEPRECATED(x)
#endif
#ifndef DEPRECATED_TYPE
# define DEPRECATED_TYPE(mesg, decl) decl
#endif
#ifndef RUBY_CXX_DEPRECATED
# define RUBY_CXX_DEPRECATED(mesg) /* nothing */
#endif
#ifndef NOINLINE
# define NOINLINE(x) x
#endif
#ifndef ALWAYS_INLINE
# define ALWAYS_INLINE(x) x
#endif
#ifndef ERRORFUNC
# define HAVE_ATTRIBUTE_ERRORFUNC 0
# define ERRORFUNC(mesg, x) x
#else
# define HAVE_ATTRIBUTE_ERRORFUNC 1
#endif
#ifndef WARNINGFUNC
# define HAVE_ATTRIBUTE_WARNINGFUNC 0
# define WARNINGFUNC(mesg, x) x
#else
# define HAVE_ATTRIBUTE_WARNINGFUNC 1
#endif

#ifndef GCC_VERSION_SINCE
# if defined(__GNUC__) && !defined(__INTEL_COMPILER) && !defined(__clang__)
#  define GCC_VERSION_SINCE(major, minor, patchlevel) \
    ((__GNUC__ > (major)) ||  \
     ((__GNUC__ == (major) && \
       ((__GNUC_MINOR__ > (minor)) || \
        (__GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ >= (patchlevel))))))
# else
#  define GCC_VERSION_SINCE(major, minor, patchlevel) 0
# endif
#endif
#ifndef GCC_VERSION_BEFORE
# if defined(__GNUC__) && !defined(__INTEL_COMPILER) && !defined(__clang__)
#  define GCC_VERSION_BEFORE(major, minor, patchlevel) \
    ((__GNUC__ < (major)) ||  \
     ((__GNUC__ == (major) && \
       ((__GNUC_MINOR__ < (minor)) || \
        (__GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ <= (patchlevel))))))
# else
#  define GCC_VERSION_BEFORE(major, minor, patchlevel) 0
# endif
#endif

/* likely */
#if __GNUC__ >= 3
#define RB_LIKELY(x)   (__builtin_expect(!!(x), 1))
#define RB_UNLIKELY(x) (__builtin_expect(!!(x), 0))
#else /* __GNUC__ >= 3 */
#define RB_LIKELY(x)   (x)
#define RB_UNLIKELY(x) (x)
#endif /* __GNUC__ >= 3 */

/*
  cold attribute for code layout improvements
  RUBY_FUNC_ATTRIBUTE not used because MSVC does not like nested func macros
 */
#if defined(__clang__) || GCC_VERSION_SINCE(4, 3, 0)
#define COLDFUNC __attribute__((cold))
#else
#define COLDFUNC
#endif

#ifdef __GNUC__
#if defined __MINGW_PRINTF_FORMAT
#define PRINTF_ARGS(decl, string_index, first_to_check) \
  decl __attribute__((format(__MINGW_PRINTF_FORMAT, string_index, first_to_check)))
#else
#define PRINTF_ARGS(decl, string_index, first_to_check) \
  decl __attribute__((format(printf, string_index, first_to_check)))
#endif
#else
#define PRINTF_ARGS(decl, string_index, first_to_check) decl
#endif

#ifdef __GNUC__
#define RB_GNUC_EXTENSION __extension__
#define RB_GNUC_EXTENSION_BLOCK(x) __extension__ ({ x; })
#else
#define RB_GNUC_EXTENSION
#define RB_GNUC_EXTENSION_BLOCK(x) (x)
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
#ifdef HAVE_STDALIGN_H
# include <stdalign.h>
#endif
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>
#endif

#ifdef RUBY_USE_SETJMPEX
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

#if GCC_VERSION_SINCE(4,3,0)
# define RUBY_ATTR_ALLOC_SIZE(params) __attribute__ ((alloc_size params))
#elif defined(__has_attribute)
# if __has_attribute(alloc_size)
#  define RUBY_ATTR_ALLOC_SIZE(params) __attribute__((__alloc_size__ params))
# endif
#endif
#ifndef RUBY_ATTR_ALLOC_SIZE
# define RUBY_ATTR_ALLOC_SIZE(params)
#endif

#ifdef __has_attribute
# if __has_attribute(malloc)
#  define RUBY_ATTR_MALLOC __attribute__((__malloc__))
# endif
#endif
#ifndef RUBY_ATTR_MALLOC
# define RUBY_ATTR_MALLOC
#endif

#ifdef __has_attribute
# if __has_attribute(returns_nonnull)
#  define RUBY_ATTR_RETURNS_NONNULL __attribute__((__returns_nonnull__))
# endif
#endif
#ifndef RUBY_ATTR_RETURNS_NONNULL
# define RUBY_ATTR_RETURNS_NONNULL
#endif

void *ruby_xmalloc(size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1));
void *ruby_xmalloc2(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xcalloc(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xrealloc(void*,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_xrealloc2(void*,size_t,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2,3));
void ruby_xfree(void*);

#ifndef USE_GC_MALLOC_OBJ_INFO_DETAILS
#define USE_GC_MALLOC_OBJ_INFO_DETAILS 0
#endif

#if USE_GC_MALLOC_OBJ_INFO_DETAILS

void *ruby_xmalloc_body(size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1));
void *ruby_xmalloc2_body(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xcalloc_body(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xrealloc_body(void*,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_xrealloc2_body(void*,size_t,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2,3));

#define ruby_xmalloc(s1)            ruby_xmalloc_with_location(s1, __FILE__, __LINE__)
#define ruby_xmalloc2(s1, s2)       ruby_xmalloc2_with_location(s1, s2, __FILE__, __LINE__)
#define ruby_xcalloc(s1, s2)        ruby_xcalloc_with_location(s1, s2, __FILE__, __LINE__)
#define ruby_xrealloc(ptr, s1)      ruby_xrealloc_with_location(ptr, s1, __FILE__, __LINE__)
#define ruby_xrealloc2(ptr, s1, s2) ruby_xrealloc2_with_location(ptr, s1, s2, __FILE__, __LINE__)

extern const char *ruby_malloc_info_file;
extern int ruby_malloc_info_line;

static inline void *
ruby_xmalloc_with_location(size_t s, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc_body(s);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xmalloc2_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc2_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xcalloc_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xcalloc_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xrealloc_with_location(void *ptr, size_t s, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc_body(ptr, s);
    ruby_malloc_info_file = NULL;
    return rptr;
}

static inline void *
ruby_xrealloc2_with_location(void *ptr, size_t s1, size_t s2, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc2_body(ptr, s1, s2);
    ruby_malloc_info_file = NULL;
    return rptr;
}
#endif

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

/* These macros are used for functions which are exported only for MJIT
   and NOT ensured to be exported in future versions. */
#define MJIT_FUNC_EXPORTED RUBY_FUNC_EXPORTED
#define MJIT_SYMBOL_EXPORT_BEGIN RUBY_SYMBOL_EXPORT_BEGIN
#define MJIT_SYMBOL_EXPORT_END RUBY_SYMBOL_EXPORT_END

#if defined(MJIT_HEADER) && defined(_MSC_VER)
# undef MJIT_FUNC_EXPORTED
# define MJIT_FUNC_EXPORTED static
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

#ifndef EXTERN
# if defined __GNUC__
#   define EXTERN _Pragma("message \"EXTERN is deprecated, use RUBY_EXTERN instead\""); \
    RUBY_EXTERN
# elif defined _MSC_VER
#   define EXTERN __pragma(message(__FILE__"("STRINGIZE(__LINE__)"): warning: "\
				   "EXTERN is deprecated, use RUBY_EXTERN instead")); \
    RUBY_EXTERN
# else
#   define EXTERN <-<-"EXTERN is deprecated, use RUBY_EXTERN instead"->->
# endif
#endif

#ifndef RUBY_MBCHAR_MAXSIZE
#define RUBY_MBCHAR_MAXSIZE INT_MAX
        /* MB_CUR_MAX will not work well in C locale */
#endif

#if defined(__sparc)
void rb_sparc_flush_register_windows(void);
#  define FLUSH_REGISTER_WINDOWS rb_sparc_flush_register_windows()
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
#ifndef RUBY_FUNC_NONNULL
#define RUBY_FUNC_NONNULL(n, x) x
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

#ifndef RUBY_ALIGNAS
#define RUBY_ALIGNAS(x) /* x */
#endif

#ifdef RUBY_ALIGNOF
/* OK, take that definition */
#elif defined(__cplusplus) && (__cplusplus >= 201103L)
#define RUBY_ALIGNOF alignof
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define RUBY_ALIGNOF _Alignof
#else
#define RUBY_ALIGNOF(type) ((size_t)offsetof(struct { char f1; type f2; }, f2))
#endif

#define NORETURN_STYLE_NEW 1
#ifdef NORETURN
/* OK, take that definition */
#elif defined(__cplusplus) && (__cplusplus >= 201103L)
#define NORETURN(x) [[ noreturn ]] x
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define NORETURN(x) _Noreturn x
#else
#define NORETURN(x) x
#endif

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_DEFINES_H */
