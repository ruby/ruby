/***************************************************************
  string.c
***************************************************************/

#include <windows.h>
#include "wince.h" /* for wce_mbtowc */

/* _strdup already exists in stdlib.h? */
char *strdup(const char * str)
{
	char *p;

	p = malloc( strlen(str)+1 );
	strcpy( p, str );
	return p;
}

char* strerror(int errno)
{
	static char buf[32]="wince::strerror called.";
	return buf;
}

/* strnicmp already exists in stdlib.h? */
int strnicmp( const char *s1, const char *s2, size_t count )
{
	wchar_t *w1, *w2;
	int n;

	w1 = wce_mbtowc(s1);
	w2 = wce_mbtowc(s2);

	n = wcsnicmp(w1, w2, count);

	free(w1);
	free(w2);

	return n;
}

#if _WIN32_WCE < 300
#include "..\missing\strtoul.c"

char *strrchr( const char *p, int c )
{
	char *pp;
	for( pp=(char*)p+strlen(p); pp!=p; pp-- )
	{
		if( *pp==c ) break;
	}
	return pp==p ? NULL : pp;
}

int stricmp( const char *s1, const char *s2 )
{
	wchar_t *w1, *w2;
	int n;

	w1 = wce_mbtowc(s1);
	w2 = wce_mbtowc(s2);

	n = wcsicmp(w1, w2);

	free(w1);
	free(w2);

	return n;
}

char *strpbrk(const char *str, const char *cs)
{
	wchar_t *wstr, *wcs, *w;
	char *s = NULL;

	wstr = wce_mbtowc(str);
	wcs  = wce_mbtowc(cs);

	w = wcspbrk(wstr, wcs);

	if( w!=NULL )
		s = str + (wcs-wstr)/sizeof(wchar_t);

	free(wstr);
	free(wcs);

	return s;
}

#endif
