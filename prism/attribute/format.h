/**
 * @file attribute/format.h
 *
 * Macro definition for specifying that a function accepts variadic parameters
 * that look like printf format strings.
 */
#ifndef PRISM_FORMAT_H
#define PRISM_FORMAT_H

/**
 * Certain compilers support specifying that a function accepts variadic
 * parameters that look like printf format strings to provide a better developer
 * experience when someone is using the function. This macro does that in a
 * compiler-agnostic way.
 */
#if defined(__GNUC__)
#   if defined(__MINGW_PRINTF_FORMAT)
#       define PRISM_ATTRIBUTE_FORMAT(string_index_, argument_index_) __attribute__((format(__MINGW_PRINTF_FORMAT, string_index_, argument_index_)))
#   else
#       define PRISM_ATTRIBUTE_FORMAT(string_index_, argument_index_) __attribute__((format(printf, string_index_, argument_index_)))
#   endif
#elif defined(__clang__)
#   define PRISM_ATTRIBUTE_FORMAT(string_index_, argument_index_) __attribute__((__format__(__printf__, string_index_, argument_index_)))
#else
#   define PRISM_ATTRIBUTE_FORMAT(string_index_, argument_index_)
#endif

#endif
