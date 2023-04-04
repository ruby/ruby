#include "yarp/include/yarp/util/yp_string.h"

// Allocate a new yp_string_t.
yp_string_t *
yp_string_alloc(void) {
  return (yp_string_t *) malloc(sizeof(yp_string_t));
}

// Initialize a shared string that is based on initial input.
void
yp_string_shared_init(yp_string_t *string, const char *start, const char *end) {
  *string = (yp_string_t) {
    .type = YP_STRING_SHARED,
    .as.shared = {
      .start = start,
      .end = end
    }
  };
}

// Initialize an owned string that is responsible for freeing allocated memory.
void
yp_string_owned_init(yp_string_t *string, char *source, size_t length) {
  *string = (yp_string_t) {
    .type = YP_STRING_OWNED,
    .as.owned = {
      .source = source,
      .length = length
    }
  };
}

// Initialize a constant string that doesn't own its memory source.
void
yp_string_constant_init(yp_string_t *string, const char *source, size_t length) {
  *string = (yp_string_t) {
    .type = YP_STRING_CONSTANT,
    .as.constant = {
      .source = source,
      .length = length
    }
  };
}

// Returns the memory size associated with the string.
size_t
yp_string_memsize(const yp_string_t *string) {
  size_t size = sizeof(yp_string_t);
  if (string->type == YP_STRING_OWNED) {
    size += string->as.owned.length;
  }
  return size;
}

// Ensure the string is owned. If it is not, then reinitialize it as owned and
// copy over the previous source.
void
yp_string_ensure_owned(yp_string_t *string) {
  if (string->type == YP_STRING_OWNED) return;

  size_t length = yp_string_length(string);
  const char *source = yp_string_source(string);

  yp_string_owned_init(string, malloc(length), length);
  memcpy(string->as.owned.source, source, length);
}

// Returns the length associated with the string.
__attribute__ ((__visibility__("default"))) extern size_t
yp_string_length(const yp_string_t *string) {
  if (string->type == YP_STRING_SHARED) {
    return (size_t) (string->as.shared.end - string->as.shared.start);
  } else {
    return string->as.owned.length;
  }
}

// Returns the start pointer associated with the string.
__attribute__ ((__visibility__("default"))) extern const char *
yp_string_source(const yp_string_t *string) {
  if (string->type == YP_STRING_SHARED) {
    return string->as.shared.start;
  } else {
    return string->as.owned.source;
  }
}

// Free the associated memory of the given string.
__attribute__((__visibility__("default"))) extern void
yp_string_free(yp_string_t *string) {
  if (string->type == YP_STRING_OWNED) {
    free(string->as.owned.source);
  }
}
