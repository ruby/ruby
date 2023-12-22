#include "prism/util/pm_string_list.h"

/**
 * Append a pm_string_t to the given string list.
 */
void
pm_string_list_append(pm_string_list_t *string_list, pm_string_t *string) {
    if (string_list->length + 1 > string_list->capacity) {
        if (string_list->capacity == 0) {
            string_list->capacity = 1;
        } else {
            string_list->capacity *= 2;
        }

        string_list->strings = realloc(string_list->strings, string_list->capacity * sizeof(pm_string_t));
        if (string_list->strings == NULL) abort();
    }

    string_list->strings[string_list->length++] = *string;
}

/**
 * Free the memory associated with the string list
 */
void
pm_string_list_free(pm_string_list_t *string_list) {
    free(string_list->strings);
}
