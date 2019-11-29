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
#else
# include "missing/stdbool.h"
#endif

#endif /* INTERNAL_STDBOOL_H */
