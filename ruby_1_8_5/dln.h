/**********************************************************************

  dln.h -

  $Author: michal $
  $Date: 2003/01/16 07:34:01 $
  created at: Wed Jan 19 16:53:09 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#ifndef DLN_H
#define DLN_H

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

char *dln_find_exe _((const char*,const char*));
char *dln_find_file _((const char*,const char*));

#ifdef USE_DLN_A_OUT
extern char *dln_argv0;
#endif

void *dln_load _((const char*));
#endif
