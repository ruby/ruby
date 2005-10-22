/* public domain rewrite of strncasecmp(3) */

#include <ctype.h>
#include <stddef.h>

int
strncasecmp(const char *p1, const char *p2, size_t len)
{
    while (len != 0) {
	if (toupper(*p1) != toupper(*p2)) {
	    return toupper(*p1) - toupper(*p2);
	}
	if (*p1 == '\0') {
	    return 0;
	}
	len--; p1++; p2++;
    }
    return 0;
}
