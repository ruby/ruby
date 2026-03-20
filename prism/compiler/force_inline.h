/**
 * @file compiler/force_inline.h
 */
#ifndef PRISM_COMPILER_FORCE_INLINE_H
#define PRISM_COMPILER_FORCE_INLINE_H

#include "prism/compiler/inline.h"

/**
 * Force a function to be inlined at every call site. Use sparingly — only for
 * small, hot functions where the compiler's heuristics fail to inline.
 */
#if defined(_MSC_VER)
#   define PRISM_FORCE_INLINE __forceinline
#elif defined(__GNUC__) || defined(__clang__)
#   define PRISM_FORCE_INLINE PRISM_INLINE __attribute__((always_inline))
#else
#   define PRISM_FORCE_INLINE PRISM_INLINE
#endif

#endif
