#ifndef RUBY_TOPLEVEL_ASSERT_H                           /*-*-C-*-vi:se ft=c:*/
#define RUBY_TOPLEVEL_ASSERT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/assert.h"

#if !defined(__STDC_VERSION__) || (__STDC_VERSION__ < 199901L)
/* C89 compilers are required to support strings of only 509 chars. */
/* can't use RUBY_ASSERT for such compilers. */
#include <assert.h>
#else
#undef assert
#define assert RUBY_ASSERT
#endif
#endif /* RUBY_TOPLEVEL_ASSERT_H */
