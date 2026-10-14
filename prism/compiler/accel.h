/**
 * @file compiler/accel.h
 */
#ifndef PRISM_COMPILER_ACCEL_H
#define PRISM_COMPILER_ACCEL_H

/**
 * Platform detection for SIMD/fast-path implementations. At most one of these
 * macros is defined, selecting the best available vectorization strategy.
 *
 * Selection is made at compile time with no runtime CPU detection, and
 * precompiled binaries run on machines other than the one that built them. So
 * each strategy relies only on instructions that the architecture baseline
 * guarantees: NEON is mandatory on AArch64 and SSE2 is mandatory on x86-64.
 */
#if (defined(__aarch64__) && defined(__ARM_NEON)) || (defined(_MSC_VER) && defined(_M_ARM64))
#   define PRISM_HAS_NEON
#elif (defined(__x86_64__) && defined(__SSE2__)) || (defined(_MSC_VER) && defined(_M_X64))
#   define PRISM_HAS_SSE2
#elif defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#   define PRISM_HAS_SWAR
#endif

#endif
