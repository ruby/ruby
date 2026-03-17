/**
 * @file attribute/force_inline.h
 *
 * Macro definitions for forcing a function to be inlined at every call site.
 */
#ifndef PRISM_FORCE_INLINE_H
#define PRISM_FORCE_INLINE_H

/**
 * Force a function to be inlined at every call site. Use sparingly — only for
 * small, hot functions where the compiler's heuristics fail to inline.
 */
#if defined(_MSC_VER)
#   define PRISM_FORCE_INLINE __forceinline
#elif defined(__GNUC__) || defined(__clang__)
#   define PRISM_FORCE_INLINE inline __attribute__((always_inline))
#else
#   define PRISM_FORCE_INLINE inline
#endif

#endif
