/************************************************

  defines.h -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Wed May 18 00:21:44 JST 1994

************************************************/
#ifndef DEFINES_H
#define DEFINES_H

#define RUBY

/* #include "config.h" */

/* define USE_DLN to load object file(.o). */
#ifdef HAVE_A_OUT_H

#undef  USE_DLN
#ifdef USE_DLN
#define LIBC_NAME "libc.a"
#define DLN_DEFAULT_PATH "/lib:/usr/lib:."
#endif

#endif

/* define USE_DBM to use dbm class. */
#define USE_DBM

#ifdef HAVE_SYSCALL_H
/* define SAFE_SIGHANDLE to override syscall for trap. */
#define SAFE_SIGHANDLE
#endif

#endif
