/* public domain rewrite of strchr(3) and strrchr(3) */

char *
strchr(s, c)
    char *s;
    int c;
{
    if (c == 0) return s + strlen(s);
    while (*s) {
	if (*s == c)
	    return s;
	s++;
    }
    return 0;
}

char *
strrchr(s, c)
    char *s;
    int c;
{
    char *save = 0;

    while (*s) {
	if (*s == c)
	    save = s;
	s++;
    }
    return save;
}
