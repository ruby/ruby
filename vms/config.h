/* config.h for OpenVMS */

#ifndef VMS_RUBY_STREAM
#define VMS_RUBY_STREAM "018"
#endif

/* #define HAVE_PROTOTYPES 1 */
#define HAVE_STDARG_PROTOTYPES 1
/* #define HAVE_ATTR_NORETURN 1 */
/* #define inline __inline */
#define HAVE_DIRENT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STDLIB_H 1
#define HAVE_LIMITS_H 1

#define HAVE_SYS_FILE_H 1
#define HAVE_FCNTL_H 1
/* #define HAVE_PWD_H 1 */
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TIMES_H 1
/* #define HAVE_SYS_PARAM_H 1 */
#define HAVE_SYS_WAIT_H 1
#define HAVE_STRING_H 1
#define HAVE_UTIME_H 1
#define HAVE_MEMORY_H 1
/* #define HAVE_ST_BLKSIZE 1  */
#define HAVE_ST_RDEV 1
/* #define GETGROUPS_T gid_t */
#define GETGROUPS_T int
#define RETSIGTYPE void
/* #define HAVE_ALLOCA 1 */
/* #define vfork fork */
#define HAVE_FMOD 1
#define HAVE_RANDOM 1
#define HAVE_WAITPID 1
#define HAVE_GETCWD 1
#define HAVE_TRUNCATE 1
/* #define HAVE_CHSIZE 1 */
#define HAVE_TIMES 1
/* #define HAVE_UTIMES 1 */
#define HAVE_FCNTL 1
/* #define HAVE_SETITIMER 1 */
/* #define HAVE_GETGROUPS 1 */
#define HAVE_SIGPROCMASK 1
#define HAVE_GETLOGIN 1
#define HAVE_TELLDIR 1
#define HAVE_SEEKDIR 1

#define RSHIFT(x,y) ((x)>>y)
#define DEFAULT_KCODE KCODE_EUC
#define DLEXT ".exe"
/* #define DLEXT2 "" */

#define HAVE_STRERROR 1

#if defined(__vax)
#define RUBY_PLATFORM     "vax-vms"	/* OpenVMS VAX */
#elif defined(__alpha)
#define RUBY_PLATFORM     "alpha-vms"	/* OpenVMS Alpha */
#elif defined(__ia64)
#define RUBY_PLATFORM     "ia64-vms"	/* OpenVMS Industry Standard 64 */
#else
#define RUBY_PLATFORM     "unknown-vms"	/* unknown processor */
#endif

#define RUBY_SITE_LIB2    "/RUBY_LIBROOT/site_ruby/" RUBY_PLATFORM
#define RUBY_SITE_ARCHLIB "/RUBY_LIBROOT/site_ruby/" VMS_RUBY_STREAM "/" RUBY_PLATFORM
#define RUBY_SITE_LIB     "/RUBY_LIBROOT/site_ruby"
#define RUBY_LIB          "/RUBY_LIBROOT/" VMS_RUBY_STREAM
#define RUBY_ARCHLIB      "/RUBY_LIBROOT/" VMS_RUBY_STREAM "/" RUBY_PLATFORM

#define SIZEOF_INT   4
#define SIZEOF_SHORT 2
#define SIZEOF_LONG  4
#define SIZEOF_VOIDP 4
#define SIZEOF_FLOAT 4
#define SIZEOF_DOUBLE 8

#define HAVE_MKDIR 	1 /* Dango */
#define HAVE_SINH 	1 /* Dango */
#define HAVE_COSH 	1 /* Dango */
#define HAVE_TANH 	1 /* Dango */

/* function flags for socket ---------------------- */

#define HAVE_GETHOSTNAME 1
#define HAVE_SENDMSG 1
#define HAVE_RECVMSG 1
#define HAVE_GETNAMEINFO 1
#define HAVE_INET_NTOP 1
#define HAVE_INET_NTOA 1
#define HAVE_INET_PTON 1
#define HAVE_INET_ATON 1
#define HAVE_GETSERVBYPORT 1
#define HAVE_UNAME 1
/*
#define HAVE_GETHOSTBYNAME2 1
#define HAVE_GETADDRINFO 1
*/
