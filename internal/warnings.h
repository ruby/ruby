#ifndef INTERNAL_WARNINGS_H /* -*- C -*- */
#define INTERNAL_WARNINGS_H
/**
 * @file
 * @brief      Internal header to suppress / mandate warnings.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "internal/compilers.h" /* for MSC_VERSION_SINCE */

#if MSC_VERSION_SINCE(1200)
# /* Not sure exactly when but it seems VC++ 6.0 is a version with it.*/
# define COMPILER_WARNING_PUSH          __pragma(warning(push))
# define COMPILER_WARNING_POP           __pragma(warning(pop))
# define COMPILER_WARNING_ERROR(flag)   __pragma(warning(error: flag))
# define COMPILER_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif defined(__clang__)
# /* Not sure exactly when but it seems LLVM 2.6.0 is a version with it. */
# define COMPILER_WARNING_PRAGMA0(x)    _Pragma(# x)
# define COMPILER_WARNING_PRAGMA1(x)    COMPILER_WARNING_PRAGMA0(clang diagnostic x)
# define COMPILER_WARNING_PRAGMA2(x, y) COMPILER_WARNING_PRAGMA1(x # y)
# define COMPILER_WARNING_PUSH          COMPILER_WARNING_PRAGMA1(push)
# define COMPILER_WARNING_POP           COMPILER_WARNING_PRAGMA1(pop)
# define COMPILER_WARNING_ERROR(flag)   COMPILER_WARNING_PRAGMA2(error, flag)
# define COMPILER_WARNING_IGNORED(flag) COMPILER_WARNING_PRAGMA2(ignored, flag)

#elif GCC_VERSION_SINCE(4, 6, 0)
# /* https://gcc.gnu.org/onlinedocs/gcc-4.6.0/gcc/Diagnostic-Pragmas.html */
# define COMPILER_WARNING_PRAGMA0(x)    _Pragma(# x)
# define COMPILER_WARNING_PRAGMA1(x)    COMPILER_WARNING_PRAGMA0(GCC diagnostic x)
# define COMPILER_WARNING_PRAGMA2(x, y) COMPILER_WARNING_PRAGMA1(x # y)
# define COMPILER_WARNING_PUSH          COMPILER_WARNING_PRAGMA1(push)
# define COMPILER_WARNING_POP           COMPILER_WARNING_PRAGMA1(pop)
# define COMPILER_WARNING_ERROR(flag)   COMPILER_WARNING_PRAGMA2(error, flag)
# define COMPILER_WARNING_IGNORED(flag) COMPILER_WARNING_PRAGMA2(ignored, flag)

#else
# /* :FIXME: improve here, for instace icc seems to have something? */
# define COMPILER_WARNING_PUSH          /* void */
# define COMPILER_WARNING_POP           /* void */
# define COMPILER_WARNING_ERROR(flag)   /* void */
# define COMPILER_WARNING_IGNORED(flag) /* void */

#endif /* _MSC_VER */
#endif /* INTERNAL_WARNINGS_H */
