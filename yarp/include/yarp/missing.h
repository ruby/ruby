#ifndef YARP_MISSING_H
#define YARP_MISSING_H

#include <ctype.h>
#include <stddef.h>
#include <string.h>

size_t
yp_strnlen(const char *string, size_t length);

#ifndef HAVE_STRNLEN
#define strnlen yp_strnlen
#endif

const char *
yp_strnstr(const char *haystack, const char *needle, size_t length);

#ifndef HAVE_STRNSTR
#define strnstr yp_strnstr
#endif

int
yp_strncasecmp(const char *string1, const char *string2, size_t length);

#ifndef HAVE_STRNCASECMP
#define strncasecmp yp_strncasecmp
#endif

#endif
