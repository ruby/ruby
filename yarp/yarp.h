#ifndef YARP_H
#define YARP_H

#include "yarp/defines.h"
#include "yarp/ast.h"
#include "yarp/diagnostic.h"
#include "yarp/node.h"
#include "yarp/pack.h"
#include "yarp/parser.h"
#include "yarp/regexp.h"
#include "yarp/unescape.h"
#include "yarp/util/yp_buffer.h"
#include "yarp/util/yp_char.h"
#include "yarp/util/yp_memchr.h"
#include "yarp/util/yp_strpbrk.h"
#include "yarp/version.h"

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

void yp_serialize_content(yp_parser_t *parser, yp_node_t *node, yp_buffer_t *buffer);

void yp_print_node(yp_parser_t *parser, yp_node_t *node);

void yp_parser_metadata(yp_parser_t *parser, const char *metadata);

// Generate a scope node from the given node.
void yp_scope_node_init(yp_node_t *node, yp_scope_node_t *dest);

// The YARP version and the serialization format.
YP_EXPORTED_FUNCTION const char * yp_version(void);

// Initialize a parser with the given start and end pointers.
YP_EXPORTED_FUNCTION void yp_parser_init(yp_parser_t *parser, const uint8_t *source, size_t size, const char *filepath);

// Register a callback that will be called whenever YARP changes the encoding it
// is using to parse based on the magic comment.
YP_EXPORTED_FUNCTION void yp_parser_register_encoding_changed_callback(yp_parser_t *parser, yp_encoding_changed_callback_t callback);

// Register a callback that will be called when YARP encounters a magic comment
// with an encoding referenced that it doesn't understand. The callback should
// return NULL if it also doesn't understand the encoding or it should return a
// pointer to a yp_encoding_t struct that contains the functions necessary to
// parse identifiers.
YP_EXPORTED_FUNCTION void yp_parser_register_encoding_decode_callback(yp_parser_t *parser, yp_encoding_decode_callback_t callback);

// Free any memory associated with the given parser.
YP_EXPORTED_FUNCTION void yp_parser_free(yp_parser_t *parser);

// Parse the Ruby source associated with the given parser and return the tree.
YP_EXPORTED_FUNCTION yp_node_t * yp_parse(yp_parser_t *parser);

// Pretty-prints the AST represented by the given node to the given buffer.
YP_EXPORTED_FUNCTION void yp_prettyprint(yp_parser_t *parser, yp_node_t *node, yp_buffer_t *buffer);

// Serialize the AST represented by the given node to the given buffer.
YP_EXPORTED_FUNCTION void yp_serialize(yp_parser_t *parser, yp_node_t *node, yp_buffer_t *buffer);

// Parse the given source to the AST and serialize the AST to the given buffer.
YP_EXPORTED_FUNCTION void yp_parse_serialize(const uint8_t *source, size_t size, yp_buffer_t *buffer, const char *metadata);

// Lex the given source and serialize to the given buffer.
YP_EXPORTED_FUNCTION void yp_lex_serialize(const uint8_t *source, size_t size, const char *filepath, yp_buffer_t *buffer);

// Parse and serialize both the AST and the tokens represented by the given
// source to the given buffer.
YP_EXPORTED_FUNCTION void yp_parse_lex_serialize(const uint8_t *source, size_t size, yp_buffer_t *buffer, const char *metadata);

// Returns a string representation of the given token type.
YP_EXPORTED_FUNCTION const char * yp_token_type_to_str(yp_token_type_t token_type);

#endif
