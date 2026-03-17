/**
 * @file attribute/inline.h
 *
 * Macro definitions for forcing a function to be inlined at every call site.
 */
#ifndef PRISM_INLINE_H
#define PRISM_INLINE_H

/**
 * Old Visual Studio versions do not support the inline keyword, so we need to
 * define it to be __inline.
 */
#if defined(_MSC_VER) && !defined(inline)
#   define PRISM_INLINE __inline
#else
#   define PRISM_INLINE inline
#endif

/**
 * Force a function to be inlined at every call site. Use sparingly — only for
 * small, hot functions where the compiler's heuristics fail to inline.
 */
#if defined(_MSC_VER)
#   define PRISM_FORCE_INLINE __forceinline
#elif defined(__GNUC__) || defined(__clang__)
#   define PRISM_FORCE_INLINE inline __attribute__((always_inline))
#else
#   define PRISM_FORCE_INLINE PRISM_INLINE
#endif

#endif
