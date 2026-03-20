/**
 * @file compiler/nonnull.h
 */
#ifndef PRISM_COMPILER_NONNULL_H
#define PRISM_COMPILER_NONNULL_H

/**
 * Mark the parameters of a function as non-null. This allows the compiler to
 * warn if a caller passes NULL for a parameter that should never be NULL. The
 * arguments are the 1-based indices of the parameters.
 */
#if defined(__GNUC__) || defined(__clang__)
#   define PRISM_NONNULL(...) __attribute__((__nonnull__(__VA_ARGS__)))
#else
#   define PRISM_NONNULL(...)
#endif

#endif
