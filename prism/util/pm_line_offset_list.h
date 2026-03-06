/**
 * @file pm_line_offset_list.h
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
#ifndef PRISM_LINE_OFFSET_LIST_H
#define PRISM_LINE_OFFSET_LIST_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

/**
 * A list of offsets of the start of lines in a string. The offsets are assumed
 * to be sorted/inserted in ascending order.
 */
typedef struct {
    /** The number of offsets in the list. */
    size_t size;

    /** The capacity of the list that has been allocated. */
    size_t capacity;

    /** The list of offsets. */
    uint32_t *offsets;
} pm_line_offset_list_t;

/**
 * A line and column in a string.
 */
typedef struct {
    /** The line number. */
    int32_t line;

    /** The column in bytes. */
    uint32_t column;
} pm_line_column_t;

/**
 * Initialize a new line offset list with the given capacity. Returns true if
 * the allocation of the offsets succeeds, otherwise returns false.
 *
 * @param list The list to initialize.
 * @param capacity The initial capacity of the list.
 * @return True if the allocation of the offsets succeeds, otherwise false.
 */
bool pm_line_offset_list_init(pm_line_offset_list_t *list, size_t capacity);

/**
 * Clear out the offsets that have been appended to the list.
 *
 * @param list The list to clear.
 */
void pm_line_offset_list_clear(pm_line_offset_list_t *list);

/**
 * Append a new offset to the list. Returns true if the reallocation of the
 * offsets succeeds (if one was necessary), otherwise returns false.
 *
 * @param list The list to append to.
 * @param cursor The offset to append.
 * @return True if the reallocation of the offsets succeeds (if one was
 *     necessary), otherwise false.
 */
bool pm_line_offset_list_append(pm_line_offset_list_t *list, uint32_t cursor);

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

/**
 * Returns the line and column of the given offset. If the offset is not in the
 * list, the line and column of the closest offset less than the given offset
 * are returned.
 *
 * @param list The list to search.
 * @param cursor The offset to search for.
 * @param start_line The line to start counting from.
 * @return The line and column of the given offset.
 */
pm_line_column_t pm_line_offset_list_line_column(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line);

/**
 * Free the internal memory allocated for the list.
 *
 * @param list The list to free.
 */
void pm_line_offset_list_free(pm_line_offset_list_t *list);

#endif
