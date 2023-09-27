#ifndef YARP_STRING_H
#define YARP_STRING_H

#include "yarp/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// This struct represents a string value.
typedef struct {
    enum { YP_STRING_SHARED, YP_STRING_OWNED, YP_STRING_CONSTANT, YP_STRING_MAPPED } type;
    const uint8_t *source;
    size_t length;
} yp_string_t;

#define YP_EMPTY_STRING ((yp_string_t) { .type = YP_STRING_CONSTANT, .source = NULL, .length = 0 })

// Initialize a shared string that is based on initial input.
void yp_string_shared_init(yp_string_t *string, const uint8_t *start, const uint8_t *end);

// Initialize an owned string that is responsible for freeing allocated memory.
void yp_string_owned_init(yp_string_t *string, uint8_t *source, size_t length);

// Initialize a constant string that doesn't own its memory source.
void yp_string_constant_init(yp_string_t *string, const char *source, size_t length);

// Read the file indicated by the filepath parameter into source and load its
// contents and size into the given yp_string_t.
// The given yp_string_t should be freed using yp_string_free() when it is no longer used.
//
// We want to use demand paging as much as possible in order to avoid having to
// read the entire file into memory (which could be detrimental to performance
// for large files). This means that if we're on windows we'll use
// `MapViewOfFile`, on POSIX systems that have access to `mmap` we'll use
// `mmap`, and on other POSIX systems we'll use `read`.
YP_EXPORTED_FUNCTION bool yp_string_mapped_init(yp_string_t *string, const char *filepath);

// Returns the memory size associated with the string.
size_t yp_string_memsize(const yp_string_t *string);

// Ensure the string is owned. If it is not, then reinitialize it as owned and
// copy over the previous source.
void yp_string_ensure_owned(yp_string_t *string);

// Returns the length associated with the string.
YP_EXPORTED_FUNCTION size_t yp_string_length(const yp_string_t *string);

// Returns the start pointer associated with the string.
YP_EXPORTED_FUNCTION const uint8_t * yp_string_source(const yp_string_t *string);

// Free the associated memory of the given string.
YP_EXPORTED_FUNCTION void yp_string_free(yp_string_t *string);

// Returns the size of the yp_string_t struct. This is necessary to allocate the
// correct amount of memory in the FFI backend.
YP_EXPORTED_FUNCTION size_t yp_string_sizeof(void);

#endif // YARP_STRING_H
