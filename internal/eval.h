#ifndef INTERNAL_EVAL_H /* -*- C -*- */
#define INTERNAL_EVAL_H
/**
 * @file
 * @brief      Internal header for the evaluator.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @note       There  also  is  eval_intern.h, which  is  evaluator's  internal
 *             header (related to this file, but not the same role).
 */

/* eval.c */
VALUE rb_refinement_module_get_refined_class(VALUE module);
extern ID ruby_static_id_signo, ruby_static_id_status;
void rb_class_modify_check(VALUE);
#define id_signo ruby_static_id_signo
#define id_status ruby_static_id_status
NORETURN(VALUE rb_f_raise(int argc, VALUE *argv));

/* eval_error.c */
VALUE rb_get_backtrace(VALUE info);

/* eval_jump.c */
void rb_call_end_proc(VALUE data);
void rb_mark_end_proc(void);

#endif /* INTERNAL_EVAL_H */
