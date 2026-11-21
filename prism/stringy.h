/**
 * @file stringy.h
 *
 * A view of a sequence of bytes owned by someone else.
 */
#ifndef PRISM_STRINGY_H
#define PRISM_STRINGY_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * A view of a sequence of bytes. The string does not own the bytes, so they
 * must remain valid for as long as the string is in use.
 */
typedef struct {
    /** A pointer to the start of the string. */
    const uint8_t *source;

    /** The length of the string in bytes of memory. */
    size_t length;
} pm_string_t;

/**
 * Initialize a string that views the given bytes. The bytes are not copied, so
 * they must remain valid for as long as the string is in use.
 *
 * @param string The string to initialize.
 * @param source The start of the bytes.
 * @param length The number of bytes.
 */
PRISM_EXPORTED_FUNCTION void pm_string_init(pm_string_t *string, const uint8_t *source, size_t length) PRISM_NONNULL(1);

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

#ifdef __cplusplus
}
#endif

#endif
