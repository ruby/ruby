/**
 * @file prettyprint.h
 *
 * An AST node pretty-printer.
 */
#ifndef PRISM_PRETTYPRINT_H
#define PRISM_PRETTYPRINT_H

#include "prism/excludes.h"

#ifdef PRISM_EXCLUDE_PRETTYPRINT

#define pm_prettyprint(output_buffer_, parser_, node_)

#else

#include "prism/ast.h"
#include "prism/buffer.h"
#include "prism/parser.h"

/**
 * Pretty-prints the AST represented by the given node to the given buffer.
 *
 * @param output_buffer The buffer to write the pretty-printed AST to.
 * @param parser The parser that parsed the AST.
 * @param node The root node of the AST to pretty-print.
 */
PRISM_EXPORTED_FUNCTION void pm_prettyprint(pm_buffer_t *output_buffer, const pm_parser_t *parser, const pm_node_t *node);

#endif

#endif
