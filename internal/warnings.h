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

#if defined(_MSC_VER)
# define COMPILER_WARNING_PUSH          __pragma(warning(push))
# define COMPILER_WARNING_POP           __pragma(warning(pop))
# define COMPILER_WARNING_ERROR(flag)   __pragma(warning(error: flag)))
# define COMPILER_WARNING_IGNORED(flag) __pragma(warning(suppress: flag)))

#elif defined(__clang__) /* clang 2.6 already had this feature */
# define COMPILER_WARNING_PUSH          _Pragma("clang diagnostic push")
# define COMPILER_WARNING_POP           _Pragma("clang diagnostic pop")
# define COMPILER_WARNING_SPECIFIER(kind, msg) \
    clang diagnostic kind # msg
# define COMPILER_WARNING_ERROR(flag) \
    COMPILER_WARNING_PRAGMA(COMPILER_WARNING_SPECIFIER(error, flag))
# define COMPILER_WARNING_IGNORED(flag) \
    COMPILER_WARNING_PRAGMA(COMPILER_WARNING_SPECIFIER(ignored, flag))

#elif GCC_VERSION_SINCE(4, 6, 0)
/* https://gcc.gnu.org/onlinedocs/gcc-4.6.4/gcc/Diagnostic-Pragmas.html */
# define COMPILER_WARNING_PUSH          _Pragma("GCC diagnostic push")
# define COMPILER_WARNING_POP           _Pragma("GCC diagnostic pop")
# define COMPILER_WARNING_SPECIFIER(kind, msg) \
    GCC diagnostic kind # msg
# define COMPILER_WARNING_ERROR(flag) \
    COMPILER_WARNING_PRAGMA(COMPILER_WARNING_SPECIFIER(error, flag))
# define COMPILER_WARNING_IGNORED(flag) \
    COMPILER_WARNING_PRAGMA(COMPILER_WARNING_SPECIFIER(ignored, flag))

#else /* other compilers to follow? */
# define COMPILER_WARNING_PUSH          /* nop */
# define COMPILER_WARNING_POP           /* nop */
# define COMPILER_WARNING_ERROR(flag)   /* nop */
# define COMPILER_WARNING_IGNORED(flag) /* nop */
#endif

#define COMPILER_WARNING_PRAGMA(str) COMPILER_WARNING_PRAGMA_(str)
#define COMPILER_WARNING_PRAGMA_(str) _Pragma(#str)

#endif /* INTERNAL_WARNINGS_H */
