#include "prism/internal/magic_comments.h"

#include "prism/internal/allocator.h"
#include "prism/internal/parser.h"

#include <stdlib.h>

/**
 * Returns the location associated with the given magic comment key.
 */
pm_location_t
pm_magic_comment_key(const pm_magic_comment_t *magic_comment) {
    return magic_comment->key;
}

/**
 * Returns the location associated with the given magic comment value.
 */
pm_location_t
pm_magic_comment_value(const pm_magic_comment_t *magic_comment) {
    return magic_comment->value;
}

/**
 * Returns the number of magic comments associated with the magic comment
 * iterator.
 */
size_t
pm_magic_comments_iter_size(const pm_magic_comments_iter_t *iter) {
    return iter->size;
}

/**
 * Returns the next magic comment in the iteration, or NULL if there are no more
 * magic comments.
 */
const pm_magic_comment_t *
pm_magic_comments_iter_next(pm_magic_comments_iter_t *iter) {
    if (iter->current == NULL) return NULL;
    const pm_magic_comment_t *magic_comment = (const pm_magic_comment_t *) iter->current;
    iter->current = iter->current->next;
    return magic_comment;
}

/**
 * Frees the memory associated with the given magic comments iterator.
 */
void
pm_magic_comments_iter_free(pm_magic_comments_iter_t *iter) {
    xfree(iter);
}
