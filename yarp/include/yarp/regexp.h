#ifndef YARP_REGEXP_H
#define YARP_REGEXP_H

#include "parser.h"
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include "yarp/include/yarp/util/yp_string_list.h"
#include "yarp/include/yarp/util/yp_string.h"

// Parse a regular expression and extract the names of all of the named capture
// groups.
__attribute__((__visibility__("default"))) extern bool
yp_regexp_named_capture_group_names(const char *source, size_t size,
                                    yp_string_list_t *named_captures);

#endif
