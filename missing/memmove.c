/* public domain rewrite of memcmp(3) */

char *
memmove (dst, src, n)
    char *dst, *src;
    int n;
{
    char *ret = dst;

    if (src < dst) {
	src += n;
	dst += n;
	while (n--)
	    *--dst = *--src;
    }
    else if (dst < src)
	while (n--)
	    *dst++ = *src++;
    return ret;
}
