#ifndef YARP_BUFFER_H
#define YARP_BUFFER_H

#include "yarp/defines.h"

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

// Allocate a new yp_buffer_t.
__attribute__ ((__visibility__("default"))) extern yp_buffer_t *
yp_buffer_alloc(void);

// Initialize a yp_buffer_t with its default values.
__attribute__ ((__visibility__("default"))) extern void
yp_buffer_init(yp_buffer_t *buffer);

// Append a string to the buffer.
void
yp_buffer_append_str(yp_buffer_t *buffer, const char *value, size_t length);

// Append a single byte to the buffer.
void
yp_buffer_append_u8(yp_buffer_t *buffer, uint8_t value);

// Append a 16-bit unsigned integer to the buffer.
void
yp_buffer_append_u16(yp_buffer_t *buffer, uint16_t value);

// Append a 32-bit unsigned integer to the buffer.
void
yp_buffer_append_u32(yp_buffer_t *buffer, uint32_t value);

// Append a 64-bit unsigned integer to the buffer.
void
yp_buffer_append_u64(yp_buffer_t *buffer, uint64_t value);

// Append an integer to the buffer.
void
yp_buffer_append_int(yp_buffer_t *buffer, int value);

// Free the memory associated with the buffer.
__attribute__ ((__visibility__("default"))) extern void
yp_buffer_free(yp_buffer_t *buffer);

#endif
