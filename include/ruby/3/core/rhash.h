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
 * @brief      Routines to manipulate struct ::RHash.
 *
 * Shyouhei really suffered agnish over placement of macros in this file.  They
 * are half-brken.  The situation (as of wriring) is:
 *
 * - #RHASH_TBL: works.
 * - #RHASH_ITER_LEV: compile-time error.
 * - #RHASH_IFNONE: compile-time error.
 * - #RHASH_SIZE: works.
 * - #RHASH_EMPTY_P: works.
 * - #RHASH_SET_IFNONE: works (why... given you cannot query).
 *
 * Shyouhei stopped thinking.  Let them be as is.
 */
#ifndef  RUBY3_RHASH_H
#define  RUBY3_RHASH_H
#include "ruby/3/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

#define RHASH_TBL(h)                rb_hash_tbl(h, __FILE__, __LINE__)
#define RHASH_ITER_LEV(h)           rb_hash_iter_lev(h)
#define RHASH_IFNONE(h)             rb_hash_ifnone(h)
#define RHASH_SIZE(h)               rb_hash_size_num(h)
#define RHASH_EMPTY_P(h)            (RHASH_SIZE(h) == 0)
#define RHASH_SET_IFNONE(h, ifnone) rb_hash_set_ifnone((VALUE)h, ifnone)

struct st_table;  /* in ruby/st.h */

RUBY3_SYMBOL_EXPORT_BEGIN()
size_t rb_hash_size_num(VALUE hash);
struct st_table *rb_hash_tbl(VALUE, const char *file, int line);
VALUE rb_hash_set_ifnone(VALUE hash, VALUE ifnone);
RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_RHASH_H */
