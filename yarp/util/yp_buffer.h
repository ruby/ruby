#ifndef YARP_BUFFER_H
#define YARP_BUFFER_H

#include "yarp/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// A yp_buffer_t is a simple memory buffer that stores data in a contiguous
// block of memory. It is used to store the serialized representation of a
// YARP tree.
typedef struct {
    char *value;
    size_t length;
    size_t capacity;
} yp_buffer_t;

// Return the size of the yp_buffer_t struct.
YP_EXPORTED_FUNCTION size_t yp_buffer_sizeof(void);

// Initialize a yp_buffer_t with its default values.
YP_EXPORTED_FUNCTION bool yp_buffer_init(yp_buffer_t *buffer);

// Return the value of the buffer.
YP_EXPORTED_FUNCTION char * yp_buffer_value(yp_buffer_t *buffer);

// Return the length of the buffer.
YP_EXPORTED_FUNCTION size_t yp_buffer_length(yp_buffer_t *buffer);

// Append the given amount of space as zeroes to the buffer.
void yp_buffer_append_zeroes(yp_buffer_t *buffer, size_t length);

// Append a string to the buffer.
void yp_buffer_append_str(yp_buffer_t *buffer, const char *value, size_t length);

// Append a list of bytes to the buffer.
void yp_buffer_append_bytes(yp_buffer_t *buffer, const uint8_t *value, size_t length);

// Append a single byte to the buffer.
void yp_buffer_append_u8(yp_buffer_t *buffer, uint8_t value);

// Append a 32-bit unsigned integer to the buffer.
void yp_buffer_append_u32(yp_buffer_t *buffer, uint32_t value);

// Free the memory associated with the buffer.
YP_EXPORTED_FUNCTION void yp_buffer_free(yp_buffer_t *buffer);

#endif
