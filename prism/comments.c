#include "prism/internal/comments.h"

#include "prism/internal/allocator.h"
#include "prism/internal/parser.h"

#include <stdlib.h>

/**
 * Returns the location associated with the given comment.
 */
pm_location_t
pm_comment_location(const pm_comment_t *comment) {
    return comment->location;
}

/**
 * Returns the type associated with the given comment.
 */
pm_comment_type_t
pm_comment_type(const pm_comment_t *comment) {
    return comment->type;
}
