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
 * @brief      Defines struct ::RObject.
 */
#ifndef  RUBY3_ROBJECT_H
#define  RUBY3_ROBJECT_H
#include "ruby/3/config.h"

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/3/attr/artificial.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/cast.h"
#include "ruby/3/fl_type.h"
#include "ruby/3/value.h"
#include "ruby/3/value_type.h"

#define ROBJECT(obj)          RUBY3_CAST((struct RObject *)(obj))
#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED         ROBJECT_EMBED
/** @cond INTERNAL_MACRO */
#define ROBJECT_NUMIV         ROBJECT_NUMIV
#define ROBJECT_IVPTR         ROBJECT_IVPTR
/** @endcond */

enum ruby_robject_flags { ROBJECT_EMBED = RUBY_FL_USER1 };

enum { ROBJECT_EMBED_LEN_MAX = RUBY3_EMBED_LEN_MAX_OF(VALUE) };

struct RObject {
    struct RBasic basic;
    union {
        struct {
            uint32_t numiv;
            VALUE *ivptr;
            void *iv_index_tbl; /* shortcut for RCLASS_IV_INDEX_TBL(rb_obj_class(obj)) */
        } heap;
        VALUE ary[ROBJECT_EMBED_LEN_MAX];
    } as;
};

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline uint32_t
ROBJECT_NUMIV(VALUE obj)
{
    RUBY3_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ROBJECT_EMBED_LEN_MAX;
    }
    else {
        return ROBJECT(obj)->as.heap.numiv;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline VALUE *
ROBJECT_IVPTR(VALUE obj)
{
    RUBY3_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    struct RObject *const ptr = ROBJECT(obj);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ptr->as.ary;
    }
    else {
        return ptr->as.heap.ivptr;
    }
}

#define ROBJECT_IV_INDEX_TBL(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     RCLASS_IV_INDEX_TBL(rb_obj_class(o)) : \
     ROBJECT(o)->as.heap.iv_index_tbl)

#endif /* RUBY3_ROBJECT_H */
