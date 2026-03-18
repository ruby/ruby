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
