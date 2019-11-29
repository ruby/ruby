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

#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
# define STATIC_ASSERT(name, expr) _Static_assert(expr, #name ": " #expr)
#elif GCC_VERSION_SINCE(4, 6, 0) || __has_extension(c_static_assert)
# define STATIC_ASSERT(name, expr) RB_GNUC_EXTENSION _Static_assert(expr, #name ": " #expr)
#else
# define STATIC_ASSERT(name, expr) typedef int static_assert_##name##_check[1 - 2*!(expr)]
#endif

#endif /* INTERNAL_STATIC_ASSERT_H */
