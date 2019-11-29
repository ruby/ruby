#ifndef INTERNAL_ENUM_H /* -*- C -*- */
#define INTERNAL_ENUM_H
/**
 * @file
 * @brief      Internal header for Enumerable.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* enum.c */
extern VALUE rb_cArithSeq;
VALUE rb_f_send(int argc, VALUE *argv, VALUE recv);
VALUE rb_nmin_run(VALUE obj, VALUE num, int by, int rev, int ary);

#endif /* INTERNAL_ENUM_H */
