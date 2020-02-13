/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Various attribute-related macros.
 *
 * ### Q&A ###
 *
 * - Q: Why  are the  macros defined  in this  header file  so inconsistent  in
 *      style?
 *
 * - A: Don't know.   Don't blame me.  Backward compatibility is  the key here.
 *      I'm just preserving what they have been.
 */
#ifndef  RUBY_BACKWARD2_ATTRIBUTES_H
#define  RUBY_BACKWARD2_ATTRIBUTES_H
#include "ruby/3/config.h"
#include "ruby/backward/2/gcc_version_since.h"

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

#ifdef __GNUC__
#define RB_UNUSED_VAR(x) x __attribute__ ((unused))
#else
#define RB_UNUSED_VAR(x) x
#endif

#endif /* RUBY_BACKWARD2_ATTRIBUTES_H */
