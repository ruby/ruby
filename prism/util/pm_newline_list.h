// When compiling the syntax tree, it's necessary to know the line and column
// of many nodes. This is necessary to support things like error messages,
// tracepoints, etc.
//
// It's possible that we could store the start line, start column, end line, and
// end column on every node in addition to the offsets that we already store,
// but that would be quite a lot of memory overhead.

#ifndef YP_NEWLINE_LIST_H
#define YP_NEWLINE_LIST_H

#include "yarp/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

// A list of offsets of newlines in a string. The offsets are assumed to be
// sorted/inserted in ascending order.
typedef struct {
    const uint8_t *start;

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

#define YP_NEWLINE_LIST_EMPTY ((yp_newline_list_t) { \
    .start = NULL, .offsets = NULL, .size = 0, .capacity = 0, .last_offset = 0, .last_index = 0 \
})

// Initialize a new newline list with the given capacity. Returns true if the
// allocation of the offsets succeeds, otherwise returns false.
bool yp_newline_list_init(yp_newline_list_t *list, const uint8_t *start, size_t capacity);

// Append a new offset to the newline list. Returns true if the reallocation of
// the offsets succeeds (if one was necessary), otherwise returns false.
bool yp_newline_list_append(yp_newline_list_t *list, const uint8_t *cursor);

// Conditionally append a new offset to the newline list, if the value passed in is a newline.
bool yp_newline_list_check_append(yp_newline_list_t *list, const uint8_t *cursor);

// Returns the line and column of the given offset. If the offset is not in the
// list, the line and column of the closest offset less than the given offset
// are returned.
yp_line_column_t yp_newline_list_line_column(yp_newline_list_t *list, const uint8_t *cursor);

// Free the internal memory allocated for the newline list.
void yp_newline_list_free(yp_newline_list_t *list);

#endif
