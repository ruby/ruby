#ifndef INTERNAL_THREAD_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_THREAD_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Thread.
 */
#include "ruby/ruby.h"          /* for VALUE */
#include "ruby/intern.h"        /* for rb_blocking_function_t */

struct rb_thread_struct;        /* in vm_core.h */

/* thread.c */
#define COVERAGE_INDEX_LINES    0
#define COVERAGE_INDEX_BRANCHES 1
#define COVERAGE_TARGET_LINES    1
#define COVERAGE_TARGET_BRANCHES 2
#define COVERAGE_TARGET_METHODS  4
#define COVERAGE_TARGET_ONESHOT_LINES 8

VALUE rb_obj_is_mutex(VALUE obj);
VALUE rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg);
void rb_thread_execute_interrupts(VALUE th);
VALUE rb_get_coverages(void);
int rb_get_coverage_mode(void);
VALUE rb_default_coverage(int);
VALUE rb_thread_shield_new(void);
VALUE rb_thread_shield_wait(VALUE self);
VALUE rb_thread_shield_release(VALUE self);
VALUE rb_thread_shield_destroy(VALUE self);
int rb_thread_to_be_killed(VALUE thread);
void rb_mutex_allow_trap(VALUE self, int val);
VALUE rb_uninterruptible(VALUE (*b_proc)(VALUE), VALUE data);
VALUE rb_mutex_owned_p(VALUE self);

VALUE rb_thread_scheduler_get(VALUE);
VALUE rb_thread_scheduler_set(VALUE, VALUE);
VALUE rb_thread_scheduler_if_nonblocking(VALUE thread);

RUBY_SYMBOL_EXPORT_BEGIN
/* Temporary.  This API will be removed (renamed). */
VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);

/* thread.c (export) */
int ruby_thread_has_gvl_p(void); /* for ext/fiddle/closure.c */
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
int rb_threadptr_execute_interrupts(struct rb_thread_struct *th, int blocking_timing);
MJIT_SYMBOL_EXPORT_END

#endif /* INTERNAL_THREAD_H */
