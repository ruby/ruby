/************************************************

  defines.h -

  $Author$
  $Date$
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

#include "config.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#define RUBY

#ifdef __cplusplus
# ifndef  HAVE_PROTOTYPES
#  define HAVE_PROTOTYPES 1
# endif
# ifndef  HAVE_STDARG_PROTOTYPES
#  define HAVE_STDARG_PROTOTYPES 1
# endif
#endif

#undef _
#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif

#undef __
#ifdef HAVE_STDARG_PROTOTYPES
# define __(args) args
#else
# define __(args) ()
#endif

#ifdef __cplusplus
#define ANYARGS ...
#else
#define ANYARGS
#endif

#define xmalloc ruby_xmalloc
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xfree ruby_xfree

void *xmalloc _((long));
void *xcalloc _((long,long));
void *xrealloc _((void*,long));
void xfree _((void*));

#define STRINGIZE(expr) STRINGIZE0(expr)
#ifndef STRINGIZE0
#define STRINGIZE0(expr) #expr
#endif

#if SIZEOF_LONG_LONG > 0
# define LONG_LONG long long
#elif SIZEOF___INT64 > 0
# define HAVE_LONG_LONG 1
# define LONG_LONG __int64
# undef SIZEOF_LONG_LONG
# define SIZEOF_LONG_LONG SIZEOF___INT64
#endif

#if SIZEOF_INT*2 <= SIZEOF_LONG_LONG
# define BDIGIT unsigned int
# define SIZEOF_BDIGITS SIZEOF_INT
# define BDIGIT_DBL unsigned LONG_LONG
# define BDIGIT_DBL_SIGNED LONG_LONG
#elif SIZEOF_INT*2 <= SIZEOF_LONG
# define BDIGIT unsigned int
# define SIZEOF_BDIGITS SIZEOF_INT
# define BDIGIT_DBL unsigned long
# define BDIGIT_DBL_SIGNED long
#elif SIZEOF_SHORT*2 <= SIZEOF_LONG
# define BDIGIT unsigned short
# define SIZEOF_BDIGITS SIZEOF_SHORT
# define BDIGIT_DBL unsigned long
# define BDIGIT_DBL_SIGNED long
#else
# define BDIGIT unsigned short
# define SIZEOF_BDIGITS (SIZEOF_LONG/2)
# define BDIGIT_DBL unsigned long
# define BDIGIT_DBL_SIGNED long
#endif

#ifdef __CYGWIN__
#undef _WIN32
#endif

#if defined(MSDOS) || defined(_WIN32) || defined(__human68k__) || defined(__EMX__)
#define DOSISH 1
#ifndef _WIN32_WCE
# define DOSISH_DRIVE_LETTER
#endif
#endif

/* define RUBY_USE_EUC/SJIS for default kanji-code */
#ifndef DEFAULT_KCODE
#if defined(DOSISH) || defined(__CYGWIN__) || defined(__MACOS__) || defined(OS2)
#define DEFAULT_KCODE KCODE_SJIS
#else
#define DEFAULT_KCODE KCODE_EUC
#endif
#endif

#if defined(__NeXT__) || defined(__APPLE__)
/* Do not trust WORDS_BIGENDIAN from configure since -arch compiler flag may
   result in a different endian.  Instead trust __BIG_ENDIAN__ and
   __LITTLE_ENDIAN__ which are set correctly by -arch. */
#undef WORDS_BIGENDIAN
#ifdef __BIG_ENDIAN__
#define WORDS_BIGENDIAN
#endif
#endif

#ifdef __NeXT__
/* NextStep, OpenStep, Rhapsody */
#ifndef S_IRUSR
#define S_IRUSR 0000400        /* read permission, owner */
#endif
#ifndef S_IRGRP
#define S_IRGRP 0000040        /* read permission, group */
#endif
#ifndef S_IROTH
#define S_IROTH 0000004        /* read permission, other */
#endif
#ifndef S_IWUSR
#define S_IWUSR 0000200        /* write permission, owner */
#endif
#ifndef S_IWGRP
#define S_IWGRP 0000020        /* write permission, group */
#endif
#ifndef S_IWOTH
#define S_IWOTH 0000002        /* write permission, other */
#endif
#ifndef S_IXUSR
#define S_IXUSR 0000100        /* execute/search permission, owner */
#endif
#ifndef S_IXGRP
#define S_IXGRP 0000010        /* execute/search permission, group */
#endif
#ifndef S_IXOTH
#define S_IXOTH 0000001        /* execute/search permission, other */
#endif
#ifndef S_IRWXU
#define S_IRWXU 0000700        /* read, write, execute permissions, owner */
#endif
#ifndef S_IRWXG
#define S_IRWXG 0000070        /* read, write, execute permissions, group */
#endif
#ifndef S_IRWXO
#define S_IRWXO 0000007        /* read, write, execute permissions, other */
#endif
#ifndef S_ISBLK
#define S_ISBLK(mode)  (((mode) & (0170000)) == (0060000))
#endif
#ifndef S_ISCHR
#define S_ISCHR(mode)  (((mode) & (0170000)) == (0020000))
#endif
#ifndef S_ISDIR
#define S_ISDIR(mode)  (((mode) & (0170000)) == (0040000))
#endif
#ifndef S_ISFIFO
#define S_ISFIFO(mode) (((mode) & (0170000)) == (0010000))
#endif
#ifndef S_ISREG
#define S_ISREG(mode)  (((mode) & (0170000)) == (0100000))
#endif
#ifndef __APPLE__
/* NextStep, OpenStep (but not Rhapsody) */
#ifndef GETPGRP_VOID
#define GETPGRP_VOID 1
#endif
#ifndef WNOHANG
#define WNOHANG 01
#endif
#ifndef WUNTRACED
#define WUNTRACED 02
#endif
#ifndef X_OK
#define X_OK 1
#endif
#endif /* __APPLE__ */
#endif /* NeXT */

#ifdef _WIN32
#include "win32/win32.h"
#endif

#if defined(__VMS)
#include "vms.h"
#endif

#if defined(__BEOS__) && !defined(BONE)
#include <net/socket.h> /* intern.h needs fd_set definition */
#endif

#ifdef RUBY_EXPORT
#undef RUBY_EXTERN
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

#ifndef EXTERN
#define EXTERN RUBY_EXTERN	/* deprecated */
#endif

#ifndef RUBY_MBCHAR_MAXSIZE
#define RUBY_MBCHAR_MAXSIZE INT_MAX
        /* MB_CUR_MAX will not work well in C locale */
#endif

#if defined(sparc) || defined(__sparc__)
static inline void
flush_register_windows(void)
{
    asm
#ifdef __GNUC__
	volatile
#endif
# if defined(__sparc_v9__) || defined(__sparcv9) || defined(__arch64__)
	("flushw")
# else
	("ta  0x03")
# endif /* trap always to flush register windows if we are on a Sparc system */
	;
}
#  define FLUSH_REGISTER_WINDOWS flush_register_windows()
#elif defined(__ia64)
void *rb_ia64_bsp(void);
void rb_ia64_flushrs(void);
#  define FLUSH_REGISTER_WINDOWS rb_ia64_flushrs()
#else
#  define FLUSH_REGISTER_WINDOWS ((void)0)
#endif

#if defined(DOSISH)
#define PATH_SEP ";"
#elif defined(riscos)
#define PATH_SEP ","
#else
#define PATH_SEP ":"
#endif
#define PATH_SEP_CHAR PATH_SEP[0]

#if defined(__human68k__)
#define PATH_ENV "path"
#else
#define PATH_ENV "PATH"
#endif

#if defined(DOSISH) && !defined(__human68k__) && !defined(__EMX__)
#define ENV_IGNORECASE
#endif

#ifndef CASEFOLD_FILESYSTEM
# if defined DOSISH || defined __VMS
#   define CASEFOLD_FILESYSTEM 1
# else
#   define CASEFOLD_FILESYSTEM 0
# endif
#endif

#ifndef DLEXT_MAXLEN
#define DLEXT_MAXLEN 4
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#endif
