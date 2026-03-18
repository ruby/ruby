/**
 * @file json.h
 */
#ifndef PRISM_JSON_H
#define PRISM_JSON_H

#include "prism/excludes.h"

/* We optionally support dumping to JSON. For systems that don't want or need
 * this functionality, it can be turned off with the PRISM_EXCLUDE_JSON define.
 */
#ifndef PRISM_EXCLUDE_JSON

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include "prism/ast.h"
#include "prism/buffer.h"
#include "prism/parser.h"

/**
 * Dump JSON to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param parser The parser that parsed the node.
 * @param node The node to serialize.
 */
PRISM_EXPORTED_FUNCTION void pm_dump_json(pm_buffer_t *buffer, const pm_parser_t *parser, const pm_node_t *node) PRISM_NONNULL(1, 2, 3);

#endif

#endif
