/**
 * @file regexp.h
 *
 * A regular expression parser.
 */
#ifndef PRISM_REGEXP_H
#define PRISM_REGEXP_H

#include "prism/defines.h"
#include "prism/parser.h"
#include "prism/encoding.h"
#include "prism/util/pm_memchr.h"
#include "prism/util/pm_string.h"

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

/**
 * This callback is called when a named capture group is found.
 */
typedef void (*pm_regexp_name_callback_t)(const pm_string_t *name, void *data);

/**
 * Parse a regular expression.
 *
 * @param parser The parser that is currently being used.
 * @param source The source code to parse.
 * @param size The size of the source code.
 * @param name_callback The callback to call when a named capture group is found.
 * @param name_data The data to pass to the name callback.
 */
PRISM_EXPORTED_FUNCTION void pm_regexp_parse(pm_parser_t *parser, const uint8_t *source, size_t size, pm_regexp_name_callback_t name_callback, void *name_data);

#endif
