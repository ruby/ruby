/**                                                         \noop-*-C-*-vi:ft=c
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for rb_serial_t.
 */
#ifndef INTERNAL_SERIAL_H
#define INTERNAL_SERIAL_H
#include "ruby/3/config.h"      /* for HAVE_LONG_LONG */
#include "ruby/defines.h"       /* for LONG_LONG */

#ifndef HAVE_LONG_LONG
# error need C99+
#endif

typedef unsigned LONG_LONG rb_serial_t;
#define SERIALT2NUM ULL2NUM
#define PRI_SERIALT_PREFIX PRI_LL_PREFIX
#define SIZEOF_SERIAL_T SIZEOF_LONG_LONG

#endif /* INTERNAL_SERIAL_H */
