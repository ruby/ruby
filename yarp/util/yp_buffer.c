#include "yarp/util/yp_buffer.h"

#define YP_BUFFER_INITIAL_SIZE 1024

// Return the size of the yp_buffer_t struct.
size_t
yp_buffer_sizeof(void) {
    return sizeof(yp_buffer_t);
}

// Initialize a yp_buffer_t with its default values.
bool
yp_buffer_init(yp_buffer_t *buffer) {
    buffer->length = 0;
    buffer->capacity = YP_BUFFER_INITIAL_SIZE;

    buffer->value = (char *) malloc(YP_BUFFER_INITIAL_SIZE);
    return buffer->value != NULL;
}

// Return the value of the buffer.
char *
yp_buffer_value(yp_buffer_t *buffer) {
    return buffer->value;
}

// Return the length of the buffer.
size_t
yp_buffer_length(yp_buffer_t *buffer) {
    return buffer->length;
}

// Append the given amount of space to the buffer.
static inline void
yp_buffer_append_length(yp_buffer_t *buffer, size_t length) {
    size_t next_length = buffer->length + length;

    if (next_length > buffer->capacity) {
        do {
            buffer->capacity *= 2;
        } while (next_length > buffer->capacity);

        buffer->value = realloc(buffer->value, buffer->capacity);
    }

    buffer->length = next_length;
}

// Append a generic pointer to memory to the buffer.
static inline void
yp_buffer_append(yp_buffer_t *buffer, const void *source, size_t length) {
    yp_buffer_append_length(buffer, length);
    memcpy(buffer->value + (buffer->length - length), source, length);
}

// Append the given amount of space as zeroes to the buffer.
void
yp_buffer_append_zeroes(yp_buffer_t *buffer, size_t length) {
    yp_buffer_append_length(buffer, length);
    memset(buffer->value + (buffer->length - length), 0, length);
}

// Append a string to the buffer.
void
yp_buffer_append_str(yp_buffer_t *buffer, const char *value, size_t length) {
    yp_buffer_append(buffer, value, length);
}

// Append a list of bytes to the buffer.
void
yp_buffer_append_bytes(yp_buffer_t *buffer, const uint8_t *value, size_t length) {
    yp_buffer_append(buffer, (const char *) value, length);
}

// Append a single byte to the buffer.
void
yp_buffer_append_u8(yp_buffer_t *buffer, uint8_t value) {
    const void *source = &value;
    yp_buffer_append(buffer, source, sizeof(uint8_t));
}

// Append a 32-bit unsigned integer to the buffer.
void
yp_buffer_append_u32(yp_buffer_t *buffer, uint32_t value) {
    if (value < 128) {
        yp_buffer_append_u8(buffer, (uint8_t) value);
    } else {
        uint32_t n = value;
        while (n >= 128) {
            yp_buffer_append_u8(buffer, (uint8_t) (n | 128));
            n >>= 7;
        }
        yp_buffer_append_u8(buffer, (uint8_t) n);
    }
}

// Free the memory associated with the buffer.
void
yp_buffer_free(yp_buffer_t *buffer) {
    free(buffer->value);
}
