#include <ctype.h>
#include <stddef.h>

int
yp_strncasecmp(const char *string1, const char *string2, size_t length) {
    size_t offset = 0;
    int difference = 0;

    while (offset < length && string1[offset] != '\0') {
        if (string2[offset] == '\0') return string1[offset];

        unsigned char left = (unsigned char) string1[offset];
        unsigned char right = (unsigned char) string2[offset];

        if ((difference = tolower(left) - tolower(right)) != 0) return difference;
        offset++;
    }

    return difference;
}
