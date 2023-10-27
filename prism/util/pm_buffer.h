#ifndef PRISM_BUFFER_H
#define PRISM_BUFFER_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// A pm_buffer_t is a simple memory buffer that stores data in a contiguous
// block of memory. It is used to store the serialized representation of a
// prism tree.
typedef struct {
    size_t length;
    size_t capacity;
    char *value;
} pm_buffer_t;

// Return the size of the pm_buffer_t struct.
PRISM_EXPORTED_FUNCTION size_t pm_buffer_sizeof(void);

// Initialize a pm_buffer_t with the given capacity.
bool pm_buffer_init_capacity(pm_buffer_t *buffer, size_t capacity);

// Initialize a pm_buffer_t with its default values.
PRISM_EXPORTED_FUNCTION bool pm_buffer_init(pm_buffer_t *buffer);

// Return the value of the buffer.
PRISM_EXPORTED_FUNCTION char * pm_buffer_value(pm_buffer_t *buffer);

// Return the length of the buffer.
PRISM_EXPORTED_FUNCTION size_t pm_buffer_length(pm_buffer_t *buffer);

// Append the given amount of space as zeroes to the buffer.
void pm_buffer_append_zeroes(pm_buffer_t *buffer, size_t length);

// Append a formatted string to the buffer.
void pm_buffer_append_format(pm_buffer_t *buffer, const char *format, ...) PRISM_ATTRIBUTE_FORMAT(2, 3);

// Append a string to the buffer.
void pm_buffer_append_string(pm_buffer_t *buffer, const char *value, size_t length);

// Append a list of bytes to the buffer.
void pm_buffer_append_bytes(pm_buffer_t *buffer, const uint8_t *value, size_t length);

// Append a single byte to the buffer.
void pm_buffer_append_byte(pm_buffer_t *buffer, uint8_t value);

// Append a 32-bit unsigned integer to the buffer.
void pm_buffer_append_varint(pm_buffer_t *buffer, uint32_t value);

// Append one buffer onto another.
void pm_buffer_concat(pm_buffer_t *destination, const pm_buffer_t *source);

// Free the memory associated with the buffer.
PRISM_EXPORTED_FUNCTION void pm_buffer_free(pm_buffer_t *buffer);

#endif
