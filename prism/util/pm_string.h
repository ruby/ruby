#ifndef PRISM_STRING_H
#define PRISM_STRING_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// This struct represents a string value.
typedef struct {
    const uint8_t *source;
    size_t length;
    // This field is not the first one, because otherwise things like .pm_string_t_field = 123/pm_constant_id_t does not warn or error
    enum { PM_STRING_SHARED, PM_STRING_OWNED, PM_STRING_CONSTANT, PM_STRING_MAPPED } type;
} pm_string_t;

#define PM_EMPTY_STRING ((pm_string_t) { .type = PM_STRING_CONSTANT, .source = NULL, .length = 0 })

// Initialize a shared string that is based on initial input.
void pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end);

// Initialize an owned string that is responsible for freeing allocated memory.
void pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length);

// Initialize a constant string that doesn't own its memory source.
void pm_string_constant_init(pm_string_t *string, const char *source, size_t length);

// Read the file indicated by the filepath parameter into source and load its
// contents and size into the given pm_string_t.
// The given pm_string_t should be freed using pm_string_free() when it is no longer used.
//
// We want to use demand paging as much as possible in order to avoid having to
// read the entire file into memory (which could be detrimental to performance
// for large files). This means that if we're on windows we'll use
// `MapViewOfFile`, on POSIX systems that have access to `mmap` we'll use
// `mmap`, and on other POSIX systems we'll use `read`.
PRISM_EXPORTED_FUNCTION bool pm_string_mapped_init(pm_string_t *string, const char *filepath);

// Returns the memory size associated with the string.
size_t pm_string_memsize(const pm_string_t *string);

// Ensure the string is owned. If it is not, then reinitialize it as owned and
// copy over the previous source.
void pm_string_ensure_owned(pm_string_t *string);

// Returns the length associated with the string.
PRISM_EXPORTED_FUNCTION size_t pm_string_length(const pm_string_t *string);

// Returns the start pointer associated with the string.
PRISM_EXPORTED_FUNCTION const uint8_t * pm_string_source(const pm_string_t *string);

// Free the associated memory of the given string.
PRISM_EXPORTED_FUNCTION void pm_string_free(pm_string_t *string);

// Returns the size of the pm_string_t struct. This is necessary to allocate the
// correct amount of memory in the FFI backend.
PRISM_EXPORTED_FUNCTION size_t pm_string_sizeof(void);

#endif // PRISM_STRING_H
