/************************************************

  defines.h -

  $Author$
  $Date$
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

#define RUBY

/* define EUC/SJIS for default kanji-code */
#if defined(MSDOS) || defined(__CYGWIN32__) || defined(__human68k__) || defined(__MACOS__)
#undef EUC
#define SJIS
#else
#define EUC
#undef SJIS
#endif

#ifdef NeXT
#define DYNAMIC_ENDIAN		/* determine endian at runtime */
#define S_IXUSR _S_IXUSR        /* execute/search permission, owner */
#define S_IXGRP 0000010         /* execute/search permission, group */
#define S_IXOTH 0000001         /* execute/search permission, other */
#endif /* NeXT */

#ifdef NT
#include "missing/nt.h"
#endif

#ifdef sparc
#define FLUSH_REGISTER_WINDOWS asm("ta 3")
#else
#define FLUSH_REGISTER_WINDOWS /* empty */
#endif

#if defined(__human68k__) || defined(__CYGWIN32__)
#undef HAVE_RANDOM
#undef HAVE_SETITIMER
#endif

#ifndef RUBY_PLATFORM
#define RUBY_PLATFORM "unknown-unknown"
#endif

#endif
