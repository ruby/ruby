/**
 * @file node.hpp
 *
 * Checked casts between node structs, iteration over lists of nodes, and
 * walking the tree from C++.
 */
#ifndef PRISM_NODE_HPP
#define PRISM_NODE_HPP

#include "prism/compiler/cplusplus.hpp"
#include "prism/compiler/exceptions.hpp"
#include "prism/compiler/lifetimebound.hpp"

#include "prism/ast.hpp"
#include "prism/node.h"
#include "prism/node_type.hpp"

#include <cassert>
#include <cstddef>
#include <exception>
#include <functional>
#include <memory>
#include <type_traits>

namespace prism {

/**
 * Whether the given node, which must not be null, is of the given struct
 *
 * @tparam T The node struct type to check against.
 * @param node The node to check.
 * @return True if the node is of the given struct, false otherwise.
 */
template <typename T> [[nodiscard]] bool
isa(const pm_node_t *node) noexcept {
    static_assert(is_node_v<T>, "isa<T> requires a node struct declared in ast.h");
    assert(node != nullptr);
    return node->type == node_type_v<T>;
}

/**
 * Cast the given node, which must not be null and must be of the given struct,
 * to that struct. The type is checked in debug builds.
 *
 * @tparam T The node struct type to cast to.
 * @param node The node to cast.
 * @return The node cast to the given struct.
 */
template <typename T> [[nodiscard]] T *
cast(pm_node_t *node) noexcept {
    assert(isa<T>(node));
    return reinterpret_cast<T *>(node);
}

/**
 * Cast the given node, which must not be null and must be of the given struct,
 * to that struct. The type is checked in debug builds.
 *
 * @tparam T The node struct type to cast to.
 * @param node The node to cast.
 * @return The node cast to the given struct.
 */
template <typename T> [[nodiscard]] const T *
cast(const pm_node_t *node) noexcept {
    assert(isa<T>(node));
    return reinterpret_cast<const T *>(node);
}

/**
 * Cast the given node to the given struct if it is of that struct, and return
 * null otherwise. The node may be null, in which case this returns null.
 *
 * @tparam T The node struct type to cast to.
 * @param node The node to cast.
 * @return The node cast to the given struct if it is of that struct, or null
 *   otherwise.
 */
template <typename T> [[nodiscard]] T *
dyn_cast(pm_node_t *node) noexcept {
    return (node != nullptr && isa<T>(node)) ? reinterpret_cast<T *>(node) : nullptr;
}

/**
 * Cast the given node to the given struct if it is of that struct, and return
 * null otherwise. The node may be null, in which case this returns null.
 *
 * @tparam T The node struct type to cast to.
 * @param node The node to cast.
 * @return The node cast to the given struct if it is of that struct, or null
 *   otherwise.
 */
template <typename T> [[nodiscard]] const T *
dyn_cast(const pm_node_t *node) noexcept {
    return (node != nullptr && isa<T>(node)) ? reinterpret_cast<const T *>(node) : nullptr;
}

/**
 * Return the pm_node_t embedded at the start of the given node struct.
 *
 * @tparam T The node struct type.
 * @param node The node struct to upcast.
 * @return The pm_node_t embedded at the start of the node struct.
 */
template <typename T> [[nodiscard]] pm_node_t *
upcast(T *node) noexcept {
    static_assert(is_node_v<T>, "upcast requires a node struct declared in ast.h");
    return &node->base;
}

/**
 * Return the pm_node_t embedded at the start of the given node struct.
 *
 * @tparam T The node struct type.
 * @param node The node struct to upcast.
 * @return The pm_node_t embedded at the start of the node struct.
 */
template <typename T> [[nodiscard]] const pm_node_t *
upcast(const T *node) noexcept {
    static_assert(is_node_v<T>, "upcast requires a node struct declared in ast.h");
    return &node->base;
}

/**
 * The nodes in a list, usable in a range-based for loop. It refers to the list
 * rather than copying it, so the list must outlive it.
 */
class node_range {
public:
    /**
     * Create a range over the nodes in the given list.
     *
     * @param list The list of nodes to create a range for.
     */
    explicit node_range(const pm_node_list_t &list PRISM_LIFETIMEBOUND) noexcept : list_(&list) {}

    /**
     * A pointer to the first node.
     *
     * @return A pointer to the first node, or null if the list is empty.
     */
    pm_node_t *const *begin() const noexcept { return list_->nodes; }

    /**
     * A pointer one past the last node.
     *
     * @return A pointer one past the last node, or null if the list is empty.
     */
    pm_node_t *const *end() const noexcept { return list_->nodes + list_->size; }

    /**
     * The number of nodes.
     *
     * @return The number of nodes.
     */
    std::size_t size() const noexcept { return list_->size; }

    /**
     * Whether there are no nodes.
     *
     * @return True if there are no nodes, false otherwise.
     */
    [[nodiscard]] bool empty() const noexcept { return list_->size == 0; }

private:
    const pm_node_list_t *list_;
};

namespace detail {

/**
 * The state shared between a walk and its C callback, passed through the C
 * function's void * data parameter.
 */
template <typename F> struct visit_context {
    /**
     * The context for a visit, holding the visitor and any exception thrown.
     *
     * @param visitor The visitor callable to be used for each node.
     */
    explicit visit_context(F *visitor) noexcept : callable(visitor) {}

    /** The visitor that the walk calls for each node. */
    F *callable;

#ifdef PRISM_HAS_EXCEPTIONS
    /** The exception thrown by the visitor, if any. */
    std::exception_ptr exception;
#endif
};

/**
 * Forwards the C visitor callback to a C++ callable. An exception cannot unwind
 * through the C frames that call this function, so one thrown by the callable
 * is caught here and the walk is stopped. The function that started the walk
 * rethrows it once the C walk has returned. Without exceptions, the callable
 * cannot throw, so it is called directly.
 *
 * @tparam F The type of the visitor callable.
 * @param node The current node being visited.
 * @param data The visit context containing the visitor and exception state.
 * @return The result of the visit, indicating whether to descend, skip, or stop.
 */
template <typename F> pm_visit_result_t
visit_callback(const pm_node_t *node, void *data) noexcept {
    visit_context<F> *context = static_cast<visit_context<F> *>(data);

#ifdef PRISM_HAS_EXCEPTIONS
    try {
        return std::invoke(*context->callable, node);
    } catch (...) {
        context->exception = std::current_exception();
        return PM_VISIT_STOP;
    }
#else
    return std::invoke(*context->callable, node);
#endif
}

}

/**
 * Walk the tree rooted at the given node in pre-order, calling the visitor with
 * each node. The visitor returns PM_VISIT_DESCEND to continue into that node's
 * children, PM_VISIT_SKIP to continue past them, or PM_VISIT_STOP to end the
 * walk. Returns false if the walk was stopped. If the visitor throws, the walk
 * stops and the exception propagates from this function.
 *
 * @tparam F The type of the visitor callable.
 * @param node The root node to start the walk from.
 * @param visitor The visitor callable to invoke for each node.
 * @return True if the walk completed, false if it was stopped.
 */
template <typename F> bool
visit_node(const pm_node_t *node, F &&visitor) {
    static_assert(std::is_invocable_r_v<pm_visit_result_t, F &, const pm_node_t *>, "visit_node requires a callable taking const pm_node_t * and returning pm_visit_result_t");
    detail::visit_context<std::remove_reference_t<F>> context(std::addressof(visitor));
    bool completed = pm_visit_node(node, detail::visit_callback<std::remove_reference_t<F>>, &context);

#ifdef PRISM_HAS_EXCEPTIONS
    if (context.exception) std::rethrow_exception(context.exception);
#endif

    return completed;
}

/**
 * Walk the children of the given node, as visit_node does for every node whose
 * visitor returns PM_VISIT_DESCEND. Returns false if the walk was stopped. If
 * the visitor throws, the walk stops and the exception propagates from this
 * function.
 *
 * @tparam F The type of the visitor callable.
 * @param node The node whose children to walk.
 * @param visitor The visitor callable to invoke for each child node.
 * @return True if the walk completed, false if it was stopped.
 */
template <typename F> bool
visit_child_nodes(const pm_node_t *node, F &&visitor) {
    static_assert(std::is_invocable_r_v<pm_visit_result_t, F &, const pm_node_t *>, "visit_child_nodes requires a callable taking const pm_node_t * and returning pm_visit_result_t");
    detail::visit_context<std::remove_reference_t<F>> context(std::addressof(visitor));
    bool completed = pm_visit_child_nodes(node, detail::visit_callback<std::remove_reference_t<F>>, &context);

#ifdef PRISM_HAS_EXCEPTIONS
    if (context.exception) std::rethrow_exception(context.exception);
#endif

    return completed;
}

}

#endif
