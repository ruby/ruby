#ifndef RBIMPL_RSTRING_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RSTRING_H
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
 * @brief      Defines struct ::RString.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value_type.h"
#include "ruby/internal/warning_push.h"
#include "ruby/assert.h"

#define RSTRING(obj)            RBIMPL_CAST((struct RString *)(obj))
#define RSTRING_NOEMBED         RSTRING_NOEMBED
#define RSTRING_EMBED_LEN_MASK  RSTRING_EMBED_LEN_MASK
#define RSTRING_EMBED_LEN_SHIFT RSTRING_EMBED_LEN_SHIFT
#define RSTRING_EMBED_LEN_MAX   RSTRING_EMBED_LEN_MAX
#define RSTRING_FSTR            RSTRING_FSTR

/** @cond INTERNAL_MACRO */
#define RSTRING_EMBED_LEN RSTRING_EMBED_LEN
#define RSTRING_LEN       RSTRING_LEN
#define RSTRING_LENINT    RSTRING_LENINT
#define RSTRING_PTR       RSTRING_PTR
#define RSTRING_END       RSTRING_END
/** @endcond */

#define StringValue(v)     rb_string_value(&(v))
#define StringValuePtr(v)  rb_string_value_ptr(&(v))
#define StringValueCStr(v) rb_string_value_cstr(&(v))
#define SafeStringValue(v) StringValue(v)
#define ExportStringValue(v) do { \
    StringValue(v);               \
    (v) = rb_str_export(v);       \
} while (0)

enum ruby_rstring_flags {
    RSTRING_NOEMBED         = RUBY_FL_USER1,
    RSTRING_EMBED_LEN_MASK  = RUBY_FL_USER2 | RUBY_FL_USER3 | RUBY_FL_USER4 |
                              RUBY_FL_USER5 | RUBY_FL_USER6,
    /* Actually,  string  encodings are  also  encoded  into the  flags,  using
     * remaining bits.*/
    RSTRING_FSTR            = RUBY_FL_USER17
};

enum ruby_rstring_consts {
    RSTRING_EMBED_LEN_SHIFT = RUBY_FL_USHIFT + 2,
    RSTRING_EMBED_LEN_MAX   = RBIMPL_EMBED_LEN_MAX_OF(char) - 1
};

struct RString {
    struct RBasic basic;
    union {
        struct {
            long len;
            char *ptr;
            union {
                long capa;
                VALUE shared;
            } aux;
        } heap;
        char ary[RSTRING_EMBED_LEN_MAX + 1];
    } as;
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_str_to_str(VALUE);
VALUE rb_string_value(volatile VALUE*);
char *rb_string_value_ptr(volatile VALUE*);
char *rb_string_value_cstr(volatile VALUE*);
VALUE rb_str_export(VALUE);
VALUE rb_str_export_locale(VALUE);

RBIMPL_ATTR_ERROR(("rb_check_safe_str() and Check_SafeStr() are obsolete; use StringValue() instead"))
void rb_check_safe_str(VALUE);
#define Check_SafeStr(v) rb_check_safe_str(RBIMPL_CAST((VALUE)(v)))
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline long
RSTRING_EMBED_LEN(VALUE str)
{
    RBIMPL_ASSERT_TYPE(str, RUBY_T_STRING);
    RBIMPL_ASSERT_OR_ASSUME(! RB_FL_ANY_RAW(str, RSTRING_NOEMBED));

    VALUE f = RBASIC(str)->flags;
    f &= RSTRING_EMBED_LEN_MASK;
    f >>= RSTRING_EMBED_LEN_SHIFT;
    return RBIMPL_CAST((long)f);
}

RBIMPL_WARNING_PUSH()
#if RBIMPL_COMPILER_IS(Intel)
RBIMPL_WARNING_IGNORED(413)
#endif

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline struct RString
rbimpl_rstring_getmem(VALUE str)
{
    RBIMPL_ASSERT_TYPE(str, RUBY_T_STRING);

    if (RB_FL_ANY_RAW(str, RSTRING_NOEMBED)) {
        return *RSTRING(str);
    }
    else {
        /* Expecting compilers to optimize this on-stack struct away. */
        struct RString retval;
        retval.as.heap.len = RSTRING_EMBED_LEN(str);
        retval.as.heap.ptr = RSTRING(str)->as.ary;
        return retval;
    }
}

RBIMPL_WARNING_POP()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline long
RSTRING_LEN(VALUE str)
{
    return rbimpl_rstring_getmem(str).as.heap.len;
}

RBIMPL_ATTR_ARTIFICIAL()
static inline char *
RSTRING_PTR(VALUE str)
{
    char *ptr = rbimpl_rstring_getmem(str).as.heap.ptr;

    if (RB_UNLIKELY(! ptr)) {
        /* :BEWARE: @shyouhei thinks  that currently, there are  rooms for this
         * function to return  NULL.  In the 20th century that  was a pointless
         * concern.  However struct RString can hold fake strings nowadays.  It
         * seems no  check against NULL  are exercised around handling  of them
         * (one  of  such   usages  is  located  in   marshal.c,  which  scares
         * @shyouhei).  Better check here for maximum safety.
         *
         * Also,  this is  not rb_warn()  because RSTRING_PTR()  can be  called
         * during GC (see  what obj_info() does).  rb_warn()  needs to allocate
         * Ruby objects.  That is not possible at this moment. */
        fprintf(stderr, "%s\n",
            "RSTRING_PTR is returning NULL!! "
            "SIGSEGV is highly expected to follow immediately. "
            "If you could reproduce, attach your debugger here, "
            "and look at the passed string."
        );
    }

    return ptr;
}

RBIMPL_ATTR_ARTIFICIAL()
static inline char *
RSTRING_END(VALUE str)
{
    struct RString buf = rbimpl_rstring_getmem(str);

    if (RB_UNLIKELY(! buf.as.heap.ptr)) {
        /* Ditto. */
        fprintf(stderr, "%s\n",
            "RSTRING_END is returning NULL!! "
            "SIGSEGV is highly expected to follow immediately. "
            "If you could reproduce, attach your debugger here, "
            "and look at the passed string."
        );
    }

    return &buf.as.heap.ptr[buf.as.heap.len];
}

RBIMPL_ATTR_ARTIFICIAL()
static inline int
RSTRING_LENINT(VALUE str)
{
    return rb_long2int(RSTRING_LEN(str));
}

#ifdef HAVE_STMT_AND_DECL_IN_EXPR
# define RSTRING_GETMEM(str, ptrvar, lenvar) \
    __extension__ ({ \
        struct RString rbimpl_str = rbimpl_rstring_getmem(str); \
        (ptrvar) = rbimpl_str.as.heap.ptr; \
        (lenvar) = rbimpl_str.as.heap.len; \
    })
#else
# define RSTRING_GETMEM(str, ptrvar, lenvar) \
    ((ptrvar) = RSTRING_PTR(str),           \
     (lenvar) = RSTRING_LEN(str))
#endif /* HAVE_STMT_AND_DECL_IN_EXPR */
#endif /* RBIMPL_RSTRING_H */
