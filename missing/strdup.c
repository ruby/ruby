/************************************************

  strdup.c -

  $Author: matz $
  $Date: 1994/12/09 09:47:57 $
  created at: Wed Dec  7 15:34:01 JST 1994

************************************************/
#include <stdio.h>

char *
strdup(str)
    char *str;
{
    extern char *xmalloc();
    char *tmp;
    int len = strlen(str) + 1;

    tmp = xmalloc(len);
    if (tmp == NULL) return NULL;
    memcpy(tmp, str, len);

    return tmp;
}
