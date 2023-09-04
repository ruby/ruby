#ifndef YARP_UNESCAPE_H
#define YARP_UNESCAPE_H

#include "yarp/defines.h"
#include "yarp/diagnostic.h"
#include "yarp/parser.h"
#include "yarp/util/yp_char.h"
#include "yarp/util/yp_list.h"
#include "yarp/util/yp_memchr.h"
#include "yarp/util/yp_string.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// The type of unescape we are performing.
typedef enum {
    // When we're creating a string inside of a list literal like %w, we
    // shouldn't escape anything.
    YP_UNESCAPE_NONE,

    // When we're unescaping a single-quoted string, we only need to unescape
    // single quotes and backslashes.
    YP_UNESCAPE_MINIMAL,

    // When we're unescaping a double-quoted string, we need to unescape all
    // escapes.
    YP_UNESCAPE_ALL
} yp_unescape_type_t;

// Unescape the contents of the given token into the given string using the given unescape mode.
YP_EXPORTED_FUNCTION void yp_unescape_manipulate_string(yp_parser_t *parser, yp_string_t *string, yp_unescape_type_t unescape_type);
void yp_unescape_manipulate_char_literal(yp_parser_t *parser, yp_string_t *string, yp_unescape_type_t unescape_type);

// Accepts a source string and a type of unescaping and returns the unescaped version.
// The caller must yp_string_free(result); after calling this function.
YP_EXPORTED_FUNCTION bool yp_unescape_string(const uint8_t *start, size_t length, yp_unescape_type_t unescape_type, yp_string_t *result);

// Returns the number of bytes that encompass the first escape sequence in the
// given string.
size_t yp_unescape_calculate_difference(yp_parser_t *parser, const uint8_t *value, yp_unescape_type_t unescape_type, bool expect_single_codepoint);

#endif
