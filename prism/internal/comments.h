#ifndef PRISM_INTERNAL_COMMENTS_H
#define PRISM_INTERNAL_COMMENTS_H

#include "prism/comments.h"
#include "prism/parser.h"

#include "prism/internal/list.h"

#include <stdint.h>

/* A comment found while parsing. */
struct pm_comment_t {
    /* The embedded base node. */
    pm_list_node_t node;

    /* The location of the comment in the source. */
    pm_location_t location;

    /* The type of the comment. */
    pm_comment_type_t type;
};

/*
 * The result of attaching comments to the nodes that own them. All of the
 * arrays are allocated in the parser's metadata arena.
 */
typedef struct {
    /* The comments found while parsing, sorted by start offset. */
    const pm_comment_t **comments;

    /*
     * Indices into comments, grouped by owning node in order of node id and
     * sorted by start offset within each group. A node's comments are not
     * necessarily contiguous in comments, because a child can own a comment
     * that falls between two comments owned by its parent.
     */
    uint32_t *attachments;

    /* The slice of attachments for each node, indexed by node id. */
    pm_comment_range_t *ranges;

    /* The number of entries in ranges. */
    uint32_t ranges_size;
} pm_comment_attachments_t;

/*
 * Sort the parser's comment list in place by start offset, then assign every
 * comment to the node that owns it. This is called after parsing when the
 * attach_comments option is set.
 */
void pm_comments_attach(pm_parser_t *parser, const pm_node_t *root);

#endif
