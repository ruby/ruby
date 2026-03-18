/**
 * @file internal/magic_comments.h
 */
#ifndef PRISM_INTERNAL_MAGIC_COMMENTS_H
#define PRISM_INTERNAL_MAGIC_COMMENTS_H

#include "prism/magic_comments.h"

#include "prism/internal/list.h"

/**
 * This is a node in the linked list of magic comments that we've found while
 * parsing.
 *
 * @extends pm_list_node_t
 */
struct pm_magic_comment_t {
    /** The embedded base node. */
    pm_list_node_t node;

    /** The key of the magic comment. */
    pm_location_t key;

    /** The value of the magic comment. */
    pm_location_t value;
};

/**
 * A struct used as an opaque pointer for the client to iterate through the
 * magic comments found while parsing.
 */
struct pm_magic_comments_iter_t {
    /** The number of magic comments in the list. */
    size_t size;

    /** The current node in the list. */
    const pm_list_node_t *current;
};

#endif
