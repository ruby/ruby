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
 * @brief      Defines #RUBY3_ASSUME / #RUBY3_UNREACHABLE.
 *
 * These macros must be defined at once because:
 *
 * - #RUBY3_ASSUME could fallback to #RUBY3_UNREACHABLE.
 * - #RUBY3_UNREACHABLE could fallback to #RUBY3_ASSUME.
 */
#ifndef  RUBY3_ASSUME_H
#define  RUBY3_ASSUME_H
#include "ruby/3/config.h"
#include "ruby/3/cast.h"
#include "ruby/3/has/builtin.h"
#include "ruby/3/warning_push.h"

/** @cond INTERNAL_MACRO */
#if RUBY3_COMPILER_SINCE(MSVC, 13, 10, 0)
# define RUBY3_HAVE___ASSUME

#elif RUBY3_COMPILER_SINCE(Intel, 13, 0, 0)
# define RUBY3_HAVE___ASSUME
#endif
/** @endcond */

/** Wraps (or simulates) `__builtin_unreachable`. */
#if RUBY3_HAS_BUILTIN(__builtin_unreachable)
# define RUBY3_UNREACHABLE_RETURN(_) __builtin_unreachable()

#elif defined(RUBY3_HAVE___ASSUME)
# define RUBY3_UNREACHABLE_RETURN(_) return (__assume(0), (_))

#else
# define RUBY3_UNREACHABLE_RETURN(_) return (_)
#endif

/** Wraps (or simulates) `__builtin_unreachable`. */
#if RUBY3_HAS_BUILTIN(__builtin_unreachable)
# define RUBY3_UNREACHABLE __builtin_unreachable

#elif defined(RUBY3_HAVE___ASSUME)
# define RUBY3_UNREACHABLE() __assume(0)
#endif

/** Wraps (or simulates) `__asume`. */
#if RUBY3_COMPILER_SINCE(Intel, 13, 0, 0)
# /* icc warnings are false positives.  Ignore them. */
# /* "warning #2261: __assume expression with side effects discarded" */
# define RUBY3_ASSUME(expr)     \
    RUBY3_WARNING_PUSH()        \
    RUBY3_WARNING_IGNORED(2261) \
    __assume(expr)              \
    RUBY3_WARNING_POP()

#elif defined(RUBY3_HAVE___ASSUME)
# define RUBY3_ASSUME __assume

#elif RUBY3_HAS_BUILTIN(__builtin_assume)
# define RUBY3_ASSUME __builtin_assume

#elif ! defined(RUBY3_UNREACHABLE)
# define RUBY3_ASSUME(_) RUBY3_CAST((void)(_))

#else
# define RUBY3_ASSUME(_) \
    (RB_LIKELY(!!(_)) ? RUBY3_CAST((void)0) : RUBY3_UNREACHABLE())
#endif

#if ! defined(RUBY3_UNREACHABLE)
# define RUBY3_UNREACHABLE() RUBY3_ASSUME(0)
#endif

#endif /* RUBY3_ASSUME_H */
