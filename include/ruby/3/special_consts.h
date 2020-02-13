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
 * @brief      Defines enum ::ruby_special_consts.
 * @see        Sasada,  K.,  "A   Lighweight  Representation  of  Floting-Point
 *             Numbers  on  Ruby Interpreter",  in  proceedings  of 10th  JSSST
 *             SIGPPL  Workshop   on  Programming  and   Programming  Languages
 *             (PPL2008), pp. 9-16, 2008.
 */
#ifndef  RUBY3_SPECIAL_CONSTS_H
#define  RUBY3_SPECIAL_CONSTS_H
#include "ruby/3/value.h"

#ifndef USE_FLONUM
#if SIZEOF_VALUE >= SIZEOF_DOUBLE
#define USE_FLONUM 1
#else
#define USE_FLONUM 0
#endif
#endif

#define RB_FIXNUM_P(f) (((int)(SIGNED_VALUE)(f))&RUBY_FIXNUM_FLAG)
#define FIXNUM_P(f) RB_FIXNUM_P(f)

#if USE_FLONUM
#define RB_FLONUM_P(x) ((((int)(SIGNED_VALUE)(x))&RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG)
#else
#define RB_FLONUM_P(x) 0
#endif
#define FLONUM_P(x) RB_FLONUM_P(x)

#define RB_STATIC_SYM_P(x) (((VALUE)(x)&~((~(VALUE)0)<<RUBY_SPECIAL_SHIFT)) == RUBY_SYMBOL_FLAG)
#define STATIC_SYM_P(x) RB_STATIC_SYM_P(x)

#define RB_IMMEDIATE_P(x) ((VALUE)(x) & RUBY_IMMEDIATE_MASK)
#define IMMEDIATE_P(x) RB_IMMEDIATE_P(x)

/* special constants - i.e. non-zero and non-fixnum constants */
enum ruby_special_consts {
#if USE_FLONUM
    RUBY_Qfalse = 0x00,         /* ...0000 0000 */
    RUBY_Qtrue  = 0x14,         /* ...0001 0100 */
    RUBY_Qnil   = 0x08,         /* ...0000 1000 */
    RUBY_Qundef = 0x34,         /* ...0011 0100 */

    RUBY_IMMEDIATE_MASK = 0x07,
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x03,
    RUBY_FLONUM_FLAG    = 0x02, /* ...xxxx xx10 */
    RUBY_SYMBOL_FLAG    = 0x0c, /* ...0000 1100 */
#else
    RUBY_Qfalse = 0,            /* ...0000 0000 */
    RUBY_Qtrue  = 2,            /* ...0000 0010 */
    RUBY_Qnil   = 4,            /* ...0000 0100 */
    RUBY_Qundef = 6,            /* ...0000 0110 */

    RUBY_IMMEDIATE_MASK = 0x03,
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x00, /* any values ANDed with FLONUM_MASK cannot be FLONUM_FLAG */
    RUBY_FLONUM_FLAG    = 0x02,
    RUBY_SYMBOL_FLAG    = 0x0e, /* ...0000 1110 */
#endif
    RUBY_SPECIAL_SHIFT  = 8
};

#define RUBY_Qfalse ((VALUE)RUBY_Qfalse)
#define RUBY_Qtrue  ((VALUE)RUBY_Qtrue)
#define RUBY_Qnil   ((VALUE)RUBY_Qnil)
#define RUBY_Qundef ((VALUE)RUBY_Qundef)        /* undefined value for placeholder */
#define Qfalse RUBY_Qfalse
#define Qtrue  RUBY_Qtrue
#define Qnil   RUBY_Qnil
#define Qundef RUBY_Qundef
#define IMMEDIATE_MASK RUBY_IMMEDIATE_MASK
#define FIXNUM_FLAG RUBY_FIXNUM_FLAG
#if USE_FLONUM
#define FLONUM_MASK RUBY_FLONUM_MASK
#define FLONUM_FLAG RUBY_FLONUM_FLAG
#endif
#define SYMBOL_FLAG RUBY_SYMBOL_FLAG

#define RB_TEST(v) !(((VALUE)(v) & (VALUE)~RUBY_Qnil) == 0)
#define RB_NIL_P(v) !((VALUE)(v) != RUBY_Qnil)
#define RTEST(v) RB_TEST(v)
#define NIL_P(v) RB_NIL_P(v)
#define RB_SPECIAL_CONST_P(x) (RB_IMMEDIATE_P(x) || !RB_TEST(x))
#define SPECIAL_CONST_P(x) RB_SPECIAL_CONST_P(x)

#endif /* RUBY3_SPECIAL_CONSTS_H */
