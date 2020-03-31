/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     $Author$
 * @date       Wed May 18 00:21:44 JST 1994
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#ifndef RUBY_DEFINES_H
#define RUBY_DEFINES_H 1

#include "ruby/3/config.h"

/* AC_INCLUDES_DEFAULT */
#include <stdio.h>

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif

#ifdef HAVE_SYS_STAT_H
# include <sys/stat.h>
#endif

#ifdef STDC_HEADERS
# include <stdlib.h>
# include <stddef.h>
#else
# ifdef HAVE_STDLIB_H
#  include <stdlib.h>
# endif
#endif

#ifdef HAVE_STRING_H
# if !defined STDC_HEADERS && defined HAVE_MEMORY_H
#  include <memory.h>
# endif
# include <string.h>
#endif

#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif

#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#ifdef HAVE_STDALIGN_H
# include <stdalign.h>
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>
#endif

#ifdef RUBY_USE_SETJMPEX
# include <setjmpex.h>
#endif

#include "ruby/3/dllexport.h"
#include "ruby/3/dosish.h"
#include "ruby/3/xmalloc.h"
#include "ruby/backward/2/assume.h"
#include "ruby/backward/2/attributes.h"
#include "ruby/backward/2/bool.h"
#include "ruby/backward/2/extern.h"
#include "ruby/backward/2/gcc_version_since.h"
#include "ruby/backward/2/long_long.h"
#include "ruby/backward/2/stdalign.h"
#include "ruby/backward/2/stdarg.h"
#include "ruby/missing.h"

#define RUBY

#ifdef __GNUC__
# define RB_GNUC_EXTENSION __extension__
# define RB_GNUC_EXTENSION_BLOCK(x) __extension__ ({ x; })
#else
# define RB_GNUC_EXTENSION
# define RB_GNUC_EXTENSION_BLOCK(x) (x)
#endif

/* :FIXME:  Can someone  tell us  why is  this macro  defined here?   @shyouhei
 * thinks this  is a  truly internal  macro but cannot  move around  because he
 * doesn't understand the reason of this arrangement. */
#ifndef RUBY_MBCHAR_MAXSIZE
# define RUBY_MBCHAR_MAXSIZE INT_MAX
# /* MB_CUR_MAX will not work well in C locale */
#endif

#if defined(__sparc)
RUBY3_SYMBOL_EXPORT_BEGIN()
void rb_sparc_flush_register_windows(void);
RUBY3_SYMBOL_EXPORT_END()
# define FLUSH_REGISTER_WINDOWS rb_sparc_flush_register_windows()
#else
# define FLUSH_REGISTER_WINDOWS ((void)0)
#endif

#endif /* RUBY_DEFINES_H */
