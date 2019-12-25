#ifndef INTERNAL_STDBOOL_H /* -*- C -*- */
#define INTERNAL_STDBOOL_H
/**
 * @file
 * @brief      Thin wrapper to <stdbool.h>
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/config.h" /* for HAVE_STDBOOL_H */

#ifdef HAVE_STDBOOL_H
# include <stdbool.h>
#endif

/* Note that we assume the compiler isn't C++. */
#ifdef __bool_true_false_are_defined
# undef bool
# undef true
# undef false
# undef __bool_true_false_are_defined
#else
typedef unsigned char _Bool;
#endif

/* See also http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2229.htm */
#define bool  _Bool
#define true  ((_Bool)+1)
#define false ((_Bool)+0)
#define __bool_true_false_are_defined

#endif /* INTERNAL_STDBOOL_H */
