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

#define SAFE_SIGHANDLE

#ifdef NT
#include "missing/nt.h"
#endif

#endif
