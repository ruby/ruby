/************************************************

  defines.h -

  $Author: matz $
  $Date: 1995/01/10 10:42:25 $
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

#define RUBY

/* define EUC/SJIS for default kanji-code */
#define EUC
#undef SJIS

#ifdef NeXT
#define S_IXUSR _S_IXUSR        /* execute/search permission, owner */
#define S_IXGRP 0000010         /* execute/search permission, group */
#define S_IXOTH 0000001         /* execute/search permission, other */
#define S_ISREG(mode)   (((mode) & (_S_IFMT)) == (_S_IFREG))
#endif /* NeXT */

#ifdef NT
#include "missing/nt.h"
#endif

#ifdef sparc
#define FLUSH_REGISTER_WINDOWS asm("ta 3")
#else
#define FLUSH_REGISTER_WINDOWS /* empty */
#endif

#endif
