/**********************************************************************

  dln.h -

  $Author$
  $Date$
  created at: Wed Jan 19 16:53:09 JST 1994

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#ifndef DLN_H
#define DLN_H

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

void dln_load _((const char*));
#endif
