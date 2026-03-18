/**
 * @file magic_comments.h
 */
#ifndef PRISM_MAGIC_COMMENTS_H
#define PRISM_MAGIC_COMMENTS_H

#include "prism/compiler/exported.h"

#include "prism/ast.h"

#include <stddef.h>

/** An opaque pointer to a magic comment found while parsing. */
typedef struct pm_magic_comment_t pm_magic_comment_t;

/**
 * Returns the location of the key associated with the given magic comment.
 *
 * @param comment the magic comment whose key location we want to get
 * @return the location of the key associated with the given magic comment
 */
PRISM_EXPORTED_FUNCTION pm_location_t pm_magic_comment_key(const pm_magic_comment_t *comment);

/**
 * Returns the location of the value associated with the given magic comment.
 *
 * @param comment the magic comment whose value location we want to get
 * @return the location of the value associated with the given magic comment
 */
PRISM_EXPORTED_FUNCTION pm_location_t pm_magic_comment_value(const pm_magic_comment_t *comment);

#endif
