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
#include "dir.h"
#ifndef index
#define index(x, y) strchr((x), (y))
#endif
#define isdirsep(x) ((x) == '/' || (x) == '\\')

#undef fclose
#undef close
#undef setsockopt

#ifndef bool
#define bool int
#endif

#if USE_INTERRUPT_WINSOCK

# if defined(_MSC_VER) && _MSC_VER <= 1000
/* VC++4.0 doesn't have this. */
extern DWORD WSAWaitForMultipleEvents(DWORD nevent, const HANDLE *events,
				      BOOL waitall, DWORD timeout,
				      BOOL alertable);
# endif

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
#if 0  // declared in header file
extern char **environ;
#define environ _environ
#endif

static bool NtHasRedirection (char *);
static int valid_filename(char *s);
static void StartSockets ();
static char *str_grow(struct RString *str, size_t new_size);
static DWORD wait_events(HANDLE event, DWORD timeout);

char *NTLoginName;

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

#undef LK_ERR
#undef LK_LEN

int
flock(int fd, int oper)
{
    static asynchronous_func_t locker = NULL;

    if (!locker) {
	if (IsWinNT())
	    locker = flock_winnt;
	else
	    locker = flock_win95;
    }

    return win32_asynchronize(locker,
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
    // subvert cmd.exe\'s feeble attempt at command line parsing
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



#if 1
// popen stuff

//
// use these so I can remember which index is which
//

#define NtPipeRead  0	   // index of pipe read descriptor
#define NtPipeWrite 1	   // index of pipe write descriptor

#define NtPipeSize  1024   // size of pipe buffer

#define MYPOPENSIZE 256	   // size of book keeping structure

struct {
    int inuse;
    int pid;
    FILE *pipe;
} MyPopenRecord[MYPOPENSIZE];

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
myget_osfhandle(int fh)
{
    return _get_osfhandle(fh);

}


FILE *
mypopen (char *cmd, char *mode) 
{
    FILE *fp;
    int saved, reading;
    int pipemode;
    int pipes[2];
    int pid;
    int slot;
    static initialized = 0;

    //
    // if first time through, intialize our book keeping structure
    //

    if (!initialized++) {
	for (slot = 0; slot < MYPOPENSIZE; slot++)
	    MyPopenRecord[slot].inuse = FALSE;
    }

    //printf("mypopen %s\n", cmd);
    
    //
    // find a free popen slot
    //

    for (slot = 0; slot < MYPOPENSIZE && MyPopenRecord[slot].inuse; slot++)
	;

    if (slot > MYPOPENSIZE) {
	return NULL;
    }

    //
    // Figure out what we\'re doing...
    //

    reading = (*mode == 'r') ? TRUE : FALSE;
    pipemode = (*(mode+1) == 'b') ? O_BINARY : O_TEXT;

    //
    // Now get a pipe
    //

#if 0    
    if (_pipe(pipes, NtPipeSize, pipemode) == -1) {
	return NULL;
    }

    if (reading) {

	//
	// we\'re reading from the pipe, so we must hook up the
	// write end of the pipe to the new processes stdout.
	// To do this we must save our file handle from stdout
	// by _dup\'ing it, then setting our stdout to be the pipe\'s 
	// write descriptor. We must also make the write handle 
	// inheritable so the new process can use it.

	if ((saved = _dup(fileno(stdout))) == -1) {
	    _close(pipes[NtPipeRead]);
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
	if (_dup2 (pipes[NtPipeWrite], fileno(stdout)) == -1) {
	    _close(pipes[NtPipeRead]);
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
    }
    else {
	//
	// must be writing to the new process. Do the opposite of
	// the above, i.e. hook up the processes stdin to the read
	// end of the pipe.
	//

	if ((saved = _dup(fileno(stdin))) == -1) {
	    _close(pipes[NtPipeRead]);
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
	if (_dup2(pipes[NtPipeRead], fileno(stdin)) == -1) {
	    _close(pipes[NtPipeRead]);
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
    }

    //
    // Start the new process. Must set _fileinfo to non-zero value
    // for file descriptors to be inherited. Reset after the process
    // is started.
    //

    if (NtHasRedirection(cmd)) {
      docmd:
	pid = spawnlpe(_P_NOWAIT, "cmd.exe", "/c", cmd, 0, environ);
	if (pid == -1) {
	    _close(pipes[NtPipeRead]);
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
    }
    else {
	char **vec;
	int vecc = NtMakeCmdVector(cmd, &vec, FALSE);

	//pid = spawnvpe (_P_NOWAIT, vec[0], vec, environ);
	pid = spawnvpe (_P_WAIT, vec[0], vec, environ);
	if (pid == -1) {
	    goto docmd;
	}
		Safefree (vec, vecc);
    }

    if (reading) {

	//
	// We need to close our instance of the inherited pipe write
	// handle now that it's been inherited so that it will actually close
	// when the child process ends.
	//

	if (_close(pipes[NtPipeWrite]) == -1) {
	    _close(pipes[NtPipeRead]);
	    return NULL;
	}
	if (_dup2 (saved, fileno(stdout)) == -1) {
	    _close(pipes[NtPipeRead]);
	    return NULL;
	}
	_close(saved);

	// 
	// Now get a stream pointer to return to the calling program.
	//

	if ((fp = (FILE *) fdopen(pipes[NtPipeRead], mode)) == NULL) {
	    return NULL;
	}
    }
    else {

	//
	// need to close our read end of the pipe so that it will go 
	// away when the write end is closed.
	//

	if (_close(pipes[NtPipeRead]) == -1) {
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
	if (_dup2 (saved, fileno(stdin)) == -1) {
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
	_close(saved);

	// 
	// Now get a stream pointer to return to the calling program.
	//

	if ((fp = (FILE *) fdopen(pipes[NtPipeWrite], mode)) == NULL) {
	    _close(pipes[NtPipeWrite]);
	    return NULL;
	}
    }

    //
    // do the book keeping
    //

    MyPopenRecord[slot].inuse = TRUE;
    MyPopenRecord[slot].pipe = fp;
    MyPopenRecord[slot].pid = pid;

    return fp;
#else
    {
		int p[2];

		BOOL fRet;
		HANDLE hInFile, hOutFile;
		LPCSTR lpApplicationName = NULL;
		LPTSTR lpCommandLine;
		LPTSTR lpCmd2 = NULL;
		DWORD  dwCreationFlags;
		STARTUPINFO aStartupInfo;
		PROCESS_INFORMATION     aProcessInformation;
		SECURITY_ATTRIBUTES sa;
		int fd;

		sa.nLength              = sizeof (SECURITY_ATTRIBUTES);
		sa.lpSecurityDescriptor = NULL;
		sa.bInheritHandle       = TRUE;

		fRet = CreatePipe(&hInFile, &hOutFile, &sa, 2048L);
		if (!fRet) {
			errno = GetLastError();
			rb_sys_fail("mypopen: CreatePipe");
		}

		memset(&aStartupInfo, 0, sizeof (STARTUPINFO));
		memset(&aProcessInformation, 0, sizeof (PROCESS_INFORMATION));
		aStartupInfo.cb = sizeof (STARTUPINFO);
		aStartupInfo.dwFlags    = STARTF_USESTDHANDLES;

		if (reading) {
			aStartupInfo.hStdInput  = GetStdHandle(STD_INPUT_HANDLE);
			aStartupInfo.hStdOutput = hOutFile;
		}
		else {
			aStartupInfo.hStdInput  = hInFile;
			aStartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
		}
		aStartupInfo.hStdError  = GetStdHandle(STD_ERROR_HANDLE);

		dwCreationFlags = (NORMAL_PRIORITY_CLASS);

		lpCommandLine = cmd;
		if (NtHasRedirection(cmd) || isInternalCmd(cmd)) {
		  lpApplicationName = getenv("COMSPEC");
		  lpCmd2 = xmalloc(strlen(lpApplicationName) + 1 + strlen(cmd) + sizeof (" /c "));
		  sprintf(lpCmd2, "%s %s%s", lpApplicationName, " /c ", cmd);
		  lpCommandLine = lpCmd2;
		}

		fRet = CreateProcess(lpApplicationName, lpCommandLine, &sa, &sa,
			sa.bInheritHandle, dwCreationFlags, NULL, NULL, &aStartupInfo, &aProcessInformation);
		errno = GetLastError();

		if (lpCmd2)
			free(lpCmd2);

		if (!fRet) {
			CloseHandle(hInFile);
			CloseHandle(hOutFile);
			return NULL;
		}

		CloseHandle(aProcessInformation.hThread);

		if (reading) {
			fd = _open_osfhandle((long)hInFile,  (_O_RDONLY | pipemode));
			CloseHandle(hOutFile);
		}
		else {
			fd = _open_osfhandle((long)hOutFile, (_O_WRONLY | pipemode));
			CloseHandle(hInFile);
		}

		if (fd == -1) {
			CloseHandle(reading ? hInFile : hOutFile);
			CloseHandle(aProcessInformation.hProcess);
			rb_sys_fail("mypopen: _open_osfhandle");
		}

		if ((fp = (FILE *) fdopen(fd, mode)) == NULL) {
			_close(fd);
			CloseHandle(aProcessInformation.hProcess);
			rb_sys_fail("mypopen: fdopen");
		}

		MyPopenRecord[slot].inuse = TRUE;
		MyPopenRecord[slot].pipe  = fp;
		MyPopenRecord[slot].pid   = (int)aProcessInformation.hProcess;
		return fp;
    }
#endif
}

int
mypclose(FILE *fp)
{
    int i;
    DWORD exitcode;

    Sleep(100);
    for (i = 0; i < MYPOPENSIZE; i++) {
	if (MyPopenRecord[i].inuse && MyPopenRecord[i].pipe == fp)
	    break;
    }
    if (i >= MYPOPENSIZE) {
                rb_fatal("Invalid file pointer passed to mypclose!\n");
    }

    //
    // get the return status of the process
    //

#if 0
    if (_cwait(&exitcode, MyPopenRecord[i].pid, WAIT_CHILD) == -1) {
	if (errno == ECHILD) {
	    fprintf(stderr, "mypclose: nosuch child as pid %x\n", 
		    MyPopenRecord[i].pid);
	}
    }
#else
	for (;;) {
		if (GetExitCodeProcess((HANDLE)MyPopenRecord[i].pid, &exitcode)) {
			if (exitcode == STILL_ACTIVE) {
				//printf("Process is Active.\n");
				Sleep(100);
				TerminateProcess((HANDLE)MyPopenRecord[i].pid, 0); // ugly...
				continue;
			}
			else if (exitcode == 0) {
				//printf("done.\n");
				break;
			}
			else {
				//printf("never.\n");
				break;
			}
		}
	}
	CloseHandle((HANDLE)MyPopenRecord[i].pid);
#endif

    //
    // close the pipe
    //

    fflush(fp);
    fclose(fp);

    //
    // free this slot
    //

    MyPopenRecord[i].inuse = FALSE;
    MyPopenRecord[i].pipe  = NULL;
    MyPopenRecord[i].pid   = 0;

    return (int)((exitcode & 0xff) << 8);
}
#endif

#if 1


typedef char* CHARP;
/*
 * The following code is based on the do_exec and do_aexec functions
 * in file doio.c
 */

int
do_spawn(cmd)
char *cmd;
{
    register char **a;
    register char *s;
    char **argv;
    int status = -1;
    char *shell, *cmd2;
    int mode = NtSyncProcess ? P_WAIT : P_NOWAIT;
    char **env = NULL;

    env = win32_get_environ();
    /* save an extra exec if possible */
    if ((shell = getenv("RUBYSHELL")) != 0) {
	if (NtHasRedirection(cmd)) {
	    int  i;
	    char *p;
	    char *argv[4];
	    char *cmdline = ALLOC_N(char, (strlen(cmd) * 2 + 1));

	    p=cmdline;           
	    *p++ = '"';
	    for (s=cmd; *s;) {
		if (*s == '"') 
		    *p++ = '\\'; /* Escape d-quote */
		*p++ = *s++;
	    }
	    *p++ = '"';
	    *p   = '\0';

	    /* fprintf(stderr, "do_spawn: %s %s\n", shell, cmdline); */
	    argv[0] = shell;
	    argv[1] = "-c";
	    argv[2] = cmdline;
	    argv[4] = NULL;
	    status = spawnvpe(mode, argv[0], argv, env);
	    /* return spawnle(mode, shell, shell, "-c", cmd, (char*)0, environ); */
	    free(cmdline);
	    if (env) win32_free_environ(env);
	    return (int)((status & 0xff) << 8);
	} 
    }
    else if ((shell = getenv("COMSPEC")) != 0) {
	if (NtHasRedirection(cmd) /* || isInternalCmd(cmd) */) {
	    status = spawnle(mode, shell, shell, "/c", cmd, (char*)0, env);
	    if (env) win32_free_environ(env);
	    return (int)((status & 0xff) << 8);
	}
    }

    argv = ALLOC_N(CHARP, (strlen(cmd) / 2 + 2));
    cmd2 = ALLOC_N(char, (strlen(cmd) + 1));
    strcpy(cmd2, cmd);
    a = argv;
    for (s = cmd2; *s;) {
	while (*s && ISSPACE(*s)) s++;
	if (*s)
	    *(a++) = s;
	while (*s && !ISSPACE(*s)) s++;
	if (*s)
	    *s++ = '\0';
    }
    *a = NULL;
    if (argv[0]) {
	if ((status = spawnvpe(mode, argv[0], argv, env)) == -1) {
	    free(argv);
	    free(cmd2);
	    if (env) win32_free_environ(env);
	    return -1;
	}
    }
    free(cmd2);
    free(argv);
    if (env) win32_free_environ(env);
    return (int)((status & 0xff) << 8);
}

#endif

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
// resulting list of new names. If the wildcard pattern doesn\'t match 
// any existing files, just leave it in the list.
//

#if 0
void
NtCmdGlob (NtCmdLineElement *patt)
{
    WIN32_FIND_DATA fd;
    HANDLE fh;
    char buffer[512];
    NtCmdLineElement *tmphead, *tmptail, *tmpcurr;

    strncpy(buffer, patt->str, patt->len);
    buffer[patt->len] = '\0';
    if ((fh = FindFirstFile (buffer, &fd)) == INVALID_HANDLE_VALUE) {
	return;
    }
    tmphead = tmptail = NULL;
    do {
	tmpcurr = ALLOC(NtCmdLineElement);
	if (tmpcurr == NULL) {
	    fprintf(stderr, "Out of Memory in globbing!\n");
	    while (tmphead) {
		tmpcurr = tmphead;
		tmphead = tmphead->next;
		free(tmpcurr->str);
		free(tmpcurr);
	    }
	    return;
	}
	memset (tmpcurr, 0, sizeof(*tmpcurr));
	tmpcurr->len = strlen(fd.cFileName);
	tmpcurr->str = ALLOC_N(char, tmpcurr->len+1);
	if (tmpcurr->str == NULL) {
	    fprintf(stderr, "Out of Memory in globbing!\n");
	    while (tmphead) {
		tmpcurr = tmphead;
		tmphead = tmphead->next;
		free(tmpcurr->str);
		free(tmpcurr);
	    }
	    return;
	}
	strcpy(tmpcurr->str, fd.cFileName);
	tmpcurr->flags |= NTMALLOC;
	if (tmptail) {
	    tmptail->next = tmpcurr;
	    tmpcurr->prev = tmptail;
	    tmptail = tmpcurr;
	}
	else {
	    tmptail = tmphead = tmpcurr;
	}
    } while(FindNextFile(fh, &fd));

    //
    // ok, now we\'ve got a list of files that matched the wildcard
    // specification. Put it in place of the pattern structure.
    //
    
    tmphead->prev = patt->prev;
    tmptail->next = patt->next;

    if (tmphead->prev)
	tmphead->prev->next = tmphead;

    if (tmptail->next)
	tmptail->next->prev = tmptail;

    //
    // Now get rid of the pattern structure
    //

    if (patt->flags & NTMALLOC)
	free(patt->str);
    // free(patt);  //TODO:  memory leak occures here. we have to fix it.
}
#else
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
    rb_iglob(buf, insert, (VALUE)&listinfo);
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
#endif

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
    // just return if we don\'t have a command line
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
    // When we\'ve finished, and it\'s an input command (meaning that it\'s
    // the processes argv), we\'ll do globing and then build the argument 
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
		// check to see if we\'re parsing an option switch
		//

		if (*ptr == '/' && base == ptr)
		    continue;
#endif
		//
		// if we\'re not in a string, then we\'re finished with this
		// element
		//

		if (!instring)
		    done++;
		break;

	      case '*':
	      case '?':

		// 
		// record the fact that this element has a wildcard character
		// N.B. Don\'t glob if inside a single quoted string
		//

		if (!(instring && quote == '\''))
		    globbing++;
		break;

	      case '\n':

		//
		// If this string contains a newline, mark it as such so
		// we can replace it with the two character sequence "\n"
		// (cmd.exe doesn\'t like raw newlines in strings...sigh).
		//

		newline++;
		break;

	      case '\'':
	      case '\"':

		//
		// if we\'re already in a string, see if this is the
		// terminating close-quote. If it is, we\'re finished with 
		// the string, but not neccessarily with the element.
		// If we\'re not already in a string, start one.
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
	// when we get here, we\'ve got a pair of pointers to the element,
	// base and ptr. Base points to the start of the element while ptr
	// points to the character following the element.
	//

	curr = ALLOC(NtCmdLineElement);
	memset (curr, 0, sizeof(*curr));

	len = ptr - base;

	//
	// if it\'s an input vector element and it\'s enclosed by quotes, 
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
	// When we get here we\'ve finished parsing the command line. Now 
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
    // and ptr point to the area we\'ll consider the string table.
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
opendir(const char *filename)
{
    DIR            *p;
    long            len;
    long            idx;
    char            scannamespc[PATHLEN];
    char	   *scanname = scannamespc;
    struct stat	    sbuf;
    struct _finddata_t fd;
    long               fh;
    char            root[PATHLEN];
    char            volname[PATHLEN];
    DWORD           serial, maxname, flags;

    //
    // check to see if we\'ve got a directory
    //

    if ((win32_stat (filename, &sbuf) < 0 ||
	sbuf.st_mode & _S_IFDIR == 0) &&
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

    fh = _findfirst(scanname, &fd);
    if (fh == -1) {
	return NULL;
    }

    //
    // now allocate the first part of the string table for the
    // filenames that we find.
    //

    idx = strlen(fd.name)+1;
    p->start = ALLOC_N(char, idx);
    strcpy(p->start, fd.name);
    p->nfiles++;
    
    //
    // loop finding all the files that match the wildcard
    // (which should be all of them in this directory!).
    // the variable idx should point one past the null terminator
    // of the previous string found.
    //
    while (_findnext(fh, &fd) == 0) {
	len = strlen(fd.name);

	//
	// bump the string table size by enough for the
	// new name and it's null terminator 
	//

	#define Renew(x, y, z) (x = (z *)realloc(x, y))

	Renew (p->start, idx+len+1, char);
	if (p->start == NULL) {
            rb_fatal ("opendir: malloc failed!\n");
	}
	strcpy(&p->start[idx], fd.name);
	p->nfiles++;
	idx += len+1;
    }
    _findclose(fh);
    p->size = idx;
    p->curr = p->start;
    return p;
}


//
// Readdir just returns the current string pointer and bumps the
// string pointer to the next entry.
//

struct direct  *
readdir(DIR *dirp)
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
telldir(DIR *dirp)
{
	return (long) dirp->curr;	/* ouch! pointer to long cast */
}

//
// Seekdir moves the string pointer to a previously saved position
// (Saved by telldir).

void
seekdir(DIR *dirp, long loc)
{
	dirp->curr = (char *) loc;	/* ouch! long to pointer cast */
}

//
// Rewinddir resets the string pointer to the start
//

void
rewinddir(DIR *dirp)
{
	dirp->curr = dirp->start;
}

//
// This just free\'s the memory allocated by opendir
//

void
closedir(DIR *dirp)
{
	free(dirp->start);
	free(dirp);
}


//
// 98.2% of this code was lifted from the OS2 port. (JCW)
//

#if 0
// add_suffix is in util.c too.
/*
 * Suffix appending for in-place editing under MS-DOS and OS/2 (and now NT!).
 *
 * Here are the rules:
 *
 * Style 0:  Append the suffix exactly as standard perl would do it.
 *           If the filesystem groks it, use it.  (HPFS will always
 *           grok it.  So will NTFS. FAT will rarely accept it.)
 *
 * Style 1:  The suffix begins with a '.'.  The extension is replaced.
 *           If the name matches the original name, use the fallback method.
 *
 * Style 2:  The suffix is a single character, not a '.'.  Try to add the 
 *           suffix to the following places, using the first one that works.
 *               [1] Append to extension.  
 *               [2] Append to filename, 
 *               [3] Replace end of extension, 
 *               [4] Replace end of filename.
 *           If the name matches the original name, use the fallback method.
 *
 * Style 3:  Any other case:  Ignore the suffix completely and use the
 *           fallback method.
 *
 * Fallback method:  Change the extension to ".$$$".  If that matches the
 *           original name, then change the extension to ".~~~".
 *
 * If filename is more than 1000 characters long, we die a horrible
 * death.  Sorry.
 *
 * The filename restriction is a cheat so that we can use buf[] to store
 * assorted temporary goo.
 *
 * Examples, assuming style 0 failed.
 *
 * suffix = ".bak" (style 1)
 *                foo.bar => foo.bak
 *                foo.bak => foo.$$$	(fallback)
 *                foo.$$$ => foo.~~~	(fallback)
 *                makefile => makefile.bak
 *
 * suffix = "~" (style 2)
 *                foo.c => foo.c~
 *                foo.c~ => foo.c~~
 *                foo.c~~ => foo~.c~~
 *                foo~.c~~ => foo~~.c~~
 *                foo~~~~~.c~~ => foo~~~~~.$$$ (fallback)
 *
 *                foo.pas => foo~.pas
 *                makefile => makefile.~
 *                longname.fil => longname.fi~
 *                longname.fi~ => longnam~.fi~
 *                longnam~.fi~ => longnam~.$$$
 *                
 */


static char suffix1[] = ".$$$";
static char suffix2[] = ".~~~";

#define ext (&buf[1000])

#define strEQ(s1,s2) (strcmp(s1,s2) == 0)

void
add_suffix(struct RString *str, char *suffix)
{
    int baselen;
    int extlen = strlen(suffix);
    char *s, *t, *p;
    int slen;
    char buf[1024];

    if (str->len > 1000)
        rb_fatal("Cannot do inplace edit on long filename (%d characters)", str->len);

    /* Style 0 */
    slen = str->len;
    str_cat(str, suffix, extlen);
    if (valid_filename(str->ptr)) return;

    /* Fooey, style 0 failed.  Fix str before continuing. */
    str->ptr[str->len = slen] = '\0';

    slen = extlen;
    t = buf; baselen = 0; s = str->ptr;
    while ( (*t = *s) && *s != '.') {
	baselen++;
	if (*s == '\\' || *s == '/') baselen = 0;
 	s++; t++;
    }
    p = t;

    t = ext; extlen = 0;
    while (*t++ = *s++) extlen++;
    if (extlen == 0) { ext[0] = '.'; ext[1] = 0; extlen++; }

    if (*suffix == '.') {        /* Style 1 */
        if (strEQ(ext, suffix)) goto fallback;
	strcpy(p, suffix);
    } else if (suffix[1] == '\0') {  /* Style 2 */
        if (extlen < 4) { 
	    ext[extlen] = *suffix;
	    ext[++extlen] = '\0';
        } else if (baselen < 8) {
   	    *p++ = *suffix;
	} else if (ext[3] != *suffix) {
	    ext[3] = *suffix;
	} else if (buf[7] != *suffix) {
	    buf[7] = *suffix;
	} else goto fallback;
	strcpy(p, ext);
    } else { /* Style 3:  Panic */
fallback:
	(void)memcpy(p, strEQ(ext, suffix1) ? suffix2 : suffix1, 5);
    }
    str_grow(str, strlen(buf));
    memcpy(str->ptr, buf, str->len);
}
#endif

static int 
valid_filename(char *s)
{
    int fd;

    //
    // if the file exists, then it\'s a valid filename!
    //

    if (_access(s, 0) == 0) {
	return 1;
    }

    //
    // It doesn\'t exist, so see if we can open it.
    //
    
    if ((fd = _open(s, _O_CREAT, 0666)) >= 0) {
	close(fd);
	_unlink (s);	// don\'t leave it laying around
	return 1;
    }
    return 0;
}


//
// This is a clone of fdopen so that we can handle the 
// brain damaged version of sockets that NT gets to use.
//
// The problem is that sockets are not real file handles and 
// cannot be fdopen\'ed. This causes problems in the do_socket
// routine in doio.c, since it tries to create two file pointers
// for the socket just created. We\'ll fake out an fdopen and see
// if we can prevent perl from trying to do stdio on sockets.
//

//EXTERN_C int __cdecl _alloc_osfhnd(void);
//EXTERN_C int __cdecl _set_osfhnd(int fh, long value);
EXTERN_C void __cdecl _lock_fhandle(int);
EXTERN_C void __cdecl _unlock_fhandle(int);
EXTERN_C void __cdecl _unlock(int);

#if defined _MT || defined __MSVCRT__
#define MSVCRT_THREADS
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

EXTERN_C _CRTIMP ioinfo * __pioinfo[];

#define IOINFO_L2E			5
#define IOINFO_ARRAY_ELTS	(1 << IOINFO_L2E)
#define _pioinfo(i)	(__pioinfo[i >> IOINFO_L2E] + (i & (IOINFO_ARRAY_ELTS - 1)))

#define _osfhnd(i)  (_pioinfo(i)->osfhnd)
#define _osfile(i)  (_pioinfo(i)->osfile)
#define _pipech(i)  (_pioinfo(i)->pipech)

#define FOPEN			0x01	/* file handle open */
#define FNOINHERIT		0x10	/* file handle opened O_NOINHERIT */
#define FAPPEND			0x20	/* file handle opened O_APPEND */
#define FDEV			0x40	/* file handle refers to device */
#define FTEXT			0x80	/* file handle is in text mode */

#define _set_osfhnd(fh, osfh) (void)(_osfhnd(fh) = osfh)

static int
_alloc_osfhnd(void)
{
    HANDLE hF = CreateFile("NUL", 0, 0, NULL, OPEN_ALWAYS, 0, NULL);
    int fh = _open_osfhandle((long)hF, 0);
    CloseHandle(hF);
    if (fh == -1)
        return fh;
#ifdef MSVCRT_THREADS
    EnterCriticalSection(&(_pioinfo(fh)->lock));
#endif
    return fh;
}

static int
my_open_osfhandle(long osfhandle, int flags)
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

    /* attempt to allocate a C Runtime file handle */
    if ((fh = _alloc_osfhnd()) == -1) {
	errno = EMFILE;		/* too many open files */
	_doserrno = 0L;		/* not an OS error */
	return -1;		/* return error to caller */
    }

    /* the file is open. now, set the info in _osfhnd array */
    _set_osfhnd(fh, osfhandle);

    fileflags |= FOPEN;		/* mark as open */

    _osfile(fh) = fileflags;	/* set osfile entry */
#ifdef MSVCRT_THREADS
    LeaveCriticalSection(&_pioinfo(fh)->lock);
#endif

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


//
// Since the errors returned by the socket error function 
// WSAGetLastError() are not known by the library routine strerror
// we have to roll our own.
//

#undef strerror

char *
mystrerror(int e)
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
// we don\'t really have permission to do something.
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
ioctl(int i, unsigned int u, long data)
{
    return -1;
}


#undef FD_SET

void
myfdset(int fd, fd_set *set)
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
myfdclr(int fd, fd_set *set)
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
myfdisset(int fd, fd_set *set)
{
       return __WSAFDIsSet(TO_SOCKET(fd), set);
}

//
// Networking trampolines
// These are used to avoid socket startup/shutdown overhead in case 
// the socket routines aren\'t used.
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
myselect (int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
	       struct timeval *timeout)
{
    long r;
    fd_set file_rd;
    fd_set file_wr;
#ifdef USE_INTERRUPT_WINSOCK
    fd_set trap;
#endif /* USE_INTERRUPT_WINSOCK */
    int file_nfds;

    if (!NtSocketsInitialized) {
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

    if ((r = select (nfds, rd, wr, ex, timeout)) == SOCKET_ERROR) {
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
    // initalize the winsock interface and insure that it\'s
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

    iSockOpt = SO_SYNCHRONOUS_NONALERT;
    /*
     * Enable the use of sockets as filehandles
     */
    setsockopt(INVALID_SOCKET, SOL_SOCKET, SO_OPENTYPE,
	       (char *)&iSockOpt, sizeof(iSockOpt));

    main_thread.handle = GetCurrentThreadHandle();
    main_thread.id = GetCurrentThreadId();

    interrupted_event = CreateSignal();
    if (!interrupted_event)
	rb_fatal("Unable to create interrupt event!\n");
    NtSocketsInitialized = 1;
}

#undef accept

SOCKET
myaccept (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    SOCKET r;

    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = accept (TO_SOCKET(s), addr, addrlen)) == INVALID_SOCKET)
	errno = WSAGetLastError();
    return my_open_osfhandle(r, O_RDWR|O_BINARY);
}

#undef bind

int 
mybind (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;

    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = bind (TO_SOCKET(s), addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef connect

int 
myconnect (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = connect (TO_SOCKET(s), addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}


#undef getpeername

int 
mygetpeername (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getpeername (TO_SOCKET(s), addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getsockname

int 
mygetsockname (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getsockname (TO_SOCKET(s), addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

int 
mygetsockopt (SOCKET s, int level, int optname, char *optval, int *optlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getsockopt (TO_SOCKET(s), level, optname, optval, optlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef ioctlsocket

int 
myioctlsocket (SOCKET s, long cmd, u_long *argp)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = ioctlsocket (TO_SOCKET(s), cmd, argp)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef listen

int 
mylisten (SOCKET s, int backlog)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = listen (TO_SOCKET(s), backlog)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recv

int 
myrecv (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = recv (TO_SOCKET(s), buf, len, flags)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recvfrom

int 
myrecvfrom (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *from, int *fromlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = recvfrom (TO_SOCKET(s), buf, len, flags, from, fromlen)) == SOCKET_ERROR)
	errno =  WSAGetLastError();
    return r;
}

#undef send

int 
mysend (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = send (TO_SOCKET(s), buf, len, flags)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef sendto

int 
mysendto (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *to, int tolen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = sendto (TO_SOCKET(s), buf, len, flags, to, tolen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef setsockopt

int 
mysetsockopt (SOCKET s, int level, int optname, char *optval, int optlen)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = setsockopt (TO_SOCKET(s), level, optname, optval, optlen))
    		 == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}
    
#undef shutdown

int 
myshutdown (SOCKET s, int how)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = shutdown (TO_SOCKET(s), how)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef socket

SOCKET 
mysocket (int af, int type, int protocol)
{
    SOCKET s;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((s = socket (af, type, protocol)) == INVALID_SOCKET) {
	errno = WSAGetLastError();
	//fprintf(stderr, "socket fail (%d)", WSAGetLastError());
    }
    return my_open_osfhandle(s, O_RDWR|O_BINARY);
}

#undef gethostbyaddr

struct hostent *
mygethostbyaddr (char *addr, int len, int type)
{
    struct hostent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = gethostbyaddr (addr, len, type)) == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef gethostbyname

struct hostent *
mygethostbyname (char *name)
{
    struct hostent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = gethostbyname (name)) == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef gethostname

int
mygethostname (char *name, int len)
{
    int r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = gethostname (name, len)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getprotobyname

struct protoent *
mygetprotobyname (char *name)
{
    struct protoent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getprotobyname (name)) == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getprotobynumber

struct protoent *
mygetprotobynumber (int num)
{
    struct protoent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getprotobynumber (num)) == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getservbyname

struct servent *
mygetservbyname (char *name, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getservbyname (name, proto)) == NULL)
	errno = WSAGetLastError();
    return r;
}

#undef getservbyport

struct servent *
mygetservbyport (int port, char *proto)
{
    struct servent *r;
    if (!NtSocketsInitialized) {
	StartSockets();
    }
    if ((r = getservbyport (port, proto)) == NULL)
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

pid_t
waitpid (pid_t pid, int *stat_loc, int options)
{
    DWORD timeout;

    if (options == WNOHANG) {
	timeout = 0;
    } else {
	timeout = INFINITE;
    }
    if (wait_events((HANDLE)pid, timeout) == WAIT_OBJECT_0) {
	pid = _cwait(stat_loc, pid, 0);
#if !defined __BORLANDC__
	*stat_loc <<= 8;
#endif
	return pid;
    }
    return 0;
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
win32_getcwd(buffer, size)
    char *buffer;
    int size;
{
    int length;
    char *bp;

    if (_getcwd(buffer, size) == NULL) {
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

#include <signal.h>
int
kill(int pid, int sig)
{
#if 1
	if ((unsigned int)pid == GetCurrentProcessId())
		return raise(sig);

	if (sig == 2 && pid > 0)
		if (GenerateConsoleCtrlEvent(CTRL_C_EVENT, (DWORD)pid))
			return 0;

	return -1;
#else
	return 0;
#endif
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
win32_getenv(const char *name)
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
myrename(const char *oldpath, const char *newpath)
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
win32_stat(const char *path, struct stat *st)
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
    len = s - buf1;
    if (!len || '\"' == *(--s)) {
	errno = ENOENT;
	return -1;
    }
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
mytimes(struct tms *tmbuf)
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

void win32_disable_interrupt(void)
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

void win32_enable_interrupt(void)
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
    int userstate;
    HANDLE handshake;
};

static void win32_call_handler(struct handler_arg_t* h)
{
    int status;
    RUBY_CRITICAL(rb_protect((VALUE (*)())h->handler, (VALUE)h->arg, &h->status);
		  status = h->status;
		  SetEvent(h->handshake));
    if (status) {
	rb_jump_tag(status);
    }
    h->userstate = 1;		/* never syscall after here */
    for (;;);			/* wait here in user state */
}

static struct handler_arg_t* setup_handler(struct handler_arg_t *harg,
					   int arg,
					   void (*handler)(int),
					   HANDLE handshake)
{
    harg->handler = handler;
    harg->arg = arg;
    harg->status = 0;
    harg->userstate = 0;
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
    ctx->Eip = (DWORD)win32_call_handler;
#else
#error unsupported processor
#endif
}

int win32_main_context(int arg, void (*handler)(int))
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
	    yield_until(harg.userstate);

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

int win32_sleep(unsigned long msec)
{
    return wait_events(NULL, msec) != WAIT_TIMEOUT;
}

static void catch_interrupt(void)
{
    yield_once();
    win32_sleep(0);
    CHECK_INTS;
}

void win32_enter_syscall(void)
{
    InterlockedExchange(&rb_trap_immediate, 1);
    catch_interrupt();
    win32_disable_interrupt();
}

void win32_leave_syscall(void)
{
    win32_enable_interrupt();
    catch_interrupt();
    InterlockedExchange(&rb_trap_immediate, 0);
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

VALUE win32_asynchronize(asynchronous_func_t func,
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

char **win32_get_environ(void)
{
    char *envtop, *env;
    char **myenvtop, **myenv;
    int num;

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

void win32_free_environ(char **env)
{
    char **t = env;

    while (*t) free(*t++);
    free(env);
}

int
win32_fclose(FILE *fp)
{
    int fd = fileno(fp);
    SOCKET sock = TO_SOCKET(fd);

    if (fflush(fp)) return -1;
    if (!is_socket(sock)) {
	return fclose(fp);
    }
    _set_osfhnd(fd, (SOCKET)INVALID_HANDLE_VALUE);
    fclose(fp);
    if (closesocket(sock) == SOCKET_ERROR) {
	errno = WSAGetLastError();
	return -1;
    }
    return 0;
}

int
win32_close(int fd)
{
    SOCKET sock = TO_SOCKET(fd);

    if (!is_socket(sock)) {
	return _close(fd);
    }
    if (closesocket(sock) == SOCKET_ERROR) {
	errno = WSAGetLastError();
	return -1;
    }
    return 0;
}
