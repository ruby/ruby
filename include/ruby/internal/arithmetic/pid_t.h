#ifndef RBIMPL_ARITHMETIC_PID_T_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_PID_T_H
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
 * @brief      Arithmetic conversion between C's `pid_t` and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/long.h"

/** Converts a C's `pid_t` into an instance of ::rb_cInteger. */
#ifndef RB_PIDT2NUM
# define RB_PIDT2NUM RB_LONG2NUM
#endif

/** Converts an instance of ::rb_cNumeric into C's `pid_t`. */
#ifndef RB_NUM2PIDT
# define RB_NUM2PIDT RB_NUM2LONG
#endif

/** A rb_sprintf() format prefix to be used for a `pid_t` parameter. */
#ifndef RB_PRI_PIDT_PREFIX
# define RB_PRI_PIDT_PREFIX PRI_LONG_PREFIX
#endif

#define PIDT2NUM RB_PIDT2NUM /**< @old{RB_PIDT2NUM} */
#define NUM2PIDT RB_NUM2PIDT /**< @old{RB_NUM2PIDT} */
#define PRI_PIDT_PREFIX RB_PRI_PIDT_PREFIX

#endif /* RBIMPL_ARITHMETIC_PID_T_H */
