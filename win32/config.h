#define THREAD 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_VOIDP 4
#define HAVE_PROTOTYPES 1
#define HAVE_STDARG_PROTOTYPES 1
#define HAVE_ATTR_NORETURN 1
/* #define HAVE_DIRENT_H 1 */
/* #define HAVE_UNISTD_H 1 */
#define HAVE_STDLIB_H 1
#define HAVE_LIMITS_H 1
#define HAVE_SYS_FILE_H 1
/* #define HAVE_PWD_H 1       */
/* #define HAVE_SYS_TIME_H 1  */
/* #define HAVE_SYS_TIMES_H 1 */
/* #define HAVE_SYS_PARAM_H 1 */
/* #define HAVE_SYS_WAIT_H 1  */
#define HAVE_STRING_H 1
/* #define HAVE_UTIME_H 1     */
#define HAVE_MEMORY_H 1
/* #define HAVE_ST_BLKSIZE 1  */
#define HAVE_ST_RDEV 1
/* #define GETGROUPS_T gid_t */
#define GETGROUPS_T int
#define RETSIGTYPE void
#define HAVE_ALLOCA 1
#define vfork fork
#define HAVE_FMOD 1
/* #define HAVE_RANDOM 1    */
/* #define HAVE_WAITPID 1   */
#define HAVE_GETCWD 1
/* #define HAVE_TRUNCATE 1  */
#define HAVE_CHSIZE 1
/* #define HAVE_TIMES 1     */
/* #define HAVE_UTIMES 1    */
/* #define HAVE_FCNTL 1     */
/* #define HAVE_SETITIMER 1 */
#define HAVE_GETGROUPS 1
/* #define HAVE_SIGPROCMASK 1 */
#define FILE_COUNT _cnt
#define DLEXT ".dll"
#define RUBY_LIB ";/usr/local/lib/ruby;."
#define RUBY_ARCHLIB "/usr/local/lib/ruby/i386-mswin32"
#define RUBY_PLATFORM "i386-mswin32"

/* NNN */
#define strcasecmp _strcmpi
#define popen _popen
#define pclose _pclose
#define pipe   _pipe
#define bzero(x, y) memset(x, 0, y)

#define S_IFMT   _S_IFMT
#define S_IFDIR  _S_IFDIR
#define S_IFCHR  _S_IFCHR
#define S_IFREG  _S_IFREG
#define S_IREAD  _S_IREAD
#define S_IWRITE _S_IWRITE
#define S_IEXEC  _S_IEXEC
#define S_IFIFO  _S_IFIFO

#define UIDTYPE int
#define GIDTYPE int
#define pid_t   int
#define WNOHANG -1
//#define NT
