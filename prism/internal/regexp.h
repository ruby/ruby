#ifndef PRISM_INTERNAL_REGEXP_H
#define PRISM_INTERNAL_REGEXP_H

#include "prism/ast.h"
#include "prism/parser.h"

/*
 * Callback invoked by pm_regexp_parse() for each named capture group found.
 * The data pointer is whatever the caller passed in alongside the callback; the
 * regexp parser passes it through without inspecting it.
 */
typedef void (*pm_regexp_name_callback_t)(pm_parser_t *parser, const pm_string_t *name, void *data);

/*
 * Parse a regular expression, validate its encoding, and optionally extract
 * named capture groups. Returns the encoding flags to set on the node.
 */
PRISM_EXPORTED_FUNCTION pm_node_flags_t pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, pm_regexp_name_callback_t name_callback, void *name_data);

/*
 * Parse an interpolated regular expression for named capture groups only.
 * No encoding validation is performed.
 */
void pm_regexp_parse_named_captures(pm_parser_t *parser, const uint8_t *source, size_t size, bool extended_mode, pm_regexp_name_callback_t name_callback, void *name_data);

#endif
