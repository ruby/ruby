/************************************************

  defines.h -

  $Author$
  $Date$
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

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

#ifdef __NeXT__
#define S_IXGRP 0000010         /* execute/search permission, group */
#define S_IXOTH 0000001         /* execute/search permission, other */
#ifndef __APPLE__
#define S_IXUSR _S_IXUSR        /* execute/search permission, owner */
#define GETPGRP_VOID 1
#define WNOHANG 01
#define WUNTRACED 02
#define X_OK 1
typedef int pid_t;
/* Do not trust WORDS_BIGENDIAN from configure since -arch compiler flag may
   result in a different endian. */
#undef WORDS_BIGENDIAN
#ifdef __BIG_ENDIAN__
#define WORDS_BIGENDIAN
#endif
#endif
#endif /* NeXT */

#ifdef __CYGWIN__
#undef _WIN32
#endif
#ifdef _WIN32
#include "win32/win32.h"
#endif

#if defined(__VMS)
#include "vms/vms.h"
#endif

#undef RUBY_EXTERN
#if defined _WIN32 && !defined __GNUC__
# ifndef RUBY_EXPORT
#  define RUBY_EXTERN extern __declspec(dllimport)
# endif
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

#ifndef EXTERN
#define EXTERN RUBY_EXTERN	/* deprecated */
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
# elif defined(linux) || defined(__linux__)
	("ta  0x83")
# else /* Solaris, OpenBSD, NetBSD, etc. */
	("ta  0x03")
# endif /* trap always to flush register windows if we are on a Sparc system */
	;
}
#  define FLUSH_REGISTER_WINDOWS flush_register_windows()
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

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#endif
