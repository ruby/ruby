#ifndef PRISM_REGEXP_H
#define PRISM_REGEXP_H

#include "prism/defines.h"
#include "prism/parser.h"
#include "prism/enc/pm_encoding.h"
#include "prism/util/pm_memchr.h"
#include "prism/util/pm_string_list.h"
#include "prism/util/pm_string.h"

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// Parse a regular expression and extract the names of all of the named capture
// groups.
PRISM_EXPORTED_FUNCTION bool pm_regexp_named_capture_group_names(const uint8_t *source, size_t size, pm_string_list_t *named_captures, bool encoding_changed, pm_encoding_t *encoding);

#endif
