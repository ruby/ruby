#ifndef PRISM_PRETTYPRINT_H
#define PRISM_PRETTYPRINT_H

#include "prism/defines.h"

#include <stdio.h>

#include "prism/ast.h"
#include "prism/parser.h"
#include "prism/util/pm_buffer.h"

// Pretty-prints the AST represented by the given node to the given buffer.
PRISM_EXPORTED_FUNCTION void pm_prettyprint(pm_buffer_t *output_buffer, const pm_parser_t *parser, const pm_node_t *node);

#endif
