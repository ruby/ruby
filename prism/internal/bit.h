/**
 * @file internal/bit.h
 *
 * Bit manipulation utilities used throughout the prism library.
 */
#ifndef PRISM_INTERNAL_BIT_H
#define PRISM_INTERNAL_BIT_H

#include "prism/compiler/inline.h"

/**
 * Count trailing zero bits in a 64-bit value. Used by SWAR identifier scanning
 * to find the first non-matching byte in a word.
 *
 * Precondition: v must be nonzero. The result is undefined when v == 0
 * (matching the behavior of __builtin_ctzll and _BitScanForward64).
 */
#if defined(__GNUC__) || defined(__clang__)
    #define pm_ctzll(v) ((unsigned) __builtin_ctzll(v))
#elif defined(_MSC_VER)
    #include <intrin.h>
    static PRISM_INLINE unsigned pm_ctzll(uint64_t v) {
        unsigned long index;
        _BitScanForward64(&index, v);
        return (unsigned) index;
    }
#else
    static PRISM_INLINE unsigned
    pm_ctzll(uint64_t v) {
        unsigned c = 0;
        v &= (uint64_t) (-(int64_t) v);
        if (v & 0x00000000FFFFFFFFULL) c += 0;  else c += 32;
        if (v & 0x0000FFFF0000FFFFULL) c += 0;  else c += 16;
        if (v & 0x00FF00FF00FF00FFULL) c += 0;  else c += 8;
        if (v & 0x0F0F0F0F0F0F0F0FULL) c += 0;  else c += 4;
        if (v & 0x3333333333333333ULL) c += 0;  else c += 2;
        if (v & 0x5555555555555555ULL) c += 0;  else c += 1;
        return c;
    }
#endif

#endif
