#ifndef PRISM_INTERNAL_STATIC_LITERALS_H
#define PRISM_INTERNAL_STATIC_LITERALS_H

#include "prism/ast.h"
#include "prism/buffer.h"
#include "prism/parser.h"

/*
 * Certain sets of nodes (hash keys and when clauses) check for duplicate nodes
 * to alert the user of potential issues. To do this, we keep a set of the nodes
 * that have been seen so far, and compare whenever we find a new node.
 */
typedef struct {
    /* The node stored in this slot, or NULL if the slot is empty. */
    pm_node_t *node;

    /* The hash of the node, kept so that it is never recomputed. */
    uint64_t hash;
} pm_static_literals_entry_t;

/*
 * The number of nodes a set holds directly before it moves them into a hash
 * table. Most sets are this small, so they are searched linearly without
 * hashing their nodes or allocating any memory.
 */
#define PM_STATIC_LITERALS_INLINE_CAPACITY 4

typedef struct {
    /*
     * The nodes in the set while it has no hash table. Once the set outgrows
     * this array, its nodes move into the hash table and this is unused.
     */
    pm_node_t *nodes[PM_STATIC_LITERALS_INLINE_CAPACITY];

    /* The array of entries in the hash table, or NULL if there is none. */
    pm_static_literals_entry_t *entries;

    /* The number of nodes in the set. */
    uint32_t size;

    /* The number of entries allocated in the hash table, or 0 if there is none. */
    uint32_t capacity;
} pm_static_literals_t;

/*
 * Add a node to the set of static literals.
 */
pm_node_t * pm_static_literals_add(const pm_parser_t *parser, pm_static_literals_t *literals, pm_node_t *node, bool replace);

/*
 * Free the internal memory associated with the given static literals set.
 */
void pm_static_literals_free(pm_static_literals_t *literals);

/*
 * Create a string-based representation of the given static literal.
 */
void pm_static_literal_inspect(pm_buffer_t *buffer, const pm_parser_t *parser, const pm_node_t *node);

#endif
