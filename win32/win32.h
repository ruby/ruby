#ifndef EXT_NT_H
#define EXT_NT_H

/*
 *  Copyright (c) 1993, Intergraph Corporation
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the perl README file.
 *
 */

#undef EXTERN
#if defined(IMPORT)
#define EXTERN extern __declspec(dllimport)
#elif defined(EXPORT)
#define EXTERN extern __declspec(dllexport)
#endif

//
// Definitions for NT port of Perl
//


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
// We're not using Microsoft's "extensions" to C for
// Structured Exception Handling (SEH) so we can nuke these
//
#undef try
#undef except
#undef finally
#undef leave

#if defined(__cplusplus)
extern "C++" {
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <direct.h>
#include <process.h>
#include <time.h>
#include <math.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#if !defined(__BORLANDC__)
# include <sys/utime.h>
#else
# include <utime.h>
#endif
#include <io.h>
#include <malloc.h>

#if defined(__cplusplus)
}
#endif

#define UIDTYPE int
#define GIDTYPE int
#define pid_t   int
#define WNOHANG -1

#undef getc
#undef putc
#undef fgetc
#undef fputc
#undef getchar
#undef putchar
#undef fgetchar
#undef fputchar
#define getc(_stream)		rb_w32_getc(_stream)
#define putc(_c, _stream)	rb_w32_putc(_c, _stream)
#define fgetc(_stream)		getc(_stream)
#define fputc(_c, _stream)	putc(_c, _stream)
#define getchar()		rb_w32_getc(stdin)
#define putchar(_c)		rb_w32_putc(_c, stdout)
#define fgetchar(_stream)	getchar()
#define fputchar(_c, _stream)	putchar(_c)

#ifndef __BORLANDC__

#define access	   _access
#define chmod	   _chmod
#define chsize	   _chsize
#define dup	   _dup
#define dup2	   _dup2
#define isatty	   _isatty
#define open	   _open
#define setmode    _setmode
#define execl	   _execl
#define execle	   _execle
#define execlp	   _execlp
#define execlpe    _execlpe
#define execv	   _execv
#define execve	   _execve
#define execvp	   _execvp
#define execvpe    _execvpe
#define lseek      _lseek
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
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#else
#define strcasecmp  stricmp
#define strncasecmp strnicmp
#define _open       _sopen
#endif

#define close	   _close
#define creat	   _creat
#define eof	   _eof
#define filelength _filelength
#define locking    _locking
#define mktemp	   _mktemp
#define perror     _perror
#define read	   _read
#define sopen	   _sopen
#define tell	   _tell
#define umask	   _umask
#define unlink	   _unlink
#define write	   _write
#define getpid	   rb_w32_getpid
#define sleep(x)   rb_w32_sleep((x)*1000)
#define utime      _utime
#define vsnprintf  _vsnprintf
#define snprintf   _snprintf
#undef stat
#define stat(path,st) rb_w32_stat(path,st)

#ifdef __MINGW32__
struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};
#endif
extern int    NtMakeCmdVector(char *, char ***, int);
extern void   NtInitialize(int *, char ***);
extern char * NtGetLib(void);
extern char * NtGetBin(void);
extern pid_t  pipe_exec(char *, int, FILE **, FILE **);
extern int    flock(int fd, int oper);
extern int    rb_w32_fddup(int);
extern void   rb_w32_fdclose(FILE *);
extern SOCKET rb_w32_accept(SOCKET, struct sockaddr *, int *);
extern int    rb_w32_bind(SOCKET, struct sockaddr *, int);
extern int    rb_w32_connect(SOCKET, struct sockaddr *, int);
extern void   rb_w32_fdset(int, fd_set*);
extern void   rb_w32_fdclr(int, fd_set*);
extern int    rb_w32_fdisset(int, fd_set*);
extern long   rb_w32_select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
extern int    rb_w32_getpeername(SOCKET, struct sockaddr *, int *);
extern int    rb_w32_getsockname(SOCKET, struct sockaddr *, int *);
extern int    rb_w32_getsockopt(SOCKET, int, int, char *, int *);
extern int    rb_w32_ioctlsocket(SOCKET, long, u_long *);
extern int    rb_w32_listen(SOCKET, int);
extern int    rb_w32_recv(SOCKET, char *, int, int);
extern int    rb_w32_recvfrom(SOCKET, char *, int, int, struct sockaddr *, int *);
extern int    rb_w32_send(SOCKET, char *, int, int);
extern int    rb_w32_sendto(SOCKET, char *, int, int, struct sockaddr *, int);
extern int    rb_w32_setsockopt(SOCKET, int, int, char *, int);
extern int    rb_w32_shutdown(SOCKET, int);
extern SOCKET rb_w32_socket(int, int, int);
extern SOCKET rb_w32_get_osfhandle(int);
extern struct hostent * rb_w32_gethostbyaddr(char *, int, int);
extern struct hostent * rb_w32_gethostbyname(char *);
extern int    rb_w32_gethostname(char *, int);
extern struct protoent * rb_w32_getprotobyname(char *);
extern struct protoent * rb_w32_getprotobynumber(int);
extern struct servent  * rb_w32_getservbyname(char *, char *);
extern struct servent  * rb_w32_getservbyport(int, char *);
extern char * rb_w32_getenv(const char *);
extern int    rb_w32_rename(const char *, const char *);
extern char **rb_w32_get_environ(void);
extern void   rb_w32_free_environ(char **);

extern int chown(const char *, int, int);
extern int link(char *, char *);
extern int gettimeofday(struct timeval *, struct timezone *);
extern pid_t waitpid (pid_t, int *, int);
extern int do_spawn(char *);
extern int kill(int, int);
extern pid_t rb_w32_getpid(void);
#ifndef __BORLANDC__
extern int isinf(double);
extern int isnan(double);
#else
#include <float.h>
#ifndef isinf
#define isinf    !_finite
#endif
#ifndef isnan
#define isnan    _isnan
#endif

#ifdef S_ISDIR
#undef S_ISDIR
#endif

#ifdef S_ISFIFO
#undef S_ISFIFO
#endif

#ifdef S_ISBLK
#undef S_ISBLK
#endif

#ifdef S_ISCHR
#undef S_ISCHR
#endif

#ifdef S_ISREG
#undef S_ISREG
#endif

#define S_ISDIR(m)  (((unsigned short)(m) & S_IFMT) == S_IFDIR)
#define S_ISFIFO(m) (((unsigned short)(m) & S_IFMT) == S_IFIFO)
#define S_ISBLK(m)  (((unsigned short)(m) & S_IFMT) == S_IFBLK)
#define S_ISCHR(m)  (((unsigned short)(m) & S_IFMT) == S_IFCHR)
#define S_ISREG(m)  (((unsigned short)(m) & S_IFMT) == S_IFREG)
#endif

#if !defined S_IRUSR && !defined __MINGW32__
#define S_IRUSR 0400
#endif
#ifndef S_IRGRP
#define S_IRGRP 0040
#endif
#ifndef S_IROTH
#define S_IROTH 0004
#endif

#if !defined S_IWUSR && !defined __MINGW32__
#define S_IWUSR 0200
#endif
#ifndef S_IWGRP
#define S_IWGRP 0020
#endif
#ifndef S_IWOTH
#define S_IWOTH 0002
#endif

#if !defined S_IXUSR && !defined __MINGW32__
#define S_IXUSR 0100
#endif
#ifndef S_IXGRP
#define S_IXGRP 0010
#endif
#ifndef S_IXOTH
#define S_IXOTH 0001
#endif

//
// define this so we can do inplace editing
//

#define SUFFIX

//
// stubs
//
#if !defined(__BORLANDC__)
extern int       ioctl (int, unsigned int, long);
#endif
extern UIDTYPE   getuid (void);
extern UIDTYPE   geteuid (void);
extern GIDTYPE   getgid (void);
extern GIDTYPE   getegid (void);
extern int       setuid (int);
extern int       setgid (int);

extern char *rb_w32_strerror(int);

#define strerror(e) rb_w32_strerror(e)

#define PIPE_BUF 1024

#define LOCK_SH 1
#define LOCK_EX 2
#define LOCK_NB 4
#define LOCK_UN 8
#ifndef EWOULDBLOCK
#define EWOULDBLOCK 10035 /* EBASEERR + 35 (winsock.h) */
#endif


#ifndef SIGINT
#define SIGINT 2
#endif
#ifndef SIGKILL
#define SIGKILL	9
#endif


/* #undef va_start */
/* #undef va_end */

#ifdef accept
#undef accept
#endif
#define accept rb_w32_accept

#ifdef bind
#undef bind
#endif
#define bind rb_w32_bind

#ifdef connect
#undef connect
#endif
#define connect rb_w32_connect

#undef FD_SET
#define FD_SET rb_w32_fdset

#undef FD_CLR
#define FD_CLR rb_w32_fdclr

#undef FD_ISSET
#define FD_ISSET rb_w32_fdisset

#undef select
#define select rb_w32_select

#ifdef getpeername
#undef getpeername
#endif
#define getpeername rb_w32_getpeername

#ifdef getsockname
#undef getsockname
#endif
#define getsockname rb_w32_getsockname

#ifdef getsockopt
#undef getsockopt
#endif
#define getsockopt rb_w32_getsockopt

#ifdef ioctlsocket
#undef ioctlsocket
#endif
#define ioctlsocket rb_w32_ioctlsocket

#ifdef listen
#undef listen
#endif
#define listen rb_w32_listen

#ifdef recv
#undef recv
#endif
#define recv rb_w32_recv

#ifdef recvfrom
#undef recvfrom
#endif
#define recvfrom rb_w32_recvfrom

#ifdef send
#undef send
#endif
#define send rb_w32_send

#ifdef sendto
#undef sendto
#endif
#define sendto rb_w32_sendto

#ifdef setsockopt
#undef setsockopt
#endif
#define setsockopt rb_w32_setsockopt

#ifdef shutdown
#undef shutdown
#endif
#define shutdown rb_w32_shutdown

#ifdef socket
#undef socket
#endif
#define socket rb_w32_socket

#ifdef gethostbyaddr
#undef gethostbyaddr
#endif
#define gethostbyaddr rb_w32_gethostbyaddr

#ifdef gethostbyname
#undef gethostbyname
#endif
#define gethostbyname rb_w32_gethostbyname

#ifdef gethostname
#undef gethostname
#endif
#define gethostname rb_w32_gethostname

#ifdef getprotobyname
#undef getprotobyname
#endif
#define getprotobyname rb_w32_getprotobyname

#ifdef getprotobynumber
#undef getprotobynumber
#endif
#define getprotobynumber rb_w32_getprotobynumber

#ifdef getservbyname
#undef getservbyname
#endif
#define getservbyname rb_w32_getservbyname

#ifdef getservbyport
#undef getservbyport
#endif
#define getservbyport rb_w32_getservbyport

#ifdef get_osfhandle
#undef get_osfhandle
#endif
#define get_osfhandle rb_w32_get_osfhandle

#ifdef getcwd
#undef getcwd
#endif
#define getcwd rb_w32_getcwd

#ifdef getenv
#undef getenv
#endif
#define getenv rb_w32_getenv

#ifdef rename
#undef rename
#endif
#define rename rb_w32_rename

struct tms {
	long	tms_utime;
	long	tms_stime;
	long	tms_cutime;
	long	tms_cstime;
};

#ifdef times
#undef times
#endif
#define times rb_w32_times

/* thread stuff */
HANDLE GetCurrentThreadHandle(void);
int  rb_w32_main_context(int arg, void (*handler)(int));
int  rb_w32_sleep(unsigned long msec);
void rb_w32_enter_critical(void);
void rb_w32_leave_critical(void);
int  rb_w32_putc(int, FILE*);
int  rb_w32_getc(FILE*);
#define Sleep(msec) (void)rb_w32_sleep(msec)

/*
== ***CAUTION***
Since this function is very dangerous, ((*NEVER*))
* lock any HANDLEs(i.e. Mutex, Semaphore, CriticalSection and so on) or,
* use anything like TRAP_BEG...TRAP_END block structure,
in asynchronous_func_t.
*/
typedef DWORD (*asynchronous_func_t)(DWORD self, int argc, DWORD* argv);
DWORD rb_w32_asynchronize(asynchronous_func_t func, DWORD self, int argc, DWORD* argv, DWORD intrval);

#endif
