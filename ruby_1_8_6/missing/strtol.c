/* public domain rewrite of strtol(3) */

#include <ctype.h>

long
strtol(nptr, endptr, base)
    char *nptr;
    char **endptr;
    int base;
{
    long result;
    char *p = nptr;

    while (isspace(*p)) {
	p++;
    }
    if (*p == '-') {
	p++;
	result = -strtoul(p, endptr, base);
    }
    else {
	if (*p == '+') p++;
	result = strtoul(p, endptr, base);
    }
    if (endptr != 0 && *endptr == p) {
	*endptr = nptr;
    }
    return result;
}
