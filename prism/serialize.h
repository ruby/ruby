/**
 * @file serialize.h
 *
 * The functions related to serializing the AST to a binary format.
 */
#ifndef PRISM_SERIALIZE_H
#define PRISM_SERIALIZE_H

#include "prism/excludes.h"

/* We optionally support serializing to a binary string. For systems that do not
 * want or need this functionality, it can be turned off with the
 * PRISM_EXCLUDE_SERIALIZATION define. */
#ifndef PRISM_EXCLUDE_SERIALIZATION

#include "prism/compiler/exported.h"

#include "prism/buffer.h"
#include "prism/parser.h"
#include "prism/stream.h"

/**
 * Serialize the AST represented by the given node to the given buffer.
 *
 * @param parser The parser to serialize.
 * @param node The node to serialize.
 * @param buffer The buffer to serialize to.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer);

/**
 * Parse the given source to the AST and dump the AST to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data);

/**
 * Parse and serialize the AST represented by the source that is read out of the
 * given stream into to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param stream The stream to parse.
 * @param stream_fgets The function to use to read from the stream.
 * @param stream_feof The function to use to tell if the stream has hit eof.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_stream(pm_buffer_t *buffer, void *stream, pm_parse_stream_fgets_t *stream_fgets, pm_parse_stream_feof_t *stream_feof, const char *data);

/**
 * Parse and serialize the comments in the given source to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_comments(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data);

/**
 * Lex the given source and serialize to the given buffer.
 *
 * @param source The source to lex.
 * @param size The size of the source.
 * @param buffer The buffer to serialize to.
 * @param data The optional data to pass to the lexer.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_lex(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data);

/**
 * Parse and serialize both the AST and the tokens represented by the given
 * source to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_lex(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data);

/**
 * Parse the source and return true if it parses without errors or warnings.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 * @return True if the source parses without errors or warnings.
 */
PRISM_EXPORTED_FUNCTION bool pm_serialize_parse_success_p(const uint8_t *source, size_t size, const char *data);

#endif

#endif
