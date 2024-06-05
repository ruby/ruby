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
#include "prism/util/pm_string_list.h"
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
 * @param source The source code to parse.
 * @param size The size of the source code.
 * @param encoding_changed Whether or not the encoding changed from the default.
 * @param encoding The encoding of the source code.
 * @param name_callback The callback to call when a named capture group is found.
 * @param name_data The data to pass to the name callback.
 * @return Whether or not the parsing was successful.
 */
PRISM_EXPORTED_FUNCTION bool pm_regexp_parse(const uint8_t *source, size_t size, bool encoding_changed, const pm_encoding_t *encoding, pm_regexp_name_callback_t name_callback, void *name_data);

#endif
