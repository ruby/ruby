#include <ctype.h>

int
strcasecmp(p1, p2)
    char *p1, *p2;
{
    for ( ; *p1 && *p2; p1++, p2++) {
	if (toupper(*p1) != toupper(*p2))
	    return toupper(*p1) - toupper(*p2);
    }
    return strlen(p1) - strlen(p2);
}
