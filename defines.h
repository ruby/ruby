/************************************************

  defines.h -

  $Author$
  $Date$
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

#define RUBY

/* define RUBY_USE_EUC/SJIS for default kanji-code */
#ifndef DEFAULT_KCODE
#if defined(MSDOS) || defined(__CYGWIN__) || defined(__human68k__) || defined(__MACOS__) || defined(__EMX__) || defined(OS2) || defined(NT)
#define DEFAULT_KCODE KCODE_SJIS
#else
#define DEFAULT_KCODE KCODE_EUC
#endif
#endif

#ifdef NeXT
#define DYNAMIC_ENDIAN		/* determine endian at runtime */
#ifndef __APPLE__
#define S_IXUSR _S_IXUSR        /* execute/search permission, owner */
#endif
#define S_IXGRP 0000010         /* execute/search permission, group */
#define S_IXOTH 0000001         /* execute/search permission, other */

#define HAVE_SYS_WAIT_H         /* configure fails to find this */
#endif /* NeXT */

#ifdef NT
#include "win32/win32.h"
#endif

#if defined __CYGWIN__
# undef EXTERN
# if defined USEIMPORTLIB
#  define EXTERN extern __declspec(dllimport)
# else
#  define EXTERN extern __declspec(dllexport)
# endif
#endif

#ifndef EXTERN
#define EXTERN extern
#endif

#if defined(sparc) || defined(__sparc__)
# if defined(linux) || defined(__linux__)
#define FLUSH_REGISTER_WINDOWS  asm("ta  0x83")
# elif defined(__FreeBSD__) && defined(__sparc64__)
#define FLUSH_REGISTER_WINDOWS  asm volatile("flushw" : :)
# else /* Solaris, OpenBSD, NetBSD, etc. */
#define FLUSH_REGISTER_WINDOWS  asm("ta  0x03")
# endif /* trap always to flush register windows if we are on a Sparc system */
#else /* Not a sparc, so */
#define FLUSH_REGISTER_WINDOWS  /* empty -- nothing to do here */
#endif 

#if defined(MSDOS) || defined(_WIN32) || defined(__human68k__) || defined(__EMX__)
#define DOSISH 1
#endif

#if defined(MSDOS) || defined(NT) || defined(__human68k__) || defined(OS2)
#define PATH_SEP ";"
#elif defined(riscos)
#define PATH_SEP ","
#else
#define PATH_SEP ":"
#endif
#define PATH_SEP_CHAR PATH_SEP[0]

#if defined(__human68k__)
#undef HAVE_RANDOM
#undef HAVE_SETITIMER
#endif

#if defined(DJGPP) || defined(__BOW__)
#undef HAVE_SETITIMER
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#endif
