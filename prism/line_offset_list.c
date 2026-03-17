#include "prism/internal/line_offset_list.h"
#include "prism/internal/arena.h"
#include "prism/align.h"

#include <assert.h>
#include <string.h>

/**
 * Initialize a new line offset list with the given capacity.
 */
void
pm_line_offset_list_init(pm_arena_t *arena, pm_line_offset_list_t *list, size_t capacity) {
    list->offsets = (uint32_t *) pm_arena_alloc(arena, capacity * sizeof(uint32_t), PRISM_ALIGNOF(uint32_t));

    // The first line always has offset 0.
    list->offsets[0] = 0;
    list->size = 1;
    list->capacity = capacity;
}

/**
 * Clear out the newlines that have been appended to the list.
 */
void
pm_line_offset_list_clear(pm_line_offset_list_t *list) {
    list->size = 1;
}

/**
 * Append a new offset to the newline list (slow path: resize and store).
 */
void
pm_line_offset_list_append_slow(pm_arena_t *arena, pm_line_offset_list_t *list, uint32_t cursor) {
    size_t new_capacity = (list->capacity * 3) / 2;
    uint32_t *new_offsets = (uint32_t *) pm_arena_alloc(arena, new_capacity * sizeof(uint32_t), PRISM_ALIGNOF(uint32_t));

    memcpy(new_offsets, list->offsets, list->size * sizeof(uint32_t));

    list->offsets = new_offsets;
    list->capacity = new_capacity;

    assert(list->size == 0 || cursor > list->offsets[list->size - 1]);
    list->offsets[list->size++] = cursor;
}

/**
 * Returns the line of the given offset. If the offset is not in the list, the
 * line of the closest offset less than the given offset is returned.
 */
int32_t
pm_line_offset_list_line(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line) {
    size_t left = 0;
    size_t right = list->size - 1;

    while (left <= right) {
        size_t mid = left + (right - left) / 2;

        if (list->offsets[mid] == cursor) {
            return ((int32_t) mid) + start_line;
        }

        if (list->offsets[mid] < cursor) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    return ((int32_t) left) + start_line - 1;
}

/**
 * Returns the line and column of the given offset. If the offset is not in the
 * list, the line and column of the closest offset less than the given offset
 * are returned.
 */
pm_line_column_t
pm_line_offset_list_line_column(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line) {
    size_t left = 0;
    size_t right = list->size - 1;

    while (left <= right) {
        size_t mid = left + (right - left) / 2;

        if (list->offsets[mid] == cursor) {
            return ((pm_line_column_t) { ((int32_t) mid) + start_line, 0 });
        }

        if (list->offsets[mid] < cursor) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    return ((pm_line_column_t) {
        .line = ((int32_t) left) + start_line - 1,
        .column = cursor - list->offsets[left - 1]
    });
}
