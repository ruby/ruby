#ifndef INTERNAL_SIGNAL_H /* -*- C -*- */
#define INTERNAL_SIGNAL_H
/**
 * @file
 * @brief      Internal header for SignalException.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* signal.c */
extern int ruby_enable_coredump;
int rb_get_next_signal(void);

RUBY_SYMBOL_EXPORT_BEGIN
/* signal.c (export) */
int rb_grantpt(int fd);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_SIGNAL_H */
