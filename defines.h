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
#if defined(MSDOS) || defined(__CYGWIN32__) || defined(__human68k__) || defined(__MACOS__) || defined(__EMX__) || defined(OS2) || defined(NT)
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

#ifdef sparc
#define FLUSH_REGISTER_WINDOWS asm("ta 3")
#else
#define FLUSH_REGISTER_WINDOWS /* empty */
#endif

#if defined(MSDOS) || defined(_WIN32) || defined(__human68k__) || defined(__EMX__)
#define DOSISH 1
#endif

#if defined(MSDOS) || defined(NT) || defined(__human68k__) || defined(OS2)
#define PATH_SEP ";"
#else
#define PATH_SEP ":"
#endif
#define PATH_SEP_CHAR PATH_SEP[0]

#if defined(__human68k__) || defined(__CYGWIN32__)
#undef HAVE_RANDOM
#undef HAVE_SETITIMER
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#endif
