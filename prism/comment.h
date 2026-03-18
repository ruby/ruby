/**
 * @file comment.h
 *
 * The comment module used to handle comments in Ruby source.
 */
#ifndef PRISM_COMMENT_H
#define PRISM_COMMENT_H

#include "prism/compiler/exported.h"

#include "prism/ast.h"
#include "prism/parser.h"

#include <stddef.h>

/** This is the type of a comment that we've found while parsing. */
typedef enum {
    PM_COMMENT_INLINE,
    PM_COMMENT_EMBDOC
} pm_comment_type_t;

/** An opaque pointer to a comment found while parsing. */
typedef struct pm_comment_t pm_comment_t;

/**
 * Returns the location associated with the given comment.
 *
 * @param comment the comment whose location we want to get
 * @return the location associated with the given comment
 */
PRISM_EXPORTED_FUNCTION pm_location_t pm_comment_location(const pm_comment_t *comment);

/**
 * Returns the type associated with the given comment.
 *
 * @param comment the comment whose type we want to get
 * @return the type associated with the given comment. This can either be
 *     PM_COMMENT_INLINE or PM_COMMENT_EMBDOC.
 */
PRISM_EXPORTED_FUNCTION pm_comment_type_t pm_comment_type(const pm_comment_t *comment);

/* An opaque pointer to an iterator that can be used to iterate over the
 * comments associated with a parser. */
typedef struct pm_comments_iter_t pm_comments_iter_t;

/**
 * Returns an iterator that knows how to iterate over the comments that are
 * associated with the given parser.
 *
 * @param parser the parser whose comments we want to get
 * @return the iterator that knows how to iterate over the comments that are
 *     associated with the given parser. It is the responsibility of the caller
 *     to free the memory associated with the iterator through
 *     pm_comments_iter_free.
 *
 * \public \memberof pm_parser
 */
PRISM_EXPORTED_FUNCTION pm_comments_iter_t * pm_comments_iter(const pm_parser_t *parser);

/**
 * Returns the number of comments associated with the comment iterator.
 *
 * @param iter the iterator to get the number of comments from
 * @return the number of comments associated with the comment iterator
 *
 * \public \memberof pm_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION size_t pm_comments_iter_size(const pm_comments_iter_t *iter);

/**
 * Returns the next comment in the iteration, or NULL if there are no more
 * comments.
 *
 * @param iter the iterator to get the next comment from
 * @return the next comment in the iteration, or NULL if there are no more
 *     comments.
 *
 * \public \memberof pm_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION const pm_comment_t * pm_comments_iter_next(pm_comments_iter_t *iter);

/**
 * Frees the memory associated with the given comments iterator.
 *
 * @param iter the iterator to free
 *
 * \public \memberof pm_comments_iter_t
 */
PRISM_EXPORTED_FUNCTION void pm_comments_iter_free(pm_comments_iter_t *iter);

#endif
