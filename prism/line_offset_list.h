/**
 * @file line_offset_list.h
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

#include "prism/compiler/exported.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

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
 * Returns the line and column of the given offset. If the offset is not in the
 * list, the line and column of the closest offset less than the given offset
 * are returned.
 *
 * @param list The list to search.
 * @param cursor The offset to search for.
 * @param start_line The line to start counting from.
 * @returns The line and column of the given offset.
 */
PRISM_EXPORTED_FUNCTION pm_line_column_t pm_line_offset_list_line_column(const pm_line_offset_list_t *list, uint32_t cursor, int32_t start_line) PRISM_NONNULL(1);

#endif
