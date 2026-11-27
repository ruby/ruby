#ifndef PRISM_INTERNAL_MEMEQUAL_H
#define PRISM_INTERNAL_MEMEQUAL_H

#include "prism/compiler/force_inline.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/* Copy into integer locals so the input slices may have any alignment. */
static PRISM_INLINE bool
pm_memequal_16(const unsigned char *a, const unsigned char *b) {
    uint16_t left, right;
    memcpy(&left, a, sizeof(left));
    memcpy(&right, b, sizeof(right));
    return left == right;
}

static PRISM_INLINE bool
pm_memequal_32(const unsigned char *a, const unsigned char *b) {
    uint32_t left, right;
    memcpy(&left, a, sizeof(left));
    memcpy(&right, b, sizeof(right));
    return left == right;
}

static PRISM_INLINE bool
pm_memequal_64(const unsigned char *a, const unsigned char *b) {
    uint64_t left, right;
    memcpy(&left, a, sizeof(left));
    memcpy(&right, b, sizeof(right));
    return left == right;
}

/* Compare slices longer than 16 bytes out of line. */
bool pm_memequal_long(const unsigned char *a, const unsigned char *b, size_t length);

/*
 * Test two byte slices for equality using fixed-size loads. The final load
 * ends at the end of the slice and may overlap the preceding load.
 */
static PRISM_FORCE_INLINE bool
pm_memequal(const void *left, const void *right, size_t length) {
    const unsigned char *a = (const unsigned char *) left;
    const unsigned char *b = (const unsigned char *) right;

    if (length > 16) {
        return pm_memequal_long(a, b, length);
    } else if (length >= 8) {
        return pm_memequal_64(a, b) && pm_memequal_64(a + (length - 8), b + (length - 8));
    } else if (length >= 4) {
        return pm_memequal_32(a, b) && pm_memequal_32(a + (length - 4), b + (length - 4));
    } else if (length >= 2) {
        return pm_memequal_16(a, b) && pm_memequal_16(a + (length - 2), b + (length - 2));
    } else if (length == 1) {
        return *a == *b;
    } else {
        return true;
    }
}

#endif
