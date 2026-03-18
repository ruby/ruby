/**
 * @file internal/constant_pool.h
 *
 * A data structure that stores a set of strings.
 *
 * Each string is assigned a unique id, which can be used to compare strings for
 * equality. This comparison ends up being much faster than strcmp, since it
 * only requires a single integer comparison.
 */
#ifndef PRISM_INTERNAL_CONSTANT_POOL_H
#define PRISM_INTERNAL_CONSTANT_POOL_H

#include "prism/constant_pool.h"

#include "prism/arena.h"

/**
 * Initialize a list of constant ids.
 *
 * @param list The list to initialize.
 */
void pm_constant_id_list_init(pm_constant_id_list_t *list);

/**
 * Initialize a list of constant ids with a given capacity.
 *
 * @param arena The arena to allocate from.
 * @param list The list to initialize.
 * @param capacity The initial capacity of the list.
 */
void pm_constant_id_list_init_capacity(pm_arena_t *arena, pm_constant_id_list_t *list, size_t capacity);

/**
 * Append a constant id to a list of constant ids.
 *
 * @param arena The arena to allocate from.
 * @param list The list to append to.
 * @param id The id to append.
 */
void pm_constant_id_list_append(pm_arena_t *arena, pm_constant_id_list_t *list, pm_constant_id_t id);

/**
 * Insert a constant id into a list of constant ids at the specified index.
 *
 * @param list The list to insert into.
 * @param index The index at which to insert.
 * @param id The id to insert.
 */
void pm_constant_id_list_insert(pm_constant_id_list_t *list, size_t index, pm_constant_id_t id);

/**
 * Checks if the current constant id list includes the given constant id.
 *
 * @param list The list to check.
 * @param id The id to check for.
 * @return Whether the list includes the given id.
 */
bool pm_constant_id_list_includes(pm_constant_id_list_t *list, pm_constant_id_t id);

/**
 * Initialize a new constant pool with a given capacity.
 *
 * @param arena The arena to allocate from.
 * @param pool The pool to initialize.
 * @param capacity The initial capacity of the pool.
 */
void pm_constant_pool_init(pm_arena_t *arena, pm_constant_pool_t *pool, uint32_t capacity);

/**
 * Return a pointer to the constant indicated by the given constant id.
 *
 * @param pool The pool to get the constant from.
 * @param constant_id The id of the constant to get.
 * @return A pointer to the constant.
 */
pm_constant_t * pm_constant_pool_id_to_constant(const pm_constant_pool_t *pool, pm_constant_id_t constant_id);

/**
 * Find a constant in a constant pool. Returns the id of the constant, or 0 if
 * the constant is not found.
 *
 * @param pool The pool to find the constant in.
 * @param start A pointer to the start of the constant.
 * @param length The length of the constant.
 * @return The id of the constant.
 */
pm_constant_id_t pm_constant_pool_find(const pm_constant_pool_t *pool, const uint8_t *start, size_t length);

/**
 * Insert a constant into a constant pool that is a slice of a source string.
 * Returns the id of the constant, or 0 if any potential calls to resize fail.
 *
 * @param arena The arena to allocate from.
 * @param pool The pool to insert the constant into.
 * @param start A pointer to the start of the constant.
 * @param length The length of the constant.
 * @return The id of the constant.
 */
pm_constant_id_t pm_constant_pool_insert_shared(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length);

/**
 * Insert a constant into a constant pool from memory that is now owned by the
 * constant pool. Returns the id of the constant, or 0 if any potential calls to
 * resize fail.
 *
 * @param arena The arena to allocate from.
 * @param pool The pool to insert the constant into.
 * @param start A pointer to the start of the constant.
 * @param length The length of the constant.
 * @return The id of the constant.
 */
pm_constant_id_t pm_constant_pool_insert_owned(pm_arena_t *arena, pm_constant_pool_t *pool, uint8_t *start, size_t length);

/**
 * Insert a constant into a constant pool from memory that is constant. Returns
 * the id of the constant, or 0 if any potential calls to resize fail.
 *
 * @param arena The arena to allocate from.
 * @param pool The pool to insert the constant into.
 * @param start A pointer to the start of the constant.
 * @param length The length of the constant.
 * @return The id of the constant.
 */
pm_constant_id_t pm_constant_pool_insert_constant(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length);

#endif
