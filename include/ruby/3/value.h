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
 * @brief      Defines ::VALUE and ::ID.
 */
#ifndef  RUBY3_VALUE_H
#define  RUBY3_VALUE_H
#include "ruby/3/static_assert.h"
#include "ruby/backward/2/long_long.h"
#include "ruby/backward/2/limits.h"

#if defined HAVE_UINTPTR_T && 0
typedef uintptr_t VALUE;
typedef uintptr_t ID;
# define SIGNED_VALUE intptr_t
# define SIZEOF_VALUE SIZEOF_UINTPTR_T
# undef PRI_VALUE_PREFIX
# define RUBY3_VALUE_NULL UINTPTR_C(0)
# define RUBY3_VALUE_ONE  UINTPTR_C(1)
# define RUBY3_VALUE_FULL UINTPTR_MAX

#elif SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long VALUE;
typedef unsigned long ID;
# define SIGNED_VALUE long
# define SIZEOF_VALUE SIZEOF_LONG
# define PRI_VALUE_PREFIX "l"
# define RUBY3_VALUE_NULL 0UL
# define RUBY3_VALUE_ONE  1UL
# define RUBY3_VALUE_FULL ULONG_MAX

#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG VALUE;
typedef unsigned LONG_LONG ID;
# define SIGNED_VALUE LONG_LONG
# define LONG_LONG_VALUE 1
# define SIZEOF_VALUE SIZEOF_LONG_LONG
# define PRI_VALUE_PREFIX PRI_LL_PREFIX
# define RUBY3_VALUE_NULL 0ULL
# define RUBY3_VALUE_ONE  1ULL
# define RUBY3_VALUE_FULL ULLONG_MAX

#else
# error ---->> ruby requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif

RUBY3_STATIC_ASSERT(sizeof_int, SIZEOF_INT == sizeof(int));
RUBY3_STATIC_ASSERT(sizeof_long, SIZEOF_LONG == sizeof(long));
RUBY3_STATIC_ASSERT(sizeof_long_long, SIZEOF_LONG_LONG == sizeof(LONG_LONG));
RUBY3_STATIC_ASSERT(sizeof_voidp, SIZEOF_VOIDP == sizeof(void *));
#endif /* RUBY3_VALUE_H */
