/************************************************

  dln.h -

  $Author$
  $Revision$
  $Date$
  created at: Wed Jan 19 16:53:09 JST 1994

************************************************/
#ifndef DLN_H
#define DLN_H

char *dln_find_exe();
char *dln_find_file();

#ifdef USE_DLN_A_OUT
extern char *dln_argv0;
#endif

void dln_load();
#endif
