#ifndef PRISM_UNESCAPE_H
#define PRISM_UNESCAPE_H

#include "prism/defines.h"
#include "prism/diagnostic.h"
#include "prism/parser.h"
#include "prism/util/pm_char.h"
#include "prism/util/pm_list.h"
#include "prism/util/pm_memchr.h"
#include "prism/util/pm_string.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// The type of unescape we are performing.
typedef enum {
    // When we're creating a string inside of a list literal like %w, we
    // shouldn't escape anything.
    PM_UNESCAPE_NONE,

    // When we're unescaping a single-quoted string, we only need to unescape
    // single quotes and backslashes.
    PM_UNESCAPE_MINIMAL,

    // When we're unescaping a string list, in addition to MINIMAL, we need to
    // unescape whitespace.
    PM_UNESCAPE_WHITESPACE,

    // When we're unescaping a double-quoted string, we need to unescape all
    // escapes.
    PM_UNESCAPE_ALL,
} pm_unescape_type_t;

// Unescape the contents of the given token into the given string using the given unescape mode.
PRISM_EXPORTED_FUNCTION void pm_unescape_manipulate_string(pm_parser_t *parser, pm_string_t *string, pm_unescape_type_t unescape_type);
void pm_unescape_manipulate_char_literal(pm_parser_t *parser, pm_string_t *string, pm_unescape_type_t unescape_type);

// Accepts a source string and a type of unescaping and returns the unescaped version.
// The caller must pm_string_free(result); after calling this function.
PRISM_EXPORTED_FUNCTION bool pm_unescape_string(const uint8_t *start, size_t length, pm_unescape_type_t unescape_type, pm_string_t *result);

// Returns the number of bytes that encompass the first escape sequence in the
// given string.
size_t pm_unescape_calculate_difference(pm_parser_t *parser, const uint8_t *value, pm_unescape_type_t unescape_type, bool expect_single_codepoint);

#endif
