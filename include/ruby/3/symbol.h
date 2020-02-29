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
 * @brief      Defines #rb_intern
 */
#ifndef  RUBY3_SYMBOL_H
#define  RUBY3_SYMBOL_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

ID rb_sym2id(VALUE);
VALUE rb_id2sym(ID);
#define RB_ID2SYM(x) (rb_id2sym(x))
#define RB_SYM2ID(x) (rb_sym2id(x))
#define ID2SYM(x) RB_ID2SYM(x)
#define SYM2ID(x) RB_SYM2ID(x)

ID rb_intern(const char*);
ID rb_intern2(const char*, long);
ID rb_intern_str(VALUE str);
const char *rb_id2name(ID);
ID rb_check_id(volatile VALUE *);
ID rb_to_id(VALUE);
VALUE rb_id2str(ID);
VALUE rb_sym2str(VALUE);
VALUE rb_to_symbol(VALUE name);
VALUE rb_check_symbol(volatile VALUE *namep);

#define RUBY_CONST_ID_CACHE(result, str)                \
    {                                                   \
        static ID rb_intern_id_cache;                   \
        if (!rb_intern_id_cache)                        \
            rb_intern_id_cache = rb_intern2((str), (long)strlen(str)); \
        result rb_intern_id_cache;                      \
    }
#define RUBY_CONST_ID(var, str) \
    do RUBY_CONST_ID_CACHE((var) =, (str)) while (0)
#define CONST_ID_CACHE(result, str) RUBY_CONST_ID_CACHE(result, str)
#define CONST_ID(var, str) RUBY_CONST_ID(var, str)
#if defined(HAVE_BUILTIN___BUILTIN_CONSTANT_P) && defined(HAVE_STMT_AND_DECL_IN_EXPR)
/* __builtin_constant_p and statement expression is available
 * since gcc-2.7.2.3 at least. */
#define rb_intern(str) \
    (__builtin_constant_p(str) ? \
        __extension__ (RUBY_CONST_ID_CACHE((ID), (str))) : \
        rb_intern(str))
#define rb_intern_const(str) \
    (__builtin_constant_p(str) ? \
     __extension__ (rb_intern2((str), (long)strlen(str))) : \
     (rb_intern)(str))

#else
#define rb_intern_const(str) rb_intern2((str), (long)strlen(str))
#endif

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_SYMBOL_H */
