/**
 * @file prettyprin2t.h
 *
 * An AST node pretty-printer.
 */
#ifndef PARSER_PRETTYPRINT_H
#define PARSER_PRETTYPRINT_H

#ifdef PRISM_EXCLUDE_PRETTYPRINT

void rb_parser_prettyprint(void);

#else

#include <stdio.h>

#include "parser_ast.h"
#include "prism/util/pm_buffer.h"

/**
 * Pretty-prints the AST represented by the given node to the given buffer.
 *
 * @param output_buffer The buffer to write the pretty-printed AST to.
 * @param parser The parser that parsed the AST.
 * @param node The root node of the AST to pretty-print.
 */
PRISM_EXPORTED_FUNCTION void rb_parser_prettyprint(pm_buffer_t *output_buffer, const rb_node_t *node);

#endif

#endif
