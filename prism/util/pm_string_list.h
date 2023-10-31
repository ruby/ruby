#ifndef PRISM_STRING_LIST_H
#define PRISM_STRING_LIST_H

#include "prism/defines.h"
#include "prism/util/pm_string.h"

#include <stddef.h>
#include <stdlib.h>

typedef struct {
    pm_string_t *strings;
    size_t length;
    size_t capacity;
} pm_string_list_t;

// Initialize a pm_string_list_t with its default values.
PRISM_EXPORTED_FUNCTION void pm_string_list_init(pm_string_list_t *string_list);

// Append a pm_string_t to the given string list.
void pm_string_list_append(pm_string_list_t *string_list, pm_string_t *string);

// Free the memory associated with the string list.
PRISM_EXPORTED_FUNCTION void pm_string_list_free(pm_string_list_t *string_list);

#endif
