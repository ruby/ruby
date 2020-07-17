#ifndef RBIMPL_NDEBUG_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_NDEBUG_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
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
 * @brief      Defines #RUBY_NDEBUG (according to #NDEBUG)
 *
 * RUBY_NDEBUG  is very  simple:  after everything  described  below are  done,
 * define it with either NDEBUG is undefined (=0) or defined (=1).  It is truly
 * subordinate.
 *
 * RUBY_DEBUG versus NDEBUG is complicated.  Assertions shall be:
 *
 *                      | -UNDEBUG | -DNDEBUG
 *       ---------------+----------+---------
 *       -URUBY_DEBUG   | (*1)     | disabled
 *       -DRUBY_DEBUG=0 | disabled | disabled
 *       -DRUBY_DEBUG=1 | enabled  | (*2)
 *       -DRUBY_DEBUG   | enabled  | (*2)
 *
 * where:
 *
 *   - (*1): Assertions shall  be silently disabled, no warnings,  in favour of
 *     commit 21991e6ca59274e41a472b5256bd3245f6596c90.
 *
 *   - (*2): Compile-time warnings shall be issued.
 */

/** @cond INTERNAL_MACRO */

/*
 * Pro tip: `!!RUBY_DEBUG-1` expands to...
 *
 * - `!!(-1)`  (== `!0`  ==  `1`) when RUBY_DEBUG is defined to be empty,
 * - `(!!0)-1` (== `0-1` == `-1`) when RUBY_DEBUG is defined as 0, and
 * - `(!!n)-1` (== `1-1` ==  `0`) when RUBY_DEBUG is defined as something else.
 */
#if ! defined(RUBY_DEBUG)
# define RBIMPL_RUBY_DEBUG 0
#elif !!RUBY_DEBUG-1 < 0
# define RBIMPL_RUBY_DEBUG 0
#else
# define RBIMPL_RUBY_DEBUG 1
#endif

/*
 * ISO/IEC 9899 (all past versions) says that  "If NDEBUG is defined as a macro
 * name at  the point  in the  source file where  <assert.h> is  included, ..."
 * which means we must not take its defined value into account.
 */
#if defined(NDEBUG)
# define RBIMPL_NDEBUG 1
#else
# define RBIMPL_NDEBUG 0
#endif

/** @endcond */

/* Here we go... */
#undef RUBY_DEBUG
#undef RUBY_NDEBUG
#undef NDEBUG
#if defined(__DOXYGEN__)
# /** Define this macro when you want assertions. */
# define RUBY_DEBUG 0
# /** Define this macro when you don't want assertions. */
# define NDEBUG
# /** This macro is basically the same as #NDEBUG */
# define RUBY_NDEBUG 1

#elif (RBIMPL_NDEBUG == 1) && (RBIMPL_RUBY_DEBUG == 0)
# /* Assertions disabled as per request, no conflicts. */
# define RUBY_DEBUG 0
# define RUBY_NDEBUG 1
# define NDEBUG

#elif (RBIMPL_NDEBUG == 0) && (RBIMPL_RUBY_DEBUG == 1)
# /* Assertions enabled as per request, no conflicts. */
# define RUBY_DEBUG 1
# define RUBY_NDEBUG 0
# /* keep NDEBUG undefined */

#elif (RBIMPL_NDEBUG == 0) && (RBIMPL_RUBY_DEBUG == 0)
# /* The (*1) situation in avobe diagram. */
# define RUBY_DEBUG 0
# define RUBY_NDEBUG 1
# define NDEBUG

#elif (RBIMPL_NDEBUG == 1) && (RBIMPL_RUBY_DEBUG == 1)
# /* The (*2) situation in above diagram. */
# define RUBY_DEBUG 1
# define RUBY_NDEBUG 0
# /* keep NDEBUG undefined */

# if defined(_MSC_VER)
#  pragma message("NDEBUG is ignored because RUBY_DEBUG>0.")
# elif defined(__GNUC__)
#  pragma GCC warning "NDEBUG is ignored because RUBY_DEBUG>0."
# else
#  error NDEBUG is ignored because RUBY_DEBUG>0.
# endif
#endif
#undef RBIMPL_NDEBUG
#undef RBIMPL_RUBY_DEBUG

#endif /* RBIMPL_NDEBUG_H */
