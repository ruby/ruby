/************************************************

  util.c -

  $Author$
  $Date$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "defines.h"
#include "config.h"
#include "util.h"
#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
#endif

unsigned long
scan_oct(start, len, retlen)
char *start;
int len;
int *retlen;
{
    register char *s = start;
    register unsigned long retval = 0;

    while (len-- && *s >= '0' && *s <= '7') {
	retval <<= 3;
	retval |= *s++ - '0';
    }
    *retlen = s - start;
    return retval;
}

unsigned long
scan_hex(start, len, retlen)
char *start;
int len;
int *retlen;
{
    static char hexdigit[] = "0123456789abcdef0123456789ABCDEFx";
    register char *s = start;
    register unsigned long retval = 0;
    char *tmp;

    while (len-- && *s && (tmp = strchr(hexdigit, *s))) {
	retval <<= 4;
	retval |= (tmp - hexdigit) & 15;
	s++;
    }
    *retlen = s - start;
    return retval;
}
