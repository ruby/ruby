/**
 * @file stream.h
 *
 * Functions for parsing streams.
 */
#ifndef PRISM_STREAM_H
#define PRISM_STREAM_H

#include "prism/compiler/exported.h"

#include "prism/arena.h"
#include "prism/buffer.h"
#include "prism/options.h"
#include "prism/parser.h"

/**
 * This function is used in pm_parse_stream() to retrieve a line of input from a
 * stream. It closely mirrors that of fgets so that fgets can be used as the
 * default implementation.
 */
typedef char * (pm_parse_stream_fgets_t)(char *string, int size, void *stream);

/**
 * This function is used in pm_parse_stream to check whether a stream is EOF.
 * It closely mirrors that of feof so that feof can be used as the
 * default implementation.
 */
typedef int (pm_parse_stream_feof_t)(void *stream);

/**
 * Parse a stream of Ruby source and return the tree.
 *
 * @param parser The out parameter to write the parser to.
 * @param arena The arena to use for all AST-lifetime allocations.
 * @param buffer The buffer to use.
 * @param stream The stream to parse.
 * @param stream_fgets The function to use to read from the stream.
 * @param stream_feof The function to use to determine if the stream has hit eof.
 * @param options The optional options to use when parsing.
 * @return The AST representing the source.
 */
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse_stream(pm_parser_t **parser, pm_arena_t *arena, pm_buffer_t *buffer, void *stream, pm_parse_stream_fgets_t *stream_fgets, pm_parse_stream_feof_t *stream_feof, const pm_options_t *options);

#endif
