#include "yarp/util/yp_memchr.h"

#define YP_MEMCHR_TRAILING_BYTE_MINIMUM 0x40

// We need to roll our own memchr to handle cases where the encoding changes and
// we need to search for a character in a buffer that could be the trailing byte
// of a multibyte character.
void *
yp_memchr(yp_parser_t *parser, const void *memory, int character, size_t number) {
    if (parser->encoding_changed && parser->encoding.multibyte && character >= YP_MEMCHR_TRAILING_BYTE_MINIMUM) {
        const char *source = (const char *) memory;
        size_t index = 0;

        while (index < number) {
            if (source[index] == character) {
                return (void *) (source + index);
            }

            size_t width = parser->encoding.char_width(source + index);
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
