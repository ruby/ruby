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

/* Inline and target attributes */
#if defined(__GNUC__) || defined(__clang__)
# define STRING_SIMD_INLINE static inline __attribute__((always_inline))
# define STRING_SIMD_PURE __attribute__((pure))
#else
# define STRING_SIMD_INLINE static inline
# define STRING_SIMD_PURE
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
 * Returns: 0 if equal, non-zero if different
 */
STRING_SIMD_INLINE int
string_simd_memcmp_neon(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
{
    const unsigned char *end = ptr1 + len;
    const unsigned char *aligned_end = ptr1 + (len & ~15UL); /* Align to 16-byte boundary */

    /* Process 16 bytes at a time */
    while (ptr1 < aligned_end) {
        uint8x16_t v1 = vld1q_u8(ptr1);
        uint8x16_t v2 = vld1q_u8(ptr2);
        uint8x16_t cmp = vceqq_u8(v1, v2);

        /* If not all bytes are equal, we need to find the first difference */
        if (vminvq_u8(cmp) == 0) {
            /* Find first differing byte */
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
 * Optimized for early exit on first difference
 */
STRING_SIMD_INLINE int
string_simd_memeq_neon(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
{
    const unsigned char *aligned_end = ptr1 + (len & ~15UL);

    /* Process 16 bytes at a time */
    while (ptr1 < aligned_end) {
        uint8x16_t v1 = vld1q_u8(ptr1);
        uint8x16_t v2 = vld1q_u8(ptr2);
        uint8x16_t cmp = vceqq_u8(v1, v2);

        /* Early exit if any byte differs */
        if (vminvq_u8(cmp) == 0) {
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
 */
STRING_TARGET_SSE2 STRING_SIMD_INLINE int
string_simd_memcmp_sse2(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
{
    const unsigned char *end = ptr1 + len;
    const unsigned char *aligned_end = ptr1 + (len & ~15UL);

    /* Process 16 bytes at a time */
    while (ptr1 < aligned_end) {
        __m128i v1 = _mm_loadu_si128((__m128i const*)ptr1);
        __m128i v2 = _mm_loadu_si128((__m128i const*)ptr2);
        __m128i cmp = _mm_cmpeq_epi8(v1, v2);
        int mask = _mm_movemask_epi8(cmp);

        /* If not all bytes equal (mask != 0xFFFF) */
        if (mask != 0xFFFF) {
            /* Find first differing byte */
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
 * SSE2-accelerated equality check
 * Optimized for early exit - faster than memcmp for equality testing
 */
STRING_TARGET_SSE2 STRING_SIMD_INLINE int
string_simd_memeq_sse2(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
{
    const unsigned char *aligned_end = ptr1 + (len & ~15UL);

    /* Process 16 bytes at a time */
    while (ptr1 < aligned_end) {
        __m128i v1 = _mm_loadu_si128((__m128i const*)ptr1);
        __m128i v2 = _mm_loadu_si128((__m128i const*)ptr2);
        __m128i cmp = _mm_cmpeq_epi8(v1, v2);
        int mask = _mm_movemask_epi8(cmp);

        /* Early exit if any byte differs */
        if (mask != 0xFFFF) {
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
 * Drop-in replacement for memcmp, but optimized with SIMD
 *
 * @param ptr1 First string pointer (as unsigned char for proper comparison)
 * @param ptr2 Second string pointer
 * @param len Length to compare
 * @return 0 if equal, <0 if ptr1 < ptr2, >0 if ptr1 > ptr2
 */
STRING_SIMD_INLINE STRING_SIMD_PURE int
rb_str_simd_memcmp(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
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
 *
 * @param ptr1 First string pointer
 * @param ptr2 Second string pointer
 * @param len Length to compare
 * @return 1 if equal, 0 if different
 */
STRING_SIMD_INLINE STRING_SIMD_PURE int
rb_str_simd_memeq(const unsigned char *ptr1, const unsigned char *ptr2, size_t len)
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
