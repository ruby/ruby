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
 * @brief      RGENGC write-barrier APIs.
 * @see        Sasada,  K.,  "Gradual  write-barrier   insertion  into  a  Ruby
 *             interpreter",   in  proceedings   of   the   2019  ACM   SIGPLAN
 *             International  Symposium on  Memory Management  (ISMM 2019),  pp
 *             115-121, 2019. https://doi.org/10.1145/3315573.3329986
 */
#ifndef  RUBY3_RGENGC_H
#define  RUBY3_RGENGC_H
#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

#ifdef USE_RGENGC
#undef USE_RGENGC
#endif
#define USE_RGENGC 1
#ifndef USE_RINCGC
#define USE_RINCGC 1
#endif

#ifndef RGENGC_WB_PROTECTED_ARRAY
#define RGENGC_WB_PROTECTED_ARRAY 1
#endif
#ifndef RGENGC_WB_PROTECTED_HASH
#define RGENGC_WB_PROTECTED_HASH 1
#endif
#ifndef RGENGC_WB_PROTECTED_STRUCT
#define RGENGC_WB_PROTECTED_STRUCT 1
#endif
#ifndef RGENGC_WB_PROTECTED_STRING
#define RGENGC_WB_PROTECTED_STRING 1
#endif
#ifndef RGENGC_WB_PROTECTED_OBJECT
#define RGENGC_WB_PROTECTED_OBJECT 1
#endif
#ifndef RGENGC_WB_PROTECTED_REGEXP
#define RGENGC_WB_PROTECTED_REGEXP 1
#endif
#ifndef RGENGC_WB_PROTECTED_CLASS
#define RGENGC_WB_PROTECTED_CLASS 1
#endif
#ifndef RGENGC_WB_PROTECTED_FLOAT
#define RGENGC_WB_PROTECTED_FLOAT 1
#endif
#ifndef RGENGC_WB_PROTECTED_COMPLEX
#define RGENGC_WB_PROTECTED_COMPLEX 1
#endif
#ifndef RGENGC_WB_PROTECTED_RATIONAL
#define RGENGC_WB_PROTECTED_RATIONAL 1
#endif
#ifndef RGENGC_WB_PROTECTED_BIGNUM
#define RGENGC_WB_PROTECTED_BIGNUM 1
#endif
#ifndef RGENGC_WB_PROTECTED_NODE_CREF
#define RGENGC_WB_PROTECTED_NODE_CREF 1
#endif

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
# define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    __extension__( \
        __builtin_choose_expr( \
            RGENGC_WB_PROTECTED_##type, \
            OBJ_WB_UNPROTECT((VALUE)(obj)), ((VALUE)(obj))))
#else
# define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    (RGENGC_WB_PROTECTED_##type ? \
     OBJ_WB_UNPROTECT((VALUE)(obj)) : ((VALUE)(obj)))
#endif

#define RB_OBJ_PROMOTED_RAW(x)      RB_FL_ALL_RAW(x, RUBY_FL_PROMOTED)
#define RB_OBJ_PROMOTED(x)          (RB_SPECIAL_CONST_P(x) ? 0 : RB_OBJ_PROMOTED_RAW(x))
#define RB_OBJ_WB_UNPROTECT(x)      rb_obj_wb_unprotect(x, __FILE__, __LINE__)

void rb_gc_writebarrier(VALUE a, VALUE b);
void rb_gc_writebarrier_unprotect(VALUE obj);

#define OBJ_PROMOTED_RAW(x)         RB_OBJ_PROMOTED_RAW(x)
#define OBJ_PROMOTED(x)             RB_OBJ_PROMOTED(x)
#define OBJ_WB_UNPROTECT(x)         RB_OBJ_WB_UNPROTECT(x)

/* Write barrier (WB) interfaces:
 * - RB_OBJ_WRITE(a, slot, b): WB for new reference from `a' to `b'.
 *     Write `b' into `*slot'. `slot' is a pointer in `a'.
 * - RB_OBJ_WRITTEN(a, oldv, b): WB for new reference from `a' to `b'.
 *     This doesn't write any values, but only a WB declaration.
 *     `oldv' is replaced value with `b' (not used in current Ruby).
 *
 * NOTE: The following core interfaces can be changed in the future.
 *       Please catch up if you want to insert WB into C-extensions
 *       correctly.
 */
#define RB_OBJ_WRITE(a, slot, b)       rb_obj_write((VALUE)(a), (VALUE *)(slot), (VALUE)(b), __FILE__, __LINE__)
#define RB_OBJ_WRITTEN(a, oldv, b)     rb_obj_written((VALUE)(a), (VALUE)(oldv), (VALUE)(b), __FILE__, __LINE__)

#ifndef USE_RGENGC_LOGGING_WB_UNPROTECT
#define USE_RGENGC_LOGGING_WB_UNPROTECT 0
#endif

#if USE_RGENGC_LOGGING_WB_UNPROTECT
void rb_gc_unprotect_logging(void *objptr, const char *filename, int line);
#define RGENGC_LOGGING_WB_UNPROTECT rb_gc_unprotect_logging
#endif

static inline VALUE
rb_obj_wb_unprotect(VALUE x, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_WB_UNPROTECT((void *)x, filename, line);
#endif
    rb_gc_writebarrier_unprotect(x);
    return x;
}

static inline VALUE
rb_obj_written(VALUE a, RB_UNUSED_VAR(VALUE oldv), VALUE b, RB_UNUSED_VAR(const char *filename), RB_UNUSED_VAR(int line))
{
#ifdef RGENGC_LOGGING_OBJ_WRITTEN
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

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_RGENGC_H */
