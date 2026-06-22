#ifndef PRISM_INTERNAL_STRINGY_H
#define PRISM_INTERNAL_STRINGY_H

#include "prism/stringy.h"

/*
 * Defines an empty string. This is useful for initializing a string that will
 * be filled in later.
 */
#define PM_STRING_EMPTY ((pm_string_t) { .type = PM_STRING_CONSTANT, .source = NULL, .length = 0 })

/*
 * Initialize a shared string that is based on initial input.
 */
void pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end);

/*
 * Compare the underlying lengths and bytes of two strings. Returns 0 if the
 * strings are equal, a negative number if the left string is less than the
 * right string, and a positive number if the left string is greater than the
 * right string.
 */
int pm_string_compare(const pm_string_t *left, const pm_string_t *right);

/*
 * Free the associated memory of the given string.
 */
void pm_string_cleanup(pm_string_t *string);

#endif
