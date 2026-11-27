#ifndef PRISM_INTERNAL_TOKENS_H
#define PRISM_INTERNAL_TOKENS_H

#include "prism/ast.h"
#include "prism/stringy.h"

/*
 * Return the name used for the token type in diagnostics.
 */
pm_string_t pm_token_string(pm_token_type_t token_type);

#endif
