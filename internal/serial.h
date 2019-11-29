#ifndef INTERNAL_SERIAL_H /* -*- C -*- */
#define INTERNAL_SERIAL_H
/**
 * @file
 * @brief      Internal header for rb_serial_t.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#if defined(HAVE_LONG_LONG)
typedef unsigned LONG_LONG rb_serial_t;
# define SERIALT2NUM ULL2NUM
# define PRI_SERIALT_PREFIX PRI_LL_PREFIX
# define SIZEOF_SERIAL_T SIZEOF_LONG_LONG
#elif defined(HAVE_UINT64_T)
typedef uint64_t rb_serial_t;
# define SERIALT2NUM SIZET2NUM
# define PRI_SERIALT_PREFIX PRI_64_PREFIX
# define SIZEOF_SERIAL_T SIZEOF_UINT64_T
#else
typedef unsigned long rb_serial_t;
# define SERIALT2NUM ULONG2NUM
# define PRI_SERIALT_PREFIX PRI_LONG_PREFIX
# define SIZEOF_SERIAL_T SIZEOF_LONG
#endif

#endif /* INTERNAL_SERIAL_H */
