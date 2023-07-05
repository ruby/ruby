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

// Unescape the contents of the given token into the given string using the
// given unescape mode.
YP_EXPORTED_FUNCTION void yp_unescape_manipulate_string(yp_parser_t *parser, const char *value, size_t length, yp_string_t *string, yp_unescape_type_t unescape_type, yp_list_t *error_list);

YP_EXPORTED_FUNCTION size_t yp_unescape_calculate_difference(const char *value, const char *end, yp_unescape_type_t unescape_type, bool expect_single_codepoint, yp_list_t *error_list);

#endif
