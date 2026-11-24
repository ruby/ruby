#include "prism/internal/memchr.h"

#include <stdint.h>
#include <string.h>

#define TRAILING_BYTE_MINIMUM 0x40

/**
 * Find an ASCII delimiter at a character boundary in the given encoding.
 */
const void *
pm_memchr(const void *memory, int character, size_t number, const pm_encoding_t *encoding) {
    if (encoding != PM_ENCODING_UTF_8_ENTRY && pm_encoding_multibyte_p(encoding) && character >= TRAILING_BYTE_MINIMUM) {
        const uint8_t *source = (const uint8_t *) memory;
        size_t index = 0;

        while (index < number) {
            if (source[index] == character) {
                return source + index;
            }

            size_t width = pm_encoding_char_width(encoding, source + index, (ptrdiff_t) (number - index));
            if (width == 0) {
                return NULL;
            }

            index += width;
        }

        return NULL;
    } else {
        return memchr(memory, character, number);
    }
}
