#ifndef PRISM_INTERNAL_STRINGY_H
#define PRISM_INTERNAL_STRINGY_H

#include "prism/stringy.h"

#include <stdbool.h>

/*
 * Backing storage for an empty string.
 */
static const uint8_t empty_source[] = "";

/*
 * Defines an empty string. This is useful for initializing a string that will
 * be filled in later.
 */
#define PM_STRING_EMPTY ((pm_string_t) { .source = empty_source, .length = 0 })

/* View a string literal without its terminating NUL. */
#define PM_STRING_LITERAL(name_) ((pm_string_t) { .source = (const uint8_t *) ("" name_), .length = sizeof(name_) - 1 })

/*
 * Initialize a shared string that is based on initial input.
 */
void pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end);

/*
 * Returns true if every byte of the string is ASCII.
 */
bool pm_string_ascii_only_p(const pm_string_t *string);

#endif
