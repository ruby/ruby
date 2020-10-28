#ifndef  RBIMPL_INTERN_EVAL_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_EVAL_H
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
 * @brief      Pre-1.9 era evaluator APIs (now considered miscellaneous).
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* eval.c */
RBIMPL_ATTR_NORETURN()
void rb_exc_raise(VALUE);

RBIMPL_ATTR_NORETURN()
void rb_exc_fatal(VALUE);

RBIMPL_ATTR_NORETURN()
VALUE rb_f_exit(int, const VALUE*);

RBIMPL_ATTR_NORETURN()
VALUE rb_f_abort(int, const VALUE*);

RBIMPL_ATTR_NORETURN()
void rb_interrupt(void);
ID rb_frame_this_func(void);

RBIMPL_ATTR_NORETURN()
void rb_jump_tag(int);
void rb_obj_call_init(VALUE, int, const VALUE*);
void rb_obj_call_init_kw(VALUE, int, const VALUE*, int);
VALUE rb_protect(VALUE (*)(VALUE), VALUE, int*);
ID rb_frame_callee(void);
VALUE rb_make_exception(int, const VALUE*);

/* eval_jump.c */
void rb_set_end_proc(void (*)(VALUE), VALUE);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_EVAL_H */
