#ifndef RBIMPL_INTERN_RANDOM_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RANDOM_H
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
 *             extension libraries. They could be written in C++98.
 * @brief      MT19937 backended pseudo random number generator.
 * @see        Matsumoto,  M.,   Nishimura,  T.,  "Mersenne  Twister:   A  623-
 *             dimensionally   equidistributed   uniform  pseudorandom   number
 *             generator", ACM  Trans. on  Modeling and Computer  Simulation, 8
 *             (1): pp 3-30, 1998.  https://doi.org/10.1145/272991.272995
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* random.c */
unsigned int rb_genrand_int32(void);
double rb_genrand_real(void);
void rb_reset_random_seed(void);
VALUE rb_random_bytes(VALUE rnd, long n);
VALUE rb_random_int(VALUE rnd, VALUE max);
unsigned int rb_random_int32(VALUE rnd);
double rb_random_real(VALUE rnd);
unsigned long rb_random_ulong_limited(VALUE rnd, unsigned long limit);
unsigned long rb_genrand_ulong_limited(unsigned long i);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RANDOM_H */
