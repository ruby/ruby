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
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/fl_type.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/r_cast.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED ROBJECT_EMBED
enum ruby_robject_flags {
    ROBJECT_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    ROBJECT_EMBED = RUBY_FL_USER1,

    ROBJECT_ENUM_END
};

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
#define ROBJECT_NUMIV(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     ROBJECT_EMBED_LEN_MAX : \
     ROBJECT(o)->as.heap.numiv)
#define ROBJECT_IVPTR(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     ROBJECT(o)->as.ary : \
     ROBJECT(o)->as.heap.ivptr)
#define ROBJECT_IV_INDEX_TBL(o) \
    ((RBASIC(o)->flags & ROBJECT_EMBED) ? \
     RCLASS_IV_INDEX_TBL(rb_obj_class(o)) : \
     ROBJECT(o)->as.heap.iv_index_tbl)
#define ROBJECT(obj) (R_CAST(RObject)(obj))

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_ROBJECT_H */
