#include "yarp/util/yp_string_list.h"

// Initialize a yp_string_list_t with its default values.
void
yp_string_list_init(yp_string_list_t *string_list) {
    string_list->strings = (yp_string_t *) malloc(sizeof(yp_string_t));
    string_list->length = 0;
    string_list->capacity = 1;
}

// Append a yp_string_t to the given string list.
void
yp_string_list_append(yp_string_list_t *string_list, yp_string_t *string) {
    if (string_list->length + 1 > string_list->capacity) {
        yp_string_t *original_string = string_list->strings;
        string_list->capacity *= 2;
        string_list->strings = (yp_string_t *) malloc(string_list->capacity * sizeof(yp_string_t));
        memcpy(string_list->strings, original_string, (string_list->length) * sizeof(yp_string_t));
        free(original_string);
    }

    string_list->strings[string_list->length++] = *string;
}

// Free the memory associated with the string list.
void
yp_string_list_free(yp_string_list_t *string_list) {
    free(string_list->strings);
}
