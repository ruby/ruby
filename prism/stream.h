/**
 * @file stream.h
 *
 * Functions for parsing streams.
 */
#ifndef PRISM_STREAM_H
#define PRISM_STREAM_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include "prism/arena.h"
#include "prism/options.h"
#include "prism/parser.h"
#include "prism/source.h"

/**
 * Parse a stream of Ruby source and return the tree.
 *
 * @param parser The out parameter to write the parser to.
 * @param arena The arena to use for all AST-lifetime allocations.
 * @param source The source to use, created via pm_source_stream_new.
 * @param options The optional options to use when parsing.
 * @returns The AST representing the source.
 */
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse_stream(pm_parser_t **parser, pm_arena_t *arena, pm_source_t *source, const pm_options_t *options) PRISM_NONNULL(1, 2, 3);

#endif
