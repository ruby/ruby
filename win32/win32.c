/*
 *  Copyright (c) 1993, Intergraph Corporation
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the perl README file.
 *
 *  Various Unix compatibility functions and NT specific functions.
 *
 *  Some of this code was derived from the MSDOS port(s) and the OS/2 port.
 *
 */

#include "ruby.h"
#include "rubysig.h"
#include "dln.h"
#include <fcntl.h>
#include <process.h>
#include <sys/stat.h>
/* #include <sys/wait.h> */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <ctype.h>

#include <windows.h>
#include <winbase.h>
#include <wincon.h>
#include <shlobj.h>
#if _MSC_VER >= 1400
#include <crtdbg.h>
#endif
#ifdef __MINGW32__
#include <mswsock.h>
#include <mbstring.h>
#endif
#include "win32.h"
#include "win32/dir.h"
#ifdef _WIN32_WCE
#include "wince.h"
#endif
#ifndef index
#define index(x, y) strchr((x), (y))
#endif
#define isdirsep(x) ((x) == '/' || (x) == '\\')

#undef stat
#undef fclose
#undef close
#undef setsockopt

#ifndef bool
#define bool int
#endif

#if defined __BORLANDC__ || defined _WIN32_WCE
#  define _filbuf _fgetc
#  define _flsbuf _fputc
#  define enough_to_get(n) (--(n) >= 0)
#  define enough_to_put(n) (++(n) < 0)
#else
#  define enough_to_get(n) (--(n) >= 0)
#  define enough_to_put(n) (--(n) >= 0)
#endif

#if HAVE_WSAWAITFORMULTIPLEEVENTS
# define USE_INTERRUPT_WINSOCK
#endif

#if USE_INTERRUPT_WINSOCK
# define WaitForMultipleEvents WSAWaitForMultipleEvents
# define CreateSignal() (HANDLE)WSACreateEvent()
# define SetSignal(ev) WSASetEvent(ev)
# define ResetSignal(ev) WSAResetEvent(ev)
#else  /* USE_INTERRUPT_WINSOCK */
# define WaitForMultipleEvents WaitForMultipleObjectsEx
# define CreateSignal() CreateEvent(NULL, FALSE, FALSE, NULL);
# define SetSignal(ev) SetEvent(ev)
# define ResetSignal(ev) (void)0
#endif /* USE_INTERRUPT_WINSOCK */

#ifdef WIN32_DEBUG
#define Debug(something) something
#else
#define Debug(something) /* nothing */
#endif

#define TO_SOCKET(x)	_get_osfhandle(x)

static struct ChildRecord *CreateChild(const char *, const char *, SECURITY_ATTRIBUTES *, HANDLE, HANDLE, HANDLE);
static bool has_redirection(const char *);
static void StartSockets ();
static DWORD wait_events(HANDLE event, DWORD timeout);
#if !defined(_WIN32_WCE)
static int rb_w32_open_osfhandle(long osfhandle, int flags);
#else
#define rb_w32_open_osfhandle(osfhandle, flags) _open_osfhandle(osfhandle, flags)
#endif

/* errno mapping */
static struct {
    DWORD winerr;
    int err;
} errmap[] = {
    {	ERROR_INVALID_FUNCTION,		EINVAL		},
    {	ERROR_FILE_NOT_FOUND,		ENOENT		},
    {	ERROR_PATH_NOT_FOUND,		ENOENT		},
    {	ERROR_TOO_MANY_OPEN_FILES,	EMFILE		},
    {	ERROR_ACCESS_DENIED,		EACCES		},
    {	ERROR_INVALID_HANDLE,		EBADF		},
    {	ERROR_ARENA_TRASHED,		ENOMEM		},
    {	ERROR_NOT_ENOUGH_MEMORY,	ENOMEM		},
    {	ERROR_INVALID_BLOCK,		ENOMEM		},
    {	ERROR_BAD_ENVIRONMENT,		E2BIG		},
    {	ERROR_BAD_FORMAT,		ENOEXEC		},
    {	ERROR_INVALID_ACCESS,		EINVAL		},
    {	ERROR_INVALID_DATA,		EINVAL		},
    {	ERROR_INVALID_DRIVE,		ENOENT		},
    {	ERROR_CURRENT_DIRECTORY,	EACCES		},
    {	ERROR_NOT_SAME_DEVICE,		EXDEV		},
    {	ERROR_NO_MORE_FILES,		ENOENT		},
    {	ERROR_WRITE_PROTECT,		EROFS		},
    {	ERROR_BAD_UNIT,			ENODEV		},
    {	ERROR_NOT_READY,		ENXIO		},
    {	ERROR_BAD_COMMAND,		EACCES		},
    {	ERROR_CRC,			EACCES		},
    {	ERROR_BAD_LENGTH,		EACCES		},
    {	ERROR_SEEK,			EIO		},
    {	ERROR_NOT_DOS_DISK,		EACCES		},
    {	ERROR_SECTOR_NOT_FOUND,		EACCES		},
    {	ERROR_OUT_OF_PAPER,		EACCES		},
    {	ERROR_WRITE_FAULT,		EIO		},
    {	ERROR_READ_FAULT,		EIO		},
    {	ERROR_GEN_FAILURE,		EACCES		},
    {	ERROR_LOCK_VIOLATION,		EACCES		},
    {	ERROR_SHARING_VIOLATION,	EACCES		},
    {	ERROR_WRONG_DISK,		EACCES		},
    {	ERROR_SHARING_BUFFER_EXCEEDED,	EACCES		},
    {	ERROR_BAD_NETPATH,		ENOENT		},
    {	ERROR_NETWORK_ACCESS_DENIED,	EACCES		},
    {	ERROR_BAD_NET_NAME,		ENOENT		},
    {	ERROR_FILE_EXISTS,		EEXIST		},
    {	ERROR_CANNOT_MAKE,		EACCES		},
    {	ERROR_FAIL_I24,			EACCES		},
    {	ERROR_INVALID_PARAMETER,	EINVAL		},
    {	ERROR_NO_PROC_SLOTS,		EAGAIN		},
    {	ERROR_DRIVE_LOCKED,		EACCES		},
    {	ERROR_BROKEN_PIPE,		EPIPE		},
    {	ERROR_DISK_FULL,		ENOSPC		},
    {	ERROR_INVALID_TARGET_HANDLE,	EBADF		},
    {	ERROR_INVALID_HANDLE,		EINVAL		},
    {	ERROR_WAIT_NO_CHILDREN,		ECHILD		},
    {	ERROR_CHILD_NOT_COMPLETE,	ECHILD		},
    {	ERROR_DIRECT_ACCESS_HANDLE,	EBADF		},
    {	ERROR_NEGATIVE_SEEK,		EINVAL		},
    {	ERROR_SEEK_ON_DEVICE,		EACCES		},
    {	ERROR_DIR_NOT_EMPTY,		ENOTEMPTY	},
    {	ERROR_DIRECTORY,		ENOTDIR		},
    {	ERROR_NOT_LOCKED,		EACCES		},
    {	ERROR_BAD_PATHNAME,		ENOENT		},
    {	ERROR_MAX_THRDS_REACHED,	EAGAIN		},
    {	ERROR_LOCK_FAILED,		EACCES		},
    {	ERROR_ALREADY_EXISTS,		EEXIST		},
    {	ERROR_INVALID_STARTING_CODESEG,	ENOEXEC		},
    {	ERROR_INVALID_STACKSEG,		ENOEXEC		},
    {	ERROR_INVALID_MODULETYPE,	ENOEXEC		},
    {	ERROR_INVALID_EXE_SIGNATURE,	ENOEXEC		},
    {	ERROR_EXE_MARKED_INVALID,	ENOEXEC		},
    {	ERROR_BAD_EXE_FORMAT,		ENOEXEC		},
    {	ERROR_ITERATED_DATA_EXCEEDS_64k,ENOEXEC		},
    {	ERROR_INVALID_MINALLOCSIZE,	ENOEXEC		},
    {	ERROR_DYNLINK_FROM_INVALID_RING,ENOEXEC		},
    {	ERROR_IOPL_NOT_ENABLED,		ENOEXEC		},
    {	ERROR_INVALID_SEGDPL,		ENOEXEC		},
    {	ERROR_AUTODATASEG_EXCEEDS_64k,	ENOEXEC		},
    {	ERROR_RING2SEG_MUST_BE_MOVABLE,	ENOEXEC		},
    {	ERROR_RELOC_CHAIN_XEEDS_SEGLIM,	ENOEXEC		},
    {	ERROR_INFLOOP_IN_RELOC_CHAIN,	ENOEXEC		},
    {	ERROR_FILENAME_EXCED_RANGE,	ENOENT		},
    {	ERROR_NESTING_NOT_ALLOWED,	EAGAIN		},
#ifndef ERROR_PIPE_LOCAL
#define ERROR_PIPE_LOCAL	229L
#endif
    {	ERROR_PIPE_LOCAL,		EPIPE		},
    {	ERROR_BAD_PIPE,			EPIPE		},
    {	ERROR_PIPE_BUSY,		EAGAIN		},
    {	ERROR_NO_DATA,			EPIPE		},
    {	ERROR_PIPE_NOT_CONNECTED,	EPIPE		},
    {	ERROR_OPERATION_ABORTED,	EINTR		},
    {	ERROR_NOT_ENOUGH_QUOTA,		ENOMEM		},
    {	ERROR_MOD_NOT_FOUND,		ENOENT		},
    {	WSAEINTR,			EINTR		},
    {	WSAEBADF,			EBADF		},
    {	WSAEACCES,			EACCES		},
    {	WSAEFAULT,			EFAULT		},
    {	WSAEINVAL,			EINVAL		},
    {	WSAEMFILE,			EMFILE		},
    {	WSAEWOULDBLOCK,			EWOULDBLOCK	},
    {	WSAEINPROGRESS,			EINPROGRESS	},
    {	WSAEALREADY,			EALREADY	},
    {	WSAENOTSOCK,			ENOTSOCK	},
    {	WSAEDESTADDRREQ,		EDESTADDRREQ	},
    {	WSAEMSGSIZE,			EMSGSIZE	},
    {	WSAEPROTOTYPE,			EPROTOTYPE	},
    {	WSAENOPROTOOPT,			ENOPROTOOPT	},
    {	WSAEPROTONOSUPPORT,		EPROTONOSUPPORT	},
    {	WSAESOCKTNOSUPPORT,		ESOCKTNOSUPPORT	},
    {	WSAEOPNOTSUPP,			EOPNOTSUPP	},
    {	WSAEPFNOSUPPORT,		EPFNOSUPPORT	},
    {	WSAEAFNOSUPPORT,		EAFNOSUPPORT	},
    {	WSAEADDRINUSE,			EADDRINUSE	},
    {	WSAEADDRNOTAVAIL,		EADDRNOTAVAIL	},
    {	WSAENETDOWN,			ENETDOWN	},
    {	WSAENETUNREACH,			ENETUNREACH	},
    {	WSAENETRESET,			ENETRESET	},
    {	WSAECONNABORTED,		ECONNABORTED	},
    {	WSAECONNRESET,			ECONNRESET	},
    {	WSAENOBUFS,			ENOBUFS		},
    {	WSAEISCONN,			EISCONN		},
    {	WSAENOTCONN,			ENOTCONN	},
    {	WSAESHUTDOWN,			ESHUTDOWN	},
    {	WSAETOOMANYREFS,		ETOOMANYREFS	},
    {	WSAETIMEDOUT,			ETIMEDOUT	},
    {	WSAECONNREFUSED,		ECONNREFUSED	},
    {	WSAELOOP,			ELOOP		},
    {	WSAENAMETOOLONG,		ENAMETOOLONG	},
    {	WSAEHOSTDOWN,			EHOSTDOWN	},
    {	WSAEHOSTUNREACH,		EHOSTUNREACH	},
    {	WSAEPROCLIM,			EPROCLIM	},
    {	WSAENOTEMPTY,			ENOTEMPTY	},
    {	WSAEUSERS,			EUSERS		},
    {	WSAEDQUOT,			EDQUOT		},
    {	WSAESTALE,			ESTALE		},
    {	WSAEREMOTE,			EREMOTE		},
};

int
rb_w32_map_errno(DWORD winerr)
{
    int i;

    if (winerr == 0) {
	return 0;
    }

    for (i = 0; i < sizeof(errmap) / sizeof(*errmap); i++) {
	if (errmap[i].winerr == winerr) {
	    return errmap[i].err;
	}
    }

    if (winerr >= WSABASEERR) {
	return winerr;
    }
    return EINVAL;
}

#define map_errno rb_w32_map_errno

static const char *NTLoginName;

#ifdef WIN95
static DWORD Win32System = (DWORD)-1;

DWORD
rb_w32_osid(void)
{
    static OSVERSIONINFO osver;

    if (osver.dwPlatformId != Win32System) {
	memset(&osver, 0, sizeof(OSVERSIONINFO));
	osver.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);
	GetVersionEx(&osver);
	Win32System = osver.dwPlatformId;
    }
    return (Win32System);
}
#endif

#define IsWinNT() rb_w32_iswinnt()
#define IsWin95() rb_w32_iswin95()

/* main thread constants */
static struct {
    HANDLE handle;
    DWORD id;
} main_thread;

/* interrupt stuff */
static HANDLE interrupted_event;

HANDLE
GetCurrentThreadHandle(void)
{
    static HANDLE current_process_handle = NULL;
    HANDLE h;

    if (!current_process_handle)
	current_process_handle = GetCurrentProcess();
    if (!DuplicateHandle(current_process_handle, GetCurrentThread(),
			 current_process_handle, &h,
			 0, FALSE, DUPLICATE_SAME_ACCESS))
	return NULL;
    return h;
}

/* simulate flock by locking a range on the file */


#define LK_ERR(f,i) \
    do {								\
	if (f)								\
	    i = 0;							\
	else {								\
	    DWORD err = GetLastError();					\
	    if (err == ERROR_LOCK_VIOLATION)				\
		errno = EWOULDBLOCK;					\
	    else if (err == ERROR_NOT_LOCKED)				\
		i = 0;							\
	    else							\
		errno = map_errno(err);					\
	}								\
    } while (0)
#define LK_LEN      ULONG_MAX

static VALUE
flock_winnt(VALUE self, int argc, VALUE* argv)
{
    OVERLAPPED o;
    int i = -1;
    const HANDLE fh = (HANDLE)self;
    const int oper = argc;

    memset(&o, 0, sizeof(o));

    switch(oper) {
      case LOCK_SH:		/* shared lock */
	LK_ERR(LockFileEx(fh, 0, 0, LK_LEN, LK_LEN, &o), i);
	break;
      case LOCK_EX:		/* exclusive lock */
	LK_ERR(LockFileEx(fh, LOCKFILE_EXCLUSIVE_LOCK, 0, LK_LEN, LK_LEN, &o), i);
	break;
      case LOCK_SH|LOCK_NB:	/* non-blocking shared lock */
	LK_ERR(LockFileEx(fh, LOCKFILE_FAIL_IMMEDIATELY, 0, LK_LEN, LK_LEN, &o), i);
	break;
      case LOCK_EX|LOCK_NB:	/* non-blocking exclusive lock */
	LK_ERR(LockFileEx(fh,
			  LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,
			  0, LK_LEN, LK_LEN, &o), i);
	break;
      case LOCK_UN:		/* unlock lock */
      case LOCK_UN|LOCK_NB:	/* unlock is always non-blocking, I hope */
	LK_ERR(UnlockFileEx(fh, 0, LK_LEN, LK_LEN, &o), i);
	break;
      default:            /* unknown */
	errno = EINVAL;
	break;
    }
    return i;
}

#ifdef WIN95
static VALUE
flock_win95(VALUE self, int argc, VALUE* argv)
{
    int i = -1;
    const HANDLE fh = (HANDLE)self;
    const int oper = argc;

    switch(oper) {
      case LOCK_EX:
	do {
	    LK_ERR(LockFile(fh, 0, 0, LK_LEN, LK_LEN), i);
	} while (i && errno == EWOULDBLOCK);
	break;
      case LOCK_EX|LOCK_NB:
	LK_ERR(LockFile(fh, 0, 0, LK_LEN, LK_LEN), i);
	break;
      case LOCK_UN:
      case LOCK_UN|LOCK_NB:
	LK_ERR(UnlockFile(fh, 0, 0, LK_LEN, LK_LEN), i);
	break;
      default:
	errno = EINVAL;
	break;
    }
    return i;
}
#endif

#undef LK_ERR

int
flock(int fd, int oper)
{
#ifdef WIN95
    static asynchronous_func_t locker = NULL;

    if (!locker) {
	if (IsWinNT())
	    locker = flock_winnt;
	else
	    locker = flock_win95;
    }
#else
    const asynchronous_func_t locker = flock_winnt;
#endif

    return rb_w32_asynchronize(locker,
			      (VALUE)_get_osfhandle(fd), oper, NULL,
			      (DWORD)-1);
}

static void init_stdhandle(void);

#if RT_VER >= 80
static void
invalid_parameter(const wchar_t *expr, const wchar_t *func, const wchar_t *file, unsigned int line, uintptr_t dummy)
{
    // nothing to do
}

static int __cdecl
rtc_error_handler(int e, const char *src, int line, const char *exe, const char *fmt, ...)
{
    return 0;
}
#endif

static CRITICAL_SECTION select_mutex;
static BOOL fWinsock;
static char *envarea;
static void
exit_handler(void)
{
    if (fWinsock) {
	WSACleanup();
	fWinsock = FALSE;
    }
    if (envarea) {
	FreeEnvironmentStrings(envarea);
	envarea = NULL;
    }
    DeleteCriticalSection(&select_mutex);
}

#ifndef CSIDL_PROFILE
#define CSIDL_PROFILE 40
#endif

static BOOL
get_special_folder(int n, char *env)
{
    LPITEMIDLIST pidl;
    LPMALLOC alloc;
    BOOL f = FALSE;
    if (SHGetSpecialFolderLocation(NULL, n, &pidl) == 0) {
	f = SHGetPathFromIDList(pidl, env);
	SHGetMalloc(&alloc);
	alloc->lpVtbl->Free(alloc, pidl);
	alloc->lpVtbl->Release(alloc);
    }
    return f;
}

static void
init_env(void)
{
    char env[_MAX_PATH];
    DWORD len;
    BOOL f;

    if (!GetEnvironmentVariable("HOME", env, sizeof(env))) {
	f = FALSE;
	if (GetEnvironmentVariable("HOMEDRIVE", env, sizeof(env)))
	    len = strlen(env);
	else
	    len = 0;
	if (GetEnvironmentVariable("HOMEPATH", env + len, sizeof(env) - len) || len) {
	    f = TRUE;
	}
	else if (GetEnvironmentVariable("USERPROFILE", env, sizeof(env))) {
	    f = TRUE;
	}
	else if (get_special_folder(CSIDL_PROFILE, env)) {
	    f = TRUE;
	}
	else if (get_special_folder(CSIDL_PERSONAL, env)) {
	    f = TRUE;
	}
	if (f) {
	    char *p = env;
	    while (*p) {
		if (*p == '\\') *p = '/';
		p = CharNext(p);
	    }
	    if (p - env == 2 && env[1] == ':') {
		*p++ = '/';
		*p = 0;
	    }
	    SetEnvironmentVariable("HOME", env);
	}
    }

    if (!GetEnvironmentVariable("USER", env, sizeof env)) {
	if (GetEnvironmentVariable("USERNAME", env, sizeof env) ||
	    GetUserName(env, (len = sizeof env, &len))) {
	    SetEnvironmentVariable("USER", env);
	}
	else {
	    NTLoginName = "<Unknown>";
	    return;
	}
    }
    NTLoginName = strdup(env);
}

//
// Initialization stuff
//
void
NtInitialize(int *argc, char ***argv)
{
#if RT_VER >= 80
    static void set_pioinfo_extra(void);

    _CrtSetReportMode(_CRT_ASSERT, 0);
    _set_invalid_parameter_handler(invalid_parameter);
    _RTC_SetErrorFunc(rtc_error_handler);
    set_pioinfo_extra();
#endif

    //
    // subvert cmd.exe's feeble attempt at command line parsing
    //
    *argc = rb_w32_cmdvector(GetCommandLine(), argv);

    //
    // Now set up the correct time stuff
    //

    tzset();

    init_env();

    init_stdhandle();

    InitializeCriticalSection(&select_mutex);

    atexit(exit_handler);

    // Initialize Winsock
    StartSockets();

#ifdef _WIN32_WCE
    // free commandline buffer
    wce_FreeCommandLine();
#endif
}

char *
getlogin()
{
    return (char *)NTLoginName;
}

#define MAXCHILDNUM 256	/* max num of child processes */

static struct ChildRecord {
    HANDLE hProcess;	/* process handle */
    rb_pid_t pid;	/* process id */
} ChildRecord[MAXCHILDNUM];

#define FOREACH_CHILD(v) do { \
    struct ChildRecord* v; \
    for (v = ChildRecord; v < ChildRecord + sizeof(ChildRecord) / sizeof(ChildRecord[0]); ++v)
#define END_FOREACH_CHILD } while (0)

static struct ChildRecord *
FindChildSlot(rb_pid_t pid)
{

    FOREACH_CHILD(child) {
	if (child->pid == pid) {
	    return child;
	}
    } END_FOREACH_CHILD;
    return NULL;
}

static struct ChildRecord *
FindChildSlotByHandle(HANDLE h)
{

    FOREACH_CHILD(child) {
	if (child->hProcess == h) {
	    return child;
	}
    } END_FOREACH_CHILD;
    return NULL;
}

static void
CloseChildHandle(struct ChildRecord *child)
{
    HANDLE h = child->hProcess;
    child->hProcess = NULL;
    child->pid = 0;
    CloseHandle(h);
}

static struct ChildRecord *
FindFreeChildSlot(void)
{
    FOREACH_CHILD(child) {
	if (!child->pid) {
	    child->pid = -1;	/* lock the slot */
	    child->hProcess = NULL;
	    return child;
	}
    } END_FOREACH_CHILD;
    return NULL;
}


/*
  ruby -lne 'BEGIN{$cmds = Hash.new(0); $mask = 1}'
   -e '$cmds[$_.downcase] |= $mask' -e '$mask <<= 1 if ARGF.eof'
   -e 'END{$cmds.sort.each{|n,f|puts "    \"\\#{f.to_s(8)}\" #{n.dump} + 1,"}}'
   98cmd ntcmd
 */
static const char *const szInternalCmds[] = {
    "\2" "assoc" + 1,
    "\3" "break" + 1,
    "\3" "call" + 1,
    "\3" "cd" + 1,
    "\1" "chcp" + 1,
    "\3" "chdir" + 1,
    "\3" "cls" + 1,
    "\2" "color" + 1,
    "\3" "copy" + 1,
    "\1" "ctty" + 1,
    "\3" "date" + 1,
    "\3" "del" + 1,
    "\3" "dir" + 1,
    "\3" "echo" + 1,
    "\2" "endlocal" + 1,
    "\3" "erase" + 1,
    "\3" "exit" + 1,
    "\3" "for" + 1,
    "\2" "ftype" + 1,
    "\3" "goto" + 1,
    "\3" "if" + 1,
    "\1" "lfnfor" + 1,
    "\1" "lh" + 1,
    "\1" "lock" + 1,
    "\3" "md" + 1,
    "\3" "mkdir" + 1,
    "\2" "move" + 1,
    "\3" "path" + 1,
    "\3" "pause" + 1,
    "\2" "popd" + 1,
    "\3" "prompt" + 1,
    "\2" "pushd" + 1,
    "\3" "rd" + 1,
    "\3" "rem" + 1,
    "\3" "ren" + 1,
    "\3" "rename" + 1,
    "\3" "rmdir" + 1,
    "\3" "set" + 1,
    "\2" "setlocal" + 1,
    "\3" "shift" + 1,
    "\2" "start" + 1,
    "\3" "time" + 1,
    "\2" "title" + 1,
    "\1" "truename" + 1,
    "\3" "type" + 1,
    "\1" "unlock" + 1,
    "\3" "ver" + 1,
    "\3" "verify" + 1,
    "\3" "vol" + 1,
};

static int
internal_match(const void *key, const void *elem)
{
    return strcmp(key, *(const char *const *)elem);
}

static int
is_command_com(const char *interp)
{
    int i = strlen(interp) - 11;

    if ((i == 0 || i > 0 && isdirsep(interp[i-1])) &&
	strcasecmp(interp+i, "command.com") == 0) {
	return 1;
    }
    return 0;
}

static int
is_internal_cmd(const char *cmd, int nt)
{
    char cmdname[9], *b = cmdname, c, **nm;

    do {
	if (!(c = *cmd++)) return 0;
    } while (isspace(c));
    while (isalpha(c)) {
	*b++ = tolower(c);
	if (b == cmdname + sizeof(cmdname)) return 0;
	c = *cmd++;
    }
    if (c == '.') c = *cmd;
    switch (c) {
      case '<': case '>': case '|':
	return 1;
      case '\0': case ' ': case '\t': case '\n':
	break;
      default:
	return 0;
    }
    *b = 0;
    nm = bsearch(cmdname, szInternalCmds,
		 sizeof(szInternalCmds) / sizeof(*szInternalCmds),
		 sizeof(*szInternalCmds),
		 internal_match);
    if (!nm || !(nm[0][-1] & (nt ? 2 : 1)))
	return 0;
    return 1;
}


SOCKET
rb_w32_get_osfhandle(int fh)
{
    return _get_osfhandle(fh);
}

rb_pid_t
pipe_exec(const char *cmd, int mode, FILE **fpr, FILE **fpw)
{
    struct ChildRecord* child;
    HANDLE hReadIn, hReadOut;
    HANDLE hWriteIn, hWriteOut;
    HANDLE hDupInFile, hDupOutFile;
    HANDLE hCurProc;
    SECURITY_ATTRIBUTES sa;
    BOOL fRet;
    BOOL reading, writing;
    int fd;
    int pipemode;
    char modes[3];
    int ret;

    /* Figure out what we're doing... */
    writing = (mode & (O_WRONLY | O_RDWR)) ? TRUE : FALSE;
    reading = ((mode & O_RDWR) || !writing) ? TRUE : FALSE;
    if (mode & O_BINARY) {
	pipemode = O_BINARY;
	modes[1] = 'b';
	modes[2] = '\0';
    }
    else {
	pipemode = O_TEXT;
	modes[1] = '\0';
    }

    sa.nLength              = sizeof (SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle       = TRUE;
    ret = -1;
    hWriteIn = hReadOut = NULL;

    RUBY_CRITICAL(do {
	/* create pipe */
	hCurProc = GetCurrentProcess();
	if (reading) {
	    fRet = CreatePipe(&hReadIn, &hReadOut, &sa, 2048L);
	    if (!fRet) {
		errno = map_errno(GetLastError());
		break;
	    }
	    if (!DuplicateHandle(hCurProc, hReadIn, hCurProc, &hDupInFile, 0,
				 FALSE, DUPLICATE_SAME_ACCESS)) {
		errno = map_errno(GetLastError());
		CloseHandle(hReadIn);
		CloseHandle(hReadOut);
		CloseHandle(hCurProc);
		break;
	    }
	    CloseHandle(hReadIn);
	}
	if (writing) {
	    fRet = CreatePipe(&hWriteIn, &hWriteOut, &sa, 2048L);
	    if (!fRet) {
		errno = map_errno(GetLastError());
	      write_pipe_failed:
		if (reading) {
		    CloseHandle(hDupInFile);
		    CloseHandle(hReadOut);
		}
		break;
	    }
	    if (!DuplicateHandle(hCurProc, hWriteOut, hCurProc, &hDupOutFile, 0,
				 FALSE, DUPLICATE_SAME_ACCESS)) {
		errno = map_errno(GetLastError());
		CloseHandle(hWriteIn);
		CloseHandle(hWriteOut);
		CloseHandle(hCurProc);
		goto write_pipe_failed;
	    }
	    CloseHandle(hWriteOut);
	}
	CloseHandle(hCurProc);

	/* create child process */
	child = CreateChild(cmd, NULL, &sa, hWriteIn, hReadOut, NULL);
	if (!child) {
	    if (reading) {
		CloseHandle(hReadOut);
		CloseHandle(hDupInFile);
	    }
	    if (writing) {
		CloseHandle(hWriteIn);
		CloseHandle(hDupOutFile);
	    }
	    break;
	}

	/* associate handle to fp */
	if (reading) {
	    fd = rb_w32_open_osfhandle((long)hDupInFile,
				       (_O_RDONLY | pipemode));
	    CloseHandle(hReadOut);
	    if (fd == -1) {
		CloseHandle(hDupInFile);
	      read_open_failed:
		if (writing) {
		    CloseHandle(hWriteIn);
		    CloseHandle(hDupOutFile);
		}
		CloseChildHandle(child);
		break;
	    }
	    modes[0] = 'r';
	    if ((*fpr = (FILE *)fdopen(fd, modes)) == NULL) {
		_close(fd);
		goto read_open_failed;
	    }
	}
	if (writing) {
	    fd = rb_w32_open_osfhandle((long)hDupOutFile,
				       (_O_WRONLY | pipemode));
	    CloseHandle(hWriteIn);
	    if (fd == -1) {
		CloseHandle(hDupOutFile);
	      write_open_failed:
		if (reading) {
		    fclose(*fpr);
		}
		CloseChildHandle(child);
		break;
	    }
	    modes[0] = 'w';
	    if ((*fpw = (FILE *)fdopen(fd, modes)) == NULL) {
		_close(fd);
		goto write_open_failed;
	    }
	}
	ret = child->pid;
    } while (0));

    return ret;
}

extern VALUE rb_last_status;

int
do_spawn(int mode, const char *cmd)
{
    struct ChildRecord *child;
    DWORD exitcode;

    switch (mode) {
      case P_WAIT:
      case P_NOWAIT:
      case P_OVERLAY:
	break;
      default:
	errno = EINVAL;
	return -1;
    }

    child = CreateChild(cmd, NULL, NULL, NULL, NULL, NULL);
    if (!child) {
	return -1;
    }

    switch (mode) {
      case P_WAIT:
	rb_syswait(child->pid);
	return NUM2INT(rb_last_status);
      case P_NOWAIT:
	return child->pid;
      case P_OVERLAY:
	WaitForSingleObject(child->hProcess, INFINITE);
	GetExitCodeProcess(child->hProcess, &exitcode);
	CloseChildHandle(child);
	_exit(exitcode);
      default:
	return -1;	/* not reached */
    }
}

int
do_aspawn(int mode, const char *prog, char **argv)
{
    char *cmd, *p, *q, *s, **t;
    int len, n, bs, quote;
    struct ChildRecord *child;
    DWORD exitcode;

    switch (mode) {
      case P_WAIT:
      case P_NOWAIT:
      case P_OVERLAY:
	break;
      default:
	errno = EINVAL;
	return -1;
    }

    for (t = argv, len = 0; *t; t++) {
	for (p = *t, n = quote = bs = 0; *p; ++p) {
	    switch (*p) {
	      case '\\':
		++bs;
		break;
	      case '"':
		n += bs + 1; bs = 0;
		quote = 1;
		break;
	      case ' ': case '\t':
		quote = 1;
	      default:
		bs = 0;
		p = CharNext(p) - 1;
		break;
	    }
	}
	len += p - *t + n + 1;
	if (quote) len += 2;
    }
    cmd = ALLOCA_N(char, len);
    for (t = argv, q = cmd; p = *t; t++) {
	quote = 0;
	s = p;
	if (!*p || strpbrk(p, " \t\"")) {
	    quote = 1;
	    *q++ = '"';
	}
	for (bs = 0; *p; ++p) {
	    switch (*p) {
	      case '\\':
		++bs;
		break;
	      case '"':
		memcpy(q, s, n = p - s); q += n; s = p;
		memset(q, '\\', ++bs); q += bs; bs = 0;
		break;
	      default:
		bs = 0;
		p = CharNext(p) - 1;
		break;
	    }
	}
	memcpy(q, s, n = p - s);
	q += n;
	if (quote) *q++ = '"';
	*q++ = ' ';
    }
    if (q > cmd) --q;
    *q = '\0';

    child = CreateChild(cmd, prog, NULL, NULL, NULL, NULL);
    if (!child) {
	return -1;
    }

    switch (mode) {
      case P_WAIT:
	rb_syswait(child->pid);
	return NUM2INT(rb_last_status);
      case P_NOWAIT:
	return child->pid;
      case P_OVERLAY:
	WaitForSingleObject(child->hProcess, INFINITE);
	GetExitCodeProcess(child->hProcess, &exitcode);
	CloseChildHandle(child);
	_exit(exitcode);
      default:
	return -1;	/* not reached */
    }
}

static struct ChildRecord *
CreateChild(const char *cmd, const char *prog, SECURITY_ATTRIBUTES *psa,
	    HANDLE hInput, HANDLE hOutput, HANDLE hError)
{
    BOOL fRet;
    DWORD  dwCreationFlags;
    STARTUPINFO aStartupInfo;
    PROCESS_INFORMATION aProcessInformation;
    SECURITY_ATTRIBUTES sa;
    const char *shell;
    struct ChildRecord *child;
    char *p = NULL;

    if (!cmd && !prog) {
	errno = EFAULT;
	return NULL;
    }

    child = FindFreeChildSlot();
    if (!child) {
	errno = EAGAIN;
	return NULL;
    }

    if (!psa) {
	sa.nLength              = sizeof (SECURITY_ATTRIBUTES);
	sa.lpSecurityDescriptor = NULL;
	sa.bInheritHandle       = TRUE;
	psa = &sa;
    }

    memset(&aStartupInfo, 0, sizeof (STARTUPINFO));
    memset(&aProcessInformation, 0, sizeof (PROCESS_INFORMATION));
    aStartupInfo.cb = sizeof (STARTUPINFO);
    if (hInput || hOutput || hError) {
	aStartupInfo.dwFlags = STARTF_USESTDHANDLES;
	if (hInput) {
	    aStartupInfo.hStdInput  = hInput;
	}
	else {
	    aStartupInfo.hStdInput  = GetStdHandle(STD_INPUT_HANDLE);
	}
	if (hOutput) {
	    aStartupInfo.hStdOutput = hOutput;
	}
	else {
	    aStartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
	}
	if (hError) {
	    aStartupInfo.hStdError = hError;
	}
	else {
	    aStartupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);
	}
    }

    dwCreationFlags = (NORMAL_PRIORITY_CLASS);

    if (prog) {
	if (!(p = dln_find_exe(prog, NULL))) {
	    shell = prog;
	}
    }
    else {
	int redir = -1;
	int len = 0;
	int nt;
	while (ISSPACE(*cmd)) cmd++;
	for (prog = cmd; *prog; prog = CharNext(prog)) {
	    if (ISSPACE(*prog)) {
		len = prog - cmd;
		do ++prog; while (ISSPACE(*prog));
		if (!*prog--) break;
	    }
	    else {
		len = 0;
	    }
	}
	if (!len) len = strlen(cmd);
	if ((shell = getenv("RUBYSHELL")) && (redir = has_redirection(cmd))) {
	    char *tmp = ALLOCA_N(char, strlen(shell) + len + sizeof(" -c ") + 2);
	    sprintf(tmp, "%s -c \"%.*s\"", shell, len, cmd);
	    cmd = tmp;
	}
	else if ((shell = getenv("COMSPEC")) &&
		 (nt = !is_command_com(shell),
		  (redir < 0 ? has_redirection(cmd) : redir) ||
		  is_internal_cmd(cmd, nt))) {
	    char *tmp = ALLOCA_N(char, strlen(shell) + len + sizeof(" /c ")
				 + (nt ? 2 : 0));
	    sprintf(tmp, nt ? "%s /c \"%.*s\"" : "%s /c %.*s", shell, len, cmd);
	    cmd = tmp;
	}
	else {
	    char quote = (*cmd == '"') ? '"' : (*cmd == '\'') ? '\'' : 0;
	    shell = NULL;
	    for (prog = cmd + !!quote;; prog = CharNext(prog)) {
		if (!*prog) {
		    p = dln_find_exe(cmd, NULL);
		    break;
		}
		if (*prog == quote) {
		    len = prog++ - cmd - 1;
		    p = ALLOCA_N(char, len + 1);
		    memcpy(p, cmd + 1, len);
		    p[len] = 0;
		    p = dln_find_exe(p, NULL);
		    break;
		}
		if (quote) continue;
		if (strchr(".:*?\"/\\", *prog)) {
		    if (cmd[len]) {
			char *tmp = ALLOCA_N(char, len + 1);
			memcpy(tmp, cmd, len);
			tmp[len] = 0;
			cmd = tmp;
		    }
		    break;
		}
		if (ISSPACE(*prog) || strchr("<>|", *prog)) {
		    len = prog - cmd;
		    p = ALLOCA_N(char, len + 1);
		    memcpy(p, cmd, len);
		    p[len] = 0;
		    p = dln_find_exe(p, NULL);
		    break;
		}
	    }
	}
    }
    if (p) {
	char *tmp = ALLOCA_N(char, strlen(p) + 1);
	strcpy(tmp, p);
	shell = tmp;
	while (*tmp) {
	    if ((unsigned char)*tmp == '/')
		*tmp = '\\';
	    tmp = CharNext(tmp);
	}
    }

    RUBY_CRITICAL({
	fRet = CreateProcess(shell, (char *)cmd, psa, psa,
			     psa->bInheritHandle, dwCreationFlags, NULL, NULL,
			     &aStartupInfo, &aProcessInformation);
	errno = map_errno(GetLastError());
    });

    if (!fRet) {
	child->pid = 0;		/* release the slot */
	return NULL;
    }

    CloseHandle(aProcessInformation.hThread);

    child->hProcess = aProcessInformation.hProcess;
    child->pid = (rb_pid_t)aProcessInformation.dwProcessId;

    if (!IsWinNT()) {
	/* On Win9x, make pid positive similarly to cygwin and perl */
	child->pid = -child->pid;
    }

    return child;
}

typedef struct _NtCmdLineElement {
    struct _NtCmdLineElement *next;
    char *str;
    int len;
    int flags;
} NtCmdLineElement;

//
// Possible values for flags
//

#define NTGLOB   0x1	// element contains a wildcard
#define NTMALLOC 0x2	// string in element was malloc'ed
#define NTSTRING 0x4	// element contains a quoted string

static int
insert(const char *path, VALUE vinfo)
{
    NtCmdLineElement *tmpcurr;
    NtCmdLineElement ***tail = (NtCmdLineElement ***)vinfo;

    tmpcurr = (NtCmdLineElement *)malloc(sizeof(NtCmdLineElement));
    if (!tmpcurr) return -1;
    MEMZERO(tmpcurr, NtCmdLineElement, 1);
    tmpcurr->len = strlen(path);
    tmpcurr->str = strdup(path);
    if (!tmpcurr->str) return -1;
    tmpcurr->flags |= NTMALLOC;
    **tail = tmpcurr;
    *tail = &tmpcurr->next;

    return 0;
}

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 512
#endif


static NtCmdLineElement **
cmdglob(NtCmdLineElement *patt, NtCmdLineElement **tail)
{
    char buffer[MAXPATHLEN], *buf = buffer;
    char *p;
    NtCmdLineElement **last = tail;
    int status;

    if (patt->len >= MAXPATHLEN)
	if (!(buf = malloc(patt->len + 1))) return 0;

    strncpy (buf, patt->str, patt->len);
    buf[patt->len] = '\0';
    for (p = buf; *p; p = CharNext(p))
	if (*p == '\\')
	    *p = '/';
    status = ruby_glob(buf, 0, insert, (VALUE)&tail);
    if (buf != buffer)
	free(buf);

    if (status || last == tail) return 0;
    if (patt->flags & NTMALLOC)
	free(patt->str);
    free(patt);
    return tail;
}

//
// Check a command string to determine if it has I/O redirection
// characters that require it to be executed by a command interpreter
//

static bool
has_redirection(const char *cmd)
{
    char quote = '\0';
    const char *ptr;

    //
    // Scan the string, looking for redirection characters (< or >), pipe
    // character (|) or newline (\n) that are not in a quoted string
    //

    for (ptr = cmd; *ptr;) {
	switch (*ptr) {
	  case '\'':
	  case '\"':
	    if (!quote)
		quote = *ptr;
	    else if (quote == *ptr)
		quote = '\0';
	    ptr++;
	    break;

	  case '>':
	  case '<':
	  case '|':
	  case '\n':
	    if (!quote)
		return TRUE;
	    ptr++;
	    break;

	  case '\\':
	    ptr++;
	  default:
	    ptr = CharNext(ptr);
	    break;
	}
    }
    return FALSE;
}

static inline char *
skipspace(char *ptr)
{
    while (ISSPACE(*ptr))
	ptr++;
    return ptr;
}

int
rb_w32_cmdvector(const char *cmd, char ***vec)
{
    int globbing, len;
    int elements, strsz, done;
    int slashes, escape;
    char *ptr, *base, *buffer, *cmdline;
    char **vptr;
    char quote;
    NtCmdLineElement *curr, **tail;
    NtCmdLineElement *cmdhead = NULL, **cmdtail = &cmdhead;

    //
    // just return if we don't have a command line
    //

    while (ISSPACE(*cmd))
	cmd++;
    if (!*cmd) {
	*vec = NULL;
	return 0;
    }

    ptr = cmdline = strdup(cmd);

    //
    // Ok, parse the command line, building a list of CmdLineElements.
    // When we've finished, and it's an input command (meaning that it's
    // the processes argv), we'll do globing and then build the argument
    // vector.
    // The outer loop does one interation for each element seen.
    // The inner loop does one interation for each character in the element.
    //

    while (*(ptr = skipspace(ptr))) {
	base = ptr;
	quote = slashes = globbing = escape = 0;
	for (done = 0; !done && *ptr; ) {
	    //
	    // Switch on the current character. We only care about the
	    // white-space characters, the  wild-card characters, and the
	    // quote characters.
	    //

	    switch (*ptr) {
	      case '\\':
		if (quote != '\'') slashes++;
	        break;

	      case ' ':
	      case '\t':
	      case '\n':
		//
		// if we're not in a string, then we're finished with this
		// element
		//

		if (!quote) {
		    *ptr = 0;
		    done = 1;
		}
		break;

	      case '*':
	      case '?':
	      case '[':
	      case '{':
		//
		// record the fact that this element has a wildcard character
		// N.B. Don't glob if inside a single quoted string
		//

		if (quote != '\'')
		    globbing++;
		slashes = 0;
		break;

	      case '\'':
	      case '\"':
		//
		// if we're already in a string, see if this is the
		// terminating close-quote. If it is, we're finished with
		// the string, but not neccessarily with the element.
		// If we're not already in a string, start one.
		//

		if (!(slashes & 1)) {
		    if (!quote)
			quote = *ptr;
		    else if (quote == *ptr) {
			if (quote == '"' && quote == ptr[1])
			    ptr++;
			quote = '\0';
		    }
		}
		escape++;
		slashes = 0;
		break;

	      default:
		ptr = CharNext(ptr);
		slashes = 0;
		continue;
	    }
	    ptr++;
	}

	//
	// when we get here, we've got a pair of pointers to the element,
	// base and ptr. Base points to the start of the element while ptr
	// points to the character following the element.
	//

	len = ptr - base;
	if (done) --len;

	//
	// if it's an input vector element and it's enclosed by quotes,
	// we can remove them.
	//

	if (escape) {
	    char *p = base, c;
	    slashes = quote = 0;
	    while (p < base + len) {
		switch (c = *p) {
		  case '\\':
		    p++;
		    if (quote != '\'') slashes++;
		    break;

		  case '\'':
		  case '"':
		    if (!(slashes & 1) && quote && quote != c) {
			p++;
			slashes = 0;
			break;
		    }
		    memcpy(p - ((slashes + 1) >> 1), p + (~slashes & 1),
			   base + len - p);
		    len -= ((slashes + 1) >> 1) + (~slashes & 1);
		    p -= (slashes + 1) >> 1;
		    if (!(slashes & 1)) {
			if (quote) {
			    if (quote == '"' && quote == *p)
				p++;
			    quote = '\0';
			}
			else
			    quote = c;
		    }
		    else
			p++;
		    slashes = 0;
		    break;

		  default:
		    p = CharNext(p);
		    slashes = 0;
		    break;
		}
	    }
	}

	curr = (NtCmdLineElement *)calloc(sizeof(NtCmdLineElement), 1);
	if (!curr) goto do_nothing;
	curr->str = base;
	curr->len = len;

	if (globbing && (tail = cmdglob(curr, cmdtail))) {
	    cmdtail = tail;
	}
	else {
	    *cmdtail = curr;
	    cmdtail = &curr->next;
	}
    }

    //
    // Almost done!
    // Count up the elements, then allocate space for a vector of pointers
    // (argv) and a string table for the elements.
    //

    for (elements = 0, strsz = 0, curr = cmdhead; curr; curr = curr->next) {
	elements++;
	strsz += (curr->len + 1);
    }

    len = (elements+1)*sizeof(char *) + strsz;
    buffer = (char *)malloc(len);
    if (!buffer) {
      do_nothing:
	while (curr = cmdhead) {
	    cmdhead = curr->next;
	    if (curr->flags & NTMALLOC) free(curr->str);
	    free(curr);
	}
	free(cmdline);
	for (vptr = *vec; *vptr; ++vptr);
	return vptr - *vec;
    }

    //
    // make vptr point to the start of the buffer
    // and ptr point to the area we'll consider the string table.
    //
    //   buffer (*vec)
    //   |
    //   V       ^---------------------V
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |   |       | ....  | NULL  |   | ..... |\0 |   | ..... |\0 |...
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |-  elements+1             -| ^ 1st element   ^ 2nd element

    vptr = (char **) buffer;

    ptr = buffer + (elements+1) * sizeof(char *);

    while (curr = cmdhead) {
	memcpy(ptr, curr->str, curr->len);
	*vptr++ = ptr;
	ptr += curr->len;
	*ptr++ = '\0';
	cmdhead = curr->next;
	if (curr->flags & NTMALLOC) free(curr->str);
	free(curr);
    }
    *vptr = 0;

    *vec = (char **) buffer;
    free(cmdline);
    return elements;
}

//
// UNIX compatible directory access functions for NT
//

#define PATHLEN 1024

//
// The idea here is to read all the directory names into a string table
// (separated by nulls) and when one of the other dir functions is called
// return the pointer to the current file name.
//

#define GetBit(bits, i) ((bits)[(i) / CHAR_BIT] &  (1 << (i) % CHAR_BIT))
#define SetBit(bits, i) ((bits)[(i) / CHAR_BIT] |= (1 << (i) % CHAR_BIT))

#define BitOfIsDir(n) ((n) * 2)
#define BitOfIsRep(n) ((n) * 2 + 1)
#define DIRENT_PER_CHAR (CHAR_BIT / 2)

static HANDLE
open_dir_handle(const char *filename, WIN32_FIND_DATA *fd)
{
    HANDLE fh;
    static const char wildcard[] = "/*";
    long len = strlen(filename);
    char *scanname = malloc(len + sizeof(wildcard));

    //
    // Create the search pattern
    //
    if (!scanname) {
	return INVALID_HANDLE_VALUE;
    }
    memcpy(scanname, filename, len + 1);

    if (index("/\\:", *CharPrev(scanname, scanname + len)) == NULL)
	memcpy(scanname + len, wildcard, sizeof(wildcard));
    else
	memcpy(scanname + len, wildcard + 1, sizeof(wildcard) - 1);

    //
    // do the FindFirstFile call
    //
    fh = FindFirstFile(scanname, fd);
    free(scanname);
    if (fh == INVALID_HANDLE_VALUE) {
	errno = map_errno(GetLastError());
    }
    return fh;
}

DIR *
rb_w32_opendir(const char *filename)
{
    DIR               *p;
    long               len;
    long               idx;
    struct stat	       sbuf;
    WIN32_FIND_DATA fd;
    HANDLE          fh;

    //
    // check to see if we've got a directory
    //

    if (rb_w32_stat(filename, &sbuf) < 0)
	return NULL;
    if (!(sbuf.st_mode & S_IFDIR) &&
	(!ISALPHA(filename[0]) || filename[1] != ':' || filename[2] != '\0' ||
	((1 << (filename[0] & 0x5f) - 'A') & GetLogicalDrives()) == 0)) {
	errno = ENOTDIR;
	return NULL;
    }

    fh = open_dir_handle(filename, &fd);
    if (fh == INVALID_HANDLE_VALUE) {
	return NULL;
    }

    //
    // Get us a DIR structure
    //
    p = calloc(sizeof(DIR), 1);
    if (p == NULL)
	return NULL;

    //
    // now allocate the first part of the string table for the
    // filenames that we find.
    //

    idx = strlen(fd.cFileName)+1;
    if (!(p->start = (char *)malloc(idx)) || !(p->bits = (char *)malloc(1))) {
      error:
	rb_w32_closedir(p);
	FindClose(fh);
	errno = ENOMEM;
	return NULL;
    }
    strcpy(p->start, fd.cFileName);
    p->bits[0] = 0;
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
	SetBit(p->bits, BitOfIsDir(0));
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
	SetBit(p->bits, BitOfIsRep(0));
    p->nfiles++;

    //
    // loop finding all the files that match the wildcard
    // (which should be all of them in this directory!).
    // the variable idx should point one past the null terminator
    // of the previous string found.
    //
    while (FindNextFile(fh, &fd)) {
	char *newpath;

	len = strlen(fd.cFileName) + 1;

	//
	// bump the string table size by enough for the
	// new name and it's null terminator
	//

	newpath = (char *)realloc(p->start, idx + len);
	if (newpath == NULL) {
	    goto error;
	}
	p->start = newpath;
	strcpy(&p->start[idx], fd.cFileName);

	if (p->nfiles % DIRENT_PER_CHAR == 0) {
	    char *tmp = realloc(p->bits, p->nfiles / DIRENT_PER_CHAR + 1);
	    if (!tmp)
		goto error;
	    p->bits = tmp;
	    p->bits[p->nfiles / DIRENT_PER_CHAR] = 0;
	}
	if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
	    SetBit(p->bits, BitOfIsDir(p->nfiles));
	if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
	    SetBit(p->bits, BitOfIsRep(p->nfiles));

	p->nfiles++;
	idx += len;
    }
    FindClose(fh);
    p->size = idx;
    p->curr = p->start;
    return p;
}

//
// Move to next entry
//

static void
move_to_next_entry(DIR *dirp)
{
    if (dirp->curr) {
	dirp->loc++;
	dirp->curr += strlen(dirp->curr) + 1;
	if (dirp->curr >= (dirp->start + dirp->size)) {
	    dirp->curr = NULL;
	}
    }
}

//
// Readdir just returns the current string pointer and bumps the
// string pointer to the next entry.
//

struct direct  *
rb_w32_readdir(DIR *dirp)
{
    static int  dummy = 0;

    if (dirp->curr) {

	//
	// first set up the structure to return
	//

	strcpy(dirp->dirstr.d_name, dirp->curr);
	dirp->dirstr.d_namlen = strlen(dirp->curr);

	//
	// Fake inode
	//
	dirp->dirstr.d_ino = dummy++;

	//
	// Attributes
	//
	dirp->dirstr.d_isdir = GetBit(dirp->bits, BitOfIsDir(dirp->loc));
	dirp->dirstr.d_isrep = GetBit(dirp->bits, BitOfIsRep(dirp->loc));

	//
	// Now set up for the next call to readdir
	//

	move_to_next_entry(dirp);

	return &(dirp->dirstr);

    } else
	return NULL;
}

//
// Telldir returns the current string pointer position
//

long
rb_w32_telldir(DIR *dirp)
{
    return dirp->loc;
}

//
// Seekdir moves the string pointer to a previously saved position
// (Saved by telldir).

void
rb_w32_seekdir(DIR *dirp, long loc)
{
    if (dirp->loc > loc) rb_w32_rewinddir(dirp);

    while (dirp->curr && dirp->loc < loc) {
	move_to_next_entry(dirp);
    }
}

//
// Rewinddir resets the string pointer to the start
//

void
rb_w32_rewinddir(DIR *dirp)
{
    dirp->curr = dirp->start;
    dirp->loc = 0;
}

//
// This just free's the memory allocated by opendir
//

void
rb_w32_closedir(DIR *dirp)
{
    free(dirp->start);
    free(dirp->bits);
    free(dirp);
}

EXTERN_C void __cdecl _lock_fhandle(int);
EXTERN_C void __cdecl _unlock_fhandle(int);
EXTERN_C void __cdecl _unlock(int);

#if (defined _MT || defined __MSVCRT__) && !defined __BORLANDC__
#define MSVCRT_THREADS
#endif
#ifdef MSVCRT_THREADS
# define MTHREAD_ONLY(x) x
# define STHREAD_ONLY(x)
#elif defined(__BORLANDC__)
# define MTHREAD_ONLY(x)
# define STHREAD_ONLY(x)
#else
# define MTHREAD_ONLY(x)
# define STHREAD_ONLY(x) x
#endif

typedef struct	{
    long osfhnd;    /* underlying OS file HANDLE */
    char osfile;    /* attributes of file (e.g., open in text mode?) */
    char pipech;    /* one char buffer for handles opened on pipes */
#ifdef MSVCRT_THREADS
    int lockinitflag;
    CRITICAL_SECTION lock;
#if RT_VER >= 80
    char textmode;
    char pipech2[2];
#endif
#endif
}	ioinfo;

#if !defined _CRTIMP || defined __MINGW32__
#undef _CRTIMP
#define _CRTIMP __declspec(dllimport)
#endif

#if !defined(__BORLANDC__) && !defined(_WIN32_WCE)
EXTERN_C _CRTIMP ioinfo * __pioinfo[];

#define IOINFO_L2E			5
#define IOINFO_ARRAY_ELTS	(1 << IOINFO_L2E)
#define _pioinfo(i)	((ioinfo*)((char*)(__pioinfo[i >> IOINFO_L2E]) + (i & (IOINFO_ARRAY_ELTS - 1)) * (sizeof(ioinfo) + pioinfo_extra)))
#define _osfhnd(i)  (_pioinfo(i)->osfhnd)
#define _osfile(i)  (_pioinfo(i)->osfile)
#define _pipech(i)  (_pioinfo(i)->pipech)

#if RT_VER >= 80
static size_t pioinfo_extra = 0;	/* workaround for VC++8 SP1 */

static void
set_pioinfo_extra(void)
{
    int fd;

    fd = open("NUL", O_RDONLY);
    for (pioinfo_extra = 0; pioinfo_extra <= 64; pioinfo_extra += sizeof(void *)) {
	if (_osfhnd(fd) == _get_osfhandle(fd)) {
	    break;
	}
    }
    close(fd);

    if (pioinfo_extra > 64) {
	/* not found, maybe something wrong... */
	pioinfo_extra = 0;
    }
}
#else
#define pioinfo_extra 0
#endif

#define _set_osfhnd(fh, osfh) (void)(_osfhnd(fh) = osfh)
#define _set_osflags(fh, flags) (_osfile(fh) = (flags))

#define FOPEN			0x01	/* file handle open */
#define FNOINHERIT		0x10	/* file handle opened O_NOINHERIT */
#define FAPPEND			0x20	/* file handle opened O_APPEND */
#define FDEV			0x40	/* file handle refers to device */
#define FTEXT			0x80	/* file handle is in text mode */

static int
rb_w32_open_osfhandle(long osfhandle, int flags)
{
    int fh;
    char fileflags;		/* _osfile flags */
    HANDLE hF;

    /* copy relevant flags from second parameter */
    fileflags = FDEV;

    if (flags & O_APPEND)
	fileflags |= FAPPEND;

    if (flags & O_TEXT)
	fileflags |= FTEXT;

    if (flags & O_NOINHERIT)
	fileflags |= FNOINHERIT;

    /* attempt to allocate a C Runtime file handle */
    hF = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
    fh = _open_osfhandle((long)hF, 0);
    CloseHandle(hF);
    if (fh == -1) {
	errno = EMFILE;		/* too many open files */
	_doserrno = 0L;		/* not an OS error */
    }
    else {

	MTHREAD_ONLY(EnterCriticalSection(&(_pioinfo(fh)->lock)));
	/* the file is open. now, set the info in _osfhnd array */
	_set_osfhnd(fh, osfhandle);

	fileflags |= FOPEN;		/* mark as open */

	_set_osflags(fh, fileflags); /* set osfile entry */
	MTHREAD_ONLY(LeaveCriticalSection(&_pioinfo(fh)->lock));
    }
    return fh;			/* return handle */
}

static void
init_stdhandle(void)
{
    int nullfd = -1;
    int keep = 0;
#define open_null(fd)						\
    (((nullfd < 0) ?						\
      (nullfd = open("NUL", O_RDWR|O_BINARY)) : 0),		\
     ((nullfd == (fd)) ? (keep = 1) : dup2(nullfd, fd)),	\
     (fd))

    if (fileno(stdin) < 0) {
	stdin->_file = open_null(0);
    }
    else {
	setmode(fileno(stdin), O_BINARY);
    }
    if (fileno(stdout) < 0) {
	stdout->_file = open_null(1);
    }
    else {
	setmode(fileno(stdout), O_BINARY);
    }
    if (fileno(stderr) < 0) {
	stderr->_file = open_null(2);
    }
    else {
	setmode(fileno(stderr), O_BINARY);
    }
    if (nullfd >= 0 && !keep) close(nullfd);
    setvbuf(stderr, NULL, _IONBF, 0);
}
#else

#define _set_osfhnd(fh, osfh) (void)((fh), (osfh))
#define _set_osflags(fh, flags) (void)((fh), (flags))

static void
init_stdhandle(void)
{
}
#endif

#ifdef __BORLANDC__
static int
rb_w32_open_osfhandle(long osfhandle, int flags)
{
    int fd = _open_osfhandle(osfhandle, flags);
    if (fd == -1) {
	errno = EMFILE;		/* too many open files */
	_doserrno = 0L;		/* not an OS error */
    }
    return fd;
}
#endif

#undef getsockopt

static int
is_socket(SOCKET fd)
{
    char sockbuf[80];
    int optlen;
    int retval;
    int result = TRUE;

    optlen = sizeof(sockbuf);
    RUBY_CRITICAL({
	retval = getsockopt(fd, SOL_SOCKET, SO_TYPE, sockbuf, &optlen);
	if (retval == SOCKET_ERROR) {
	    int iRet;
	    iRet = WSAGetLastError();
	    if (iRet == WSAENOTSOCK || iRet == WSANOTINITIALISED)
		result = FALSE;
	}
    });

    //
    // If we get here, then fd is actually a socket.
    //

    return result;
}

//
// Since the errors returned by the socket error function
// WSAGetLastError() are not known by the library routine strerror
// we have to roll our own.
//

#undef strerror

char *
rb_w32_strerror(int e)
{
    static char buffer[512];
    DWORD source = 0;
    char *p;

#if defined __BORLANDC__ && defined ENOTEMPTY // _sys_errlist is broken
    switch (e) {
      case ENAMETOOLONG:
	return "Filename too long";
      case ENOTEMPTY:
	return "Directory not empty";
    }
#endif

    if (e < 0 || e > sys_nerr) {
	if (e < 0)
	    e = GetLastError();
	if (FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
			  FORMAT_MESSAGE_IGNORE_INSERTS, &source, e, 0,
			  buffer, sizeof(buffer), NULL) == 0) {
	    strcpy(buffer, "Unknown Error");
	}
    }
    else {
	strncpy(buffer, strerror(e), sizeof(buffer));
	buffer[sizeof(buffer) - 1] = 0;
    }

    p = buffer;
    while ((p = strpbrk(p, "\r\n")) != NULL) {
	memmove(p, p + 1, strlen(p));
    }
    return buffer;
}

//
// various stubs
//


// Ownership
//
// Just pretend that everyone is a superuser. NT will let us know if
// we don't really have permission to do something.
//

#define ROOT_UID	0
#define ROOT_GID	0

rb_uid_t
getuid(void)
{
	return ROOT_UID;
}

rb_uid_t
geteuid(void)
{
	return ROOT_UID;
}

rb_gid_t
getgid(void)
{
	return ROOT_GID;
}

rb_gid_t
getegid(void)
{
    return ROOT_GID;
}

int
setuid(rb_uid_t uid)
{
    return (uid == ROOT_UID ? 0 : -1);
}

int
setgid(rb_gid_t gid)
{
    return (gid == ROOT_GID ? 0 : -1);
}

//
// File system stuff
//

int
/* ioctl(int i, unsigned int u, char *data) */
#ifdef __BORLANDC__
  ioctl(int i, int u, ...)
#else
  ioctl(int i, unsigned int u, long data)
#endif
{
    errno = EINVAL;
    return -1;
}

#undef FD_SET

void
rb_w32_fdset(int fd, fd_set *set)
{
    unsigned int i;
    SOCKET s = TO_SOCKET(fd);

    for (i = 0; i < set->fd_count; i++) {
        if (set->fd_array[i] == s) {
            return;
        }
    }
    if (i == set->fd_count) {
        if (set->fd_count < FD_SETSIZE) {
            set->fd_array[i] = s;
            set->fd_count++;
        }
    }
}

#undef FD_CLR

void
rb_w32_fdclr(int fd, fd_set *set)
{
    unsigned int i;
    SOCKET s = TO_SOCKET(fd);

    for (i = 0; i < set->fd_count; i++) {
        if (set->fd_array[i] == s) {
            while (i < set->fd_count - 1) {
                set->fd_array[i] = set->fd_array[i + 1];
                i++;
            }
            set->fd_count--;
            break;
        }
    }
}

#undef FD_ISSET

int
rb_w32_fdisset(int fd, fd_set *set)
{
    int ret;
    SOCKET s = TO_SOCKET(fd);
    if (s == (SOCKET)INVALID_HANDLE_VALUE)
        return 0;
    RUBY_CRITICAL(ret = __WSAFDIsSet(s, set));
    return ret;
}

//
// Networking trampolines
// These are used to avoid socket startup/shutdown overhead in case
// the socket routines aren't used.
//

#undef select

static int NtSocketsInitialized = 0;

static int
extract_fd(fd_set *dst, fd_set *src, int (*func)(SOCKET))
{
    int s = 0;
    if (!src || !dst) return 0;

    while (s < src->fd_count) {
        SOCKET fd = src->fd_array[s];

	if (!func || (*func)(fd)) { /* move it to dst */
	    int d;

	    for (d = 0; d < dst->fd_count; d++) {
		if (dst->fd_array[d] == fd) break;
	    }
	    if (d == dst->fd_count && dst->fd_count < FD_SETSIZE) {
		dst->fd_array[dst->fd_count++] = fd;
	    }
	    memmove(
		&src->fd_array[s],
		&src->fd_array[s+1],
		sizeof(src->fd_array[0]) * (--src->fd_count - s));
	}
	else s++;
    }

    return dst->fd_count;
}

static int
is_not_socket(SOCKET sock)
{
    return !is_socket(sock);
}

static int
is_pipe(SOCKET sock) /* DONT call this for SOCKET! it clains it is PIPE. */
{
    int ret;

    RUBY_CRITICAL(
	ret = (GetFileType((HANDLE)sock) == FILE_TYPE_PIPE)
    );

    return ret;
}

static int
is_readable_pipe(SOCKET sock) /* call this for pipe only */
{
    int ret;
    DWORD n = 0;

    RUBY_CRITICAL(
	if (PeekNamedPipe((HANDLE)sock, NULL, 0, NULL, &n, NULL)) {
	    ret = (n > 0);
	}
	else {
	    ret = (GetLastError() == ERROR_BROKEN_PIPE); /* pipe was closed */
	}
    );

    return ret;
}

static int
is_console(SOCKET sock) /* DONT call this for SOCKET! */
{
    int ret;
    DWORD n = 0;
    INPUT_RECORD ir;

    RUBY_CRITICAL(
	ret = (PeekConsoleInput((HANDLE)sock, &ir, 1, &n))
    );

    return ret;
}

static int
is_readable_console(SOCKET sock) /* call this for console only */
{
    int ret = 0;
    DWORD n = 0;
    INPUT_RECORD ir;

    RUBY_CRITICAL(
	if (PeekConsoleInput((HANDLE)sock, &ir, 1, &n) && n > 0) {
	    if (ir.EventType == KEY_EVENT && ir.Event.KeyEvent.bKeyDown &&
		ir.Event.KeyEvent.uChar.AsciiChar) {
		ret = 1;
	    }
	    else {
		ReadConsoleInput((HANDLE)sock, &ir, 1, &n);
	    }
	}
    );

    return ret;
}

static int
do_select(int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
            struct timeval *timeout)
{
    int r = 0;

    if (nfds == 0) {
	if (timeout)
	    rb_w32_sleep(timeout->tv_sec * 1000 + timeout->tv_usec / 1000);
	else
	    rb_w32_sleep(INFINITE);
    }
    else {
	RUBY_CRITICAL(
	    EnterCriticalSection(&select_mutex);
	    r = select(nfds, rd, wr, ex, timeout);
	    LeaveCriticalSection(&select_mutex);
	    if (r == SOCKET_ERROR) {
		errno = map_errno(WSAGetLastError());
		r = -1;
	    }
	);
    }

    return r;
}

static inline int
subtract(struct timeval *rest, const struct timeval *wait)
{
    if (rest->tv_sec < wait->tv_sec) {
	return 0;
    }
    while (rest->tv_usec <= wait->tv_usec) {
	if (rest->tv_sec <= wait->tv_sec) {
	    return 0;
	}
	rest->tv_sec -= 1;
	rest->tv_usec += 1000 * 1000;
    }
    rest->tv_sec -= wait->tv_sec;
    rest->tv_usec -= wait->tv_usec;
    return 1;
}

static inline int
compare(const struct timeval *t1, const struct timeval *t2)
{
    if (t1->tv_sec < t2->tv_sec)
	return -1;
    if (t1->tv_sec > t2->tv_sec)
	return 1;
    if (t1->tv_usec < t2->tv_usec)
	return -1;
    if (t1->tv_usec > t2->tv_usec)
	return 1;
    return 0;
}

#undef Sleep
long
rb_w32_select(int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
	      struct timeval *timeout)
{
    long r;
    fd_set pipe_rd;
    fd_set cons_rd;
    fd_set else_rd;
    fd_set else_wr;
    int nonsock = 0;
    struct timeval limit;

    if (nfds < 0 || (timeout && (timeout->tv_sec < 0 || timeout->tv_usec < 0))) {
	errno = EINVAL;
	return -1;
    }

    if (timeout) {
	if (timeout->tv_sec < 0 ||
	    timeout->tv_usec < 0 ||
	    timeout->tv_usec >= 1000000) {
	    errno = EINVAL;
	    return -1;
	}
	gettimeofday(&limit, NULL);
	limit.tv_sec += timeout->tv_sec;
	limit.tv_usec += timeout->tv_usec;
	if (limit.tv_usec >= 1000000) {
	    limit.tv_usec -= 1000000;
	    limit.tv_sec++;
	}
    }

    if (!NtSocketsInitialized) {
	StartSockets();
    }

    // assume else_{rd,wr} (other than socket, pipe reader, console reader)
    // are always readable/writable. but this implementation still has
    // problem. if pipe's buffer is full, writing to pipe will block
    // until some data is read from pipe. but ruby is single threaded system,
    // so whole system will be blocked forever.

    else_rd.fd_count = 0;
    nonsock += extract_fd(&else_rd, rd, is_not_socket);

    pipe_rd.fd_count = 0;
    extract_fd(&pipe_rd, &else_rd, is_pipe); // should not call is_pipe for socket

    cons_rd.fd_count = 0;
    extract_fd(&cons_rd, &else_rd, is_console); // ditto

    else_wr.fd_count = 0;
    nonsock += extract_fd(&else_wr, wr, is_not_socket);

    r = 0;
    if (rd && rd->fd_count > r) r = rd->fd_count;
    if (wr && wr->fd_count > r) r = wr->fd_count;
    if (ex && ex->fd_count > r) r = ex->fd_count;
    if (nfds > r) nfds = r;

    {
	struct timeval rest;
	struct timeval wait;
	struct timeval zero;
	wait.tv_sec = 0; wait.tv_usec = 10 * 1000; // 10ms
	zero.tv_sec = 0; zero.tv_usec = 0;         //  0ms
	if (timeout) rest = *timeout;
	for (;;) {
	    if (nonsock) {
		// modifying {else,pipe,cons}_rd is safe because
		// if they are modified, function returns immediately.
		extract_fd(&else_rd, &pipe_rd, is_readable_pipe);
		extract_fd(&else_rd, &cons_rd, is_readable_console);
	    }

	    if (else_rd.fd_count || else_wr.fd_count) {
		r = do_select(nfds, rd, wr, ex, &zero); // polling
		if (r < 0) break; // XXX: should I ignore error and return signaled handles?
		r += extract_fd(rd, &else_rd, NULL); // move all
		r += extract_fd(wr, &else_wr, NULL); // move all
		break;
	    }
	    else {
		fd_set orig_rd;
		fd_set orig_wr;
		fd_set orig_ex;
		struct timeval *dowait = &wait;
		if (timeout && compare(&rest, &wait) < 0) dowait = &rest;

		if (rd) orig_rd = *rd;
		if (wr) orig_wr = *wr;
		if (ex) orig_ex = *ex;
		r = do_select(nfds, rd, wr, ex, dowait);
		if (r != 0) break; // signaled or error
		if (rd) *rd = orig_rd;
		if (wr) *wr = orig_wr;
		if (ex) *ex = orig_ex;

		if (timeout) {
		    struct timeval now;
		    gettimeofday(&now, NULL);
		    rest = limit;
		    if (!subtract(&rest, &now)) break;
		}
	    }
	}
    }

    return r;
}

static void
StartSockets ()
{
    WORD version;
    WSADATA retdata;
    int ret;
#ifndef USE_WINSOCK2
    int iSockOpt;
#endif

    //
    // initalize the winsock interface and insure that it's
    // cleaned up at exit.
    //
#ifdef USE_WINSOCK2
    version = MAKEWORD(2, 0);
    if (WSAStartup(version, &retdata))
	rb_fatal ("Unable to locate winsock library!\n");
    if (LOBYTE(retdata.wVersion) != 2)
	rb_fatal("could not find version 2 of winsock dll\n");
#else
    version = MAKEWORD(1, 1);
    if (ret = WSAStartup(version, &retdata))
	rb_fatal ("Unable to locate winsock library!\n");
    if (LOBYTE(retdata.wVersion) != 1)
	rb_fatal("could not find version 1 of winsock dll\n");

    if (HIBYTE(retdata.wVersion) != 1)
	rb_fatal("could not find version 1 of winsock dll\n");
#endif	/* USE_WINSOCK2 */

    fWinsock = TRUE;

#ifndef USE_WINSOCK2
# ifndef SO_SYNCHRONOUS_NONALERT
#  define SO_SYNCHRONOUS_NONALERT 0x20
# endif

    iSockOpt = SO_SYNCHRONOUS_NONALERT;
    /*
     * Enable the use of sockets as filehandles
     */
# ifndef SO_OPENTYPE
#  define SO_OPENTYPE     0x7008
# endif

    setsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE,
	       (char *)&iSockOpt, sizeof(iSockOpt));
#endif	/* USE_WINSOCK2 */

    main_thread.handle = GetCurrentThreadHandle();
    main_thread.id = GetCurrentThreadId();

    interrupted_event = CreateSignal();
    if (!interrupted_event)
	rb_fatal("Unable to create interrupt event!\n");
    NtSocketsInitialized = 1;
}

#undef accept

int
rb_w32_accept(int s, struct sockaddr *addr, int *addrlen)
{
    SOCKET r;
    int fd;

    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	HANDLE h = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
	fd = rb_w32_open_osfhandle((long)h, O_RDWR|O_BINARY|O_NOINHERIT);
	if (fd != -1) {
	    r = accept(TO_SOCKET(s), addr, addrlen);
	    if (r != INVALID_SOCKET) {
		MTHREAD_ONLY(EnterCriticalSection(&(_pioinfo(fd)->lock)));
		_set_osfhnd(fd, r);
		MTHREAD_ONLY(LeaveCriticalSection(&_pioinfo(fd)->lock));
		CloseHandle(h);
	    }
	    else {
		errno = map_errno(WSAGetLastError());
		close(fd);
		fd = -1;
	    }
	}
	else
	    CloseHandle(h);
    });
    return fd;
}

#undef bind

int
rb_w32_bind(int s, struct sockaddr *addr, int addrlen)
{
    int r;

    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = bind(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef connect

int
rb_w32_connect(int s, struct sockaddr *addr, int addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = connect(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR) {
	    int err = WSAGetLastError();
	    if (err != WSAEWOULDBLOCK)
		errno = map_errno(err);
	    else
		errno = EINPROGRESS;
	}
    });
    return r;
}


#undef getpeername

int
rb_w32_getpeername(int s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getpeername(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef getsockname

int
rb_w32_getsockname(int s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getsockname(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

int
rb_w32_getsockopt(int s, int level, int optname, char *optval, int *optlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getsockopt(TO_SOCKET(s), level, optname, optval, optlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef ioctlsocket

int
rb_w32_ioctlsocket(int s, long cmd, u_long *argp)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = ioctlsocket(TO_SOCKET(s), cmd, argp);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef listen

int
rb_w32_listen(int s, int backlog)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = listen(TO_SOCKET(s), backlog);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef recv

int
rb_w32_recv(int s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = recv(TO_SOCKET(s), buf, len, flags);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef recvfrom

int
rb_w32_recvfrom(int s, char *buf, int len, int flags,
		struct sockaddr *from, int *fromlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = recvfrom(TO_SOCKET(s), buf, len, flags, from, fromlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef send

int
rb_w32_send(int s, const char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = send(TO_SOCKET(s), buf, len, flags);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef sendto

int
rb_w32_sendto(int s, const char *buf, int len, int flags,
	      struct sockaddr *to, int tolen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = sendto(TO_SOCKET(s), buf, len, flags, to, tolen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef setsockopt

int
rb_w32_setsockopt(int s, int level, int optname, char *optval, int optlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = setsockopt(TO_SOCKET(s), level, optname, optval, optlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef shutdown

int
rb_w32_shutdown(int s, int how)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = shutdown(TO_SOCKET(s), how);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#ifdef USE_WINSOCK2
static SOCKET
open_ifs_socket(int af, int type, int protocol)
{
    unsigned long proto_buffers_len = 0;
    int error_code;
    SOCKET out = INVALID_SOCKET;

    if (WSAEnumProtocols(NULL, NULL, &proto_buffers_len) == SOCKET_ERROR) {
	error_code = WSAGetLastError();
	if (error_code == WSAENOBUFS) {
	    WSAPROTOCOL_INFO *proto_buffers;
	    int protocols_available = 0;

	    proto_buffers = (WSAPROTOCOL_INFO *)malloc(proto_buffers_len);
	    if (!proto_buffers) {
		WSASetLastError(WSA_NOT_ENOUGH_MEMORY);
		return INVALID_SOCKET;
	    }

	    protocols_available =
		WSAEnumProtocols(NULL, proto_buffers, &proto_buffers_len);
	    if (protocols_available != SOCKET_ERROR) {
		int i;
		for (i = 0; i < protocols_available; i++) {
		    if ((af != AF_UNSPEC && af != proto_buffers[i].iAddressFamily) ||
			(type != proto_buffers[i].iSocketType) ||
			(protocol != 0 && protocol != proto_buffers[i].iProtocol))
			continue;

		    if ((proto_buffers[i].dwServiceFlags1 & XP1_IFS_HANDLES) == 0)
			continue;

		    out = WSASocket(af, type, protocol, &(proto_buffers[i]), 0, 0);
		    break;
		}
		if (out == INVALID_SOCKET)
		    out = WSASocket(af, type, protocol, NULL, 0, 0);
	    }

	    free(proto_buffers);
	}
    }

    return out;
}
#endif	/* USE_WINSOCK2 */

#undef socket
#ifdef USE_WINSOCK2
#define open_socket(a, t, p)	open_ifs_socket(a, t, p)
#else
#define open_socket(a, t, p)	socket(a, t, p)
#endif

int
rb_w32_socket(int af, int type, int protocol)
{
    SOCKET s;
    int fd;

    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	s = open_socket(af, type, protocol);
	if (s == INVALID_SOCKET) {
	    errno = map_errno(WSAGetLastError());
	    fd = -1;
	}
	else {
	    fd = rb_w32_open_osfhandle(s, O_RDWR|O_BINARY);
	}
    });
    return fd;
}

#undef gethostbyaddr

struct hostent *
rb_w32_gethostbyaddr (char *addr, int len, int type)
{
    struct hostent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = gethostbyaddr(addr, len, type);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef gethostbyname

struct hostent *
rb_w32_gethostbyname (char *name)
{
    struct hostent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = gethostbyname(name);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef gethostname

int
rb_w32_gethostname (char *name, int len)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = gethostname(name, len);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef getprotobyname

struct protoent *
rb_w32_getprotobyname (char *name)
{
    struct protoent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getprotobyname(name);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef getprotobynumber

struct protoent *
rb_w32_getprotobynumber (int num)
{
    struct protoent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getprotobynumber(num);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef getservbyname

struct servent *
rb_w32_getservbyname (char *name, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getservbyname(name, proto);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

#undef getservbyport

struct servent *
rb_w32_getservbyport (int port, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    RUBY_CRITICAL({
	r = getservbyport(port, proto);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    });
    return r;
}

//
// Networking stubs
//

void endhostent() {}
void endnetent() {}
void endprotoent() {}
void endservent() {}

struct netent *getnetent (void) {return (struct netent *) NULL;}

struct netent *getnetbyaddr(long net, int type) {return (struct netent *)NULL;}

struct netent *getnetbyname(char *name) {return (struct netent *)NULL;}

struct protoent *getprotoent (void) {return (struct protoent *) NULL;}

struct servent *getservent (void) {return (struct servent *) NULL;}

void sethostent (int stayopen) {}

void setnetent (int stayopen) {}

void setprotoent (int stayopen) {}

void setservent (int stayopen) {}

int
fcntl(int fd, int cmd, ...)
{
    SOCKET sock = TO_SOCKET(fd);
    va_list va;
    int arg;
    int ret;
    u_long ioctlArg;

    if (!is_socket(sock)) {
	errno = EBADF;
	return -1;
    }
    if (cmd != F_SETFL) {
	errno = EINVAL;
	return -1;
    }

    va_start(va, cmd);
    arg = va_arg(va, int);
    va_end(va);
    if (arg & O_NONBLOCK) {
	ioctlArg = 1;
    }
    else {
	ioctlArg = 0;
    }
    RUBY_CRITICAL({
	ret = ioctlsocket(sock, FIONBIO, &ioctlArg);
	if (ret == -1) {
	    errno = map_errno(WSAGetLastError());
	}
    });

    return ret;
}

#ifndef WNOHANG
#define WNOHANG -1
#endif

static rb_pid_t
poll_child_status(struct ChildRecord *child, int *stat_loc)
{
    DWORD exitcode;
    DWORD err;

    if (!GetExitCodeProcess(child->hProcess, &exitcode)) {
	/* If an error occured, return immediatly. */
	err = GetLastError();
	if (err == ERROR_INVALID_PARAMETER)
	    errno = ECHILD;
	else
	    errno = map_errno(GetLastError());
	CloseChildHandle(child);
	return -1;
    }
    if (exitcode != STILL_ACTIVE) {
	/* If already died, return immediatly. */
	rb_pid_t pid = child->pid;
	CloseChildHandle(child);
	if (stat_loc) *stat_loc = exitcode << 8;
	return pid;
    }
    return 0;
}

rb_pid_t
waitpid(rb_pid_t pid, int *stat_loc, int options)
{
    DWORD timeout;

    if (options == WNOHANG) {
	timeout = 0;
    } else {
	timeout = INFINITE;
    }

    if (pid == -1) {
	int count = 0;
	DWORD ret;
	HANDLE events[MAXCHILDNUM + 1];

	FOREACH_CHILD(child) {
	    if (!child->pid || child->pid < 0) continue;
	    if ((pid = poll_child_status(child, stat_loc))) return pid;
	    events[count++] = child->hProcess;
	} END_FOREACH_CHILD;
	if (!count) {
	    errno = ECHILD;
	    return -1;
	}
	events[count] = interrupted_event;

	ret = WaitForMultipleEvents(count + 1, events, FALSE, timeout, TRUE);
	if (ret == WAIT_TIMEOUT) return 0;
	if ((ret -= WAIT_OBJECT_0) == count) {
	    ResetSignal(interrupted_event);
	    errno = EINTR;
	    return -1;
	}
	if (ret > count) {
	    errno = map_errno(GetLastError());
	    return -1;
	}

	return poll_child_status(FindChildSlotByHandle(events[ret]), stat_loc);
    }
    else {
	struct ChildRecord* child = FindChildSlot(pid);
	if (!child) {
	    errno = ECHILD;
	    return -1;
	}

	while (!(pid = poll_child_status(child, stat_loc))) {
	    /* wait... */
	    if (wait_events(child->hProcess, timeout) != WAIT_OBJECT_0) {
		/* still active */
		pid = 0;
		break;
	    }
	}
    }

    return pid;
}

#include <sys/timeb.h>

static int
filetime_to_timeval(const FILETIME* ft, struct timeval *tv)
{
    ULARGE_INTEGER tmp;
    unsigned LONG_LONG lt;

    tmp.LowPart = ft->dwLowDateTime;
    tmp.HighPart = ft->dwHighDateTime;
    lt = tmp.QuadPart;

    /* lt is now 100-nanosec intervals since 1601/01/01 00:00:00 UTC,
       convert it into UNIX time (since 1970/01/01 00:00:00 UTC).
       the first leap second is at 1972/06/30, so we doesn't need to think
       about it. */
    lt /= 10;	/* to usec */
    lt -= (LONG_LONG)((1970-1601)*365.2425) * 24 * 60 * 60 * 1000 * 1000;

    tv->tv_sec = lt / (1000 * 1000);
    tv->tv_usec = lt % (1000 * 1000);

    return tv->tv_sec > 0 ? 0 : -1;
}

int _cdecl
gettimeofday(struct timeval *tv, struct timezone *tz)
{
    FILETIME ft;

    GetSystemTimeAsFileTime(&ft);
    filetime_to_timeval(&ft, tv);

    return 0;
}

char *
rb_w32_getcwd(char *buffer, int size)
{
    char *p = buffer;
    char *bp;
    int len;

    len = GetCurrentDirectory(0, NULL);
    if (!len) {
	errno = map_errno(GetLastError());
	return NULL;
    }

    if (p) {
	if (size < len) {
	    errno = ERANGE;
	    return NULL;
	}
    }
    else {
	p = malloc(len);
	size = len;
	if (!p) {
	    errno = ENOMEM;
	    return NULL;
	}
    }

    if (!GetCurrentDirectory(size, p)) {
	errno = map_errno(GetLastError());
	if (!buffer)
	    free(p);
	return NULL;
    }

    for (bp = p; *bp != '\0'; bp = CharNext(bp)) {
	if (*bp == '\\') {
	    *bp = '/';
	}
    }

    return p;
}

int
chown(const char *path, int owner, int group)
{
	return 0;
}

int
kill(int pid, int sig)
{
    int ret = 0;
    DWORD err;

    if (pid <= 0) {
	errno = EINVAL;
	return -1;
    }

    if (IsWin95()) pid = -pid;
    if ((unsigned int)pid == GetCurrentProcessId() &&
	(sig != 0 && sig != SIGKILL)) {
	if ((ret = raise(sig)) != 0) {
	    /* MSVCRT doesn't set errno... */
	    errno = EINVAL;
	}
	return ret;
    }

    switch (sig) {
      case 0:
	RUBY_CRITICAL({
	    HANDLE hProc =
		OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
	    if (hProc == NULL || hProc == INVALID_HANDLE_VALUE) {
		if (GetLastError() == ERROR_INVALID_PARAMETER) {
		    errno = ESRCH;
		}
		else {
		    errno = EPERM;
		}
		ret = -1;
	    }
	    else {
		CloseHandle(hProc);
	    }
	});
	break;

      case SIGINT:
	RUBY_CRITICAL({
	    if (!GenerateConsoleCtrlEvent(CTRL_C_EVENT, (DWORD)pid)) {
		if ((err = GetLastError()) == 0)
		    errno = EPERM;
		else
		    errno = map_errno(GetLastError());
		ret = -1;
	    }
	});
	break;

      case SIGKILL:
	RUBY_CRITICAL({
	    HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, (DWORD)pid);
	    if (hProc == NULL || hProc == INVALID_HANDLE_VALUE) {
		if (GetLastError() == ERROR_INVALID_PARAMETER) {
		    errno = ESRCH;
		}
		else {
		    errno = EPERM;
		}
		ret = -1;
	    }
	    else {
		if (!TerminateProcess(hProc, 0)) {
		    errno = EPERM;
		    ret = -1;
		}
		CloseHandle(hProc);
	    }
	});
	break;

      default:
	errno = EINVAL;
	ret = -1;
	break;
    }

    return ret;
}

int
link(char *from, char *to)
{
    static BOOL (WINAPI *pCreateHardLink)(LPCTSTR, LPCTSTR, LPSECURITY_ATTRIBUTES) = NULL;
    static int myerrno = 0;

    if (!pCreateHardLink && !myerrno) {
	HANDLE hKernel;

	hKernel = GetModuleHandle("kernel32.dll");
	if (hKernel) {
	    pCreateHardLink = (BOOL (WINAPI *)(LPCTSTR, LPCTSTR, LPSECURITY_ATTRIBUTES))GetProcAddress(hKernel, "CreateHardLinkA");
	    if (!pCreateHardLink) {
		myerrno = map_errno(GetLastError());
	    }
	    CloseHandle(hKernel);
	}
	else {
	    myerrno = map_errno(GetLastError());
	}
    }
    if (!pCreateHardLink) {
	errno = myerrno;
	return -1;
    }

    if (!pCreateHardLink(to, from, NULL)) {
	errno = map_errno(GetLastError());
	return -1;
    }

    return 0;
}

int
wait()
{
	return 0;
}

char *
rb_w32_getenv(const char *name)
{
    int len = strlen(name);
    char *env;

    if (envarea)
	FreeEnvironmentStrings(envarea);
    envarea = GetEnvironmentStrings();
    if (!envarea) {
	map_errno(GetLastError());
	return NULL;
    }

    for (env = envarea; *env; env += strlen(env) + 1)
	if (strncasecmp(env, name, len) == 0 && *(env + len) == '=')
	    return env + len + 1;

    return NULL;
}

int
rb_w32_rename(const char *oldpath, const char *newpath)
{
    int res = 0;
    int oldatts;
    int newatts;

    oldatts = GetFileAttributes(oldpath);
    newatts = GetFileAttributes(newpath);

    if (oldatts == -1) {
	errno = map_errno(GetLastError());
	return -1;
    }

    RUBY_CRITICAL({
	if (newatts != -1 && newatts & FILE_ATTRIBUTE_READONLY)
	    SetFileAttributesA(newpath, newatts & ~ FILE_ATTRIBUTE_READONLY);

	if (!MoveFile(oldpath, newpath))
	    res = -1;

	if (res) {
	    switch (GetLastError()) {
	      case ERROR_ALREADY_EXISTS:
	      case ERROR_FILE_EXISTS:
		if (IsWinNT()) {
		    if (MoveFileEx(oldpath, newpath, MOVEFILE_REPLACE_EXISTING))
			res = 0;
		} else {
		    for (;;) {
			if (!DeleteFile(newpath) && GetLastError() != ERROR_FILE_NOT_FOUND)
			    break;
			else if (MoveFile(oldpath, newpath)) {
			    res = 0;
			    break;
			}
		    }
		}
	    }
	}

	if (res)
	    errno = map_errno(GetLastError());
	else
	    SetFileAttributes(newpath, oldatts);
    });

    return res;
}

static int
isUNCRoot(const char *path)
{
    if (path[0] == '\\' && path[1] == '\\') {
	const char *p;
	for (p = path + 2; *p; p = CharNext(p)) {
	    if (*p == '\\')
		break;
	}
	if (p[0] && p[1]) {
	    for (p++; *p; p = CharNext(p)) {
		if (*p == '\\')
		    break;
	    }
	    if (!p[0] || !p[1] || (p[1] == '.' && !p[2]))
		return 1;
	}
    }
    return 0;
}

static time_t
filetime_to_unixtime(const FILETIME *ft)
{
    struct timeval tv;

    if (filetime_to_timeval(ft, &tv) == (time_t)-1)
	return 0;
    else
	return tv.tv_sec;
}

static unsigned
fileattr_to_unixmode(DWORD attr, const char *path)
{
    unsigned mode = 0;

    if (attr & FILE_ATTRIBUTE_READONLY) {
	mode |= S_IREAD;
    }
    else {
	mode |= S_IREAD | S_IWRITE | S_IWUSR;
    }

    if (attr & FILE_ATTRIBUTE_DIRECTORY) {
	mode |= S_IFDIR | S_IEXEC;
    }
    else {
	mode |= S_IFREG;
    }

    if (path && (mode & S_IFREG)) {
	const char *end = path + strlen(path);
	while (path < end) {
	    end = CharPrev(path, end);
	    if (*end == '.') {
		if ((strcmpi(end, ".bat") == 0) ||
		    (strcmpi(end, ".cmd") == 0) ||
		    (strcmpi(end, ".com") == 0) ||
		    (strcmpi(end, ".exe") == 0)) {
		    mode |= S_IEXEC;
		}
		break;
	    }
	}
    }

    mode |= (mode & 0700) >> 3;
    mode |= (mode & 0700) >> 6;

    return mode;
}

static int
check_valid_dir(const char *path)
{
    WIN32_FIND_DATA fd;
    HANDLE fh = open_dir_handle(path, &fd);
    if (fh == INVALID_HANDLE_VALUE)
	return -1;
    FindClose(fh);
    return 0;
}

static int
winnt_stat(const char *path, struct stat *st)
{
    HANDLE h;
    WIN32_FIND_DATA wfd;

    memset(st, 0, sizeof(struct stat));
    st->st_nlink = 1;

    if (_mbspbrk(path, "?*")) {
	errno = ENOENT;
	return -1;
    }
    h = FindFirstFile(path, &wfd);
    if (h != INVALID_HANDLE_VALUE) {
	FindClose(h);
	st->st_mode  = fileattr_to_unixmode(wfd.dwFileAttributes, path);
	st->st_atime = filetime_to_unixtime(&wfd.ftLastAccessTime);
	st->st_mtime = filetime_to_unixtime(&wfd.ftLastWriteTime);
	st->st_ctime = filetime_to_unixtime(&wfd.ftCreationTime);
	st->st_size  = wfd.nFileSizeLow; /* TODO: 64bit support */
    }
    else {
	// If runtime stat(2) is called for network shares, it fails on WinNT.
	// Because GetDriveType returns 1 for network shares. (Win98 returns 4)
	DWORD attr = GetFileAttributes(path);
	if (attr == -1) {
	    errno = map_errno(GetLastError());
	    return -1;
	}
	if (attr & FILE_ATTRIBUTE_DIRECTORY) {
	    if (check_valid_dir(path)) return -1;
	}
	st->st_mode  = fileattr_to_unixmode(attr, path);
    }

    st->st_dev = st->st_rdev = (isalpha(path[0]) && path[1] == ':') ?
	toupper(path[0]) - 'A' : _getdrive() - 1;

    return 0;
}

#ifdef WIN95
static int
win95_stat(const char *path, struct stat *st)
{
    int ret = stat(path, st);
    if (ret) return ret;
    if (st->st_mode & S_IFDIR) {
	return check_valid_dir(path);
    }
    return 0;
}
#else
#define win95_stat(path, st) -1
#endif

int
rb_w32_stat(const char *path, struct stat *st)
{
    const char *p;
    char *buf1, *s, *end;
    int len;
    int ret;

    if (!path || !st) {
	errno = EFAULT;
	return -1;
    }
    buf1 = ALLOCA_N(char, strlen(path) + 2);
    for (p = path, s = buf1; *p; p++, s++) {
	if (*p == '/')
	    *s = '\\';
	else
	    *s = *p;
    }
    *s = '\0';
    len = s - buf1;
    if (!len || '\"' == *(--s)) {
	errno = ENOENT;
	return -1;
    }
    end = CharPrev(buf1, buf1 + len);

    if (isUNCRoot(buf1)) {
	if (*end == '.')
	    *end = '\0';
	else if (*end != '\\')
	    strcat(buf1, "\\");
    } else if (*end == '\\' || (buf1 + 1 == end && *end == ':'))
	strcat(buf1, ".");

    ret = IsWinNT() ? winnt_stat(buf1, st) : win95_stat(buf1, st);
    if (ret == 0) {
	st->st_mode &= ~(S_IWGRP | S_IWOTH);
    }
    return ret;
}

static long
filetime_to_clock(FILETIME *ft)
{
    __int64 qw = ft->dwHighDateTime;
    qw <<= 32;
    qw |= ft->dwLowDateTime;
    qw /= 10000;  /* File time ticks at 0.1uS, clock at 1mS */
    return (long) qw;
}

int
rb_w32_times(struct tms *tmbuf)
{
    FILETIME create, exit, kernel, user;

    if (GetProcessTimes(GetCurrentProcess(),&create, &exit, &kernel, &user)) {
	tmbuf->tms_utime = filetime_to_clock(&user);
	tmbuf->tms_stime = filetime_to_clock(&kernel);
	tmbuf->tms_cutime = 0;
	tmbuf->tms_cstime = 0;
    }
    else {
	tmbuf->tms_utime = clock();
	tmbuf->tms_stime = 0;
	tmbuf->tms_cutime = 0;
	tmbuf->tms_cstime = 0;
    }
    return 0;
}

#define yield_once() Sleep(0)
#define yield_until(condition) do yield_once(); while (!(condition))

static DWORD
wait_events(HANDLE event, DWORD timeout)
{
    HANDLE events[2];
    int count = 0;
    DWORD ret;

    if (event) {
	events[count++] = event;
    }
    events[count++] = interrupted_event;

    ret = WaitForMultipleEvents(count, events, FALSE, timeout, TRUE);

    if (ret == WAIT_OBJECT_0 + count - 1) {
	ResetSignal(interrupted_event);
	errno = EINTR;
    }

    return ret;
}

static CRITICAL_SECTION *
system_state(void)
{
    static int initialized = 0;
    static CRITICAL_SECTION syssect;

    if (!initialized) {
	InitializeCriticalSection(&syssect);
	initialized = 1;
    }
    return &syssect;
}

static LONG flag_interrupt = -1;
static volatile DWORD tlsi_interrupt = TLS_OUT_OF_INDEXES;

void
rb_w32_enter_critical(void)
{
    if (IsWinNT()) {
	EnterCriticalSection(system_state());
	return;
    }

    if (tlsi_interrupt == TLS_OUT_OF_INDEXES) {
	tlsi_interrupt = TlsAlloc();
    }

    {
	DWORD ti = (DWORD)TlsGetValue(tlsi_interrupt);
	while (InterlockedIncrement(&flag_interrupt) > 0 && !ti) {
	    InterlockedDecrement(&flag_interrupt);
	    Sleep(1);
	}
	TlsSetValue(tlsi_interrupt, (PVOID)++ti);
    }
}

void
rb_w32_leave_critical(void)
{
    if (IsWinNT()) {
	LeaveCriticalSection(system_state());
	return;
    }

    InterlockedDecrement(&flag_interrupt);
    TlsSetValue(tlsi_interrupt, (PVOID)((DWORD)TlsGetValue(tlsi_interrupt) - 1));
}

struct handler_arg_t {
    void (*handler)(int);
    int arg;
    int status;
    int finished;
    HANDLE handshake;
};

static void
rb_w32_call_handler(struct handler_arg_t* h)
{
    int status;
    RUBY_CRITICAL(rb_protect((VALUE (*)(VALUE))h->handler, (VALUE)h->arg, &h->status);
		  status = h->status;
		  SetEvent(h->handshake));
    if (status) {
	rb_jump_tag(status);
    }
    h->finished = 1;
    yield_until(0);
}

static struct handler_arg_t *
setup_handler(struct handler_arg_t *harg, int arg, void (*handler)(int),
	      HANDLE handshake)
{
    harg->handler = handler;
    harg->arg = arg;
    harg->status = 0;
    harg->finished = 0;
    harg->handshake = handshake;
    return harg;
}

static void
setup_call(CONTEXT* ctx, struct handler_arg_t *harg)
{
#ifdef _M_IX86
    DWORD *esp = (DWORD *)ctx->Esp;
    *--esp = (DWORD)harg;
    *--esp = ctx->Eip;
    ctx->Esp = (DWORD)esp;
    ctx->Eip = (DWORD)rb_w32_call_handler;
#else
#ifndef _WIN32_WCE
#error unsupported processor
#endif
#endif
}

void
rb_w32_interrupted(void)
{
    SetSignal(interrupted_event);
}

int
rb_w32_main_context(int arg, void (*handler)(int))
{
    static HANDLE interrupt_done = NULL;
    struct handler_arg_t harg;
    CONTEXT ctx_orig;
    HANDLE current_thread = GetCurrentThread();
    int old_priority = GetThreadPriority(current_thread);

    if (GetCurrentThreadId() == main_thread.id) return FALSE;

    rb_w32_interrupted();

    RUBY_CRITICAL({		/* the main thread must be in user state */
	CONTEXT ctx;

	SuspendThread(main_thread.handle);
	SetThreadPriority(current_thread, GetThreadPriority(main_thread.handle));

	ZeroMemory(&ctx, sizeof(CONTEXT));
	ctx.ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT;
	GetThreadContext(main_thread.handle, &ctx);
	ctx_orig = ctx;

	/* handler context setup */
	if (!interrupt_done) {
	    interrupt_done = CreateEvent(NULL, FALSE, FALSE, NULL);
	    /* anonymous one-shot event */
	}
	else {
	    ResetEvent(interrupt_done);
	}
	setup_call(&ctx, setup_handler(&harg, arg, handler, interrupt_done));

	ctx.ContextFlags = CONTEXT_CONTROL;
	SetThreadContext(main_thread.handle, &ctx);
	ResumeThread(main_thread.handle);
    });

    /* give a chance to the main thread */
    yield_once();
    WaitForSingleObject(interrupt_done, INFINITE); /* handshaking */

    if (!harg.status) {
	/* no exceptions raised, restore old context. */
	RUBY_CRITICAL({
	    /* ensure the main thread is in user state. */
	    yield_until(harg.finished);

	    SuspendThread(main_thread.handle);
	    ctx_orig.ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT;
	    SetThreadContext(main_thread.handle, &ctx_orig);
	    ResumeThread(main_thread.handle);
	});
    }
    /* otherwise leave the main thread raised */

    SetThreadPriority(current_thread, old_priority);

    return TRUE;
}

int
rb_w32_sleep(unsigned long msec)
{
    DWORD ret;
    RUBY_CRITICAL(ret = wait_events(NULL, msec));
    yield_once();
    CHECK_INTS;
    return ret != WAIT_TIMEOUT;
}

static void
catch_interrupt(void)
{
    yield_once();
    RUBY_CRITICAL(wait_events(NULL, 0));
    CHECK_INTS;
}

#undef fgetc
int
rb_w32_getc(FILE* stream)
{
    int c, trap_immediate = rb_trap_immediate;
#ifndef _WIN32_WCE
    if (enough_to_get(stream->FILE_COUNT)) {
	c = (unsigned char)*stream->FILE_READPTR++;
	rb_trap_immediate = trap_immediate;
    }
    else
#endif
    {
	c = _filbuf(stream);
#if defined __BORLANDC__ || defined _WIN32_WCE
        if ((c == EOF) && (errno == EPIPE)) {
	    clearerr(stream);
        }
#endif
	rb_trap_immediate = trap_immediate;
	catch_interrupt();
    }
    return c;
}

#undef fputc
int
rb_w32_putc(int c, FILE* stream)
{
    int trap_immediate = rb_trap_immediate;
#ifndef _WIN32_WCE
    if (enough_to_put(stream->FILE_COUNT)) {
	c = (unsigned char)(*stream->FILE_READPTR++ = (char)c);
	rb_trap_immediate = trap_immediate;
    }
    else
#endif
    {
	c = _flsbuf(c, stream);
	rb_trap_immediate = trap_immediate;
	catch_interrupt();
    }
    return c;
}

struct asynchronous_arg_t {
    /* output field */
    void* stackaddr;
    int errnum;

    /* input field */
    VALUE (*func)(VALUE self, int argc, VALUE* argv);
    VALUE self;
    int argc;
    VALUE* argv;
};

static DWORD WINAPI
call_asynchronous(PVOID argp)
{
    DWORD ret;
    struct asynchronous_arg_t *arg = argp;
    arg->stackaddr = &argp;
    ret = (DWORD)arg->func(arg->self, arg->argc, arg->argv);
    arg->errnum = errno;
    return ret;
}

VALUE
rb_w32_asynchronize(asynchronous_func_t func, VALUE self,
		    int argc, VALUE* argv, VALUE intrval)
{
    DWORD val;
    BOOL interrupted = FALSE;
    HANDLE thr;

    RUBY_CRITICAL({
	struct asynchronous_arg_t arg;

	arg.stackaddr = NULL;
	arg.errnum = 0;
	arg.func = func;
	arg.self = self;
	arg.argc = argc;
	arg.argv = argv;

	thr = CreateThread(NULL, 0, call_asynchronous, &arg, 0, &val);

	if (thr) {
	    yield_until(arg.stackaddr);

	    if (wait_events(thr, INFINITE) != WAIT_OBJECT_0) {
		interrupted = TRUE;

		if (TerminateThread(thr, intrval)) {
		    yield_once();
		}
	    }

	    GetExitCodeThread(thr, &val);
	    CloseHandle(thr);

	    if (interrupted) {
		/* must release stack of killed thread, why doesn't Windows? */
		MEMORY_BASIC_INFORMATION m;

		memset(&m, 0, sizeof(m));
		if (!VirtualQuery(arg.stackaddr, &m, sizeof(m))) {
		    Debug(fprintf(stderr, "couldn't get stack base:%p:%d\n",
				  arg.stackaddr, GetLastError()));
		}
		else if (!VirtualFree(m.AllocationBase, 0, MEM_RELEASE)) {
		    Debug(fprintf(stderr, "couldn't release stack:%p:%d\n",
				  m.AllocationBase, GetLastError()));
		}
		errno = EINTR;
	    }
	    else {
		errno = arg.errnum;
	    }
	}
    });

    if (!thr) {
	rb_fatal("failed to launch waiter thread:%d", GetLastError());
    }

    if (interrupted) {
	CHECK_INTS;
    }

    return val;
}

char **
rb_w32_get_environ(void)
{
    char *envtop, *env;
    char **myenvtop, **myenv;
    int num;

    /*
     * We avoid values started with `='. If you want to deal those values,
     * change this function, and some functions in hash.c which recognize
     * `=' as delimiter or rb_w32_getenv() and ruby_setenv().
     * CygWin deals these values by changing first `=' to '!'. But we don't
     * use such trick and follow cmd.exe's way that just doesn't show these
     * values.
     * (U.N. 2001-11-15)
     */
    envtop = GetEnvironmentStrings();
    for (env = envtop, num = 0; *env; env += strlen(env) + 1)
	if (*env != '=') num++;

    myenvtop = (char **)malloc(sizeof(char *) * (num + 1));
    for (env = envtop, myenv = myenvtop; *env; env += strlen(env) + 1) {
	if (*env != '=') {
	    if (!(*myenv = (char *)malloc(strlen(env) + 1))) {
		break;
	    }
	    strcpy(*myenv, env);
	    myenv++;
	}
    }
    *myenv = NULL;
    FreeEnvironmentStrings(envtop);

    return myenvtop;
}

void
rb_w32_free_environ(char **env)
{
    char **t = env;

    while (*t) free(*t++);
    free(env);
}

rb_pid_t
rb_w32_getpid(void)
{
    rb_pid_t pid;

    pid = GetCurrentProcessId();

    if (IsWin95()) pid = -pid;

    return pid;
}

int
rb_w32_fclose(FILE *fp)
{
    int fd = fileno(fp);
    SOCKET sock = TO_SOCKET(fd);
    int save_errno = errno;

    if (fflush(fp)) return -1;
    if (!is_socket(sock)) {
	UnlockFile((HANDLE)sock, 0, 0, LK_LEN, LK_LEN);
	return fclose(fp);
    }
    _set_osfhnd(fd, (SOCKET)INVALID_HANDLE_VALUE);
    fclose(fp);
    errno = save_errno;
    if (closesocket(sock) == SOCKET_ERROR) {
	errno = map_errno(WSAGetLastError());
	return -1;
    }
    return 0;
}

int
rb_w32_close(int fd)
{
    SOCKET sock = TO_SOCKET(fd);
    int save_errno = errno;

    if (!is_socket(sock)) {
	UnlockFile((HANDLE)sock, 0, 0, LK_LEN, LK_LEN);
	return _close(fd);
    }
    _set_osfhnd(fd, (SOCKET)INVALID_HANDLE_VALUE);
    _close(fd);
    errno = save_errno;
    if (closesocket(sock) == SOCKET_ERROR) {
	errno = map_errno(WSAGetLastError());
	return -1;
    }
    return 0;
}

#undef read
size_t
rb_w32_read(int fd, void *buf, size_t size)
{
    SOCKET sock = TO_SOCKET(fd);

    if (!is_socket(sock))
	return read(fd, buf, size);
    else
	return rb_w32_recv(fd, buf, size, 0);
}

#undef write
size_t
rb_w32_write(int fd, const void *buf, size_t size)
{
    SOCKET sock = TO_SOCKET(fd);

    if (!is_socket(sock))
	return write(fd, buf, size);
    else
	return rb_w32_send(fd, buf, size, 0);
}

static int
unixtime_to_filetime(time_t time, FILETIME *ft)
{
    struct tm *tm;
    SYSTEMTIME st;
    FILETIME lt;

    tm = localtime(&time);
    st.wYear = tm->tm_year + 1900;
    st.wMonth = tm->tm_mon + 1;
    st.wDayOfWeek = tm->tm_wday;
    st.wDay = tm->tm_mday;
    st.wHour = tm->tm_hour;
    st.wMinute = tm->tm_min;
    st.wSecond = tm->tm_sec;
    st.wMilliseconds = 0;
    if (!SystemTimeToFileTime(&st, &lt) ||
	!LocalFileTimeToFileTime(&lt, ft)) {
	errno = map_errno(GetLastError());
	return -1;
    }
    return 0;
}

int
rb_w32_utime(const char *path, struct utimbuf *times)
{
    HANDLE hFile;
    FILETIME atime, mtime;
    struct stat stat;
    int ret = 0;

    if (rb_w32_stat(path, &stat)) {
	return -1;
    }

    if (times) {
	if (unixtime_to_filetime(times->actime, &atime)) {
	    return -1;
	}
	if (unixtime_to_filetime(times->modtime, &mtime)) {
	    return -1;
	}
    }
    else {
	GetSystemTimeAsFileTime(&atime);
	mtime = atime;
    }

    RUBY_CRITICAL({
	const DWORD attr = GetFileAttributes(path);
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY))
	    SetFileAttributes(path, attr & ~FILE_ATTRIBUTE_READONLY);
	hFile = CreateFile(path, GENERIC_WRITE, 0, 0, OPEN_EXISTING,
			   IsWin95() ? 0 : FILE_FLAG_BACKUP_SEMANTICS, 0);
	if (hFile == INVALID_HANDLE_VALUE) {
	    errno = map_errno(GetLastError());
	    ret = -1;
	}
	else {
	    if (!SetFileTime(hFile, NULL, &atime, &mtime)) {
		errno = map_errno(GetLastError());
		ret = -1;
	    }
	    CloseHandle(hFile);
	}
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY))
	    SetFileAttributes(path, attr);
    });

    return ret;
}

int
rb_w32_vsnprintf(char *buf, size_t size, const char *format, va_list va)
{
    int ret = _vsnprintf(buf, size, format, va);
    if (size > 0) buf[size - 1] = 0;
    return ret;
}

int
rb_w32_snprintf(char *buf, size_t size, const char *format, ...)
{
    int ret;
    va_list va;

    va_start(va, format);
    ret = vsnprintf(buf, size, format, va);
    va_end(va);
    return ret;
}

int
rb_w32_mkdir(const char *path, int mode)
{
    int ret = -1;
    RUBY_CRITICAL(do {
	if (CreateDirectory(path, NULL) == FALSE) {
	    errno = map_errno(GetLastError());
	    break;
	}
	if (chmod(path, mode) == -1) {
	    RemoveDirectory(path);
	    break;
	}
	ret = 0;
    } while (0));
    return ret;
}

int
rb_w32_rmdir(const char *path)
{
    int ret = 0;
    RUBY_CRITICAL({
	const DWORD attr = GetFileAttributes(path);
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
	    SetFileAttributes(path, attr & ~FILE_ATTRIBUTE_READONLY);
	}
	if (RemoveDirectory(path) == FALSE) {
	    errno = map_errno(GetLastError());
	    ret = -1;
	    if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
		SetFileAttributes(path, attr);
	    }
	}
    });
    return ret;
}

int
rb_w32_unlink(const char *path)
{
    int ret = 0;
    RUBY_CRITICAL({
	const DWORD attr = GetFileAttributes(path);
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
	    SetFileAttributes(path, attr & ~FILE_ATTRIBUTE_READONLY);
	}
	if (DeleteFile(path) == FALSE) {
	    errno = map_errno(GetLastError());
	    ret = -1;
	    if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
		SetFileAttributes(path, attr);
	    }
	}
    });
    return ret;
}

#if !defined(__BORLANDC__) && !defined(_WIN32_WCE)
int
rb_w32_isatty(int fd)
{
    // validate fd by using _get_osfhandle() because we cannot access _nhandle
    if (_get_osfhandle(fd) == -1) {
	return 0;
    }
    if (!(_osfile(fd) & FOPEN)) {
	errno = EBADF;
	return 0;
    }
    if (!(_osfile(fd) & FDEV)) {
	errno = ENOTTY;
	return 0;
    }
    return 1;
}
#endif

//
// Fix bcc32's stdio bug
//

#ifdef __BORLANDC__
static int
too_many_files()
{
    FILE *f;
    for (f = _streams; f < _streams + _nfile; f++) {
	if (f->fd < 0) return 0;
    }
    return 1;
}

#undef fopen
FILE *
rb_w32_fopen(const char *path, const char *mode)
{
    FILE *f = (errno = 0, fopen(path, mode));
    if (f == NULL && errno == 0) {
	if (too_many_files())
	    errno = EMFILE;
    }
    return f;
}

FILE *
rb_w32_fdopen(int handle, const char *type)
{
    FILE *f = (errno = 0, _fdopen(handle, (char *)type));
    if (f == NULL && errno == 0) {
	if (handle < 0)
	    errno = EBADF;
	else if (too_many_files())
	    errno = EMFILE;
    }
    return f;
}

FILE *
rb_w32_fsopen(const char *path, const char *mode, int shflags)
{
    FILE *f = (errno = 0, _fsopen(path, mode, shflags));
    if (f == NULL && errno == 0) {
	if (too_many_files())
	    errno = EMFILE;
    }
    return f;
}
#endif

RUBY_EXTERN int __cdecl _CrtDbgReportW() {return 0;}
