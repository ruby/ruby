/**
 * @file strings.h
 *
 * A generic string type that can have various ownership semantics.
 */
#ifndef PRISM_STRINGS_H
#define PRISM_STRINGS_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

/**
 * A generic string type that can have various ownership semantics.
 */
typedef struct {
    /** A pointer to the start of the string. */
    const uint8_t *source;

    /** The length of the string in bytes of memory. */
    size_t length;

    /** The type of the string. This field determines how the string should be freed. */
    enum {
        /** This string is a constant string, and should not be freed. */
        PM_STRING_CONSTANT,

        /** This is a slice of another string, and should not be freed. */
        PM_STRING_SHARED,

        /** This string owns its memory, and should be freed internally. */
        PM_STRING_OWNED
    } type;
} pm_string_t;

/**
 * Initialize a constant string that doesn't own its memory source.
 *
 * @param string The string to initialize.
 * @param source The source of the string.
 * @param length The length of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_string_constant_init(pm_string_t *string, const char *source, size_t length) PRISM_NONNULL(1);

/**
 * Initialize an owned string that is responsible for freeing allocated memory.
 *
 * @param string The string to initialize.
 * @param source The source of the string.
 * @param length The length of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length) PRISM_NONNULL(1, 2);

/**
 * Returns the length associated with the string.
 *
 * @param string The string to get the length of.
 * @returns The length of the string.
 */
PRISM_EXPORTED_FUNCTION size_t pm_string_length(const pm_string_t *string) PRISM_NONNULL(1);

/**
 * Returns the start pointer associated with the string.
 *
 * @param string The string to get the start pointer of.
 * @returns The start pointer of the string.
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_string_source(const pm_string_t *string) PRISM_NONNULL(1);

#endif
