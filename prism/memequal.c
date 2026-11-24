#include "prism/internal/memequal.h"

/* Combine the differing bits so the compiler can compare the words in parallel. */
static PRISM_INLINE bool
pm_memequal_256(const unsigned char *a, const unsigned char *b) {
    uint64_t left[4], right[4];
    memcpy(left, a, sizeof(left));
    memcpy(right, b, sizeof(right));

    uint64_t difference = 0;
    for (size_t idx = 0; idx < 4; ++idx) {
        difference |= left[idx] ^ right[idx];
    }

    return !difference;
}

/* Compare slices longer than 16 bytes out of line. */
bool
pm_memequal_long(const unsigned char *a, const unsigned char *b, size_t length) {
    size_t offset = 0;
    while (length - offset >= 32) {
        if (!pm_memequal_256(a + offset, b + offset)) return false;
        offset += 32;
    }

    const size_t last = length - 8;
    while (offset < last) {
        if (!pm_memequal_64(a + offset, b + offset)) return false;
        offset += 8;
    }

    return pm_memequal_64(a + last, b + last);
}
