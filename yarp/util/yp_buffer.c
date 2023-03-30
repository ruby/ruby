#include "yp_buffer.h"

#define YP_BUFFER_INITIAL_SIZE 1024

// Allocate a new yp_buffer_t.
yp_buffer_t *
yp_buffer_alloc(void) {
  return (yp_buffer_t *) malloc(sizeof(yp_buffer_t));
}

// Initialize a yp_buffer_t with its default values.
void
yp_buffer_init(yp_buffer_t *buffer) {
  buffer->value = (char *) malloc(YP_BUFFER_INITIAL_SIZE);
  buffer->length = 0;
  buffer->capacity = YP_BUFFER_INITIAL_SIZE;
}

// Append a generic pointer to memory to the buffer.
static inline void
yp_buffer_append(yp_buffer_t *buffer, const void *source, size_t length) {
  if (buffer->length + length > buffer->capacity) {
    buffer->capacity = buffer->capacity * 2;
    buffer->value = realloc(buffer->value, buffer->capacity);
  }
  memcpy(buffer->value + buffer->length, source, length);
  buffer->length += length;
}

// Append a string to the buffer.
void
yp_buffer_append_str(yp_buffer_t *buffer, const char *value, size_t length) {
  const void *source = value;
  yp_buffer_append(buffer, source, length);
}

// Append a single byte to the buffer.
void
yp_buffer_append_u8(yp_buffer_t *buffer, uint8_t value) {
  const void *source = &value;
  yp_buffer_append(buffer, source, sizeof(uint8_t));
}

// Append a 16-bit unsigned integer to the buffer.
void
yp_buffer_append_u16(yp_buffer_t *buffer, uint16_t value) {
  const void *source = &value;
  yp_buffer_append(buffer, source, sizeof(uint16_t));
}

// Append a 32-bit unsigned integer to the buffer.
void
yp_buffer_append_u32(yp_buffer_t *buffer, uint32_t value) {
  const void *source = &value;
  yp_buffer_append(buffer, source, sizeof(uint32_t));
}

// Append a 64-bit unsigned integer to the buffer.
void
yp_buffer_append_u64(yp_buffer_t *buffer, uint64_t value) {
  const void *source = &value;
  yp_buffer_append(buffer, source, sizeof(uint64_t));
}

// Append an integer to the buffer.
void
yp_buffer_append_int(yp_buffer_t *buffer, int value) {
  const void *source = &value;
  yp_buffer_append(buffer, source, sizeof(int));
}

// Free the memory associated with the buffer.
void
yp_buffer_free(yp_buffer_t *buffer) {
  free(buffer->value);
}
