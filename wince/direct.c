/***************************************************************
  direct.c
***************************************************************/

#include <windows.h>
#include <tchar.h>
#include <direct.h>
#include "wince.h" /* for wce_mbtowc */

/* global for chdir, getcwd */
char _currentdir[MAX_PATH+1];


char *getcwd(char* buffer, int maxlen)
{
	strcpy( buffer, _currentdir );
	return buffer;
}

int _chdir(const char * dirname)
{
	if( MAX_PATH < strlen(dirname) )
		return -1;

	strcpy( _currentdir, dirname );
	return 0;
}

int _rmdir(const char * dir)
{
	wchar_t *wdir;
	BOOL rc;

	/* replace with RemoveDirectory. */
	wdir = wce_mbtowc(dir);
	rc = RemoveDirectoryW(wdir);
	free(wdir);

	return rc==TRUE ? 0 : -1;
}

int _mkdir(const char * dir)
{
	wchar_t* wdir;
	BOOL rc;

	/* replace with CreateDirectory. */
	wdir = wce_mbtowc(dir);
	rc = CreateDirectoryW(wdir, NULL);
	free(wdir);

	return rc==TRUE ? 0 : -1;
}

