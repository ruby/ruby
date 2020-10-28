#ifndef RBIMPL_ITERATOR_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ITERATOR_H
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
 * @brief      Block related APIs.
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#define RB_BLOCK_CALL_FUNC_STRICT 1
#define RUBY_BLOCK_CALL_FUNC_TAKES_BLOCKARG 1
#define RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg) \
    VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg
typedef VALUE rb_block_call_func(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg));
typedef rb_block_call_func *rb_block_call_func_t;

VALUE rb_each(VALUE);
VALUE rb_yield(VALUE);
VALUE rb_yield_values(int n, ...);
VALUE rb_yield_values2(int n, const VALUE *argv);
VALUE rb_yield_values_kw(int n, const VALUE *argv, int kw_splat);
VALUE rb_yield_splat(VALUE);
VALUE rb_yield_splat_kw(VALUE, int);
VALUE rb_yield_block(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg)); /* rb_block_call_func */
int rb_keyword_given_p(void);
int rb_block_given_p(void);
void rb_need_block(void);
VALUE rb_iterate(VALUE(*)(VALUE),VALUE,rb_block_call_func_t,VALUE);
VALUE rb_block_call(VALUE,ID,int,const VALUE*,rb_block_call_func_t,VALUE);
VALUE rb_block_call_kw(VALUE,ID,int,const VALUE*,rb_block_call_func_t,VALUE,int);
VALUE rb_rescue(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE);
VALUE rb_rescue2(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE,...);
VALUE rb_vrescue2(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE,VALUE),VALUE,va_list);
VALUE rb_ensure(VALUE(*)(VALUE),VALUE,VALUE(*)(VALUE),VALUE);
VALUE rb_catch(const char*,rb_block_call_func_t,VALUE);
VALUE rb_catch_obj(VALUE,rb_block_call_func_t,VALUE);

RBIMPL_ATTR_NORETURN()
void rb_throw(const char*,VALUE);

RBIMPL_ATTR_NORETURN()
void rb_throw_obj(VALUE,VALUE);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_ITERATOR_H */
