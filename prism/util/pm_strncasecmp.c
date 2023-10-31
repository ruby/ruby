#include "prism/util/pm_strncasecmp.h"

/**
 * Compare two strings, ignoring case, up to the given length. Returns 0 if the
 * strings are equal, a negative number if string1 is less than string2, or a
 * positive number if string1 is greater than string2.
 *
 * Note that this is effectively our own implementation of strncasecmp, but it's
 * not available on all of the platforms we want to support so we're rolling it
 * here.
 */
int
pm_strncasecmp(const uint8_t *string1, const uint8_t *string2, size_t length) {
    size_t offset = 0;
    int difference = 0;

    while (offset < length && string1[offset] != '\0') {
        if (string2[offset] == '\0') return string1[offset];
        if ((difference = tolower(string1[offset]) - tolower(string2[offset])) != 0) return difference;
        offset++;
    }

    return difference;
}
