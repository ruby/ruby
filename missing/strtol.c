/* 
 * strtol.c --
 *
 *	Source code for the "strtol" library procedure.
 *
 * Copyright 1988 Regents of the University of California
 * Permission to use, copy, modify, and distribute this
 * software and its documentation for any purpose and without
 * fee is hereby granted, provided that the above copyright
 * notice appear in all copies.  The University of California
 * makes no representations about the suitability of this
 * software for any purpose.  It is provided "as is" without
 * express or implied warranty.
 */

#include <ctype.h>


/*
 *----------------------------------------------------------------------
 *
 * strtol --
 *
 *	Convert an ASCII string into an integer.
 *
 * Results:
 *	The return value is the integer equivalent of string.  If endPtr
 *	is non-NULL, then *endPtr is filled in with the character
 *	after the last one that was part of the integer.  If string
 *	doesn't contain a valid integer value, then zero is returned
 *	and *endPtr is set to string.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

long int
strtol(string, endPtr, base)
    char *string;		/* String of ASCII digits, possibly
				 * preceded by white space.  For bases
				 * greater than 10, either lower- or
				 * upper-case digits may be used.
				 */
    char **endPtr;		/* Where to store address of terminating
				 * character, or NULL. */
    int base;			/* Base for conversion.  Must be less
				 * than 37.  If 0, then the base is chosen
				 * from the leading characters of string:
				 * "0x" means hex, "0" means octal, anything
				 * else means decimal.
				 */
{
    register char *p;
    int result;

    /*
     * Skip any leading blanks.
     */

    p = string;
    while (isspace(*p)) {
	p += 1;
    }

    /*
     * Check for a sign.
     */

    if (*p == '-') {
	p += 1;
	result = -(strtoul(p, endPtr, base));
    } else {
	if (*p == '+') {
	    p += 1;
	}
	result = strtoul(p, endPtr, base);
    }
    if ((result == 0) && (endPtr != 0) && (*endPtr == p)) {
	*endPtr = string;
    }
    return result;
}
