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
#include <fcntl.h>
#include <process.h>
#include <sys/stat.h>
/* #include <sys/wait.h> */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <assert.h>

#include <windows.h>
#include <winbase.h>
#include <wincon.h>
#ifdef __MINGW32__
#include <mswsock.h>
#endif
#include "win32.h"
#include "win32/dir.h"
#ifndef index
#define index(x, y) strchr((x), (y))
#endif
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#undef stat

#ifndef bool
#define bool int
#endif

#ifdef _M_IX86
# define WIN95 1
#else
# undef  WIN95
#endif

#ifdef __BORLANDC__
#  define _filbuf _fgetc
#  define _flsbuf fputc
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

bool NtSyncProcess = TRUE;

static struct ChildRecord *CreateChild(char *, SECURITY_ATTRIBUTES *, HANDLE, HANDLE, HANDLE);
static bool NtHasRedirection (char *);
static int valid_filename(char *s);
static void StartSockets ();
static char *str_grow(struct RString *str, size_t new_size);
static DWORD wait_events(HANDLE event, DWORD timeout);
#ifndef __BORLANDC__
static int rb_w32_open_osfhandle(long osfhandle, int flags);
#endif

char *NTLoginName;

#ifdef WIN95
DWORD Win32System = (DWORD)-1;

static DWORD
IdOS(void)
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

static int 
IsWin95(void) {
    return (IdOS() == VER_PLATFORM_WIN32_WINDOWS);
}

static int
IsWinNT(void) {
    return (IdOS() == VER_PLATFORM_WIN32_NT);
}
#else
# define IsWinNT() TRUE
# define IsWin95() FALSE
#endif

/* main thread constants */
static struct {
    HANDLE handle;
    DWORD id;
} main_thread;

/* interrupt stuff */
static HANDLE interrupted_event;

HANDLE GetCurrentThreadHandle(void)
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


#define LK_ERR(f,i) ((f) ? (i = 0) : (errno = GetLastError()))
#define LK_LEN      0xffff0000

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
	LK_ERR(LockFileEx(fh, 0, 0, LK_LEN, 0, &o), i);
	break;
      case LOCK_EX:		/* exclusive lock */
	LK_ERR(LockFileEx(fh, LOCKFILE_EXCLUSIVE_LOCK, 0, LK_LEN, 0, &o), i);
	break;
      case LOCK_SH|LOCK_NB:	/* non-blocking shared lock */
	LK_ERR(LockFileEx(fh, LOCKFILE_FAIL_IMMEDIATELY, 0, LK_LEN, 0, &o), i);
	break;
      case LOCK_EX|LOCK_NB:	/* non-blocking exclusive lock */
	LK_ERR(LockFileEx(fh,
			  LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,
			  0, LK_LEN, 0, &o), i);
	if (errno == EDOM)
	    errno = EWOULDBLOCK;
	break;
      case LOCK_UN:		/* unlock lock */
	if (UnlockFileEx(fh, 0, LK_LEN, 0, &o)) {
	    i = 0;
	    if (errno == EDOM)
		errno = EWOULDBLOCK;
	}
	else {
	    /* GetLastError() must returns `ERROR_NOT_LOCKED' */
	    errno = EWOULDBLOCK;
	}
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
	while(i == -1) {
	    LK_ERR(LockFile(fh, 0, 0, LK_LEN, 0), i);
	    if (errno != EDOM && i == -1) break;
	}
	break;
      case LOCK_EX | LOCK_NB:
	LK_ERR(LockFile(fh, 0, 0, LK_LEN, 0), i);
	if (errno == EDOM)
	    errno = EWOULDBLOCK;
	break;
      case LOCK_UN:
	LK_ERR(UnlockFile(fh, 0, 0, LK_LEN, 0), i);
	if (errno == EDOM)
	    errno = EWOULDBLOCK;
	break;
      default:
	errno = EINVAL;
	break;
    }
    return i;
}
#endif

#undef LK_ERR
#undef LK_LEN

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

//#undef const
//FILE *fdopen(int, const char *);

//
// Initialization stuff
//
void
NtInitialize(int *argc, char ***argv)
{

    WORD version;
    int ret;

    //
    // subvert cmd.exe's feeble attempt at command line parsing
    //
    *argc = NtMakeCmdVector((char *)GetCommandLine(), argv, TRUE);

    //
    // Now set up the correct time stuff
    //

    tzset();

    // Initialize Winsock
    StartSockets();
}

char *getlogin()
{
    char buffer[200];
    DWORD len = 200;
    extern char *NTLoginName;

    if (NTLoginName == NULL) {
	if (GetUserName(buffer, &len)) {
	    NTLoginName = ALLOC_N(char, len+1);
	    strncpy(NTLoginName, buffer, len);
	    NTLoginName[len] = '\0';
	}
	else {
	    NTLoginName = "<Unknown>";
	}
    }
    return NTLoginName;
}

#define MAXCHILDNUM 256	/* max num of child processes */

struct ChildRecord {
    HANDLE hProcess;	/* process handle */
    pid_t pid;		/* process id */
} ChildRecord[MAXCHILDNUM];

#define FOREACH_CHILD(v) do { \
    struct ChildRecord* v; \
    for (v = ChildRecord; v < ChildRecord + sizeof(ChildRecord) / sizeof(ChildRecord[0]); ++v)
#define END_FOREACH_CHILD } while (0)

static struct ChildRecord *
FindFirstChildSlot(void)
{
    FOREACH_CHILD(child) {
	if (child->pid) return child;
    } END_FOREACH_CHILD;
    return NULL;
}

static struct ChildRecord *
FindChildSlot(pid_t pid)
{

    FOREACH_CHILD(child) {
	if (child->pid == pid) {
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


int SafeFree(char **vec, int vecc)
{
    //   vec
    //   |
    //   V       ^---------------------V
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |   |       | ....  |  NULL |   | ..... |\0 |   | ..... |\0 |...
    //   +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
    //   |-  elements+1             -| ^ 1st element   ^ 2nd element

	char *p;

	p = (char *)vec;
	free(p);

	return 0;
}


static char *szInternalCmds[] = {
  "append",
  "break",
  "call",
  "cd",
  "chdir",
  "cls",
  "copy",
  "date",
  "del",
  "dir",
  "echo",
  "erase",
  "label",
  "md",
  "mkdir",
  "path",
  "pause",
  "rd",
  "rem",
  "ren",
  "rename",
  "rmdir",
  "set",
  "start",
  "time",
  "type",
  "ver",
  "vol",
  NULL
};

int
isInternalCmd(char *cmd)
{
    int i, fRet=0;
    char **vec;
    int vecc = NtMakeCmdVector(cmd, &vec, FALSE);

    if (vecc == 0)
	return 0;
    for( i = 0; szInternalCmds[i] ; i++){
	if(!strcasecmp(szInternalCmds[i], vec[0])){
	    fRet = 1;
	    break;
	}
    }

    SafeFree(vec, vecc);

    return fRet;
}


SOCKET
rb_w32_get_osfhandle(int fh)
{
    return _get_osfhandle(fh);

}

pid_t
pipe_exec(char *cmd, int mode, FILE **fpr, FILE **fpw)
{
    struct ChildRecord* child;
    HANDLE hReadIn, hReadOut;
    HANDLE hWriteIn, hWriteOut;
    HANDLE hSavedStdIn, hSavedStdOut;
    HANDLE hDupInFile, hDupOutFile;
    HANDLE hCurProc;
    SECURITY_ATTRIBUTES sa;
    BOOL fRet;
    BOOL reading, writing;
    int fdin, fdout;
    int pipemode;
    char modes[3];
    int ret;

    /* Figure out what we're doing... */
    writing = (mode & (O_WRONLY | O_RDWR)) ? TRUE : FALSE;
    reading = ((mode & O_RDWR) || !writing) ? TRUE : FALSE;
    pipemode = (mode & O_BINARY) ? O_BINARY : O_TEXT;

    sa.nLength              = sizeof (SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle       = TRUE;

    /* create pipe, save parent's STDIN/STDOUT and redirect them for child */
    RUBY_CRITICAL(do {
	ret = -1;
	hCurProc = GetCurrentProcess();
	if (reading) {
	    fRet = CreatePipe(&hReadIn, &hReadOut, &sa, 2048L);
	    if (!fRet) {
		errno = GetLastError();
		break;
	    }
	    hSavedStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
	    if (!SetStdHandle(STD_OUTPUT_HANDLE, hReadOut) ||
		!DuplicateHandle(hCurProc, hReadIn, hCurProc, &hDupInFile, 0,
				 FALSE, DUPLICATE_SAME_ACCESS)) {
		errno = GetLastError();
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
		errno = GetLastError();
		if (reading) {
		    CloseHandle(hDupInFile);
		    CloseHandle(hReadOut);
		}
		break;
	    }
	    hSavedStdIn = GetStdHandle(STD_INPUT_HANDLE);
	    if (!SetStdHandle(STD_INPUT_HANDLE, hWriteIn) ||
		!DuplicateHandle(hCurProc, hWriteOut, hCurProc, &hDupOutFile, 0,
				 FALSE, DUPLICATE_SAME_ACCESS)) {
		errno = GetLastError();
		CloseHandle(hWriteIn);
		CloseHandle(hWriteOut);
		CloseHandle(hCurProc);
		if (reading) {
		    CloseHandle(hDupInFile);
		    CloseHandle(hReadOut);
		}
		break;
	    }
	    CloseHandle(hWriteOut);
	}
	CloseHandle(hCurProc);
	ret = 0;
    } while (0));
    if (ret != 0) {
	return ret;
    }

    /* create child process */
    child = CreateChild(cmd, &sa, NULL, NULL, NULL);
    if (!child) {
	RUBY_CRITICAL({
	    if (reading) {
		SetStdHandle(STD_OUTPUT_HANDLE, hSavedStdOut);
		CloseHandle(hReadOut);
		CloseHandle(hDupInFile);
	    }
	    if (writing) {
		SetStdHandle(STD_INPUT_HANDLE, hSavedStdIn);
		CloseHandle(hWriteIn);
		CloseHandle(hDupOutFile);
	    }
	});
	return -1;
    }

    /* restore STDIN/STDOUT */
    RUBY_CRITICAL(do {
	ret = -1;
	if (reading) {
	    if (!SetStdHandle(STD_OUTPUT_HANDLE, hSavedStdOut)) {
		errno = GetLastError();
		CloseChildHandle(child);
		CloseHandle(hReadOut);
		CloseHandle(hDupInFile);
		if (writing) {
		    CloseHandle(hWriteIn);
		    CloseHandle(hDupOutFile);
		}
		break;
	    }
	}
	if (writing) {
	    if (!SetStdHandle(STD_INPUT_HANDLE, hSavedStdIn)) {
		errno = GetLastError();
		CloseChildHandle(child);
		CloseHandle(hWriteIn);
		CloseHandle(hDupOutFile);
		if (reading) {
		    CloseHandle(hReadOut);
		    CloseHandle(hDupInFile);
		}
		break;
	    }
	}
	ret = 0;
    } while (0));
    if (ret != 0) {
	return ret;
    }

    if (reading) {
#ifdef __BORLANDC__
	fdin = _open_osfhandle((long)hDupInFile, (_O_RDONLY | pipemode));
#else
	fdin = rb_w32_open_osfhandle((long)hDupInFile, (_O_RDONLY | pipemode));
#endif
	CloseHandle(hReadOut);
	if (fdin == -1) {
	    CloseHandle(hDupInFile);
	    if (writing) {
		CloseHandle(hWriteIn);
		CloseHandle(hDupOutFile);
	    }
	    CloseChildHandle(child);
	    return -1;
	}
    }
    if (writing) {
#ifdef __BORLANDC__
	fdout = _open_osfhandle((long)hDupOutFile, (_O_WRONLY | pipemode));
#else
	fdout = rb_w32_open_osfhandle((long)hDupOutFile,
				      (_O_WRONLY | pipemode));
#endif
	CloseHandle(hWriteIn);
	if (fdout == -1) {
	    CloseHandle(hDupOutFile);
	    if (reading) {
		_close(fdin);
	    }
	    CloseChildHandle(child);
	    return -1;
	}
    }

    if (reading) {
	sprintf(modes, "r%s", pipemode == O_BINARY ? "b" : "");
	if ((*fpr = (FILE *)fdopen(fdin, modes)) == NULL) {
	    _close(fdin);
	    if (writing) {
		_close(fdout);
	    }
	    CloseChildHandle(child);
	    return -1;
	}
    }
    if (writing) {
	sprintf(modes, "w%s", pipemode == O_BINARY ? "b" : "");
	if ((*fpw = (FILE *)fdopen(fdout, modes)) == NULL) {
	    _close(fdout);
	    if (reading) {
		fclose(*fpr);
	    }
	    CloseChildHandle(child);
	    return -1;
	}
    }

    return child->pid;
}

extern VALUE rb_last_status;

int
do_spawn(cmd)
char *cmd;
{
    struct ChildRecord *child = CreateChild(cmd, NULL, NULL, NULL, NULL);
    if (!child) {
	return -1;
    }
    rb_syswait(child->pid);
    return NUM2INT(rb_last_status);
}

static struct ChildRecord *
CreateChild(char *cmd, SECURITY_ATTRIBUTES *psa, HANDLE hInput, HANDLE hOutput, HANDLE hError)
{
    BOOL fRet;
    DWORD  dwCreationFlags;
    STARTUPINFO aStartupInfo;
    PROCESS_INFORMATION aProcessInformation;
    SECURITY_ATTRIBUTES sa;
    char *shell;
    struct ChildRecord *child;

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

    if ((shell = getenv("RUBYSHELL")) && NtHasRedirection(cmd)) {
	char *tmp = ALLOCA_N(char, strlen(shell) + strlen(cmd) + sizeof (" -c "));
	sprintf(tmp, "%s -c %s", shell, cmd);
	cmd = tmp;
    }
    else if ((shell = getenv("COMSPEC")) &&
	     (NtHasRedirection(cmd) || isInternalCmd(cmd))) {
	char *tmp = ALLOCA_N(char, strlen(shell) + strlen(cmd) + sizeof (" /c "));
	sprintf(tmp, "%s /c %s", shell, cmd);
	cmd = tmp;
    }
    else {
	shell = NULL;
    }

    RUBY_CRITICAL({
	fRet = CreateProcess(shell, cmd, psa, psa,
			     psa->bInheritHandle, dwCreationFlags, NULL, NULL,
			     &aStartupInfo, &aProcessInformation);
	errno = GetLastError();
    });

    if (!fRet) {
	child->pid = 0;		/* release the slot */
	return NULL;
    }

    CloseHandle(aProcessInformation.hThread);

    child->hProcess = aProcessInformation.hProcess;
    child->pid = (pid_t)aProcessInformation.dwProcessId;

    if (!IsWinNT()) {
	/* On Win9x, make pid positive similarly to cygwin and perl */
	child->pid = -child->pid;
    }

    return child;
}

typedef struct _NtCmdLineElement {
    struct _NtCmdLineElement *next, *prev;
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

NtCmdLineElement *NtCmdHead = NULL, *NtCmdTail = NULL;

void
NtFreeCmdLine(void)
{
    NtCmdLineElement *ptr;
    
    while(NtCmdHead) {
	ptr = NtCmdHead;
	NtCmdHead = NtCmdHead->next;
	free(ptr);
    }
    NtCmdHead = NtCmdTail = NULL;
}

//
// This function expands wild card characters that were spotted 
// during the parse phase. The idea here is to call FindFirstFile and
// FindNextFile with the wildcard pattern specified, and splice in the
// resulting list of new names. If the wildcard pattern doesn't match 
// any existing files, just leave it in the list.
//
typedef struct {
    NtCmdLineElement *head;
    NtCmdLineElement *tail;
} ListInfo;

static void
insert(const char *path, VALUE vinfo)
{
    NtCmdLineElement *tmpcurr;
    ListInfo *listinfo = (ListInfo *)vinfo;

    tmpcurr = ALLOC(NtCmdLineElement);
    MEMZERO(tmpcurr, NtCmdLineElement, 1);
    tmpcurr->len = strlen(path);
    tmpcurr->str = ALLOC_N(char, tmpcurr->len + 1);
    tmpcurr->flags |= NTMALLOC;
    strcpy(tmpcurr->str, path);
    if (listinfo->tail) {
	listinfo->tail->next = tmpcurr;
	tmpcurr->prev = listinfo->tail;
	listinfo->tail = tmpcurr;
    }
    else {
	listinfo->tail = listinfo->head = tmpcurr;
    }
}

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 512
#endif

void
NtCmdGlob (NtCmdLineElement *patt)
{
    ListInfo listinfo;
    char buffer[MAXPATHLEN], *buf = buffer;
    char *p;

    listinfo.head = listinfo.tail = 0;

    if (patt->len >= MAXPATHLEN)
	buf = ruby_xmalloc(patt->len + 1);

    strncpy (buf, patt->str, patt->len);
    buf[patt->len] = '\0';
    for (p = buf; *p; p = CharNext(p))
	if (*p == '\\')
	    *p = '/';
    rb_globi(buf, insert, (VALUE)&listinfo);
    if (buf != buffer)
	free(buf);

    if (listinfo.head && listinfo.tail) {
	listinfo.head->prev = patt->prev;
	listinfo.tail->next = patt->next;
	if (listinfo.head->prev)
	    listinfo.head->prev->next = listinfo.head;
	if (listinfo.tail->next)
	    listinfo.tail->next->prev = listinfo.tail;
    }
    if (patt->flags & NTMALLOC)
	free(patt->str);
    // free(patt);  //TODO:  memory leak occures here. we have to fix it.
}

// 
// Check a command string to determine if it has I/O redirection
// characters that require it to be executed by a command interpreter
//

static bool
NtHasRedirection (char *cmd)
{
    int inquote = 0;
    char quote = '\0';
    char *ptr ;

    //
    // Scan the string, looking for redirection (< or >) or pipe 
    // characters (|) that are not in a quoted string
    //

    for (ptr = cmd; *ptr; ptr++) {

	switch (*ptr) {

	  case '\'':
	  case '\"':
	    if (inquote) {
		if (quote == *ptr) {
		    inquote = 0;
		    quote = '\0';
		}
	    }
	    else {
		quote = *ptr;
		inquote++;
	    }
	    break;

	  case '>':
	  case '<':
	  case '|':

	    if (!inquote)
		return TRUE;
	}
    }
    return FALSE;
}


int 
NtMakeCmdVector (char *cmdline, char ***vec, int InputCmd)
{
    int cmdlen = strlen(cmdline);
    int done, instring, globbing, quoted, len;
    int newline, need_free = 0, i;
    int elements, strsz;
    int slashes = 0;
    char *ptr, *base, *buffer;
    char **vptr;
    char quote;
    NtCmdLineElement *curr;

    //
    // just return if we don't have a command line
    //

    if (cmdlen == 0) {
	*vec = NULL;
	return 0;
    }

    cmdline = strdup(cmdline);

    //
    // strip trailing white space
    //

    ptr = cmdline+(cmdlen - 1);
    while(ptr >= cmdline && ISSPACE(*ptr))
        --ptr;
    *++ptr = '\0';


    //
    // Ok, parse the command line, building a list of CmdLineElements.
    // When we've finished, and it's an input command (meaning that it's
    // the processes argv), we'll do globing and then build the argument 
    // vector.
    // The outer loop does one interation for each element seen. 
    // The inner loop does one interation for each character in the element.
    //

    for (done = 0, ptr = cmdline; *ptr;) {

	//
	// zap any leading whitespace
	//

	while(ISSPACE(*ptr))
	    ptr++;
	base = ptr;

	for (done = newline = globbing = instring = quoted = 0; 
	     *ptr && !done; ptr++) {

	    //
	    // Switch on the current character. We only care about the
	    // white-space characters, the  wild-card characters, and the
	    // quote characters.
	    //

	    switch (*ptr) {
	      case '\\':
	        if (ptr[1] == '"') ptr++;
	        break;
	      case ' ':
	      case '\t':
#if 0
	      case '/':  // have to do this for NT/DOS option strings

		//
		// check to see if we're parsing an option switch
		//

		if (*ptr == '/' && base == ptr)
		    continue;
#endif
		//
		// if we're not in a string, then we're finished with this
		// element
		//

		if (!instring)
		    done++;
		break;

	      case '*':
	      case '?':

		// 
		// record the fact that this element has a wildcard character
		// N.B. Don't glob if inside a single quoted string
		//

		if (!(instring && quote == '\''))
		    globbing++;
		break;

	      case '\n':

		//
		// If this string contains a newline, mark it as such so
		// we can replace it with the two character sequence "\n"
		// (cmd.exe doesn't like raw newlines in strings...sigh).
		//

		newline++;
		break;

	      case '\'':
	      case '\"':

		//
		// if we're already in a string, see if this is the
		// terminating close-quote. If it is, we're finished with 
		// the string, but not neccessarily with the element.
		// If we're not already in a string, start one.
		//

		if (instring) {
		    if (quote == *ptr) {
			instring = 0;
			quote = '\0';
		    }
		}
		else {
		    instring++;
		    quote = *ptr;
		    quoted++;
		}
		break;
	    }
	}

	//
	// need to back up ptr by one due to last increment of for loop
	// (if we got out by seeing white space)
	//

	if (*ptr)
	    ptr--;

	//
	// when we get here, we've got a pair of pointers to the element,
	// base and ptr. Base points to the start of the element while ptr
	// points to the character following the element.
	//

	curr = ALLOC(NtCmdLineElement);
	memset (curr, 0, sizeof(*curr));

	len = ptr - base;

	//
	// if it's an input vector element and it's enclosed by quotes, 
	// we can remove them.
	//

	if (InputCmd && (base[0] == '\"' && base[len-1] == '\"')) {
	    char *p;
	    base++;
	    len -= 2;
	    base[len] = 0;
	    for (p = base; p < base + len; p++) {
		if ((p[0] == '\\' || p[0] == '\"') && p[1] == '"') {
		    strcpy(p, p + 1);
		    len--;
		}
	    }
	}
	else if (InputCmd && (base[0] == '\'' && base[len-1] == '\'')) {
	    base++;
	    len -= 2;
	}

	curr->str = base;
	curr->len = len;
	curr->flags |= (globbing ? NTGLOB : 0);

	//
	// Now put it in the list of elements
	//
	if (NtCmdTail) {
	    NtCmdTail->next = curr;
	    curr->prev = NtCmdTail;
	    NtCmdTail = curr;
	}
	else {
	    NtCmdHead = NtCmdTail = curr;
	}
    }

    if (InputCmd) {

	//
	// When we get here we've finished parsing the command line. Now 
	// we need to run the list, expanding any globbing patterns.
	//
	
	for(curr = NtCmdHead; curr; curr = curr->next) {
	    if (curr->flags & NTGLOB) {
		NtCmdGlob(curr);
	    }
	}
    }

    //
    // Almost done! 
    // Count up the elements, then allocate space for a vector of pointers
    // (argv) and a string table for the elements.
    // 

    for (elements = 0, strsz = 0, curr = NtCmdHead; curr; curr = curr->next) {
	elements++;
	strsz += (curr->len + 1);
    }

    len = (elements+1)*sizeof(char *) + strsz;
    buffer = ALLOC_N(char, len);
    
    memset (buffer, 0, len);

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

    for (curr =  NtCmdHead; curr;  curr = curr->next) {
	strncpy (ptr, curr->str, curr->len);
	ptr[curr->len] = '\0';
	*vptr++ = ptr;
	ptr += curr->len + 1;
    }
    NtFreeCmdLine();
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

DIR *
rb_w32_opendir(const char *filename)
{
    DIR            *p;
    long            len;
    long            idx;
    char            scannamespc[PATHLEN];
    char	   *scanname = scannamespc;
    struct stat	    sbuf;
    WIN32_FIND_DATA FindData;
    HANDLE          fh;

    //
    // check to see if we've got a directory
    //

    if ((rb_w32_stat (filename, &sbuf) < 0 ||
#ifdef __BORLANDC__
	(unsigned short)(sbuf.st_mode) & _S_IFDIR == 0) &&
#else
	sbuf.st_mode & _S_IFDIR == 0) &&
#endif
	(!ISALPHA(filename[0]) || filename[1] != ':' || filename[2] != '\0' ||
	((1 << (filename[0] & 0x5f) - 'A') & GetLogicalDrives()) == 0)) {
	return NULL;
    }

    //
    // Get us a DIR structure
    //

    p = xcalloc(sizeof(DIR), 1);
    if (p == NULL)
	return NULL;
    
    //
    // Create the search pattern
    //

    strcpy(scanname, filename);

    if (index("/\\:", *CharPrev(scanname, scanname + strlen(scanname))) == NULL)
	strcat(scanname, "/*");
    else
	strcat(scanname, "*");

    //
    // do the FindFirstFile call
    //

    fh = FindFirstFile (scanname, &FindData);
    if (fh == INVALID_HANDLE_VALUE) {
	return NULL;
    }

    //
    // now allocate the first part of the string table for the
    // filenames that we find.
    //

    idx = strlen(FindData.cFileName)+1;
    p->start = ALLOC_N(char, idx);
    strcpy (p->start, FindData.cFileName);
    p->nfiles++;
    
    //
    // loop finding all the files that match the wildcard
    // (which should be all of them in this directory!).
    // the variable idx should point one past the null terminator
    // of the previous string found.
    //
    while (FindNextFile(fh, &FindData)) {
	len = strlen (FindData.cFileName);

	//
	// bump the string table size by enough for the
	// new name and it's null terminator 
	//

	#define Renew(x, y, z) (x = (z *)realloc(x, y))

	Renew (p->start, idx+len+1, char);
	if (p->start == NULL) {
            rb_fatal ("opendir: malloc failed!\n");
	}
	strcpy(&p->start[idx], FindData.cFileName);
	p->nfiles++;
	idx += len+1;
    }
    FindClose(fh);
    p->size = idx;
    p->curr = p->start;
    return p;
}


//
// Readdir just returns the current string pointer and bumps the
// string pointer to the next entry.
//

struct direct  *
rb_w32_readdir(DIR *dirp)
{
    int         len;
    static int  dummy = 0;

    if (dirp->curr) {

	//
	// first set up the structure to return
	//

	len = strlen(dirp->curr);
	strcpy(dirp->dirstr.d_name, dirp->curr);
	dirp->dirstr.d_namlen = len;

	//
	// Fake inode
	//
	dirp->dirstr.d_ino = dummy++;

	//
	// Now set up for the next call to readdir
	//

	dirp->curr += len + 1;
	if (dirp->curr >= (dirp->start + dirp->size)) {
	    dirp->curr = NULL;
	}

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
	return (long) dirp->curr;	/* ouch! pointer to long cast */
}

//
// Seekdir moves the string pointer to a previously saved position
// (Saved by telldir).

void
rb_w32_seekdir(DIR *dirp, long loc)
{
	dirp->curr = (char *) loc;	/* ouch! long to pointer cast */
}

//
// Rewinddir resets the string pointer to the start
//

void
rb_w32_rewinddir(DIR *dirp)
{
	dirp->curr = dirp->start;
}

//
// This just free's the memory allocated by opendir
//

void
rb_w32_closedir(DIR *dirp)
{
	free(dirp->start);
	free(dirp);
}

static int 
valid_filename(char *s)
{
    int fd;

    //
    // if the file exists, then it's a valid filename!
    //

    if (_access(s, 0) == 0) {
	return 1;
    }

    //
    // It doesn't exist, so see if we can open it.
    //
    
    if ((fd = _open(s, _O_CREAT, 0666)) >= 0) {
	close(fd);
	_unlink (s);	// don't leave it laying around
	return 1;
    }
    return 0;
}

//
// This is a clone of fdopen so that we can handle the 
// brain damaged version of sockets that NT gets to use.
//
// The problem is that sockets are not real file handles and 
// cannot be fdopen'ed. This causes problems in the do_socket
// routine in doio.c, since it tries to create two file pointers
// for the socket just created. We'll fake out an fdopen and see
// if we can prevent perl from trying to do stdio on sockets.
//

//EXTERN_C int __cdecl _alloc_osfhnd(void);
//EXTERN_C int __cdecl _set_osfhnd(int fh, long value);
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
#endif
}	ioinfo;

#if !defined _CRTIMP
#define _CRTIMP __declspec(dllimport)
#endif

#ifndef __BORLANDC__
EXTERN_C _CRTIMP ioinfo * __pioinfo[];

#define IOINFO_L2E			5
#define IOINFO_ARRAY_ELTS	(1 << IOINFO_L2E)
#define _pioinfo(i)	(__pioinfo[i >> IOINFO_L2E] + (i & (IOINFO_ARRAY_ELTS - 1)))
#define _osfhnd(i)  (_pioinfo(i)->osfhnd)
#define _osfile(i)  (_pioinfo(i)->osfile)
#define _pipech(i)  (_pioinfo(i)->pipech)

#define _set_osfhnd(fh, osfh) (void)(_osfhnd(fh) = osfh)
#define _set_osflags(fh, flags) (_osfile(fh) = (flags))

#else

#define _set_osfhnd(fh, osfh) (void)((fh), (osfh))
#define _set_osflags(fh, flags) (void)((fh), (flags))

#endif

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

    /* copy relevant flags from second parameter */
    fileflags = FDEV;

    if (flags & O_APPEND)
	fileflags |= FAPPEND;

    if (flags & O_TEXT)
	fileflags |= FTEXT;

    if (flags & O_NOINHERIT)
	fileflags |= FNOINHERIT;

    RUBY_CRITICAL({
	/* attempt to allocate a C Runtime file handle */
	HANDLE hF = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
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
    });
    return fh;			/* return handle */
}

#undef getsockopt

static int
is_socket(SOCKET fd)
{
    char sockbuf[80];
    int optlen;
    int retval;

    optlen = sizeof(sockbuf);
    retval = getsockopt(fd, SOL_SOCKET, SO_TYPE, sockbuf, &optlen);
    if (retval == SOCKET_ERROR) {
	int iRet;

	iRet = WSAGetLastError();
	if (iRet == WSAENOTSOCK || iRet == WSANOTINITIALISED)
	    return FALSE;
    }

    //
    // If we get here, then fd is actually a socket.
    //

    return TRUE;
}

int
rb_w32_fddup (int fd)
{
    SOCKET s = TO_SOCKET(fd);

    if (s == -1)
	return -1;

    return rb_w32_open_osfhandle(s, O_RDWR|O_BINARY);
}


void
rb_w32_fdclose(FILE *fp)
{
    RUBY_CRITICAL({
	STHREAD_ONLY(_free_osfhnd(fileno(fp)));
	fclose(fp);
    });
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
#if !defined __MINGW32__
    extern int sys_nerr;
#endif
    DWORD source = 0;
    char *p;

    if (e < 0 || e > sys_nerr) {
	if (e < 0)
	    e = GetLastError();
	if (FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
			  FORMAT_MESSAGE_IGNORE_INSERTS, &source, e, 0,
			  buffer, 512, NULL) == 0) {
	    strcpy(buffer, "Unknown Error");
	}
	for (p = buffer + strlen(buffer) - 1; buffer <= p; p--) {
	    if (*p != '\r' && *p != '\n') break;
	    *p = 0;
	}
	return buffer;
    }
    return strerror(e);
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

UIDTYPE
getuid(void)
{
	return ROOT_UID;
}

UIDTYPE
geteuid(void)
{
	return ROOT_UID;
}

GIDTYPE
getgid(void)
{
	return ROOT_GID;
}

GIDTYPE
getegid(void)
{
    return ROOT_GID;
}

int
setuid(int uid)
{ 
    return (uid == ROOT_UID ? 0 : -1);
}

int
setgid(int gid)
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
       return __WSAFDIsSet(TO_SOCKET(fd), set);
}

//
// Networking trampolines
// These are used to avoid socket startup/shutdown overhead in case 
// the socket routines aren't used.
//

#undef select

static int NtSocketsInitialized = 0;

static int
extract_file_fd(fd_set *set, fd_set *fileset)
{
    int idx;

    fileset->fd_count = 0;
    if (!set)
	return 0;
    for (idx = 0; idx < set->fd_count; idx++) {
	SOCKET fd = set->fd_array[idx];

	if (!is_socket(fd)) {
	    int i;

	    for (i = 0; i < fileset->fd_count; i++) {
		if (fileset->fd_array[i] == fd) {
		    break;
		}
	    }
	    if (i == fileset->fd_count) {
		if (fileset->fd_count < FD_SETSIZE) {
		    fileset->fd_array[i] = fd;
		    fileset->fd_count++;
		}
	    }
	}
    }
    return fileset->fd_count;
}

long 
rb_w32_select (int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
	       struct timeval *timeout)
{
    long r;
    fd_set file_rd;
    fd_set file_wr;
#ifdef USE_INTERRUPT_WINSOCK
    fd_set trap;
#endif /* USE_INTERRUPT_WINSOCK */
    int file_nfds;

    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    r = 0;
    if (rd && rd->fd_count > r) r = rd->fd_count;
    if (wr && wr->fd_count > r) r = wr->fd_count;
    if (ex && ex->fd_count > r) r = ex->fd_count;
    if (nfds > r) nfds = r;
    if (nfds == 0 && timeout) {
	Sleep(timeout->tv_sec * 1000 + timeout->tv_usec / 1000);
	return 0;
    }
    file_nfds = extract_file_fd(rd, &file_rd);
    file_nfds += extract_file_fd(wr, &file_wr);
    if (file_nfds)
    {
	// assume normal files are always readable/writable
	// fake read/write fd_set and return value
	if (rd) *rd = file_rd;
	if (wr) *wr = file_wr;
	return file_nfds;
    }

#if USE_INTERRUPT_WINSOCK
    if (ex)
	trap = *ex;
    else
	trap.fd_count = 0;
    if (trap.fd_count < FD_SETSIZE)
	trap.fd_array[trap.fd_count++] = (SOCKET)interrupted_event;
    // else unable to catch interrupt.
    ex = &trap;
#endif /* USE_INTERRUPT_WINSOCK */

    RUBY_CRITICAL(r = select (nfds, rd, wr, ex, timeout));
    if (r == SOCKET_ERROR) {
	errno = WSAGetLastError();
	switch (errno) {
	  case WSAEINTR:
	    errno = EINTR;
	    break;
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
	int iSockOpt;
    
    //
    // initalize the winsock interface and insure that it's
    // cleaned up at exit.
    //
    version = MAKEWORD(1, 1);
    if (ret = WSAStartup(version, &retdata))
	rb_fatal ("Unable to locate winsock library!\n");
    if (LOBYTE(retdata.wVersion) != 1)
	rb_fatal("could not find version 1 of winsock dll\n");

    if (HIBYTE(retdata.wVersion) != 1)
	rb_fatal("could not find version 1 of winsock dll\n");

    atexit((void (*)(void)) WSACleanup);

#ifndef SO_SYNCHRONOUS_NONALERT
#define SO_SYNCHRONOUS_NONALERT 0x20
#endif

    iSockOpt = SO_SYNCHRONOUS_NONALERT;
    /*
     * Enable the use of sockets as filehandles
     */
#ifndef SO_OPENTYPE
#define SO_OPENTYPE     0x7008
#endif

    setsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE,
	       (char *)&iSockOpt, sizeof(iSockOpt));

    main_thread.handle = GetCurrentThreadHandle();
    main_thread.id = GetCurrentThreadId();

    interrupted_event = CreateSignal();
    if (!interrupted_event)
	rb_fatal("Unable to create interrupt event!\n");
}

#undef accept

SOCKET
rb_w32_accept (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    SOCKET r;

    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = accept (TO_SOCKET(s), addr, addrlen));
    if (r == INVALID_SOCKET)
	errno = WSAGetLastError();
    return rb_w32_open_osfhandle(r, O_RDWR|O_BINARY);
}

#undef bind

int 
rb_w32_bind (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;

    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = bind (TO_SOCKET(s), addr, addrlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef connect

int 
rb_w32_connect (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = connect (TO_SOCKET(s), addr, addrlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}


#undef getpeername

int 
rb_w32_getpeername (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getpeername (TO_SOCKET(s), addr, addrlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getsockname

int 
rb_w32_getsockname (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getsockname (TO_SOCKET(s), addr, addrlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

int 
rb_w32_getsockopt (SOCKET s, int level, int optname, char *optval, int *optlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getsockopt (TO_SOCKET(s), level, optname, optval, optlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef ioctlsocket

int 
rb_w32_ioctlsocket (SOCKET s, long cmd, u_long *argp)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = ioctlsocket (TO_SOCKET(s), cmd, argp));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef listen

int 
rb_w32_listen (SOCKET s, int backlog)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = listen (TO_SOCKET(s), backlog));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recv

int 
rb_w32_recv (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = recv (TO_SOCKET(s), buf, len, flags));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recvfrom

int 
rb_w32_recvfrom (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *from, int *fromlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = recvfrom (TO_SOCKET(s), buf, len, flags, from, fromlen));
    if (r == SOCKET_ERROR)
	errno =  WSAGetLastError();
    return r;
}

#undef send

int 
rb_w32_send (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = send (TO_SOCKET(s), buf, len, flags));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef sendto

int 
rb_w32_sendto (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *to, int tolen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = sendto (TO_SOCKET(s), buf, len, flags, to, tolen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef setsockopt

int 
rb_w32_setsockopt (SOCKET s, int level, int optname, char *optval, int optlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = setsockopt (TO_SOCKET(s), level, optname, optval, optlen));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}
    
#undef shutdown

int 
rb_w32_shutdown (SOCKET s, int how)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = shutdown (TO_SOCKET(s), how));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef socket

SOCKET 
rb_w32_socket (int af, int type, int protocol)
{
    SOCKET s;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(s = socket (af, type, protocol));
    if (s == INVALID_SOCKET) {
	errno = WSAGetLastError();
	//fprintf(stderr, "socket fail (%d)", WSAGetLastError());
    }
#ifdef __BORLANDC__
    return _open_osfhandle(s, O_RDWR|O_BINARY);
#else
    return rb_w32_open_osfhandle(s, O_RDWR|O_BINARY);
#endif
}

#undef gethostbyaddr

struct hostent *
rb_w32_gethostbyaddr (char *addr, int len, int type)
{
    struct hostent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = gethostbyaddr (addr, len, type));
    if (r == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef gethostbyname

struct hostent *
rb_w32_gethostbyname (char *name)
{
    struct hostent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = gethostbyname (name));
    if (r == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef gethostname

int
rb_w32_gethostname (char *name, int len)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = gethostname (name, len));
    if (r == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getprotobyname

struct protoent *
rb_w32_getprotobyname (char *name)
{
    struct protoent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getprotobyname (name));
    if (r == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getprotobynumber

struct protoent *
rb_w32_getprotobynumber (int num)
{
    struct protoent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getprotobynumber (num));
    if (r == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getservbyname

struct servent *
rb_w32_getservbyname (char *name, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getservbyname (name, proto));
    if (r == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getservbyport

struct servent *
rb_w32_getservbyport (int port, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    RUBY_CRITICAL(r = getservbyport (port, proto));
    if (r == NULL)
	errno = WSAGetLastError();
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

struct netent *getnetbyaddr(char *name) {return (struct netent *)NULL;}

struct netent *getnetbyname(long net, int type) {return (struct netent *)NULL;}

struct protoent *getprotoent (void) {return (struct protoent *) NULL;}

struct servent *getservent (void) {return (struct servent *) NULL;}

void sethostent (int stayopen) {}

void setnetent (int stayopen) {}

void setprotoent (int stayopen) {}

void setservent (int stayopen) {}

#ifndef WNOHANG
#define WNOHANG -1
#endif

static pid_t
poll_child_status(struct ChildRecord *child, int *stat_loc)
{
    DWORD exitcode;

    if (!GetExitCodeProcess(child->hProcess, &exitcode)) {
	/* If an error occured, return immediatly. */
	errno = GetLastError();
	if (errno == ERROR_INVALID_PARAMETER) {
	    errno = ECHILD;
	}
	CloseChildHandle(child);
	return -1;
    }
    if (exitcode != STILL_ACTIVE) {
	/* If already died, return immediatly. */
	pid_t pid = child->pid;
	CloseChildHandle(child);
	if (stat_loc) *stat_loc = exitcode << 8;
	return pid;
    }
    return 0;
}

pid_t
waitpid (pid_t pid, int *stat_loc, int options)
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
	    errno = GetLastError();
	    return -1;
	}

	return poll_child_status(ChildRecord + ret, stat_loc);
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

int _cdecl
gettimeofday(struct timeval *tv, struct timezone *tz)
{
    SYSTEMTIME st;
    time_t t;
    struct tm tm;

    GetLocalTime(&st);
    tm.tm_sec = st.wSecond;
    tm.tm_min = st.wMinute;
    tm.tm_hour = st.wHour;
    tm.tm_mday = st.wDay;
    tm.tm_mon = st.wMonth - 1;
    tm.tm_year = st.wYear - 1900;
    tm.tm_isdst = -1;
    t = mktime(&tm);
    tv->tv_sec = t;
    tv->tv_usec = st.wMilliseconds * 1000;

    return 0;
}

char *
rb_w32_getcwd(buffer, size)
    char *buffer;
    int size;
{
    int length;
    char *bp;

#ifdef __BORLANDC__
#undef getcwd
    if (getcwd(buffer, size) == NULL) {
#else
    if (_getcwd(buffer, size) == NULL) {
#endif
        return NULL;
    }
    length = strlen(buffer);
    if (length >= size) {
        return NULL;
    }

    for (bp = buffer; *bp != '\0'; bp = CharNext(bp)) {
	if (*bp == '\\') {
	    *bp = '/';
	}
    }
    return buffer;
}

static char *
str_grow(struct RString *str, size_t new_size)
{
	char *p;

	p = realloc(str->ptr, new_size);
	if (p == NULL)
                rb_fatal("cannot grow string\n");

	str->len = new_size;
	str->ptr = p;

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

    if (pid <= 0) {
	errno = EINVAL;
	return -1;
    }

    if (IsWin95()) pid = -pid;
    if ((unsigned int)pid == GetCurrentProcessId() && sig != SIGKILL)
	return raise(sig);

    switch (sig) {
      case SIGINT:
	RUBY_CRITICAL({
	    if (!GenerateConsoleCtrlEvent(CTRL_C_EVENT, (DWORD)pid)) {
		if ((errno = GetLastError()) == 0) {
		    errno = EPERM;
		}
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
	    else if (!TerminateProcess(hProc, 0)) {
		errno = EPERM;
		ret = -1;
	    }
	    CloseHandle(hProc);
	});
	break;

      define:
	errno = EINVAL;
	ret = -1;
	break;
    }

    return ret;
}

int
link(char *from, char *to)
{
	return -1;
}

int
wait()
{
	return 0;
}

char *
rb_w32_getenv(const char *name)
{
    static char *curitem = NULL;
    static DWORD curlen = 0;
    DWORD needlen;

    if (curitem == NULL || curlen == 0) {
	curlen = 512;
	curitem = ALLOC_N(char, curlen);
    }

    needlen = GetEnvironmentVariable(name, curitem, curlen);
    if (needlen != 0) {
	while (needlen > curlen) {
	    REALLOC_N(curitem, char, needlen);
	    curlen = needlen;
	    needlen = GetEnvironmentVariable(name, curitem, curlen);
	}
    }
    else {
	return NULL;
    }

    return curitem;
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
	errno = GetLastError();
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
	    errno = GetLastError();
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
	for (p = path + 3; *p; p = CharNext(p)) {
	    if (*p == '\\')
		break;
	}
	if (p[0] && p[1]) {
	    for (p++; *p; p = CharNext(p)) {
		if (*p == '\\')
		    break;
	    }
	    if (!p[0] || !p[1])
		return 1;
	}
    }
    return 0;
}

int
rb_w32_stat(const char *path, struct stat *st)
{
    const char *p;
    char *buf1 = ALLOCA_N(char, strlen(path) + 2);
    char *buf2 = ALLOCA_N(char, MAXPATHLEN);
    char *s;
    int len;
    int ret;

    for (p = path, s = buf1; *p; p++, s++) {
	if (*p == '/')
	    *s = '\\';
	else
	    *s = *p;
    }
    *s = '\0';
    len = strlen(buf1);
    p = CharPrev(buf1, buf1 + len);
    if (isUNCRoot(buf1)) {
	if (*p != '\\')
	    strcat(buf1, "\\");
    } else if (*p == '\\' || *p == ':')
	strcat(buf1, ".");
    if (_fullpath(buf2, buf1, MAXPATHLEN)) {
	ret = stat(buf2, st);
	if (ret == 0) {
	    st->st_mode &= ~(S_IWGRP | S_IWOTH);
	}
	return ret;
    }
    else
	return -1;
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

#undef Sleep
#define yield_once() Sleep(0)
#define yield_until(condition) do yield_once(); while (!(condition))

static DWORD wait_events(HANDLE event, DWORD timeout)
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

static CRITICAL_SECTION* system_state(void)
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

void rb_w32_enter_critical(void)
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

void rb_w32_leave_critical(void)
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

static void rb_w32_call_handler(struct handler_arg_t* h)
{
    int status;
    RUBY_CRITICAL(rb_protect((VALUE (*)(VALUE))h->handler, (VALUE)h->arg, &h->status);
		  status = h->status;
		  SetEvent(h->handshake));
    if (status) {
	rb_jump_tag(status);
    }
    h->finished = 1;
    Sleep(INFINITE);		/* safe on Win95? */
}

static struct handler_arg_t* setup_handler(struct handler_arg_t *harg,
					   int arg,
					   void (*handler)(int),
					   HANDLE handshake)
{
    harg->handler = handler;
    harg->arg = arg;
    harg->status = 0;
    harg->finished = 0;
    harg->handshake = handshake;
    return harg;
}

static void setup_call(CONTEXT* ctx, struct handler_arg_t *harg)
{
#ifdef _M_IX86
    DWORD *esp = (DWORD *)ctx->Esp;
    *--esp = (DWORD)harg;
    *--esp = ctx->Eip;
    ctx->Esp = (DWORD)esp;
    ctx->Eip = (DWORD)rb_w32_call_handler;
#else
#error unsupported processor
#endif
}

int rb_w32_main_context(int arg, void (*handler)(int))
{
    static HANDLE interrupt_done = NULL;
    struct handler_arg_t harg;
    CONTEXT ctx_orig;
    HANDLE current_thread = GetCurrentThread();
    int old_priority = GetThreadPriority(current_thread);

    if (GetCurrentThreadId() == main_thread.id) return FALSE;

    SetSignal(interrupted_event);

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

int rb_w32_sleep(unsigned long msec)
{
    DWORD ret;
    RUBY_CRITICAL(ret = wait_events(NULL, msec));
    yield_once();
    CHECK_INTS;
    return ret != WAIT_TIMEOUT;
}

static void catch_interrupt(void)
{
    yield_once();
    RUBY_CRITICAL(wait_events(NULL, 0));
    CHECK_INTS;
}

#undef fgetc
int rb_w32_getc(FILE* stream)
{
    int c, trap_immediate = rb_trap_immediate;
    if (--stream->FILE_COUNT >= 0) {
	c = (unsigned char)*stream->FILE_READPTR++;
	rb_trap_immediate = trap_immediate;
    }
    else {
	c = _filbuf(stream);
#ifdef __BORLANDC__
        if( ( c == EOF )&&( errno == EPIPE ) )
        {
          clearerr(stream);
        }
#endif
	rb_trap_immediate = trap_immediate;
	catch_interrupt();
    }
    return c;
}

#undef fputc
int rb_w32_putc(int c, FILE* stream)
{
    int trap_immediate = rb_trap_immediate;
    if (--stream->FILE_COUNT >= 0) {
	c = (unsigned char)(*stream->FILE_READPTR++ = (char)c);
	rb_trap_immediate = trap_immediate;
    }
    else {
	c = _flsbuf(c, stream);
	rb_trap_immediate = trap_immediate;
	catch_interrupt();
    }
    return c;
}

struct asynchronous_arg_t {
    /* output field */
    void* stackaddr;

    /* input field */
    VALUE (*func)(VALUE self, int argc, VALUE* argv);
    VALUE self;
    int argc;
    VALUE* argv;
};

static DWORD WINAPI
call_asynchronous(PVOID argp)
{
    struct asynchronous_arg_t *arg = argp;
    arg->stackaddr = &argp;
    return (DWORD)arg->func(arg->self, arg->argc, arg->argv);
}

VALUE rb_w32_asynchronize(asynchronous_func_t func,
			 VALUE self, int argc, VALUE* argv, VALUE intrval)
{
    DWORD val;
    BOOL interrupted = FALSE;
    HANDLE thr;

    RUBY_CRITICAL({
	struct asynchronous_arg_t arg;

	arg.stackaddr = NULL;
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
	    }
	}
    });

    if (!thr) {
	rb_fatal("failed to launch waiter thread:%d", GetLastError());
    }

    if (interrupted) {
	errno = EINTR;
	CHECK_INTS;
    }

    return val;
}

char **rb_w32_get_environ(void)
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

    myenvtop = ALLOC_N(char*, num + 1);
    for (env = envtop, myenv = myenvtop; *env; env += strlen(env) + 1) {
	if (*env != '=') {
	    *myenv = ALLOC_N(char, strlen(env) + 1);
	    strcpy(*myenv, env);
	    myenv++;
	}
    }
    *myenv = NULL;
    FreeEnvironmentStrings(envtop);

    return myenvtop;
}

void rb_w32_free_environ(char **env)
{
    char **t = env;

    while (*t) free(*t++);
    free(env);
}

pid_t rb_w32_getpid(void)
{
    pid_t pid;

    pid = _getpid();
    if (IsWin95()) pid = -pid;

    return pid;
}
