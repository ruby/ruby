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
#include "prism/compiler/nonnull.h"

#include "prism/buffer.h"
#include "prism/errors_format.h"
#include "prism/parser.h"
#include "prism/source.h"
#include "prism/stream.h"

/**
 * Serialize the AST represented by the given node to the given buffer.
 *
 * @param parser The parser to serialize.
 * @param node The node to serialize.
 * @param buffer The buffer to serialize to.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize(pm_parser_t *parser, pm_node_t *node, pm_buffer_t *buffer) PRISM_NONNULL(1, 2, 3);

/**
 * Parse the given source to the AST and dump the AST to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data) PRISM_NONNULL(1, 2);

/**
 * Parse and serialize the AST represented by the given source into the given
 * buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_stream(pm_buffer_t *buffer, pm_source_t *source, const char *data) PRISM_NONNULL(1, 2);

/**
 * Parse and serialize the comments in the given source to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_comments(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data) PRISM_NONNULL(1, 2);

/**
 * Lex the given source and serialize to the given buffer.
 *
 * @param source The source to lex.
 * @param size The size of the source.
 * @param buffer The buffer to serialize to.
 * @param data The optional data to pass to the lexer.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_lex(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data) PRISM_NONNULL(1, 2);

/**
 * Parse and serialize both the AST and the tokens represented by the given
 * source to the given buffer.
 *
 * @param buffer The buffer to serialize to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 */
PRISM_EXPORTED_FUNCTION void pm_serialize_parse_lex(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data) PRISM_NONNULL(1, 2);

/**
 * Parse the source and return true if it parses without errors or warnings.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 * @returns True if the source parses without errors or warnings.
 */
PRISM_EXPORTED_FUNCTION bool pm_serialize_parse_success_p(const uint8_t *source, size_t size, const char *data) PRISM_NONNULL(1);

/**
 * Parse the given source and format any errors that are encountered into the
 * given buffer using the given format type. If the source parses without any
 * errors, then -1 is returned and the buffer is left empty. Otherwise, the
 * name of the encoding of the source is written to the buffer, followed by a
 * null byte, followed by the formatted errors, and the error level of the
 * error with the highest precedence is returned.
 *
 * @param buffer The buffer to write the encoding name and formatted errors to.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 * @param format_type The type of formatting to use when formatting the errors.
 * @returns The error level of the error with the highest precedence, or -1 if
 *   the source parsed without errors.
 */
PRISM_EXPORTED_FUNCTION int8_t pm_serialize_parse_errors_format(pm_buffer_t *buffer, const uint8_t *source, size_t size, const char *data, pm_errors_format_type_t format_type) PRISM_NONNULL(1, 2);

#endif

#endif
