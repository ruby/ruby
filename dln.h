/************************************************

  dln.h -

  $Author: matz $
  $Revision: 1.2 $
  $Date: 1994/08/12 04:47:17 $
  created at: Wed Jan 19 16:53:09 JST 1994

************************************************/
#ifndef DLN_H
#define DLN_H

#include <sys/errno.h>

char *dln_find_exe();
char *dln_find_file();

int dln_init();
int dln_load();
int dln_load_lib();

char *dln_strerror();
void dln_perror();

#endif
