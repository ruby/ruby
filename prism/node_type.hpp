/**
 * @file node_type.hpp
 *
 * The traits that map node structs to node types. The specialization for each
 * node struct is generated into ast.hpp.
 */
#ifndef PRISM_NODE_TYPE_HPP
#define PRISM_NODE_TYPE_HPP

#include "prism/compiler/cplusplus.hpp"

#include "prism/ast.h"

#include <type_traits>

namespace prism {

/**
 * Maps a node struct to its node type, as in node_type<pm_call_node_t>::value
 * being PM_CALL_NODE. Only the node structs declared in ast.h have a value.
 */
template <typename T> struct node_type {};

/** The node type of the given node struct. */
template <typename T> inline constexpr pm_node_type_t node_type_v = node_type<T>::value;

/** Whether the given type is one of the node structs declared in ast.h. */
template <typename T, typename = void> struct is_node : std::false_type {};

/** Whether the given type is one of the node structs declared in ast.h. */
template <typename T> struct is_node<T, std::void_t<decltype(node_type<T>::value)>> : std::true_type {};

/** Whether the given type is one of the node structs declared in ast.h. */
template <typename T> inline constexpr bool is_node_v = is_node<T>::value;

}

#endif
