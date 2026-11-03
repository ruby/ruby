/**
 * @file compiler/noreturn.h
 */
#ifndef PRISM_COMPILER_NORETURN_H
#define PRISM_COMPILER_NORETURN_H

/**
 * Mark a function as never returning to its caller, so that the compiler can
 * treat the code after a call to it as unreachable. Every form of this goes
 * before the declaration.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
#   define PRISM_NORETURN [[noreturn]]
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#   define PRISM_NORETURN _Noreturn
#elif defined(__GNUC__) || defined(__clang__)
#   define PRISM_NORETURN __attribute__((__noreturn__))
#elif defined(_MSC_VER)
#   define PRISM_NORETURN __declspec(noreturn)
#else
#   define PRISM_NORETURN
#endif

#endif
