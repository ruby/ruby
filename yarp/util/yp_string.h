#ifndef YARP_STRING_H
#define YARP_STRING_H

#include <stddef.h>
#include <stdlib.h>

// This struct represents a string value.
typedef struct {
  enum { YP_STRING_SHARED, YP_STRING_OWNED, YP_STRING_CONSTANT } type;

  union {
    struct {
      const char *start;
      const char *end;
    } shared;

    struct {
      char *source;
      size_t length;
    } owned;

    struct {
      const char *source;
      size_t length;
    } constant;
  } as;
} yp_string_t;

// Allocate a new yp_string_t.
yp_string_t *
yp_string_alloc(void);

// Initialize a shared string that is based on initial input.
void
yp_string_shared_init(yp_string_t *string, const char *start, const char *end);

// Initialize an owned string that is responsible for freeing allocated memory.
void
yp_string_owned_init(yp_string_t *string, char *source, size_t length);

// Initialize a constant string that doesn't own its memory source.
void
yp_string_constant_init(yp_string_t *string, const char *source, size_t length);

// Returns the memory size associated with the string.
size_t
yp_string_memsize(const yp_string_t *string);

// Returns the length associated with the string.
__attribute__ ((__visibility__("default"))) extern size_t
yp_string_length(const yp_string_t *string);

// Returns the start pointer associated with the string.
__attribute__ ((__visibility__("default"))) extern const char *
yp_string_source(const yp_string_t *string);

// Free the associated memory of the given string.
__attribute__((__visibility__("default"))) extern void
yp_string_free(yp_string_t *string);

#endif // YARP_STRING_H
