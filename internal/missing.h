/**                                                         \noop-*-C-*-vi:ft=c
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header corresponding missing.
 */
#ifndef INTERNAL_MISSING_H
#define INTERNAL_MISSING_H
#include "ruby/3/config.h"      /* for HAVE_SETPROCTITLE */

/* missing/setproctitle.c */
#ifndef HAVE_SETPROCTITLE
extern void ruby_init_setproctitle(int argc, char *argv[]);
#endif

#endif /* INTERNAL_MISSING_H */
