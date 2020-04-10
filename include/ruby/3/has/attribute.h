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
 * @brief      Defines #RUBY3_HAS_ATTRIBUTE.
 */
#include "ruby/3/config.h"

/** Wraps (or simulates) `__has_attribute`. */
#if defined(RUBY3_HAS_ATTRIBUTE)
# /* Take that. */

#elif defined(__has_attribute)
# define RUBY3_HAS_ATTRIBUTE(_) __has_attribute(_)

#elif RUBY3_COMPILER_IS(GCC)
# /* GCC  <= 4  lack __has_attribute  predefined macro,  while have  attributes
#  * themselves.  We can simulate the macro like the following: */
# define RUBY3_HAS_ATTRIBUTE(_) RUBY3_TOKEN_PASTE(RUBY3_HAS_ATTRIBUTE_, _)
# define RUBY3_HAS_ATTRIBUTE_aligned                    RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_alloc_size                 RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_artificial                 RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_always_inline              RUBY3_COMPILER_SINCE(GCC, 3, 1, 0)
# define RUBY3_HAS_ATTRIBUTE_cdecl                      RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_cold                       RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_const                      RUBY3_COMPILER_SINCE(GCC, 2, 6, 0)
# define RUBY3_HAS_ATTRIBUTE_deprecated                 RUBY3_COMPILER_SINCE(GCC, 3, 1, 0)
# define RUBY3_HAS_ATTRIBUTE_dllexport                  RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_dllimport                  RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_error                      RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_format                     RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_hot                        RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_leaf                       RUBY3_COMPILER_SINCE(GCC, 4, 6, 0)
# define RUBY3_HAS_ATTRIBUTE_malloc                     RUBY3_COMPILER_SINCE(GCC, 3, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_no_address_safety_analysis RUBY3_COMPILER_SINCE(GCC, 4, 8, 0)
# define RUBY3_HAS_ATTRIBUTE_no_sanitize_address        RUBY3_COMPILER_SINCE(GCC, 4, 8, 0)
# define RUBY3_HAS_ATTRIBUTE_no_sanitize_undefined      RUBY3_COMPILER_SINCE(GCC, 4, 9, 0)
# define RUBY3_HAS_ATTRIBUTE_noinline                   RUBY3_COMPILER_SINCE(GCC, 3, 1, 0)
# define RUBY3_HAS_ATTRIBUTE_nonnull                    RUBY3_COMPILER_SINCE(GCC, 3, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_noreturn                   RUBY3_COMPILER_SINCE(GCC, 2, 5, 0)
# define RUBY3_HAS_ATTRIBUTE_nothrow                    RUBY3_COMPILER_SINCE(GCC, 3, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_pure                       RUBY3_COMPILER_SINCE(GCC, 2,96, 0)
# define RUBY3_HAS_ATTRIBUTE_returns_nonnull            RUBY3_COMPILER_SINCE(GCC, 4, 9, 0)
# define RUBY3_HAS_ATTRIBUTE_returns_twice              RUBY3_COMPILER_SINCE(GCC, 4, 1, 0)
# define RUBY3_HAS_ATTRIBUTE_stdcall                    RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_unused                     RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_ATTRIBUTE_visibility                 RUBY3_COMPILER_SINCE(GCC, 3, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_warn_unused_result         RUBY3_COMPILER_SINCE(GCC, 3, 4, 0)
# define RUBY3_HAS_ATTRIBUTE_warning                    RUBY3_COMPILER_SINCE(GCC, 4, 3, 0)
# define RUBY3_HAS_ATTRIBUTE_weak                       RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# /* Note that "0, 0, 0" might be inaccurate. */

#elif RUBY3_COMPILER_IS(SunPro)
# /* Oracle Solaris Studio 12.4 (cc version 5.11) introduced __has_attribute.
#  * Before that, following attributes were available. */
# /* See https://docs.oracle.com/cd/F24633_01/index.html */
# define RUBY3_HAS_ATTRIBUTE(_) RUBY3_TOKEN_PASTE(RUBY3_HAS_ATTRIBUTE_, _)
# define RUBY3_HAS_ATTRIBUTE_alias                      RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_aligned                    RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_always_inline              RUBY3_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RUBY3_HAS_ATTRIBUTE_const                      RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_constructor                RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_destructor                 RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_malloc                     RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_noinline                   RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_noreturn                   RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_packed                     RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_pure                       RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_returns_twice              RUBY3_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RUBY3_HAS_ATTRIBUTE_vector_size                RUBY3_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RUBY3_HAS_ATTRIBUTE_visibility                 RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RUBY3_HAS_ATTRIBUTE_weak                       RUBY3_COMPILER_SINCE(SunPro, 5,  9, 0)

#elif defined (_MSC_VER)
# define RUBY3_HAS_ATTRIBUTE(_) 0
# /* Fallback below doesn't work: see win32/Makefile.sub */

#else
# /* Take config.h definition when available. */
# define RUBY3_HAS_ATTRIBUTE(_) (RUBY3_TOKEN_PASTE(RUBY3_HAS_ATTRIBUTE_, _)+0)
# ifdef ALWAYS_INLINE
#  define RUBY3_HAS_ATTRIBUTE_always_inline 1
# endif
# ifdef FUNC_CDECL
#  define RUBY3_HAS_ATTRIBUTE_cdecl 1
# endif
# ifdef CONSTFUNC
#  define RUBY3_HAS_ATTRIBUTE_const 1
# endif
# ifdef DEPRECATED
#  define RUBY3_HAS_ATTRIBUTE_deprecated 1
# endif
# ifdef ERRORFUNC
#  define RUBY3_HAS_ATTRIBUTE_error 1
# endif
# ifdef FUNC_FASTCALL
#  define RUBY3_HAS_ATTRIBUTE_fastcall 1
# endif
# ifdef PUREFUNC
#  define RUBY3_HAS_ATTRIBUTE_pure 1
# endif
# ifdef NO_ADDRESS_SAFETY_ANALYSIS
#  define RUBY3_HAS_ATTRIBUTE_no_address_safety_analysis 1
# endif
# ifdef NO_SANITIZE
#  define RUBY3_HAS_ATTRIBUTE_no_sanitize 1
# endif
# ifdef NO_SANITIZE_ADDRESS
#  define RUBY3_HAS_ATTRIBUTE_no_sanitize_address 1
# endif
# ifdef NOINLINE
#  define RUBY3_HAS_ATTRIBUTE_noinline 1
# endif
# ifdef RUBY3_FUNC_NONNULL
#  define RUBY3_HAS_ATTRIBUTE_nonnull 1
# endif
# ifdef NORETURN
#  define RUBY3_HAS_ATTRIBUTE_noreturn 1
# endif
# ifdef FUNC_OPTIMIZED
#  define RUBY3_HAS_ATTRIBUTE_optimize 1
# endif
# ifdef FUNC_STDCALL
#  define RUBY3_HAS_ATTRIBUTE_stdcall 1
# endif
# ifdef MAYBE_UNUSED
#  define RUBY3_HAS_ATTRIBUTE_unused 1
# endif
# ifdef WARN_UNUSED_RESULT
#  define RUBY3_HAS_ATTRIBUTE_warn_unused_result 1
# endif
# ifdef WARNINGFUNC
#  define RUBY3_HAS_ATTRIBUTE_warning 1
# endif
# ifdef WEAK
#  define RUBY3_HAS_ATTRIBUTE_weak 1
# endif
#endif
