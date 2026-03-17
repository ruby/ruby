/**
 * @file flex_array.h
 *
 * Macro definitions for working with flexible array members.
 */
#ifndef PRISM_FLEX_ARRAY_H
#define PRISM_FLEX_ARRAY_H

/**
 * A macro for defining a flexible array member. C99 supports `data[]`, GCC
 * supports `data[0]` as an extension, and older compilers require `data[1]`.
 */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
    #define PM_FLEX_ARRAY_LENGTH   /* data[] */
#elif defined(__GNUC__) && !defined(__STRICT_ANSI__)
    #define PM_FLEX_ARRAY_LENGTH 0 /* data[0] */
#else
    #define PM_FLEX_ARRAY_LENGTH 1 /* data[1] */
#endif

#endif
