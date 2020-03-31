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
#include "ruby/3/config.h"

#ifdef HAVE_STDDEF_H
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#include "ruby/3/attr/nonnull.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/attr/noalias.h"
#include "ruby/3/cast.h"
#include "ruby/3/constant_p.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/has/builtin.h"
#include "ruby/3/value.h"

#define RB_ID2SYM      rb_id2sym
#define RB_SYM2ID      rb_sym2id
#define ID2SYM         RB_ID2SYM
#define SYM2ID         RB_SYM2ID
#define CONST_ID_CACHE RUBY_CONST_ID_CACHE
#define CONST_ID       RUBY_CONST_ID

/** @cond INTERNAL_MACRO */
#define rb_intern_const rb_intern_const
/** @endcond */

RUBY3_SYMBOL_EXPORT_BEGIN()
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
RUBY3_SYMBOL_EXPORT_END()

RUBY3_ATTR_PURE()
RUBY3_ATTR_NONNULL(())
static inline ID
rb_intern_const(const char *str)
{
    size_t len = strlen(str);
    return rb_intern2(str, RUBY3_CAST((long)len));
}

RUBY3_ATTR_NOALIAS()
RUBY3_ATTR_NONNULL(())
static inline ID
ruby3_intern_const(ID *ptr, const char *str)
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
        ruby3_intern_const(&rb_intern_id_cache, (str)); \
        result rb_intern_id_cache;                      \
    }
#define RUBY_CONST_ID(var, str) \
    do { \
        static ID ruby3_id; \
        (var) = ruby3_intern_const(&ruby3_id, (str)); \
    } while (0)

#if defined(HAVE_STMT_AND_DECL_IN_EXPR)
/* __builtin_constant_p and statement expression is available
 * since gcc-2.7.2.3 at least. */
#define rb_intern(str) \
    (RUBY3_CONSTANT_P(str) ? \
     __extension__ ({ \
         static ID ruby3_id; \
         ruby3_intern_const(&ruby3_id, (str)); \
     }) : \
     (rb_intern)(str))
#endif

#endif /* RUBY3_SYMBOL_H */
