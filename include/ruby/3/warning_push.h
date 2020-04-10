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
 * @brief      Defines RUBY3_WARNING_PUSH.
 * @cond       INTERNAL_MACRO
 *
 * ### Q&A ###
 *
 * Q: Why all the macros defined in this file are function-like macros?
 *
 * A: Sigh.   This  is  because of  Doxgen.   Its  `SKIP_FUNCTION_MACROS = YES`
 *    configuration setting  requests us  that if  we want  it to  ignore these
 *    macros,  then we  have to  do  two things:  (1)  let them  be defined  as
 *    function-like macros,  and (2) place  them separately in their  own line,
 *    like below:
 *
 *    ```CXX
 *    // NG -- foo's type  considered something like `unsigned int`.
 *    RUBY3_WARNING_PUSH
 *    int foo(void);
 *    RUBY3_WARNING_POP
 *
 *    // OK -- the macros are ignored by Doxygen.
 *    RUBY3_WARNING_PUSH()
 *    int foo(void);
 *    RUBY3_WARNING_POP()
 *    ```
 */
#include "ruby/3/compiler_is.h"

#ifdef RUBY3_WARNING_PUSH
# /* Take that. */

#elif RUBY3_COMPILER_SINCE(MSVC, 12, 0, 0)
# /* Not sure exactly when but it seems VC++ 6.0 is a version with it.*/
# define RUBY3_WARNING_PUSH()        __pragma(warning(push))
# define RUBY3_WARNING_POP()         __pragma(warning(pop))
# define RUBY3_WARNING_ERROR(flag)   __pragma(warning(error: flag))
# define RUBY3_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif RUBY3_COMPILER_SINCE(Intel, 13, 0, 0)
# define RUBY3_WARNING_PUSH()        __pragma(warning(push))
# define RUBY3_WARNING_POP()         __pragma(warning(pop))
# define RUBY3_WARNING_ERROR(flag)   __pragma(warning(error: flag))
# define RUBY3_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif RUBY3_COMPILER_IS(Clang) || RUBY3_COMPILER_IS(Apple)
# /* Not sure exactly when but it seems LLVM 2.6.0 is a version with it. */
# define RUBY3_WARNING_PRAGMA0(x)    _Pragma(# x)
# define RUBY3_WARNING_PRAGMA1(x)    RUBY3_WARNING_PRAGMA0(clang diagnostic x)
# define RUBY3_WARNING_PRAGMA2(x, y) RUBY3_WARNING_PRAGMA1(x # y)
# define RUBY3_WARNING_PUSH()        RUBY3_WARNING_PRAGMA1(push)
# define RUBY3_WARNING_POP()         RUBY3_WARNING_PRAGMA1(pop)
# define RUBY3_WARNING_ERROR(flag)   RUBY3_WARNING_PRAGMA2(error, flag)
# define RUBY3_WARNING_IGNORED(flag) RUBY3_WARNING_PRAGMA2(ignored, flag)

#elif RUBY3_COMPILER_SINCE(GCC, 4, 6, 0)
# /* https://gcc.gnu.org/onlinedocs/gcc-4.6.0/gcc/Diagnostic-Pragmas.html */
# define RUBY3_WARNING_PRAGMA0(x)    _Pragma(# x)
# define RUBY3_WARNING_PRAGMA1(x)    RUBY3_WARNING_PRAGMA0(GCC diagnostic x)
# define RUBY3_WARNING_PRAGMA2(x, y) RUBY3_WARNING_PRAGMA1(x # y)
# define RUBY3_WARNING_PUSH()        RUBY3_WARNING_PRAGMA1(push)
# define RUBY3_WARNING_POP()         RUBY3_WARNING_PRAGMA1(pop)
# define RUBY3_WARNING_ERROR(flag)   RUBY3_WARNING_PRAGMA2(error, flag)
# define RUBY3_WARNING_IGNORED(flag) RUBY3_WARNING_PRAGMA2(ignored, flag)

#else
# /* :FIXME: improve here */
# define RUBY3_WARNING_PUSH()        /* void */
# define RUBY3_WARNING_POP()         /* void */
# define RUBY3_WARNING_ERROR(flag)   /* void */
# define RUBY3_WARNING_IGNORED(flag) /* void */
#endif /* _MSC_VER */
/** @endcond */
