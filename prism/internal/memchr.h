#ifndef PRISM_INTERNAL_MEMCHR_H
#define PRISM_INTERNAL_MEMCHR_H

#include "prism/internal/encoding.h"

#include <stddef.h>

/*
 * Find an ASCII delimiter at a character boundary in the given encoding.
 */
const void * pm_memchr(const void *source, int character, size_t number, const pm_encoding_t *encoding);

#endif
