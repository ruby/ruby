/**
 * @file node.h
 *
 * Functions related to nodes in the AST.
 */
#ifndef PRISM_NODE_H
#define PRISM_NODE_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include "prism/ast.h"

/**
 * Loop through each node in the node list, writing each node to the given
 * pm_node_t pointer.
 */
#define PM_NODE_LIST_FOREACH(list, index, node) \
    for (size_t index = 0; index < (list)->size && ((node) = (list)->nodes[index]); index++)

/**
 * Returns a string representation of the given node type.
 *
 * @param node_type The node type to convert to a string.
 * @return A string representation of the given node type.
 */
PRISM_EXPORTED_FUNCTION const char * pm_node_type(pm_node_type_t node_type);

/**
 * Visit each of the nodes in this subtree using the given visitor callback. The
 * callback function will be called for each node in the subtree. If it returns
 * false, then that node's children will not be visited. If it returns true,
 * then the children will be visited. The data parameter is treated as an opaque
 * pointer and is passed to the visitor callback for consumers to use as they
 * see fit.
 *
 * As an example:
 *
 * ```c
 * #include "prism.h"
 *
 * bool visit(const pm_node_t *node, void *data) {
 *     size_t *indent = (size_t *) data;
 *     for (size_t i = 0; i < *indent * 2; i++) putc(' ', stdout);
 *     printf("%s\n", pm_node_type(node->type));
 *
 *     size_t next_indent = *indent + 1;
 *     size_t *next_data = &next_indent;
 *     pm_visit_child_nodes(node, visit, next_data);
 *
 *     return false;
 * }
 *
 * int main(void) {
 *     const char *source = "1 + 2; 3 + 4";
 *     size_t size = strlen(source);
 *
 *     pm_arena_t *arena = pm_arena_new();
 *     pm_options_t *options = pm_options_new();
 *
 *     pm_parser_t *parser = pm_parser_new(arena, (const uint8_t *) source, size, options);
 *
 *     size_t indent = 0;
 *     pm_node_t *node = pm_parse(parser);
 *
 *     size_t *data = &indent;
 *     pm_visit_node(node, visit, data);
 *
 *     pm_parser_free(parser);
 *     pm_options_free(options);
 *     pm_arena_free(arena);
 *
 *     return EXIT_SUCCESS;
 * }
 * ```
 *
 * @param node The root node to start visiting from.
 * @param visitor The callback to call for each node in the subtree.
 * @param data An opaque pointer that is passed to the visitor callback.
 */
PRISM_EXPORTED_FUNCTION void pm_visit_node(const pm_node_t *node, bool (*visitor)(const pm_node_t *node, void *data), void *data) PRISM_NONNULL(1);

/**
 * Visit the children of the given node with the given callback. This is the
 * default behavior for walking the tree that is called from pm_visit_node if
 * the callback returns true.
 *
 * @param node The node to visit the children of.
 * @param visitor The callback to call for each child node.
 * @param data An opaque pointer that is passed to the visitor callback.
 */
PRISM_EXPORTED_FUNCTION void pm_visit_child_nodes(const pm_node_t *node, bool (*visitor)(const pm_node_t *node, void *data), void *data) PRISM_NONNULL(1);

#endif
