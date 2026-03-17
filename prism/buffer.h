/**
 * @file buffer.h
 *
 * A wrapper around a contiguous block of allocated memory.
 */
#ifndef PRISM_BUFFER_H
#define PRISM_BUFFER_H

#include "prism/compiler/exported.h"

#include <stddef.h>

/**
 * A wrapper around a contiguous block of allocated memory.
 */
typedef struct pm_buffer_t pm_buffer_t;

/**
 * Allocate and initialize a new buffer. If the buffer cannot be allocated, this
 * function will abort the process.
 *
 * @returns A pointer to the initialized buffer. The caller is responsible for
 *     freeing the buffer with pm_buffer_free.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION pm_buffer_t * pm_buffer_new(void);

/**
 * Free both the memory held by the buffer and the buffer itself.
 *
 * @param buffer The buffer to free.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION void pm_buffer_free(pm_buffer_t *buffer);

/**
 * Return the value of the buffer.
 *
 * @param buffer The buffer to get the value of.
 * @returns The value of the buffer.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION char * pm_buffer_value(const pm_buffer_t *buffer);

/**
 * Return the length of the buffer.
 *
 * @param buffer The buffer to get the length of.
 * @returns The length of the buffer.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION size_t pm_buffer_length(const pm_buffer_t *buffer);

#endif
