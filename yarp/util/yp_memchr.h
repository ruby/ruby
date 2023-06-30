#ifndef YP_MEMCHR_H
#define YP_MEMCHR_H

#include "yarp/defines.h"
#include "yarp/parser.h"

#include <stddef.h>

// We need to roll our own memchr to handle cases where the encoding changes and
// we need to search for a character in a buffer that could be the trailing byte
// of a multibyte character.
void * yp_memchr(yp_parser_t *parser, const void *source, int character, size_t number);

#endif
