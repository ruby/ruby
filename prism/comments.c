#include "prism/internal/comments.h"

#include "prism/internal/arena.h"
#include "prism/internal/char.h"
#include "prism/internal/node.h"
#include "prism/internal/parser.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

/* The state used while walking the tree to find the owner of each comment. */
typedef struct {
    /* The arena for memory that is only needed during the walk. */
    pm_arena_t *arena;

    /* The start of the source that was parsed. */
    const uint8_t *source;

    /* The comments found while parsing, sorted by start offset. */
    const pm_comment_t **comments;

    /* The number of comments. */
    uint32_t size;

    /* The start offset of each comment. */
    uint32_t *starts;

    /*
     * The result of the most recent search for the first comment after the end
     * of a node. This is a hint to the search to avoid fully binary searching
     * the comments list if possible.
     */
    uint32_t cursor;

    /* The node each comment is attached to. */
    const pm_node_t **attached;

    /*
     * A disjoint set over comment indices that maps each index to the next
     * index at or after it that has not yet been claimed. It has one extra
     * entry at the end that is never claimed, so that every lookup ends. This
     * allows quickly finding the next unclaimed comment without having to check
     * the state of each comment individually.
     */
    uint32_t *unclaimed;

    /*
     * A stack of nodes whose children are being visited. Each level of the
     * walk pushes its children, visits them, then pops back to where it
     * started.
     */
    struct {
        const pm_node_t **nodes;
        size_t size;
        size_t capacity;
    } stack;
} pm_comments_walk_t;

/* Compare two comments by start offset for qsort. */
static int
pm_comments_compare(const void *left, const void *right) {
    uint32_t left_start = (*(const pm_comment_t *const *) left)->location.start;
    uint32_t right_start = (*(const pm_comment_t *const *) right)->location.start;
    return (left_start > right_start) - (left_start < right_start);
}

/*
 * Copy the linked list of comments from the parser sorted by start offset, and
 * relink the list in that order. Usually comments arrive in source order, but
 * unfortunately because of heredocs they can occasionally be out of order.
 */
static const pm_comment_t **
pm_comments_sort(pm_parser_t *parser, uint32_t size) {
    pm_comment_t **comments = (pm_comment_t **) pm_arena_alloc(&parser->metadata_arena, sizeof(pm_comment_t *) * size, PRISM_ALIGNOF(pm_comment_t *));

    uint32_t index = 0;
    for (pm_list_node_t *node = parser->comment_list.head; node != NULL; node = node->next) {
        comments[index++] = (pm_comment_t *) node;
    }

    qsort((void *) comments, size, sizeof(pm_comment_t *), pm_comments_compare);

    for (index = 0; index + 1 < size; index++) {
        comments[index]->node.next = &comments[index + 1]->node;
    }

    comments[size - 1]->node.next = NULL;
    parser->comment_list.head = &comments[0]->node;
    parser->comment_list.tail = &comments[size - 1]->node;

    return (const pm_comment_t **) comments;
}

/*
 * Return the index of the first comment in [left, right) that starts at or
 * after the given offset, or right if there is none.
 */
static uint32_t
pm_comments_lower_bound(const pm_comments_walk_t *walk, uint32_t left, uint32_t right, uint32_t offset) {
    while (left < right) {
        uint32_t middle = left + (right - left) / 2;

        if (walk->starts[middle] < offset) {
            left = middle + 1;
        } else {
            right = middle;
        }
    }

    return left;
}

/*
 * Return the index of the first comment that starts at or after the given
 * offset, or the number of comments if there is none. This gallops outward
 * from the previous result to find a range to search, so that a run of nearby
 * offsets costs a constant number of comparisons each.
 */
static uint32_t
pm_comments_seek(pm_comments_walk_t *walk, uint32_t offset) {
    const uint32_t *starts = walk->starts;

    uint32_t size = walk->size;
    uint32_t cursor = walk->cursor;
    uint32_t left;
    uint32_t right;
    uint32_t step = 1;

    if (cursor == size || starts[cursor] >= offset) {
        /*
         * The answer is at or before the cursor. Widen the range backward
         * until the comment before it starts before the offset.
         */
        right = cursor;
        left = cursor;

        while (left > 0 && starts[left - 1] >= offset) {
            right = left - 1;
            left = (left - 1 > step) ? left - 1 - step : 0;
            step *= 2;
        }
    } else {
        /*
         * The answer is after the cursor. Widen the range forward until it
         * ends at a comment that starts at or after the offset.
         */
        left = cursor + 1;
        right = left;

        while (right < size && starts[right] < offset) {
            left = right + 1;
            right = (size - left > step) ? left + step : size;
            step *= 2;
        }
    }

    walk->cursor = pm_comments_lower_bound(walk, left, right, offset);
    return walk->cursor;
}

/*
 * The first comment index at or after the given index that has not yet been
 * claimed, compressing the path along the way.
 */
static uint32_t
pm_comments_unclaimed(pm_comments_walk_t *walk, uint32_t index) {
    uint32_t *unclaimed = walk->unclaimed;

    while (unclaimed[index] != index) {
        unclaimed[index] = unclaimed[unclaimed[index]];
        index = unclaimed[index];
    }

    return index;
}

/*
 * Return the earliest offset before the given one from which the source up to
 * it holds only whitespace and comments. Any comment that starts at or after
 * the returned offset is separated from the given offset by only whitespace and
 * other comments.
 */
static uint32_t
pm_comments_blank_before(const pm_comments_walk_t *walk, uint32_t offset) {
    uint32_t index = pm_comments_lower_bound(walk, 0, walk->size, offset);

    while (true) {
        offset -= (uint32_t) pm_strrspn_whitespace(walk->source, (ptrdiff_t) offset);
        if (index == 0) return offset;

        /* An embedded document's location includes its trailing newline, so
         * the whitespace that was just skipped can end inside a comment. */
        const pm_location_t *location = &walk->comments[index - 1]->location;
        if (location->start >= offset || PM_LOCATION_END(location) < offset) return offset;

        offset = location->start;
        index--;
    }
}

/*
 * Return the latest offset after the given one, and no later than the given
 * end, up to which the source from the given offset holds only whitespace and
 * comments. Any comment that ends at or before the returned offset is
 * separated from the given offset by only whitespace and other comments.
 */
static uint32_t
pm_comments_blank_after(const pm_comments_walk_t *walk, uint32_t offset, uint32_t end) {
    uint32_t index = pm_comments_lower_bound(walk, 0, walk->size, offset);

    while (true) {
        offset += (uint32_t) pm_strspn_whitespace(walk->source + offset, (ptrdiff_t) end - (ptrdiff_t) offset);
        if (index == walk->size || walk->starts[index] != offset) return offset;

        offset = PM_LOCATION_END(&walk->comments[index]->location);
        index++;
    }
}

/*
 * Push a child node onto the walk stack without descending into it. The walk
 * descends itself, so that it can visit children in source order and handle
 * each node after all of its descendants.
 */
static pm_visit_result_t
pm_comments_push(const pm_node_t *node, void *data) {
    pm_comments_walk_t *walk = (pm_comments_walk_t *) data;

    if (walk->stack.size == walk->stack.capacity) {
        size_t capacity = walk->stack.capacity == 0 ? 64 : walk->stack.capacity * 2;
        const pm_node_t **nodes = (const pm_node_t **) pm_arena_alloc(walk->arena, sizeof(pm_node_t *) * capacity, PRISM_ALIGNOF(pm_node_t *));
        if (walk->stack.size > 0) memcpy((void *) nodes, (const void *) walk->stack.nodes, sizeof(pm_node_t *) * walk->stack.size);

        walk->stack.nodes = nodes;
        walk->stack.capacity = capacity;
    }

    walk->stack.nodes[walk->stack.size++] = node;
    return PM_VISIT_SKIP;
}

/*
 * Visit the given node and its descendants in post-order, attaching comments as
 * the nodes are visited.
 */
static void
pm_comments_visit(pm_comments_walk_t *walk, const pm_node_t *node) {
    /* First, push all of the children of this node onto the stack. */
    size_t base = walk->stack.size;
    pm_visit_child_nodes(node, pm_comments_push, walk);
    size_t top = walk->stack.size;

    /* Next, in-place sort the children by their starting location. */
    for (size_t index = base + 1; index < top; index++) {
        const pm_node_t *child = walk->stack.nodes[index];
        size_t insert = index;

        while (insert > base && walk->stack.nodes[insert - 1]->location.start > child->location.start) {
            walk->stack.nodes[insert] = walk->stack.nodes[insert - 1];
            insert--;
        }

        walk->stack.nodes[insert] = child;
    }

    /* Next, visit all of the children so that they can claim comments. */
    for (size_t index = base; index < top; index++) {
        pm_comments_visit(walk, walk->stack.nodes[index]);
    }

    uint32_t start = node->location.start;
    uint32_t end = PM_LOCATION_END(&node->location);
    uint32_t after = pm_comments_seek(walk, end);

    /* If this node is followed by a comment on the same line, attach it if
     * appropriate. Appropriate in this case means if no other node has claimed
     * it or if we are closer in distance or equal in distance to the current
     * claimant. */
    if (
        after < walk->size &&
        !PM_NODE_TYPE_P(node, PM_PROGRAM_NODE) &&
        !PM_NODE_TYPE_P(node, PM_STATEMENTS_NODE) &&
        (node->location.length == 0 || walk->source[end - 1] != '\n')
    ) {
        uint32_t comment_start = walk->starts[after];

        if (memchr(walk->source + end, '\n', comment_start - end) == NULL) {
            const pm_node_t *attached = walk->attached[after];
            uint32_t attached_end = attached == NULL ? 0 : PM_LOCATION_END(&attached->location);

            if (end >= attached_end || attached_end > comment_start) {
                walk->attached[after] = node;
            }
        }
    }

    /* Grab up the remaining comments within the range of this node that were
     * not claimed by any of its descendants. A comment that is separated by
     * only whitespace and other comments from a statements node child, either
     * the child after it or the child before it, is attached to the statements
     * instead, so that the comments before the first statement and after the
     * last statement in a body belong to the body. The claimed comments are in
     * order, so the children around each one are found by moving forward
     * through the sorted children. */
    if (after > 0 && walk->starts[after - 1] >= start) {
        uint32_t index = pm_comments_unclaimed(walk, pm_comments_lower_bound(walk, 0, after, start));
        size_t child_index = base;

        /* The boundaries around the statements children are each found once,
         * when the first comment that needs them is reached, since the
         * comments that follow reach the same children. */
        const pm_node_t *leading = NULL;
        uint32_t leading_boundary = 0;
        const pm_node_t *trailing = NULL;
        uint32_t trailing_boundary = 0;

        while (index < after && PM_LOCATION_END(&walk->comments[index]->location) <= end) {
            if (walk->attached[index] == NULL) {
                uint32_t comment_end = PM_LOCATION_END(&walk->comments[index]->location);
                const pm_node_t *attached = node;

                while (child_index < top && walk->stack.nodes[child_index]->location.start < comment_end) child_index++;

                if (child_index < top) {
                    const pm_node_t *child = walk->stack.nodes[child_index];

                    if (PM_NODE_TYPE_P(child, PM_STATEMENTS_NODE)) {
                        if (child != leading) {
                            leading = child;
                            leading_boundary = pm_comments_blank_before(walk, child->location.start);
                        }

                        if (walk->starts[index] >= leading_boundary) attached = child;
                    }
                }

                if (attached == node && child_index > base) {
                    const pm_node_t *child = walk->stack.nodes[child_index - 1];

                    /* A rescue clause ends at its last statement rather than at
                     * the keyword that follows it, and the first clause in a
                     * body contains the clauses after it. So a comment after
                     * the statements of the last clause follows the first
                     * clause, and belongs to the statements of the last. */
                    if (PM_NODE_TYPE_P(child, PM_RESCUE_NODE)) {
                        const pm_rescue_node_t *rescue = (const pm_rescue_node_t *) child;
                        while (rescue->subsequent != NULL) rescue = rescue->subsequent;
                        child = (const pm_node_t *) rescue->statements;
                    }

                    if (child != NULL && PM_NODE_TYPE_P(child, PM_STATEMENTS_NODE) && PM_LOCATION_END(&child->location) <= walk->starts[index]) {
                        if (child != trailing) {
                            trailing = child;
                            trailing_boundary = pm_comments_blank_after(walk, PM_LOCATION_END(&child->location), end);
                        }

                        if (comment_end <= trailing_boundary) attached = child;
                    }
                }

                walk->attached[index] = attached;
            }

            walk->unclaimed[index] = index + 1;
            index = pm_comments_unclaimed(walk, index + 1);
        }
    }

    /* Truncate the stack back to the base size. */
    walk->stack.size = base;
}

/*
 * Sort the parser's comment list in place by start offset, then assign every
 * comment to the node that owns it. A comment is owned by:
 *
 * 1. the node that ends latest on the comment's line before the comment starts,
 *    with ties going to the node that is higher in the tree;
 * 2. otherwise, the innermost node whose location contains the comment, or the
 *    statements node child of that node if only whitespace and other comments
 *    come between the statements and the comment, on either side;
 * 3. otherwise, the top-level statements node of the program.
 */
void
pm_comments_attach(pm_parser_t *parser, const pm_node_t *root) {
    assert(PM_NODE_TYPE_P(root, PM_PROGRAM_NODE));

    uint32_t size = (uint32_t) parser->comment_list.size;
    if (size == 0) return;

    pm_arena_t arena = { 0 };
    pm_comments_walk_t walk = {
        .arena = &arena,
        .source = parser->start,
        .comments = pm_comments_sort(parser, size),
        .size = size,
        .starts = (uint32_t *) pm_arena_alloc(&arena, sizeof(uint32_t) * size, PRISM_ALIGNOF(uint32_t)),
        .attached = (const pm_node_t **) pm_arena_zalloc(&arena, sizeof(pm_node_t *) * size, PRISM_ALIGNOF(pm_node_t *)),
        .unclaimed = (uint32_t *) pm_arena_alloc(&arena, sizeof(uint32_t) * (size + 1), PRISM_ALIGNOF(uint32_t))
    };

    for (uint32_t index = 0; index < size; index++) walk.starts[index] = walk.comments[index]->location.start;
    for (uint32_t index = 0; index <= size; index++) walk.unclaimed[index] = index;

    pm_comments_visit(&walk, root);

    /*
     * Attach comments that no node attached to during the walk to the
     * top-level statements, then group the comments by node with a counting
     * sort. Comments are placed in sorted order, so each node's comments stay
     * sorted by start offset.
     */
    const pm_node_t *statements = (const pm_node_t *) ((const pm_program_node_t *) root)->statements;
    uint32_t ranges_size = 0;

    for (uint32_t index = 0; index < size; index++) {
        if (walk.attached[index] == NULL) walk.attached[index] = statements;

        uint32_t node_id = walk.attached[index]->node_id;
        assert(node_id <= parser->node_id);
        if (node_id >= ranges_size) ranges_size = node_id + 1;
    }

    /* The ranges only extend to the largest node id that owns a comment, since
     * none of the nodes after it own any. */
    pm_comment_range_t *ranges = (pm_comment_range_t *) pm_arena_zalloc(&parser->metadata_arena, sizeof(pm_comment_range_t) * ranges_size, PRISM_ALIGNOF(pm_comment_range_t));
    uint32_t *attachments = (uint32_t *) pm_arena_alloc(&parser->metadata_arena, sizeof(uint32_t) * size, PRISM_ALIGNOF(uint32_t));

    for (uint32_t index = 0; index < size; index++) {
        ranges[walk.attached[index]->node_id].length++;
    }

    uint32_t offset = 0;
    for (uint32_t index = 0; index < ranges_size; index++) {
        ranges[index].index = offset;
        offset += ranges[index].length;
        ranges[index].length = 0;
    }

    for (uint32_t index = 0; index < size; index++) {
        pm_comment_range_t *range = &ranges[walk.attached[index]->node_id];
        attachments[range->index + range->length++] = index;
    }

    pm_arena_cleanup(&arena);

    parser->comment_attachments = (pm_comment_attachments_t) {
        .comments = walk.comments,
        .attachments = attachments,
        .ranges = ranges,
        .ranges_size = ranges_size
    };
}
