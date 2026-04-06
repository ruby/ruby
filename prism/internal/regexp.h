#ifndef PRISM_INTERNAL_REGEXP_H
#define PRISM_INTERNAL_REGEXP_H

#include "prism/ast.h"
#include "prism/parser.h"

/*
 * Accumulation state for named capture groups found during regexp parsing.
 * The caller initializes this with the call node and passes it to
 * pm_regexp_parse. The regexp parser populates match and names as groups
 * are found.
 */
typedef struct {
    /* The call node wrapping the regular expression node (for =~). */
    pm_call_node_t *call;

    /* The match write node being built, or NULL if no captures found yet. */
    pm_match_write_node_t *match;

    /* The list of capture names found so far (for deduplication). */
    pm_constant_id_list_t names;
} pm_regexp_name_data_t;

/*
 * Callback invoked by pm_regexp_parse() for each named capture group found.
 */
typedef void (*pm_regexp_name_callback_t)(pm_parser_t *parser, const pm_string_t *name, bool shared, pm_regexp_name_data_t *data);

/*
 * Parse a regular expression, validate its encoding, and optionally extract
 * named capture groups. Returns the encoding flags to set on the node.
 */
PRISM_EXPORTED_FUNCTION pm_node_flags_t pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, pm_regexp_name_callback_t name_callback, pm_regexp_name_data_t *name_data);

/*
 * Parse an interpolated regular expression for named capture groups only.
 * No encoding validation is performed.
 */
void pm_regexp_parse_named_captures(pm_parser_t *parser, const uint8_t *source, size_t size, bool shared, bool extended_mode, pm_regexp_name_callback_t name_callback, pm_regexp_name_data_t *name_data);

#endif
