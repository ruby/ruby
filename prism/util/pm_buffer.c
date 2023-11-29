#include "prism/util/pm_buffer.h"

/**
 * Return the size of the pm_buffer_t struct.
 */
size_t
pm_buffer_sizeof(void) {
    return sizeof(pm_buffer_t);
}

/**
 * Initialize a pm_buffer_t with the given capacity.
 */
bool
pm_buffer_init_capacity(pm_buffer_t *buffer, size_t capacity) {
    buffer->length = 0;
    buffer->capacity = capacity;

    buffer->value = (char *) malloc(capacity);
    return buffer->value != NULL;
}

/**
 * Initialize a pm_buffer_t with its default values.
 */
bool
pm_buffer_init(pm_buffer_t *buffer) {
    return pm_buffer_init_capacity(buffer, 1024);
}

/**
 * Return the value of the buffer.
 */
char *
pm_buffer_value(pm_buffer_t *buffer) {
    return buffer->value;
}

/**
 * Return the length of the buffer.
 */
size_t
pm_buffer_length(pm_buffer_t *buffer) {
    return buffer->length;
}

/**
 * Append the given amount of space to the buffer.
 */
static inline void
pm_buffer_append_length(pm_buffer_t *buffer, size_t length) {
    size_t next_length = buffer->length + length;

    if (next_length > buffer->capacity) {
        if (buffer->capacity == 0) {
            buffer->capacity = 1;
        }

        while (next_length > buffer->capacity) {
            buffer->capacity *= 2;
        }

        buffer->value = realloc(buffer->value, buffer->capacity);
    }

    buffer->length = next_length;
}

/**
 * Append a generic pointer to memory to the buffer.
 */
static inline void
pm_buffer_append(pm_buffer_t *buffer, const void *source, size_t length) {
    size_t cursor = buffer->length;
    pm_buffer_append_length(buffer, length);
    memcpy(buffer->value + cursor, source, length);
}

/**
 * Append the given amount of space as zeroes to the buffer.
 */
void
pm_buffer_append_zeroes(pm_buffer_t *buffer, size_t length) {
    size_t cursor = buffer->length;
    pm_buffer_append_length(buffer, length);
    memset(buffer->value + cursor, 0, length);
}

/**
 * Append a formatted string to the buffer.
 */
void
pm_buffer_append_format(pm_buffer_t *buffer, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = vsnprintf(NULL, 0, format, arguments);
    va_end(arguments);

    if (result < 0) return;
    size_t length = (size_t) (result + 1);

    size_t cursor = buffer->length;
    pm_buffer_append_length(buffer, length);

    va_start(arguments, format);
    vsnprintf(buffer->value + cursor, length, format, arguments);
    va_end(arguments);

    buffer->length--;
}

/**
 * Append a string to the buffer.
 */
void
pm_buffer_append_string(pm_buffer_t *buffer, const char *value, size_t length) {
    pm_buffer_append(buffer, value, length);
}

/**
 * Append a list of bytes to the buffer.
 */
void
pm_buffer_append_bytes(pm_buffer_t *buffer, const uint8_t *value, size_t length) {
    pm_buffer_append(buffer, (const char *) value, length);
}

/**
 * Append a single byte to the buffer.
 */
void
pm_buffer_append_byte(pm_buffer_t *buffer, uint8_t value) {
    const void *source = &value;
    pm_buffer_append(buffer, source, sizeof(uint8_t));
}

/**
 * Append a 32-bit unsigned integer to the buffer as a variable-length integer.
 */
void
pm_buffer_append_varuint(pm_buffer_t *buffer, uint32_t value) {
    if (value < 128) {
        pm_buffer_append_byte(buffer, (uint8_t) value);
    } else {
        uint32_t n = value;
        while (n >= 128) {
            pm_buffer_append_byte(buffer, (uint8_t) (n | 128));
            n >>= 7;
        }
        pm_buffer_append_byte(buffer, (uint8_t) n);
    }
}

/**
 * Append a 32-bit signed integer to the buffer as a variable-length integer.
 */
void
pm_buffer_append_varsint(pm_buffer_t *buffer, int32_t value) {
    uint32_t unsigned_int = ((uint32_t)(value) << 1) ^ ((uint32_t)(value >> 31));
    pm_buffer_append_varuint(buffer, unsigned_int);
}

/**
 * Concatenate one buffer onto another.
 */
void
pm_buffer_concat(pm_buffer_t *destination, const pm_buffer_t *source) {
    if (source->length > 0) {
        pm_buffer_append(destination, source->value, source->length);
    }
}

/**
 * Free the memory associated with the buffer.
 */
void
pm_buffer_free(pm_buffer_t *buffer) {
    free(buffer->value);
}
