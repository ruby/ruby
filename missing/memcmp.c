/*
 * memcmp --- compare memories.
 *
 */

int
memcmp(s1,s2,len)
    char *s1;
    char *s2;
    register int len;
{
    register unsigned char *a = (unsigned char*)s1;
    register unsigned char *b = (unsigned char*)s2;
    register int tmp;

    while (len--) {
	if (tmp = *a++ - *b++)
	    return tmp;
    }
    return 0;
}
