#ifndef PRISM_INTERNAL_COMMENTS_H
#define PRISM_INTERNAL_COMMENTS_H

#include "prism/comments.h"

#include "prism/internal/list.h"

/* A comment found while parsing. */
struct pm_comment_t {
    /* The embedded base node. */
    pm_list_node_t node;

    /* The location of the comment in the source. */
    pm_location_t location;

    /* The type of the comment. */
    pm_comment_type_t type;
};

#endif
