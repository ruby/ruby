#ifndef EXT_NT_H
#define EXT_NT_H

/*
 *  Copyright (c) 1993, Intergraph Corporation
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the perl README file.
 *
 */

//
// Definitions for NT port of Perl
//

//
// GRRRR!!!!  Windows Nonsense.
// Define the following so we don't get tons of extra stuff
// when we include windows.h 
//
#if 0
#define NOGDICAPMASKS     
#define NOVIRTUALKEYCODES 
#define NOWINMESSAGES     
#define NOWINSTYLES       
#define NOSYSMETRICS      
#define NOMENUS           
#define NOICONS           
#define NOKEYSTATES       
#define NOSYSCOMMANDS     
#define NORASTEROPS       
#define NOSHOWWINDOW      
#define OEMRESOURCE       
#define NOATOM            
#define NOCLIPBOARD       
#define NOCOLOR           
#define NOCTLMGR          
#define NODRAWTEXT        
#define NOGDI             
//#define NOKERNEL        
//#define NOUSER          
#define NONLS             
#define NOMB              
#define NOMEMMGR          
#define NOMETAFILE        
#define NOMINMAX          
#define NOMSG             
#define NOOPENFILE        
#define NOSCROLL          
#define NOSERVICE         
#define NOSOUND           
#define NOTEXTMETRIC      
#define NOWH              
#define NOWINOFFSETS      
#define NOCOMM            
#define NOKANJI           
#define NOHELP            
#define NOPROFILER        
#define NODEFERWINDOWPOS  
#endif

//
// Ok now we can include the normal include files.
//

// #include <stdarg.h> conflict with varargs.h?
// There is function-name conflitct, so we rename it
#if !defined(IN) && !defined(FLOAT)
#define OpenFile  WINAPI_OpenFile
#include <windows.h>
#include <winsock.h>
#undef OpenFile
#endif
//
// We\'re not using Microsoft\'s "extensions" to C for
// Structured Exception Handling (SEH) so we can nuke these
//
#undef try
#undef except
#undef finally
#undef leave
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <direct.h>
#include <process.h>
#include <time.h>
#include <math.h>
#include <sys/types.h>
#include <sys/utime.h>

//
// Grrr...
//

#define access	   _access
#define chmod	   _chmod
#define chsize	   _chsize
#define close	   _close
#define creat	   _creat
#define dup	   _dup
#define dup2	   _dup2
#define eof	   _eof
#define filelength _filelength
#define isatty	   _isatty
#define locking    _locking
#define lseek	   _lseek
#define mktemp	   _mktemp
#define open	   _open
#define read	   _read
#define setmode    _setmode
#define sopen	   _sopen
#define tell	   _tell
#define umask	   _umask
#define unlink	   _unlink
#define write	   _write
#define execl	   _execl
#define execle	   _execle
#define execlp	   _execlp
#define execlpe    _execlpe
#define execv	   _execv
#define execve	   _execve
#define execvp	   _execvp
#define execvpe    _execvpe
#define getpid	   _getpid
#define spawnl	   _spawnl
#define spawnle    _spawnle
#define spawnlp    _spawnlp
#define spawnlpe   _spawnlpe
#define spawnv	   _spawnv
#define spawnve    _spawnve
#define spawnvp    _spawnvp
#define spawnvpe   _spawnvpe
#if _MSC_VER < 800
#define fileno	   _fileno
#endif
#define utime      _utime
//#define pipe       _pipe
#define perror      _perror


/* these are defined in nt.c */

extern int NtMakeCmdVector(char *, char ***, int);
/* extern void NtInitialize(int *, char ***); */
extern char *NtGetLib(void);
extern char *NtGetBin(void);
extern FILE *mypopen(char *, char *);
extern int  flock(int fd, int oper);

//
// define this so we can do inplace editing
//

#define SUFFIX

//
// stubs
//
// extern int       ioctl (int, unsigned int, char *);
extern int       ioctl (int, unsigned int, long);
#if 0
extern void      sleep (unsigned int);
#else
#define sleep(x) Sleep(x*1000)
#endif

extern UIDTYPE   getuid (void);
extern UIDTYPE   geteuid (void);
extern GIDTYPE   getgid (void);
extern GIDTYPE   getegid (void);
extern int       setuid (int);
extern int       setgid (int);


#undef IN  /* confict in parse.c */

#if 0
extern int sys_nerr;
extern char *sys_errlist[];
#endif
extern char *mystrerror(int);

#define strerror(e) mystrerror(e)

#define PIPE_BUF 1024

#define HAVE_STDLIB_H 1
#define HAVE_GETLOGIN 1
#define HAVE_WAITPID 1
#define HAVE_GETCWD 1

#define LOCK_SH 1
#define LOCK_EX 2
#define LOCK_NB 4
#define LOCK_UN 8
#ifndef EWOULDBLOCK
#define EWOULDBLOCK 10035 /* EBASEERR + 35 (winsock.h) */
#endif

#ifdef popen
#undef popen
#define popen    mypopen
#endif
#ifdef pclose
#undef pclose
#define pclose   mypclose
#endif

#undef va_start
#undef va_end

#ifdef popen
#undef popen
#define popen    mypopen
#endif
#ifdef pclose
#undef pclose
#define pclose   mypclose
#endif

#undef va_start
#undef va_end

#endif
