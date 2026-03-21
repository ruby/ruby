/**
 * @file string_query.h
 *
 * Functions for querying properties of strings, such as whether they are valid
 * local variable names, constant names, or method names.
 */
#ifndef PRISM_STRING_QUERY_H
#define PRISM_STRING_QUERY_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

/**
 * Represents the results of a slice query.
 */
typedef enum {
    /** Returned if the encoding given to a slice query was invalid. */
    PM_STRING_QUERY_ERROR = -1,

    /** Returned if the result of the slice query is false. */
    PM_STRING_QUERY_FALSE,

    /** Returned if the result of the slice query is true. */
    PM_STRING_QUERY_TRUE
} pm_string_query_t;

/**
 * Check that the slice is a valid local variable name.
 *
 * @param source The source to check.
 * @param length The length of the source.
 * @param encoding_name The name of the encoding of the source.
 * @returns PM_STRING_QUERY_TRUE if the query is true, PM_STRING_QUERY_FALSE if
 *   the query is false, and PM_STRING_QUERY_ERROR if the encoding was invalid.
 */
PRISM_EXPORTED_FUNCTION pm_string_query_t pm_string_query_local(const uint8_t *source, size_t length, const char *encoding_name) PRISM_NONNULL(1, 3);

/**
 * Check that the slice is a valid constant name.
 *
 * @param source The source to check.
 * @param length The length of the source.
 * @param encoding_name The name of the encoding of the source.
 * @returns PM_STRING_QUERY_TRUE if the query is true, PM_STRING_QUERY_FALSE if
 *   the query is false, and PM_STRING_QUERY_ERROR if the encoding was invalid.
 */
PRISM_EXPORTED_FUNCTION pm_string_query_t pm_string_query_constant(const uint8_t *source, size_t length, const char *encoding_name) PRISM_NONNULL(1, 3);

/**
 * Check that the slice is a valid method name.
 *
 * @param source The source to check.
 * @param length The length of the source.
 * @param encoding_name The name of the encoding of the source.
 * @returns PM_STRING_QUERY_TRUE if the query is true, PM_STRING_QUERY_FALSE if
 *   the query is false, and PM_STRING_QUERY_ERROR if the encoding was invalid.
 */
PRISM_EXPORTED_FUNCTION pm_string_query_t pm_string_query_method_name(const uint8_t *source, size_t length, const char *encoding_name) PRISM_NONNULL(1, 3);

#endif
