/**
 * @file compiler/nodiscard.h
 */
#ifndef PRISM_COMPILER_NODISCARD_H
#define PRISM_COMPILER_NODISCARD_H

/**
 * Mark the return value of a function as important so that the compiler warns
 * if a caller ignores it. This is useful for functions that return error codes
 * or allocated resources that must be freed.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
#   define PRISM_NODISCARD [[nodiscard]]
#elif defined(__GNUC__) || defined(__clang__)
#   define PRISM_NODISCARD __attribute__((__warn_unused_result__))
#elif defined(_MSC_VER)
#   define PRISM_NODISCARD _Check_return_
#else
#   define PRISM_NODISCARD
#endif

#endif
