#include "prism/internal/stringy.h"

#include <assert.h>
#include <string.h>

/**
 * Initialize a shared string that is based on initial input.
 */
void
pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end) {
    assert(start <= end);

    *string = (pm_string_t) {
        .source = start,
        .length = (size_t) (end - start)
    };
}

/**
 * Initialize a string that views the given bytes.
 */
void
pm_string_init(pm_string_t *string, const uint8_t *source, size_t length) {
    *string = (pm_string_t) { .source = source, .length = length };
}

/**
 * Compare the underlying lengths and bytes of two strings. Returns 0 if the
 * strings are equal, a negative number if the left string is less than the
 * right string, and a positive number if the left string is greater than the
 * right string.
 */
int
pm_string_compare(const pm_string_t *left, const pm_string_t *right) {
    size_t left_length = pm_string_length(left);
    size_t right_length = pm_string_length(right);

    if (left_length < right_length) {
        return -1;
    } else if (left_length > right_length) {
        return 1;
    }

    return memcmp(pm_string_source(left), pm_string_source(right), left_length);
}

/**
 * Returns the length associated with the string.
 */
size_t
pm_string_length(const pm_string_t *string) {
    return string->length;
}

/**
 * Returns the start pointer associated with the string.
 */
const uint8_t *
pm_string_source(const pm_string_t *string) {
    return string->source;
}
