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
/*
  The parts licensed under above copyright notice are marked as "Artistic or
  GPL".
  Another parts are licensed under Ruby's License.

  Copyright (C) 1993-2011 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan
 */

#undef __STRICT_ANSI__

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "ruby/io.h"
#include "ruby/util.h"
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
#include <share.h>
#include <shlobj.h>
#include <mbstring.h>
#include <shlwapi.h>
#if _MSC_VER >= 1400
#include <crtdbg.h>
#include <rtcapi.h>
#endif
#ifdef __MINGW32__
#include <mswsock.h>
#endif
#include "ruby/win32.h"
#include "ruby/vm.h"
#include "win32/dir.h"
#include "win32/file.h"
#include "id.h"
#include "internal.h"
#include "encindex.h"
#define isdirsep(x) ((x) == '/' || (x) == '\\')

#if defined _MSC_VER && _MSC_VER <= 1200
# define CharNextExA(cp, p, flags) CharNextExA((WORD)(cp), (p), (flags))
#endif

static int w32_wopen(const WCHAR *file, int oflag, int perm);
static int w32_stati128(const char *path, struct stati128 *st, UINT cp, BOOL lstat);
static char *w32_getenv(const char *name, UINT cp);

#undef getenv
#define DLN_FIND_EXTRA_ARG_DECL ,UINT cp
#define DLN_FIND_EXTRA_ARG ,cp
#define rb_w32_stati128(path, st) w32_stati128(path, st, cp, FALSE)
#define getenv(name) w32_getenv(name, cp)
#undef CharNext
#define CharNext(p) CharNextExA(cp, (p), 0)
#define dln_find_exe_r rb_w32_udln_find_exe_r
#define dln_find_file_r rb_w32_udln_find_file_r
#include "dln.h"
#include "dln_find.c"
#undef MAXPATHLEN
#undef rb_w32_stati128
#undef dln_find_exe_r
#undef dln_find_file_r
#define dln_find_exe_r(fname, path, buf, size) rb_w32_udln_find_exe_r(fname, path, buf, size, cp)
#define dln_find_file_r(fname, path, buf, size) rb_w32_udln_find_file_r(fname, path, buf, size, cp)
#undef CharNext			/* no default cp version */

#ifndef PATH_MAX
# if defined MAX_PATH
#   define PATH_MAX MAX_PATH
# elif defined HAVE_SYS_PARAM_H
#   include <sys/param.h>
#   define PATH_MAX MAXPATHLEN
# endif
#endif
#define ENV_MAX 512

#undef stat
#undef fclose
#undef close
#undef setsockopt
#undef dup2
#undef strdup

#if RUBY_MSVCRT_VERSION >= 140
# define _filbuf _fgetc_nolock
# define _flsbuf _fputc_nolock
#endif
#define enough_to_get(n) (--(n) >= 0)
#define enough_to_put(n) (--(n) >= 0)

#ifdef WIN32_DEBUG
#define Debug(something) something
#else
#define Debug(something) /* nothing */
#endif

#define TO_SOCKET(x)	_get_osfhandle(x)

int rb_w32_reparse_symlink_p(const WCHAR *path);

static int has_redirection(const char *, UINT);
int rb_w32_wait_events(HANDLE *events, int num, DWORD timeout);
static int rb_w32_open_osfhandle(intptr_t osfhandle, int flags);
static int wstati128(const WCHAR *path, struct stati128 *st, BOOL lstat);
VALUE rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc);
int ruby_brace_glob_with_enc(const char *str, int flags, ruby_glob_func *func, VALUE arg, rb_encoding *enc);
static FARPROC get_proc_address(const char *module, const char *func, HANDLE *mh);

#define RUBY_CRITICAL if (0) {} else /* just remark */

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
    {	ERROR_PRIVILEGE_NOT_HELD,	EACCES,		},
    {	ERROR_CANT_RESOLVE_FILENAME,	ELOOP,		},
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

/* License: Ruby's */
int
rb_w32_map_errno(DWORD winerr)
{
    int i;

    if (winerr == 0) {
	return 0;
    }

    for (i = 0; i < (int)(sizeof(errmap) / sizeof(*errmap)); i++) {
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

static OSVERSIONINFO osver;

/* License: Artistic or GPL */
static void
get_version(void)
{
    memset(&osver, 0, sizeof(OSVERSIONINFO));
    osver.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);
    GetVersionEx(&osver);
}

#ifdef _M_IX86
/* License: Artistic or GPL */
DWORD
rb_w32_osid(void)
{
    return osver.dwPlatformId;
}
#endif

/* License: Artistic or GPL */
DWORD
rb_w32_osver(void)
{
    return osver.dwMajorVersion;
}

/* simulate flock by locking a range on the file */

/* License: Artistic or GPL */
#define LK_ERR(f,i) \
    do {								\
	if (f)								\
	    i = 0;							\
	else {								\
	    DWORD err = GetLastError();					\
	    if (err == ERROR_LOCK_VIOLATION || err == ERROR_IO_PENDING)	\
		errno = EWOULDBLOCK;					\
	    else if (err == ERROR_NOT_LOCKED)				\
		i = 0;							\
	    else							\
		errno = map_errno(err);					\
	}								\
    } while (0)
#define LK_LEN      ULONG_MAX

/* License: Artistic or GPL */
static uintptr_t
flock_winnt(uintptr_t self, int argc, uintptr_t* argv)
{
    OVERLAPPED o;
    int i = -1;
    const HANDLE fh = (HANDLE)self;
    const int oper = argc;

    memset(&o, 0, sizeof(o));

    switch (oper) {
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

#undef LK_ERR

/* License: Artistic or GPL */
int
flock(int fd, int oper)
{
    const asynchronous_func_t locker = flock_winnt;

    return rb_w32_asynchronize(locker,
			      (VALUE)_get_osfhandle(fd), oper, NULL,
			      (DWORD)-1);
}

/* License: Ruby's */
static inline WCHAR *
translate_wchar(WCHAR *p, int from, int to)
{
    for (; *p; p++) {
	if (*p == from)
	    *p = to;
    }
    return p;
}

/* License: Ruby's */
static inline char *
translate_char(char *p, int from, int to, UINT cp)
{
    while (*p) {
	if ((unsigned char)*p == from)
	    *p = to;
	p = CharNextExA(cp, p, 0);
    }
    return p;
}

#ifndef CSIDL_LOCAL_APPDATA
#define CSIDL_LOCAL_APPDATA 28
#endif
#ifndef CSIDL_COMMON_APPDATA
#define CSIDL_COMMON_APPDATA 35
#endif
#ifndef CSIDL_WINDOWS
#define CSIDL_WINDOWS	36
#endif
#ifndef CSIDL_SYSTEM
#define CSIDL_SYSTEM	37
#endif
#ifndef CSIDL_PROFILE
#define CSIDL_PROFILE 40
#endif

/* License: Ruby's */
static BOOL
get_special_folder(int n, WCHAR *buf, size_t len)
{
    LPITEMIDLIST pidl;
    LPMALLOC alloc;
    BOOL f = FALSE;
    typedef BOOL (WINAPI *get_path_func)(LPITEMIDLIST, WCHAR*, DWORD, int);
    static get_path_func func = (get_path_func)-1;

    if (func == (get_path_func)-1) {
	func = (get_path_func)
	    get_proc_address("shell32", "SHGetPathFromIDListEx", NULL);
    }
    if (!func && len < MAX_PATH) return FALSE;

    if (SHGetSpecialFolderLocation(NULL, n, &pidl) == 0) {
	if (func) {
	    f = func(pidl, buf, len, 0);
	}
	else {
	    f = SHGetPathFromIDListW(pidl, buf);
	}
	SHGetMalloc(&alloc);
	alloc->lpVtbl->Free(alloc, pidl);
	alloc->lpVtbl->Release(alloc);
    }
    return f;
}

/* License: Ruby's */
static void
regulate_path(WCHAR *path)
{
    WCHAR *p = translate_wchar(path, L'\\', L'/');
    if (p - path == 2 && path[1] == L':') {
	*p++ = L'/';
	*p = L'\0';
    }
}

/* License: Ruby's */
static FARPROC
get_proc_address(const char *module, const char *func, HANDLE *mh)
{
    HANDLE h;
    FARPROC ptr;

    if (mh)
	h = LoadLibrary(module);
    else
	h = GetModuleHandle(module);
    if (!h)
	return NULL;

    ptr = GetProcAddress(h, func);
    if (mh) {
	if (ptr)
	    *mh = h;
	else
	    FreeLibrary(h);
    }
    return ptr;
}

/* License: Ruby's */
VALUE
rb_w32_special_folder(int type)
{
    WCHAR path[PATH_MAX];

    if (!get_special_folder(type, path, numberof(path))) return Qnil;
    regulate_path(path);
    return rb_w32_conv_from_wchar(path, rb_filesystem_encoding());
}

#if defined _MSC_VER && _MSC_VER <= 1200
/* License: Ruby's */
#define GetSystemWindowsDirectoryW GetWindowsDirectoryW
#endif

/* License: Ruby's */
UINT
rb_w32_system_tmpdir(WCHAR *path, UINT len)
{
    static const WCHAR temp[] = L"temp";
    WCHAR *p;

    if (!get_special_folder(CSIDL_LOCAL_APPDATA, path, len)) {
	if (GetSystemWindowsDirectoryW(path, len)) return 0;
    }
    p = translate_wchar(path, L'\\', L'/');
    if (*(p - 1) != L'/') *p++ = L'/';
    if ((UINT)(p - path + numberof(temp)) >= len) return 0;
    memcpy(p, temp, sizeof(temp));
    return (UINT)(p - path + numberof(temp) - 1);
}

/*
  Return user's home directory using environment variables combinations.
  Memory allocated by this function should be manually freed
  afterwards with xfree.

  Try:
  HOME, HOMEDRIVE + HOMEPATH and USERPROFILE environment variables
  Special Folders - Profile and Personal
*/
WCHAR *
rb_w32_home_dir(void)
{
    WCHAR *buffer = NULL;
    size_t buffer_len = MAX_PATH, len = 0;
    enum {
	HOME_NONE, ENV_HOME, ENV_DRIVEPATH, ENV_USERPROFILE
    } home_type = HOME_NONE;

    if ((len = GetEnvironmentVariableW(L"HOME", NULL, 0)) != 0) {
	buffer_len = len;
	home_type = ENV_HOME;
    }
    else if ((len = GetEnvironmentVariableW(L"HOMEDRIVE", NULL, 0)) != 0) {
	buffer_len = len;
	if ((len = GetEnvironmentVariableW(L"HOMEPATH", NULL, 0)) != 0) {
	    buffer_len += len;
	    home_type = ENV_DRIVEPATH;
	}
    }
    else if ((len = GetEnvironmentVariableW(L"USERPROFILE", NULL, 0)) != 0) {
	buffer_len = len;
	home_type = ENV_USERPROFILE;
    }

    /* allocate buffer */
    buffer = ALLOC_N(WCHAR, buffer_len);

    switch (home_type) {
      case ENV_HOME:
	GetEnvironmentVariableW(L"HOME", buffer, buffer_len);
	break;
      case ENV_DRIVEPATH:
	len = GetEnvironmentVariableW(L"HOMEDRIVE", buffer, buffer_len);
	GetEnvironmentVariableW(L"HOMEPATH", buffer + len, buffer_len - len);
	break;
      case ENV_USERPROFILE:
	GetEnvironmentVariableW(L"USERPROFILE", buffer, buffer_len);
	break;
      default:
	if (!get_special_folder(CSIDL_PROFILE, buffer, buffer_len) &&
	    !get_special_folder(CSIDL_PERSONAL, buffer, buffer_len)) {
	    xfree(buffer);
	    return NULL;
	}
	REALLOC_N(buffer, WCHAR, lstrlenW(buffer) + 1);
	break;
    }

    /* sanitize backslashes with forwardslashes */
    regulate_path(buffer);

    return buffer;
}

/* License: Ruby's */
static void
init_env(void)
{
    static const WCHAR TMPDIR[] = L"TMPDIR";
    struct {WCHAR name[6], eq, val[ENV_MAX];} wk;
    DWORD len;
    BOOL f;
#define env wk.val
#define set_env_val(vname) do { \
	typedef char wk_name_offset[(numberof(wk.name) - (numberof(vname) - 1)) * 2 + 1]; \
	WCHAR *const buf = wk.name + sizeof(wk_name_offset) / 2; \
	MEMCPY(buf, vname, WCHAR, numberof(vname) - 1); \
	_wputenv(buf); \
    } while (0)

    wk.eq = L'=';

    if (!GetEnvironmentVariableW(L"HOME", env, numberof(env))) {
	f = FALSE;
	if (GetEnvironmentVariableW(L"HOMEDRIVE", env, numberof(env)))
	    len = lstrlenW(env);
	else
	    len = 0;
	if (GetEnvironmentVariableW(L"HOMEPATH", env + len, numberof(env) - len) || len) {
	    f = TRUE;
	}
	else if (GetEnvironmentVariableW(L"USERPROFILE", env, numberof(env))) {
	    f = TRUE;
	}
	else if (get_special_folder(CSIDL_PROFILE, env, numberof(env))) {
	    f = TRUE;
	}
	else if (get_special_folder(CSIDL_PERSONAL, env, numberof(env))) {
	    f = TRUE;
	}
	if (f) {
	    regulate_path(env);
	    set_env_val(L"HOME");
	}
    }

    if (!GetEnvironmentVariableW(L"USER", env, numberof(env))) {
	if (!GetEnvironmentVariableW(L"USERNAME", env, numberof(env)) &&
	    !GetUserNameW(env, (len = numberof(env), &len))) {
	    NTLoginName = "<Unknown>";
	}
	else {
	    set_env_val(L"USER");
	    NTLoginName = rb_w32_wstr_to_mbstr(CP_UTF8, env, -1, NULL);
	}
    }
    else {
	NTLoginName = rb_w32_wstr_to_mbstr(CP_UTF8, env, -1, NULL);
    }

    if (!GetEnvironmentVariableW(TMPDIR, env, numberof(env)) &&
	!GetEnvironmentVariableW(L"TMP", env, numberof(env)) &&
	!GetEnvironmentVariableW(L"TEMP", env, numberof(env)) &&
	rb_w32_system_tmpdir(env, numberof(env))) {
	set_env_val(TMPDIR);
    }

#undef env
#undef set_env_val
}

static void init_stdhandle(void);

#if RUBY_MSVCRT_VERSION >= 80
/* License: Ruby's */
static void
invalid_parameter(const wchar_t *expr, const wchar_t *func, const wchar_t *file, unsigned int line, uintptr_t dummy)
{
    // nothing to do
}

int ruby_w32_rtc_error;

/* License: Ruby's */
static int __cdecl
rtc_error_handler(int e, const char *src, int line, const char *exe, const char *fmt, ...)
{
    va_list ap;
    VALUE str;

    if (!ruby_w32_rtc_error) return 0;
    str = rb_sprintf("%s:%d: ", src, line);
    va_start(ap, fmt);
    rb_str_vcatf(str, fmt, ap);
    va_end(ap);
    rb_str_cat(str, "\n", 1);
    rb_write_error2(RSTRING_PTR(str), RSTRING_LEN(str));
    return 0;
}
#endif

static CRITICAL_SECTION select_mutex;

static CRITICAL_SECTION socklist_mutex;
static st_table *socklist = NULL;

static CRITICAL_SECTION conlist_mutex;
static st_table *conlist = NULL;
#define conlist_disabled ((st_table *)-1)

static char *uenvarea;

/* License: Ruby's */
struct constat {
    struct {
	int state, seq[16], reverse;
	WORD attr;
	COORD saved;
    } vt100;
};
enum {constat_init = -2, constat_esc = -1, constat_seq = 0};

/* License: Ruby's */
static int
free_conlist(st_data_t key, st_data_t val, st_data_t arg)
{
    xfree((struct constat *)val);
    return ST_DELETE;
}

/* License: Ruby's */
static void
constat_delete(HANDLE h)
{
    EnterCriticalSection(&conlist_mutex);
    if (conlist && conlist != conlist_disabled) {
	st_data_t key = (st_data_t)h, val;
	st_delete(conlist, &key, &val);
	xfree((struct constat *)val);
    }
    LeaveCriticalSection(&conlist_mutex);
}

/* License: Ruby's */
static void
exit_handler(void)
{
    WSACleanup();
    DeleteCriticalSection(&select_mutex);
    DeleteCriticalSection(&socklist_mutex);
    DeleteCriticalSection(&conlist_mutex);
    if (uenvarea) {
	free(uenvarea);
	uenvarea = NULL;
    }
}

/* License: Ruby's */
static void
vm_exit_handler(ruby_vm_t *vm)
{
    EnterCriticalSection(&socklist_mutex);
    if (socklist) {
	st_free_table(socklist);
	socklist = NULL;
    }
    LeaveCriticalSection(&socklist_mutex);

    EnterCriticalSection(&conlist_mutex);
    if (conlist && conlist != conlist_disabled) {
	st_foreach(conlist, free_conlist, 0);
	st_free_table(conlist);
	conlist = NULL;
    }
    LeaveCriticalSection(&conlist_mutex);
}

/* License: Ruby's */
static void
install_vm_exit_handler(void)
{
    static bool installed = 0;

    if (!installed) {
	ruby_vm_at_exit(vm_exit_handler);
	installed = 1;
    }
}

/* License: Artistic or GPL */
static void
StartSockets(void)
{
    WORD version;
    WSADATA retdata;

    //
    // initialize the winsock interface and insure that it's
    // cleaned up at exit.
    //
    version = MAKEWORD(2, 0);
    if (WSAStartup(version, &retdata))
	rb_fatal("Unable to locate winsock library!");
    if (LOBYTE(retdata.wVersion) != 2)
	rb_fatal("could not find version 2 of winsock dll");

    InitializeCriticalSection(&select_mutex);
    InitializeCriticalSection(&socklist_mutex);
    InitializeCriticalSection(&conlist_mutex);

    atexit(exit_handler);
}

#define MAKE_SOCKDATA(af, fl)	((int)((((int)af)<<4)|((fl)&0xFFFF)))
#define GET_FAMILY(v)		((int)(((v)>>4)&0xFFFF))
#define GET_FLAGS(v)		((int)((v)&0xFFFF))

/* License: Ruby's */
static inline int
socklist_insert(SOCKET sock, int flag)
{
    int ret;

    EnterCriticalSection(&socklist_mutex);
    if (!socklist) {
	socklist = st_init_numtable();
	install_vm_exit_handler();
    }
    ret = st_insert(socklist, (st_data_t)sock, (st_data_t)flag);
    LeaveCriticalSection(&socklist_mutex);

    return ret;
}

/* License: Ruby's */
static inline int
socklist_lookup(SOCKET sock, int *flagp)
{
    st_data_t data;
    int ret;

    EnterCriticalSection(&socklist_mutex);
    if (socklist) {
	ret = st_lookup(socklist, (st_data_t)sock, (st_data_t *)&data);
	if (ret && flagp)
	    *flagp = (int)data;
    } else {
	ret = 0;
    }
    LeaveCriticalSection(&socklist_mutex);

    return ret;
}

/* License: Ruby's */
static inline int
socklist_delete(SOCKET *sockp, int *flagp)
{
    st_data_t key;
    st_data_t data;
    int ret;

    EnterCriticalSection(&socklist_mutex);
    if (socklist) {
	key = (st_data_t)*sockp;
	if (flagp)
	    data = (st_data_t)*flagp;
	ret = st_delete(socklist, &key, &data);
	if (ret) {
	    *sockp = (SOCKET)key;
	    if (flagp)
		*flagp = (int)data;
	}
    } else {
	ret = 0;
    }
    LeaveCriticalSection(&socklist_mutex);

    return ret;
}

static int w32_cmdvector(const WCHAR *, char ***, UINT, rb_encoding *);
//
// Initialization stuff
//
/* License: Ruby's */
void
rb_w32_sysinit(int *argc, char ***argv)
{
#if RUBY_MSVCRT_VERSION >= 80
    static void set_pioinfo_extra(void);

    _CrtSetReportMode(_CRT_ASSERT, 0);
    _set_invalid_parameter_handler(invalid_parameter);
    _RTC_SetErrorFunc(rtc_error_handler);
    set_pioinfo_extra();
#endif
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);

    get_version();

    //
    // subvert cmd.exe's feeble attempt at command line parsing
    //
    *argc = w32_cmdvector(GetCommandLineW(), argv, CP_UTF8, &OnigEncodingUTF_8);

    //
    // Now set up the correct time stuff
    //

    tzset();

    init_env();

    init_stdhandle();

    // Initialize Winsock
    StartSockets();
}

char *
getlogin(void)
{
    return (char *)NTLoginName;
}

#define MAXCHILDNUM 256	/* max num of child processes */

/* License: Ruby's */
static struct ChildRecord {
    HANDLE hProcess;	/* process handle */
    rb_pid_t pid;	/* process id */
} ChildRecord[MAXCHILDNUM];

/* License: Ruby's */
#define FOREACH_CHILD(v) do { \
    struct ChildRecord* v; \
    for (v = ChildRecord; v < ChildRecord + sizeof(ChildRecord) / sizeof(ChildRecord[0]); ++v)
#define END_FOREACH_CHILD } while (0)

/* License: Ruby's */
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

/* License: Ruby's */
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

/* License: Ruby's */
static void
CloseChildHandle(struct ChildRecord *child)
{
    HANDLE h = child->hProcess;
    child->hProcess = NULL;
    child->pid = 0;
    CloseHandle(h);
}

/* License: Ruby's */
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
#define InternalCmdsMax 8
static const char szInternalCmds[][InternalCmdsMax+2] = {
    "\2" "assoc",
    "\3" "break",
    "\3" "call",
    "\3" "cd",
    "\1" "chcp",
    "\3" "chdir",
    "\3" "cls",
    "\2" "color",
    "\3" "copy",
    "\1" "ctty",
    "\3" "date",
    "\3" "del",
    "\3" "dir",
    "\3" "echo",
    "\2" "endlocal",
    "\3" "erase",
    "\3" "exit",
    "\3" "for",
    "\2" "ftype",
    "\3" "goto",
    "\3" "if",
    "\1" "lfnfor",
    "\1" "lh",
    "\1" "lock",
    "\3" "md",
    "\3" "mkdir",
    "\2" "move",
    "\3" "path",
    "\3" "pause",
    "\2" "popd",
    "\3" "prompt",
    "\2" "pushd",
    "\3" "rd",
    "\3" "rem",
    "\3" "ren",
    "\3" "rename",
    "\3" "rmdir",
    "\3" "set",
    "\2" "setlocal",
    "\3" "shift",
    "\2" "start",
    "\3" "time",
    "\2" "title",
    "\1" "truename",
    "\3" "type",
    "\1" "unlock",
    "\3" "ver",
    "\3" "verify",
    "\3" "vol",
};

/* License: Ruby's */
static int
internal_match(const void *key, const void *elem)
{
    return strncmp(key, ((const char *)elem) + 1, InternalCmdsMax);
}

/* License: Ruby's */
static int
is_command_com(const char *interp)
{
    int i = strlen(interp) - 11;

    if ((i == 0 || (i > 0 && isdirsep(interp[i-1]))) &&
	strcasecmp(interp+i, "command.com") == 0) {
	return 1;
    }
    return 0;
}

static int internal_cmd_match(const char *cmdname, int nt);

/* License: Ruby's */
static int
is_internal_cmd(const char *cmd, int nt)
{
    char cmdname[9], *b = cmdname, c;

    do {
	if (!(c = *cmd++)) return 0;
    } while (isspace(c));
    if (c == '@')
	return 1;
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
    return internal_cmd_match(cmdname, nt);
}

/* License: Ruby's */
static int
internal_cmd_match(const char *cmdname, int nt)
{
    char *nm;

    nm = bsearch(cmdname, szInternalCmds,
		 sizeof(szInternalCmds) / sizeof(*szInternalCmds),
		 sizeof(*szInternalCmds),
		 internal_match);
    if (!nm || !(nm[0] & (nt ? 2 : 1)))
	return 0;
    return 1;
}

/* License: Ruby's */
SOCKET
rb_w32_get_osfhandle(int fh)
{
    return _get_osfhandle(fh);
}

/* License: Ruby's */
static int
join_argv(char *cmd, char *const *argv, BOOL escape, UINT cp, int backslash)
{
    const char *p, *s;
    char *q, *const *t;
    int len, n, bs, quote;

    for (t = argv, q = cmd, len = 0; (p = *t) != 0; t++) {
	quote = 0;
	s = p;
	if (!*p || strpbrk(p, " \t\"'")) {
	    quote = 1;
	    len++;
	    if (q) *q++ = '"';
	}
	for (bs = 0; *p; ++p) {
	    switch (*p) {
	      case '\\':
		++bs;
		break;
	      case '"':
		len += n = p - s;
		if (q) {
		    memcpy(q, s, n);
		    q += n;
		}
		s = p;
		len += ++bs;
		if (q) {
		    memset(q, '\\', bs);
		    q += bs;
		}
		bs = 0;
		break;
	      case '<': case '>': case '|': case '^':
		if (escape && !quote) {
		    len += (n = p - s) + 1;
		    if (q) {
			memcpy(q, s, n);
			q += n;
			*q++ = '^';
		    }
		    s = p;
		    break;
		}
	      default:
		bs = 0;
		p = CharNextExA(cp, p, 0) - 1;
		break;
	    }
	}
	len += (n = p - s) + 1;
	if (quote) len++;
	if (q) {
	    memcpy(q, s, n);
	    if (backslash > 0) {
		--backslash;
		q[n] = 0;
		translate_char(q, '/', '\\', cp);
	    }
	    q += n;
	    if (quote) *q++ = '"';
	    *q++ = ' ';
	}
    }
    if (q > cmd) --len;
    if (q) {
	if (q > cmd) --q;
	*q = '\0';
    }
    return len;
}

/* License: Ruby's */
#define STRNDUPV(ptr, v, src, len)					\
    (((char *)memcpy(((ptr) = ALLOCV((v), (len) + 1)), (src), (len)))[len] = 0)

/* License: Ruby's */
static int
check_spawn_mode(int mode)
{
    switch (mode) {
      case P_NOWAIT:
      case P_OVERLAY:
	return 0;
      default:
	errno = EINVAL;
	return -1;
    }
}

/* License: Ruby's */
static rb_pid_t
child_result(struct ChildRecord *child, int mode)
{
    DWORD exitcode;

    if (!child) {
	return -1;
    }

    if (mode == P_OVERLAY) {
	WaitForSingleObject(child->hProcess, INFINITE);
	GetExitCodeProcess(child->hProcess, &exitcode);
	CloseChildHandle(child);
	_exit(exitcode);
    }
    return child->pid;
}

/* License: Ruby's */
static int
CreateChild(struct ChildRecord *child, const WCHAR *cmd, const WCHAR *prog, HANDLE hInput, HANDLE hOutput, HANDLE hError, DWORD dwCreationFlags)
{
    BOOL fRet;
    STARTUPINFOW aStartupInfo;
    PROCESS_INFORMATION aProcessInformation;
    SECURITY_ATTRIBUTES sa;

    if (!cmd && !prog) {
	errno = EFAULT;
        return FALSE;
    }

    if (!child) {
        errno = EAGAIN;
        return FALSE;
    }

    sa.nLength              = sizeof(SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle       = TRUE;

    memset(&aStartupInfo, 0, sizeof(aStartupInfo));
    memset(&aProcessInformation, 0, sizeof(aProcessInformation));
    aStartupInfo.cb = sizeof(aStartupInfo);
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

    dwCreationFlags |= NORMAL_PRIORITY_CLASS;

    if (lstrlenW(cmd) > 32767) {
	child->pid = 0;		/* release the slot */
	errno = E2BIG;
        return FALSE;
    }

    RUBY_CRITICAL {
        fRet = CreateProcessW(prog, (WCHAR *)cmd, &sa, &sa,
                              sa.bInheritHandle, dwCreationFlags, NULL, NULL,
			      &aStartupInfo, &aProcessInformation);
	errno = map_errno(GetLastError());
    }

    if (!fRet) {
	child->pid = 0;		/* release the slot */
        return FALSE;
    }

    CloseHandle(aProcessInformation.hThread);

    child->hProcess = aProcessInformation.hProcess;
    child->pid = (rb_pid_t)aProcessInformation.dwProcessId;

    return TRUE;
}

/* License: Ruby's */
static int
is_batch(const char *cmd)
{
    int len = strlen(cmd);
    if (len <= 4) return 0;
    cmd += len - 4;
    if (*cmd++ != '.') return 0;
    if (strcasecmp(cmd, "bat") == 0) return 1;
    if (strcasecmp(cmd, "cmd") == 0) return 1;
    return 0;
}

#define filecp rb_w32_filecp
#define mbstr_to_wstr rb_w32_mbstr_to_wstr
#define wstr_to_mbstr rb_w32_wstr_to_mbstr
#define acp_to_wstr(str, plen) mbstr_to_wstr(CP_ACP, str, -1, plen)
#define wstr_to_acp(str, plen) wstr_to_mbstr(CP_ACP, str, -1, plen)
#define filecp_to_wstr(str, plen) mbstr_to_wstr(filecp(), str, -1, plen)
#define wstr_to_filecp(str, plen) wstr_to_mbstr(filecp(), str, -1, plen)
#define utf8_to_wstr(str, plen) mbstr_to_wstr(CP_UTF8, str, -1, plen)
#define wstr_to_utf8(str, plen) wstr_to_mbstr(CP_UTF8, str, -1, plen)

/* License: Ruby's */
MJIT_FUNC_EXPORTED HANDLE
rb_w32_start_process(const char *abspath, char *const *argv, int out_fd)
{
    /* NOTE: This function is used by MJIT worker, so it can be used parallelly with
       Ruby's main thread. So functions touching things shared with main thread can't
       be used, like `ALLOCV` that may trigger GC or `FindFreeChildSlot` that finds
       a slot from shared memory without atomic locks. */
    struct ChildRecord child;
    char *cmd;
    size_t len;
    WCHAR *wcmd = NULL, *wprog = NULL;
    HANDLE outHandle = NULL;

    if (out_fd) {
        outHandle = (HANDLE)rb_w32_get_osfhandle(out_fd);
    }

    len = join_argv(NULL, argv, FALSE, filecp(), 1);
    cmd = alloca(sizeof(char) * len);
    join_argv(cmd, argv, FALSE, filecp(), 1);

    if (!(wcmd = mbstr_to_wstr(filecp(), cmd, -1, NULL))) {
        errno = E2BIG;
        return NULL;
    }
    if (!(wprog = mbstr_to_wstr(filecp(), abspath, -1, NULL))) {
        errno = E2BIG;
        return NULL;
    }

    if (!CreateChild(&child, wcmd, wprog, NULL, outHandle, outHandle, 0)) {
        return NULL;
    }

    free(wcmd);
    free(wprog);
    return child.hProcess;
}

/* License: Artistic or GPL */
static rb_pid_t
w32_spawn(int mode, const char *cmd, const char *prog, UINT cp)
{
    char fbuf[PATH_MAX];
    char *p = NULL;
    const char *shell = NULL;
    WCHAR *wcmd = NULL, *wshell = NULL;
    int e = 0;
    rb_pid_t ret = -1;
    VALUE v = 0;
    VALUE v2 = 0;
    int sep = 0;
    char *cmd_sep = NULL;

    if (check_spawn_mode(mode)) return -1;

    if (prog) {
	if (!(p = dln_find_exe_r(prog, NULL, fbuf, sizeof(fbuf)))) {
	    shell = prog;
	}
	else {
	    shell = p;
	    translate_char(p, '/', '\\', cp);
	}
    }
    else {
	int redir = -1;
	int nt;
	while (ISSPACE(*cmd)) cmd++;
	if ((shell = getenv("RUBYSHELL")) && (redir = has_redirection(cmd, cp))) {
	    size_t shell_len = strlen(shell);
	    char *tmp = ALLOCV(v, shell_len + strlen(cmd) + sizeof(" -c ") + 2);
	    memcpy(tmp, shell, shell_len + 1);
	    translate_char(tmp, '/', '\\', cp);
	    sprintf(tmp + shell_len, " -c \"%s\"", cmd);
	    cmd = tmp;
	}
	else if ((shell = getenv("COMSPEC")) &&
		 (nt = !is_command_com(shell),
		  (redir < 0 ? has_redirection(cmd, cp) : redir) ||
		  is_internal_cmd(cmd, nt))) {
	    char *tmp = ALLOCV(v, strlen(shell) + strlen(cmd) + sizeof(" /c ") + (nt ? 2 : 0));
	    sprintf(tmp, nt ? "%s /c \"%s\"" : "%s /c %s", shell, cmd);
	    cmd = tmp;
	}
	else {
	    int len = 0, quote = (*cmd == '"') ? '"' : (*cmd == '\'') ? '\'' : 0;
	    int slash = 0;
	    for (prog = cmd + !!quote;; prog = CharNextExA(cp, prog, 0)) {
		if (*prog == '/') slash = 1;
		if (!*prog) {
		    len = prog - cmd;
		    if (slash) {
			STRNDUPV(p, v2, cmd, len);
			cmd = p;
		    }
		    shell = cmd;
		    break;
		}
		if ((unsigned char)*prog == quote) {
		    len = prog++ - cmd - 1;
		    STRNDUPV(p, v2, cmd + 1, len);
		    shell = p;
		    break;
		}
		if (quote) continue;
		if (ISSPACE(*prog) || strchr("<>|*?\"", *prog)) {
		    len = prog - cmd;
		    STRNDUPV(p, v2, cmd, len + (slash ? strlen(prog) : 0));
		    if (slash) {
			cmd = p;
			sep = *(cmd_sep = &p[len]);
			*cmd_sep = '\0';
		    }
		    shell = p;
		    break;
		}
	    }
	    shell = dln_find_exe_r(shell, NULL, fbuf, sizeof(fbuf));
	    if (p && slash) translate_char(p, '/', '\\', cp);
	    if (!shell) {
		shell = p ? p : cmd;
	    }
	    else {
		len = strlen(shell);
		if (strchr(shell, ' ')) quote = -1;
		if (shell == fbuf) {
		    p = fbuf;
		}
		else if (shell != p && strchr(shell, '/')) {
		    STRNDUPV(p, v2, shell, len);
		    shell = p;
		}
		if (p) translate_char(p, '/', '\\', cp);
		if (is_batch(shell)) {
		    int alen = strlen(prog);
		    cmd = p = ALLOCV(v, len + alen + (quote ? 2 : 0) + 1);
		    if (quote) *p++ = '"';
		    memcpy(p, shell, len);
		    p += len;
		    if (quote) *p++ = '"';
		    memcpy(p, prog, alen + 1);
		    shell = 0;
		}
	    }
	}
    }

    if (!e && shell && !(wshell = mbstr_to_wstr(cp, shell, -1, NULL))) e = E2BIG;
    if (cmd_sep) *cmd_sep = sep;
    if (!e && cmd && !(wcmd = mbstr_to_wstr(cp, cmd, -1, NULL))) e = E2BIG;
    if (v2) ALLOCV_END(v2);
    if (v) ALLOCV_END(v);

    if (!e) {
        struct ChildRecord *child = FindFreeChildSlot();
        if (CreateChild(child, wcmd, wshell, NULL, NULL, NULL, 0)) {
            ret = child_result(child, mode);
        }
    }
    free(wshell);
    free(wcmd);
    if (e) errno = e;
    return ret;
}

/* License: Ruby's */
rb_pid_t
rb_w32_spawn(int mode, const char *cmd, const char *prog)
{
    /* assume ACP */
    return w32_spawn(mode, cmd, prog, filecp());
}

/* License: Ruby's */
rb_pid_t
rb_w32_uspawn(int mode, const char *cmd, const char *prog)
{
    return w32_spawn(mode, cmd, prog, CP_UTF8);
}

/* License: Artistic or GPL */
static rb_pid_t
w32_aspawn_flags(int mode, const char *prog, char *const *argv, DWORD flags, UINT cp)
{
    int c_switch = 0;
    size_t len;
    BOOL ntcmd = FALSE, tmpnt;
    const char *shell;
    char *cmd, fbuf[PATH_MAX];
    WCHAR *wcmd = NULL, *wprog = NULL;
    int e = 0;
    rb_pid_t ret = -1;
    VALUE v = 0;

    if (check_spawn_mode(mode)) return -1;

    if (!prog) prog = argv[0];
    if ((shell = getenv("COMSPEC")) &&
	internal_cmd_match(prog, tmpnt = !is_command_com(shell))) {
	ntcmd = tmpnt;
	prog = shell;
	c_switch = 1;
    }
    else if ((cmd = dln_find_exe_r(prog, NULL, fbuf, sizeof(fbuf)))) {
	if (cmd == prog) strlcpy(cmd = fbuf, prog, sizeof(fbuf));
	translate_char(cmd, '/', '\\', cp);
	prog = cmd;
    }
    else if (strchr(prog, '/')) {
	len = strlen(prog);
	if (len < sizeof(fbuf))
	    strlcpy(cmd = fbuf, prog, sizeof(fbuf));
	else
	    STRNDUPV(cmd, v, prog, len);
	translate_char(cmd, '/', '\\', cp);
	prog = cmd;
    }
    if (c_switch || is_batch(prog)) {
	char *progs[2];
	progs[0] = (char *)prog;
	progs[1] = NULL;
	len = join_argv(NULL, progs, ntcmd, cp, 1);
	if (c_switch) len += 3;
	else ++argv;
	if (argv[0]) len += join_argv(NULL, argv, ntcmd, cp, 0);
	cmd = ALLOCV(v, len);
	join_argv(cmd, progs, ntcmd, cp, 1);
	if (c_switch) strlcat(cmd, " /c", len);
	if (argv[0]) join_argv(cmd + strlcat(cmd, " ", len), argv, ntcmd, cp, 0);
	prog = c_switch ? shell : 0;
    }
    else {
	len = join_argv(NULL, argv, FALSE, cp, 1);
	cmd = ALLOCV(v, len);
	join_argv(cmd, argv, FALSE, cp, 1);
    }

    if (!e && cmd && !(wcmd = mbstr_to_wstr(cp, cmd, -1, NULL))) e = E2BIG;
    if (v) ALLOCV_END(v);
    if (!e && prog && !(wprog = mbstr_to_wstr(cp, prog, -1, NULL))) e = E2BIG;

    if (!e) {
        struct ChildRecord *child = FindFreeChildSlot();
        if (CreateChild(child, wcmd, wprog, NULL, NULL, NULL, flags)) {
            ret = child_result(child, mode);
        }
    }
    free(wprog);
    free(wcmd);
    if (e) errno = e;
    return ret;
}

/* License: Ruby's */
rb_pid_t
rb_w32_aspawn_flags(int mode, const char *prog, char *const *argv, DWORD flags)
{
    /* assume ACP */
    return w32_aspawn_flags(mode, prog, argv, flags, filecp());
}

/* License: Ruby's */
rb_pid_t
rb_w32_uaspawn_flags(int mode, const char *prog, char *const *argv, DWORD flags)
{
    return w32_aspawn_flags(mode, prog, argv, flags, CP_UTF8);
}

/* License: Ruby's */
rb_pid_t
rb_w32_aspawn(int mode, const char *prog, char *const *argv)
{
    return rb_w32_aspawn_flags(mode, prog, argv, 0);
}

/* License: Ruby's */
rb_pid_t
rb_w32_uaspawn(int mode, const char *prog, char *const *argv)
{
    return rb_w32_uaspawn_flags(mode, prog, argv, 0);
}

/* License: Artistic or GPL */
typedef struct _NtCmdLineElement {
    struct _NtCmdLineElement *next;
    char *str;
    long len;
    int flags;
} NtCmdLineElement;

//
// Possible values for flags
//

#define NTGLOB   0x1	// element contains a wildcard
#define NTMALLOC 0x2	// string in element was malloc'ed
#define NTSTRING 0x4	// element contains a quoted string

/* License: Ruby's */
static int
insert(const char *path, VALUE vinfo, void *enc)
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

/* License: Artistic or GPL */
static NtCmdLineElement **
cmdglob(NtCmdLineElement *patt, NtCmdLineElement **tail, UINT cp, rb_encoding *enc)
{
    char buffer[PATH_MAX], *buf = buffer;
    NtCmdLineElement **last = tail;
    int status;

    if (patt->len >= PATH_MAX)
	if (!(buf = malloc(patt->len + 1))) return 0;

    memcpy(buf, patt->str, patt->len);
    buf[patt->len] = '\0';
    translate_char(buf, '\\', '/', cp);
    status = ruby_brace_glob_with_enc(buf, 0, insert, (VALUE)&tail, enc);
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

/* License: Artistic or GPL */
static int
has_redirection(const char *cmd, UINT cp)
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
	  case '&':
	  case '\n':
	    if (!quote)
		return TRUE;
	    ptr++;
	    break;

	  case '%':
	    if (*++ptr != '_' && !ISALPHA(*ptr)) break;
	    while (*++ptr == '_' || ISALNUM(*ptr));
	    if (*ptr++ == '%') return TRUE;
	    break;

	  case '\\':
	    ptr++;
	  default:
	    ptr = CharNextExA(cp, ptr, 0);
	    break;
	}
    }
    return FALSE;
}

/* License: Ruby's */
static inline WCHAR *
skipspace(WCHAR *ptr)
{
    while (ISSPACE(*ptr))
	ptr++;
    return ptr;
}

/* License: Artistic or GPL */
static int
w32_cmdvector(const WCHAR *cmd, char ***vec, UINT cp, rb_encoding *enc)
{
    int globbing, len;
    int elements, strsz, done;
    int slashes, escape;
    WCHAR *ptr, *base, *cmdline;
    char *cptr, *buffer;
    char **vptr;
    WCHAR quote;
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

    ptr = cmdline = wcsdup(cmd);

    //
    // Ok, parse the command line, building a list of CmdLineElements.
    // When we've finished, and it's an input command (meaning that it's
    // the processes argv), we'll do globing and then build the argument
    // vector.
    // The outer loop does one iteration for each element seen.
    // The inner loop does one iteration for each character in the element.
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
	      case L'\\':
		if (quote != L'\'') slashes++;
	        break;

	      case L' ':
	      case L'\t':
	      case L'\n':
		//
		// if we're not in a string, then we're finished with this
		// element
		//

		if (!quote) {
		    *ptr = 0;
		    done = 1;
		}
		break;

	      case L'*':
	      case L'?':
	      case L'[':
	      case L'{':
		//
		// record the fact that this element has a wildcard character
		// N.B. Don't glob if inside a single quoted string
		//

		if (quote != L'\'')
		    globbing++;
		slashes = 0;
		break;

	      case L'\'':
	      case L'\"':
		//
		// if we're already in a string, see if this is the
		// terminating close-quote. If it is, we're finished with
		// the string, but not necessarily with the element.
		// If we're not already in a string, start one.
		//

		if (!(slashes & 1)) {
		    if (!quote)
			quote = *ptr;
		    else if (quote == *ptr) {
			if (quote == L'"' && quote == ptr[1])
			    ptr++;
			quote = L'\0';
		    }
		}
		escape++;
		slashes = 0;
		break;

	      default:
		ptr = CharNextW(ptr);
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
	    WCHAR *p = base, c;
	    slashes = quote = 0;
	    while (p < base + len) {
		switch (c = *p) {
		  case L'\\':
		    p++;
		    if (quote != L'\'') slashes++;
		    break;

		  case L'\'':
		  case L'"':
		    if (!(slashes & 1) && quote && quote != c) {
			p++;
			slashes = 0;
			break;
		    }
		    memcpy(p - ((slashes + 1) >> 1), p + (~slashes & 1),
			   sizeof(WCHAR) * (base + len - p));
		    len -= ((slashes + 1) >> 1) + (~slashes & 1);
		    p -= (slashes + 1) >> 1;
		    if (!(slashes & 1)) {
			if (quote) {
			    if (quote == L'"' && quote == *p)
				p++;
			    quote = L'\0';
			}
			else
			    quote = c;
		    }
		    else
			p++;
		    slashes = 0;
		    break;

		  default:
		    p = CharNextW(p);
		    slashes = 0;
		    break;
		}
	    }
	}

	curr = (NtCmdLineElement *)calloc(sizeof(NtCmdLineElement), 1);
	if (!curr) goto do_nothing;
	curr->str = rb_w32_wstr_to_mbstr(cp, base, len, &curr->len);
	curr->flags |= NTMALLOC;

	if (globbing && (tail = cmdglob(curr, cmdtail, cp, enc))) {
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
	while ((curr = cmdhead) != 0) {
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
    // and cptr point to the area we'll consider the string table.
    //
    //   buffer (*vec)
    //   |
    //   V       ^---------------------V
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |   |       | ....  | NULL  |   | ..... |\0 |   | ..... |\0 |...
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |-  elements+1             -| ^ 1st element   ^ 2nd element

    vptr = (char **) buffer;

    cptr = buffer + (elements+1) * sizeof(char *);

    while ((curr = cmdhead) != 0) {
	memcpy(cptr, curr->str, curr->len);
	cptr[curr->len] = '\0';
	*vptr++ = cptr;
	cptr += curr->len + 1;
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

typedef DWORD (WINAPI *get_final_path_func)(HANDLE, WCHAR*, DWORD, DWORD);
static get_final_path_func get_final_path;

static DWORD WINAPI
get_final_path_fail(HANDLE f, WCHAR *buf, DWORD len, DWORD flag)
{
    return 0;
}

static DWORD WINAPI
get_final_path_unknown(HANDLE f, WCHAR *buf, DWORD len, DWORD flag)
{
    get_final_path_func func = (get_final_path_func)
	get_proc_address("kernel32", "GetFinalPathNameByHandleW", NULL);
    if (!func) func = get_final_path_fail;
    get_final_path = func;
    return func(f, buf, len, flag);
}

static get_final_path_func get_final_path = get_final_path_unknown;

/* License: Ruby's */
/* TODO: better name */
static HANDLE
open_special(const WCHAR *path, DWORD access, DWORD flags)
{
    const DWORD share_mode =
	FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    return CreateFileW(path, access, share_mode, NULL, OPEN_EXISTING,
		       FILE_FLAG_BACKUP_SEMANTICS|flags, NULL);
}

//
// The idea here is to read all the directory names into a string table
// (separated by nulls) and when one of the other dir functions is called
// return the pointer to the current file name.
//

/* License: Ruby's */
#define GetBit(bits, i) ((bits)[(i) / CHAR_BIT] &  (1 << (i) % CHAR_BIT))
#define SetBit(bits, i) ((bits)[(i) / CHAR_BIT] |= (1 << (i) % CHAR_BIT))

#define BitOfIsDir(n) ((n) * 2)
#define BitOfIsRep(n) ((n) * 2 + 1)
#define DIRENT_PER_CHAR (CHAR_BIT / 2)

/* License: Artistic or GPL */
static HANDLE
open_dir_handle(const WCHAR *filename, WIN32_FIND_DATAW *fd)
{
    HANDLE fh;
    WCHAR fullname[PATH_MAX + rb_strlen_lit("\\*")];
    WCHAR *p;
    int len = 0;

    //
    // Create the search pattern
    //

    fh = open_special(filename, 0, 0);
    if (fh != INVALID_HANDLE_VALUE) {
	len = get_final_path(fh, fullname, PATH_MAX, 0);
	CloseHandle(fh);
    }
    if (!len) {
	len = lstrlenW(filename);
	if (len >= PATH_MAX) {
	    errno = ENAMETOOLONG;
	    return INVALID_HANDLE_VALUE;
	}
	MEMCPY(fullname, filename, WCHAR, len);
    }
    p = &fullname[len-1];
    if (!(isdirsep(*p) || *p == L':')) *++p = L'\\';
    *++p = L'*';
    *++p = L'\0';

    //
    // do the FindFirstFile call
    //
    fh = FindFirstFileW(fullname, fd);
    if (fh == INVALID_HANDLE_VALUE) {
	errno = map_errno(GetLastError());
    }
    return fh;
}

/* License: Artistic or GPL */
static DIR *
w32_wopendir(const WCHAR *wpath)
{
    struct stati128 sbuf;
    WIN32_FIND_DATAW fd;
    HANDLE fh;
    DIR *p;
    long pathlen;
    long len;
    long altlen;
    long idx;
    WCHAR *tmpW;
    char *tmp;

    //
    // check to see if we've got a directory
    //
    if (wstati128(wpath, &sbuf, FALSE) < 0) {
	return NULL;
    }
    if (!(sbuf.st_mode & S_IFDIR) &&
	(!ISALPHA(wpath[0]) || wpath[1] != L':' || wpath[2] != L'\0' ||
	 ((1 << ((wpath[0] & 0x5f) - 'A')) & GetLogicalDrives()) == 0)) {
	errno = ENOTDIR;
	return NULL;
    }
    fh = open_dir_handle(wpath, &fd);
    if (fh == INVALID_HANDLE_VALUE) {
	return NULL;
    }

    //
    // Get us a DIR structure
    //
    p = calloc(sizeof(DIR), 1);
    if (p == NULL)
	return NULL;

    pathlen = lstrlenW(wpath);
    idx = 0;

    //
    // loop finding all the files that match the wildcard
    // (which should be all of them in this directory!).
    // the variable idx should point one past the null terminator
    // of the previous string found.
    //
    do {
	len = lstrlenW(fd.cFileName) + 1;
	altlen = lstrlenW(fd.cAlternateFileName) + 1;

	//
	// bump the string table size by enough for the
	// new name and it's null terminator
	//
	tmpW = realloc(p->start, (idx + len + altlen) * sizeof(WCHAR));
	if (!tmpW) {
	  error:
	    rb_w32_closedir(p);
	    FindClose(fh);
	    errno = ENOMEM;
	    return NULL;
	}

	p->start = tmpW;
	memcpy(&p->start[idx], fd.cFileName, len * sizeof(WCHAR));
	memcpy(&p->start[idx + len], fd.cAlternateFileName, altlen * sizeof(WCHAR));

	if (p->nfiles % DIRENT_PER_CHAR == 0) {
	    tmp = realloc(p->bits, p->nfiles / DIRENT_PER_CHAR + 1);
	    if (!tmp)
		goto error;
	    p->bits = tmp;
	    p->bits[p->nfiles / DIRENT_PER_CHAR] = 0;
	}
	if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
	    SetBit(p->bits, BitOfIsDir(p->nfiles));
	if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
	    WCHAR *tmppath = malloc((pathlen + len + 1) * sizeof(WCHAR));
	    memcpy(tmppath, wpath, pathlen * sizeof(WCHAR));
	    tmppath[pathlen] = L'\\';
	    memcpy(tmppath + pathlen + 1, fd.cFileName, len * sizeof(WCHAR));
	    if (rb_w32_reparse_symlink_p(tmppath))
		SetBit(p->bits, BitOfIsRep(p->nfiles));
	    free(tmppath);
	}

	p->nfiles++;
	idx += len + altlen;
    } while (FindNextFileW(fh, &fd));
    FindClose(fh);
    p->size = idx;
    p->curr = p->start;
    return p;
}

/* License: Ruby's */
UINT
filecp(void)
{
    UINT cp = AreFileApisANSI() ? CP_ACP : CP_OEMCP;
    return cp;
}

/* License: Ruby's */
char *
rb_w32_wstr_to_mbstr(UINT cp, const WCHAR *wstr, int clen, long *plen)
{
    char *ptr;
    int len = WideCharToMultiByte(cp, 0, wstr, clen, NULL, 0, NULL, NULL);
    if (!(ptr = malloc(len))) return 0;
    WideCharToMultiByte(cp, 0, wstr, clen, ptr, len, NULL, NULL);
    if (plen) {
	/* exclude NUL only if NUL-terminated string */
	if (clen == -1) --len;
	*plen = len;
    }
    return ptr;
}

/* License: Ruby's */
WCHAR *
rb_w32_mbstr_to_wstr(UINT cp, const char *str, int clen, long *plen)
{
    /* This is used by MJIT worker. Do not trigger GC or call Ruby method here. */
    WCHAR *ptr;
    int len = MultiByteToWideChar(cp, 0, str, clen, NULL, 0);
    if (!(ptr = malloc(sizeof(WCHAR) * len))) return 0;
    MultiByteToWideChar(cp, 0, str, clen, ptr, len);
    if (plen) {
	/* exclude NUL only if NUL-terminated string */
	if (clen == -1) --len;
	*plen = len;
    }
    return ptr;
}

/* License: Ruby's */
DIR *
rb_w32_opendir(const char *filename)
{
    DIR *ret;
    WCHAR *wpath = filecp_to_wstr(filename, NULL);
    if (!wpath)
	return NULL;
    ret = w32_wopendir(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
DIR *
rb_w32_uopendir(const char *filename)
{
    DIR *ret;
    WCHAR *wpath = utf8_to_wstr(filename, NULL);
    if (!wpath)
	return NULL;
    ret = w32_wopendir(wpath);
    free(wpath);
    return ret;
}

//
// Move to next entry
//

/* License: Artistic or GPL */
static void
move_to_next_entry(DIR *dirp)
{
    if (dirp->curr) {
	dirp->loc++;
	dirp->curr += lstrlenW(dirp->curr) + 1;
	dirp->curr += lstrlenW(dirp->curr) + 1;
	if (dirp->curr >= (dirp->start + dirp->size)) {
	    dirp->curr = NULL;
	}
    }
}

//
// Readdir just returns the current string pointer and bumps the
// string pointer to the next entry.
//
/* License: Ruby's */
static BOOL
win32_direct_conv(const WCHAR *file, const WCHAR *alt, struct direct *entry, const void *enc)
{
    UINT cp = *((UINT *)enc);
    if (!(entry->d_name = wstr_to_mbstr(cp, file, -1, &entry->d_namlen)))
	return FALSE;
    if (alt && *alt) {
	long altlen = 0;
	entry->d_altname = wstr_to_mbstr(cp, alt, -1, &altlen);
	entry->d_altlen = altlen;
    }
    return TRUE;
}

/* License: Ruby's */
VALUE
rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc)
{
    VALUE src;
    long len = lstrlenW(wstr);
    int encindex = rb_enc_to_index(enc);

    if (encindex == ENCINDEX_UTF_16LE) {
	return rb_enc_str_new((char *)wstr, len * sizeof(WCHAR), enc);
    }
    else {
#if SIZEOF_INT < SIZEOF_LONG
# error long should equal to int on Windows
#endif
	int clen = rb_long2int(len);
	len = WideCharToMultiByte(CP_UTF8, 0, wstr, clen, NULL, 0, NULL, NULL);
	src = rb_enc_str_new(0, len, rb_enc_from_index(ENCINDEX_UTF_8));
	WideCharToMultiByte(CP_UTF8, 0, wstr, clen, RSTRING_PTR(src), len, NULL, NULL);
    }
    switch (encindex) {
      case ENCINDEX_ASCII:
      case ENCINDEX_US_ASCII:
	/* assume UTF-8 */
      case ENCINDEX_UTF_8:
	/* do nothing */
	return src;
    }
    return rb_str_conv_enc_opts(src, NULL, enc, ECONV_UNDEF_REPLACE, Qnil);
}

/* License: Ruby's */
char *
rb_w32_conv_from_wstr(const WCHAR *wstr, long *lenp, rb_encoding *enc)
{
    VALUE str = rb_w32_conv_from_wchar(wstr, enc);
    long len;
    char *ptr;

    if (NIL_P(str)) return wstr_to_filecp(wstr, lenp);
    *lenp = len = RSTRING_LEN(str);
    memcpy(ptr = malloc(len + 1), RSTRING_PTR(str), len);
    ptr[len] = '\0';
    return ptr;
}

/* License: Ruby's */
static BOOL
ruby_direct_conv(const WCHAR *file, const WCHAR *alt, struct direct *entry, const void *enc)
{
    if (!(entry->d_name = rb_w32_conv_from_wstr(file, &entry->d_namlen, enc)))
	return FALSE;
    if (alt && *alt) {
	long altlen = 0;
	entry->d_altname = rb_w32_conv_from_wstr(alt, &altlen, enc);
	entry->d_altlen = altlen;
    }
    return TRUE;
}

/* License: Artistic or GPL */
static struct direct *
readdir_internal(DIR *dirp, BOOL (*conv)(const WCHAR *, const WCHAR *, struct direct *, const void *), const void *enc)
{
    static int dummy = 0;

    if (dirp->curr) {

	//
	// first set up the structure to return
	//
	if (dirp->dirstr.d_name)
	    free(dirp->dirstr.d_name);
	if (dirp->dirstr.d_altname)
	    free(dirp->dirstr.d_altname);
	dirp->dirstr.d_altname = 0;
	dirp->dirstr.d_altlen = 0;
	conv(dirp->curr, dirp->curr + lstrlenW(dirp->curr) + 1, &dirp->dirstr, enc);

	//
	// Fake inode
	//
	dirp->dirstr.d_ino = dummy++;

	//
	// Attributes
	//
	/* ignore FILE_ATTRIBUTE_DIRECTORY as unreliable for reparse points */
	if (GetBit(dirp->bits, BitOfIsRep(dirp->loc)))
	    dirp->dirstr.d_type = DT_LNK;
	else if (GetBit(dirp->bits, BitOfIsDir(dirp->loc)))
	    dirp->dirstr.d_type = DT_DIR;
	else
	    dirp->dirstr.d_type = DT_REG;

	//
	// Now set up for the next call to readdir
	//

	move_to_next_entry(dirp);

	return &(dirp->dirstr);

    }
    else
	return NULL;
}

/* License: Ruby's */
struct direct  *
rb_w32_readdir(DIR *dirp, rb_encoding *enc)
{
    int idx = rb_enc_to_index(enc);
    if (idx == ENCINDEX_ASCII) {
	const UINT cp = filecp();
	return readdir_internal(dirp, win32_direct_conv, &cp);
    }
    else if (idx == ENCINDEX_UTF_8) {
	const UINT cp = CP_UTF8;
	return readdir_internal(dirp, win32_direct_conv, &cp);
    }
    else
	return readdir_internal(dirp, ruby_direct_conv, enc);
}

//
// Telldir returns the current string pointer position
//

/* License: Artistic or GPL */
long
rb_w32_telldir(DIR *dirp)
{
    return dirp->loc;
}

//
// Seekdir moves the string pointer to a previously saved position
// (Saved by telldir).

/* License: Ruby's */
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

/* License: Artistic or GPL */
void
rb_w32_rewinddir(DIR *dirp)
{
    dirp->curr = dirp->start;
    dirp->loc = 0;
}

//
// This just free's the memory allocated by opendir
//

/* License: Artistic or GPL */
void
rb_w32_closedir(DIR *dirp)
{
    if (dirp) {
	if (dirp->dirstr.d_name)
	    free(dirp->dirstr.d_name);
	if (dirp->dirstr.d_altname)
	    free(dirp->dirstr.d_altname);
	if (dirp->start)
	    free(dirp->start);
	if (dirp->bits)
	    free(dirp->bits);
	free(dirp);
    }
}

#if RUBY_MSVCRT_VERSION >= 140
typedef struct {
    union
    {
        FILE  _public_file;
        char* _ptr;
    };

    char*            _base;
    int              _cnt;
    long             _flags;
    long             _file;
    int              _charbuf;
    int              _bufsiz;
    char*            _tmpfname;
    CRITICAL_SECTION _lock;
} vcruntime_file;
#define FILE_COUNT(stream) ((vcruntime_file*)stream)->_cnt
#define FILE_READPTR(stream) ((vcruntime_file*)stream)->_ptr
#define FILE_FILENO(stream) ((vcruntime_file*)stream)->_file
#else
#define FILE_COUNT(stream) stream->_cnt
#define FILE_READPTR(stream) stream->_ptr
#define FILE_FILENO(stream) stream->_file
#endif

/* License: Ruby's */
#if RUBY_MSVCRT_VERSION >= 140
typedef char lowio_text_mode;
typedef char lowio_pipe_lookahead[3];

typedef struct {
    CRITICAL_SECTION           lock;
    intptr_t                   osfhnd;          // underlying OS file HANDLE
    __int64                    startpos;        // File position that matches buffer start
    unsigned char              osfile;          // Attributes of file (e.g., open in text mode?)
    lowio_text_mode            textmode;
    lowio_pipe_lookahead       _pipe_lookahead;

    uint8_t unicode          : 1; // Was the file opened as unicode?
    uint8_t utf8translations : 1; // Buffer contains translations other than CRLF
    uint8_t dbcsBufferUsed   : 1; // Is the dbcsBuffer in use?
    char    dbcsBuffer;           // Buffer for the lead byte of DBCS when converting from DBCS to Unicode
} ioinfo;
#else
typedef struct	{
    intptr_t osfhnd;	/* underlying OS file HANDLE */
    char osfile;	/* attributes of file (e.g., open in text mode?) */
    char pipech;	/* one char buffer for handles opened on pipes */
    int lockinitflag;
    CRITICAL_SECTION lock;
#if RUBY_MSVCRT_VERSION >= 80
    char textmode;
    char pipech2[2];
#endif
}	ioinfo;
#endif

#if !defined _CRTIMP || defined __MINGW32__
#undef _CRTIMP
#define _CRTIMP __declspec(dllimport)
#endif

#if RUBY_MSVCRT_VERSION >= 140
static ioinfo ** __pioinfo = NULL;
#define IOINFO_L2E 6
#else
EXTERN_C _CRTIMP ioinfo * __pioinfo[];
#define IOINFO_L2E 5
#endif
static inline ioinfo* _pioinfo(int);


#define IOINFO_ARRAY_ELTS	(1 << IOINFO_L2E)
#define _osfhnd(i)  (_pioinfo(i)->osfhnd)
#define _osfile(i)  (_pioinfo(i)->osfile)
#define rb_acrt_lowio_lock_fh(i)   EnterCriticalSection(&_pioinfo(i)->lock)
#define rb_acrt_lowio_unlock_fh(i) LeaveCriticalSection(&_pioinfo(i)->lock)

#if RUBY_MSVCRT_VERSION >= 80
static size_t pioinfo_extra = 0;	/* workaround for VC++8 SP1 */

/* License: Ruby's */
static void
set_pioinfo_extra(void)
{
#if RUBY_MSVCRT_VERSION >= 140
# define FUNCTION_RET 0xc3 /* ret */
# ifdef _DEBUG
#  define UCRTBASE "ucrtbased.dll"
# else
#  define UCRTBASE "ucrtbase.dll"
# endif
    /* get __pioinfo addr with _isatty */
    char *p = (char*)get_proc_address(UCRTBASE, "_isatty", NULL);
    char *pend = p;
    /* _osfile(fh) & FDEV */

# if _WIN64
    int32_t rel;
    char *rip;
    /* add rsp, _ */
#  define FUNCTION_BEFORE_RET_MARK "\x48\x83\xc4"
#  define FUNCTION_SKIP_BYTES 1
#  ifdef _DEBUG
    /* lea rcx,[__pioinfo's addr in RIP-relative 32bit addr] */
#   define PIOINFO_MARK "\x48\x8d\x0d"
#  else
    /* lea rdx,[__pioinfo's addr in RIP-relative 32bit addr] */
#   define PIOINFO_MARK "\x48\x8d\x15"
#  endif

# else /* x86 */
    /* pop ebp */
#  define FUNCTION_BEFORE_RET_MARK "\x5d"
#  define FUNCTION_SKIP_BYTES 0
    /* mov eax,dword ptr [eax*4+100EB430h] */
#  define PIOINFO_MARK "\x8B\x04\x85"
# endif
    if (p) {
        for (pend += 10; pend < p + 300; pend++) {
            // find end of function
            if (memcmp(pend, FUNCTION_BEFORE_RET_MARK, sizeof(FUNCTION_BEFORE_RET_MARK) - 1) == 0 &&
                *(pend + (sizeof(FUNCTION_BEFORE_RET_MARK) - 1) + FUNCTION_SKIP_BYTES) & FUNCTION_RET == FUNCTION_RET) {
                // search backwards from end of function
                for (pend -= (sizeof(PIOINFO_MARK) - 1); pend > p; pend--) {
                    if (memcmp(pend, PIOINFO_MARK, sizeof(PIOINFO_MARK) - 1) == 0) {
                        p = pend;
                        goto found;
                    }
                }
                break;
            }
        }
    }
    fprintf(stderr, "unexpected " UCRTBASE "\n");
    _exit(1);

    found:
    p += sizeof(PIOINFO_MARK) - 1;
#if _WIN64
    rel = *(int32_t*)(p);
    rip = p + sizeof(int32_t);
    __pioinfo = (ioinfo**)(rip + rel);
#else
    __pioinfo = *(ioinfo***)(p);
#endif
#endif
    int fd;

    fd = _open("NUL", O_RDONLY);
    for (pioinfo_extra = 0; pioinfo_extra <= 64; pioinfo_extra += sizeof(void *)) {
	if (_osfhnd(fd) == _get_osfhandle(fd)) {
	    break;
	}
    }
    _close(fd);

    if (pioinfo_extra > 64) {
	/* not found, maybe something wrong... */
	pioinfo_extra = 0;
    }
}
#else
#define pioinfo_extra 0
#endif

static inline ioinfo*
_pioinfo(int fd)
{
    const size_t sizeof_ioinfo = sizeof(ioinfo) + pioinfo_extra;
    return (ioinfo*)((char*)__pioinfo[fd >> IOINFO_L2E] +
		     (fd & (IOINFO_ARRAY_ELTS - 1)) * sizeof_ioinfo);
}

#define _set_osfhnd(fh, osfh) (void)(_osfhnd(fh) = osfh)
#define _set_osflags(fh, flags) (_osfile(fh) = (flags))

#define FOPEN			0x01	/* file handle open */
#define FEOFLAG			0x02	/* end of file has been encountered */
#define FPIPE			0x08	/* file handle refers to a pipe */
#define FNOINHERIT		0x10	/* file handle opened O_NOINHERIT */
#define FAPPEND			0x20	/* file handle opened O_APPEND */
#define FDEV			0x40	/* file handle refers to device */
#define FTEXT			0x80	/* file handle is in text mode */

static int is_socket(SOCKET);
static int is_console(SOCKET);

/* License: Ruby's */
int
rb_w32_io_cancelable_p(int fd)
{
    return is_socket(TO_SOCKET(fd)) || !is_console(TO_SOCKET(fd));
}

/* License: Ruby's */
static int
rb_w32_open_osfhandle(intptr_t osfhandle, int flags)
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
    fh = _open_osfhandle((intptr_t)hF, 0);
    CloseHandle(hF);
    if (fh == -1) {
	errno = EMFILE;		/* too many open files */
	_doserrno = 0L;		/* not an OS error */
    }
    else {

	rb_acrt_lowio_lock_fh(fh);
	/* the file is open. now, set the info in _osfhnd array */
	_set_osfhnd(fh, osfhandle);

	fileflags |= FOPEN;		/* mark as open */

	_set_osflags(fh, fileflags); /* set osfile entry */
	rb_acrt_lowio_unlock_fh(fh);
    }
    return fh;			/* return handle */
}

/* License: Ruby's */
static void
init_stdhandle(void)
{
    int nullfd = -1;
    int keep = 0;
#define open_null(fd)						\
    (((nullfd < 0) ?						\
      (nullfd = open("NUL", O_RDWR)) : 0),		\
     ((nullfd == (fd)) ? (keep = 1) : dup2(nullfd, fd)),	\
     (fd))

    if (fileno(stdin) < 0) {
	FILE_FILENO(stdin) = open_null(0);
    }
    else {
	setmode(fileno(stdin), O_BINARY);
    }
    if (fileno(stdout) < 0) {
	FILE_FILENO(stdout) = open_null(1);
    }
    if (fileno(stderr) < 0) {
	FILE_FILENO(stderr) = open_null(2);
    }
    if (nullfd >= 0 && !keep) close(nullfd);
    setvbuf(stderr, NULL, _IONBF, 0);
}

#undef getsockopt

/* License: Ruby's */
static int
is_socket(SOCKET sock)
{
    if (socklist_lookup(sock, NULL))
	return TRUE;
    else
	return FALSE;
}

/* License: Ruby's */
int
rb_w32_is_socket(int fd)
{
    return is_socket(TO_SOCKET(fd));
}

//
// Since the errors returned by the socket error function
// WSAGetLastError() are not known by the library routine strerror
// we have to roll our own.
//

#undef strerror

/* License: Artistic or GPL */
char *
rb_w32_strerror(int e)
{
    static char buffer[512];
    DWORD source = 0;
    char *p;

    if (e < 0 || e > sys_nerr) {
	if (e < 0)
	    e = GetLastError();
#if WSAEWOULDBLOCK != EWOULDBLOCK
	else if (e >= EADDRINUSE && e <= EWOULDBLOCK) {
	    static int s = -1;
	    int i;
	    if (s < 0)
		for (s = 0; s < (int)(sizeof(errmap)/sizeof(*errmap)); s++)
		    if (errmap[s].winerr == WSAEWOULDBLOCK)
			break;
	    for (i = s; i < (int)(sizeof(errmap)/sizeof(*errmap)); i++)
		if (errmap[i].err == e) {
		    e = errmap[i].winerr;
		    break;
		}
	}
#endif
	if (FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
			  FORMAT_MESSAGE_IGNORE_INSERTS, &source, e,
			  MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
			  buffer, sizeof(buffer), NULL) == 0 &&
	    FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
			  FORMAT_MESSAGE_IGNORE_INSERTS, &source, e, 0,
			  buffer, sizeof(buffer), NULL) == 0)
	    strlcpy(buffer, "Unknown Error", sizeof(buffer));
    }
    else
	strlcpy(buffer, strerror(e), sizeof(buffer));

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

/* License: Artistic or GPL */
rb_uid_t
getuid(void)
{
	return ROOT_UID;
}

/* License: Artistic or GPL */
rb_uid_t
geteuid(void)
{
	return ROOT_UID;
}

/* License: Artistic or GPL */
rb_gid_t
getgid(void)
{
	return ROOT_GID;
}

/* License: Artistic or GPL */
rb_gid_t
getegid(void)
{
    return ROOT_GID;
}

/* License: Artistic or GPL */
int
setuid(rb_uid_t uid)
{
    return (uid == ROOT_UID ? 0 : -1);
}

/* License: Artistic or GPL */
int
setgid(rb_gid_t gid)
{
    return (gid == ROOT_GID ? 0 : -1);
}

//
// File system stuff
//

/* License: Artistic or GPL */
int
ioctl(int i, int u, ...)
{
    errno = EINVAL;
    return -1;
}

void
rb_w32_fdset(int fd, fd_set *set)
{
    FD_SET(fd, set);
}

#undef FD_CLR

/* License: Ruby's */
void
rb_w32_fdclr(int fd, fd_set *set)
{
    unsigned int i;
    SOCKET s = TO_SOCKET(fd);

    for (i = 0; i < set->fd_count; i++) {
        if (set->fd_array[i] == s) {
	    memmove(&set->fd_array[i], &set->fd_array[i+1],
		    sizeof(set->fd_array[0]) * (--set->fd_count - i));
            break;
        }
    }
}

#undef FD_ISSET

/* License: Ruby's */
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

/* License: Ruby's */
void
rb_w32_fd_copy(rb_fdset_t *dst, const fd_set *src, int max)
{
    max = min(src->fd_count, (UINT)max);
    if ((UINT)dst->capa < (UINT)max) {
	dst->capa = (src->fd_count / FD_SETSIZE + 1) * FD_SETSIZE;
	dst->fdset = xrealloc(dst->fdset, sizeof(unsigned int) + sizeof(SOCKET) * dst->capa);
    }

    memcpy(dst->fdset->fd_array, src->fd_array,
	   max * sizeof(src->fd_array[0]));
    dst->fdset->fd_count = src->fd_count;
}

/* License: Ruby's */
void
rb_w32_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src)
{
    if ((UINT)dst->capa < src->fdset->fd_count) {
	dst->capa = (src->fdset->fd_count / FD_SETSIZE + 1) * FD_SETSIZE;
	dst->fdset = xrealloc(dst->fdset, sizeof(unsigned int) + sizeof(SOCKET) * dst->capa);
    }

    memcpy(dst->fdset->fd_array, src->fdset->fd_array,
	   src->fdset->fd_count * sizeof(src->fdset->fd_array[0]));
    dst->fdset->fd_count = src->fdset->fd_count;
}

//
// Networking trampolines
// These are used to avoid socket startup/shutdown overhead in case
// the socket routines aren't used.
//

#undef select

/* License: Ruby's */
static int
extract_fd(rb_fdset_t *dst, fd_set *src, int (*func)(SOCKET))
{
    unsigned int s = 0;
    unsigned int m = 0;
    if (!src) return 0;

    while (s < src->fd_count) {
        SOCKET fd = src->fd_array[s];

	if (!func || (*func)(fd)) {
	    if (dst) { /* move it to dst */
		unsigned int d;

		for (d = 0; d < dst->fdset->fd_count; d++) {
		    if (dst->fdset->fd_array[d] == fd)
			break;
		}
		if (d == dst->fdset->fd_count) {
		    if ((int)dst->fdset->fd_count >= dst->capa) {
			dst->capa = (dst->fdset->fd_count / FD_SETSIZE + 1) * FD_SETSIZE;
			dst->fdset = xrealloc(dst->fdset, sizeof(unsigned int) + sizeof(SOCKET) * dst->capa);
		    }
		    dst->fdset->fd_array[dst->fdset->fd_count++] = fd;
		}
		memmove(
		    &src->fd_array[s],
		    &src->fd_array[s+1],
		    sizeof(src->fd_array[0]) * (--src->fd_count - s));
	    }
	    else {
		m++;
		s++;
	    }
	}
	else s++;
    }

    return dst ? dst->fdset->fd_count : m;
}

/* License: Ruby's */
static int
copy_fd(fd_set *dst, fd_set *src)
{
    unsigned int s;
    if (!src || !dst) return 0;

    for (s = 0; s < src->fd_count; ++s) {
	SOCKET fd = src->fd_array[s];
	unsigned int d;
	for (d = 0; d < dst->fd_count; ++d) {
	    if (dst->fd_array[d] == fd)
		break;
	}
	if (d == dst->fd_count && d < FD_SETSIZE) {
	    dst->fd_array[dst->fd_count++] = fd;
	}
    }

    return dst->fd_count;
}

/* License: Ruby's */
static int
is_not_socket(SOCKET sock)
{
    return !is_socket(sock);
}

/* License: Ruby's */
static int
is_pipe(SOCKET sock) /* DONT call this for SOCKET! it claims it is PIPE. */
{
    int ret;

    RUBY_CRITICAL {
	ret = (GetFileType((HANDLE)sock) == FILE_TYPE_PIPE);
    }

    return ret;
}

/* License: Ruby's */
static int
is_readable_pipe(SOCKET sock) /* call this for pipe only */
{
    int ret;
    DWORD n = 0;

    RUBY_CRITICAL {
	if (PeekNamedPipe((HANDLE)sock, NULL, 0, NULL, &n, NULL)) {
	    ret = (n > 0);
	}
	else {
	    ret = (GetLastError() == ERROR_BROKEN_PIPE); /* pipe was closed */
	}
    }

    return ret;
}

/* License: Ruby's */
static int
is_console(SOCKET sock) /* DONT call this for SOCKET! */
{
    int ret;
    DWORD n = 0;
    INPUT_RECORD ir;

    RUBY_CRITICAL {
	ret = (PeekConsoleInput((HANDLE)sock, &ir, 1, &n));
    }

    return ret;
}

/* License: Ruby's */
static int
is_readable_console(SOCKET sock) /* call this for console only */
{
    int ret = 0;
    DWORD n = 0;
    INPUT_RECORD ir;

    RUBY_CRITICAL {
	if (PeekConsoleInput((HANDLE)sock, &ir, 1, &n) && n > 0) {
	    if (ir.EventType == KEY_EVENT && ir.Event.KeyEvent.bKeyDown &&
		ir.Event.KeyEvent.uChar.AsciiChar) {
		ret = 1;
	    }
	    else {
		ReadConsoleInput((HANDLE)sock, &ir, 1, &n);
	    }
	}
    }

    return ret;
}

/* License: Ruby's */
static int
is_invalid_handle(SOCKET sock)
{
    return (HANDLE)sock == INVALID_HANDLE_VALUE;
}

/* License: Artistic or GPL */
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
	RUBY_CRITICAL {
	    EnterCriticalSection(&select_mutex);
	    r = select(nfds, rd, wr, ex, timeout);
	    LeaveCriticalSection(&select_mutex);
	    if (r == SOCKET_ERROR) {
		errno = map_errno(WSAGetLastError());
		r = -1;
	    }
	}
    }

    return r;
}

/*
 * rest -= wait
 * return 0 if rest is smaller than wait.
 */
/* License: Ruby's */
int
rb_w32_time_subtract(struct timeval *rest, const struct timeval *wait)
{
    if (rest->tv_sec < wait->tv_sec) {
	return 0;
    }
    while (rest->tv_usec < wait->tv_usec) {
	if (rest->tv_sec <= wait->tv_sec) {
	    return 0;
	}
	rest->tv_sec -= 1;
	rest->tv_usec += 1000 * 1000;
    }
    rest->tv_sec -= wait->tv_sec;
    rest->tv_usec -= wait->tv_usec;
    return rest->tv_sec != 0 || rest->tv_usec != 0;
}

/* License: Ruby's */
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

int rb_w32_check_interrupt(void *);	/* @internal */

/* @internal */
/* License: Ruby's */
int
rb_w32_select_with_thread(int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
			  struct timeval *timeout, void *th)
{
    int r;
    rb_fdset_t pipe_rd;
    rb_fdset_t cons_rd;
    rb_fdset_t else_rd;
    rb_fdset_t else_wr;
    rb_fdset_t except;
    int nonsock = 0;
    struct timeval limit = {0, 0};

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

    // assume else_{rd,wr} (other than socket, pipe reader, console reader)
    // are always readable/writable. but this implementation still has
    // problem. if pipe's buffer is full, writing to pipe will block
    // until some data is read from pipe. but ruby is single threaded system,
    // so whole system will be blocked forever.

    rb_fd_init(&else_rd);
    nonsock += extract_fd(&else_rd, rd, is_not_socket);

    rb_fd_init(&else_wr);
    nonsock += extract_fd(&else_wr, wr, is_not_socket);

    // check invalid handles
    if (extract_fd(NULL, else_rd.fdset, is_invalid_handle) > 0 ||
	extract_fd(NULL, else_wr.fdset, is_invalid_handle) > 0) {
	rb_fd_term(&else_wr);
	rb_fd_term(&else_rd);
	errno = EBADF;
	return -1;
    }

    rb_fd_init(&pipe_rd);
    extract_fd(&pipe_rd, else_rd.fdset, is_pipe); // should not call is_pipe for socket

    rb_fd_init(&cons_rd);
    extract_fd(&cons_rd, else_rd.fdset, is_console); // ditto

    rb_fd_init(&except);
    extract_fd(&except, ex, is_not_socket); // drop only

    r = 0;
    if (rd && (int)rd->fd_count > r) r = (int)rd->fd_count;
    if (wr && (int)wr->fd_count > r) r = (int)wr->fd_count;
    if (ex && (int)ex->fd_count > r) r = (int)ex->fd_count;
    if (nfds > r) nfds = r;

    {
	struct timeval rest;
	const struct timeval wait = {0, 10 * 1000}; // 10ms
	struct timeval zero = {0, 0};		    // 0ms
	for (;;) {
	    if (th && rb_w32_check_interrupt(th) != WAIT_TIMEOUT) {
		r = -1;
		break;
	    }
	    if (nonsock) {
		// modifying {else,pipe,cons}_rd is safe because
		// if they are modified, function returns immediately.
		extract_fd(&else_rd, pipe_rd.fdset, is_readable_pipe);
		extract_fd(&else_rd, cons_rd.fdset, is_readable_console);
	    }

	    if (else_rd.fdset->fd_count || else_wr.fdset->fd_count) {
		r = do_select(nfds, rd, wr, ex, &zero); // polling
		if (r < 0) break; // XXX: should I ignore error and return signaled handles?
		r += copy_fd(rd, else_rd.fdset);
		r += copy_fd(wr, else_wr.fdset);
		if (ex)
		    r += ex->fd_count;
		break;
	    }
	    else {
		const struct timeval *dowait = &wait;

		fd_set orig_rd;
		fd_set orig_wr;
		fd_set orig_ex;

		FD_ZERO(&orig_rd);
		FD_ZERO(&orig_wr);
		FD_ZERO(&orig_ex);

		if (rd) copy_fd(&orig_rd, rd);
		if (wr) copy_fd(&orig_wr, wr);
		if (ex) copy_fd(&orig_ex, ex);
		r = do_select(nfds, rd, wr, ex, &zero);	// polling
		if (r != 0) break; // signaled or error
		if (rd) copy_fd(rd, &orig_rd);
		if (wr) copy_fd(wr, &orig_wr);
		if (ex) copy_fd(ex, &orig_ex);

		if (timeout) {
		    struct timeval now;
		    gettimeofday(&now, NULL);
		    rest = limit;
		    if (!rb_w32_time_subtract(&rest, &now)) break;
		    if (compare(&rest, &wait) < 0) dowait = &rest;
		}
		Sleep(dowait->tv_sec * 1000 + (dowait->tv_usec + 999) / 1000);
	    }
	}
    }

    rb_fd_term(&except);
    rb_fd_term(&cons_rd);
    rb_fd_term(&pipe_rd);
    rb_fd_term(&else_wr);
    rb_fd_term(&else_rd);

    return r;
}

/* License: Ruby's */
int WSAAPI
rb_w32_select(int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
	      struct timeval *timeout)
{
    return rb_w32_select_with_thread(nfds, rd, wr, ex, timeout, 0);
}

/* License: Ruby's */
static FARPROC
get_wsa_extension_function(SOCKET s, GUID *guid)
{
    DWORD dmy;
    FARPROC ptr = NULL;

    WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER, guid, sizeof(*guid),
	     &ptr, sizeof(ptr), &dmy, NULL, NULL);
    if (!ptr)
	errno = ENOSYS;
    return ptr;
}

#undef accept

/* License: Artistic or GPL */
int WSAAPI
rb_w32_accept(int s, struct sockaddr *addr, int *addrlen)
{
    SOCKET r;
    int fd;

    RUBY_CRITICAL {
	r = accept(TO_SOCKET(s), addr, addrlen);
	if (r != INVALID_SOCKET) {
	    SetHandleInformation((HANDLE)r, HANDLE_FLAG_INHERIT, 0);
	    fd = rb_w32_open_osfhandle((intptr_t)r, O_RDWR|O_BINARY|O_NOINHERIT);
	    if (fd != -1)
		socklist_insert(r, 0);
	    else
		closesocket(r);
	}
	else {
	    errno = map_errno(WSAGetLastError());
	    fd = -1;
	}
    }
    return fd;
}

#undef bind

/* License: Artistic or GPL */
int WSAAPI
rb_w32_bind(int s, const struct sockaddr *addr, int addrlen)
{
    int r;

    RUBY_CRITICAL {
	r = bind(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef connect

/* License: Artistic or GPL */
int WSAAPI
rb_w32_connect(int s, const struct sockaddr *addr, int addrlen)
{
    int r;
    RUBY_CRITICAL {
	r = connect(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR) {
	    int err = WSAGetLastError();
	    if (err != WSAEWOULDBLOCK)
		errno = map_errno(err);
	    else
		errno = EINPROGRESS;
	}
    }
    return r;
}


#undef getpeername

/* License: Artistic or GPL */
int WSAAPI
rb_w32_getpeername(int s, struct sockaddr *addr, int *addrlen)
{
    int r;
    RUBY_CRITICAL {
	r = getpeername(TO_SOCKET(s), addr, addrlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef getsockname

/* License: Artistic or GPL */
int WSAAPI
rb_w32_getsockname(int fd, struct sockaddr *addr, int *addrlen)
{
    int sock;
    int r;
    RUBY_CRITICAL {
	sock = TO_SOCKET(fd);
	r = getsockname(sock, addr, addrlen);
	if (r == SOCKET_ERROR) {
	    DWORD wsaerror = WSAGetLastError();
	    if (wsaerror == WSAEINVAL) {
		int flags;
		if (socklist_lookup(sock, &flags)) {
		    int af = GET_FAMILY(flags);
		    if (af) {
			memset(addr, 0, *addrlen);
			addr->sa_family = af;
			return 0;
		    }
		}
	    }
	    errno = map_errno(wsaerror);
	}
    }
    return r;
}

#undef getsockopt

/* License: Artistic or GPL */
int WSAAPI
rb_w32_getsockopt(int s, int level, int optname, char *optval, int *optlen)
{
    int r;
    RUBY_CRITICAL {
	r = getsockopt(TO_SOCKET(s), level, optname, optval, optlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef ioctlsocket

/* License: Artistic or GPL */
int WSAAPI
rb_w32_ioctlsocket(int s, long cmd, u_long *argp)
{
    int r;
    RUBY_CRITICAL {
	r = ioctlsocket(TO_SOCKET(s), cmd, argp);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef listen

/* License: Artistic or GPL */
int WSAAPI
rb_w32_listen(int s, int backlog)
{
    int r;
    RUBY_CRITICAL {
	r = listen(TO_SOCKET(s), backlog);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef recv
#undef recvfrom
#undef send
#undef sendto

/* License: Ruby's */
static int
finish_overlapped_socket(BOOL input, SOCKET s, WSAOVERLAPPED *wol, int result, DWORD *len, DWORD size)
{
    DWORD flg;
    int err;

    if (result != SOCKET_ERROR)
	*len = size;
    else if ((err = WSAGetLastError()) == WSA_IO_PENDING) {
	switch (rb_w32_wait_events_blocking(&wol->hEvent, 1, INFINITE)) {
	  case WAIT_OBJECT_0:
	    RUBY_CRITICAL {
		result = WSAGetOverlappedResult(s, wol, &size, TRUE, &flg);
	    }
	    if (result) {
		result = 0;
		*len = size;
		break;
	    }
	    result = SOCKET_ERROR;
	    /* thru */
	  default:
	    if ((err = WSAGetLastError()) == WSAECONNABORTED && !input)
		errno = EPIPE;
	    else if (err == WSAEMSGSIZE && input) {
		result = 0;
		*len = size;
		break;
	    }
	    else
		errno = map_errno(err);
	    /* thru */
	  case WAIT_OBJECT_0 + 1:
	    /* interrupted */
	    *len = -1;
	    CancelIo((HANDLE)s);
	    break;
	}
    }
    else {
	if (err == WSAECONNABORTED && !input)
	    errno = EPIPE;
	else
	    errno = map_errno(err);
	*len = -1;
    }
    CloseHandle(wol->hEvent);

    return result;
}

/* License: Artistic or GPL */
static int
overlapped_socket_io(BOOL input, int fd, char *buf, int len, int flags,
		     struct sockaddr *addr, int *addrlen)
{
    int r;
    int ret;
    int mode = 0;
    DWORD flg;
    WSAOVERLAPPED wol;
    WSABUF wbuf;
    SOCKET s;

    s = TO_SOCKET(fd);
    socklist_lookup(s, &mode);
    if (GET_FLAGS(mode) & O_NONBLOCK) {
	RUBY_CRITICAL {
	    if (input) {
		if (addr && addrlen)
		    r = recvfrom(s, buf, len, flags, addr, addrlen);
		else
		    r = recv(s, buf, len, flags);
		if (r == SOCKET_ERROR)
		    errno = map_errno(WSAGetLastError());
	    }
	    else {
		if (addr && addrlen)
		    r = sendto(s, buf, len, flags, addr, *addrlen);
		else
		    r = send(s, buf, len, flags);
		if (r == SOCKET_ERROR) {
		    DWORD err = WSAGetLastError();
		    if (err == WSAECONNABORTED)
			errno = EPIPE;
		    else
			errno = map_errno(err);
		}
	    }
	}
    }
    else {
	DWORD size;
	DWORD rlen;
	wbuf.len = len;
	wbuf.buf = buf;
	memset(&wol, 0, sizeof(wol));
	RUBY_CRITICAL {
	    wol.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	    if (input) {
		flg = flags;
		if (addr && addrlen)
		    ret = WSARecvFrom(s, &wbuf, 1, &size, &flg, addr, addrlen,
				      &wol, NULL);
		else
		    ret = WSARecv(s, &wbuf, 1, &size, &flg, &wol, NULL);
	    }
	    else {
		if (addr && addrlen)
		    ret = WSASendTo(s, &wbuf, 1, &size, flags, addr, *addrlen,
				    &wol, NULL);
		else
		    ret = WSASend(s, &wbuf, 1, &size, flags, &wol, NULL);
	    }
	}

	finish_overlapped_socket(input, s, &wol, ret, &rlen, size);
	r = (int)rlen;
    }

    return r;
}

/* License: Ruby's */
int WSAAPI
rb_w32_recv(int fd, char *buf, int len, int flags)
{
    return overlapped_socket_io(TRUE, fd, buf, len, flags, NULL, NULL);
}

/* License: Ruby's */
int WSAAPI
rb_w32_recvfrom(int fd, char *buf, int len, int flags,
		struct sockaddr *from, int *fromlen)
{
    return overlapped_socket_io(TRUE, fd, buf, len, flags, from, fromlen);
}

/* License: Ruby's */
int WSAAPI
rb_w32_send(int fd, const char *buf, int len, int flags)
{
    return overlapped_socket_io(FALSE, fd, (char *)buf, len, flags, NULL, NULL);
}

/* License: Ruby's */
int WSAAPI
rb_w32_sendto(int fd, const char *buf, int len, int flags,
	      const struct sockaddr *to, int tolen)
{
    return overlapped_socket_io(FALSE, fd, (char *)buf, len, flags,
				(struct sockaddr *)to, &tolen);
}

#if !defined(MSG_TRUNC) && !defined(__MINGW32__)
/* License: Ruby's */
typedef struct {
    SOCKADDR *name;
    int namelen;
    WSABUF *lpBuffers;
    DWORD dwBufferCount;
    WSABUF Control;
    DWORD dwFlags;
} WSAMSG;
#endif
#ifndef WSAID_WSARECVMSG
#define WSAID_WSARECVMSG {0xf689d7c8,0x6f1f,0x436b,{0x8a,0x53,0xe5,0x4f,0xe3,0x51,0xc3,0x22}}
#endif
#ifndef WSAID_WSASENDMSG
#define WSAID_WSASENDMSG {0xa441e712,0x754f,0x43ca,{0x84,0xa7,0x0d,0xee,0x44,0xcf,0x60,0x6d}}
#endif

/* License: Ruby's */
#define msghdr_to_wsamsg(msg, wsamsg) \
    do { \
	int i; \
	(wsamsg)->name = (msg)->msg_name; \
	(wsamsg)->namelen = (msg)->msg_namelen; \
	(wsamsg)->lpBuffers = ALLOCA_N(WSABUF, (msg)->msg_iovlen); \
	(wsamsg)->dwBufferCount = (msg)->msg_iovlen; \
	for (i = 0; i < (msg)->msg_iovlen; ++i) { \
	    (wsamsg)->lpBuffers[i].buf = (msg)->msg_iov[i].iov_base; \
	    (wsamsg)->lpBuffers[i].len = (msg)->msg_iov[i].iov_len; \
	} \
	(wsamsg)->Control.buf = (msg)->msg_control; \
	(wsamsg)->Control.len = (msg)->msg_controllen; \
	(wsamsg)->dwFlags = (msg)->msg_flags; \
    } while (0)

/* License: Ruby's */
int
recvmsg(int fd, struct msghdr *msg, int flags)
{
    typedef int (WSAAPI *WSARecvMsg_t)(SOCKET, WSAMSG *, DWORD *, WSAOVERLAPPED *, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
    static WSARecvMsg_t pWSARecvMsg = NULL;
    WSAMSG wsamsg;
    SOCKET s;
    int mode = 0;
    DWORD len;
    int ret;

    s = TO_SOCKET(fd);

    if (!pWSARecvMsg) {
	static GUID guid = WSAID_WSARECVMSG;
	pWSARecvMsg = (WSARecvMsg_t)get_wsa_extension_function(s, &guid);
	if (!pWSARecvMsg)
	    return -1;
    }

    msghdr_to_wsamsg(msg, &wsamsg);
    wsamsg.dwFlags |= flags;

    socklist_lookup(s, &mode);
    if (GET_FLAGS(mode) & O_NONBLOCK) {
	RUBY_CRITICAL {
	    if ((ret = pWSARecvMsg(s, &wsamsg, &len, NULL, NULL)) == SOCKET_ERROR) {
		errno = map_errno(WSAGetLastError());
		len = -1;
	    }
	}
    }
    else {
	DWORD size;
	WSAOVERLAPPED wol;
	memset(&wol, 0, sizeof(wol));
	RUBY_CRITICAL {
	    wol.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	    ret = pWSARecvMsg(s, &wsamsg, &size, &wol, NULL);
	}

	ret = finish_overlapped_socket(TRUE, s, &wol, ret, &len, size);
    }
    if (ret == SOCKET_ERROR)
	return -1;

    /* WSAMSG to msghdr */
    msg->msg_name = wsamsg.name;
    msg->msg_namelen = wsamsg.namelen;
    msg->msg_flags = wsamsg.dwFlags;

    return len;
}

/* License: Ruby's */
int
sendmsg(int fd, const struct msghdr *msg, int flags)
{
    typedef int (WSAAPI *WSASendMsg_t)(SOCKET, const WSAMSG *, DWORD, DWORD *, WSAOVERLAPPED *, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
    static WSASendMsg_t pWSASendMsg = NULL;
    WSAMSG wsamsg;
    SOCKET s;
    int mode = 0;
    DWORD len;
    int ret;

    s = TO_SOCKET(fd);

    if (!pWSASendMsg) {
	static GUID guid = WSAID_WSASENDMSG;
	pWSASendMsg = (WSASendMsg_t)get_wsa_extension_function(s, &guid);
	if (!pWSASendMsg)
	    return -1;
    }

    msghdr_to_wsamsg(msg, &wsamsg);

    socklist_lookup(s, &mode);
    if (GET_FLAGS(mode) & O_NONBLOCK) {
	RUBY_CRITICAL {
	    if ((ret = pWSASendMsg(s, &wsamsg, flags, &len, NULL, NULL)) == SOCKET_ERROR) {
		errno = map_errno(WSAGetLastError());
		len = -1;
	    }
	}
    }
    else {
	DWORD size;
	WSAOVERLAPPED wol;
	memset(&wol, 0, sizeof(wol));
	RUBY_CRITICAL {
	    wol.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	    ret = pWSASendMsg(s, &wsamsg, flags, &size, &wol, NULL);
	}

	finish_overlapped_socket(FALSE, s, &wol, ret, &len, size);
    }

    return len;
}

#undef setsockopt

/* License: Artistic or GPL */
int WSAAPI
rb_w32_setsockopt(int s, int level, int optname, const char *optval, int optlen)
{
    int r;
    RUBY_CRITICAL {
	r = setsockopt(TO_SOCKET(s), level, optname, optval, optlen);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef shutdown

/* License: Artistic or GPL */
int WSAAPI
rb_w32_shutdown(int s, int how)
{
    int r;
    RUBY_CRITICAL {
	r = shutdown(TO_SOCKET(s), how);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

/* License: Ruby's */
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

		    out = WSASocket(af, type, protocol, &(proto_buffers[i]), 0,
				    WSA_FLAG_OVERLAPPED);
		    break;
		}
		if (out == INVALID_SOCKET)
		    out = WSASocket(af, type, protocol, NULL, 0, 0);
		if (out != INVALID_SOCKET)
		    SetHandleInformation((HANDLE)out, HANDLE_FLAG_INHERIT, 0);
	    }

	    free(proto_buffers);
	}
    }

    return out;
}

#undef socket

/* License: Artistic or GPL */
int WSAAPI
rb_w32_socket(int af, int type, int protocol)
{
    SOCKET s;
    int fd;

    RUBY_CRITICAL {
	s = open_ifs_socket(af, type, protocol);
	if (s == INVALID_SOCKET) {
	    errno = map_errno(WSAGetLastError());
	    fd = -1;
	}
	else {
	    fd = rb_w32_open_osfhandle(s, O_RDWR|O_BINARY|O_NOINHERIT);
	    if (fd != -1)
		socklist_insert(s, MAKE_SOCKDATA(af, 0));
	    else
		closesocket(s);
	}
    }
    return fd;
}

#undef gethostbyaddr

/* License: Artistic or GPL */
struct hostent * WSAAPI
rb_w32_gethostbyaddr(const char *addr, int len, int type)
{
    struct hostent *r;
    RUBY_CRITICAL {
	r = gethostbyaddr(addr, len, type);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef gethostbyname

/* License: Artistic or GPL */
struct hostent * WSAAPI
rb_w32_gethostbyname(const char *name)
{
    struct hostent *r;
    RUBY_CRITICAL {
	r = gethostbyname(name);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef gethostname

/* License: Artistic or GPL */
int WSAAPI
rb_w32_gethostname(char *name, int len)
{
    int r;
    RUBY_CRITICAL {
	r = gethostname(name, len);
	if (r == SOCKET_ERROR)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef getprotobyname

/* License: Artistic or GPL */
struct protoent * WSAAPI
rb_w32_getprotobyname(const char *name)
{
    struct protoent *r;
    RUBY_CRITICAL {
	r = getprotobyname(name);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef getprotobynumber

/* License: Artistic or GPL */
struct protoent * WSAAPI
rb_w32_getprotobynumber(int num)
{
    struct protoent *r;
    RUBY_CRITICAL {
	r = getprotobynumber(num);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef getservbyname

/* License: Artistic or GPL */
struct servent * WSAAPI
rb_w32_getservbyname(const char *name, const char *proto)
{
    struct servent *r;
    RUBY_CRITICAL {
	r = getservbyname(name, proto);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

#undef getservbyport

/* License: Artistic or GPL */
struct servent * WSAAPI
rb_w32_getservbyport(int port, const char *proto)
{
    struct servent *r;
    RUBY_CRITICAL {
	r = getservbyport(port, proto);
	if (r == NULL)
	    errno = map_errno(WSAGetLastError());
    }
    return r;
}

/* License: Ruby's */
static int
socketpair_internal(int af, int type, int protocol, SOCKET *sv)
{
    SOCKET svr = INVALID_SOCKET, r = INVALID_SOCKET, w = INVALID_SOCKET;
    struct sockaddr_in sock_in4;
#ifdef INET6
    struct sockaddr_in6 sock_in6;
#endif
    struct sockaddr *addr;
    int ret = -1;
    int len;

    switch (af) {
      case AF_INET:
#if defined PF_INET && PF_INET != AF_INET
      case PF_INET:
#endif
	sock_in4.sin_family = AF_INET;
	sock_in4.sin_port = 0;
	sock_in4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	addr = (struct sockaddr *)&sock_in4;
	len = sizeof(sock_in4);
	break;
#ifdef INET6
      case AF_INET6:
	memset(&sock_in6, 0, sizeof(sock_in6));
	sock_in6.sin6_family = AF_INET6;
	sock_in6.sin6_addr = IN6ADDR_LOOPBACK_INIT;
	addr = (struct sockaddr *)&sock_in6;
	len = sizeof(sock_in6);
	break;
#endif
      default:
	errno = EAFNOSUPPORT;
	return -1;
    }
    if (type != SOCK_STREAM) {
	errno = EPROTOTYPE;
	return -1;
    }

    sv[0] = (SOCKET)INVALID_HANDLE_VALUE;
    sv[1] = (SOCKET)INVALID_HANDLE_VALUE;
    RUBY_CRITICAL {
	do {
	    svr = open_ifs_socket(af, type, protocol);
	    if (svr == INVALID_SOCKET)
		break;
	    if (bind(svr, addr, len) < 0)
		break;
	    if (getsockname(svr, addr, &len) < 0)
		break;
	    if (type == SOCK_STREAM)
		listen(svr, 5);

	    w = open_ifs_socket(af, type, protocol);
	    if (w == INVALID_SOCKET)
		break;
	    if (connect(w, addr, len) < 0)
		break;

	    r = accept(svr, addr, &len);
	    if (r == INVALID_SOCKET)
		break;
	    SetHandleInformation((HANDLE)r, HANDLE_FLAG_INHERIT, 0);

	    ret = 0;
	} while (0);

	if (ret < 0) {
	    errno = map_errno(WSAGetLastError());
	    if (r != INVALID_SOCKET)
		closesocket(r);
	    if (w != INVALID_SOCKET)
		closesocket(w);
	}
	else {
	    sv[0] = r;
	    sv[1] = w;
	}
	if (svr != INVALID_SOCKET)
	    closesocket(svr);
    }

    return ret;
}

/* License: Ruby's */
int
socketpair(int af, int type, int protocol, int *sv)
{
    SOCKET pair[2];

    if (socketpair_internal(af, type, protocol, pair) < 0)
	return -1;
    sv[0] = rb_w32_open_osfhandle(pair[0], O_RDWR|O_BINARY|O_NOINHERIT);
    if (sv[0] == -1) {
	closesocket(pair[0]);
	closesocket(pair[1]);
	return -1;
    }
    sv[1] = rb_w32_open_osfhandle(pair[1], O_RDWR|O_BINARY|O_NOINHERIT);
    if (sv[1] == -1) {
	rb_w32_close(sv[0]);
	closesocket(pair[1]);
	return -1;
    }
    socklist_insert(pair[0], MAKE_SOCKDATA(af, 0));
    socklist_insert(pair[1], MAKE_SOCKDATA(af, 0));

    return 0;
}

#if !defined(_MSC_VER) || _MSC_VER >= 1400
/* License: Ruby's */
static void
str2guid(const char *str, GUID *guid)
{
#define hex2byte(str) \
    ((isdigit(*(str)) ? *(str) - '0' : toupper(*(str)) - 'A' + 10) << 4 | (isdigit(*((str) + 1)) ? *((str) + 1) - '0' : toupper(*((str) + 1)) - 'A' + 10))
    char *end;
    int i;
    if (*str == '{') str++;
    guid->Data1 = (long)strtoul(str, &end, 16);
    str += 9;
    guid->Data2 = (unsigned short)strtoul(str, &end, 16);
    str += 5;
    guid->Data3 = (unsigned short)strtoul(str, &end, 16);
    str += 5;
    guid->Data4[0] = hex2byte(str);
    str += 2;
    guid->Data4[1] = hex2byte(str);
    str += 3;
    for (i = 0; i < 6; i++) {
	guid->Data4[i + 2] = hex2byte(str);
	str += 2;
    }
}

/* License: Ruby's */
#ifndef HAVE_TYPE_NET_LUID
    typedef struct {
	uint64_t Value;
	struct {
	    uint64_t Reserved :24;
	    uint64_t NetLuidIndex :24;
	    uint64_t IfType :16;
	} Info;
    } NET_LUID;
#endif
typedef DWORD (WINAPI *cigl_t)(const GUID *, NET_LUID *);
typedef DWORD (WINAPI *cilnA_t)(const NET_LUID *, char *, size_t);
static cigl_t pConvertInterfaceGuidToLuid = (cigl_t)-1;
static cilnA_t pConvertInterfaceLuidToNameA = (cilnA_t)-1;

int
getifaddrs(struct ifaddrs **ifap)
{
    ULONG size = 0;
    ULONG ret;
    IP_ADAPTER_ADDRESSES *root, *addr;
    struct ifaddrs *prev;

    ret = GetAdaptersAddresses(AF_UNSPEC, 0, NULL, NULL, &size);
    if (ret != ERROR_BUFFER_OVERFLOW) {
	errno = map_errno(ret);
	return -1;
    }
    root = ruby_xmalloc(size);
    ret = GetAdaptersAddresses(AF_UNSPEC, 0, NULL, root, &size);
    if (ret != ERROR_SUCCESS) {
	errno = map_errno(ret);
	ruby_xfree(root);
	return -1;
    }

    if (pConvertInterfaceGuidToLuid == (cigl_t)-1)
	pConvertInterfaceGuidToLuid =
	    (cigl_t)get_proc_address("iphlpapi.dll",
				     "ConvertInterfaceGuidToLuid", NULL);
    if (pConvertInterfaceLuidToNameA == (cilnA_t)-1)
	pConvertInterfaceLuidToNameA =
	    (cilnA_t)get_proc_address("iphlpapi.dll",
				      "ConvertInterfaceLuidToNameA", NULL);

    for (prev = NULL, addr = root; addr; addr = addr->Next) {
	struct ifaddrs *ifa = ruby_xcalloc(1, sizeof(*ifa));
	char name[IFNAMSIZ];
	GUID guid;
	NET_LUID luid;

	if (prev)
	    prev->ifa_next = ifa;
	else
	    *ifap = ifa;

	str2guid(addr->AdapterName, &guid);
	if (pConvertInterfaceGuidToLuid && pConvertInterfaceLuidToNameA &&
	    pConvertInterfaceGuidToLuid(&guid, &luid) == NO_ERROR &&
	    pConvertInterfaceLuidToNameA(&luid, name, sizeof(name)) == NO_ERROR) {
	    ifa->ifa_name = ruby_strdup(name);
	}
	else {
	    ifa->ifa_name = ruby_strdup(addr->AdapterName);
	}

	if (addr->IfType & IF_TYPE_SOFTWARE_LOOPBACK)
	    ifa->ifa_flags |= IFF_LOOPBACK;
	if (addr->OperStatus == IfOperStatusUp) {
	    ifa->ifa_flags |= IFF_UP;

	    if (addr->FirstUnicastAddress) {
		IP_ADAPTER_UNICAST_ADDRESS *cur;
		int added = 0;
		for (cur = addr->FirstUnicastAddress; cur; cur = cur->Next) {
		    if (cur->Flags & IP_ADAPTER_ADDRESS_TRANSIENT ||
			cur->DadState == IpDadStateDeprecated) {
			continue;
		    }
		    if (added) {
			prev = ifa;
			ifa = ruby_xcalloc(1, sizeof(*ifa));
			prev->ifa_next = ifa;
			ifa->ifa_name = ruby_strdup(prev->ifa_name);
			ifa->ifa_flags = prev->ifa_flags;
		    }
		    ifa->ifa_addr = ruby_xmalloc(cur->Address.iSockaddrLength);
		    memcpy(ifa->ifa_addr, cur->Address.lpSockaddr,
			   cur->Address.iSockaddrLength);
		    added = 1;
		}
	    }
	}

	prev = ifa;
    }

    ruby_xfree(root);
    return 0;
}

/* License: Ruby's */
void
freeifaddrs(struct ifaddrs *ifp)
{
    while (ifp) {
	struct ifaddrs *next = ifp->ifa_next;
	if (ifp->ifa_addr) ruby_xfree(ifp->ifa_addr);
	if (ifp->ifa_name) ruby_xfree(ifp->ifa_name);
	ruby_xfree(ifp);
	ifp = next;
    }
}
#endif

//
// Networking stubs
//

void endhostent(void) {}
void endnetent(void) {}
void endprotoent(void) {}
void endservent(void) {}

struct netent *getnetent (void) {return (struct netent *) NULL;}

struct netent *getnetbyaddr(long net, int type) {return (struct netent *)NULL;}

struct netent *getnetbyname(const char *name) {return (struct netent *)NULL;}

struct protoent *getprotoent (void) {return (struct protoent *) NULL;}

struct servent *getservent (void) {return (struct servent *) NULL;}

void sethostent (int stayopen) {}

void setnetent (int stayopen) {}

void setprotoent (int stayopen) {}

void setservent (int stayopen) {}

/* License: Ruby's */
static int
setfl(SOCKET sock, int arg)
{
    int ret;
    int af = 0;
    int flag = 0;
    u_long ioctlArg;

    socklist_lookup(sock, &flag);
    af = GET_FAMILY(flag);
    flag = GET_FLAGS(flag);
    if (arg & O_NONBLOCK) {
	flag |= O_NONBLOCK;
	ioctlArg = 1;
    }
    else {
	flag &= ~O_NONBLOCK;
	ioctlArg = 0;
    }
    RUBY_CRITICAL {
	ret = ioctlsocket(sock, FIONBIO, &ioctlArg);
	if (ret == 0)
	    socklist_insert(sock, MAKE_SOCKDATA(af, flag));
	else
	    errno = map_errno(WSAGetLastError());
    }

    return ret;
}

/* License: Ruby's */
static int
dupfd(HANDLE hDup, int flags, int minfd)
{
    int save_errno;
    int ret;
    int fds[32];
    int filled = 0;

    do {
	ret = _open_osfhandle((intptr_t)hDup, flags | FOPEN);
	if (ret == -1) {
	    goto close_fds_and_return;
	}
	if (ret >= minfd) {
	    goto close_fds_and_return;
	}
	fds[filled++] = ret;
    } while (filled < (int)numberof(fds));

    ret = dupfd(hDup, flags, minfd);

  close_fds_and_return:
    save_errno = errno;
    while (filled > 0) {
	int fd = fds[--filled];
	_set_osfhnd(fd, (intptr_t)INVALID_HANDLE_VALUE);
	close(fd);
    }
    errno = save_errno;

    return ret;
}

/* License: Ruby's */
int
fcntl(int fd, int cmd, ...)
{
    va_list va;
    int arg;
    DWORD flag;

    switch (cmd) {
      case F_SETFL: {
	SOCKET sock = TO_SOCKET(fd);
	if (!is_socket(sock)) {
	    errno = EBADF;
	    return -1;
	}

	va_start(va, cmd);
	arg = va_arg(va, int);
	va_end(va);
	return setfl(sock, arg);
      }
      case F_DUPFD: case F_DUPFD_CLOEXEC: {
	int ret;
	HANDLE hDup;
	flag = _osfile(fd);
	if (!(DuplicateHandle(GetCurrentProcess(), (HANDLE)_get_osfhandle(fd),
			      GetCurrentProcess(), &hDup, 0L,
			      cmd == F_DUPFD && !(flag & FNOINHERIT),
			      DUPLICATE_SAME_ACCESS))) {
	    errno = map_errno(GetLastError());
	    return -1;
	}

	va_start(va, cmd);
	arg = va_arg(va, int);
	va_end(va);

	if (cmd != F_DUPFD)
	    flag |= FNOINHERIT;
	else
	    flag &= ~FNOINHERIT;
	if ((ret = dupfd(hDup, flag, arg)) == -1)
	    CloseHandle(hDup);
	return ret;
      }
      case F_GETFD: {
	SIGNED_VALUE h = _get_osfhandle(fd);
	if (h == -1) return -1;
	if (!GetHandleInformation((HANDLE)h, &flag)) {
	    errno = map_errno(GetLastError());
	    return -1;
	}
	return (flag & HANDLE_FLAG_INHERIT) ? 0 : FD_CLOEXEC;
      }
      case F_SETFD: {
	SIGNED_VALUE h = _get_osfhandle(fd);
	if (h == -1) return -1;
	va_start(va, cmd);
	arg = va_arg(va, int);
	va_end(va);
	if (!SetHandleInformation((HANDLE)h, HANDLE_FLAG_INHERIT,
				  (arg & FD_CLOEXEC) ? 0 : HANDLE_FLAG_INHERIT)) {
	    errno = map_errno(GetLastError());
	    return -1;
	}
	if (arg & FD_CLOEXEC)
	    _osfile(fd) |= FNOINHERIT;
	else
	    _osfile(fd) &= ~FNOINHERIT;
	return 0;
      }
      default:
	errno = EINVAL;
	return -1;
    }
}

/* License: Ruby's */
int
rb_w32_set_nonblock2(int fd, int nonblock)
{
    SOCKET sock = TO_SOCKET(fd);
    if (is_socket(sock)) {
	return setfl(sock, nonblock ? O_NONBLOCK : 0);
    }
    else if (is_pipe(sock)) {
	DWORD state;
	if (!GetNamedPipeHandleState((HANDLE)sock, &state, NULL, NULL, NULL, NULL, 0)) {
	    errno = map_errno(GetLastError());
	    return -1;
	}
        if (nonblock) {
            state |= PIPE_NOWAIT;
        }
        else {
            state &= ~PIPE_NOWAIT;
        }
	if (!SetNamedPipeHandleState((HANDLE)sock, &state, NULL, NULL)) {
	    errno = map_errno(GetLastError());
	    return -1;
	}
	return 0;
    }
    else {
	errno = EBADF;
	return -1;
    }
}

int
rb_w32_set_nonblock(int fd)
{
    return rb_w32_set_nonblock2(fd, TRUE);
}

#ifndef WNOHANG
#define WNOHANG -1
#endif

/* License: Ruby's */
static rb_pid_t
poll_child_status(struct ChildRecord *child, int *stat_loc)
{
    DWORD exitcode;
    DWORD err;

    if (!GetExitCodeProcess(child->hProcess, &exitcode)) {
	/* If an error occurred, return immediately. */
	err = GetLastError();
	switch (err) {
	  case ERROR_INVALID_PARAMETER:
	    errno = ECHILD;
	    break;
	  case ERROR_INVALID_HANDLE:
	    errno = EINVAL;
	    break;
	  default:
	    errno = map_errno(err);
	    break;
	}
    error_exit:
	CloseChildHandle(child);
	return -1;
    }
    if (exitcode != STILL_ACTIVE) {
        rb_pid_t pid;
	/* If already died, wait process's real termination. */
        if (rb_w32_wait_events_blocking(&child->hProcess, 1, INFINITE) != WAIT_OBJECT_0) {
	    goto error_exit;
        }
	pid = child->pid;
	CloseChildHandle(child);
	if (stat_loc) {
	    *stat_loc = exitcode << 8;
	    if (exitcode & 0xC0000000) {
		static const struct {
		    DWORD status;
		    int sig;
		} table[] = {
		    {STATUS_ACCESS_VIOLATION,        SIGSEGV},
		    {STATUS_ILLEGAL_INSTRUCTION,     SIGILL},
		    {STATUS_PRIVILEGED_INSTRUCTION,  SIGILL},
		    {STATUS_FLOAT_DENORMAL_OPERAND,  SIGFPE},
		    {STATUS_FLOAT_DIVIDE_BY_ZERO,    SIGFPE},
		    {STATUS_FLOAT_INEXACT_RESULT,    SIGFPE},
		    {STATUS_FLOAT_INVALID_OPERATION, SIGFPE},
		    {STATUS_FLOAT_OVERFLOW,          SIGFPE},
		    {STATUS_FLOAT_STACK_CHECK,       SIGFPE},
		    {STATUS_FLOAT_UNDERFLOW,         SIGFPE},
#ifdef STATUS_FLOAT_MULTIPLE_FAULTS
		    {STATUS_FLOAT_MULTIPLE_FAULTS,   SIGFPE},
#endif
#ifdef STATUS_FLOAT_MULTIPLE_TRAPS
		    {STATUS_FLOAT_MULTIPLE_TRAPS,    SIGFPE},
#endif
		    {STATUS_CONTROL_C_EXIT,          SIGINT},
		};
		int i;
		for (i = 0; i < (int)numberof(table); i++) {
		    if (table[i].status == exitcode) {
			*stat_loc |= table[i].sig;
			break;
		    }
		}
		// if unknown status, assume SEGV
		if (i >= (int)numberof(table))
		    *stat_loc |= SIGSEGV;
	    }
	}
	return pid;
    }
    return 0;
}

/* License: Artistic or GPL */
rb_pid_t
waitpid(rb_pid_t pid, int *stat_loc, int options)
{
    DWORD timeout;

    /* Artistic or GPL part start */
    if (options == WNOHANG) {
	timeout = 0;
    }
    else {
	timeout = INFINITE;
    }
    /* Artistic or GPL part end */

    if (pid == -1) {
	int count = 0;
	int ret;
	HANDLE events[MAXCHILDNUM];
	struct ChildRecord* cause;

	FOREACH_CHILD(child) {
	    if (!child->pid || child->pid < 0) continue;
	    if ((pid = poll_child_status(child, stat_loc))) return pid;
	    events[count++] = child->hProcess;
	} END_FOREACH_CHILD;
	if (!count) {
	    errno = ECHILD;
	    return -1;
	}

	ret = rb_w32_wait_events_blocking(events, count, timeout);
	if (ret == WAIT_TIMEOUT) return 0;
	if ((ret -= WAIT_OBJECT_0) == count) {
	    return -1;
	}
	if (ret > count) {
	    errno = map_errno(GetLastError());
	    return -1;
	}

	cause = FindChildSlotByHandle(events[ret]);
	if (!cause) {
	    errno = ECHILD;
	    return -1;
	}
	return poll_child_status(cause, stat_loc);
    }
    else {
	struct ChildRecord* child = FindChildSlot(pid);
	int retried = 0;
	if (!child) {
	    errno = ECHILD;
	    return -1;
	}

	while (!(pid = poll_child_status(child, stat_loc))) {
	    /* wait... */
	    int ret = rb_w32_wait_events_blocking(&child->hProcess, 1, timeout);
	    if (ret == WAIT_OBJECT_0 + 1) return -1; /* maybe EINTR */
	    if (ret != WAIT_OBJECT_0) {
		/* still active */
		if (options & WNOHANG) {
		    pid = 0;
		    break;
		}
		++retried;
	    }
	}
	if (pid == -1 && retried) pid = 0;
    }

    return pid;
}

#include <sys/timeb.h>

static int have_precisetime = -1;

static void
get_systemtime(FILETIME *ft)
{
    typedef void (WINAPI *get_time_func)(FILETIME *ft);
    static get_time_func func = (get_time_func)-1;

    if (func == (get_time_func)-1) {
	/* GetSystemTimePreciseAsFileTime is available since Windows 8 and Windows Server 2012. */
	func = (get_time_func)get_proc_address("kernel32", "GetSystemTimePreciseAsFileTime", NULL);
	if (func == NULL) {
	    func = GetSystemTimeAsFileTime;
	    have_precisetime = 0;
	}
	else
	    have_precisetime = 1;
    }
    if (!ft) return;
    func(ft);
}

/* License: Ruby's */
/* split FILETIME value into UNIX time and sub-seconds in NT ticks */
static time_t
filetime_split(const FILETIME* ft, long *subsec)
{
    ULARGE_INTEGER tmp;
    unsigned LONG_LONG lt;
    const unsigned LONG_LONG subsec_unit = (unsigned LONG_LONG)10 * 1000 * 1000;

    tmp.LowPart = ft->dwLowDateTime;
    tmp.HighPart = ft->dwHighDateTime;
    lt = tmp.QuadPart;

    /* lt is now 100-nanosec intervals since 1601/01/01 00:00:00 UTC,
       convert it into UNIX time (since 1970/01/01 00:00:00 UTC).
       the first leap second is at 1972/06/30, so we doesn't need to think
       about it. */
    lt -= (LONG_LONG)((1970-1601)*365.2425) * 24 * 60 * 60 * subsec_unit;

    *subsec = (long)(lt % subsec_unit);
    return (time_t)(lt / subsec_unit);
}

/* License: Ruby's */
int __cdecl
gettimeofday(struct timeval *tv, struct timezone *tz)
{
    FILETIME ft;
    long subsec;

    get_systemtime(&ft);
    tv->tv_sec = filetime_split(&ft, &subsec);
    tv->tv_usec = subsec / 10;

    return 0;
}

/* License: Ruby's */
int
clock_gettime(clockid_t clock_id, struct timespec *sp)
{
    switch (clock_id) {
      case CLOCK_REALTIME:
	{
	    FILETIME ft;
	    long subsec;

	    get_systemtime(&ft);
	    sp->tv_sec = filetime_split(&ft, &subsec);
	    sp->tv_nsec = subsec * 100;
	    return 0;
	}
      case CLOCK_MONOTONIC:
	{
	    LARGE_INTEGER freq;
	    LARGE_INTEGER count;
	    if (!QueryPerformanceFrequency(&freq)) {
		errno = map_errno(GetLastError());
		return -1;
	    }
	    if (!QueryPerformanceCounter(&count)) {
		errno = map_errno(GetLastError());
		return -1;
	    }
	    sp->tv_sec = count.QuadPart / freq.QuadPart;
	    if (freq.QuadPart < 1000000000)
		sp->tv_nsec = (count.QuadPart % freq.QuadPart) * 1000000000 / freq.QuadPart;
	    else
		sp->tv_nsec = (long)((count.QuadPart % freq.QuadPart) * (1000000000.0 / freq.QuadPart));
	    return 0;
	}
      default:
	errno = EINVAL;
	return -1;
    }
}

/* License: Ruby's */
int
clock_getres(clockid_t clock_id, struct timespec *sp)
{
    switch (clock_id) {
      case CLOCK_REALTIME:
	{
	    sp->tv_sec = 0;
	    sp->tv_nsec = 1000;
	    return 0;
	}
      case CLOCK_MONOTONIC:
	{
	    LARGE_INTEGER freq;
	    if (!QueryPerformanceFrequency(&freq)) {
		errno = map_errno(GetLastError());
		return -1;
	    }
	    sp->tv_sec = 0;
	    sp->tv_nsec = (long)(1000000000.0 / freq.QuadPart);
	    return 0;
	}
      default:
	errno = EINVAL;
	return -1;
    }
}

/* License: Ruby's */
static char *
w32_getcwd(char *buffer, int size, UINT cp, void *alloc(int, void *), void *arg)
{
    WCHAR *p;
    int wlen, len;

    len = GetCurrentDirectoryW(0, NULL);
    if (!len) {
	errno = map_errno(GetLastError());
	return NULL;
    }

    if (buffer && size < len) {
	errno = ERANGE;
	return NULL;
    }

    p = ALLOCA_N(WCHAR, len);
    if (!GetCurrentDirectoryW(len, p)) {
	errno = map_errno(GetLastError());
        return NULL;
    }

    wlen = translate_wchar(p, L'\\', L'/') - p + 1;
    len = WideCharToMultiByte(cp, 0, p, wlen, NULL, 0, NULL, NULL);
    if (buffer) {
	if (size < len) {
	    errno = ERANGE;
	    return NULL;
	}
    }
    else {
	buffer = (*alloc)(len, arg);
	if (!buffer) {
	    errno = ENOMEM;
	    return NULL;
	}
    }
    WideCharToMultiByte(cp, 0, p, wlen, buffer, len, NULL, NULL);

    return buffer;
}

/* License: Ruby's */
static void *
getcwd_alloc(int size, void *dummy)
{
    return malloc(size);
}

/* License: Ruby's */
char *
rb_w32_getcwd(char *buffer, int size)
{
    return w32_getcwd(buffer, size, filecp(), getcwd_alloc, NULL);
}

/* License: Ruby's */
char *
rb_w32_ugetcwd(char *buffer, int size)
{
    return w32_getcwd(buffer, size, CP_UTF8, getcwd_alloc, NULL);
}

/* License: Ruby's */
static void *
getcwd_value(int size, void *arg)
{
    VALUE str = *(VALUE *)arg = rb_utf8_str_new(0, size - 1);
    OBJ_TAINT(str);
    return RSTRING_PTR(str);
}

/* License: Ruby's */
VALUE
rb_dir_getwd_ospath(void)
{
    VALUE cwd = Qnil;
    w32_getcwd(NULL, 0, CP_UTF8, getcwd_value, &cwd);
    return cwd;
}

/* License: Artistic or GPL */
int
chown(const char *path, int owner, int group)
{
    return 0;
}

/* License: Artistic or GPL */
int
rb_w32_uchown(const char *path, int owner, int group)
{
    return 0;
}

int
lchown(const char *path, int owner, int group)
{
    return 0;
}

int
rb_w32_ulchown(const char *path, int owner, int group)
{
    return 0;
}

/* License: Ruby's */
int
kill(int pid, int sig)
{
    int ret = 0;
    DWORD err;

    if (pid < 0 || (pid == 0 && sig != SIGINT)) {
	errno = EINVAL;
	return -1;
    }

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
	RUBY_CRITICAL {
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
	}
	break;

      case SIGINT:
	RUBY_CRITICAL {
	    DWORD ctrlEvent = CTRL_C_EVENT;
	    if (pid != 0) {
	        /* CTRL+C signal cannot be generated for process groups.
		 * Instead, we use CTRL+BREAK signal. */
	        ctrlEvent = CTRL_BREAK_EVENT;
	    }
	    if (!GenerateConsoleCtrlEvent(ctrlEvent, (DWORD)pid)) {
		if ((err = GetLastError()) == 0)
		    errno = EPERM;
		else
		    errno = map_errno(GetLastError());
		ret = -1;
	    }
	}
	break;

      case SIGKILL:
	RUBY_CRITICAL {
	    HANDLE hProc;
	    struct ChildRecord* child = FindChildSlot(pid);
	    if (child) {
		hProc = child->hProcess;
	    }
	    else {
		hProc = OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
	    }
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
		DWORD status;
		if (!GetExitCodeProcess(hProc, &status)) {
		    errno = map_errno(GetLastError());
		    ret = -1;
		}
		else if (status == STILL_ACTIVE) {
		    if (!TerminateProcess(hProc, 0)) {
			errno = EPERM;
			ret = -1;
		    }
		}
		else {
		    errno = ESRCH;
		    ret = -1;
		}
		if (!child) {
		    CloseHandle(hProc);
		}
	    }
	}
	break;

      default:
	errno = EINVAL;
	ret = -1;
	break;
    }

    return ret;
}

/* License: Ruby's */
static int
wlink(const WCHAR *from, const WCHAR *to)
{
    if (!CreateHardLinkW(to, from, NULL)) {
	errno = map_errno(GetLastError());
	return -1;
    }

    return 0;
}

/* License: Ruby's */
int
rb_w32_ulink(const char *from, const char *to)
{
    WCHAR *wfrom;
    WCHAR *wto;
    int ret;

    if (!(wfrom = utf8_to_wstr(from, NULL)))
	return -1;
    if (!(wto = utf8_to_wstr(to, NULL))) {
	free(wfrom);
	return -1;
    }
    ret = wlink(wfrom, wto);
    free(wto);
    free(wfrom);
    return ret;
}

/* License: Ruby's */
int
link(const char *from, const char *to)
{
    WCHAR *wfrom;
    WCHAR *wto;
    int ret;

    if (!(wfrom = filecp_to_wstr(from, NULL)))
	return -1;
    if (!(wto = filecp_to_wstr(to, NULL))) {
	free(wfrom);
	return -1;
    }
    ret = wlink(wfrom, wto);
    free(wto);
    free(wfrom);
    return ret;
}

/* License: Public Domain, copied from mingw headers */
#ifndef FILE_DEVICE_FILE_SYSTEM
# define FILE_DEVICE_FILE_SYSTEM 0x00000009
#endif
#ifndef FSCTL_GET_REPARSE_POINT
# define FSCTL_GET_REPARSE_POINT ((0x9<<16)|(42<<2))
#endif
#ifndef IO_REPARSE_TAG_SYMLINK
# define IO_REPARSE_TAG_SYMLINK 0xA000000CL
#endif

/* License: Ruby's */
static int
reparse_symlink(const WCHAR *path, rb_w32_reparse_buffer_t *rp, size_t size)
{
    HANDLE f;
    DWORD ret;
    int e = 0;

    f = open_special(path, 0, FILE_FLAG_OPEN_REPARSE_POINT);
    if (f == INVALID_HANDLE_VALUE) {
	return GetLastError();
    }

    if (!DeviceIoControl(f, FSCTL_GET_REPARSE_POINT, NULL, 0,
			   rp, size, &ret, NULL)) {
	e = GetLastError();
    }
    else if (rp->ReparseTag != IO_REPARSE_TAG_SYMLINK &&
	     rp->ReparseTag != IO_REPARSE_TAG_MOUNT_POINT) {
	e = ERROR_INVALID_PARAMETER;
    }
    CloseHandle(f);
    return e;
}

/* License: Ruby's */
int
rb_w32_reparse_symlink_p(const WCHAR *path)
{
    VALUE wtmp = 0;
    rb_w32_reparse_buffer_t rbuf, *rp = &rbuf;
    WCHAR *wbuf;
    DWORD len;
    int e;

    e = rb_w32_read_reparse_point(path, rp, sizeof(rbuf), &wbuf, &len);
    if (e == ERROR_MORE_DATA) {
	size_t size = rb_w32_reparse_buffer_size(len + 1);
	rp = ALLOCV(wtmp, size);
	e = rb_w32_read_reparse_point(path, rp, size, &wbuf, &len);
	ALLOCV_END(wtmp);
    }
    switch (e) {
      case 0:
      case ERROR_MORE_DATA:
	return TRUE;
    }
    return FALSE;
}

/* License: Ruby's */
int
rb_w32_read_reparse_point(const WCHAR *path, rb_w32_reparse_buffer_t *rp,
			  size_t bufsize, WCHAR **result, DWORD *len)
{
    int e = reparse_symlink(path, rp, bufsize);
    DWORD ret = 0;

    if (!e || e == ERROR_MORE_DATA) {
	void *name;
	if (rp->ReparseTag == IO_REPARSE_TAG_SYMLINK) {
	    name = ((char *)rp->SymbolicLinkReparseBuffer.PathBuffer +
		    rp->SymbolicLinkReparseBuffer.PrintNameOffset);
	    ret = rp->SymbolicLinkReparseBuffer.PrintNameLength;
	    *len = ret / sizeof(WCHAR);
	}
	else if (rp->ReparseTag == IO_REPARSE_TAG_MOUNT_POINT) {
	    static const WCHAR *volume = L"Volume{";
	    enum {volume_prefix_len = rb_strlen_lit("\\??\\")};
	    name = ((char *)rp->MountPointReparseBuffer.PathBuffer +
		    rp->MountPointReparseBuffer.SubstituteNameOffset +
		    volume_prefix_len * sizeof(WCHAR));
	    ret = rp->MountPointReparseBuffer.SubstituteNameLength;
	    *len = ret / sizeof(WCHAR);
	    ret -= volume_prefix_len * sizeof(WCHAR);
	    if (ret > sizeof(volume) - 1 * sizeof(WCHAR) &&
		memcmp(name, volume, sizeof(volume) - 1 * sizeof(WCHAR)) == 0)
		return -1;
	}
	else {
	    return -1;
	}
	*result = name;
	if (e) {
	    if ((char *)name + ret + sizeof(WCHAR) > (char *)rp + bufsize)
		return e;
	    /* SubstituteName is not used */
	}
	((WCHAR *)name)[ret/sizeof(WCHAR)] = L'\0';
	translate_wchar(name, L'\\', L'/');
	return 0;
    }
    else {
	return e;
    }
}

/* License: Ruby's */
static ssize_t
w32_readlink(UINT cp, const char *path, char *buf, size_t bufsize)
{
    VALUE wtmp;
    DWORD len = MultiByteToWideChar(cp, 0, path, -1, NULL, 0);
    size_t size = rb_w32_reparse_buffer_size(len);
    WCHAR *wname, *wpath = ALLOCV(wtmp, size + sizeof(WCHAR) * len);
    rb_w32_reparse_buffer_t *rp = (void *)(wpath + len);
    ssize_t ret;
    int e;

    MultiByteToWideChar(cp, 0, path, -1, wpath, len);
    e = rb_w32_read_reparse_point(wpath, rp, size, &wname, &len);
    if (e && e != ERROR_MORE_DATA) {
	ALLOCV_END(wtmp);
	errno = map_errno(e);
	return -1;
    }
    len = lstrlenW(wname) + 1;
    ret = WideCharToMultiByte(cp, 0, wname, len, buf, bufsize, NULL, NULL);
    ALLOCV_END(wtmp);
    if (e) {
	ret = bufsize;
    }
    else if (!ret) {
	e = GetLastError();
	errno = map_errno(e);
	ret = -1;
    }
    return ret;
}

/* License: Ruby's */
ssize_t
rb_w32_ureadlink(const char *path, char *buf, size_t bufsize)
{
    return w32_readlink(CP_UTF8, path, buf, bufsize);
}

/* License: Ruby's */
ssize_t
readlink(const char *path, char *buf, size_t bufsize)
{
    return w32_readlink(filecp(), path, buf, bufsize);
}

#ifndef SYMBOLIC_LINK_FLAG_DIRECTORY
#define SYMBOLIC_LINK_FLAG_DIRECTORY (0x1)
#endif
#ifndef SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
#define SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE (0x2)
#endif

/* License: Ruby's */
static int
w32_symlink(UINT cp, const char *src, const char *link)
{
    int atts, len1, len2;
    VALUE buf;
    WCHAR *wsrc, *wlink;
    DWORD flag = 0;
    BOOLEAN ret;
    int e;

    typedef BOOLEAN (WINAPI *create_symbolic_link_func)(WCHAR*, WCHAR*, DWORD);
    static create_symbolic_link_func create_symbolic_link =
	(create_symbolic_link_func)-1;
    static DWORD create_flag = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;

    if (create_symbolic_link == (create_symbolic_link_func)-1) {
	create_symbolic_link = (create_symbolic_link_func)
	    get_proc_address("kernel32", "CreateSymbolicLinkW", NULL);
    }
    if (!create_symbolic_link) {
	errno = ENOSYS;
	return -1;
    }

    if (!*link) {
        errno = ENOENT;
        return -1;
    }
    if (!*src) {
        errno = EINVAL;
        return -1;
    }
    len1 = MultiByteToWideChar(cp, 0, src, -1, NULL, 0);
    len2 = MultiByteToWideChar(cp, 0, link, -1, NULL, 0);
    wsrc = ALLOCV_N(WCHAR, buf, len1+len2);
    wlink = wsrc + len1;
    MultiByteToWideChar(cp, 0, src, -1, wsrc, len1);
    MultiByteToWideChar(cp, 0, link, -1, wlink, len2);
    translate_wchar(wsrc, L'/', L'\\');

    atts = GetFileAttributesW(wsrc);
    if (atts != -1 && atts & FILE_ATTRIBUTE_DIRECTORY)
	flag = SYMBOLIC_LINK_FLAG_DIRECTORY;
    ret = create_symbolic_link(wlink, wsrc, flag |= create_flag);
    if (!ret &&
        (e = GetLastError()) == ERROR_INVALID_PARAMETER &&
        (flag & SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)) {
        create_flag = 0;
        flag &= ~SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
        ret = create_symbolic_link(wlink, wsrc, flag);
        if (!ret) e = GetLastError();
    }
    ALLOCV_END(buf);

    if (!ret) {
	errno = map_errno(e);
	return -1;
    }
    return 0;
}

/* License: Ruby's */
int
rb_w32_usymlink(const char *src, const char *link)
{
    return w32_symlink(CP_UTF8, src, link);
}

/* License: Ruby's */
int
symlink(const char *src, const char *link)
{
    return w32_symlink(filecp(), src, link);
}

/* License: Ruby's */
int
wait(int *status)
{
    return waitpid(-1, status, 0);
}

/* License: Ruby's */
static char *
w32_getenv(const char *name, UINT cp)
{
    WCHAR *wenvarea, *wenv;
    int len = strlen(name);
    char *env;
    int wlen;

    if (len == 0) return NULL;

    if (uenvarea) {
	free(uenvarea);
	uenvarea = NULL;
    }
    wenvarea = GetEnvironmentStringsW();
    if (!wenvarea) {
	map_errno(GetLastError());
	return NULL;
    }
    for (wenv = wenvarea, wlen = 1; *wenv; wenv += lstrlenW(wenv) + 1)
	wlen += lstrlenW(wenv) + 1;
    uenvarea = wstr_to_mbstr(cp, wenvarea, wlen, NULL);
    FreeEnvironmentStringsW(wenvarea);
    if (!uenvarea)
	return NULL;

    for (env = uenvarea; *env; env += strlen(env) + 1)
	if (strncasecmp(env, name, len) == 0 && *(env + len) == '=')
	    return env + len + 1;

    return NULL;
}

/* License: Ruby's */
char *
rb_w32_ugetenv(const char *name)
{
    return w32_getenv(name, CP_UTF8);
}

/* License: Ruby's */
char *
rb_w32_getenv(const char *name)
{
    return w32_getenv(name, CP_ACP);
}

/* License: Ruby's */
static DWORD
get_attr_vsn(const WCHAR *path, DWORD *atts, DWORD *vsn)
{
    BY_HANDLE_FILE_INFORMATION st = {0};
    DWORD e = 0;
    HANDLE h = open_special(path, 0, FILE_FLAG_OPEN_REPARSE_POINT);

    if (h == INVALID_HANDLE_VALUE) {
	ASSUME(e = GetLastError());
	return e;
    }
    if (!GetFileInformationByHandle(h, &st)) {
	ASSUME(e = GetLastError());
    }
    else {
	*atts = st.dwFileAttributes;
	*vsn = st.dwVolumeSerialNumber;
    }
    CloseHandle(h);
    return e;
}

/* License: Artistic or GPL */
static int
wrename(const WCHAR *oldpath, const WCHAR *newpath)
{
    int res = 0;
    DWORD oldatts, newatts = (DWORD)-1;
    DWORD oldvsn = 0, newvsn = 0, e;

    e = get_attr_vsn(oldpath, &oldatts, &oldvsn);
    if (e) {
	errno = map_errno(e);
	return -1;
    }
    if (oldatts & FILE_ATTRIBUTE_REPARSE_POINT) {
	HANDLE fh = open_special(oldpath, 0, 0);
	if (fh == INVALID_HANDLE_VALUE) {
	    e = GetLastError();
	    if (e == ERROR_CANT_RESOLVE_FILENAME) {
		errno = ELOOP;
		return -1;
	    }
	}
	CloseHandle(fh);
    }
    get_attr_vsn(newpath, &newatts, &newvsn);

    RUBY_CRITICAL {
	if (newatts != (DWORD)-1 && newatts & FILE_ATTRIBUTE_READONLY)
	    SetFileAttributesW(newpath, newatts & ~ FILE_ATTRIBUTE_READONLY);

	if (!MoveFileExW(oldpath, newpath, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED))
	    res = -1;

	if (res) {
	    DWORD e = GetLastError();
	    if ((e == ERROR_ACCESS_DENIED) && (oldatts & FILE_ATTRIBUTE_DIRECTORY) &&
		oldvsn != newvsn)
		errno = EXDEV;
	    else
		errno = map_errno(e);
	}
	else
	    SetFileAttributesW(newpath, oldatts);
    }

    return res;
}

/* License: Ruby's */
int rb_w32_urename(const char *from, const char *to)
{
    WCHAR *wfrom;
    WCHAR *wto;
    int ret = -1;

    if (!(wfrom = utf8_to_wstr(from, NULL)))
	return -1;
    if (!(wto = utf8_to_wstr(to, NULL))) {
	free(wfrom);
	return -1;
    }
    ret = wrename(wfrom, wto);
    free(wto);
    free(wfrom);
    return ret;
}

/* License: Ruby's */
int rb_w32_rename(const char *from, const char *to)
{
    WCHAR *wfrom;
    WCHAR *wto;
    int ret = -1;

    if (!(wfrom = filecp_to_wstr(from, NULL)))
	return -1;
    if (!(wto = filecp_to_wstr(to, NULL))) {
	free(wfrom);
	return -1;
    }
    ret = wrename(wfrom, wto);
    free(wto);
    free(wfrom);
    return ret;
}

/* License: Ruby's */
static int
isUNCRoot(const WCHAR *path)
{
    if (path[0] == L'\\' && path[1] == L'\\') {
	const WCHAR *p = path + 2;
	if (p[0] == L'?' && p[1] == L'\\') {
	    p += 2;
	}
	for (; *p; p++) {
	    if (*p == L'\\')
		break;
	}
	if (p[0] && p[1]) {
	    for (p++; *p; p++) {
		if (*p == L'\\')
		    break;
	    }
	    if (!p[0] || !p[1] || (p[1] == L'.' && !p[2]))
		return 1;
	}
    }
    return 0;
}

#define COPY_STAT(src, dest, size_cast) do {	\
	(dest).st_dev 	= (src).st_dev;		\
	(dest).st_ino 	= (src).st_ino;		\
	(dest).st_mode  = (src).st_mode;	\
	(dest).st_nlink = (src).st_nlink;	\
	(dest).st_uid   = (src).st_uid;		\
	(dest).st_gid   = (src).st_gid;		\
	(dest).st_rdev 	= (src).st_rdev;	\
	(dest).st_size 	= size_cast(src).st_size; \
	(dest).st_atime = (src).st_atime;	\
	(dest).st_mtime = (src).st_mtime;	\
	(dest).st_ctime = (src).st_ctime;	\
    } while (0)

static time_t filetime_to_unixtime(const FILETIME *ft);
static long filetime_to_nsec(const FILETIME *ft);
static WCHAR *name_for_stat(WCHAR *buf, const WCHAR *path);
static DWORD stati128_handle(HANDLE h, struct stati128 *st);

#undef fstat
/* License: Ruby's */
int
rb_w32_fstat(int fd, struct stat *st)
{
    BY_HANDLE_FILE_INFORMATION info;
    int ret = fstat(fd, st);

    if (ret) return ret;
    if (GetEnvironmentVariableW(L"TZ", NULL, 0) == 0 && GetLastError() == ERROR_ENVVAR_NOT_FOUND) return ret;
    if (GetFileInformationByHandle((HANDLE)_get_osfhandle(fd), &info)) {
	st->st_atime = filetime_to_unixtime(&info.ftLastAccessTime);
	st->st_mtime = filetime_to_unixtime(&info.ftLastWriteTime);
	st->st_ctime = filetime_to_unixtime(&info.ftCreationTime);
    }
    return ret;
}

/* License: Ruby's */
int
rb_w32_fstati128(int fd, struct stati128 *st)
{
    struct stat tmp;
    int ret = fstat(fd, &tmp);

    if (ret) return ret;
    COPY_STAT(tmp, *st, +);
    stati128_handle((HANDLE)_get_osfhandle(fd), st);
    return ret;
}

#if !defined FILE_INVALID_FILE_ID && !defined __MINGW32__
typedef struct {
    BYTE  Identifier[16];
} FILE_ID_128;
#endif

#if !defined(_WIN32_WINNT_WIN8) || _WIN32_WINNT < 0x602
#define FileIdInfo 0x12

typedef struct {
    unsigned LONG_LONG VolumeSerialNumber;
    FILE_ID_128 FileId;
} FILE_ID_INFO;
#endif

static DWORD
get_ino(HANDLE h, FILE_ID_INFO *id)
{
    typedef BOOL (WINAPI *gfibhe_t)(HANDLE, int, void *, DWORD);
    static gfibhe_t pGetFileInformationByHandleEx = (gfibhe_t)-1;

    if (pGetFileInformationByHandleEx == (gfibhe_t)-1)
	pGetFileInformationByHandleEx = (gfibhe_t)get_proc_address("kernel32", "GetFileInformationByHandleEx", NULL);

    if (pGetFileInformationByHandleEx) {
	if (pGetFileInformationByHandleEx(h, FileIdInfo, id, sizeof(*id)))
	    return 0;
	else
	    return GetLastError();
    }
    return ERROR_INVALID_PARAMETER;
}

/* License: Ruby's */
static DWORD
stati128_handle(HANDLE h, struct stati128 *st)
{
    BY_HANDLE_FILE_INFORMATION info;
    DWORD attr = (DWORD)-1;

    if (GetFileInformationByHandle(h, &info)) {
	FILE_ID_INFO fii;
	st->st_size = ((__int64)info.nFileSizeHigh << 32) | info.nFileSizeLow;
	st->st_atime = filetime_to_unixtime(&info.ftLastAccessTime);
	st->st_atimensec = filetime_to_nsec(&info.ftLastAccessTime);
	st->st_mtime = filetime_to_unixtime(&info.ftLastWriteTime);
	st->st_mtimensec = filetime_to_nsec(&info.ftLastWriteTime);
	st->st_ctime = filetime_to_unixtime(&info.ftCreationTime);
	st->st_ctimensec = filetime_to_nsec(&info.ftCreationTime);
	st->st_nlink = info.nNumberOfLinks;
	attr = info.dwFileAttributes;
	if (!get_ino(h, &fii)) {
	    st->st_ino = *((unsigned __int64 *)&fii.FileId);
	    st->st_inohigh = *((__int64 *)&fii.FileId + 1);
	}
	else {
	    st->st_ino = ((__int64)info.nFileIndexHigh << 32) | info.nFileIndexLow;
	    st->st_inohigh = 0;
	}
    }
    return attr;
}

/* License: Ruby's */
static time_t
filetime_to_unixtime(const FILETIME *ft)
{
    long subsec;
    time_t t = filetime_split(ft, &subsec);

    if (t < 0) return 0;
    return t;
}

/* License: Ruby's */
static long
filetime_to_nsec(const FILETIME *ft)
{
    if (have_precisetime <= 0)
	return 0;
    else {
	ULARGE_INTEGER tmp;
	tmp.LowPart = ft->dwLowDateTime;
	tmp.HighPart = ft->dwHighDateTime;
	return (long)(tmp.QuadPart % 10000000) * 100;
    }
}

/* License: Ruby's */
static unsigned
fileattr_to_unixmode(DWORD attr, const WCHAR *path)
{
    unsigned mode = 0;

    if (attr & FILE_ATTRIBUTE_READONLY) {
	mode |= S_IREAD;
    }
    else {
	mode |= S_IREAD | S_IWRITE | S_IWUSR;
    }

    if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {
	if (rb_w32_reparse_symlink_p(path))
	    mode |= S_IFLNK | S_IEXEC;
	else
	    mode |= S_IFDIR | S_IEXEC;
    }
    else if (attr & FILE_ATTRIBUTE_DIRECTORY) {
	mode |= S_IFDIR | S_IEXEC;
    }
    else {
	mode |= S_IFREG;
    }

    if (path && (mode & S_IFREG)) {
	const WCHAR *end = path + lstrlenW(path);
	while (path < end) {
	    end = CharPrevW(path, end);
	    if (*end == L'.') {
		if ((_wcsicmp(end, L".bat") == 0) ||
		    (_wcsicmp(end, L".cmd") == 0) ||
		    (_wcsicmp(end, L".com") == 0) ||
		    (_wcsicmp(end, L".exe") == 0)) {
		    mode |= S_IEXEC;
		}
		break;
	    }
	    if (!iswalnum(*end)) break;
	}
    }

    mode |= (mode & 0500) >> 3;
    mode |= (mode & 0500) >> 6;

    return mode;
}

/* License: Ruby's */
static int
check_valid_dir(const WCHAR *path)
{
    WIN32_FIND_DATAW fd;
    HANDLE fh;
    WCHAR full[PATH_MAX];
    WCHAR *dmy;
    WCHAR *p, *q;

    /* GetFileAttributes() determines "..." as directory. */
    /* We recheck it by FindFirstFile(). */
    if (!(p = wcsstr(path, L"...")))
	return 0;
    q = p + wcsspn(p, L".");
    if ((p == path || wcschr(L":/\\", *(p - 1))) &&
	(!*q || wcschr(L":/\\", *q))) {
	errno = ENOENT;
	return -1;
    }

    /* if the specified path is the root of a drive and the drive is empty, */
    /* FindFirstFile() returns INVALID_HANDLE_VALUE. */
    if (!GetFullPathNameW(path, sizeof(full) / sizeof(WCHAR), full, &dmy)) {
	errno = map_errno(GetLastError());
	return -1;
    }
    if (full[1] == L':' && !full[3] && GetDriveTypeW(full) != DRIVE_NO_ROOT_DIR)
	return 0;

    fh = open_dir_handle(path, &fd);
    if (fh == INVALID_HANDLE_VALUE)
	return -1;
    FindClose(fh);
    return 0;
}

/* License: Ruby's */
static int
stat_by_find(const WCHAR *path, struct stati128 *st)
{
    HANDLE h;
    WIN32_FIND_DATAW wfd;
    /* GetFileAttributesEx failed; check why. */
    int e = GetLastError();

    if ((e == ERROR_FILE_NOT_FOUND) || (e == ERROR_INVALID_NAME)
	|| (e == ERROR_PATH_NOT_FOUND || (e == ERROR_BAD_NETPATH))) {
	errno = map_errno(e);
	return -1;
    }

    /* Fall back to FindFirstFile for ERROR_SHARING_VIOLATION */
    h = FindFirstFileW(path, &wfd);
    if (h == INVALID_HANDLE_VALUE) {
	errno = map_errno(GetLastError());
	return -1;
    }
    FindClose(h);
    st->st_mode  = fileattr_to_unixmode(wfd.dwFileAttributes, path);
    st->st_atime = filetime_to_unixtime(&wfd.ftLastAccessTime);
    st->st_atimensec = filetime_to_nsec(&wfd.ftLastAccessTime);
    st->st_mtime = filetime_to_unixtime(&wfd.ftLastWriteTime);
    st->st_mtimensec = filetime_to_nsec(&wfd.ftLastWriteTime);
    st->st_ctime = filetime_to_unixtime(&wfd.ftCreationTime);
    st->st_ctimensec = filetime_to_nsec(&wfd.ftCreationTime);
    st->st_size = ((__int64)wfd.nFileSizeHigh << 32) | wfd.nFileSizeLow;
    st->st_nlink = 1;
    return 0;
}

/* License: Ruby's */
static int
path_drive(const WCHAR *path)
{
    return (iswalpha(path[0]) && path[1] == L':') ?
	towupper(path[0]) - L'A' : _getdrive() - 1;
}

static const WCHAR namespace_prefix[] = {L'\\', L'\\', L'?', L'\\'};

/* License: Ruby's */
static int
winnt_stat(const WCHAR *path, struct stati128 *st, BOOL lstat)
{
    DWORD flags = lstat ? FILE_FLAG_OPEN_REPARSE_POINT : 0;
    HANDLE f;
    WCHAR finalname[PATH_MAX];

    memset(st, 0, sizeof(*st));
    f = open_special(path, 0, flags);
    if (f != INVALID_HANDLE_VALUE) {
	DWORD attr = stati128_handle(f, st);
	const DWORD len = get_final_path(f, finalname, numberof(finalname), 0);
	CloseHandle(f);
	if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {
	    /* TODO: size in which encoding? */
	    if (rb_w32_reparse_symlink_p(path))
		st->st_size = 0;
	    else
		attr &= ~FILE_ATTRIBUTE_REPARSE_POINT;
	}
	if (attr & FILE_ATTRIBUTE_DIRECTORY) {
	    if (check_valid_dir(path)) return -1;
	}
	st->st_mode = fileattr_to_unixmode(attr, path);
	if (len) {
	    finalname[min(len, numberof(finalname)-1)] = L'\0';
	    path = finalname;
	    if (wcsncmp(path, namespace_prefix, numberof(namespace_prefix)) == 0)
		path += numberof(namespace_prefix);
	}
    }
    else {
	if (stat_by_find(path, st)) return -1;
    }

    st->st_dev = st->st_rdev = path_drive(path);

    return 0;
}

/* License: Ruby's */
int
rb_w32_stat(const char *path, struct stat *st)
{
    struct stati128 tmp;

    if (rb_w32_stati128(path, &tmp)) return -1;
    COPY_STAT(tmp, *st, (_off_t));
    return 0;
}

/* License: Ruby's */
static int
wstati128(const WCHAR *path, struct stati128 *st, BOOL lstat)
{
    WCHAR *buf1;
    int ret, size;
    VALUE v;

    if (!path || !st) {
	errno = EFAULT;
	return -1;
    }
    size = lstrlenW(path) + 2;
    buf1 = ALLOCV_N(WCHAR, v, size);
    if (!(path = name_for_stat(buf1, path)))
	return -1;
    ret = winnt_stat(path, st, lstat);
    if (v)
	ALLOCV_END(v);

    return ret;
}

/* License: Ruby's */
static WCHAR *
name_for_stat(WCHAR *buf1, const WCHAR *path)
{
    const WCHAR *p;
    WCHAR *s, *end;
    int len;

    for (p = path, s = buf1; *p; p++, s++) {
	if (*p == L'/')
	    *s = L'\\';
	else
	    *s = *p;
    }
    *s = '\0';
    len = s - buf1;
    if (!len || L'\"' == *(--s)) {
	errno = ENOENT;
	return NULL;
    }
    end = buf1 + len - 1;

    if (isUNCRoot(buf1)) {
	if (*end == L'.')
	    *end = L'\0';
	else if (*end != L'\\')
	    lstrcatW(buf1, L"\\");
    }
    else if (*end == L'\\' || (buf1 + 1 == end && *end == L':'))
	lstrcatW(buf1, L".");

    return buf1;
}

/* License: Ruby's */
int
rb_w32_ustati128(const char *path, struct stati128 *st)
{
    return w32_stati128(path, st, CP_UTF8, FALSE);
}

/* License: Ruby's */
int
rb_w32_stati128(const char *path, struct stati128 *st)
{
    return w32_stati128(path, st, filecp(), FALSE);
}

/* License: Ruby's */
static int
w32_stati128(const char *path, struct stati128 *st, UINT cp, BOOL lstat)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = mbstr_to_wstr(cp, path, -1, NULL)))
	return -1;
    ret = wstati128(wpath, st, lstat);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_ulstati128(const char *path, struct stati128 *st)
{
    return w32_stati128(path, st, CP_UTF8, TRUE);
}

/* License: Ruby's */
int
rb_w32_lstati128(const char *path, struct stati128 *st)
{
    return w32_stati128(path, st, filecp(), TRUE);
}

/* License: Ruby's */
off_t
rb_w32_lseek(int fd, off_t ofs, int whence)
{
    SOCKET sock = TO_SOCKET(fd);
    if (is_socket(sock) || is_pipe(sock)) {
        errno = ESPIPE;
        return -1;
    }
    return _lseeki64(fd, ofs, whence);
}

/* License: Ruby's */
int
rb_w32_access(const char *path, int mode)
{
    struct stati128 stat;
    if (rb_w32_stati128(path, &stat) != 0)
	return -1;
    mode <<= 6;
    if ((stat.st_mode & mode) != mode) {
	errno = EACCES;
	return -1;
    }
    return 0;
}

/* License: Ruby's */
int
rb_w32_uaccess(const char *path, int mode)
{
    struct stati128 stat;
    if (rb_w32_ustati128(path, &stat) != 0)
	return -1;
    mode <<= 6;
    if ((stat.st_mode & mode) != mode) {
	errno = EACCES;
	return -1;
    }
    return 0;
}

/* License: Ruby's */
static int
rb_chsize(HANDLE h, off_t size)
{
    long upos, lpos, usize, lsize;
    int ret = -1;
    DWORD e;

    if ((lpos = SetFilePointer(h, 0, (upos = 0, &upos), SEEK_CUR)) == -1L &&
	(e = GetLastError())) {
	errno = map_errno(e);
	return -1;
    }
    usize = (long)(size >> 32);
    lsize = (long)size;
    if (SetFilePointer(h, lsize, &usize, SEEK_SET) == (DWORD)-1L &&
	(e = GetLastError())) {
	errno = map_errno(e);
    }
    else if (!SetEndOfFile(h)) {
	errno = map_errno(GetLastError());
    }
    else {
	ret = 0;
    }
    SetFilePointer(h, lpos, &upos, SEEK_SET);
    return ret;
}

/* License: Ruby's */
static int
w32_truncate(const char *path, off_t length, UINT cp)
{
    HANDLE h;
    int ret;
    WCHAR *wpath;

    if (!(wpath = mbstr_to_wstr(cp, path, -1, NULL)))
	return -1;
    h = CreateFileW(wpath, GENERIC_WRITE, 0, 0, OPEN_EXISTING, 0, 0);
    if (h == INVALID_HANDLE_VALUE) {
	errno = map_errno(GetLastError());
	free(wpath);
	return -1;
    }
    free(wpath);
    ret = rb_chsize(h, length);
    CloseHandle(h);
    return ret;
}

/* License: Ruby's */
int
rb_w32_utruncate(const char *path, off_t length)
{
    return w32_truncate(path, length, CP_UTF8);
}

/* License: Ruby's */
int
rb_w32_truncate(const char *path, off_t length)
{
    return w32_truncate(path, length, filecp());
}

/* License: Ruby's */
int
rb_w32_ftruncate(int fd, off_t length)
{
    HANDLE h;

    h = (HANDLE)_get_osfhandle(fd);
    if (h == (HANDLE)-1) return -1;
    return rb_chsize(h, length);
}

/* License: Ruby's */
static long
filetime_to_clock(FILETIME *ft)
{
    __int64 qw = ft->dwHighDateTime;
    qw <<= 32;
    qw |= ft->dwLowDateTime;
    qw /= 10000;  /* File time ticks at 0.1uS, clock at 1mS */
    return (long) qw;
}

/* License: Ruby's */
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


/* License: Ruby's */
#define yield_once() Sleep(0)
#define yield_until(condition) do yield_once(); while (!(condition))

/* License: Ruby's */
struct asynchronous_arg_t {
    /* output field */
    void* stackaddr;
    int errnum;

    /* input field */
    uintptr_t (*func)(uintptr_t self, int argc, uintptr_t* argv);
    uintptr_t self;
    int argc;
    uintptr_t* argv;
};

/* License: Ruby's */
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

/* License: Ruby's */
uintptr_t
rb_w32_asynchronize(asynchronous_func_t func, uintptr_t self,
		    int argc, uintptr_t* argv, uintptr_t intrval)
{
    DWORD val;
    BOOL interrupted = FALSE;
    HANDLE thr;

    RUBY_CRITICAL {
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

	    if (rb_w32_wait_events_blocking(&thr, 1, INFINITE) != WAIT_OBJECT_0) {
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
    }

    if (!thr) {
	rb_fatal("failed to launch waiter thread:%ld", GetLastError());
    }

    return val;
}

/* License: Ruby's */
char **
rb_w32_get_environ(void)
{
    WCHAR *envtop, *env;
    char **myenvtop, **myenv;
    int num;

    /*
     * We avoid values started with `='. If you want to deal those values,
     * change this function, and some functions in hash.c which recognize
     * `=' as delimiter or rb_w32_getenv() and ruby_setenv().
     * CygWin deals these values by changing first `=' to '!'. But we don't
     * use such trick and follow cmd.exe's way that just doesn't show these
     * values.
     *
     * This function returns UTF-8 strings.
     */
    envtop = GetEnvironmentStringsW();
    for (env = envtop, num = 0; *env; env += lstrlenW(env) + 1)
	if (*env != '=') num++;

    myenvtop = (char **)malloc(sizeof(char *) * (num + 1));
    for (env = envtop, myenv = myenvtop; *env; env += lstrlenW(env) + 1) {
	if (*env != '=') {
	    if (!(*myenv = wstr_to_utf8(env, NULL))) {
		break;
	    }
	    myenv++;
	}
    }
    *myenv = NULL;
    FreeEnvironmentStringsW(envtop);

    return myenvtop;
}

/* License: Ruby's */
void
rb_w32_free_environ(char **env)
{
    char **t = env;

    while (*t) free(*t++);
    free(env);
}

/* License: Ruby's */
rb_pid_t
rb_w32_getpid(void)
{
    return GetCurrentProcessId();
}


/* License: Ruby's */
rb_pid_t
rb_w32_getppid(void)
{
    typedef long (WINAPI query_func)(HANDLE, int, void *, ULONG, ULONG *);
    static query_func *pNtQueryInformationProcess = (query_func *)-1;
    rb_pid_t ppid = 0;

    if (pNtQueryInformationProcess == (query_func *)-1)
	pNtQueryInformationProcess = (query_func *)get_proc_address("ntdll.dll", "NtQueryInformationProcess", NULL);
    if (pNtQueryInformationProcess) {
	struct {
	    long ExitStatus;
	    void* PebBaseAddress;
	    uintptr_t AffinityMask;
	    uintptr_t BasePriority;
	    uintptr_t UniqueProcessId;
	    uintptr_t ParentProcessId;
	} pbi;
	ULONG len;
	long ret = pNtQueryInformationProcess(GetCurrentProcess(), 0, &pbi, sizeof(pbi), &len);
	if (!ret) {
	    ppid = pbi.ParentProcessId;
	}
    }

    return ppid;
}

STATIC_ASSERT(std_handle, (STD_OUTPUT_HANDLE-STD_INPUT_HANDLE)==(STD_ERROR_HANDLE-STD_OUTPUT_HANDLE));

/* License: Ruby's */
#define set_new_std_handle(newfd, handle) do { \
	if ((unsigned)(newfd) > 2) break; \
	SetStdHandle(STD_INPUT_HANDLE+(STD_OUTPUT_HANDLE-STD_INPUT_HANDLE)*(newfd), \
		     (handle)); \
    } while (0)
#define set_new_std_fd(newfd) set_new_std_handle(newfd, (HANDLE)rb_w32_get_osfhandle(newfd))

/* License: Ruby's */
int
rb_w32_dup2(int oldfd, int newfd)
{
    int ret;

    if (oldfd == newfd) return newfd;
    ret = dup2(oldfd, newfd);
    if (ret < 0) return ret;
    set_new_std_fd(newfd);
    return newfd;
}

/* License: Ruby's */
int
rb_w32_uopen(const char *file, int oflag, ...)
{
    WCHAR *wfile;
    int ret;
    int pmode;

    va_list arg;
    va_start(arg, oflag);
    pmode = va_arg(arg, int);
    va_end(arg);

    if (!(wfile = utf8_to_wstr(file, NULL)))
	return -1;
    ret = w32_wopen(wfile, oflag, pmode);
    free(wfile);
    return ret;
}

/* License: Ruby's */
static int
check_if_wdir(const WCHAR *wfile)
{
    DWORD attr = GetFileAttributesW(wfile);
    if (attr == (DWORD)-1L ||
	!(attr & FILE_ATTRIBUTE_DIRECTORY) ||
	check_valid_dir(wfile)) {
	return FALSE;
    }
    errno = EISDIR;
    return TRUE;
}

/* License: Ruby's */
int
rb_w32_open(const char *file, int oflag, ...)
{
    WCHAR *wfile;
    int ret;
    int pmode;

    va_list arg;
    va_start(arg, oflag);
    pmode = va_arg(arg, int);
    va_end(arg);

    if (!(wfile = filecp_to_wstr(file, NULL)))
	return -1;
    ret = w32_wopen(wfile, oflag, pmode);
    free(wfile);
    return ret;
}

/* License: Ruby's */
int
rb_w32_wopen(const WCHAR *file, int oflag, ...)
{
    int pmode = 0;

    if (oflag & O_CREAT) {
	va_list arg;
	va_start(arg, oflag);
	pmode = va_arg(arg, int);
	va_end(arg);
    }

    return w32_wopen(file, oflag, pmode);
}

static int
w32_wopen(const WCHAR *file, int oflag, int pmode)
{
    char flags = 0;
    int fd;
    DWORD access;
    DWORD create;
    DWORD attr = FILE_ATTRIBUTE_NORMAL;
    SECURITY_ATTRIBUTES sec;
    HANDLE h;
    int share_delete;

    share_delete = oflag & O_SHARE_DELETE ? FILE_SHARE_DELETE : 0;
    oflag &= ~O_SHARE_DELETE;
    if ((oflag & O_TEXT) || !(oflag & O_BINARY)) {
	fd = _wopen(file, oflag, pmode);
	if (fd == -1) {
	    switch (errno) {
	      case EACCES:
		check_if_wdir(file);
		break;
	      case EINVAL:
		errno = map_errno(GetLastError());
		break;
	    }
	}
	return fd;
    }

    sec.nLength = sizeof(sec);
    sec.lpSecurityDescriptor = NULL;
    if (oflag & O_NOINHERIT) {
	sec.bInheritHandle = FALSE;
	flags |= FNOINHERIT;
    }
    else {
	sec.bInheritHandle = TRUE;
    }
    oflag &= ~O_NOINHERIT;

    /* always open with binary mode */
    oflag &= ~(O_BINARY | O_TEXT);

    switch (oflag & (O_RDWR | O_RDONLY | O_WRONLY)) {
      case O_RDWR:
	access = GENERIC_READ | GENERIC_WRITE;
	break;
      case O_RDONLY:
	access = GENERIC_READ;
	break;
      case O_WRONLY:
	access = GENERIC_WRITE;
	break;
      default:
	errno = EINVAL;
	return -1;
    }
    oflag &= ~(O_RDWR | O_RDONLY | O_WRONLY);

    switch (oflag & (O_CREAT | O_EXCL | O_TRUNC)) {
      case O_CREAT:
	create = OPEN_ALWAYS;
	break;
      case 0:
      case O_EXCL:
	create = OPEN_EXISTING;
	break;
      case O_CREAT | O_EXCL:
      case O_CREAT | O_EXCL | O_TRUNC:
	create = CREATE_NEW;
	break;
      case O_TRUNC:
      case O_TRUNC | O_EXCL:
	create = TRUNCATE_EXISTING;
	break;
      case O_CREAT | O_TRUNC:
	create = CREATE_ALWAYS;
	break;
      default:
	errno = EINVAL;
	return -1;
    }
    if (oflag & O_CREAT) {
	/* TODO: we need to check umask here, but it's not exported... */
	if (!(pmode & S_IWRITE))
	    attr = FILE_ATTRIBUTE_READONLY;
    }
    oflag &= ~(O_CREAT | O_EXCL | O_TRUNC);

    if (oflag & O_TEMPORARY) {
	attr |= FILE_FLAG_DELETE_ON_CLOSE;
	access |= DELETE;
    }
    oflag &= ~O_TEMPORARY;

    if (oflag & _O_SHORT_LIVED)
	attr |= FILE_ATTRIBUTE_TEMPORARY;
    oflag &= ~_O_SHORT_LIVED;

    switch (oflag & (O_SEQUENTIAL | O_RANDOM)) {
      case 0:
	break;
      case O_SEQUENTIAL:
	attr |= FILE_FLAG_SEQUENTIAL_SCAN;
	break;
      case O_RANDOM:
	attr |= FILE_FLAG_RANDOM_ACCESS;
	break;
      default:
	errno = EINVAL;
	return -1;
    }
    oflag &= ~(O_SEQUENTIAL | O_RANDOM);

    if (oflag & ~O_APPEND) {
	errno = EINVAL;
	return -1;
    }

    /* allocate a C Runtime file handle */
    RUBY_CRITICAL {
	h = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
	fd = _open_osfhandle((intptr_t)h, 0);
	CloseHandle(h);
    }
    if (fd == -1) {
	errno = EMFILE;
	return -1;
    }
    RUBY_CRITICAL {
	rb_acrt_lowio_lock_fh(fd);
	_set_osfhnd(fd, (intptr_t)INVALID_HANDLE_VALUE);
	_set_osflags(fd, 0);

	h = CreateFileW(file, access, FILE_SHARE_READ | FILE_SHARE_WRITE | share_delete, &sec, create, attr, NULL);
	if (h == INVALID_HANDLE_VALUE) {
	    DWORD e = GetLastError();
	    if (e != ERROR_ACCESS_DENIED || !check_if_wdir(file))
		errno = map_errno(e);
	    rb_acrt_lowio_unlock_fh(fd);
	    fd = -1;
	    goto quit;
	}

	switch (GetFileType(h)) {
	  case FILE_TYPE_CHAR:
	    flags |= FDEV;
	    break;
	  case FILE_TYPE_PIPE:
	    flags |= FPIPE;
	    break;
	  case FILE_TYPE_UNKNOWN:
	    errno = map_errno(GetLastError());
	    CloseHandle(h);
	    rb_acrt_lowio_unlock_fh(fd);
	    fd = -1;
	    goto quit;
	}
	if (!(flags & (FDEV | FPIPE)) && (oflag & O_APPEND))
	    flags |= FAPPEND;

	_set_osfhnd(fd, (intptr_t)h);
	_set_osflags(fd, flags | FOPEN);

	rb_acrt_lowio_unlock_fh(fd);
      quit:
	;
    }

    return fd;
}

/* License: Ruby's */
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

/* License: Ruby's */
int
rb_w32_pipe(int fds[2])
{
    static DWORD serial = 0;
    static const char prefix[] = "\\\\.\\pipe\\ruby";
    enum {
	width_of_prefix = (int)sizeof(prefix) - 1,
	width_of_pid = (int)sizeof(rb_pid_t) * 2,
	width_of_serial = (int)sizeof(serial) * 2,
	width_of_ids = width_of_pid + 1 + width_of_serial + 1
    };
    char name[sizeof(prefix) + width_of_ids];
    SECURITY_ATTRIBUTES sec;
    HANDLE hRead, hWrite, h;
    int fdRead, fdWrite;
    int ret;

    memcpy(name, prefix, width_of_prefix);
    snprintf(name + width_of_prefix, width_of_ids, "%.*"PRI_PIDT_PREFIX"x-%.*lx",
	     width_of_pid, rb_w32_getpid(), width_of_serial, serial++);

    sec.nLength = sizeof(sec);
    sec.lpSecurityDescriptor = NULL;
    sec.bInheritHandle = FALSE;

    RUBY_CRITICAL {
	hRead = CreateNamedPipe(name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
				0, 2, 65536, 65536, 0, &sec);
    }
    if (hRead == INVALID_HANDLE_VALUE) {
	DWORD err = GetLastError();
	if (err == ERROR_PIPE_BUSY)
	    errno = EMFILE;
	else
	    errno = map_errno(GetLastError());
	return -1;
    }

    RUBY_CRITICAL {
	hWrite = CreateFile(name, GENERIC_READ | GENERIC_WRITE, 0, &sec,
			    OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
    }
    if (hWrite == INVALID_HANDLE_VALUE) {
	errno = map_errno(GetLastError());
	CloseHandle(hRead);
	return -1;
    }

    RUBY_CRITICAL do {
	ret = 0;
	h = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
	fdRead = _open_osfhandle((intptr_t)h, 0);
	CloseHandle(h);
	if (fdRead == -1) {
	    errno = EMFILE;
	    CloseHandle(hWrite);
	    CloseHandle(hRead);
	    ret = -1;
	    break;
	}

	rb_acrt_lowio_lock_fh(fdRead);
	_set_osfhnd(fdRead, (intptr_t)hRead);
	_set_osflags(fdRead, FOPEN | FPIPE | FNOINHERIT);
	rb_acrt_lowio_unlock_fh(fdRead);
    } while (0);
    if (ret)
	return ret;

    RUBY_CRITICAL do {
	h = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
	fdWrite = _open_osfhandle((intptr_t)h, 0);
	CloseHandle(h);
	if (fdWrite == -1) {
	    errno = EMFILE;
	    CloseHandle(hWrite);
	    ret = -1;
	    break;
	}
	rb_acrt_lowio_lock_fh(fdWrite);
	_set_osfhnd(fdWrite, (intptr_t)hWrite);
	_set_osflags(fdWrite, FOPEN | FPIPE | FNOINHERIT);
	rb_acrt_lowio_unlock_fh(fdWrite);
    } while (0);
    if (ret) {
	rb_w32_close(fdRead);
	return ret;
    }

    fds[0] = fdRead;
    fds[1] = fdWrite;

    return 0;
}

/* License: Ruby's */
static int
console_emulator_p(void)
{
#ifdef _WIN32_WCE
    return FALSE;
#else
    const void *const func = WriteConsoleW;
    HMODULE k;
    MEMORY_BASIC_INFORMATION m;

    memset(&m, 0, sizeof(m));
    if (!VirtualQuery(func, &m, sizeof(m))) {
	return FALSE;
    }
    k = GetModuleHandle("kernel32.dll");
    if (!k) return FALSE;
    return (HMODULE)m.AllocationBase != k;
#endif
}

/* License: Ruby's */
static struct constat *
constat_handle(HANDLE h)
{
    st_data_t data;
    struct constat *p;

    EnterCriticalSection(&conlist_mutex);
    if (!conlist) {
	if (console_emulator_p()) {
	    conlist = conlist_disabled;
	} else {
	    conlist = st_init_numtable();
	    install_vm_exit_handler();
	}
    }
    if (conlist != conlist_disabled) {
	if (st_lookup(conlist, (st_data_t)h, &data)) {
	    p = (struct constat *)data;
	} else {
	    CONSOLE_SCREEN_BUFFER_INFO csbi;
	    p = ALLOC(struct constat);
	    p->vt100.state = constat_init;
	    p->vt100.attr = FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED;
	    p->vt100.reverse = 0;
	    p->vt100.saved.X = p->vt100.saved.Y = 0;
	    if (GetConsoleScreenBufferInfo(h, &csbi)) {
		p->vt100.attr = csbi.wAttributes;
	    }
	    st_insert(conlist, (st_data_t)h, (st_data_t)p);
	}
    } else {
	p = NULL;
    }
    LeaveCriticalSection(&conlist_mutex);

    return p;
}

/* License: Ruby's */
static void
constat_reset(HANDLE h)
{
    st_data_t data;
    struct constat *p;

    EnterCriticalSection(&conlist_mutex);
    if (
	conlist && conlist != conlist_disabled &&
	st_lookup(conlist, (st_data_t)h, &data)
    ) {
	p = (struct constat *)data;
	p->vt100.state = constat_init;
    }
    LeaveCriticalSection(&conlist_mutex);
}

#define FOREGROUND_MASK (FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY)
#define BACKGROUND_MASK (BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY)

#define constat_attr_color_reverse(attr) \
    ((attr) & ~(FOREGROUND_MASK | BACKGROUND_MASK)) | \
	   (((attr) & FOREGROUND_MASK) << 4) | \
	   (((attr) & BACKGROUND_MASK) >> 4)

/* License: Ruby's */
static WORD
constat_attr(int count, const int *seq, WORD attr, WORD default_attr, int *reverse)
{
    int rev = *reverse;
    WORD bold;

    if (!count) return attr;
    if (rev) attr = constat_attr_color_reverse(attr);
    bold = attr & FOREGROUND_INTENSITY;
    attr &= ~(FOREGROUND_INTENSITY | BACKGROUND_INTENSITY);

    while (count-- > 0) {
	switch (*seq++) {
	  case 0:
	    attr = default_attr;
	    rev = 0;
	    bold = 0;
	    break;
	  case 1:
	    bold = FOREGROUND_INTENSITY;
	    break;
	  case 4:
#ifndef COMMON_LVB_UNDERSCORE
#define COMMON_LVB_UNDERSCORE 0x8000
#endif
	    attr |= COMMON_LVB_UNDERSCORE;
	    break;
	  case 7:
	    rev = 1;
	    break;

	  case 30:
	    attr &= ~(FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED);
	    break;
	  case 17:
	  case 31:
	    attr = (attr & ~(FOREGROUND_BLUE | FOREGROUND_GREEN)) | FOREGROUND_RED;
	    break;
	  case 18:
	  case 32:
	    attr = (attr & ~(FOREGROUND_BLUE | FOREGROUND_RED)) | FOREGROUND_GREEN;
	    break;
	  case 19:
	  case 33:
	    attr = (attr & ~FOREGROUND_BLUE) | FOREGROUND_GREEN | FOREGROUND_RED;
	    break;
	  case 20:
	  case 34:
	    attr = (attr & ~(FOREGROUND_GREEN | FOREGROUND_RED)) | FOREGROUND_BLUE;
	    break;
	  case 21:
	  case 35:
	    attr = (attr & ~FOREGROUND_GREEN) | FOREGROUND_BLUE | FOREGROUND_RED;
	    break;
	  case 22:
	  case 36:
	    attr = (attr & ~FOREGROUND_RED) | FOREGROUND_BLUE | FOREGROUND_GREEN;
	    break;
	  case 23:
	  case 37:
	    attr |= FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED;
	    break;

	  case 40:
	    attr &= ~(BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED);
	    break;
	  case 41:
	    attr = (attr & ~(BACKGROUND_BLUE | BACKGROUND_GREEN)) | BACKGROUND_RED;
	    break;
	  case 42:
	    attr = (attr & ~(BACKGROUND_BLUE | BACKGROUND_RED)) | BACKGROUND_GREEN;
	    break;
	  case 43:
	    attr = (attr & ~BACKGROUND_BLUE) | BACKGROUND_GREEN | BACKGROUND_RED;
	    break;
	  case 44:
	    attr = (attr & ~(BACKGROUND_GREEN | BACKGROUND_RED)) | BACKGROUND_BLUE;
	    break;
	  case 45:
	    attr = (attr & ~BACKGROUND_GREEN) | BACKGROUND_BLUE | BACKGROUND_RED;
	    break;
	  case 46:
	    attr = (attr & ~BACKGROUND_RED) | BACKGROUND_BLUE | BACKGROUND_GREEN;
	    break;
	  case 47:
	    attr |= BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED;
	    break;
	}
    }
    attr |= bold;
    if (rev) attr = constat_attr_color_reverse(attr);
    *reverse = rev;
    return attr;
}

/* License: Ruby's */
static void
constat_clear(HANDLE handle, WORD attr, DWORD len, COORD pos)
{
    DWORD written;

    FillConsoleOutputAttribute(handle, attr, len, pos, &written);
    FillConsoleOutputCharacterW(handle, L' ', len, pos, &written);
}

/* License: Ruby's */
static void
constat_apply(HANDLE handle, struct constat *s, WCHAR w)
{
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    const int *seq = s->vt100.seq;
    int count = s->vt100.state;
    int arg0, arg1 = 1;
    COORD pos;

    if (!GetConsoleScreenBufferInfo(handle, &csbi)) return;
    arg0 = (count > 0 && seq[0] > 0);
    if (arg0) arg1 = seq[0];
    switch (w) {
      case L'm':
	SetConsoleTextAttribute(handle, constat_attr(count, seq, csbi.wAttributes, s->vt100.attr, &s->vt100.reverse));
	break;
      case L'F':
	csbi.dwCursorPosition.X = 0;
      case L'A':
	csbi.dwCursorPosition.Y -= arg1;
	if (csbi.dwCursorPosition.Y < csbi.srWindow.Top)
	    csbi.dwCursorPosition.Y = csbi.srWindow.Top;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'E':
	csbi.dwCursorPosition.X = 0;
      case L'B':
      case L'e':
	csbi.dwCursorPosition.Y += arg1;
	if (csbi.dwCursorPosition.Y > csbi.srWindow.Bottom)
	    csbi.dwCursorPosition.Y = csbi.srWindow.Bottom;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'C':
	csbi.dwCursorPosition.X += arg1;
	if (csbi.dwCursorPosition.X >= csbi.srWindow.Right)
	    csbi.dwCursorPosition.X = csbi.srWindow.Right;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'D':
	csbi.dwCursorPosition.X -= arg1;
	if (csbi.dwCursorPosition.X < csbi.srWindow.Left)
	    csbi.dwCursorPosition.X = csbi.srWindow.Left;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'G':
      case L'`':
	arg1 += csbi.srWindow.Left;
	if (arg1 > csbi.srWindow.Right)
	    arg1 = csbi.srWindow.Right;
	csbi.dwCursorPosition.X = arg1;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'd':
	arg1 += csbi.srWindow.Top;
	if (arg1 > csbi.srWindow.Bottom)
	    arg1 = csbi.srWindow.Bottom;
	csbi.dwCursorPosition.Y = arg1;
	SetConsoleCursorPosition(handle, csbi.dwCursorPosition);
	break;
      case L'H':
      case L'f':
	pos.Y = arg1 + csbi.srWindow.Top - 1;
	if (pos.Y > csbi.srWindow.Bottom) pos.Y = csbi.srWindow.Bottom;
	if (count < 2 || (arg1 = seq[1]) <= 0) arg1 = 1;
	pos.X = arg1 + csbi.srWindow.Left - 1;
	if (pos.X > csbi.srWindow.Right) pos.X = csbi.srWindow.Right;
	SetConsoleCursorPosition(handle, pos);
	break;
      case L'J':
	switch (arg0 ? arg1 : 0) {
	  case 0:	/* erase after cursor */
	    constat_clear(handle, csbi.wAttributes,
			  (csbi.dwSize.X * (csbi.srWindow.Bottom - csbi.dwCursorPosition.Y + 1)
			   - csbi.dwCursorPosition.X),
			  csbi.dwCursorPosition);
	    break;
	  case 1:	/* erase before *and* cursor */
	    pos.X = 0;
	    pos.Y = csbi.srWindow.Top;
	    constat_clear(handle, csbi.wAttributes,
			  (csbi.dwSize.X * (csbi.dwCursorPosition.Y - csbi.srWindow.Top)
			   + csbi.dwCursorPosition.X + 1),
			  pos);
	    break;
	  case 2:	/* erase entire screen */
	    pos.X = 0;
	    pos.Y = csbi.srWindow.Top;
	    constat_clear(handle, csbi.wAttributes,
			  (csbi.dwSize.X * (csbi.srWindow.Bottom - csbi.srWindow.Top + 1)),
			  pos);
	    break;
	  case 3:	/* erase entire screen */
	    pos.X = 0;
	    pos.Y = 0;
	    constat_clear(handle, csbi.wAttributes,
			  (csbi.dwSize.X * csbi.dwSize.Y),
			  pos);
	    break;
	}
	break;
      case L'K':
	switch (arg0 ? arg1 : 0) {
	  case 0:	/* erase after cursor */
	    constat_clear(handle, csbi.wAttributes,
			  (csbi.dwSize.X - csbi.dwCursorPosition.X),
			  csbi.dwCursorPosition);
	    break;
	  case 1:	/* erase before *and* cursor */
	    pos.X = 0;
	    pos.Y = csbi.dwCursorPosition.Y;
	    constat_clear(handle, csbi.wAttributes,
			  csbi.dwCursorPosition.X + 1, pos);
	    break;
	  case 2:	/* erase entire line */
	    pos.X = 0;
	    pos.Y = csbi.dwCursorPosition.Y;
	    constat_clear(handle, csbi.wAttributes,
			  csbi.dwSize.X, pos);
	    break;
	}
	break;
      case L's':
	s->vt100.saved = csbi.dwCursorPosition;
	break;
      case L'u':
	SetConsoleCursorPosition(handle, s->vt100.saved);
	break;
      case L'h':
	if (count >= 2 && seq[0] == -1 && seq[1] == 25) {
	    CONSOLE_CURSOR_INFO cci;
	    GetConsoleCursorInfo(handle, &cci);
	    cci.bVisible = TRUE;
	    SetConsoleCursorInfo(handle, &cci);
	}
	break;
      case L'l':
	if (count >= 2 && seq[0] == -1 && seq[1] == 25) {
	    CONSOLE_CURSOR_INFO cci;
	    GetConsoleCursorInfo(handle, &cci);
	    cci.bVisible = FALSE;
	    SetConsoleCursorInfo(handle, &cci);
	}
	break;
    }
}

/* get rid of console writing bug; assume WriteConsole and WriteFile
 * on a console share the same limit. */
static const long MAXSIZE_CONSOLE_WRITING = 31366;

/* License: Ruby's */
static long
constat_parse(HANDLE h, struct constat *s, const WCHAR **ptrp, long *lenp)
{
    const WCHAR *ptr = *ptrp;
    long rest, len = *lenp;
    while (len-- > 0) {
	WCHAR wc = *ptr++;
	if (wc == 0x1b) {
	    rest = *lenp - len - 1;
	    if (s->vt100.state == constat_esc) {
		rest++;		/* reuse this ESC */
	    }
	    s->vt100.state = constat_init;
	    if (len > 0 && *ptr != L'[') continue;
	    s->vt100.state = constat_esc;
	}
	else if (s->vt100.state == constat_esc) {
	    if (wc != L'[') {
		/* TODO: supply dropped ESC at beginning */
		s->vt100.state = constat_init;
		continue;
	    }
	    rest = *lenp - len - 1;
	    if (rest > 0) --rest;
	    s->vt100.state = constat_seq;
	    s->vt100.seq[0] = 0;
	}
	else if (s->vt100.state >= constat_seq) {
	    if (wc >= L'0' && wc <= L'9') {
		if (s->vt100.state < (int)numberof(s->vt100.seq)) {
		    int *seq = &s->vt100.seq[s->vt100.state];
		    *seq = (*seq * 10) + (wc - L'0');
		}
	    }
	    else if (s->vt100.state == constat_seq && s->vt100.seq[0] == 0 && wc == L'?') {
		s->vt100.seq[s->vt100.state++] = -1;
	    }
	    else {
		do {
		    if (++s->vt100.state < (int)numberof(s->vt100.seq)) {
			s->vt100.seq[s->vt100.state] = 0;
		    }
		    else {
			s->vt100.state = (int)numberof(s->vt100.seq);
		    }
		} while (0);
		if (wc != L';') {
		    constat_apply(h, s, wc);
		    s->vt100.state = constat_init;
		}
	    }
	    rest = 0;
	}
	else if ((rest = *lenp - len) < MAXSIZE_CONSOLE_WRITING) {
	    continue;
	}
	*ptrp = ptr;
	*lenp = len;
	return rest;
    }
    len = *lenp;
    *ptrp = ptr;
    *lenp = 0;
    return len;
}


/* License: Ruby's */
int
rb_w32_close(int fd)
{
    SOCKET sock = TO_SOCKET(fd);
    int save_errno = errno;

    if (!is_socket(sock)) {
	UnlockFile((HANDLE)sock, 0, 0, LK_LEN, LK_LEN);
	constat_delete((HANDLE)sock);
	return _close(fd);
    }
    _set_osfhnd(fd, (SOCKET)INVALID_HANDLE_VALUE);
    socklist_delete(&sock, NULL);
    _close(fd);
    errno = save_errno;
    if (closesocket(sock) == SOCKET_ERROR) {
	errno = map_errno(WSAGetLastError());
	return -1;
    }
    return 0;
}

static int
setup_overlapped(OVERLAPPED *ol, int fd, int iswrite)
{
    memset(ol, 0, sizeof(*ol));
    if (!(_osfile(fd) & (FDEV | FPIPE))) {
	LONG high = 0;
	/* On mode:a, it can write only FILE_END.
	 * On mode:a+, though it can write only FILE_END,
	 * it can read from everywhere.
	 */
	DWORD method = ((_osfile(fd) & FAPPEND) && iswrite) ? FILE_END : FILE_CURRENT;
	DWORD low = SetFilePointer((HANDLE)_osfhnd(fd), 0, &high, method);
#ifndef INVALID_SET_FILE_POINTER
#define INVALID_SET_FILE_POINTER ((DWORD)-1)
#endif
	if (low == INVALID_SET_FILE_POINTER) {
	    DWORD err = GetLastError();
	    if (err != NO_ERROR) {
		errno = map_errno(err);
		return -1;
	    }
	}
	ol->Offset = low;
	ol->OffsetHigh = high;
    }
    ol->hEvent = CreateEvent(NULL, TRUE, TRUE, NULL);
    if (!ol->hEvent) {
	errno = map_errno(GetLastError());
	return -1;
    }
    return 0;
}

static void
finish_overlapped(OVERLAPPED *ol, int fd, DWORD size)
{
    CloseHandle(ol->hEvent);

    if (!(_osfile(fd) & (FDEV | FPIPE))) {
	LONG high = ol->OffsetHigh;
	DWORD low = ol->Offset + size;
	if (low < ol->Offset)
	    ++high;
	SetFilePointer((HANDLE)_osfhnd(fd), low, &high, FILE_BEGIN);
    }
}

#undef read
/* License: Ruby's */
ssize_t
rb_w32_read(int fd, void *buf, size_t size)
{
    SOCKET sock = TO_SOCKET(fd);
    DWORD read;
    DWORD wait;
    DWORD err;
    size_t len;
    size_t ret;
    OVERLAPPED ol;
    BOOL isconsole;
    BOOL islineinput = FALSE;
    int start = 0;

    if (is_socket(sock))
	return rb_w32_recv(fd, buf, size, 0);

    // validate fd by using _get_osfhandle() because we cannot access _nhandle
    if (_get_osfhandle(fd) == -1) {
	return -1;
    }

    if (_osfile(fd) & FTEXT) {
	return _read(fd, buf, size);
    }

    rb_acrt_lowio_lock_fh(fd);

    if (!size || _osfile(fd) & FEOFLAG) {
	_set_osflags(fd, _osfile(fd) & ~FEOFLAG);
	rb_acrt_lowio_unlock_fh(fd);
	return 0;
    }

    ret = 0;
    isconsole = is_console(_osfhnd(fd)) && (osver.dwMajorVersion < 6 || (osver.dwMajorVersion == 6 && osver.dwMinorVersion < 2));
    if (isconsole) {
	DWORD mode;
	GetConsoleMode((HANDLE)_osfhnd(fd),&mode);
	islineinput = (mode & ENABLE_LINE_INPUT) != 0;
    }
  retry:
    /* get rid of console reading bug */
    if (isconsole) {
	constat_reset((HANDLE)_osfhnd(fd));
	if (start)
	    len = 1;
	else {
	    len = 0;
	    start = 1;
	}
    }
    else
	len = size;
    size -= len;

    if (setup_overlapped(&ol, fd, FALSE)) {
	rb_acrt_lowio_unlock_fh(fd);
	return -1;
    }

    if (!ReadFile((HANDLE)_osfhnd(fd), buf, len, &read, &ol)) {
	err = GetLastError();
	if (err == ERROR_NO_DATA && (_osfile(fd) & FPIPE)) {
	    DWORD state;
	    if (GetNamedPipeHandleState((HANDLE)_osfhnd(fd), &state, NULL, NULL, NULL, NULL, 0) && (state & PIPE_NOWAIT)) {
		errno = EWOULDBLOCK;
	    }
	    else {
		errno = map_errno(err);
	    }
	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}
	else if (err != ERROR_IO_PENDING) {
	    CloseHandle(ol.hEvent);
	    if (err == ERROR_ACCESS_DENIED)
		errno = EBADF;
	    else if (err == ERROR_BROKEN_PIPE || err == ERROR_HANDLE_EOF) {
		rb_acrt_lowio_unlock_fh(fd);
		return 0;
	    }
	    else
		errno = map_errno(err);

	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}

	wait = rb_w32_wait_events_blocking(&ol.hEvent, 1, INFINITE);
	if (wait != WAIT_OBJECT_0) {
	    if (wait == WAIT_OBJECT_0 + 1)
		errno = EINTR;
	    else
		errno = map_errno(GetLastError());
	    CloseHandle(ol.hEvent);
	    CancelIo((HANDLE)_osfhnd(fd));
	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}

	if (!GetOverlappedResult((HANDLE)_osfhnd(fd), &ol, &read, TRUE) &&
	    (err = GetLastError()) != ERROR_HANDLE_EOF) {
	    int ret = 0;
	    if (err != ERROR_BROKEN_PIPE) {
		errno = map_errno(err);
		ret = -1;
	    }
	    CloseHandle(ol.hEvent);
	    CancelIo((HANDLE)_osfhnd(fd));
	    rb_acrt_lowio_unlock_fh(fd);
	    return ret;
	}
    }
    else {
	err = GetLastError();
	errno = map_errno(err);
    }

    finish_overlapped(&ol, fd, read);

    ret += read;
    if (read >= len) {
	buf = (char *)buf + read;
	if (err != ERROR_OPERATION_ABORTED &&
	    !(isconsole && len == 1 && (!islineinput || *((char *)buf - 1) == '\n')) && size > 0)
	    goto retry;
    }
    if (read == 0)
	_set_osflags(fd, _osfile(fd) | FEOFLAG);


    rb_acrt_lowio_unlock_fh(fd);

    return ret;
}

#undef write
/* License: Ruby's */
ssize_t
rb_w32_write(int fd, const void *buf, size_t size)
{
    SOCKET sock = TO_SOCKET(fd);
    DWORD written;
    DWORD wait;
    DWORD err;
    size_t len;
    size_t ret;
    OVERLAPPED ol;

    if (is_socket(sock))
	return rb_w32_send(fd, buf, size, 0);

    // validate fd by using _get_osfhandle() because we cannot access _nhandle
    if (_get_osfhandle(fd) == -1) {
	return -1;
    }

    if ((_osfile(fd) & FTEXT) &&
        (!(_osfile(fd) & FPIPE) || fd == fileno(stdout) || fd == fileno(stderr))) {
	ssize_t w = _write(fd, buf, size);
	if (w == (ssize_t)-1 && errno == EINVAL) {
	    errno = map_errno(GetLastError());
	}
	return w;
    }

    rb_acrt_lowio_lock_fh(fd);

    if (!size || _osfile(fd) & FEOFLAG) {
	rb_acrt_lowio_unlock_fh(fd);
	return 0;
    }

    ret = 0;
  retry:
    len = (_osfile(fd) & FDEV) ? min(MAXSIZE_CONSOLE_WRITING, size) : size;
    size -= len;
  retry2:

    if (setup_overlapped(&ol, fd, TRUE)) {
	rb_acrt_lowio_unlock_fh(fd);
	return -1;
    }

    if (!WriteFile((HANDLE)_osfhnd(fd), buf, len, &written, &ol)) {
	err = GetLastError();
	if (err != ERROR_IO_PENDING) {
	    CloseHandle(ol.hEvent);
	    if (err == ERROR_ACCESS_DENIED)
		errno = EBADF;
	    else
		errno = map_errno(err);

	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}

	wait = rb_w32_wait_events_blocking(&ol.hEvent, 1, INFINITE);
	if (wait != WAIT_OBJECT_0) {
	    if (wait == WAIT_OBJECT_0 + 1)
		errno = EINTR;
	    else
		errno = map_errno(GetLastError());
	    CloseHandle(ol.hEvent);
	    CancelIo((HANDLE)_osfhnd(fd));
	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}

	if (!GetOverlappedResult((HANDLE)_osfhnd(fd), &ol, &written, TRUE)) {
	    errno = map_errno(GetLastError());
	    CloseHandle(ol.hEvent);
	    CancelIo((HANDLE)_osfhnd(fd));
	    rb_acrt_lowio_unlock_fh(fd);
	    return -1;
	}
    }

    finish_overlapped(&ol, fd, written);

    ret += written;
    if (written == len) {
	buf = (const char *)buf + len;
	if (size > 0)
	    goto retry;
    }
    if (ret == 0) {
	size_t newlen = len / 2;
	if (newlen > 0) {
	    size += len - newlen;
	    len = newlen;
	    goto retry2;
	}
	ret = -1;
	errno = EWOULDBLOCK;
    }

    rb_acrt_lowio_unlock_fh(fd);

    return ret;
}

/* License: Ruby's */
long
rb_w32_write_console(uintptr_t strarg, int fd)
{
    HANDLE handle;
    DWORD dwMode, reslen;
    VALUE str = strarg;
    int encindex;
    WCHAR *wbuffer = 0;
    const WCHAR *ptr, *next;
    struct constat *s;
    long len;

    handle = (HANDLE)_osfhnd(fd);
    if (!GetConsoleMode(handle, &dwMode))
	return -1L;

    s = constat_handle(handle);
    if (!s) return -1L;
    encindex = ENCODING_GET(str);
    switch (encindex) {
      default:
	if (!rb_econv_has_convpath_p(rb_enc_name(rb_enc_from_index(encindex)), "UTF-8"))
	    return -1L;
	str = rb_str_conv_enc_opts(str, NULL, rb_enc_from_index(ENCINDEX_UTF_8),
				   ECONV_INVALID_REPLACE|ECONV_UNDEF_REPLACE, Qnil);
	/* fall through */
      case ENCINDEX_US_ASCII:
      case ENCINDEX_ASCII:
	/* assume UTF-8 */
      case ENCINDEX_UTF_8:
	ptr = wbuffer = mbstr_to_wstr(CP_UTF8, RSTRING_PTR(str), RSTRING_LEN(str), &len);
	if (!ptr) return -1L;
	break;
      case ENCINDEX_UTF_16LE:
	ptr = (const WCHAR *)RSTRING_PTR(str);
	len = RSTRING_LEN(str) / sizeof(WCHAR);
	break;
    }
    reslen = 0;
    if (dwMode & 4) {	/* ENABLE_VIRTUAL_TERMINAL_PROCESSING */
	if (!WriteConsoleW(handle, ptr, len, &reslen, NULL))
	    reslen = (DWORD)-1L;
    }
    else {
	while (len > 0) {
	    long curlen = constat_parse(handle, s, (next = ptr, &next), &len);
	    reslen += next - ptr;
	    if (curlen > 0) {
		DWORD written;
		if (!WriteConsoleW(handle, ptr, curlen, &written, NULL)) {
		    reslen = (DWORD)-1L;
		    break;
		}
	    }
	    ptr = next;
	}
    }
    RB_GC_GUARD(str);
    if (wbuffer) free(wbuffer);
    return (long)reslen;
}

#if RUBY_MSVCRT_VERSION < 80 && !defined(HAVE__GMTIME64_S)
/* License: Ruby's */
static int
unixtime_to_filetime(time_t time, FILETIME *ft)
{
    ULARGE_INTEGER tmp;

    tmp.QuadPart = ((LONG_LONG)time + (LONG_LONG)((1970-1601)*365.2425) * 24 * 60 * 60) * 10 * 1000 * 1000;
    ft->dwLowDateTime = tmp.LowPart;
    ft->dwHighDateTime = tmp.HighPart;
    return 0;
}
#endif

/* License: Ruby's */
static int
timespec_to_filetime(const struct timespec *ts, FILETIME *ft)
{
    ULARGE_INTEGER tmp;

    tmp.QuadPart = ((LONG_LONG)ts->tv_sec + (LONG_LONG)((1970-1601)*365.2425) * 24 * 60 * 60) * 10 * 1000 * 1000;
    tmp.QuadPart += ts->tv_nsec / 100;
    ft->dwLowDateTime = tmp.LowPart;
    ft->dwHighDateTime = tmp.HighPart;
    return 0;
}

/* License: Ruby's */
static int
wutimensat(int dirfd, const WCHAR *path, const struct timespec *times, int flags)
{
    HANDLE hFile;
    FILETIME atime, mtime;
    struct stati128 stat;
    int ret = 0;

    /* TODO: When path is absolute, dirfd should be ignored. */
    if (dirfd != AT_FDCWD) {
	errno = ENOSYS;
	return -1;
    }

    if (flags != 0) {
	errno = EINVAL; /* AT_SYMLINK_NOFOLLOW isn't supported. */
	return -1;
    }

    if (wstati128(path, &stat, FALSE)) {
	return -1;
    }

    if (times) {
	if (timespec_to_filetime(&times[0], &atime)) {
	    return -1;
	}
	if (timespec_to_filetime(&times[1], &mtime)) {
	    return -1;
	}
    }
    else {
	get_systemtime(&atime);
	mtime = atime;
    }

    RUBY_CRITICAL {
	const DWORD attr = GetFileAttributesW(path);
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY))
	    SetFileAttributesW(path, attr & ~FILE_ATTRIBUTE_READONLY);
	hFile = open_special(path, GENERIC_WRITE, 0);
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
	    SetFileAttributesW(path, attr);
    }

    return ret;
}

/* License: Ruby's */
int
rb_w32_uutime(const char *path, const struct utimbuf *times)
{
    struct timespec ts[2];

    ts[0].tv_sec = times->actime;
    ts[0].tv_nsec = 0;
    ts[1].tv_sec = times->modtime;
    ts[1].tv_nsec = 0;
    return rb_w32_uutimensat(AT_FDCWD, path, ts, 0);
}

/* License: Ruby's */
int
rb_w32_utime(const char *path, const struct utimbuf *times)
{
    struct timespec ts[2];

    ts[0].tv_sec = times->actime;
    ts[0].tv_nsec = 0;
    ts[1].tv_sec = times->modtime;
    ts[1].tv_nsec = 0;
    return rb_w32_utimensat(AT_FDCWD, path, ts, 0);
}

/* License: Ruby's */
int
rb_w32_uutimes(const char *path, const struct timeval *times)
{
    struct timespec ts[2];

    ts[0].tv_sec = times[0].tv_sec;
    ts[0].tv_nsec = times[0].tv_usec * 1000;
    ts[1].tv_sec = times[1].tv_sec;
    ts[1].tv_nsec = times[1].tv_usec * 1000;
    return rb_w32_uutimensat(AT_FDCWD, path, ts, 0);
}

/* License: Ruby's */
int
rb_w32_utimes(const char *path, const struct timeval *times)
{
    struct timespec ts[2];

    ts[0].tv_sec = times[0].tv_sec;
    ts[0].tv_nsec = times[0].tv_usec * 1000;
    ts[1].tv_sec = times[1].tv_sec;
    ts[1].tv_nsec = times[1].tv_usec * 1000;
    return rb_w32_utimensat(AT_FDCWD, path, ts, 0);
}

/* License: Ruby's */
int
rb_w32_uutimensat(int dirfd, const char *path, const struct timespec *times, int flags)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = wutimensat(dirfd, wpath, times, flags);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_utimensat(int dirfd, const char *path, const struct timespec *times, int flags)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = filecp_to_wstr(path, NULL)))
	return -1;
    ret = wutimensat(dirfd, wpath, times, flags);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_uchdir(const char *path)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = _wchdir(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
static int
wmkdir(const WCHAR *wpath, int mode)
{
    int ret = -1;

    RUBY_CRITICAL do {
	if (CreateDirectoryW(wpath, NULL) == FALSE) {
	    errno = map_errno(GetLastError());
	    break;
	}
	if (_wchmod(wpath, mode) == -1) {
	    RemoveDirectoryW(wpath);
	    break;
	}
	ret = 0;
    } while (0);
    return ret;
}

/* License: Ruby's */
int
rb_w32_umkdir(const char *path, int mode)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = wmkdir(wpath, mode);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_mkdir(const char *path, int mode)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = filecp_to_wstr(path, NULL)))
	return -1;
    ret = wmkdir(wpath, mode);
    free(wpath);
    return ret;
}

/* License: Ruby's */
static int
wrmdir(const WCHAR *wpath)
{
    int ret = 0;
    RUBY_CRITICAL {
	const DWORD attr = GetFileAttributesW(wpath);
	if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
	    SetFileAttributesW(wpath, attr & ~FILE_ATTRIBUTE_READONLY);
	}
	if (RemoveDirectoryW(wpath) == FALSE) {
	    errno = map_errno(GetLastError());
	    ret = -1;
	    if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
		SetFileAttributesW(wpath, attr);
	    }
	}
    }
    return ret;
}

/* License: Ruby's */
int
rb_w32_rmdir(const char *path)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = filecp_to_wstr(path, NULL)))
	return -1;
    ret = wrmdir(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_urmdir(const char *path)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = wrmdir(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
static int
wunlink(const WCHAR *path)
{
    int ret = 0;
    const DWORD SYMLINKD = FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY;
    RUBY_CRITICAL {
	const DWORD attr = GetFileAttributesW(path);
	if (attr == (DWORD)-1) {
	}
	else if ((attr & SYMLINKD) == SYMLINKD) {
	    ret = RemoveDirectoryW(path);
	}
	else {
	    if (attr & FILE_ATTRIBUTE_READONLY) {
		SetFileAttributesW(path, attr & ~FILE_ATTRIBUTE_READONLY);
	    }
	    ret = DeleteFileW(path);
	}
	if (!ret) {
	    errno = map_errno(GetLastError());
	    ret = -1;
	    if (attr != (DWORD)-1 && (attr & FILE_ATTRIBUTE_READONLY)) {
		SetFileAttributesW(path, attr);
	    }
	}
    }
    return ret;
}

/* License: Ruby's */
int
rb_w32_uunlink(const char *path)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = wunlink(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_unlink(const char *path)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = filecp_to_wstr(path, NULL)))
	return -1;
    ret = wunlink(wpath);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
rb_w32_uchmod(const char *path, int mode)
{
    WCHAR *wpath;
    int ret;

    if (!(wpath = utf8_to_wstr(path, NULL)))
	return -1;
    ret = _wchmod(wpath, mode);
    free(wpath);
    return ret;
}

/* License: Ruby's */
int
fchmod(int fd, int mode)
{
    typedef BOOL (WINAPI *set_file_information_by_handle_func)
	(HANDLE, int, void*, DWORD);
    static set_file_information_by_handle_func set_file_info =
	(set_file_information_by_handle_func)-1;

    /* from winbase.h of the mingw-w64 runtime package. */
    struct {
	LARGE_INTEGER CreationTime;
	LARGE_INTEGER LastAccessTime;
	LARGE_INTEGER LastWriteTime;
	LARGE_INTEGER ChangeTime;
	DWORD         FileAttributes;
    } info = {{{0}}, {{0}}, {{0}},}; /* fields with 0 are unchanged */
    HANDLE h = (HANDLE)_get_osfhandle(fd);

    if (h == INVALID_HANDLE_VALUE) {
	errno = EBADF;
	return -1;
    }
    if (set_file_info == (set_file_information_by_handle_func)-1) {
	set_file_info = (set_file_information_by_handle_func)
	    get_proc_address("kernel32", "SetFileInformationByHandle", NULL);
    }
    if (!set_file_info) {
	errno = ENOSYS;
	return -1;
    }

    info.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    if (!(mode & 0200)) info.FileAttributes |= FILE_ATTRIBUTE_READONLY;
    if (!set_file_info(h, 0, &info, sizeof(info))) {
	errno = map_errno(GetLastError());
	return -1;
    }
    return 0;
}

/* License: Ruby's */
int
rb_w32_isatty(int fd)
{
    DWORD mode;

    // validate fd by using _get_osfhandle() because we cannot access _nhandle
    if (_get_osfhandle(fd) == -1) {
	return 0;
    }
    if (!GetConsoleMode((HANDLE)_osfhnd(fd), &mode)) {
	errno = ENOTTY;
	return 0;
    }
    return 1;
}

#if defined(_MSC_VER) && RUBY_MSVCRT_VERSION <= 60
extern long _ftol(double);
/* License: Ruby's */
long
_ftol2(double d)
{
    return _ftol(d);
}

/* License: Ruby's */
long
_ftol2_sse(double d)
{
    return _ftol(d);
}
#endif

#ifndef signbit
/* License: Ruby's */
int
signbit(double x)
{
    int *ip = (int *)(&x + 1) - 1;
    return *ip < 0;
}
#endif

/* License: Ruby's */
const char * WSAAPI
rb_w32_inet_ntop(int af, const void *addr, char *numaddr, size_t numaddr_len)
{
    typedef char *(WSAAPI inet_ntop_t)(int, void *, char *, size_t);
    static inet_ntop_t *pInetNtop = (inet_ntop_t *)-1;
    if (pInetNtop == (inet_ntop_t *)-1)
	pInetNtop = (inet_ntop_t *)get_proc_address("ws2_32", "inet_ntop", NULL);
    if (pInetNtop) {
	return pInetNtop(af, (void *)addr, numaddr, numaddr_len);
    }
    else {
	struct in_addr in;
	memcpy(&in.s_addr, addr, sizeof(in.s_addr));
	snprintf(numaddr, numaddr_len, "%s", inet_ntoa(in));
    }
    return numaddr;
}

/* License: Ruby's */
int WSAAPI
rb_w32_inet_pton(int af, const char *src, void *dst)
{
    typedef int (WSAAPI inet_pton_t)(int, const char*, void *);
    static inet_pton_t *pInetPton = (inet_pton_t *)-1;
    if (pInetPton == (inet_pton_t *)-1)
	pInetPton = (inet_pton_t *)get_proc_address("ws2_32", "inet_pton", NULL);
    if (pInetPton) {
	return pInetPton(af, src, dst);
    }
    return 0;
}

/* License: Ruby's */
char
rb_w32_fd_is_text(int fd)
{
    return _osfile(fd) & FTEXT;
}

#if RUBY_MSVCRT_VERSION < 80 && !defined(HAVE__GMTIME64_S)
/* License: Ruby's */
static int
unixtime_to_systemtime(const time_t t, SYSTEMTIME *st)
{
    FILETIME ft;
    if (unixtime_to_filetime(t, &ft)) return -1;
    if (!FileTimeToSystemTime(&ft, st)) return -1;
    return 0;
}

/* License: Ruby's */
static void
systemtime_to_tm(const SYSTEMTIME *st, struct tm *t)
{
    int y = st->wYear, m = st->wMonth, d = st->wDay;
    t->tm_sec  = st->wSecond;
    t->tm_min  = st->wMinute;
    t->tm_hour = st->wHour;
    t->tm_mday = st->wDay;
    t->tm_mon  = st->wMonth - 1;
    t->tm_year = y - 1900;
    t->tm_wday = st->wDayOfWeek;
    switch (m) {
      case 1:
	break;
      case 2:
	d += 31;
	break;
      default:
	d += 31 + 28 + (!(y % 4) && ((y % 100) || !(y % 400)));
	d += ((m - 3) * 153 + 2) / 5;
	break;
    }
    t->tm_yday = d - 1;
}

/* License: Ruby's */
static int
systemtime_to_localtime(TIME_ZONE_INFORMATION *tz, SYSTEMTIME *gst, SYSTEMTIME *lst)
{
    TIME_ZONE_INFORMATION stdtz;
    SYSTEMTIME sst;

    if (!SystemTimeToTzSpecificLocalTime(tz, gst, lst)) return -1;
    if (!tz) {
	GetTimeZoneInformation(&stdtz);
	tz = &stdtz;
    }
    if (tz->StandardBias == tz->DaylightBias) return 0;
    if (!tz->StandardDate.wMonth) return 0;
    if (!tz->DaylightDate.wMonth) return 0;
    if (tz != &stdtz) stdtz = *tz;

    stdtz.StandardDate.wMonth = stdtz.DaylightDate.wMonth = 0;
    if (!SystemTimeToTzSpecificLocalTime(&stdtz, gst, &sst)) return 0;
    if (lst->wMinute == sst.wMinute && lst->wHour == sst.wHour)
	return 0;
    return 1;
}
#endif

#ifdef HAVE__GMTIME64_S
# ifndef HAVE__LOCALTIME64_S
/* assume same as _gmtime64_s() */
#  define HAVE__LOCALTIME64_S 1
# endif
# ifndef MINGW_HAS_SECURE_API
   _CRTIMP errno_t __cdecl _gmtime64_s(struct tm* tm, const __time64_t *time);
   _CRTIMP errno_t __cdecl _localtime64_s(struct tm* tm, const __time64_t *time);
# endif
# define gmtime_s _gmtime64_s
# define localtime_s _localtime64_s
#endif

/* License: Ruby's */
struct tm *
gmtime_r(const time_t *tp, struct tm *rp)
{
    int e = EINVAL;
    if (!tp || !rp) {
      error:
	errno = e;
	return NULL;
    }
#if RUBY_MSVCRT_VERSION >= 80 || defined(HAVE__GMTIME64_S)
    e = gmtime_s(rp, tp);
    if (e != 0) goto error;
#else
    {
	SYSTEMTIME st;
	if (unixtime_to_systemtime(*tp, &st)) goto error;
	rp->tm_isdst = 0;
	systemtime_to_tm(&st, rp);
    }
#endif
    return rp;
}

/* License: Ruby's */
struct tm *
localtime_r(const time_t *tp, struct tm *rp)
{
    int e = EINVAL;
    if (!tp || !rp) {
      error:
	errno = e;
	return NULL;
    }
#if RUBY_MSVCRT_VERSION >= 80 || defined(HAVE__LOCALTIME64_S)
    e = localtime_s(rp, tp);
    if (e) goto error;
#else
    {
	SYSTEMTIME gst, lst;
	if (unixtime_to_systemtime(*tp, &gst)) goto error;
	rp->tm_isdst = systemtime_to_localtime(NULL, &gst, &lst);
	systemtime_to_tm(&lst, rp);
    }
#endif
    return rp;
}

/* License: Ruby's */
int
rb_w32_wrap_io_handle(HANDLE h, int flags)
{
    BOOL tmp;
    int len = sizeof(tmp);
    int r = getsockopt((SOCKET)h, SOL_SOCKET, SO_DEBUG, (char *)&tmp, &len);
    if (r != SOCKET_ERROR || WSAGetLastError() != WSAENOTSOCK) {
        int f = 0;
        if (flags & O_NONBLOCK) {
            flags &= ~O_NONBLOCK;
            f = O_NONBLOCK;
        }
        socklist_insert((SOCKET)h, f);
    }
    else if (flags & O_NONBLOCK) {
        errno = EINVAL;
        return -1;
    }
    return rb_w32_open_osfhandle((intptr_t)h, flags);
}

/* License: Ruby's */
int
rb_w32_unwrap_io_handle(int fd)
{
    SOCKET sock = TO_SOCKET(fd);
    _set_osfhnd(fd, (SOCKET)INVALID_HANDLE_VALUE);
    if (!is_socket(sock)) {
	UnlockFile((HANDLE)sock, 0, 0, LK_LEN, LK_LEN);
	constat_delete((HANDLE)sock);
    }
    else {
	socklist_delete(&sock, NULL);
    }
    return _close(fd);
}

#if !defined(__MINGW64__) && defined(__MINGW64_VERSION_MAJOR)
/*
 * Set floating point precision for pow() of mingw-w64 x86.
 * With default precision the result is not proper on WinXP.
 */
double
rb_w32_pow(double x, double y)
{
#undef pow
    double r;
    unsigned int default_control = _controlfp(0, 0);
    _controlfp(_PC_64, _MCW_PC);
    r = pow(x, y);
    /* Restore setting */
    _controlfp(default_control, _MCW_PC);
    return r;
}
#endif

typedef struct {
    BOOL file_id_p;
    union {
	BY_HANDLE_FILE_INFORMATION bhfi;
	FILE_ID_INFO fii;
    } info;
} w32_io_info_t;

static HANDLE
w32_io_info(VALUE *file, w32_io_info_t *st)
{
    VALUE tmp;
    HANDLE f, ret = 0;

    tmp = rb_check_convert_type_with_id(*file, T_FILE, "IO", idTo_io);
    if (!NIL_P(tmp)) {
	rb_io_t *fptr;

	GetOpenFile(tmp, fptr);
	f = (HANDLE)rb_w32_get_osfhandle(fptr->fd);
	if (f == (HANDLE)-1) return INVALID_HANDLE_VALUE;
    }
    else {
	VALUE tmp;
	WCHAR *ptr;
	int len;
	VALUE v;

	FilePathValue(*file);
	tmp = rb_str_encode_ospath(*file);
	len = MultiByteToWideChar(CP_UTF8, 0, RSTRING_PTR(tmp), -1, NULL, 0);
	ptr = ALLOCV_N(WCHAR, v, len);
	MultiByteToWideChar(CP_UTF8, 0, RSTRING_PTR(tmp), -1, ptr, len);
	f = CreateFileW(ptr, 0,
			FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS, NULL);
	ALLOCV_END(v);
	if (f == INVALID_HANDLE_VALUE) return f;
	ret = f;
    }
    if (GetFileType(f) == FILE_TYPE_DISK) {
	DWORD err;
	ZeroMemory(st, sizeof(*st));
	err = get_ino(f, &st->info.fii);
	if (!err) {
	    st->file_id_p = TRUE;
	    return ret;
	}
	else if (err != ERROR_INVALID_PARAMETER) {
	    CloseHandle(f);
	    return INVALID_HANDLE_VALUE;
	}
	/* this API may not work at files on non Microsoft SMB
	 * server, fallback to old API then. */
	if (GetFileInformationByHandle(f, &st->info.bhfi)) {
	    st->file_id_p = FALSE;
	    return ret;
	}
    }
    if (ret) CloseHandle(ret);
    return INVALID_HANDLE_VALUE;
}

static VALUE
close_handle(VALUE h)
{
    CloseHandle((HANDLE)h);
    return Qfalse;
}

struct w32_io_info_args {
    VALUE *fname;
    w32_io_info_t *st;
};

static VALUE
call_w32_io_info(VALUE arg)
{
    struct w32_io_info_args *p = (void *)arg;
    return (VALUE)w32_io_info(p->fname, p->st);
}

VALUE
rb_w32_file_identical_p(VALUE fname1, VALUE fname2)
{
    w32_io_info_t st1, st2;
    HANDLE f1 = 0, f2 = 0;

    f1 = w32_io_info(&fname1, &st1);
    if (f1 == INVALID_HANDLE_VALUE) return Qfalse;
    if (f1) {
	struct w32_io_info_args arg;
	arg.fname = &fname2;
	arg.st = &st2;
	f2 = (HANDLE)rb_ensure(call_w32_io_info, (VALUE)&arg, close_handle, (VALUE)f1);
    }
    else {
	f2 = w32_io_info(&fname2, &st2);
    }
    if (f2 == INVALID_HANDLE_VALUE) return Qfalse;
    if (f2) CloseHandle(f2);

    if (st1.file_id_p != st2.file_id_p) return Qfalse;
    if (!st1.file_id_p) {
	if (st1.info.bhfi.dwVolumeSerialNumber == st2.info.bhfi.dwVolumeSerialNumber &&
	    st1.info.bhfi.nFileIndexHigh == st2.info.bhfi.nFileIndexHigh &&
	    st1.info.bhfi.nFileIndexLow == st2.info.bhfi.nFileIndexLow)
	    return Qtrue;
    }
    else {
	if (st1.info.fii.VolumeSerialNumber == st2.info.fii.VolumeSerialNumber &&
	    memcmp(&st1.info.fii.FileId, &st2.info.fii.FileId, sizeof(FILE_ID_128)) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

int
rb_w32_set_thread_description(HANDLE th, const WCHAR *name)
{
    int result = FALSE;
    typedef HRESULT (WINAPI *set_thread_description_func)(HANDLE, PCWSTR);
    static set_thread_description_func set_thread_description =
	(set_thread_description_func)-1;
    if (set_thread_description == (set_thread_description_func)-1) {
	set_thread_description = (set_thread_description_func)
	    get_proc_address("kernel32", "SetThreadDescription", NULL);
    }
    if (set_thread_description) {
	result = set_thread_description(th, name);
    }
    return result;
}

int
rb_w32_set_thread_description_str(HANDLE th, VALUE name)
{
    int idx, result = FALSE;
    WCHAR *s;

    if (NIL_P(name)) {
	return rb_w32_set_thread_description(th, L"");
    }
    s = (WCHAR *)StringValueCStr(name);
    idx = rb_enc_get_index(name);
    if (idx == ENCINDEX_UTF_16LE) {
	result = rb_w32_set_thread_description(th, s);
    }
    else {
	name = rb_str_conv_enc(name, rb_enc_from_index(idx), rb_utf8_encoding());
	s = mbstr_to_wstr(CP_UTF8, RSTRING_PTR(name), RSTRING_LEN(name)+1, NULL);
	result = rb_w32_set_thread_description(th, s);
	free(s);
    }
    RB_GC_GUARD(name);
    return result;
}

VALUE (*const rb_f_notimplement_)(int, const VALUE *, VALUE, VALUE) = rb_f_notimplement;

#if RUBY_MSVCRT_VERSION < 120
#include "missing/nextafter.c"
#endif
