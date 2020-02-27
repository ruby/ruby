/**                                                         \noop-*-C-*-vi:ft=c
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Dir.
 */
#ifndef INTERNAL_DIR_H
#define INTERNAL_DIR_H
#include "ruby/ruby.h"          /* for VALUE */

/* dir.c */
VALUE rb_dir_getwd_ospath(void);

#endif /* INTERNAL_DIR_H */
