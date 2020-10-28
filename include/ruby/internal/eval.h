#ifndef RBIMPL_EVAL_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_EVAL_H
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
 * @brief      Declares ::rb_eval_string().
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

VALUE rb_eval_string(const char*);
VALUE rb_eval_string_protect(const char*, int*);
VALUE rb_eval_string_wrap(const char*, int*);
VALUE rb_funcall(VALUE, ID, int, ...);
VALUE rb_funcallv(VALUE, ID, int, const VALUE*);
VALUE rb_funcallv_kw(VALUE, ID, int, const VALUE*, int);
VALUE rb_funcallv_public(VALUE, ID, int, const VALUE*);
VALUE rb_funcallv_public_kw(VALUE, ID, int, const VALUE*, int);
#define rb_funcall2 rb_funcallv
#define rb_funcall3 rb_funcallv_public
VALUE rb_funcall_passing_block(VALUE, ID, int, const VALUE*);
VALUE rb_funcall_passing_block_kw(VALUE, ID, int, const VALUE*, int);
VALUE rb_funcall_with_block(VALUE, ID, int, const VALUE*, VALUE);
VALUE rb_funcall_with_block_kw(VALUE, ID, int, const VALUE*, VALUE, int);
VALUE rb_call_super(int, const VALUE*);
VALUE rb_call_super_kw(int, const VALUE*, int);
VALUE rb_current_receiver(void);
int rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *);
VALUE rb_extract_keywords(VALUE *orighash);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_EVAL_H */
