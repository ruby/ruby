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
 * @brief      Looser macros.
 */
#ifndef  RUBY_BACKWARD2_LOOSER_MACROS_H
#define  RUBY_BACKWARD2_LOOSER_MACROS_H
#include "ruby/3/cast.h"
#include "ruby/3/core/rbasic.h"
#include "ruby/3/core/rarray.h"
#include "ruby/3/core/rtypeddata.h"
#include "ruby/3/fl_type.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/value_type.h"

#undef RB_SPECIAL_CONST_P
#define RB_SPECIAL_CONST_P(_) ((RB_SPECIAL_CONST_P)(RUBY3_CAST((VALUE)(_))))

#undef RB_STATIC_SYM_P
#define RB_STATIC_SYM_P(_) ((RB_STATIC_SYM_P)(RUBY3_CAST((VALUE)(_))))

#undef RBASIC_CLASS
#define RBASIC_CLASS(_) ((RBASIC_CLASS)(RUBY3_CAST((VALUE)(_))))

#undef RB_BUILTIN_TYPE
#define RB_BUILTIN_TYPE(_) RUBY3_CAST((int)((RB_BUILTIN_TYPE)((VALUE)(_))))

#undef SYMBOL_P
#define SYMBOL_P(_) RB_SYMBOL_P(RUBY3_CAST((VALUE)(_)))

#undef RB_FL_TEST
#define RB_FL_TEST(_, __) ((RB_FL_TEST)((VALUE)(_), __))

#undef RB_FL_TEST_RAW
#define RB_FL_TEST_RAW(_, __) RUBY3_CAST((int)((RB_FL_TEST_RAW)((VALUE)(_), __)))

#undef RB_FL_SET
#define RB_FL_SET(_, __) ((RB_FL_SET)(RUBY3_CAST((VALUE)(_)), __))

#undef RB_FL_SET_RAW
#define RB_FL_SET_RAW(_, __) ((RB_FL_SET_RAW)(RUBY3_CAST((VALUE)(_)), __))

#undef RB_FL_UNSET
#define RB_FL_UNSET(_, __) ((RB_FL_UNSET)(RUBY3_CAST((VALUE)(_)), __))

#undef RB_OBJ_FREEZE
#define RB_OBJ_FREEZE(_) rb_obj_freeze_inline(RUBY3_CAST((VALUE)(_)))

#undef RB_OBJ_FREEZE_RAW
#define RB_OBJ_FREEZE_RAW(_) ((RB_OBJ_FREEZE_RAW)(RUBY3_CAST((VALUE)(_))))

#undef RARRAY_TRANSIENT_P
#define RARRAY_TRANSIENT_P(_) ((RARRAY_TRANSIENT_P)(RUBY3_CAST((VALUE)(_))))

#undef RTYPEDDATA_P
#define RTYPEDDATA_P(_) ((RTYPEDDATA_P)(RUBY3_CAST((VALUE)(_))))

#endif /* RUBY_BACKWARD2_LOOSER_MACROS_H */
