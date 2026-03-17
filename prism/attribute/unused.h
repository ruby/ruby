/**
 * @file attribute/unused.h
 *
 * Macro definitions for marking functions and parameters as unused to suppress
 * compiler warnings.
 */
#ifndef PRISM_ATTRIBUTE_UNUSED_H
#define PRISM_ATTRIBUTE_UNUSED_H

/**
 * GCC will warn if you specify a function or parameter that is unused at
 * runtime. This macro allows you to mark a function or parameter as unused in a
 * compiler-agnostic way.
 */
#if defined(__GNUC__)
#   define PRISM_ATTRIBUTE_UNUSED __attribute__((unused))
#else
#   define PRISM_ATTRIBUTE_UNUSED
#endif

#endif
