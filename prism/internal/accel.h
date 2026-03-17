/**
 * @file internal/accel.h
 *
 * Platform detection for acceleration implementations.
 */
#ifndef PRISM_INTERNAL_ACCEL_H
#define PRISM_INTERNAL_ACCEL_H

/**
 * Platform detection for SIMD / fast-path implementations. At most one of
 * these macros is defined, selecting the best available vectorization strategy.
 */
#if (defined(__aarch64__) && defined(__ARM_NEON)) || (defined(_MSC_VER) && defined(_M_ARM64))
    #define PRISM_HAS_NEON
#elif (defined(__x86_64__) && defined(__SSSE3__)) || (defined(_MSC_VER) && defined(_M_X64))
    #define PRISM_HAS_SSSE3
#elif defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    #define PRISM_HAS_SWAR
#endif

#endif
