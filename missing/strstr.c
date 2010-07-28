/* public domain rewrite of strstr(3) */

#include "missing.h"

char *
strstr(haystack, needle)
    char *haystack, *needle;
{
    char *hend;
    char *a, *b;

    if (*needle == 0) return haystack;
    hend = haystack + strlen(haystack) - strlen(needle) + 1;
    while (haystack < hend) {
	if (*haystack == *needle) {
	    a = haystack;
	    b = needle;
	    for (;;) {
		if (*b == 0) return haystack;
		if (*a++ != *b++) {
		    break;
		}
	    }
	}
	haystack++;
    }
    return 0;
}
