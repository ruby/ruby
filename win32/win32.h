#ifndef RUBY_WIN32_H
#define RUBY_WIN32_H

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
// Ok now we can include the normal include files.
//

// #include <stdarg.h> conflict with varargs.h?
#if !defined(IN) && !defined(FLOAT)
#ifdef __BORLANDC__
#define USE_WINSOCK2
#endif
#ifdef USE_WINSOCK2
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#else
#include <windows.h>
#include <winsock.h>
#endif
#endif

#define NT 1			/* deprecated */

#ifdef _WIN32_WCE
#undef CharNext
#define CharNext CharNextA
#endif

//
// We're not using Microsoft's "extensions" to C for
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
#if defined(__cplusplus) && defined(_MSC_VER) && _MSC_VER == 1200
extern "C++" {			/* template without extern "C++" */
#endif
#include <math.h>
#if defined(__cplusplus) && defined(_MSC_VER) && _MSC_VER == 1200
}
#endif
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

#ifdef _M_IX86
# define WIN95 1
#else
# undef  WIN95
#endif

#ifdef WIN95
extern DWORD rb_w32_osid(void);
#define rb_w32_iswinnt()  (rb_w32_osid() == VER_PLATFORM_WIN32_NT)
#define rb_w32_iswin95()  (rb_w32_osid() == VER_PLATFORM_WIN32_WINDOWS)
#else
#define rb_w32_iswinnt()  TRUE
#define rb_w32_iswin95()  FALSE
#endif

#define WNOHANG -1

#undef getc
#undef putc
#undef fgetc
#undef fputc
#undef getchar
#undef putchar
#undef fgetchar
#undef fputchar
#undef utime
#define getc(_stream)		rb_w32_getc(_stream)
#define putc(_c, _stream)	rb_w32_putc(_c, _stream)
#define fgetc(_stream)		getc(_stream)
#define fputc(_c, _stream)	putc(_c, _stream)
#define getchar()		rb_w32_getc(stdin)
#define putchar(_c)		rb_w32_putc(_c, stdout)
#define fgetchar()		getchar()
#define fputchar(_c)		putchar(_c)
#define utime(_p, _t)		rb_w32_utime(_p, _t)

#define strcasecmp(s1, s2)	stricmp(s1, s2)
#define strncasecmp(s1, s2, n)	strnicmp(s1, s2, n)

#define close(h)		rb_w32_close(h)
#define fclose(f)		rb_w32_fclose(f)
#define read(f, b, s)		rb_w32_read(f, b, s)
#define write(f, b, s)		rb_w32_write(f, b, s)
#define getpid()		rb_w32_getpid()
#define sleep(x)		rb_w32_sleep((x)*1000)
#ifdef __BORLANDC__
#define creat(p, m)		_creat(p, m)
#define eof()			_eof()
#define filelength(h)		_filelength(h)
#define mktemp(t)		_mktemp(t)
#define tell(h)			_tell(h)
#define unlink(p)		_unlink(p)
#define _open			_sopen
#define sopen			_sopen
#undef fopen
#define fopen(p, m)		rb_w32_fopen(p, m)
#undef fdopen
#define fdopen(h, m)		rb_w32_fdopen(h, m)
#undef fsopen
#define fsopen(p, m, sh)	rb_w32_fsopen(p, m, sh)
#endif
#define fsync(h)		_commit(h)
#undef stat
#define stat(path,st)		rb_w32_stat(path,st)
#undef execv
#define execv(path,argv)	do_aspawn(P_OVERLAY,path,argv)
#if !defined(__BORLANDC__) && !defined(_WIN32_WCE)
#undef isatty
#define isatty(h)		rb_w32_isatty(h)
#endif
#undef mkdir
#define mkdir(p, m)		rb_w32_mkdir(p, m)
#undef rmdir
#define rmdir(p)		rb_w32_rmdir(p)
#undef unlink
#define unlink(p)		rb_w32_unlink(p)

struct timezone;

#ifdef __MINGW32__
#undef isascii
#define isascii __isascii
#endif
extern void   NtInitialize(int *, char ***);
extern int    rb_w32_cmdvector(const char *, char ***);
extern rb_pid_t pipe_exec(const char *, int, FILE **, FILE **);
extern int    flock(int fd, int oper);
extern int    rb_w32_accept(int, struct sockaddr *, int *);
extern int    rb_w32_bind(int, struct sockaddr *, int);
extern int    rb_w32_connect(int, struct sockaddr *, int);
extern void   rb_w32_fdset(int, fd_set*);
extern void   rb_w32_fdclr(int, fd_set*);
extern int    rb_w32_fdisset(int, fd_set*);
extern long   rb_w32_select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
extern int    rb_w32_getpeername(int, struct sockaddr *, int *);
extern int    rb_w32_getsockname(int, struct sockaddr *, int *);
extern int    rb_w32_getsockopt(int, int, int, char *, int *);
extern int    rb_w32_ioctlsocket(int, long, u_long *);
extern int    rb_w32_listen(int, int);
extern int    rb_w32_recv(int, char *, int, int);
extern int    rb_w32_recvfrom(int, char *, int, int, struct sockaddr *, int *);
extern int    rb_w32_send(int, const char *, int, int);
extern int    rb_w32_sendto(int, const char *, int, int, struct sockaddr *, int);
extern int    rb_w32_setsockopt(int, int, int, char *, int);
extern int    rb_w32_shutdown(int, int);
extern int    rb_w32_socket(int, int, int);
extern SOCKET rb_w32_get_osfhandle(int);
extern struct hostent * rb_w32_gethostbyaddr(char *, int, int);
extern struct hostent * rb_w32_gethostbyname(char *);
extern int    rb_w32_gethostname(char *, int);
extern struct protoent * rb_w32_getprotobyname(char *);
extern struct protoent * rb_w32_getprotobynumber(int);
extern struct servent  * rb_w32_getservbyname(char *, char *);
extern struct servent  * rb_w32_getservbyport(int, char *);
extern char * rb_w32_getcwd(char *, int);
extern char * rb_w32_getenv(const char *);
extern int    rb_w32_rename(const char *, const char *);
extern int    rb_w32_stat(const char *, struct stat *);
extern char **rb_w32_get_environ(void);
extern void   rb_w32_free_environ(char **);
extern int    rb_w32_map_errno(DWORD);

#define vsnprintf(s,n,f,l) rb_w32_vsnprintf(s,n,f,l)
#define snprintf   rb_w32_snprintf
extern int rb_w32_vsnprintf(char *, size_t, const char *, va_list);
extern int rb_w32_snprintf(char *, size_t, const char *, ...);

extern int chown(const char *, int, int);
extern int link(char *, char *);
extern int gettimeofday(struct timeval *, struct timezone *);
extern rb_pid_t waitpid (rb_pid_t, int *, int);
extern int do_spawn(int, const char *);
extern int do_aspawn(int, const char *, char **);
extern int kill(int, int);
extern int fcntl(int, int, ...);
extern rb_pid_t rb_w32_getpid(void);

#if !defined(__BORLANDC__) && !defined(_WIN32_WCE)
extern int rb_w32_isatty(int);
#endif
extern int rb_w32_mkdir(const char *, int);
extern int rb_w32_rmdir(const char *);
extern int rb_w32_unlink(const char*);

#ifdef __BORLANDC__
extern FILE *rb_w32_fopen(const char *, const char *);
extern FILE *rb_w32_fdopen(int, const char *);
extern FILE *rb_w32_fsopen(const char *, const char *, int);
#endif

#include <float.h>
#if !defined __MINGW32__ || defined __NO_ISOCEXT
#ifndef isnan
#define isnan(x) _isnan(x)
#endif
static inline int
finite(double x)
{
    return _finite(x);
}
#ifndef copysign
#define copysign(a, b) _copysign(a, b)
#endif
static inline double
scalb(double a, long b)
{
    return _scalb(a, b);
}
#endif

#if !defined S_IFIFO && defined _S_IFIFO
#define S_IFIFO _S_IFIFO
#endif

#ifdef __BORLANDC__
#undef S_ISDIR
#undef S_ISFIFO
#undef S_ISBLK
#undef S_ISCHR
#undef S_ISREG
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
extern rb_uid_t  getuid (void);
extern rb_uid_t  geteuid (void);
extern rb_gid_t  getgid (void);
extern rb_gid_t  getegid (void);
extern int       setuid (rb_uid_t);
extern int       setgid (rb_gid_t);

extern char *rb_w32_strerror(int);

#define strerror(e) rb_w32_strerror(e)

#define PIPE_BUF 1024

#define LOCK_SH 1
#define LOCK_EX 2
#define LOCK_NB 4
#define LOCK_UN 8


#ifndef SIGINT
#define SIGINT 2
#endif
#ifndef SIGKILL
#define SIGKILL	9
#endif


/* #undef va_start */
/* #undef va_end */

/* winsock error map */
#include <errno.h>

#ifndef EWOULDBLOCK
# define EWOULDBLOCK		WSAEWOULDBLOCK
#endif
#ifndef EINPROGRESS
# define EINPROGRESS		WSAEINPROGRESS
#endif
#ifndef EALREADY
# define EALREADY		WSAEALREADY
#endif
#ifndef ENOTSOCK
# define ENOTSOCK		WSAENOTSOCK
#endif
#ifndef EDESTADDRREQ
# define EDESTADDRREQ		WSAEDESTADDRREQ
#endif
#ifndef EMSGSIZE
# define EMSGSIZE		WSAEMSGSIZE
#endif
#ifndef EPROTOTYPE
# define EPROTOTYPE		WSAEPROTOTYPE
#endif
#ifndef ENOPROTOOPT
# define ENOPROTOOPT		WSAENOPROTOOPT
#endif
#ifndef EPROTONOSUPPORT
# define EPROTONOSUPPORT	WSAEPROTONOSUPPORT
#endif
#ifndef ESOCKTNOSUPPORT
# define ESOCKTNOSUPPORT	WSAESOCKTNOSUPPORT
#endif
#ifndef EOPNOTSUPP
# define EOPNOTSUPP		WSAEOPNOTSUPP
#endif
#ifndef EPFNOSUPPORT
# define EPFNOSUPPORT		WSAEPFNOSUPPORT
#endif
#ifndef EAFNOSUPPORT
# define EAFNOSUPPORT		WSAEAFNOSUPPORT
#endif
#ifndef EADDRINUSE
# define EADDRINUSE		WSAEADDRINUSE
#endif
#ifndef EADDRNOTAVAIL
# define EADDRNOTAVAIL		WSAEADDRNOTAVAIL
#endif
#ifndef ENETDOWN
# define ENETDOWN		WSAENETDOWN
#endif
#ifndef ENETUNREACH
# define ENETUNREACH		WSAENETUNREACH
#endif
#ifndef ENETRESET
# define ENETRESET		WSAENETRESET
#endif
#ifndef ECONNABORTED
# define ECONNABORTED		WSAECONNABORTED
#endif
#ifndef ECONNRESET
# define ECONNRESET		WSAECONNRESET
#endif
#ifndef ENOBUFS
# define ENOBUFS		WSAENOBUFS
#endif
#ifndef EISCONN
# define EISCONN		WSAEISCONN
#endif
#ifndef ENOTCONN
# define ENOTCONN		WSAENOTCONN
#endif
#ifndef ESHUTDOWN
# define ESHUTDOWN		WSAESHUTDOWN
#endif
#ifndef ETOOMANYREFS
# define ETOOMANYREFS		WSAETOOMANYREFS
#endif
#ifndef ETIMEDOUT
# define ETIMEDOUT		WSAETIMEDOUT
#endif
#ifndef ECONNREFUSED
# define ECONNREFUSED		WSAECONNREFUSED
#endif
#ifndef ELOOP
# define ELOOP			WSAELOOP
#endif
/*#define ENAMETOOLONG	WSAENAMETOOLONG*/
#ifndef EHOSTDOWN
# define EHOSTDOWN		WSAEHOSTDOWN
#endif
#ifndef EHOSTUNREACH
# define EHOSTUNREACH		WSAEHOSTUNREACH
#endif
/*#define ENOTEMPTY	WSAENOTEMPTY*/
#ifndef EPROCLIM
# define EPROCLIM		WSAEPROCLIM
#endif
#ifndef EUSERS
# define EUSERS			WSAEUSERS
#endif
#ifndef EDQUOT
# define EDQUOT			WSAEDQUOT
#endif
#ifndef ESTALE
# define ESTALE			WSAESTALE
#endif
#ifndef EREMOTE
# define EREMOTE		WSAEREMOTE
#endif

#define F_SETFL 1
#define O_NONBLOCK 1

#ifdef accept
#undef accept
#endif
#define accept(s, a, l)		rb_w32_accept(s, a, l)

#ifdef bind
#undef bind
#endif
#define bind(s, a, l)		rb_w32_bind(s, a, l)

#ifdef connect
#undef connect
#endif
#define connect(s, a, l)	rb_w32_connect(s, a, l)

#undef FD_SET
#define FD_SET(f, s)		rb_w32_fdset(f, s)

#undef FD_CLR
#define FD_CLR(f, s)		rb_w32_fdclr(f, s)

#undef FD_ISSET
#define FD_ISSET(f, s)		rb_w32_fdisset(f, s)

#undef select
#define select(n, r, w, e, t)	rb_w32_select(n, r, w, e, t)

#ifdef getpeername
#undef getpeername
#endif
#define getpeername(s, a, l)	rb_w32_getpeername(s, a, l)

#ifdef getsockname
#undef getsockname
#endif
#define getsockname(s, a, l)	rb_w32_getsockname(s, a, l)

#ifdef getsockopt
#undef getsockopt
#endif
#define getsockopt(s, v, n, o, l) rb_w32_getsockopt(s, v, n, o, l)

#ifdef ioctlsocket
#undef ioctlsocket
#endif
#define ioctlsocket(s, c, a)	rb_w32_ioctlsocket(s, c, a)

#ifdef listen
#undef listen
#endif
#define listen(s, b)		rb_w32_listen(s, b)

#ifdef recv
#undef recv
#endif
#define recv(s, b, l, f)	rb_w32_recv(s, b, l, f)

#ifdef recvfrom
#undef recvfrom
#endif
#define recvfrom(s, b, l, f, fr, frl) rb_w32_recvfrom(s, b, l, f, fr, frl)

#ifdef send
#undef send
#endif
#define send(s, b, l, f)	rb_w32_send(s, b, l, f)

#ifdef sendto
#undef sendto
#endif
#define sendto(s, b, l, f, t, tl) rb_w32_sendto(s, b, l, f, t, tl)

#ifdef setsockopt
#undef setsockopt
#endif
#define setsockopt(s, v, n, o, l) rb_w32_setsockopt(s, v, n, o, l)

#ifdef shutdown
#undef shutdown
#endif
#define shutdown(s, h)		rb_w32_shutdown(s, h)

#ifdef socket
#undef socket
#endif
#define socket(s, t, p)		rb_w32_socket(s, t, p)

#ifdef gethostbyaddr
#undef gethostbyaddr
#endif
#define gethostbyaddr(a, l, t)	rb_w32_gethostbyaddr(a, l, t)

#ifdef gethostbyname
#undef gethostbyname
#endif
#define gethostbyname(n)	rb_w32_gethostbyname(n)

#ifdef gethostname
#undef gethostname
#endif
#define gethostname(n, l)	rb_w32_gethostname(n, l)

#ifdef getprotobyname
#undef getprotobyname
#endif
#define getprotobyname(n)	rb_w32_getprotobyname(n)

#ifdef getprotobynumber
#undef getprotobynumber
#endif
#define getprotobynumber(n)	rb_w32_getprotobynumber(n)

#ifdef getservbyname
#undef getservbyname
#endif
#define getservbyname(n, p)	rb_w32_getservbyname(n, p)

#ifdef getservbyport
#undef getservbyport
#endif
#define getservbyport(p, pr)	rb_w32_getservbyport(p, pr)

#ifdef get_osfhandle
#undef get_osfhandle
#endif
#define get_osfhandle(h)	rb_w32_get_osfhandle(h)

#ifdef getcwd
#undef getcwd
#endif
#define getcwd(b, s)		rb_w32_getcwd(b, s)

#ifdef getenv
#undef getenv
#endif
#define getenv(n)		rb_w32_getenv(n)

#ifdef rename
#undef rename
#endif
#define rename(o, n)		rb_w32_rename(o, n)

struct tms {
	long	tms_utime;
	long	tms_stime;
	long	tms_cutime;
	long	tms_cstime;
};

#ifdef times
#undef times
#endif
#define times(t) rb_w32_times(t)
int rb_w32_times(struct tms *);

/* thread stuff */
HANDLE GetCurrentThreadHandle(void);
void rb_w32_interrupted(void);
int  rb_w32_main_context(int arg, void (*handler)(int));
int  rb_w32_sleep(unsigned long msec);
void rb_w32_enter_critical(void);
void rb_w32_leave_critical(void);
int  rb_w32_putc(int, FILE*);
int  rb_w32_getc(FILE*);
int  rb_w32_close(int);
int  rb_w32_fclose(FILE*);
size_t rb_w32_read(int, void *, size_t);
size_t rb_w32_write(int, const void *, size_t);
int  rb_w32_utime(const char *, struct utimbuf *);
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
