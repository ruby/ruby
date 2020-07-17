#ifndef RUBY_ASSERT_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ASSERT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @date       Wed May 18 00:21:44 JST 1994
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
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
#include "ruby/internal/assume.h"
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/ndebug.h"
#include "ruby/backward/2/assume.h"

/** @cond INTERNAL_MACRO */
#define RBIMPL_ASSERT_NOTHING RBIMPL_CAST((void)0)

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_COLD()
void rb_assert_failure(const char *file, int line, const char *name, const char *expr);
RBIMPL_SYMBOL_EXPORT_END()

#ifdef RUBY_FUNCTION_NAME_STRING
# define RBIMPL_ASSERT_FUNC RUBY_FUNCTION_NAME_STRING
#else
# define RBIMPL_ASSERT_FUNC RBIMPL_CAST((const char *)0)
#endif

/** @endcond */

/**
 * Prints the given message, and terminates the entire process abnormally.
 *
 * @param  mesg  The message to display.
 */
#define RUBY_ASSERT_FAIL(mesg) \
    rb_assert_failure(__FILE__, __LINE__, RBIMPL_ASSERT_FUNC, mesg)

/**
 * Asserts that the expression is truthy.  If not aborts with the message.
 *
 * @param  expr  What supposedly evaluates to true.
 * @param  mesg  The message to display on failure.
 */
#define RUBY_ASSERT_MESG(expr, mesg) \
    (RB_LIKELY(expr) ? RBIMPL_ASSERT_NOTHING : RUBY_ASSERT_FAIL(mesg))

/**
 * A variant of #RUBY_ASSERT that does not interface with #RUBY_DEBUG.
 *
 * @copydetails #RUBY_ASSERT
 */
#define RUBY_ASSERT_ALWAYS(expr) RUBY_ASSERT_MESG((expr), #expr)

/**
 * Asserts that the given expression is truthy iff #RUBY_DEBUG is truthy.
 *
 * @param  expr  What supposedly evaluates to true.
 */
#if RUBY_DEBUG
# define RUBY_ASSERT(expr) RUBY_ASSERT_MESG((expr), #expr)
#else
# define RUBY_ASSERT(expr) RBIMPL_ASSERT_NOTHING
#endif

/**
 * A  variant  of   #RUBY_ASSERT  that  interfaces  with   #NDEBUG  instead  of
 * #RUBY_DEBUG.  This almost resembles `assert`  C standard macro, except minor
 * implementation details.
 *
 * @copydetails #RUBY_ASSERT
 */
/* Currently  `RUBY_DEBUG == ! defined(NDEBUG)` is  always true.   There is  no
 * difference any longer between this one and `RUBY_ASSERT`. */
#if defined(NDEBUG)
# define RUBY_ASSERT_NDEBUG(expr) RBIMPL_ASSERT_NOTHING
#else
# define RUBY_ASSERT_NDEBUG(expr) RUBY_ASSERT_MESG((expr), #expr)
#endif

/**
 * @copydoc #RUBY_ASSERT_WHEN
 * @param  mesg  The message to display on failure.
 */
#if RUBY_DEBUG
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) RUBY_ASSERT_MESG((expr), (mesg))
#else
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) \
    ((cond) ? RUBY_ASSERT_MESG((expr), (mesg)) : RBIMPL_ASSERT_NOTHING)
#endif

/**
 * A variant  of #RUBY_ASSERT  that asserts when  either #RUBY_DEBUG  or `cond`
 * parameter is truthy.
 *
 * @param  cond  Extra condition that shall hold for assertion to take effect.
 * @param  expr  What supposedly evaluates to true.
 */
#define RUBY_ASSERT_WHEN(cond, expr) RUBY_ASSERT_MESG_WHEN((cond), (expr), #expr)

/**
 * This is either #RUBY_ASSERT or #RBIMPL_ASSUME, depending on #RUBY_DEBUG.
 *
 * @copydetails #RUBY_ASSERT
 */
#if RUBY_DEBUG
# define RBIMPL_ASSERT_OR_ASSUME(expr) RUBY_ASSERT_ALWAYS(expr)
#elif RBIMPL_COMPILER_BEFORE(Clang, 7, 0, 0)
# /* See commit 67d259c5dccd31fe49d417fec169977712ffdf10 */
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#elif defined(RUBY_ASSERT_NOASSUME)
# /* See commit d300a734414ef6de7e8eb563b7cc4389c455ed08 */
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#elif ! defined(RBIMPL_HAVE___ASSUME)
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#else
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSUME(expr)
#endif

#endif /* RUBY_ASSERT_H */
