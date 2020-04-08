/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Core data structures, definitions and manupulations.
 */
#include "ruby/3/core/rarray.h"
#include "ruby/3/core/rbasic.h"
#include "ruby/3/core/rbignum.h"
#include "ruby/3/core/rclass.h"
#include "ruby/3/core/rdata.h"
#include "ruby/3/core/rfile.h"
#include "ruby/3/core/rhash.h"
#include "ruby/3/core/robject.h"
#include "ruby/3/core/rregexp.h"
#include "ruby/3/core/rstring.h"
#include "ruby/3/core/rstruct.h"
#include "ruby/3/core/rtypeddata.h"
