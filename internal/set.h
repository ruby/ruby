#ifndef INTERNAL_SET_H                                   /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_SET_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Set.
 */
#include "ruby/internal/config.h"
#include "ruby/ruby.h"

VALUE rb_ident_set_new(void);
bool rb_set_add_no_check(VALUE set, VALUE element);
bool rb_set_delete_no_check(VALUE set, VALUE element);
VALUE rb_set_to_a(VALUE set);

#endif /* INTERNAL_SET_H */
