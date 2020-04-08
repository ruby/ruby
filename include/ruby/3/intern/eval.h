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
 * @brief      Pre-1.9 era evaluator APIs (now considered miscellaneous).
 */
#ifndef  RUBY3_INTERN_EVAL_H
#define  RUBY3_INTERN_EVAL_H
#include "ruby/3/attr/noreturn.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

/* eval.c */
RUBY3_ATTR_NORETURN()
void rb_exc_raise(VALUE);

RUBY3_ATTR_NORETURN()
void rb_exc_fatal(VALUE);

RUBY3_ATTR_NORETURN()
VALUE rb_f_exit(int, const VALUE*);

RUBY3_ATTR_NORETURN()
VALUE rb_f_abort(int, const VALUE*);

RUBY3_ATTR_NORETURN()
void rb_interrupt(void);
ID rb_frame_this_func(void);

RUBY3_ATTR_NORETURN()
void rb_jump_tag(int);
void rb_obj_call_init(VALUE, int, const VALUE*);
void rb_obj_call_init_kw(VALUE, int, const VALUE*, int);
VALUE rb_protect(VALUE (*)(VALUE), VALUE, int*);
ID rb_frame_callee(void);
VALUE rb_make_exception(int, const VALUE*);

/* eval_jump.c */
void rb_set_end_proc(void (*)(VALUE), VALUE);

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_EVAL_H */
