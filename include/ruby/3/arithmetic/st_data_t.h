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
 * @brief      Arithmetic conversion between C's `st_data_t` and Ruby's.
 */
#ifndef  RUBY3_ARITHMERIC_ST_DATA_T_H
#define  RUBY3_ARITHMERIC_ST_DATA_T_H
#include "ruby/3/config.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/st.h"

#if SIZEOF_LONG < SIZEOF_VALUE
#define RB_ST2FIX(h) RB_LONG2FIX((long)((h) > 0 ? (h) & (unsigned long)-1 >> 2 : (h) | ~((unsigned long)-1 >> 2)))
#else
#define RB_ST2FIX(h) RB_LONG2FIX((long)(h))
#endif
#define ST2FIX(h) RB_ST2FIX(h)

#endif /* RUBY3_ARITHMERIC_ST_DATA_T_H */
