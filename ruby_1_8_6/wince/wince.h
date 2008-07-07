
#ifndef _EXT_CE_
#define _EXT_CE_

/* unique difinition in wince platform. */

#ifndef _MIPS_
  #define CONTEXT_FLOATING_POINT  0x00000002L
#endif

/* LockFile difinition. */
#define LOCKFILE_FAIL_IMMEDIATELY   0x00000001
#define LOCKFILE_EXCLUSIVE_LOCK     0x00000002

/* Dual Mode difinition. */
#define STARTF_USESHOWWINDOW    0x00000001
#define STARTF_USESIZE          0x00000002
#define STARTF_USEPOSITION      0x00000004
#define STARTF_USECOUNTCHARS    0x00000008
#define STARTF_USEFILLATTRIBUTE 0x00000010
#define STARTF_RUNFULLSCREEN    0x00000020
#define STARTF_FORCEONFEEDBACK  0x00000040
#define STARTF_FORCEOFFFEEDBACK 0x00000080
#define STARTF_USESTDHANDLES    0x00000100
/* #define STARTF_USEHOTKEY        0x00000200 */

#define STD_INPUT_HANDLE    (DWORD)-10
#define STD_OUTPUT_HANDLE   (DWORD)-11
#define STD_ERROR_HANDLE    (DWORD)-12

#define NORMAL_PRIORITY_CLASS       0x00000020
#define IDLE_PRIORITY_CLASS         0x00000040
#define HIGH_PRIORITY_CLASS         0x00000080
#define REALTIME_PRIORITY_CLASS     0x00000100


/* WINSOCK.H? */
#define SO_SYNCHRONOUS_NONALERT 0x20

/* MoveFileEx definition. */
#define MOVEFILE_REPLACE_EXISTING       0x00000001
/*
#define MOVEFILE_COPY_ALLOWED           0x00000002
#define MOVEFILE_DELAY_UNTIL_REBOOT     0x00000004
#define MOVEFILE_WRITE_THROUGH          0x00000008
#define MOVEFILE_CREATE_HARDLINK        0x00000010
#define MOVEFILE_FAIL_IF_NOT_TRACKABLE  0x00000020
*/

#define _fgetc fgetc
#define _fputc fputc

#ifdef __cplusplus
extern "C" {
#endif

/* Win32 API redifinition. */

#undef GetCommandLine
#define GetCommandLine GetCommandLineA

#undef SetFileAttributes
#define SetFileAttributes SetFileAttributesA

#undef GetFileAttributes
#define GetFileAttributes GetFileAttributesA

#undef FormatMessage
#define FormatMessage FormatMessageA

#undef GetModuleFileName
#define GetModuleFileName GetModuleFileNameA

#undef CreateFile
#define CreateFile CreateFileA

#undef MoveFile
#define MoveFile MoveFileA

#undef DeleteFile
#define DeleteFile DeleteFileA

#undef CreateProcess
#define CreateProcess CreateProcessA

#undef CharNext
#define CharNext CharNextA

#undef CharPrev
#define CharPrev CharPrevA

#undef WIN32_FIND_DATA
#define WIN32_FIND_DATA WIN32_FIND_DATAA

#undef FindFirstFile
#define FindFirstFile FindFirstFileA

#undef FindNextFile
#define FindNextFile FindNextFileA

/* stdio.c */
FILE *freopen(const char *filename, const char *mode, FILE *file);
FILE *fdopen( int handle, const char *mode );

//#define fdopen _fdopen

/* stdlib.c */
char *getenv(const char *charstuff);
char *_fullpath(char *absPath, const char *relPath, size_t maxLength);

/* string.c */
char *strdup(const char * str);
/* char *strerror(int errno); */
int strnicmp( const char *s1, const char *s2, size_t count );

//#define strnicmp _strnicmp
#define stricmp _stricmp

/* for win32.c */
FARPROC GetProcAddressX(HMODULE hModule, LPCSTR lpProcName);

BOOL MoveFileEx(LPCSTR oldname, LPCSTR newname, DWORD dwFlags);
BOOL DuplicateHandle(
	HANDLE source_process, HANDLE source,
	HANDLE dest_process, HANDLE *dest,
	DWORD access, BOOL inherit, DWORD options);
BOOL LockFile(HANDLE hFile,
	DWORD dwFileOffsetLow, DWORD dwFileOffsetHigh,
	DWORD nNumberOfBytesToLockLow, DWORD nNumberOfBytesToLockHigh);
BOOL LockFileEx(HANDLE hFile,
	DWORD dwFlags, DWORD dwReserved,
	DWORD nNumberOfBytesToLockLow, DWORD nNumberOfBytesToLockHigh,
	LPOVERLAPPED lpOverlapped);
BOOL UnlockFile( HFILE hFile,
	DWORD dwFileOffsetLow, DWORD dwFileOffsetHigh,
	DWORD nNumberOfBytesToUnlockLow, DWORD nNumberOfBytesToUnlockHigh);
BOOL UnlockFileEx(HANDLE hFile,
	DWORD dwReserved, DWORD nNumberOfBytesToUnlockLow,
	DWORD nNumberOfBytesToUnlockHigh, LPOVERLAPPED lpOverlapped);
BOOL GetUserName(LPSTR lpBuffer, LPDWORD nSize);
BOOL CreatePipe(PHANDLE hReadPipe, PHANDLE hWritePipe,
	LPSECURITY_ATTRIBUTES lpPipeAttributes, DWORD nSize);
HANDLE GetStdHandle(DWORD nStdHandle);
BOOL SetStdHandle(DWORD nStdHandle, HANDLE h);
DWORD GetLogicalDrives(VOID);
DWORD WaitForMultipleObjectsEx(DWORD count,
	const HANDLE *handles, BOOL wait_all,
	DWORD timeout, BOOL alertable);
DWORD GetEnvironmentVariable(LPCSTR name, LPSTR value, DWORD size);
LPVOID GetEnvironmentStrings(VOID);
BOOL FreeEnvironmentStrings(LPSTR lpszEnvironmentBlock);
BOOL GenerateConsoleCtrlEvent(DWORD dwCtrlEvent,
		DWORD dwProcessGroupID);
BOOL GetProcessTimes(HANDLE hprocess,
	LPFILETIME lpCreationTime, LPFILETIME lpExitTime,
	LPFILETIME lpKernelTime, LPFILETIME lpUserTime);

/* char -> wchar_t, wchar_t -> char */
wchar_t* wce_mbtowc(const char* a);
char*    wce_wctomb(const wchar_t* w);
/* other helpers. */
void wce_SetCommandLine(LPCWSTR wcmd);
void wce_FreeCommandLine(void);
TCHAR *wce_replaceRelativeDir(const char* str);
void wce_SetCurrentDir();

#if _WIN32_WCE < 300
  /* for Handheld PC Pro. */
  char *strrchr( const char *p, int c );
  int stricmp( const char *p1, const char *p2 );
  VOID ZeroMemory(PVOID p, DWORD length);

  #define isascii(c) ( (c>=0x00&&c<=0x7f)?1:0 )
  #define isspace(c) ( ((c>=0x09&&c<=0x0d)||c==0x20)?1:0 )
  #define isdigit(c) ( (c>=0x00&&c<=0x09)?1:0 )
  #define isupper(c) ( (c>='A'&&c<='Z')?1:0 )
  #define isalpha(c) ( ((c>='A'&&c<='Z')||(c>='a'&&c<='z'))?1:0 )
  #define isprint(c) ( (c>=0x20&&c<=0x7e)?1:0 )
  #define isalnum(c) ( (isalpha(c)||isdigit(c))?1:0 )
  #define iscntrl(c) ( ((c>=0x00&&c<=0x1f)||c==0x7f)?1:0 )
  #define islower(c) ( (c>='a'&&c<='z')?1:0 )
  #define ispunct(c) ( !(isalnum(c)||isspace(c))?1:0 )
  #define isxdigit(c) ( ((c>=0&&c<=9)||(c>='A'&&c<='F')||(c>='a'&&c<='f'))?1:0 )
#endif

#ifdef __cplusplus
};
#endif


#endif /* _EXT_CE_ */
