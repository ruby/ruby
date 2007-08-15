/***************************************************************
  wince.c

  author : uema2
  date   : Nov 30, 2002

  You can freely use, copy, modify, and redistribute
  the whole contents.
***************************************************************/

#include <windows.h>
#include <tchar.h>
#include "wince.h"

/* global for GetCommandLineA */
char *_commandLine;

extern char _currentdir[];

/* make up Win32API except wce_* functions.  */

DWORD GetModuleFileNameA( 
	HMODULE hModule, LPSTR lpFileName,
	DWORD size )
{
	LPWSTR lpFileNameW;
	LPSTR  mb;
	size_t ret;

	if( size==0 ) return 0;

	lpFileNameW = (LPWSTR)malloc( size*sizeof(wchar_t) );
	ret = GetModuleFileNameW( hModule, lpFileNameW, size );
	mb = wce_wctomb(lpFileNameW);
	strcpy(lpFileName, mb);
	free(mb);
	free(lpFileNameW);

	return ret;
}

#if _WIN32_WCE < 300
FARPROC GetProcAddressA(HMODULE hModule, LPCSTR lpProcName)
{
	FARPROC p;
	LPWSTR  lpwProcName;

	lpwProcName = wce_mbtowc( lpProcName );
	p = GetProcAddressW( hModule, lpwProcName );
	free( lpwProcName );
	return p;
}
#endif 

char * GetCommandLineA(void)
{
	return _commandLine;
}

/* this is not Win32API. GetCommandLineA helper. */
void wce_SetCommandLine(LPCWSTR wcmd)
{
	char* acmd;

	acmd = wce_wctomb( wcmd );
	_commandLine = (char*)malloc( strlen(acmd)+5 );
	sprintf( _commandLine, "ruby %s", acmd );
	free(acmd);
}

/* this is not Win32API. GetCommandLineA helper. */
void wce_FreeCommandLine(void)
{
	free(_commandLine);
	_commandLine = NULL;
}

/* I have no idea how to replace this. */
BOOL GetProcessTimes(HANDLE hprocess,
	LPFILETIME lpCreationTime, LPFILETIME lpExitTime,
	LPFILETIME lpKernelTime, LPFILETIME lpUserTime) 
{
	return 0;
}

/* --------------  file attributes functions. ------------------- */
DWORD GetFileAttributesA(LPCSTR lpFileName)
{
	LPWSTR lpwFileName;
	DWORD dw;

	lpwFileName = wce_mbtowc(lpFileName);
	dw = GetFileAttributesW(lpwFileName);
	free(lpwFileName);
	return dw;
}

BOOL SetFileAttributesA(
	LPCSTR lpFileName, DWORD attributes) 
{
	LPWSTR lpwFileName;
	BOOL b;

	lpwFileName = wce_mbtowc(lpFileName);
	b = SetFileAttributesW(lpwFileName, attributes);
	free(lpwFileName);
	return b;
}

/* ---------------  move and remove functions. ------------------- */
BOOL MoveFileA(LPCSTR fn1, LPCSTR fn2)
{
	LPWSTR wfn1, wfn2;
	BOOL b;

	wfn1 = wce_mbtowc(fn1);
	wfn2 = wce_mbtowc(fn2);
	b = MoveFileW(wfn1, wfn2);
	free(wfn1);
	free(wfn2);
	return 0;
}

BOOL MoveFileEx(LPCSTR oldname, LPCSTR newname, DWORD dwFlags)
{
	LPWSTR woldname, wnewname;
	BOOL b;

	woldname = wce_mbtowc(oldname);
	wnewname = wce_mbtowc(newname);

	if( (dwFlags&MOVEFILE_REPLACE_EXISTING)!=0 )
		DeleteFileW( wnewname );

	b = MoveFileW( woldname, wnewname );

	free(woldname);
	free(wnewname);

	return b;
}

BOOL DeleteFileA(LPCSTR path)
{ 
	LPWSTR wpath;
	BOOL b;

	wpath = wce_mbtowc(path);
	b = DeleteFileW(wpath);
	free(wpath);
	return 0;
}

/* --------------- EnvironmentVariable functions. ----------------- */
DWORD GetEnvironmentVariable(
	LPCSTR name, LPSTR value, DWORD size)
{
	/* use registry instead of "environment valuable". */
	HKEY	hk;
	LONG	lret;
	LPBYTE	lpData;
	DWORD	dwType=REG_SZ, cbData;
	TCHAR   buf[MAX_PATH]={0};
	LPWSTR  wname;
	LPSTR   avalue;

	lret = RegOpenKeyEx( HKEY_LOCAL_MACHINE,
				_T("Software\\ruby_mswince"),
				0, KEY_QUERY_VALUE, &hk );

	if ( lret != ERROR_SUCCESS )
	{
		strcpy( value, "" );
		return 0;
	}

	lpData = (LPBYTE)buf;
	cbData = MAX_PATH*sizeof(*buf);
	wname  = wce_mbtowc( name );

	lret = RegQueryValueEx( hk, wname,
		NULL, &dwType, lpData, &cbData );
	RegCloseKey( hk );

	if ( lret != ERROR_SUCCESS )
	{
		strcpy( value, "" );
		free( wname );
		return 0;
	}

	avalue = wce_wctomb( (LPCTSTR)lpData );
	strcpy( value, avalue );
	free( avalue );
	free( wname );

	return strlen(value);
}

BOOL SetEnvironmentVariable(LPCSTR name, LPCSTR value)
{
	/* use registry instead of "environment valuable". */
	HKEY	hk;
	LONG	lret;
	LPBYTE	lpData;
	DWORD	ret, dwType=REG_SZ, cbData;
	LPWSTR  wname, wvalue;

	lret = RegCreateKeyEx( HKEY_LOCAL_MACHINE,
			_T("Software\\ruby_mswince"),
			0, _T(""), 0,
			0, NULL, &hk, &ret );
	if( lret != ERROR_SUCCESS )
		return FALSE;

	wname  = wce_mbtowc(name);
	wvalue = wce_mbtowc(value);

	lpData = (LPBYTE)wvalue;
	cbData = (wcslen(wvalue) + 1) * sizeof(*wvalue);
	lret = RegSetValueEx( hk, wname,
		0, dwType, lpData, cbData );
	RegCloseKey( hk );
	free(wname);
	free(wvalue);
	return lret == ERROR_SUCCESS;
}

LPVOID GetEnvironmentStrings(VOID)
{
	return NULL;
}

BOOL FreeEnvironmentStrings(LPSTR lpszEnvironmentBlock)
{
	return FALSE;
}

/* DuplicateHandle, LockFile, etc... */
/* I have no idea...  */
BOOL GenerateConsoleCtrlEvent(DWORD dwCtrlEvent,
		DWORD dwProcessGroupID)
{
	return 0;
}

BOOL DuplicateHandle(
	HANDLE source_process, HANDLE source,
	HANDLE dest_process, HANDLE *dest,
	DWORD access, BOOL inherit, DWORD options)
{
	return 0;
}

BOOL LockFile(HANDLE hFile,
	DWORD dwFileOffsetLow, DWORD dwFileOffsetHigh,
	DWORD nNumberOfBytesToLockLow, DWORD nNumberOfBytesToLockHigh)
{
	return FALSE;
}

BOOL LockFileEx(HANDLE hFile,
	DWORD dwFlags, DWORD dwReserved,
	DWORD nNumberOfBytesToLockLow, DWORD nNumberOfBytesToLockHigh,
	LPOVERLAPPED lpOverlapped)
{
	return FALSE;
}

BOOL UnlockFile( HFILE hFile,
	DWORD dwFileOffsetLow, DWORD dwFileOffsetHigh,
	DWORD nNumberOfBytesToUnlockLow, DWORD nNumberOfBytesToUnlockHigh)
{
	return FALSE;
}

BOOL UnlockFileEx(HANDLE hFile,
	DWORD dwReserved, DWORD nNumberOfBytesToUnlockLow,
	DWORD nNumberOfBytesToUnlockHigh, LPOVERLAPPED lpOverlapped)
{
	return FALSE;
}

/* --------------------- etc, etc, etc... ----------------------- */
BOOL GetVersionExA(OSVERSIONINFOA *v)
{
	OSVERSIONINFOW wv;
	BOOL b;
	LPSTR mb;

	b = GetVersionExW(&wv);
	mb = wce_wctomb(wv.szCSDVersion);

	strcpy( v->szCSDVersion, mb );
	free(mb);
	return b;
}

DWORD WaitForMultipleObjectsEx(DWORD count,
	const HANDLE *handles, BOOL wait_all,
	DWORD timeout, BOOL alertable)
{
	return WaitForMultipleObjects(
		count, handles, wait_all,
		timeout );
}

BOOL CreateProcessA(LPCSTR appname, LPCSTR commandline,
	LPSECURITY_ATTRIBUTES att, LPSECURITY_ATTRIBUTES threadatt,
	BOOL bOpt, DWORD dwFlag, LPVOID lpEnv, LPSTR dir,
	LPSTARTUPINFO lpsi, LPPROCESS_INFORMATION lppi)
{
	LPWSTR wappname, wcommandline, wdir;
	BOOL b;

	wappname     = wce_mbtowc(appname);
	wcommandline = wce_mbtowc(commandline);
	wdir         = wce_mbtowc(dir);

	b = CreateProcessW(wappname, wcommandline,
			att, threadatt, bOpt, dwFlag, lpEnv,
			wdir, lpsi, lppi);

	free(wappname);
	free(wcommandline);
	free(wdir);

	return b;
}

HANDLE CreateEventA(SECURITY_ATTRIBUTES *sa, 
	BOOL manual_reset, BOOL initial_state, LPCSTR name)
{
	HANDLE h;
	LPWSTR wname;

	wname = wce_mbtowc(name);
	h = CreateEventW(sa, manual_reset,
		initial_state, wname);
	free(wname);

	return h;
}

DWORD FormatMessageA(DWORD dwFlags, LPCVOID lpSource, 
	DWORD dwMessageId, DWORD dwLanguageId, LPSTR lpBuffer, 
	DWORD nSize, va_list* args)
{
	DWORD dw;
	LPWSTR lpWBuffer;

	lpWBuffer = wce_mbtowc(lpBuffer);
	dw = FormatMessageW( dwFlags, lpSource,
			dwMessageId, dwLanguageId,
			lpWBuffer, nSize, (va_list*)args );
	free(lpWBuffer);
	return dw;
}

/*---------------- FindFirstFile, FindNextFile ------------------ */
HANDLE FindFirstFileA(LPCSTR path,
			WIN32_FIND_DATAA *data)
{
	LPWSTR wpath;
	LPSTR  mb;
	HANDLE h;
	WIN32_FIND_DATAW wdata;

	wpath = wce_mbtowc(path);
	h = FindFirstFileW( wpath, &wdata );
	free(wpath);
	
	mb = wce_wctomb( wdata.cFileName );
	strcpy( data->cFileName, mb );
	free(mb);

	return h;
}

BOOL FindNextFileA(HANDLE handle,
	WIN32_FIND_DATAA *data)
{
	BOOL b;
	WIN32_FIND_DATAW wdata;
	LPSTR mb1;

	b = FindNextFileW(handle, &wdata);

	mb1 = wce_wctomb( wdata.cFileName );
	strcpy( data->cFileName, mb1 );
	free(mb1);

	return b;
}

/* CreateFile doesn't support SECURITY_ATTRIBUTES in WinCE. */
/* it must be NULL. */
HANDLE CreateFileA(LPCSTR filename, DWORD access,
	DWORD sharing, LPSECURITY_ATTRIBUTES sa,
	DWORD creation, DWORD attributes, HANDLE template)
{
	LPWSTR wfilename;
	HANDLE h;

	wfilename = wce_mbtowc(filename);
	h = CreateFileW(wfilename, access, sharing,
			NULL, creation, 0, NULL);
	free(wfilename);

	return 0;
}

/* ---------------- CharNext, CharPrev. ---------------------*/
LPSTR CharNextA(LPCSTR a)
{
	char *p=(char *)a;
	if( TRUE==IsDBCSLeadByteEx(CP_ACP, (BYTE)*a) )
		p+=2;
	else
		p++;

	return p;
}

LPSTR CharPrevA(LPCSTR start, LPCSTR ptr)
{
	if( start==ptr ) return (LPSTR)start;
	else if( start+1==ptr ) return (LPSTR)start;
	else if( TRUE==IsDBCSLeadByteEx(CP_ACP, (BYTE)*(ptr-2)) )
		return (LPSTR)(ptr-2);
	else
		return (LPSTR)(ptr-1);
}

/* WinCE doesn't have "drives". */
DWORD GetLogicalDrives(VOID)
{
	return 0;
}

/* WinCE doesn't have "user name". */
BOOL GetUserName(LPSTR lpBuffer, LPDWORD nSize)
{
	return 0;
}

/*------------------- LoadLibrary -----------------------*/
HINSTANCE LoadLibraryA(LPCSTR libname)
{
	HINSTANCE h;
	LPWSTR wlibname;

	// if starts ".\", replace current directory.
//	wlibname = wce_replaceRelativeDir(libname);

	wlibname = wce_mbtowc(libname);
	h = LoadLibraryW(wlibname);
	free(wlibname);
	return h;
}

HINSTANCE LoadLibraryExA(LPCSTR lpLibFileName, HANDLE hFile,
			DWORD dwFlags)
{
	HINSTANCE h;
	LPWSTR wlibname;

	wlibname = wce_mbtowc(lpLibFileName);
//	wlibname = wce_replaceRelativeDir(lpLibFileName);

#if _WIN32_WCE < 300
	h = LoadLibraryW(wlibname);
#else
	h = LoadLibraryExW(wlibname, hFile, dwFlags);
#endif
	free(wlibname);
	return h;
}

/* WinCE doesn't have "CreatePipe". */
BOOL CreatePipe(PHANDLE hReadPipe, PHANDLE hWritePipe,
	LPSECURITY_ATTRIBUTES lpPipeAttributes, DWORD nSize)
{
	return FALSE;
}

/* WinCE doesn't have "Standard Devices". */
HANDLE GetStdHandle(DWORD nStdHandle)
{
	return NULL;
}

BOOL SetStdHandle(DWORD nStdHandle, HANDLE h)
{
	return FALSE;
}

#if _WIN32_WCE < 300
VOID ZeroMemory(PVOID p, DWORD length)
{
	memset(p,0,length);
}
#endif


/* need in ruby/io.c. */
int ReadDataPending()
{
	return 0;
}

/*---------------- helper functions. ---------------------------- */
FILE *wce_fopen( const char *fname, const char *mode )
{
	TCHAR* tfname = wce_replaceRelativeDir(fname);
	TCHAR* tmode = wce_mbtowc(mode);
	FILE* fp = _tfopen(tfname, tmode);
	free(tfname); free(tmode);
	return fp;
}

void wce_SetCurrentDir()
{
	WCHAR tbuf[MAX_PATH+1]={0};
	WCHAR *tp;
	char *buf;

	GetModuleFileNameW( NULL, tbuf, MAX_PATH );
	tp = _tcsrchr( tbuf, '\\' );
	if( tp!=NULL ) *tp=_T('\0');
	buf = wce_wctomb(tbuf);
	strcpy( _currentdir, buf );
	free(buf);
}

TCHAR *wce_replaceRelativeDir(const char* str)
{
	TCHAR *tbuf;

	if( 2<=strlen(str) && str[0]=='.' &&
		(str[1]=='/' || str[1]=='\\') )
	{
		char *buf;
		int len = strlen(str) + strlen(_currentdir);
		buf = malloc( len+1 );
		sprintf(buf, "%s%s", _currentdir, &str[1]);
		tbuf = wce_mbtowc(buf);
		free(buf);
	}
	else
		tbuf = wce_mbtowc(str);
	return tbuf;
}

/* char -> wchar_t */
wchar_t* wce_mbtowc(const char* a)
{
	int length;
	wchar_t *wbuf;

	length = MultiByteToWideChar(CP_ACP, 0, 
		a, -1, NULL, 0);
	wbuf = (wchar_t*)malloc( (length+1)*sizeof(wchar_t) );
	MultiByteToWideChar(CP_ACP, 0,
		a, -1, wbuf, length);

	return wbuf;
}

/* wchar_t -> char */
char* wce_wctomb(const wchar_t* w)
{
	DWORD charlength;
	char* pChar;

	charlength = WideCharToMultiByte(CP_ACP, 0, w,
					-1, NULL, 0, NULL, NULL);
	pChar = (char*)malloc(charlength+1);
	WideCharToMultiByte(CP_ACP, 0, w,
		-1, pChar, charlength, NULL, NULL);

	return pChar;
}
