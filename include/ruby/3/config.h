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
 * @brief      Thin wrapper to ruby/config.h
 */
#ifndef  RUBY3_CONFIG_H
#define  RUBY3_CONFIG_H
#include "ruby/config.h"

#ifdef RUBY_EXTCONF_H
# include RUBY_EXTCONF_H
#endif

#include "ruby/backward/2/gcc_version_since.h"

#if defined(__cplusplus)
/* __builtin_choose_expr and __builtin_types_compatible aren't available
 * on C++.  See https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
# undef HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P
#elif GCC_VERSION_BEFORE(4,8,6) /* Bug #14221 */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
#endif

#ifdef __cplusplus
# ifndef  HAVE_PROTOTYPES
#  define HAVE_PROTOTYPES 1
# endif
# ifndef  HAVE_STDARG_PROTOTYPES
#  define HAVE_STDARG_PROTOTYPES 1
# endif
#endif

#if GCC_VERSION_BEFORE(4,9,5)
/* GCC 4.9.2 reportedly has this feature and is broken.
 * The function is not officially documented below.
 * Seems we should not use it.
 * https://gcc.gnu.org/onlinedocs/gcc-4.9.4/gcc/Other-Builtins.html#Other-Builtins */
# undef HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN
#endif

#define STRINGIZE(expr) STRINGIZE0(expr)
#ifndef STRINGIZE0
#define STRINGIZE0(expr) #expr
#endif

#ifdef AC_APPLE_UNIVERSAL_BUILD
#undef WORDS_BIGENDIAN
#ifdef __BIG_ENDIAN__
#define WORDS_BIGENDIAN
#endif
#endif

#ifndef DLEXT_MAXLEN
#define DLEXT_MAXLEN 4
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
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

#endif /* RUBY3_CONFIG_H */
