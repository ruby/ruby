    /**********************************************************************

  internal/string_simd.h - SIMD-accelerated string operations

  Copyright (C) 2025

**********************************************************************/

#ifndef INTERNAL_STRING_SIMD_H
#define INTERNAL_STRING_SIMD_H

#include "ruby/internal/config.h"
#include "ruby/internal/stdbool.h"
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* SIMD Implementation Detection */
typedef enum {
    STRING_SIMD_NONE,
    STRING_SIMD_NEON,
    STRING_SIMD_SSE2,
    STRING_SIMD_AVX2
} string_simd_implementation;

/* Compiler detection for builtins */
#ifndef __has_builtin
  #define __has_builtin(x) 0
#endif

/* Inline and target attributes for maximum performance */
#if defined(__GNUC__) || defined(__clang__)
# define STRING_SIMD_INLINE static inline __attribute__((always_inline))
# define STRING_SIMD_PURE __attribute__((pure))
# define STRING_SIMD_HOT __attribute__((hot))
# define STRING_SIMD_RESTRICT __restrict__
#else
# define STRING_SIMD_INLINE static inline
# define STRING_SIMD_PURE
# define STRING_SIMD_HOT
# define STRING_SIMD_RESTRICT
#endif

/* Use Ruby's existing LIKELY/UNLIKELY macros if available, otherwise define them */
#ifndef LIKELY
# if defined(__GNUC__) || defined(__clang__)
#  define LIKELY(x) __builtin_expect(!!(x), 1)
#  define UNLIKELY(x) __builtin_expect(!!(x), 0)
# else
#  define LIKELY(x) (x)
#  define UNLIKELY(x) (x)
# endif
#endif

/* SIMD configuration thresholds */
#define STRING_SIMD_MIN_THRESHOLD 16    /* Minimum bytes to activate SIMD */
#define STRING_SIMD_MAX_THRESHOLD 256   /* Maximum bytes - fallback to memcmp for larger */

/* ========================================================================
 * ARM NEON Implementation
 * ======================================================================== */

#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(_M_ARM64)

#include <arm_neon.h>

#define STRING_HAVE_SIMD_NEON 1
#define STRING_HAVE_SIMD 1

STRING_SIMD_INLINE string_simd_implementation
string_simd_get_implementation(void)
{
    return STRING_SIMD_NEON;
}

/**
 * NEON-accelerated memory comparison
 * Compares 16 bytes at a time using NEON SIMD instructions
 * Optimized with restrict pointers and branch hints for maximum performance
 * Returns: 0 if equal, non-zero if different
 */
STRING_SIMD_INLINE STRING_SIMD_HOT int
string_simd_memcmp_neon(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                        const unsigned char *STRING_SIMD_RESTRICT ptr2,
                        size_t len)
{
    const unsigned char *end = ptr1 + len;
    const unsigned char *aligned_end = ptr1 + (len & ~15UL); /* Align to 16-byte boundary */

    /* Process 16 bytes at a time with branch hints */
    while (LIKELY(ptr1 < aligned_end)) {
        uint8x16_t v1 = vld1q_u8(ptr1);
        uint8x16_t v2 = vld1q_u8(ptr2);
        uint8x16_t cmp = vceqq_u8(v1, v2);

        /* If not all bytes are equal, we need to find the first difference */
        if (UNLIKELY(vminvq_u8(cmp) == 0)) {
            /* Find first differing byte using optimized search */
            for (size_t i = 0; i < 16; i++) {
                if (ptr1[i] != ptr2[i]) {
                    return (int)ptr1[i] - (int)ptr2[i];
                }
            }
        }

        ptr1 += 16;
        ptr2 += 16;
    }

    /* Handle remaining bytes */
    while (ptr1 < end) {
        if (*ptr1 != *ptr2) {
            return (int)*ptr1 - (int)*ptr2;
        }
        ptr1++;
        ptr2++;
    }

    return 0;
}

/**
 * NEON-accelerated equality check
 * Returns: 1 if equal, 0 if different
 * Optimized for early exit with restrict pointers and branch hints
 */
STRING_SIMD_INLINE STRING_SIMD_HOT int
string_simd_memeq_neon(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                       const unsigned char *STRING_SIMD_RESTRICT ptr2,
                       size_t len)
{
    const unsigned char *aligned_end = ptr1 + (len & ~15UL);

    /* Process 16 bytes at a time with branch hints for common case (equality) */
    while (LIKELY(ptr1 < aligned_end)) {
        uint8x16_t v1 = vld1q_u8(ptr1);
        uint8x16_t v2 = vld1q_u8(ptr2);
        uint8x16_t cmp = vceqq_u8(v1, v2);

        /* Early exit if any byte differs (unlikely in equality check) */
        if (UNLIKELY(vminvq_u8(cmp) == 0)) {
            return 0;
        }

        ptr1 += 16;
        ptr2 += 16;
    }

    /* Handle remaining bytes */
    const unsigned char *end = ptr1 + (len & 15);
    while (ptr1 < end) {
        if (*ptr1++ != *ptr2++) {
            return 0;
        }
    }

    return 1;
}

#endif /* ARM NEON */

/* ========================================================================
 * x86_64 SSE2/AVX2 Implementation
 * ======================================================================== */

#if defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64) || defined(_M_X64) || defined(_M_AMD64)

#ifdef HAVE_X86INTRIN_H
#include <x86intrin.h>

#define STRING_HAVE_SIMD_SSE2 1
#define STRING_HAVE_SIMD 1

/* CPU feature detection */
#if defined(__clang__) || defined(__GNUC__)
# define STRING_TARGET_SSE2 __attribute__((target("sse2")))
# define STRING_TARGET_AVX2 __attribute__((target("avx2")))
#else
# define STRING_TARGET_SSE2
# define STRING_TARGET_AVX2
#endif

/**
 * SSE2-accelerated memory comparison
 * Compares 16 bytes at a time using SSE2 SIMD instructions
 * Optimized with restrict pointers, loop unrolling, and branch hints
 */
STRING_TARGET_SSE2 STRING_SIMD_INLINE STRING_SIMD_HOT int
string_simd_memcmp_sse2(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                        const unsigned char *STRING_SIMD_RESTRICT ptr2,
                        size_t len)
{
    const unsigned char *end = ptr1 + len;
    const unsigned char *aligned_end = ptr1 + (len & ~15UL);

    /* Process 16 bytes at a time */
    while (LIKELY(ptr1 < aligned_end)) {
        __m128i v1 = _mm_loadu_si128((__m128i const*)ptr1);
        __m128i v2 = _mm_loadu_si128((__m128i const*)ptr2);
        __m128i cmp = _mm_cmpeq_epi8(v1, v2);
        unsigned int mask = (unsigned int)_mm_movemask_epi8(cmp);

        /* If not all bytes equal (mask != 0xFFFF) - early exit */
        if (UNLIKELY(mask != 0xFFFFu)) {
            /* Find first differing byte using ctz for speed */
            unsigned int diff_mask = ~mask & 0xFFFFu;
            #if defined(__GNUC__) || defined(__clang__)
            unsigned int first_diff = (unsigned int)__builtin_ctz(diff_mask);
            #else
            unsigned int first_diff = 0;
            while ((diff_mask & (1u << first_diff)) == 0) first_diff++;
            #endif
            return (int)ptr1[first_diff] - (int)ptr2[first_diff];
        }

        ptr1 += 16;
        ptr2 += 16;
    }

    /* Handle remaining bytes (< 16) */
    while (UNLIKELY(ptr1 < end)) {
        if (*ptr1 != *ptr2) {
            return (int)*ptr1 - (int)*ptr2;
        }
        ptr1++;
        ptr2++;
    }

    return 0;
}

/**
 * SSE2-accelerated equality check
 * Optimized for early exit with restrict pointers and branch prediction hints
 */
STRING_TARGET_SSE2 STRING_SIMD_INLINE STRING_SIMD_HOT int
string_simd_memeq_sse2(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                       const unsigned char *STRING_SIMD_RESTRICT ptr2,
                       size_t len)
{
    const unsigned char *aligned_end = ptr1 + (len & ~31UL); /* Process 32 bytes when possible */

    /* Unrolled loop - process 32 bytes (2x SSE2) per iteration for better throughput */
    while (LIKELY(ptr1 < aligned_end)) {
        __m128i v1a = _mm_loadu_si128((__m128i const*)ptr1);
        __m128i v2a = _mm_loadu_si128((__m128i const*)ptr2);
        __m128i v1b = _mm_loadu_si128((__m128i const*)(ptr1 + 16));
        __m128i v2b = _mm_loadu_si128((__m128i const*)(ptr2 + 16));

        __m128i cmpa = _mm_cmpeq_epi8(v1a, v2a);
        __m128i cmpb = _mm_cmpeq_epi8(v1b, v2b);
        __m128i combined = _mm_and_si128(cmpa, cmpb);

        /* Early exit if any byte differs */
        if (UNLIKELY(_mm_movemask_epi8(combined) != 0xFFFF)) {
            /* Check first 16 bytes */
            if (_mm_movemask_epi8(cmpa) != 0xFFFF) {
                return 0;
            }
            /* Check second 16 bytes */
            return 0;
        }

        ptr1 += 32;
        ptr2 += 32;
    }

    /* Process remaining 16-byte chunk if any */
    aligned_end = ptr1 + ((len & 31) & ~15UL);
    if (LIKELY(ptr1 < aligned_end)) {
        __m128i v1 = _mm_loadu_si128((__m128i const*)ptr1);
        __m128i v2 = _mm_loadu_si128((__m128i const*)ptr2);
        __m128i cmp = _mm_cmpeq_epi8(v1, v2);

        if (UNLIKELY(_mm_movemask_epi8(cmp) != 0xFFFF)) {
            return 0;
        }
        ptr1 += 16;
        ptr2 += 16;
    }

    /* Handle remaining bytes (< 16) */
    const unsigned char *end = ptr1 + (len & 15);
    while (UNLIKELY(ptr1 < end)) {
        if (*ptr1++ != *ptr2++) {
            return 0;
        }
    }

    return 1;
}

#ifdef HAVE_CPUID_H
#include <cpuid.h>

STRING_SIMD_INLINE string_simd_implementation
string_simd_get_implementation(void)
{
    /* Check for AVX2 support (future optimization) */
    /* if (__builtin_cpu_supports("avx2")) {
        return STRING_SIMD_AVX2;
    } */

    /* Check for SSE2 support (should be universal on x86_64) */
    if (__builtin_cpu_supports("sse2")) {
        return STRING_SIMD_SSE2;
    }

    return STRING_SIMD_NONE;
}
#else
STRING_SIMD_INLINE string_simd_implementation
string_simd_get_implementation(void)
{
    /* Assume SSE2 on x86_64 if cpuid.h not available */
    return STRING_SIMD_SSE2;
}
#endif /* HAVE_CPUID_H */

#endif /* HAVE_X86INTRIN_H */
#endif /* x86_64 */

/* ========================================================================
 * Fallback Implementation (no SIMD)
 * ======================================================================== */

#ifndef STRING_HAVE_SIMD
#define STRING_HAVE_SIMD 0

STRING_SIMD_INLINE string_simd_implementation
string_simd_get_implementation(void)
{
    return STRING_SIMD_NONE;
}
#endif

/* ========================================================================
 * Public API - Dispatches to appropriate SIMD implementation
 * ======================================================================== */

/**
 * SIMD-accelerated string comparison
 * Drop-in replacement for memcmp, optimized with SIMD, restrict pointers,
 * and intelligent branch prediction for maximum CPU performance
 *
 * @param ptr1 First string pointer (as unsigned char for proper comparison)
 * @param ptr2 Second string pointer
 * @param len Length to compare
 * @return 0 if equal, <0 if ptr1 < ptr2, >0 if ptr1 > ptr2
 */
STRING_SIMD_INLINE STRING_SIMD_PURE STRING_SIMD_HOT int
rb_str_simd_memcmp(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                   const unsigned char *STRING_SIMD_RESTRICT ptr2,
                   size_t len)
{
    /* Quick checks for identical pointers or zero length */
    if (ptr1 == ptr2 || len == 0) {
        return 0;
    }

    /* Use SIMD only for strings in the sweet spot (16-512 bytes) */
    /* Outside this range, standard memcmp is faster */
    if (len < STRING_SIMD_MIN_THRESHOLD || len > STRING_SIMD_MAX_THRESHOLD) {
        return memcmp(ptr1, ptr2, len);
    }

#ifdef STRING_HAVE_SIMD_SSE2
    return string_simd_memcmp_sse2(ptr1, ptr2, len);
#elif defined(STRING_HAVE_SIMD_NEON)
    return string_simd_memcmp_neon(ptr1, ptr2, len);
#else
    return memcmp(ptr1, ptr2, len);
#endif
}

/**
 * SIMD-accelerated string equality check
 * Faster than memcmp when you only need to know if strings are equal
 * Heavily optimized with restrict, inline, hot attribute, and branch hints
 *
 * @param ptr1 First string pointer
 * @param ptr2 Second string pointer
 * @param len Length to compare
 * @return 1 if equal, 0 if different
 */
STRING_SIMD_INLINE STRING_SIMD_PURE STRING_SIMD_HOT int
rb_str_simd_memeq(const unsigned char *STRING_SIMD_RESTRICT ptr1,
                  const unsigned char *STRING_SIMD_RESTRICT ptr2,
                  size_t len)
{
    /* Quick checks */
    if (ptr1 == ptr2 || len == 0) {
        return 1;
    }

    /* Use SIMD only for strings in the sweet spot (16-512 bytes) */
    /* For very small or very large strings, memcmp is faster */
    if (len < STRING_SIMD_MIN_THRESHOLD || len > STRING_SIMD_MAX_THRESHOLD) {
        return memcmp(ptr1, ptr2, len) == 0;
    }

#ifdef STRING_HAVE_SIMD_SSE2
    return string_simd_memeq_sse2(ptr1, ptr2, len);
#elif defined(STRING_HAVE_SIMD_NEON)
    return string_simd_memeq_neon(ptr1, ptr2, len);
#else
    return memcmp(ptr1, ptr2, len) == 0;
#endif
}

#endif /* INTERNAL_STRING_SIMD_H */
