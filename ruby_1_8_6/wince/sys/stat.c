/***************************************************************
  stat.c

  author : uema2
  date   : Nov 30, 2002

  You can freely use, copy, modify, and redistribute
  the whole contents.
***************************************************************/

#include <windows.h>
#include <sys/stat.h>
#include <time.h>
#include "..\wince.h" /* for wce_mbtowc */


int _stat(const char *filename, struct _stat *st)
{
	DWORD dwAttribute;
	HANDLE h;
	DWORD dwSizeLow=0, dwSizeHigh=0, dwError=0;
	WIN32_FIND_DATAW fd;
	wchar_t *wfilename;

//	wfilename = wce_mbtowc(filename);
	wfilename = wce_replaceRelativeDir(filename);

	dwAttribute = GetFileAttributesW(wfilename);
	if(dwAttribute==0xFFFFFFFF)
	{
		free(wfilename);
		return -1;
	}

	st->st_mode = 0;
	if((dwAttribute & FILE_ATTRIBUTE_DIRECTORY) != 0)
		st->st_mode += S_IFDIR;
	else
		st->st_mode += S_IFREG;

	/* initialize */
	st->st_atime = 0;
    st->st_mtime = 0;
    st->st_ctime = 0;
	st->st_size  = 0;
	st->st_dev   = 0;

	h = FindFirstFileW(wfilename, &fd);
	if(h == INVALID_HANDLE_VALUE)
	{
		if(wfilename[wcslen(wfilename)-1]	== L'\\')
		{
			wfilename[wcslen(wfilename)-1] = L'\0';
			h = FindFirstFileW(wfilename, &fd);
			if(h == INVALID_HANDLE_VALUE)
			{
				free(wfilename);
				return 0;
			}
		}
		else
		{
			free(wfilename);
			return 0;
		}
	}

	/* FILETIME -> time_t */
	st->st_atime = wce_FILETIME2time_t(&fd.ftLastAccessTime);
    st->st_mtime = wce_FILETIME2time_t(&fd.ftLastWriteTime);
    st->st_ctime = wce_FILETIME2time_t(&fd.ftCreationTime);
	st->st_size  = fd.nFileSizeLow;

	FindClose( h );
	free(wfilename);
	return 0;
}

int fstat(int file, struct stat *sbuf)
{
	/* GetFileSize & GetFileTime */
	DWORD dwSize;
	FILETIME ctime, atime, mtime;

	dwSize = GetFileSize( (HANDLE)file, NULL );
	if( dwSize == 0xFFFFFFFF )
		return -1;

	sbuf->st_size = dwSize;
	sbuf->st_dev  = 0;
	sbuf->st_rdev = 0;
	sbuf->st_mode = _S_IFREG;
	sbuf->st_nlink= 1;

	GetFileTime( (HANDLE)file, &ctime, &atime, &mtime );
	sbuf->st_ctime = wce_FILETIME2time_t(&ctime);
	sbuf->st_atime = wce_FILETIME2time_t(&atime);
	sbuf->st_mtime = wce_FILETIME2time_t(&mtime);

	return 0;
}

