#ifndef PRISM_MEMCHR_H
#define PRISM_MEMCHR_H

#include "prism/defines.h"
#include "prism/enc/pm_encoding.h"

#include <stddef.h>

// We need to roll our own memchr to handle cases where the encoding changes and
// we need to search for a character in a buffer that could be the trailing byte
// of a multibyte character.
void * pm_memchr(const void *source, int character, size_t number, bool encoding_changed, pm_encoding_t *encoding);

#endif
