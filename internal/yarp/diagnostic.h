#ifndef YARP_DIAGNOSTIC_H
#define YARP_DIAGNOSTIC_H

#include "yarp/defines.h"

#include <stdlib.h>

#include "yarp/util/yp_list.h"

// This struct represents a diagnostic found during parsing.
typedef struct {
  yp_list_node_t node;
  const char *start;
  const char *end;
  const char *message;
} yp_diagnostic_t;

// Append a diagnostic to the given list of diagnostics.
void
yp_diagnostic_list_append(yp_list_t *list, const char *start, const char *end, const char *message);

// Deallocate the internal state of the given diagnostic list.
void
yp_diagnostic_list_free(yp_list_t *list);

#endif
