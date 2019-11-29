#ifndef INTERNAL_ENUMERATOR_H /* -*- C -*- */
#define INTERNAL_ENUMERATOR_H
/**
 * @file
 * @brief      Internal header for Enumerator.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

RUBY_SYMBOL_EXPORT_BEGIN
/* enumerator.c (export) */
VALUE rb_arith_seq_new(VALUE obj, VALUE meth, int argc, VALUE const *argv,
                       rb_enumerator_size_func *size_fn,
                       VALUE beg, VALUE end, VALUE step, int excl);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_ENUMERATOR_H */
