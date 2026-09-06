#ifndef INTERNAL_SIMD_H
#define INTERNAL_SIMD_H

#if defined(__amd64__) || defined(__amd64) || defined(__x86_64__) || defined(__x86_64) || defined(_M_X64) || defined(_M_AMD64)
#ifdef HAVE_X86INTRIN_H
#include <x86intrin.h>
#define HAVE_SIMD 1
#define HAVE_SIMD_SSE2 1
#endif
#endif

#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(_M_ARM64)
#define HAVE_SIMD 1
#define HAVE_SIMD_NEON 1
#include <arm_neon.h>
#endif

#endif /* INTERNAL_SIMD_H */
