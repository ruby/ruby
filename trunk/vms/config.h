#define HAVE_ACOSH 1
/* #define HAVE_ALLOCA_H 1 */
/* #define HAVE_CHROOT 1 */
#define HAVE_COSH 1
/* #define HAVE_CRYPT 1 */
#define HAVE_DAYLIGHT 1
#define HAVE_DECL_SYS_NERR 1
#define HAVE_DIRENT_H 1
#define HAVE_DLOPEN 1
#define HAVE_DUP2 1
/* #define HAVE_FCHMOD 1 */
#define HAVE_FCNTL 1
#define HAVE_FCNTL_H 1
#define HAVE_FINITE 1
#define HAVE_FLOCK 1
#define HAVE_FMOD 1
#define HAVE_FREXP 1
/* #define HAVE_FSEEKO 1 */
#define HAVE_FSYNC 1
/* #define HAVE_FTELLO 1 */
#define HAVE_GETCWD 1
/* #define HAVE_GETPGID 1 xxxx */
#define HAVE_GETPGRP 1
/* #define HAVE_GETPRIORITY 1 */
/* #define HAVE_GETRLIMIT 1 */
#define HAVE_PID_T 1
#define HAVE_GID_T 1
#define HAVE_UID_T 1
#define HAVE_HYPOT 1
#define HAVE_ISASCII 1
/* #define HAVE_ISINF 1 */
#define HAVE_ISNAN 1
/* #define HAVE_LCHMOD 1 */
/* #define HAVE_LCHOWN 1 */
#define HAVE_LONG_LONG 1 
/* #define HAVE_LSTAT 1 */
#define HAVE_MEMCMP 1
#define HAVE_MEMMOVE 1
#define HAVE_MKDIR 1
#define HAVE_MKTIME 1
#define HAVE_MODF 1
#define HAVE_OFF_T 1
#define HAVE_PAUSE 1
/* #define HAVE_PROTOTYPES 1 */
/* #define HAVE_PWD_H 1 */
/* #define HAVE_READLINK 1 */
#define HAVE_SEEKDIR 1
/* #define HAVE_SETITIMER 1 */
/* #define HAVE_SETPGID 1 xxxx */
/* #define HAVE_SETRESGID 1 */
/* #define HAVE_SETRESUID 1 */
/* #define HAVE_SETSID 1 xxxx */
#define HAVE_SIGPROCMASK 1
#define HAVE_SINH 1
#define HAVE_STDARG_PROTOTYPES 1
#define HAVE_STDLIB_H 1
#define HAVE_STRCASECMP 1
#define HAVE_STRCHR 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRING_H 1
#define HAVE_STRNCASECMP 1
#define HAVE_STRSTR 1
#define HAVE_STRTOD 1
#define HAVE_STRTOL 1
#define HAVE_STRTOUL 1
#define HAVE_STRUCT_TM_TM_GMTOFF 1
/* #define HAVE_ST_BLKSIZE 1 */
/* #define HAVE_ST_BLOCKS 1 */
#define HAVE_ST_RDEV 1
/* #define HAVE_SYMLINK 1 */
/* #define HAVE_SYSCALL 1 */
#define HAVE_SYS_FILE_H 1
/* #define HAVE_SYS_MKDEV_H 1 */
/* #define HAVE_SYS_PARAM_H 1 */
#define HAVE_SYS_RESOURCE_H 1
/* #define HAVE_SYS_SELECT_H 1 */
#define HAVE_SYS_TIMES_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TANH 1
#define HAVE_TELLDIR 1
/* #define HAVE_TIMEGM 1 */
#define HAVE_TIMES 1
#define HAVE_TM_ZONE 1
#define HAVE_TRUNCATE 1
#define HAVE_TZNAME 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIMES 1
#define HAVE_UTIME_H 1
/* #define HAVE_VSNPRINTF 1 */
#define HAVE_WAIT4 1
#define HAVE_WAITPID 1
 #define HAVE__SETJMP 1

#define GETGROUPS_T gid_t
#define RETSIGTYPE void

#define RSHIFT(x,y) ((x)>>y)
#define DEFAULT_KCODE KCODE_EUC
#define DLEXT ".EXE"
#define DLEXT2 ""
#define RUBY_LIB "/RUBY_LIB"
#define RUBY_SITE_LIB "/RUBY_SYSLIB"
#define RUBY_SITE_LIB2 "/SYS$SHARE"
#define RUBY_ARCHLIB ""
#define RUBY_SITE_ARCHLIB ""
#define SIZEOF_INT 4
#define SIZEOF_SHORT 2
#define SIZEOF_LONG 4
#define SIZEOF_VOIDP 4
#define SIZEOF_FLOAT 4
#define SIZEOF_DOUBLE 8

#if defined(__vax)
#define RUBY_PLATFORM "vax-vms"
#elif defined(__alpha)
#define RUBY_PLATFORM "alpha-vms"
#elif defined(__ia-64)
#define RUBY_PLATFORM "ia64-vms"
#else
#define RUBY_PLATFORM "vms"
#endif
