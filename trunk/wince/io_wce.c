/***************************************************************
  io.c

  author : uema2
  date   : Nov 30, 2002

  You can freely use, copy, modify, and redistribute
  the whole contents.
***************************************************************/

#include <windows.h>
#include <stdlib.h>
#include <io.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include "wince.h" /* for wce_mbtowc */

extern int _errno;


int _rename(const char *oldname, const char *newname)
{
	wchar_t *wold, *wnew;
	BOOL rc;

	wold = wce_mbtowc(oldname);
	wnew = wce_mbtowc(newname);

	/* replace with MoveFile. */
	rc = MoveFileW(wold, wnew);

	free(wold);
	free(wnew);

	return rc==TRUE ? 0 : -1;
}

int _unlink(const char *file)
{
	wchar_t *wfile;
	BOOL rc;

	/* replace with DeleteFile. */
	wfile = wce_mbtowc(file);
	rc = DeleteFileW(wfile);
	free(wfile);

	return rc==TRUE ? 0 : -1;
}

/* replace "open" with "CreateFile", etc. */
int _open(const char *file, int mode, va_list arg)
{
	wchar_t *wfile;
	DWORD access=0, share=0, create=0;
	HANDLE h;

	if( (mode&_O_RDWR) != 0 )
		access = GENERIC_READ|GENERIC_WRITE;
	else if( (mode&_O_RDONLY) != 0 )
		access = GENERIC_READ;
	else if( (mode&_O_WRONLY) != 0 )
		access = GENERIC_WRITE;

	if( (mode&_O_CREAT) != 0 )
		create = CREATE_ALWAYS;
	else
		create = OPEN_ALWAYS;

	wfile = wce_mbtowc(file);

	h = CreateFileW(wfile, access, share, NULL,
			create, 0, NULL );

	free(wfile);
	return (int)h;
}

int close(int fd)
{
	CloseHandle( (HANDLE)fd );
	return 0;
}

int _read(int fd, void *buffer, int length)
{
	DWORD dw;
	ReadFile( (HANDLE)fd, buffer, length, &dw, NULL );
	return (int)dw;
}

int _write(int fd, const void *buffer, unsigned count)
{
	DWORD dw;
	WriteFile( (HANDLE)fd, buffer, count, &dw, NULL );
	return (int)dw;
}

long _lseek(int handle, long offset, int origin)
{
	DWORD flag, ret;

	switch(origin)
	{
	case SEEK_SET: flag = FILE_BEGIN;   break;
	case SEEK_CUR: flag = FILE_CURRENT; break;
	case SEEK_END: flag = FILE_END;     break;
	default:       flag = FILE_CURRENT; break;
	}

	ret = SetFilePointer( (HANDLE)handle, offset, NULL, flag );
	return ret==0xFFFFFFFF ? -1 : 0;
}

/* _findfirst, _findnext, _findclose. */
/* replace them with FindFirstFile, etc. */
long _findfirst( char *file, struct _finddata_t *fi )
{
	HANDLE h;
	WIN32_FIND_DATAA fda;

	h = FindFirstFileA( file, &fda );
	if( h==NULL )
	{
		errno = EINVAL; return -1;
	}

	fi->attrib      = fda.dwFileAttributes;
	fi->time_create = wce_FILETIME2time_t( &fda.ftCreationTime );
	fi->time_access = wce_FILETIME2time_t( &fda.ftLastAccessTime );
	fi->time_write  = wce_FILETIME2time_t( &fda.ftLastWriteTime );
	fi->size        = fda.nFileSizeLow + (fda.nFileSizeHigh<<32);
	strcpy( fi->name, fda.cFileName );

	return (long)h;
}

int _findnext( long handle, struct _finddata_t *fi )
{
	WIN32_FIND_DATAA fda;
	BOOL b;

	b = FindNextFileA( (HANDLE)handle, &fda );

	if( b==FALSE )
	{
		errno = ENOENT; return -1;
	}

	fi->attrib      = fda.dwFileAttributes;
	fi->time_create = wce_FILETIME2time_t( &fda.ftCreationTime );
	fi->time_access = wce_FILETIME2time_t( &fda.ftLastAccessTime );
	fi->time_write  = wce_FILETIME2time_t( &fda.ftLastWriteTime );
	fi->size        = fda.nFileSizeLow + (fda.nFileSizeHigh<<32);
	strcpy( fi->name, fda.cFileName );

	return 0;
}

int _findclose( long handle )
{
	BOOL b;
	b = FindClose( (HANDLE)handle );
	return b==FALSE ? -1 : 0;
}

/* below functions unsupported... */
/* I have no idea how to replace... */
int _chsize(int handle, long size)
{
	errno = EACCES;
	return -1;
}

int _umask(int cmask)
{
	return 0;
}

int _chmod(const char *path, int mode)
{
	return 0;
}

/* WinCE doesn't have dup and dup2.  */
/* so, we cannot use missing/dup2.c. */
int dup( int handle )
{
	errno = EBADF;
	return -1;
}
/*
int dup2( int handle1, int handle2 )
{
	errno = EBADF;
	return -1;
}
*/
int _isatty(int fd)
{
	if( fd==(int)_fileno(stdin) || 
		fd==(int)_fileno(stdout)||
		fd==(int)_fileno(stderr) )
		return 1;
	else
		return 0;
}

int _pipe(int *phandles, unsigned int psize, int textmode)
{
	return -1;
}

int _access(const char *filename, int flags)
{
	return 0;
}

int _open_osfhandle( long osfhandle, int flags)
{
/*	return 0; */
	return (int)osfhandle;
}

long _get_osfhandle( int filehandle )
{
/*	return 0; */
	return (long)filehandle;
}
