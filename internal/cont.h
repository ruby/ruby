#ifndef INTERNAL_CONT_H /* -*- C -*- */
#define INTERNAL_CONT_H
/**
 * @file
 * @brief      Internal header for Fiber.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

struct rb_thread_struct;
/* cont.c */
VALUE rb_obj_is_fiber(VALUE);
void rb_fiber_reset_root_local_storage(struct rb_thread_struct *);
void ruby_register_rollback_func_for_ensure(VALUE (*ensure_func)(VALUE), VALUE (*rollback_func)(VALUE));

#endif /* INTERNAL_CONT_H */
