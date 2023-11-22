#include "prism/util/pm_newline_list.h"

/**
 * Initialize a new newline list with the given capacity. Returns true if the
 * allocation of the offsets succeeds, otherwise returns false.
 */
bool
pm_newline_list_init(pm_newline_list_t *list, const uint8_t *start, size_t capacity) {
    list->offsets = (size_t *) calloc(capacity, sizeof(size_t));
    if (list->offsets == NULL) return false;

    list->start = start;

    // This is 1 instead of 0 because we want to include the first line of the
    // file as having offset 0, which is set because of calloc.
    list->size = 1;
    list->capacity = capacity;

    return true;
}

/**
 * Append a new offset to the newline list. Returns true if the reallocation of
 * the offsets succeeds (if one was necessary), otherwise returns false.
 */
bool
pm_newline_list_append(pm_newline_list_t *list, const uint8_t *cursor) {
    if (list->size == list->capacity) {
        size_t *original_offsets = list->offsets;

        list->capacity = (list->capacity * 3) / 2;
        list->offsets = (size_t *) calloc(list->capacity, sizeof(size_t));
        memcpy(list->offsets, original_offsets, list->size * sizeof(size_t));
        free(original_offsets);
        if (list->offsets == NULL) return false;
    }

    assert(*cursor == '\n');
    assert(cursor >= list->start);
    size_t newline_offset = (size_t) (cursor - list->start + 1);

    assert(list->size == 0 || newline_offset > list->offsets[list->size - 1]);
    list->offsets[list->size++] = newline_offset;

    return true;
}

/**
 * Conditionally append a new offset to the newline list, if the value passed in
 * is a newline.
 */
bool
pm_newline_list_check_append(pm_newline_list_t *list, const uint8_t *cursor) {
    if (*cursor != '\n') {
        return true;
    }
    return pm_newline_list_append(list, cursor);
}

/**
 * Returns the line and column of the given offset. If the offset is not in the
 * list, the line and column of the closest offset less than the given offset
 * are returned.
 */
pm_line_column_t
pm_newline_list_line_column(const pm_newline_list_t *list, const uint8_t *cursor) {
    assert(cursor >= list->start);
    size_t offset = (size_t) (cursor - list->start);

    size_t left = 0;
    size_t right = list->size - 1;

    while (left <= right) {
        size_t mid = left + (right - left) / 2;

        if (list->offsets[mid] == offset) {
            return ((pm_line_column_t) { mid, 0 });
        }

        if (list->offsets[mid] < offset) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    return ((pm_line_column_t) { left - 1, offset - list->offsets[left - 1] });
}

/**
 * Free the internal memory allocated for the newline list.
 */
void
pm_newline_list_free(pm_newline_list_t *list) {
    free(list->offsets);
}
