#ifndef PRISM_INTERNAL_BUFFER_H
#define PRISM_INTERNAL_BUFFER_H

#include "prism/compiler/format.h"

#include "prism/buffer.h"

#include <stdbool.h>
#include <stdint.h>

/*
 * A simple memory buffer that stores data in a contiguous block of memory.
 */
struct pm_buffer_t {
    /* The length of the buffer in bytes. */
    size_t length;

    /* The capacity of the buffer in bytes that has been allocated. */
    size_t capacity;

    /* A pointer to the start of the buffer. */
    char *value;
};

/* Initialize a pm_buffer_t with the given capacity. */
void pm_buffer_init(pm_buffer_t *buffer, size_t capacity);

/* Free the memory held by the buffer. */
void pm_buffer_cleanup(pm_buffer_t *buffer);

/* Append the given amount of space as zeroes to the buffer. */
void pm_buffer_append_zeroes(pm_buffer_t *buffer, size_t length);

/* Append a formatted string to the buffer. */
void pm_buffer_append_format(pm_buffer_t *buffer, const char *format, ...) PRISM_ATTRIBUTE_FORMAT(2, 3);

/* Append a string to the buffer. */
void pm_buffer_append_string(pm_buffer_t *buffer, const char *value, size_t length);

/* Append a list of bytes to the buffer. */
void pm_buffer_append_bytes(pm_buffer_t *buffer, const uint8_t *value, size_t length);

/* Append a single byte to the buffer. */
void pm_buffer_append_byte(pm_buffer_t *buffer, uint8_t value);

/* Append a 32-bit unsigned integer to the buffer as a variable-length integer. */
void pm_buffer_append_varuint(pm_buffer_t *buffer, uint32_t value);

/* Append a 32-bit signed integer to the buffer as a variable-length integer. */
void pm_buffer_append_varsint(pm_buffer_t *buffer, int32_t value);

/* Append a double to the buffer. */
void pm_buffer_append_double(pm_buffer_t *buffer, double value);

/* Append a unicode codepoint to the buffer. */
bool pm_buffer_append_unicode_codepoint(pm_buffer_t *buffer, uint32_t value);

/*
 * The different types of escaping that can be performed by the buffer when
 * appending a slice of Ruby source code.
 */
typedef enum {
    PM_BUFFER_ESCAPING_RUBY,
    PM_BUFFER_ESCAPING_JSON
} pm_buffer_escaping_t;

/* Append a slice of source code to the buffer. */
void pm_buffer_append_source(pm_buffer_t *buffer, const uint8_t *source, size_t length, pm_buffer_escaping_t escaping);

/* Prepend the given string to the buffer. */
void pm_buffer_prepend_string(pm_buffer_t *buffer, const char *value, size_t length);

/* Concatenate one buffer onto another. */
void pm_buffer_concat(pm_buffer_t *destination, const pm_buffer_t *source);

/*
 * Clear the buffer by reducing its size to 0. This does not free the allocated
 * memory, but it does allow the buffer to be reused.
 */
void pm_buffer_clear(pm_buffer_t *buffer);

/* Strip the whitespace from the end of the buffer. */
void pm_buffer_rstrip(pm_buffer_t *buffer);

/* Checks if the buffer includes the given value. */
size_t pm_buffer_index(const pm_buffer_t *buffer, char value);

/* Insert the given string into the buffer at the given index. */
void pm_buffer_insert(pm_buffer_t *buffer, size_t index, const char *value, size_t length);

#endif
