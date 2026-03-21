/**
 * @file compiler/format.h
 */
#ifndef PRISM_COMPILER_FORMAT_H
#define PRISM_COMPILER_FORMAT_H

/**
 * Certain compilers support specifying that a function accepts variadic
 * parameters that look like printf format strings to provide a better developer
 * experience when someone is using the function. This macro does that in a
 * compiler-agnostic way.
 */
#if defined(__GNUC__)
#   if defined(__MINGW_PRINTF_FORMAT)
#       define PRISM_ATTRIBUTE_FORMAT(fmt_idx_, arg_idx_) __attribute__((format(__MINGW_PRINTF_FORMAT, fmt_idx_, arg_idx_)))
#   else
#       define PRISM_ATTRIBUTE_FORMAT(fmt_idx_, arg_idx_) __attribute__((format(printf, fmt_idx_, arg_idx_)))
#   endif
#elif defined(__clang__)
#   define PRISM_ATTRIBUTE_FORMAT(fmt_idx_, arg_idx_) __attribute__((__format__(__printf__, fmt_idx_, arg_idx_)))
#else
#   define PRISM_ATTRIBUTE_FORMAT(fmt_idx_, arg_idx_)
#endif

#endif
