#ifndef RBIMPL_RBASIC_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RBASIC_H
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
 * @brief      Defines struct ::RBasic.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/forceinline.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

#define RBASIC(obj)          RBIMPL_CAST((struct RBasic *)(obj))
#define RBASIC_CLASS         RBASIC_CLASS
#define RVALUE_EMBED_LEN_MAX RVALUE_EMBED_LEN_MAX

/** @cond INTERNAL_MACRO */
#define RBIMPL_EMBED_LEN_MAX_OF(T) \
    RBIMPL_CAST((int)(sizeof(VALUE[RVALUE_EMBED_LEN_MAX]) / sizeof(T)))
/** @endcond */

enum ruby_rvalue_flags { RVALUE_EMBED_LEN_MAX = 3 };

struct
RUBY_ALIGNAS(SIZEOF_VALUE)
RBasic {
    VALUE flags;                /**< @see enum ::ruby_fl_type. */
    const VALUE klass;

#ifdef __cplusplus
  public:
    RBIMPL_ATTR_CONSTEXPR(CXX11)
    RBIMPL_ATTR_ARTIFICIAL()
    RBIMPL_ATTR_FORCEINLINE()
    RBIMPL_ATTR_NOALIAS()
    /**
     * We need to define this explicit constructor because the field `klass` is
     * const-qualified above,  which effectively  defines the  implicit default
     * constructor as "deleted"  (as of C++11) --  No way but to  define one by
     * ourselves.
     */
    RBasic() :
        flags(RBIMPL_VALUE_NULL),
        klass(RBIMPL_VALUE_NULL)
    {
    }
#endif
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_obj_hide(VALUE obj);
VALUE rb_obj_reveal(VALUE obj, VALUE klass); /* do not use this API to change klass information */
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline VALUE
RBASIC_CLASS(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(obj));
    return RBASIC(obj)->klass;
}

#endif /* RBIMPL_RBASIC_H */
