#include <ctype.h>
#include <stddef.h>
#include <stdint.h>

int
yp_strncasecmp(const uint8_t *string1, const uint8_t *string2, size_t length) {
    size_t offset = 0;
    int difference = 0;

    while (offset < length && string1[offset] != '\0') {
        if (string2[offset] == '\0') return string1[offset];
        if ((difference = tolower(string1[offset]) - tolower(string2[offset])) != 0) return difference;
        offset++;
    }

    return difference;
}
