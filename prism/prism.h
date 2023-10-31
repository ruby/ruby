#ifndef PRISM_H
#define PRISM_H

#include "prism/defines.h"
#include "prism/util/pm_buffer.h"
#include "prism/util/pm_char.h"
#include "prism/util/pm_memchr.h"
#include "prism/util/pm_strncasecmp.h"
#include "prism/util/pm_strpbrk.h"
#include "prism/ast.h"
#include "prism/diagnostic.h"
#include "prism/node.h"
#include "prism/pack.h"
#include "prism/parser.h"
#include "prism/prettyprint.h"
#include "prism/regexp.h"
#include "prism/version.h"

#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <strings.h>
#endif

/**
 * The prism version and the serialization format.
 *
 * @returns The prism version as a constant string.
 */
PRISM_EXPORTED_FUNCTION const char * pm_version(void);

/**
 * Initialize a parser with the given start and end pointers.
 *
 * @param parser The parser to initialize.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param filepath The optional filepath to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_init(pm_parser_t *parser, const uint8_t *source, size_t size, const char *filepath);

/**
 * Register a callback that will be called whenever prism changes the encoding
 * it is using to parse based on the magic comment.
 *
 * @param parser The parser to register the callback with.
 * @param callback The callback to register.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_register_encoding_changed_callback(pm_parser_t *parser, pm_encoding_changed_callback_t callback);

/**
 * Register a callback that will be called when prism encounters a magic comment
 * with an encoding referenced that it doesn't understand. The callback should
 * return NULL if it also doesn't understand the encoding or it should return a
 * pointer to a pm_encoding_t struct that contains the functions necessary to
 * parse identifiers.
 *
 * @param parser The parser to register the callback with.
 * @param callback The callback to register.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_register_encoding_decode_callback(pm_parser_t *parser, pm_encoding_decode_callback_t callback);

/**
 * Free any memory associated with the given parser.
 *
 * @param parser The parser to free.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_free(pm_parser_t *parser);

/**
 * Parse the Ruby source associated with the given parser and return the tree.
 *
 * @param parser The parser to use.
 * @return The AST representing the Ruby source.
 */
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse(pm_parser_t *parser);

/**
 * Serialize the given list of comments to the given buffer.
 *
 * @param parser The parser to serialize.
 * @param list The list of comments to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_comment_list(pm_parser_t *parser, pm_list_t *list, pm_buffer_t *buffer);

/**
 * Serialize the name of the encoding to the buffer.
 *
 * @param encoding The encoding to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_encoding(pm_encoding_t *encoding, pm_buffer_t *buffer);

/**
 * Serialize the encoding, metadata, nodes, and constant pool.
 *
 * @param parser The parser to serialize.
 * @param node The node to serialize.
 * @param buffer The buffer to serialize to.
 */
void pm_serialize_content(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

/**
 * Serialize the AST represented by the given node to the given buffer.
 *
 * @param parser The parser to serialize.
 * @param node The node to serialize.
 * @param buffer The buffer to serialize to.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

/**
 * Process any additional metadata being passed into a call to the parser via
 * the pm_parse_serialize function. Since the source of these calls will be from
 * Ruby implementation internals we assume it is from a trusted source.
 *
 * Currently, this is only passing in variable scoping surrounding an eval, but
 * eventually it will be extended to hold any additional metadata.  This data
 * is serialized to reduce the calling complexity for a foreign function call
 * vs a foreign runtime making a bindable in-memory version of a C structure.
 *
 * @param parser The parser to process the metadata for.
 * @param metadata The metadata to process.
 */
void pm_parser_metadata(pm_parser_t *parser, const char *metadata);

/**
 * Parse the given source to the AST and serialize the AST to the given buffer.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param buffer The buffer to serialize to.
 * @param metadata The optional metadata to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_parse_serialize(const uint8_t *source, size_t size, pm_buffer_t *buffer, const char *metadata);

/**
 * Parse and serialize the comments in the given source to the given buffer.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param buffer The buffer to serialize to.
 * @param metadata The optional metadata to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_parse_serialize_comments(const uint8_t *source, size_t size, pm_buffer_t *buffer, const char *metadata);

/**
 * Lex the given source and serialize to the given buffer.
 *
 * @param source The source to lex.
 * @param size The size of the source.
 * @param filepath The optional filepath to pass to the lexer.
 * @param buffer The buffer to serialize to.
 */
PRISM_EXPORTED_FUNCTION void pm_lex_serialize(const uint8_t *source, size_t size, const char *filepath, pm_buffer_t *buffer);

/**
 * Parse and serialize both the AST and the tokens represented by the given
 * source to the given buffer.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param buffer The buffer to serialize to.
 * @param metadata The optional metadata to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_parse_lex_serialize(const uint8_t *source, size_t size, pm_buffer_t *buffer, const char *metadata);

/**
 * Returns a string representation of the given token type.
 *
 * @param token_type The token type to convert to a string.
 * @return A string representation of the given token type.
 */
PRISM_EXPORTED_FUNCTION const char * pm_token_type_to_str(pm_token_type_t token_type);

#endif
