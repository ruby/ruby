#include <ctype.h>

int
strncasecmp(p1, p2, len)
    char *p1;
    char *p2;
    int len;
{
    for (; len != 0; len--, p1++, p2++) {
	if (toupper(*p1) != toupper(*p2)) {
	    return toupper(*p1) - toupper(*p2);
	}
	if (*p1 == '\0') {
	    return 0;
	}
    }
    return 0;
}
