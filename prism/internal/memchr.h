#ifndef PRISM_INTERNAL_MEMCHR_H
#define PRISM_INTERNAL_MEMCHR_H

#include "prism/internal/encoding.h"

#include <stddef.h>
#include <stdint.h>

/* Return the first occurrence of byte in the slice, or NULL. */
const uint8_t * pm_memchr(const uint8_t *source, uint8_t byte, size_t length);

/*
 * Find an ASCII delimiter at a character boundary in the given encoding.
 * Scan one character at a time when the delimiter could be a trailing byte.
 */
const uint8_t * pm_memchr_boundary(const uint8_t *source, uint8_t byte, size_t length, const pm_encoding_t *encoding);

#endif
