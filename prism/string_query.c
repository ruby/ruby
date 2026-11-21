#include "prism/string_query.h"

#include "prism/internal/assert.h"
#include "prism/internal/char.h"
#include "prism/internal/encoding.h"
#include "prism/internal/options.h"
#include "prism/internal/parser.h"

#include <string.h>

/** The category of slice returned from pm_slice_type. */
typedef enum {
    /** Returned when the given version is invalid. */
    PM_SLICE_TYPE_ERROR_VERSION = -2,

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
 * Check that the slice is a valid local variable name or constant, in the
 * given version of Ruby. The version is read as pm_options_version_set reads
 * it, and NULL is the latest version.
 */
static pm_slice_type_t
pm_slice_type(const uint8_t *source, size_t length, const char *encoding_name, const char *version) {
    // first, get the right encoding object
    const pm_encoding_t *encoding = pm_encoding_find((const uint8_t *) encoding_name, (const uint8_t *) (encoding_name + strlen(encoding_name)));
    if (encoding == NULL) return PM_SLICE_TYPE_ERROR;

    /* Then the version of Ruby, which decides which letters are uppercase. */
    pm_options_version_t target;
    if (!pm_options_version_parse(version, version == NULL ? 0 : strlen(version), &target)) return PM_SLICE_TYPE_ERROR_VERSION;

    // check that there is at least one character
    if (length == 0) return PM_SLICE_TYPE_NONE;

    /* A name starts with an ASCII letter, an underscore, or any valid character
     * that is not ASCII. */
    size_t width;
    if (*source >= 0x80) {
        if ((width = pm_encoding_char_width(encoding, source, (ptrdiff_t) length)) == 0) return PM_SLICE_TYPE_NONE;
    } else if (pm_encoding_ascii_alpha_p(*source) || (*source == '_')) {
        width = 1;
    } else {
        return PM_SLICE_TYPE_NONE;
    }

    // determine the type of the slice based on the first character
    const uint8_t *end = source + length;
    pm_slice_type_t result = pm_encoding_isupper_char(encoding, source, end - source, target) ? PM_SLICE_TYPE_CONSTANT : PM_SLICE_TYPE_LOCAL;

    /* The rest of a name is ASCII letters, digits, and underscores, and any
     * valid characters that are not ASCII. */
    source += width;

    while (source < end) {
        if (*source >= 0x80) {
            if ((width = pm_encoding_char_width(encoding, source, end - source)) == 0) break;
            source += width;
        } else if (pm_encoding_ascii_alnum_p(*source) || (*source == '_')) {
            source++;
        } else {
            break;
        }
    }

    // accept a ! or ? at the end of the slice as a method name
    if (source < end && (*source == '!' || *source == '?' || *source == '=')) {
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
pm_string_query_local(const uint8_t *source, size_t length, const char *encoding_name, const char *version) {
    switch (pm_slice_type(source, length, encoding_name, version)) {
        case PM_SLICE_TYPE_ERROR_VERSION:
            return PM_STRING_QUERY_ERROR_VERSION;
        case PM_SLICE_TYPE_ERROR:
            return PM_STRING_QUERY_ERROR;
        case PM_SLICE_TYPE_NONE:
        case PM_SLICE_TYPE_CONSTANT:
        case PM_SLICE_TYPE_METHOD_NAME:
            return PM_STRING_QUERY_FALSE;
        case PM_SLICE_TYPE_LOCAL:
            return PM_STRING_QUERY_TRUE;
    }

    PRISM_ASSERT(false && "unreachable");
    return PM_STRING_QUERY_FALSE;
}

/**
 * Check that the slice is a valid constant name.
 */
pm_string_query_t
pm_string_query_constant(const uint8_t *source, size_t length, const char *encoding_name, const char *version) {
    switch (pm_slice_type(source, length, encoding_name, version)) {
        case PM_SLICE_TYPE_ERROR_VERSION:
            return PM_STRING_QUERY_ERROR_VERSION;
        case PM_SLICE_TYPE_ERROR:
            return PM_STRING_QUERY_ERROR;
        case PM_SLICE_TYPE_NONE:
        case PM_SLICE_TYPE_LOCAL:
        case PM_SLICE_TYPE_METHOD_NAME:
            return PM_STRING_QUERY_FALSE;
        case PM_SLICE_TYPE_CONSTANT:
            return PM_STRING_QUERY_TRUE;
    }

    PRISM_ASSERT(false && "unreachable");
    return PM_STRING_QUERY_FALSE;
}

/**
 * Check that the slice is a valid method name.
 */
pm_string_query_t
pm_string_query_method_name(const uint8_t *source, size_t length, const char *encoding_name, const char *version) {
#define B(p) ((p) ? PM_STRING_QUERY_TRUE : PM_STRING_QUERY_FALSE)
#define C1(c) (*source == c)
#define C2(s) (memcmp(source, s, 2) == 0)
#define C3(s) (memcmp(source, s, 3) == 0)

    switch (pm_slice_type(source, length, encoding_name, version)) {
        case PM_SLICE_TYPE_ERROR_VERSION:
            return PM_STRING_QUERY_ERROR_VERSION;
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

/**
 * Check that the slice is a keyword. Keywords are spelled in ASCII, so any
 * ASCII-compatible encoding spells them with the same bytes. Every version of
 * Ruby that prism supports has the same keywords, but the version must still
 * be valid.
 */
pm_string_query_t
pm_string_query_keyword(const uint8_t *source, size_t length, const char *encoding_name, const char *version) {
    if (pm_encoding_find((const uint8_t *) encoding_name, (const uint8_t *) (encoding_name + strlen(encoding_name))) == NULL) {
        return PM_STRING_QUERY_ERROR;
    }

    if (version != NULL && !pm_options_version_supported_p(version, strlen(version))) {
        return PM_STRING_QUERY_ERROR_VERSION;
    }

    return pm_keyword_p(source, source + length) ? PM_STRING_QUERY_TRUE : PM_STRING_QUERY_FALSE;
}
