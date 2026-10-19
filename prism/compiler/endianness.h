/**
 * @file compiler/endianness.h
 */
#ifndef PRISM_COMPILER_ENDIANNESS_H
#define PRISM_COMPILER_ENDIANNESS_H

/**
 * Detect endianness at compile-time through the use of predefined macros.
 */
#if defined(_WIN32) || defined(__LITTLE_ENDIAN__) || (defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#define PRISM_LITTLE_ENDIAN_COMPTIME
#endif

/**
 * Determine endianness at runtime, either through predefined macros or through
 * a runtime check that is usually folded.
 */
#if defined(PRISM_LITTLE_ENDIAN_COMPTIME)
#define PRISM_LITTLE_ENDIAN_RUNTIME 1
#elif defined(__BIG_ENDIAN__) || (defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#define PRISM_LITTLE_ENDIAN_RUNTIME 0
#else
#include <stdint.h>

static inline int
pm_little_endian(void) {
    const union { uint32_t u; uint8_t c[4]; } one = { 1 };
    return one.c[0];
}

#define PRISM_LITTLE_ENDIAN_RUNTIME pm_little_endian()
#endif

#endif
