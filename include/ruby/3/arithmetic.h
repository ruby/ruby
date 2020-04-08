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
 * @brief      Conversion between C's arithmtic types and Ruby's numeric types.
 */
#include "ruby/3/arithmetic/char.h"
#include "ruby/3/arithmetic/double.h"
#include "ruby/3/arithmetic/fixnum.h"
#include "ruby/3/arithmetic/gid_t.h"
#include "ruby/3/arithmetic/int.h"
#include "ruby/3/arithmetic/intptr_t.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/3/arithmetic/long_long.h"
#include "ruby/3/arithmetic/mode_t.h"
#include "ruby/3/arithmetic/off_t.h"
#include "ruby/3/arithmetic/pid_t.h"
#include "ruby/3/arithmetic/short.h"
#include "ruby/3/arithmetic/size_t.h"
#include "ruby/3/arithmetic/st_data_t.h"
#include "ruby/3/arithmetic/uid_t.h"
