#include "prism/internal/buffer.h"

#include "prism/compiler/inline.h"

#include "prism/internal/allocator.h"
#include "prism/internal/char.h"
#include "prism/internal/oom.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

/**
 * Initialize a pm_buffer_t with the given capacity.
 */
void
pm_buffer_init(pm_buffer_t *buffer, size_t capacity) {
    buffer->length = 0;
    buffer->capacity = capacity;

    buffer->value = (char *) xmalloc(capacity);
    if (buffer->value == NULL) PRISM_OOM();
}

/**
 * Allocate and initialize a new buffer.
 */
pm_buffer_t *
pm_buffer_new(void) {
    pm_buffer_t *buffer = (pm_buffer_t *) xmalloc(sizeof(pm_buffer_t));
    if (buffer == NULL) PRISM_OOM();

    pm_buffer_init(buffer, 1024);
    return buffer;
}

/**
 * Return the value of the buffer.
 */
char *
pm_buffer_value(const pm_buffer_t *buffer) {
    return buffer->value;
}

/**
 * Return the length of the buffer.
 */
size_t
pm_buffer_length(const pm_buffer_t *buffer) {
    return buffer->length;
}

/**
 * Append the given amount of space to the buffer. Returns false when there is
 * nothing to write because the length is zero. A zero-initialized buffer has a
 * NULL value until its first allocation, and passing NULL to
 * memcpy/memset/memmove is undefined behavior even for zero bytes, so callers
 * must not write in the zero case.
 *
 * The value and capacity are only updated together once the allocation has
 * succeeded, so the buffer remains valid to free if PRISM_OOM unwinds.
 */
static PRISM_INLINE bool
pm_buffer_append_length(pm_buffer_t *buffer, size_t length) {
    if (length == 0) return false;

    size_t next_length = buffer->length + length;
    if (next_length < buffer->length) PRISM_OOM();

    if (next_length > buffer->capacity) {
        size_t next_capacity = buffer->capacity == 0 ? 1 : buffer->capacity;

        while (next_length > next_capacity) {
            if (next_capacity > SIZE_MAX / 2) PRISM_OOM();
            next_capacity *= 2;
        }

        char *next_value = xrealloc_sized(buffer->value, next_capacity, buffer->capacity);
        if (next_value == NULL) PRISM_OOM();

        buffer->value = next_value;
        buffer->capacity = next_capacity;
    }

    buffer->length = next_length;
    return true;
}

/**
 * Append a generic pointer to memory to the buffer.
 */
static PRISM_INLINE void
pm_buffer_append(pm_buffer_t *buffer, const void *source, size_t length) {
    size_t cursor = buffer->length;
    if (pm_buffer_append_length(buffer, length)) {
        memcpy(buffer->value + cursor, source, length);
    }
}

/**
 * Append the given amount of space as zeroes to the buffer.
 */
void
pm_buffer_append_zeroes(pm_buffer_t *buffer, size_t length) {
    size_t cursor = buffer->length;
    if (pm_buffer_append_length(buffer, length)) {
        memset(buffer->value + cursor, 0, length);
    }
}

/**
 * Append the given byte to the buffer the given number of times.
 */
void
pm_buffer_append_repeated(pm_buffer_t *buffer, uint8_t value, size_t length) {
    size_t cursor = buffer->length;
    if (pm_buffer_append_length(buffer, length)) {
        memset(buffer->value + cursor, value, length);
    }
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
    if (pm_buffer_append_length(buffer, length)) {
        va_start(arguments, format);
        vsnprintf(buffer->value + cursor, length, format, arguments);
        va_end(arguments);
        buffer->length--;
    }
}

/**
 * Append the decimal digits of an unsigned integer without leading zeros.
 */
void
pm_buffer_append_decimal(pm_buffer_t *buffer, uint64_t value) {
    char digits[20]; /* UINT64_MAX has 20 decimal digits. */
    size_t offset = sizeof(digits);

    do {
        digits[--offset] = (char) ('0' + value % 10);
        value /= 10;
    } while (value);

    pm_buffer_append_string(buffer, digits + offset, sizeof(digits) - offset);
}

/** The uppercase hexadecimal digits in order of value. */
static const char pm_buffer_hexadecimal_digits[] = "0123456789ABCDEF";

/**
 * Append uppercase hexadecimal digits, padded with zeros to the given width.
 */
void
pm_buffer_append_hexadecimal(pm_buffer_t *buffer, uint32_t value, uint8_t width) {
    char digits[8]; /* UINT32_MAX has eight hexadecimal digits. */
    size_t offset = sizeof(digits);

    do {
        digits[--offset] = pm_buffer_hexadecimal_digits[value & 0xF];
        value >>= 4;
    } while (value);

    size_t length = sizeof(digits) - offset;
    if (width > length) pm_buffer_append_repeated(buffer, '0', width - length);
    pm_buffer_append_string(buffer, digits + offset, length);
}

/**
 * Append a byte as a \xHH escape.
 */
void
pm_buffer_append_byte_escape(pm_buffer_t *buffer, uint8_t byte) {
    const char escape[] = { '\\', 'x', pm_buffer_hexadecimal_digits[byte >> 4], pm_buffer_hexadecimal_digits[byte & 0xF] };
    pm_buffer_append_string(buffer, escape, sizeof(escape));
}

/**
 * Write a signed line number at the end of digits and return its length.
 * The widest possible line number is -2147483648.
 */
static uint8_t
pm_buffer_line_number_digits(int32_t line, char digits[11]) {
    /* Use unsigned arithmetic so that INT32_MIN has a representable magnitude. */
    uint32_t magnitude = (line < 0) ? (0U - (uint32_t) line) : (uint32_t) line;
    uint8_t length = 0;

    do {
        digits[10 - length++] = (char) ('0' + (magnitude % 10));
        magnitude /= 10;
    } while (magnitude);

    if (line < 0) digits[10 - length++] = '-';
    return length;
}

/**
 * Return the decimal width of a line number, including its sign.
 */
uint8_t
pm_buffer_line_number_width(int32_t line) {
    char digits[11];
    return pm_buffer_line_number_digits(line, digits);
}

/**
 * Append a line number, padded on the left with spaces to the given width.
 */
void
pm_buffer_append_line_number(pm_buffer_t *buffer, int32_t line, uint8_t width) {
    char digits[11];
    uint8_t length = pm_buffer_line_number_digits(line, digits);

    if (width > length) pm_buffer_append_repeated(buffer, ' ', (size_t) (width - length));
    pm_buffer_append_string(buffer, digits + sizeof(digits) - length, length);
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
 * Append a double to the buffer.
 */
void
pm_buffer_append_double(pm_buffer_t *buffer, double value) {
    const void *source = &value;
    pm_buffer_append(buffer, source, sizeof(double));
}

/**
 * Append a 64-bit unsigned integer to the buffer in native endian order.
 */
void
pm_buffer_append_uint64(pm_buffer_t *buffer, uint64_t value) {
    const void *source = &value;
    pm_buffer_append(buffer, source, sizeof(uint64_t));
}

/**
 * Append a unicode codepoint to the buffer.
 */
bool
pm_buffer_append_unicode_codepoint(pm_buffer_t *buffer, uint32_t value) {
    if (value <= 0x7F) {
        pm_buffer_append_byte(buffer, (uint8_t) value); // 0xxxxxxx
        return true;
    } else if (value <= 0x7FF) {
        uint8_t bytes[] = {
            (uint8_t) (0xC0 | ((value >> 6) & 0x3F)), // 110xxxxx
            (uint8_t) (0x80 | (value & 0x3F))         // 10xxxxxx
        };

        pm_buffer_append_bytes(buffer, bytes, 2);
        return true;
    } else if (value <= 0xFFFF) {
        uint8_t bytes[] = {
            (uint8_t) (0xE0 | ((value >> 12) & 0x3F)), // 1110xxxx
            (uint8_t) (0x80 | ((value >> 6) & 0x3F)),  // 10xxxxxx
            (uint8_t) (0x80 | (value & 0x3F))          // 10xxxxxx
        };

        pm_buffer_append_bytes(buffer, bytes, 3);
        return true;
    } else if (value <= 0x10FFFF) {
        uint8_t bytes[] = {
            (uint8_t) (0xF0 | ((value >> 18) & 0x3F)), // 11110xxx
            (uint8_t) (0x80 | ((value >> 12) & 0x3F)), // 10xxxxxx
            (uint8_t) (0x80 | ((value >> 6) & 0x3F)),  // 10xxxxxx
            (uint8_t) (0x80 | (value & 0x3F))          // 10xxxxxx
        };

        pm_buffer_append_bytes(buffer, bytes, 4);
        return true;
    } else {
        return false;
    }
}

/**
 * Append a slice of source code to the buffer.
 */
void
pm_buffer_append_source(pm_buffer_t *buffer, const uint8_t *source, size_t length, pm_buffer_escaping_t escaping) {
    for (size_t index = 0; index < length; index++) {
        const uint8_t byte = source[index];

        if ((byte <= 0x06) || (byte >= 0x0E && byte <= 0x1F) || (byte >= 0x7F)) {
            if (escaping == PM_BUFFER_ESCAPING_RUBY) {
                pm_buffer_append_byte_escape(buffer, byte);
            } else {
                PM_BUFFER_APPEND_LITERAL(buffer, "\\u");
                pm_buffer_append_hexadecimal(buffer, byte, 4);
            }
        } else {
            switch (byte) {
                case '\a':
                    if (escaping == PM_BUFFER_ESCAPING_RUBY) {
                        PM_BUFFER_APPEND_LITERAL(buffer, "\\a");
                    } else {
                        PM_BUFFER_APPEND_LITERAL(buffer, "\\u0007");
                    }
                    break;
                case '\b':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\b");
                    break;
                case '\t':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\t");
                    break;
                case '\n':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\n");
                    break;
                case '\v':
                    if (escaping == PM_BUFFER_ESCAPING_RUBY) {
                        PM_BUFFER_APPEND_LITERAL(buffer, "\\v");
                    } else {
                        PM_BUFFER_APPEND_LITERAL(buffer, "\\u000B");
                    }
                    break;
                case '\f':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\f");
                    break;
                case '\r':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\r");
                    break;
                case '"':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\\"");
                    break;
                case '#': {
                    if (escaping == PM_BUFFER_ESCAPING_RUBY && index + 1 < length) {
                        const uint8_t next_byte = source[index + 1];
                        if (next_byte == '{' || next_byte == '@' || next_byte == '$') {
                            pm_buffer_append_byte(buffer, '\\');
                        }
                    }

                    pm_buffer_append_byte(buffer, '#');
                    break;
                }
                case '\\':
                    PM_BUFFER_APPEND_LITERAL(buffer, "\\\\");
                    break;
                default:
                    pm_buffer_append_byte(buffer, byte);
                    break;
            }
        }
    }
}

/**
 * Prepend the given string to the buffer.
 */
void
pm_buffer_prepend_string(pm_buffer_t *buffer, const char *value, size_t length) {
    size_t cursor = buffer->length;
    if (pm_buffer_append_length(buffer, length)) {
        memmove(buffer->value + length, buffer->value, cursor);
        memcpy(buffer->value, value, length);
    }
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
 * Clear the buffer by reducing its size to 0. This does not free the allocated
 * memory, but it does allow the buffer to be reused.
 */
void
pm_buffer_clear(pm_buffer_t *buffer) {
    buffer->length = 0;
}

/**
 * Strip the whitespace from the end of the buffer.
 */
void
pm_buffer_rstrip(pm_buffer_t *buffer) {
    while (buffer->length > 0 && pm_char_is_whitespace((uint8_t) buffer->value[buffer->length - 1])) {
        buffer->length--;
    }
}

/**
 * Free the memory held by the buffer.
 */
void
pm_buffer_cleanup(pm_buffer_t *buffer) {
    xfree_sized(buffer->value, buffer->capacity);
}

/**
 * Free both the memory held by the buffer and the buffer itself.
 */
void
pm_buffer_free(pm_buffer_t *buffer) {
    pm_buffer_cleanup(buffer);
    xfree_sized(buffer, sizeof(pm_buffer_t));
}
