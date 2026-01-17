#ifndef RBIMPL_RDATA_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RDATA_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Defines struct ::RData.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/warning.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/defines.h"

/** @cond INTERNAL_MACRO */
#ifndef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 1
#endif

#define RBIMPL_DATA_FUNC(f) RBIMPL_CAST((void (*)(void *))(f))
/** @endcond */

/**
 * This is a value you can set  to ::RData::dfree.  Setting this means the data
 * was allocated using ::ruby_xmalloc() (or variants), and shall be freed using
 * ::ruby_xfree().
 *
 * @warning  Do not  use this  if you  want to use  system malloc,  because the
 *           system  and  Ruby  might  or  might  not  share  the  same  malloc
 *           implementation.
 */
#define RUBY_DEFAULT_FREE         RBIMPL_DATA_FUNC(-1)

/**
 * This is a value you can set  to ::RData::dfree.  Setting this means the data
 * is managed by  someone else, like, statically allocated.  Of  course you are
 * on your own then.
 */
#define RUBY_NEVER_FREE           RBIMPL_DATA_FUNC(0)

/**
 * This is  the type of callbacks  registered to ::RData.  The  argument is the
 * `data` field.
 */
typedef void (*RUBY_DATA_FUNC)(void*);

/**
 * @deprecated
 *
 * DO NOT USE: Obsolete "untyped" user data.
 */
struct RData {
    struct RBasic basic;
    RUBY_DATA_FUNC dmark;
    RUBY_DATA_FUNC dfree;
    void *data;
};

#endif /* RBIMPL_RDATA_H */
