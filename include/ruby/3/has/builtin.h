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
 * @brief      Defines #RUBY3_HAS_BUILTIN.
 */
#include "ruby/3/config.h"

/** Wraps (or simulates) `__has_builtin`. */
#if defined(RUBY3_HAS_BUILTIN)
# /* Take that. */

#elif defined(__has_builtin) && ! RUBY3_COMPILER_IS(Intel)
# /* :TODO:  Intel C  Compiler has  __has_builtin (since  19.1 maybe?),  and is
#  * reportedly  broken.  We  have to  skip  them.  However  the situation  can
#  * change.  They might improve someday.  We need to revisit here later. */
# define RUBY3_HAS_BUILTIN(_) __has_builtin(_)

#elif RUBY3_COMPILER_IS(GCC)
# /* :FIXME: Historically  GCC has had  tons of builtins, but  it implemented
#  * __has_builtin  only  since  GCC  10.   This section  can  be  made  more
#  * granular. */
# /* https://gcc.gnu.org/bugzilla/show_bug.cgi?id=66970 */
# define RUBY3_HAS_BUILTIN(_) RUBY3_TOKEN_PASTE(RUBY3_HAS_BUILTIN_, _)
# define RUBY3_HAS_BUILTIN___builtin_add_overflow      RUBY3_COMPILER_SINCE(GCC, 5, 1, 0)
# define RUBY3_HAS_BUILTIN___builtin_alloca            RUBY3_COMPILER_SINCE(GCC, 0, 0, 0)
# define RUBY3_HAS_BUILTIN___builtin_alloca_with_align RUBY3_COMPILER_SINCE(GCC, 6, 1, 0)
# /* See http://gcc.gnu.org/bugzilla/show_bug.cgi?id=52624 for bswap16. */
# define RUBY3_HAS_BUILTIN___builtin_bswap16           RUBY3_COMPILER_SINCE(GCC, 4, 8, 0)
# define RUBY3_HAS_BUILTIN___builtin_bswap32           RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_bswap64           RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_clz               RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_clzl              RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_clzll             RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_constant_p        RUBY3_COMPILER_SINCE(GCC, 2,95, 3)
# define RUBY3_HAS_BUILTIN___builtin_ctz               RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_ctzl              RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_ctzll             RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_expect            RUBY3_COMPILER_SINCE(GCC, 3, 0, 0)
# define RUBY3_HAS_BUILTIN___builtin_mul_overflow      RUBY3_COMPILER_SINCE(GCC, 5, 1, 0)
# define RUBY3_HAS_BUILTIN___builtin_mul_overflow_p    RUBY3_COMPILER_SINCE(GCC, 7, 0, 0)
# define RUBY3_HAS_BUILTIN___builtin_popcount          RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_popcountl         RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_popcountll        RUBY3_COMPILER_SINCE(GCC, 3, 6, 0)
# define RUBY3_HAS_BUILTIN___builtin_sub_overflow      RUBY3_COMPILER_SINCE(GCC, 5, 1, 0)
# define RUBY3_HAS_BUILTIN___builtin_unreachable       RUBY3_COMPILER_SINCE(GCC, 4, 5, 0)
# /* Note that "0, 0, 0" might be inaccurate. */

#elif RUBY3_COMPILER_IS(MSVC)
# /* MSVC has UNREACHABLE, but that is not __builtin_unreachable. */
# define RUBY3_HAS_BUILTIN(_) 0

#else
# /* Take config.h definition when available */
# define RUBY3_HAS_BUILTIN(_) (RUBY3_TOKEN_PASTE(RUBY3_HAS_BUILTIN_, _)+0)
# define RUBY3_HAS_BUILTIN___builtin_add_overflow      HAVE_BUILTIN___BUILTIN_ADD_OVERFLOW
# define RUBY3_HAS_BUILTIN___builtin_alloca_with_align HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN
# define RUBY3_HAS_BUILTIN___builtin_assume_aligned    HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED
# define RUBY3_HAS_BUILTIN___builtin_bswap16           HAVE_BUILTIN___BUILTIN_BSWAP16
# define RUBY3_HAS_BUILTIN___builtin_bswap32           HAVE_BUILTIN___BUILTIN_BSWAP32
# define RUBY3_HAS_BUILTIN___builtin_bswap64           HAVE_BUILTIN___BUILTIN_BSWAP64
# define RUBY3_HAS_BUILTIN___builtin_clz               HAVE_BUILTIN___BUILTIN_CLZ
# define RUBY3_HAS_BUILTIN___builtin_clzl              HAVE_BUILTIN___BUILTIN_CLZL
# define RUBY3_HAS_BUILTIN___builtin_clzll             HAVE_BUILTIN___BUILTIN_CLZLL
# define RUBY3_HAS_BUILTIN___builtin_constant_p        HAVE_BUILTIN___BUILTIN_CONSTANT_P
# define RUBY3_HAS_BUILTIN___builtin_ctz               HAVE_BUILTIN___BUILTIN_CTZ
# define RUBY3_HAS_BUILTIN___builtin_ctzll             HAVE_BUILTIN___BUILTIN_CTZLL
# define RUBY3_HAS_BUILTIN___builtin_expect            HAVE_BUILTIN___BUILTIN_EXPECT
# define RUBY3_HAS_BUILTIN___builtin_mul_overflow      HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW
# define RUBY3_HAS_BUILTIN___builtin_mul_overflow_p    HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW_P
# define RUBY3_HAS_BUILTIN___builtin_popcount          HAVE_BUILTIN___BUILTIN_POPCOUNT
# define RUBY3_HAS_BUILTIN___builtin_popcountll        HAVE_BUILTIN___BUILTIN_POPCOUNTLL
# define RUBY3_HAS_BUILTIN___builtin_sub_overflow      HAVE_BUILTIN___BUILTIN_SUB_OVERFLOW
# if defined(UNREACHABLE)
#  define RUBY3_HAS_BUILTIN___builtin_unreachable 1
# endif
#endif
