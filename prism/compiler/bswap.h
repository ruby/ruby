/**
 * @file compiler/bswap.h
 */
#ifndef PRISM_COMPILER_BSWAP_H
#define PRISM_COMPILER_BSWAP_H

/**
 * Byte swap utilities for 32-bit and 64-bit integers.
 */
#if defined(__GNUC__) || defined(__clang__)
#define pm_bswap32(x_) __builtin_bswap32((x_))
#define pm_bswap64(x_) __builtin_bswap64((x_))
#elif defined(_MSC_VER)
#include <stdlib.h>

#define pm_bswap32(x_) _byteswap_ulong((x_))
#define pm_bswap64(x_) _byteswap_uint64((x_))
#else
#include <stdint.h>

static uint32_t
pm_bswap32(uint32_t x) {
    return (
      ((x >> 24) & 0x000000FFUL) |
      ((x << 24) & 0xFF000000UL) |
      ((x >> 8)  & 0x0000FF00UL) |
      ((x << 8)  & 0x00FF0000UL)
    );
}

static uint64_t
pm_bswap64(uint64_t x) {
    return (
      ((x >> 56) & 0x00000000000000FFULL) |
      ((x << 56) & 0xFF00000000000000ULL) |
      ((x >> 40) & 0x000000000000FF00ULL) |
      ((x << 40) & 0x00FF000000000000ULL) |
      ((x >> 24) & 0x0000000000FF0000ULL) |
      ((x << 24) & 0x0000FF0000000000ULL) |
      ((x >> 8)  & 0x00000000FF000000ULL) |
      ((x << 8)  & 0x000000FF00000000ULL)
    );
}
#endif

#endif
