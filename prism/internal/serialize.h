/**
 * @file internal/serialize.h
 */
#ifndef PRISM_INTERNAL_SERIALIZE_H
#define PRISM_INTERNAL_SERIALIZE_H

#include "prism/internal/encoding.h"
#include "prism/internal/list.h"

#include "prism/ast.h"
#include "prism/buffer.h"
#include "prism/excludes.h"
#include "prism/parser.h"

/* We optionally support serializing to a binary string. For systems that do not
 * want or need this functionality, it can be turned off with the
 * PRISM_EXCLUDE_SERIALIZATION define. */
#ifndef PRISM_EXCLUDE_SERIALIZATION

/**
 * Serialize the given list of comments to the given buffer.
 *
 * @param list The list of comments to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_comment_list(pm_list_t *list, pm_buffer_t *buffer);

/**
 * Serialize the name of the encoding to the buffer.
 *
 * @param encoding The encoding to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_encoding(const pm_encoding_t *encoding, pm_buffer_t *buffer);

/**
 * Serialize the encoding, metadata, nodes, and constant pool.
 *
 * @param parser The parser to serialize.
 * @param node The node to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_content(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

#endif

#endif
