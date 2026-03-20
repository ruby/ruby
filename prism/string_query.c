#include "prism/string_query.h"

#include "prism/internal/char.h"
#include "prism/internal/encoding.h"

#include <assert.h>
#include <string.h>

/** The category of slice returned from pm_slice_type. */
typedef enum {
    /** Returned when the given encoding name is invalid. */
    PM_SLICE_TYPE_ERROR = -1,

    /** Returned when no other types apply to the slice. */
    PM_SLICE_TYPE_NONE,

    /** Returned when the slice is a valid local variable name. */
    PM_SLICE_TYPE_LOCAL,

    /** Returned when the slice is a valid constant name. */
    PM_SLICE_TYPE_CONSTANT,

    /** Returned when the slice is a valid method name. */
    PM_SLICE_TYPE_METHOD_NAME
} pm_slice_type_t;

/**
 * Check that the slice is a valid local variable name or constant.
 */
static pm_slice_type_t
pm_slice_type(const uint8_t *source, size_t length, const char *encoding_name) {
    // first, get the right encoding object
    const pm_encoding_t *encoding = pm_encoding_find((const uint8_t *) encoding_name, (const uint8_t *) (encoding_name + strlen(encoding_name)));
    if (encoding == NULL) return PM_SLICE_TYPE_ERROR;

    // check that there is at least one character
    if (length == 0) return PM_SLICE_TYPE_NONE;

    size_t width;
    if ((width = encoding->alpha_char(source, (ptrdiff_t) length)) != 0) {
        // valid because alphabetical
    } else if (*source == '_') {
        // valid because underscore
        width = 1;
    } else if ((*source >= 0x80) && ((width = encoding->char_width(source, (ptrdiff_t) length)) > 0)) {
        // valid because multibyte
    } else {
        // invalid because no match
        return PM_SLICE_TYPE_NONE;
    }

    // determine the type of the slice based on the first character
    const uint8_t *end = source + length;
    pm_slice_type_t result = encoding->isupper_char(source, end - source) ? PM_SLICE_TYPE_CONSTANT : PM_SLICE_TYPE_LOCAL;

    // next, iterate through all of the bytes of the string to ensure that they
    // are all valid identifier characters
    source += width;

    while (source < end) {
        if ((width = encoding->alnum_char(source, end - source)) != 0) {
            // valid because alphanumeric
            source += width;
        } else if (*source == '_') {
            // valid because underscore
            source++;
        } else if ((*source >= 0x80) && ((width = encoding->char_width(source, end - source)) > 0)) {
            // valid because multibyte
            source += width;
        } else {
            // invalid because no match
            break;
        }
    }

    // accept a ! or ? at the end of the slice as a method name
    if (*source == '!' || *source == '?' || *source == '=') {
        source++;
        result = PM_SLICE_TYPE_METHOD_NAME;
    }

    // valid if we are at the end of the slice
    return source == end ? result : PM_SLICE_TYPE_NONE;
}

/**
 * Check that the slice is a valid local variable name.
 */
pm_string_query_t
pm_string_query_local(const uint8_t *source, size_t length, const char *encoding_name) {
    switch (pm_slice_type(source, length, encoding_name)) {
        case PM_SLICE_TYPE_ERROR:
            return PM_STRING_QUERY_ERROR;
        case PM_SLICE_TYPE_NONE:
        case PM_SLICE_TYPE_CONSTANT:
        case PM_SLICE_TYPE_METHOD_NAME:
            return PM_STRING_QUERY_FALSE;
        case PM_SLICE_TYPE_LOCAL:
            return PM_STRING_QUERY_TRUE;
    }

    assert(false && "unreachable");
    return PM_STRING_QUERY_FALSE;
}

/**
 * Check that the slice is a valid constant name.
 */
pm_string_query_t
pm_string_query_constant(const uint8_t *source, size_t length, const char *encoding_name) {
    switch (pm_slice_type(source, length, encoding_name)) {
        case PM_SLICE_TYPE_ERROR:
            return PM_STRING_QUERY_ERROR;
        case PM_SLICE_TYPE_NONE:
        case PM_SLICE_TYPE_LOCAL:
        case PM_SLICE_TYPE_METHOD_NAME:
            return PM_STRING_QUERY_FALSE;
        case PM_SLICE_TYPE_CONSTANT:
            return PM_STRING_QUERY_TRUE;
    }

    assert(false && "unreachable");
    return PM_STRING_QUERY_FALSE;
}

/**
 * Check that the slice is a valid method name.
 */
pm_string_query_t
pm_string_query_method_name(const uint8_t *source, size_t length, const char *encoding_name) {
#define B(p) ((p) ? PM_STRING_QUERY_TRUE : PM_STRING_QUERY_FALSE)
#define C1(c) (*source == c)
#define C2(s) (memcmp(source, s, 2) == 0)
#define C3(s) (memcmp(source, s, 3) == 0)

    switch (pm_slice_type(source, length, encoding_name)) {
        case PM_SLICE_TYPE_ERROR:
            return PM_STRING_QUERY_ERROR;
        case PM_SLICE_TYPE_NONE:
            break;
        case PM_SLICE_TYPE_LOCAL:
            // numbered parameters are not valid method names
            return B((length != 2) || (source[0] != '_') || (source[1] == '0') || !pm_char_is_decimal_digit(source[1]));
        case PM_SLICE_TYPE_CONSTANT:
            // all constants are valid method names
        case PM_SLICE_TYPE_METHOD_NAME:
            // all method names are valid method names
            return PM_STRING_QUERY_TRUE;
    }

    switch (length) {
        case 1:
            return B(C1('&') || C1('`') || C1('!') || C1('^') || C1('>') || C1('<') || C1('-') || C1('%') || C1('|') || C1('+') || C1('/') || C1('*') || C1('~'));
        case 2:
            return B(C2("!=") || C2("!~") || C2("[]") || C2("==") || C2("=~") || C2(">=") || C2(">>") || C2("<=") || C2("<<") || C2("**"));
        case 3:
            return B(C3("===") || C3("<=>") || C3("[]="));
        default:
            return PM_STRING_QUERY_FALSE;
    }

#undef B
#undef C1
#undef C2
#undef C3
}
