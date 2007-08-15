/***************************************************************
  stdio.c
***************************************************************/

#include <windows.h>
#include "wince.h" /* for wce_mbtowc */


FILE *freopen(const char *filename, const char *mode, FILE *file)
{
	wchar_t *wfilename, *wmode;
	FILE *fp;

	wfilename = wce_mbtowc(filename);
	wmode     = wce_mbtowc(mode);

	fp = _wfreopen(wfilename, wmode, file);

	free(wfilename);
	free(wmode);

	return fp;
}

FILE *fdopen( int handle, const char *mode )
{
	wchar_t *wmode;
	FILE* fp;

	wmode = wce_mbtowc(mode);
	fp = _wfdopen( (void*)handle, wmode );

	free(wmode);
	return fp;
}

