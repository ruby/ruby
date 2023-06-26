#ifndef YARP_MISSING_H
#define YARP_MISSING_H

#include "yarp/defines.h"

#include <ctype.h>
#include <stddef.h>
#include <string.h>

const char * yp_strnstr(const char *haystack, const char *needle, size_t length);

int yp_strncasecmp(const char *string1, const char *string2, size_t length);

#ifndef HAVE_STRNCASECMP
#ifndef strncasecmp
#define strncasecmp yp_strncasecmp
#endif
#endif

#endif
