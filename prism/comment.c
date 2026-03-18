#include "prism/internal/comment.h"

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

/**
 * Returns an iterator that knows how to iterate over the comments that are
 * associated with the given parser.
 */
pm_comments_iter_t *
pm_comments_iter(const pm_parser_t *parser) {
    pm_comments_iter_t *iter = (pm_comments_iter_t *) xmalloc(sizeof(pm_comments_iter_t));
    iter->size = parser->comment_list.size;
    iter->current = parser->comment_list.head;
    return iter;
}

/**
 * Returns the number of comments associated with the comment iterator.
 */
size_t
pm_comments_iter_size(const pm_comments_iter_t *iter) {
    return iter->size;
}

/**
 * Returns the next comment in the iteration, or NULL if there are no more
 * comments.
 */
const pm_comment_t *
pm_comments_iter_next(pm_comments_iter_t *iter) {
    if (iter->current == NULL) return NULL;
    const pm_comment_t *comment = (const pm_comment_t *) iter->current;
    iter->current = iter->current->next;
    return comment;
}

/**
 * Frees the memory associated with the given comments iterator.
 */
void
pm_comments_iter_free(pm_comments_iter_t *iter) {
    xfree(iter);
}
