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


/* define USE_DL to load object file(.o). */
#define USE_DL

/* a.out.h or dlopen() needed to load object */
#if !defined(HAVE_DLOPEN) || !defined(HAVE_A_OUT_H)
# undef USE_DL
#endif

#ifdef USE_MY_DLN
#  define LIBC_NAME "libc.a"
#  define DLN_DEFAULT_PATH "/lib:/usr/lib:."
#endif

/* define USE_DBM to use dbm class. */
#define USE_DBM

#define SAFE_SIGHANDLE

#endif
