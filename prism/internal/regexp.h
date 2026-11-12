#ifndef PRISM_INTERNAL_REGEXP_H
#define PRISM_INTERNAL_REGEXP_H

#include "prism/ast.h"
#include "prism/internal/parser.h"

/*
 * Callback invoked by pm_regexp_parse_named_captures() for each named capture
 * group found. The data pointer is whatever the caller passed in alongside the
 * callback; the regexp parser passes it through without inspecting it.
 */
typedef void (*pm_regexp_name_callback_t)(pm_parser_t *parser, const pm_string_t *name, void *data);

/*
 * Parse a regular expression and validate its encoding. The offsets are where
 * the unescaped content of the node stops lining up with the source, as the
 * lexer recorded them. Returns the encoding flags to set on the node.
 */
PRISM_EXPORTED_FUNCTION pm_node_flags_t pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, const pm_regexp_offsets_t *offsets);

/*
 * Parse the content of a regular expression for named capture groups only.
 * No errors are reported.
 */
void pm_regexp_parse_named_captures(pm_parser_t *parser, const uint8_t *source, size_t size, bool extended_mode, pm_regexp_name_callback_t name_callback, void *name_data);

#endif
