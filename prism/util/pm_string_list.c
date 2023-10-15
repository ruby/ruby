#include "prism/util/pm_string_list.h"

// Initialize a pm_string_list_t with its default values.
void
pm_string_list_init(pm_string_list_t *string_list) {
    string_list->strings = (pm_string_t *) malloc(sizeof(pm_string_t));
    string_list->length = 0;
    string_list->capacity = 1;
}

// Append a pm_string_t to the given string list.
void
pm_string_list_append(pm_string_list_t *string_list, pm_string_t *string) {
    if (string_list->length + 1 > string_list->capacity) {
        pm_string_t *original_string = string_list->strings;
        string_list->capacity *= 2;
        string_list->strings = (pm_string_t *) malloc(string_list->capacity * sizeof(pm_string_t));
        memcpy(string_list->strings, original_string, (string_list->length) * sizeof(pm_string_t));
        free(original_string);
    }

    string_list->strings[string_list->length++] = *string;
}

// Free the memory associated with the string list.
void
pm_string_list_free(pm_string_list_t *string_list) {
    free(string_list->strings);
}
