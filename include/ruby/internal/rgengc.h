#ifndef RBIMPL_RGENGC_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RGENGC_H
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
 * @brief      RGENGC write-barrier APIs.
 * @see        Sasada,  K.,  "Gradual  write-barrier   insertion  into  a  Ruby
 *             interpreter",   in  proceedings   of   the   2019  ACM   SIGPLAN
 *             International  Symposium on  Memory Management  (ISMM 2019),  pp
 *             115-121, 2019. https://doi.org/10.1145/3315573.3329986
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"
#include "ruby/backward/2/attributes.h"

#undef USE_RGENGC
#define USE_RGENGC 1

#ifndef USE_RINCGC
# define USE_RINCGC 1
#endif

#ifndef USE_RGENGC_LOGGING_WB_UNPROTECT
# define USE_RGENGC_LOGGING_WB_UNPROTECT 0
#endif

#ifndef RGENGC_WB_PROTECTED_ARRAY
# define RGENGC_WB_PROTECTED_ARRAY 1
#endif

#ifndef RGENGC_WB_PROTECTED_HASH
# define RGENGC_WB_PROTECTED_HASH 1
#endif

#ifndef RGENGC_WB_PROTECTED_STRUCT
# define RGENGC_WB_PROTECTED_STRUCT 1
#endif

#ifndef RGENGC_WB_PROTECTED_STRING
# define RGENGC_WB_PROTECTED_STRING 1
#endif

#ifndef RGENGC_WB_PROTECTED_OBJECT
# define RGENGC_WB_PROTECTED_OBJECT 1
#endif

#ifndef RGENGC_WB_PROTECTED_REGEXP
# define RGENGC_WB_PROTECTED_REGEXP 1
#endif

#ifndef RGENGC_WB_PROTECTED_CLASS
# define RGENGC_WB_PROTECTED_CLASS 1
#endif

#ifndef RGENGC_WB_PROTECTED_FLOAT
# define RGENGC_WB_PROTECTED_FLOAT 1
#endif

#ifndef RGENGC_WB_PROTECTED_COMPLEX
# define RGENGC_WB_PROTECTED_COMPLEX 1
#endif

#ifndef RGENGC_WB_PROTECTED_RATIONAL
# define RGENGC_WB_PROTECTED_RATIONAL 1
#endif

#ifndef RGENGC_WB_PROTECTED_BIGNUM
# define RGENGC_WB_PROTECTED_BIGNUM 1
#endif

#ifndef RGENGC_WB_PROTECTED_NODE_CREF
# define RGENGC_WB_PROTECTED_NODE_CREF 1
#endif

/**
 * @name Write barrier (WB) interfaces:
 * @{
 *
 * @note The following  core interfaces can  be changed in the  future.  Please
 *       catch up if you want to insert WB into C-extensions correctly.
 */

/**
 * WB for new  reference from `a' to  `b'. Write `b' into `*slot'.  `slot' is a
 * pointer in `a'.
 */
#define RB_OBJ_WRITE(a, slot, b) \
    RBIMPL_CAST(rb_obj_write((VALUE)(a), (VALUE *)(slot), (VALUE)(b), __FILE__, __LINE__))
/**
 * WB for new  reference from `a' to  `b'.  This doesn't write  any values, but
 * only  a WB  declaration.  `oldv'  is replaced  value with  `b' (not  used in
 * current Ruby).
 */
#define RB_OBJ_WRITTEN(a, oldv, b) \
    RBIMPL_CAST(rb_obj_written((VALUE)(a), (VALUE)(oldv), (VALUE)(b), __FILE__, __LINE__))
/** @} */

#define OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW
#define OBJ_PROMOTED     RB_OBJ_PROMOTED
#define OBJ_WB_UNPROTECT RB_OBJ_WB_UNPROTECT

#define RB_OBJ_WB_UNPROTECT(x) rb_obj_wb_unprotect(x, __FILE__, __LINE__)
#define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    (RGENGC_WB_PROTECTED_##type ? OBJ_WB_UNPROTECT(obj) : obj)
#define RGENGC_LOGGING_WB_UNPROTECT rb_gc_unprotect_logging

/** @cond INTERNAL_MACRO */
#define RB_OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW
#define RB_OBJ_PROMOTED     RB_OBJ_PROMOTED
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
void rb_gc_writebarrier(VALUE a, VALUE b);
void rb_gc_writebarrier_unprotect(VALUE obj);
#if USE_RGENGC_LOGGING_WB_UNPROTECT
void rb_gc_unprotect_logging(void *objptr, const char *filename, int line);
#endif
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_OBJ_PROMOTED_RAW(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    return RB_FL_ANY_RAW(obj,  RUBY_FL_PROMOTED);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_OBJ_PROMOTED(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return false;
    }
    else {
        return RB_OBJ_PROMOTED_RAW(obj);
    }
}

static inline VALUE
rb_obj_wb_unprotect(VALUE x, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#if USE_RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_WB_UNPROTECT(RBIMPL_CAST((void *)x), filename, line);
#endif
    rb_gc_writebarrier_unprotect(x);
    return x;
}

static inline VALUE
rb_obj_written(VALUE a, RB_UNUSED_VAR(VALUE oldv), VALUE b, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#if USE_RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_OBJ_WRITTEN(a, oldv, b, filename, line);
#endif

    if (!RB_SPECIAL_CONST_P(b)) {
        rb_gc_writebarrier(a, b);
    }

    return a;
}

static inline VALUE
rb_obj_write(VALUE a, VALUE *slot, VALUE b, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_WRITE
    RGENGC_LOGGING_WRITE(a, slot, b, filename, line);
#endif

    *slot = b;

    rb_obj_written(a, RUBY_Qundef /* ignore `oldv' now */, b, filename, line);
    return a;
}

#endif /* RBIMPL_RGENGC_H */
