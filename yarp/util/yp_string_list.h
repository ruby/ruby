#ifndef YARP_STRING_LIST_H
#define YARP_STRING_LIST_H

#include "yarp/defines.h"

#include <stddef.h>
#include <stdlib.h>

#include "yarp/util/yp_string.h"

typedef struct {
    yp_string_t *strings;
    size_t length;
    size_t capacity;
} yp_string_list_t;

// Allocate a new yp_string_list_t.
yp_string_list_t * yp_string_list_alloc(void);

// Initialize a yp_string_list_t with its default values.
YP_EXPORTED_FUNCTION void yp_string_list_init(yp_string_list_t *string_list);

// Append a yp_string_t to the given string list.
void yp_string_list_append(yp_string_list_t *string_list, yp_string_t *string);

// Free the memory associated with the string list.
YP_EXPORTED_FUNCTION void yp_string_list_free(yp_string_list_t *string_list);

#endif
