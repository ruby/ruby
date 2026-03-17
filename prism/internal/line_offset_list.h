/**
 * @file internal/line_offset_list.h
 *
 * A list of byte offsets of newlines in a string.
 *
 * When compiling the syntax tree, it's necessary to know the line and column
 * of many nodes. This is necessary to support things like error messages,
 * tracepoints, etc.
 *
 * It's possible that we could store the start line, start column, end line, and
 * end column on every node in addition to the offsets that we already store,
 * but that would be quite a lot of memory overhead.
 */
#ifndef PRISM_INTERNAL_LINE_OFFSET_LIST_H
#define PRISM_INTERNAL_LINE_OFFSET_LIST_H

#include "prism/line_offset_list.h"

#include "prism/attribute/force_inline.h"
#include "prism/arena.h"

/**
 * Initialize a new line offset list with the given capacity.
 *
 * @param arena The arena to allocate from.
 * @param list The list to initialize.
 * @param capacity The initial capacity of the list.
 */
void pm_line_offset_list_init(pm_arena_t *arena, pm_line_offset_list_t *list, size_t capacity);

/**
 * Clear out the offsets that have been appended to the list.
 *
 * @param list The list to clear.
 */
void pm_line_offset_list_clear(pm_line_offset_list_t *list);

/**
 * Append a new offset to the list (slow path with resize).
 *
 * @param arena The arena to allocate from.
 * @param list The list to append to.
 * @param cursor The offset to append.
 */
void pm_line_offset_list_append_slow(pm_arena_t *arena, pm_line_offset_list_t *list, uint32_t cursor);

/**
 * Append a new offset to the list.
 *
 * @param arena The arena to allocate from.
 * @param list The list to append to.
 * @param cursor The offset to append.
 */
static PRISM_FORCE_INLINE void
pm_line_offset_list_append(pm_arena_t *arena, pm_line_offset_list_t *list, uint32_t cursor) {
    if (list->size < list->capacity) {
        list->offsets[list->size++] = cursor;
    } else {
        pm_line_offset_list_append_slow(arena, list, cursor);
    }
}

/**
 * Returns the line of the given offset. If the offset is not in the list, the
 * line of the closest offset less than the given offset is returned.
 *
 * @param list The list to search.
 * @param cursor The offset to search for.
 * @param start_line The line to start counting from.
 * @return The line of the given offset.
 */
int32_t pm_line_offset_list_line(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line);

#endif
