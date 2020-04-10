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
 * @brief      Defines old #LONG_LONG
 *
 * No  known  compiler   that  can  compile  today's  ruby   lacks  long  long.
 * Historically MSVC was  one of such compiler, but it  implemented long long a
 * while  ago  (some  time  back  in  2013).   The  macros  are  for  backwards
 * compatibility only.
 */
#include "ruby/3/config.h"

#if defined(LONG_LONG)
# /* Take that. */

#elif RUBY3_HAS_WARNING("-Wc++11-long-long")
# define HAVE_TRUE_LONG_LONG 1
# define LONG_LONG                           \
    RUBY3_WARNING_PUSH()                     \
    RUBY3_WARNING_IGNORED(-Wc++11-long-long) \
    long long                                \
    RUBY3_WARNING_POP()

#elif RUBY3_HAS_WARNING("-Wlong-long")
# define HAVE_TRUE_LONG_LONG 1
# define LONG_LONG                     \
    RUBY3_WARNING_PUSH()               \
    RUBY3_WARNING_IGNORED(-Wlong-long) \
    long long                          \
    RUBY3_WARNING_POP()

#elif defined(HAVE_LONG_LONG)
# define HAVE_TRUE_LONG_LONG 1
# define LONG_LONG long long

#elif SIZEOF___INT64 > 0
# define HAVE_LONG_LONG 1
# define LONG_LONG __int64
# undef SIZEOF_LONG_LONG
# define SIZEOF_LONG_LONG SIZEOF___INT64

#else
# error Hello!  Ruby developers believe this message must not happen.
# error If you encounter this message, can you file a bug report?
# error Remember to attach a detailed description of your environment.
# error Thank you!
#endif
