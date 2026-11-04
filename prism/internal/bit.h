#ifndef PRISM_INTERNAL_BIT_H
#define PRISM_INTERNAL_BIT_H

#include "prism/compiler/inline.h"

/*
 * Count trailing zero bits in a 64-bit value, and find the index of the
 * highest set bit in one (the result of the x86 bsr instruction). pm_ctzll is
 * used by SWAR identifier scanning to find the first non-matching byte in a
 * word, and pm_bsrll by integer parsing and printing to find the largest power
 * of two below a count.
 *
 * Precondition: v must be nonzero. The results are undefined when v == 0
 * (matching the behavior of __builtin_ctzll, __builtin_clzll,
 * _BitScanForward64, and _BitScanReverse64).
 */
#if defined(__GNUC__) || defined(__clang__)
#define pm_bsrll(v) (63 - (unsigned) __builtin_clzll(v))
#define pm_ctzll(v) ((unsigned) __builtin_ctzll(v))
#elif defined(_MSC_VER) && defined(_WIN64)
#include <intrin.h>
#include <stdint.h>

static PRISM_INLINE unsigned
pm_bsrll(uint64_t v) {
    unsigned long index;
    _BitScanReverse64(&index, v);
    return (unsigned) index;
}

static PRISM_INLINE unsigned
pm_ctzll(uint64_t v) {
    unsigned long index;
    _BitScanForward64(&index, v);
    return (unsigned) index;
}
#else
#include <stdint.h>

static PRISM_INLINE unsigned
pm_bsrll(uint64_t v) {
    unsigned c = 0;
    if (v & 0xFFFFFFFF00000000ULL) { c += 32; v >>= 32; }
    if (v & 0x00000000FFFF0000ULL) { c += 16; v >>= 16; }
    if (v & 0x000000000000FF00ULL) { c += 8; v >>= 8; }
    if (v & 0x00000000000000F0ULL) { c += 4; v >>= 4; }
    if (v & 0x000000000000000CULL) { c += 2; v >>= 2; }
    if (v & 0x0000000000000002ULL) { c += 1; }
    return c;
}

static PRISM_INLINE unsigned
pm_ctzll(uint64_t v) {
    unsigned c = 0;
    v &= (uint64_t) (-(int64_t) v);
    if (!(v & 0x00000000FFFFFFFFULL)) c += 32;
    if (!(v & 0x0000FFFF0000FFFFULL)) c += 16;
    if (!(v & 0x00FF00FF00FF00FFULL)) c += 8;
    if (!(v & 0x0F0F0F0F0F0F0F0FULL)) c += 4;
    if (!(v & 0x3333333333333333ULL)) c += 2;
    if (!(v & 0x5555555555555555ULL)) c += 1;
    return c;
}
#endif

#endif
