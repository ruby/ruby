/**
 * @file internal/comments.h
 */
#ifndef PRISM_INTERNAL_COMMENTS_H
#define PRISM_INTERNAL_COMMENTS_H

#include "prism/comments.h"

#include "prism/list.h"

/**
 * A comment found while parsing.
 */
struct pm_comment_t {
    /** The embedded base node. */
    pm_list_node_t node;

    /** The location of the comment in the source. */
    pm_location_t location;

    /** The type of the comment. */
    pm_comment_type_t type;
};

/**
 * A struct used as an opaque pointer for the client to iterate through the
 * comments found while parsing.
 */
struct pm_comments_iter_t {
    /** The number of comments in the list. */
    size_t size;

    /** The current node in the list. */
    const pm_list_node_t *current;
};

#endif
