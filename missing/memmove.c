/* public domain rewrite of memcmp(3) */

void *
memmove (d, s, n)
    void *d, *s;
    int n;
{
    char *dst = d;
    char *src = s;
    void *ret = dst;

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
