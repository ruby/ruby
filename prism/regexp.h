#ifndef YARP_REGEXP_H
#define YARP_REGEXP_H

#include "yarp/defines.h"
#include "yarp/parser.h"
#include "yarp/enc/yp_encoding.h"
#include "yarp/util/yp_memchr.h"
#include "yarp/util/yp_string_list.h"
#include "yarp/util/yp_string.h"

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// Parse a regular expression and extract the names of all of the named capture
// groups.
YP_EXPORTED_FUNCTION bool yp_regexp_named_capture_group_names(const uint8_t *source, size_t size, yp_string_list_t *named_captures, bool encoding_changed, yp_encoding_t *encoding);

#endif
