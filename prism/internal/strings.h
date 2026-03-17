/**
 * @file internal/strings.h
 *
 * A generic string type that can have various ownership semantics.
 */
#ifndef PRISM_INTERNAL_STRINGS_H
#define PRISM_INTERNAL_STRINGS_H

#include "prism/strings.h"

/**
 * Defines an empty string. This is useful for initializing a string that will
 * be filled in later.
 */
#define PM_STRING_EMPTY ((pm_string_t) { .type = PM_STRING_CONSTANT, .source = NULL, .length = 0 })

/**
 * Initialize a shared string that is based on initial input.
 *
 * @param string The string to initialize.
 * @param start The start of the string.
 * @param end The end of the string.
 */
void pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end);

/**
 * Initialize an owned string that is responsible for freeing allocated memory.
 *
 * @param string The string to initialize.
 * @param source The source of the string.
 * @param length The length of the string.
 */
void pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length);

/**
 * Ensure the string is owned. If it is not, then reinitialize it as owned and
 * copy over the previous source.
 *
 * @param string The string to ensure is owned.
 */
void pm_string_ensure_owned(pm_string_t *string);

/**
 * Compare the underlying lengths and bytes of two strings. Returns 0 if the
 * strings are equal, a negative number if the left string is less than the
 * right string, and a positive number if the left string is greater than the
 * right string.
 *
 * @param left The left string to compare.
 * @param right The right string to compare.
 * @return The comparison result.
 */
int pm_string_compare(const pm_string_t *left, const pm_string_t *right);

#endif
