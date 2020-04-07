/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @date       Wed May 18 00:21:44 JST 1994
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
 */
#ifndef  RUBY_ASSERT_H
#define  RUBY_ASSERT_H
#include "ruby/3/assume.h"
#include "ruby/3/attr/cold.h"
#include "ruby/3/attr/noreturn.h"
#include "ruby/3/cast.h"
#include "ruby/3/dllexport.h"
#include "ruby/backward/2/assume.h"

#ifndef RUBY_DEBUG
# define RUBY_DEBUG 0
#endif

/*
 * Pro tip: `!!NDEBUG-1` expands to...
 *
 * - `!!(-1)`  (== `!0`  ==  `1`) when NDEBUG is defined to be empty,
 * - `(!!0)-1` (== `0-1` == `-1`) when NDEBUG is defined as 0, and
 * - `(!!n)-1` (== `1-1` ==  `0`) when NDEBUG is defined as something else.
 */
#if defined(RUBY_NDEBUG)
# /* Take that. */
#elif ! defined(NDEBUG)
# define RUBY_NDEBUG 0
#elif !!NDEBUG-1 < 0
# define RUBY_NDEBUG 0
#else
# define RUBY_NDEBUG 1
#endif

#define RUBY3_ASSERT_NOTHING RUBY3_CAST((void)0)

RUBY3_SYMBOL_EXPORT_BEGIN()
RUBY3_ATTR_NORETURN()
RUBY3_ATTR_COLD()
void rb_assert_failure(const char *file, int line, const char *name, const char *expr);
RUBY3_SYMBOL_EXPORT_END()

#ifdef RUBY_FUNCTION_NAME_STRING
# define RUBY3_ASSERT_FUNC RUBY_FUNCTION_NAME_STRING
#else
# define RUBY3_ASSERT_FUNC RUBY3_CAST((const char *)0)
#endif

#define RUBY_ASSERT_FAIL(expr) \
    rb_assert_failure(__FILE__, __LINE__, RUBY3_ASSERT_FUNC, #expr)

#define RUBY_ASSERT_MESG(expr, mesg) \
    (RB_LIKELY(expr) ? RUBY3_ASSERT_NOTHING : RUBY_ASSERT_FAIL(mesg))

#if RUBY_DEBUG
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) RUBY_ASSERT_MESG((expr), mesg)
#elif ! defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) RUBY_ASSERT_MESG(!(cond) || (expr), mesg)
#else
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) \
    __builtin_choose_expr( \
        __builtin_constant_p(cond), \
        __builtin_choose_expr(cond, \
            RUBY_ASSERT_MESG(expr, mesg), \
            RUBY3_ASSERT_NOTHING), \
        RUBY_ASSERT_MESG(!(cond) || (expr), mesg))
#endif /* RUBY_DEBUG */

#define RUBY_ASSERT(expr) RUBY_ASSERT_MESG_WHEN((!RUBY_NDEBUG+0), expr, #expr)
#define RUBY_ASSERT_WHEN(cond, expr) RUBY_ASSERT_MESG_WHEN(cond, expr, #expr)
#define RUBY_ASSERT_ALWAYS(expr) RUBY_ASSERT_MESG_WHEN(TRUE, expr, #expr)

#if ! RUBY_NDEBUG
# define RUBY3_ASSERT_OR_ASSUME(_) RUBY_ASSERT(_)
#elif defined(RUBY3_HAVE___ASSUME)
# define RUBY3_ASSERT_OR_ASSUME(_) RUBY3_ASSUME(_)
#elif RUBY3_HAS_BUILTIN(__builtin_assume)
# define RUBY3_ASSERT_OR_ASSUME(_) RUBY3_ASSUME(_)
#else
# define RUBY3_ASSERT_OR_ASSUME(_) /* void */
#endif

#endif /* RUBY_ASSERT_H */
