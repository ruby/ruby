#ifndef PRISM_H
#define PRISM_H

#include "prism/defines.h"
#include "prism/ast.h"
#include "prism/diagnostic.h"
#include "prism/node.h"
#include "prism/pack.h"
#include "prism/parser.h"
#include "prism/regexp.h"
#include "prism/util/pm_buffer.h"
#include "prism/util/pm_char.h"
#include "prism/util/pm_memchr.h"
#include "prism/util/pm_strpbrk.h"
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

void pm_serialize_content(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

void pm_print_node(pm_parser_t *parser, pm_node_t *node);

void pm_parser_metadata(pm_parser_t *parser, const char *metadata);

// Generate a scope node from the given node.
void pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous, pm_parser_t *parser);

// The prism version and the serialization format.
PRISM_EXPORTED_FUNCTION const char * pm_version(void);

// Initialize a parser with the given start and end pointers.
PRISM_EXPORTED_FUNCTION void pm_parser_init(pm_parser_t *parser, const uint8_t *source, size_t size, const char *filepath);

// Register a callback that will be called whenever prism changes the encoding it
// is using to parse based on the magic comment.
PRISM_EXPORTED_FUNCTION void pm_parser_register_encoding_changed_callback(pm_parser_t *parser, pm_encoding_changed_callback_t callback);

// Register a callback that will be called when prism encounters a magic comment
// with an encoding referenced that it doesn't understand. The callback should
// return NULL if it also doesn't understand the encoding or it should return a
// pointer to a pm_encoding_t struct that contains the functions necessary to
// parse identifiers.
PRISM_EXPORTED_FUNCTION void pm_parser_register_encoding_decode_callback(pm_parser_t *parser, pm_encoding_decode_callback_t callback);

// Free any memory associated with the given parser.
PRISM_EXPORTED_FUNCTION void pm_parser_free(pm_parser_t *parser);

// Parse the Ruby source associated with the given parser and return the tree.
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse(pm_parser_t *parser);

// Pretty-prints the AST represented by the given node to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_prettyprint(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

// Serialize the AST represented by the given node to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_serialize(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

// Parse the given source to the AST and serialize the AST to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_parse_serialize(const uint8_t *source, size_t size, pm_buffer_t *buffer, const char *metadata);

// Lex the given source and serialize to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_lex_serialize(const uint8_t *source, size_t size, const char *filepath, pm_buffer_t *buffer);

// Parse and serialize both the AST and the tokens represented by the given
// source to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_parse_lex_serialize(const uint8_t *source, size_t size, pm_buffer_t *buffer, const char *metadata);

// Returns a string representation of the given token type.
PRISM_EXPORTED_FUNCTION const char * pm_token_type_to_str(pm_token_type_t token_type);

#endif
