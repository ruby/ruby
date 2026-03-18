/**
 * @file internal/tokens.h
 */
#ifndef PRISM_INTERNAL_TOKENS_H
#define PRISM_INTERNAL_TOKENS_H

#include "prism/ast.h"

/**
 * Returns the human name of the given token type.
 *
 * @param token_type The token type to convert to a human name.
 * @return The human name of the given token type.
 */
const char * pm_token_str(pm_token_type_t token_type);

#endif
