#ifndef RBIMPL_SYMBOL_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_SYMBOL_H
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
 * @brief      Defines #rb_intern
 */
#include "ruby/internal/config.h"

#ifdef HAVE_STDDEF_H
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/constant_p.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/value.h"

#define RB_ID2SYM      rb_id2sym
#define RB_SYM2ID      rb_sym2id
#define ID2SYM         RB_ID2SYM
#define SYM2ID         RB_SYM2ID
#define CONST_ID_CACHE RUBY_CONST_ID_CACHE
#define CONST_ID       RUBY_CONST_ID

/** @cond INTERNAL_MACRO */
#define rb_intern_const rb_intern_const
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
ID rb_sym2id(VALUE);
VALUE rb_id2sym(ID);
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
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE()
RBIMPL_ATTR_NONNULL(())
static inline ID
rb_intern_const(const char *str)
{
    size_t len = strlen(str);
    return rb_intern2(str, RBIMPL_CAST((long)len));
}

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL(())
static inline ID
rbimpl_intern_const(ID *ptr, const char *str)
{
    while (! *ptr) {
        *ptr = rb_intern_const(str);
    }

    return *ptr;
}

/* Does anyone use it?  Preserved for backward compat. */
#define RUBY_CONST_ID_CACHE(result, str)                \
    {                                                   \
        static ID rb_intern_id_cache;                   \
        rbimpl_intern_const(&rb_intern_id_cache, (str)); \
        result rb_intern_id_cache;                      \
    }
#define RUBY_CONST_ID(var, str) \
    do { \
        static ID rbimpl_id; \
        (var) = rbimpl_intern_const(&rbimpl_id, (str)); \
    } while (0)

#if defined(HAVE_STMT_AND_DECL_IN_EXPR)
/* __builtin_constant_p and statement expression is available
 * since gcc-2.7.2.3 at least. */
#define rb_intern(str) \
    (RBIMPL_CONSTANT_P(str) ? \
     __extension__ ({ \
         static ID rbimpl_id; \
         rbimpl_intern_const(&rbimpl_id, (str)); \
     }) : \
     (rb_intern)(str))
#endif

#endif /* RBIMPL_SYMBOL_H */
