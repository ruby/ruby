/************************************************

  dln.h -

  $Author: matz $
  $Revision: 1.1.1.1 $
  $Date: 1994/06/17 14:23:49 $
  created at: Wed Jan 19 16:53:09 JST 1994

************************************************/
#ifndef DLN_H
#define DLN_H

#include <sys/errno.h>

int dln_init();
int dln_load();
int dln_load_lib();

extern int dln_errno;

#define DLN_ENOENT	ENOENT	/* No such file or directory */
#define DLN_ENOEXEC	ENOEXEC	/* Exec format error */
#define DLN_ECONFL	101	/* Symbol name conflict */
#define DLN_ENOINIT	102	/* No inititalizer given */
#define DLN_EUNDEF	103	/* Undefine symbol remains */
#define DLN_ENOTLIB	104	/* Not a library file */
#define DLN_EBADLIB	105	/* Malformed library file */
#define DLN_EINIT	106	/* Not initialized */

char *dln_strerror();

#endif
