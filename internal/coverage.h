#ifndef INTERNAL_COVERAGE_H                         /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_COVERAGE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Coverage.
 */
#include "ruby/ruby.h"

#define COVERAGE_INDEX_LINES    0
#define COVERAGE_INDEX_BRANCHES 1

#define COVERAGE_TARGET_LINES         1
#define COVERAGE_TARGET_BRANCHES      2
#define COVERAGE_TARGET_METHODS       4
#define COVERAGE_TARGET_ONESHOT_LINES 8
#define COVERAGE_TARGET_EVAL          16

struct rb_coverage_method_data {
    VALUE owner;
    VALUE method_id;
    VALUE path;
    VALUE first_lineno;
    VALUE first_column;
    VALUE last_lineno;
    VALUE last_column;
    VALUE count;
};

typedef void rb_coverage_method_callback(const struct rb_coverage_method_data *, void *);

RUBY_SYMBOL_EXPORT_BEGIN

VALUE rb_get_coverages(void);
void rb_set_coverages(VALUE coverages, int mode, VALUE cme2counter, VALUE me_set);
void rb_clear_coverages(void);
void rb_reset_coverages(void);
void rb_resume_coverages(void);
void rb_suspend_coverages(void);
void rb_coverage_each_method(rb_coverage_method_callback callback, void *data);

RUBY_SYMBOL_EXPORT_END

int rb_get_coverage_mode(void);
VALUE rb_default_coverage(int n);

#endif /* INTERNAL_COVERAGE_H */
