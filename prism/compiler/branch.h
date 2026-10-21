/**
 * @file compiler/branch.h
 */
#ifndef PRISM_COMPILER_BRANCH_H
#define PRISM_COMPILER_BRANCH_H

/**
 * Branch prediction hints. These tell the compiler which side of a branch to
 * predicate the fast path through, so it can lay out instructions to favour
 * that side and steer the static branch predictor.
 */
#if defined(__GNUC__) || defined(__clang__)
    /** The compiler should predicate that this branch will be taken. */
    #define PRISM_LIKELY(x) __builtin_expect(!!(x), 1)

    /** The compiler should predicate that this branch will not be taken. */
    #define PRISM_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
    /** Void because this platform does not support branch prediction hints. */
    #define PRISM_LIKELY(x)   (x)

    /** Void because this platform does not support branch prediction hints. */
    #define PRISM_UNLIKELY(x) (x)
#endif

#endif
