#ifndef INTERNAL_COMPILERS_H /* -*- C -*- */
#define INTERNAL_COMPILERS_H
/**
 * @file
 * @brief      Internal header absorbing C compipler differences.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#ifndef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x
#endif

#ifndef WARN_UNUSED_RESULT
# define WARN_UNUSED_RESULT(x) x
#endif

#ifndef __has_feature
# define __has_feature(x) 0
#endif

#ifndef __has_extension
# define __has_extension __has_feature
#endif

#define RB_OBJ_BUILTIN_TYPE(obj) rb_obj_builtin_type(obj)
#define OBJ_BUILTIN_TYPE(obj) RB_OBJ_BUILTIN_TYPE(obj)
#ifdef __GNUC__
#define rb_obj_builtin_type(obj) \
__extension__({ \
    VALUE arg_obj = (obj); \
    RB_SPECIAL_CONST_P(arg_obj) ? -1 : \
        RB_BUILTIN_TYPE(arg_obj); \
    })
#else
static inline int
rb_obj_builtin_type(VALUE obj)
{
    return RB_SPECIAL_CONST_P(obj) ? -1 :
        RB_BUILTIN_TYPE(obj);
}
#endif

/* A macro for defining a flexible array, like: VALUE ary[FLEX_ARY_LEN]; */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
# define FLEX_ARY_LEN   /* VALUE ary[]; */
#elif defined(__GNUC__) && !defined(__STRICT_ANSI__)
# define FLEX_ARY_LEN 0 /* VALUE ary[0]; */
#else
# define FLEX_ARY_LEN 1 /* VALUE ary[1]; */
#endif

/*
 * For declaring bitfields out of non-unsigned int types:
 *   struct date {
 *      BITFIELD(enum months, month, 4);
 *      ...
 *   };
 */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
# define BITFIELD(type, name, size) type name : size
#else
# define BITFIELD(type, name, size) unsigned int name : size
#endif

#if defined(USE_UNALIGNED_MEMBER_ACCESS) && USE_UNALIGNED_MEMBER_ACCESS && \
    (defined(__clang__) || GCC_VERSION_SINCE(9, 0, 0))
#include "warnings.h"
# define UNALIGNED_MEMBER_ACCESS(expr) __extension__({ \
    COMPILER_WARNING_PUSH; \
    COMPILER_WARNING_IGNORED(-Waddress-of-packed-member); \
    typeof(expr) unaligned_member_access_result = (expr); \
    COMPILER_WARNING_POP; \
    unaligned_member_access_result; \
})
#else
# define UNALIGNED_MEMBER_ACCESS(expr) expr
#endif
#define UNALIGNED_MEMBER_PTR(ptr, mem) UNALIGNED_MEMBER_ACCESS(&(ptr)->mem)

#undef RB_OBJ_WRITE
#define RB_OBJ_WRITE(a, slot, b) UNALIGNED_MEMBER_ACCESS(rb_obj_write((VALUE)(a), (VALUE *)(slot), (VALUE)(b), __FILE__, __LINE__))

#endif /* INTERNAL_COMPILERS_H */
