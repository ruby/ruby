/***************************************************************
  string.c
***************************************************************/

#include <windows.h>
#include "wince.h" /* for wce_mbtowc */

extern char* rb_w32_strerror(int errno);

/* _strdup already exists in stdlib.h? */
char *strdup(const char * str)
{
	char *p;

	p = malloc( strlen(str)+1 );
	strcpy( p, str );
	return p;
}

/* strerror shoud replace with rb_w32_strerror. */
char* strerror(int errno)
{
	return rb_w32_strerror(errno);
}

/* _strnicmp already exists in stdlib.h? */
int _strnicmp( const char *s1, const char *s2, size_t count )
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
	for( pp=(char*)p+strlen(p); pp!=p; p-- )
	{
		if( *pp==c ) break;
	}
	return pp==p ? NULL : pp;
}

int _stricmp( const char *s1, const char *s2 )
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
#endif
