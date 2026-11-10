#ifndef PRISM_INTERNAL_XXH3_H
#define PRISM_INTERNAL_XXH3_H

#include <stddef.h>
#include <stdint.h>

/**
 * Computes the XXH3 digest of the given input.
 *
 * @param input The input data to hash.
 * @param length The length of the input data.
 * @return The 64-bit XXH3 hash of the input data.
 */
uint64_t pm_xxh3(const uint8_t *input, size_t length);

#endif
