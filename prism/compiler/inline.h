/**
 * @file compiler/inline.h
 */
#ifndef PRISM_COMPILER_INLINE_H
#define PRISM_COMPILER_INLINE_H

/**
 * Old Visual Studio versions do not support the inline keyword, so we need to
 * define it to be __inline.
 */
#if defined(_MSC_VER) && !defined(inline)
#   define PRISM_INLINE __inline
#else
#   define PRISM_INLINE inline
#endif

#endif
