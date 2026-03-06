#include "prism/util/pm_line_offset_list.h"

/**
 * Initialize a new newline list with the given capacity. Returns true if the
 * allocation of the offsets succeeds, otherwise returns false.
 */
bool
pm_line_offset_list_init(pm_line_offset_list_t *list, size_t capacity) {
    list->offsets = (uint32_t *) xcalloc(capacity, sizeof(uint32_t));
    if (list->offsets == NULL) return false;

    // This is 1 instead of 0 because we want to include the first line of the
    // file as having offset 0, which is set because of calloc.
    list->size = 1;
    list->capacity = capacity;

    return true;
}

/**
 * Clear out the newlines that have been appended to the list.
 */
void
pm_line_offset_list_clear(pm_line_offset_list_t *list) {
    list->size = 1;
}

/**
 * Append a new offset to the newline list. Returns true if the reallocation of
 * the offsets succeeds (if one was necessary), otherwise returns false.
 */
bool
pm_line_offset_list_append(pm_line_offset_list_t *list, uint32_t cursor) {
    if (list->size == list->capacity) {
        uint32_t *original_offsets = list->offsets;

        list->capacity = (list->capacity * 3) / 2;
        list->offsets = (uint32_t *) xcalloc(list->capacity, sizeof(uint32_t));
        if (list->offsets == NULL) return false;

        memcpy(list->offsets, original_offsets, list->size * sizeof(uint32_t));
        xfree_sized(original_offsets, list->size * sizeof(uint32_t));
    }

    assert(list->size == 0 || cursor > list->offsets[list->size - 1]);
    list->offsets[list->size++] = cursor;

    return true;
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

/**
 * Free the internal memory allocated for the newline list.
 */
void
pm_line_offset_list_free(pm_line_offset_list_t *list) {
    xfree_sized(list->offsets, list->capacity * sizeof(uint32_t));
}
