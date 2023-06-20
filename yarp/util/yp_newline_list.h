// When compiling the syntax tree, it's necessary to know the line and column
// of many nodes. This is necessary to support things like error messages,
// tracepoints, etc.
//
// It's possible that we could store the start line, start column, end line, and
// end column on every node in addition to the offsets that we already store,
// but that would be quite a lot of memory overhead.

#ifndef YP_NEWLINE_LIST_H
#define YP_NEWLINE_LIST_H

#include <assert.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>

#include "yarp/defines.h"

// A list of offsets of newlines in a string. The offsets are assumed to be
// sorted/inserted in ascending order.
typedef struct {
    const char *start;

    size_t *offsets;
    size_t size;
    size_t capacity;

    size_t last_offset;
    size_t last_index;
} yp_newline_list_t;

// A line and column in a string.
typedef struct {
    size_t line;
    size_t column;
} yp_line_column_t;

// Initialize a new newline list with the given capacity. Returns true if the
// allocation of the offsets succeeds, otherwise returns false.
bool yp_newline_list_init(yp_newline_list_t *list, const char *start, size_t capacity);

// Append a new offset to the newline list. Returns true if the reallocation of
// the offsets succeeds (if one was necessary), otherwise returns false.
bool yp_newline_list_append(yp_newline_list_t *list, const char *cursor);

// Returns the line and column of the given offset. If the offset is not in the
// list, the line and column of the closest offset less than the given offset
// are returned.
yp_line_column_t yp_newline_list_line_column(yp_newline_list_t *list, const char *cursor);

// Free the internal memory allocated for the newline list.
void yp_newline_list_free(yp_newline_list_t *list);

#endif
