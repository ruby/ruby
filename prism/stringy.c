#include "prism/internal/stringy.h"

#include "prism/internal/allocator.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

/**
 * Initialize a shared string that is based on initial input.
 */
void
pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end) {
    assert(start <= end);

    *string = (pm_string_t) {
        .type = PM_STRING_SHARED,
        .source = start,
        .length = (size_t) (end - start)
    };
}

/**
 * Initialize an owned string that is responsible for freeing allocated memory.
 */
void
pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length) {
    *string = (pm_string_t) {
        .type = PM_STRING_OWNED,
        .source = source,
        .length = length
    };
}

/**
 * Initialize a constant string that doesn't own its memory source.
 */
void
pm_string_constant_init(pm_string_t *string, const char *source, size_t length) {
    *string = (pm_string_t) {
        .type = PM_STRING_CONSTANT,
        .source = (const uint8_t *) source,
        .length = length
    };
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

/**
 * Free the associated memory of the given string.
 */
void
pm_string_cleanup(pm_string_t *string) {
    if (string->type == PM_STRING_OWNED) {
        xfree_sized((void *) string->source, string->length);
    }
}
