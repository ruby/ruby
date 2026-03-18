/**
 * @file comments.h
 *
 * Types and functions related to comments found during parsing.
 */
#ifndef PRISM_COMMENTS_H
#define PRISM_COMMENTS_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nodiscard.h"
#include "prism/compiler/nonnull.h"

#include "prism/ast.h"

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
 * @returns the location associated with the given comment
 */
PRISM_EXPORTED_FUNCTION pm_location_t pm_comment_location(const pm_comment_t *comment) PRISM_NONNULL(1);

/**
 * Returns the type associated with the given comment.
 *
 * @param comment the comment whose type we want to get
 * @returns the type associated with the given comment. This can either be
 *     PM_COMMENT_INLINE or PM_COMMENT_EMBDOC.
 */
PRISM_EXPORTED_FUNCTION pm_comment_type_t pm_comment_type(const pm_comment_t *comment) PRISM_NONNULL(1);

#endif
