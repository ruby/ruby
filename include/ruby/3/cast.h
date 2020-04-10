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
 * @brief      Defines RUBY3_CAST.
 * @cond       INTERNAL_MACRO
 *
 * This casting macro makes sense only inside  of other macros that are part of
 * public headers.  They could be used  from C++, and C-style casts could issue
 * warnings.  Ruby internals are pure C so they should not bother.
 */

#if defined(RUBY3_CAST)
# /* Take that. */

#elif ! defined(__cplusplus)
# define RUBY3_CAST(expr) (expr)

#elif RUBY3_COMPILER_SINCE(GCC, 4, 6, 0)
# /* g++ has -Wold-style-cast since 1997 or so, but its _Pragma is broken. */
# /* See https://gcc.godbolt.org/z/XWhU6J */
# define RUBY3_CAST(expr) (expr)
# pragma GCC diagnostic ignored "-Wold-style-cast"

#elif RUBY3_HAS_WARNING("-Wold-style-cast")
# define RUBY3_CAST(expr)                   \
    RUBY3_WARNING_PUSH()                    \
    RUBY3_WARNING_IGNORED(-Wold-style-cast) \
    (expr)                                  \
    RUBY3_WARNING_POP()

#else
# define RUBY3_CAST(expr) (expr)
#endif
/** @endcond */
