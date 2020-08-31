#ifndef RBIMPL_ROBJECT_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ROBJECT_H
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
 * @brief      Defines struct ::RObject.
 */
#include "ruby/internal/config.h"

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

#define ROBJECT(obj)          RBIMPL_CAST((struct RObject *)(obj))
#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED         ROBJECT_EMBED
/** @cond INTERNAL_MACRO */
#define ROBJECT_NUMIV         ROBJECT_NUMIV
#define ROBJECT_IVPTR         ROBJECT_IVPTR
#define ROBJECT_IV_INDEX_TBL  ROBJECT_IV_INDEX_TBL
/** @endcond */

enum ruby_robject_flags { ROBJECT_EMBED = RUBY_FL_USER1 };

enum ruby_robject_consts { ROBJECT_EMBED_LEN_MAX = RBIMPL_EMBED_LEN_MAX_OF(VALUE) };

struct st_table;

struct RObject {
    struct RBasic basic;
    union {
        struct {
            uint32_t numiv;
            VALUE *ivptr;
            struct st_table *iv_index_tbl; /* shortcut for RCLASS_IV_INDEX_TBL(rb_obj_class(obj)) */
        } heap;
        VALUE ary[ROBJECT_EMBED_LEN_MAX];
    } as;
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
struct st_table *rb_obj_iv_index_tbl(const struct RObject *obj);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline uint32_t
ROBJECT_NUMIV(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ROBJECT_EMBED_LEN_MAX;
    }
    else {
        return ROBJECT(obj)->as.heap.numiv;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline VALUE *
ROBJECT_IVPTR(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    struct RObject *const ptr = ROBJECT(obj);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ptr->as.ary;
    }
    else {
        return ptr->as.heap.ivptr;
    }
}

RBIMPL_ATTR_DEPRECATED(("Whoever have used it before?  Just tell us so.  We can stop deleting it."))
RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline struct st_table *
ROBJECT_IV_INDEX_TBL(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    struct RObject *const ptr = ROBJECT(obj);

    return rb_obj_iv_index_tbl(ptr);
}

#endif /* RBIMPL_ROBJECT_H */
