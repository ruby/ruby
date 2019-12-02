#ifndef INTERNAL_STATIC_ASSERT_H /* -*- C -*- */
#define INTERNAL_STATIC_ASSERT_H
/**
 * @file
 * @brief      C11 shim for _Static_assert.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include <assert.h>             /* for static_assert */
#include "compilers.h"          /* for __has_extension */

#if defined(static_assert)
/* Take assert.h definition */
# define STATIC_ASSERT(name, expr) static_assert(expr, # name ": " # expr)

#elif __has_extension(c_static_assert) || GCC_VERSION_SINCE(4, 6, 0)
# define STATIC_ASSERT(name, expr) \
    __extension__ _Static_assert(expr, # name ": " # expr)

#else
# define STATIC_ASSERT(name, expr) \
    typedef int static_assert_ ## name ## _check[1 - 2 * !(expr)]

#endif /* static_assert */
#endif /* INTERNAL_STATIC_ASSERT_H */
