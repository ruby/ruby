#ifndef PRISM_INTERNAL_LINE_OFFSET_LIST_H
#define PRISM_INTERNAL_LINE_OFFSET_LIST_H

#include "prism/compiler/force_inline.h"

#include "prism/internal/assert.h"

#include "prism/arena.h"
#include "prism/line_offset_list.h"

/* Initialize a new line offset list with the given capacity. */
void pm_line_offset_list_init(pm_arena_t *arena, pm_line_offset_list_t *list, size_t capacity);

/* Clear out the offsets that have been appended to the list. */
void pm_line_offset_list_clear(pm_line_offset_list_t *list);

/* Append a new offset to the list (slow path with resize). */
void pm_line_offset_list_append_slow(pm_arena_t *arena, pm_line_offset_list_t *list, uint32_t cursor);

/* Add the zero-based line index to the starting line with defined 32-bit
 * wraparound. Keep both the addition and conversion free of signed overflow. */
static PRISM_FORCE_INLINE int32_t
pm_line_offset_list_line_number(size_t index, int32_t start_line) {
    uint32_t line = (uint32_t) index + (uint32_t) start_line;
    if (line <= INT32_MAX) return (int32_t) line;

    return INT32_MIN + (int32_t) (line - ((uint32_t) INT32_MAX + 1));
}

/* Append a new offset to the list. */
static PRISM_FORCE_INLINE void
pm_line_offset_list_append(pm_arena_t *arena, pm_line_offset_list_t *list, uint32_t cursor) {
    /* Line and column lookups binary search this list, so it must stay strictly
     * increasing. */
    PRISM_ASSERT(list->size == 0 || cursor > list->offsets[list->size - 1]);

    if (list->size < list->capacity) {
        list->offsets[list->size++] = cursor;
    } else {
        pm_line_offset_list_append_slow(arena, list, cursor);
    }
}

/*
 * Returns the line of the given offset. If the offset is not in the list, the
 * line of the closest offset less than the given offset is returned.
 */
int32_t pm_line_offset_list_line(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line);

#endif
