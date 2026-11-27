#ifndef INTERNAL_MARSHAL_H                               /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_MARSHAL_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Marshal.
 */
#include "ruby/internal/stdbool.h"    /* for bool */
#include "ruby/ruby.h"                /* for VALUE */

/* marshal.c */
bool rb_marshal_compat_lookup(VALUE klass, VALUE (**dumper)(VALUE), VALUE (**loader)(VALUE, VALUE));

#endif /* INTERNAL_MARSHAL_H */
