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
#include "nt.h"
#include "dir.h"
#ifndef index
#define index(x, y) strchr((x), (y))
#endif

#ifndef bool
#define bool int
#endif

bool NtSyncProcess = TRUE;
#if 0  // declared in header file
extern char **environ;
#define environ _environ
#endif

static bool NtHasRedirection (char *);
static int valid_filename(char *s);
static void StartSockets ();
static char *str_grow(struct RString *str, size_t new_size);

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


/* simulate flock by locking a range on the file */


#define LK_ERR(f,i) ((f) ? (i = 0) : (errno = GetLastError()))
#define LK_LEN      0xffff0000

int
flock(int fd, int oper)
{
    OVERLAPPED o;
    int i = -1;
    HANDLE fh;

    fh = (HANDLE)_get_osfhandle(fd);
    memset(&o, 0, sizeof(o));

    if(IsWinNT()) {
        switch(oper) {
        case LOCK_SH:       /* shared lock */
            LK_ERR(LockFileEx(fh, 0, 0, LK_LEN, 0, &o),i);
            break;
        case LOCK_EX:       /* exclusive lock */
            LK_ERR(LockFileEx(fh, LOCKFILE_EXCLUSIVE_LOCK, 0, LK_LEN, 0, &o),i);
            break;
        case LOCK_SH|LOCK_NB:   /* non-blocking shared lock */
            LK_ERR(LockFileEx(fh, LOCKFILE_FAIL_IMMEDIATELY, 0, LK_LEN, 0, &o),i);
            break;
        case LOCK_EX|LOCK_NB:   /* non-blocking exclusive lock */
            LK_ERR(LockFileEx(fh,
                   LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,
                   0, LK_LEN, 0, &o),i);
	    if(errno == EDOM) errno = EWOULDBLOCK;
            break;
        case LOCK_UN:       /* unlock lock */
	    if (UnlockFileEx(fh, 0, LK_LEN, 0, &o)) {
		i = 0;
	    }
	    else {
		/* GetLastError() must returns `ERROR_NOT_LOCKED' */
		errno = EWOULDBLOCK;
	    }
	    if(errno == EDOM) errno = EWOULDBLOCK;
            break;
        default:            /* unknown */
            errno = EINVAL;
            break;
        }
    }
    else if(IsWin95()) {
        switch(oper) {
        case LOCK_EX:
	    while(i == -1) {
	        LK_ERR(LockFile(fh, 0, 0, LK_LEN, 0), i);
		if(errno != EDOM && i == -1) break;
	    }
	    break;
	case LOCK_EX | LOCK_NB:
	    LK_ERR(LockFile(fh, 0, 0, LK_LEN, 0), i);
	    if(errno == EDOM) errno = EWOULDBLOCK;
            break;
        case LOCK_UN:
            LK_ERR(UnlockFile(fh, 0, 0, LK_LEN, 0), i);
	    if(errno == EDOM) errno = EWOULDBLOCK;
            break;
        default:
            errno = EINVAL;
            break;
        }
    }
    return i;
}

#undef LK_ERR
#undef LK_LEN


#undef const
FILE *fdopen(int, const char *);

#if 0
void
sleep(unsigned int len)
{
	time_t end;

	end = time((time_t *)0) + len;
	while (time((time_t *)0) < end)
		;
}
#endif

//
// Initialization stuff
//
void
NtInitialize(int *argc, char ***argv) {

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
	// StartSockets();
}


char *getlogin()
{
    char buffer[200];
    int len = 200;
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
    HANDLE oshandle;
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

	p = (char *)(vec - (vecc * sizeof (char *) + 1));
	free(p);

	return 0;
}


static char *szInternalCmds[] = {
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
};

int
isInternalCmd(char *cmd)
{
	int fRet;
	char **vec;
	int vecc = NtMakeCmdVector(cmd, &vec, FALSE);

	SafeFree (vec, vecc);

	return 0;
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
		HANDLE hInFile, hOutFile, hStdin, hStdout;
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

		if (!reading) {
        	FILE *fp;

			fp = (_popen)(cmd, mode);

			MyPopenRecord[slot].inuse = TRUE;
			MyPopenRecord[slot].pipe = fp;
			MyPopenRecord[slot].pid = -1;

			if (!fp)
			Fatal("cannot open pipe \"%s\" (%s)", cmd, strerror(errno));
				return fp;
		}


		fRet = CreatePipe(&hInFile, &hOutFile, &sa, 2048L);
		if (!fRet)
			Fatal("cannot open pipe \"%s\" (%s)", cmd, strerror(errno));

		memset(&aStartupInfo, 0, sizeof (STARTUPINFO));
		memset(&aProcessInformation, 0, sizeof (PROCESS_INFORMATION));
		aStartupInfo.cb = sizeof (STARTUPINFO);
		aStartupInfo.dwFlags    = STARTF_USESTDHANDLES;

		if (reading) {
			aStartupInfo.hStdInput  = GetStdHandle(STD_OUTPUT_HANDLE);//hStdin;
			aStartupInfo.hStdError  = INVALID_HANDLE_VALUE;
			//for save
			DuplicateHandle(GetCurrentProcess(), GetStdHandle(STD_OUTPUT_HANDLE),
			  GetCurrentProcess(), &hStdout,
			  0, FALSE, DUPLICATE_SAME_ACCESS
			);
			//for redirect
			DuplicateHandle(GetCurrentProcess(), GetStdHandle(STD_INPUT_HANDLE),
			  GetCurrentProcess(), &hStdin,
			  0, TRUE, DUPLICATE_SAME_ACCESS
			);
			aStartupInfo.hStdOutput = hOutFile;
		}
		else {
			aStartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE); //hStdout;
			aStartupInfo.hStdError  = INVALID_HANDLE_VALUE;
			// for save
			DuplicateHandle(GetCurrentProcess(), GetStdHandle(STD_INPUT_HANDLE),
			  GetCurrentProcess(), &hStdin,
			  0, FALSE, DUPLICATE_SAME_ACCESS
			);
			//for redirect
			DuplicateHandle(GetCurrentProcess(), GetStdHandle(STD_OUTPUT_HANDLE),
			  GetCurrentProcess(), &hStdout,
			  0, TRUE, DUPLICATE_SAME_ACCESS
			);
			aStartupInfo.hStdInput = hInFile;
		}

		dwCreationFlags = (NORMAL_PRIORITY_CLASS);

		lpCommandLine = cmd;
		if (NtHasRedirection(cmd) || isInternalCmd(cmd)) {
		  lpApplicationName = getenv("COMSPEC");
		  lpCmd2 = malloc(strlen(lpApplicationName) + 1 + strlen(cmd) + sizeof (" /c "));
		  if (lpCmd2 == NULL)
		     Fatal("Mypopen: malloc failed");
		  sprintf(lpCmd2, "%s %s%s", lpApplicationName, " /c ", cmd);
		  lpCommandLine = lpCmd2;
		}

		fRet = CreateProcess(lpApplicationName, lpCommandLine, &sa, &sa,
			sa.bInheritHandle, dwCreationFlags, NULL, NULL, &aStartupInfo, &aProcessInformation);

		if (!fRet) {
			CloseHandle(hInFile);
			CloseHandle(hOutFile);
			Fatal("cannot fork for \"%s\" (%s)", cmd, strerror(errno));
		}

		CloseHandle(aProcessInformation.hThread);

		if (reading) {
			HANDLE hDummy;

			fd = _open_osfhandle((long)hInFile,  (_O_RDONLY | pipemode));
			CloseHandle(hOutFile);
			DuplicateHandle(GetCurrentProcess(), hStdout,
			  GetCurrentProcess(), &hDummy,
			  0, TRUE, (DUPLICATE_SAME_ACCESS | DUPLICATE_CLOSE_SOURCE)
			);
		}
		else {
			HANDLE hDummy;

		    fd = _open_osfhandle((long)hOutFile, (_O_WRONLY | pipemode));
			CloseHandle(hInFile);
			DuplicateHandle(GetCurrentProcess(), hStdin,
			  GetCurrentProcess(), &hDummy,
			  0, TRUE, (DUPLICATE_SAME_ACCESS | DUPLICATE_CLOSE_SOURCE)
			);
		}

		if (fd == -1) 
		  Fatal("cannot open pipe \"%s\" (%s)", cmd, strerror(errno));


		if ((fp = (FILE *) fdopen(fd, mode)) == NULL)
			return NULL;

		if (lpCmd2)
			free(lpCmd2);

		MyPopenRecord[slot].inuse = TRUE;
		MyPopenRecord[slot].pipe  = fp;
		MyPopenRecord[slot].oshandle = (reading ? hInFile : hOutFile);
		MyPopenRecord[slot].pid   = (int)aProcessInformation.hProcess;
		return fp;
    }
#endif
}

int
mypclose(FILE *fp)
{
    int i;
    int exitcode;

    Sleep(100);
    for (i = 0; i < MYPOPENSIZE; i++) {
	if (MyPopenRecord[i].inuse && MyPopenRecord[i].pipe == fp)
	    break;
    }
    if (i >= MYPOPENSIZE) {
		Fatal("Invalid file pointer passed to mypclose!\n");
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
#endif


    //
    // close the pipe
    //
    CloseHandle(MyPopenRecord[i].oshandle);
    fflush(fp);
    fclose(fp);

    //
    // free this slot
    //

    MyPopenRecord[i].inuse = FALSE;
    MyPopenRecord[i].pipe  = NULL;
    MyPopenRecord[i].pid   = 0;

    return exitcode;
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
    int status;
    char *shell, *cmd2;
    int mode = NtSyncProcess ? P_WAIT : P_NOWAIT;

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
	    status = spawnvpe(mode, argv[0], argv, environ);
	    /* return spawnle(mode, shell, shell, "-c", cmd, (char*)0, environ); */
	    free(cmdline);
	    return status;
	} 
    }
    else if ((shell = getenv("COMSPEC")) != 0) {
	if (NtHasRedirection(cmd) /* || isInternalCmd(cmd) */) {
	  do_comspec_shell:
	    return spawnle(mode, shell, shell, "/c", cmd, (char*)0, environ);
	}
    }

    argv = ALLOC_N(CHARP, (strlen(cmd) / 2 + 2));
    cmd2 = ALLOC_N(char, (strlen(cmd) + 1));
    strcpy(cmd2, cmd);
    a = argv;
    for (s = cmd2; *s;) {
	while (*s && isspace(*s)) s++;
	if (*s)
	    *(a++) = s;
	while (*s && !isspace(*s)) s++;
	if (*s)
	    *s++ = '\0';
    }
    *a = NULL;
    if (argv[0]) {
	if ((status = spawnvpe(mode, argv[0], argv, environ)) == -1) {
	    free(argv);
	    free(cmd2);
	    return -1;
	}
    }
    free(cmd2);
    free(argv);
    return status;
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

    //
    // strip trailing white space
    //

    ptr = cmdline+(cmdlen - 1);
    while(ptr >= cmdline && isspace(*ptr))
        --ptr;
    *++ptr = '\0';

    //
    // check for newlines and formfeeds. If we find any, make a new
    // command string that replaces them with escaped sequences (\n or \f)
    //

    for (ptr = cmdline, newline = 0; *ptr; ptr++) {
	if (*ptr == '\n' || *ptr == '\f')
	    newline++;
    }

    if (newline) {
	base = ALLOC_N(char, strlen(cmdline) + 1 + newline + slashes);
	if (base == NULL) {
	    fprintf(stderr, "malloc failed!\n");
	    return 0;
	}
	for (i = 0, ptr = base; (unsigned) i < strlen(cmdline); i++) {
	    switch (cmdline[i]) {
	      case '\n':
		*ptr++ = '\\';
		*ptr++ = 'n';
		break;
	      default:
		*ptr++ = cmdline[i];
	    }
	}
	*ptr = '\0';
	cmdline = base;
	need_free++;
    }

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

	while(isspace(*ptr))
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
	if (curr == NULL) {
	    NtFreeCmdLine();
	    fprintf(stderr, "Out of memory!!\n");
	    *vec = NULL;
	    return 0;
	}
	memset (curr, 0, sizeof(*curr));

	len = ptr - base;

	//
	// if it\'s an input vector element and it\'s enclosed by quotes, 
	// we can remove them.
	//

	if (InputCmd &&
	    ((base[0] == '\"' && base[len-1] == '\"') ||
	     (base[0] == '\'' && base[len-1] == '\''))) {
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
    if (buffer == NULL) {
	fprintf(stderr, "Out of memory!!\n");
	NtFreeCmdLine();
	*vec = NULL;
	return 0;
    }
    
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
    return elements;
}


#if 1
//
// UNIX compatible directory access functions for NT
//

//
// File names are converted to lowercase if the
// CONVERT_TO_LOWER_CASE variable is defined.
//

#define CONVERT_TO_LOWER_CASE
#define PATHLEN 1024

//
// The idea here is to read all the directory names into a string table
// (separated by nulls) and when one of the other dir functions is called
// return the pointer to the current file name. 
//

DIR *
opendir(char *filename)
{
    DIR            *p;
    long            len;
    long            idx;
    char            scannamespc[PATHLEN];
    char	   *scanname = scannamespc;
    struct stat	    sbuf;
    WIN32_FIND_DATA FindData;
    HANDLE          fh;
    char            root[PATHLEN];
    char            volname[PATHLEN];
    DWORD           serial, maxname, flags;
    BOOL            downcase;
    char           *dummy;

    //
    // check to see if we\'ve got a directory
    //

    if (stat (filename, &sbuf) < 0 ||
	sbuf.st_mode & _S_IFDIR == 0) {
	return NULL;
    }

    //
    // check out the file system characteristics
    //
    if (GetFullPathName(filename, PATHLEN, root, &dummy)) {
	if (dummy = strchr(root, '\\'))
	    *++dummy = '\0';
	if (GetVolumeInformation(root, volname, PATHLEN, 
				 &serial, &maxname, &flags, 0, 0)) {
	    downcase = !(flags & FS_CASE_SENSITIVE);
	}
    }
    else {
	downcase = TRUE;
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

    if (index("/\\", *(scanname + strlen(scanname) - 1)) == NULL)
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
    if (downcase)
	strlwr(p->start);
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
	    Fatal ("opendir: malloc failed!\n");
	}
	strcpy(&p->start[idx], FindData.cFileName);
	if (downcase) 
	    strlwr(&p->start[idx]);
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
#endif


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
        Fatal("Cannot do inplace edit on long filename (%d characters)", str->len);

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

FILE *
fdopen (int fd, const char *mode)
{
    FILE *fp;
    char sockbuf[80];
    int optlen;
    int retval;
    extern int errno;

    retval = getsockopt((SOCKET)fd, SOL_SOCKET, SO_TYPE, sockbuf, &optlen);
    if (retval == SOCKET_ERROR) {
	int iRet;

	iRet = WSAGetLastError();
	if (iRet == WSAENOTSOCK || iRet == WSANOTINITIALISED)
	return (_fdopen(fd, mode));
    }

    //
    // If we get here, then fd is actually a socket.
    //
    fp = xcalloc(sizeof(FILE), 1);
#if _MSC_VER < 800
    fileno(fp) = fd;
#else
    fp->_file = fd;
#endif
    if (*mode == 'r')
	fp->_flag = _IOREAD;
    else
	fp->_flag = _IOWRT;
    return fp;
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
    extern int sys_nerr;
    DWORD source = 0;

    if (e < 0 || e > sys_nerr) {
	if (e < 0)
	    e = GetLastError();
	if (FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, &source, e, 0,
			  buffer, 512, NULL) == 0) {
	    strcpy (buffer, "Unknown Error");
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


//
// Networking trampolines
// These are used to avoid socket startup/shutdown overhead in case 
// the socket routines aren\'t used.
//

#undef select

static int NtSocketsInitialized = 0;

long 
myselect (int nfds, fd_set *rd, fd_set *wr, fd_set *ex,
	       struct timeval *timeout)
{
    long r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = select (nfds, rd, wr, ex, timeout)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

static void
StartSockets () {
    WORD version;
    WSADATA retdata;
    int ret;
    
    //
    // initalize the winsock interface and insure that it\'s
    // cleaned up at exit.
    //
    version = MAKEWORD(1, 1);
    if (ret = WSAStartup(version, &retdata))
	Fatal ("Unable to locate winsock library!\n");
    if (LOBYTE(retdata.wVersion) != 1)
	Fatal("could not find version 1 of winsock dll\n");

    if (HIBYTE(retdata.wVersion) != 1)
	Fatal("could not find version 1 of winsock dll\n");

    atexit((void (*)(void)) WSACleanup);
}

#undef accept

SOCKET 
myaccept (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    SOCKET r;

    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = accept (s, addr, addrlen)) == INVALID_SOCKET)
	errno = WSAGetLastError();
    return r;
}

#undef bind

int 
mybind (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;

    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = bind (s, addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef connect

int 
myconnect (SOCKET s, struct sockaddr *addr, int addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = connect (s, addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}


#undef getpeername

int 
mygetpeername (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = getpeername (s, addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getsockname

int 
mygetsockname (SOCKET s, struct sockaddr *addr, int *addrlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = getsockname (s, addr, addrlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef getsockopt

int 
mygetsockopt (SOCKET s, int level, int optname, char *optval, int *optlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = getsockopt (s, level, optname, optval, optlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef ioctlsocket

int 
myioctlsocket (SOCKET s, long cmd, u_long *argp)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = ioctlsocket (s, cmd, argp)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef listen

int 
mylisten (SOCKET s, int backlog)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = listen (s, backlog)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recv

int 
myrecv (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = recv (s, buf, len, flags)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef recvfrom

int 
myrecvfrom (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *from, int *fromlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = recvfrom (s, buf, len, flags, from, fromlen)) == SOCKET_ERROR)
	errno =  WSAGetLastError();
    return r;
}

#undef send

int 
mysend (SOCKET s, char *buf, int len, int flags)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = send (s, buf, len, flags)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef sendto

int 
mysendto (SOCKET s, char *buf, int len, int flags, 
		struct sockaddr *to, int tolen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = sendto (s, buf, len, flags, to, tolen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef setsockopt

int 
mysetsockopt (SOCKET s, int level, int optname, char *optval, int optlen)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = setsockopt (s, level, optname, optval, optlen)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}
    
#undef shutdown

int 
myshutdown (SOCKET s, int how)
{
    int r;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((r = shutdown (s, how)) == SOCKET_ERROR)
	errno = WSAGetLastError();
    return r;
}

#undef socket

SOCKET 
mysocket (int af, int type, int protocol)
{
    SOCKET s;
    if (!NtSocketsInitialized++) {
	StartSockets();
    }
    if ((s = socket (af, type, protocol)) == INVALID_SOCKET)
	errno = WSAGetLastError();
    return s;
}

#undef gethostbyaddr

struct hostent *
mygethostbyaddr (char *addr, int len, int type)
{
    struct hostent *r;
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (!NtSocketsInitialized++) {
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
    if (WaitForSingleObject((HANDLE) pid, timeout) == WAIT_OBJECT_0) {
	pid = _cwait(stat_loc, pid, 0);
	return pid;
    }
    return 0;
}

#include <sys/timeb.h>

void _cdecl
gettimeofday(struct timeval *tv, struct timezone *tz)
{                                
    struct timeb tb;

    ftime(&tb);
    tv->tv_sec = tb.time;
    tv->tv_usec = tb.millitm * 1000;
}

char *
getcwd(buffer, size)
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

    for (bp = buffer; *bp != '\0'; bp++) {
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
		Fatal("cannot grow string\n");

	str->len = new_size;
	str->ptr = p;

	return p;
}

int
chown(char *path, int owner, int group)
{
	return 0;
}

int
kill(int pid, int sig)
{
#if 1
	if (pid == GetCurrentProcessId())
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

