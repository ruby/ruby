/**
 * @file compiler/align.h
 */
#ifndef PRISM_COMPILER_ALIGN_H
#define PRISM_COMPILER_ALIGN_H

/**
 * Compiler-agnostic macros for specifying alignment of types and variables.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L /* C11 or later */
    /** Specify alignment for a type or variable. */
    #define PRISM_ALIGNAS _Alignas

    /** Get the alignment requirement of a type. */
    #define PRISM_ALIGNOF _Alignof
#elif defined(__GNUC__) || defined(__clang__)
    /** Specify alignment for a type or variable. */
    #define PRISM_ALIGNAS(size) __attribute__((aligned(size)))

    /** Get the alignment requirement of a type. */
    #define PRISM_ALIGNOF(type) __alignof__(type)
#elif defined(_MSC_VER)
    /** Specify alignment for a type or variable. */
    #define PRISM_ALIGNAS(size) __declspec(align(size))

    /** Get the alignment requirement of a type. */
    #define PRISM_ALIGNOF(type) __alignof(type)
#else
    /** Void because this platform does not support specifying alignment. */
    #define PRISM_ALIGNAS(size)

    /** Fallback to sizeof as alignment requirement of a type. */
    #define PRISM_ALIGNOF(type) sizeof(type)
#endif

#endif
