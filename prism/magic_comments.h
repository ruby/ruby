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

/* An opaque pointer to an iterator that can be used to iterate over the
 * magic comments associated with a parser. */
typedef struct pm_magic_comments_iter_t pm_magic_comments_iter_t;

/**
 * Returns the number of magic comments associated with the magic comments iterator.
 *
 * @param iter the iterator to get the number of magic comments from
 * @return the number of magic comments associated with the magic comments iterator
 *
 * \public \memberof pm_magic_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION size_t pm_magic_comments_iter_size(const pm_magic_comments_iter_t *iter);

/**
 * Returns the next magic comment in the iteration, or NULL if there are no more
 * magic comments.
 *
 * @param iter the iterator to get the next magic comment from
 * @return the next magic comment in the iteration, or NULL if there are no more
 *     magic comments.
 *
 * \public \memberof pm_magic_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION const pm_magic_comment_t * pm_magic_comments_iter_next(pm_magic_comments_iter_t *iter);

/**
 * Frees the memory associated with the given magic comments iterator.
 *
 * @param iter the iterator to free
 *
 * \public \memberof pm_magic_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION void pm_magic_comments_iter_free(pm_magic_comments_iter_t *iter);

#endif
