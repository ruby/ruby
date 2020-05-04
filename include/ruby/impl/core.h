#ifndef RUBY3_CORE_H                                 /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY3_CORE_H
/**
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
#include "ruby/impl/core/rarray.h"
#include "ruby/impl/core/rbasic.h"
#include "ruby/impl/core/rbignum.h"
#include "ruby/impl/core/rclass.h"
#include "ruby/impl/core/rdata.h"
#include "ruby/impl/core/rfile.h"
#include "ruby/impl/core/rhash.h"
#include "ruby/impl/core/robject.h"
#include "ruby/impl/core/rregexp.h"
#include "ruby/impl/core/rstring.h"
#include "ruby/impl/core/rstruct.h"
#include "ruby/impl/core/rtypeddata.h"
#endif /* RUBY3_CORE_H */
