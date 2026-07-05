/**
 * @file compiler/assume.h
 */
#ifndef PRISM_COMPILER_ASSUME_H
#define PRISM_COMPILER_ASSUME_H

/**
 * Tell the compiler that the given expression can be assumed to be true. Unlike
 * assert, this emits no runtime check — it only feeds the optimizer's value
 * range analysis so it can prune impossible paths. Use it to communicate an
 * invariant the caller guarantees but that the compiler cannot otherwise prove.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L /* C23 or later */
    #define PRISM_ASSUME(expr_) [[assume(expr_)]]
#elif defined(__clang__)
    #define PRISM_ASSUME(expr_) __builtin_assume(expr_)
#elif defined(_MSC_VER)
    #define PRISM_ASSUME(expr_) __assume(expr_)
#elif defined(__GNUC__)
    #define PRISM_ASSUME(expr_) ((expr_) ? (void) 0 : __builtin_unreachable())
#else
    #define PRISM_ASSUME(expr_) ((void) 0)
#endif

#endif
