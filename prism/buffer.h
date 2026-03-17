/**
 * @file buffer.h
 *
 * A wrapper around a contiguous block of allocated memory.
 */
#ifndef PRISM_BUFFER_H
#define PRISM_BUFFER_H

#include "prism/compiler/exported.h"

#include <stdbool.h>
#include <stddef.h>

/**
 * A pm_buffer_t is a simple memory buffer that stores data in a contiguous
 * block of memory.
 */
typedef struct {
    /** The length of the buffer in bytes. */
    size_t length;

    /** The capacity of the buffer in bytes that has been allocated. */
    size_t capacity;

    /** A pointer to the start of the buffer. */
    char *value;
} pm_buffer_t;

/**
 * Return the size of the pm_buffer_t struct.
 *
 * @returns The size of the pm_buffer_t struct.
 */
PRISM_EXPORTED_FUNCTION size_t pm_buffer_sizeof(void);

/**
 * Initialize a pm_buffer_t with its default values.
 *
 * @param buffer The buffer to initialize.
 * @returns True if the buffer was initialized successfully, false otherwise.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION bool pm_buffer_init(pm_buffer_t *buffer);

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

/**
 * Free the memory associated with the buffer.
 *
 * @param buffer The buffer to free.
 *
 * \public \memberof pm_buffer_t
 */
PRISM_EXPORTED_FUNCTION void pm_buffer_free(pm_buffer_t *buffer);

#endif
